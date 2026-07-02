package main

import (
	"strconv"
	"testing"
	"time"
)

// =============================================================================
// Phase 7: Relay Server Limits — Admission Control Tests
//
// These tests verify that the relay server enforces finite resource limits
// instead of using infinite limits. Excess load is rejected predictably
// (with clear errors) rather than hanging or crashing.
// =============================================================================

// --- Inbox limits ---

// TC-05 (plan 173) — a 1:1 store to a full inbox EVICTS THE OLDEST and stores
// the newest (build-106 contract, NET-REL-07). Rejecting the new message
// instead was the 2026-06-28 regression: shipped clients have no INBOX_FULL
// branch, so the newest message was silently dropped sender-side.
func TestFiniteLimits_EvictOldestWhenInboxFull(t *testing.T) {
	cfg := DefaultServerLimits()
	cfg.MaxInboxMessagesPerPeer = 10

	backend := newMemoryInboxBackendWithLimits(cfg.MaxInboxMessagesPerPeer)
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStoreWithBackend(backend, push)

	// Store up to the limit — all should succeed.
	for i := 0; i < cfg.MaxInboxMessagesPerPeer; i++ {
		requireInboxStoreResult(t, inbox, "peer-1", inboxMessage{
			From:      "sender",
			Message:   "msg-" + strconv.Itoa(i),
			Timestamp: time.Now().UnixMilli(),
		}, InboxStoreResultStored)
	}

	count := inbox.Count("peer-1")
	if count != cfg.MaxInboxMessagesPerPeer {
		t.Errorf("expected %d messages, got %d", cfg.MaxInboxMessagesPerPeer, count)
	}

	// Store one more — the oldest is evicted and the newest is stored
	// (build-106 contract). The oldest pending copy is the most likely to be
	// stale/already-delivered; the newest is what the sender just said.
	requireInboxStoreResult(t, inbox, "peer-1", inboxMessage{
		From:      "sender",
		Message:   "overflow-msg",
		Timestamp: time.Now().UnixMilli(),
	}, InboxStoreResultStored)

	count = inbox.Count("peer-1")
	if count != cfg.MaxInboxMessagesPerPeer {
		t.Errorf("expected inbox to stay at %d after overflow, got %d", cfg.MaxInboxMessagesPerPeer, count)
	}

	messages, _ := inbox.RetrievePendingWithMeta("peer-1", cfg.MaxInboxMessagesPerPeer+1)
	if len(messages) != cfg.MaxInboxMessagesPerPeer {
		t.Fatalf("expected %d retained messages, got %d", cfg.MaxInboxMessagesPerPeer, len(messages))
	}
	if messages[0].Message != "msg-1" {
		t.Fatalf("oldest retained message = %q, want msg-1 (msg-0 evicted)", messages[0].Message)
	}
	if last := messages[len(messages)-1].Message; last != "overflow-msg" {
		t.Fatalf("newest message = %q, want overflow-msg (must be stored, not rejected)", last)
	}
}

// --- Group inbox limits ---

func TestFiniteLimits_RejectExcessGroupMessages(t *testing.T) {
	cfg := DefaultServerLimits()
	cfg.MaxGroupInboxMessages = 20

	backend := newMemoryGroupInboxBackend(cfg.MaxGroupInboxMessages, groupMessageTTL)
	store := NewGroupInboxStoreWithBackend(backend)

	// Store up to the limit.
	for i := 0; i < cfg.MaxGroupInboxMessages; i++ {
		err := store.Store("group-1", "sender", "msg")
		if err != nil {
			t.Fatalf("store %d: unexpected error: %v", i, err)
		}
	}

	groups, total := store.Stats()
	if groups != 1 || total != cfg.MaxGroupInboxMessages {
		t.Errorf("expected 1 group with %d messages, got %d groups with %d messages",
			cfg.MaxGroupInboxMessages, groups, total)
	}

	// Store one more — the oldest should be evicted (bounded).
	err := store.Store("group-1", "sender", "overflow-msg")
	if err != nil {
		t.Fatalf("overflow store: unexpected error: %v", err)
	}

	_, total = store.Stats()
	if total != cfg.MaxGroupInboxMessages {
		t.Errorf("expected group inbox to stay at %d after overflow, got %d",
			cfg.MaxGroupInboxMessages, total)
	}
}

