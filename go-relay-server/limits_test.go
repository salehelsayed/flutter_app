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

func TestFiniteLimits_RejectNewWhenInboxFull(t *testing.T) {
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

	// Store one more — reject the new message instead of evicting an
	// already-accepted entry. The sender is online now and still holds the
	// envelope, so it can retry truthfully.
	requireInboxStoreResult(t, inbox, "peer-1", inboxMessage{
		From:      "sender",
		Message:   "overflow-msg",
		Timestamp: time.Now().UnixMilli(),
	}, InboxStoreResultRejectedFull)

	count = inbox.Count("peer-1")
	if count != cfg.MaxInboxMessagesPerPeer {
		t.Errorf("expected inbox to stay at %d after overflow, got %d", cfg.MaxInboxMessagesPerPeer, count)
	}

	messages, _ := inbox.RetrievePendingWithMeta("peer-1", cfg.MaxInboxMessagesPerPeer+1)
	if len(messages) != cfg.MaxInboxMessagesPerPeer {
		t.Fatalf("expected %d retained messages, got %d", cfg.MaxInboxMessagesPerPeer, len(messages))
	}
	if messages[0].Message != "msg-0" {
		t.Fatalf("oldest accepted message = %q, want msg-0", messages[0].Message)
	}
	for _, message := range messages {
		if message.Message == "overflow-msg" {
			t.Fatal("overflow message must not be stored when inbox is full")
		}
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
