package main

import (
	"fmt"
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

// =============================================================================
// Phase 2: Shared Relay Control State — 1:1 Inbox Store tests
// =============================================================================

// TestInboxStore_RetrieveExactlyOnceAcrossInstances proves that a message
// stored through inbox instance A is retrieved (and consumed) exactly once
// through inbox instance B. The destructive FIFO semantics must hold.
func TestInboxStore_RetrieveExactlyOnceAcrossInstances(t *testing.T) {
	backend := newMemoryInboxBackend()
	pushBackend := newMemoryPushTokenStore()
	pushA := NewPushServiceWithBackend(pushBackend)
	pushB := NewPushServiceWithBackend(pushBackend)
	inboxA := NewInboxStoreWithBackend(backend, pushA)
	inboxB := NewInboxStoreWithBackend(backend, pushB)

	// Store through instance A.
	inboxA.Store("peer-recipient", inboxMessage{
		From:      "peer-sender",
		Message:   "hello from A",
		Timestamp: time.Now().UnixMilli(),
	})

	// Retrieve through instance B (destructive).
	msgs := inboxB.Retrieve("peer-recipient", 50)
	if len(msgs) != 1 {
		t.Fatalf("expected 1 message from B, got %d", len(msgs))
	}
	if msgs[0].Message != "hello from A" {
		t.Fatalf("expected 'hello from A', got %q", msgs[0].Message)
	}

	// Second retrieve from either instance should return nothing.
	msgsA := inboxA.Retrieve("peer-recipient", 50)
	if len(msgsA) != 0 {
		t.Fatalf("expected 0 messages on second retrieve from A, got %d", len(msgsA))
	}
	msgsB := inboxB.Retrieve("peer-recipient", 50)
	if len(msgsB) != 0 {
		t.Fatalf("expected 0 messages on second retrieve from B, got %d", len(msgsB))
	}
}

// TestInboxStore_RegisterTokenVisibleAcrossInstances proves that a push
// token registered through one PushService instance is visible to another
// instance sharing the same PushTokenBackend.
func TestInboxStore_RegisterTokenVisibleAcrossInstances(t *testing.T) {
	pushBackend := newMemoryPushTokenStore()
	pushA := NewPushServiceWithBackend(pushBackend)
	pushB := NewPushServiceWithBackend(pushBackend)

	// Register through instance A.
	pushA.RegisterToken("peer-1", "fcm-token-abc", "ios")

	// Verify visible through instance B.
	entry := pushB.tokenBackend.LookupToken("peer-1")
	if entry == nil {
		t.Fatal("expected push B to see token registered by push A")
	}
	if entry.Token != "fcm-token-abc" {
		t.Fatalf("expected token 'fcm-token-abc', got %q", entry.Token)
	}
	if entry.Platform != "ios" {
		t.Fatalf("expected platform 'ios', got %q", entry.Platform)
	}

	// Verify count is consistent.
	if pushA.TokenCount() != pushB.TokenCount() {
		t.Fatalf("token counts should match: A=%d, B=%d",
			pushA.TokenCount(), pushB.TokenCount())
	}
}

// TestInboxStore_PushTokenSurvivesServerRestart simulates a server restart
// by creating a new PushService instance with the same backend and verifying
// that the previously registered token is still accessible.
func TestInboxStore_PushTokenSurvivesServerRestart(t *testing.T) {
	pushBackend := newMemoryPushTokenStore()

	// "Server 1" registers a token.
	push1 := NewPushServiceWithBackend(pushBackend)
	push1.RegisterToken("peer-1", "fcm-token-xyz", "android")

	// "Server 1" goes down. "Server 2" starts with the same backend.
	push2 := NewPushServiceWithBackend(pushBackend)

	// Token should survive.
	entry := push2.tokenBackend.LookupToken("peer-1")
	if entry == nil {
		t.Fatal("expected token to survive server restart")
	}
	if entry.Token != "fcm-token-xyz" {
		t.Fatalf("expected 'fcm-token-xyz', got %q", entry.Token)
	}
	if push2.TokenCount() != 1 {
		t.Fatalf("expected 1 token after restart, got %d", push2.TokenCount())
	}
}

// TestInboxStore_PaginatedRetrieveKeepsFIFOAcrossInstances proves that
// paginated retrieval (with hasMore) works correctly across instances.
// Store 5 messages through A, retrieve 2 through B (expecting hasMore=true),
// then retrieve the rest through A (expecting hasMore=false).
func TestInboxStore_PaginatedRetrieveKeepsFIFOAcrossInstances(t *testing.T) {
	backend := newMemoryInboxBackend()
	pushBackend := newMemoryPushTokenStore()
	pushA := NewPushServiceWithBackend(pushBackend)
	pushB := NewPushServiceWithBackend(pushBackend)
	inboxA := NewInboxStoreWithBackend(backend, pushA)
	inboxB := NewInboxStoreWithBackend(backend, pushB)

	// Store 5 messages through instance A.
	for i := 0; i < 5; i++ {
		inboxA.Store("peer-recipient", inboxMessage{
			From:      "peer-sender",
			Message:   fmt.Sprintf("msg-%d", i),
			Timestamp: time.Now().UnixMilli(),
		})
		time.Sleep(1 * time.Millisecond) // ensure distinct timestamps
	}

	// Retrieve first 2 through instance B.
	msgs1, hasMore1 := inboxB.RetrieveWithMeta("peer-recipient", 2)
	if len(msgs1) != 2 {
		t.Fatalf("expected 2 messages in first page, got %d", len(msgs1))
	}
	if !hasMore1 {
		t.Fatal("expected hasMore=true after retrieving 2 of 5")
	}
	if msgs1[0].Message != "msg-0" {
		t.Fatalf("expected first message 'msg-0', got %q", msgs1[0].Message)
	}
	if msgs1[1].Message != "msg-1" {
		t.Fatalf("expected second message 'msg-1', got %q", msgs1[1].Message)
	}

	// Retrieve remaining through instance A.
	msgs2, hasMore2 := inboxA.RetrieveWithMeta("peer-recipient", 50)
	if len(msgs2) != 3 {
		t.Fatalf("expected 3 remaining messages, got %d", len(msgs2))
	}
	if hasMore2 {
		t.Fatal("expected hasMore=false after retrieving all remaining")
	}
	if msgs2[0].Message != "msg-2" {
		t.Fatalf("expected continuation at 'msg-2', got %q", msgs2[0].Message)
	}
}
