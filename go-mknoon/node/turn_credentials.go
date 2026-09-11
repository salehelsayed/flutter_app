package node

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
)

const (
	turnCredentialsV1Action      = "turn_credentials_v1"
	turnCredentialsSchema        = "turn_credentials"
	turnCredentialsVersion       = 1
	turnCredentialsMaxClockSkew  = 5 * time.Minute
	turnCredentialsMaxTTL        = time.Hour
	turnCredentialsMaxFieldBytes = 4096
	turnCredentialsMaxURLs       = 16
	turnCredentialsMaxRetryAfter = 15 * time.Minute
	// Flutter's callP2PTurnCredentialsV1 bridge deadline is five seconds. Keep
	// the whole native operation inside it, including fallback and stream I/O.
	turnCredentialsRequestTimeout = 4 * time.Second
)

var (
	ErrTurnCredentialsUnsupported     = errors.New("turn credentials unsupported")
	ErrTurnCredentialsInvalidResponse = errors.New("turn credentials response invalid")
	ErrTurnCredentialsUnavailable     = errors.New("turn credentials unavailable")
	ErrTurnCredentialsRejected        = errors.New("turn credential retrieval rejected")
	ErrTurnCredentialsRequired        = errors.New("valid turn credentials required")
)

// TurnCredentialBundle is the short-lived, action-scoped credential response.
// It intentionally contains no peer identity, static credential, shared
// secret, call metadata, SDP, candidate, or allocation address.
type TurnCredentialBundle struct {
	Schema       string   `json:"schema"`
	Version      int      `json:"version"`
	URLs         []string `json:"urls"`
	Username     string   `json:"username"`
	Password     string   `json:"password"`
	TTLSeconds   int64    `json:"ttlSeconds"`
	ExpiresAtMs  int64    `json:"expiresAtMs"`
	ServerTimeMs int64    `json:"serverTimeMs"`
}

// TurnCredentialsRelayError is a finite, structured relay rejection. Error
// text never includes a relay response, address, peer ID, or credential value.
type TurnCredentialsRelayError struct {
	Code       string
	RetryAfter time.Duration
}

func (e *TurnCredentialsRelayError) Error() string {
	if e == nil || e.Code == "" {
		return ErrTurnCredentialsUnavailable.Error()
	}
	return "turn credentials unavailable: " + e.Code
}

func (e *TurnCredentialsRelayError) Unwrap() error {
	return ErrTurnCredentialsUnavailable
}

// Transient is deliberately an allowlist. Authentication, invalid requests and
// unknown relay codes must not authorize a direct fallback at the call layer.
func (e *TurnCredentialsRelayError) Transient() bool {
	return e != nil && (e.Code == "TURN_CREDENTIALS_UNAVAILABLE" ||
		e.Code == "TURN_CREDENTIALS_RATE_LIMITED" || e.Code == "RATE_LIMITED")
}

type turnCredentialsWireResponse struct {
	Status       string   `json:"status"`
	Error        string   `json:"error,omitempty"`
	ErrorCode    string   `json:"errorCode,omitempty"`
	RetryAfterMs int64    `json:"retryAfterMs,omitempty"`
	Schema       string   `json:"schema,omitempty"`
	Version      int      `json:"version,omitempty"`
	URLs         []string `json:"urls,omitempty"`
	Username     string   `json:"username,omitempty"`
	Password     string   `json:"password,omitempty"`
	TTLSeconds   int64    `json:"ttlSeconds,omitempty"`
	ExpiresAtMs  int64    `json:"expiresAtMs,omitempty"`
	ServerTimeMs int64    `json:"serverTimeMs,omitempty"`
}

// TurnCredentialsV1 requests an authenticated action-only credential bundle.
// The relay derives the subject from the libp2p stream; the request therefore
// carries no claimed identity or payload. Configured relays are tried in order
// within one shared deadline; received failures stay privacy-safe.
func (n *Node) TurnCredentialsV1() (TurnCredentialBundle, error) {
	return n.turnCredentialsV1At(time.Now)
}

