package main

import (
	"fmt"
	"testing"
	"time"
)

// =============================================================================
// Phase 2: Shared Relay Control State — Failover Integration Tests
//
// These tests boot two relay server "instances" (represented by separate
// store objects) sharing the same backend, and verify that state written
// through instance A is readable through instance B.
// =============================================================================

// relayPair holds two sets of stores backed by the same shared state.
type relayPair struct {
	rzA         *RendezvousStore
	rzB         *RendezvousStore
	inboxA      *InboxStore
	inboxB      *InboxStore
	groupInboxA *GroupInboxStore
	groupInboxB *GroupInboxStore
	pushA       *PushService
	pushB       *PushService
}

func newRelayPair() *relayPair {
	rzBackend := newMemoryRendezvousBackend()
	inboxBackend := newMemoryInboxBackend()
	groupInboxBackend := newMemoryGroupInboxBackend(maxMessagesPerGroup, groupMessageTTL)
	pushBackend := newMemoryPushTokenStore()

	return &relayPair{
		rzA:         NewRendezvousStoreWithBackend(rzBackend),
		rzB:         NewRendezvousStoreWithBackend(rzBackend),
		inboxA:      NewInboxStoreWithBackend(inboxBackend, NewPushServiceWithBackend(pushBackend)),
		inboxB:      NewInboxStoreWithBackend(inboxBackend, NewPushServiceWithBackend(pushBackend)),
		groupInboxA: NewGroupInboxStoreWithBackend(groupInboxBackend),
		groupInboxB: NewGroupInboxStoreWithBackend(groupInboxBackend),
		pushA:       NewPushServiceWithBackend(pushBackend),
		pushB:       NewPushServiceWithBackend(pushBackend),
	}
}

// --- Rendezvous failover ---

// TestTwoRelayServers_SharedRendezvousBackend proves that peer registration
// through relay A is discoverable through relay B, and vice versa.
func TestTwoRelayServers_SharedRendezvousBackend(t *testing.T) {
	rp := newRelayPair()

	// Register peer through relay A.
	rp.rzA.Register("ns1", "peer-1", []byte("record-from-A"), 3600)

	// Register another peer through relay B.
	rp.rzB.Register("ns1", "peer-2", []byte("record-from-B"), 3600)

	// Discover through relay A — should see peer-2 (registered on B).
	results := rp.rzA.Discover("ns1", "peer-1", 10)
	if len(results) != 1 {
		t.Fatalf("expected 1 result from A (peer-2), got %d", len(results))
	}
	if string(results[0].SignedPeerRecord) != "record-from-B" {
		t.Fatalf("expected record-from-B, got %s", results[0].SignedPeerRecord)
	}

	// Discover through relay B — should see peer-1 (registered on A).
	results = rp.rzB.Discover("ns1", "peer-2", 10)
	if len(results) != 1 {
		t.Fatalf("expected 1 result from B (peer-1), got %d", len(results))
	}
	if string(results[0].SignedPeerRecord) != "record-from-A" {
		t.Fatalf("expected record-from-A, got %s", results[0].SignedPeerRecord)
	}

	// Stats should be consistent across both instances.
	nsA, peersA := rp.rzA.Stats()
	nsB, peersB := rp.rzB.Stats()
	if nsA != nsB || peersA != peersB {
		t.Fatalf("stats mismatch: A(%d/%d) vs B(%d/%d)", nsA, peersA, nsB, peersB)
	}
	if nsA != 1 || peersA != 2 {
		t.Fatalf("expected 1 namespace, 2 peers, got %d/%d", nsA, peersA)
	}

	// Unregister through A, verify B sees it.
	rp.rzA.Unregister("ns1", "peer-1")
	results = rp.rzB.Discover("ns1", "requester", 10)
	if len(results) != 1 {
		t.Fatalf("expected 1 result after unregister, got %d", len(results))
	}
}

// --- Inbox failover ---

// TestTwoRelayServers_SharedInboxBackend proves that messages stored through
// relay A can be retrieved (exactly once) through relay B.
func TestTwoRelayServers_SharedInboxBackend(t *testing.T) {
	rp := newRelayPair()

	// Store message through relay A.
	rp.inboxA.Store("peer-recipient", inboxMessage{
		From:      "peer-sender",
		Message:   "hello via relay A",
		Timestamp: time.Now().UnixMilli(),
	})

	// Verify count visible through B.
	if count := rp.inboxB.Count("peer-recipient"); count != 1 {
		t.Fatalf("expected count=1 from B, got %d", count)
	}

	// Retrieve through relay B (destructive).
	msgs := rp.inboxB.Retrieve("peer-recipient", 50)
	if len(msgs) != 1 {
		t.Fatalf("expected 1 message from B, got %d", len(msgs))
	}
	if msgs[0].Message != "hello via relay A" {
		t.Fatalf("expected 'hello via relay A', got %q", msgs[0].Message)
	}

	// Verify consumed (gone from both).
	if count := rp.inboxA.Count("peer-recipient"); count != 0 {
		t.Fatalf("expected count=0 from A after retrieval, got %d", count)
	}
}

// --- Group inbox failover ---

// TestTwoRelayServers_SharedGroupInboxBackend proves that group messages
// stored through relay A are visible (non-destructive) through relay B.
func TestTwoRelayServers_SharedGroupInboxBackend(t *testing.T) {
	rp := newRelayPair()

	// Store messages through relay A.
	rp.groupInboxA.Store("group-1", "peer-1", "msg-1")
	rp.groupInboxA.Store("group-1", "peer-2", "msg-2")

	// Retrieve through relay B.
	msgs := rp.groupInboxB.Retrieve("group-1", 0)
	if len(msgs) != 2 {
		t.Fatalf("expected 2 messages from B, got %d", len(msgs))
	}

	// Messages should still be there (non-destructive).
	msgs2 := rp.groupInboxA.Retrieve("group-1", 0)
	if len(msgs2) != 2 {
		t.Fatalf("expected 2 messages still from A, got %d", len(msgs2))
	}

	// Stats should match.
	gA, mA := rp.groupInboxA.Stats()
	gB, mB := rp.groupInboxB.Stats()
	if gA != gB || mA != mB {
		t.Fatalf("stats mismatch: A(%d/%d) vs B(%d/%d)", gA, mA, gB, mB)
	}
}

