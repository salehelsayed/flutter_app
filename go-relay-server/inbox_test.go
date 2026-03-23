package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
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
	})

	return &inboxStreamEnv{
		server:    server,
		sender:    sender,
		recipient: recipient,
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

func TestBuildChatPushMessage_IncludesAndroidAlertAndData(t *testing.T) {
	msg := buildChatPushMessage(chatPushRequest{
		Token:      "fcm-token",
		FromPeerID: "peer-from",
	})

	if msg.Token != "fcm-token" {
		t.Fatalf("token = %q, want %q", msg.Token, "fcm-token")
	}
	if msg.Data["type"] != "new_message" {
		t.Fatalf("type = %q, want %q", msg.Data["type"], "new_message")
	}
	if msg.Data["from"] != "peer-from" {
		t.Fatalf("from = %q, want %q", msg.Data["from"], "peer-from")
	}
	if msg.Data["title"] != pushNotificationTitle {
		t.Fatalf("title = %q, want %q", msg.Data["title"], pushNotificationTitle)
	}
	if msg.Data["body"] != pushNotificationBody {
		t.Fatalf("body = %q, want %q", msg.Data["body"], pushNotificationBody)
	}

	if msg.Android == nil {
		t.Fatal("expected Android config")
	}
	if msg.Android.Priority != "high" {
		t.Fatalf("priority = %q, want %q", msg.Android.Priority, "high")
	}
	if msg.Android.Notification == nil {
		t.Fatal("expected Android notification payload")
	}
	if msg.Android.Notification.Title != pushNotificationTitle {
		t.Fatalf(
			"android title = %q, want %q",
			msg.Android.Notification.Title,
			pushNotificationTitle,
		)
	}
	if msg.Android.Notification.Body != pushNotificationBody {
		t.Fatalf(
			"android body = %q, want %q",
			msg.Android.Notification.Body,
			pushNotificationBody,
		)
	}
	if msg.Android.Notification.ChannelID != pushNotificationChannelID {
		t.Fatalf(
			"android channel = %q, want %q",
			msg.Android.Notification.ChannelID,
			pushNotificationChannelID,
		)
	}
}

func TestBuildChatPushMessage_PreservesIOSAlertPayload(t *testing.T) {
	msg := buildChatPushMessage(chatPushRequest{
		Token:      "fcm-token",
		FromPeerID: "peer-from",
	})

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
	if msg.APNS.Payload.Aps.Alert.Title != pushNotificationTitle {
		t.Fatalf(
			"apns title = %q, want %q",
			msg.APNS.Payload.Aps.Alert.Title,
			pushNotificationTitle,
		)
	}
	if msg.APNS.Payload.Aps.Alert.Body != pushNotificationBody {
		t.Fatalf(
			"apns body = %q, want %q",
			msg.APNS.Payload.Aps.Alert.Body,
			pushNotificationBody,
		)
	}
	if !msg.APNS.Payload.Aps.ContentAvailable {
		t.Fatal("expected APNS content-available")
	}
}

func TestHandleInboxStream_StoreTriggersPushSendAfterPersistence(t *testing.T) {
	backend := newMemoryInboxBackend()
	tokenBackend := newMemoryPushTokenStore()
	pushSender := newRecordingPushSender()
	push := newPushServiceWithSender(tokenBackend, pushSender)
	inbox := NewInboxStoreWithBackend(backend, push)
	groupInbox := NewGroupInboxStore(maxMessagesPerGroup, groupMessageTTL)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	recipientID := env.recipient.ID().String()
	push.RegisterToken(recipientID, "fcm-token", "ios")

	observedStoredCount := 0
	pushSender.onSend = func(_ context.Context, msg *messaging.Message) (string, error) {
		observedStoredCount = inbox.Count(recipientID)
		if msg.Data["type"] != "new_message" {
			t.Fatalf("type = %q, want %q", msg.Data["type"], "new_message")
		}
		if msg.Data["from"] != env.sender.ID().String() {
			t.Fatalf("from = %q, want %q", msg.Data["from"], env.sender.ID().String())
		}
		return "mock-message-id", nil
	}

	stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open inbox stream: %v", err)
	}
	defer stream.Close()

	sendInboxReq(t, stream, inboxRequest{
		Action:  "store",
		To:      recipientID,
		Message: "hello from sender",
	})

	resp := recvInboxResp(t, stream)
	if resp.Status != "OK" {
		t.Fatalf("status = %q, want %q", resp.Status, "OK")
	}

	waitFor(t, time.Second, func() bool {
		return pushSender.SendCallCount() == 1
	}, "expected push send after store")

	if observedStoredCount != 1 {
		t.Fatalf("stored count observed by push sender = %d, want 1", observedStoredCount)
	}

	stored := inbox.Retrieve(recipientID, 50)
	if len(stored) != 1 {
		t.Fatalf("expected 1 stored inbox message, got %d", len(stored))
	}
	if stored[0].Message != "hello from sender" {
		t.Fatalf("message = %q, want %q", stored[0].Message, "hello from sender")
	}
	if stored[0].From != env.sender.ID().String() {
		t.Fatalf("from = %q, want %q", stored[0].From, env.sender.ID().String())
	}
}

