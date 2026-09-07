package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/redis/go-redis/v9"
)

const (
	wakeOutcomeAction     = "wake_outcome_v1"
	wakeOutcomeCapability = "wake_outcome_v1"

	wakeOutcomeDebounce         = 500 * time.Millisecond
	wakeOutcomeRetention        = 7 * 24 * time.Hour
	wakeOutcomeClaimLease       = 10 * time.Second
	wakeOutcomeProviderTimeout  = 5 * time.Second
	wakeOutcomeCoordinatorTick  = 100 * time.Millisecond
	wakeOutcomeCoordinatorBatch = 32
	wakeOutcomePerPeerCapacity  = 512

	wakeOutcomeCorrelationDomain    = "mknoon/wake-outcome/v1"
	wakeOutcomeMaxPhysicalPeerBytes = 1024
	wakeOutcomeMaxEventKeyBytes     = 4096
)

var (
	errWakeOutcomeRouteChanged       = errors.New("wake outcome route changed")
	errWakeOutcomeCapacity           = errors.New("wake outcome capacity")
	errWakeOutcomeBackendUnavailable = errors.New("wake outcome backend unavailable")
	errWakeOutcomeClaimChanged       = errors.New("wake outcome claim changed")
)

type wakeOutcomeProducerKind byte

const (
	wakeOutcomeProducerDirectMessage  wakeOutcomeProducerKind = 0x01
	wakeOutcomeProducerDirectReaction wakeOutcomeProducerKind = 0x02
	wakeOutcomeProducerGroupMessage   wakeOutcomeProducerKind = 0x03
	wakeOutcomeProducerGroupReaction  wakeOutcomeProducerKind = 0x04
)

type wakeOutcomeRoutePolicy string

const (
	wakeOutcomePolicyNone           wakeOutcomeRoutePolicy = "none"
	wakeOutcomePolicyDirectReaction wakeOutcomeRoutePolicy = directReactionCapability
	wakeOutcomePolicyGroupReaction  wakeOutcomeRoutePolicy = groupReactionCapability
)

func (p wakeOutcomeRoutePolicy) valid() bool {
	switch p {
	case wakeOutcomePolicyNone, wakeOutcomePolicyDirectReaction, wakeOutcomePolicyGroupReaction:
		return true
	default:
		return false
	}
}

func wakeOutcomePolicyForProducer(producer wakeOutcomeProducerKind) (wakeOutcomeRoutePolicy, bool) {
	switch producer {
	case wakeOutcomeProducerDirectMessage, wakeOutcomeProducerGroupMessage:
		return wakeOutcomePolicyNone, true
	case wakeOutcomeProducerDirectReaction:
		return wakeOutcomePolicyDirectReaction, true
	case wakeOutcomeProducerGroupReaction:
		return wakeOutcomePolicyGroupReaction, true
	default:
		return "", false
	}
}

type wakeOutcomeAdmission struct {
	recipientPeerID                  string
	correlation                      string
	producer                         wakeOutcomeProducerKind
	policy                           wakeOutcomeRoutePolicy
	groupMessageDispatchAdmissionKey string
	route                            pushRouteLease
	storedAtMs                       int64
	eventExpiresAtMs                 int64
	androidRichMaterial              []byte
}

func (a wakeOutcomeAdmission) RecipientPeerID() string { return a.recipientPeerID }
func (a wakeOutcomeAdmission) Correlation() string     { return a.correlation }
func (a wakeOutcomeAdmission) Route() pushRouteLease   { return copyPushRouteLease(a.route) }

type wakeOutcomeAdmissionStatus string

const (
	wakeOutcomeAdmissionDelayed           wakeOutcomeAdmissionStatus = "delayed"
	wakeOutcomeAdmissionSuppressed        wakeOutcomeAdmissionStatus = "suppressed"
	wakeOutcomeAdmissionCapacityFallback  wakeOutcomeAdmissionStatus = "capacity_fallback"
	wakeOutcomeAdmissionImmediateFallback wakeOutcomeAdmissionStatus = "immediate_fallback"
	wakeOutcomeAdmissionAndroidRich       wakeOutcomeAdmissionStatus = "android_rich"
)

type wakeOutcomeAdmissionResult struct {
	recipientPeerID string
	correlation     string
	status          wakeOutcomeAdmissionStatus
}

func (r wakeOutcomeAdmissionResult) RequiresImmediateWake() bool {
	return r.status == wakeOutcomeAdmissionCapacityFallback ||
		r.status == wakeOutcomeAdmissionImmediateFallback
}

func (r wakeOutcomeAdmissionResult) Delayed() bool {
	return r.status == wakeOutcomeAdmissionDelayed
}

func newWakeOutcomeAdmission(
	recipientPeerID string,
	message string,
	producer wakeOutcomeProducerKind,
	route pushRouteLease,
	storedAtMs int64,
	eventExpiresAtMs int64,
) (wakeOutcomeAdmission, bool) {
	correlation, ok := wakeOutcomeCorrelation(recipientPeerID, producer, message)
	if !ok {
		return wakeOutcomeAdmission{}, false
	}
	return newWakeOutcomeAdmissionWithCorrelation(
		recipientPeerID,
		producer,
		correlation,
		route,
		storedAtMs,
		eventExpiresAtMs,
	)
}

// newWakeOutcomeAdmissionForEvent is reserved for producer adapters that have
// already authenticated an event identity whose wire spelling differs from the
// Plan-369 correlation projection. The direct- and group-reaction adapters pass
// only their incumbent parser's validated EventID/TransitionID here; the raw
// vector extractor remains exact and never accepts those wire keys as aliases.
func newWakeOutcomeAdmissionForEvent(
	recipientPeerID string,
	producer wakeOutcomeProducerKind,
	eventKey string,
	route pushRouteLease,
	storedAtMs int64,
	eventExpiresAtMs int64,
) (wakeOutcomeAdmission, bool) {
	correlation, ok := wakeOutcomeCorrelationForEvent(recipientPeerID, producer, eventKey)
	if !ok {
		return wakeOutcomeAdmission{}, false
	}
	return newWakeOutcomeAdmissionWithCorrelation(
		recipientPeerID,
		producer,
		correlation,
		route,
		storedAtMs,
		eventExpiresAtMs,
	)
}

func newWakeOutcomeAdmissionWithCorrelation(
	recipientPeerID string,
	producer wakeOutcomeProducerKind,
	correlation string,
	route pushRouteLease,
	storedAtMs int64,
	eventExpiresAtMs int64,
) (wakeOutcomeAdmission, bool) {
	policy, ok := wakeOutcomePolicyForProducer(producer)
	if !ok || storedAtMs <= 0 || eventExpiresAtMs <= storedAtMs {
		return wakeOutcomeAdmission{}, false
	}
	if route.Handle == "" || route.Generation == 0 || route.lookupKey == "" ||
		!route.hasCapability(opaqueWakeCapability) ||
		!route.hasCapability(wakeOutcomeCapability) ||
		!slices.Equal(route.Capabilities, canonicalPushCapabilities(route.Capabilities)) {
		return wakeOutcomeAdmission{}, false
	}
	if policy != wakeOutcomePolicyNone && !route.hasCapability(string(policy)) {
		return wakeOutcomeAdmission{}, false
	}
	if !isCanonicalWakeOutcomeCorrelation(correlation) {
		return wakeOutcomeAdmission{}, false
	}
	return wakeOutcomeAdmission{
		recipientPeerID:  recipientPeerID,
		correlation:      correlation,
		producer:         producer,
		policy:           policy,
		route:            copyPushRouteLease(route),
		storedAtMs:       storedAtMs,
		eventExpiresAtMs: eventExpiresAtMs,
	}, true
}

