package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"
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
) bool {
	if ceiling == nil {
		return true
	}
	// The additive bound belongs only to v108 direct-media envelopes. Reactions
	// and every legacy action retain their frozen timestamp-derived lifetime.
	if custodyKind != ackCustodyDirectTextKind {
		return false
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
// inbox dedupe parser. The new lane accepts only the two custody-owned envelope
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
	if directKey := extractDirectInboxDedupeKey(message); directKey != "" {
		return directKey
	}
	return ""
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
	result, storedEntry, err := backend.StoreAckCustody(toPeerID, entry, dedupeKey)
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
		is.recordStoredAndLaunchPush(toPeerID, storedEntry)
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
