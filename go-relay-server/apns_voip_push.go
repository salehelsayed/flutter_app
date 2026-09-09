package main

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	apnsVoIPPushEnabledEnv    = "APNS_VOIP_PUSH_ENABLED"
	apnsVoIPEnvironmentEnv    = "APNS_VOIP_ENVIRONMENT"
	apnsVoIPTopicEnv          = "APNS_VOIP_TOPIC"
	apnsVoIPKeyIDEnv          = "APNS_VOIP_KEY_ID"
	apnsVoIPTeamIDEnv         = "APNS_VOIP_TEAM_ID"
	apnsVoIPPrivateKeyFileEnv = "APNS_VOIP_PRIVATE_KEY_FILE"

	apnsVoIPEnvironmentSandbox    = "sandbox"
	apnsVoIPEnvironmentProduction = "production"
	apnsVoIPSandboxEndpoint       = "https://api.sandbox.push.apple.com"
	apnsVoIPProductionEndpoint    = "https://api.push.apple.com"
	apnsVoIPPayloadMaxBytes       = 256
	apnsVoIPResponseMaxBytes      = 1024
	apnsVoIPAuthorizationMax      = 4096
	apnsVoIPPrivateKeyMaxBytes    = 16 * 1024
	apnsVoIPTokenMinRefreshAge    = 20 * time.Minute
	apnsVoIPTokenRefreshAge       = 50 * time.Minute
	apnsVoIPTokenMaxAge           = 60 * time.Minute
	apnsVoIPServerRetryDelay      = 15 * time.Minute
	apnsVoIPRateLimitRetryMax     = 1
)

var (
	errAPNSVoIPNetwork       = errors.New("apns voip network error")
	errAPNSVoIPInvalidConfig = errors.New("apns voip configuration invalid")
)

type apnsVoIPConfig struct {
	Enabled     bool
	Environment string
	Topic       string
	KeyID       string
	TeamID      string
	privateKey  *ecdsa.PrivateKey
}

func loadAPNSVoIPConfigFromEnv() (apnsVoIPConfig, error) {
	enabled, err := parseAPNSVoIPEnabled(strings.TrimSpace(os.Getenv(apnsVoIPPushEnabledEnv)))
	if err != nil {
		return apnsVoIPConfig{}, err
	}
	config := apnsVoIPConfig{Enabled: enabled}
	if !enabled {
		return config, nil
	}
	config.Environment = strings.TrimSpace(os.Getenv(apnsVoIPEnvironmentEnv))
	config.Topic = strings.TrimSpace(os.Getenv(apnsVoIPTopicEnv))
	config.KeyID = strings.TrimSpace(os.Getenv(apnsVoIPKeyIDEnv))
	config.TeamID = strings.TrimSpace(os.Getenv(apnsVoIPTeamIDEnv))
	privateKeyFile := strings.TrimSpace(os.Getenv(apnsVoIPPrivateKeyFileEnv))
	if !validAPNSVoIPEnvironment(config.Environment) {
		return apnsVoIPConfig{}, fmt.Errorf("%w: %s must be sandbox or production", errAPNSVoIPInvalidConfig, apnsVoIPEnvironmentEnv)
	}
	if !validAPNSVoIPTopic(config.Topic) {
		return apnsVoIPConfig{}, fmt.Errorf("%w: %s must be a valid .voip topic", errAPNSVoIPInvalidConfig, apnsVoIPTopicEnv)
	}
	if !validAPNSVoIPProviderIdentifier(config.KeyID) {
		return apnsVoIPConfig{}, fmt.Errorf("%w: %s is invalid", errAPNSVoIPInvalidConfig, apnsVoIPKeyIDEnv)
	}
	if !validAPNSVoIPProviderIdentifier(config.TeamID) {
		return apnsVoIPConfig{}, fmt.Errorf("%w: %s is invalid", errAPNSVoIPInvalidConfig, apnsVoIPTeamIDEnv)
	}
	if privateKeyFile == "" {
		return apnsVoIPConfig{}, fmt.Errorf("%w: %s is required", errAPNSVoIPInvalidConfig, apnsVoIPPrivateKeyFileEnv)
	}
	config.privateKey, err = loadAPNSVoIPPrivateKey(privateKeyFile)
	if err != nil {
		return apnsVoIPConfig{}, err
	}
	return config, nil
}

