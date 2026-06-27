package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"strings"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"

	"github.com/google/uuid"
)

const (
	InboxProtocol      = "/mknoon/inbox/1.0.0"
	maxFrameLen        = 128 * 1024 // 128 KB
	maxMessagesPerPeer = 100
	maxMessageAge      = 7 * 24 * time.Hour

	// Group inbox constants.
	maxMessagesPerGroup = 500
	groupMessageTTL     = 7 * 24 * time.Hour

	pushNotificationTitle      = "New Message"
	pushNotificationBody       = "You have a new message"
	pushNotificationChannelID  = "mknoon_messages"
	pushNotificationSound      = "default"
	contactRequestPushTitle    = "New Contact Request"
	contactRequestPushBody     = "Open Mknoon to respond"
	groupInvitePushTitle       = "Group Invite"
	groupInvitePushBody        = "Open Mknoon to review"
	introPushNotificationTitle = "New Introduction"
	introPushNotificationBody  = "Open Mknoon to review"

	// maxPushDataBytes caps the assembled FCM `data` payload. FCM rejects any
	// message whose data exceeds 4096 bytes with "Message is too large. The
	// maximum is 4K (4096 bytes)"; a media envelope's encrypted descriptor
	// (ciphertext) plus the ~1.4 KB base64 ML-KEM `kem` pushes a silent
	// ciphertext-only push past that limit, so an offline media recipient gets
	// NO notification at all. When the assembled data would exceed this budget
	// we drop the encrypted fields and emit a visible generic fallback instead.
	// 4000 leaves headroom under FCM's 4096 for SDK/wire overhead.
	maxPushDataBytes = 4000
)

func defaultPushRetryDelays() []time.Duration {
	return []time.Duration{
		250 * time.Millisecond,
		1 * time.Second,
	}
}

// --- Push service ---

type PushService struct {
	client       *messaging.Client
	tokenBackend PushTokenBackend
	sender       func(context.Context, *messaging.Message) (string, error)
	retryDelays  []time.Duration
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
		retryDelays:  defaultPushRetryDelays(),
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
		retryDelays:  defaultPushRetryDelays(),
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

func (ps *PushService) SendNotification(ctx context.Context, toPeerId, fromPeerId, message string) {
	entry := ps.tokenBackend.LookupToken(toPeerId)
	if entry == nil {
		pushSentCounter.WithLabelValues("missing_token").Inc()
		log.Printf("[PUSH] Skip chat push to %s: no registered token",
			toPeerId[:min(20, len(toPeerId))])
		return
	}

	msg := buildPushMessage(entry.Token, fromPeerId, message)
	ps.sendWithRetry(ctx, toPeerId, msg, "chat", "")
}

func (ps *PushService) SendGroupNotification(
	ctx context.Context,
	toPeerId string,
	groupId string,
	messageID string,
	message string,
) {
	entry := ps.tokenBackend.LookupToken(toPeerId)
	if entry == nil {
		pushSentCounter.WithLabelValues("missing_token").Inc()
		log.Printf("[PUSH] Skip group push to %s for group %s: no registered token",
			toPeerId[:min(20, len(toPeerId))],
			groupId[:min(20, len(groupId))])
		return
	}

	msg := buildGroupPushMessage(entry.Token, groupId, messageID, message)
	ps.sendWithRetry(ctx, toPeerId, msg, "group", groupId)
}

func (ps *PushService) send(ctx context.Context, msg *messaging.Message) error {
	if ps.sender != nil {
		_, err := ps.sender(ctx, msg)
		return err
	}
	if ps.client == nil {
		return nil
	}
	_, err := ps.client.Send(ctx, msg)
	return err
}

func (ps *PushService) sendWithRetry(
	ctx context.Context,
	toPeerId string,
	msg *messaging.Message,
	pushKind string,
	groupId string,
) {
	totalAttempts := len(ps.retryDelays) + 1

	for attempt := 1; attempt <= totalAttempts; attempt++ {
		err := ps.send(ctx, msg)
		if err == nil {
			pushSentCounter.WithLabelValues("success").Inc()
			if pushKind == "group" {
				log.Printf("[PUSH] Group notification sent to %s for group %s (attempt %d/%d)",
					toPeerId[:min(20, len(toPeerId))],
					groupId[:min(20, len(groupId))],
					attempt,
					totalAttempts)
			} else {
				log.Printf("[PUSH] Notification sent to %s (attempt %d/%d)",
					toPeerId[:min(20, len(toPeerId))],
					attempt,
					totalAttempts)
			}
			return
		}

		if isInvalidTokenError(err) {
			ps.tokenBackend.UnregisterToken(toPeerId)
			pushSentCounter.WithLabelValues("invalid_token").Inc()
			log.Printf("[PUSH] Removed invalid token for %s after %s push error: %v",
				toPeerId[:min(20, len(toPeerId))],
				pushKind,
				err)
			return
		}

		if attempt == totalAttempts {
			pushSentCounter.WithLabelValues("failed").Inc()
			if pushKind == "group" {
				log.Printf("[PUSH] Failed to send group push to %s for group %s after %d attempt(s): %v",
					toPeerId[:min(20, len(toPeerId))],
					groupId[:min(20, len(groupId))],
					attempt,
					err)
			} else {
				log.Printf("[PUSH] Failed to send push to %s after %d attempt(s): %v",
					toPeerId[:min(20, len(toPeerId))],
					attempt,
					err)
			}
			return
		}

		delay := ps.retryDelays[attempt-1]
		if pushKind == "group" {
			log.Printf("[PUSH] Group push to %s for group %s failed on attempt %d/%d: %v; retrying in %s",
				toPeerId[:min(20, len(toPeerId))],
				groupId[:min(20, len(groupId))],
				attempt,
				totalAttempts,
				err,
				delay)
		} else {
			log.Printf("[PUSH] Push to %s failed on attempt %d/%d: %v; retrying in %s",
				toPeerId[:min(20, len(toPeerId))],
				attempt,
				totalAttempts,
				err,
				delay)
		}

		if !waitForRetryDelay(ctx, delay) {
			pushSentCounter.WithLabelValues("failed").Inc()
			log.Printf("[PUSH] Aborting %s push retry to %s: context canceled",
				pushKind,
				toPeerId[:min(20, len(toPeerId))])
			return
		}
	}
}

func waitForRetryDelay(ctx context.Context, delay time.Duration) bool {
	if delay <= 0 {
		select {
		case <-ctx.Done():
			return false
		default:
			return true
		}
	}

	timer := time.NewTimer(delay)
	defer timer.Stop()

	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}

func buildPushMessage(token, fromPeerId, message string) *messaging.Message {
	metadata := extractChatPushMetadata(message)
	if metadata.RouteType == "new_message" {
		data := map[string]string{
			"type":      "new_message",
			"sender_id": fromPeerId,
		}
		if metadata.MessageID != "" {
			data["message_id"] = metadata.MessageID
		}
		addChatEncryptedPushData(data, message)
		if pushDataSize(data) > maxPushDataBytes {
			// Oversized media envelope: FCM would reject the silent ciphertext-only
			// push (>4 KB). Drop the encrypted payload, keep only routing, and emit a
			// visible generic fallback so the offline recipient is still alerted.
			fallback := map[string]string{
				"type":                "new_message",
				"sender_id":           fromPeerId,
				"preview_unavailable": "1",
			}
			if metadata.MessageID != "" {
				fallback["message_id"] = metadata.MessageID
			}
			return buildOversizedFallbackPushMessage(token, fallback, fromPeerId)
		}
		return buildCiphertextOnlyPushMessage(token, data, fromPeerId)
	}

	resolvedTitle := metadata.SenderUsername
	switch metadata.RouteType {
	case "intros":
		resolvedTitle = introPushNotificationTitle
	case "contact_request":
		resolvedTitle = contactRequestPushTitle
	case "group_invite":
		if metadata.GroupName != "" {
			resolvedTitle = metadata.GroupName
		} else {
			resolvedTitle = groupInvitePushTitle
		}
	case "new_message":
		if resolvedTitle == "" {
			resolvedTitle = pushNotificationTitle
		}
	default:
		resolvedTitle = pushNotificationTitle
	}
	resolvedBody := metadata.Body
	if resolvedBody == "" {
		switch metadata.RouteType {
		case "intros":
			resolvedBody = introPushNotificationBody
		case "contact_request":
			resolvedBody = contactRequestPushBody
		case "group_invite":
			resolvedBody = groupInvitePushBody
		default:
			resolvedBody = pushNotificationBody
		}
	}

	data := map[string]string{
		"type":  metadata.RouteType,
		"title": resolvedTitle,
		"body":  resolvedBody,
	}
	if metadata.RouteType == "new_message" || metadata.RouteType == "contact_request" {
		data["sender_id"] = fromPeerId
	}
	if metadata.RouteType == "group_invite" && metadata.GroupID != "" {
		data["groupId"] = metadata.GroupID
	}
	if metadata.MessageID != "" {
		data["message_id"] = metadata.MessageID
	}
	if metadata.SenderUsername != "" {
		data["sender_username"] = metadata.SenderUsername
		data["senderUsername"] = metadata.SenderUsername
	}

	return &messaging.Message{
		Token: token,
		Notification: &messaging.Notification{
			Title: resolvedTitle,
			Body:  resolvedBody,
		},
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
			Notification: &messaging.AndroidNotification{
				Title:     resolvedTitle,
				Body:      resolvedBody,
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
					Sound:            pushNotificationSound,
					Alert: &messaging.ApsAlert{
						Title: resolvedTitle,
						Body:  resolvedBody,
					},
				},
			},
		},
	}
}

