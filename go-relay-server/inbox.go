package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"time"

	"github.com/libp2p/go-libp2p/core/network"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

const (
	InboxProtocol      = "/mknoon/inbox/1.0.0"
	maxFrameLen        = 128 * 1024 // 128 KB
	maxMessagesPerPeer = 100
	maxMessageAge      = 7 * 24 * time.Hour

	// Group inbox constants.
	maxMessagesPerGroup = 500
	groupMessageTTL     = 7 * 24 * time.Hour

	pushNotificationTitle     = "New Message"
	pushNotificationBody      = "You have a new message"
	pushNotificationChannelID = "mknoon_messages"
)

// --- Push service ---

type PushService struct {
	client       *messaging.Client
	tokenBackend PushTokenBackend
}

type tokenEntry struct {
	Token     string
	Platform  string
	UpdatedAt time.Time
}

func NewPushService(ctx context.Context, serviceAccountPath string) *PushService {
	return newPushServiceWithTokenBackend(ctx, serviceAccountPath, newMemoryPushTokenStore())
}

func newPushServiceWithTokenBackend(
	ctx context.Context,
	serviceAccountPath string,
	tokenBackend PushTokenBackend,
) *PushService {
	ps := &PushService{
		tokenBackend: tokenBackend,
	}

	opt := option.WithCredentialsFile(serviceAccountPath)
	app, err := firebase.NewApp(ctx, nil, opt)
	if err != nil {
		log.Printf("[PUSH] Firebase not initialized — push disabled: %v", err)
		return ps
	}

	client, err := app.Messaging(ctx)
	if err != nil {
		log.Printf("[PUSH] Firebase messaging init failed — push disabled: %v", err)
		return ps
	}

	ps.client = client
	log.Println("[PUSH] Firebase Admin SDK initialized")
	return ps
}

// NewPushServiceWithBackend creates a PushService with a custom token backend.
func NewPushServiceWithBackend(tokenBackend PushTokenBackend) *PushService {
	return &PushService{
		tokenBackend: tokenBackend,
	}
}

func (ps *PushService) Status() string {
	if ps.client != nil {
		return "enabled"
	}
	return "disabled (no service account)"
}

func (ps *PushService) RegisterToken(peerId, token, platform string) {
	ps.tokenBackend.RegisterToken(peerId, token, platform)
	log.Printf("[PUSH] Token registered for %s (%s)", peerId[:min(20, len(peerId))], platform)
}

func (ps *PushService) UnregisterToken(peerId string) {
	ps.tokenBackend.UnregisterToken(peerId)
	log.Printf("[PUSH] Token unregistered for %s", peerId[:min(20, len(peerId))])
}

func (ps *PushService) SendNotification(ctx context.Context, toPeerId, fromPeerId string) {
	if ps.client == nil {
		return
	}

	entry := ps.tokenBackend.LookupToken(toPeerId)
	if entry == nil {
		return
	}

	msg := buildPushMessage(entry.Token, fromPeerId)

	_, err := ps.client.Send(ctx, msg)
	if err != nil {
		log.Printf("[PUSH] Failed to send to %s: %v", toPeerId[:min(20, len(toPeerId))], err)
		// Remove invalid tokens
		if isInvalidTokenError(err) {
			ps.tokenBackend.UnregisterToken(toPeerId)
			pushSentCounter.WithLabelValues("invalid_token").Inc()
			log.Printf("[PUSH] Removed invalid token for %s", toPeerId[:min(20, len(toPeerId))])
		} else {
			pushSentCounter.WithLabelValues("failed").Inc()
		}
		return
	}
	pushSentCounter.WithLabelValues("success").Inc()
	log.Printf("[PUSH] Notification sent to %s", toPeerId[:min(20, len(toPeerId))])
}

func buildPushMessage(token, fromPeerId string) *messaging.Message {
	return &messaging.Message{
		Token: token,
		Data: map[string]string{
			"type":  "new_message",
			"from":  fromPeerId,
			"title": pushNotificationTitle,
			"body":  pushNotificationBody,
		},
		Android: &messaging.AndroidConfig{
			Priority: "high",
			Notification: &messaging.AndroidNotification{
				Title:     pushNotificationTitle,
				Body:      pushNotificationBody,
				ChannelID: pushNotificationChannelID,
			},
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{
				"apns-priority":  "10",
				"apns-push-type": "alert",
			},
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{
					ContentAvailable: true,
					Alert: &messaging.ApsAlert{
						Title: pushNotificationTitle,
						Body:  pushNotificationBody,
					},
				},
			},
		},
	}
}

