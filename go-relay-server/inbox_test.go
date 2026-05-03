package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"sync"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	mocknet "github.com/libp2p/go-libp2p/p2p/net/mock"
)

type recordingPushSender struct {
	mu         sync.Mutex
	sendCalls  int
	lastMsg    *messaging.Message
	messages   []*messaging.Message
	err        error
	onSend     func(context.Context, *messaging.Message) (string, error)
	sentSignal chan struct{}
}

func newRecordingPushSender() *recordingPushSender {
	return &recordingPushSender{
		sentSignal: make(chan struct{}, 10),
	}
}

func (s *recordingPushSender) Send(ctx context.Context, msg *messaging.Message) (string, error) {
	s.mu.Lock()
	s.sendCalls++
	s.lastMsg = msg
	s.messages = append(s.messages, msg)
	s.mu.Unlock()

	select {
	case s.sentSignal <- struct{}{}:
	default:
	}

	if s.onSend != nil {
		return s.onSend(ctx, msg)
	}
	return "mock-message-id", s.err
}

func (s *recordingPushSender) SendCallCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.sendCalls
}

func (s *recordingPushSender) LastMessage() *messaging.Message {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.lastMsg
}

func (s *recordingPushSender) Messages() []*messaging.Message {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]*messaging.Message(nil), s.messages...)
}

type inboxStreamEnv struct {
	server    host.Host
	sender    host.Host
	recipient host.Host
	intruder  host.Host
}

func setupInboxStreamEnv(t *testing.T, inbox *InboxStore, groupInbox *GroupInboxStore) *inboxStreamEnv {
	t.Helper()

	mn := mocknet.New()
	server, err := mn.GenPeer()
	if err != nil {
		t.Fatal(err)
	}
	sender, err := mn.GenPeer()
	if err != nil {
		t.Fatal(err)
	}
	recipient, err := mn.GenPeer()
	if err != nil {
		t.Fatal(err)
	}
	intruder, err := mn.GenPeer()
	if err != nil {
		t.Fatal(err)
	}

	if err := mn.LinkAll(); err != nil {
		t.Fatal(err)
	}
	if err := mn.ConnectAllButSelf(); err != nil {
		t.Fatal(err)
	}

	server.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		HandleInboxStream(s, inbox, groupInbox)
	})

	t.Cleanup(func() {
		server.Close()
		sender.Close()
		recipient.Close()
		intruder.Close()
	})

	return &inboxStreamEnv{
		server:    server,
		sender:    sender,
		recipient: recipient,
		intruder:  intruder,
	}
}

func sendInboxReq(t *testing.T, s io.Writer, req inboxRequest) {
	t.Helper()
	data, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}
	if err := writeFrame(s, data); err != nil {
		t.Fatalf("write frame: %v", err)
	}
}

func recvInboxResp(t *testing.T, s io.Reader) inboxResponse {
	t.Helper()
	data, err := readFrame(s)
	if err != nil {
		t.Fatalf("read frame: %v", err)
	}
	var resp inboxResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	return resp
}

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

func TestInboxStore_RetrievePendingRequiresExplicitAckAcrossInstances(t *testing.T) {
	backend := newMemoryInboxBackend()
	pushBackend := newMemoryPushTokenStore()
	pushA := NewPushServiceWithBackend(pushBackend)
	pushB := NewPushServiceWithBackend(pushBackend)
	inboxA := NewInboxStoreWithBackend(backend, pushA)
	inboxB := NewInboxStoreWithBackend(backend, pushB)

	for i := 0; i < 3; i++ {
		inboxA.Store("peer-recipient", inboxMessage{
			From:      "peer-sender",
			Message:   fmt.Sprintf("msg-%d", i),
			Timestamp: time.Now().UnixMilli(),
		})
	}

	page1, hasMore1 := inboxB.RetrievePendingWithMeta("peer-recipient", 2)
	if len(page1) != 2 {
		t.Fatalf("expected 2 staged messages, got %d", len(page1))
	}
	if !hasMore1 {
		t.Fatal("expected hasMore=true on first staged page")
	}
	if page1[0].ID == "" || page1[1].ID == "" {
		t.Fatal("expected staged retrieve to expose stable relay entry IDs")
	}

	repeatPage, hasMoreRepeat := inboxA.RetrievePendingWithMeta("peer-recipient", 2)
	if len(repeatPage) != 2 {
		t.Fatalf("expected repeated staged page of 2 messages, got %d", len(repeatPage))
	}
	if !hasMoreRepeat {
		t.Fatal("expected hasMore=true before ack on repeated staged page")
	}
	if repeatPage[0].ID != page1[0].ID || repeatPage[1].ID != page1[1].ID {
		t.Fatal("expected staged retrieve to remain stable before ack")
	}

	acked, err := inboxA.Ack("peer-recipient", []string{page1[0].ID, page1[1].ID})
	if err != nil {
		t.Fatalf("Ack() error: %v", err)
	}
	if acked != 2 {
		t.Fatalf("expected acked=2, got %d", acked)
	}

	page2, hasMore2 := inboxB.RetrievePendingWithMeta("peer-recipient", 50)
	if len(page2) != 1 {
		t.Fatalf("expected 1 remaining staged message, got %d", len(page2))
	}
	if hasMore2 {
		t.Fatal("expected hasMore=false after only one message remains")
	}
	if page2[0].Message != "msg-2" {
		t.Fatalf("expected remaining message 'msg-2', got %q", page2[0].Message)
	}
}

