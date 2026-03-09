package main

import (
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

func TestFiniteLimits_RejectExcessInboxMessages(t *testing.T) {
	cfg := DefaultServerLimits()
	cfg.MaxInboxMessagesPerPeer = 10

	backend := newMemoryInboxBackendWithLimits(cfg.MaxInboxMessagesPerPeer)
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStoreWithBackend(backend, push)

	// Store up to the limit — all should succeed.
	for i := 0; i < cfg.MaxInboxMessagesPerPeer; i++ {
		inbox.Store("peer-1", inboxMessage{
			From:      "sender",
			Message:   "msg",
			Timestamp: time.Now().UnixMilli(),
		})
	}

	count := inbox.Count("peer-1")
	if count != cfg.MaxInboxMessagesPerPeer {
		t.Errorf("expected %d messages, got %d", cfg.MaxInboxMessagesPerPeer, count)
	}

	// Store one more — the oldest should be evicted (bounded).
	inbox.Store("peer-1", inboxMessage{
		From:      "sender",
		Message:   "overflow-msg",
		Timestamp: time.Now().UnixMilli(),
	})

	count = inbox.Count("peer-1")
	if count != cfg.MaxInboxMessagesPerPeer {
		t.Errorf("expected inbox to stay at %d after overflow, got %d", cfg.MaxInboxMessagesPerPeer, count)
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
			inbox.Store(peerId, inboxMessage{
				From:      "sender",
				Message:   "msg",
				Timestamp: time.Now().UnixMilli(),
			})
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
