// Package callaudiooracle provides a host-only, deterministic media-forwarding
// oracle. It is intentionally isolated from the shipped Flutter application.
package callaudiooracle

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	credentialSchema = "mknoon.call_audio_oracle.credentials.v1"
	resultSchema     = "mknoon.call_audio_oracle.result.v1"
	resultVersion    = 1
	fixtureSchema    = "mknoon.call_audio_oracle.fixture.v1"
	coturnLockSchema = "mknoon.call_audio_oracle.coturn_lock.v1"

	pionVersion                = "v4.2.19"
	lockedCoturnImage          = "coturn/coturn:4.17.2-r0"
	lockedCoturnDigest         = "sha256:aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e"
	knownFixtureSHA256         = "429dc0349c60f06f5c062fd237a333c7941e6b98445f33272c0be5185425b9f5"
	knownPayloadSequenceSHA256 = "be7d1839fb31844c2c23feaa0a1c3435b63c2ba29d404980ed6675a4c4e6f8a0"

	maximumPrivateJSONBytes = 16 * 1024
	minimumCredentialLife   = 30 * time.Second
	maximumCredentialAge    = 5 * time.Minute
	maximumCredentialLife   = 24 * time.Hour
)

var (
	errPrivateFileRequired = errors.New("private regular credential file required")
	errCredentialDocument  = errors.New("credential document invalid")
	errCredentialFreshness = errors.New("TURN credentials are not fresh")
	errTurnAuthority       = errors.New("TURN authority invalid")
	errFixtureDocument     = errors.New("known-Opus fixture provenance invalid")
	errFixtureDigest       = errors.New("known-Opus fixture digest mismatch")
	errCoturnLock          = errors.New("coturn dependency lock invalid")
	errResultIncomplete    = errors.New("audio oracle result incomplete")
	errResultFile          = errors.New("sanitized result file unavailable")
	errPeerSetup           = errors.New("audio oracle peer setup failed")
	errPeerSignaling       = errors.New("audio oracle peer signaling failed")
	errPeerConnection      = errors.New("audio oracle relay connection failed")
	errPeerRoute           = errors.New("audio oracle selected route invalid")
	errMediaTransfer       = errors.New("known-Opus media transfer failed")
	errOracleCleanup       = errors.New("audio oracle cleanup incomplete")
)

// EphemeralCredential is a short-lived credential issued by the production
// TURN authority. It is input only and is never copied into OracleResult.
type EphemeralCredential struct {
	Username        string `json:"username"`
	Password        string `json:"password"`
	IssuedAtUnixMs  int64  `json:"issued_at_unix_ms"`
	ExpiresAtUnixMs int64  `json:"expires_at_unix_ms"`
}

// CredentialConfig is accepted only from an ephemeral mode-0600 file. It has
// deliberately no field capable of carrying the coturn REST shared secret.
type CredentialConfig struct {
	Schema                string              `json:"schema"`
	TurnURL               string              `json:"turn_url"`
	ExpectedTransport     string              `json:"expected_transport"`
	FixtureInstanceSHA256 string              `json:"fixture_instance_sha256"`
	PeerA                 EphemeralCredential `json:"peer_a"`
	PeerB                 EphemeralCredential `json:"peer_b"`

	fixtureInstanceSHA256Proof string
}

// DirectionResult exposes only boolean proof. Counts, RTP identifiers, audio
// bytes, and observed hashes remain process-local.
type DirectionResult struct {
	CodecValid        bool `json:"codec_valid"`
	PayloadCountExact bool `json:"payload_count_exact"`
	PayloadOrderExact bool `json:"payload_order_exact"`
	PayloadHashExact  bool `json:"payload_hash_exact"`
}

// RouteResult proves the selected route class without retaining candidates or
// network addresses.
type RouteResult struct {
	RelaySelected  bool `json:"relay_selected"`
	TransportMatch bool `json:"transport_match"`
}

type CoturnDependency struct {
	Image  string `json:"image"`
	Digest string `json:"digest"`
}

// OracleResult is the complete durable allowlist for this tool.
type OracleResult struct {
	Schema                string           `json:"schema"`
	Version               int              `json:"version"`
	Passed                bool             `json:"passed"`
	PionVersion           string           `json:"pion_version"`
	FixtureSHA256         string           `json:"fixture_sha256"`
	Coturn                CoturnDependency `json:"coturn"`
	ExpectedTransport     string           `json:"expected_transport"`
	TurnAuthoritySHA256   string           `json:"turn_authority_sha256"`
	FixtureInstanceSHA256 string           `json:"fixture_instance_sha256"`
	AToB                  DirectionResult  `json:"a_to_b"`
	BToA                  DirectionResult  `json:"b_to_a"`
	PeerARoute            RouteResult      `json:"peer_a_route"`
	PeerBRoute            RouteResult      `json:"peer_b_route"`
	CleanupComplete       bool             `json:"cleanup_complete"`

	turnAuthoritySHA256Proof   string
	fixtureInstanceSHA256Proof string
}