func parseAPNSVoIPEnabled(value string) (bool, error) {
	switch strings.ToLower(value) {
	case "", "0", "false":
		return false, nil
	case "1", "true":
		return true, nil
	default:
		return false, fmt.Errorf("%w: %s must be true or false", errAPNSVoIPInvalidConfig, apnsVoIPPushEnabledEnv)
	}
}

func validAPNSVoIPAuthorization(value string) bool {
	if value == "" || value != strings.TrimSpace(value) || len(value) > apnsVoIPAuthorizationMax ||
		strings.ContainsAny(value, "\r\n\t") || !strings.HasPrefix(strings.ToLower(value), "bearer ") {
		return false
	}
	token := value[len("bearer "):]
	return token != "" && !strings.Contains(token, " ")
}

func validAPNSVoIPProviderIdentifier(value string) bool {
	if len(value) != 10 {
		return false
	}
	for _, char := range value {
		if (char >= 'A' && char <= 'Z') || (char >= '0' && char <= '9') {
			continue
		}
		return false
	}
	return true
}

func loadAPNSVoIPPrivateKey(path string) (*ecdsa.PrivateKey, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("%w: cannot read %s", errAPNSVoIPInvalidConfig, apnsVoIPPrivateKeyFileEnv)
	}
	defer file.Close()
	raw, err := io.ReadAll(io.LimitReader(file, apnsVoIPPrivateKeyMaxBytes+1))
	if err != nil || len(raw) == 0 || len(raw) > apnsVoIPPrivateKeyMaxBytes {
		return nil, fmt.Errorf("%w: cannot read %s", errAPNSVoIPInvalidConfig, apnsVoIPPrivateKeyFileEnv)
	}
	block, rest := pem.Decode(raw)
	if block == nil || block.Type != "PRIVATE KEY" || len(bytes.TrimSpace(rest)) != 0 {
		return nil, fmt.Errorf("%w: %s must contain one PKCS#8 P-256 key", errAPNSVoIPInvalidConfig, apnsVoIPPrivateKeyFileEnv)
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("%w: %s must contain one PKCS#8 P-256 key", errAPNSVoIPInvalidConfig, apnsVoIPPrivateKeyFileEnv)
	}
	privateKey, ok := parsed.(*ecdsa.PrivateKey)
	if !ok || privateKey.Curve != elliptic.P256() || privateKey.D == nil ||
		privateKey.D.Sign() <= 0 || privateKey.PublicKey.X == nil || privateKey.PublicKey.Y == nil ||
		!elliptic.P256().IsOnCurve(privateKey.PublicKey.X, privateKey.PublicKey.Y) {
		return nil, fmt.Errorf("%w: %s must contain one PKCS#8 P-256 key", errAPNSVoIPInvalidConfig, apnsVoIPPrivateKeyFileEnv)
	}
	return privateKey, nil
}

func (c apnsVoIPConfig) endpoint() string {
	if c.Environment == "sandbox" {
		return apnsVoIPSandboxEndpoint
	}
	return apnsVoIPProductionEndpoint
}

type apnsVoIPProviderRequest struct {
	Token      string
	Topic      string
	Expiration time.Time
	Payload    []byte
}

type apnsVoIPProviderResponse struct {
	StatusCode       int
	Reason           string
	RetryAfter       time.Duration
	RetryAfterValid  bool
	AuthTokenRefresh bool
}

type apnsVoIPProvider interface {
	Send(context.Context, apnsVoIPProviderRequest) (apnsVoIPProviderResponse, error)
}

type apnsVoIPAuthorizationSource interface {
	Authorization(context.Context) (string, error)
	HandleExpiredProviderToken(string) bool
}

type apnsVoIPES256Signer interface {
	SignDigest([]byte) (*big.Int, *big.Int, error)
}

type ecdsaAPNSVoIPSigner struct {
	privateKey *ecdsa.PrivateKey
}