func TestPushService_SendNotification_UnregistersInvalidToken(t *testing.T) {
	tokenBackend := newMemoryPushTokenStore()
	pushSender := newRecordingPushSender()
	pushSender.err = fmt.Errorf("registration-token-not-registered")
	push := newPushServiceWithSender(tokenBackend, pushSender)

	push.RegisterToken("peer-target", "fcm-token", "ios")
	push.SendNotification(context.Background(), "peer-target", "peer-from")

	if pushSender.SendCallCount() != 1 {
		t.Fatalf("send calls = %d, want 1", pushSender.SendCallCount())
	}
	if entry := tokenBackend.LookupToken("peer-target"); entry != nil {
		t.Fatal("expected invalid token to be unregistered")
	}
}

func TestPushService_SendNotification_LogsWhenTokenMissing(t *testing.T) {
	tokenBackend := newMemoryPushTokenStore()
	pushSender := newRecordingPushSender()
	push := newPushServiceWithSender(tokenBackend, pushSender)

	var logBuffer bytes.Buffer
	previousWriter := log.Writer()
	log.SetOutput(&logBuffer)
	t.Cleanup(func() {
		log.SetOutput(previousWriter)
	})

	push.SendNotification(context.Background(), "peer-target", "peer-from")

	if pushSender.SendCallCount() != 0 {
		t.Fatalf("send calls = %d, want 0", pushSender.SendCallCount())
	}
	if !strings.Contains(logBuffer.String(), "[PUSH] No token registered for peer-target; skipping push") {
		t.Fatalf("expected missing-token push log, got %q", logBuffer.String())
	}
}

func TestHandleInboxStream_GroupStoreFansOutPushToRecipientsWithTokens(t *testing.T) {
	backend := newMemoryInboxBackend()
	tokenBackend := newMemoryPushTokenStore()
	pushSender := newRecordingPushSender()
	push := newPushServiceWithSender(tokenBackend, pushSender)
	inbox := NewInboxStoreWithBackend(backend, push)
	groupInbox := NewGroupInboxStore(maxMessagesPerGroup, groupMessageTTL)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	senderID := env.sender.ID().String()
	recipientOne := env.recipient.ID().String()
	recipientTwo := "peer-with-token-2"
	noTokenRecipient := "peer-without-token"

	push.RegisterToken(senderID, "self-token", "ios")
	push.RegisterToken(recipientOne, "token-1", "ios")
	push.RegisterToken(recipientTwo, "token-2", "android")

	stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open inbox stream: %v", err)
	}
	defer stream.Close()

	sendInboxReq(t, stream, inboxRequest{
		Action:           "group_store",
		GroupId:          "group-42",
		Message:          `{"text":"hello group"}`,
		RecipientPeerIds: []string{senderID, recipientOne, recipientTwo, noTokenRecipient},
		PushTitle:        "Test Group",
		PushBody:         "Alice: hello group",
	})

	resp := recvInboxResp(t, stream)
	if resp.Status != "OK" {
		t.Fatalf("status = %q, want %q", resp.Status, "OK")
	}

	waitFor(t, time.Second, func() bool {
		return pushSender.SendCallCount() == 2
	}, "expected group push fanout to registered recipients only")

	sentMessages := pushSender.Messages()
	if len(sentMessages) != 2 {
		t.Fatalf("sent messages = %d, want 2", len(sentMessages))
	}

	tokens := map[string]bool{}
	for _, msg := range sentMessages {
		tokens[msg.Token] = true
		if msg.Data["type"] != "group_message" {
			t.Fatalf("type = %q, want %q", msg.Data["type"], "group_message")
		}
		if msg.Data["groupId"] != "group-42" {
			t.Fatalf("groupId = %q, want %q", msg.Data["groupId"], "group-42")
		}
		if msg.Data["title"] != "Test Group" {
			t.Fatalf("title = %q, want %q", msg.Data["title"], "Test Group")
		}
		if msg.Data["body"] != "Alice: hello group" {
			t.Fatalf("body = %q, want %q", msg.Data["body"], "Alice: hello group")
		}
	}

	if !tokens["token-1"] || !tokens["token-2"] {
		t.Fatalf("expected fanout to token-1 and token-2, got %#v", tokens)
	}
	if tokens["self-token"] {
		t.Fatal("sender should be excluded from group push fanout")
	}

	storedMessages := groupInbox.Retrieve("group-42", 0)
	if len(storedMessages) != 1 {
		t.Fatalf("expected 1 stored group inbox message, got %d", len(storedMessages))
	}
	if storedMessages[0].Message != `{"text":"hello group"}` {
		t.Fatalf(
			"stored message = %q, want %q",
			storedMessages[0].Message,
			`{"text":"hello group"}`,
		)
	}
}