func wakeOutcomeCorrelation(
	recipientPeerID string,
	producer wakeOutcomeProducerKind,
	message string,
) (string, bool) {
	fields, err := decodePushTokenJSONObject([]byte(message), nil, maxFrameLen)
	if err != nil {
		return "", false
	}
	field := ""
	switch producer {
	case wakeOutcomeProducerDirectMessage:
		field = "messageId"
	case wakeOutcomeProducerDirectReaction:
		field = "reactionId"
	case wakeOutcomeProducerGroupMessage:
		field = "messageId"
		if _, present := fields["logicalDeliveryId"]; present {
			field = "logicalDeliveryId"
		}
	case wakeOutcomeProducerGroupReaction:
		field = "notificationTransitionId"
	default:
		return "", false
	}
	eventKey, ok := decodeWakeOutcomeJSONStringToken(fields[field])
	if !ok {
		return "", false
	}
	return wakeOutcomeCorrelationForEvent(recipientPeerID, producer, eventKey)
}

// wakeOutcomeJSONStringField decodes an exact string-valued authority at the
// requested object path without allowing encoding/json to normalize malformed
// Unicode into U+FFFD first. It is intentionally path-exact: reaction adapters
// name their authenticated event field rather than accepting correlation-vector
// aliases from a different wire shape.
func wakeOutcomeJSONStringField(message string, path ...string) (string, bool) {
	if len(path) == 0 {
		return "", false
	}
	raw := json.RawMessage(message)
	for _, field := range path {
		fields, err := decodePushTokenJSONObject(raw, nil, maxFrameLen)
		if err != nil {
			return "", false
		}
		var present bool
		raw, present = fields[field]
		if !present {
			return "", false
		}
	}
	return decodeWakeOutcomeJSONStringToken(raw)
}

func decodeWakeOutcomeJSONStringToken(raw json.RawMessage) (string, bool) {
	token := bytes.TrimSpace(raw)
	if !validWakeOutcomeJSONStringScalars(token) {
		return "", false
	}
	var value string
	if err := decodePushTokenJSONField(token, &value); err != nil {
		return "", false
	}
	return value, true
}

// validWakeOutcomeJSONStringScalars validates the scalar boundary that Go's
// encoding/json deliberately repairs. Raw UTF-8 must be well formed, a high
// UTF-16 surrogate escape must be followed immediately by its low surrogate,
// and a low surrogate may never stand alone. Explicit U+FFFD remains valid,
// as does escaped text such as "\\uD800" whose backslash is itself escaped.
func validWakeOutcomeJSONStringScalars(token []byte) bool {
	if len(token) < 2 || token[0] != '"' || token[len(token)-1] != '"' {
		return false
	}
	end := len(token) - 1
	for index := 1; index < end; {
		candidate := token[index]
		switch {
		case candidate == '\\':
			if index+1 >= end {
				return false
			}
			escape := token[index+1]
			if escape != 'u' {
				switch escape {
				case '"', '\\', '/', 'b', 'f', 'n', 'r', 't':
					index += 2
					continue
				default:
					return false
				}
			}

			codeUnit, ok := wakeOutcomeJSONHexCodeUnit(token, index)
			if !ok {
				return false
			}
			if codeUnit >= 0xd800 && codeUnit <= 0xdbff {
				next := index + 6
				if next+1 >= end || token[next] != '\\' || token[next+1] != 'u' {
					return false
				}
				low, ok := wakeOutcomeJSONHexCodeUnit(token, next)
				if !ok || low < 0xdc00 || low > 0xdfff {
					return false
				}
				index = next + 6
				continue
			}
			if codeUnit >= 0xdc00 && codeUnit <= 0xdfff {
				return false
			}
			index += 6
		case candidate < 0x20 || candidate == '"':
			return false
		case candidate < utf8.RuneSelf:
			index++
		default:
			decoded, size := utf8.DecodeRune(token[index:end])
			if decoded == utf8.RuneError && size == 1 {
				return false
			}
			index += size
		}
	}
	return true
}

func wakeOutcomeJSONHexCodeUnit(token []byte, slashIndex int) (uint16, bool) {
	if slashIndex < 0 || slashIndex+6 > len(token)-1 ||
		token[slashIndex] != '\\' || token[slashIndex+1] != 'u' {
		return 0, false
	}
	var result uint16
	for _, candidate := range token[slashIndex+2 : slashIndex+6] {
		result <<= 4
		switch {
		case candidate >= '0' && candidate <= '9':
			result |= uint16(candidate - '0')
		case candidate >= 'a' && candidate <= 'f':
			result |= uint16(candidate-'a') + 10
		case candidate >= 'A' && candidate <= 'F':
			result |= uint16(candidate-'A') + 10
		default:
			return 0, false
		}
	}
	return result, true
}

func wakeOutcomeCorrelationForEvent(
	recipientPeerID string,
	producer wakeOutcomeProducerKind,
	eventKey string,
) (string, bool) {
	if _, ok := wakeOutcomePolicyForProducer(producer); !ok {
		return "", false
	}
	peerBytes, ok := canonicalWakeOutcomeUTF8(recipientPeerID, wakeOutcomeMaxPhysicalPeerBytes)
	if !ok {
		return "", false
	}
	eventBytes, ok := canonicalWakeOutcomeUTF8(eventKey, wakeOutcomeMaxEventKeyBytes)
	if !ok {
		return "", false
	}
	domain := []byte(wakeOutcomeCorrelationDomain)
	preimage := make([]byte, 0, 4+len(domain)+4+len(peerBytes)+1+4+len(eventBytes))
	preimage = appendWakeOutcomeLP32(preimage, domain)
	preimage = appendWakeOutcomeLP32(preimage, peerBytes)
	preimage = append(preimage, byte(producer))
	preimage = appendWakeOutcomeLP32(preimage, eventBytes)
	digest := sha256.Sum256(preimage)
	return hex.EncodeToString(digest[:]), true
}

func appendWakeOutcomeLP32(destination, value []byte) []byte {
	var length [4]byte
	binary.BigEndian.PutUint32(length[:], uint32(len(value)))
	destination = append(destination, length[:]...)
	return append(destination, value...)
}

func canonicalWakeOutcomeUTF8(value string, maxBytes int) ([]byte, bool) {
	if value == "" || value != strings.TrimSpace(value) || !utf8.ValidString(value) ||
		strings.HasPrefix(value, "\uFEFF") || strings.HasSuffix(value, "\uFEFF") ||
		len(value) > maxBytes {
		return nil, false
	}
	for _, candidate := range value {
		if candidate <= 0x1f || candidate == 0x7f {
			return nil, false
		}
	}
	return []byte(value), true
}

type wakeOutcomeState string

const (
	wakeOutcomeStatePending   wakeOutcomeState = "pending"
	wakeOutcomeStateClaimed   wakeOutcomeState = "claimed"
	wakeOutcomeStateCompleted wakeOutcomeState = "completed"
)

type redisWakeOutcomeRecord struct {
	State                            wakeOutcomeState       `json:"state"`
	Revision                         uint64                 `json:"revision"`
	DueAtMs                          int64                  `json:"due_at_ms,omitempty"`
	ClaimUntilMs                     int64                  `json:"claim_until_ms,omitempty"`
	ClaimToken                       string                 `json:"claim_token,omitempty"`
	RetryCount                       int                    `json:"retry_count"`
	ExpiresAtMs                      int64                  `json:"expires_at_ms"`
	Policy                           wakeOutcomeRoutePolicy `json:"policy"`
	GroupMessageDispatchAdmissionKey string                 `json:"group_message_dispatch_admission_key,omitempty"`
	AndroidRichDigest                string                 `json:"android_rich_digest,omitempty"`
}