func (s ecdsaAPNSVoIPSigner) SignDigest(digest []byte) (*big.Int, *big.Int, error) {
	if s.privateKey == nil {
		return nil, nil, ErrCallBackendUnavailable
	}
	return ecdsa.Sign(rand.Reader, s.privateKey, digest)
}

type apnsVoIPProviderTokenSource struct {
	mu                  sync.Mutex
	keyID               string
	teamID              string
	signer              apnsVoIPES256Signer
	now                 func() time.Time
	cachedAuthorization string
	issuedAt            time.Time
	refreshNotBefore    time.Time
}

func newAPNSVoIPProviderTokenSource(config apnsVoIPConfig) *apnsVoIPProviderTokenSource {
	return &apnsVoIPProviderTokenSource{
		keyID: config.KeyID, teamID: config.TeamID,
		signer: ecdsaAPNSVoIPSigner{privateKey: config.privateKey}, now: time.Now,
	}
}

func (s *apnsVoIPProviderTokenSource) Authorization(ctx context.Context) (string, error) {
	if s == nil || !validAPNSVoIPProviderIdentifier(s.keyID) ||
		!validAPNSVoIPProviderIdentifier(s.teamID) || s.signer == nil {
		return "", ErrCallBackendUnavailable
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.nowTime()
	if !s.refreshNotBefore.IsZero() {
		if now.Before(s.refreshNotBefore) {
			return "", ErrCallBackendUnavailable
		}
		s.refreshNotBefore = time.Time{}
	}
	age := now.Sub(s.issuedAt)
	if s.cachedAuthorization != "" {
		if age < 0 {
			s.invalidateRollbackLocked()
			return "", ErrCallBackendUnavailable
		}
		if age < apnsVoIPTokenRefreshAge {
			return s.cachedAuthorization, nil
		}
	}
	authorization, err := buildAPNSVoIPProviderAuthorization(
		s.keyID, s.teamID, now, s.signer,
	)
	if err != nil {
		if s.cachedAuthorization != "" && age >= 0 && age < apnsVoIPTokenMaxAge {
			return s.cachedAuthorization, nil
		}
		return "", ErrCallBackendUnavailable
	}
	s.cachedAuthorization = authorization
	s.issuedAt = now
	return authorization, nil
}

func (s *apnsVoIPProviderTokenSource) HandleExpiredProviderToken(usedAuthorization string) bool {
	if s == nil || usedAuthorization == "" {
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if usedAuthorization != s.cachedAuthorization || s.issuedAt.IsZero() {
		return false
	}
	age := s.nowTime().Sub(s.issuedAt)
	if age < 0 {
		s.invalidateRollbackLocked()
		return false
	}
	if age < apnsVoIPTokenMinRefreshAge {
		return false
	}
	s.cachedAuthorization = ""
	s.issuedAt = time.Time{}
	return true
}

func (s *apnsVoIPProviderTokenSource) invalidateRollbackLocked() {
	if s == nil || s.issuedAt.IsZero() {
		return
	}
	s.refreshNotBefore = s.issuedAt.Add(apnsVoIPTokenMinRefreshAge)
	s.cachedAuthorization = ""
	s.issuedAt = time.Time{}
}

func (s *apnsVoIPProviderTokenSource) nowTime() time.Time {
	if s != nil && s.now != nil {
		return s.now().UTC().Truncate(time.Second)
	}
	return time.Now().UTC().Truncate(time.Second)
}

func buildAPNSVoIPProviderAuthorization(
	keyID string,
	teamID string,
	issuedAt time.Time,
	signer apnsVoIPES256Signer,
) (string, error) {
	if !validAPNSVoIPProviderIdentifier(keyID) ||
		!validAPNSVoIPProviderIdentifier(teamID) || signer == nil {
		return "", ErrCallBackendUnavailable
	}
	header, err := json.Marshal(struct {
		Algorithm string `json:"alg"`
		KeyID     string `json:"kid"`
	}{Algorithm: "ES256", KeyID: keyID})
	if err != nil {
		return "", ErrCallBackendUnavailable
	}
	claims, err := json.Marshal(struct {
		Issuer   string `json:"iss"`
		IssuedAt int64  `json:"iat"`
	}{Issuer: teamID, IssuedAt: issuedAt.UTC().Unix()})
	if err != nil {
		return "", ErrCallBackendUnavailable
	}
	unsigned := base64.RawURLEncoding.EncodeToString(header) + "." +
		base64.RawURLEncoding.EncodeToString(claims)
	digest := sha256.Sum256([]byte(unsigned))
	r, signatureS, err := signer.SignDigest(digest[:])
	if err != nil || !validAPNSVoIPES256Component(r) || !validAPNSVoIPES256Component(signatureS) {
		return "", ErrCallBackendUnavailable
	}
	signature := make([]byte, 64)
	r.FillBytes(signature[:32])
	signatureS.FillBytes(signature[32:])
	authorization := "bearer " + unsigned + "." + base64.RawURLEncoding.EncodeToString(signature)
	if !validAPNSVoIPAuthorization(authorization) {
		return "", ErrCallBackendUnavailable
	}
	return authorization, nil
}

func validAPNSVoIPES256Component(value *big.Int) bool {
	return value != nil && value.Sign() > 0 && value.BitLen() <= 256 &&
		value.Cmp(elliptic.P256().Params().N) < 0
}

type httpAPNSVoIPProvider struct {
	client        *http.Client
	endpoint      string
	authorization apnsVoIPAuthorizationSource
	now           func() time.Time
}

func newHTTPAPNSVoIPProvider(config apnsVoIPConfig) *httpAPNSVoIPProvider {
	return newHTTPAPNSVoIPProviderForEndpoint(config.endpoint(), newAPNSVoIPProviderTokenSource(config))
}

// newHTTPAPNSVoIPProviderForEndpoint builds one APNs HTTP/2 client for a
// single environment endpoint. The provider-token source is shared between the
// sandbox and production providers: the ES256 provider token is not bound to
// an environment, so one cache serves both doors.
func newHTTPAPNSVoIPProviderForEndpoint(
	endpoint string,
	authorization apnsVoIPAuthorizationSource,
) *httpAPNSVoIPProvider {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.ForceAttemptHTTP2 = true
	return &httpAPNSVoIPProvider{
		client: &http.Client{
			Transport: transport,
			CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
				return http.ErrUseLastResponse
			},
		}, endpoint: endpoint,
		authorization: authorization, now: time.Now,
	}
}

func (p *httpAPNSVoIPProvider) Send(
	ctx context.Context,
	request apnsVoIPProviderRequest,
) (apnsVoIPProviderResponse, error) {
	if p == nil || p.client == nil || p.endpoint == "" || p.authorization == nil ||
		request.Token == "" ||
		!validAPNSVoIPTopic(request.Topic) || request.Expiration.IsZero() ||
		len(request.Payload) == 0 || len(request.Payload) > apnsVoIPPayloadMaxBytes {
		return apnsVoIPProviderResponse{}, ErrCallBackendUnavailable
	}
	authorization, err := p.authorization.Authorization(ctx)
	if err != nil || !validAPNSVoIPAuthorization(authorization) {
		if err != nil && (errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded)) {
			return apnsVoIPProviderResponse{}, err
		}
		return apnsVoIPProviderResponse{}, ErrCallBackendUnavailable
	}
	endpoint := strings.TrimRight(p.endpoint, "/") + "/3/device/" + url.PathEscape(request.Token)
	httpRequest, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(request.Payload))
	if err != nil {
		return apnsVoIPProviderResponse{}, ErrCallBackendUnavailable
	}
	httpRequest.Header.Set("authorization", authorization)
	httpRequest.Header.Set("apns-topic", request.Topic)
	httpRequest.Header.Set("apns-push-type", "voip")
	httpRequest.Header.Set("apns-priority", "10")
	httpRequest.Header.Set("apns-expiration", strconv.FormatInt(request.Expiration.Unix(), 10))
	httpRequest.Header.Set("content-type", "application/json")

	response, err := p.client.Do(httpRequest)
	if err != nil {
		if ctxErr := ctx.Err(); ctxErr != nil {
			return apnsVoIPProviderResponse{}, ctxErr
		}
		return apnsVoIPProviderResponse{}, errAPNSVoIPNetwork
	}
	defer response.Body.Close()

	result := apnsVoIPProviderResponse{StatusCode: response.StatusCode}
	result.RetryAfter, result.RetryAfterValid = parseAPNSVoIPRetryAfter(
		response.Header.Get("retry-after"), p.nowTime(),
	)
	body, readErr := io.ReadAll(io.LimitReader(response.Body, apnsVoIPResponseMaxBytes+1))
	if readErr != nil {
		return apnsVoIPProviderResponse{}, errAPNSVoIPNetwork
	}
	if len(body) <= apnsVoIPResponseMaxBytes {
		var providerError struct {
			Reason string `json:"reason"`
		}
		if json.Unmarshal(body, &providerError) == nil {
			result.Reason = providerError.Reason
		}
	}
	if result.StatusCode == http.StatusForbidden && result.Reason == "ExpiredProviderToken" {
		result.AuthTokenRefresh = p.authorization.HandleExpiredProviderToken(authorization)
	}
	return result, nil
}

