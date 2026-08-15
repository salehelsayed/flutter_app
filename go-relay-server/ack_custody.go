package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
	"time"
	"unicode"
)

const (
	ackCustodyContract                    = "ack_or_expiry_v1"
	ackCustodyStoreAction                 = "store_custody_v1"
	ackCustodyRetrievePendingAction       = "retrieve_custody_pending_v1"
	ackCustodyAckAction                   = "ack_custody_v1"
	ackCustodyDirectTextKind              = "direct_text_v108"
	ackCustodyDirectReactionKind          = "direct_reaction_v109"
	ackCustodyDirectMutationKind          = "direct_mutation_v109"
	ackCustodyGroupBootstrapKind          = "group_bootstrap_v1"
	ackCustodyGroupAuthorityKind          = "group_authority_v1"
	ackCustodyGroupContentKind            = "group_content_v1"
	ackCustodyGroupContentMessagePrefix   = "group-content-message-id:"
	ackCustodyGroupContentReactionPrefix  = "group-content-reaction-id:"
	ackCustodyAdmissionEnabledEnv         = "DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED"
	ackCustodyErrorAdmissionDisabled      = "CUSTODY_ADMISSION_DISABLED"
	ackCustodyErrorIdentityConflict       = "CUSTODY_IDENTITY_CONFLICT"
	ackCustodyErrorIneligible             = "CUSTODY_INELIGIBLE"
	ackCustodyErrorBackendUnavailable     = "CUSTODY_BACKEND_UNAVAILABLE"
	ackCustodyErrorInboxFull              = "INBOX_FULL"
	ackCustodyStoreMetricStored           = "stored"
	ackCustodyStoreMetricDuplicate        = "duplicate"
	ackCustodyStoreMetricRejectedFull     = "rejected_full"
	ackCustodyStoreMetricDisabled         = "disabled"
	ackCustodyStoreMetricIdentityConflict = "identity_conflict"
	ackCustodyStoreMetricIneligible       = "ineligible"
	ackCustodyStoreMetricFailed           = "failed"
)

var (
	errAckCustodyAdmissionDisabled  = errors.New(ackCustodyErrorAdmissionDisabled)
	errAckCustodyIdentityConflict   = errors.New(ackCustodyErrorIdentityConflict)
	errAckCustodyIneligible         = errors.New(ackCustodyErrorIneligible)
	errAckCustodyBackendUnavailable = errors.New(ackCustodyErrorBackendUnavailable)
)

func hasExactJSONKeys(value map[string]interface{}, keys ...string) bool {
	if len(value) != len(keys) {
		return false
	}
	for _, key := range keys {
		if _, ok := value[key]; !ok {
			return false
		}
	}
	return true
}

// AckCustodyInboxBackend is an optional, durable-only extension beside the
// frozen InboxBackend contract. Production memory backends deliberately do not
// implement it, so protected rows can never be admitted into process memory or
// the legacy inbox namespace.
type AckCustodyInboxBackend interface {
	StoreAckCustody(
		toPeerID string,
		entry inboxMessage,
		dedupeKey string,
	) (InboxStoreResult, inboxMessage, error)
	RetrieveAckCustodyPending(
		peerID string,
		limit int,
	) (messages []inboxMessage, hasMore bool, err error)
	AckAckCustody(peerID string, entryIDs []string) (removed int, err error)
	CountAckCustody(peerID string) int
	AckCustodyStats() (totalPeers int, totalMessages int)
}

func loadAckCustodyAdmissionEnabledFromEnv() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(ackCustodyAdmissionEnabledEnv))) {
	case "1", "true":
		return true
	default:
		return false
	}
}

func (is *InboxStore) ackCustodyNow() time.Time {
	if is != nil && is.now != nil {
		return is.now()
	}
	return time.Now()
}

// SetAckCustodyNowForTest keeps the relay handler and Redis pruning on the same
// deterministic clock. Production never calls this seam.
func (is *InboxStore) SetAckCustodyNowForTest(now func() time.Time) {
	if is == nil {
		return
	}
	if now == nil {
		now = time.Now
	}
	is.now = now
	if backend, ok := is.backend.(*redisInboxBackend); ok {
		backend.now = now
	}
}

func validAckCustodyExpiryCeiling(
	custodyKind string,
	ceiling *int64,
	now time.Time,
	message string,
	authenticatedSender string,
	expectedRecipient string,
) bool {
	switch custodyKind {
	case ackCustodyDirectTextKind:
		if ceiling == nil {
			return true
		}
	case ackCustodyGroupContentKind:
		if _, eligible := extractAckCustodyGroupContentDedupeKey(
			message,
			authenticatedSender,
			expectedRecipient,
		); !eligible {
			return false
		}
		binding, valid := extractAckCustodyGroupMediaManifestBinding(message, expectedRecipient)
		if !valid {
			return false
		}
		if !binding.present {
			// Blob-free protected group content retains Plan 364's unbounded
			// timestamp-derived lifetime and request shape.
			return ceiling == nil
		}
		if ceiling == nil || *ceiling != binding.recipientExpiryCeilingMs {
			return false
		}
	default:
		// Reactions, mutations, bootstrap/authority, and every legacy action
		// retain their frozen timestamp-derived lifetime.
		return ceiling == nil
	}
	nowMs := now.UnixMilli()
	return *ceiling > nowMs && *ceiling <= now.Add(maxMessageAge).UnixMilli()
}

