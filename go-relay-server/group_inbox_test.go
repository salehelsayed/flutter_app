package main

import (
	"fmt"
	"testing"
	"time"
)

func opaqueGroupReplayEnvelope(messageID string) string {
	return fmt.Sprintf(
		`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":4,"messageId":"%s","ciphertext":"opaque-ciphertext-%s","nonce":"opaque-nonce-%s"}`,
		messageID,
		messageID,
		messageID,
	)
}

// =============================================================================
// Phase 2: Shared Relay Control State — Group Inbox Store tests
// =============================================================================

func TestGroupInboxStore_PreservesOpaqueReplayEnvelopeAcrossInstances(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 7*24*time.Hour)
	storeA := NewGroupInboxStoreWithBackend(backend)
	storeB := NewGroupInboxStoreWithBackend(backend)

	envelope1 := opaqueGroupReplayEnvelope("msg-opaque-001")
	envelope2 := opaqueGroupReplayEnvelope("msg-opaque-002")

	if err := storeA.Store("group-opaque", "peer-1", envelope1); err != nil {
		t.Fatalf("Store envelope1: %v", err)
	}
	if err := storeA.Store("group-opaque", "peer-1", envelope2); err != nil {
		t.Fatalf("Store envelope2: %v", err)
	}

	msgs := storeB.Retrieve("group-opaque", 0)
	if len(msgs) != 2 {
		t.Fatalf("expected 2 opaque replay envelopes, got %d", len(msgs))
	}
	if msgs[0].Message != envelope1 {
		t.Fatalf("first message = %q, want exact envelope %q", msgs[0].Message, envelope1)
	}
	if msgs[1].Message != envelope2 {
		t.Fatalf("second message = %q, want exact envelope %q", msgs[1].Message, envelope2)
	}
}

// TestGroupInboxStore_RetrieveBySinceTimestampAcrossInstances proves that
// messages stored through one GroupInboxStore instance are visible via
// sinceTimestamp filtering on another instance sharing the same backend.
func TestGroupInboxStore_RetrieveBySinceTimestampAcrossInstances(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 7*24*time.Hour)
	storeA := NewGroupInboxStoreWithBackend(backend)
	storeB := NewGroupInboxStoreWithBackend(backend)

	// Store first message through A.
	storeA.Store("group-1", "peer-1", "msg-old")

	// Record a timestamp boundary.
	time.Sleep(2 * time.Millisecond)
	sinceTs := time.Now().UnixMilli()
	time.Sleep(2 * time.Millisecond)

	// Store second message through A.
	storeA.Store("group-1", "peer-1", "msg-new")

	// Retrieve from B with sinceTimestamp.
	msgs := storeB.Retrieve("group-1", sinceTs)
	if len(msgs) != 1 {
		t.Fatalf("expected 1 message since timestamp from B, got %d", len(msgs))
	}
	if msgs[0].Message != "msg-new" {
		t.Fatalf("expected 'msg-new', got %q", msgs[0].Message)
	}

	// Retrieve all from B (sinceTimestamp=0).
	allMsgs := storeB.Retrieve("group-1", 0)
	if len(allMsgs) != 2 {
		t.Fatalf("expected 2 total messages from B, got %d", len(allMsgs))
	}
}

// TestGroupInboxStore_PruneUsesSharedBackendTTL proves that pruning on
// one store instance removes expired messages visible to another instance.
func TestGroupInboxStore_PruneUsesSharedBackendTTL(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 50*time.Millisecond)
	storeA := NewGroupInboxStoreWithBackend(backend)
	storeB := NewGroupInboxStoreWithBackend(backend)

	// Store through A.
	storeA.Store("group-1", "peer-1", "will expire")

	// Verify visible through B.
	msgs := storeB.Retrieve("group-1", 0)
	if len(msgs) != 1 {
		t.Fatalf("expected 1 message before TTL, got %d", len(msgs))
	}

	// Wait for TTL to expire.
	time.Sleep(100 * time.Millisecond)

	// Prune through instance A.
	storeA.Prune()

	// Verify gone from instance B.
	msgs = storeB.Retrieve("group-1", 0)
	if len(msgs) != 0 {
		t.Fatalf("expected 0 messages after TTL prune from B, got %d", len(msgs))
	}

	// Stats should be consistent.
	gA, mA := storeA.Stats()
	gB, mB := storeB.Stats()
	if gA != gB || mA != mB {
		t.Fatalf("stats mismatch: A(%d/%d) vs B(%d/%d)", gA, mA, gB, mB)
	}
}