func (p *httpAPNSVoIPProvider) nowTime() time.Time {
	if p != nil && p.now != nil {
		return p.now().UTC()
	}
	return time.Now().UTC()
}

func parseAPNSVoIPRetryAfter(value string, now time.Time) (time.Duration, bool) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return 0, false
	}
	if seconds, err := strconv.ParseUint(trimmed, 10, 64); err == nil {
		const maxRetryAfterSeconds = uint64((1<<63 - 1) / int64(time.Second))
		if seconds == 0 || seconds > maxRetryAfterSeconds {
			return 0, false
		}
		return time.Duration(seconds) * time.Second, true
	}
	retryAt, err := http.ParseTime(trimmed)
	if err != nil {
		return 0, false
	}
	delay := retryAt.Sub(now)
	if delay <= 0 {
		return 0, false
	}
	return delay, true
}

type apnsVoIPCallWakeDispatcher struct {
	// providers is keyed by APNs environment (sandbox / production). A wake is
	// sent to the environment the token was registered under first; the other
	// environment is a single fallback attempt when Apple rejects the token.
	providers         map[string]apnsVoIPProvider
	topic             string
	capabilityVersion uint64
	retryDelays       []time.Duration
	now               func() time.Time
}

func newAPNSVoIPCallWakeDispatcher(config apnsVoIPConfig) *apnsVoIPCallWakeDispatcher {
	authorization := newAPNSVoIPProviderTokenSource(config)
	return &apnsVoIPCallWakeDispatcher{
		providers: map[string]apnsVoIPProvider{
			apnsVoIPEnvironmentSandbox:    newHTTPAPNSVoIPProviderForEndpoint(apnsVoIPSandboxEndpoint, authorization),
			apnsVoIPEnvironmentProduction: newHTTPAPNSVoIPProviderForEndpoint(apnsVoIPProductionEndpoint, authorization),
		},
		topic: config.Topic, capabilityVersion: callIOSVoIPCapabilityVersion,
		retryDelays: []time.Duration{100 * time.Millisecond, 250 * time.Millisecond},
		now:         time.Now,
	}
}