func ackCustodyEntryExpiresAtMs(entry inboxMessage) int64 {
	if entry.ExpiresAtMs > 0 {
		return entry.ExpiresAtMs
	}
	return entry.Timestamp + maxMessageAge.Milliseconds()
}

// extractAckCustodyDedupeKey is intentionally narrower than the legacy direct
// inbox dedupe parser. The new lane accepts only custody-owned envelope
// families and binds their claimed sender to the authenticated stream peer.
func extractAckCustodyDedupeKey(
	custodyKind string,
	message string,
	authenticatedSender string,
) (string, bool) {
	return extractAckCustodyDedupeKeyForRecipient(
		custodyKind,
		message,
		authenticatedSender,
		"",
	)
}

func extractAckCustodyDedupeKeyForRecipient(
	custodyKind string,
	message string,
	authenticatedSender string,
	expectedRecipient string,
) (string, bool) {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil {
		return "", false
	}
	if custodyKind == ackCustodyGroupContentKind {
		return extractAckCustodyGroupContentDedupeKey(
			message,
			authenticatedSender,
			expectedRecipient,
		)
	}

	sender := exactString(envelope["senderPeerId"])
	if sender == "" || sender != authenticatedSender {
		return "", false
	}
	encrypted, ok := envelope["encrypted"].(map[string]interface{})
	if !ok ||
		!hasExactJSONKeys(encrypted, "kem", "ciphertext", "nonce") ||
		exactString(encrypted["kem"]) == "" ||
		exactString(encrypted["ciphertext"]) == "" ||
		exactString(encrypted["nonce"]) == "" {
		return "", false
	}

	switch custodyKind {
	case ackCustodyDirectTextKind:
		if !hasExactJSONKeys(
			envelope,
			"type",
			"version",
			"id",
			"senderPeerId",
			"encrypted",
		) {
			return "", false
		}
		if exactString(envelope["type"]) != "chat_message" ||
			exactString(envelope["version"]) != "2" {
			return "", false
		}
		if _, hasEditEventID := envelope["eventId"]; hasEditEventID {
			return "", false
		}
		messageID := exactString(envelope["id"])
		if messageID == "" {
			return "", false
		}
		return directInboxTargetIDDedupePrefix + messageID, true

	case ackCustodyDirectReactionKind:
		if !hasExactJSONKeys(
			envelope,
			"type",
			"version",
			"eventId",
			"action",
			"targetMessageId",
			"senderPeerId",
			"encrypted",
		) {
			return "", false
		}
		if exactString(envelope["type"]) != "message_reaction" ||
			exactString(envelope["version"]) != "2" {
			return "", false
		}
		eventID := exactString(envelope["eventId"])
		action := exactString(envelope["action"])
		if eventID == "" ||
			(action != "add" && action != "remove") ||
			exactString(envelope["targetMessageId"]) == "" {
			return "", false
		}
		return directInboxReactionEventIDDedupePrefix + eventID, true

	case ackCustodyDirectMutationKind:
		eventID := exactString(envelope["eventId"])
		if eventID == "" || exactString(envelope["version"]) != "2" {
			return "", false
		}
		switch exactString(envelope["type"]) {
		case "chat_message":
			if !hasExactJSONKeys(
				envelope,
				"type",
				"version",
				"id",
				"eventId",
				"senderPeerId",
				"encrypted",
			) || exactString(envelope["id"]) == "" {
				return "", false
			}
			return directInboxEditEventIDDedupePrefix + eventID, true
		case "message_deletion":
			if !hasExactJSONKeys(
				envelope,
				"type",
				"version",
				"eventId",
				"senderPeerId",
				"encrypted",
			) {
				return "", false
			}
			return directInboxDeletionEventIDDedupePrefix + eventID, true
		default:
			return "", false
		}
	case ackCustodyGroupBootstrapKind, ackCustodyGroupAuthorityKind:
		if !hasExactJSONKeys(
			envelope,
			"type",
			"version",
			"id",
			"senderPeerId",
			"recipientPeerId",
			"encrypted",
		) || expectedRecipient == "" ||
			exactString(envelope["version"]) != "1" ||
			exactString(envelope["recipientPeerId"]) != expectedRecipient {
			return "", false
		}
		wantType := "linked_group_bootstrap_v1"
		prefix := "group-bootstrap-id:"
		if custodyKind == ackCustodyGroupAuthorityKind {
			wantType = "group_authority_v1"
			prefix = "group-authority-id:"
		}
		logicalID := exactString(envelope["id"])
		if exactString(envelope["type"]) != wantType || !validProtectedGroupLogicalID(logicalID) {
			return "", false
		}
		return prefix + logicalID, true
	default:
		return "", false
	}
}