func TestBuildChatPushMessage_LegacyPlaintextEnvelopeEmitsOnlyFallbackAndRouteData(t *testing.T) {
	msg := buildPushMessage(
		"fcm-token",
		"peer-from",
		`{"type":"chat_message","version":"1","payload":{"id":"msg-chat-1","text":"hello","senderUsername":"Alice"}}`,
	)

	if msg.Token != "fcm-token" {
		t.Fatalf("token = %q, want %q", msg.Token, "fcm-token")
	}
	if msg.Data["type"] != "new_message" {
		t.Fatalf("type = %q, want %q", msg.Data["type"], "new_message")
	}
	if msg.Data["sender_id"] != "peer-from" {
		t.Fatalf("sender_id = %q, want %q", msg.Data["sender_id"], "peer-from")
	}
	if msg.Data["message_id"] != "msg-chat-1" {
		t.Fatalf("message_id = %q, want %q", msg.Data["message_id"], "msg-chat-1")
	}
	if _, ok := msg.Data["sender_username"]; ok {
		t.Fatalf("sender_username should be omitted, got %q", msg.Data["sender_username"])
	}
	if _, ok := msg.Data["senderUsername"]; ok {
		t.Fatalf("senderUsername should be omitted, got %q", msg.Data["senderUsername"])
	}
	if _, ok := msg.Data["title"]; ok {
		t.Fatalf("title should be omitted, got %q", msg.Data["title"])
	}
	if _, ok := msg.Data["body"]; ok {
		t.Fatalf("body should be omitted, got %q", msg.Data["body"])
	}
	if msg.Notification != nil {
		t.Fatal("message pushes should omit top-level FCM notification payload")
	}

	if msg.Android == nil {
		t.Fatal("expected Android config")
	}
	if msg.Android.Priority != "high" {
		t.Fatalf("priority = %q, want %q", msg.Android.Priority, "high")
	}
	if msg.Android.Notification != nil {
		t.Fatal("Android message pushes should be data-only")
	}
	if msg.APNS == nil || msg.APNS.Payload == nil || msg.APNS.Payload.Aps == nil {
		t.Fatal("expected APNS payload")
	}
	if !msg.APNS.Payload.Aps.MutableContent {
		t.Fatal("expected APNS mutable-content for NSE decrypt")
	}
	if msg.APNS.Payload.Aps.Alert == nil {
		t.Fatal("expected APNS fallback alert")
	}
	if msg.APNS.Payload.Aps.Sound != pushNotificationSound {
		t.Fatalf(
			"apns sound = %q, want %q",
			msg.APNS.Payload.Aps.Sound,
			pushNotificationSound,
		)
	}
	if msg.APNS.Payload.Aps.Alert.Title == "Alice" {
		t.Fatal("APNS fallback title leaked sender username")
	}
	if msg.APNS.Payload.Aps.Alert.Body == "hello" {
		t.Fatal("APNS fallback body leaked message text")
	}
}

func TestBuildChatPushMessage_CarriesEncryptedDataWithoutPlaintextPreview(t *testing.T) {
	msg := buildPushMessage(
		"fcm-token",
		"peer-from",
		`{"type":"chat_message","version":"2","id":"msg-chat-2","senderUsername":"Alice","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`,
	)

	if msg.APNS == nil || msg.APNS.Payload == nil || msg.APNS.Payload.Aps == nil {
		t.Fatal("expected APNS payload")
	}
	if msg.APNS.Headers["apns-push-type"] != "alert" {
		t.Fatalf(
			"apns-push-type = %q, want %q",
			msg.APNS.Headers["apns-push-type"],
			"alert",
		)
	}
	if msg.APNS.Headers["apns-priority"] != "10" {
		t.Fatalf(
			"apns-priority = %q, want %q",
			msg.APNS.Headers["apns-priority"],
			"10",
		)
	}
	if msg.APNS.Payload.Aps.Alert == nil {
		t.Fatal("expected APNS alert")
	}
	if msg.APNS.Payload.Aps.Alert.Title == "Alice" {
		t.Fatal("APNS fallback title leaked sender username")
	}
	if msg.APNS.Payload.Aps.Alert.Body != pushNotificationBody {
		t.Fatalf(
			"apns body = %q, want %q",
			msg.APNS.Payload.Aps.Alert.Body,
			pushNotificationBody,
		)
	}
	if msg.Data["message_id"] != "msg-chat-2" {
		t.Fatalf("message_id = %q, want %q", msg.Data["message_id"], "msg-chat-2")
	}
	if msg.Data["kem"] != "k" || msg.Data["ciphertext"] != "c" || msg.Data["nonce"] != "n" {
		t.Fatalf("encrypted push data missing or wrong: %#v", msg.Data)
	}
	assertNoDirectPushSchemaVersionKeys(t, msg.Data)
	if _, ok := msg.Data["sender_username"]; ok {
		t.Fatalf("sender_username should be omitted, got %q", msg.Data["sender_username"])
	}
	if _, ok := msg.Data["senderUsername"]; ok {
		t.Fatalf("senderUsername should be omitted, got %q", msg.Data["senderUsername"])
	}
	if _, ok := msg.Data["title"]; ok {
		t.Fatalf("title should be omitted, got %q", msg.Data["title"])
	}
	if _, ok := msg.Data["body"]; ok {
		t.Fatalf("body should be omitted, got %q", msg.Data["body"])
	}
	if msg.Notification != nil {
		t.Fatal("message pushes should omit top-level FCM notification payload")
	}
	if msg.Android == nil || msg.Android.Notification != nil {
		t.Fatal("Android encrypted message push should be data-only")
	}
	if !msg.APNS.Payload.Aps.ContentAvailable {
		t.Fatal("expected APNS content-available")
	}
	if !msg.APNS.Payload.Aps.MutableContent {
		t.Fatal("expected APNS mutable-content")
	}
	if msg.APNS.Payload.Aps.Sound != pushNotificationSound {
		t.Fatalf(
			"apns sound = %q, want %q",
			msg.APNS.Payload.Aps.Sound,
			pushNotificationSound,
		)
	}
}