func (record redisWakeOutcomeRecord) validate() error {
	if record.Revision == 0 || record.RetryCount < 0 || record.ExpiresAtMs <= 0 || !record.Policy.valid() {
		return errors.New("wake outcome record metadata is invalid")
	}
	if record.AndroidRichDigest != "" && (!isCanonicalWakeOutcomeCorrelation(record.AndroidRichDigest) || record.Policy != wakeOutcomePolicyNone) {
		return errors.New("Android notification recovery record is invalid")
	}
	if record.GroupMessageDispatchAdmissionKey != "" &&
		!canonicalGroupMessageDispatchAdmissionStorageKey(record.GroupMessageDispatchAdmissionKey) {
		return errors.New("wake outcome group-message dispatch admission key is invalid")
	}
	switch record.State {
	case wakeOutcomeStatePending:
		if record.DueAtMs <= 0 || record.ClaimUntilMs != 0 || record.ClaimToken != "" {
			return errors.New("pending wake outcome record is invalid")
		}
	case wakeOutcomeStateClaimed:
		if record.DueAtMs <= 0 || record.ClaimUntilMs <= 0 || record.ClaimToken == "" {
			return errors.New("claimed wake outcome record is invalid")
		}
	case wakeOutcomeStateCompleted:
		if record.DueAtMs != 0 || record.ClaimUntilMs != 0 || record.ClaimToken != "" {
			return errors.New("completed wake outcome record is invalid")
		}
	default:
		return errors.New("wake outcome state is invalid")
	}
	return nil
}

func encodeRedisWakeOutcomeRecord(record redisWakeOutcomeRecord) (string, error) {
	if err := record.validate(); err != nil {
		return "", err
	}
	payload, err := json.Marshal(record)
	return string(payload), err
}

func decodeRedisWakeOutcomeRecord(payload string) (redisWakeOutcomeRecord, error) {
	var record redisWakeOutcomeRecord
	if err := json.Unmarshal([]byte(payload), &record); err != nil {
		return record, err
	}
	return record, record.validate()
}

type redisWakeOutcomeStore struct {
	client  *redis.Client
	prefix  string
	now     func() time.Time
	entropy io.Reader
}

func newRedisWakeOutcomeStore(client *redis.Client, prefix string) *redisWakeOutcomeStore {
	return &redisWakeOutcomeStore{client: client, prefix: prefix, now: time.Now, entropy: rand.Reader}
}

func (s *redisWakeOutcomeStore) nowTime() time.Time {
	if s != nil && s.now != nil {
		return s.now()
	}
	return time.Now()
}

func (s *redisWakeOutcomeStore) stateKey(peerID string) string {
	return s.prefix + "wake-outcome:" + encodeRedisComponent(peerID)
}

func (s *redisWakeOutcomeStore) dueKey() string { return s.prefix + "wake-outcome:due" }

func (s *redisWakeOutcomeStore) validateDueIndexType(
	ctx context.Context,
	tx *redis.Tx,
) error {
	keyType, err := tx.Type(ctx, s.dueKey()).Result()
	if err != nil {
		return fmt.Errorf("inspect wake outcome due index type: %w", err)
	}
	if keyType != "none" && keyType != "zset" {
		return fmt.Errorf("wake outcome due index has invalid Redis type %q", keyType)
	}
	return nil
}

func wakeOutcomeDueMember(peerID, correlation string) string {
	return encodeRedisComponent(peerID) + "." + correlation
}

func parseWakeOutcomeDueMember(value string) (string, string, error) {
	peerComponent, correlation, found := strings.Cut(value, ".")
	if !found || !isCanonicalWakeOutcomeCorrelation(correlation) {
		return "", "", errors.New("wake outcome due member is invalid")
	}
	peerBytes, err := base64.RawURLEncoding.Strict().DecodeString(peerComponent)
	if err != nil || len(peerBytes) == 0 || encodeRedisComponent(string(peerBytes)) != peerComponent {
		return "", "", errors.New("wake outcome due peer is invalid")
	}
	if _, ok := canonicalWakeOutcomeUTF8(string(peerBytes), wakeOutcomeMaxPhysicalPeerBytes); !ok {
		return "", "", errors.New("wake outcome due peer is invalid")
	}
	return string(peerBytes), correlation, nil
}

func (s *redisWakeOutcomeStore) loadLiveRecords(
	getter interface {
		HGetAll(context.Context, string) *redis.MapStringStringCmd
	},
	peerID string,
	nowMs int64,
) (map[string]redisWakeOutcomeRecord, []string, bool, error) {
	raw, err := getter.HGetAll(context.Background(), s.stateKey(peerID)).Result()
	if err != nil {
		return nil, nil, false, err
	}
	records := make(map[string]redisWakeOutcomeRecord, len(raw))
	expiredMembers := make([]string, 0)
	dirty := false
	for correlation, payload := range raw {
		if !isCanonicalWakeOutcomeCorrelation(correlation) {
			return nil, nil, false, errors.New("wake outcome hash field is invalid")
		}
		record, err := decodeRedisWakeOutcomeRecord(payload)
		if err != nil {
			return nil, nil, false, fmt.Errorf("decode wake outcome record: %w", err)
		}
		if record.ExpiresAtMs <= nowMs {
			dirty = true
			expiredMembers = append(expiredMembers, wakeOutcomeDueMember(peerID, correlation))
			continue
		}
		records[correlation] = record
	}
	return records, expiredMembers, dirty, nil
}

func queueWakeOutcomeHash(
	ctx context.Context,
	pipe redis.Pipeliner,
	key string,
	records map[string]redisWakeOutcomeRecord,
) error {
	pipe.Del(ctx, key)
	if len(records) == 0 {
		return nil
	}
	correlations := make([]string, 0, len(records))
	for correlation := range records {
		correlations = append(correlations, correlation)
	}
	slices.Sort(correlations)
	values := make([]interface{}, 0, len(records)*2)
	var expiresAtMs int64
	for _, correlation := range correlations {
		record := records[correlation]
		payload, err := encodeRedisWakeOutcomeRecord(record)
		if err != nil {
			return err
		}
		values = append(values, correlation, payload)
		if record.ExpiresAtMs > expiresAtMs {
			expiresAtMs = record.ExpiresAtMs
		}
	}
	pipe.HSet(ctx, key, values...)
	pipe.PExpireAt(ctx, key, time.UnixMilli(expiresAtMs))
	return nil
}

func queueWakeOutcomeDueRemovals(
	ctx context.Context,
	pipe redis.Pipeliner,
	dueKey string,
	members []string,
) {
	if len(members) == 0 {
		return
	}
	values := make([]interface{}, len(members))
	for index, member := range members {
		values[index] = member
	}
	pipe.ZRem(ctx, dueKey, values...)
}

type wakeOutcomeCompletionStatus string

const (
	wakeOutcomeCompletionRecorded   wakeOutcomeCompletionStatus = "recorded"
	wakeOutcomeCompletionIdempotent wakeOutcomeCompletionStatus = "idempotent"
	wakeOutcomeCompletionClaimed    wakeOutcomeCompletionStatus = "claimed"
)

func (is *InboxStore) CompleteWakeOutcome(
	authenticatedPeerID string,
	correlation string,
) (wakeOutcomeCompletionStatus, error) {
	if is == nil {
		return "", errWakeOutcomeBackendUnavailable
	}
	if _, permanentImmediateOwner := is.backend.(*memoryInboxBackend); permanentImmediateOwner {
		return wakeOutcomeCompletionIdempotent, nil
	}
	backend, ok := is.backend.(interface {
		CompleteWakeOutcome(string, string) (wakeOutcomeCompletionStatus, error)
	})
	if !ok {
		return "", errWakeOutcomeBackendUnavailable
	}
	return backend.CompleteWakeOutcome(authenticatedPeerID, correlation)
}

