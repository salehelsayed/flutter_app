package main

import (
	"context"
	"fmt"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
)

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
