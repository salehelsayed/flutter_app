package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha1" //nolint:gosec // coturn REST authentication requires HMAC-SHA1.
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"log"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

const (
	turnTestSchema  = "turn_credentials"
	turnTestVersion = 1
)

var turnTestNow = time.Date(2026, time.August, 30, 11, 22, 0, 0, time.UTC)

type turnTestSecretProvider struct {
	mu    sync.Mutex
	set   TurnSecretSet
	err   error
	calls int
}

func (p *turnTestSecretProvider) LoadTurnSecrets(context.Context) (TurnSecretSet, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.calls++
	return cloneTurnTestSecretSet(p.set), p.err
}

func (p *turnTestSecretProvider) replace(set TurnSecretSet, err error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.set = cloneTurnTestSecretSet(set)
	p.err = err
}

func (p *turnTestSecretProvider) callCount() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.calls
}

func cloneTurnTestSecretSet(set TurnSecretSet) TurnSecretSet {
	cloned := TurnSecretSet{
		Primary: append([]byte(nil), set.Primary...),
	}
	cloned.Verification = make([][]byte, len(set.Verification))
	for i := range set.Verification {
		cloned.Verification[i] = append([]byte(nil), set.Verification[i]...)
	}
	return cloned
}

type turnTestNonceReader struct {
	mu   sync.Mutex
	next byte
}

func (r *turnTestNonceReader) Read(dst []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for i := range dst {
		dst[i] = r.next + byte(i) //nolint:gosec // deterministic synthetic fixture bytes.
	}
	r.next++
	return len(dst), nil
}

type turnTestFailingReader struct {
	err error
}

func (r turnTestFailingReader) Read([]byte) (int, error) {
	return 0, r.err
}

func turnTestSecret(seed byte) []byte {
	secret := make([]byte, 32)
	for i := range secret {
		secret[i] = seed + byte(i) //nolint:gosec // deterministic synthetic fixture bytes.
	}
	return secret
}

func turnTestSubject(seed byte) string {
	fixture := make([]byte, 24)
	for i := range fixture {
		fixture[i] = seed + byte(i) //nolint:gosec // deterministic synthetic fixture bytes.
	}
	return base64.RawURLEncoding.EncodeToString(fixture)
}

func turnTestConfig() TurnCredentialServiceConfig {
	return TurnCredentialServiceConfig{
		URLs: []string{
			"turn:relay.invalid:3478?transport=udp",
			"turns:relay.invalid:443?transport=tcp",
		},
		TTL:                10 * time.Minute,
		MaxClockSkew:       30 * time.Second,
		MaxRequests:        32,
		RateWindow:         time.Minute,
		MaxTrackedSubjects: 64,
	}
}

func newTurnTestService(
	t *testing.T,
	config TurnCredentialServiceConfig,
	provider TurnSecretProvider,
	clock func() time.Time,
	nonce io.Reader,
) *TurnCredentialService {
	t.Helper()
	service, err := NewTurnCredentialService(config, provider, clock, nonce)
	if err != nil {
		t.Fatal("construct TURN credential service from valid synthetic fixtures")
	}
	return service
}

func turnTestProvider(secret []byte) *turnTestSecretProvider {
	return &turnTestSecretProvider{set: TurnSecretSet{
		Primary:      append([]byte(nil), secret...),
		Verification: [][]byte{append([]byte(nil), secret...)},
	}}
}

func mutateTurnTestPassword(value string) string {
	if value == "" {
		return "A"
	}
	result := []byte(value)
	if result[0] == 'A' {
		result[0] = 'B'
	} else {
		result[0] = 'A'
	}
	return string(result)
}