// apnsVoIPOtherEnvironment names the environment to try when Apple rejects a
// token at the environment the device registered it under.
func apnsVoIPOtherEnvironment(environment string) string {
	if environment == apnsVoIPEnvironmentSandbox {
		return apnsVoIPEnvironmentProduction
	}
	return apnsVoIPEnvironmentSandbox
}

func (d *apnsVoIPCallWakeDispatcher) DispatchCallWake(
	ctx context.Context,
	route CallWakeRoute,
	payload CallWakePayload,
) error {
	var primary apnsVoIPProvider
	if d != nil && validAPNSVoIPEnvironment(route.Environment) {
		primary = d.providers[route.Environment]
	}
	if primary == nil || route.Kind != CallTokenKindIOSVoIP ||
		route.Platform != "ios" || route.Token == "" ||
		route.Topic != d.topic || route.CapabilityVersion != d.capabilityVersion ||
		route.RefreshEpoch == 0 || route.Generation == 0 {
		recordAPNSVoIPPushOutcome(apnsVoIPMetricRejectedRoute)
		return ErrCallBackendUnavailable
	}
	now := d.nowTime()
	body, err := buildAPNSVoIPPayload(payload, now)
	if err != nil {
		recordAPNSVoIPPushOutcome(apnsVoIPMetricRejectedPayload)
		return err
	}
	expiration := time.UnixMilli(payload.ExpiresAtMs)
	dispatchCtx, cancel := context.WithDeadline(ctx, expiration)
	defer cancel()
	request := apnsVoIPProviderRequest{
		Token: route.Token, Topic: route.Topic, Expiration: expiration, Payload: body,
	}
	err = d.dispatchThrough(dispatchCtx, primary, request, expiration)
	if !errors.Is(err, ErrCallTokenInvalid) {
		return err
	}
	// Apple rejected the token at the environment the device registered it
	// under. A dev-signed build holds a sandbox PushKit token yet reports the
	// Info.plist environment ("production"), so the other environment gets one
	// attempt before the token is treated as invalid and revoked.
	fallback := d.providers[apnsVoIPOtherEnvironment(route.Environment)]
	if fallback == nil {
		return ErrCallTokenInvalid
	}
	fallbackErr := d.dispatchThrough(dispatchCtx, fallback, request, expiration)
	switch {
	case fallbackErr == nil:
		recordAPNSVoIPPushOutcome(apnsVoIPMetricSentCrossEnvironment)
		return nil
	case errors.Is(fallbackErr, ErrCallTokenInvalid):
		return ErrCallTokenInvalid
	default:
		// Inconclusive at the other environment: keep the token so the next
		// wake retries instead of revoking on a single environment's answer.
		return ErrCallBackendUnavailable
	}
}