func buildGroupPushMessage(token, groupId, messageID, message string) *messaging.Message {
	data := map[string]string{
		"type":    "group_message",
		"groupId": groupId,
	}
	if messageID != "" {
		data["message_id"] = messageID
	}
	addGroupEncryptedPushData(data, message)
	if pushDataSize(data) > maxPushDataBytes {
		// Oversized group media envelope: same as the 1:1 path — drop the encrypted
		// payload, keep only routing, emit a visible generic fallback under budget.
		fallback := map[string]string{
			"type":                "group_message",
			"groupId":             groupId,
			"preview_unavailable": "1",
		}
		if data["message_id"] != "" {
			fallback["message_id"] = data["message_id"]
		}
		return buildOversizedFallbackPushMessage(token, fallback, groupId)
	}

	return buildCiphertextOnlyPushMessage(token, data, groupId)
}

func buildCiphertextOnlyPushMessage(token string, data map[string]string, threadID string) *messaging.Message {
	aps := &messaging.Aps{
		ContentAvailable: true,
		MutableContent:   true,
		Sound:            pushNotificationSound,
		Alert: &messaging.ApsAlert{
			Title: pushNotificationTitle,
			Body:  pushNotificationBody,
		},
	}
	if threadID != "" {
		aps.ThreadID = threadID
	}

	return &messaging.Message{
		Token: token,
		Data:  data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{
				"apns-priority":  "10",
				"apns-push-type": "alert",
			},
			Payload: &messaging.APNSPayload{
				Aps:        aps,
				CustomData: apnsCustomDataFromPushData(data),
			},
		},
	}
}

// pushDataSize returns the byte size of the assembled FCM `data` map, counting
// both keys and values. FCM measures the whole data payload against its 4096
// byte limit, so the budget check must include keys, not just values.
func pushDataSize(data map[string]string) int {
	total := 0
	for key, value := range data {
		total += len(key) + len(value)
	}
	return total
}

// buildOversizedFallbackPushMessage builds a VISIBLE, under-budget notification
// for a push whose encrypted payload would exceed maxPushDataBytes (e.g. a media
// envelope). The caller has already trimmed `data` down to minimal routing keys
// (+ preview_unavailable="1"); here we attach generic, content-free copy to the
// FCM/Android/APNS notification blocks so the offline recipient is alerted and
// the client fetches the real message from the inbox on open. Unlike the silent
// ciphertext-only push, there is nothing to decrypt, so MutableContent stays off
// and the generic alert is shown directly.
func buildOversizedFallbackPushMessage(token string, data map[string]string, threadID string) *messaging.Message {
	// Defensive clamp: the routing-only fallback must itself stay under budget.
	// message_id is copied from the remote-supplied envelope (id/messageId), so a
	// pathologically large id could keep the fallback oversized and re-trigger the
	// FCM rejection. Drop it if needed — routing by sender_id/groupId (server-bounded
	// peer/group identifiers) still alerts the recipient, so INV-1 holds unconditionally.
	if pushDataSize(data) > maxPushDataBytes {
		delete(data, "message_id")
	}

	pushSentCounter.WithLabelValues("oversized_fallback").Inc()

	aps := &messaging.Aps{
		ContentAvailable: true,
		Sound:            pushNotificationSound,
		Alert: &messaging.ApsAlert{
			Title: pushNotificationTitle,
			Body:  pushNotificationBody,
		},
	}
	if threadID != "" {
		aps.ThreadID = threadID
	}

	return &messaging.Message{
		Token: token,
		Notification: &messaging.Notification{
			Title: pushNotificationTitle,
			Body:  pushNotificationBody,
		},
		Data: data,
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
				Aps:        aps,
				CustomData: apnsCustomDataFromPushData(data),
			},
		},
	}
}

