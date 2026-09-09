package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1" //nolint:gosec // coturn REST authentication mandates HMAC-SHA1.
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	turnCredentialsAction      = "turn_credentials_v1"
	turnCredentialSchema       = "turn_credentials"
	turnCredentialVersion      = 1
	turnCredentialNonceLen     = 32
	turnCredentialIssueTimeout = 2 * time.Second
	// Mirrors the client cap in go-mknoon/node/turn_credentials.go.
	turnCredentialMaxTTL = time.Hour

	turnCredentialsEnabledEnv             = "TURN_CREDENTIALS_ENABLED"
	turnCredentialsURLsEnv                = "TURN_CREDENTIAL_URLS"
	turnCredentialsPrimarySecretEnv       = "TURN_CREDENTIAL_PRIMARY_SECRET_B64"
	turnCredentialsVerificationSecretsEnv = "TURN_CREDENTIAL_VERIFICATION_SECRETS_B64"

	turnCredentialErrorInvalidRequest = "TURN_CREDENTIALS_INVALID_REQUEST"
	turnCredentialErrorUnauthorized   = "TURN_CREDENTIALS_UNAUTHORIZED"
	turnCredentialErrorRateLimited    = "TURN_CREDENTIALS_RATE_LIMITED"
	turnCredentialErrorUnavailable    = "TURN_CREDENTIALS_UNAVAILABLE"
)

var (
	ErrTurnCredentialUnauthorized    = errors.New("turn credential unauthorized")
	ErrTurnCredentialInvalid         = errors.New("turn credential invalid")
	ErrTurnCredentialExpired         = errors.New("turn credential expired")
	ErrTurnCredentialUnavailable     = errors.New("turn credential unavailable")
	ErrTurnCredentialRateLimited     = errors.New("turn credential rate limited")
	ErrTurnCredentialLimiterCapacity = errors.New("turn credential limiter capacity reached")
	errTurnCredentialConfig          = errors.New("turn credential configuration invalid")
	errTurnCredentialRequest         = errors.New("turn credential request invalid")
)

// TurnCredentialIssuer is the narrow authenticated stream-handler boundary.
// Its subject must come from network.Stream.Conn().RemotePeer(), never JSON.
type TurnCredentialIssuer interface {
	Issue(context.Context, string) (TurnCredentialBundle, error)
}

// TurnCredentialBundle is short-lived client material. It deliberately has no
// field capable of carrying a shared secret, peer identity, or static fallback.
type TurnCredentialBundle struct {
	Schema       string
	Version      int
	Username     string
	Password     string
	TTLSeconds   int64
	URLs         []string
	ServerTimeMs int64
	ExpiresAtMs  int64
}

// TurnSecretSet separates the primary minting key from the keys retained by a
// coordinated coturn overlap/rollback window.
type TurnSecretSet struct {
	Primary      []byte
	Verification [][]byte
}

type TurnSecretProvider interface {
	LoadTurnSecrets(context.Context) (TurnSecretSet, error)
}

type TurnCredentialServiceConfig struct {
	URLs               []string
	TTL                time.Duration
	MaxClockSkew       time.Duration
	MaxRequests        int
	RateWindow         time.Duration
	MaxTrackedSubjects int
}

type turnCredentialRateEntry struct {
	windowStart time.Time
	requests    int
}

type TurnCredentialService struct {
	config   TurnCredentialServiceConfig
	provider TurnSecretProvider
	clock    func() time.Time
	nonce    io.Reader

	nonceMu sync.Mutex
	rateMu  sync.Mutex
	rate    map[[sha256.Size]byte]turnCredentialRateEntry
}

func NewTurnCredentialService(
	config TurnCredentialServiceConfig,
	provider TurnSecretProvider,
	clock func() time.Time,
	nonce io.Reader,
) (*TurnCredentialService, error) {
	if provider == nil || clock == nil || nonce == nil || !validTurnCredentialConfig(config) {
		return nil, errTurnCredentialConfig
	}
	config.URLs = append([]string(nil), config.URLs...)
	return &TurnCredentialService{
		config:   config,
		provider: provider,
		clock:    clock,
		nonce:    nonce,
		rate:     make(map[[sha256.Size]byte]turnCredentialRateEntry),
	}, nil
}