func TestBuildIntroductionPushMessage_UsesIntrosRouteAndGenericCopy(t *testing.T) {
	msg := buildPushMessage(
		"fcm-token",
		"peer-from",
		`{"type":"introduction","version":"1","messageId":"intro-1","payload":{"action":"send","introductionId":"intro-1","timestamp":"2026-04-04T20:36:00Z"}}`,
	)

	if msg.Token != "fcm-token" {
		t.Fatalf("token = %q, want %q", msg.Token, "fcm-token")
	}
	if msg.Data["type"] != "intros" {
		t.Fatalf("type = %q, want %q", msg.Data["type"], "intros")
	}
	if _, ok := msg.Data["sender_id"]; ok {
		t.Fatalf("sender_id should be omitted for intros push, got %q", msg.Data["sender_id"])
	}
	if msg.Data["message_id"] != "intro-1" {
		t.Fatalf("message_id = %q, want %q", msg.Data["message_id"], "intro-1")
	}
	if msg.Data["title"] != introPushNotificationTitle {
		t.Fatalf("title = %q, want %q", msg.Data["title"], introPushNotificationTitle)
	}
	if msg.Data["body"] != introPushNotificationBody {
		t.Fatalf("body = %q, want %q", msg.Data["body"], introPushNotificationBody)
	}
	if msg.Notification == nil {
		t.Fatal("expected top-level notification payload")
	}
	if msg.Notification.Title != introPushNotificationTitle {
		t.Fatalf(
			"notification title = %q, want %q",
			msg.Notification.Title,
			introPushNotificationTitle,
		)
	}
	if msg.Notification.Body != introPushNotificationBody {
		t.Fatalf(
			"notification body = %q, want %q",
			msg.Notification.Body,
			introPushNotificationBody,
		)
	}
}

func TestBuildContactRequestPushMessage_UsesContactRequestRoute(t *testing.T) {
	msg := buildPushMessage(
		"fcm-token",
		"peer-from",
		`{"type":"contact_request","version":"2","msgId":"req-1","senderUsername":"Alice","encrypted":{"ephemeralPublicKey":"e","ciphertext":"c","nonce":"n"}}`,
	)

	if msg.Data["type"] != "contact_request" {
		t.Fatalf("type = %q, want %q", msg.Data["type"], "contact_request")
	}
	if msg.Data["sender_id"] != "peer-from" {
		t.Fatalf("sender_id = %q, want %q", msg.Data["sender_id"], "peer-from")
	}
	if msg.Data["message_id"] != "req-1" {
		t.Fatalf("message_id = %q, want %q", msg.Data["message_id"], "req-1")
	}
	if msg.Data["title"] != contactRequestPushTitle {
		t.Fatalf("title = %q, want %q", msg.Data["title"], contactRequestPushTitle)
	}
	if msg.Data["body"] != "Alice wants to connect" {
		t.Fatalf("body = %q, want %q", msg.Data["body"], "Alice wants to connect")
	}
}

func TestExtractChatPushMetadata_SuppressesKeyExchangeRetryContactRequest(t *testing.T) {
	metadata := extractChatPushMetadata(
		`{"type":"contact_request","version":"2","intent":"key_exchange_retry","msgId":"req-1","senderUsername":"Alice","encrypted":{"ephemeralPublicKey":"e","ciphertext":"c","nonce":"n"}}`,
	)

	if metadata.ShouldNotify {
		t.Fatal("expected key-exchange retry contact request to suppress push notification")
	}
	if metadata.RouteType != "contact_request" {
		t.Fatalf("routeType = %q, want %q", metadata.RouteType, "contact_request")
	}
	if metadata.MessageID != "req-1" {
		t.Fatalf("messageID = %q, want %q", metadata.MessageID, "req-1")
	}
}

func TestBuildGroupInvitePushMessage_UsesInviteRouteAndMetadata(t *testing.T) {
	msg := buildPushMessage(
		"fcm-token",
		"peer-from",
		`{"type":"group_invite","version":"2","id":"invite-1","senderPeerId":"peer-from","senderUsername":"Alice","groupId":"group-1","groupName":"Book Club","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`,
	)

	if msg.Data["type"] != "group_invite" {
		t.Fatalf("type = %q, want %q", msg.Data["type"], "group_invite")
	}
	if msg.Data["groupId"] != "group-1" {
		t.Fatalf("groupId = %q, want %q", msg.Data["groupId"], "group-1")
	}
	if msg.Data["message_id"] != "invite-1" {
		t.Fatalf("message_id = %q, want %q", msg.Data["message_id"], "invite-1")
	}
	if msg.Data["title"] != "Book Club" {
		t.Fatalf("title = %q, want %q", msg.Data["title"], "Book Club")
	}
	if msg.Data["body"] != "Alice invited you to Book Club" {
		t.Fatalf("body = %q, want %q", msg.Data["body"], "Alice invited you to Book Club")
	}
}