// extractAckCustodyGroupContentDedupeKey admits only the self-describing,
// transport-signed Plan-364 replay shape. The request kind is deliberately not
// persisted by the relay, so every fact needed to recover the namespace and
// recipient entitlement must be present both in the envelope and its canonical
// signed payload.
func extractAckCustodyGroupContentDedupeKey(
	message string,
	authenticatedSender string,
	expectedRecipient string,
) (string, bool) {
	envelope, ok := decodeJSONObjectPreservingNumbers(message)
	if !ok {
		return "", false
	}
	if exactString(envelope["kind"]) != "group_offline_replay" ||
		!exactJSONInteger(envelope["version"], 1) ||
		exactString(envelope["custodyKind"]) != ackCustodyGroupContentKind {
		return "", false
	}

	payloadType := exactString(envelope["payloadType"])
	if payloadType != "group_message" && payloadType != "group_reaction" {
		return "", false
	}
	if !hasExactAckCustodyGroupContentEnvelopeKeys(envelope, payloadType) {
		return "", false
	}
	groupID := exactString(envelope["groupId"])
	contentEventID := exactString(envelope["contentEventId"])
	messageID := exactString(envelope["messageId"])
	senderPeerID := exactString(envelope["senderPeerId"])
	senderDeviceID := exactString(envelope["senderDeviceId"])
	senderTransportPeerID := exactString(envelope["senderTransportPeerId"])
	senderPublicKey := exactString(envelope["senderPublicKey"])
	recipientSetHash := exactString(envelope["recipientSetHash"])
	ciphertext := exactString(envelope["ciphertext"])
	nonce := exactString(envelope["nonce"])
	authorityEventAt := exactString(envelope["authorityEventAt"])
	authorityEventID := exactString(envelope["authorityEventId"])
	if groupID == "" || contentEventID == "" || messageID != contentEventID ||
		senderPeerID == "" || senderDeviceID == "" || senderTransportPeerID == "" ||
		senderTransportPeerID != authenticatedSender || senderPublicKey == "" ||
		recipientSetHash == "" || ciphertext == "" || nonce == "" ||
		authorityEventAt == "" || authorityEventID == "" ||
		expectedRecipient == "" || !validProtectedGroupLogicalID(groupID) ||
		!validProtectedGroupLogicalID(authorityEventID) {
		return "", false
	}
	parsedAuthorityAt, err := time.Parse("2006-01-02T15:04:05.000000Z", authorityEventAt)
	if err != nil || parsedAuthorityAt.Format("2006-01-02T15:04:05.000000Z") != authorityEventAt {
		return "", false
	}

	keyEpoch, validKeyEpoch := exactJSONIntegerLexemeValue(envelope["keyEpoch"])
	authorityKeyEpoch, validAuthorityKeyEpoch := exactJSONIntegerLexemeValue(
		envelope["authorityKeyEpoch"],
	)
	if !validKeyEpoch || !validAuthorityKeyEpoch || keyEpoch != authorityKeyEpoch {
		return "", false
	}

	recipients, ok := parseGroupReactionPeerIDs(envelope["recipientPeerIds"], true)
	if !ok || len(recipients) == 0 ||
		groupReactionPeerSetHash(recipients) != recipientSetHash ||
		!containsExactString(recipients, expectedRecipient) {
		return "", false
	}

	signedPayload := exactString(envelope["signedPayload"])
	signature := exactString(envelope["signature"])
	if exactString(envelope["signatureAlgorithm"]) != "ed25519" ||
		signedPayload == "" || signature == "" {
		return "", false
	}
	var signed map[string]interface{}
	if err := json.Unmarshal([]byte(signedPayload), &signed); err != nil {
		return "", false
	}
	canonicalSigned, err := canonicalGroupReactionJSON(signed)
	if err != nil || canonicalSigned != signedPayload {
		return "", false
	}
	plaintextHash := exactString(signed["plaintextHash"])
	if !isLowerHexOfLength(plaintextHash, 64) {
		return "", false
	}
	mediaBinding, validMediaBinding := extractAckCustodyGroupMediaManifestBinding(
		message,
		expectedRecipient,
	)
	if !validMediaBinding {
		return "", false
	}

	expectedSigned := map[string]interface{}{
		"schemaVersion":          1,
		"kind":                   "group_offline_replay",
		"custodyKind":            ackCustodyGroupContentKind,
		"groupId":                groupID,
		"payloadType":            payloadType,
		"keyEpoch":               keyEpoch,
		"messageId":              messageID,
		"contentEventId":         contentEventID,
		"authorityEventAt":       authorityEventAt,
		"authorityEventId":       authorityEventID,
		"authorityKeyEpoch":      authorityKeyEpoch,
		"senderPeerId":           senderPeerID,
		"senderDeviceId":         senderDeviceID,
		"senderTransportPeerId":  senderTransportPeerID,
		"senderSigningPublicKey": senderPublicKey,
		"ciphertextHash":         sha256Hex(ciphertext),
		"nonceHash":              sha256Hex(nonce),
		"plaintextHash":          plaintextHash,
		"recipientPeerIds":       recipients,
		"recipientSetHash":       recipientSetHash,
	}
	if rawKeyPackage, exists := envelope["senderKeyPackageId"]; exists {
		keyPackageID := exactString(rawKeyPackage)
		if keyPackageID == "" {
			return "", false
		}
		expectedSigned["senderKeyPackageId"] = keyPackageID
	}
	if mediaBinding.present {
		expectedSigned["mediaManifestHash"] = mediaBinding.manifestHash
	}
	expectedCanonical, err := canonicalGroupReactionJSON(expectedSigned)
	if err != nil || expectedCanonical != signedPayload ||
		!verifyGroupReactionSignature(senderPublicKey, signedPayload, signature) {
		return "", false
	}

	if payloadType == "group_reaction" {
		metadata, recognized, valid := extractGroupReactionPushMetadata(
			message,
			groupID,
			authenticatedSender,
			nil,
		)
		if !recognized || !valid || metadata.TransitionID != contentEventID ||
			!validGroupContentReactionTransitionID(contentEventID) {
			return "", false
		}
		return ackCustodyGroupContentReactionPrefix + contentEventID, true
	}
	if _, hasNotificationExtension := envelope["notificationExtension"]; hasNotificationExtension ||
		!validProtectedGroupLogicalID(contentEventID) {
		return "", false
	}
	return ackCustodyGroupContentMessagePrefix + contentEventID, true
}