func TestTurnCredentialsV1_CoturnRESTGrammarAndTenMinuteExpiry(t *testing.T) {
	secret := turnTestSecret(0x11)
	provider := turnTestProvider(secret)
	config := turnTestConfig()
	service := newTurnTestService(
		t,
		config,
		provider,
		func() time.Time { return turnTestNow },
		&turnTestNonceReader{next: 0x41},
	)

	bundle, err := service.Issue(context.Background(), turnTestSubject(0x21))
	if err != nil {
		t.Fatal("issue TURN credential from valid synthetic fixtures")
	}
	if bundle.Schema != turnTestSchema || bundle.Version != turnTestVersion {
		t.Fatal("TURN credential schema/version changed")
	}
	if bundle.TTLSeconds != 600 {
		t.Fatalf("TURN credential TTL = %d seconds, want 600", bundle.TTLSeconds)
	}
	if bundle.ServerTimeMs != turnTestNow.UnixMilli() {
		t.Fatal("TURN credential server time did not use the injected clock")
	}
	wantExpiryMs := turnTestNow.Add(10 * time.Minute).UnixMilli()
	if bundle.ExpiresAtMs != wantExpiryMs {
		t.Fatal("TURN credential expiry was not exactly ten minutes")
	}
	if len(bundle.URLs) != len(config.URLs) {
		t.Fatal("TURN credential URL count changed")
	}
	for i := range config.URLs {
		if bundle.URLs[i] != config.URLs[i] {
			t.Fatal("TURN credential URL ordering changed")
		}
	}

	parts := strings.Split(bundle.Username, ":")
	if len(parts) != 2 || parts[1] == "" {
		t.Fatal("coturn username must be expiry:opaque-subject")
	}
	expiresUnix, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil || expiresUnix != turnTestNow.Add(10*time.Minute).Unix() {
		t.Fatal("coturn username expiry prefix is invalid")
	}
	if _, err := base64.RawURLEncoding.DecodeString(parts[1]); err != nil {
		t.Fatal("coturn username subject component is not opaque base64url")
	}

	mac := hmac.New(sha1.New, secret)
	_, _ = mac.Write([]byte(bundle.Username))
	wantPassword := base64.StdEncoding.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(bundle.Password), []byte(wantPassword)) {
		t.Fatal("coturn password is not base64(HMAC-SHA1(secret, username))")
	}
	if err := service.Verify(context.Background(), bundle.Username, bundle.Password); err != nil {
		t.Fatal("issuer rejected its freshly minted coturn credential")
	}
}

func TestTurnCredentialsV1_AuthenticatedSubjectIsBoundButNotDisclosed(t *testing.T) {
	secret := turnTestSecret(0x31)
	providerA := turnTestProvider(secret)
	providerB := turnTestProvider(secret)
	config := turnTestConfig()
	subjectA := turnTestSubject(0x51)
	subjectB := turnTestSubject(0x71)
	serviceA := newTurnTestService(
		t,
		config,
		providerA,
		func() time.Time { return turnTestNow },
		&turnTestNonceReader{next: 0x22},
	)
	serviceB := newTurnTestService(
		t,
		config,
		providerB,
		func() time.Time { return turnTestNow },
		&turnTestNonceReader{next: 0x22},
	)

	bundleA, err := serviceA.Issue(context.Background(), subjectA)
	if err != nil {
		t.Fatal("issue first authenticated TURN credential")
	}
	bundleB, err := serviceB.Issue(context.Background(), subjectB)
	if err != nil {
		t.Fatal("issue second authenticated TURN credential")
	}
	if bundleA.Username == bundleB.Username {
		t.Fatal("authenticated subjects produced the same username under the same nonce")
	}
	if strings.Contains(bundleA.Username, subjectA) || strings.Contains(bundleB.Username, subjectB) {
		t.Fatal("TURN username disclosed its authenticated subject")
	}
	if _, err := serviceA.Issue(context.Background(), ""); !errors.Is(err, ErrTurnCredentialUnauthorized) {
		t.Fatal("empty authenticated subject did not fail closed")
	}
}