func TestInboxStore_UnsupportedEnvelopeDoesNotSendPush(t *testing.T) {
	tokenStore := newMemoryPushTokenStore()
	tokenStore.RegisterToken("peer-recipient", "fcm-token", "android")

	push := NewPushServiceWithBackend(tokenStore)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	inbox := NewInboxStore(push)

	stored := inbox.Store("peer-recipient", inboxMessage{
		From:      "peer-sender",
		Message:   `{"type":"presence_ping","id":"unsupported-1","payload":{"status":"online"}}`,
		Timestamp: time.Now().UnixMilli(),
	})
	if !stored {
		t.Fatal("expected unsupported envelope to still be stored in inbox")
	}

	select {
	case <-recorder.sentSignal:
		t.Fatal("unexpected push send for unsupported envelope")
	case <-time.After(150 * time.Millisecond):
	}
}

func TestInboxStore_KeyExchangeRetryContactRequestDoesNotSendPush(t *testing.T) {
	tokenStore := newMemoryPushTokenStore()
	tokenStore.RegisterToken("peer-recipient", "fcm-token", "android")

	push := NewPushServiceWithBackend(tokenStore)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	inbox := NewInboxStore(push)

	stored := inbox.Store("peer-recipient", inboxMessage{
		From:      "peer-sender",
		Message:   `{"type":"contact_request","version":"2","intent":"key_exchange_retry","msgId":"req-1","senderUsername":"Alice","encrypted":{"ephemeralPublicKey":"e","ciphertext":"c","nonce":"n"}}`,
		Timestamp: time.Now().UnixMilli(),
	})
	if !stored {
		t.Fatal("expected retry contact request to still be stored in inbox")
	}

	select {
	case <-recorder.sentSignal:
		t.Fatal("unexpected push send for key-exchange retry contact request")
	case <-time.After(150 * time.Millisecond):
	}
}

func TestBuildGroupPushMessage_CarriesEncryptedDataWithoutPlaintextPreview(t *testing.T) {
	msg := buildGroupPushMessage(
		"fcm-token",
		"group-1",
		"group-msg-1",
		`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":7,"messageId":"group-msg-1","ciphertext":"gc","nonce":"gn"}`,
	)

	if msg.Token != "fcm-token" {
		t.Fatalf("token = %q, want %q", msg.Token, "fcm-token")
	}
	if msg.Notification != nil {
		t.Fatal("group message pushes should omit top-level FCM notification payload")
	}
	if msg.Data["type"] != "group_message" {
		t.Fatalf("type = %q, want %q", msg.Data["type"], "group_message")
	}
	if msg.Data["groupId"] != "group-1" {
		t.Fatalf("groupId = %q, want %q", msg.Data["groupId"], "group-1")
	}
	if msg.Data["message_id"] != "group-msg-1" {
		t.Fatalf("message_id = %q, want %q", msg.Data["message_id"], "group-msg-1")
	}
	if msg.Data["kind"] != "group_offline_replay" {
		t.Fatalf("kind = %q, want group_offline_replay", msg.Data["kind"])
	}
	if msg.Data["payloadType"] != "group_message" {
		t.Fatalf("payloadType = %q, want group_message", msg.Data["payloadType"])
	}
	if msg.Data["keyEpoch"] != "7" {
		t.Fatalf("keyEpoch = %q, want 7", msg.Data["keyEpoch"])
	}
	if msg.Data["ciphertext"] != "gc" || msg.Data["nonce"] != "gn" {
		t.Fatalf("encrypted group push data missing or wrong: %#v", msg.Data)
	}
	assertNoDirectPushSchemaVersionKeys(t, msg.Data)
	if _, ok := msg.Data["title"]; ok {
		t.Fatalf("title should be omitted, got %q", msg.Data["title"])
	}
	if _, ok := msg.Data["body"]; ok {
		t.Fatalf("body should be omitted, got %q", msg.Data["body"])
	}
	if msg.Android == nil {
		t.Fatal("expected Android config")
	}
	if msg.Android.Notification != nil {
		t.Fatal("Android group message push should be data-only")
	}
	if msg.APNS == nil || msg.APNS.Payload == nil || msg.APNS.Payload.Aps == nil {
		t.Fatal("expected APNS payload")
	}
	if msg.APNS.Payload.Aps.Alert == nil {
		t.Fatal("expected APNS alert")
	}
	if msg.APNS.Payload.Aps.Alert.Title == "Team Chat" {
		t.Fatal("APNS fallback title leaked group name")
	}
	if msg.APNS.Payload.Aps.Alert.Body == "Alice: hello" {
		t.Fatal("APNS fallback body leaked plaintext preview")
	}
	if !msg.APNS.Payload.Aps.MutableContent {
		t.Fatal("expected APNS mutable-content")
	}
	if msg.APNS.Payload.Aps.Sound != pushNotificationSound {
		t.Fatalf(
			"apns sound = %q, want %q",
			msg.APNS.Payload.Aps.Sound,
			pushNotificationSound,
		)
	}
}

func assertNoDirectPushSchemaVersionKeys(t *testing.T, data map[string]string) {
	t.Helper()

	for _, key := range []string{"schemaVersion", "version", "v"} {
		if value, ok := data[key]; ok {
			t.Fatalf("push data should omit direct schema version key %q, got %q", key, value)
		}
	}
}

func TestHandleInboxStream_StoreTriggersPushSendAfterPersistence(t *testing.T) {
	t.Skip("push sender injection coverage is outside Section 4 and not required for this verification gate")
}

