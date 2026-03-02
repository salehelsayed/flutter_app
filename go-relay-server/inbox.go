package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p/core/network"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

const (
	InboxProtocol       = "/mknoon/inbox/1.0.0"
	maxFrameLen         = 128 * 1024     // 128 KB
	maxMessagesPerPeer  = 100
	maxMessageAge       = 7 * 24 * time.Hour

	// Group inbox constants.
	maxMessagesPerGroup = 500
	groupMessageTTL     = 7 * 24 * time.Hour
)

// --- Push service ---

type PushService struct {
	client *messaging.Client
	tokens sync.Map // peerId → tokenEntry
}

type tokenEntry struct {
	Token     string
	Platform  string
	UpdatedAt time.Time
}

func NewPushService(ctx context.Context, serviceAccountPath string) *PushService {
	ps := &PushService{}

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

func (ps *PushService) Status() string {
	if ps.client != nil {
		return "enabled"
	}
	return "disabled (no service account)"
}

func (ps *PushService) RegisterToken(peerId, token, platform string) {
	ps.tokens.Store(peerId, tokenEntry{
		Token:     token,
		Platform:  platform,
		UpdatedAt: time.Now(),
	})
	log.Printf("[PUSH] Token registered for %s (%s)", peerId[:min(20, len(peerId))], platform)
}

func (ps *PushService) UnregisterToken(peerId string) {
	ps.tokens.Delete(peerId)
	log.Printf("[PUSH] Token unregistered for %s", peerId[:min(20, len(peerId))])
}

func (ps *PushService) SendNotification(ctx context.Context, toPeerId, fromPeerId string) {
	if ps.client == nil {
		return
	}

	val, ok := ps.tokens.Load(toPeerId)
	if !ok {
		return
	}
	entry := val.(tokenEntry)

	msg := &messaging.Message{
		Token: entry.Token,
		Data: map[string]string{
			"type": "new_message",
			"from": fromPeerId,
		},
		Android: &messaging.AndroidConfig{
			Priority: "high",
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
						Title: "New Message",
						Body:  "You have a new message",
					},
				},
			},
		},
	}

	_, err := ps.client.Send(ctx, msg)
	if err != nil {
		log.Printf("[PUSH] Failed to send to %s: %v", toPeerId[:min(20, len(toPeerId))], err)
		// Remove invalid tokens
		if isInvalidTokenError(err) {
			ps.tokens.Delete(toPeerId)
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

func (ps *PushService) TokenCount() int {
	count := 0
	ps.tokens.Range(func(_, _ interface{}) bool {
		count++
		return true
	})
	return count
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

type InboxStore struct {
	mu    sync.Mutex
	store map[string][]inboxMessage // peerId → messages
	push  *PushService
}

func NewInboxStore(push *PushService) *InboxStore {
	return &InboxStore{
		store: make(map[string][]inboxMessage),
		push:  push,
	}
}

func (is *InboxStore) Store(toPeerId string, entry inboxMessage) {
	is.mu.Lock()
	defer is.mu.Unlock()

	before := is.store[toPeerId]
	messages := is.pruneExpired(before)
	expired := len(before) - len(messages)
	if expired > 0 {
		inboxExpiredCounter.Add(float64(expired))
	}

	// Cap at max
	if len(messages) >= maxMessagesPerPeer {
		overflow := len(messages) - maxMessagesPerPeer + 1
		inboxCappedCounter.Add(float64(overflow))
		messages = messages[len(messages)-maxMessagesPerPeer+1:]
	}

	messages = append(messages, entry)
	is.store[toPeerId] = messages
	inboxStoredCounter.Inc()

	log.Printf("[INBOX] Stored message for %s from %s (total: %d)",
		toPeerId[:min(20, len(toPeerId))],
		entry.From[:min(20, len(entry.From))],
		len(messages))
}

func (is *InboxStore) Retrieve(peerId string, limit int) []inboxMessage {
	is.mu.Lock()
	defer is.mu.Unlock()

	before := is.store[peerId]
	messages := is.pruneExpired(before)
	expired := len(before) - len(messages)
	if expired > 0 {
		inboxExpiredCounter.Add(float64(expired))
	}
	is.store[peerId] = messages

	if len(messages) == 0 {
		log.Printf("[INBOX] No messages for %s", peerId[:min(20, len(peerId))])
		return nil
	}

	if limit > len(messages) {
		limit = len(messages)
	}

	result := make([]inboxMessage, limit)
	copy(result, messages[:limit])

	remaining := messages[limit:]
	if len(remaining) > 0 {
		is.store[peerId] = remaining
	} else {
		delete(is.store, peerId)
	}

	inboxRetrievedCounter.Add(float64(len(result)))

	log.Printf("[INBOX] Retrieved %d message(s) for %s — deleted from memory (%d remaining)",
		len(result), peerId[:min(20, len(peerId))], len(remaining))
	return result
}

func (is *InboxStore) Count(peerId string) int {
	is.mu.Lock()
	defer is.mu.Unlock()
	return len(is.store[peerId])
}

func (is *InboxStore) Stats() (totalPeers, totalMessages int) {
	is.mu.Lock()
	defer is.mu.Unlock()
	totalPeers = len(is.store)
	for _, msgs := range is.store {
		totalMessages += len(msgs)
	}
	return
}

func (is *InboxStore) pruneExpired(messages []inboxMessage) []inboxMessage {
	if len(messages) == 0 {
		return messages
	}
	cutoff := time.Now().Add(-maxMessageAge).UnixMilli()
	var result []inboxMessage
	for _, m := range messages {
		if m.Timestamp > cutoff {
			result = append(result, m)
		}
	}
	return result
}

// --- Group Inbox store ---

type groupInboxMessage struct {
	From      string `json:"from"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
}

type GroupInboxStore struct {
	mu          sync.RWMutex
	messages    map[string][]groupInboxMessage // key: groupId
	maxPerGroup int
	ttl         time.Duration
}

func NewGroupInboxStore(maxPerGroup int, ttl time.Duration) *GroupInboxStore {
	return &GroupInboxStore{
		messages:    make(map[string][]groupInboxMessage),
		maxPerGroup: maxPerGroup,
		ttl:         ttl,
	}
}

func (s *GroupInboxStore) Store(groupId, from, message string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	msgs := s.pruneExpiredLocked(s.messages[groupId])

	// Cap enforcement: drop oldest when exceeding max.
	if len(msgs) >= s.maxPerGroup {
		overflow := len(msgs) - s.maxPerGroup + 1
		groupInboxCappedCounter.Add(float64(overflow))
		msgs = msgs[overflow:]
	}

	msgs = append(msgs, groupInboxMessage{
		From:      from,
		Message:   message,
		Timestamp: time.Now().UnixMilli(),
	})
	s.messages[groupId] = msgs
	groupInboxStoredCounter.Inc()

	log.Printf("[GROUP_INBOX] Stored message for group %s from %s (total: %d)",
		groupId[:min(20, len(groupId))],
		from[:min(20, len(from))],
		len(msgs))
	return nil
}

func (s *GroupInboxStore) Retrieve(groupId string, sinceTimestamp int64) []groupInboxMessage {
	s.mu.RLock()
	defer s.mu.RUnlock()

	msgs := s.messages[groupId]
	if len(msgs) == 0 {
		return nil
	}

	var result []groupInboxMessage
	cutoff := time.Now().Add(-s.ttl).UnixMilli()
	for _, m := range msgs {
		if m.Timestamp <= cutoff {
			continue // expired
		}
		if sinceTimestamp > 0 && m.Timestamp <= sinceTimestamp {
			continue // before requested window
		}
		result = append(result, m)
	}

	groupInboxRetrievedCounter.Add(float64(len(result)))

	log.Printf("[GROUP_INBOX] Retrieved %d message(s) for group %s (since=%d)",
		len(result), groupId[:min(20, len(groupId))], sinceTimestamp)
	return result
}

// Prune removes expired messages across all groups. Called periodically.
func (s *GroupInboxStore) Prune() {
	s.mu.Lock()
	defer s.mu.Unlock()

	totalExpired := 0
	for groupId, msgs := range s.messages {
		before := len(msgs)
		pruned := s.pruneExpiredLocked(msgs)
		expired := before - len(pruned)
		totalExpired += expired

		if len(pruned) == 0 {
			delete(s.messages, groupId)
		} else {
			s.messages[groupId] = pruned
		}
	}

	if totalExpired > 0 {
		groupInboxExpiredCounter.Add(float64(totalExpired))
		log.Printf("[GROUP_INBOX] Pruned %d expired messages across %d groups",
			totalExpired, len(s.messages))
	}
}

func (s *GroupInboxStore) Stats() (groups int, totalMessages int) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	groups = len(s.messages)
	for _, msgs := range s.messages {
		totalMessages += len(msgs)
	}
	return
}

func (s *GroupInboxStore) pruneExpiredLocked(messages []groupInboxMessage) []groupInboxMessage {
	if len(messages) == 0 {
		return messages
	}
	cutoff := time.Now().Add(-s.ttl).UnixMilli()
	var result []groupInboxMessage
	for _, m := range messages {
		if m.Timestamp > cutoff {
			result = append(result, m)
		}
	}
	return result
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
}

type inboxResponse struct {
	Status        string              `json:"status"`
	Error         string              `json:"error,omitempty"`
	Messages      []inboxMessage      `json:"messages,omitempty"`
	GroupMessages []groupInboxMessage `json:"groupMessages,omitempty"`
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
		messages := inbox.Retrieve(remotePeer, limit)
		if len(messages) > 0 {
			resp = inboxResponse{Status: "OK", Messages: messages}
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
