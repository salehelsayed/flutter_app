package main

import (
	"fmt"
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

	backendA.Store("peer-recipient", inboxMessage{
		From:      "peer-sender",
		Message:   "expired",
		Timestamp: time.Now().Add(-maxMessageAge - time.Hour).UnixMilli(),
	})
	for i := 0; i < 4; i++ {
		backendA.Store("peer-recipient", inboxMessage{
			From:      "peer-sender",
			Message:   fmt.Sprintf("msg-%d", i),
			Timestamp: time.Now().UnixMilli(),
		})
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

func TestRedisInboxBackend_RetrievePendingRequiresExplicitAckAcrossClients(t *testing.T) {
	server := miniredis.RunT(t)

	maxPerPeer := DefaultServerLimits().MaxInboxMessagesPerPeer
	backendA := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", maxPerPeer)
	backendB := newRedisInboxBackend(newTestRedisClient(t, server), "phase2:", maxPerPeer)

	for i := 0; i < 4; i++ {
		backendA.Store("peer-recipient", inboxMessage{
			From:      "peer-sender",
			Message:   fmt.Sprintf("msg-%d", i),
			Timestamp: time.Now().UnixMilli(),
		})
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

	page1, cursor1 := backendB.RetrieveCursor("group-1", "", 2)
	if len(page1) != 2 {
		t.Fatalf("expected 2 messages in page 1, got %d", len(page1))
	}
	if cursor1 == "" {
		t.Fatal("expected non-empty cursor after page 1")
	}
	if page1[0].Message != "msg-00" || page1[1].Message != "msg-01" {
		t.Fatalf("unexpected page 1: %q, %q", page1[0].Message, page1[1].Message)
	}

	page2, cursor2 := backendA.RetrieveCursor("group-1", cursor1, 2)
	if len(page2) != 2 {
		t.Fatalf("expected 2 messages in page 2, got %d", len(page2))
	}
	if cursor2 == "" {
		t.Fatal("expected non-empty cursor after page 2")
	}
	if page2[0].Message != "msg-02" || page2[1].Message != "msg-03" {
		t.Fatalf("unexpected page 2: %q, %q", page2[0].Message, page2[1].Message)
	}

	page3, cursor3 := backendB.RetrieveCursor("group-1", cursor2, 2)
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