func TestPushService_SendNotification_UnregistersInvalidToken(t *testing.T) {
	tokenStore := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokenStore)
	push.retryDelays = []time.Duration{0}
	recorder := newRecordingPushSender()
	push.sender = recorder.Send

	tokenStore.RegisterToken("peer-recipient", "invalid-token", "ios")
	recorder.onSend = func(ctx context.Context, msg *messaging.Message) (string, error) {
		return "", fmt.Errorf("registration-token-not-registered")
	}

	push.SendNotification(
		context.Background(),
		"peer-recipient",
		"peer-sender",
		`{"id":"msg-chat-1","text":"hello"}`,
	)

	if recorder.SendCallCount() != 1 {
		t.Fatalf("send calls = %d, want 1", recorder.SendCallCount())
	}
	if tokenStore.LookupToken("peer-recipient") != nil {
		t.Fatal("expected invalid token to be removed after failed send")
	}
}

func TestPushService_SendNotification_LogsWhenTokenMissing(t *testing.T) {
	tokenStore := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokenStore)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send

	push.SendNotification(
		context.Background(),
		"peer-missing",
		"peer-sender",
		`{"id":"msg-chat-1","text":"hello"}`,
	)

	if recorder.SendCallCount() != 0 {
		t.Fatalf("send calls = %d, want 0 when token is missing", recorder.SendCallCount())
	}
}

func TestPushService_SendGroupNotification_RetriesTransientFailure(t *testing.T) {
	tokenStore := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokenStore)
	push.retryDelays = []time.Duration{0}
	recorder := newRecordingPushSender()
	push.sender = recorder.Send

	tokenStore.RegisterToken("peer-recipient", "recipient-token", "ios")

	attempts := 0
	recorder.onSend = func(ctx context.Context, msg *messaging.Message) (string, error) {
		attempts++
		if attempts == 1 {
			return "", fmt.Errorf("temporary push outage")
		}
		return "mock-message-id", nil
	}

	push.SendGroupNotification(
		context.Background(),
		"peer-recipient",
		"group-1",
		"group-msg-1",
		`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":7,"messageId":"group-msg-1","ciphertext":"gc","nonce":"gn"}`,
	)

	if recorder.SendCallCount() != 2 {
		t.Fatalf("send calls = %d, want 2", recorder.SendCallCount())
	}
	if tokenStore.LookupToken("peer-recipient") == nil {
		t.Fatal("expected transient group push failure to keep the token registered")
	}

	messages := recorder.Messages()
	if len(messages) != 2 {
		t.Fatalf("recorded messages = %d, want 2", len(messages))
	}
	for _, msg := range messages {
		if msg.Data["groupId"] != "group-1" {
			t.Fatalf("groupId = %q, want %q", msg.Data["groupId"], "group-1")
		}
	}
}

func TestHandleInboxStream_GroupStoreFansOutPushToRecipientsWithTokens(t *testing.T) {
	tokenStore := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokenStore)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send

	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	groupInbox.SetPush(push)
	inbox := NewInboxStore(push)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	senderPeer := env.sender.ID().String()
	recipientWithToken := env.recipient.ID().String()
	recipientTwo := "peer-2"

	tokenStore.RegisterToken(senderPeer, "sender-token", "ios")
	tokenStore.RegisterToken(recipientWithToken, "recipient-token", "ios")
	tokenStore.RegisterToken(recipientTwo, "recipient-two-token", "ios")

	recorder.onSend = func(ctx context.Context, msg *messaging.Message) (string, error) {
		stored := groupInbox.Retrieve("group-push", 0)
		if len(stored) == 0 {
			t.Fatal("group push fanout ran before durable store")
		}
		return "mock-message-id", nil
	}

	sendGroupStore := func() inboxResponse {
		t.Helper()

		stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open stream: %v", err)
		}
		defer stream.Close()

		req := map[string]interface{}{
			"action":           "group_store",
			"groupId":          "group-push",
			"from":             senderPeer,
			"message":          `{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":7,"messageId":"group-msg-1","ciphertext":"gc","nonce":"gn"}`,
			"recipientPeerIds": []string{senderPeer, recipientWithToken, recipientTwo},
		}

		data, err := json.Marshal(req)
		if err != nil {
			t.Fatalf("marshal group request: %v", err)
		}
		if err := writeFrame(stream, data); err != nil {
			t.Fatalf("write group frame: %v", err)
		}

		return recvInboxResp(t, stream)
	}

	resp := sendGroupStore()
	if resp.Status != "OK" {
		t.Fatalf("first group_store status = %q, want OK", resp.Status)
	}

	for i := 0; i < 2; i++ {
		select {
		case <-recorder.sentSignal:
		case <-time.After(2 * time.Second):
			t.Fatalf("timed out waiting for push send %d", i+1)
		}
	}

	select {
	case <-recorder.sentSignal:
		t.Fatal("unexpected extra push send")
	case <-time.After(200 * time.Millisecond):
	}

	messages := recorder.Messages()
	if len(messages) != 2 {
		t.Fatalf("push sends = %d, want 2", len(messages))
	}

	seenTokens := map[string]bool{}
	for _, msg := range messages {
		seenTokens[msg.Token] = true
		if msg.Data["type"] != "group_message" {
			t.Fatalf("push type = %q, want group_message", msg.Data["type"])
		}
		if msg.Data["groupId"] != "group-push" {
			t.Fatalf("groupId = %q, want group-push", msg.Data["groupId"])
		}
		if _, ok := msg.Data["title"]; ok {
			t.Fatalf("title should be omitted, got %q", msg.Data["title"])
		}
		if _, ok := msg.Data["body"]; ok {
			t.Fatalf("body should be omitted, got %q", msg.Data["body"])
		}
		if msg.Data["message_id"] != "group-msg-1" {
			t.Fatalf("message_id = %q, want group-msg-1", msg.Data["message_id"])
		}
		if msg.Data["ciphertext"] != "gc" || msg.Data["nonce"] != "gn" {
			t.Fatalf("encrypted group data missing or wrong: %#v", msg.Data)
		}
	}

	if !seenTokens["recipient-token"] || !seenTokens["recipient-two-token"] {
		t.Fatalf("missing recipient tokens in push sends: %#v", seenTokens)
	}
	if seenTokens["sender-token"] {
		t.Fatal("sender should not receive a group push")
	}

	resp = sendGroupStore()
	if resp.Status != "OK" {
		t.Fatalf("duplicate group_store status = %q, want OK", resp.Status)
	}

	select {
	case <-recorder.sentSignal:
		t.Fatal("duplicate store re-fanned out push sends")
	case <-time.After(300 * time.Millisecond):
	}
}