func TestTurnCredentialsV1_VerificationRejectsForgedWrongExpiredAndSkewed(t *testing.T) {
	now := turnTestNow
	secret := turnTestSecret(0x17)
	service := newTurnTestService(
		t,
		turnTestConfig(),
		turnTestProvider(secret),
		func() time.Time { return now },
		&turnTestNonceReader{next: 0x62},
	)
	bundle, err := service.Issue(context.Background(), turnTestSubject(0x33))
	if err != nil {
		t.Fatal("issue verification fixture")
	}

	forged := mutateTurnTestPassword(bundle.Password)
	if err := service.Verify(context.Background(), bundle.Username, forged); !errors.Is(err, ErrTurnCredentialInvalid) {
		t.Fatal("forged coturn password was not rejected")
	}

	wrongSecretService := newTurnTestService(
		t,
		turnTestConfig(),
		turnTestProvider(turnTestSecret(0x91)),
		func() time.Time { return now },
		&turnTestNonceReader{next: 0x72},
	)
	if err := wrongSecretService.Verify(context.Background(), bundle.Username, bundle.Password); !errors.Is(err, ErrTurnCredentialInvalid) {
		t.Fatal("coturn credential verified under the wrong shared secret")
	}

	for _, username := range []string{
		"",
		"not-a-timestamp:opaque",
		strconv.FormatInt(turnTestNow.Add(10*time.Minute).Unix(), 10),
		strconv.FormatInt(turnTestNow.Add(10*time.Minute).Unix(), 10) + ":opaque:extra",
	} {
		if err := service.Verify(context.Background(), username, bundle.Password); !errors.Is(err, ErrTurnCredentialInvalid) {
			t.Fatal("malformed coturn username was not rejected")
		}
	}

	now = turnTestNow.Add(10 * time.Minute)
	if err := service.Verify(context.Background(), bundle.Username, bundle.Password); !errors.Is(err, ErrTurnCredentialExpired) {
		t.Fatal("credential remained valid at its expiry boundary")
	}

	skewedVerifier := newTurnTestService(
		t,
		turnTestConfig(),
		turnTestProvider(secret),
		func() time.Time { return turnTestNow.Add(-2 * time.Minute) },
		&turnTestNonceReader{next: 0x73},
	)
	if err := skewedVerifier.Verify(context.Background(), bundle.Username, bundle.Password); !errors.Is(err, ErrTurnCredentialInvalid) {
		t.Fatal("credential outside the configured future-skew bound was accepted")
	}
}

func TestTurnCredentialsV1_SecretRotationOverlapAndRollback(t *testing.T) {
	now := turnTestNow
	oldSecret := turnTestSecret(0x12)
	newSecret := turnTestSecret(0x92)
	provider := turnTestProvider(oldSecret)
	service := newTurnTestService(
		t,
		turnTestConfig(),
		provider,
		func() time.Time { return now },
		&turnTestNonceReader{next: 0x35},
	)
	subject := turnTestSubject(0x52)

	oldBundle, err := service.Issue(context.Background(), subject)
	if err != nil {
		t.Fatal("issue pre-rotation credential")
	}
	provider.replace(TurnSecretSet{
		Primary: newSecret,
		Verification: [][]byte{
			newSecret,
			oldSecret,
		},
	}, nil)
	if err := service.Verify(context.Background(), oldBundle.Username, oldBundle.Password); err != nil {
		t.Fatal("rotation invalidated a still-live credential minted by the old secret")
	}
	newBundle, err := service.Issue(context.Background(), subject)
	if err != nil {
		t.Fatal("issue post-rotation credential")
	}
	if err := service.Verify(context.Background(), newBundle.Username, newBundle.Password); err != nil {
		t.Fatal("post-rotation credential did not use the new primary secret")
	}

	provider.replace(TurnSecretSet{
		Primary: oldSecret,
		Verification: [][]byte{
			oldSecret,
			newSecret,
		},
	}, nil)
	if err := service.Verify(context.Background(), oldBundle.Username, oldBundle.Password); err != nil {
		t.Fatal("rollback invalidated the original still-live credential")
	}
	if err := service.Verify(context.Background(), newBundle.Username, newBundle.Password); err != nil {
		t.Fatal("rollback invalidated a still-live credential from the rotated secret")
	}
	rollbackBundle, err := service.Issue(context.Background(), subject)
	if err != nil {
		t.Fatal("issue credential after rollback")
	}
	mac := hmac.New(sha1.New, oldSecret)
	_, _ = mac.Write([]byte(rollbackBundle.Username))
	wantRollbackPassword := base64.StdEncoding.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(rollbackBundle.Password), []byte(wantRollbackPassword)) {
		t.Fatal("rollback did not restore the old primary minting secret")
	}

	now = turnTestNow.Add(10 * time.Minute)
	if err := service.Verify(context.Background(), oldBundle.Username, oldBundle.Password); !errors.Is(err, ErrTurnCredentialExpired) {
		t.Fatal("rotation overlap extended an old credential beyond its advertised TTL")
	}
}