// TestGroupInboxStore_FailoverDoesNotDuplicateMessages proves that when
// messages are stored through one instance and retrieved through another
// (simulating failover), no messages are duplicated.
func TestGroupInboxStore_FailoverDoesNotDuplicateMessages(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 7*24*time.Hour)
	storeA := NewGroupInboxStoreWithBackend(backend)
	storeB := NewGroupInboxStoreWithBackend(backend)

	// Store 3 messages through A.
	for i := 0; i < 3; i++ {
		storeA.Store("group-1", "peer-1", fmt.Sprintf("msg-%d", i))
	}

	// Retrieve all from B (simulating failover — A goes down, B takes over).
	msgs := storeB.Retrieve("group-1", 0)
	if len(msgs) != 3 {
		t.Fatalf("expected 3 messages, got %d", len(msgs))
	}

	// Verify no duplicates: messages are distinct.
	seen := make(map[string]bool)
	for _, m := range msgs {
		if seen[m.Message] {
			t.Fatalf("duplicate message detected: %q", m.Message)
		}
		seen[m.Message] = true
	}

	// Retrieve again from A — messages should still be there (non-destructive).
	msgs2 := storeA.Retrieve("group-1", 0)
	if len(msgs2) != 3 {
		t.Fatalf("expected 3 messages on second retrieve from A, got %d", len(msgs2))
	}
}

// =============================================================================
// Phase 6: Group Continuity — Exactly-Once Cursor Pagination
// =============================================================================

// TestGroupInboxStore_CursorPaginationExactOnceAcrossPages proves that
// cursor-based pagination delivers every message exactly once, even when
// paginating across multiple pages with varying page sizes.
func TestGroupInboxStore_CursorPaginationExactOnceAcrossPages(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 7*24*time.Hour)
	store := NewGroupInboxStoreWithBackend(backend)

	// Store 25 messages.
	for i := 0; i < 25; i++ {
		store.Store("group-exact", "peer-1", fmt.Sprintf("msg-%03d", i))
		time.Sleep(1 * time.Millisecond)
	}

	// Paginate with page size 7 (25 / 7 = 3 full pages + 1 partial).
	var allMessages []groupInboxMessage
	cursor := ""
	pageCount := 0
	for {
		msgs, nextCursor, _ := store.RetrieveWithCursor("group-exact", cursor, 7)
		if len(msgs) == 0 {
			break
		}
		allMessages = append(allMessages, msgs...)
		pageCount++
		if nextCursor == "" {
			break
		}
		cursor = nextCursor
	}

	// Exactly 25 messages across all pages.
	if len(allMessages) != 25 {
		t.Fatalf("expected 25 messages total, got %d (across %d pages)", len(allMessages), pageCount)
	}

	// Verify order is FIFO and no duplicates.
	seen := make(map[string]bool)
	for i, m := range allMessages {
		expected := fmt.Sprintf("msg-%03d", i)
		if m.Message != expected {
			t.Fatalf("message %d: expected %q, got %q", i, expected, m.Message)
		}
		if seen[m.ID] {
			t.Fatalf("duplicate message ID detected at position %d: %q", i, m.ID)
		}
		seen[m.ID] = true
	}

	// Re-paginating from the beginning should return the same messages.
	var secondPass []groupInboxMessage
	cursor = ""
	for {
		msgs, nextCursor, _ := store.RetrieveWithCursor("group-exact", cursor, 10)
		if len(msgs) == 0 {
			break
		}
		secondPass = append(secondPass, msgs...)
		if nextCursor == "" {
			break
		}
		cursor = nextCursor
	}

	if len(secondPass) != 25 {
		t.Fatalf("second pass: expected 25 messages, got %d", len(secondPass))
	}
	for i, m := range secondPass {
		if m.ID != allMessages[i].ID {
			t.Fatalf("second pass message %d: ID mismatch %q vs %q", i, m.ID, allMessages[i].ID)
		}
	}
}

// TestGroupInboxStore_CursorPaginationStableAcrossInstances proves that
// cursor-based pagination works across different store instances and
// delivers messages in stable order without duplication or omission.
func TestGroupInboxStore_CursorPaginationStableAcrossInstances(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 7*24*time.Hour)
	storeA := NewGroupInboxStoreWithBackend(backend)
	storeB := NewGroupInboxStoreWithBackend(backend)

	// Store 10 messages through A.
	for i := 0; i < 10; i++ {
		storeA.Store("group-1", "peer-1", fmt.Sprintf("msg-%02d", i))
		time.Sleep(1 * time.Millisecond)
	}

	// Paginate through B with page size 3.
	var allMessages []groupInboxMessage
	cursor := ""
	pageCount := 0
	for {
		msgs, nextCursor, _ := storeB.RetrieveWithCursor("group-1", cursor, 3)
		if len(msgs) == 0 {
			break
		}
		allMessages = append(allMessages, msgs...)
		pageCount++
		if nextCursor == "" {
			break
		}
		cursor = nextCursor
	}

	// Should have collected all 10 messages.
	if len(allMessages) != 10 {
		t.Fatalf("expected 10 messages total across pages, got %d", len(allMessages))
	}

	// Verify order is preserved (FIFO).
	for i, m := range allMessages {
		expected := fmt.Sprintf("msg-%02d", i)
		if m.Message != expected {
			t.Fatalf("message %d: expected %q, got %q", i, expected, m.Message)
		}
	}

	// Verify no duplicates.
	seen := make(map[string]bool)
	for _, m := range allMessages {
		if seen[m.ID] {
			t.Fatalf("duplicate message ID detected: %q", m.ID)
		}
		seen[m.ID] = true
	}
}
