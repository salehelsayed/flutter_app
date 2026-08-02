package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"os"
	"sort"
	"strings"

	"firebase.google.com/go/v4/messaging"
)

const (
	directReactionCapability       = "direct_reaction_v1"
	directReactionPushEnabledEnv   = "DIRECT_REACTION_PUSH_ENABLED"
	groupReactionCapability        = "group_reaction_v1"
	groupReactionPushEnabledEnv    = "GROUP_REACTION_PUSH_ENABLED"
	groupOfflineReplayEnvelopeKind = "group_offline_replay"
	reactionPushTitle              = "New reaction"
	reactionPushBody               = "Someone reacted to your message"
	reactionNotificationCategory   = "MESSAGE_REACTION"
	reactionIdentityDigestHexBytes = 48
	groupReactionNotificationKind  = "group_reaction_notification"
)

func normalizeCapabilities(capabilities []string) []string {
	seen := make(map[string]struct{}, len(capabilities))
	normalized := make([]string, 0, len(capabilities))
	for _, capability := range capabilities {
		capability = strings.TrimSpace(capability)
		if capability == "" {
			continue
		}
		if _, duplicate := seen[capability]; duplicate {
			continue
		}
		seen[capability] = struct{}{}
		normalized = append(normalized, capability)
	}
	return normalized
}

func (entry *tokenEntry) hasCapability(capability string) bool {
	if entry == nil {
		return false
	}
	for _, candidate := range entry.Capabilities {
		if candidate == capability {
			return true
		}
	}
	return false
}

// directReactionPushMetadata is the relay-visible, content-free subset of a
// v2 direct reaction. Emoji, actor display name, target text, and generated
// preview copy stay inside ciphertext or recipient-owned local state.
type directReactionPushMetadata struct {
	EventID         string
	Action          string
	TargetMessageID string
	EnvelopeSender  string
	EnvelopeVersion string
}

// extractDirectReactionPushMetadata recognizes every message_reaction envelope
// while returning eligible=false unless the optional notification metadata is
// complete and exact. Legacy v2 envelopes therefore remain valid opaque inbox
// entries but do not wake a recipient.
func extractDirectReactionPushMetadata(message string) (
	metadata directReactionPushMetadata,
	recognized bool,
	eligible bool,
) {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil {
		return directReactionPushMetadata{}, false, false
	}
	if exactString(envelope["type"]) != "message_reaction" {
		return directReactionPushMetadata{}, false, false
	}

	metadata = directReactionPushMetadata{
		EventID:         exactString(envelope["eventId"]),
		Action:          exactString(envelope["action"]),
		TargetMessageID: exactString(envelope["targetMessageId"]),
		EnvelopeSender:  exactString(envelope["senderPeerId"]),
		EnvelopeVersion: exactString(envelope["version"]),
	}
	if metadata.EnvelopeVersion != "2" ||
		metadata.EventID == "" ||
		metadata.Action != "add" ||
		metadata.TargetMessageID == "" ||
		metadata.EnvelopeSender == "" {
		return metadata, true, false
	}

	encrypted, ok := envelope["encrypted"].(map[string]interface{})
	if !ok || exactString(encrypted["kem"]) == "" ||
		exactString(encrypted["ciphertext"]) == "" ||
		exactString(encrypted["nonce"]) == "" {
		return metadata, true, false
	}
	return metadata, true, true
}

// exactString rejects surrounding whitespace instead of normalizing attacker-
// supplied identifiers or action discriminators into an eligible push hint.
func exactString(raw interface{}) string {
	value, ok := raw.(string)
	if !ok || value == "" || value != strings.TrimSpace(value) {
		return ""
	}
	return value
}

// groupReactionPushMetadata is the verified, relay-visible notification
// extension attached to an unchanged group_offline_replay v1 envelope. Display
// names, emoji, and target text remain inside ciphertext or recipient-owned
// state; the relay uses this structure only for custody identity and wake
// selection.
type groupReactionPushMetadata struct {
	TransitionID                          string
	Action                                string
	TargetMessageID                       string
	ReactorPeerID                         string
	ReactorTransportPeerID                string
	ReplayRecipientSetHash                string
	ReplayRecipientTransportPeerIDs       []string
	NotificationRecipientTransportPeerIDs []string
	BaseEnvelopeHash                      string
	BaseMessageID                         string
	SenderPublicKey                       string
	NotificationExtensionJSON             string
}

