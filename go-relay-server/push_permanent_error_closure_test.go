package main

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"google.golang.org/api/option"
)

// syncLogBuffer is a mutex-guarded log sink: dispatched fan-outs log from the
// send goroutine concurrently with the storing goroutine's wake lines.
type syncLogBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (s *syncLogBuffer) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.Write(p)
}

func (s *syncLogBuffer) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.String()
}

// Plan 320 TC-320-01 — the HEADLINE typed arm. A REAL SDK client pointed at a
// fake FCM (httptest) that answers the v1 error JSON with
// details[].errorCode=UNREGISTERED: the typed predicate must classify it
// permanent — exactly one HTTP hit, token evicted, invalid_token counted,
// reason=typed_unregistered logged. The response message text is deliberately
// opaque (matches NO literal), so this row is also the standing do-not-wrap
// detector: messaging.Is* type-asserts *internal.FirebaseError without
// Unwrap, and one fmt.Errorf("…: %w") in ps.send would fall through to the
// transient ladder and red this row.
func TestRelayNotificationClosure_PermanentTokenErrorEvictsWithoutRetry(t *testing.T) {
	var hits int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&hits, 1)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		fmt.Fprint(w, `{"error":{"code":404,"status":"NOT_FOUND","message":"opaque provider message","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}`)
	}))
	defer srv.Close()

	ctx := context.Background()
	app, err := firebase.NewApp(
		ctx,
		&firebase.Config{ProjectID: "test-project"},
		option.WithEndpoint(srv.URL),
		option.WithoutAuthentication(),
	)
	if err != nil {
		t.Fatalf("firebase app against fake FCM: %v", err)
	}
	client, err := app.Messaging(ctx)
	if err != nil {
		t.Fatalf("messaging client against fake FCM: %v", err)
	}

	tokenStore := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokenStore)
	push.retryDelays = []time.Duration{0, 0}
	push.client = client // real SDK client path; ps.sender stays nil
	tokenStore.RegisterToken("peer-typed-dead", "typed-dead-token", "android")

	journal := &bytes.Buffer{}
	previousWriter := log.Writer()
	log.SetOutput(journal)
	t.Cleanup(func() { log.SetOutput(previousWriter) })

	invalidTokenCounter := pushSentCounter.WithLabelValues("invalid_token")
	before := testutil.ToFloat64(invalidTokenCounter)

	push.SendNotification(ctx, "peer-typed-dead", "peer-sender", `{"id":"msg-typed","text":"hi"}`)

	if got := atomic.LoadInt32(&hits); got != 1 {
		t.Fatalf("fake FCM hits = %d, want exactly 1 (typed permanent error must not retry)", got)
	}
	if tokenStore.LookupToken("peer-typed-dead") != nil {
		t.Fatal("token was not evicted on typed UNREGISTERED")
	}
	if delta := testutil.ToFloat64(invalidTokenCounter) - before; delta != 1 {
		t.Fatalf("invalid_token delta = %v, want 1", delta)
	}
	if got := journal.String(); !strings.Contains(got, "reason=typed_unregistered") {
		t.Fatalf("journal = %q, want reason=typed_unregistered attribution", got)
	}
}

// Plan 320 TC-320-01b — the BLOCKER-1 row. The production journal shows FCM's
// error *message* text ("NotRegistered", and for the same dead peer at another
// time "Requested entity was not found."), which is NOT the SDK errorCode the
// typed predicates read. Without a literal arm the fix ships inert: the legacy
// hyphenated literals match neither string, so a permanent dead-token error
// walks the transient ladder and the token is never evicted.
func TestRelayNotificationClosure_ObservedPermanentTextEvictsWithoutRetry(t *testing.T) {
	for _, observed := range []string{
		"NotRegistered",
		"Requested entity was not found.",
	} {
		tokenStore := newMemoryPushTokenStore()
		push := NewPushServiceWithBackend(tokenStore)
		push.retryDelays = []time.Duration{0, 0}
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		tokenStore.RegisterToken("peer-dead", "dead-token", "android")
		recorder.onSend = func(ctx context.Context, msg *messaging.Message) (string, error) {
			return "", fmt.Errorf("%s", observed)
		}

		push.SendNotification(
			context.Background(),
			"peer-dead",
			"peer-sender",
			`{"id":"msg-1","text":"hi"}`,
		)

		if got := recorder.SendCallCount(); got != 1 {
			t.Fatalf("observed=%q send calls = %d, want 1 (permanent error must not retry)", observed, got)
		}
		if tokenStore.LookupToken("peer-dead") != nil {
			t.Fatalf("observed=%q token was not evicted", observed)
		}
	}
}

