package main

import (
	"fmt"
	"reflect"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

func newTestRedisClient(t *testing.T, server *miniredis.Miniredis) *redis.Client {
	t.Helper()

	client, err := newRedisClientFromURL("redis://" + server.Addr())
	if err != nil {
		t.Fatalf("newRedisClientFromURL() error: %v", err)
	}
	t.Cleanup(func() {
		_ = client.Close()
	})
	return client
}

func requireRedisInboxStoreResult(
	t *testing.T,
	backend *redisInboxBackend,
	toPeerId string,
	message inboxMessage,
	want InboxStoreResult,
) {
	t.Helper()

	got, err := backend.Store(toPeerId, message)
	if err != nil {
		t.Fatalf("Store() error: %v", err)
	}
	if got != want {
		t.Fatalf("Store() result = %q, want %q", got, want)
	}
}

func TestGIRD004RedisGroupInboxDuplicateMessageIDStoresOneRowAcrossClients(t *testing.T) {
	server := miniredis.RunT(t)

	backendA := newRedisGroupInboxBackend(newTestRedisClient(t, server), "gird004:", 500, 7*24*time.Hour)
	backendB := newRedisGroupInboxBackend(newTestRedisClient(t, server), "gird004:", 500, 7*24*time.Hour)
	groupID := "group-gird004-redis-duplicate"
	message := opaqueGroupReplayEnvelope("gird004-redis-duplicate")

	if _, err := backendA.StoreWithRecipients(groupID, "peer-a", message, []string{"peer-b"}); err != nil {
		t.Fatalf("first StoreWithRecipients: %v", err)
	}
	if _, err := backendB.StoreWithRecipients(groupID, "peer-a", message, []string{"peer-b"}); err != nil {
		t.Fatalf("duplicate StoreWithRecipients: %v", err)
	}

	messages := backendA.RetrieveSince(groupID, 0)
	if len(messages) != 1 {
		t.Fatalf("RetrieveSince returned %d message(s), want 1: %#v", len(messages), messages)
	}
	cursorPage, nextCursor, historyGaps := backendB.RetrieveCursor(groupID, "", 50)
	if len(cursorPage) != 1 || nextCursor != "" || len(historyGaps) != 0 {
		t.Fatalf("RetrieveCursor = (%d, %q, %#v), want one row/no cursor/no gaps", len(cursorPage), nextCursor, historyGaps)
	}
	groups, total := backendB.Stats()
	if groups != 1 || total != 1 {
		t.Fatalf("Stats = (%d, %d), want (1, 1)", groups, total)
	}
}

func TestGIRD004RedisGroupInboxMalformedAndUnkeyedMessagesStoreTwice(t *testing.T) {
	server := miniredis.RunT(t)
	backendA := newRedisGroupInboxBackend(newTestRedisClient(t, server), "gird004:", 500, 7*24*time.Hour)
	backendB := newRedisGroupInboxBackend(newTestRedisClient(t, server), "gird004:", 500, 7*24*time.Hour)

	tests := []struct {
		name    string
		groupID string
		message string
	}{
		{name: "malformed", groupID: "group-gird004-redis-malformed", message: `{"messageId":`},
		{name: "unkeyed", groupID: "group-gird004-redis-unkeyed", message: `{"kind":"group_offline_replay","ciphertext":"c","nonce":"n"}`},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := backendA.StoreWithRecipients(tc.groupID, "peer-a", tc.message, []string{"peer-b"}); err != nil {
				t.Fatalf("first StoreWithRecipients: %v", err)
			}
			if _, err := backendB.StoreWithRecipients(tc.groupID, "peer-a", tc.message, []string{"peer-b"}); err != nil {
				t.Fatalf("second StoreWithRecipients: %v", err)
			}
			messages := backendA.RetrieveSince(tc.groupID, 0)
			if len(messages) != 2 {
				t.Fatalf("messages = %d, want 2 for %s input", len(messages), tc.name)
			}
		})
	}
}