func (b *redisInboxBackend) CompleteWakeOutcome(
	authenticatedPeerID string,
	correlation string,
) (wakeOutcomeCompletionStatus, error) {
	if b == nil || b.wakeOutcomes == nil {
		return "", errWakeOutcomeBackendUnavailable
	}
	return b.wakeOutcomes.complete(authenticatedPeerID, correlation)
}

func (s *redisWakeOutcomeStore) complete(
	authenticatedPeerID string,
	correlation string,
) (wakeOutcomeCompletionStatus, error) {
	if _, ok := canonicalWakeOutcomeUTF8(authenticatedPeerID, wakeOutcomeMaxPhysicalPeerBytes); !ok ||
		!isCanonicalWakeOutcomeCorrelation(correlation) {
		return "", errors.New("wake outcome authority is invalid")
	}
	stateKey := s.stateKey(authenticatedPeerID)
	dueKey := s.dueKey()
	var result wakeOutcomeCompletionStatus
	err := withRedisWatchRetryKeys(s.client, []string{stateKey, dueKey, s.androidRichCompletedKey(authenticatedPeerID, correlation)}, func(tx *redis.Tx) error {
		if err := s.validateDueIndexType(context.Background(), tx); err != nil {
			return err
		}
		nowMs := s.nowTime().UnixMilli()
		completed, err := s.androidRichCompleted(tx, authenticatedPeerID, correlation)
		if err != nil {
			return err
		}
		if completed {
			result = wakeOutcomeCompletionIdempotent
			return nil
		}
		var richCompletionExpiry int64
		records, expired, dirty, err := s.loadLiveRecords(tx, authenticatedPeerID, nowMs)
		if err != nil {
			return err
		}
		record, exists := records[correlation]
		if exists {
			switch record.State {
			case wakeOutcomeStateClaimed:
				result = wakeOutcomeCompletionClaimed
			case wakeOutcomeStateCompleted:
				result = wakeOutcomeCompletionIdempotent
			default:
				if record.Revision == math.MaxUint64 {
					return errors.New("wake outcome revision overflow")
				}
				record.State = wakeOutcomeStateCompleted
				record.Revision++
				record.DueAtMs = 0
				record.ClaimUntilMs = 0
				record.ClaimToken = ""
				if record.AndroidRichDigest != "" {
					richCompletionExpiry = record.ExpiresAtMs
					delete(records, correlation)
				} else {
					record.ExpiresAtMs = s.nowTime().Add(wakeOutcomeRetention).UnixMilli()
					records[correlation] = record
				}
				dirty = true
				result = wakeOutcomeCompletionRecorded
				expired = append(expired, wakeOutcomeDueMember(authenticatedPeerID, correlation))
			}
		} else {
			if len(records) >= wakeOutcomePerPeerCapacity {
				return errWakeOutcomeCapacity
			}
			records[correlation] = redisWakeOutcomeRecord{
				State: wakeOutcomeStateCompleted, Revision: 1,
				ExpiresAtMs: s.nowTime().Add(wakeOutcomeRetention).UnixMilli(),
				Policy:      wakeOutcomePolicyNone,
			}
			dirty = true
			result = wakeOutcomeCompletionRecorded
		}
		if !dirty {
			return nil
		}
		_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
			if err := queueWakeOutcomeHash(context.Background(), pipe, stateKey, records); err != nil {
				return err
			}
			if richCompletionExpiry > 0 {
				s.queueAndroidRichCompleted(context.Background(), pipe, authenticatedPeerID, correlation, richCompletionExpiry, nowMs)
			}
			queueWakeOutcomeDueRemovals(context.Background(), pipe, dueKey, expired)
			return nil
		})
		return err
	})
	if err != nil {
		return "", fmt.Errorf("complete wake outcome: %w", err)
	}
	return result, nil
}

type wakeOutcomePreparedState struct {
	peerID         string
	correlation    string
	records        map[string]redisWakeOutcomeRecord
	expiredMembers []string
	dirty          bool
	dueAtMs        int64
	status         wakeOutcomeAdmissionStatus
	androidRichRaw []byte
	materialExpiry int64
}

func (s *redisWakeOutcomeStore) admissionWatchKeys(admission wakeOutcomeAdmission) ([]string, error) {
	expectedRouteKey := s.prefix + "push-token-directory:" + encodeRedisComponent(admission.recipientPeerID)
	if len(admission.androidRichMaterial) > 0 && admission.route.Generation == 0 {
		expectedRouteKey = s.prefix + "push:" + encodeRedisComponent(admission.recipientPeerID)
	}
	if admission.recipientPeerID == "" || !isCanonicalWakeOutcomeCorrelation(admission.correlation) ||
		admission.route.lookupKey != expectedRouteKey {
		return nil, errWakeOutcomeRouteChanged
	}
	keys := uniqueRedisKeys(
		s.stateKey(admission.recipientPeerID),
		s.dueKey(),
		admission.route.lookupKey,
		s.prefix+"push-token-state",
	)
	if len(admission.androidRichMaterial) > 0 {
		keys = append(keys, s.androidRichMaterialKey(admission.recipientPeerID, admission.correlation), s.androidRichCompletedKey(admission.recipientPeerID, admission.correlation))
	}
	return keys, nil
}

func (s *redisWakeOutcomeStore) routeMatchesAdmission(
	tx *redis.Tx,
	admission wakeOutcomeAdmission,
) (bool, error) {
	if len(admission.androidRichMaterial) > 0 {
		return s.androidRichRouteMatchesAdmission(tx, admission)
	}
	return s.encryptedRouteMatchesAdmission(tx, admission)
}

func (s *redisWakeOutcomeStore) encryptedRouteMatchesAdmission(
	tx *redis.Tx,
	admission wakeOutcomeAdmission,
) (bool, error) {
	if admission.route.lookupKey != s.prefix+"push-token-directory:"+
		encodeRedisComponent(admission.recipientPeerID) {
		return false, nil
	}
	markerPayload, err := optionalRedisBytes(tx, s.prefix+"push-token-state")
	if err != nil || markerPayload == nil {
		return false, err
	}
	marker, err := decodePushTokenStateMarker(markerPayload)
	if err != nil {
		return false, err
	}
	if marker.State != pushTokenStateEncrypted {
		return false, nil
	}
	directoryPayload, err := optionalRedisBytes(tx, admission.route.lookupKey)
	if err != nil || directoryPayload == nil {
		return false, err
	}
	directory, err := decodePushTokenDirectoryRecord(directoryPayload)
	if err != nil {
		return false, err
	}
	// decodePushTokenDirectoryRecord validates the source-legacy digest. The
	// watched exact directory row then fences that source, handle, generation,
	// and canonical capability set through the event/state EXEC.
	return encryptedDirectoryMatchesRoute(directory, admission.route), nil
}

