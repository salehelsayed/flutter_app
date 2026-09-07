package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log"
	"slices"
	"strings"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/redis/go-redis/v9"
)

// Only the already-filtered ciphertext/routing data is retained. Provider
// tokens, notification previews, raw user envelopes, and route leases never
// enter this independent, expiring notification custody.
type androidRichPushMaterial struct {
	Version       int               `json:"version"`
	RecipientHash string            `json:"recipient_hash"`
	Correlation   string            `json:"correlation"`
	ExpiresAtMs   int64             `json:"expires_at_ms"`
	Data          map[string]string `json:"data"`
}

const maxAndroidRichMaterialBytes = 8192

var errAndroidRichRouteInspected = errors.New("Android rich route inspected without sending")

func androidRichRecipientHash(peerID string) string {
	hash := sha256.Sum256([]byte("android-rich-recipient-v1\x00" + peerID))
	return hex.EncodeToString(hash[:])
}

func androidRichMaterialDigest(raw []byte) string {
	hash := sha256.Sum256(raw)
	return hex.EncodeToString(hash[:])
}

func (material androidRichPushMaterial) validate(peerID, correlation string) error {
	if material.Version != 1 || material.RecipientHash != androidRichRecipientHash(peerID) ||
		material.Correlation != correlation || !isCanonicalWakeOutcomeCorrelation(correlation) ||
		material.ExpiresAtMs <= 0 || material.Data["message_id"] == "" {
		return errors.New("Android notification recovery identity is invalid")
	}
	for key := range material.Data {
		switch key {
		case "type", "sender_id", "message_id", "envelope_version", "kem", "ciphertext", "nonce",
			"groupId", "sender_transport_peer_id", "kind", "payloadType", "keyEpoch", "preview_unavailable":
		default:
			return errors.New("Android notification recovery contains unsupported material")
		}
	}
	switch material.Data["type"] {
	case "new_message":
		if material.Data["sender_id"] == "" || material.Data["groupId"] != "" {
			return errors.New("Android direct recovery route is invalid")
		}
	case "group_message":
		if material.Data["groupId"] == "" || material.Data["sender_transport_peer_id"] == "" {
			return errors.New("Android group recovery route is invalid")
		}
	default:
		return errors.New("Android notification recovery producer is invalid")
	}
	if material.Data["preview_unavailable"] != "1" &&
		(material.Data["ciphertext"] == "" || material.Data["nonce"] == "" ||
			(material.Data["type"] == "new_message" && material.Data["kem"] == "")) {
		return errors.New("Android notification recovery ciphertext is incomplete")
	}
	message := &messaging.Message{Data: material.Data, Android: &messaging.AndroidConfig{Priority: "high"}}
	if pushDataSize(material.Data) > maxPushDataBytes || !messageFitsProviderBudgets(message) {
		return errors.New("Android notification recovery exceeds provider budget")
	}
	return nil
}

// Reuse the private resolver boundary for platform inspection. The factory
// intentionally returns before any provider operation; no token leaves it.
func (ps *PushService) isAndroidRichRecoveryRoute(route pushRouteLease) bool {
	opaque, eligible := classifySelectedPushRoute(route, "")
	if !eligible || opaque || route.lookupKey == "" {
		return false
	}
	android := false
	err := ps.sendPushRouteThroughGateway(context.Background(), route,
		func(platform string) (*messaging.Message, error) {
			android = strings.EqualFold(strings.TrimSpace(platform), "android")
			return nil, errAndroidRichRouteInspected
		}, false)
	return errors.Is(err, errAndroidRichRouteInspected) && android
}

