package node

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	libp2p "github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
)

const (
	turnTestUsername = "1700000600:fixture-subject"
	turnTestPassword = "fixture-password-never-log"
)

func TestTurnCredentialsV1_ExactActionDecodeAndNoClaimedIdentity(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Millisecond)
	relay, requests := startTurnCredentialsRelayFixture(t, validTurnCredentialsResponse(now, "first"))
	n := turnCredentialsNode(t, relay)

	got, err := n.TurnCredentialsV1()
	if err != nil {
		t.Fatal("TurnCredentialsV1 returned an error")
	}

	select {
	case raw := <-requests:
		if raw != `{"action":"turn_credentials_v1"}` {
			t.Fatal("TURN credential request was not the exact action-only grammar")
		}
		var request map[string]any
		if json.Unmarshal([]byte(raw), &request) != nil {
			t.Fatal("TURN credential request was not valid JSON")
		}
		for _, forbidden := range []string{"peerId", "peerID", "from", "to", "username", "address"} {
			if _, claimed := request[forbidden]; claimed {
				t.Fatal("TURN credential request claimed client identity or credential material")
			}
		}
	case <-time.After(2 * time.Second):
		t.Fatal("TURN credential relay did not receive a request")
	}

	if got.Schema != "turn_credentials" || got.Version != 1 ||
		got.Username != turnTestUsername || got.Password != turnTestPassword ||
		got.TTLSeconds != 600 || got.ServerTimeMs != now.UnixMilli() ||
		got.ExpiresAtMs != now.Add(10*time.Minute).UnixMilli() {
		t.Fatal("TURN credential response fields were not decoded exactly")
	}
	wantURLs := []string{
		"turn:relay.invalid:3478?transport=udp",
		"turn:relay.invalid:3478?transport=tcp",
		"turns:relay.invalid:443?transport=tcp",
	}
	if len(got.URLs) != len(wantURLs) {
		t.Fatal("TURN credential URL count changed")
	}
	for i := range wantURLs {
		if got.URLs[i] != wantURLs[i] {
			t.Fatal("TURN credential URL order changed")
		}
	}
}

func TestTurnCredentialsV1_RejectsInvalidExpiredAndClockSkewedResponsesWithoutEcho(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Millisecond)
	tests := map[string]string{
		"malformed schema": fmt.Sprintf(`{"status":"OK","schema":"wrong","version":1,"urls":["turn:relay.invalid:3478?transport=udp"],"username":%q,"password":%q,"ttlSeconds":600,"expiresAtMs":%d,"serverTimeMs":%d}`,
			turnTestUsername, turnTestPassword, now.Add(10*time.Minute).UnixMilli(), now.UnixMilli()),
		"expired": fmt.Sprintf(`{"status":"OK","schema":"turn_credentials","version":1,"urls":["turn:relay.invalid:3478?transport=udp"],"username":%q,"password":%q,"ttlSeconds":600,"expiresAtMs":%d,"serverTimeMs":%d}`,
			turnTestUsername, turnTestPassword, now.Add(-time.Second).UnixMilli(), now.Add(-10*time.Minute).UnixMilli()),
		"clock skew": fmt.Sprintf(`{"status":"OK","schema":"turn_credentials","version":1,"urls":["turn:relay.invalid:3478?transport=udp"],"username":%q,"password":%q,"ttlSeconds":600,"expiresAtMs":%d,"serverTimeMs":%d}`,
			turnTestUsername, turnTestPassword, now.Add(2*time.Hour).UnixMilli(), now.Add(time.Hour).UnixMilli()),
		"unknown field": fmt.Sprintf(`{"status":"OK","schema":"turn_credentials","version":1,"urls":["turn:relay.invalid:3478?transport=udp"],"username":%q,"password":%q,"ttlSeconds":600,"expiresAtMs":%d,"serverTimeMs":%d,"staticPassword":"forbidden-static-fixture"}`,
			turnTestUsername, turnTestPassword, now.Add(10*time.Minute).UnixMilli(), now.UnixMilli()),
		"embedded URL userinfo": fmt.Sprintf(`{"status":"OK","schema":"turn_credentials","version":1,"urls":["turn:fixture-user@relay.invalid:3478?transport=udp"],"username":%q,"password":%q,"ttlSeconds":600,"expiresAtMs":%d,"serverTimeMs":%d}`,
			turnTestUsername, turnTestPassword, now.Add(10*time.Minute).UnixMilli(), now.UnixMilli()),
		"malformed URL authority": fmt.Sprintf(`{"status":"OK","schema":"turn_credentials","version":1,"urls":["turn::3478?transport=udp"],"username":%q,"password":%q,"ttlSeconds":600,"expiresAtMs":%d,"serverTimeMs":%d}`,
			turnTestUsername, turnTestPassword, now.Add(10*time.Minute).UnixMilli(), now.UnixMilli()),
	}

	for name, response := range tests {
		t.Run(name, func(t *testing.T) {
			relay, _ := startTurnCredentialsRelayFixture(t, response)
			n := turnCredentialsNode(t, relay)
			bundle, err := n.TurnCredentialsV1()
			if !errors.Is(err, ErrTurnCredentialsInvalidResponse) {
				t.Fatal("invalid TURN response did not return the typed validation error")
			}
			if bundle.Schema != "" || bundle.Version != 0 || len(bundle.URLs) != 0 ||
				bundle.Username != "" || bundle.Password != "" || bundle.TTLSeconds != 0 ||
				bundle.ExpiresAtMs != 0 || bundle.ServerTimeMs != 0 {
				t.Fatal("invalid TURN response returned credential material")
			}
			message := err.Error()
			for _, forbidden := range []string{
				turnTestUsername,
				turnTestPassword,
				"forbidden-static-fixture",
				response,
				relay.ID().String(),
				relay.Addrs()[0].String(),
			} {
				if strings.Contains(message, forbidden) {
					t.Fatal("TURN validation error echoed sensitive or identifying input")
				}
			}
		})
	}
}