type coturnLock struct {
	Schema  string `json:"schema"`
	Image   string `json:"image"`
	Digest  string `json:"digest"`
	Source  string `json:"source"`
	Version string `json:"version"`
	License string `json:"license"`
}

type fixtureProvenance struct {
	Schema                    string `json:"schema"`
	File                      string `json:"file"`
	FileSHA256                string `json:"file_sha256"`
	License                   string `json:"license"`
	Codec                     string `json:"codec"`
	SampleRateHz              int    `json:"sample_rate_hz"`
	Channels                  int    `json:"channels"`
	FrameDurationMs           int    `json:"frame_duration_ms"`
	RTPPayloadCount           int    `json:"rtp_payload_count"`
	RTPPayloadSequenceSHA256  string `json:"rtp_payload_sequence_sha256"`
	PayloadHashDomain         string `json:"payload_hash_domain"`
	GenerationFormula         string `json:"generation_formula"`
	Generator                 string `json:"generator"`
	GeneratorVersion          string `json:"generator_version"`
	GeneratedAtSourceEpochUTC string `json:"generated_at_source_epoch_utc"`
}

type knownFixture struct {
	payloads      [][]byte
	payloadDigest [sha256.Size]byte
	fileDigestHex string
}

// LoadCredentialConfig loads and validates two independently issued TURN REST
// credentials without ever accepting the authority's shared secret.
func LoadCredentialConfig(
	path string,
	now time.Time,
) (CredentialConfig, error) {
	var config CredentialConfig
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm() != 0o600 {
		return config, errPrivateFileRequired
	}
	file, err := os.Open(path)
	if err != nil {
		return config, errPrivateFileRequired
	}
	defer file.Close()
	openedInfo, err := file.Stat()
	if err != nil || !os.SameFile(info, openedInfo) ||
		openedInfo.Mode().Perm() != 0o600 {
		return config, errPrivateFileRequired
	}
	if err := decodeStrictJSON(file, maximumPrivateJSONBytes, &config); err != nil {
		return CredentialConfig{}, errCredentialDocument
	}
	if !validCredentialConfig(config, now.UTC()) {
		return CredentialConfig{}, errCredentialFreshness
	}
	config.fixtureInstanceSHA256Proof = config.FixtureInstanceSHA256
	return config, nil
}

func validCredentialConfig(config CredentialConfig, now time.Time) bool {
	if config.Schema != credentialSchema ||
		!validTurnURLAndTransport(config.TurnURL, config.ExpectedTransport) ||
		!validLowerHexSHA256(config.FixtureInstanceSHA256) ||
		!validEphemeralCredential(config.PeerA, now) ||
		!validEphemeralCredential(config.PeerB, now) {
		return false
	}
	return config.PeerA.Username != config.PeerB.Username &&
		config.PeerA.Password != config.PeerB.Password
}

func hasFixtureInstanceRuntimeProvenance(config CredentialConfig) bool {
	return config.fixtureInstanceSHA256Proof != "" &&
		config.FixtureInstanceSHA256 == config.fixtureInstanceSHA256Proof
}

func validTurnURLAndTransport(rawURL string, expected string) bool {
	_, transport, err := canonicalTurnURL(rawURL)
	return err == nil && expected == transport
}

func canonicalTurnAuthoritySHA256(rawURL string) (string, error) {
	canonical, _, err := canonicalTurnURL(rawURL)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256([]byte(canonical))
	return hex.EncodeToString(digest[:]), nil
}