// --- Phase B: Top-level Notification field tests ---

func TestBuildChatPushMessage_TopLevelNotification(t *testing.T) {
	t.Run("has non-nil Notification with correct Title and Body", func(t *testing.T) {
		msg := buildChatPushMessage(chatPushRequest{
			Token:      "fcm-token",
			FromPeerID: "peer-from",
		})

		if msg.Notification == nil {
			t.Fatal("expected top-level Notification to be non-nil")
		}
		if msg.Notification.Title != pushNotificationTitle {
			t.Fatalf("Notification.Title = %q, want %q", msg.Notification.Title, pushNotificationTitle)
		}
		if msg.Notification.Body != pushNotificationBody {
			t.Fatalf("Notification.Body = %q, want %q", msg.Notification.Body, pushNotificationBody)
		}
	})

	t.Run("uses custom Title and Body when provided", func(t *testing.T) {
		msg := buildChatPushMessage(chatPushRequest{
			Token:      "fcm-token",
			FromPeerID: "peer-from",
			Title:      "Custom Title",
			Body:       "Custom Body",
		})

		if msg.Notification == nil {
			t.Fatal("expected top-level Notification to be non-nil")
		}
		if msg.Notification.Title != "Custom Title" {
			t.Fatalf("Notification.Title = %q, want %q", msg.Notification.Title, "Custom Title")
		}
		if msg.Notification.Body != "Custom Body" {
			t.Fatalf("Notification.Body = %q, want %q", msg.Notification.Body, "Custom Body")
		}
	})

	t.Run("preserves Data map with type, from, title, body", func(t *testing.T) {
		msg := buildChatPushMessage(chatPushRequest{
			Token:      "fcm-token",
			FromPeerID: "peer-from",
		})

		expected := map[string]string{
			"type":  "new_message",
			"from":  "peer-from",
			"title": pushNotificationTitle,
			"body":  pushNotificationBody,
		}
		for key, want := range expected {
			got, ok := msg.Data[key]
			if !ok {
				t.Fatalf("Data[%q] missing", key)
			}
			if got != want {
				t.Fatalf("Data[%q] = %q, want %q", key, got, want)
			}
		}
	})

	t.Run("preserves Android.Notification with ChannelID", func(t *testing.T) {
		msg := buildChatPushMessage(chatPushRequest{
			Token:      "fcm-token",
			FromPeerID: "peer-from",
		})

		if msg.Android == nil {
			t.Fatal("expected Android config to be non-nil")
		}
		if msg.Android.Notification == nil {
			t.Fatal("expected Android.Notification to be non-nil")
		}
		if msg.Android.Notification.ChannelID != pushNotificationChannelID {
			t.Fatalf(
				"Android.Notification.ChannelID = %q, want %q",
				msg.Android.Notification.ChannelID,
				pushNotificationChannelID,
			)
		}
		if msg.Android.Notification.Title != pushNotificationTitle {
			t.Fatalf(
				"Android.Notification.Title = %q, want %q",
				msg.Android.Notification.Title,
				pushNotificationTitle,
			)
		}
		if msg.Android.Notification.Body != pushNotificationBody {
			t.Fatalf(
				"Android.Notification.Body = %q, want %q",
				msg.Android.Notification.Body,
				pushNotificationBody,
			)
		}
	})

	t.Run("preserves APNS.Payload.Aps.Alert", func(t *testing.T) {
		msg := buildChatPushMessage(chatPushRequest{
			Token:      "fcm-token",
			FromPeerID: "peer-from",
		})

		if msg.APNS == nil || msg.APNS.Payload == nil || msg.APNS.Payload.Aps == nil {
			t.Fatal("expected APNS payload to be non-nil")
		}
		if msg.APNS.Payload.Aps.Alert == nil {
			t.Fatal("expected APNS Alert to be non-nil")
		}
		if msg.APNS.Payload.Aps.Alert.Title != pushNotificationTitle {
			t.Fatalf(
				"APNS Alert.Title = %q, want %q",
				msg.APNS.Payload.Aps.Alert.Title,
				pushNotificationTitle,
			)
		}
		if msg.APNS.Payload.Aps.Alert.Body != pushNotificationBody {
			t.Fatalf(
				"APNS Alert.Body = %q, want %q",
				msg.APNS.Payload.Aps.Alert.Body,
				pushNotificationBody,
			)
		}
	})
}