func TestGIRD004RedisGroupInboxDistinctMessageIDsPreserveOrder(t *testing.T) {
	server := miniredis.RunT(t)
	backendA := newRedisGroupInboxBackend(newTestRedisClient(t, server), "gird004:", 500, 7*24*time.Hour)
	backendB := newRedisGroupInboxBackend(newTestRedisClient(t, server), "gird004:", 500, 7*24*time.Hour)
	groupID := "group-gird004-redis-distinct"
	first := opaqueGroupReplayEnvelope("gird004-redis-distinct-1")
	second := opaqueGroupReplayEnvelope("gird004-redis-distinct-2")

	if _, err := backendA.StoreWithRecipients(groupID, "peer-a", first, []string{"peer-b"}); err != nil {
		t.Fatalf("first StoreWithRecipients: %v", err)
	}
	if _, err := backendB.StoreWithRecipients(groupID, "peer-a", second, []string{"peer-b"}); err != nil {
		t.Fatalf("second StoreWithRecipients: %v", err)
	}

	messages := backendA.RetrieveSince(groupID, 0)
	if len(messages) != 2 {
		t.Fatalf("messages = %d, want 2", len(messages))
	}
	if messages[0].Message != first || messages[1].Message != second {
		t.Fatalf("messages out of order: %#v", messages)
	}
}

func TestGIRD004RedisGroupInboxConflictingSameMessageIDRejected(t *testing.T) {
	tests := []struct {
		name               string
		groupID            string
		firstFrom          string
		firstMessage       string
		conflictingFrom    string
		conflictingMessage string
	}{
		{
			name:               "different sender",
			groupID:            "group-gird004-redis-conflict-sender",
			firstFrom:          "peer-a",
			firstMessage:       opaqueGroupReplayEnvelope("gird004-redis-conflict-sender"),
			conflictingFrom:    "peer-x",
			conflictingMessage: opaqueGroupReplayEnvelope("gird004-redis-conflict-sender"),
		},
		{
			name:               "different body",
			groupID:            "group-gird004-redis-conflict-body",
			firstFrom:          "peer-a",
			firstMessage:       `{"kind":"group_offline_replay","messageId":"gird004-redis-conflict-body","ciphertext":"first","nonce":"n1"}`,
			conflictingFrom:    "peer-a",
			conflictingMessage: `{"kind":"group_offline_replay","messageId":"gird004-redis-conflict-body","ciphertext":"second","nonce":"n2"}`,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			server := miniredis.RunT(t)
			backendA := newRedisGroupInboxBackend(newTestRedisClient(t, server), "gird004:", 500, 7*24*time.Hour)
			backendB := newRedisGroupInboxBackend(newTestRedisClient(t, server), "gird004:", 500, 7*24*time.Hour)

			if _, err := backendA.StoreWithRecipients(tc.groupID, tc.firstFrom, tc.firstMessage, []string{"peer-b"}); err != nil {
				t.Fatalf("first StoreWithRecipients: %v", err)
			}
			if _, err := backendB.StoreWithRecipients(tc.groupID, tc.conflictingFrom, tc.conflictingMessage, []string{"peer-b"}); err == nil {
				t.Fatal("expected conflicting duplicate messageId to be rejected")
			}
			messages := backendA.RetrieveSince(tc.groupID, 0)
			if len(messages) != 1 || messages[0].From != tc.firstFrom || messages[0].Message != tc.firstMessage {
				t.Fatalf("canonical row not preserved: %#v", messages)
			}
		})
	}
}

func TestGIRD004RedisGroupInboxDuplicateExpandedRecipientACLMerges(t *testing.T) {
	server := miniredis.RunT(t)
	backendA := newRedisGroupInboxBackend(newTestRedisClient(t, server), "gird004:", 500, 7*24*time.Hour)
	backendB := newRedisGroupInboxBackend(newTestRedisClient(t, server), "gird004:", 500, 7*24*time.Hour)
	groupID := "group-gird004-redis-acl-merge"
	message := opaqueGroupReplayEnvelope("gird004-redis-acl-merge")

	if _, err := backendA.StoreWithRecipients(groupID, "peer-a", message, []string{"peer-b"}); err != nil {
		t.Fatalf("first StoreWithRecipients: %v", err)
	}
	if _, err := backendB.StoreWithRecipients(groupID, "peer-a", message, []string{"peer-b", "peer-c"}); err != nil {
		t.Fatalf("duplicate expanded StoreWithRecipients: %v", err)
	}

	messages := backendA.RetrieveSince(groupID, 0)
	if len(messages) != 1 {
		t.Fatalf("messages = %d, want one canonical row", len(messages))
	}
	wantRecipients := []string{"peer-b", "peer-c"}
	if !reflect.DeepEqual(messages[0].RecipientPeerIds, wantRecipients) {
		t.Fatalf("RecipientPeerIds = %#v, want %#v", messages[0].RecipientPeerIds, wantRecipients)
	}
}