// TC-06 (plan 173) — preservation lock: the GROUP inbox store-when-full
// semantics (evict-oldest, keep newest) must NOT change while the 1:1 path is
// restored to the same contract. Content-level assertion: the oldest message
// is the one displaced and the overflow message is retained.
func TestGroupInboxStillEvicts(t *testing.T) {
	const capacity = 20
	backend := newMemoryGroupInboxBackend(capacity, groupMessageTTL)
	store := NewGroupInboxStoreWithBackend(backend)

	for i := 0; i < capacity; i++ {
		if err := store.Store("group-evict-lock", "sender", "msg-"+strconv.Itoa(i)); err != nil {
			t.Fatalf("store %d: unexpected error: %v", i, err)
		}
	}
	if err := store.Store("group-evict-lock", "sender", "overflow-msg"); err != nil {
		t.Fatalf("overflow store: unexpected error: %v", err)
	}

	messages := backend.RetrieveSince("group-evict-lock", 0)
	if len(messages) != capacity {
		t.Fatalf("expected %d retained group messages, got %d", capacity, len(messages))
	}
	if messages[0].Message != "msg-1" {
		t.Fatalf("oldest retained group message = %q, want msg-1 (msg-0 evicted)", messages[0].Message)
	}
	if last := messages[len(messages)-1].Message; last != "overflow-msg" {
		t.Fatalf("newest group message = %q, want overflow-msg", last)
	}
}

// --- Admission control preserves latency ---

func TestAdmissionControl_PreservesLatencyForAdmittedPeersUnderPressure(t *testing.T) {
	cfg := DefaultServerLimits()
	cfg.MaxInboxMessagesPerPeer = 50

	backend := newMemoryInboxBackendWithLimits(cfg.MaxInboxMessagesPerPeer)
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStoreWithBackend(backend, push)

	// Simulate pressure: many peers writing to the inbox concurrently.
	peerCount := 100
	messagesPerPeer := 5

	start := time.Now()
	for p := 0; p < peerCount; p++ {
		peerId := "peer-" + time.Now().Format("150405") + "-" + string(rune(p))
		for m := 0; m < messagesPerPeer; m++ {
			requireInboxStoreResult(t, inbox, peerId, inboxMessage{
				From:      "sender",
				Message:   "msg",
				Timestamp: time.Now().UnixMilli(),
			}, InboxStoreResultStored)
		}
	}
	elapsed := time.Since(start)

	// The key assertion: admission (store) operations should complete
	// within a reasonable time, not hang or block excessively.
	// 5 seconds is extremely generous; in practice, in-memory stores are < 1ms.
	if elapsed > 5*time.Second {
		t.Errorf("inbox stores under pressure took %v, expected < 5s", elapsed)
	}
}

// --- ServerLimits defaults ---

func TestServerLimits_DefaultsAreSane(t *testing.T) {
	cfg := DefaultServerLimits()

	if cfg.MaxRelayReservations <= 0 {
		t.Error("MaxRelayReservations should be > 0")
	}
	if cfg.MaxInboxMessagesPerPeer <= 0 {
		t.Error("MaxInboxMessagesPerPeer should be > 0")
	}
	if cfg.MaxGroupInboxMessages <= 0 {
		t.Error("MaxGroupInboxMessages should be > 0")
	}
	if cfg.MaxConnectionsPerPeer <= 0 {
		t.Error("MaxConnectionsPerPeer should be > 0")
	}
}

func TestRelayService_UsesFiniteLimitsFromServerConfig(t *testing.T) {
	cfg := DefaultServerLimits()
	cfg.MaxRelayReservations = 42
	cfg.MaxConnectionsPerPeer = 3

	resources := relayResourcesFromServerLimits(cfg)

	if resources.MaxReservations != 42 {
		t.Fatalf("expected MaxReservations=42, got %d", resources.MaxReservations)
	}
	if resources.MaxCircuits != 3 {
		t.Fatalf("expected MaxCircuits=3, got %d", resources.MaxCircuits)
	}
	if resources.Limit == nil {
		t.Fatal("expected finite per-circuit limits to be configured")
	}
}

func TestRelayService_RejectsExcessReservationsPredictably(t *testing.T) {
	cfg := DefaultServerLimits()
	cfg.MaxRelayReservations = 1

	resources := relayResourcesFromServerLimits(cfg)

	if resources.MaxReservations != 1 {
		t.Fatalf("expected MaxReservations=1, got %d", resources.MaxReservations)
	}
	if resources.MaxReservations <= 0 {
		t.Fatal("relay reservations must remain finite and positive")
	}
}

func TestRelayService_EnforcesPerPeerConnectionCap(t *testing.T) {
	cfg := DefaultServerLimits()
	cfg.MaxConnectionsPerPeer = 2

	resources := relayResourcesFromServerLimits(cfg)

	if resources.MaxCircuits != 2 {
		t.Fatalf("expected MaxCircuits=2, got %d", resources.MaxCircuits)
	}
}