func validTurnCredentialConfig(config TurnCredentialServiceConfig) bool {
	if config.TTL <= 0 || config.MaxClockSkew < 0 || config.MaxRequests <= 0 ||
		config.RateWindow <= 0 || config.MaxTrackedSubjects <= 0 || len(config.URLs) == 0 {
		return false
	}
	for _, rawURL := range config.URLs {
		if !validTurnCredentialURL(rawURL) {
			return false
		}
	}
	return true
}

func validTurnCredentialURL(raw string) bool {
	if raw == "" || strings.TrimSpace(raw) != raw || strings.ContainsAny(raw, "\r\n\t") {
		return false
	}
	parsed, err := url.Parse(raw)
	if err != nil || (parsed.Scheme != "turn" && parsed.Scheme != "turns") || parsed.Fragment != "" {
		return false
	}
	if parsed.User != nil || strings.Contains(parsed.Opaque, "@") {
		return false
	}
	return parsed.Host != "" || parsed.Opaque != ""
}

func (s *TurnCredentialService) Issue(
	ctx context.Context,
	authenticatedSubject string,
) (TurnCredentialBundle, error) {
	if s == nil || authenticatedSubject == "" {
		return TurnCredentialBundle{}, ErrTurnCredentialUnauthorized
	}
	now := s.clock()
	if err := s.admit(authenticatedSubject, now); err != nil {
		return TurnCredentialBundle{}, err
	}
	secretSet, err := s.provider.LoadTurnSecrets(ctx)
	if err != nil || len(secretSet.Primary) == 0 {
		clearTurnSecretSet(&secretSet)
		return TurnCredentialBundle{}, ErrTurnCredentialUnavailable
	}
	primary := append([]byte(nil), secretSet.Primary...)
	clearTurnSecretSet(&secretSet)
	defer clear(primary)

	nonce := make([]byte, turnCredentialNonceLen)
	defer clear(nonce)
	if err := s.readNonce(nonce); err != nil {
		return TurnCredentialBundle{}, ErrTurnCredentialUnavailable
	}

	expiresAt := now.Add(s.config.TTL)
	opaqueSubject := deriveTurnOpaqueSubject(primary, authenticatedSubject, nonce)
	username := strconv.FormatInt(expiresAt.Unix(), 10) + ":" + opaqueSubject
	password := deriveTurnPassword(primary, username)
	return TurnCredentialBundle{
		Schema:       turnCredentialSchema,
		Version:      turnCredentialVersion,
		Username:     username,
		Password:     password,
		TTLSeconds:   int64(s.config.TTL / time.Second),
		URLs:         append([]string(nil), s.config.URLs...),
		ServerTimeMs: now.UnixMilli(),
		ExpiresAtMs:  expiresAt.UnixMilli(),
	}, nil
}

func (s *TurnCredentialService) readNonce(dst []byte) error {
	s.nonceMu.Lock()
	defer s.nonceMu.Unlock()
	_, err := io.ReadFull(s.nonce, dst)
	return err
}

func (s *TurnCredentialService) admit(subject string, now time.Time) error {
	digest := sha256.New()
	_, _ = digest.Write([]byte("mknoon.turn-rate.v1\x00"))
	_, _ = digest.Write([]byte(subject))
	var key [sha256.Size]byte
	_ = digest.Sum(key[:0])
	s.rateMu.Lock()
	defer s.rateMu.Unlock()
	for candidate, entry := range s.rate {
		if !now.Before(entry.windowStart.Add(s.config.RateWindow)) {
			delete(s.rate, candidate)
		}
	}
	entry, exists := s.rate[key]
	if !exists {
		if len(s.rate) >= s.config.MaxTrackedSubjects {
			return ErrTurnCredentialLimiterCapacity
		}
		entry.windowStart = now
	}
	if entry.requests >= s.config.MaxRequests {
		return ErrTurnCredentialRateLimited
	}
	entry.requests++
	s.rate[key] = entry
	return nil
}

func deriveTurnOpaqueSubject(secret []byte, subject string, nonce []byte) string {
	mac := hmac.New(sha256.New, secret)
	_, _ = mac.Write([]byte("mknoon.turn-subject.v1\x00"))
	var length [binary.MaxVarintLen64]byte
	n := binary.PutUvarint(length[:], uint64(len(subject)))
	_, _ = mac.Write(length[:n])
	_, _ = mac.Write([]byte(subject))
	_, _ = mac.Write(nonce)
	digest := mac.Sum(nil)
	result := base64.RawURLEncoding.EncodeToString(digest)
	clear(digest)
	return result
}