func TestRedisRendezvousBackend_RefreshesTTLAndSharesAcrossClients(t *testing.T) {
	server := miniredis.RunT(t)

	backendA := newRedisRendezvousBackend(newTestRedisClient(t, server), "phase2:")
	backendB := newRedisRendezvousBackend(newTestRedisClient(t, server), "phase2:")

	backendA.Register("ns-1", "peer-1", []byte("record-1"), 1)
	server.FastForward(500 * time.Millisecond)

	backendA.Register("ns-1", "peer-1", []byte("record-1"), 3)
	server.FastForward(1500 * time.Millisecond)

	results := backendB.Discover("ns-1", "other-peer", 10)
	if len(results) != 1 {
		t.Fatalf("expected refreshed registration to remain discoverable, got %d result(s)", len(results))
	}
	if string(results[0].SignedPeerRecord) != "record-1" {
		t.Fatalf("expected record-1, got %q", string(results[0].SignedPeerRecord))
	}

	server.FastForward(2 * time.Second)

	results = backendB.Discover("ns-1", "other-peer", 10)
	if len(results) != 0 {
		t.Fatalf("expected registration to expire after refreshed TTL, got %d result(s)", len(results))
	}
}

func TestRedisInboxBackend_RetrieveOnceAcrossClients(t *testing.T) {
	server := miniredis.RunT(t)

	maxPerPeer := DefaultServerLimits().MaxInboxMessagesPerPeer
	backendA := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", maxPerPeer)
	backendB := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", maxPerPeer)

	requireRedisInboxStoreResult(t, backendA, "peer-recipient", inboxMessage{
		From:      "peer-sender",
		Message:   "expired",
		Timestamp: time.Now().Add(-maxMessageAge - time.Hour).UnixMilli(),
	}, InboxStoreResultStored)
	for i := 0; i < 4; i++ {
		requireRedisInboxStoreResult(t, backendA, "peer-recipient", inboxMessage{
			From:      "peer-sender",
			Message:   fmt.Sprintf("msg-%d", i),
			Timestamp: time.Now().UnixMilli(),
		}, InboxStoreResultStored)
	}

	page1, hasMore1 := backendB.Retrieve("peer-recipient", 2)
	if len(page1) != 2 {
		t.Fatalf("expected first page of 2 messages, got %d", len(page1))
	}
	if !hasMore1 {
		t.Fatal("expected hasMore=true after first page")
	}
	if page1[0].Message != "msg-0" || page1[1].Message != "msg-1" {
		t.Fatalf("unexpected first page: %q, %q", page1[0].Message, page1[1].Message)
	}

	page2, hasMore2 := backendA.Retrieve("peer-recipient", 10)
	if len(page2) != 2 {
		t.Fatalf("expected second page of 2 messages, got %d", len(page2))
	}
	if hasMore2 {
		t.Fatal("expected hasMore=false after second page")
	}
	if page2[0].Message != "msg-2" || page2[1].Message != "msg-3" {
		t.Fatalf("unexpected second page: %q, %q", page2[0].Message, page2[1].Message)
	}

	final, hasMoreFinal := backendB.Retrieve("peer-recipient", 10)
	if len(final) != 0 || hasMoreFinal {
		t.Fatalf("expected inbox to be empty after destructive retrieval, got %d message(s), hasMore=%v", len(final), hasMoreFinal)
	}
}