func hasExactAckCustodyGroupContentEnvelopeKeys(
	envelope map[string]interface{},
	payloadType string,
) bool {
	keys := []string{
		"kind",
		"version",
		"custodyKind",
		"groupId",
		"payloadType",
		"keyEpoch",
		"messageId",
		"contentEventId",
		"authorityEventAt",
		"authorityEventId",
		"authorityKeyEpoch",
		"senderPeerId",
		"senderDeviceId",
		"senderTransportPeerId",
		"senderPublicKey",
		"recipientPeerIds",
		"recipientSetHash",
		"ciphertext",
		"nonce",
		"signatureAlgorithm",
		"signedPayload",
		"signature",
	}
	if _, exists := envelope["senderKeyPackageId"]; exists {
		keys = append(keys, "senderKeyPackageId")
	}
	if _, exists := envelope["mediaManifest"]; exists {
		keys = append(keys, "mediaManifest")
	}
	if _, exists := envelope["mediaManifestHash"]; exists {
		keys = append(keys, "mediaManifestHash")
	}
	if payloadType == "group_reaction" {
		keys = append(keys, "notificationExtension")
	}
	return hasExactJSONKeys(envelope, keys...)
}

type ackCustodyGroupMediaManifestBinding struct {
	present                  bool
	manifestHash             string
	recipientExpiryCeilingMs int64
}

type ackCustodyGroupMediaManifest struct {
	Schema           string                                   `json:"schema"`
	GroupID          string                                   `json:"groupId"`
	MessageID        string                                   `json:"messageId"`
	CustodyKind      string                                   `json:"custodyKind"`
	CustodyContract  string                                   `json:"custodyContract"`
	RecipientPeerIDs []string                                 `json:"recipientPeerIds"`
	Attachments      []ackCustodyGroupMediaManifestAttachment `json:"attachments"`
}

type ackCustodyGroupMediaManifestAttachment struct {
	AttachmentID        string        `json:"attachmentId"`
	CustodyBlobID       string        `json:"custodyBlobId"`
	CiphertextSHA256    string        `json:"ciphertextSha256"`
	CiphertextSize      int64         `json:"ciphertextSize"`
	MIME                string        `json:"mime"`
	MediaType           string        `json:"mediaType"`
	Width               *int64        `json:"width,omitempty"`
	Height              *int64        `json:"height,omitempty"`
	DurationMs          *int64        `json:"durationMs,omitempty"`
	Waveform            []json.Number `json:"waveform,omitempty"`
	EncryptionScheme    string        `json:"encryptionScheme"`
	EncryptionKeyBase64 string        `json:"encryptionKeyBase64"`
	EncryptionNonce     string        `json:"encryptionNonce"`
	Caption             *string       `json:"caption,omitempty"`
	ExpiresAtMs         []int64       `json:"expiresAtMs"`
}

// extractAckCustodyGroupMediaManifestBinding validates the exact canonical
// Plan-365 manifest carried outside the transport signature. The signed
// manifest hash binds those canonical bytes without duplicating them inside
// signedPayload. It returns the earliest blob expiry committed for the request
// recipient.
func extractAckCustodyGroupMediaManifestBinding(
	message string,
	expectedRecipient string,
) (ackCustodyGroupMediaManifestBinding, bool) {
	envelope, ok := decodeJSONObjectPreservingNumbers(message)
	if !ok {
		return ackCustodyGroupMediaManifestBinding{}, false
	}
	signedPayload := exactString(envelope["signedPayload"])
	signed, ok := decodeJSONObjectPreservingNumbers(signedPayload)
	if !ok {
		return ackCustodyGroupMediaManifestBinding{}, false
	}

	outerManifest, outerHasManifest := envelope["mediaManifest"]
	outerHash, outerHasHash := envelope["mediaManifestHash"]
	_, signedHasManifest := signed["mediaManifest"]
	signedHash, signedHasHash := signed["mediaManifestHash"]
	if !outerHasManifest && !outerHasHash && !signedHasManifest && !signedHasHash {
		return ackCustodyGroupMediaManifestBinding{}, true
	}
	if !outerHasManifest || !outerHasHash || signedHasManifest || !signedHasHash ||
		exactString(envelope["payloadType"]) != "group_message" {
		return ackCustodyGroupMediaManifestBinding{}, false
	}

	manifest := exactString(outerManifest)
	manifestHash := exactString(outerHash)
	if manifest == "" || !isLowerHexOfLength(manifestHash, 64) ||
		exactString(signedHash) != manifestHash ||
		sha256Hex(manifest) != manifestHash {
		return ackCustodyGroupMediaManifestBinding{}, false
	}
	recipients, ok := parseGroupReactionPeerIDs(envelope["recipientPeerIds"], true)
	if !ok {
		return ackCustodyGroupMediaManifestBinding{}, false
	}
	expiry, ok := parseAckCustodyGroupMediaManifest(
		manifest,
		exactString(envelope["groupId"]),
		exactString(envelope["messageId"]),
		recipients,
		expectedRecipient,
	)
	if !ok {
		return ackCustodyGroupMediaManifestBinding{}, false
	}
	return ackCustodyGroupMediaManifestBinding{
		present:                  true,
		manifestHash:             manifestHash,
		recipientExpiryCeilingMs: expiry,
	}, true
}