// dispatchThrough sends one wake through a single environment provider with
// the bounded network / rate-limit / provider-token retries Apple documents.
func (d *apnsVoIPCallWakeDispatcher) dispatchThrough(
	dispatchCtx context.Context,
	provider apnsVoIPProvider,
	request apnsVoIPProviderRequest,
	expiration time.Time,
) error {
	networkAttempt := 0
	rateLimitRetries := 0
	authTokenRetried := false
	for {
		if ctxErr := dispatchCtx.Err(); ctxErr != nil {
			return ErrCallBackendUnavailable
		}
		if !d.nowTime().Before(expiration) {
			recordAPNSVoIPPushOutcome(apnsVoIPMetricExpired)
			return ErrCallBackendUnavailable
		}
		callDiagnosticProvider(dispatchCtx, "ios", networkAttempt+rateLimitRetries, true, nil)
		response, sendErr := provider.Send(dispatchCtx, request)
		outcome, retryable, invalid := classifyAPNSVoIPResult(response, sendErr)
		recordAPNSVoIPPushOutcome(outcome)
		diagnosticErr := sendErr
		if outcome != apnsVoIPMetricSent && diagnosticErr == nil {
			diagnosticErr = ErrCallBackendUnavailable
		}
		callDiagnosticProvider(dispatchCtx, "ios", networkAttempt+rateLimitRetries, false, diagnosticErr)
		if outcome == apnsVoIPMetricSent {
			return nil
		}
		if invalid {
			return ErrCallTokenInvalid
		}
		if !retryable {
			return ErrCallBackendUnavailable
		}
		var delay time.Duration
		switch outcome {
		case apnsVoIPMetricNetwork:
			if networkAttempt >= len(d.retryDelays) {
				return ErrCallBackendUnavailable
			}
			delay = d.retryDelays[networkAttempt]
			networkAttempt++
		case apnsVoIPMetricRateLimited:
			if rateLimitRetries >= apnsVoIPRateLimitRetryMax ||
				!response.RetryAfterValid || response.RetryAfter <= 0 {
				return ErrCallBackendUnavailable
			}
			rateLimitRetries++
			delay = response.RetryAfter
		case apnsVoIPMetricAuthError:
			if authTokenRetried || !response.AuthTokenRefresh {
				return ErrCallBackendUnavailable
			}
			authTokenRetried = true
		default:
			return ErrCallBackendUnavailable
		}
		if delay < 0 || !d.nowTime().Add(delay).Before(expiration) ||
			!waitForRetryDelay(dispatchCtx, delay) {
			recordAPNSVoIPPushOutcome(apnsVoIPMetricExpired)
			return ErrCallBackendUnavailable
		}
	}
}