func (ps *PushService) newAndroidRichAdmission(
	peerID string, route pushRouteLease, draft *messaging.Message,
	storedAtMs, expiresAtMs int64,
) (wakeOutcomeAdmission, bool) {
	if draft == nil || draft.Token != "" || draft.Notification != nil ||
		storedAtMs <= 0 || expiresAtMs <= storedAtMs || !ps.isAndroidRichRecoveryRoute(route) {
		return wakeOutcomeAdmission{}, false
	}
	data := make(map[string]string, len(draft.Data))
	for key, value := range draft.Data {
		data[key] = value
	}
	// Include group and sender scope: old clients may reuse a logical message
	// identifier across conversations. Never let one conversation suppress another.
	identity, _ := json.Marshal([]string{"android-rich-v1", peerID, data["type"],
		data["groupId"], data["sender_id"], data["sender_transport_peer_id"], data["message_id"]})
	correlation := androidRichMaterialDigest(identity)
	expiresAtMs = min(expiresAtMs, storedAtMs+wakeOutcomeRetention.Milliseconds())
	material := androidRichPushMaterial{Version: 1, RecipientHash: androidRichRecipientHash(peerID),
		Correlation: correlation, ExpiresAtMs: expiresAtMs, Data: data}
	if err := material.validate(peerID, correlation); err != nil {
		return wakeOutcomeAdmission{}, false
	}
	raw, err := json.Marshal(material)
	if err != nil || len(raw) > maxAndroidRichMaterialBytes {
		return wakeOutcomeAdmission{}, false
	}
	producer := wakeOutcomeProducerDirectMessage
	if data["type"] == "group_message" {
		producer = wakeOutcomeProducerGroupMessage
	}
	return wakeOutcomeAdmission{recipientPeerID: peerID, correlation: correlation, producer: producer,
		policy: wakeOutcomePolicyNone, route: copyPushRouteLease(route), storedAtMs: storedAtMs,
		eventExpiresAtMs: expiresAtMs, androidRichMaterial: raw}, true
}

func (s *redisWakeOutcomeStore) androidRichMaterialKey(peerID, correlation string) string {
	return s.prefix + "android-rich-material:" + encodeRedisComponent(peerID) + ":" + correlation
}

// Terminal markers have the original custody horizon, independently of the
// bounded active-job hash. Their count follows accepted traffic within that
// horizon; successful traffic must never consume the 512 active obligation slots.
func (s *redisWakeOutcomeStore) androidRichCompletedKey(peerID, correlation string) string {
	return s.prefix + "android-rich-completed:" + encodeRedisComponent(peerID) + ":" + correlation
}

func (s *redisWakeOutcomeStore) androidRichCompleted(tx *redis.Tx, peerID, correlation string) (bool, error) {
	raw, err := optionalRedisBytes(tx, s.androidRichCompletedKey(peerID, correlation))
	if err != nil {
		return false, err
	}
	if raw == nil {
		return false, nil
	}
	if string(raw) != "1" {
		return false, errors.New("Android notification completion marker is invalid")
	}
	return true, nil
}

func (s *redisWakeOutcomeStore) queueAndroidRichCompleted(ctx context.Context, pipe redis.Pipeliner, peerID, correlation string, expiresAtMs, nowMs int64) {
	pipe.Del(ctx, s.androidRichMaterialKey(peerID, correlation))
	pipe.Set(ctx, s.androidRichCompletedKey(peerID, correlation), "1", androidRichMaterialTTL(expiresAtMs, nowMs))
}

// Legacy authority is fenced by the same digest used by ResolveRoute. Encrypted
// authority retains the existing exact directory/generation/capability fence.
func (s *redisWakeOutcomeStore) androidRichRouteMatchesAdmission(tx *redis.Tx, admission wakeOutcomeAdmission) (bool, error) {
	if admission.route.Generation != 0 {
		return s.encryptedRouteMatchesAdmission(tx, admission)
	}
	if admission.route.lookupKey != s.prefix+"push:"+encodeRedisComponent(admission.recipientPeerID) {
		return false, nil
	}
	markerRaw, err := optionalRedisBytes(tx, s.prefix+"push-token-state")
	if err != nil {
		return false, err
	}
	if markerRaw != nil {
		marker, err := decodePushTokenStateMarker(markerRaw)
		if err != nil || marker.State == pushTokenStateEncrypted {
			return false, err
		}
	}
	raw, err := optionalRedisBytes(tx, admission.route.lookupKey)
	if err != nil || raw == nil {
		return false, err
	}
	entry, err := decodeLegacyPushTokenRecord(raw)
	if err != nil {
		return false, err
	}
	return strings.EqualFold(strings.TrimSpace(entry.Platform), "android") &&
		pushRouteLegacyDigestBytes(raw) == admission.route.legacyDigest &&
		slices.Equal(entry.Capabilities, admission.route.Capabilities), nil
}