// Plan 320 TC-320-02 — SENDER_ID_MISMATCH is permanent too.
func TestRelayNotificationClosure_SenderIdMismatchIsPermanent(t *testing.T) {
	tokenStore := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokenStore)
	push.retryDelays = []time.Duration{0, 0}
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	tokenStore.RegisterToken("peer-mismatch", "other-project-token", "android")
	recorder.onSend = func(ctx context.Context, msg *messaging.Message) (string, error) {
		return "", fmt.Errorf("SenderId mismatch")
	}

	push.SendNotification(
		context.Background(),
		"peer-mismatch",
		"peer-sender",
		`{"id":"msg-2","text":"hi"}`,
	)

	if got := recorder.SendCallCount(); got != 1 {
		t.Fatalf("send calls = %d, want 1", got)
	}
	if tokenStore.LookupToken("peer-mismatch") != nil {
		t.Fatal("token was not evicted on sender-id mismatch")
	}
}

// Plan 320 TC-320-03 — transient errors keep the ladder and the token.
// Deliberately on the ps.sender stub seam: the SDK layers its own retry ladder
// under a real client, so a real-client fixture's attempt count would not mean
// what this row asserts.
func TestRelayNotificationClosure_TransientErrorKeepsRetryLadderAndToken(t *testing.T) {
	tokenStore := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokenStore)
	push.retryDelays = []time.Duration{0, 0}
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	tokenStore.RegisterToken("peer-live", "live-token", "android")
	recorder.onSend = func(ctx context.Context, msg *messaging.Message) (string, error) {
		return "", fmt.Errorf("service unavailable")
	}

	push.SendNotification(
		context.Background(),
		"peer-live",
		"peer-sender",
		`{"id":"msg-3","text":"hi"}`,
	)

	if got := recorder.SendCallCount(); got != 3 {
		t.Fatalf("send calls = %d, want 3 (transient keeps the full ladder)", got)
	}
	if tokenStore.LookupToken("peer-live") == nil {
		t.Fatal("a transient error must never evict a live token")
	}
}

// Plan 320 TC-320-04 — the legacy hyphenated literals still evict.
func TestRelayNotificationClosure_LegacyInvalidTokenLiteralsStillEvict(t *testing.T) {
	for _, legacy := range []string{
		"registration-token-not-registered",
		"invalid-registration-token",
	} {
		tokenStore := newMemoryPushTokenStore()
		push := NewPushServiceWithBackend(tokenStore)
		push.retryDelays = []time.Duration{0, 0}
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		tokenStore.RegisterToken("peer-legacy", "legacy-token", "ios")
		recorder.onSend = func(ctx context.Context, msg *messaging.Message) (string, error) {
			return "", fmt.Errorf("%s", legacy)
		}

		push.SendNotification(
			context.Background(),
			"peer-legacy",
			"peer-sender",
			`{"id":"msg-4","text":"hi"}`,
		)

		if got := recorder.SendCallCount(); got != 1 {
			t.Fatalf("legacy=%q send calls = %d, want 1", legacy, got)
		}
		if tokenStore.LookupToken("peer-legacy") != nil {
			t.Fatalf("legacy=%q token was not evicted", legacy)
		}
	}
}

// Plan 320 TC-320-05 (P3) — the SAME transition id must appear on BOTH wake
// lines, captured from one store and one byte-identical re-store. Without the
// shared id an `attempted` and a `duplicate_suppressed` line can NEVER be
// correlated per transition, which is exactly why the "production shows zero
// lost wakes" inference was structurally invalid.
func TestRelayNotificationClosure_WakeLinesCarryTransitionId(t *testing.T) {
	const (
		groupID = "group-wake-transition-correlation"
		from    = "reactor-transport"
		author  = "author-transport"
	)
	fixture := newSignedGroupReactionFixture(t, groupID, "reactor-account", from)
	tokens := newMemoryPushTokenStore()
	tokens.RegisterToken(author, "author-token", "android", groupReactionCapability)
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	store := NewGroupInboxStore(500, 7*24*time.Hour)
	store.SetPush(push)
	store.SetGroupReactionPushEnabled(true)

	journal := &syncLogBuffer{}
	previousWriter := log.Writer()
	log.SetOutput(journal)
	t.Cleanup(func() { log.SetOutput(previousWriter) })

	transitionID := "transition-correlation-0001"
	envelope := fixture.envelope(
		t,
		transitionID,
		"add",
		"correlation-state",
		"target-message",
		[]string{author},
		[]string{author},
	)
	if err := store.StoreWithPushRecipients(groupID, from, envelope, []string{author}); err != nil {
		t.Fatalf("store reaction: %v", err)
	}
	waitForGroupReactionPushes(t, recorder, 1)
	if err := store.StoreWithPushRecipients(groupID, from, envelope, []string{author}); err != nil {
		t.Fatalf("byte-identical re-store: %v", err)
	}

	wantToken := "transition=" + transitionID[:24]
	var dispatchedLine, duplicateLine string
	for _, line := range strings.Split(journal.String(), "\n") {
		if strings.Contains(line, "outcome=dispatched") {
			dispatchedLine = line
		}
		if strings.Contains(line, "outcome=duplicate_suppressed") {
			duplicateLine = line
		}
	}
	if dispatchedLine == "" || duplicateLine == "" {
		t.Fatalf("journal missing wake lines: dispatched=%q duplicate=%q", dispatchedLine, duplicateLine)
	}
	if !strings.Contains(dispatchedLine, wantToken) {
		t.Fatalf("dispatched line %q lacks %q", dispatchedLine, wantToken)
	}
	if !strings.Contains(duplicateLine, wantToken) {
		t.Fatalf("duplicate_suppressed line %q lacks %q", duplicateLine, wantToken)
	}
}