func (s *redisWakeOutcomeStore) prepareAdmission(
	tx *redis.Tx,
	admission wakeOutcomeAdmission,
	nowMs int64,
) (wakeOutcomePreparedState, error) {
	prepared := wakeOutcomePreparedState{
		peerID:      admission.recipientPeerID,
		correlation: admission.correlation,
	}
	matches, err := s.routeMatchesAdmission(tx, admission)
	if err != nil {
		return prepared, err
	}
	if !matches {
		return prepared, errWakeOutcomeRouteChanged
	}
	records, expired, dirty, err := s.loadLiveRecords(tx, admission.recipientPeerID, nowMs)
	if err != nil {
		return prepared, err
	}
	prepared.records = records
	prepared.expiredMembers = expired
	prepared.dirty = dirty
	if len(admission.androidRichMaterial) > 0 {
		completed, err := s.androidRichCompleted(tx, admission.recipientPeerID, admission.correlation)
		if err != nil {
			return prepared, err
		}
		if completed {
			prepared.status = wakeOutcomeAdmissionSuppressed
			return prepared, nil
		}
	}
	if _, exists := records[admission.correlation]; exists {
		prepared.status = wakeOutcomeAdmissionSuppressed
		return prepared, nil
	}
	if len(records) >= wakeOutcomePerPeerCapacity {
		prepared.status = wakeOutcomeAdmissionCapacityFallback
		return prepared, nil
	}
	expiresAtMs := admission.storedAtMs + wakeOutcomeRetention.Milliseconds()
	if admission.eventExpiresAtMs < expiresAtMs {
		expiresAtMs = admission.eventExpiresAtMs
	}
	dueAtMs := admission.storedAtMs + wakeOutcomeDebounce.Milliseconds()
	if len(admission.androidRichMaterial) > 0 {
		dueAtMs = nowMs // Keep the initial Android send immediate.
	}
	if expiresAtMs <= nowMs {
		prepared.status = wakeOutcomeAdmissionSuppressed
		return prepared, nil
	}
	if dueAtMs >= expiresAtMs {
		// A fresh event whose custody horizon ends before the debounce cannot own
		// a useful obligation. It is not suppressed by authenticated outcome
		// authority, so preserve its selected lease for one immediate fixed wake.
		prepared.status = wakeOutcomeAdmissionImmediateFallback
		return prepared, nil
	}
	records[admission.correlation] = redisWakeOutcomeRecord{
		State: wakeOutcomeStatePending, Revision: 1, DueAtMs: dueAtMs,
		ExpiresAtMs: expiresAtMs, Policy: admission.policy,
		GroupMessageDispatchAdmissionKey: admission.groupMessageDispatchAdmissionKey,
	}
	if len(admission.androidRichMaterial) > 0 {
		var material androidRichPushMaterial
		if len(admission.androidRichMaterial) > maxAndroidRichMaterialBytes ||
			json.Unmarshal(admission.androidRichMaterial, &material) != nil ||
			material.validate(admission.recipientPeerID, admission.correlation) != nil || material.ExpiresAtMs != expiresAtMs {
			return prepared, errors.New("Android recovery material is invalid at custody admission")
		}
		record := records[admission.correlation]
		record.AndroidRichDigest = androidRichMaterialDigest(admission.androidRichMaterial)
		records[admission.correlation] = record
		prepared.androidRichRaw = admission.androidRichMaterial
		prepared.materialExpiry = expiresAtMs
	}
	prepared.dirty = true
	prepared.dueAtMs = dueAtMs
	prepared.status = wakeOutcomeAdmissionDelayed
	if len(admission.androidRichMaterial) > 0 {
		prepared.status = wakeOutcomeAdmissionAndroidRich
	}
	return prepared, nil
}

func queueWakeOutcomePreparedState(
	ctx context.Context,
	pipe redis.Pipeliner,
	store *redisWakeOutcomeStore,
	prepared wakeOutcomePreparedState,
) error {
	if len(prepared.androidRichRaw) > 0 {
		pipe.Set(ctx, store.androidRichMaterialKey(prepared.peerID, prepared.correlation), prepared.androidRichRaw,
			androidRichMaterialTTL(prepared.materialExpiry, store.nowTime().UnixMilli()))
	}
	if prepared.dirty {
		if err := queueWakeOutcomeHash(ctx, pipe, store.stateKey(prepared.peerID), prepared.records); err != nil {
			return err
		}
	}
	queueWakeOutcomeDueRemovals(ctx, pipe, store.dueKey(), prepared.expiredMembers)
	if prepared.dueAtMs > 0 {
		pipe.ZAdd(ctx, store.dueKey(), redis.Z{
			Score:  float64(prepared.dueAtMs),
			Member: wakeOutcomeDueMember(prepared.peerID, prepared.correlation),
		})
	}
	return nil
}

func (b *redisInboxBackend) StoreWithWakeOutcome(
	toPeerID string,
	entry inboxMessage,
	admission wakeOutcomeAdmission,
) (InboxStoreResult, wakeOutcomeAdmissionStatus, error) {
	if b == nil || b.wakeOutcomes == nil {
		return "", "", errWakeOutcomeBackendUnavailable
	}
	watchKeys, err := b.wakeOutcomes.admissionWatchKeys(admission)
	if err != nil || admission.recipientPeerID != toPeerID {
		return "", "", errWakeOutcomeRouteChanged
	}
	entry = ensureInboxMessageID(entry)
	payload, err := json.Marshal(entry)
	if err != nil {
		return "", "", fmt.Errorf("encode inbox message: %w", err)
	}
	eventKey := b.key(toPeerID)
	watchKeys = uniqueRedisKeys(append(watchKeys, eventKey)...)
	dedupeKey := extractDirectInboxDedupeKey(entry.Message)
	var result InboxStoreResult
	var admissionStatus wakeOutcomeAdmissionStatus
	pruned, evicted := 0, 0

	err = withRedisWatchRetryKeys(b.client, watchKeys, func(tx *redis.Tx) error {
		if err := b.wakeOutcomes.validateDueIndexType(context.Background(), tx); err != nil {
			return err
		}
		rawEntries, err := tx.LRange(context.Background(), eventKey, 0, -1).Result()
		if err == redis.Nil {
			rawEntries = nil
		} else if err != nil {
			return err
		}
		cutoff := b.nowTime().Add(-maxMessageAge).UnixMilli()
		validRaw, validMessages, prunedInTx := normalizeInboxEntries(rawEntries, cutoff)
		pruned = prunedInTx
		evicted = 0
		if dedupeKey != "" {
			for _, message := range validMessages {
				if extractDirectInboxDedupeKey(message.Message) == dedupeKey {
					result = InboxStoreResultDuplicate
					admissionStatus = wakeOutcomeAdmissionSuppressed
					if slices.Equal(rawEntries, validRaw) {
						return nil
					}
					_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
						queueRedisListReplacement(context.Background(), pipe, eventKey, validRaw)
						return nil
					})
					return err
				}
			}
		}
		if len(validRaw) >= b.maxPerPeer {
			evicted = len(validRaw) - b.maxPerPeer + 1
			validRaw = validRaw[evicted:]
		}
		validRaw = append(validRaw, string(payload))
		prepared, err := b.wakeOutcomes.prepareAdmission(tx, admission, b.wakeOutcomes.nowTime().UnixMilli())
		if err != nil {
			return err
		}
		result = InboxStoreResultStored
		admissionStatus = prepared.status
		_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
			queueRedisListReplacement(context.Background(), pipe, eventKey, validRaw)
			return queueWakeOutcomePreparedState(context.Background(), pipe, b.wakeOutcomes, prepared)
		})
		return err
	})
	if err != nil {
		return "", "", fmt.Errorf("atomic inbox/wake outcome store: %w", err)
	}
	recordInboxExpiredPruned(pruned)
	if evicted > 0 {
		inboxCappedCounter.Add(float64(evicted))
	}
	return result, admissionStatus, nil
}

func queueRedisListReplacement(
	ctx context.Context,
	pipe redis.Pipeliner,
	key string,
	values []string,
) {
	pipe.Del(ctx, key)
	if len(values) == 0 {
		return
	}
	items := make([]interface{}, len(values))
	for index, value := range values {
		items[index] = value
	}
	pipe.RPush(ctx, key, items...)
}