func (n *Node) turnCredentialsV1At(now func() time.Time, diagnostics ...*CallDiagnosticContext) (TurnCredentialBundle, error) {
	n.mu.RLock()
	h := n.host
	ctx := n.ctx
	n.mu.RUnlock()
	if h == nil || ctx == nil {
		return TurnCredentialBundle{}, ErrTurnCredentialsUnavailable
	}
	ctx, cancel := context.WithTimeout(ctx, turnCredentialsRequestTimeout)
	defer cancel()

	relays := n.buildRelaySelector(nil).Relays()
	if len(relays) == 0 {
		return TurnCredentialBundle{}, ErrTurnCredentialsUnavailable
	}

	deadline, _ := ctx.Deadline()
	var lastErr error
	for i, relay := range relays {
		if ctx.Err() != nil {
			break
		}
		// Reserve a fair share for each remaining peer. An unresponsive first
		// relay must not consume the bridge deadline before fallback can run.
		// Keep each peer's addresses together for the swarm's family/transport
		// racing, and issue at most one credential request to that peer.
		attemptTimeout := time.Until(deadline) / time.Duration(len(relays)-i)
		if attemptTimeout <= 0 {
			break
		}
		attemptCtx, attemptCancel := context.WithTimeout(ctx, attemptTimeout)
		diagnostic := n.diagnosticForRelay(relay.ID, diagnostics)
		bundle, err := requestTurnCredentialsV1(attemptCtx, h, relay, now(), diagnostic)
		if diagnostic != nil && errors.Is(err, errTurnDiagnosticUnsupported) {
			n.setDiagnosticRelay(relay.ID, false)
			bundle, err = requestTurnCredentialsV1(attemptCtx, h, relay, now())
		}
		attemptCancel()
		if err == nil {
			return bundle, nil
		}
		lastErr = preferTurnCredentialError(lastErr, err)
	}
	if lastErr == nil {
		lastErr = ErrTurnCredentialsUnavailable
	}
	return TurnCredentialBundle{}, lastErr
}

func requestTurnCredentialsV1(
	parent context.Context,
	h host.Host,
	relay RelayInfo,
	now time.Time,
	diagnostics ...*CallDiagnosticContext,
) (TurnCredentialBundle, error) {
	ctx, cancel := context.WithTimeout(parent, RelayProbeTimeout)
	defer cancel()
	if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
		return TurnCredentialBundle{}, turnCredentialConnectError(err)
	}

	stream, err := h.NewStream(ctx, relay.ID, InboxProtocol)
	if err != nil {
		return TurnCredentialBundle{}, turnCredentialConnectError(err)
	}
	streamOK := false
	defer finishStream(stream, &streamOK)
	// A fresh relative stream deadline would extend the dial/request budget.
	// Context cancellation also needs to interrupt a blocked libp2p read.
	deadline, _ := ctx.Deadline()
	if err := stream.SetDeadline(deadline); err != nil {
		return TurnCredentialBundle{}, ErrTurnCredentialsUnavailable
	}
	stopReset := context.AfterFunc(ctx, func() { _ = stream.Reset() })
	defer stopReset()

	requestBytes, err := json.Marshal(inboxRequest{Action: turnCredentialsV1Action})
	requestBytes = diagnosticWrapRequest(requestBytes, diagnosticContext(diagnostics))
	if err != nil || ctx.Err() != nil {
		return TurnCredentialBundle{}, ErrTurnCredentialsUnavailable
	}
	if err := writeFrame(stream, requestBytes); err != nil {
		return TurnCredentialBundle{}, ErrTurnCredentialsUnavailable
	}
	responseBytes, err := readFrame(stream)
	if ctx.Err() != nil {
		return TurnCredentialBundle{}, ErrTurnCredentialsUnavailable
	}
	if err != nil {
		var timeout net.Error
		if errors.As(err, &timeout) && timeout.Timeout() {
			return TurnCredentialBundle{}, ErrTurnCredentialsUnavailable
		}
		// Includes invalid frame lengths and truncated responses. Do not turn
		// an unvalidated response into permission to attempt direct media.
		return TurnCredentialBundle{}, ErrTurnCredentialsInvalidResponse
	}
	streamOK = true
	if diagnosticContext(diagnostics) != nil && diagnosticUnsupported(responseBytes) {
		return TurnCredentialBundle{}, errTurnDiagnosticUnsupported
	}
	return parseTurnCredentialsV1Response(responseBytes, now)
}