// Plan 320 TC-320-06 (P3) — all THREE formerly-silent decline paths emit
// counted outcomes, and for one transition the emitted outcome count equals
// len(notificationRecipientTransportPeerIds) — the accounting identity the
// uncounted in-loop self-skip used to break.
func TestRelayNotificationClosure_SilentWakeGuardsAreCounted(t *testing.T) {
	const from = "reactor-transport"

	journal := &syncLogBuffer{}
	previousWriter := log.Writer()
	log.SetOutput(journal)
	t.Cleanup(func() { log.SetOutput(previousWriter) })

	// (a) recognized-but-disabled: the flag is default-off (TC-320-11), so a
	// valid add reaction hits the invalid_or_disabled guard.
	flagOffGroup := "group-wake-flag-off"
	flagOffFixture := newSignedGroupReactionFixture(t, flagOffGroup, "reactor-account", from)
	flagOffStore := NewGroupInboxStore(500, 7*24*time.Hour)
	invalidOrDisabled := groupReactionWakeCounter.WithLabelValues("invalid_or_disabled")
	beforeInvalid := testutil.ToFloat64(invalidOrDisabled)
	flagOffEnvelope := flagOffFixture.envelope(
		t,
		"flag-off-transition",
		"add",
		"flag-off-state",
		"target-message",
		[]string{"author-transport"},
		[]string{"author-transport"},
	)
	if err := flagOffStore.StoreWithPushRecipients(
		flagOffGroup, from, flagOffEnvelope, []string{"author-transport"},
	); err != nil {
		t.Fatalf("store flag-off reaction: %v", err)
	}
	if delta := testutil.ToFloat64(invalidOrDisabled) - beforeInvalid; delta != 1 {
		t.Fatalf("invalid_or_disabled delta = %v, want 1", delta)
	}
	if !strings.Contains(journal.String(), "outcome=invalid_or_disabled") {
		t.Fatalf("journal = %q, want invalid_or_disabled line", journal.String())
	}

	// (b) push-service-nil: flag on, no push service wired.
	nilPushGroup := "group-wake-nil-push"
	nilPushFixture := newSignedGroupReactionFixture(t, nilPushGroup, "reactor-account", from)
	nilPushStore := NewGroupInboxStore(500, 7*24*time.Hour)
	nilPushStore.SetGroupReactionPushEnabled(true)
	pushUnavailable := groupReactionWakeCounter.WithLabelValues("push_unavailable")
	beforeUnavailable := testutil.ToFloat64(pushUnavailable)
	nilPushEnvelope := nilPushFixture.envelope(
		t,
		"nil-push-transition",
		"add",
		"nil-push-state",
		"target-message",
		[]string{"author-transport"},
		[]string{"author-transport"},
	)
	if err := nilPushStore.StoreWithPushRecipients(
		nilPushGroup, from, nilPushEnvelope, []string{"author-transport"},
	); err != nil {
		t.Fatalf("store nil-push reaction: %v", err)
	}
	if delta := testutil.ToFloat64(pushUnavailable) - beforeUnavailable; delta != 1 {
		t.Fatalf("push_unavailable delta = %v, want 1", delta)
	}
	if !strings.Contains(journal.String(), "outcome=push_unavailable") {
		t.Fatalf("journal = %q, want push_unavailable line", journal.String())
	}

	// (c) the in-loop self-skip, plus the accounting identity: a nomination of
	// [capable, incapable, self] must emit exactly three counted outcomes.
	const (
		capable   = "author-capable-transport"
		incapable = "author-incapable-transport"
	)
	identityGroup := "group-wake-identity"
	identityFixture := newSignedGroupReactionFixture(t, identityGroup, "reactor-account", from)
	tokens := newMemoryPushTokenStore()
	tokens.RegisterToken(capable, "capable-token", "android", groupReactionCapability)
	tokens.RegisterToken(incapable, "incapable-token", "android", directReactionCapability)
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	identityStore := NewGroupInboxStore(500, 7*24*time.Hour)
	identityStore.SetPush(push)
	identityStore.SetGroupReactionPushEnabled(true)

	nominations := []string{capable, incapable, from}
	selfSkipped := groupReactionWakeCounter.WithLabelValues("self_or_empty_skipped")
	incapableSkipped := groupReactionWakeCounter.WithLabelValues("incapable_skipped")
	attempted := groupReactionWakeCounter.WithLabelValues("attempted")
	beforeSelf := testutil.ToFloat64(selfSkipped)
	beforeIncapable := testutil.ToFloat64(incapableSkipped)
	beforeAttempted := testutil.ToFloat64(attempted)

	identityEnvelope := identityFixture.envelope(
		t,
		"identity-transition",
		"add",
		"identity-state",
		"target-message",
		nominations,
		nominations,
	)
	if err := identityStore.StoreWithPushRecipients(
		identityGroup, from, identityEnvelope, nominations,
	); err != nil {
		t.Fatalf("store identity reaction: %v", err)
	}
	waitForGroupReactionPushes(t, recorder, 1)

	selfDelta := testutil.ToFloat64(selfSkipped) - beforeSelf
	incapableDelta := testutil.ToFloat64(incapableSkipped) - beforeIncapable
	attemptedDelta := testutil.ToFloat64(attempted) - beforeAttempted
	if selfDelta != 1 {
		t.Fatalf("self_or_empty_skipped delta = %v, want 1", selfDelta)
	}
	if incapableDelta != 1 {
		t.Fatalf("incapable_skipped delta = %v, want 1", incapableDelta)
	}
	if attemptedDelta != 1 {
		t.Fatalf("attempted delta = %v, want 1", attemptedDelta)
	}
	if emitted := selfDelta + incapableDelta + attemptedDelta; emitted != float64(len(nominations)) {
		t.Fatalf("accounting identity broken: emitted outcomes = %v, want %d", emitted, len(nominations))
	}
}