func TestTurnCredentialsV1_TypedUnsupportedFiniteFailureAndRelayFailover(t *testing.T) {
	t.Run("old relay is typed unsupported", func(t *testing.T) {
		relay, _ := startTurnCredentialsRelayFixture(t, `{"status":"ERROR","error":"Unknown action: turn_credentials_v1"}`)
		n := turnCredentialsNode(t, relay)
		if _, err := n.TurnCredentialsV1(); !errors.Is(err, ErrTurnCredentialsUnsupported) {
			t.Fatal("old relay response was not classified as unsupported")
		}
	})

	t.Run("finite relay failure is typed and bounded", func(t *testing.T) {
		relay, _ := startTurnCredentialsRelayFixture(t, `{"status":"ERROR","errorCode":"RATE_LIMITED","retryAfterMs":2500}`)
		n := turnCredentialsNode(t, relay)
		_, err := n.TurnCredentialsV1()
		var relayErr *TurnCredentialsRelayError
		if !errors.As(err, &relayErr) || relayErr.Code != "RATE_LIMITED" || relayErr.RetryAfter != 2500*time.Millisecond {
			t.Fatal("finite relay response was not preserved as a typed bounded failure")
		}
		if strings.Contains(err.Error(), turnTestUsername) || strings.Contains(err.Error(), turnTestPassword) {
			t.Fatal("finite relay error exposed credential material")
		}
	})

	t.Run("later relay wins without static fallback", func(t *testing.T) {
		oldRelay, oldRequests := startTurnCredentialsRelayFixture(t, `{"status":"ERROR","error":"Unknown action: turn_credentials_v1"}`)
		now := time.Now().UTC().Truncate(time.Millisecond)
		currentRelay, currentRequests := startTurnCredentialsRelayFixture(t, validTurnCredentialsResponse(now, "second"))
		n := turnCredentialsNode(t, oldRelay, currentRelay)

		got, err := n.TurnCredentialsV1()
		if err != nil || got.Schema != "turn_credentials" || got.Version != 1 {
			t.Fatal("client did not fail over to the later authenticated relay")
		}
		for name, requests := range map[string]<-chan string{"old": oldRequests, "current": currentRequests} {
			select {
			case raw := <-requests:
				if raw != `{"action":"turn_credentials_v1"}` {
					t.Fatalf("%s relay did not receive the action-only request", name)
				}
			case <-time.After(2 * time.Second):
				t.Fatalf("%s relay was not attempted", name)
			}
		}
	})
}