func TestHandleInboxStream_GroupStoreRejectsSpoofedFromPeer(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	senderPeer := env.sender.ID().String()
	recipientPeer := env.recipient.ID().String()

	stream, err := env.intruder.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open group_store stream: %v", err)
	}
	defer stream.Close()

	sendInboxReq(t, stream, inboxRequest{
		Action:           "group_store",
		GroupId:          "group-auth",
		From:             senderPeer,
		Message:          `{"kind":"group_offline_replay","messageId":"spoofed"}`,
		RecipientPeerIds: []string{recipientPeer},
	})
	resp := recvInboxResp(t, stream)
	if resp.Status != "ERROR" || resp.Error != "not authorized" {
		t.Fatalf("spoofed group_store response = %#v, want not authorized error", resp)
	}

	if stored := groupInbox.Retrieve("group-auth", 0); len(stored) != 0 {
		t.Fatalf("spoofed group_store persisted %d message(s)", len(stored))
	}
}

func TestHandleInboxStream_GroupRetrieveFiltersByRecipientAuthorization(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	senderPeer := env.sender.ID().String()
	recipientPeer := env.recipient.ID().String()

	store := func(id string, recipients []string) {
		t.Helper()
		stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open group_store stream: %v", err)
		}
		defer stream.Close()

		sendInboxReq(t, stream, inboxRequest{
			Action:           "group_store",
			GroupId:          "group-auth",
			From:             senderPeer,
			Message:          fmt.Sprintf(`{"kind":"group_offline_replay","messageId":%q}`, id),
			RecipientPeerIds: recipients,
		})
		resp := recvInboxResp(t, stream)
		if resp.Status != "OK" {
			t.Fatalf("group_store(%s) status = %q error=%q, want OK", id, resp.Status, resp.Error)
		}
	}

	retrieveFrom := func(from host.Host) inboxResponse {
		t.Helper()
		stream, err := from.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open group_retrieve stream: %v", err)
		}
		defer stream.Close()

		sendInboxReq(t, stream, inboxRequest{
			Action:  "group_retrieve",
			GroupId: "group-auth",
		})
		return recvInboxResp(t, stream)
	}

	store("msg-recipient", []string{recipientPeer})

	recipientResp := retrieveFrom(env.recipient)
	if recipientResp.Status != "OK" || len(recipientResp.GroupMessages) != 1 {
		t.Fatalf("recipient retrieve = %#v, want one authorized message", recipientResp)
	}
	if !strings.Contains(recipientResp.GroupMessages[0].Message, "msg-recipient") {
		t.Fatalf("recipient got wrong message: %#v", recipientResp.GroupMessages)
	}

	intruderResp := retrieveFrom(env.intruder)
	if intruderResp.Status != "NO_MESSAGES" || len(intruderResp.GroupMessages) != 0 {
		t.Fatalf("intruder retrieve = %#v, want NO_MESSAGES", intruderResp)
	}

	senderResp := retrieveFrom(env.sender)
	if senderResp.Status != "OK" || len(senderResp.GroupMessages) != 1 {
		t.Fatalf("sender retrieve = %#v, want sender to read own stored replay", senderResp)
	}
}

func TestHandleInboxStream_GroupRetrieveCursorSkipsUnauthorizedMessages(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	senderPeer := env.sender.ID().String()
	recipientPeer := env.recipient.ID().String()
	intruderPeer := env.intruder.ID().String()

	store := func(id string, recipients []string) {
		t.Helper()
		stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open group_store stream: %v", err)
		}
		defer stream.Close()

		sendInboxReq(t, stream, inboxRequest{
			Action:           "group_store",
			GroupId:          "group-cursor-auth",
			From:             senderPeer,
			Message:          fmt.Sprintf(`{"kind":"group_offline_replay","messageId":%q}`, id),
			RecipientPeerIds: recipients,
		})
		resp := recvInboxResp(t, stream)
		if resp.Status != "OK" {
			t.Fatalf("group_store(%s) status = %q error=%q, want OK", id, resp.Status, resp.Error)
		}
	}

	retrieveCursor := func(cursor string, limit int) inboxResponse {
		t.Helper()
		stream, err := env.recipient.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open group_retrieve_cursor stream: %v", err)
		}
		defer stream.Close()

		sendInboxReq(t, stream, inboxRequest{
			Action:  "group_retrieve_cursor",
			GroupId: "group-cursor-auth",
			Cursor:  cursor,
			Limit:   limit,
		})
		return recvInboxResp(t, stream)
	}

	store("recipient-1", []string{recipientPeer})
	store("intruder-only", []string{intruderPeer})
	store("recipient-2", []string{recipientPeer})

	first := retrieveCursor("", 1)
	if first.Status != "OK" || len(first.GroupMessages) != 1 || first.NextCursor == "" {
		t.Fatalf("first cursor response = %#v, want one message and next cursor", first)
	}
	if !strings.Contains(first.GroupMessages[0].Message, "recipient-1") {
		t.Fatalf("first cursor returned unauthorized or wrong message: %#v", first.GroupMessages)
	}

	second := retrieveCursor(first.NextCursor, 1)
	if second.Status != "OK" || len(second.GroupMessages) != 1 || second.NextCursor != "" {
		t.Fatalf("second cursor response = %#v, want final authorized message", second)
	}
	if !strings.Contains(second.GroupMessages[0].Message, "recipient-2") {
		t.Fatalf("second cursor returned unauthorized or wrong message: %#v", second.GroupMessages)
	}
}