// Before an authenticated stream exists, an arbitrary transport error may be
// a peer identity or security negotiation rejection. Only a proven deadline
// permits transient treatment; do not expose the underlying address/error.
func turnCredentialConnectError(err error) error {
	// Unwrap only a single causal chain. A joined dial failure can contain both
	// a deadline and a trust rejection, and must remain conservative. Context
	// expiry alone must never relabel a separately reported authentication error.
	for cause := err; cause != nil; cause = errors.Unwrap(cause) {
		if cause == context.DeadlineExceeded {
			return ErrTurnCredentialsUnavailable
		}
	}
	return ErrTurnCredentialsRejected
}

func parseTurnCredentialsV1Response(raw []byte, now time.Time) (TurnCredentialBundle, error) {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	var response turnCredentialsWireResponse
	if err := decoder.Decode(&response); err != nil {
		return TurnCredentialBundle{}, ErrTurnCredentialsInvalidResponse
	}
	if err := ensureTurnCredentialsJSONEOF(decoder); err != nil {
		return TurnCredentialBundle{}, ErrTurnCredentialsInvalidResponse
	}

	if response.Status == "ERROR" {
		if response.Error == "Unknown action: "+turnCredentialsV1Action &&
			response.ErrorCode == "" && response.RetryAfterMs == 0 {
			return TurnCredentialBundle{}, ErrTurnCredentialsUnsupported
		}
		if !isSafeTurnCredentialErrorCode(response.ErrorCode) || response.Error != "" ||
			response.RetryAfterMs < 0 ||
			time.Duration(response.RetryAfterMs)*time.Millisecond > turnCredentialsMaxRetryAfter {
			return TurnCredentialBundle{}, ErrTurnCredentialsInvalidResponse
		}
		return TurnCredentialBundle{}, &TurnCredentialsRelayError{
			Code:       response.ErrorCode,
			RetryAfter: time.Duration(response.RetryAfterMs) * time.Millisecond,
		}
	}
	if response.Status != "OK" || response.Error != "" || response.ErrorCode != "" ||
		response.RetryAfterMs != 0 {
		return TurnCredentialBundle{}, ErrTurnCredentialsInvalidResponse
	}

	bundle := TurnCredentialBundle{
		Schema:       response.Schema,
		Version:      response.Version,
		URLs:         append([]string(nil), response.URLs...),
		Username:     response.Username,
		Password:     response.Password,
		TTLSeconds:   response.TTLSeconds,
		ExpiresAtMs:  response.ExpiresAtMs,
		ServerTimeMs: response.ServerTimeMs,
	}
	if err := validateTurnCredentialBundle(bundle, now); err != nil {
		return TurnCredentialBundle{}, ErrTurnCredentialsInvalidResponse
	}
	return bundle, nil
}

func ensureTurnCredentialsJSONEOF(decoder *json.Decoder) error {
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return ErrTurnCredentialsInvalidResponse
	}
	return nil
}

func validateTurnCredentialBundle(bundle TurnCredentialBundle, now time.Time) error {
	if bundle.Schema != turnCredentialsSchema || bundle.Version != turnCredentialsVersion ||
		bundle.TTLSeconds <= 0 || time.Duration(bundle.TTLSeconds)*time.Second > turnCredentialsMaxTTL ||
		bundle.ServerTimeMs <= 0 || bundle.ExpiresAtMs <= bundle.ServerTimeMs ||
		bundle.ExpiresAtMs-bundle.ServerTimeMs != bundle.TTLSeconds*1000 ||
		bundle.ExpiresAtMs <= now.UnixMilli() ||
		absDuration(now.Sub(time.UnixMilli(bundle.ServerTimeMs))) > turnCredentialsMaxClockSkew ||
		!isValidTurnCredentialText(bundle.Username) || !isValidTurnCredentialText(bundle.Password) ||
		len(bundle.URLs) == 0 || len(bundle.URLs) > turnCredentialsMaxURLs {
		return ErrTurnCredentialsInvalidResponse
	}
	for _, url := range bundle.URLs {
		if !isValidTurnCredentialURL(url) {
			return ErrTurnCredentialsInvalidResponse
		}
	}
	return nil
}

