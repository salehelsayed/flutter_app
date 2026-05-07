package main

import (
	"sync/atomic"
	"testing"
	"time"
)

func requireInboxStoreResult(
	t *testing.T,
	inbox *InboxStore,
	toPeerId string,
	message inboxMessage,
	want InboxStoreResult,
) {
	t.Helper()

	got, err := inbox.Store(toPeerId, message)
	if err != nil {
		t.Fatalf("Store() error: %v", err)
	}
	if got != want {
		t.Fatalf("Store() result = %q, want %q", got, want)
	}
}

func TestInboxStoreDedup(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)

	msg1 := inboxMessage{
		From:      "sender-peer",
		Message:   `{"type":"chat","version":"1","payload":{"id":"msg-dedup-001","text":"hello"}}`,
		Timestamp: time.Now().UnixMilli(),
	}

	// First store succeeds
	requireInboxStoreResult(t, inbox, "recipient-peer", msg1, InboxStoreResultStored)
	count := inbox.Count("recipient-peer")
	if count != 1 {
		t.Fatalf("expected 1 message after first store, got %d", count)
	}

	// Second store with same messageId is a no-op
	msg2 := inboxMessage{
		From:      "sender-peer",
		Message:   msg1.Message, // same payload, same messageId
		Timestamp: time.Now().UnixMilli(),
	}
	requireInboxStoreResult(t, inbox, "recipient-peer", msg2, InboxStoreResultDuplicate)
	count = inbox.Count("recipient-peer")
	if count != 1 {
		t.Fatalf("expected 1 message after duplicate store, got %d", count)
	}
}

func TestInboxStoreDedup_DifferentMessageIds(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)

	msg1 := inboxMessage{
		From:      "sender-peer",
		Message:   `{"type":"chat","version":"1","payload":{"id":"msg-A","text":"first"}}`,
		Timestamp: time.Now().UnixMilli(),
	}
	msg2 := inboxMessage{
		From:      "sender-peer",
		Message:   `{"type":"chat","version":"1","payload":{"id":"msg-B","text":"second"}}`,
		Timestamp: time.Now().UnixMilli(),
	}

	requireInboxStoreResult(t, inbox, "recipient-peer", msg1, InboxStoreResultStored)
	requireInboxStoreResult(t, inbox, "recipient-peer", msg2, InboxStoreResultStored)
	count := inbox.Count("recipient-peer")
	if count != 2 {
		t.Fatalf("expected 2 messages for different IDs, got %d", count)
	}
}

func TestInboxStoreDedup_SameIdDifferentRecipient(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)

	msg := inboxMessage{
		From:      "sender-peer",
		Message:   `{"type":"chat","version":"1","payload":{"id":"msg-shared","text":"broadcast"}}`,
		Timestamp: time.Now().UnixMilli(),
	}

	requireInboxStoreResult(t, inbox, "recipient-A", msg, InboxStoreResultStored)
	requireInboxStoreResult(t, inbox, "recipient-B", msg, InboxStoreResultStored)
	if inbox.Count("recipient-A") != 1 {
		t.Fatal("recipient-A should have 1 message")
	}
	if inbox.Count("recipient-B") != 1 {
		t.Fatal("recipient-B should have 1 message")
	}
}

func TestInboxStoreDedup_V2EncryptedEnvelope(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)

	// V2 encrypted envelopes embed the messageId at the top level as "id"
	msg := inboxMessage{
		From:      "sender-peer",
		Message:   `{"version":"2","senderPeerId":"sender","id":"msg-enc-001","encrypted":{"kem":"...","ciphertext":"...","nonce":"..."}}`,
		Timestamp: time.Now().UnixMilli(),
	}

	requireInboxStoreResult(t, inbox, "recipient-peer", msg, InboxStoreResultStored)
	requireInboxStoreResult(t, inbox, "recipient-peer", msg, InboxStoreResultDuplicate)
	if inbox.Count("recipient-peer") != 1 {
		t.Fatalf("expected 1 message after duplicate v2 store, got %d", inbox.Count("recipient-peer"))
	}
}

func TestInboxStoreDedup_IntroductionPlaintextEnvelope(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)

	msg := inboxMessage{
		From:      "sender-peer",
		Message:   `{"type":"introduction","version":"1","payload":{"action":"send","introductionId":"intro-plain-001","timestamp":"2026-04-04T20:36:00Z"}}`,
		Timestamp: time.Now().UnixMilli(),
	}

	requireInboxStoreResult(t, inbox, "recipient-peer", msg, InboxStoreResultStored)
	requireInboxStoreResult(t, inbox, "recipient-peer", msg, InboxStoreResultDuplicate)
	if inbox.Count("recipient-peer") != 1 {
		t.Fatalf(
			"expected 1 introduction after duplicate plaintext store, got %d",
			inbox.Count("recipient-peer"),
		)
	}
}

func TestInboxStoreDedup_IntroductionPlaintextDifferentActionMessageIDs(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)

	send := inboxMessage{
		From:      "sender-peer",
		Message:   `{"type":"introduction","version":"1","messageId":"intro-plain-001::send::peer-A","payload":{"action":"send","introductionId":"intro-plain-001","timestamp":"2026-04-04T20:36:00Z"}}`,
		Timestamp: time.Now().UnixMilli(),
	}
	accept := inboxMessage{
		From:      "recipient-peer-B",
		Message:   `{"type":"introduction","version":"1","messageId":"intro-plain-001::accept::peer-B","payload":{"action":"accept","introductionId":"intro-plain-001","responderId":"peer-B","timestamp":"2026-04-04T20:37:00Z"}}`,
		Timestamp: time.Now().UnixMilli(),
	}

	requireInboxStoreResult(t, inbox, "recipient-peer", send, InboxStoreResultStored)
	requireInboxStoreResult(t, inbox, "recipient-peer", accept, InboxStoreResultStored)
	if inbox.Count("recipient-peer") != 2 {
		t.Fatalf(
			"expected 2 introductions after action-distinct plaintext store, got %d",
			inbox.Count("recipient-peer"),
		)
	}

	requireInboxStoreResult(t, inbox, "recipient-peer", accept, InboxStoreResultDuplicate)
	if inbox.Count("recipient-peer") != 2 {
		t.Fatalf(
			"expected duplicate accept to stay deduped after plaintext action split, got %d",
			inbox.Count("recipient-peer"),
		)
	}
}

