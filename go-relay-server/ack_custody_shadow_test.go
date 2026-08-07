package main

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
)

func TestRelayNotificationClosure_AckCustodyProtectedShadowAtomicity(t *testing.T) {
	server := miniredis.RunT(t)
	backend := newAckCustodyRedisBackend(t, server, "ack-shadow:", 8)
	tokens := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	inbox := NewInboxStoreWithBackendAndCapacity(backend, push, 8)
	inbox.SetAckCustodyAdmissionEnabled(true)

	const (
		recipient = "peer-recipient"
		sender    = "peer-sender"
	)
	if err := tokens.RegisterToken(recipient, "recipient-token", "ios"); err != nil {
		t.Fatal(err)
	}
	entry := inboxMessage{
		ID:        "relay-new",
		From:      sender,
		Message:   ackCustodyTextEnvelope("text-new", sender, "cipher-new"),
		Timestamp: time.Now().UnixMilli(),
	}
	result, stored, err := inbox.StoreAckCustody(recipient, entry, ackCustodyDirectTextKind)
	if err != nil || result != InboxStoreResultStored {
		t.Fatalf("new StoreAckCustody = (%q, %v), want stored", result, err)
	}
	assertAtomicShadowPair(t, backend, recipient, stored)
	select {
	case <-recorder.sentSignal:
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for post-commit push launch")
	}
	if got := recorder.SendCallCount(); got != 1 {
		t.Fatalf("push launches after new commit = %d, want 1", got)
	}

	// Exact protected duplicate preserves the original physical identity and
	// expiry and cannot refanout.
	retry := entry
	retry.ID = "relay-retry"
	retry.Timestamp = time.Now().Add(time.Hour).UnixMilli()
	result, duplicate, err := inbox.StoreAckCustody(recipient, retry, ackCustodyDirectTextKind)
	if err != nil || result != InboxStoreResultDuplicate {
		t.Fatalf("exact duplicate = (%q, %v), want duplicate", result, err)
	}
	if duplicate.ID != stored.ID || duplicate.Timestamp != stored.Timestamp {
		t.Fatalf("duplicate identity/expiry = %#v, want original %#v", duplicate, stored)
	}
	time.Sleep(20 * time.Millisecond)
	if got := recorder.SendCallCount(); got != 1 {
		t.Fatalf("duplicate refanout count = %d, want 1 total", got)
	}

	// A legacy-only exact row is promoted in the same transaction with its
	// existing ID/timestamp, returns duplicate, and launches no push.
	const promotionPeer = "peer-promotion"
	promotion := inboxMessage{
		ID:        "relay-legacy-existing",
		From:      sender,
		Message:   ackCustodyTextEnvelope("text-promotion", sender, "cipher-promotion"),
		Timestamp: time.Now().Add(-2 * time.Hour).UnixMilli(),
	}
	legacyResult, err := backend.Store(promotionPeer, promotion)
	if err != nil || legacyResult != InboxStoreResultStored {
		t.Fatalf("seed legacy promotion row = (%q, %v)", legacyResult, err)
	}
	result, promoted, err := inbox.StoreAckCustody(
		promotionPeer,
		inboxMessage{
			ID:        "must-not-replace-legacy-id",
			From:      sender,
			Message:   promotion.Message,
			Timestamp: time.Now().UnixMilli(),
		},
		ackCustodyDirectTextKind,
	)
	if err != nil || result != InboxStoreResultDuplicate {
		t.Fatalf("legacy promotion = (%q, %v), want duplicate", result, err)
	}
	if promoted.ID != promotion.ID || promoted.Timestamp != promotion.Timestamp {
		t.Fatalf("promotion minted/refreshed row: got %#v want %#v", promoted, promotion)
	}
	assertAtomicShadowPair(t, backend, promotionPeer, promotion)
	if got := recorder.SendCallCount(); got != 1 {
		t.Fatalf("promotion refanout count = %d, want 1 total", got)
	}

	// A known pre-commit failure exposes neither physical copy and cannot launch.
	const preCommitPeer = "peer-pre-commit-abort"
	backend.ackCustodyBeforeCommit = func() error { return errors.New("known abort") }
	preCommit := inboxMessage{
		From:      sender,
		Message:   ackCustodyTextEnvelope("text-pre-abort", sender, "cipher"),
		Timestamp: time.Now().UnixMilli(),
	}
	result, _, err = inbox.StoreAckCustody(preCommitPeer, preCommit, ackCustodyDirectTextKind)
	backend.ackCustodyBeforeCommit = nil
	if err == nil || result != "" {
		t.Fatalf("pre-commit abort = (%q, %v), want nonaccepting error", result, err)
	}
	if backend.CountAckCustody(preCommitPeer) != 0 || backend.Count(preCommitPeer) != 0 {
		t.Fatal("known abort exposed a one-sided or complete physical copy")
	}
	if got := recorder.SendCallCount(); got != 1 {
		t.Fatalf("known abort push count = %d, want 1 total", got)
	}

	// Repeated WATCH conflicts are also a known pre-commit failure. Dirty the
	// watched protected key and restore its empty contents before each EXEC so
	// every optimistic transaction attempt loses without exposing either copy.
	const conflictPeer = "peer-watch-conflict-exhaustion"
	conflictAttempts := 0
	backend.ackCustodyBeforeCommit = func() error {
		conflictAttempts++
		ctx := context.Background()
		key := backend.ackCustodyKey(conflictPeer)
		if err := backend.client.RPush(ctx, key, `{"watch":"conflict"}`).Err(); err != nil {
			return err
		}
		return backend.client.RPop(ctx, key).Err()
	}
	conflicted := inboxMessage{
		From:      sender,
		Message:   ackCustodyTextEnvelope("text-watch-conflict", sender, "cipher"),
		Timestamp: time.Now().UnixMilli(),
	}
	result, _, err = inbox.StoreAckCustody(conflictPeer, conflicted, ackCustodyDirectTextKind)
	backend.ackCustodyBeforeCommit = nil
	if err == nil || result != "" {
		t.Fatalf("WATCH conflict exhaustion = (%q, %v), want nonaccepting error", result, err)
	}
	if conflictAttempts != redisWatchRetries {
		t.Fatalf("WATCH conflict attempts = %d, want %d", conflictAttempts, redisWatchRetries)
	}
	if backend.CountAckCustody(conflictPeer) != 0 || backend.Count(conflictPeer) != 0 {
		t.Fatal("WATCH conflict exhaustion exposed a one-sided or complete physical copy")
	}
	if got := recorder.SendCallCount(); got != 1 {
		t.Fatalf("WATCH conflict exhaustion push count = %d, want 1 total", got)
	}

	// An error after EXEC is ambiguous to the sender: both copies may exist, but
	// no receipt or push is returned. An exact retry converges to duplicate with
	// the committed ID/timestamp and still does not refanout.
	const ambiguousPeer = "peer-post-commit-ambiguous"
	backend.ackCustodyAfterCommit = func() error { return errors.New("response lost") }
	ambiguous := inboxMessage{
		ID:        "relay-ambiguous",
		From:      sender,
		Message:   ackCustodyTextEnvelope("text-ambiguous", sender, "cipher"),
		Timestamp: time.Now().UnixMilli(),
	}
	result, _, err = inbox.StoreAckCustody(ambiguousPeer, ambiguous, ackCustodyDirectTextKind)
	backend.ackCustodyAfterCommit = nil
	if err == nil || result != "" {
		t.Fatalf("post-commit ambiguity = (%q, %v), want nonaccepting error", result, err)
	}
	assertAtomicShadowPair(t, backend, ambiguousPeer, ambiguous)
	result, converged, err := inbox.StoreAckCustody(
		ambiguousPeer,
		inboxMessage{
			From:      sender,
			Message:   ambiguous.Message,
			Timestamp: time.Now().Add(time.Minute).UnixMilli(),
		},
		ackCustodyDirectTextKind,
	)
	if err != nil || result != InboxStoreResultDuplicate {
		t.Fatalf("retry after ambiguous commit = (%q, %v), want duplicate", result, err)
	}
	if converged.ID != ambiguous.ID || converged.Timestamp != ambiguous.Timestamp {
		t.Fatalf("ambiguous retry identity = %#v, want %#v", converged, ambiguous)
	}
	time.Sleep(20 * time.Millisecond)
	if got := recorder.SendCallCount(); got != 1 {
		t.Fatalf("ambiguous/retry push count = %d, want 1 total", got)
	}
}