func TestTurnCredentialsV1_StalledFirstRelayLeavesTimeForHealthyFallback(t *testing.T) {
	slowRelay, slowRequests, slowClosed := startStalledTurnCredentialsRelayFixture(t)
	now := time.Now().UTC().Truncate(time.Millisecond)
	healthyRelay, healthyRequests := startTurnCredentialsRelayFixture(t, validTurnCredentialsResponse(now, "fallback"))
	n := turnCredentialsNode(t, slowRelay, healthyRelay)
	result := make(chan turnCredentialFetchResult, 1)
	go func() {
		bundle, err := n.TurnCredentialsV1()
		result <- turnCredentialFetchResult{bundle: bundle, err: err}
	}()

	select {
	case <-slowRequests:
	case <-time.After(2 * time.Second):
		t.Fatal("first relay did not receive the credential request")
	}
	// Flutter abandons this native request after five seconds. The first
	// unresponsive peer must leave time for a later authenticated response.
	select {
	case got := <-result:
		if got.err != nil || got.bundle.Schema != "turn_credentials" {
			t.Fatal("healthy fallback did not supply credentials")
		}
	case <-time.After(4500 * time.Millisecond):
		t.Fatal("stalled first relay exhausted the Flutter credential deadline before fallback")
	}
	select {
	case <-healthyRequests:
	default:
		t.Fatal("healthy fallback was not attempted")
	}
	select {
	case <-slowClosed:
	case <-time.After(time.Second):
		t.Fatal("abandoned first-relay stream remained open after fallback")
	}
}

func TestTurnCredentialsV1_CanceledRequestInterruptsBlockedResponse(t *testing.T) {
	relay, requests, closed := startStalledTurnCredentialsRelayFixture(t)
	n := turnCredentialsNode(t, relay)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	result := make(chan turnCredentialFetchResult, 1)
	go func() {
		bundle, err := requestTurnCredentialsV1(ctx, n.host, RelayInfo{
			ID: relay.ID(), Addrs: relay.Addrs(),
		}, time.Now())
		result <- turnCredentialFetchResult{bundle: bundle, err: err}
	}()
	select {
	case <-requests:
	case <-time.After(2 * time.Second):
		t.Fatal("relay did not receive the credential request")
	}
	cancel()
	select {
	case got := <-result:
		if !errors.Is(got.err, ErrTurnCredentialsUnavailable) || got.bundle.Username != "" {
			t.Fatal("canceled request returned credentials or an unexpected failure")
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("cancellation did not interrupt the blocked credential response")
	}
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("canceled credential stream was not released")
	}
}

func TestTurnCredentialsV1_AllStalledRelaysFinishInsideBridgeDeadline(t *testing.T) {
	first, firstRequests, firstClosed := startStalledTurnCredentialsRelayFixture(t)
	second, secondRequests, secondClosed := startStalledTurnCredentialsRelayFixture(t)
	n := turnCredentialsNode(t, first, second)
	result := make(chan turnCredentialFetchResult, 1)
	go func() {
		bundle, err := n.TurnCredentialsV1()
		result <- turnCredentialFetchResult{bundle: bundle, err: err}
	}()
	select {
	case got := <-result:
		if !errors.Is(got.err, ErrTurnCredentialsUnavailable) || got.bundle.Username != "" {
			t.Fatal("stalled relays returned credentials or an unexpected failure")
		}
	case <-time.After(4500 * time.Millisecond):
		t.Fatal("per-relay timeouts exceeded the shared native credential budget")
	}
	for _, requests := range []<-chan struct{}{firstRequests, secondRequests} {
		select {
		case <-requests:
		default:
			t.Fatal("a stalled relay starved a later configured peer")
		}
	}
	for _, closed := range []<-chan struct{}{firstClosed, secondClosed} {
		select {
		case <-closed:
		case <-time.After(time.Second):
			t.Fatal("credential deadline left an abandoned stream open")
		}
	}
}