func canonicalTurnURL(rawURL string) (string, string, error) {
	if rawURL == "" || rawURL != strings.TrimSpace(rawURL) ||
		strings.ContainsAny(rawURL, "\r\n\t") {
		return "", "", errTurnAuthority
	}
	parsed, err := url.Parse(rawURL)
	if err != nil || parsed.Fragment != "" || parsed.User != nil ||
		parsed.Host != "" || parsed.Opaque == "" || parsed.Path != "" ||
		parsed.RawPath != "" || parsed.ForceQuery ||
		(parsed.Scheme != "turn" && parsed.Scheme != "turns") {
		return "", "", errTurnAuthority
	}
	transportValues, present := parsed.Query()["transport"]
	if !present || len(parsed.Query()) != 1 || len(transportValues) != 1 {
		return "", "", errTurnAuthority
	}
	transport := strings.ToLower(transportValues[0])
	if (transport != "udp" && transport != "tcp") ||
		(parsed.Scheme == "turns" && transport != "tcp") {
		return "", "", errTurnAuthority
	}
	host, portText, err := net.SplitHostPort(parsed.Opaque)
	if err != nil || host == "" || portText == "" || strings.Contains(host, "%") {
		return "", "", errTurnAuthority
	}
	port, err := strconv.ParseUint(portText, 10, 16)
	if err != nil || port == 0 {
		return "", "", errTurnAuthority
	}
	if parsedIP := net.ParseIP(host); parsedIP != nil {
		host = parsedIP.String()
	} else {
		host = strings.ToLower(host)
		if !validTurnHostname(host) {
			return "", "", errTurnAuthority
		}
	}
	canonical := parsed.Scheme + ":" +
		net.JoinHostPort(host, strconv.FormatUint(port, 10)) +
		"?transport=" + transport
	return canonical, transport, nil
}

func validTurnHostname(host string) bool {
	if len(host) == 0 || len(host) > 253 || strings.HasPrefix(host, ".") ||
		strings.HasSuffix(host, ".") {
		return false
	}
	for _, label := range strings.Split(host, ".") {
		if len(label) == 0 || len(label) > 63 || label[0] == '-' ||
			label[len(label)-1] == '-' {
			return false
		}
		for _, character := range label {
			if (character < 'a' || character > 'z') &&
				(character < '0' || character > '9') && character != '-' {
				return false
			}
		}
	}
	return true
}

func validEphemeralCredential(
	credential EphemeralCredential,
	now time.Time,
) bool {
	if credential.Username == "" || credential.Password == "" ||
		strings.ContainsAny(credential.Username, "\r\n\t") ||
		strings.ContainsAny(credential.Password, "\r\n\t") {
		return false
	}
	issuedAt := time.UnixMilli(credential.IssuedAtUnixMs)
	expiresAt := time.UnixMilli(credential.ExpiresAtUnixMs)
	if issuedAt.After(now.Add(5*time.Second)) ||
		now.Sub(issuedAt) > maximumCredentialAge ||
		expiresAt.Sub(now) < minimumCredentialLife ||
		expiresAt.Sub(issuedAt) > maximumCredentialLife {
		return false
	}
	expiryPrefix, _, present := strings.Cut(credential.Username, ":")
	expirySeconds, err := strconv.ParseInt(expiryPrefix, 10, 64)
	return present && err == nil &&
		absInt64(expirySeconds-expiresAt.Unix()) <= 1
}

func absInt64(value int64) int64 {
	if value < 0 {
		return -value
	}
	return value
}

// RunKnownOpusBothDirections runs two relay-only peers. Its named return and
// deferred cleanup ensure every error path closes the same resources.
func RunKnownOpusBothDirections(
	ctx context.Context,
	credentials CredentialConfig,
	fixturePath string,
	coturnLockPath string,
) (result OracleResult, runErr error) {
	if !validCredentialConfig(credentials, time.Now().UTC()) ||
		!hasFixtureInstanceRuntimeProvenance(credentials) {
		return result, errCredentialFreshness
	}
	fixture, err := loadKnownFixture(fixturePath)
	if err != nil {
		return result, err
	}
	lock, err := loadCoturnLock(coturnLockPath)
	if err != nil {
		return result, err
	}
	turnAuthoritySHA256, err := canonicalTurnAuthoritySHA256(credentials.TurnURL)
	if err != nil {
		return result, errTurnAuthority
	}
	result = OracleResult{
		Schema:                     resultSchema,
		Version:                    resultVersion,
		PionVersion:                pionVersion,
		FixtureSHA256:              fixture.fileDigestHex,
		Coturn:                     CoturnDependency{Image: lock.Image, Digest: lock.Digest},
		ExpectedTransport:          credentials.ExpectedTransport,
		TurnAuthoritySHA256:        turnAuthoritySHA256,
		FixtureInstanceSHA256:      credentials.FixtureInstanceSHA256,
		turnAuthoritySHA256Proof:   turnAuthoritySHA256,
		fixtureInstanceSHA256Proof: credentials.FixtureInstanceSHA256,
	}

	runContext, cancel := context.WithCancel(ctx)
	resources, err := newOracleResources(runContext, credentials, fixture)
	if err != nil {
		cancel()
		return result, err
	}
	defer func() {
		cancel()
		result.CleanupComplete = resources.close()
		if !result.CleanupComplete && runErr == nil {
			runErr = errOracleCleanup
		}
		result.Passed = runErr == nil && result.coreProofComplete()
	}()

	if err := resources.negotiate(runContext); err != nil {
		return result, err
	}
	result.PeerARoute, result.PeerBRoute, err = resources.verifyRoutes(
		credentials.ExpectedTransport,
	)
	if err != nil {
		return result, err
	}
	result.AToB, result.BToA, err = resources.exchange(runContext)
	if err != nil {
		return result, err
	}
	if !result.coreProofComplete() {
		return result, errMediaTransfer
	}
	return result, nil
}