func (ps *PushService) sendAndroidRichMaterial(ctx context.Context, peerID string, material androidRichPushMaterial) pushDeliveryResult {
	if err := material.validate(peerID, material.Correlation); err != nil {
		return pushDeliveryRetryable
	}
	for attempt := 0; attempt < 2; attempt++ {
		route, err := ps.selectPushRoute(peerID, "")
		if err != nil || route == nil {
			return pushDeliveryRetryable
		}
		opaque, eligible := classifySelectedPushRoute(*route, "")
		if !eligible || opaque {
			// A privacy-mode change never causes retained rich ciphertext to be
			// submitted on an opaque route. Keep it retryable until its bounded expiry.
			return pushDeliveryRetryable
		}
		err = ps.sendPushRouteThroughGateway(ctx, *route, func(platform string) (*messaging.Message, error) {
			if !strings.EqualFold(strings.TrimSpace(platform), "android") {
				return nil, errPushDeliverySuppressed // iOS remains outside this recovery mode.
			}
			return &messaging.Message{Data: material.Data, Android: &messaging.AndroidConfig{Priority: "high"}}, nil
		}, true) // Preserve the incumbent single routing-only provider-size rescue.
		switch {
		case err == nil:
			return pushDeliveryAccepted
		case errors.Is(err, errPushDeliveryPermanent):
			return pushDeliveryPermanent
		case errors.Is(err, errPushDeliverySuppressed):
			return pushDeliverySuppressed
		case errors.Is(err, ErrPushRouteStale):
			continue
		default:
			return pushDeliveryRetryable
		}
	}
	return pushDeliveryRetryable
}

func (ps *PushService) sendAndroidRichRecovery(ctx context.Context, store *redisWakeOutcomeStore, claim wakeOutcomeClaim) pushDeliveryResult {
	raw, err := store.client.Get(ctx, store.androidRichMaterialKey(claim.peerID, claim.correlation)).Bytes()
	if err != nil || len(raw) > maxAndroidRichMaterialBytes || androidRichMaterialDigest(raw) != claim.androidRichDigest {
		return pushDeliveryRetryable
	}
	var material androidRichPushMaterial
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&material); err != nil || material.ExpiresAtMs <= store.nowTime().UnixMilli() ||
		material.validate(claim.peerID, claim.correlation) != nil || decoder.Decode(new(any)) != io.EOF {
		return pushDeliveryRetryable
	}
	return ps.sendAndroidRichMaterial(ctx, claim.peerID, material)
}

func (ps *PushService) launchAndroidRichAdmission(store *redisWakeOutcomeStore, admission wakeOutcomeAdmission) {
	if store == nil {
		return
	}
	go func() {
		claim, claimed, err := store.claimOne(wakeOutcomeDueMember(admission.recipientPeerID, admission.correlation), store.nowTime())
		if err != nil || !claimed {
			// The existing due index retains an unclaimed row for coordinator/restart recovery.
			return
		}
		coordinator := newWakeOutcomeCoordinator(store, nil, store.nowTime)
		coordinator.sendAndroidRich = func(ctx context.Context, claim wakeOutcomeClaim) pushDeliveryResult {
			return ps.sendAndroidRichRecovery(ctx, store, claim)
		}
		if err := coordinator.runClaim(context.Background(), claim); err != nil && !errors.Is(err, errWakeOutcomeClaimChanged) {
			log.Printf("[ANDROID_RICH_RECOVERY] outcome=settlement_retryable")
		}
	}()
}

func (ps *PushService) launchAndroidRichCapacityFallback(peerID string, raw []byte) {
	var material androidRichPushMaterial
	if json.Unmarshal(raw, &material) != nil || material.validate(peerID, material.Correlation) != nil {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), wakeOutcomeProviderTimeout)
		defer cancel()
		ps.sendAndroidRichMaterial(ctx, peerID, material)
	}()
}

func androidRichMaterialTTL(expiresAtMs, nowMs int64) time.Duration {
	return time.Duration(max(int64(1), expiresAtMs-nowMs)) * time.Millisecond
}
