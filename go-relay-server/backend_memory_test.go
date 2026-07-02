package main

import (
	"fmt"
	"testing"
	"time"
)

// TC-02 (plan 173) — the PRODUCTION in-memory 1:1 inbox backend evicts the
// OLDEST message at cap and returns Stored (build-106 contract, NET-REL-07).
// The 2026-06-28 regression inverted this to reject-the-newest, which shipped
// clients (no INBOX_FULL branch) experience as silent sender-side loss.
func TestMemoryInbox_StoreAtCapEvictsOldestReturnsStored(t *testing.T) {
	backend := newMemoryInboxBackend()

	entry := func(i int) inboxMessage {
		return inboxMessage{
			From:      "sender",
			Message:   fmt.Sprintf(`{"type":"chat_message","version":"2","id":"m-%d","text":"x"}`, i),
			Timestamp: time.Now().UnixMilli(),
		}
	}

	for i := 0; i < maxMessagesPerPeer; i++ {
		result, err := backend.Store("peer-1", entry(i))
		if err != nil {
			t.Fatalf("store %d: unexpected error: %v", i, err)
		}
		if result != InboxStoreResultStored {
			t.Fatalf("store %d result = %q, want %q", i, result, InboxStoreResultStored)
		}
	}

	// The at-cap store must evict m-0 and store the newest, NOT reject it.
	result, err := backend.Store("peer-1", entry(maxMessagesPerPeer))
	if err != nil {
		t.Fatalf("at-cap store: unexpected error: %v", err)
	}
	if result != InboxStoreResultStored {
		t.Fatalf("at-cap store result = %q, want %q (evict-oldest, build-106 contract)",
			result, InboxStoreResultStored)
	}

	if count := backend.Count("peer-1"); count != maxMessagesPerPeer {
		t.Fatalf("count after at-cap store = %d, want %d", count, maxMessagesPerPeer)
	}

	messages, _ := backend.RetrievePending("peer-1", 1)
	if len(messages) != 1 {
		t.Fatalf("expected 1 pending head message, got %d", len(messages))
	}
	if got, want := extractMessageId(messages[0].Message), "m-1"; got != want {
		t.Fatalf("oldest pending message id = %q, want %q (m-0 must be evicted)", got, want)
	}

	// The evicted message's id must be pruned from the dedup set: re-storing
	// the SAME id as the evicted m-0 is a fresh store, not a duplicate.
	result, err = backend.Store("peer-1", entry(0))
	if err != nil {
		t.Fatalf("re-store evicted id: unexpected error: %v", err)
	}
	if result != InboxStoreResultStored {
		t.Fatalf("re-store evicted id result = %q, want %q (dedup set must drop evicted ids)",
			result, InboxStoreResultStored)
	}
}