func apnsCustomDataFromPushData(data map[string]string) map[string]interface{} {
	customData := make(map[string]interface{}, len(data))
	for key, value := range data {
		customData[key] = value
	}
	return customData
}

func addChatEncryptedPushData(data map[string]string, message string) bool {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil {
		return false
	}

	if version := trimmedString(envelope["version"]); version != "" {
		data["envelope_version"] = version
	}
	encrypted, ok := envelope["encrypted"].(map[string]interface{})
	if !ok {
		return false
	}

	addTrimmedData(data, "kem", encrypted["kem"])
	addTrimmedData(data, "ciphertext", encrypted["ciphertext"])
	addTrimmedData(data, "nonce", encrypted["nonce"])
	return data["kem"] != "" && data["ciphertext"] != "" && data["nonce"] != ""
}

func addGroupEncryptedPushData(data map[string]string, message string) bool {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil {
		return false
	}

	addTrimmedData(data, "kind", envelope["kind"])
	addJSONScalarData(data, "envelope_version", envelope["version"])
	addTrimmedData(data, "payloadType", envelope["payloadType"])
	if data["payloadType"] == "" {
		addTrimmedData(data, "payloadType", envelope["type"])
	}
	addJSONScalarData(data, "keyEpoch", envelope["keyEpoch"])
	if encrypted, ok := envelope["encrypted"].(map[string]interface{}); ok {
		addTrimmedData(data, "ciphertext", encrypted["ciphertext"])
		addTrimmedData(data, "nonce", encrypted["nonce"])
	}
	if data["ciphertext"] == "" {
		addTrimmedData(data, "ciphertext", envelope["ciphertext"])
	}
	if data["nonce"] == "" {
		addTrimmedData(data, "nonce", envelope["nonce"])
	}
	if data["message_id"] == "" {
		addTrimmedData(data, "message_id", envelope["messageId"])
	}
	if data["groupId"] == "" {
		addTrimmedData(data, "groupId", envelope["groupId"])
	}
	return data["keyEpoch"] != "" &&
		data["ciphertext"] != "" &&
		data["nonce"] != ""
}

func addTrimmedData(data map[string]string, key string, raw interface{}) {
	if value := trimmedString(raw); value != "" {
		data[key] = value
	}
}

func addJSONScalarData(data map[string]string, key string, raw interface{}) {
	switch value := raw.(type) {
	case string:
		if strings.TrimSpace(value) != "" {
			data[key] = strings.TrimSpace(value)
		}
	case float64:
		if value == float64(int64(value)) {
			data[key] = fmt.Sprintf("%d", int64(value))
		} else {
			data[key] = fmt.Sprintf("%g", value)
		}
	case int:
		data[key] = fmt.Sprintf("%d", value)
	case int64:
		data[key] = fmt.Sprintf("%d", value)
	case json.Number:
		data[key] = value.String()
	}
}

type chatPushMetadata struct {
	ShouldNotify   bool
	RouteType      string
	MessageID      string
	SenderUsername string
	GroupID        string
	GroupName      string
	Body           string
}