func deriveTurnPassword(secret []byte, username string) string {
	mac := hmac.New(sha1.New, secret)
	_, _ = mac.Write([]byte(username))
	digest := mac.Sum(nil)
	password := base64.StdEncoding.EncodeToString(digest)
	clear(digest)
	return password
}

func (s *TurnCredentialService) Verify(
	ctx context.Context,
	username string,
	password string,
) error {
	if s == nil || !validTurnUsernameGrammar(username) {
		return ErrTurnCredentialInvalid
	}
	separator := strings.IndexByte(username, ':')
	expiresUnix, err := strconv.ParseInt(username[:separator], 10, 64)
	if err != nil || strconv.FormatInt(expiresUnix, 10) != username[:separator] {
		return ErrTurnCredentialInvalid
	}
	now := s.clock()
	expiresAt := time.Unix(expiresUnix, 0)
	if !now.Before(expiresAt) {
		return ErrTurnCredentialExpired
	}
	if expiresAt.After(now.Add(s.config.TTL + s.config.MaxClockSkew)) {
		return ErrTurnCredentialInvalid
	}
	decodedPassword, err := base64.StdEncoding.Strict().DecodeString(password)
	if err != nil || len(decodedPassword) != sha1.Size {
		clear(decodedPassword)
		return ErrTurnCredentialInvalid
	}
	defer clear(decodedPassword)

	secretSet, err := s.provider.LoadTurnSecrets(ctx)
	if err != nil || len(secretSet.Verification) == 0 {
		clearTurnSecretSet(&secretSet)
		return ErrTurnCredentialUnavailable
	}
	defer clearTurnSecretSet(&secretSet)
	for _, source := range secretSet.Verification {
		if len(source) == 0 {
			return ErrTurnCredentialUnavailable
		}
		secret := append([]byte(nil), source...)
		mac := hmac.New(sha1.New, secret)
		_, _ = mac.Write([]byte(username))
		expected := mac.Sum(nil)
		matched := hmac.Equal(decodedPassword, expected)
		clear(expected)
		clear(secret)
		if matched {
			return nil
		}
	}
	return ErrTurnCredentialInvalid
}

func validTurnUsernameGrammar(username string) bool {
	if strings.Count(username, ":") != 1 {
		return false
	}
	parts := strings.SplitN(username, ":", 2)
	if parts[0] == "" || parts[1] == "" {
		return false
	}
	for _, candidate := range []byte(parts[0]) {
		if candidate < '0' || candidate > '9' {
			return false
		}
	}
	opaque, err := base64.RawURLEncoding.Strict().DecodeString(parts[1])
	valid := err == nil && len(opaque) == sha256.Size
	clear(opaque)
	return valid
}

func clearTurnSecretSet(set *TurnSecretSet) {
	if set == nil {
		return
	}
	clear(set.Primary)
	for i := range set.Verification {
		clear(set.Verification[i])
	}
	set.Primary = nil
	set.Verification = nil
}

type turnCredentialRequest struct {
	action string
}

func decodeTurnCredentialRequest(raw []byte) (turnCredentialRequest, error) {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	opening, err := decoder.Token()
	if err != nil || opening != json.Delim('{') || !decoder.More() {
		return turnCredentialRequest{}, errTurnCredentialRequest
	}
	key, err := decoder.Token()
	if err != nil || key != "action" {
		return turnCredentialRequest{}, errTurnCredentialRequest
	}
	var action string
	if err := decoder.Decode(&action); err != nil || action != turnCredentialsAction || decoder.More() {
		return turnCredentialRequest{}, errTurnCredentialRequest
	}
	closing, err := decoder.Token()
	if err != nil || closing != json.Delim('}') {
		return turnCredentialRequest{}, errTurnCredentialRequest
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return turnCredentialRequest{}, errTurnCredentialRequest
	}
	return turnCredentialRequest{action: action}, nil
}