func (ps *PushService) TokenCount() int {
	return ps.tokenBackend.TokenCount()
}

func (ps *PushService) PlatformCounts() map[string]int {
	return ps.tokenBackend.PlatformCounts()
}

func isInvalidTokenError(err error) bool {
	// Firebase returns specific error codes for invalid tokens
	errStr := err.Error()
	return contains(errStr, "registration-token-not-registered") ||
		contains(errStr, "invalid-registration-token")
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsImpl(s, substr))
}

func containsImpl(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

// --- Inbox store ---

type inboxMessage struct {
	From      string                 `json:"from"`
	Message   string                 `json:"message"`
	Timestamp int64                  `json:"timestamp"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
}

// InboxStore wraps an InboxBackend and a PushService.
type InboxStore struct {
	backend InboxBackend
	push    *PushService
}

// NewInboxStore creates an InboxStore with an in-memory backend.
func NewInboxStore(push *PushService) *InboxStore {
	return &InboxStore{
		backend: newMemoryInboxBackend(),
		push:    push,
	}
}

// NewInboxStoreWithBackend creates an InboxStore with a custom backend.
func NewInboxStoreWithBackend(backend InboxBackend, push *PushService) *InboxStore {
	return &InboxStore{
		backend: backend,
		push:    push,
	}
}

func (is *InboxStore) Store(toPeerId string, entry inboxMessage) {
	is.backend.Store(toPeerId, entry)
	inboxStoredCounter.Inc()
	if biz != nil {
		biz.RecordMessageStored()
	}

	log.Printf("[INBOX] Stored message for %s from %s",
		toPeerId[:min(20, len(toPeerId))],
		entry.From[:min(20, len(entry.From))])
}

func (is *InboxStore) Retrieve(peerId string, limit int) []inboxMessage {
	messages, hasMore := is.backend.Retrieve(peerId, limit)

	if len(messages) == 0 {
		log.Printf("[INBOX] No messages for %s", peerId[:min(20, len(peerId))])
		return nil
	}

	inboxRetrievedCounter.Add(float64(len(messages)))

	remaining := 0
	if hasMore {
		remaining = is.backend.Count(peerId)
	}
	log.Printf("[INBOX] Retrieved %d message(s) for %s — deleted from memory (%d remaining)",
		len(messages), peerId[:min(20, len(peerId))], remaining)
	return messages
}

// RetrieveWithMeta retrieves messages and returns pagination metadata.
func (is *InboxStore) RetrieveWithMeta(peerId string, limit int) ([]inboxMessage, bool) {
	messages, hasMore := is.backend.Retrieve(peerId, limit)

	if len(messages) > 0 {
		inboxRetrievedCounter.Add(float64(len(messages)))
	}

	return messages, hasMore
}

func (is *InboxStore) Count(peerId string) int {
	return is.backend.Count(peerId)
}

func (is *InboxStore) Stats() (totalPeers, totalMessages int) {
	return is.backend.Stats()
}

// --- Group Inbox store ---

type groupInboxMessage struct {
	From      string `json:"from"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
	ID        string `json:"id,omitempty"`
}

// GroupInboxStore wraps a GroupInboxBackend.
type GroupInboxStore struct {
	backend GroupInboxBackend
}

// NewGroupInboxStore creates a store with an in-memory backend.
func NewGroupInboxStore(maxPerGroup int, ttl time.Duration) *GroupInboxStore {
	return &GroupInboxStore{
		backend: newMemoryGroupInboxBackend(maxPerGroup, ttl),
	}
}

// NewGroupInboxStoreWithBackend creates a store with a custom backend.
func NewGroupInboxStoreWithBackend(backend GroupInboxBackend) *GroupInboxStore {
	return &GroupInboxStore{
		backend: backend,
	}
}

func (s *GroupInboxStore) Store(groupId, from, message string) error {
	err := s.backend.Store(groupId, from, message)
	if err == nil {
		groupInboxStoredCounter.Inc()
		log.Printf("[GROUP_INBOX] Stored message for group %s from %s",
			groupId[:min(20, len(groupId))],
			from[:min(20, len(from))])
	}
	return err
}

func (s *GroupInboxStore) Retrieve(groupId string, sinceTimestamp int64) []groupInboxMessage {
	result := s.backend.RetrieveSince(groupId, sinceTimestamp)
	groupInboxRetrievedCounter.Add(float64(len(result)))

	log.Printf("[GROUP_INBOX] Retrieved %d message(s) for group %s (since=%d)",
		len(result), groupId[:min(20, len(groupId))], sinceTimestamp)
	return result
}

// RetrieveWithCursor retrieves messages using cursor-based pagination.
func (s *GroupInboxStore) RetrieveWithCursor(groupId string, cursor string, limit int) ([]groupInboxMessage, string) {
	messages, nextCursor := s.backend.RetrieveCursor(groupId, cursor, limit)
	groupInboxRetrievedCounter.Add(float64(len(messages)))
	return messages, nextCursor
}

// Prune removes expired messages across all groups. Called periodically.
func (s *GroupInboxStore) Prune() {
	s.backend.Prune()
}

func (s *GroupInboxStore) Stats() (groups int, totalMessages int) {
	return s.backend.Stats()
}

// --- 4-byte BE framing (matches JS inbox protocol) ---

func readFrame(r io.Reader) ([]byte, error) {
	var lenBuf [4]byte
	if _, err := io.ReadFull(r, lenBuf[:]); err != nil {
		return nil, fmt.Errorf("read length: %w", err)
	}
	length := binary.BigEndian.Uint32(lenBuf[:])
	if length > maxFrameLen {
		return nil, fmt.Errorf("frame too large: %d", length)
	}
	data := make([]byte, length)
	if _, err := io.ReadFull(r, data); err != nil {
		return nil, fmt.Errorf("read payload: %w", err)
	}
	return data, nil
}

func writeFrame(w io.Writer, data []byte) error {
	if len(data) > maxFrameLen {
		return fmt.Errorf("frame too large: %d", len(data))
	}
	var lenBuf [4]byte
	binary.BigEndian.PutUint32(lenBuf[:], uint32(len(data)))
	if _, err := w.Write(lenBuf[:]); err != nil {
		return fmt.Errorf("write length: %w", err)
	}
	if _, err := w.Write(data); err != nil {
		return fmt.Errorf("write payload: %w", err)
	}
	return nil
}

// --- Inbox stream handler ---

type inboxRequest struct {
	Action   string                 `json:"action"`
	To       string                 `json:"to,omitempty"`
	From     string                 `json:"from,omitempty"`
	Message  string                 `json:"message,omitempty"`
	Metadata map[string]interface{} `json:"metadata,omitempty"`
	Limit    int                    `json:"limit,omitempty"`
	Token    string                 `json:"token,omitempty"`
	Platform string                 `json:"platform,omitempty"`
	// Group inbox fields.
	GroupId        string `json:"groupId,omitempty"`
	SinceTimestamp int64  `json:"sinceTimestamp,omitempty"`
	Cursor         string `json:"cursor,omitempty"`
}

type inboxResponse struct {
	Status        string              `json:"status"`
	Error         string              `json:"error,omitempty"`
	Messages      []inboxMessage      `json:"messages,omitempty"`
	HasMore       bool                `json:"hasMore,omitempty"`
	GroupMessages []groupInboxMessage `json:"groupMessages,omitempty"`
	NextCursor    string              `json:"nextCursor,omitempty"`
}

func HandleInboxStream(s network.Stream, inbox *InboxStore, groupInbox *GroupInboxStore) {
	start := time.Now()
	activeStreams.WithLabelValues("inbox").Inc()
	streamResult := "ok"
	defer func() {
		activeStreams.WithLabelValues("inbox").Dec()
		streamDuration.WithLabelValues("inbox", streamResult).Observe(time.Since(start).Seconds())
		log.Printf("[INBOX] stream handled in %s", time.Since(start))
	}()
	defer s.Close()

	remotePeer := s.Conn().RemotePeer().String()
	log.Printf("[INBOX] Incoming stream from %s", remotePeer[:min(20, len(remotePeer))])

	requestBytes, err := readFrame(s)
	if err != nil {
		streamResult = "error"
		streamErrorsCounter.WithLabelValues("inbox", "read").Inc()
		log.Printf("[INBOX] Read error from %s: %v", remotePeer[:min(20, len(remotePeer))], err)
		return
	}

	var req inboxRequest
	if err := json.Unmarshal(requestBytes, &req); err != nil {
		streamResult = "error"
		streamErrorsCounter.WithLabelValues("inbox", "decode").Inc()
		log.Printf("[INBOX] JSON decode error: %v", err)
		writeResponse(s, inboxResponse{Status: "ERROR", Error: "invalid JSON"})
		return
	}

	var resp inboxResponse

	switch req.Action {
	case "store":
		if req.To == "" || req.Message == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required fields: to, message"}
		} else {
			from := req.From
			if from == "" {
				from = remotePeer
			}
			entry := inboxMessage{
				From:      from,
				Message:   req.Message,
				Timestamp: time.Now().UnixMilli(),
				Metadata:  req.Metadata,
			}
			inbox.Store(req.To, entry)
			resp = inboxResponse{Status: "OK"}

			// Fire push notification (non-blocking)
			go inbox.push.SendNotification(context.Background(), req.To, from)
		}

	case "retrieve":
		limit := req.Limit
		if limit <= 0 {
			limit = 50
		}
		messages, hasMore := inbox.RetrieveWithMeta(remotePeer, limit)
		if len(messages) > 0 {
			resp = inboxResponse{Status: "OK", Messages: messages, HasMore: hasMore}
		} else {
			resp = inboxResponse{Status: "NO_MESSAGES"}
		}

	case "register_token":
		if req.Token == "" || req.Platform == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required fields: token, platform"}
		} else {
			inbox.push.RegisterToken(remotePeer, req.Token, req.Platform)
			resp = inboxResponse{Status: "OK"}
		}

	case "unregister_token":
		inbox.push.UnregisterToken(remotePeer)
		resp = inboxResponse{Status: "OK"}

	case "group_store":
		if req.GroupId == "" || req.Message == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required fields: groupId, message"}
		} else {
			from := req.From
			if from == "" {
				from = remotePeer
			}
			if err := groupInbox.Store(req.GroupId, from, req.Message); err != nil {
				resp = inboxResponse{Status: "ERROR", Error: err.Error()}
			} else {
				resp = inboxResponse{Status: "OK"}
			}
		}

	case "group_retrieve":
		if req.GroupId == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required field: groupId"}
		} else {
			messages := groupInbox.Retrieve(req.GroupId, req.SinceTimestamp)
			if len(messages) > 0 {
				resp = inboxResponse{Status: "OK", GroupMessages: messages}
			} else {
				resp = inboxResponse{Status: "NO_MESSAGES"}
			}
		}

	case "group_retrieve_cursor":
		if req.GroupId == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required field: groupId"}
		} else {
			limit := req.Limit
			if limit <= 0 {
				limit = 50
			}
			messages, nextCursor := groupInbox.RetrieveWithCursor(req.GroupId, req.Cursor, limit)
			if len(messages) > 0 {
				resp = inboxResponse{Status: "OK", GroupMessages: messages, NextCursor: nextCursor}
			} else {
				resp = inboxResponse{Status: "NO_MESSAGES"}
			}
		}

	default:
		resp = inboxResponse{Status: "ERROR", Error: fmt.Sprintf("Unknown action: %s", req.Action)}
	}

	writeResponse(s, resp)
	log.Printf("[INBOX] Stream closed for %s", remotePeer[:min(20, len(remotePeer))])
}

func writeResponse(s network.Stream, resp inboxResponse) {
	data, err := json.Marshal(resp)
	if err != nil {
		streamErrorsCounter.WithLabelValues("inbox", "write").Inc()
		log.Printf("[INBOX] JSON encode error: %v", err)
		return
	}
	if err := writeFrame(s, data); err != nil {
		streamErrorsCounter.WithLabelValues("inbox", "write").Inc()
		log.Printf("[INBOX] Write error: %v", err)
	}
}