func TestTurnCredentialsV1_MissingAndFailingDependenciesFailClosedAndRedacted(t *testing.T) {
	config := turnTestConfig()
	secret := turnTestSecret(0x44)
	clock := func() time.Time { return turnTestNow }
	nonce := &turnTestNonceReader{next: 0x14}

	if _, err := NewTurnCredentialService(config, nil, clock, nonce); err == nil {
		t.Fatal("missing secret provider did not fail closed")
	}
	if _, err := NewTurnCredentialService(config, turnTestProvider(secret), nil, nonce); err == nil {
		t.Fatal("missing clock did not fail closed")
	}
	if _, err := NewTurnCredentialService(config, turnTestProvider(secret), clock, nil); err == nil {
		t.Fatal("missing nonce source did not fail closed")
	}

	privateMarker := string([]byte{0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2d, 0x63, 0x61, 0x6e, 0x61, 0x72, 0x79})
	provider := turnTestProvider(secret)
	provider.replace(TurnSecretSet{}, errors.New(privateMarker))
	service := newTurnTestService(t, config, provider, clock, nonce)
	var journal bytes.Buffer
	previousWriter := log.Writer()
	log.SetOutput(&journal)
	t.Cleanup(func() { log.SetOutput(previousWriter) })

	_, err := service.Issue(context.Background(), turnTestSubject(0x66))
	if !errors.Is(err, ErrTurnCredentialUnavailable) {
		t.Fatal("secret provider failure did not return the finite unavailable class")
	}
	if strings.Contains(err.Error(), privateMarker) || strings.Contains(journal.String(), privateMarker) {
		t.Fatal("secret provider failure details crossed the redaction boundary")
	}

	provider.replace(TurnSecretSet{
		Verification: [][]byte{secret},
	}, nil)
	if _, err := service.Issue(context.Background(), turnTestSubject(0x67)); !errors.Is(err, ErrTurnCredentialUnavailable) {
		t.Fatal("missing primary secret fell back to a verification/static secret")
	}

	nonceMarker := string([]byte{0x6e, 0x6f, 0x6e, 0x63, 0x65, 0x2d, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65})
	nonceFailureService := newTurnTestService(
		t,
		config,
		turnTestProvider(secret),
		clock,
		turnTestFailingReader{err: errors.New(nonceMarker)},
	)
	_, err = nonceFailureService.Issue(context.Background(), turnTestSubject(0x68))
	if !errors.Is(err, ErrTurnCredentialUnavailable) {
		t.Fatal("nonce source failure did not fail closed")
	}
	if strings.Contains(err.Error(), nonceMarker) || strings.Contains(journal.String(), nonceMarker) {
		t.Fatal("nonce source failure details crossed the redaction boundary")
	}
}

func TestTurnCredentialsV1_ConfigRejectsInvalidTTLAndStaticURLCredentials(t *testing.T) {
	provider := turnTestProvider(turnTestSecret(0x55))
	clock := func() time.Time { return turnTestNow }

	for _, ttl := range []time.Duration{0, -time.Second} {
		config := turnTestConfig()
		config.TTL = ttl
		if _, err := NewTurnCredentialService(config, provider, clock, &turnTestNonceReader{}); err == nil {
			t.Fatal("non-positive TURN credential TTL was accepted")
		}
	}

	for _, rawURL := range []string{
		"turn://fixture-user:fixture-password@relay.invalid:3478",
		"turns://fixture-user:fixture-password@relay.invalid:443",
	} {
		config := turnTestConfig()
		config.URLs = []string{rawURL}
		if _, err := NewTurnCredentialService(config, provider, clock, &turnTestNonceReader{}); err == nil {
			t.Fatal("TURN URL containing static userinfo credentials was accepted")
		}
	}

	config := turnTestConfig()
	config.URLs = nil
	if _, err := NewTurnCredentialService(config, provider, clock, &turnTestNonceReader{}); err == nil {
		t.Fatal("empty TURN URL allowlist was accepted")
	}
}