func parseAckCustodyGroupMediaManifest(
	raw string,
	expectedGroupID string,
	expectedMessageID string,
	expectedRecipients []string,
	expectedRecipient string,
) (int64, bool) {
	value, ok := decodeJSONObjectPreservingNumbers(raw)
	if !ok || !hasExactJSONKeys(
		value,
		"schema",
		"groupId",
		"messageId",
		"custodyKind",
		"custodyContract",
		"recipientPeerIds",
		"attachments",
	) ||
		exactString(value["schema"]) != "group_media_manifest_v1" ||
		exactString(value["groupId"]) != expectedGroupID ||
		exactString(value["messageId"]) != expectedMessageID ||
		exactString(value["custodyKind"]) != groupMediaBlobCustodyKind ||
		exactString(value["custodyContract"]) != directMediaBlobCustodyContract ||
		expectedRecipient == "" {
		return 0, false
	}
	manifestRecipients, ok := parseGroupReactionPeerIDs(value["recipientPeerIds"], true)
	if !ok || !stringSlicesEqual(manifestRecipients, expectedRecipients) {
		return 0, false
	}
	recipientIndex := -1
	for index, recipient := range manifestRecipients {
		if recipient == expectedRecipient {
			recipientIndex = index
			break
		}
	}
	if recipientIndex < 0 {
		return 0, false
	}
	rawAttachments, ok := value["attachments"].([]interface{})
	if !ok || len(rawAttachments) == 0 {
		return 0, false
	}

	manifest := ackCustodyGroupMediaManifest{
		Schema:           "group_media_manifest_v1",
		GroupID:          expectedGroupID,
		MessageID:        expectedMessageID,
		CustodyKind:      groupMediaBlobCustodyKind,
		CustodyContract:  directMediaBlobCustodyContract,
		RecipientPeerIDs: manifestRecipients,
		Attachments:      make([]ackCustodyGroupMediaManifestAttachment, 0, len(rawAttachments)),
	}
	seenAttachmentIDs := make(map[string]struct{}, len(rawAttachments))
	seenBlobIDs := make(map[string]struct{}, len(rawAttachments))
	previousAttachmentID := ""
	recipientCeiling := int64(0)
	for _, rawAttachment := range rawAttachments {
		attachmentMap, ok := rawAttachment.(map[string]interface{})
		if !ok || !hasAllowedAndRequiredAckCustodyGroupMediaKeys(
			attachmentMap,
			[]string{
				"attachmentId", "custodyBlobId", "ciphertextSha256", "ciphertextSize",
				"mime", "mediaType", "width", "height", "durationMs", "waveform",
				"encryptionScheme", "encryptionKeyBase64", "encryptionNonce", "caption", "expiresAtMs",
			},
			[]string{
				"attachmentId", "custodyBlobId", "ciphertextSha256", "ciphertextSize",
				"mime", "mediaType", "encryptionScheme", "encryptionKeyBase64",
				"encryptionNonce", "expiresAtMs",
			},
		) {
			return 0, false
		}

		attachmentID := exactString(attachmentMap["attachmentId"])
		blobID := exactString(attachmentMap["custodyBlobId"])
		ciphertextHash := exactString(attachmentMap["ciphertextSha256"])
		ciphertextSize, validSize := exactJSONIntegerLexemeValue(attachmentMap["ciphertextSize"])
		mime := exactString(attachmentMap["mime"])
		mediaType := exactString(attachmentMap["mediaType"])
		encryptionScheme := exactString(attachmentMap["encryptionScheme"])
		encryptionKey := exactString(attachmentMap["encryptionKeyBase64"])
		encryptionNonce := exactString(attachmentMap["encryptionNonce"])
		if attachmentID == "" || previousAttachmentID >= attachmentID ||
			!mediaCustodyBlobIDPattern.MatchString(blobID) ||
			!isLowerHexOfLength(ciphertextHash, 64) || !validSize || ciphertextSize <= 0 ||
			!validAckCustodyGroupMediaMIME(mime) || mediaType == "" ||
			encryptionScheme != "blob_aes_256_gcm_v1" || encryptionKey == "" || encryptionNonce == "" {
			return 0, false
		}
		if _, duplicate := seenAttachmentIDs[attachmentID]; duplicate {
			return 0, false
		}
		if _, duplicate := seenBlobIDs[blobID]; duplicate {
			return 0, false
		}
		seenAttachmentIDs[attachmentID] = struct{}{}
		seenBlobIDs[blobID] = struct{}{}
		previousAttachmentID = attachmentID

		attachment := ackCustodyGroupMediaManifestAttachment{
			AttachmentID:        attachmentID,
			CustodyBlobID:       blobID,
			CiphertextSHA256:    ciphertextHash,
			CiphertextSize:      ciphertextSize,
			MIME:                mime,
			MediaType:           mediaType,
			EncryptionScheme:    encryptionScheme,
			EncryptionKeyBase64: encryptionKey,
			EncryptionNonce:     encryptionNonce,
		}
		if rawWidth, exists := attachmentMap["width"]; exists {
			width, valid := exactJSONIntegerLexemeValue(rawWidth)
			if !valid || width <= 0 {
				return 0, false
			}
			attachment.Width = &width
		}
		if rawHeight, exists := attachmentMap["height"]; exists {
			height, valid := exactJSONIntegerLexemeValue(rawHeight)
			if !valid || height <= 0 {
				return 0, false
			}
			attachment.Height = &height
		}
		if rawDuration, exists := attachmentMap["durationMs"]; exists {
			duration, valid := exactJSONIntegerLexemeValue(rawDuration)
			if !valid {
				return 0, false
			}
			attachment.DurationMs = &duration
		}
		if rawWaveform, exists := attachmentMap["waveform"]; exists {
			values, ok := rawWaveform.([]interface{})
			if !ok || len(values) == 0 {
				return 0, false
			}
			attachment.Waveform = make([]json.Number, 0, len(values))
			for _, rawSample := range values {
				sample, ok := rawSample.(json.Number)
				parsed, err := strconv.ParseFloat(string(sample), 64)
				if !ok || err != nil || math.IsNaN(parsed) || math.IsInf(parsed, 0) {
					return 0, false
				}
				attachment.Waveform = append(attachment.Waveform, sample)
			}
		}
		if rawCaption, exists := attachmentMap["caption"]; exists {
			caption := exactString(rawCaption)
			if caption == "" {
				return 0, false
			}
			attachment.Caption = &caption
		}

		rawExpiries, ok := attachmentMap["expiresAtMs"].([]interface{})
		if !ok || len(rawExpiries) != len(manifestRecipients) {
			return 0, false
		}
		attachment.ExpiresAtMs = make([]int64, 0, len(rawExpiries))
		for index, rawExpiry := range rawExpiries {
			expiresAtMs, valid := exactJSONIntegerLexemeValue(rawExpiry)
			if !valid || expiresAtMs <= 0 {
				return 0, false
			}
			attachment.ExpiresAtMs = append(attachment.ExpiresAtMs, expiresAtMs)
			if index == recipientIndex &&
				(recipientCeiling == 0 || expiresAtMs < recipientCeiling) {
				recipientCeiling = expiresAtMs
			}
		}
		manifest.Attachments = append(manifest.Attachments, attachment)
	}
	if recipientCeiling <= 0 {
		return 0, false
	}
	canonical, err := canonicalGroupReactionJSON(manifest)
	if err != nil || canonical != raw {
		return 0, false
	}
	return recipientCeiling, true
}

