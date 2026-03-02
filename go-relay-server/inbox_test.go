package main

import (
	"testing"
	"time"
)

// --- TestGroupInboxStore_Basic ---

func TestGroupInboxStore_Basic(t *testing.T) {
	store := NewGroupInboxStore(500, 7*24*time.Hour)

	err := store.Store("group-1", "peer-1", `{"text":"hello"}`)
	if err != nil {
		t.Fatalf("Store() error: %v", err)
	}

	msgs := store.Retrieve("group-1", 0)
	if len(msgs) != 1 {
		t.Fatalf("expected 1 message, got %d", len(msgs))
	}
	if msgs[0].Message != `{"text":"hello"}` {
		t.Errorf("message = %q, want %q", msgs[0].Message, `{"text":"hello"}`)
	}
	if msgs[0].From != "peer-1" {
		t.Errorf("from = %q, want %q", msgs[0].From, "peer-1")
	}
	if msgs[0].Timestamp <= 0 {
		t.Error("timestamp should be positive")
	}
}

// --- TestGroupInboxStore_MultipleMessages ---

func TestGroupInboxStore_MultipleMessages(t *testing.T) {
	store := NewGroupInboxStore(500, 7*24*time.Hour)

	for i := 0; i < 5; i++ {
		err := store.Store("group-1", "peer-1", "msg")
		if err != nil {
			t.Fatalf("Store() error: %v", err)
		}
	}

	msgs := store.Retrieve("group-1", 0)
	if len(msgs) != 5 {
		t.Fatalf("expected 5 messages, got %d", len(msgs))
	}
}

// --- TestGroupInboxStore_RetrieveSinceTimestamp ---

func TestGroupInboxStore_RetrieveSinceTimestamp(t *testing.T) {
	store := NewGroupInboxStore(500, 7*24*time.Hour)

	// Store first message.
	err := store.Store("group-1", "peer-1", "old message")
	if err != nil {
		t.Fatalf("Store() error: %v", err)
	}

	// Record timestamp after first message.
	time.Sleep(2 * time.Millisecond)
	sinceTs := time.Now().UnixMilli()
	time.Sleep(2 * time.Millisecond)

	// Store second message.
	err = store.Store("group-1", "peer-1", "new message")
	if err != nil {
		t.Fatalf("Store() error: %v", err)
	}

	msgs := store.Retrieve("group-1", sinceTs)
	if len(msgs) != 1 {
		t.Fatalf("expected 1 message since timestamp, got %d", len(msgs))
	}
	if msgs[0].Message != "new message" {
		t.Errorf("message = %q, want %q", msgs[0].Message, "new message")
	}
}

// --- TestGroupInboxStore_NotDeletedOnRetrieve ---

func TestGroupInboxStore_NotDeletedOnRetrieve(t *testing.T) {
	store := NewGroupInboxStore(500, 7*24*time.Hour)

	err := store.Store("group-1", "peer-1", "persistent message")
	if err != nil {
		t.Fatalf("Store() error: %v", err)
	}

	// Retrieve once.
	msgs1 := store.Retrieve("group-1", 0)
	if len(msgs1) != 1 {
		t.Fatalf("first retrieve: expected 1 message, got %d", len(msgs1))
	}

	// Retrieve again — messages should still be there.
	msgs2 := store.Retrieve("group-1", 0)
	if len(msgs2) != 1 {
		t.Fatalf("second retrieve: expected 1 message, got %d (messages were deleted on retrieve)", len(msgs2))
	}
}

// --- TestGroupInboxStore_CapEnforcement ---

func TestGroupInboxStore_CapEnforcement(t *testing.T) {
	maxPerGroup := 5
	store := NewGroupInboxStore(maxPerGroup, 7*24*time.Hour)

	// Store maxPerGroup + 3 messages.
	for i := 0; i < maxPerGroup+3; i++ {
		err := store.Store("group-1", "peer-1", "msg")
		if err != nil {
			t.Fatalf("Store() error at i=%d: %v", i, err)
		}
	}

	msgs := store.Retrieve("group-1", 0)
	if len(msgs) != maxPerGroup {
		t.Fatalf("expected %d messages (capped), got %d", maxPerGroup, len(msgs))
	}
}

// --- TestGroupInboxStore_TTLPruning ---

func TestGroupInboxStore_TTLPruning(t *testing.T) {
	// Use a very short TTL for testing.
	store := NewGroupInboxStore(500, 50*time.Millisecond)

	err := store.Store("group-1", "peer-1", "will expire")
	if err != nil {
		t.Fatalf("Store() error: %v", err)
	}

	// Verify it's there initially.
	msgs := store.Retrieve("group-1", 0)
	if len(msgs) != 1 {
		t.Fatalf("expected 1 message before TTL, got %d", len(msgs))
	}

	// Wait for TTL to expire.
	time.Sleep(100 * time.Millisecond)

	// Prune should remove expired messages.
	store.Prune()

	msgs = store.Retrieve("group-1", 0)
	if len(msgs) != 0 {
		t.Fatalf("expected 0 messages after TTL prune, got %d", len(msgs))
	}
}

// --- TestGroupInboxStore_Stats ---

func TestGroupInboxStore_Stats(t *testing.T) {
	store := NewGroupInboxStore(500, 7*24*time.Hour)

	// Empty store.
	groups, totalMsgs := store.Stats()
	if groups != 0 || totalMsgs != 0 {
		t.Errorf("empty store: groups=%d, msgs=%d, want 0, 0", groups, totalMsgs)
	}

	// Add some messages to different groups.
	store.Store("group-1", "peer-1", "msg1")
	store.Store("group-1", "peer-1", "msg2")
	store.Store("group-2", "peer-1", "msg3")

	groups, totalMsgs = store.Stats()
	if groups != 2 {
		t.Errorf("groups = %d, want 2", groups)
	}
	if totalMsgs != 3 {
		t.Errorf("totalMsgs = %d, want 3", totalMsgs)
	}
}

// --- TestGroupInboxStore_EmptyGroup ---

func TestGroupInboxStore_EmptyGroup(t *testing.T) {
	store := NewGroupInboxStore(500, 7*24*time.Hour)

	msgs := store.Retrieve("nonexistent-group", 0)
	if len(msgs) != 0 {
		t.Fatalf("expected 0 messages for empty group, got %d", len(msgs))
	}
}

// --- TestGroupInboxStore_MultipleGroups ---

func TestGroupInboxStore_MultipleGroups(t *testing.T) {
	store := NewGroupInboxStore(500, 7*24*time.Hour)

	store.Store("group-A", "peer-1", "msg-A1")
	store.Store("group-A", "peer-1", "msg-A2")
	store.Store("group-B", "peer-2", "msg-B1")

	msgsA := store.Retrieve("group-A", 0)
	if len(msgsA) != 2 {
		t.Fatalf("group-A: expected 2 messages, got %d", len(msgsA))
	}

	msgsB := store.Retrieve("group-B", 0)
	if len(msgsB) != 1 {
		t.Fatalf("group-B: expected 1 message, got %d", len(msgsB))
	}

	// Verify isolation: group A messages are only in group A.
	if msgsA[0].Message != "msg-A1" {
		t.Errorf("group-A[0] = %q, want %q", msgsA[0].Message, "msg-A1")
	}
	if msgsA[1].Message != "msg-A2" {
		t.Errorf("group-A[1] = %q, want %q", msgsA[1].Message, "msg-A2")
	}
	if msgsB[0].Message != "msg-B1" {
		t.Errorf("group-B[0] = %q, want %q", msgsB[0].Message, "msg-B1")
	}
}