func isValidTurnCredentialText(value string) bool {
	return value != "" && len(value) <= turnCredentialsMaxFieldBytes && utf8.ValidString(value) &&
		strings.TrimSpace(value) == value && !strings.ContainsAny(value, "\r\n\x00")
}

func isValidTurnCredentialURL(value string) bool {
	if value == "" || len(value) > turnCredentialsMaxFieldBytes || !utf8.ValidString(value) ||
		strings.TrimSpace(value) != value || strings.ContainsAny(value, "\r\n\x00@%") {
		return false
	}
	parsed, err := url.Parse(value)
	if err != nil || parsed.Opaque == "" || parsed.Host != "" || parsed.User != nil || parsed.Fragment != "" {
		return false
	}
	switch parsed.Scheme {
	case "turn", "turns", "stun", "stuns":
	default:
		return false
	}
	if !isValidTurnCredentialAuthority(parsed.Opaque) {
		return false
	}
	if parsed.RawQuery == "" {
		return true
	}
	query, err := url.ParseQuery(parsed.RawQuery)
	if err != nil || len(query) != 1 {
		return false
	}
	transports, ok := query["transport"]
	return ok && len(transports) == 1 && (transports[0] == "udp" || transports[0] == "tcp")
}

func isValidTurnCredentialAuthority(authority string) bool {
	if authority == "" || strings.ContainsAny(authority, "/?#") {
		return false
	}
	host := authority
	port := ""
	if strings.HasPrefix(authority, "[") {
		closing := strings.IndexByte(authority, ']')
		if closing <= 1 || net.ParseIP(authority[1:closing]) == nil {
			return false
		}
		host = authority[1:closing]
		rest := authority[closing+1:]
		if rest != "" {
			if !strings.HasPrefix(rest, ":") || len(rest) == 1 {
				return false
			}
			port = rest[1:]
		}
	} else {
		if strings.Count(authority, ":") > 1 {
			return false
		}
		if index := strings.LastIndexByte(authority, ':'); index >= 0 {
			host = authority[:index]
			port = authority[index+1:]
		}
		if !isValidTurnCredentialHostname(host) {
			return false
		}
	}
	if host == "" {
		return false
	}
	if port == "" {
		return true
	}
	numericPort, err := strconv.Atoi(port)
	return err == nil && numericPort > 0 && numericPort <= 65535
}

func isValidTurnCredentialHostname(hostname string) bool {
	if net.ParseIP(hostname) != nil {
		return true
	}
	if hostname == "" || len(hostname) > 253 || strings.HasPrefix(hostname, ".") || strings.HasSuffix(hostname, ".") {
		return false
	}
	for _, label := range strings.Split(hostname, ".") {
		if label == "" || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
			return false
		}
		for _, r := range label {
			if (r < 'a' || r > 'z') && (r < 'A' || r > 'Z') && (r < '0' || r > '9') && r != '-' {
				return false
			}
		}
	}
	return true
}

func isSafeTurnCredentialErrorCode(code string) bool {
	if code == "" || len(code) > 64 {
		return false
	}
	for _, r := range code {
		if (r < 'A' || r > 'Z') && (r < '0' || r > '9') && r != '_' {
			return false
		}
	}
	return true
}

func preferTurnCredentialError(previous, candidate error) error {
	if candidate == nil {
		return previous
	}
	if previous == nil {
		return candidate
	}
	// Do not let a later outage erase a received malformed/authentication error.
	if turnCredentialFailureIsFatal(previous) {
		return previous
	}
	if turnCredentialFailureIsFatal(candidate) {
		return candidate
	}
	var previousRelay, candidateRelay *TurnCredentialsRelayError
	if errors.As(candidate, &candidateRelay) {
		return candidate
	}
	if errors.As(previous, &previousRelay) {
		return previous
	}
	if errors.Is(candidate, ErrTurnCredentialsInvalidResponse) {
		return candidate
	}
	if errors.Is(previous, ErrTurnCredentialsInvalidResponse) {
		return previous
	}
	if errors.Is(candidate, ErrTurnCredentialsUnsupported) {
		return candidate
	}
	return previous
}

func turnCredentialFailureIsFatal(err error) bool {
	var relayErr *TurnCredentialsRelayError
	if errors.As(err, &relayErr) {
		return !relayErr.Transient()
	}
	return !errors.Is(err, ErrTurnCredentialsUnavailable) && !errors.Is(err, ErrTurnCredentialsUnsupported)
}