func hasAllowedAndRequiredAckCustodyGroupMediaKeys(
	value map[string]interface{},
	allowed []string,
	required []string,
) bool {
	allowedSet := make(map[string]struct{}, len(allowed))
	for _, key := range allowed {
		allowedSet[key] = struct{}{}
	}
	for key := range value {
		if _, ok := allowedSet[key]; !ok {
			return false
		}
	}
	for _, key := range required {
		if _, ok := value[key]; !ok {
			return false
		}
	}
	return true
}

func validAckCustodyGroupMediaMIME(value string) bool {
	if exactString(value) == "" || strings.Count(value, "/") != 1 {
		return false
	}
	parts := strings.SplitN(value, "/", 2)
	return parts[0] != "" && parts[1] != "" &&
		strings.IndexFunc(value, unicode.IsSpace) < 0
}

func containsExactString(values []string, expected string) bool {
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
}

func isLowerHexOfLength(value string, length int) bool {
	if len(value) != length {
		return false
	}
	for _, char := range value {
		if (char < '0' || char > '9') && (char < 'a' || char > 'f') {
			return false
		}
	}
	return true
}

func validGroupContentReactionTransitionID(value string) bool {
	parts := strings.Split(value, ":")
	if len(parts) != 4 || parts[0] != "gr1" ||
		!isLowerHexOfLength(parts[1], 32) || len(parts[2]) != 20 ||
		!isLowerHexOfLength(parts[3], 32) {
		return false
	}
	for _, char := range parts[2] {
		if char < '0' || char > '9' {
			return false
		}
	}
	return true
}

func validProtectedGroupLogicalID(value string) bool {
	if value == "" || len(value) > 512 {
		return false
	}
	for _, r := range value {
		if (r >= 'a' && r <= 'z') ||
			(r >= 'A' && r <= 'Z') ||
			(r >= '0' && r <= '9') ||
			r == '.' || r == '_' || r == ':' || r == '-' {
			continue
		}
		return false
	}
	return true
}