type turnCredentialResponse struct {
	Status       string   `json:"status"`
	ErrorCode    string   `json:"errorCode,omitempty"`
	Schema       string   `json:"schema,omitempty"`
	Version      int      `json:"version,omitempty"`
	Username     string   `json:"username,omitempty"`
	Password     string   `json:"password,omitempty"`
	TTLSeconds   int64    `json:"ttlSeconds,omitempty"`
	URLs         []string `json:"urls,omitempty"`
	ServerTimeMs int64    `json:"serverTimeMs,omitempty"`
	ExpiresAtMs  int64    `json:"expiresAtMs,omitempty"`
}

func handleTurnCredentialRequest(
	stream io.Writer,
	raw []byte,
	authenticatedSubject string,
	issuer TurnCredentialIssuer,
) {
	if _, err := decodeTurnCredentialRequest(raw); err != nil {
		recordTurnCredentialOutcome("invalid_request")
		writeTurnCredentialResponse(stream, turnCredentialResponse{
			Status: "ERROR", ErrorCode: turnCredentialErrorInvalidRequest,
		})
		return
	}
	if issuer == nil {
		recordTurnCredentialOutcome("unavailable")
		writeTurnCredentialResponse(stream, turnCredentialResponse{
			Status: "ERROR", ErrorCode: turnCredentialErrorUnavailable,
		})
		return
	}
	span := callDiagnosticSpanFromStream(stream)
	span.emit("turn", "mint", "started", "none", nil)
	ctx, cancel := context.WithTimeout(callDiagnosticWithContext(context.Background(), span), turnCredentialIssueTimeout)
	defer cancel()
	bundle, err := issuer.Issue(ctx, authenticatedSubject)
	if err != nil {
		code, outcome := turnCredentialFailure(err)
		recordTurnCredentialOutcome(outcome)
		writeTurnCredentialResponse(stream, turnCredentialResponse{Status: "ERROR", ErrorCode: code})
		return
	}
	if !validTurnCredentialBundle(bundle) {
		recordTurnCredentialOutcome("unavailable")
		writeTurnCredentialResponse(stream, turnCredentialResponse{
			Status: "ERROR", ErrorCode: turnCredentialErrorUnavailable,
		})
		return
	}
	recordTurnCredentialOutcome("issued")
	writeTurnCredentialResponse(stream, turnCredentialResponse{
		Status:       "OK",
		Schema:       bundle.Schema,
		Version:      bundle.Version,
		Username:     bundle.Username,
		Password:     bundle.Password,
		TTLSeconds:   bundle.TTLSeconds,
		URLs:         append([]string(nil), bundle.URLs...),
		ServerTimeMs: bundle.ServerTimeMs,
		ExpiresAtMs:  bundle.ExpiresAtMs,
	})
}

func validTurnCredentialBundle(bundle TurnCredentialBundle) bool {
	// The TTL is a deployment choice (config), bounded by the client's cap;
	// the bundle must simply be self-consistent.
	if bundle.Schema != turnCredentialSchema || bundle.Version != turnCredentialVersion ||
		bundle.TTLSeconds <= 0 || bundle.TTLSeconds > int64(turnCredentialMaxTTL/time.Second) ||
		bundle.ServerTimeMs <= 0 ||
		bundle.ExpiresAtMs-bundle.ServerTimeMs != bundle.TTLSeconds*1000 ||
		!validTurnUsernameGrammar(bundle.Username) || len(bundle.URLs) == 0 {
		return false
	}
	password, err := base64.StdEncoding.Strict().DecodeString(bundle.Password)
	validPassword := err == nil && len(password) == sha1.Size
	clear(password)
	if !validPassword {
		return false
	}
	for _, rawURL := range bundle.URLs {
		if !validTurnCredentialURL(rawURL) {
			return false
		}
	}
	return true
}

func turnCredentialFailure(err error) (string, string) {
	switch {
	case errors.Is(err, ErrTurnCredentialUnauthorized):
		return turnCredentialErrorUnauthorized, "unauthorized"
	case errors.Is(err, ErrTurnCredentialRateLimited),
		errors.Is(err, ErrTurnCredentialLimiterCapacity):
		return turnCredentialErrorRateLimited, "rate_limited"
	default:
		return turnCredentialErrorUnavailable, "unavailable"
	}
}