func (result OracleResult) coreProofComplete() bool {
	return directionComplete(result.AToB) &&
		directionComplete(result.BToA) &&
		result.PeerARoute.RelaySelected &&
		result.PeerARoute.TransportMatch &&
		result.PeerBRoute.RelaySelected &&
		result.PeerBRoute.TransportMatch
}

func directionComplete(result DirectionResult) bool {
	return result.CodecValid && result.PayloadCountExact &&
		result.PayloadOrderExact && result.PayloadHashExact
}

// Validate rejects direct-route, one-direction, unclean, dependency-drift,
// and malformed-success mutations.
func (result OracleResult) Validate() error {
	if result.Schema != resultSchema || result.Version != resultVersion ||
		result.PionVersion != pionVersion ||
		result.Coturn.Image != lockedCoturnImage ||
		result.Coturn.Digest != lockedCoturnDigest ||
		result.FixtureSHA256 != knownFixtureSHA256 ||
		!validLowerHexSHA256(result.TurnAuthoritySHA256) ||
		result.turnAuthoritySHA256Proof == "" ||
		result.TurnAuthoritySHA256 != result.turnAuthoritySHA256Proof ||
		!validLowerHexSHA256(result.FixtureInstanceSHA256) ||
		result.fixtureInstanceSHA256Proof == "" ||
		result.FixtureInstanceSHA256 != result.fixtureInstanceSHA256Proof ||
		(result.ExpectedTransport != "udp" && result.ExpectedTransport != "tcp") ||
		!result.Passed || !result.CleanupComplete || !result.coreProofComplete() {
		return errResultIncomplete
	}
	return nil
}

// WriteSanitizedResultExclusive writes only OracleResult's explicit allowlist.
// O_EXCL prevents overwriting an existing evidence artifact.
func WriteSanitizedResultExclusive(path string, result OracleResult) error {
	if err := result.Validate(); err != nil {
		return err
	}
	encoded, err := json.Marshal(result)
	if err != nil {
		return errResultFile
	}
	encoded = append(encoded, '\n')
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return errResultFile
	}
	complete := false
	defer func() {
		_ = file.Close()
		if !complete {
			_ = os.Remove(path)
		}
	}()
	if err := file.Chmod(0o600); err != nil {
		return errResultFile
	}
	if _, err := file.Write(encoded); err != nil {
		return errResultFile
	}
	if err := file.Sync(); err != nil {
		return errResultFile
	}
	if err := file.Close(); err != nil {
		return errResultFile
	}
	complete = true
	return nil
}

func loadCoturnLock(path string) (coturnLock, error) {
	var lock coturnLock
	file, err := os.Open(path)
	if err != nil {
		return lock, errCoturnLock
	}
	defer file.Close()
	if err := decodeStrictJSON(file, maximumPrivateJSONBytes, &lock); err != nil ||
		lock.Schema != coturnLockSchema ||
		lock.Image != lockedCoturnImage || lock.Digest != lockedCoturnDigest ||
		lock.Source != "https://github.com/coturn/coturn" ||
		lock.Version != "4.17.2-r0" || lock.License != "BSD-3-Clause" {
		return coturnLock{}, errCoturnLock
	}
	return lock, nil
}

func decodeStrictJSON(reader io.Reader, maxBytes int64, destination any) error {
	limited := &io.LimitedReader{R: reader, N: maxBytes + 1}
	decoder := json.NewDecoder(limited)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return errors.New("trailing JSON data")
	}
	if limited.N <= 0 {
		return errors.New("JSON document too large")
	}
	return nil
}

func validLowerHexSHA256(value string) bool {
	if len(value) != sha256.Size*2 || value != strings.ToLower(value) {
		return false
	}
	decoded, err := hex.DecodeString(value)
	return err == nil && len(decoded) == sha256.Size
}

func containsBytes(haystack []byte, needle []byte) bool {
	return bytes.Contains(haystack, needle)
}

func provenancePathForFixture(path string) string {
	extension := filepath.Ext(path)
	return strings.TrimSuffix(path, extension) + ".provenance.json"
}