func TestRedisInboxBackend_DedupesByMessageIDAcrossClients(t *testing.T) {
	server := miniredis.RunT(t)

	maxPerPeer := DefaultServerLimits().MaxInboxMessagesPerPeer
	backendA := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", maxPerPeer)
	backendB := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", maxPerPeer)

	entry := inboxMessage{
		From:      "peer-sender",
		Message:   `{"type":"chat_message","version":"2","id":"msg-dedup-redis-001","text":"hello"}`,
		Timestamp: time.Now().UnixMilli(),
	}

	result, err := backendA.Store("peer-recipient", entry)
	if err != nil {
		t.Fatalf("first Store() error: %v", err)
	}
	if result != InboxStoreResultStored {
		t.Fatalf("first Store() result = %q, want %q", result, InboxStoreResultStored)
	}

	result, err = backendB.Store("peer-recipient", entry)
	if err != nil {
		t.Fatalf("duplicate Store() error: %v", err)
	}
	if result != InboxStoreResultDuplicate {
		t.Fatalf("duplicate Store() result = %q, want %q", result, InboxStoreResultDuplicate)
	}
	if count := backendA.Count("peer-recipient"); count != 1 {
		t.Fatalf("expected 1 message after duplicate store, got %d", count)
	}
}

func TestRedisInboxBackend_DedupesByMessageIDPerRecipient(t *testing.T) {
	server := miniredis.RunT(t)

	maxPerPeer := DefaultServerLimits().MaxInboxMessagesPerPeer
	backendA := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", maxPerPeer)
	backendB := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", maxPerPeer)

	entry := inboxMessage{
		From:      "peer-sender",
		Message:   `{"type":"introduction","version":"2","messageId":"intro-shared::send::peer-A","senderPeerId":"peer-A","encrypted":{"kem":"...","ciphertext":"...","nonce":"..."}}`,
		Timestamp: time.Now().UnixMilli(),
	}

	requireRedisInboxStoreResult(
		t,
		backendA,
		"recipient-A",
		entry,
		InboxStoreResultStored,
	)
	requireRedisInboxStoreResult(
		t,
		backendB,
		"recipient-B",
		entry,
		InboxStoreResultStored,
	)

	if count := backendA.Count("recipient-A"); count != 1 {
		t.Fatalf("expected recipient-A inbox to keep shared message id, got %d", count)
	}
	if count := backendB.Count("recipient-B"); count != 1 {
		t.Fatalf("expected recipient-B inbox to keep shared message id, got %d", count)
	}

	requireRedisInboxStoreResult(
		t,
		backendA,
		"recipient-A",
		entry,
		InboxStoreResultDuplicate,
	)
	if count := backendA.Count("recipient-A"); count != 1 {
		t.Fatalf("expected recipient-A duplicate to be deduped, got %d", count)
	}
	if count := backendB.Count("recipient-B"); count != 1 {
		t.Fatalf("expected recipient-B inbox to remain unchanged, got %d", count)
	}
}

func TestRedisInboxBackend_StoreReturnsErrorOnWriteFailure(t *testing.T) {
	server := miniredis.RunT(t)

	maxPerPeer := DefaultServerLimits().MaxInboxMessagesPerPeer
	backend := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", maxPerPeer)
	server.Close()

	result, err := backend.Store("peer-recipient", inboxMessage{
		From:      "peer-sender",
		Message:   `{"type":"chat_message","version":"2","id":"msg-redis-write-failure-001","text":"hello"}`,
		Timestamp: time.Now().UnixMilli(),
	})
	if err == nil {
		t.Fatal("expected Store() to return an error after Redis closes")
	}
	if result == InboxStoreResultStored || result == InboxStoreResultDuplicate {
		t.Fatalf("Store() result = %q, want neither stored nor duplicate on failure", result)
	}
}