func (b *redisGroupInboxBackend) StoreWithRecipientsAndWakeOutcomes(
	groupID string,
	from string,
	message string,
	recipientPeerIDs []string,
	admissions []wakeOutcomeAdmission,
) (GroupInboxStoreResult, []wakeOutcomeAdmissionResult, error) {
	if b == nil || b.wakeOutcomes == nil {
		return "", nil, errWakeOutcomeBackendUnavailable
	}
	normalizedRecipients := normalizePeerIds(recipientPeerIDs)
	if len(normalizedRecipients) == 0 || len(admissions) == 0 {
		return "", nil, errors.New("wake outcome group recipients are required")
	}
	eventKey := b.key(groupID)
	watchKeys := []string{eventKey}
	seenPeers := make(map[string]struct{}, len(admissions))
	for _, admission := range admissions {
		if _, duplicate := seenPeers[admission.recipientPeerID]; duplicate {
			return "", nil, errors.New("duplicate wake outcome group recipient")
		}
		seenPeers[admission.recipientPeerID] = struct{}{}
		keys, err := b.wakeOutcomes.admissionWatchKeys(admission)
		if err != nil {
			return "", nil, err
		}
		watchKeys = append(watchKeys, keys...)
	}
	watchKeys = uniqueRedisKeys(watchKeys...)
	messageID := extractMessageId(message)
	var result GroupInboxStoreResult
	var results []wakeOutcomeAdmissionResult
	droppedByCap := 0

	err := withRedisWatchRetryKeys(b.client, watchKeys, func(tx *redis.Tx) error {
		if err := b.wakeOutcomes.validateDueIndexType(context.Background(), tx); err != nil {
			return err
		}
		now := b.wakeOutcomes.nowTime()
		rawEntries, err := tx.LRange(context.Background(), eventKey, 0, -1).Result()
		if err == redis.Nil {
			rawEntries = nil
		} else if err != nil {
			return err
		}
		validRaw, validMessages, err := normalizeRedisGroupInboxRecords(
			rawEntries,
			now.Add(-b.ttl).UnixMilli(),
		)
		if err != nil {
			return err
		}
		if messageID != "" {
			for index := range validMessages {
				if extractMessageId(validMessages[index].Message) != messageID {
					continue
				}
				if validMessages[index].From != from || validMessages[index].Message != message {
					return fmt.Errorf("conflicting group inbox messageId %q", messageID)
				}
				validMessages[index].RecipientPeerIds = mergePeerIds(
					validMessages[index].RecipientPeerIds,
					normalizedRecipients,
				)
				nextRaw, err := encodeRedisGroupInboxRecords(validMessages)
				if err != nil {
					return err
				}
				result = GroupInboxStoreResultDuplicate
				results = nil
				if slices.Equal(rawEntries, nextRaw) {
					return nil
				}
				_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
					queueRedisListReplacement(context.Background(), pipe, eventKey, nextRaw)
					return nil
				})
				return err
			}
		}
		id, err := tx.Incr(context.Background(), b.sequenceKey()).Result()
		if err != nil {
			return fmt.Errorf("allocate group inbox id: %w", err)
		}
		record := redisGroupRecord{
			From: from, Message: message, Timestamp: now.UnixMilli(),
			ID: fmt.Sprintf("%d", id), RecipientPeerIds: normalizedRecipients,
		}
		payload, err := json.Marshal(record)
		if err != nil {
			return fmt.Errorf("encode group inbox message: %w", err)
		}
		values := append(append([]string(nil), validRaw...), string(payload))
		droppedByCap = 0
		if len(values) > b.maxPerGroup {
			droppedByCap = len(values) - b.maxPerGroup
			values = values[len(values)-b.maxPerGroup:]
		}
		preparedStates := make([]wakeOutcomePreparedState, 0, len(admissions))
		results = make([]wakeOutcomeAdmissionResult, 0, len(admissions))
		for _, original := range admissions {
			admission := original
			custodyExpiry := now.Add(b.ttl).UnixMilli()
			if admission.eventExpiresAtMs > custodyExpiry {
				admission.eventExpiresAtMs = custodyExpiry
			}
			prepared, err := b.wakeOutcomes.prepareAdmission(tx, admission, now.UnixMilli())
			if err != nil {
				return err
			}
			preparedStates = append(preparedStates, prepared)
			results = append(results, wakeOutcomeAdmissionResult{
				recipientPeerID: admission.recipientPeerID,
				correlation:     admission.correlation,
				status:          prepared.status,
			})
		}
		result = GroupInboxStoreResultStored
		_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
			queueRedisListReplacement(context.Background(), pipe, eventKey, values)
			for _, prepared := range preparedStates {
				if err := queueWakeOutcomePreparedState(context.Background(), pipe, b.wakeOutcomes, prepared); err != nil {
					return err
				}
			}
			return nil
		})
		return err
	})
	if err != nil {
		return "", nil, fmt.Errorf("atomic group inbox/wake outcome store: %w", err)
	}
	if droppedByCap > 0 {
		groupInboxCappedCounter.Add(float64(droppedByCap))
	}
	return result, results, nil
}