func absDuration(value time.Duration) time.Duration {
	if value < 0 {
		return -value
	}
	return value
}

// TurnCredentialLeaseUse names only the credential-consuming operation. It is
// deliberately not call state or signaling state.
type TurnCredentialLeaseUse string

const (
	TurnCredentialUseNewAllocation TurnCredentialLeaseUse = "new_allocation"
	TurnCredentialUseRestart       TurnCredentialLeaseUse = "restart"
)

type TurnCredentialLeaseConfig struct {
	Now            func() time.Time
	Fetch          func(context.Context) (TurnCredentialBundle, error)
	Wait           func(context.Context, time.Duration) error
	Release        func(TurnCredentialBundle)
	MaxAttempts    int
	RetryInterval  time.Duration
	RequiredWindow time.Duration
}

type TurnCredentialRefreshOutcome struct {
	Attempted             bool
	StagedReplacement     bool
	KeepHealthyAllocation bool
}

type TurnCredentialLeaseManager struct {
	mu      sync.Mutex
	config  TurnCredentialLeaseConfig
	staged  TurnCredentialBundle
	hasData bool
	closed  bool
}

// Close releases and clears the staged bundle. It is safe to call repeatedly;
// the injected release hook observes each staged bundle at most once.
func (manager *TurnCredentialLeaseManager) Close() {
	manager.mu.Lock()
	if manager.closed {
		manager.mu.Unlock()
		return
	}
	manager.closed = true
	old := manager.staged
	hadData := manager.hasData
	manager.staged = TurnCredentialBundle{}
	manager.hasData = false
	manager.mu.Unlock()
	if hadData {
		manager.config.Release(old)
	}
}

func NewTurnCredentialLeaseManager(config TurnCredentialLeaseConfig) *TurnCredentialLeaseManager {
	if config.Now == nil {
		config.Now = time.Now
	}
	if config.Wait == nil {
		config.Wait = waitForTurnCredentialRetry
	}
	if config.Release == nil {
		config.Release = func(TurnCredentialBundle) {}
	}
	if config.MaxAttempts <= 0 {
		config.MaxAttempts = 4
	}
	if config.RetryInterval <= 0 {
		config.RetryInterval = 5 * time.Second
	}
	if config.RequiredWindow <= 0 {
		config.RequiredWindow = 15 * time.Second
	}
	return &TurnCredentialLeaseManager{config: config}
}

func (manager *TurnCredentialLeaseManager) Stage(ctx context.Context) error {
	if manager.isClosed() {
		return ErrTurnCredentialsUnavailable
	}
	bundle, err := manager.fetchValid(ctx)
	if err != nil {
		return err
	}
	if !manager.replace(bundle) {
		return ErrTurnCredentialsUnavailable
	}
	return nil
}

// NextPrefetchAt is two-thirds through the server-advertised lifetime, which
// is strictly before the frozen 70% ceiling.
func (manager *TurnCredentialLeaseManager) NextPrefetchAt() time.Time {
	manager.mu.Lock()
	defer manager.mu.Unlock()
	if manager.closed || !manager.hasData {
		return time.Time{}
	}
	lifetimeMs := manager.staged.ExpiresAtMs - manager.staged.ServerTimeMs
	return time.UnixMilli(manager.staged.ServerTimeMs + lifetimeMs*2/3)
}

func (manager *TurnCredentialLeaseManager) RefreshStaged(ctx context.Context) (TurnCredentialRefreshOutcome, error) {
	outcome := TurnCredentialRefreshOutcome{KeepHealthyAllocation: true}
	if manager.isClosed() {
		return outcome, ErrTurnCredentialsUnavailable
	}
	prefetchAt := manager.NextPrefetchAt()
	if !prefetchAt.IsZero() && manager.config.Now().Before(prefetchAt) {
		return outcome, nil
	}
	outcome.Attempted = true
	bundle, err := manager.fetchValid(ctx)
	if err != nil {
		return outcome, err
	}
	if !manager.replace(bundle) {
		return outcome, ErrTurnCredentialsUnavailable
	}
	outcome.StagedReplacement = true
	return outcome, nil
}