// Plan 320 TC-320-07 — the wake counter label set stays backward compatible:
// the pre-dispatch LOG token became "dispatched", but the counter label must
// remain "attempted" (dashboards read it), and the legacy outcome series stay
// addressable.
func TestRelayNotificationClosure_WakeOutcomeLabelsRemainCompatible(t *testing.T) {
	for _, outcome := range []string{
		"attempted", "duplicate_suppressed", "no_wake_recipients", "incapable_skipped",
	} {
		if got := testutil.ToFloat64(groupReactionWakeCounter.WithLabelValues(outcome)); got < 0 {
			t.Fatalf("legacy outcome %q not addressable", outcome)
		}
	}

	const (
		groupID = "group-wake-label-compat"
		from    = "reactor-transport"
		author  = "author-labels-transport"
	)
	fixture := newSignedGroupReactionFixture(t, groupID, "reactor-account", from)
	tokens := newMemoryPushTokenStore()
	tokens.RegisterToken(author, "author-token", "android", groupReactionCapability)
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	store := NewGroupInboxStore(500, 7*24*time.Hour)
	store.SetPush(push)
	store.SetGroupReactionPushEnabled(true)

	attempted := groupReactionWakeCounter.WithLabelValues("attempted")
	renamed := groupReactionWakeCounter.WithLabelValues("dispatched")
	beforeAttempted := testutil.ToFloat64(attempted)
	beforeRenamed := testutil.ToFloat64(renamed)

	envelope := fixture.envelope(
		t,
		"label-compat-transition",
		"add",
		"label-compat-state",
		"target-message",
		[]string{author},
		[]string{author},
	)
	if err := store.StoreWithPushRecipients(groupID, from, envelope, []string{author}); err != nil {
		t.Fatalf("store reaction: %v", err)
	}
	waitForGroupReactionPushes(t, recorder, 1)

	if delta := testutil.ToFloat64(attempted) - beforeAttempted; delta != 1 {
		t.Fatalf("attempted delta = %v, want 1 (dashboard label must survive the log-token rename)", delta)
	}
	if delta := testutil.ToFloat64(renamed) - beforeRenamed; delta != 0 {
		t.Fatalf("a 'dispatched' counter series incremented (%v) — the rename must stay log-only", delta)
	}
}