func TestTurnCredentialsV1_RateLimitIsPerSubjectAndResetsAtBoundary(t *testing.T) {
	now := turnTestNow
	config := turnTestConfig()
	config.MaxRequests = 2
	config.RateWindow = time.Minute
	config.MaxTrackedSubjects = 2
	provider := turnTestProvider(turnTestSecret(0x19))
	service := newTurnTestService(
		t,
		config,
		provider,
		func() time.Time { return now },
		&turnTestNonceReader{next: 0x19},
	)
	subjectA := turnTestSubject(0x20)
	subjectB := turnTestSubject(0x40)

	for i := 0; i < 2; i++ {
		if _, err := service.Issue(context.Background(), subjectA); err != nil {
			t.Fatal("in-quota authenticated subject was rejected")
		}
	}
	if _, err := service.Issue(context.Background(), subjectA); !errors.Is(err, ErrTurnCredentialRateLimited) {
		t.Fatal("over-quota authenticated subject was not rate limited")
	}
	if provider.callCount() != 2 {
		t.Fatal("over-quota request reached the secret provider")
	}
	if _, err := service.Issue(context.Background(), subjectB); err != nil {
		t.Fatal("one subject's quota blocked a different authenticated subject")
	}

	now = now.Add(time.Minute)
	if _, err := service.Issue(context.Background(), subjectA); err != nil {
		t.Fatal("subject quota did not reset at the exact window boundary")
	}
}

func TestTurnCredentialsV1_RateLimitIsConcurrent(t *testing.T) {
	const (
		allowed = 8
		total   = 64
	)
	config := turnTestConfig()
	config.MaxRequests = allowed
	config.MaxTrackedSubjects = 4
	service := newTurnTestService(
		t,
		config,
		turnTestProvider(turnTestSecret(0x28)),
		func() time.Time { return turnTestNow },
		&turnTestNonceReader{next: 0x28},
	)
	subject := turnTestSubject(0x38)

	type result struct {
		username string
		err      error
	}
	start := make(chan struct{})
	results := make(chan result, total)
	var group sync.WaitGroup
	for i := 0; i < total; i++ {
		group.Add(1)
		go func() {
			defer group.Done()
			<-start
			bundle, err := service.Issue(context.Background(), subject)
			results <- result{username: bundle.Username, err: err}
		}()
	}
	close(start)
	group.Wait()
	close(results)

	successes := 0
	rateLimited := 0
	usernames := make(map[string]struct{}, allowed)
	for got := range results {
		switch {
		case got.err == nil:
			successes++
			if _, duplicate := usernames[got.username]; duplicate {
				t.Fatal("concurrent issuance reused a credential username")
			}
			usernames[got.username] = struct{}{}
		case errors.Is(got.err, ErrTurnCredentialRateLimited):
			rateLimited++
		default:
			t.Fatal("concurrent issuance returned an unexpected error class")
		}
	}
	if successes != allowed || rateLimited != total-allowed {
		t.Fatalf("concurrent limiter results = success %d limited %d, want %d/%d", successes, rateLimited, allowed, total-allowed)
	}
}

func TestTurnCredentialsV1_RateLimiterCapacityFailsClosedWithoutEvictionBypass(t *testing.T) {
	now := turnTestNow
	config := turnTestConfig()
	config.MaxRequests = 3
	config.RateWindow = time.Minute
	config.MaxTrackedSubjects = 2
	service := newTurnTestService(
		t,
		config,
		turnTestProvider(turnTestSecret(0x39)),
		func() time.Time { return now },
		&turnTestNonceReader{next: 0x39},
	)
	subjectA := turnTestSubject(0x30)
	subjectB := turnTestSubject(0x50)
	subjectC := turnTestSubject(0x70)

	if _, err := service.Issue(context.Background(), subjectA); err != nil {
		t.Fatal("first capacity fixture was rejected")
	}
	if _, err := service.Issue(context.Background(), subjectB); err != nil {
		t.Fatal("second capacity fixture was rejected")
	}
	if _, err := service.Issue(context.Background(), subjectC); !errors.Is(err, ErrTurnCredentialLimiterCapacity) {
		t.Fatal("unseen subject did not fail closed at limiter capacity")
	}
	if _, err := service.Issue(context.Background(), subjectA); err != nil {
		t.Fatal("capacity pressure evicted an active subject and changed its quota")
	}
	if _, err := service.Issue(context.Background(), subjectC); !errors.Is(err, ErrTurnCredentialLimiterCapacity) {
		t.Fatal("repeated unseen-subject attempts bypassed limiter capacity")
	}

	now = now.Add(time.Minute)
	if _, err := service.Issue(context.Background(), subjectC); err != nil {
		t.Fatal("expired limiter entries were not pruned at the window boundary")
	}
}