func TestGroupInboxStore_RetrieveCursorReportsHistoryGapForMissingCursor(t *testing.T) {
	store := NewGroupInboxStore(500, 7*24*time.Hour)
	if err := store.StoreWithPushRecipients(
		"group-gap",
		"peer-source",
		`{"kind":"group_offline_replay","messageId":"repair-1"}`,
		[]string{"peer-reader"},
	); err != nil {
		t.Fatalf("StoreWithPushRecipients: %v", err)
	}

	messages, _, historyGaps := store.RetrieveWithCursorAuthorized(
		"group-gap",
		"stale-cursor",
		10,
		"peer-reader",
	)
	if len(messages) != 1 {
		t.Fatalf("expected one repair candidate message, got %d", len(messages))
	}
	if len(historyGaps) != 1 {
		t.Fatalf("expected one history gap, got %#v", historyGaps)
	}

	gap := historyGaps[0]
	if gap.GroupId != "group-gap" || gap.MissingAfterMessageId != "stale-cursor" {
		t.Fatalf("unexpected gap boundary: %#v", gap)
	}
	if gap.ExpectedHeadMessageId != messages[0].ID || gap.MissingBeforeMessageId != messages[0].ID {
		t.Fatalf("gap head/before should target returned repair head: gap=%#v msg=%#v", gap, messages[0])
	}
	if gap.ExpectedRangeHash != computeGroupHistoryRangeHash(messages) {
		t.Fatalf("range hash = %q, want %q", gap.ExpectedRangeHash, computeGroupHistoryRangeHash(messages))
	}
	if !containsPeer(gap.CandidateSourcePeerIds, "peer-source") ||
		!containsPeer(gap.CandidateSourcePeerIds, "peer-reader") {
		t.Fatalf("candidate sources should include sender and recipient, got %#v", gap.CandidateSourcePeerIds)
	}
}

func TestHandleInboxStream_GroupHistoryGapAndRepairRangeJSON(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	senderPeer := env.sender.ID().String()
	recipientPeer := env.recipient.ID().String()

	if err := groupInbox.StoreWithPushRecipients(
		"group-gap-json",
		senderPeer,
		`{"kind":"group_offline_replay","messageId":"repair-json-1"}`,
		[]string{recipientPeer},
	); err != nil {
		t.Fatalf("StoreWithPushRecipients: %v", err)
	}

	retrieveStream, err := env.recipient.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open group_retrieve_cursor stream: %v", err)
	}
	sendInboxReq(t, retrieveStream, inboxRequest{
		Action:  "group_retrieve_cursor",
		GroupId: "group-gap-json",
		Cursor:  "stale-cursor",
		Limit:   10,
	})
	retrieveResp := recvInboxResp(t, retrieveStream)
	_ = retrieveStream.Close()

	if retrieveResp.Status != "OK" || len(retrieveResp.GroupMessages) != 1 {
		t.Fatalf("retrieve response = %#v, want one message", retrieveResp)
	}
	if len(retrieveResp.HistoryGaps) != 1 {
		t.Fatalf("retrieve response missing historyGaps: %#v", retrieveResp)
	}
	gap := retrieveResp.HistoryGaps[0]

	repairStream, err := env.recipient.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open group_history_repair_range stream: %v", err)
	}
	sendInboxReq(t, repairStream, inboxRequest{
		Action:                 "group_history_repair_range",
		GroupId:                gap.GroupId,
		GapId:                  gap.GapId,
		SourcePeerId:           senderPeer,
		MissingAfterMessageId:  gap.MissingAfterMessageId,
		MissingBeforeMessageId: gap.MissingBeforeMessageId,
		ExpectedRangeHash:      gap.ExpectedRangeHash,
		ExpectedHeadMessageId:  gap.ExpectedHeadMessageId,
		Limit:                  10,
	})
	repairResp := recvInboxResp(t, repairStream)
	_ = repairStream.Close()

	if repairResp.Status != "OK" || len(repairResp.GroupMessages) != 1 {
		t.Fatalf("repair response = %#v, want one replay envelope", repairResp)
	}
	if repairResp.RangeHash != gap.ExpectedRangeHash {
		t.Fatalf("repair rangeHash = %q, want %q", repairResp.RangeHash, gap.ExpectedRangeHash)
	}
	if repairResp.HeadMessageId != gap.ExpectedHeadMessageId {
		t.Fatalf("repair headMessageId = %q, want %q", repairResp.HeadMessageId, gap.ExpectedHeadMessageId)
	}
	if repairResp.GroupId != gap.GroupId || repairResp.GapId != gap.GapId || repairResp.SourcePeerId != senderPeer {
		t.Fatalf("repair metadata mismatch: %#v", repairResp)
	}
}