func TestRedisInboxBackend_RetrievePendingRequiresExplicitAckAcrossClients(t *testing.T) {
	server := miniredis.RunT(t)

	maxPerPeer := DefaultServerLimits().MaxInboxMessagesPerPeer
	backendA := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", maxPerPeer)
	backendB := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", maxPerPeer)

	for i := 0; i < 4; i++ {
		requireRedisInboxStoreResult(t, backendA, "peer-recipient", inboxMessage{
			From:      "peer-sender",
			Message:   fmt.Sprintf("msg-%d", i),
			Timestamp: time.Now().UnixMilli(),
		}, InboxStoreResultStored)
	}

	page1, hasMore1 := backendB.RetrievePending("peer-recipient", 2)
	if len(page1) != 2 {
		t.Fatalf("expected first staged page of 2 messages, got %d", len(page1))
	}
	if !hasMore1 {
		t.Fatal("expected hasMore=true after first staged page")
	}
	if page1[0].ID == "" || page1[1].ID == "" {
		t.Fatal("expected staged retrieval to expose stable relay entry IDs")
	}

	page1Again, hasMoreAgain := backendA.RetrievePending("peer-recipient", 2)
	if len(page1Again) != 2 {
		t.Fatalf("expected repeated staged page of 2 messages, got %d", len(page1Again))
	}
	if !hasMoreAgain {
		t.Fatal("expected hasMore=true before ack on repeated staged page")
	}
	if page1Again[0].ID != page1[0].ID || page1Again[1].ID != page1[1].ID {
		t.Fatal("expected staged retrieval to remain stable before ack")
	}

	acked, err := backendB.Ack("peer-recipient", []string{page1[0].ID, page1[1].ID})
	if err != nil {
		t.Fatalf("Ack() error: %v", err)
	}
	if acked != 2 {
		t.Fatalf("expected acked=2, got %d", acked)
	}

	page2, hasMore2 := backendA.RetrievePending("peer-recipient", 10)
	if len(page2) != 2 {
		t.Fatalf("expected 2 remaining messages after ack, got %d", len(page2))
	}
	if hasMore2 {
		t.Fatal("expected hasMore=false after retrieving final staged page")
	}
	if page2[0].Message != "msg-2" || page2[1].Message != "msg-3" {
		t.Fatalf("unexpected remaining staged page: %q, %q", page2[0].Message, page2[1].Message)
	}

	acked, err = backendA.Ack("peer-recipient", []string{page2[0].ID, page2[1].ID})
	if err != nil {
		t.Fatalf("Ack() second page error: %v", err)
	}
	if acked != 2 {
		t.Fatalf("expected second ack to remove 2 messages, got %d", acked)
	}

	final, hasMoreFinal := backendB.RetrievePending("peer-recipient", 10)
	if len(final) != 0 || hasMoreFinal {
		t.Fatalf("expected inbox to be empty after staged ack flow, got %d message(s), hasMore=%v", len(final), hasMoreFinal)
	}
}

func TestRedisInboxBackend_StoreRejectsNewWhenFull(t *testing.T) {
	server := miniredis.RunT(t)

	backend := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", 2)

	requireRedisInboxStoreResult(t, backend, "peer-recipient", inboxMessage{
		From:      "peer-sender",
		Message:   "msg-0",
		Timestamp: time.Now().UnixMilli(),
	}, InboxStoreResultStored)
	requireRedisInboxStoreResult(t, backend, "peer-recipient", inboxMessage{
		From:      "peer-sender",
		Message:   "msg-1",
		Timestamp: time.Now().UnixMilli(),
	}, InboxStoreResultStored)
	requireRedisInboxStoreResult(t, backend, "peer-recipient", inboxMessage{
		From:      "peer-sender",
		Message:   "overflow-msg",
		Timestamp: time.Now().UnixMilli(),
	}, InboxStoreResultRejectedFull)

	messages, hasMore := backend.RetrievePending("peer-recipient", 10)
	if hasMore || len(messages) != 2 {
		t.Fatalf("pending after overflow = %d hasMore=%v, want 2/false", len(messages), hasMore)
	}
	if messages[0].Message != "msg-0" || messages[1].Message != "msg-1" {
		t.Fatalf("oldest accepted messages not retained: %#v", messages)
	}
}

func TestRedisInboxBackend_ExpiredMessageIdReStorableAfterTTLCutoff(t *testing.T) {
	server := miniredis.RunT(t)

	backend := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", 10)
	expired := inboxMessage{
		From:      "peer-sender",
		Message:   `{"type":"chat_message","version":"2","id":"msg-redis-expired-restorable","text":"hello"}`,
		Timestamp: time.Now().Add(-8 * 24 * time.Hour).UnixMilli(),
	}
	fresh := expired
	fresh.Timestamp = time.Now().UnixMilli()

	requireRedisInboxStoreResult(t, backend, "peer-recipient", expired, InboxStoreResultStored)
	requireRedisInboxStoreResult(t, backend, "peer-recipient", fresh, InboxStoreResultStored)
	if count := backend.Count("peer-recipient"); count != 1 {
		t.Fatalf("expected expired entry to be pruned and fresh re-store retained, got %d", count)
	}
}