// --- Inbox pagination continuation across relays ---

// TestTwoRelayServers_SharedInboxPaginationContinuation proves that
// paginated inbox retrieval can continue across relay instances.
// Start retrieval on relay A, continue on relay B.
func TestTwoRelayServers_SharedInboxPaginationContinuation(t *testing.T) {
	rp := newRelayPair()

	// Store 6 messages.
	for i := 0; i < 6; i++ {
		rp.inboxA.Store("peer-recipient", inboxMessage{
			From:      "peer-sender",
			Message:   fmt.Sprintf("msg-%d", i),
			Timestamp: time.Now().UnixMilli(),
		})
		time.Sleep(1 * time.Millisecond)
	}

	// First page of 2 through relay A.
	msgs1, hasMore1 := rp.inboxA.RetrieveWithMeta("peer-recipient", 2)
	if len(msgs1) != 2 {
		t.Fatalf("expected 2 in first page, got %d", len(msgs1))
	}
	if !hasMore1 {
		t.Fatal("expected hasMore=true after page 1")
	}
	if msgs1[0].Message != "msg-0" || msgs1[1].Message != "msg-1" {
		t.Fatalf("unexpected page 1 content: %q, %q", msgs1[0].Message, msgs1[1].Message)
	}

	// "Relay A goes down." Continue through relay B.
	msgs2, hasMore2 := rp.inboxB.RetrieveWithMeta("peer-recipient", 2)
	if len(msgs2) != 2 {
		t.Fatalf("expected 2 in second page (from B), got %d", len(msgs2))
	}
	if !hasMore2 {
		t.Fatal("expected hasMore=true after page 2")
	}
	if msgs2[0].Message != "msg-2" || msgs2[1].Message != "msg-3" {
		t.Fatalf("unexpected page 2 content: %q, %q", msgs2[0].Message, msgs2[1].Message)
	}

	// Final page through relay B.
	msgs3, hasMore3 := rp.inboxB.RetrieveWithMeta("peer-recipient", 50)
	if len(msgs3) != 2 {
		t.Fatalf("expected 2 in final page, got %d", len(msgs3))
	}
	if hasMore3 {
		t.Fatal("expected hasMore=false in final page")
	}
	if msgs3[0].Message != "msg-4" || msgs3[1].Message != "msg-5" {
		t.Fatalf("unexpected final page content: %q, %q", msgs3[0].Message, msgs3[1].Message)
	}
}

// --- Group inbox cursor continuation across relays ---

// TestTwoRelayServers_SharedGroupCursorContinuation proves that cursor-based
// group inbox pagination can continue across relay instances without
// duplication or omission.
func TestTwoRelayServers_SharedGroupCursorContinuation(t *testing.T) {
	rp := newRelayPair()

	// Store 8 messages through relay A.
	for i := 0; i < 8; i++ {
		rp.groupInboxA.Store("group-1", "peer-1", fmt.Sprintf("msg-%02d", i))
		time.Sleep(1 * time.Millisecond)
	}

	// First page of 3 through relay A.
	msgs1, cursor1, _ := rp.groupInboxA.RetrieveWithCursor("group-1", "", 3)
	if len(msgs1) != 3 {
		t.Fatalf("expected 3 in first page, got %d", len(msgs1))
	}
	if cursor1 == "" {
		t.Fatal("expected non-empty cursor after first page")
	}
	if msgs1[0].Message != "msg-00" || msgs1[2].Message != "msg-02" {
		t.Fatalf("unexpected first page: [0]=%q [2]=%q", msgs1[0].Message, msgs1[2].Message)
	}

	// "Relay A goes down." Continue through relay B using cursor from A.
	msgs2, cursor2, _ := rp.groupInboxB.RetrieveWithCursor("group-1", cursor1, 3)
	if len(msgs2) != 3 {
		t.Fatalf("expected 3 in second page (from B), got %d", len(msgs2))
	}
	if msgs2[0].Message != "msg-03" || msgs2[2].Message != "msg-05" {
		t.Fatalf("unexpected second page: [0]=%q [2]=%q", msgs2[0].Message, msgs2[2].Message)
	}

	// Final page through relay B.
	msgs3, cursor3, _ := rp.groupInboxB.RetrieveWithCursor("group-1", cursor2, 3)
	if len(msgs3) != 2 {
		t.Fatalf("expected 2 in final page, got %d", len(msgs3))
	}
	if cursor3 != "" {
		t.Fatalf("expected empty cursor for final page, got %q", cursor3)
	}
	if msgs3[0].Message != "msg-06" || msgs3[1].Message != "msg-07" {
		t.Fatalf("unexpected final page: [0]=%q [1]=%q", msgs3[0].Message, msgs3[1].Message)
	}

	// Verify total: no duplicates, no omissions.
	allMsgs := append(append(msgs1, msgs2...), msgs3...)
	if len(allMsgs) != 8 {
		t.Fatalf("expected 8 total messages, got %d", len(allMsgs))
	}
	seen := make(map[string]bool)
	for _, m := range allMsgs {
		if seen[m.Message] {
			t.Fatalf("duplicate message: %q", m.Message)
		}
		seen[m.Message] = true
	}
}