// extractGroupReactionPushMetadata recognizes both upgraded and legacy group
// reaction replay envelopes. A recognized-but-invalid envelope is intentionally
// returned with valid=false so it remains in opaque replay custody without ever
// falling through to the ordinary group_message push path.
func extractGroupReactionPushMetadata(
	message string,
	expectedGroupID string,
	authenticatedTransportPeerID string,
	requestRecipientPeerIDs []string,
) (
	metadata groupReactionPushMetadata,
	recognized bool,
	valid bool,
) {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil {
		return groupReactionPushMetadata{}, false, false
	}
	payloadType := trimmedString(envelope["payloadType"])
	if payloadType != "group_reaction" && trimmedString(envelope["type"]) != "group_reaction" {
		return groupReactionPushMetadata{}, false, false
	}
	recognized = true

	if exactString(envelope["kind"]) != groupOfflineReplayEnvelopeKind ||
		!exactJSONInteger(envelope["version"], 1) ||
		exactString(envelope["payloadType"]) != "group_reaction" {
		return groupReactionPushMetadata{}, true, false
	}
	groupID := exactString(envelope["groupId"])
	baseMessageID := exactString(envelope["messageId"])
	reactorPeerID := exactString(envelope["senderPeerId"])
	reactorTransportPeerID := exactString(envelope["senderTransportPeerId"])
	senderPublicKey := exactString(envelope["senderPublicKey"])
	baseRecipientSetHash := exactString(envelope["recipientSetHash"])
	if groupID == "" || baseMessageID == "" || reactorPeerID == "" ||
		reactorTransportPeerID == "" || senderPublicKey == "" ||
		baseRecipientSetHash == "" || !exactJSONIntegerValue(envelope["keyEpoch"]) ||
		exactString(envelope["ciphertext"]) == "" || exactString(envelope["nonce"]) == "" ||
		exactString(envelope["signatureAlgorithm"]) != "ed25519" ||
		exactString(envelope["signedPayload"]) == "" || exactString(envelope["signature"]) == "" {
		return groupReactionPushMetadata{}, true, false
	}
	if expectedGroupID != "" && groupID != expectedGroupID {
		return groupReactionPushMetadata{}, true, false
	}

	replayRecipients, ok := parseGroupReactionPeerIDs(envelope["recipientPeerIds"], false)
	if !ok || groupReactionPeerSetHash(replayRecipients) != baseRecipientSetHash {
		return groupReactionPushMetadata{}, true, false
	}
	if requestRecipientPeerIDs != nil {
		requestRecipients := canonicalGroupReactionPeerIDs(requestRecipientPeerIDs)
		if !stringSlicesEqual(requestRecipients, replayRecipients) {
			return groupReactionPushMetadata{}, true, false
		}
	}

	extension, ok := envelope["notificationExtension"].(map[string]interface{})
	if !ok || !hasExactGroupReactionExtensionKeys(extension) {
		return groupReactionPushMetadata{}, true, false
	}
	if !exactJSONInteger(extension["version"], 1) ||
		exactString(extension["signatureAlgorithm"]) != "ed25519" {
		return groupReactionPushMetadata{}, true, false
	}
	transitionID := exactString(extension["transitionId"])
	action := exactString(extension["action"])
	targetMessageID := exactString(extension["targetMessageId"])
	extensionReactorPeerID := exactString(extension["reactorPeerId"])
	extensionReactorTransportPeerID := exactString(extension["reactorTransportPeerId"])
	extensionReplayHash := exactString(extension["replayRecipientSetHash"])
	baseEnvelopeHash := exactString(extension["baseEnvelopeHash"])
	signedPayload := exactString(extension["signedPayload"])
	signature := exactString(extension["signature"])
	if transitionID == "" || (action != "add" && action != "remove") ||
		targetMessageID == "" || extensionReactorPeerID == "" ||
		extensionReactorTransportPeerID == "" || extensionReplayHash == "" ||
		baseEnvelopeHash == "" || signedPayload == "" || signature == "" ||
		extensionReactorPeerID != reactorPeerID ||
		extensionReactorTransportPeerID != reactorTransportPeerID ||
		extensionReplayHash != baseRecipientSetHash {
		return groupReactionPushMetadata{}, true, false
	}
	if authenticatedTransportPeerID != "" && reactorTransportPeerID != authenticatedTransportPeerID {
		return groupReactionPushMetadata{}, true, false
	}

	notificationRecipients, ok := parseGroupReactionPeerIDs(
		extension["notificationRecipientTransportPeerIds"],
		true,
	)
	if !ok || !groupReactionPeerIDsSubset(notificationRecipients, replayRecipients) {
		return groupReactionPushMetadata{}, true, false
	}

	baseEnvelope := make(map[string]interface{}, len(envelope)-1)
	for key, value := range envelope {
		if key != "notificationExtension" {
			baseEnvelope[key] = value
		}
	}
	canonicalBaseEnvelope, err := canonicalGroupReactionJSON(baseEnvelope)
	if err != nil || sha256Hex(canonicalBaseEnvelope) != baseEnvelopeHash {
		return groupReactionPushMetadata{}, true, false
	}

	expectedSignedPayload, err := canonicalGroupReactionJSON(map[string]interface{}{
		"kind":                                  groupReactionNotificationKind,
		"version":                               1,
		"transitionId":                          transitionID,
		"action":                                action,
		"targetMessageId":                       targetMessageID,
		"reactorPeerId":                         reactorPeerID,
		"reactorTransportPeerId":                reactorTransportPeerID,
		"replayRecipientSetHash":                baseRecipientSetHash,
		"notificationRecipientTransportPeerIds": notificationRecipients,
		"baseEnvelopeHash":                      baseEnvelopeHash,
	})
	if err != nil || signedPayload != expectedSignedPayload ||
		!verifyGroupReactionSignature(senderPublicKey, signedPayload, signature) {
		return groupReactionPushMetadata{}, true, false
	}

	canonicalExtension, err := canonicalGroupReactionJSON(extension)
	if err != nil {
		return groupReactionPushMetadata{}, true, false
	}
	return groupReactionPushMetadata{
		TransitionID:                          transitionID,
		Action:                                action,
		TargetMessageID:                       targetMessageID,
		ReactorPeerID:                         reactorPeerID,
		ReactorTransportPeerID:                reactorTransportPeerID,
		ReplayRecipientSetHash:                baseRecipientSetHash,
		ReplayRecipientTransportPeerIDs:       replayRecipients,
		NotificationRecipientTransportPeerIDs: notificationRecipients,
		BaseEnvelopeHash:                      baseEnvelopeHash,
		BaseMessageID:                         baseMessageID,
		SenderPublicKey:                       senderPublicKey,
		NotificationExtensionJSON:             canonicalExtension,
	}, true, true
}