func TestRedisInboxBackend_AckedEntryMessageIdReStorable(t *testing.T) {
	server := miniredis.RunT(t)

	backend := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", 10)
	entry := inboxMessage{
		From:      "peer-sender",
		Message:   `{"type":"chat_message","version":"2","id":"msg-redis-acked-restorable","text":"hello"}`,
		Timestamp: time.Now().UnixMilli(),
	}

	requireRedisInboxStoreResult(t, backend, "peer-recipient", entry, InboxStoreResultStored)
	messages, _ := backend.RetrievePending("peer-recipient", 10)
	if len(messages) != 1 {
		t.Fatalf("pending count = %d, want 1", len(messages))
	}
	acked, err := backend.Ack("peer-recipient", []string{messages[0].ID})
	if err != nil {
		t.Fatalf("Ack() error: %v", err)
	}
	if acked != 1 {
		t.Fatalf("Ack() removed = %d, want 1", acked)
	}

	requireRedisInboxStoreResult(t, backend, "peer-recipient", entry, InboxStoreResultStored)
}

func TestRedisPushTokenBackend_SurvivesAcrossClients(t *testing.T) {
	server := miniredis.RunT(t)

	backendA := newRedisPushTokenBackend(newTestRedisClient(t, server), "phase2:")
	backendB := newRedisPushTokenBackend(newTestRedisClient(t, server), "phase2:")

	backendA.RegisterToken("peer-1", "token-abc", "ios")

	entry := backendB.LookupToken("peer-1")
	if entry == nil {
		t.Fatal("expected token registered through backend A to be visible on backend B")
	}
	if entry.Token != "token-abc" {
		t.Fatalf("expected token-abc, got %q", entry.Token)
	}
	if entry.Platform != "ios" {
		t.Fatalf("expected ios platform, got %q", entry.Platform)
	}

	backendB.UnregisterToken("peer-1")
	backendB.UnregisterToken("peer-1")
	backendB.UnregisterToken("missing-peer")
	if backendA.LookupToken("peer-1") != nil {
		t.Fatal("expected token to be removed across clients")
	}
}

func TestRedisGroupInboxBackend_CursorStableAcrossClients(t *testing.T) {
	server := miniredis.RunT(t)

	backendA := newRedisGroupInboxBackend(newTestRedisClient(t, server), "phase2:", 500, 7*24*time.Hour)
	backendB := newRedisGroupInboxBackend(newTestRedisClient(t, server), "phase2:", 500, 7*24*time.Hour)

	for i := 0; i < 5; i++ {
		if err := backendA.Store("group-1", "peer-1", fmt.Sprintf("msg-%02d", i)); err != nil {
			t.Fatalf("Store() error at message %d: %v", i, err)
		}
	}

	page1, cursor1, _ := backendB.RetrieveCursor("group-1", "", 2)
	if len(page1) != 2 {
		t.Fatalf("expected 2 messages in page 1, got %d", len(page1))
	}
	if cursor1 == "" {
		t.Fatal("expected non-empty cursor after page 1")
	}
	if page1[0].Message != "msg-00" || page1[1].Message != "msg-01" {
		t.Fatalf("unexpected page 1: %q, %q", page1[0].Message, page1[1].Message)
	}

	page2, cursor2, _ := backendA.RetrieveCursor("group-1", cursor1, 2)
	if len(page2) != 2 {
		t.Fatalf("expected 2 messages in page 2, got %d", len(page2))
	}
	if cursor2 == "" {
		t.Fatal("expected non-empty cursor after page 2")
	}
	if page2[0].Message != "msg-02" || page2[1].Message != "msg-03" {
		t.Fatalf("unexpected page 2: %q, %q", page2[0].Message, page2[1].Message)
	}

	page3, cursor3, _ := backendB.RetrieveCursor("group-1", cursor2, 2)
	if len(page3) != 1 {
		t.Fatalf("expected 1 message in page 3, got %d", len(page3))
	}
	if cursor3 != "" {
		t.Fatalf("expected empty cursor after final page, got %q", cursor3)
	}
	if page3[0].Message != "msg-04" {
		t.Fatalf("unexpected final page message: %q", page3[0].Message)
	}
}