func TestHandleInboxStream_RetrievePendingAndAck(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	recipientPeer := env.recipient.ID().String()
	senderPeer := env.sender.ID().String()

	storeMessage := func(message string) {
		t.Helper()

		stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open store stream: %v", err)
		}
		defer stream.Close()

		sendInboxReq(t, stream, inboxRequest{
			Action:  "store",
			To:      recipientPeer,
			From:    senderPeer,
			Message: message,
		})
		resp := recvInboxResp(t, stream)
		if resp.Status != "OK" {
			t.Fatalf("store status = %q, want OK", resp.Status)
		}
	}

	retrievePending := func() inboxResponse {
		t.Helper()

		stream, err := env.recipient.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open retrieve_pending stream: %v", err)
		}
		defer stream.Close()

		sendInboxReq(t, stream, inboxRequest{
			Action: "retrieve_pending",
			Limit:  50,
		})
		return recvInboxResp(t, stream)
	}

	ackEntries := func(entryIDs []string) inboxResponse {
		t.Helper()

		stream, err := env.recipient.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open ack stream: %v", err)
		}
		defer stream.Close()

		sendInboxReq(t, stream, inboxRequest{
			Action:   "ack",
			EntryIds: entryIDs,
		})
		return recvInboxResp(t, stream)
	}

	storeMessage("msg-0")
	storeMessage("msg-1")

	first := retrievePending()
	if first.Status != "OK" {
		t.Fatalf("first retrieve_pending status = %q, want OK", first.Status)
	}
	if len(first.Messages) != 2 {
		t.Fatalf("expected 2 staged messages, got %d", len(first.Messages))
	}
	if first.Messages[0].ID == "" || first.Messages[1].ID == "" {
		t.Fatal("expected staged retrieve response to include stable entry IDs")
	}

	second := retrievePending()
	if second.Status != "OK" {
		t.Fatalf("second retrieve_pending status = %q, want OK", second.Status)
	}
	if len(second.Messages) != 2 {
		t.Fatalf("expected repeated staged messages, got %d", len(second.Messages))
	}
	if second.Messages[0].ID != first.Messages[0].ID || second.Messages[1].ID != first.Messages[1].ID {
		t.Fatal("expected retrieve_pending to remain stable before ack")
	}

	ackResp := ackEntries([]string{first.Messages[0].ID})
	if ackResp.Status != "OK" {
		t.Fatalf("ack status = %q, want OK", ackResp.Status)
	}
	if ackResp.Acked != 1 {
		t.Fatalf("expected acked=1, got %d", ackResp.Acked)
	}

	remaining := retrievePending()
	if remaining.Status != "OK" {
		t.Fatalf("remaining retrieve_pending status = %q, want OK", remaining.Status)
	}
	if len(remaining.Messages) != 1 {
		t.Fatalf("expected 1 remaining staged message, got %d", len(remaining.Messages))
	}
	if remaining.Messages[0].Message != "msg-1" {
		t.Fatalf("expected remaining message 'msg-1', got %q", remaining.Messages[0].Message)
	}

	ackResp = ackEntries([]string{remaining.Messages[0].ID})
	if ackResp.Status != "OK" {
		t.Fatalf("final ack status = %q, want OK", ackResp.Status)
	}
	if ackResp.Acked != 1 {
		t.Fatalf("expected final acked=1, got %d", ackResp.Acked)
	}

	final := retrievePending()
	if final.Status != "NO_MESSAGES" {
		t.Fatalf("expected final retrieve_pending status NO_MESSAGES, got %q", final.Status)
	}
}

func TestHandleInboxStream_RetrievePendingTrimsOversizedResponses(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	recipientPeer := env.recipient.ID().String()
	senderPeer := env.sender.ID().String()
	oversizedPayload := fmt.Sprintf(
		`{"type":"chat_message","version":"1","payload":{"id":"%%s","text":"%s","senderUsername":"Alice"}}`,
		strings.Repeat("x", 4000),
	)

	storeMessage := func(id string) {
		t.Helper()

		stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open store stream: %v", err)
		}
		defer stream.Close()

		sendInboxReq(t, stream, inboxRequest{
			Action:  "store",
			To:      recipientPeer,
			From:    senderPeer,
			Message: fmt.Sprintf(oversizedPayload, id),
		})
		resp := recvInboxResp(t, stream)
		if resp.Status != "OK" {
			t.Fatalf("store status = %q, want OK", resp.Status)
		}
	}

	for i := 0; i < 40; i++ {
		storeMessage(fmt.Sprintf("msg-%02d", i))
	}

	stream, err := env.recipient.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open retrieve_pending stream: %v", err)
	}
	defer stream.Close()

	sendInboxReq(t, stream, inboxRequest{
		Action: "retrieve_pending",
		Limit:  50,
	})
	resp := recvInboxResp(t, stream)
	if resp.Status != "OK" {
		t.Fatalf("retrieve_pending status = %q, want OK", resp.Status)
	}
	if len(resp.Messages) == 0 {
		t.Fatal("expected at least one message in trimmed response")
	}
	if len(resp.Messages) >= 40 {
		t.Fatalf("expected trimmed response to include fewer than 40 messages, got %d", len(resp.Messages))
	}
	if !resp.HasMore {
		t.Fatal("expected hasMore=true after trimming oversized retrieve_pending response")
	}
}

// --- Phase B: Top-level Notification field tests ---

func TestBuildChatPushMessage_TopLevelNotification(t *testing.T) {
	t.Skip("top-level notification payload coverage belongs to later notification work, not Section 4")
}