func extractChatPushMetadata(message string) chatPushMetadata {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil {
		return chatPushMetadata{}
	}

	switch trimmedString(envelope["type"]) {
	case "introduction":
		return chatPushMetadata{
			ShouldNotify: true,
			RouteType:    "intros",
			MessageID:    extractMessageId(message),
			Body:         introPushNotificationBody,
		}
	case "chat_message":
		return chatPushMetadata{
			ShouldNotify: true,
			RouteType:    "new_message",
			MessageID:    extractMessageId(message),
		}
	case "contact_request":
		intent := trimmedString(envelope["intent"])
		metadata := chatPushMetadata{
			ShouldNotify:   intent != "key_exchange_retry",
			RouteType:      "contact_request",
			MessageID:      extractMessageId(message),
			SenderUsername: trimmedString(envelope["senderUsername"]),
		}
		if payload, ok := envelope["payload"].(map[string]interface{}); ok {
			if metadata.SenderUsername == "" {
				metadata.SenderUsername = trimmedString(payload["senderUsername"])
			}
			if metadata.SenderUsername == "" {
				metadata.SenderUsername = trimmedString(payload["un"])
			}
		}
		if metadata.SenderUsername != "" {
			metadata.Body = fmt.Sprintf("%s wants to connect", metadata.SenderUsername)
		} else {
			metadata.Body = contactRequestPushBody
		}
		return metadata
	case "group_invite":
		metadata := chatPushMetadata{
			ShouldNotify:   true,
			RouteType:      "group_invite",
			MessageID:      extractMessageId(message),
			SenderUsername: trimmedString(envelope["senderUsername"]),
			GroupID:        trimmedString(envelope["groupId"]),
			GroupName:      trimmedString(envelope["groupName"]),
		}
		if payload, ok := envelope["payload"].(map[string]interface{}); ok {
			if metadata.SenderUsername == "" {
				metadata.SenderUsername = trimmedString(payload["senderUsername"])
			}
			if metadata.GroupID == "" {
				metadata.GroupID = trimmedString(payload["groupId"])
			}
			if metadata.GroupName == "" {
				if groupConfig, ok := payload["groupConfig"].(map[string]interface{}); ok {
					metadata.GroupName = trimmedString(groupConfig["name"])
				}
			}
		}
		switch {
		case metadata.SenderUsername != "" && metadata.GroupName != "":
			metadata.Body = fmt.Sprintf("%s invited you to %s", metadata.SenderUsername, metadata.GroupName)
		case metadata.SenderUsername != "":
			metadata.Body = fmt.Sprintf("%s sent you a group invite", metadata.SenderUsername)
		default:
			metadata.Body = groupInvitePushBody
		}
		return metadata
	default:
		return chatPushMetadata{}
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

// extractMessageId attempts to extract a message ID from the JSON payload
// for deduplication. Supports chat IDs, introduction IDs, and v2 contact
// request `msgId` values.
// Returns "" if the payload is malformed or has no extractable ID.
func extractMessageId(message string) string {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil {
		return ""
	}

	// V2 encrypted: top-level "id" field
	if id, ok := envelope["id"].(string); ok && id != "" {
		return id
	}

	if id, ok := envelope["messageId"].(string); ok && id != "" {
		return id
	}

	if id, ok := envelope["msgId"].(string); ok && id != "" {
		return id
	}

	// V1 plaintext: payload.id
	if payload, ok := envelope["payload"].(map[string]interface{}); ok {
		if id, ok := payload["id"].(string); ok {
			return id
		}
		if introID, ok := payload["introductionId"].(string); ok {
			return introID
		}
	}

	return ""
}

func trimmedString(raw interface{}) string {
	value, ok := raw.(string)
	if !ok {
		return ""
	}
	return strings.TrimSpace(value)
}

// --- Inbox store ---

type inboxMessage struct {
	ID        string                 `json:"id,omitempty"`
	From      string                 `json:"from"`
	Message   string                 `json:"message"`
	Timestamp int64                  `json:"timestamp"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
	// FDC-09 §12: the opaque wake-token the sender presented (TRANSIENT — json:"-",
	// never persisted or returned in a retrieve). Read once at store time for the
	// access-token wake gate; the durable message shape is unchanged.
	WakeToken string `json:"-"`
}

func ensureInboxMessageID(entry inboxMessage) inboxMessage {
	if entry.ID == "" {
		entry.ID = uuid.New().String()
	}
	return entry
}

// InboxStore wraps an InboxBackend and a PushService.
type InboxStore struct {
	backend  InboxBackend
	push     *PushService
	capacity int
	// FDC-09 §12 access-token wake gate (always non-nil; fail-open until a
	// recipient registers a set).
	wakeTokens *memoryWakeTokenStore
}

// NewInboxStore creates an InboxStore with an in-memory backend.
func NewInboxStore(push *PushService) *InboxStore {
	return &InboxStore{
		backend:    newMemoryInboxBackend(),
		push:       push,
		capacity:   maxMessagesPerPeer,
		wakeTokens: newMemoryWakeTokenStore(),
	}
}

// NewInboxStoreWithBackend creates an InboxStore with a custom backend.
func NewInboxStoreWithBackend(backend InboxBackend, push *PushService) *InboxStore {
	return NewInboxStoreWithBackendAndCapacity(backend, push, maxMessagesPerPeer)
}

func NewInboxStoreWithBackendAndCapacity(
	backend InboxBackend,
	push *PushService,
	capacity int,
) *InboxStore {
	if capacity <= 0 {
		capacity = maxMessagesPerPeer
	}
	return &InboxStore{
		backend:    backend,
		push:       push,
		capacity:   capacity,
		wakeTokens: newMemoryWakeTokenStore(),
	}
}

// RegisterWakeTokens registers the recipient's authorized opaque wake-token set
// (FDC-09 §12). The subject is the AUTHENTICATED stream peer (the dispatch arm
// passes remotePeer) — a peer registers only ITS OWN authorized set.
func (is *InboxStore) RegisterWakeTokens(peerId string, tokens []string) {
	if is.wakeTokens == nil {
		return
	}
	is.wakeTokens.RegisterWakeTokens(peerId, tokens)
}

// ClearWakeTokens drops a recipient's authorized wake-token set (e.g. on
// unregister_token — no orphaned wake authorization).
func (is *InboxStore) ClearWakeTokens(peerId string) {
	if is.wakeTokens == nil {
		return
	}
	is.wakeTokens.ClearWakeTokens(peerId)
}

func (is *InboxStore) Store(toPeerId string, entry inboxMessage) (InboxStoreResult, error) {
	entry = ensureInboxMessageID(entry)
	result, err := is.backend.Store(toPeerId, entry)
	if err != nil {
		log.Printf("[INBOX] Store failed for %s from %s: %v",
			toPeerId[:min(20, len(toPeerId))],
			entry.From[:min(20, len(entry.From))],
			err)
		return "", err
	}
	if result == InboxStoreResultDuplicate {
		// Duplicate — do not fire push notification.
		log.Printf("[INBOX] Duplicate message for %s from %s — skipped",
			toPeerId[:min(20, len(toPeerId))],
			entry.From[:min(20, len(entry.From))])
		inboxStoredCounter.Inc() // still count for metrics visibility
		return InboxStoreResultDuplicate, nil
	}
	if result == InboxStoreResultRejectedFull {
		inboxRejectedFullCounter.Inc()
		inboxCappedCounter.Inc()
		log.Printf("[INBOX] Rejected store for %s from %s: inbox full",
			toPeerId[:min(20, len(toPeerId))],
			entry.From[:min(20, len(entry.From))])
		return InboxStoreResultRejectedFull, nil
	}
	inboxStoredCounter.Inc()
	if biz != nil {
		biz.RecordMessageStored()
	}

	log.Printf("[INBOX] Stored message for %s from %s",
		toPeerId[:min(20, len(toPeerId))],
		entry.From[:min(20, len(entry.From))])

	// Fire push only for supported user-visible envelope types (the existing
	// ShouldNotify type filter) AND only when the sender is authorized to wake the
	// recipient (FDC-09 §12 access-token gate — LAYERED ON TOP of ShouldNotify,
	// never replacing or widening it). The gate is presence-INDEPENDENT: the
	// store->push seam never consults the presence store, so a wrong presence value
	// can never suppress (or trigger) a wake (PRESENCE_NEVER_LOAD_BEARING). It is
	// FAIL-OPEN when the recipient has registered no wake-token set, so existing
	// push delivery for already-paired contacts is unchanged. The message is
	// already STORED above either way — only the wake is gated (delivery preserved).
	if metadata := extractChatPushMetadata(entry.Message); metadata.ShouldNotify {
		if is.wakeTokens == nil || !wakeTokenGateEnforced ||
			is.wakeTokens.IsAuthorized(toPeerId, entry.WakeToken) {
			go is.push.SendNotification(context.Background(), toPeerId, entry.From, entry.Message)
		} else {
			pushSentCounter.WithLabelValues("unauthorized_wake").Inc()
			log.Printf("[INBOX] Suppressed unauthorized wake for %s (no valid wake-token; message still stored)",
				toPeerId[:min(20, len(toPeerId))])
		}
	}
	return InboxStoreResultStored, nil
}

func (is *InboxStore) Capacity() int {
	if is.capacity <= 0 {
		return maxMessagesPerPeer
	}
	return is.capacity
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

// RetrievePendingWithMeta retrieves messages without deleting them and returns
// pagination metadata.
func (is *InboxStore) RetrievePendingWithMeta(peerId string, limit int) ([]inboxMessage, bool) {
	return is.backend.RetrievePending(peerId, limit)
}

// Ack deletes only the inbox entries whose stable relay entry IDs match the
// provided list.
func (is *InboxStore) Ack(peerId string, entryIDs []string) (int, error) {
	removed, err := is.backend.Ack(peerId, entryIDs)
	if err != nil {
		return 0, err
	}

	if removed > 0 {
		log.Printf("[INBOX] Acked %d message(s) for %s",
			removed, peerId[:min(20, len(peerId))])
	}

	return removed, nil
}

func (is *InboxStore) Count(peerId string) int {
	return is.backend.Count(peerId)
}

func (is *InboxStore) Stats() (totalPeers, totalMessages int) {
	return is.backend.Stats()
}

// --- Group Inbox store ---

type groupInboxMessage struct {
	From             string   `json:"from"`
	Message          string   `json:"message"`
	Timestamp        int64    `json:"timestamp"`
	ID               string   `json:"id,omitempty"`
	RecipientPeerIds []string `json:"-"`
}

type groupInboxHistoryGap struct {
	GroupId                string   `json:"groupId"`
	GapId                  string   `json:"gapId"`
	MissingAfterMessageId  string   `json:"missingAfterMessageId"`
	MissingBeforeMessageId string   `json:"missingBeforeMessageId"`
	ExpectedRangeHash      string   `json:"expectedRangeHash"`
	ExpectedHeadMessageId  string   `json:"expectedHeadMessageId"`
	CandidateSourcePeerIds []string `json:"candidateSourcePeerIds"`
}

// GroupInboxStore wraps a GroupInboxBackend.
type GroupInboxStore struct {
	backend GroupInboxBackend
	push    *PushService
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

func (s *GroupInboxStore) SetPush(push *PushService) {
	s.push = push
}

func (s *GroupInboxStore) Store(groupId, from, message string) error {
	_, err := s.store(groupId, from, message, []string{from})
	return err
}

func (s *GroupInboxStore) store(
	groupId string,
	from string,
	message string,
	recipientPeerIds []string,
) (GroupInboxStoreResult, error) {
	normalizedRecipients := normalizePeerIds(recipientPeerIds)
	if len(normalizedRecipients) == 0 {
		return "", fmt.Errorf("recipientPeerIds required")
	}

	result, err := s.backend.StoreWithRecipients(
		groupId,
		from,
		message,
		normalizedRecipients,
	)
	if err != nil {
		return "", err
	}
	if result == GroupInboxStoreResultDuplicate {
		log.Printf("[GROUP_INBOX] Duplicate message for group %s from %s skipped",
			groupId[:min(20, len(groupId))],
			from[:min(20, len(from))])
		return GroupInboxStoreResultDuplicate, nil
	}
	if result == GroupInboxStoreResultStored {
		groupInboxStoredCounter.Inc()
		log.Printf("[GROUP_INBOX] Stored message for group %s from %s",
			groupId[:min(20, len(groupId))],
			from[:min(20, len(from))])
	}
	return result, nil
}

func (s *GroupInboxStore) StoreWithPushRecipients(
	groupId string,
	from string,
	message string,
	recipientPeerIds []string,
) error {
	normalizedRecipients := normalizePeerIds(recipientPeerIds)
	result, err := s.store(groupId, from, message, normalizedRecipients)
	if err != nil {
		return err
	}
	if result == GroupInboxStoreResultDuplicate {
		return nil
	}

	if !s.shouldFanoutPush(groupId, message) {
		return nil
	}

	s.fanOutPush(groupId, from, normalizedRecipients, message)
	return nil
}

func (s *GroupInboxStore) shouldFanoutPush(groupId, message string) bool {
	if s.push == nil {
		return false
	}
	if len(s.backend.RetrieveSince(groupId, 0)) == 0 {
		return false
	}

	messageID := extractMessageId(message)
	if messageID == "" {
		return true
	}

	seen := 0
	for _, stored := range s.backend.RetrieveSince(groupId, 0) {
		if extractMessageId(stored.Message) == messageID {
			seen++
			if seen > 1 {
				return false
			}
		}
	}
	return seen == 1
}

func (s *GroupInboxStore) fanOutPush(
	groupId string,
	from string,
	recipientPeerIds []string,
	message string,
) {
	if s.push == nil || len(recipientPeerIds) == 0 {
		return
	}

	messageID := extractMessageId(message)
	seen := make(map[string]struct{}, len(recipientPeerIds))
	for _, peerID := range recipientPeerIds {
		if peerID == "" || peerID == from {
			continue
		}
		if _, ok := seen[peerID]; ok {
			continue
		}
		seen[peerID] = struct{}{}
		go s.push.SendGroupNotification(
			context.Background(),
			peerID,
			groupId,
			messageID,
			message,
		)
	}
}

func (s *GroupInboxStore) Retrieve(groupId string, sinceTimestamp int64) []groupInboxMessage {
	result := s.backend.RetrieveSince(groupId, sinceTimestamp)
	groupInboxRetrievedCounter.Add(float64(len(result)))

	log.Printf("[GROUP_INBOX] Retrieved %d message(s) for group %s (since=%d)",
		len(result), groupId[:min(20, len(groupId))], sinceTimestamp)
	return result
}

func (s *GroupInboxStore) RetrieveAuthorized(
	groupId string,
	sinceTimestamp int64,
	requesterPeerId string,
) []groupInboxMessage {
	messages := s.backend.RetrieveSince(groupId, sinceTimestamp)
	result := filterGroupInboxMessagesForPeer(messages, requesterPeerId)
	groupInboxRetrievedCounter.Add(float64(len(result)))

	log.Printf("[GROUP_INBOX] Retrieved %d authorized message(s) for group %s peer %s (since=%d)",
		len(result),
		groupId[:min(20, len(groupId))],
		requesterPeerId[:min(20, len(requesterPeerId))],
		sinceTimestamp)
	return result
}

// RetrieveWithCursor retrieves messages using cursor-based pagination.
func (s *GroupInboxStore) RetrieveWithCursor(groupId string, cursor string, limit int) ([]groupInboxMessage, string, []groupInboxHistoryGap) {
	messages, nextCursor, historyGaps := s.backend.RetrieveCursor(groupId, cursor, limit)
	groupInboxRetrievedCounter.Add(float64(len(messages)))
	return messages, nextCursor, historyGaps
}

func (s *GroupInboxStore) RetrieveWithCursorAuthorized(
	groupId string,
	cursor string,
	limit int,
	requesterPeerId string,
) ([]groupInboxMessage, string, []groupInboxHistoryGap) {
	if limit <= 0 {
		return nil, "", nil
	}

	allMessages := s.backend.RetrieveSince(groupId, 0)
	cursorFound := cursor == ""
	startIdx := 0
	if cursor != "" {
		for i, message := range allMessages {
			if message.ID == cursor {
				startIdx = i + 1
				cursorFound = true
				break
			}
		}
	}

	result := make([]groupInboxMessage, 0, min(limit, len(allMessages)))
	lastReturnedIndex := -1

	for i := startIdx; i < len(allMessages); i++ {
		message := allMessages[i]
		if !groupInboxMessageAuthorizedForPeer(message, requesterPeerId) {
			continue
		}
		result = append(result, message)
		lastReturnedIndex = i
		if len(result) == limit {
			break
		}
	}

	if len(result) == 0 {
		return nil, "", nil
	}

	nextCursor := ""
	for i := lastReturnedIndex + 1; i < len(allMessages); i++ {
		if groupInboxMessageAuthorizedForPeer(allMessages[i], requesterPeerId) {
			nextCursor = result[len(result)-1].ID
			break
		}
	}

	groupInboxRetrievedCounter.Add(float64(len(result)))
	return result, nextCursor, buildGroupInboxHistoryGaps(groupId, cursor, cursorFound, result)
}

func (s *GroupInboxStore) RetrieveHistoryRepairRangeAuthorized(
	groupId string,
	missingAfterMessageId string,
	missingBeforeMessageId string,
	limit int,
	requesterPeerId string,
) ([]groupInboxMessage, string, string) {
	if limit <= 0 {
		limit = 50
	}

	allMessages := s.backend.RetrieveSince(groupId, 0)
	startIdx := 0
	if missingAfterMessageId != "" {
		for i, message := range allMessages {
			if message.ID == missingAfterMessageId {
				startIdx = i + 1
				break
			}
		}
	}

	result := make([]groupInboxMessage, 0, min(limit, len(allMessages)))
	for i := startIdx; i < len(allMessages) && len(result) < limit; i++ {
		message := allMessages[i]
		if !groupInboxMessageAuthorizedForPeer(message, requesterPeerId) {
			continue
		}
		result = append(result, message)
		if message.ID == missingBeforeMessageId {
			break
		}
	}

	if len(result) == 0 {
		return nil, "", ""
	}
	return result, computeGroupHistoryRangeHash(result), result[len(result)-1].ID
}

func buildGroupInboxHistoryGaps(
	groupId string,
	cursor string,
	cursorFound bool,
	repairMessages []groupInboxMessage,
) []groupInboxHistoryGap {
	if cursor == "" || cursorFound || len(repairMessages) == 0 {
		return nil
	}

	headMessageID := repairMessages[len(repairMessages)-1].ID
	rangeHash := computeGroupHistoryRangeHash(repairMessages)
	gapSeed := fmt.Sprintf("%s|%s|%s|%s", groupId, cursor, headMessageID, rangeHash)
	gapHash := sha256.Sum256([]byte(gapSeed))
	return []groupInboxHistoryGap{{
		GroupId:                groupId,
		GapId:                  fmt.Sprintf("relay-gap-%x", gapHash[:8]),
		MissingAfterMessageId:  cursor,
		MissingBeforeMessageId: headMessageID,
		ExpectedRangeHash:      rangeHash,
		ExpectedHeadMessageId:  headMessageID,
		CandidateSourcePeerIds: groupInboxCandidateSourcePeerIds(repairMessages),
	}}
}

func groupInboxCandidateSourcePeerIds(messages []groupInboxMessage) []string {
	seen := make(map[string]struct{})
	result := make([]string, 0)
	add := func(peerId string) {
		peerId = strings.TrimSpace(peerId)
		if peerId == "" {
			return
		}
		if _, ok := seen[peerId]; ok {
			return
		}
		seen[peerId] = struct{}{}
		result = append(result, peerId)
	}

	for _, message := range messages {
		add(message.From)
		for _, peerId := range message.RecipientPeerIds {
			add(peerId)
		}
	}
	return result
}

func computeGroupHistoryRangeHash(messages []groupInboxMessage) string {
	parts := make([]string, 0, len(messages))
	for _, message := range messages {
		payload := map[string]interface{}{
			"from":      message.From,
			"message":   message.Message,
			"timestamp": message.Timestamp,
		}
		// SetEscapeHTML(false): the Dart client's jsonEncode does NOT escape
		// < > &, so the relay must not either or the two range hashes diverge
		// (finding 06 Phase 1C). json.Encoder.Encode appends a trailing
		// newline, trimmed here before joining with the inter-message "\n".
		//
		// Caveat: encoding/json still escapes U+2028/U+2029 even with HTML
		// escaping off, while Dart's jsonEncode emits them raw — a message with
		// those code points would hash differently across languages. Unreachable
		// for real group messages (the hashed `message` is the base64/ASCII
		// encrypted offline-replay envelope); see the Dart twin's doc comment.
		var buf bytes.Buffer
		enc := json.NewEncoder(&buf)
		enc.SetEscapeHTML(false)
		if err := enc.Encode(payload); err != nil {
			continue
		}
		parts = append(parts, strings.TrimRight(buf.String(), "\n"))
	}
	sum := sha256.Sum256([]byte(strings.Join(parts, "\n")))
	return fmt.Sprintf("%x", sum[:])
}

func normalizePeerIds(peerIds []string) []string {
	if len(peerIds) == 0 {
		return nil
	}
	seen := make(map[string]struct{}, len(peerIds))
	result := make([]string, 0, len(peerIds))
	for _, peerId := range peerIds {
		if peerId == "" {
			continue
		}
		if _, ok := seen[peerId]; ok {
			continue
		}
		seen[peerId] = struct{}{}
		result = append(result, peerId)
	}
	return result
}

func mergePeerIds(existing []string, incoming []string) []string {
	merged := normalizePeerIds(existing)
	if len(incoming) == 0 {
		return merged
	}
	seen := make(map[string]struct{}, len(merged)+len(incoming))
	for _, peerId := range merged {
		seen[peerId] = struct{}{}
	}
	for _, peerId := range incoming {
		if peerId == "" {
			continue
		}
		if _, ok := seen[peerId]; ok {
			continue
		}
		seen[peerId] = struct{}{}
		merged = append(merged, peerId)
	}
	return merged
}

func stringSlicesEqual(a []string, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func groupInboxMessageAuthorizedForPeer(message groupInboxMessage, peerId string) bool {
	if peerId == "" {
		return false
	}
	return message.From == peerId || containsPeer(message.RecipientPeerIds, peerId)
}

func filterGroupInboxMessagesForPeer(messages []groupInboxMessage, peerId string) []groupInboxMessage {
	if len(messages) == 0 {
		return nil
	}
	result := make([]groupInboxMessage, 0, len(messages))
	for _, message := range messages {
		if groupInboxMessageAuthorizedForPeer(message, peerId) {
			result = append(result, message)
		}
	}
	return result
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
	EntryIds []string               `json:"entryIds,omitempty"`
	Token    string                 `json:"token,omitempty"`
	Platform string                 `json:"platform,omitempty"`
	// FDC-09 §12 access-token wake gate (additive). WakeToken is the opaque token a
	// SENDER presents on `store` to authorize waking the recipient; WakeTokens is
	// the SET a RECIPIENT registers via `register_wake_tokens`. omitempty keeps
	// every other action's frame byte-identical (NET-REL-07).
	WakeToken  string   `json:"wakeToken,omitempty"`
	WakeTokens []string `json:"wakeTokens,omitempty"`
	// Group inbox fields.
	GroupId                string   `json:"groupId,omitempty"`
	RecipientPeerIds       []string `json:"recipientPeerIds,omitempty"`
	SinceTimestamp         int64    `json:"sinceTimestamp,omitempty"`
	Cursor                 string   `json:"cursor,omitempty"`
	GapId                  string   `json:"gapId,omitempty"`
	SourcePeerId           string   `json:"sourcePeerId,omitempty"`
	MissingAfterMessageId  string   `json:"missingAfterMessageId,omitempty"`
	MissingBeforeMessageId string   `json:"missingBeforeMessageId,omitempty"`
	ExpectedRangeHash      string   `json:"expectedRangeHash,omitempty"`
	ExpectedHeadMessageId  string   `json:"expectedHeadMessageId,omitempty"`
}

type inboxResponse struct {
	Status        string                 `json:"status"`
	Error         string                 `json:"error,omitempty"`
	StoreStatus   string                 `json:"storeStatus,omitempty"`
	ExpiresAtMs   int64                  `json:"expiresAtMs,omitempty"`
	Occupancy     int                    `json:"occupancy,omitempty"`
	Capacity      int                    `json:"capacity,omitempty"`
	Messages      []inboxMessage         `json:"messages,omitempty"`
	HasMore       bool                   `json:"hasMore,omitempty"`
	Acked         int                    `json:"acked,omitempty"`
	GroupMessages []groupInboxMessage    `json:"groupMessages,omitempty"`
	NextCursor    string                 `json:"nextCursor,omitempty"`
	HistoryGaps   []groupInboxHistoryGap `json:"historyGaps,omitempty"`
	GroupId       string                 `json:"groupId,omitempty"`
	GapId         string                 `json:"gapId,omitempty"`
	SourcePeerId  string                 `json:"sourcePeerId,omitempty"`
	RangeHash     string                 `json:"rangeHash,omitempty"`
	HeadMessageId string                 `json:"headMessageId,omitempty"`
	// FDC-08 presence_get response fields (additive — `omitempty` keeps every
	// other action's response byte-identical for NET-REL-07). Presence is
	// "online-ish", never a foreground/background claim. AgeMs is a pointer so a
	// legitimate `ageMs:0` on a presence response is still emitted, while every
	// non-presence response omits the key entirely.
	Presence string `json:"presence,omitempty"`
	AgeMs    *int64 `json:"ageMs,omitempty"`
}

func fitRetrievePendingResponse(
	messages []inboxMessage,
	hasMore bool,
) ([]inboxMessage, bool, error) {
	if len(messages) == 0 {
		return nil, hasMore, nil
	}

	trimmed := append([]inboxMessage(nil), messages...)
	trimmedHasMore := hasMore
	for len(trimmed) > 0 {
		data, err := json.Marshal(inboxResponse{
			Status:   "OK",
			Messages: trimmed,
			HasMore:  trimmedHasMore,
		})
		if err == nil && len(data) <= maxFrameLen {
			if len(trimmed) != len(messages) {
				log.Printf("[INBOX] retrieve_pending trimmed response from %d to %d message(s) to fit %d-byte frame",
					len(messages), len(trimmed), maxFrameLen)
			}
			return trimmed, trimmedHasMore, nil
		}
		trimmed = trimmed[:len(trimmed)-1]
		trimmedHasMore = true
	}

	return nil, true, fmt.Errorf("single retrieve_pending entry exceeds %d-byte frame limit", maxFrameLen)
}

// HandleInboxStream dispatches a single inbox request over a libp2p stream. Its
// gocyclo is pre-existing (the 11-case action dispatch); FDC-08 adds one
// delegating `presence_get` arm (-> handlePresenceGet) and does not refactor the
// inherited switch (out of scope — see FDC-08 Scope Guard / named-handler rule).
//
//nolint:gocyclo,funlen // pre-existing dispatch size/complexity; FDC-08 adds one delegating case
func HandleInboxStream(s network.Stream, inbox *InboxStore, groupInbox *GroupInboxStore, h host.Host, presence *PresenceStore) {
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
				WakeToken: req.WakeToken, // FDC-09 §12: presented opaque wake-token (transient)
			}
			result, err := inbox.Store(req.To, entry)
			if err != nil {
				resp = inboxResponse{Status: "ERROR", Error: fmt.Sprintf("store failed: %v", err)}
			} else if result == InboxStoreResultRejectedFull {
				resp = inboxResponse{
					Status:      "ERROR",
					Error:       "INBOX_FULL",
					StoreStatus: string(result),
					Occupancy:   inbox.Count(req.To),
					Capacity:    inbox.Capacity(),
				}
			} else {
				resp = inboxResponse{
					Status:      "OK",
					StoreStatus: string(result),
					Occupancy:   inbox.Count(req.To),
					Capacity:    inbox.Capacity(),
				}
				if result == InboxStoreResultStored {
					resp.ExpiresAtMs = entry.Timestamp + maxMessageAge.Milliseconds()
				}
			}
			// Push notification is now fired inside InboxStore.Store
			// (only for genuinely new messages, skipped for duplicates).
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

	case "retrieve_pending":
		limit := req.Limit
		if limit <= 0 {
			limit = 50
		}
		messages, hasMore := inbox.RetrievePendingWithMeta(remotePeer, limit)
		if len(messages) > 0 {
			fittedMessages, fittedHasMore, err := fitRetrievePendingResponse(messages, hasMore)
			if err != nil {
				resp = inboxResponse{Status: "ERROR", Error: err.Error()}
			} else {
				resp = inboxResponse{
					Status:   "OK",
					Messages: fittedMessages,
					HasMore:  fittedHasMore,
				}
			}
		} else {
			resp = inboxResponse{Status: "NO_MESSAGES"}
		}

	case "ack":
		if len(req.EntryIds) == 0 {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required field: entryIds"}
		} else {
			acked, err := inbox.Ack(remotePeer, req.EntryIds)
			if err != nil {
				resp = inboxResponse{Status: "ERROR", Error: err.Error()}
			} else {
				resp = inboxResponse{Status: "OK", Acked: acked}
			}
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
		inbox.ClearWakeTokens(remotePeer) // FDC-09 §12: no orphaned wake authorization
		resp = inboxResponse{Status: "OK"}

	case "register_wake_tokens":
		// FDC-09 §12: the recipient registers the opaque wake-token SET it minted
		// for its contacts (anti-spam — only a contact presenting a member token can
		// wake it). Subject = the AUTHENTICATED stream peer (remotePeer), never a
		// request field. An empty set clears the gate (back to fail-open).
		inbox.RegisterWakeTokens(remotePeer, req.WakeTokens)
		resp = inboxResponse{Status: "OK"}

	case "group_store":
		if req.GroupId == "" || req.Message == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required fields: groupId, message"}
		} else if len(normalizePeerIds(req.RecipientPeerIds)) == 0 {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required field: recipientPeerIds"}
		} else {
			from := req.From
			if from == "" {
				from = remotePeer
			}
			if from != remotePeer {
				resp = inboxResponse{Status: "ERROR", Error: "not authorized"}
			} else if err := groupInbox.StoreWithPushRecipients(
				req.GroupId,
				remotePeer,
				req.Message,
				normalizePeerIds(req.RecipientPeerIds),
			); err != nil {
				resp = inboxResponse{Status: "ERROR", Error: err.Error()}
			} else {
				resp = inboxResponse{Status: "OK"}
			}
		}

	case "group_retrieve":
		if req.GroupId == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required field: groupId"}
		} else {
			messages := groupInbox.RetrieveAuthorized(req.GroupId, req.SinceTimestamp, remotePeer)
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
			messages, nextCursor, historyGaps := groupInbox.RetrieveWithCursorAuthorized(req.GroupId, req.Cursor, limit, remotePeer)
			if len(messages) > 0 {
				resp = inboxResponse{Status: "OK", GroupMessages: messages, NextCursor: nextCursor, HistoryGaps: historyGaps}
			} else {
				resp = inboxResponse{Status: "NO_MESSAGES"}
			}
		}

	case "group_history_repair_range":
		if req.GroupId == "" || req.GapId == "" || req.SourcePeerId == "" ||
			req.MissingAfterMessageId == "" || req.MissingBeforeMessageId == "" ||
			req.ExpectedRangeHash == "" || req.ExpectedHeadMessageId == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required history repair fields"}
		} else {
			limit := req.Limit
			if limit <= 0 {
				limit = 50
			}
			messages, rangeHash, headMessageId := groupInbox.RetrieveHistoryRepairRangeAuthorized(
				req.GroupId,
				req.MissingAfterMessageId,
				req.MissingBeforeMessageId,
				limit,
				remotePeer,
			)
			if len(messages) > 0 {
				resp = inboxResponse{
					Status:        "OK",
					GroupMessages: messages,
					GroupId:       req.GroupId,
					GapId:         req.GapId,
					SourcePeerId:  req.SourcePeerId,
					RangeHash:     rangeHash,
					HeadMessageId: headMessageId,
				}
			} else {
				resp = inboxResponse{Status: "NO_MESSAGES"}
			}
		}

	case "presence_get":
		resp = handlePresenceGet(req, h, presence)

	case "presence_set":
		resp = handlePresenceSet(s.Conn().RemotePeer(), req, presence)

	default:
		resp = inboxResponse{Status: "ERROR", Error: fmt.Sprintf("Unknown action: %s", req.Action)}
	}

	writeResponse(s, resp)
	log.Printf("[INBOX] Stream closed for %s", remotePeer[:min(20, len(remotePeer))])
}

// handlePresenceGet answers the additive `presence_get` inbox action: a cheap,
// read-only "is this peer online-ish?" lookup that replaces the blind ≤5 s
// circuit dial on the send-decision path (FDC-08). It NEVER dials a circuit and
// NEVER mutates inbox state (PRESENCE_LOOKUP_IS_READ_ONLY) — it reads the
// peer's live socket connectedness plus the shared presence store's last-seen /
// self-published state. The answer is coarse "online-ish, TTL-lagged" and
// carries no foreground/background field (PRESENCE_IS_ONLINE_ISH_NOT_FOREGROUND).
// A stale last-seen resolves to `unknown`, never silently `unreachable`.
func handlePresenceGet(req inboxRequest, h host.Host, presence *PresenceStore) inboxResponse {
	if req.To == "" {
		return inboxResponse{Status: "ERROR", Error: "Missing required field: to"}
	}
	pid, err := peer.Decode(req.To)
	if err != nil {
		return inboxResponse{Status: "ERROR", Error: fmt.Sprintf("invalid peer ID: %v", err)}
	}

	connected := h.Network().Connectedness(pid) == network.Connected
	res := presence.Lookup(pid, connected)

	ageMs := res.ageMs
	return inboxResponse{Status: "OK", Presence: res.presence, AgeMs: &ageMs}
}

// maxPresenceSelfTTL bounds a self-published presence TTL so a misbehaving peer
// cannot claim "reachable forever". The locked default is relayPresenceTTL
// (≈180 s); this is the generous upper clamp (FDC-S3 device-tunable window).
const maxPresenceSelfTTL = 10 * time.Minute

// handlePresenceSet answers the additive `presence_set` inbox action (FDC-09):
// a peer SELF-PUBLISHES its coarse foreground/background state to the shared
// presence store. The subject is the AUTHENTICATED stream peer (`self`), NEVER a
// request field — a peer can publish only ITS OWN presence (anti-spoof). The
// write records BOTH the self-published state (with its TTL, preferred by the
// resolver) AND seeds the connectedness last-seen, so a STALE self-state
// degrades to `unknown` via the same R5 freshness rule the last-seen uses
// (FDC-S3: never silently `unreachable`).
//
// Presence is a HINT, never load-bearing: this WRITE feeds the read-side
// emphasis hint only — the store→push delivery seam never consults it
// (PRESENCE_NEVER_LOAD_BEARING). Old relays answer "Unknown action: presence_set"
// (the stable `default` arm), which new clients map to "unsupported -> skip"
// (NET-REL-07).
func handlePresenceSet(self peer.ID, req inboxRequest, presence *PresenceStore) inboxResponse {
	if presence == nil {
		return inboxResponse{Status: "ERROR", Error: "presence store unavailable"}
	}

	state := trimmedString(req.Metadata["state"])
	switch state {
	case "foreground", "background":
		// accepted coarse self-published states
	default:
		return inboxResponse{Status: "ERROR", Error: fmt.Sprintf("invalid presence state: %q", state)}
	}

	ttl := relayPresenceTTL
	if ms := presenceMetadataTTLMs(req.Metadata); ms > 0 {
		ttl = time.Duration(ms) * time.Millisecond
		if ttl > maxPresenceSelfTTL {
			ttl = maxPresenceSelfTTL
		}
	}

	presence.SetSelfPublished(self, state, ttl)
	presence.RecordSeen(self) // seed last-seen so a stale self-state degrades to `unknown`, not `unreachable`
	return inboxResponse{Status: "OK"}
}

// presenceMetadataTTLMs extracts the optional `ttlMs` from a `presence_set`
// request's Metadata map. JSON numbers decode to float64 through the
// map[string]interface{} field; the other arms tolerate a node-side int64 /
// json.Number for robustness. A missing/zero value falls back to the default.
func presenceMetadataTTLMs(meta map[string]interface{}) int64 {
	if meta == nil {
		return 0
	}
	switch v := meta["ttlMs"].(type) {
	case float64:
		return int64(v)
	case int64:
		return v
	case int:
		return int64(v)
	case json.Number:
		n, _ := v.Int64()
		return n
	}
	return 0
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