func TestRedisGroupInboxBackend_PreservesRecipientPeerIdsAcrossClients(t *testing.T) {
	server := miniredis.RunT(t)

	backendA := newRedisGroupInboxBackend(newTestRedisClient(t, server), "phase2:", 500, 7*24*time.Hour)
	backendB := newRedisGroupInboxBackend(newTestRedisClient(t, server), "phase2:", 500, 7*24*time.Hour)

	if _, err := backendA.StoreWithRecipients(
		"group-acl",
		"peer-a",
		"msg-acl",
		[]string{"peer-b", "", "peer-b", "peer-c"},
	); err != nil {
		t.Fatalf("StoreWithRecipients: %v", err)
	}

	messages := backendB.RetrieveSince("group-acl", 0)
	if len(messages) != 1 {
		t.Fatalf("messages = %d, want 1", len(messages))
	}
	wantRecipients := []string{"peer-b", "peer-c"}
	if !reflect.DeepEqual(messages[0].RecipientPeerIds, wantRecipients) {
		t.Fatalf("RecipientPeerIds = %#v, want %#v", messages[0].RecipientPeerIds, wantRecipients)
	}
}

func TestRedisGroupInboxBackendStoreHelperUsesSenderACL(t *testing.T) {
	server := miniredis.RunT(t)

	backend := newRedisGroupInboxBackend(newTestRedisClient(t, server), "phase2:", 500, 7*24*time.Hour)

	if err := backend.Store("group-helper", "peer-a", "msg-helper"); err != nil {
		t.Fatalf("Store: %v", err)
	}

	messages := backend.RetrieveSince("group-helper", 0)
	if len(messages) != 1 {
		t.Fatalf("messages = %d, want 1", len(messages))
	}
	wantRecipients := []string{"peer-a"}
	if !reflect.DeepEqual(messages[0].RecipientPeerIds, wantRecipients) {
		t.Fatalf("RecipientPeerIds = %#v, want %#v", messages[0].RecipientPeerIds, wantRecipients)
	}
}

func TestRedisGroupInboxBackend_PreservesOpaqueReplayEnvelopeAcrossClients(t *testing.T) {
	server := miniredis.RunT(t)

	backendA := newRedisGroupInboxBackend(newTestRedisClient(t, server), "phase2:", 500, 7*24*time.Hour)
	backendB := newRedisGroupInboxBackend(newTestRedisClient(t, server), "phase2:", 500, 7*24*time.Hour)

	envelope1 := opaqueGroupReplayEnvelope("msg-opaque-redis-001")
	envelope2 := opaqueGroupReplayEnvelope("msg-opaque-redis-002")

	if err := backendA.Store("group-opaque", "peer-1", envelope1); err != nil {
		t.Fatalf("Store envelope1: %v", err)
	}
	if err := backendA.Store("group-opaque", "peer-1", envelope2); err != nil {
		t.Fatalf("Store envelope2: %v", err)
	}

	page1, cursor1, _ := backendB.RetrieveCursor("group-opaque", "", 1)
	if len(page1) != 1 {
		t.Fatalf("expected 1 message in page 1, got %d", len(page1))
	}
	if page1[0].Message != envelope1 {
		t.Fatalf("page1 message = %q, want exact envelope %q", page1[0].Message, envelope1)
	}
	if cursor1 == "" {
		t.Fatal("expected non-empty cursor after first opaque replay page")
	}

	page2, cursor2, _ := backendA.RetrieveCursor("group-opaque", cursor1, 1)
	if len(page2) != 1 {
		t.Fatalf("expected 1 message in page 2, got %d", len(page2))
	}
	if page2[0].Message != envelope2 {
		t.Fatalf("page2 message = %q, want exact envelope %q", page2[0].Message, envelope2)
	}
	if cursor2 != "" {
		t.Fatalf("expected empty cursor after final opaque replay page, got %q", cursor2)
	}
}