func TestTurnCredentialLeaseManager_PrefetchReplacementAndHealthyAllocationSurvival(t *testing.T) {
	clock := &turnCredentialTestClock{now: time.Unix(1_800_000_000, 0)}
	first := turnCredentialLeaseFixture(clock.now, "first")
	second := turnCredentialLeaseFixture(clock.now.Add(6*time.Minute), "second")
	fetches := []turnCredentialFetchResult{{bundle: first}, {bundle: second}, {err: errors.New("mint unavailable")}}
	var released int
	manager := NewTurnCredentialLeaseManager(TurnCredentialLeaseConfig{
		Now: func() time.Time { return clock.now },
		Fetch: func(context.Context) (TurnCredentialBundle, error) {
			result := fetches[0]
			fetches = fetches[1:]
			return result.bundle, result.err
		},
		Wait: func(_ context.Context, delay time.Duration) error {
			clock.now = clock.now.Add(delay)
			return nil
		},
		Release:        func(TurnCredentialBundle) { released++ },
		MaxAttempts:    4,
		RetryInterval:  5 * time.Second,
		RequiredWindow: 15 * time.Second,
	})

	if err := manager.Stage(context.Background()); err != nil {
		t.Fatal("initial credential staging failed")
	}
	prefetchAt := manager.NextPrefetchAt()
	lifetime := time.Duration(first.ExpiresAtMs-first.ServerTimeMs) * time.Millisecond
	if !prefetchAt.Before(time.UnixMilli(first.ServerTimeMs).Add(lifetime * 7 / 10)) {
		t.Fatal("credential prefetch was not scheduled strictly before 70 percent of lifetime")
	}

	clock.now = prefetchAt.Add(-time.Millisecond)
	if outcome, err := manager.RefreshStaged(context.Background()); err != nil || outcome.Attempted {
		t.Fatal("credential replacement was attempted before its scheduled prefetch point")
	}
	clock.now = prefetchAt
	if outcome, err := manager.RefreshStaged(context.Background()); err != nil || !outcome.Attempted || !outcome.StagedReplacement {
		t.Fatal("credential replacement was not staged at the prefetch point")
	}
	if released != 1 {
		t.Fatal("superseded credential bundle was not released exactly once")
	}

	clock.now = time.UnixMilli(second.ExpiresAtMs).Add(time.Second)
	outcome, err := manager.RefreshStaged(context.Background())
	if err == nil || !outcome.KeepHealthyAllocation {
		t.Fatal("mint outage or credential expiry was treated as healthy allocation duration")
	}
}

func TestTurnCredentialLeaseManager_NewAllocationAndRestartFailClosedAfterBudget(t *testing.T) {
	for _, use := range []TurnCredentialLeaseUse{TurnCredentialUseNewAllocation, TurnCredentialUseRestart} {
		t.Run(string(use), func(t *testing.T) {
			clock := &turnCredentialTestClock{now: time.Unix(1_800_000_000, 0)}
			attempts := 0
			manager := NewTurnCredentialLeaseManager(TurnCredentialLeaseConfig{
				Now: func() time.Time { return clock.now },
				Fetch: func(context.Context) (TurnCredentialBundle, error) {
					attempts++
					return TurnCredentialBundle{}, errors.New("mint unavailable")
				},
				Wait: func(_ context.Context, delay time.Duration) error {
					clock.now = clock.now.Add(delay)
					return nil
				},
				Release:        func(TurnCredentialBundle) {},
				MaxAttempts:    4,
				RetryInterval:  5 * time.Second,
				RequiredWindow: 15 * time.Second,
			})

			started := clock.now
			bundle, err := manager.RequireValid(context.Background(), use)
			if bundle.Schema != "" || len(bundle.URLs) != 0 || bundle.Username != "" ||
				bundle.Password != "" || !errors.Is(err, ErrTurnCredentialsRequired) {
				t.Fatal("required allocation did not fail closed without credentials")
			}
			if elapsed := clock.now.Sub(started); elapsed != 15*time.Second {
				t.Fatal("required allocation did not exhaust the exact fifteen-second window")
			}
			if attempts != 4 {
				t.Fatal("required allocation mint attempts were not bounded")
			}
			fallbackPolicy, ok := err.(interface{ DirectFallbackAllowed() bool })
			if !ok || fallbackPolicy.DirectFallbackAllowed() {
				t.Fatal("relay-only credential failure permitted a direct/static downgrade")
			}
		})
	}
}

func TestTurnCredentialLeaseManager_CloseIsIdempotentAndReleasesOnce(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	released := 0
	fetched := 0
	manager := NewTurnCredentialLeaseManager(TurnCredentialLeaseConfig{
		Now: func() time.Time { return now },
		Fetch: func(context.Context) (TurnCredentialBundle, error) {
			fetched++
			return turnCredentialLeaseFixture(now, "close"), nil
		},
		Release: func(TurnCredentialBundle) { released++ },
	})
	if err := manager.Stage(context.Background()); err != nil {
		t.Fatal("credential staging failed before close")
	}

	manager.Close()
	manager.Close()
	if released != 1 {
		t.Fatal("idempotent close did not release the staged bundle exactly once")
	}
	if !manager.NextPrefetchAt().IsZero() {
		t.Fatal("closed credential manager retained staged lease state")
	}
	if _, err := manager.RefreshStaged(context.Background()); err == nil || fetched != 1 {
		t.Fatal("closed credential manager fetched or restaged credential material")
	}
}

type turnCredentialFetchResult struct {
	bundle TurnCredentialBundle
	err    error
}

type turnCredentialTestClock struct{ now time.Time }