func writeTurnCredentialResponse(stream io.Writer, response turnCredentialResponse) {
	data, err := json.Marshal(response)
	if err != nil {
		recordTurnCredentialOutcome("write_error")
		return
	}
	defer clear(data)
	span := callDiagnosticSpanFromStream(stream)
	if response.Status == "OK" {
		span.emit("turn", "mint", "ok", "none", nil)
	} else {
		span.emit("turn", "mint", "failed", diagnosticReason(response.ErrorCode), nil)
	}
	err = writeFrame(stream, data)
	if err != nil {
		recordTurnCredentialOutcome("write_error")
		span.emit("turn", "response", "failed", "write_failed", map[string]any{"responseWritten": false})
	} else {
		span.emit("turn", "response", "ok", "none", map[string]any{"responseWritten": true})
	}
}

type turnCredentialLookup func(string) (string, bool)

type lookupTurnSecretProvider struct {
	lookup turnCredentialLookup
}

func (p lookupTurnSecretProvider) LoadTurnSecrets(context.Context) (TurnSecretSet, error) {
	primaryEncoded, ok := p.lookup(turnCredentialsPrimarySecretEnv)
	if !ok || strings.TrimSpace(primaryEncoded) == "" {
		return TurnSecretSet{}, ErrTurnCredentialUnavailable
	}
	primary, err := base64.StdEncoding.Strict().DecodeString(strings.TrimSpace(primaryEncoded))
	if err != nil || len(primary) == 0 {
		clear(primary)
		return TurnSecretSet{}, ErrTurnCredentialUnavailable
	}
	set := TurnSecretSet{Primary: primary}
	verificationEncoded, ok := p.lookup(turnCredentialsVerificationSecretsEnv)
	if !ok || strings.TrimSpace(verificationEncoded) == "" {
		set.Verification = [][]byte{append([]byte(nil), primary...)}
		return set, nil
	}
	for _, encoded := range strings.Split(verificationEncoded, ",") {
		secret, err := base64.StdEncoding.Strict().DecodeString(strings.TrimSpace(encoded))
		if err != nil || len(secret) == 0 {
			clear(secret)
			clearTurnSecretSet(&set)
			return TurnSecretSet{}, ErrTurnCredentialUnavailable
		}
		set.Verification = append(set.Verification, secret)
	}
	return set, nil
}

func newTurnCredentialIssuerFromLookup(
	lookup turnCredentialLookup,
	clock func() time.Time,
	nonce io.Reader,
) (TurnCredentialIssuer, error) {
	if lookup == nil {
		return nil, errTurnCredentialConfig
	}
	rawEnabled, exists := lookup(turnCredentialsEnabledEnv)
	if !exists || strings.TrimSpace(rawEnabled) == "" ||
		strings.EqualFold(strings.TrimSpace(rawEnabled), "false") || strings.TrimSpace(rawEnabled) == "0" {
		return nil, nil
	}
	if !strings.EqualFold(strings.TrimSpace(rawEnabled), "true") && strings.TrimSpace(rawEnabled) != "1" {
		return nil, errTurnCredentialConfig
	}
	rawURLs, ok := lookup(turnCredentialsURLsEnv)
	if !ok {
		return nil, errTurnCredentialConfig
	}
	urls := splitTurnCredentialURLs(rawURLs)
	provider := lookupTurnSecretProvider{lookup: lookup}
	loaded, err := provider.LoadTurnSecrets(context.Background())
	if err != nil {
		return nil, errTurnCredentialConfig
	}
	clearTurnSecretSet(&loaded)
	service, err := NewTurnCredentialService(TurnCredentialServiceConfig{
		URLs: urls,
		// A call must outlive its TURN credential without an audible ICE
		// restart every ten minutes; libwebrtc refreshes the allocation with
		// the credential it was given, so the TTL bounds the call length.
		TTL:                time.Hour,
		MaxClockSkew:       30 * time.Second,
		MaxRequests:        6,
		RateWindow:         time.Minute,
		MaxTrackedSubjects: 10_000,
	}, provider, clock, nonce)
	if err != nil {
		return nil, errTurnCredentialConfig
	}
	return service, nil
}

func splitTurnCredentialURLs(raw string) []string {
	parts := strings.Split(raw, ",")
	result := make([]string, 0, len(parts))
	for _, part := range parts {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			result = append(result, trimmed)
		}
	}
	return result
}

func loadTurnCredentialIssuerFromEnv() (TurnCredentialIssuer, error) {
	return newTurnCredentialIssuerFromLookup(os.LookupEnv, time.Now, rand.Reader)
}