func TestTurnCredentialsV1_RateLimiterCapacityIsAtomicAcrossSubjects(t *testing.T) {
	const (
		capacity = 5
		total    = 40
	)
	config := turnTestConfig()
	config.MaxRequests = 1
	config.MaxTrackedSubjects = capacity
	service := newTurnTestService(
		t,
		config,
		turnTestProvider(turnTestSecret(0x48)),
		func() time.Time { return turnTestNow },
		&turnTestNonceReader{next: 0x48},
	)

	start := make(chan struct{})
	errs := make(chan error, total)
	var group sync.WaitGroup
	for i := 0; i < total; i++ {
		subject := turnTestSubject(byte(i + 1))
		group.Add(1)
		go func() {
			defer group.Done()
			<-start
			_, err := service.Issue(context.Background(), subject)
			errs <- err
		}()
	}
	close(start)
	group.Wait()
	close(errs)

	successes := 0
	capacityRejected := 0
	for err := range errs {
		switch {
		case err == nil:
			successes++
		case errors.Is(err, ErrTurnCredentialLimiterCapacity):
			capacityRejected++
		default:
			t.Fatal("concurrent capacity test returned an unexpected error class")
		}
	}
	if successes != capacity || capacityRejected != total-capacity {
		t.Fatalf("capacity results = success %d rejected %d, want %d/%d", successes, capacityRejected, capacity, total-capacity)
	}
}

func TestTurnCredentialsV1_DefensiveCopiesProviderSecretsAndURLs(t *testing.T) {
	config := turnTestConfig()
	secret := turnTestSecret(0x58)
	provider := turnTestProvider(secret)
	service := newTurnTestService(
		t,
		config,
		provider,
		func() time.Time { return turnTestNow },
		&turnTestNonceReader{next: 0x58},
	)

	config.URLs[0] = "turn:mutated.invalid:3478"
	secret[0] ^= 0xff
	bundle, err := service.Issue(context.Background(), turnTestSubject(0x58))
	if err != nil {
		t.Fatal("issue defensive-copy fixture")
	}
	if bundle.URLs[0] == config.URLs[0] {
		t.Fatal("service retained the caller's mutable URL slice")
	}
	bundle.URLs[0] = "turn:response-mutated.invalid:3478"
	next, err := service.Issue(context.Background(), turnTestSubject(0x59))
	if err != nil {
		t.Fatal("issue second defensive-copy fixture")
	}
	if next.URLs[0] == bundle.URLs[0] {
		t.Fatal("issued bundles share a mutable URL slice")
	}
}

func TestTurnCredentialsV1_ProviderFailureDoesNotConsumeNonceOrMintFallback(t *testing.T) {
	config := turnTestConfig()
	privateMarker := string([]byte{0x70, 0x72, 0x6f, 0x76, 0x69, 0x64, 0x65, 0x72, 0x2d, 0x66, 0x61, 0x69, 0x6c})
	provider := &turnTestSecretProvider{err: fmt.Errorf("%s", privateMarker)}
	nonce := &turnTestNonceReader{next: 0x63}
	service := newTurnTestService(
		t,
		config,
		provider,
		func() time.Time { return turnTestNow },
		nonce,
	)

	if _, err := service.Issue(context.Background(), turnTestSubject(0x63)); !errors.Is(err, ErrTurnCredentialUnavailable) {
		t.Fatal("provider outage did not fail closed")
	}
	nonce.mu.Lock()
	nextAfterFailure := nonce.next
	nonce.mu.Unlock()
	if nextAfterFailure != 0x63 {
		t.Fatal("provider outage consumed nonce material before authorization could complete")
	}
	if provider.callCount() != 1 {
		t.Fatal("provider outage was retried without an explicit bounded retry policy")
	}
}