func turnCredentialLeaseFixture(serverTime time.Time, suffix string) TurnCredentialBundle {
	return TurnCredentialBundle{
		Schema:       "turn_credentials",
		Version:      1,
		URLs:         []string{"turn:relay.invalid:3478?transport=udp"},
		Username:     "fixture-user-" + suffix,
		Password:     "fixture-pass-" + suffix,
		TTLSeconds:   600,
		ExpiresAtMs:  serverTime.Add(10 * time.Minute).UnixMilli(),
		ServerTimeMs: serverTime.UnixMilli(),
	}
}

func validTurnCredentialsResponse(now time.Time, suffix string) string {
	return fmt.Sprintf(`{"status":"OK","schema":"turn_credentials","version":1,"urls":["turn:relay.invalid:3478?transport=udp","turn:relay.invalid:3478?transport=tcp","turns:relay.invalid:443?transport=tcp"],"username":%q,"password":%q,"ttlSeconds":600,"expiresAtMs":%d,"serverTimeMs":%d}`,
		turnTestUsername, turnTestPassword, now.Add(10*time.Minute).UnixMilli(), now.UnixMilli())
}

func startTurnCredentialsRelayFixture(t *testing.T, response string) (host.Host, <-chan string) {
	t.Helper()
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatal("failed to start synthetic relay fixture")
	}
	t.Cleanup(func() { _ = relayHost.Close() })

	requests := make(chan string, 2)
	relayHost.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
		defer stream.Close()
		raw, readErr := readFrame(stream)
		if readErr != nil {
			return
		}
		requests <- string(raw)
		_ = writeFrame(stream, []byte(response))
	})
	return relayHost, requests
}

func startStalledTurnCredentialsRelayFixture(t *testing.T) (host.Host, <-chan struct{}, <-chan struct{}) {
	t.Helper()
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatal("failed to start stalled relay fixture")
	}
	t.Cleanup(func() { _ = relayHost.Close() })
	requests := make(chan struct{}, 1)
	closed := make(chan struct{}, 1)
	relayHost.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
		defer stream.Close()
		if _, err := readFrame(stream); err != nil {
			return
		}
		requests <- struct{}{}
		// No response is issued. The client's deadline/cancellation must reset
		// the stream and unblock this read without shutting down either host.
		_, _ = readFrame(stream)
		closed <- struct{}{}
	})
	return relayHost, requests, closed
}

func turnCredentialsNode(t *testing.T, relays ...host.Host) *Node {
	t.Helper()
	n := startLocalNodeForMultiRelayTest(t)
	addresses := make([]string, 0, len(relays))
	for _, relay := range relays {
		addresses = append(addresses, relay.Addrs()[0].String()+"/p2p/"+relay.ID().String())
	}
	n.mu.Lock()
	n.relayAddresses = addresses
	n.mu.Unlock()
	return n
}

func TestTurnCredentialsV1_FatalFailureSurvivesLaterOutage(t *testing.T) {
	for _, fatal := range []error{
		ErrTurnCredentialsInvalidResponse,
		ErrTurnCredentialsRejected,
		&TurnCredentialsRelayError{Code: "TURN_CREDENTIALS_UNAUTHORIZED"},
		&TurnCredentialsRelayError{Code: "TURN_CREDENTIALS_INVALID_REQUEST"},
		&TurnCredentialsRelayError{Code: "UNKNOWN_TRUST_FAILURE"},
	} {
		for _, transient := range []error{ErrTurnCredentialsUnavailable, &TurnCredentialsRelayError{Code: "TURN_CREDENTIALS_RATE_LIMITED"}} {
			if preferTurnCredentialError(fatal, transient) != fatal || preferTurnCredentialError(transient, fatal) != fatal {
				t.Fatal("transient failure erased a fatal credential failure")
			}
		}
	}
}

func TestTurnCredentialsV1_ConnectFailureClassification(t *testing.T) {
	if turnCredentialConnectError(errors.New("private peer identity mismatch")) != ErrTurnCredentialsRejected {
		t.Fatal("unclassified connection rejection permitted transient fallback")
	}
	ctx, cancel := context.WithDeadline(context.Background(), time.Time{})
	defer cancel()
	if turnCredentialConnectError(ctx.Err()) != ErrTurnCredentialsUnavailable {
		t.Fatal("deadline was not classified as transient")
	}
	if turnCredentialConnectError(errors.Join(ctx.Err(), errors.New("private trust failure"))) != ErrTurnCredentialsRejected {
		t.Fatal("deadline erased a joined trust failure")
	}
}