func hasExactGroupReactionExtensionKeys(extension map[string]interface{}) bool {
	if len(extension) != 12 {
		return false
	}
	for _, key := range []string{
		"version",
		"transitionId",
		"action",
		"targetMessageId",
		"reactorPeerId",
		"reactorTransportPeerId",
		"replayRecipientSetHash",
		"notificationRecipientTransportPeerIds",
		"baseEnvelopeHash",
		"signatureAlgorithm",
		"signedPayload",
		"signature",
	} {
		if _, ok := extension[key]; !ok {
			return false
		}
	}
	return true
}

func exactJSONInteger(raw interface{}, expected int64) bool {
	value, ok := raw.(float64)
	return ok && value == float64(expected)
}

func exactJSONIntegerValue(raw interface{}) bool {
	value, ok := raw.(float64)
	return ok && value >= 0 && value == float64(int64(value))
}

func canonicalGroupReactionPeerIDs(peerIDs []string) []string {
	seen := make(map[string]struct{}, len(peerIDs))
	result := make([]string, 0, len(peerIDs))
	for _, peerID := range peerIDs {
		peerID = strings.TrimSpace(peerID)
		if peerID == "" {
			continue
		}
		if _, duplicate := seen[peerID]; duplicate {
			continue
		}
		seen[peerID] = struct{}{}
		result = append(result, peerID)
	}
	sort.Strings(result)
	return result
}