func (b *redisInboxBackend) StoreAckCustodyWithWakeOutcome(
	toPeerID string,
	entry inboxMessage,
	dedupeKey string,
	admission wakeOutcomeAdmission,
) (InboxStoreResult, inboxMessage, wakeOutcomeAdmissionStatus, error) {
	if b == nil || b.wakeOutcomes == nil {
		return "", inboxMessage{}, "", errWakeOutcomeBackendUnavailable
	}
	wakeWatchKeys, err := b.wakeOutcomes.admissionWatchKeys(admission)
	if err != nil || admission.recipientPeerID != toPeerID {
		return "", inboxMessage{}, "", errWakeOutcomeRouteChanged
	}
	entry = ensureInboxMessageID(entry)
	protectedKey := b.ackCustodyKey(toPeerID)
	legacyKey := b.key(toPeerID)
	watchKeys := uniqueRedisKeys(append(wakeWatchKeys, protectedKey, legacyKey)...)
	cutoff := b.nowTime().Add(-maxMessageAge).UnixMilli()
	capacity := b.maxPerPeer
	if capacity <= 0 {
		capacity = maxMessagesPerPeer
	}
	var (
		result          InboxStoreResult
		storedEntry     inboxMessage
		admissionStatus wakeOutcomeAdmissionStatus
		decisionErr     error
		protectedPruned int
		legacyPruned    int
		legacyEvicted   int
		acceptedCommit  bool
	)

	err = withRedisWatchRetryKeys(b.client, watchKeys, func(tx *redis.Tx) error {
		ctx := context.Background()
		if err := b.wakeOutcomes.validateDueIndexType(ctx, tx); err != nil {
			return err
		}
		protectedRaw, err := tx.LRange(ctx, protectedKey, 0, -1).Result()
		if err == redis.Nil {
			protectedRaw = nil
		} else if err != nil {
			return err
		}
		legacyRaw, err := tx.LRange(ctx, legacyKey, 0, -1).Result()
		if err == redis.Nil {
			legacyRaw = nil
		} else if err != nil {
			return err
		}
		validProtectedRaw, protectedMessages, protectedPrunedInTx :=
			normalizeInboxEntries(protectedRaw, cutoff)
		validLegacyRaw, legacyMessages, legacyPrunedInTx :=
			normalizeInboxEntries(legacyRaw, cutoff)
		protectedPruned = protectedPrunedInTx
		legacyPruned = legacyPrunedInTx
		legacyEvicted = 0
		acceptedCommit = false
		decisionErr = nil
		result = ""
		storedEntry = inboxMessage{}
		admissionStatus = wakeOutcomeAdmissionSuppressed

		var protectedMatch *inboxMessage
		for index := range protectedMessages {
			messageKey := extractStoredAckCustodyDedupeKey(
				protectedMessages[index].Message,
				protectedMessages[index].From,
				toPeerID,
			)
			if messageKey != dedupeKey {
				continue
			}
			if !inboxCustodyIdentityMatches(protectedMessages[index], entry) {
				decisionErr = errAckCustodyIdentityConflict
				break
			}
			matched := protectedMessages[index]
			protectedMatch = &matched
		}

		if decisionErr == nil && protectedMatch != nil {
			result = InboxStoreResultDuplicate
			storedEntry = *protectedMatch
		} else if decisionErr == nil {
			var legacyMatch *inboxMessage
			for index := range legacyMessages {
				if extractStoredAckCustodyDedupeKey(
					legacyMessages[index].Message,
					legacyMessages[index].From,
					toPeerID,
				) != dedupeKey {
					continue
				}
				if !inboxCustodyIdentityMatches(legacyMessages[index], entry) {
					decisionErr = errAckCustodyIdentityConflict
					break
				}
				matched := legacyMessages[index]
				legacyMatch = &matched
			}
			if decisionErr == nil && legacyMatch != nil && entry.ExpiresAtMs > 0 {
				decisionErr = errAckCustodyIdentityConflict
			} else if decisionErr == nil && len(protectedMessages) >= capacity {
				result = InboxStoreResultRejectedFull
			} else if decisionErr == nil && legacyMatch != nil {
				storedEntry = *legacyMatch
				payload, err := json.Marshal(storedEntry)
				if err != nil {
					return fmt.Errorf("encode promoted custody message: %w", err)
				}
				validProtectedRaw = append(validProtectedRaw, string(payload))
				result = InboxStoreResultDuplicate
				acceptedCommit = true
			} else if decisionErr == nil {
				storedEntry = entry
				payload, err := json.Marshal(storedEntry)
				if err != nil {
					return fmt.Errorf("encode custody message: %w", err)
				}
				validProtectedRaw = append(validProtectedRaw, string(payload))
				if len(validLegacyRaw) >= capacity {
					legacyEvicted = len(validLegacyRaw) - capacity + 1
					validLegacyRaw = validLegacyRaw[legacyEvicted:]
				}
				validLegacyRaw = append(validLegacyRaw, string(payload))
				result = InboxStoreResultStored
				acceptedCommit = true
			}
		}

		var prepared wakeOutcomePreparedState
		if result == InboxStoreResultStored && decisionErr == nil {
			prepared, err = b.wakeOutcomes.prepareAdmission(
				tx,
				admission,
				b.wakeOutcomes.nowTime().UnixMilli(),
			)
			if err != nil {
				return err
			}
			admissionStatus = prepared.status
		}
		needsWrite := !equalStringSlices(protectedRaw, validProtectedRaw) ||
			!equalStringSlices(legacyRaw, validLegacyRaw) || prepared.dirty ||
			len(prepared.expiredMembers) > 0 || prepared.dueAtMs > 0
		if !needsWrite {
			return nil
		}
		if acceptedCommit && b.ackCustodyBeforeCommit != nil {
			if err := b.ackCustodyBeforeCommit(); err != nil {
				return err
			}
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			queueRedisListReplacement(ctx, pipe, protectedKey, validProtectedRaw)
			queueRedisListReplacement(ctx, pipe, legacyKey, validLegacyRaw)
			if result == InboxStoreResultStored {
				return queueWakeOutcomePreparedState(ctx, pipe, b.wakeOutcomes, prepared)
			}
			return nil
		})
		return err
	})
	if err != nil {
		return "", inboxMessage{}, "", fmt.Errorf("atomic protected/shadow/wake outcome store: %w", err)
	}
	recordAckCustodyExpired(protectedPruned)
	recordInboxExpiredPruned(legacyPruned)
	if legacyEvicted > 0 {
		inboxCappedCounter.Add(float64(legacyEvicted))
	}
	if decisionErr != nil {
		return "", inboxMessage{}, "", decisionErr
	}
	if acceptedCommit && b.ackCustodyAfterCommit != nil {
		if err := b.ackCustodyAfterCommit(); err != nil {
			return "", inboxMessage{}, "", fmt.Errorf("ack custody response after commit: %w", err)
		}
	}
	return result, storedEntry, admissionStatus, nil
}

type wakeOutcomeClaim struct {
	peerID                           string
	correlation                      string
	policy                           wakeOutcomeRoutePolicy
	token                            string
	revision                         uint64
	groupMessageDispatchAdmissionKey string
	androidRichDigest                string
}

func (s *redisWakeOutcomeStore) newClaimToken() (string, error) {
	buffer := make([]byte, 16)
	if _, err := io.ReadFull(s.entropy, buffer); err != nil {
		return "", err
	}
	return hex.EncodeToString(buffer), nil
}

func (s *redisWakeOutcomeStore) claimDue(now time.Time, limit int) ([]wakeOutcomeClaim, error) {
	if limit <= 0 {
		return nil, nil
	}
	claims := make([]wakeOutcomeClaim, 0, limit)
	for handled := 0; handled < limit; handled++ {
		claim, claimed, found, err := s.claimNextDue(now)
		if err != nil {
			return nil, err
		}
		if !found {
			break
		}
		if claimed {
			claims = append(claims, claim)
		}
	}
	return claims, nil
}

// claimNextDue distinguishes an empty due index from one stale due member that
// was inspected and repaired/pruned without producing a provider claim. The
// coordinator needs that distinction to consume stale head-of-line work within
// its fixed batch budget instead of delaying every later live row by one tick.
func (s *redisWakeOutcomeStore) claimNextDue(
	now time.Time,
) (wakeOutcomeClaim, bool, bool, error) {
	members, err := s.client.ZRangeByScore(context.Background(), s.dueKey(), &redis.ZRangeBy{
		Min: "-inf", Max: strconv.FormatInt(now.UnixMilli(), 10), Count: 1,
	}).Result()
	if err != nil {
		return wakeOutcomeClaim{}, false, false, err
	}
	if len(members) == 0 {
		return wakeOutcomeClaim{}, false, false, nil
	}
	claim, claimed, err := s.claimOne(members[0], now)
	return claim, claimed, true, err
}

func (s *redisWakeOutcomeStore) claimOne(
	member string,
	now time.Time,
) (wakeOutcomeClaim, bool, error) {
	peerID, correlation, err := parseWakeOutcomeDueMember(member)
	if err != nil {
		_ = s.client.ZRem(context.Background(), s.dueKey(), member).Err()
		return wakeOutcomeClaim{}, false, nil
	}
	stateKey := s.stateKey(peerID)
	var result wakeOutcomeClaim
	claimed := false
	err = withRedisWatchRetryKeys(s.client, []string{stateKey, s.dueKey()}, func(tx *redis.Tx) error {
		if err := s.validateDueIndexType(context.Background(), tx); err != nil {
			return err
		}
		nowMs := now.UnixMilli()
		records, expired, dirty, err := s.loadLiveRecords(tx, peerID, nowMs)
		if err != nil {
			return err
		}
		record, exists := records[correlation]
		if !exists || record.State == wakeOutcomeStateCompleted {
			expired = append(expired, member)
			dirty = true
		} else if record.State == wakeOutcomeStatePending && record.DueAtMs > nowMs {
			_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
				pipe.ZAdd(context.Background(), s.dueKey(), redis.Z{Score: float64(record.DueAtMs), Member: member})
				return nil
			})
			return err
		} else if record.State == wakeOutcomeStateClaimed && record.ClaimUntilMs > nowMs {
			_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
				pipe.ZAdd(context.Background(), s.dueKey(), redis.Z{Score: float64(record.ClaimUntilMs), Member: member})
				return nil
			})
			return err
		} else {
			if record.Revision == math.MaxUint64 {
				return errors.New("wake outcome revision overflow")
			}
			token, err := s.newClaimToken()
			if err != nil {
				return err
			}
			record.State = wakeOutcomeStateClaimed
			record.Revision++
			record.ClaimToken = token
			record.ClaimUntilMs = now.Add(wakeOutcomeClaimLease).UnixMilli()
			records[correlation] = record
			dirty = true
			claimed = true
			result = wakeOutcomeClaim{
				peerID: peerID, correlation: correlation, policy: record.Policy,
				token: token, revision: record.Revision,
				groupMessageDispatchAdmissionKey: record.GroupMessageDispatchAdmissionKey,
				androidRichDigest:                record.AndroidRichDigest,
			}
		}
		if !dirty {
			return nil
		}
		_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
			if err := queueWakeOutcomeHash(context.Background(), pipe, stateKey, records); err != nil {
				return err
			}
			queueWakeOutcomeDueRemovals(context.Background(), pipe, s.dueKey(), expired)
			if claimed {
				pipe.ZAdd(context.Background(), s.dueKey(), redis.Z{
					Score: float64(now.Add(wakeOutcomeClaimLease).UnixMilli()), Member: member,
				})
			}
			return nil
		})
		return err
	})
	return result, claimed, err
}