func (manager *TurnCredentialLeaseManager) RequireValid(
	ctx context.Context,
	use TurnCredentialLeaseUse,
) (TurnCredentialBundle, error) {
	if manager.isClosed() {
		return TurnCredentialBundle{}, &turnCredentialsRequiredError{}
	}
	if use != TurnCredentialUseNewAllocation && use != TurnCredentialUseRestart {
		return TurnCredentialBundle{}, &turnCredentialsRequiredError{}
	}
	if bundle, ok := manager.validStaged(); ok {
		return bundle, nil
	}

	deadline := manager.config.Now().Add(manager.config.RequiredWindow)
	for attempt := 0; attempt < manager.config.MaxAttempts; attempt++ {
		bundle, err := manager.fetchValid(ctx)
		if err == nil {
			if manager.replace(bundle) {
				return bundle, nil
			}
			return TurnCredentialBundle{}, &turnCredentialsRequiredError{}
		}
		if attempt+1 >= manager.config.MaxAttempts {
			break
		}
		now := manager.config.Now()
		delay := manager.config.RetryInterval
		if remaining := deadline.Sub(now); remaining < delay {
			delay = remaining
		}
		if delay <= 0 || manager.config.Wait(ctx, delay) != nil {
			break
		}
	}
	if remaining := deadline.Sub(manager.config.Now()); remaining > 0 {
		_ = manager.config.Wait(ctx, remaining)
	}
	return TurnCredentialBundle{}, &turnCredentialsRequiredError{}
}

func (manager *TurnCredentialLeaseManager) fetchValid(ctx context.Context) (TurnCredentialBundle, error) {
	if manager.config.Fetch == nil {
		return TurnCredentialBundle{}, ErrTurnCredentialsUnavailable
	}
	bundle, err := manager.config.Fetch(ctx)
	if err != nil {
		return TurnCredentialBundle{}, ErrTurnCredentialsUnavailable
	}
	if err := validateTurnCredentialBundle(bundle, manager.config.Now()); err != nil {
		return TurnCredentialBundle{}, ErrTurnCredentialsInvalidResponse
	}
	return bundle, nil
}

func (manager *TurnCredentialLeaseManager) validStaged() (TurnCredentialBundle, bool) {
	manager.mu.Lock()
	defer manager.mu.Unlock()
	if manager.closed || !manager.hasData || validateTurnCredentialBundle(manager.staged, manager.config.Now()) != nil {
		return TurnCredentialBundle{}, false
	}
	return cloneTurnCredentialBundle(manager.staged), true
}

func (manager *TurnCredentialLeaseManager) replace(bundle TurnCredentialBundle) bool {
	manager.mu.Lock()
	if manager.closed {
		manager.mu.Unlock()
		manager.config.Release(bundle)
		return false
	}
	old := manager.staged
	hadOld := manager.hasData
	manager.staged = cloneTurnCredentialBundle(bundle)
	manager.hasData = true
	manager.mu.Unlock()
	if hadOld {
		manager.config.Release(old)
	}
	return true
}

func (manager *TurnCredentialLeaseManager) isClosed() bool {
	manager.mu.Lock()
	defer manager.mu.Unlock()
	return manager.closed
}

func cloneTurnCredentialBundle(bundle TurnCredentialBundle) TurnCredentialBundle {
	bundle.URLs = append([]string(nil), bundle.URLs...)
	return bundle
}

type turnCredentialsRequiredError struct{}

func (*turnCredentialsRequiredError) Error() string               { return ErrTurnCredentialsRequired.Error() }
func (*turnCredentialsRequiredError) Unwrap() error               { return ErrTurnCredentialsRequired }
func (*turnCredentialsRequiredError) DirectFallbackAllowed() bool { return false }

func waitForTurnCredentialRetry(ctx context.Context, delay time.Duration) error {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

// TurnCredentialsWithDiagnosticsV1 preserves the same overall deadline and credential response.
func (n *Node) TurnCredentialsWithDiagnosticsV1(d *CallDiagnosticContext) (TurnCredentialBundle, error) {
	return n.turnCredentialsV1At(time.Now, d)
}

var errTurnDiagnosticUnsupported = errors.New("diagnostic wrapper unsupported")