func parseGroupReactionPeerIDs(raw interface{}, requireCanonicalOrder bool) ([]string, bool) {
	entries, ok := raw.([]interface{})
	if !ok {
		return nil, false
	}
	rawPeerIDs := make([]string, 0, len(entries))
	for _, entry := range entries {
		peerID, ok := entry.(string)
		if !ok || peerID == "" || peerID != strings.TrimSpace(peerID) {
			return nil, false
		}
		rawPeerIDs = append(rawPeerIDs, peerID)
	}
	canonical := canonicalGroupReactionPeerIDs(rawPeerIDs)
	if len(canonical) != len(rawPeerIDs) {
		return nil, false
	}
	if requireCanonicalOrder && !stringSlicesEqual(rawPeerIDs, canonical) {
		return nil, false
	}
	return canonical, true
}

func groupReactionPeerSetHash(peerIDs []string) string {
	canonical, err := canonicalGroupReactionJSON(canonicalGroupReactionPeerIDs(peerIDs))
	if err != nil {
		return ""
	}
	return sha256Hex(canonical)
}

func groupReactionPeerIDsSubset(candidates, replayRecipients []string) bool {
	replaySet := make(map[string]struct{}, len(replayRecipients))
	for _, peerID := range replayRecipients {
		replaySet[peerID] = struct{}{}
	}
	for _, peerID := range candidates {
		if _, ok := replaySet[peerID]; !ok {
			return false
		}
	}
	return true
}

func canonicalGroupReactionJSON(value interface{}) (string, error) {
	var buffer bytes.Buffer
	encoder := json.NewEncoder(&buffer)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(value); err != nil {
		return "", err
	}
	return strings.TrimSuffix(buffer.String(), "\n"), nil
}

func sha256Hex(value string) string {
	digest := sha256.Sum256([]byte(value))
	return hex.EncodeToString(digest[:])
}

func verifyGroupReactionSignature(publicKeyBase64, signedPayload, signatureBase64 string) bool {
	publicKey, err := base64.StdEncoding.DecodeString(publicKeyBase64)
	if err != nil || len(publicKey) != ed25519.PublicKeySize {
		return false
	}
	signature, err := base64.StdEncoding.DecodeString(signatureBase64)
	if err != nil || len(signature) != ed25519.SignatureSize {
		return false
	}
	return ed25519.Verify(ed25519.PublicKey(publicKey), []byte(signedPayload), signature)
}

func buildGroupReactionPushMessage(
	token,
	groupID,
	message string,
	metadata groupReactionPushMetadata,
) *messaging.Message {
	if token == "" || groupID == "" || metadata.Action != "add" || metadata.TransitionID == "" {
		return nil
	}
	data := map[string]string{
		"type":                      "group_reaction",
		"groupId":                   groupID,
		"event_id":                  metadata.TransitionID,
		"target_message_id":         metadata.TargetMessageID,
		"action":                    "add",
		"capability_version":        groupReactionCapability,
		"envelope_version":          "1",
		"reactor_peer_id":           metadata.ReactorPeerID,
		"reactor_transport_peer_id": metadata.ReactorTransportPeerID,
		"base_envelope_hash":        metadata.BaseEnvelopeHash,
		"notification_extension":    metadata.NotificationExtensionJSON,
		"sender_public_key":         metadata.SenderPublicKey,
	}
	if !addGroupEncryptedPushData(data, message) {
		return nil
	}
	if pushDataSize(data) > maxPushDataBytes {
		for _, key := range []string{
			"ciphertext",
			"nonce",
			"notification_extension",
			"sender_public_key",
			"kind",
			"payloadType",
			"keyEpoch",
			"message_id",
		} {
			delete(data, key)
		}
		data["preview_unavailable"] = "1"
		if pushDataSize(data) > maxPushDataBytes {
			return nil
		}
	}

	// Plan 309 D1b (resolved 2026-08-01, industry practice): discrete reaction
	// events are delivered per-event and visually grouped by ThreadID; the
	// per-EVENT collapse id only dedupes provider retries of the same event,
	// never merges distinct reactions — mirroring the 1:1 reaction lane.
	apnsCollapseIdentity := boundedReactionEventIdentity(metadata.TransitionID)
	aps := &messaging.Aps{
		ContentAvailable: true,
		MutableContent:   true,
		ThreadID:         groupID,
		Category:         reactionNotificationCategory,
		Alert: &messaging.ApsAlert{
			Title: reactionPushTitle,
			Body:  reactionPushBody,
		},
	}
	return &messaging.Message{
		Token: token,
		Data:  data,
		Android: &messaging.AndroidConfig{
			// Plan 309 D1(b): no CollapseKey. The per-group key silently
			// discarded concurrent reactions in transit, and per-event keys
			// hit FCM's four-collapse-key-per-token cap; non-collapsible
			// messages use the 100-message queue with onDeletedMessages()
			// on overflow, matching the ordinary group-message builders.
			Priority: "high",
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{
				"apns-priority":  "10",
				"apns-push-type": "alert",
				// D1b: per-group on purpose (one stable card per group);
				// the iOS in-transit collapse loss is a documented open
				// half of C2 while this holds.
				"apns-collapse-id": apnsCollapseIdentity,
			},
			Payload: &messaging.APNSPayload{
				Aps:        aps,
				CustomData: apnsCustomDataFromPushData(data),
			},
		},
	}
}