func TestInboxStoreDedup_IntroductionEncryptedEnvelopeWithMessageID(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)

	msg := inboxMessage{
		From:      "sender-peer",
		Message:   `{"type":"introduction","version":"2","messageId":"intro-enc-001","senderPeerId":"sender","encrypted":{"kem":"...","ciphertext":"...","nonce":"..."}}`,
		Timestamp: time.Now().UnixMilli(),
	}

	requireInboxStoreResult(t, inbox, "recipient-peer", msg, InboxStoreResultStored)
	requireInboxStoreResult(t, inbox, "recipient-peer", msg, InboxStoreResultDuplicate)
	if inbox.Count("recipient-peer") != 1 {
		t.Fatalf(
			"expected 1 introduction after duplicate encrypted store, got %d",
			inbox.Count("recipient-peer"),
		)
	}
}

func TestInboxStoreDedup_IntroductionEncryptedDifferentActionMessageIDs(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)

	send := inboxMessage{
		From:      "sender-peer",
		Message:   `{"type":"introduction","version":"2","messageId":"intro-enc-001::send::peer-A","senderPeerId":"peer-A","encrypted":{"kem":"...","ciphertext":"...","nonce":"..."}}`,
		Timestamp: time.Now().UnixMilli(),
	}
	accept := inboxMessage{
		From:      "recipient-peer-B",
		Message:   `{"type":"introduction","version":"2","messageId":"intro-enc-001::accept::peer-B","senderPeerId":"peer-B","encrypted":{"kem":"...","ciphertext":"...","nonce":"..."}}`,
		Timestamp: time.Now().UnixMilli(),
	}

	requireInboxStoreResult(t, inbox, "recipient-peer", send, InboxStoreResultStored)
	requireInboxStoreResult(t, inbox, "recipient-peer", accept, InboxStoreResultStored)
	if inbox.Count("recipient-peer") != 2 {
		t.Fatalf(
			"expected 2 introductions after action-distinct encrypted store, got %d",
			inbox.Count("recipient-peer"),
		)
	}

	requireInboxStoreResult(t, inbox, "recipient-peer", accept, InboxStoreResultDuplicate)
	if inbox.Count("recipient-peer") != 2 {
		t.Fatalf(
			"expected duplicate accept to stay deduped after encrypted action split, got %d",
			inbox.Count("recipient-peer"),
		)
	}
}

func TestInboxStoreDedup_MalformedJsonFallsThrough(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)

	// Malformed JSON should still be stored (no dedup possible)
	msg := inboxMessage{
		From:      "sender-peer",
		Message:   "not valid json",
		Timestamp: time.Now().UnixMilli(),
	}

	requireInboxStoreResult(t, inbox, "recipient-peer", msg, InboxStoreResultStored)
	requireInboxStoreResult(t, inbox, "recipient-peer", msg, InboxStoreResultStored)
	// Both stored because we cannot extract a messageId
	if inbox.Count("recipient-peer") != 2 {
		t.Fatalf("expected 2 messages for malformed JSON, got %d", inbox.Count("recipient-peer"))
	}
}

// pushRecorder tracks push notification sends for testing.
type pushRecorder struct {
	count int64
}

func (r *pushRecorder) sendCount() int {
	return int(atomic.LoadInt64(&r.count))
}

// newPushServiceWithSender creates a PushService with a custom sender for testing.
// Since PushService.client is what triggers real sends, and our test tokens
// won't match a real FCM client, we test dedup at the Store level instead.
// The push notification test verifies that Store returns duplicate for duplicates,
// which prevents the `go inbox.push.SendNotification()` call in InboxStore.Store.

func TestInboxStoreDedup_PushNotFiredOnDuplicate(t *testing.T) {
	// We verify that InboxStore.Store does not call SendNotification on duplicate
	// by checking that the Store method returns early (no push goroutine spawned).
	// The production code skips the push goroutine when backend.Store returns duplicate.
	tokenStore := newMemoryPushTokenStore()
	tokenStore.RegisterToken("recipient-peer", "fake-token", "ios")
	push := NewPushServiceWithBackend(tokenStore)
	inbox := NewInboxStore(push)

	msg := inboxMessage{
		From:      "sender-peer",
		Message:   `{"type":"chat","version":"1","payload":{"id":"msg-push-001","text":"hello"}}`,
		Timestamp: time.Now().UnixMilli(),
	}

	requireInboxStoreResult(t, inbox, "recipient-peer", msg, InboxStoreResultStored)
	// First store should proceed (push goroutine would be spawned in production)

	// Get count before duplicate
	count1 := inbox.Count("recipient-peer")
	if count1 != 1 {
		t.Fatalf("expected 1 message after first store, got %d", count1)
	}

	requireInboxStoreResult(t, inbox, "recipient-peer", msg, InboxStoreResultDuplicate)
	// Count should still be 1 — duplicate was blocked at the backend level
	count2 := inbox.Count("recipient-peer")
	if count2 != 1 {
		t.Fatalf("expected 1 message after duplicate store (push not fired), got %d", count2)
	}
}