// extractStoredAckCustodyDedupeKey reconstructs the namespace-qualified key
// for rows already accepted into custody. Direct envelopes retain their frozen
// parser; protected group envelopes are revalidated against the stored stream
// sender and recipient before they may participate in duplicate detection.
func extractStoredAckCustodyDedupeKey(
	message string,
	authenticatedSender string,
	expectedRecipient string,
) string {
	// Try the strict protected shapes first: the frozen legacy helper falls
	// back to any outer `id`, which would otherwise collapse these namespaces
	// into `target-id:` before their exact type/recipient can be considered.
	for _, kind := range []string{
		ackCustodyGroupBootstrapKind,
		ackCustodyGroupAuthorityKind,
		ackCustodyGroupContentKind,
	} {
		if key, ok := extractAckCustodyDedupeKeyForRecipient(
			kind,
			message,
			authenticatedSender,
			expectedRecipient,
		); ok {
			return key
		}
	}
	// A row marked as protected content must never fall through to the legacy
	// outer-message-id parser when Redis bytes are malformed or crossed. The
	// signed discriminator catches a damaged/missing outer copy as well.
	var envelope map[string]interface{}
	if json.Unmarshal([]byte(message), &envelope) == nil &&
		declaresAckCustodyGroupContent(envelope) {
		return ""
	}
	if directKey := extractDirectInboxDedupeKey(message); directKey != "" {
		return directKey
	}
	return ""
}

// declaresAckCustodyGroupContent is a fail-closed stored-row classifier, not
// admission authority. Redis retrieval does not retain the outer request kind,
// so damaged protected bytes must still be kept out of the legacy messageId
// fallback whenever either discriminator or a Plan-364-only authority/event
// field survives. A malformed signedPayload is covered by raw protected-kind
// and strict-field-name sentinels after all structured checks fail.
func declaresAckCustodyGroupContent(envelope map[string]interface{}) bool {
	if exactString(envelope["custodyKind"]) == ackCustodyGroupContentKind ||
		hasAnyAckCustodyGroupContentField(envelope) {
		return true
	}
	signedPayload := exactString(envelope["signedPayload"])
	if signedPayload == "" {
		return false
	}
	var signed map[string]interface{}
	if json.Unmarshal([]byte(signedPayload), &signed) == nil {
		return exactString(signed["custodyKind"]) == ackCustodyGroupContentKind ||
			hasAnyAckCustodyGroupContentField(signed)
	}
	if strings.Contains(signedPayload, ackCustodyGroupContentKind) {
		return true
	}
	for _, field := range ackCustodyGroupContentFields {
		if strings.Contains(signedPayload, field) {
			return true
		}
	}
	return false
}

var ackCustodyGroupContentFields = []string{
	"contentEventId",
	"authorityEventAt",
	"authorityEventId",
	"authorityKeyEpoch",
	"mediaManifest",
	"mediaManifestHash",
}

func hasAnyAckCustodyGroupContentField(value map[string]interface{}) bool {
	for _, field := range ackCustodyGroupContentFields {
		if _, exists := value[field]; exists {
			return true
		}
	}
	return false
}

func (is *InboxStore) SetAckCustodyAdmissionEnabled(enabled bool) {
	is.ackCustodyAdmissionEnabled = enabled
	setAckCustodyAdmissionGauge(enabled)
}

func (is *InboxStore) AckCustodyAdmissionEnabled() bool {
	return is != nil && is.ackCustodyAdmissionEnabled
}

func (is *InboxStore) StoreAckCustody(
	toPeerID string,
	entry inboxMessage,
	custodyKind string,
) (InboxStoreResult, inboxMessage, error) {
	if !is.AckCustodyAdmissionEnabled() {
		recordAckCustodyStoreResult(ackCustodyStoreMetricDisabled)
		return "", inboxMessage{}, errAckCustodyAdmissionDisabled
	}

	backend, ok := is.backend.(AckCustodyInboxBackend)
	if !ok {
		recordAckCustodyStoreResult(ackCustodyStoreMetricFailed)
		return "", inboxMessage{}, errAckCustodyBackendUnavailable
	}

	dedupeKey, eligible := extractAckCustodyDedupeKeyForRecipient(
		custodyKind,
		entry.Message,
		entry.From,
		toPeerID,
	)
	if !eligible {
		recordAckCustodyStoreResult(ackCustodyStoreMetricIneligible)
		return "", inboxMessage{}, errAckCustodyIneligible
	}

	entry = ensureInboxMessageID(entry)
	result, storedEntry, admissionStatus, admission, preflightFallback, handled, err :=
		is.storeAckCustodyWithWakeOutcome(toPeerID, entry, dedupeKey)
	if !handled {
		result, storedEntry, err = backend.StoreAckCustody(toPeerID, entry, dedupeKey)
	}
	if err != nil {
		if errors.Is(err, errAckCustodyIdentityConflict) {
			recordAckCustodyStoreResult(ackCustodyStoreMetricIdentityConflict)
			return "", inboxMessage{}, err
		}
		recordAckCustodyStoreResult(ackCustodyStoreMetricFailed)
		return "", inboxMessage{}, fmt.Errorf("store ack custody: %w", err)
	}

	switch result {
	case InboxStoreResultStored:
		recordAckCustodyStoreResult(ackCustodyStoreMetricStored)
		if handled {
			is.recordStoredWithoutPush(toPeerID, storedEntry)
			switch admissionStatus {
			case wakeOutcomeAdmissionDelayed, wakeOutcomeAdmissionSuppressed:
			case wakeOutcomeAdmissionCapacityFallback, wakeOutcomeAdmissionImmediateFallback:
				is.launchDirectPushForWakeAdmission(toPeerID, storedEntry, admission)
			default:
				is.launchStoredDirectPush(toPeerID, storedEntry)
			}
		} else {
			is.recordStoredWithoutPush(toPeerID, storedEntry)
			is.launchStoredDirectPushAfterPreflight(toPeerID, storedEntry, preflightFallback)
		}
	case InboxStoreResultDuplicate:
		recordAckCustodyStoreResult(ackCustodyStoreMetricDuplicate)
	case InboxStoreResultRejectedFull:
		recordAckCustodyStoreResult(ackCustodyStoreMetricRejectedFull)
	default:
		recordAckCustodyStoreResult(ackCustodyStoreMetricFailed)
		return "", inboxMessage{}, fmt.Errorf("store ack custody returned unknown result %q", result)
	}
	return result, storedEntry, nil
}