func wakeOutcomeRetryDelay(retryCount int) time.Duration {
	if retryCount < 1 {
		return time.Second
	}
	shift := min(retryCount-1, 6)
	delay := time.Second * time.Duration(1<<shift)
	if delay > time.Minute {
		return time.Minute
	}
	return delay
}

func (s *redisWakeOutcomeStore) settle(
	claim wakeOutcomeClaim,
	result pushDeliveryResult,
	now time.Time,
) error {
	stateKey := s.stateKey(claim.peerID)
	member := wakeOutcomeDueMember(claim.peerID, claim.correlation)
	return withRedisWatchRetryKeys(s.client, []string{stateKey, s.dueKey(), s.androidRichCompletedKey(claim.peerID, claim.correlation)}, func(tx *redis.Tx) error {
		if err := s.validateDueIndexType(context.Background(), tx); err != nil {
			return err
		}
		records, expired, dirty, err := s.loadLiveRecords(tx, claim.peerID, now.UnixMilli())
		if err != nil {
			return err
		}
		record, exists := records[claim.correlation]
		if !exists || record.State != wakeOutcomeStateClaimed ||
			record.ClaimToken != claim.token || record.Revision != claim.revision {
			return errWakeOutcomeClaimChanged
		}
		if record.Revision == math.MaxUint64 {
			return errors.New("wake outcome revision overflow")
		}
		record.Revision++
		var richCompletionExpiry int64
		switch result {
		case pushDeliveryAccepted, pushDeliveryPermanent, pushDeliverySuppressed:
			record.State = wakeOutcomeStateCompleted
			record.DueAtMs = 0
			record.ClaimUntilMs = 0
			record.ClaimToken = ""
			if record.AndroidRichDigest != "" {
				richCompletionExpiry = record.ExpiresAtMs
				delete(records, claim.correlation)
			} else {
				record.ExpiresAtMs = now.Add(wakeOutcomeRetention).UnixMilli()
				records[claim.correlation] = record
			}
			expired = append(expired, member)
		case pushDeliveryRetryable:
			record.RetryCount++
			record.ClaimUntilMs = 0
			record.ClaimToken = ""
			if record.ExpiresAtMs <= now.UnixMilli() {
				delete(records, claim.correlation)
				expired = append(expired, member)
			} else {
				record.State = wakeOutcomeStatePending
				record.DueAtMs = now.Add(wakeOutcomeRetryDelay(record.RetryCount)).UnixMilli()
				if record.DueAtMs >= record.ExpiresAtMs {
					record.DueAtMs = record.ExpiresAtMs
				}
				records[claim.correlation] = record
			}
		default:
			return errors.New("wake outcome provider result is invalid")
		}
		dirty = true
		_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
			if dirty {
				if err := queueWakeOutcomeHash(context.Background(), pipe, stateKey, records); err != nil {
					return err
				}
			}
			if richCompletionExpiry > 0 {
				s.queueAndroidRichCompleted(context.Background(), pipe, claim.peerID, claim.correlation, richCompletionExpiry, now.UnixMilli())
			}
			queueWakeOutcomeDueRemovals(context.Background(), pipe, s.dueKey(), expired)
			if pending, ok := records[claim.correlation]; ok && pending.State == wakeOutcomeStatePending {
				pipe.ZAdd(context.Background(), s.dueKey(), redis.Z{
					Score: float64(pending.DueAtMs), Member: member,
				})
			}
			return nil
		})
		return err
	})
}

type wakeOutcomeSendFunc func(context.Context, string, wakeOutcomeRoutePolicy) pushDeliveryResult
type wakeOutcomeGroupSendFunc func(
	context.Context,
	string,
	wakeOutcomeRoutePolicy,
	string,
) pushDeliveryResult

type wakeOutcomeCoordinator struct {
	backend         *redisWakeOutcomeStore
	send            wakeOutcomeSendFunc
	sendGroup       wakeOutcomeGroupSendFunc
	sendAndroidRich func(context.Context, wakeOutcomeClaim) pushDeliveryResult
	now             func() time.Time
	startOnce       sync.Once
	runMu           sync.Mutex
}

func newWakeOutcomeCoordinator(
	backend *redisWakeOutcomeStore,
	send wakeOutcomeSendFunc,
	now func() time.Time,
) *wakeOutcomeCoordinator {
	if now == nil {
		now = time.Now
	}
	return &wakeOutcomeCoordinator{backend: backend, send: send, now: now}
}

func (c *wakeOutcomeCoordinator) Start(ctx context.Context) {
	if c == nil || c.backend == nil {
		return
	}
	c.startOnce.Do(func() {
		go func() {
			if err := c.RunDue(ctx); err != nil && ctx.Err() == nil {
				log.Printf("[WAKE_OUTCOME] outcome=coordinator_retryable")
			}
			ticker := time.NewTicker(wakeOutcomeCoordinatorTick)
			defer ticker.Stop()
			for {
				select {
				case <-ticker.C:
					if err := c.RunDue(ctx); err != nil && ctx.Err() == nil {
						log.Printf("[WAKE_OUTCOME] outcome=coordinator_retryable")
					}
				case <-ctx.Done():
					return
				}
			}
		}()
	})
}

func (c *wakeOutcomeCoordinator) RunDue(ctx context.Context) error {
	if c == nil || c.backend == nil {
		return errWakeOutcomeBackendUnavailable
	}
	c.runMu.Lock()
	defer c.runMu.Unlock()
	// Claim immediately before each provider call. Claiming a whole batch and
	// sending it sequentially lets later leases age (or even expire) behind one
	// blocked provider call before their submission has started.
	for handled := 0; handled < wakeOutcomeCoordinatorBatch; handled++ {
		claim, claimed, found, err := c.backend.claimNextDue(c.now())
		if err != nil {
			return err
		}
		if !found {
			return nil
		}
		if !claimed {
			continue
		}
		if err := c.runClaim(ctx, claim); err != nil &&
			!errors.Is(err, errWakeOutcomeClaimChanged) {
			return err
		}
	}
	return nil
}

// Both immediate Android dispatch and the existing due worker use this exact
// provider deadline and settlement boundary. There is no second retry queue.
func (c *wakeOutcomeCoordinator) runClaim(ctx context.Context, claim wakeOutcomeClaim) error {
	result := pushDeliveryRetryable
	providerCtx, cancel := context.WithTimeout(ctx, wakeOutcomeProviderTimeout)
	defer cancel()
	switch {
	case claim.androidRichDigest != "":
		if c.sendAndroidRich != nil {
			result = c.sendAndroidRich(providerCtx, claim)
		}
	case claim.groupMessageDispatchAdmissionKey != "":
		// Keep the existing iOS group provider-admission boundary intact.
		if c.sendGroup != nil {
			result = c.sendGroup(providerCtx, claim.peerID, claim.policy, claim.groupMessageDispatchAdmissionKey)
		}
	default:
		if c.send != nil {
			result = c.send(providerCtx, claim.peerID, claim.policy)
		}
	}
	return c.backend.settle(claim, result, c.now())
}