func TestTurnCredentialsV1_RuntimeConfigurationIsDefaultOff(t *testing.T) {
	values := map[string]string{
		turnCredentialsURLsEnv:          "turn:relay.invalid:3478?transport=udp",
		turnCredentialsPrimarySecretEnv: base64.StdEncoding.EncodeToString(turnTestSecret(0x69)),
	}
	lookup := func(key string) (string, bool) {
		value, ok := values[key]
		return value, ok
	}

	issuer, err := newTurnCredentialIssuerFromLookup(
		lookup,
		func() time.Time { return turnTestNow },
		&turnTestNonceReader{next: 0x69},
	)
	if err != nil || issuer != nil {
		t.Fatal("TURN credential runtime configuration was not default-off")
	}

	values[turnCredentialsEnabledEnv] = "false"
	issuer, err = newTurnCredentialIssuerFromLookup(
		lookup,
		func() time.Time { return turnTestNow },
		&turnTestNonceReader{next: 0x69},
	)
	if err != nil || issuer != nil {
		t.Fatal("explicitly disabled TURN credentials constructed an issuer")
	}
}

func TestTurnCredentialsV1_RuntimeConfigurationUsesInjectedLookupAndFailsClosed(t *testing.T) {
	oldSecret := turnTestSecret(0x6a)
	newSecret := turnTestSecret(0x7a)
	values := map[string]string{
		turnCredentialsEnabledEnv:       "true",
		turnCredentialsURLsEnv:          "turn:relay.invalid:3478?transport=udp,turns:relay.invalid:443?transport=tcp",
		turnCredentialsPrimarySecretEnv: base64.StdEncoding.EncodeToString(newSecret),
		turnCredentialsVerificationSecretsEnv: strings.Join([]string{
			base64.StdEncoding.EncodeToString(newSecret),
			base64.StdEncoding.EncodeToString(oldSecret),
		}, ","),
	}
	lookup := func(key string) (string, bool) {
		value, ok := values[key]
		return value, ok
	}

	issuer, err := newTurnCredentialIssuerFromLookup(
		lookup,
		func() time.Time { return turnTestNow },
		&turnTestNonceReader{next: 0x6a},
	)
	if err != nil || issuer == nil {
		t.Fatal("valid injected TURN credential configuration was rejected")
	}
	bundle, err := issuer.Issue(context.Background(), turnTestSubject(0x6a))
	if err != nil || bundle.TTLSeconds != 3600 || len(bundle.URLs) != 2 {
		t.Fatal("runtime issuer did not freeze the one-hour ordered URL contract")
	}
	service, ok := issuer.(*TurnCredentialService)
	if !ok {
		t.Fatal("runtime issuer did not use the testable credential service")
	}
	if err := service.Verify(context.Background(), bundle.Username, bundle.Password); err != nil {
		t.Fatal("runtime issuer did not retain the configured verification overlap")
	}

	delete(values, turnCredentialsPrimarySecretEnv)
	if _, err := issuer.Issue(context.Background(), turnTestSubject(0x6b)); !errors.Is(err, ErrTurnCredentialUnavailable) {
		t.Fatal("runtime secret removal did not fail closed without a static fallback")
	}

	invalidValues := []map[string]string{
		{turnCredentialsEnabledEnv: "sometimes"},
		{turnCredentialsEnabledEnv: "true"},
		{
			turnCredentialsEnabledEnv:       "true",
			turnCredentialsURLsEnv:          "turn:relay.invalid:3478?transport=udp",
			turnCredentialsPrimarySecretEnv: "not-base64",
		},
		{
			turnCredentialsEnabledEnv:       "true",
			turnCredentialsURLsEnv:          "turn://fixture:fixture@relay.invalid:3478",
			turnCredentialsPrimarySecretEnv: base64.StdEncoding.EncodeToString(turnTestSecret(0x6c)),
		},
	}
	for _, invalid := range invalidValues {
		invalidLookup := func(key string) (string, bool) {
			value, exists := invalid[key]
			return value, exists
		}
		if issuer, err := newTurnCredentialIssuerFromLookup(
			invalidLookup,
			func() time.Time { return turnTestNow },
			&turnTestNonceReader{next: 0x6c},
		); err == nil || issuer != nil {
			t.Fatal("invalid enabled TURN credential configuration did not fail closed")
		}
	}
}
