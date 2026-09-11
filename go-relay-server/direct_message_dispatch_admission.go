package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	directMessageDispatchAdmissionDomain = "mknoon.direct-message-provider-dispatch.v1"
	directMessageDispatchAdmissionTTL    = 7 * 24 * time.Hour
)

func directMessageDispatchAdmissionIdentityFromStorageKey(
	storageKey string,
) (messageDispatchAdmissionIdentity, bool) {
	if !canonicalGroupMessageDispatchAdmissionStorageKey(storageKey) {
		return messageDispatchAdmissionIdentity{}, false
	}
	return messageDispatchAdmissionIdentity{direct: true, prehashedKey: storageKey}, true
}

// The authenticated transport sender scopes the identity; an envelope's
// senderPeerId never decides which sender owns a provider dispatch claim.
// Custody IDs are deliberately absent because ACK removes the custody row and
// a later retry of the immutable envelope receives a new custody ID.
func newDirectMessageDispatchAdmissionIdentity(
	recipientPeerID string,
	authenticatedSenderPeerID string,
	message string,
) (messageDispatchAdmissionIdentity, bool) {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil ||
		exactString(envelope["type"]) != "chat_message" {
		return messageDispatchAdmissionIdentity{}, false
	}
	messageID := extractMessageId(message)
	for _, value := range []string{recipientPeerID, authenticatedSenderPeerID, messageID} {
		if value == "" || value != strings.TrimSpace(value) {
			return messageDispatchAdmissionIdentity{}, false
		}
	}

	// New edits carry an independent eventId. Legacy edits reused the target
	// message ID without an event ID, so their canonical content fingerprint
	// must also participate: the immutable replay is the same notification,
	// while changed ciphertext (or a changed v1 payload) may be an actual edit.
	var content map[string]interface{}
	if encrypted, ok := envelope["encrypted"].(map[string]interface{}); ok {
		if exactString(encrypted["kem"]) == "" ||
			exactString(encrypted["ciphertext"]) == "" ||
			exactString(encrypted["nonce"]) == "" {
			return messageDispatchAdmissionIdentity{}, false
		}
		content = encrypted
	} else if payload, ok := envelope["payload"].(map[string]interface{}); ok && len(payload) > 0 {
		content = payload
	} else {
		return messageDispatchAdmissionIdentity{}, false
	}

	eventID, hasEventID := envelope["eventId"]
	if hasEventID && exactString(eventID) == "" {
		return messageDispatchAdmissionIdentity{}, false
	}
	identity := messageDispatchAdmissionIdentity{
		direct:          true,
		recipientPeerID: recipientPeerID,
		senderPeerID:    authenticatedSenderPeerID,
		messageID:       extractDirectInboxDedupeKey(message),
	}
	if !hasEventID {
		canonicalContent, err := json.Marshal(content)
		if err != nil {
			return messageDispatchAdmissionIdentity{}, false
		}
		digest := sha256.Sum256(canonicalContent)
		identity.contentDigest = hex.EncodeToString(digest[:])
	}
	return identity, true
}

func newMemoryDirectMessageDispatchAdmissionBackend(ttl time.Duration) *memoryMessageDispatchAdmissionBackend {
	return newMemoryMessageDispatchAdmissionBackend(ttl)
}

func newRedisDirectMessageDispatchAdmissionBackend(
	client *redis.Client,
	prefix string,
	ttl time.Duration,
) *redisMessageDispatchAdmissionBackend {
	return newRedisMessageDispatchAdmissionBackend(client, prefix, "direct-message-provider-dispatch:v1:", ttl)
}