// projectGroupReactionPushMessageForPlatform delegates to the generalized
// per-platform projection shared by every send site. Group-reaction messages
// always carry an APNs CustomData copy, so the generalized ios rule (drop the
// duplicate data map only when CustomData exists) is byte-identical here.
func projectGroupReactionPushMessageForPlatform(
	message *messaging.Message,
	platform string,
) *messaging.Message {
	return projectPushMessageForPlatform(message, platform)
}

// boundedReactionEventIdentity is shared by Dart, Go, and Swift. It is stable
// across processes and 57 bytes (`reaction:` + 48 lowercase SHA-256 hex chars),
// safely below APNs' 64-byte collapse-id ceiling.
func boundedReactionEventIdentity(eventID string) string {
	digest := sha256.Sum256([]byte(eventID))
	hexDigest := hex.EncodeToString(digest[:])
	return "reaction:" + hexDigest[:reactionIdentityDigestHexBytes]
}

func buildReactionPushMessage(token, authenticatedFromPeerID, message string) *messaging.Message {
	metadata, recognized, eligible := extractDirectReactionPushMetadata(message)
	if !recognized || !eligible || authenticatedFromPeerID == "" ||
		metadata.EnvelopeSender != authenticatedFromPeerID {
		return nil
	}

	data := map[string]string{
		"type":               "message_reaction",
		"sender_id":          authenticatedFromPeerID,
		"event_id":           metadata.EventID,
		"target_message_id":  metadata.TargetMessageID,
		"action":             "add",
		"capability_version": directReactionCapability,
		"envelope_version":   metadata.EnvelopeVersion,
	}
	if !addChatEncryptedPushData(data, message) || pushDataSize(data) > maxPushDataBytes {
		// A typed reaction wake is ciphertext-only. Unlike the ordinary-message
		// media fallback, an oversized/malformed encrypted envelope is stored but
		// never converted into a plaintext or generic message notification.
		return nil
	}

	identity := boundedReactionEventIdentity(metadata.EventID)
	aps := &messaging.Aps{
		ContentAvailable: true,
		MutableContent:   true,
		ThreadID:         authenticatedFromPeerID,
		Category:         reactionNotificationCategory,
		Alert: &messaging.ApsAlert{
			Title: reactionPushTitle,
			Body:  reactionPushBody,
		},
	}

	pushMessage := &messaging.Message{
		Token: token,
		Data:  data,
		Android: &messaging.AndroidConfig{
			Priority:    "high",
			CollapseKey: identity,
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{
				"apns-priority":    "10",
				"apns-push-type":   "alert",
				"apns-collapse-id": identity,
			},
			Payload: &messaging.APNSPayload{
				Aps:        aps,
				CustomData: apnsCustomDataFromPushData(data),
			},
		},
	}
	// The raw data cap alone admits envelopes whose single marshalled platform
	// leg exceeds the provider budget once projected — enforce the same per-leg
	// check the ordinary lanes use (a refused build stays silent custody).
	if !messageFitsProviderBudgets(pushMessage) {
		return nil
	}
	return pushMessage
}

func loadDirectReactionPushEnabledFromEnv() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(directReactionPushEnabledEnv))) {
	case "1", "true":
		return true
	default:
		return false
	}
}

func loadGroupReactionPushEnabledFromEnv() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(groupReactionPushEnabledEnv))) {
	case "1", "true":
		return true
	default:
		return false
	}
}