func (is *InboxStore) storeAckCustodyWithWakeOutcome(
	toPeerID string,
	entry inboxMessage,
	dedupeKey string,
) (
	InboxStoreResult,
	inboxMessage,
	wakeOutcomeAdmissionStatus,
	wakeOutcomeAdmission,
	wakeOutcomePreflightFallback,
	bool,
	error,
) {
	backend, ok := is.backend.(interface {
		StoreAckCustodyWithWakeOutcome(
			toPeerID string,
			entry inboxMessage,
			dedupeKey string,
			admission wakeOutcomeAdmission,
		) (InboxStoreResult, inboxMessage, wakeOutcomeAdmissionStatus, error)
	})
	if !ok || !is.WakeOutcomeAdmissionEnabled() {
		return "", inboxMessage{}, "", wakeOutcomeAdmission{}, wakeOutcomePreflightFallback{}, false, nil
	}
	producer, requiredCapability, verifiedEventKey, eligible := is.directWakeOutcomeProducer(toPeerID, entry)
	if !eligible {
		return "", inboxMessage{}, "", wakeOutcomeAdmission{}, wakeOutcomePreflightFallback{}, false, nil
	}
	for routeAttempt := 0; routeAttempt < 2; routeAttempt++ {
		fallback, admission, admitted := is.preflightDirectWakeOutcome(
			toPeerID,
			entry,
			producer,
			requiredCapability,
			verifiedEventKey,
		)
		if !admitted {
			return "", inboxMessage{}, "", wakeOutcomeAdmission{}, fallback, false, nil
		}
		result, storedEntry, status, err := backend.StoreAckCustodyWithWakeOutcome(
			toPeerID,
			entry,
			dedupeKey,
			admission,
		)
		if errors.Is(err, errWakeOutcomeRouteChanged) {
			if routeAttempt == 1 {
				return "", inboxMessage{}, "", wakeOutcomeAdmission{}, fallback, false, nil
			}
			continue
		}
		return result, storedEntry, status, admission, wakeOutcomePreflightFallback{}, true, err
	}
	return "", inboxMessage{}, "", wakeOutcomeAdmission{}, wakeOutcomePreflightFallback{}, false, nil
}

// RetrieveAckCustodyPending is available even while admission is disabled. A
// new binary on a legacy-only memory deployment returns an explicit backend
// error so clients can negotiate same-peer legacy retrieval.
func (is *InboxStore) RetrieveAckCustodyPending(
	peerID string,
	limit int,
) ([]inboxMessage, bool, error) {
	backend, ok := is.backend.(AckCustodyInboxBackend)
	if !ok {
		return nil, false, errAckCustodyBackendUnavailable
	}
	return backend.RetrieveAckCustodyPending(peerID, limit)
}

// AckAckCustody removes each logical ID from the protected lane and its legacy
// shadow atomically. Like retrieval, draining stays enabled under kill switch.
func (is *InboxStore) AckAckCustody(peerID string, entryIDs []string) (int, error) {
	backend, ok := is.backend.(AckCustodyInboxBackend)
	if !ok {
		return 0, errAckCustodyBackendUnavailable
	}
	return backend.AckAckCustody(peerID, entryIDs)
}

func (is *InboxStore) CountAckCustody(peerID string) int {
	backend, ok := is.backend.(AckCustodyInboxBackend)
	if !ok {
		return 0
	}
	return backend.CountAckCustody(peerID)
}

func (is *InboxStore) AckCustodyStats() (int, int) {
	backend, ok := is.backend.(AckCustodyInboxBackend)
	if !ok {
		return 0, 0
	}
	return backend.AckCustodyStats()
}

func refreshAckCustodyPendingGauge(inbox *InboxStore) int {
	if inbox == nil {
		inboxCustodyMessagesPendingGauge.Set(0)
		return 0
	}
	_, totalMessages := inbox.AckCustodyStats()
	inboxCustodyMessagesPendingGauge.Set(float64(totalMessages))
	return totalMessages
}