func (d *apnsVoIPCallWakeDispatcher) nowTime() time.Time {
	if d != nil && d.now != nil {
		return d.now().UTC()
	}
	return time.Now().UTC()
}

func buildAPNSVoIPPayload(payload CallWakePayload, now time.Time) ([]byte, error) {
	if !validCallRandomID(payload.CallHandle) || !validCallRandomID(payload.WakeHandle) ||
		payload.ExpiresAtMs <= 0 {
		return nil, ErrCallInvalidRequest
	}
	expiration := time.UnixMilli(payload.ExpiresAtMs)
	if !expiration.After(now) || expiration.After(now.Add(CallMaxPreconnectTTL)) {
		return nil, ErrCallExpiry
	}
	wire := struct {
		APS struct {
			ContentAvailable int `json:"content-available"`
		} `json:"aps"`
		Diagnostics *callDiagnosticPush `json:"diagnostics,omitempty"`
		Version     string              `json:"v"`
		WakeType    string              `json:"w"`
		CallHandle  string              `json:"c"`
		WakeHandle  string              `json:"h"`
		ExpiresAt   string              `json:"e"`
	}{
		Version: "1", WakeType: "call", CallHandle: payload.CallHandle,
		WakeHandle: payload.WakeHandle, ExpiresAt: strconv.FormatInt(payload.ExpiresAtMs, 10),
	}
	wire.APS.ContentAvailable = 1
	raw, err := json.Marshal(wire)
	if err != nil || len(raw) > apnsVoIPPayloadMaxBytes {
		return nil, ErrCallInvalidRequest
	}
	if payload.Diagnostics != nil && payload.Diagnostics.SchemaVersion == 1 && diagnosticUUID.MatchString(payload.Diagnostics.TraceID) {
		wire.Diagnostics = payload.Diagnostics
		raw, err = json.Marshal(wire)
		if err != nil || len(raw) > apnsVoIPPayloadMaxBytes+128 {
			return nil, ErrCallInvalidRequest
		}
	}
	return raw, nil
}

func classifyAPNSVoIPResult(
	response apnsVoIPProviderResponse,
	err error,
) (outcome string, retryable, invalid bool) {
	if err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return apnsVoIPMetricCanceled, false, false
		}
		if errors.Is(err, errAPNSVoIPNetwork) {
			return apnsVoIPMetricNetwork, true, false
		}
		return apnsVoIPMetricProviderError, false, false
	}
	if response.StatusCode == http.StatusOK {
		return apnsVoIPMetricSent, false, false
	}
	if (response.StatusCode == http.StatusBadRequest &&
		(response.Reason == "BadDeviceToken" || response.Reason == "DeviceTokenNotForTopic")) ||
		(response.StatusCode == http.StatusGone && response.Reason == "Unregistered") {
		return apnsVoIPMetricInvalidToken, false, true
	}
	if response.Reason == "TooManyProviderTokenUpdates" {
		return apnsVoIPMetricAuthError, false, false
	}
	if response.StatusCode == http.StatusTooManyRequests {
		return apnsVoIPMetricRateLimited, response.RetryAfterValid && response.RetryAfter > 0, false
	}
	if response.StatusCode == http.StatusForbidden && response.Reason == "ExpiredProviderToken" {
		return apnsVoIPMetricAuthError, response.AuthTokenRefresh, false
	}
	if response.StatusCode >= 500 && response.StatusCode <= 599 {
		return apnsVoIPMetricServerError, false, false
	}
	return apnsVoIPMetricProviderError, false, false
}

var _ apnsVoIPProvider = (*httpAPNSVoIPProvider)(nil)
var _ CallWakeDispatcher = (*apnsVoIPCallWakeDispatcher)(nil)
