package main

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"sort"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	redisCallWakeClaimSchema       = "mknoon.call_wake_claim.v1"
	redisCallWakeDirectorySchema   = "mknoon.call_wake_directory.v1"
	redisCallReplayDirectorySchema = "mknoon.call_replay_directory.v1"
	redisCallWakeClaimed           = "claimed"
	redisCallWakeDispatching       = "dispatching"
	redisCallWakeCompleted         = "completed"
)

type redisCallControlStore struct {
	client *redis.Client
	prefix string

	// Test-only commit seam. Production leaves this nil.
	beforeStoreCommit    func() error
	beforeRetrieveCommit func()
}

type redisCallMeta struct {
	SenderPeerID          string `json:"senderPeerId"`
	RecipientDevicePeerID string `json:"recipientDevicePeerId"`
	CallHandle            string `json:"callHandle"`
	ReceiptAtMs           int64  `json:"receiptAtMs"`
	ExpiresAtMs           int64  `json:"expiresAtMs"`
	EventCount            int    `json:"eventCount"`
	TotalBytes            int    `json:"totalBytes"`
	// AckedEvents counts events the recipient acknowledged on this call. Old
	// records decode as zero, which never marks a recipient attached.
	AckedEvents int `json:"ackedEvents,omitempty"`
}

type redisCallTombstone struct {
	State        string `json:"state"`
	SenderDigest string `json:"senderDigest"`
	ExpiresAtMs  int64  `json:"expiresAtMs"`
	TerminalAtMs int64  `json:"terminalAtMs,omitempty"`
}

type redisCallWakeRecord struct {
	Schema       string `json:"schema"`
	Version      int    `json:"version"`
	HandleDigest string `json:"handleDigest"`
	ExpiresAtMs  int64  `json:"expiresAtMs"`
}

type redisCallWakeClaim struct {
	Schema       string   `json:"schema"`
	Version      int      `json:"version"`
	State        string   `json:"state"`
	Owner        string   `json:"owner,omitempty"`
	LeaseUntilMs int64    `json:"leaseUntilMs,omitempty"`
	Attempts     int      `json:"attempts,omitempty"`
	ActiveOwners []string `json:"activeOwners,omitempty"`
}

type redisCallWakeDirectoryRecord struct {
	Schema       string `json:"schema"`
	Version      int    `json:"version"`
	SenderDigest string `json:"senderDigest"`
}

type redisCallReplayDirectoryRecord struct {
	Schema       string `json:"schema"`
	Version      int    `json:"version"`
	HandleDigest string `json:"handleDigest"`
}

type redisCallEndpointRoute struct {
	AccountPeerID   string `json:"accountPeerId"`
	DevicePeerID    string `json:"devicePeerId"`
	Platform        string `json:"platform"`
	ExpiresAtMs     int64  `json:"expiresAtMs"`
	PreferenceEpoch uint64 `json:"preferenceEpoch"`
}

func newRedisCallControlStore(client *redis.Client, prefix string) *redisCallControlStore {
	return &redisCallControlStore{client: client, prefix: prefix}
}

func (s *redisCallControlStore) Store(
	ctx context.Context,
	sender string,
	request CallStoreRequest,
	now time.Time,
) (CallStoreReceipt, error) {
	if s == nil || s.client == nil {
		return CallStoreReceipt{}, ErrCallBackendUnavailable
	}
	keys := s.callKeys(request.RecipientDevicePeerID, request.CallHandle)
	wakeKey := s.wakeKey(request.RecipientDevicePeerID, sender)
	rateKey := s.rateKey(sender)
	replayMember := redisCallReplayDirectoryMember(request.CallHandle)
	digest := callEventDigest(sender, request)
	nowMs := now.UnixMilli()
	var receipt CallStoreReceipt
	err := s.watch(ctx, []string{
		keys.handles, keys.meta, keys.events, keys.ids, keys.claims, keys.tombstone, keys.replays,
		wakeKey, rateKey,
	}, func(tx *redis.Tx) error {
		wake, err := readRedisCallJSON[redisCallWakeRecord](ctx, tx, wakeKey)
		if err != nil {
			return err
		}
		if wake == nil || wake.Schema != CallWakeSchema || wake.Version != CallControlVersion ||
			wake.ExpiresAtMs <= nowMs ||
			wake.HandleDigest != callOpaqueDigest("mknoon.call-wake.v1", request.WakeHandle) {
			return ErrCallUnauthorized
		}

		tombstone, err := readRedisCallJSON[redisCallTombstone](ctx, tx, keys.tombstone)
		if err != nil {
			return err
		}
		meta, err := readRedisCallJSON[redisCallMeta](ctx, tx, keys.meta)
		if err != nil {
			return err
		}
		if tombstone != nil && (tombstone.State != "pending" || tombstone.ExpiresAtMs <= nowMs) {
			return ErrCallReplay
		}
		if tombstone != nil && meta == nil {
			return ErrCallReplay
		}
		reservations, err := tx.ZRangeByScore(ctx, keys.replays, &redis.ZRangeBy{
			Min: strconv.FormatInt(nowMs+1, 10), Max: "+inf",
		}).Result()
		if err != nil && !errors.Is(err, redis.Nil) {
			return err
		}
		reservationExists := false
		for _, member := range reservations {
			reservationExists = reservationExists || member == replayMember
		}

		liveHandles, err := tx.ZRangeByScore(ctx, keys.handles, &redis.ZRangeBy{
			Min: strconv.FormatInt(nowMs+1, 10), Max: "+inf",
		}).Result()
		if err != nil && !errors.Is(err, redis.Nil) {
			return err
		}
		newHandle := meta == nil
		if newHandle && reservationExists {
			return ErrCallReplay
		}
		if newHandle && len(reservations) >= callMaxTerminalTombstonesPerRecipient {
			return ErrCallRecipientCapacity
		}
		if newHandle && len(liveHandles) >= CallMaxPendingHandles {
			return ErrCallRecipientCapacity
		}

		if meta != nil {
			if meta.SenderPeerID != sender || meta.RecipientDevicePeerID != request.RecipientDevicePeerID ||
				meta.CallHandle != request.CallHandle {
				return ErrCallUnauthorized
			}
			storedDigest, err := tx.HGet(ctx, keys.ids, request.MessageID).Result()
			switch {
			case err == nil:
				if storedDigest != digest {
					return ErrCallIdentityConflict
				}
				metaRaw, marshalErr := marshalCallRecord(*meta)
				if marshalErr != nil {
					return marshalErr
				}
				_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
					pipe.HSet(ctx, keys.meta, "record", metaRaw)
					pipe.PExpireAt(ctx, keys.meta, time.UnixMilli(meta.ExpiresAtMs))
					return nil
				})
				if err != nil {
					return err
				}
				receipt = callReceipt(CallStoreStatusDuplicate, *meta, len(liveHandles))
				receipt.ExpiresAtMs = request.ExpiresAtMs
				return nil
			case !errors.Is(err, redis.Nil):
				return err
			}
			if meta.EventCount >= CallMaxEventsPerCall {
				return ErrCallEventCapacity
			}
			if meta.TotalBytes+len(request.Envelope) > CallMaxBytesPerCall {
				return ErrCallByteCapacity
			}
		}

		rate, err := tx.Get(ctx, rateKey).Int()
		if err != nil && !errors.Is(err, redis.Nil) {
			return err
		}
		if rate >= callStoreRateLimit {
			return ErrCallRateLimited
		}

		event := CallMailboxEvent{
			CallHandle: request.CallHandle, MessageID: request.MessageID,
			SenderPeerID: sender, RecipientDevicePeerID: request.RecipientDevicePeerID,
			Envelope: append([]byte(nil), request.Envelope...), ReceiptAtMs: nowMs,
			ExpiresAtMs: request.ExpiresAtMs,
		}
		eventRaw, err := marshalCallRecord(event)
		if err != nil {
			return err
		}
		if meta == nil {
			meta = &redisCallMeta{
				SenderPeerID: sender, RecipientDevicePeerID: request.RecipientDevicePeerID,
				CallHandle: request.CallHandle, ReceiptAtMs: nowMs,
				ExpiresAtMs: request.ExpiresAtMs,
			}
		}
		// One call sends several control events (invite, ringing, accept,
		// terminate) through the same handle, each with its own expiry. The
		// handle lives until the latest pending event expires.
		if request.ExpiresAtMs > meta.ExpiresAtMs {
			meta.ExpiresAtMs = request.ExpiresAtMs
		}
		meta.EventCount++
		meta.TotalBytes += len(request.Envelope)
		metaRaw, err := marshalCallRecord(*meta)
		if err != nil {
			return err
		}
		tombstone = &redisCallTombstone{
			State: "pending", SenderDigest: callOpaqueDigest("mknoon.call-sender.v1", sender),
			ExpiresAtMs: meta.ExpiresAtMs,
		}
		tombRaw, err := marshalCallRecord(*tombstone)
		if err != nil {
			return err
		}
		if s.beforeStoreCommit != nil {
			if err := s.beforeStoreCommit(); err != nil {
				return err
			}
		}
		payloadExpiry := time.UnixMilli(meta.ExpiresAtMs)
		tombExpiry := payloadExpiry.Add(CallReplayTombstoneTTL)
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.ZRemRangeByScore(ctx, keys.handles, "-inf", strconv.FormatInt(nowMs, 10))
			pipe.ZAdd(ctx, keys.handles, redis.Z{Score: float64(meta.ExpiresAtMs), Member: request.CallHandle})
			pipe.PExpireAt(ctx, keys.handles, tombExpiry)
			pipe.HSet(ctx, keys.meta, "record", metaRaw)
			pipe.RPush(ctx, keys.events, eventRaw)
			pipe.HSet(ctx, keys.ids, request.MessageID, digest)
			pipe.HSet(ctx, keys.tombstone, "record", tombRaw)
			pipe.ZRemRangeByScore(ctx, keys.replays, "-inf", strconv.FormatInt(nowMs, 10))
			pipe.ZAdd(ctx, keys.replays, redis.Z{Score: float64(tombExpiry.UnixMilli()), Member: replayMember})
			pipe.Expire(ctx, keys.replays, CallReplayTombstoneTTL+CallMaxPreconnectTTL)
			for _, key := range []string{keys.meta, keys.events, keys.ids, keys.claims} {
				pipe.PExpireAt(ctx, key, payloadExpiry)
			}
			pipe.PExpireAt(ctx, keys.tombstone, tombExpiry)
			if rate == 0 {
				pipe.Set(ctx, rateKey, 1, callStoreRateWindow)
			} else {
				pipe.Incr(ctx, rateKey)
			}
			return nil
		})
		if err != nil {
			return err
		}
		pending := len(liveHandles)
		if !slices.Contains(liveHandles, request.CallHandle) {
			pending++
		}
		receipt = callReceipt(CallStoreStatusStored, *meta, pending)
		receipt.ExpiresAtMs = request.ExpiresAtMs
		return nil
	})
	if err != nil {
		return CallStoreReceipt{}, callRedisError(err)
	}
	return receipt, nil
}

func (s *redisCallControlStore) Retrieve(
	ctx context.Context,
	recipient, callHandle string,
	limit int,
	now time.Time,
) (CallRetrieveResult, error) {
	if s == nil || s.client == nil {
		return CallRetrieveResult{}, ErrCallBackendUnavailable
	}
	result := CallRetrieveResult{Schema: CallMailboxSchema, Version: CallControlVersion, ReceiptAtMs: now.UnixMilli()}
	handles := []string{callHandle}
	if callHandle == "" {
		var err error
		handles, err = s.client.ZRangeByScore(ctx, s.handlesKey(recipient), &redis.ZRangeBy{
			Min: strconv.FormatInt(now.UnixMilli()+1, 10), Max: "+inf", Offset: 0, Count: CallMaxPendingHandles,
		}).Result()
		if err != nil {
			return CallRetrieveResult{}, callRedisError(err)
		}
	}
	remaining := limit
	for _, handle := range handles {
		if remaining == 0 {
			result.HasMore = true
			break
		}
		events, expiresAt, hasMore, err := s.retrieveOne(ctx, recipient, handle, remaining, now)
		if err != nil {
			return CallRetrieveResult{}, err
		}
		result.Events = append(result.Events, events...)
		if expiresAt > result.ExpiresAtMs {
			result.ExpiresAtMs = expiresAt
		}
		remaining -= len(events)
		result.HasMore = result.HasMore || hasMore
	}
	return result, nil
}

func (s *redisCallControlStore) retrieveOne(
	ctx context.Context,
	recipient, handle string,
	limit int,
	now time.Time,
) ([]CallMailboxEvent, int64, bool, error) {
	keys := s.callKeys(recipient, handle)
	var (
		events    []CallMailboxEvent
		expiresAt int64
		hasMore   bool
	)
	err := s.watch(ctx, []string{
		keys.handles, keys.meta, keys.events, keys.ids, keys.claims, keys.tombstone, keys.replays,
	}, func(tx *redis.Tx) error {
		meta, err := readRedisCallJSON[redisCallMeta](ctx, tx, keys.meta)
		if err != nil {
			return err
		}
		if meta == nil || meta.RecipientDevicePeerID != recipient {
			return nil
		}
		if meta.ExpiresAtMs <= now.UnixMilli() {
			return s.terminalizeTx(ctx, tx, keys, meta, "expired", now)
		}
		rows, err := tx.LRange(ctx, keys.events, 0, int64(limit)).Result()
		if err != nil && !errors.Is(err, redis.Nil) {
			return err
		}
		if len(rows) > limit {
			hasMore = true
			rows = rows[:limit]
		}
		decoded := make([]CallMailboxEvent, 0, len(rows))
		for _, row := range rows {
			var event CallMailboxEvent
			if err := json.Unmarshal([]byte(row), &event); err != nil ||
				event.SenderPeerID != meta.SenderPeerID || event.RecipientDevicePeerID != recipient ||
				event.CallHandle != handle || event.ExpiresAtMs > meta.ExpiresAtMs {
				return ErrCallBackendUnavailable
			}
			if event.ExpiresAtMs <= now.UnixMilli() {
				// An earlier event of a still-live call expired on its own clock.
				continue
			}
			decoded = append(decoded, event)
		}
		if s.beforeRetrieveCommit != nil {
			s.beforeRetrieveCommit()
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.HSet(ctx, keys.meta, "lastRetrieveAtMs", now.UnixMilli())
			return nil
		})
		if err != nil {
			return err
		}
		events = decoded
		expiresAt = meta.ExpiresAtMs
		return nil
	})
	if err != nil {
		return nil, 0, false, callRedisError(err)
	}
	return events, expiresAt, hasMore, nil
}

func (s *redisCallControlStore) Ack(
	ctx context.Context,
	recipient, handle string,
	messageIDs map[string]struct{},
	now time.Time,
) (int, error) {
	keys := s.callKeys(recipient, handle)
	acked := 0
	err := s.watch(ctx, []string{
		keys.handles, keys.meta, keys.events, keys.ids, keys.claims, keys.tombstone, keys.replays,
	}, func(tx *redis.Tx) error {
		attemptAcked := 0
		meta, err := readRedisCallJSON[redisCallMeta](ctx, tx, keys.meta)
		if err != nil {
			return err
		}
		if meta == nil {
			return nil
		}
		if meta.RecipientDevicePeerID != recipient {
			return ErrCallUnauthorized
		}
		if meta.ExpiresAtMs <= now.UnixMilli() {
			return s.terminalizeTx(ctx, tx, keys, meta, "expired", now)
		}
		rows, err := tx.LRange(ctx, keys.events, 0, -1).Result()
		if err != nil && !errors.Is(err, redis.Nil) {
			return err
		}
		kept := make([]any, 0, len(rows))
		keptCount := 0
		keptBytes := 0
		ackedIDs := make([]string, 0, len(messageIDs))
		for _, row := range rows {
			var event CallMailboxEvent
			if json.Unmarshal([]byte(row), &event) != nil {
				return ErrCallBackendUnavailable
			}
			if _, remove := messageIDs[event.MessageID]; remove {
				claimRaw, claimErr := tx.HGet(ctx, keys.claims, event.MessageID).Result()
				switch {
				case claimErr == nil:
					claim, decodeErr := decodeRedisCallWakeClaim(claimRaw)
					if decodeErr != nil {
						return decodeErr
					}
					if redisCallWakeClaimBlocksTerminal(claim, now.UnixMilli()) {
						return ErrCallBackendUnavailable
					}
				case errors.Is(claimErr, redis.Nil):
				case claimErr != nil:
					return claimErr
				}
				attemptAcked++
				ackedIDs = append(ackedIDs, event.MessageID)
				continue
			}
			kept = append(kept, row)
			keptCount++
			keptBytes += len(event.Envelope)
		}
		if attemptAcked == 0 {
			_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
				pipe.HSet(ctx, keys.meta, "lastAckAtMs", now.UnixMilli())
				return nil
			})
			if err == nil {
				acked = 0
			}
			return err
		}
		// A fully drained mailbox stays open until the call expires: the same
		// call still routes ringing, accept and terminate through it, and a
		// terminal tombstone here would reject those as replays. Only the
		// pending-handle index drops the handle, so drains and capacity checks
		// see no undelivered events.
		meta.EventCount = keptCount
		meta.TotalBytes = keptBytes
		meta.AckedEvents += attemptAcked
		metaRaw, err := marshalCallRecord(*meta)
		if err != nil {
			return err
		}
		completedClaimRaw, err := marshalCallRecord(newRedisCallWakeClaim(redisCallWakeCompleted))
		if err != nil {
			return err
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.Del(ctx, keys.events)
			if len(kept) > 0 {
				pipe.RPush(ctx, keys.events, kept...)
			} else {
				pipe.ZRem(ctx, keys.handles, meta.CallHandle)
			}
			pipe.HSet(ctx, keys.meta, "record", metaRaw)
			for _, id := range ackedIDs {
				pipe.HSet(ctx, keys.claims, id, completedClaimRaw)
			}
			pipe.PExpireAt(ctx, keys.events, time.UnixMilli(meta.ExpiresAtMs))
			pipe.PExpireAt(ctx, keys.claims, time.UnixMilli(meta.ExpiresAtMs))
			return nil
		})
		if err == nil {
			acked = attemptAcked
		}
		return err
	})
	if err != nil {
		return 0, callRedisError(err)
	}
	return acked, nil
}

func (s *redisCallControlStore) Cancel(
	ctx context.Context,
	sender string,
	request CallCancelRequest,
	now time.Time,
) error {
	keys := s.callKeys(request.RecipientDevicePeerID, request.CallHandle)
	return callRedisError(s.watch(ctx, []string{
		keys.handles, keys.meta, keys.events, keys.ids, keys.claims, keys.tombstone, keys.replays,
	}, func(tx *redis.Tx) error {
		meta, err := readRedisCallJSON[redisCallMeta](ctx, tx, keys.meta)
		if err != nil {
			return err
		}
		if meta == nil {
			tomb, err := readRedisCallJSON[redisCallTombstone](ctx, tx, keys.tombstone)
			if err != nil {
				return err
			}
			if tomb != nil && tomb.SenderDigest == callOpaqueDigest("mknoon.call-sender.v1", sender) {
				return nil
			}
			return ErrCallUnauthorized
		}
		if meta.SenderPeerID != sender || meta.RecipientDevicePeerID != request.RecipientDevicePeerID {
			return ErrCallUnauthorized
		}
		return s.terminalizeTx(ctx, tx, keys, meta, "canceled", now)
	}))
}

func (s *redisCallControlStore) ClaimWake(
	ctx context.Context,
	sender string,
	request CallStoreRequest,
	now time.Time,
) (*CallWakeRoute, bool, error) {
	if s == nil || s.client == nil {
		return nil, false, ErrCallBackendUnavailable
	}
	keys := s.callKeys(request.RecipientDevicePeerID, request.CallHandle)
	wakeKey := s.wakeKey(request.RecipientDevicePeerID, sender)
	standardKey := s.tokenKey(request.RecipientDevicePeerID, CallTokenKindStandard)
	voipKey := s.tokenKey(request.RecipientDevicePeerID, CallTokenKindIOSVoIP)
	routeKey := s.endpointDeviceKey(request.RecipientDevicePeerID)
	endpointRoute, err := readRedisCallJSON[redisCallEndpointRoute](ctx, s.client, routeKey)
	if err != nil || endpointRoute == nil || endpointRoute.ExpiresAtMs <= now.UnixMilli() {
		return nil, false, callRedisError(err)
	}
	endpointKey := s.endpointKey(endpointRoute.AccountPeerID)
	var selected *CallWakeRoute
	claimed := false
	err = s.watch(ctx, []string{
		keys.meta, keys.ids, keys.events, keys.claims, keys.tombstone, wakeKey, standardKey, voipKey,
		routeKey, endpointKey,
	}, func(tx *redis.Tx) error {
		meta, err := readRedisCallJSON[redisCallMeta](ctx, tx, keys.meta)
		if err != nil || meta == nil {
			return err
		}
		if meta.SenderPeerID != sender || meta.ExpiresAtMs <= now.UnixMilli() {
			return nil
		}
		if exists, err := tx.HExists(ctx, keys.ids, request.MessageID).Result(); err != nil || !exists {
			return err
		}
		claimState := ""
		claimRaw, err := tx.HGet(ctx, keys.claims, request.MessageID).Result()
		switch {
		case err == nil:
			claim, decodeErr := decodeRedisCallWakeClaim(claimRaw)
			if decodeErr != nil {
				return decodeErr
			}
			claimState = claim.State
			if claimState == redisCallWakeCompleted {
				return nil
			}
			if claimState == redisCallWakeDispatching {
				if claim.Owner != "" && claim.LeaseUntilMs > now.UnixMilli() {
					return ErrCallBackendUnavailable
				}
				if claim.Attempts >= callMaxWakeDispatchAttempts {
					if len(claim.ActiveOwners) != 0 {
						return nil
					}
					completedRaw, marshalErr := marshalCallRecord(newRedisCallWakeClaim(redisCallWakeCompleted))
					if marshalErr != nil {
						return marshalErr
					}
					_, commitErr := tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
						pipe.HSet(ctx, keys.claims, request.MessageID, completedRaw)
						pipe.PExpireAt(ctx, keys.claims, time.UnixMilli(meta.ExpiresAtMs))
						return nil
					})
					return commitErr
				}
			}
			if claimState != redisCallWakeClaimed {
				if claimState != redisCallWakeDispatching {
					return ErrCallBackendUnavailable
				}
			}
		case errors.Is(err, redis.Nil):
		case err != nil:
			return err
		}
		wake, err := readRedisCallJSON[redisCallWakeRecord](ctx, tx, wakeKey)
		if err != nil || wake == nil || wake.Schema != CallWakeSchema || wake.Version != CallControlVersion ||
			wake.ExpiresAtMs <= now.UnixMilli() ||
			wake.HandleDigest != callOpaqueDigest("mknoon.call-wake.v1", request.WakeHandle) {
			return err
		}
		currentRoute, err := readRedisCallJSON[redisCallEndpointRoute](ctx, tx, routeKey)
		if err != nil || currentRoute == nil || currentRoute.ExpiresAtMs <= now.UnixMilli() ||
			currentRoute.AccountPeerID != endpointRoute.AccountPeerID ||
			currentRoute.DevicePeerID != request.RecipientDevicePeerID {
			return err
		}
		endpoint, err := readRedisCallJSON[CallEndpointRecord](ctx, tx, endpointKey)
		if err != nil || endpoint == nil || endpoint.ExpiresAtMs <= now.UnixMilli() ||
			endpoint.Schema != CallEndpointSchema || endpoint.Version != CallControlVersion ||
			endpoint.DevicePeerID != request.RecipientDevicePeerID ||
			endpoint.Platform != currentRoute.Platform ||
			endpoint.PreferenceEpoch != currentRoute.PreferenceEpoch {
			return err
		}
		var token *CallTokenRecord
		voip, err := readRedisCallJSON[CallTokenRecord](ctx, tx, voipKey)
		if err != nil {
			return err
		}
		standard, err := readRedisCallJSON[CallTokenRecord](ctx, tx, standardKey)
		if err != nil {
			return err
		}
		switch currentRoute.Platform {
		case "ios":
			if voip != nil {
				if voip.Kind != CallTokenKindIOSVoIP || !validStoredCallTokenShape(*voip) {
					return ErrCallBackendUnavailable
				}
				if voip.ExpiresAtMs > now.UnixMilli() {
					if !validStoredCallToken(*voip, now) {
						return ErrCallBackendUnavailable
					}
					token = voip
				}
			}
			if token != nil {
				// A recipient that already drained every earlier event of this
				// call runs live on it and drains the mailbox itself. A VoIP
				// wake for a later control event would force CallKit to present
				// a brand-new incoming call, so the event stays in the mailbox
				// without a wake. Android data wakes present nothing by
				// themselves and keep firing for every event.
				attached, err := s.recipientAttachedTx(ctx, tx, keys, *meta, request.MessageID)
				if err != nil {
					return err
				}
				if attached {
					if claimState == "" || claimState == redisCallWakeClaimed {
						completedRaw, marshalErr := marshalCallRecord(newRedisCallWakeClaim(redisCallWakeCompleted))
						if marshalErr != nil {
							return marshalErr
						}
						_, commitErr := tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
							pipe.HSet(ctx, keys.claims, request.MessageID, completedRaw)
							pipe.PExpireAt(ctx, keys.claims, time.UnixMilli(meta.ExpiresAtMs))
							return nil
						})
						return commitErr
					}
					return nil
				}
			}
		case "android":
			if standard != nil {
				if standard.Kind != CallTokenKindStandard || !validStoredCallTokenShape(*standard) {
					return ErrCallBackendUnavailable
				}
				if standard.ExpiresAtMs > now.UnixMilli() {
					if !validStoredCallToken(*standard, now) {
						return ErrCallBackendUnavailable
					}
					token = standard
				}
			}
		}
		if token == nil {
			return nil
		}
		if claimState == "" {
			claimRaw, err := marshalCallRecord(newRedisCallWakeClaim(redisCallWakeClaimed))
			if err != nil {
				return err
			}
			_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
				pipe.HSet(ctx, keys.claims, request.MessageID, claimRaw)
				pipe.PExpireAt(ctx, keys.claims, time.UnixMilli(meta.ExpiresAtMs))
				return nil
			})
			if err != nil {
				return err
			}
		}
		route := callWakeRouteFromToken(*token)
		selected = &route
		claimed = true
		return nil
	})
	if err != nil {
		return nil, false, callRedisError(err)
	}
	return selected, claimed, nil
}

// recipientAttachedTx reports whether the recipient has acknowledged at least
// one event of this call and every event stored before messageID (the list
// then holds at most that message). Such a recipient is live on the call and
// needs no wake. A call's first event never counts: nothing was acknowledged.
func (s *redisCallControlStore) recipientAttachedTx(
	ctx context.Context,
	tx *redis.Tx,
	keys redisCallKeySet,
	meta redisCallMeta,
	messageID string,
) (bool, error) {
	if meta.AckedEvents <= 0 {
		return false, nil
	}
	rows, err := tx.LRange(ctx, keys.events, 0, -1).Result()
	if err != nil && !errors.Is(err, redis.Nil) {
		return false, err
	}
	for _, row := range rows {
		var event CallMailboxEvent
		if err := json.Unmarshal([]byte(row), &event); err != nil {
			return false, ErrCallBackendUnavailable
		}
		if event.MessageID != messageID {
			return false, nil
		}
	}
	return true, nil
}

func (s *redisCallControlStore) WakeCurrent(
	ctx context.Context,
	sender string,
	request CallStoreRequest,
	route CallWakeRoute,
	owner string,
	now time.Time,
) (bool, error) {
	if s == nil || s.client == nil || owner == "" {
		return false, ErrCallBackendUnavailable
	}
	keys := s.callKeys(request.RecipientDevicePeerID, request.CallHandle)
	wakeKey := s.wakeKey(request.RecipientDevicePeerID, sender)
	routeKey := s.endpointDeviceKey(request.RecipientDevicePeerID)
	endpointRoute, err := readRedisCallJSON[redisCallEndpointRoute](ctx, s.client, routeKey)
	if err != nil || endpointRoute == nil || endpointRoute.ExpiresAtMs <= now.UnixMilli() {
		return false, callRedisError(err)
	}
	endpointKey := s.endpointKey(endpointRoute.AccountPeerID)
	tokenKey := s.tokenKey(request.RecipientDevicePeerID, route.Kind)
	current := false
	err = s.watch(ctx, []string{
		keys.meta, keys.ids, keys.claims, keys.tombstone, wakeKey, routeKey, endpointKey, tokenKey,
	}, func(tx *redis.Tx) error {
		meta, err := readRedisCallJSON[redisCallMeta](ctx, tx, keys.meta)
		if err != nil || meta == nil {
			return err
		}
		if meta.SenderPeerID != sender || meta.RecipientDevicePeerID != request.RecipientDevicePeerID ||
			meta.CallHandle != request.CallHandle || meta.ExpiresAtMs <= now.UnixMilli() {
			return nil
		}
		if exists, err := tx.HExists(ctx, keys.ids, request.MessageID).Result(); err != nil || !exists {
			return err
		}
		claimRaw, err := tx.HGet(ctx, keys.claims, request.MessageID).Result()
		if errors.Is(err, redis.Nil) {
			return nil
		}
		if err != nil {
			return err
		}
		claim, err := decodeRedisCallWakeClaim(claimRaw)
		if err != nil {
			return err
		}
		attempts := 1
		switch claim.State {
		case redisCallWakeClaimed:
		case redisCallWakeDispatching:
			if claim.Owner == owner && claim.LeaseUntilMs > now.UnixMilli() {
				current = true
				return nil
			}
			if claim.LeaseUntilMs > now.UnixMilli() || claim.Attempts >= callMaxWakeDispatchAttempts {
				return nil
			}
			attempts = claim.Attempts + 1
		default:
			return nil
		}
		wake, err := readRedisCallJSON[redisCallWakeRecord](ctx, tx, wakeKey)
		if err != nil || wake == nil || wake.Schema != CallWakeSchema || wake.Version != CallControlVersion ||
			wake.ExpiresAtMs <= now.UnixMilli() ||
			wake.HandleDigest != callOpaqueDigest("mknoon.call-wake.v1", request.WakeHandle) {
			return err
		}
		currentRoute, err := readRedisCallJSON[redisCallEndpointRoute](ctx, tx, routeKey)
		if err != nil || currentRoute == nil || currentRoute.ExpiresAtMs <= now.UnixMilli() ||
			currentRoute.AccountPeerID != endpointRoute.AccountPeerID ||
			currentRoute.DevicePeerID != request.RecipientDevicePeerID ||
			currentRoute.Platform != route.Platform {
			return err
		}
		endpoint, err := readRedisCallJSON[CallEndpointRecord](ctx, tx, endpointKey)
		if err != nil || endpoint == nil || endpoint.ExpiresAtMs <= now.UnixMilli() ||
			endpoint.Schema != CallEndpointSchema || endpoint.Version != CallControlVersion ||
			endpoint.DevicePeerID != request.RecipientDevicePeerID ||
			endpoint.Platform != currentRoute.Platform ||
			endpoint.PreferenceEpoch != currentRoute.PreferenceEpoch {
			return err
		}
		token, err := readRedisCallJSON[CallTokenRecord](ctx, tx, tokenKey)
		if err != nil || token == nil {
			return err
		}
		if token.Kind != route.Kind || !validStoredCallTokenShape(*token) {
			return ErrCallBackendUnavailable
		}
		if token.ExpiresAtMs <= now.UnixMilli() || !callWakeRouteMatchesToken(route, *token) {
			return nil
		}
		if !validStoredCallToken(*token, now) {
			return ErrCallBackendUnavailable
		}
		leaseUntilMs := now.Add(callWakeDispatchLease).UnixMilli()
		if leaseUntilMs > meta.ExpiresAtMs {
			leaseUntilMs = meta.ExpiresAtMs
		}
		dispatchingRaw, err := marshalCallRecord(newRedisCallDispatchingClaim(
			owner, leaseUntilMs, attempts, claim.ActiveOwners,
		))
		if err != nil {
			return err
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.HSet(ctx, keys.claims, request.MessageID, dispatchingRaw)
			pipe.PExpireAt(ctx, keys.claims, time.UnixMilli(meta.ExpiresAtMs))
			return nil
		})
		if err == nil {
			current = true
		}
		return err
	})
	if err != nil {
		return false, callRedisError(err)
	}
	return current, nil
}

func (s *redisCallControlStore) WakeDispatchOwned(
	ctx context.Context,
	sender string,
	request CallStoreRequest,
	owner string,
	now time.Time,
) (bool, error) {
	if owner == "" {
		return false, ErrCallBackendUnavailable
	}
	keys := s.callKeys(request.RecipientDevicePeerID, request.CallHandle)
	owned := false
	err := s.watch(ctx, []string{keys.meta, keys.ids, keys.claims, keys.tombstone}, func(tx *redis.Tx) error {
		meta, err := readRedisCallJSON[redisCallMeta](ctx, tx, keys.meta)
		if err != nil || meta == nil {
			return err
		}
		if meta.SenderPeerID != sender || meta.RecipientDevicePeerID != request.RecipientDevicePeerID ||
			meta.CallHandle != request.CallHandle || meta.ExpiresAtMs <= now.UnixMilli() {
			return nil
		}
		if exists, err := tx.HExists(ctx, keys.ids, request.MessageID).Result(); err != nil || !exists {
			return err
		}
		claimRaw, err := tx.HGet(ctx, keys.claims, request.MessageID).Result()
		if errors.Is(err, redis.Nil) {
			return nil
		}
		if err != nil {
			return err
		}
		claim, err := decodeRedisCallWakeClaim(claimRaw)
		if err != nil {
			return err
		}
		if claim.State != redisCallWakeDispatching || claim.Owner != owner ||
			claim.LeaseUntilMs <= now.UnixMilli() {
			return nil
		}
		leaseUntilMs := now.Add(callWakeDispatchLease).UnixMilli()
		if leaseUntilMs > meta.ExpiresAtMs {
			leaseUntilMs = meta.ExpiresAtMs
		}
		updatedClaimRaw, err := marshalCallRecord(newRedisCallDispatchingClaim(
			owner, leaseUntilMs, claim.Attempts, claim.ActiveOwners,
		))
		if err != nil {
			return err
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.HSet(ctx, keys.claims, request.MessageID, updatedClaimRaw)
			pipe.PExpireAt(ctx, keys.claims, time.UnixMilli(meta.ExpiresAtMs))
			return nil
		})
		if err == nil {
			owned = true
		}
		return err
	})
	if err != nil {
		return false, callRedisError(err)
	}
	return owned, nil
}

// AuthorizeWakeDispatch durably records the owner as able to enter the
// provider. Terminalization must retain that barrier even if the dispatch
// lease expires and another bounded recovery attempt takes ownership.
func (s *redisCallControlStore) AuthorizeWakeDispatch(
	ctx context.Context,
	sender string,
	request CallStoreRequest,
	owner string,
	now time.Time,
) (bool, error) {
	if owner == "" {
		return false, ErrCallBackendUnavailable
	}
	keys := s.callKeys(request.RecipientDevicePeerID, request.CallHandle)
	authorized := false
	err := s.watch(ctx, []string{keys.meta, keys.ids, keys.claims, keys.tombstone}, func(tx *redis.Tx) error {
		meta, err := readRedisCallJSON[redisCallMeta](ctx, tx, keys.meta)
		if err != nil || meta == nil {
			return err
		}
		if meta.SenderPeerID != sender || meta.RecipientDevicePeerID != request.RecipientDevicePeerID ||
			meta.CallHandle != request.CallHandle || meta.ExpiresAtMs <= now.UnixMilli() {
			return nil
		}
		if exists, err := tx.HExists(ctx, keys.ids, request.MessageID).Result(); err != nil || !exists {
			return err
		}
		claimRaw, err := tx.HGet(ctx, keys.claims, request.MessageID).Result()
		if errors.Is(err, redis.Nil) {
			return nil
		}
		if err != nil {
			return err
		}
		claim, err := decodeRedisCallWakeClaim(claimRaw)
		if err != nil {
			return err
		}
		if claim.State != redisCallWakeDispatching || claim.Owner != owner ||
			claim.LeaseUntilMs <= now.UnixMilli() {
			return nil
		}
		activeOwners := append([]string(nil), claim.ActiveOwners...)
		if !wakeOwnerPresent(activeOwners, owner) {
			if len(activeOwners) >= callMaxWakeDispatchAttempts || len(activeOwners) >= claim.Attempts {
				return ErrCallBackendUnavailable
			}
			activeOwners = append(activeOwners, owner)
		}
		leaseUntilMs := now.Add(callWakeDispatchLease).UnixMilli()
		if leaseUntilMs > meta.ExpiresAtMs {
			leaseUntilMs = meta.ExpiresAtMs
		}
		authorizedClaimRaw, err := marshalCallRecord(newRedisCallDispatchingClaim(
			owner, leaseUntilMs, claim.Attempts, activeOwners,
		))
		if err != nil {
			return err
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.HSet(ctx, keys.claims, request.MessageID, authorizedClaimRaw)
			pipe.PExpireAt(ctx, keys.claims, time.UnixMilli(meta.ExpiresAtMs))
			return nil
		})
		if err == nil {
			authorized = true
		}
		return err
	})
	if err != nil {
		return false, callRedisError(err)
	}
	return authorized, nil
}

func (s *redisCallControlStore) CompleteWake(
	ctx context.Context,
	sender string,
	request CallStoreRequest,
	owner string,
) error {
	if owner == "" {
		return ErrCallBackendUnavailable
	}
	keys := s.callKeys(request.RecipientDevicePeerID, request.CallHandle)
	return callRedisError(s.watch(ctx, []string{keys.meta, keys.claims, keys.tombstone}, func(tx *redis.Tx) error {
		meta, err := readRedisCallJSON[redisCallMeta](ctx, tx, keys.meta)
		if err != nil || meta == nil {
			return err
		}
		if meta.SenderPeerID != sender || meta.RecipientDevicePeerID != request.RecipientDevicePeerID ||
			meta.CallHandle != request.CallHandle {
			return ErrCallUnauthorized
		}
		claimRaw, err := tx.HGet(ctx, keys.claims, request.MessageID).Result()
		if err != nil {
			return err
		}
		claim, err := decodeRedisCallWakeClaim(claimRaw)
		if err != nil {
			return err
		}
		if claim.State == redisCallWakeCompleted {
			return nil
		}
		if claim.State != redisCallWakeDispatching || !wakeOwnerPresent(claim.ActiveOwners, owner) {
			return ErrCallBackendUnavailable
		}
		activeOwners := make([]string, 0, len(claim.ActiveOwners)-1)
		for _, activeOwner := range claim.ActiveOwners {
			if activeOwner != owner {
				activeOwners = append(activeOwners, activeOwner)
			}
		}
		currentOwner := claim.Owner
		leaseUntilMs := claim.LeaseUntilMs
		if currentOwner == owner {
			currentOwner = ""
			leaseUntilMs = 0
		}
		var completedClaim redisCallWakeClaim
		if len(activeOwners) == 0 && currentOwner == "" {
			completedClaim = newRedisCallWakeClaim(redisCallWakeCompleted)
		} else {
			completedClaim = newRedisCallDispatchingClaim(
				currentOwner, leaseUntilMs, claim.Attempts, activeOwners,
			)
		}
		completedRaw, err := marshalCallRecord(completedClaim)
		if err != nil {
			return err
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.HSet(ctx, keys.claims, request.MessageID, completedRaw)
			pipe.PExpireAt(ctx, keys.claims, time.UnixMilli(meta.ExpiresAtMs))
			return nil
		})
		return err
	}))
}

// ReleaseWakeDispatchAuthorization records only that this invocation has
// returned from the provider. It intentionally leaves the attempt dispatching
// so an ambiguous CompleteWake can recover after its bounded lease.
func (s *redisCallControlStore) ReleaseWakeDispatchAuthorization(
	ctx context.Context,
	sender string,
	request CallStoreRequest,
	owner string,
) error {
	if owner == "" {
		return ErrCallBackendUnavailable
	}
	keys := s.callKeys(request.RecipientDevicePeerID, request.CallHandle)
	return callRedisError(s.watch(ctx, []string{keys.meta, keys.claims, keys.tombstone}, func(tx *redis.Tx) error {
		meta, err := readRedisCallJSON[redisCallMeta](ctx, tx, keys.meta)
		if err != nil || meta == nil {
			return err
		}
		if meta.SenderPeerID != sender || meta.RecipientDevicePeerID != request.RecipientDevicePeerID ||
			meta.CallHandle != request.CallHandle {
			return ErrCallUnauthorized
		}
		claimRaw, err := tx.HGet(ctx, keys.claims, request.MessageID).Result()
		if err != nil {
			return err
		}
		claim, err := decodeRedisCallWakeClaim(claimRaw)
		if err != nil {
			return err
		}
		if claim.State == redisCallWakeCompleted {
			return nil
		}
		if claim.State != redisCallWakeDispatching || !wakeOwnerPresent(claim.ActiveOwners, owner) {
			return ErrCallBackendUnavailable
		}
		activeOwners := make([]string, 0, len(claim.ActiveOwners)-1)
		for _, activeOwner := range claim.ActiveOwners {
			if activeOwner != owner {
				activeOwners = append(activeOwners, activeOwner)
			}
		}
		var releasedClaim redisCallWakeClaim
		if len(activeOwners) == 0 && claim.Owner == "" {
			releasedClaim = newRedisCallWakeClaim(redisCallWakeCompleted)
		} else {
			releasedClaim = newRedisCallDispatchingClaim(
				claim.Owner, claim.LeaseUntilMs, claim.Attempts, activeOwners,
			)
		}
		releasedRaw, err := marshalCallRecord(releasedClaim)
		if err != nil {
			return err
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.HSet(ctx, keys.claims, request.MessageID, releasedRaw)
			pipe.PExpireAt(ctx, keys.claims, time.UnixMilli(meta.ExpiresAtMs))
			return nil
		})
		return err
	}))
}

func (s *redisCallControlStore) SetEndpoint(
	ctx context.Context,
	record CallEndpointRecord,
	now time.Time,
) error {
	key := s.endpointKey(record.AccountPeerID)
	tombKey := s.endpointTombstoneKey(record.AccountPeerID)
	deviceRouteKey := s.endpointDeviceKey(record.DevicePeerID)
	return callRedisError(s.watch(ctx, []string{key, tombKey, deviceRouteKey}, func(tx *redis.Tx) error {
		tombEpoch, err := tx.HGet(ctx, tombKey, "preferenceEpoch").Uint64()
		if err != nil && !errors.Is(err, redis.Nil) {
			return err
		}
		existing, err := readRedisCallJSON[CallEndpointRecord](ctx, tx, key)
		if err != nil {
			return err
		}
		raw, err := marshalCallRecord(record)
		if err != nil {
			return err
		}
		exactExisting := false
		if existing != nil && existing.ExpiresAtMs > now.UnixMilli() {
			if record.PreferenceEpoch < existing.PreferenceEpoch {
				return ErrCallStaleEpoch
			}
			if record.PreferenceEpoch == existing.PreferenceEpoch {
				existingRaw, marshalErr := marshalCallRecord(*existing)
				if marshalErr != nil {
					return marshalErr
				}
				if string(existingRaw) != string(raw) {
					return ErrCallStaleEpoch
				}
				exactExisting = true
			}
		}
		if !exactExisting && tombEpoch >= record.PreferenceEpoch {
			return ErrCallStaleEpoch
		}
		routeRaw, err := marshalCallRecord(redisCallEndpointRoute{
			AccountPeerID: record.AccountPeerID, DevicePeerID: record.DevicePeerID,
			Platform: record.Platform, ExpiresAtMs: record.ExpiresAtMs,
			PreferenceEpoch: record.PreferenceEpoch,
		})
		if err != nil {
			return err
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.HSet(ctx, key, "record", raw)
			pipe.PExpireAt(ctx, key, time.UnixMilli(record.ExpiresAtMs))
			pipe.HSet(ctx, deviceRouteKey, "record", routeRaw)
			pipe.PExpireAt(ctx, deviceRouteKey, time.UnixMilli(record.ExpiresAtMs))
			pipe.HSet(ctx, tombKey,
				"preferenceEpoch", record.PreferenceEpoch,
				"deviceKeyEpoch", record.DeviceKeyEpoch,
				"deviceDigest", callOpaqueDigest("mknoon.call-endpoint-device.v1", record.DevicePeerID),
			)
			pipe.Expire(ctx, tombKey, callMaxTypedRecordTTL)
			return nil
		})
		return err
	}))
}

func (s *redisCallControlStore) GetEndpoint(
	ctx context.Context,
	accountPeerID string,
	now time.Time,
) (*CallEndpointRecord, error) {
	if s == nil || s.client == nil {
		return nil, ErrCallBackendUnavailable
	}
	record, err := readRedisCallJSON[CallEndpointRecord](ctx, s.client, s.endpointKey(accountPeerID))
	if err != nil {
		return nil, callRedisError(err)
	}
	if record == nil || record.ExpiresAtMs <= now.UnixMilli() || record.Schema != CallEndpointSchema ||
		record.Version != CallControlVersion {
		return nil, nil
	}
	copy := *record
	copy.Capabilities = append([]string(nil), record.Capabilities...)
	copy.Signature = append([]byte(nil), record.Signature...)
	return &copy, nil
}

func (s *redisCallControlStore) RevokeEndpoint(
	ctx context.Context,
	devicePeerID, accountPeerID string,
	preferenceEpoch uint64,
) error {
	key := s.endpointKey(accountPeerID)
	tombKey := s.endpointTombstoneKey(accountPeerID)
	return callRedisError(s.watch(ctx, []string{key, tombKey}, func(tx *redis.Tx) error {
		tombEpoch, err := tx.HGet(ctx, tombKey, "preferenceEpoch").Uint64()
		if err != nil && !errors.Is(err, redis.Nil) {
			return err
		}
		record, err := readRedisCallJSON[CallEndpointRecord](ctx, tx, key)
		if err != nil {
			return err
		}
		if record != nil {
			if record.DevicePeerID != devicePeerID {
				return ErrCallUnauthorized
			}
			if preferenceEpoch < record.PreferenceEpoch {
				return ErrCallStaleEpoch
			}
		} else {
			deviceDigest, err := tx.HGet(ctx, tombKey, "deviceDigest").Result()
			if err != nil && !errors.Is(err, redis.Nil) {
				return err
			}
			if deviceDigest == "" || deviceDigest != callOpaqueDigest("mknoon.call-endpoint-device.v1", devicePeerID) {
				return ErrCallUnauthorized
			}
		}
		if preferenceEpoch < tombEpoch {
			return ErrCallStaleEpoch
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.Del(ctx, key)
			if record != nil {
				pipe.Del(ctx, s.endpointDeviceKey(record.DevicePeerID))
			}
			pipe.HSet(ctx, tombKey, "preferenceEpoch", preferenceEpoch)
			if record != nil {
				pipe.HSet(ctx, tombKey, "deviceKeyEpoch", record.DeviceKeyEpoch)
				pipe.HSet(ctx, tombKey, "deviceDigest", callOpaqueDigest("mknoon.call-endpoint-device.v1", record.DevicePeerID))
			}
			pipe.Expire(ctx, tombKey, callMaxTypedRecordTTL)
			return nil
		})
		return err
	}))
}

func (s *redisCallControlStore) SetWakeHandle(
	ctx context.Context,
	recipient string,
	record CallWakeHandleRecord,
	now time.Time,
) error {
	key := s.wakeKey(recipient, record.AuthorizedSenderPeerID)
	directory := s.wakeDirectoryKey(recipient)
	directoryMember := redisCallWakeDirectoryMember(record.AuthorizedSenderPeerID)
	legacyMember := encodeRedisComponent(record.AuthorizedSenderPeerID)
	return callRedisError(s.watch(ctx, []string{key, directory}, func(tx *redis.Tx) error {
		live, err := tx.ZRangeByScoreWithScores(ctx, directory, &redis.ZRangeBy{
			Min: strconv.FormatInt(now.UnixMilli()+1, 10), Max: "+inf",
		}).Result()
		if err != nil && !errors.Is(err, redis.Nil) {
			return err
		}
		exists := false
		maxExpiryMs := record.ExpiresAtMs
		for _, entry := range live {
			member, ok := entry.Member.(string)
			if !ok {
				return ErrCallBackendUnavailable
			}
			exists = exists || member == directoryMember || member == legacyMember
			if int64(entry.Score) > maxExpiryMs {
				maxExpiryMs = int64(entry.Score)
			}
		}
		if !exists && len(live) >= callMaxWakeHandlesPerDevice {
			return ErrCallRecipientCapacity
		}
		stored := redisCallWakeRecord{
			Schema: CallWakeSchema, Version: CallControlVersion,
			HandleDigest: callOpaqueDigest("mknoon.call-wake.v1", record.WakeHandle),
			ExpiresAtMs:  record.ExpiresAtMs,
		}
		raw, err := marshalCallRecord(stored)
		if err != nil {
			return err
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.ZRemRangeByScore(ctx, directory, "-inf", strconv.FormatInt(now.UnixMilli(), 10))
			pipe.ZRem(ctx, directory, legacyMember)
			pipe.ZAdd(ctx, directory, redis.Z{Score: float64(record.ExpiresAtMs), Member: directoryMember})
			pipe.PExpire(ctx, directory, time.Duration(maxExpiryMs-now.UnixMilli())*time.Millisecond)
			pipe.HSet(ctx, key, "record", raw)
			pipe.PExpireAt(ctx, key, time.UnixMilli(record.ExpiresAtMs))
			return nil
		})
		return err
	}))
}

func (s *redisCallControlStore) RevokeWakeHandle(
	ctx context.Context,
	recipient, sender string,
) error {
	if s == nil || s.client == nil {
		return ErrCallBackendUnavailable
	}
	_, err := s.client.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
		pipe.Del(ctx, s.wakeKey(recipient, sender))
		pipe.ZRem(ctx, s.wakeDirectoryKey(recipient),
			redisCallWakeDirectoryMember(sender), encodeRedisComponent(sender))
		return nil
	})
	return callRedisError(err)
}

func (s *redisCallControlStore) SetCallToken(
	ctx context.Context,
	device string,
	record CallTokenRecord,
) (*CallTokenRecord, error) {
	if s == nil || s.client == nil {
		return nil, ErrCallBackendUnavailable
	}
	key := s.tokenKey(device, record.Kind)
	if record.Kind == CallTokenKindStandard {
		err := s.watch(ctx, []string{key}, func(tx *redis.Tx) error {
			existing, readErr := readRedisCallJSON[CallTokenRecord](ctx, tx, key)
			if readErr != nil {
				return readErr
			}
			if existing != nil && (existing.Kind != record.Kind || !validStoredCallTokenShape(*existing)) {
				return ErrCallBackendUnavailable
			}
			raw, marshalErr := marshalCallRecord(record)
			if marshalErr != nil {
				return marshalErr
			}
			_, commitErr := tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
				pipe.HSet(ctx, key, "record", raw)
				pipe.PExpireAt(ctx, key, time.UnixMilli(record.ExpiresAtMs))
				return nil
			})
			return commitErr
		})
		if err != nil {
			return nil, callRedisError(err)
		}
		copy := record
		return &copy, nil
	}

	generationKey := s.tokenGenerationKey(device, record.Kind)
	var stored *CallTokenRecord
	err := s.watch(ctx, []string{key, generationKey}, func(tx *redis.Tx) error {
		existing, err := readRedisCallJSON[CallTokenRecord](ctx, tx, key)
		if err != nil {
			return err
		}
		if existing != nil && (existing.Kind != CallTokenKindIOSVoIP || !validStoredCallTokenShape(*existing)) {
			return ErrCallBackendUnavailable
		}
		existingCurrent := existing != nil && validStoredIOSVoIPTokenBinding(*existing)
		if existingCurrent {
			if sameCallTokenRegistration(*existing, record) {
				copy := *existing
				stored = &copy
				return nil
			}
			if sameCallTokenRefreshIdentity(*existing, record) {
				if record.ExpiresAtMs <= existing.ExpiresAtMs {
					copy := *existing
					stored = &copy
					return nil
				}
				record.Generation = existing.Generation
				raw, marshalErr := marshalCallRecord(record)
				if marshalErr != nil {
					return marshalErr
				}
				_, commitErr := tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
					pipe.HSet(ctx, key, "record", raw)
					pipe.PExpireAt(ctx, key, time.UnixMilli(record.ExpiresAtMs))
					pipe.HSet(ctx, generationKey,
						"generation", record.Generation,
						"refreshEpoch", record.RefreshEpoch,
					)
					pipe.Expire(ctx, generationKey, callMaxTypedRecordTTL)
					return nil
				})
				if commitErr == nil {
					copy := record
					stored = &copy
				}
				return commitErr
			}
			if record.RefreshEpoch <= existing.RefreshEpoch {
				return ErrCallStaleEpoch
			}
		}
		highWater, err := tx.HGet(ctx, generationKey, "generation").Uint64()
		if err != nil && !errors.Is(err, redis.Nil) {
			return err
		}
		refreshHighWater, err := tx.HGet(ctx, generationKey, "refreshEpoch").Uint64()
		if err != nil && !errors.Is(err, redis.Nil) {
			return err
		}
		if existingCurrent && existing.Generation > highWater {
			highWater = existing.Generation
		}
		if existingCurrent && existing.RefreshEpoch > refreshHighWater {
			refreshHighWater = existing.RefreshEpoch
		}
		if record.RefreshEpoch <= refreshHighWater {
			return ErrCallStaleEpoch
		}
		if highWater == ^uint64(0) {
			return ErrCallBackendUnavailable
		}
		record.Generation = highWater + 1
		raw, err := marshalCallRecord(record)
		if err != nil {
			return err
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.HSet(ctx, key, "record", raw)
			pipe.PExpireAt(ctx, key, time.UnixMilli(record.ExpiresAtMs))
			pipe.HSet(ctx, generationKey,
				"generation", record.Generation,
				"refreshEpoch", record.RefreshEpoch,
			)
			pipe.Expire(ctx, generationKey, callMaxTypedRecordTTL)
			return nil
		})
		if err == nil {
			copy := record
			stored = &copy
		}
		return err
	})
	if err != nil {
		return nil, callRedisError(err)
	}
	if stored == nil {
		return nil, ErrCallBackendUnavailable
	}
	return stored, nil
}

func (s *redisCallControlStore) GetCallToken(
	ctx context.Context,
	device string,
	kind CallTokenKind,
	now time.Time,
) (*CallTokenRecord, error) {
	if s == nil || s.client == nil {
		return nil, ErrCallBackendUnavailable
	}
	record, err := readRedisCallJSON[CallTokenRecord](ctx, s.client, s.tokenKey(device, kind))
	if err != nil {
		return nil, callRedisError(err)
	}
	if record == nil {
		return nil, nil
	}
	if record.Kind != kind || !validStoredCallTokenShape(*record) {
		return nil, ErrCallBackendUnavailable
	}
	if record.ExpiresAtMs <= now.UnixMilli() {
		return nil, nil
	}
	if !validStoredCallToken(*record, now) {
		return nil, ErrCallBackendUnavailable
	}
	copy := *record
	return &copy, nil
}

func (s *redisCallControlStore) RevokeCallToken(
	ctx context.Context,
	device string,
	kind CallTokenKind,
) error {
	if s == nil || s.client == nil {
		return ErrCallBackendUnavailable
	}
	key := s.tokenKey(device, kind)
	return callRedisError(s.watch(ctx, []string{key}, func(tx *redis.Tx) error {
		record, err := readRedisCallJSON[CallTokenRecord](ctx, tx, key)
		if err != nil || record == nil {
			return err
		}
		if record.Kind != kind || !validStoredCallTokenShape(*record) {
			return ErrCallBackendUnavailable
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.Del(ctx, key)
			return nil
		})
		return err
	}))
}

func (s *redisCallControlStore) RevokeCallTokenRefreshEpochIfMatch(
	ctx context.Context,
	device string,
	kind CallTokenKind,
	refreshEpoch uint64,
) (bool, error) {
	key := s.tokenKey(device, kind)
	revoked := false
	err := s.watch(ctx, []string{key}, func(tx *redis.Tx) error {
		record, err := readRedisCallJSON[CallTokenRecord](ctx, tx, key)
		if err != nil || record == nil {
			return err
		}
		if record.Kind != kind || !validStoredCallTokenShape(*record) {
			return ErrCallBackendUnavailable
		}
		if record.RefreshEpoch != refreshEpoch {
			return nil
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.Del(ctx, key)
			return nil
		})
		if err == nil {
			revoked = true
		}
		return err
	})
	if err != nil {
		return false, callRedisError(err)
	}
	return revoked, nil
}

func (s *redisCallControlStore) RevokeCallTokenIfMatch(
	ctx context.Context,
	device string,
	route CallWakeRoute,
) error {
	key := s.tokenKey(device, route.Kind)
	return callRedisError(s.watch(ctx, []string{key}, func(tx *redis.Tx) error {
		record, err := readRedisCallJSON[CallTokenRecord](ctx, tx, key)
		if err != nil || record == nil {
			return err
		}
		if record.Kind != route.Kind || !validStoredCallTokenShape(*record) {
			return ErrCallBackendUnavailable
		}
		if !callWakeRouteMatchesToken(route, *record) {
			return nil
		}
		_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
			pipe.Del(ctx, key)
			return nil
		})
		return err
	}))
}

type redisCallKeySet struct {
	handles, meta, events, ids, claims, tombstone, replays string
}

func (s *redisCallControlStore) callKeys(recipient, handle string) redisCallKeySet {
	base := s.prefix + "call:v1:mailbox:" + encodeRedisComponent(recipient)
	callBase := base + ":call:" + encodeRedisComponent(handle)
	return redisCallKeySet{
		handles: base + ":handles", meta: callBase + ":meta", events: callBase + ":events",
		ids: callBase + ":ids", claims: callBase + ":wake-claims", tombstone: callBase + ":tombstone",
		replays: base + ":replay-directory",
	}
}

func (s *redisCallControlStore) handlesKey(recipient string) string {
	return s.prefix + "call:v1:mailbox:" + encodeRedisComponent(recipient) + ":handles"
}

func (s *redisCallControlStore) endpointKey(account string) string {
	return s.prefix + "call:v1:endpoint:" + encodeRedisComponent(account)
}

func (s *redisCallControlStore) endpointTombstoneKey(account string) string {
	return s.prefix + "call:v1:endpoint-tombstone:" + encodeRedisComponent(account)
}

func (s *redisCallControlStore) endpointDeviceKey(device string) string {
	return s.prefix + "call:v1:endpoint-device:" + encodeRedisComponent(device)
}

func (s *redisCallControlStore) wakeKey(recipient, sender string) string {
	return s.prefix + "call:v1:wake:" + encodeRedisComponent(recipient) + ":" + encodeRedisComponent(sender)
}

func (s *redisCallControlStore) wakeDirectoryKey(recipient string) string {
	return s.prefix + "call:v1:wake-directory:" + encodeRedisComponent(recipient)
}

func newRedisCallWakeClaim(state string) redisCallWakeClaim {
	return redisCallWakeClaim{
		Schema: redisCallWakeClaimSchema, Version: CallControlVersion, State: state,
	}
}

func newRedisCallDispatchingClaim(
	owner string,
	leaseUntilMs int64,
	attempts int,
	activeOwners []string,
) redisCallWakeClaim {
	return redisCallWakeClaim{
		Schema: redisCallWakeClaimSchema, Version: CallControlVersion,
		State: redisCallWakeDispatching, Owner: owner,
		LeaseUntilMs: leaseUntilMs, Attempts: attempts,
		ActiveOwners: append([]string(nil), activeOwners...),
	}
}

func decodeRedisCallWakeClaim(raw string) (*redisCallWakeClaim, error) {
	var claim redisCallWakeClaim
	if err := json.Unmarshal([]byte(raw), &claim); err != nil ||
		claim.Schema != redisCallWakeClaimSchema || claim.Version != CallControlVersion ||
		(claim.State != redisCallWakeClaimed && claim.State != redisCallWakeDispatching &&
			claim.State != redisCallWakeCompleted) {
		return nil, ErrCallBackendUnavailable
	}
	switch claim.State {
	case redisCallWakeClaimed:
		if claim.Owner != "" || claim.LeaseUntilMs != 0 || claim.Attempts != 0 ||
			len(claim.ActiveOwners) != 0 {
			return nil, ErrCallBackendUnavailable
		}
	case redisCallWakeDispatching:
		if claim.Attempts <= 0 || claim.Attempts > callMaxWakeDispatchAttempts ||
			len(claim.ActiveOwners) > claim.Attempts ||
			len(claim.ActiveOwners) > callMaxWakeDispatchAttempts ||
			(claim.Owner == "" && claim.LeaseUntilMs != 0) ||
			(claim.Owner != "" && claim.LeaseUntilMs <= 0) ||
			(claim.Owner == "" && len(claim.ActiveOwners) == 0) {
			return nil, ErrCallBackendUnavailable
		}
		seenOwners := make(map[string]struct{}, len(claim.ActiveOwners))
		for _, owner := range claim.ActiveOwners {
			if owner == "" {
				return nil, ErrCallBackendUnavailable
			}
			if _, exists := seenOwners[owner]; exists {
				return nil, ErrCallBackendUnavailable
			}
			seenOwners[owner] = struct{}{}
		}
	case redisCallWakeCompleted:
		if claim.Owner != "" || claim.LeaseUntilMs != 0 || claim.Attempts != 0 ||
			len(claim.ActiveOwners) != 0 {
			return nil, ErrCallBackendUnavailable
		}
	}
	return &claim, nil
}

func wakeOwnerPresent(owners []string, owner string) bool {
	return slices.Contains(owners, owner)
}

func redisCallWakeClaimBlocksTerminal(claim *redisCallWakeClaim, nowMs int64) bool {
	if claim == nil || claim.State != redisCallWakeDispatching {
		return false
	}
	return len(claim.ActiveOwners) != 0 ||
		(claim.Owner != "" && claim.LeaseUntilMs > nowMs)
}

func redisCallWakeDirectoryMember(sender string) string {
	raw, _ := json.Marshal(redisCallWakeDirectoryRecord{
		Schema: redisCallWakeDirectorySchema, Version: CallControlVersion,
		SenderDigest: callOpaqueDigest("mknoon.call-wake-directory-sender.v1", sender),
	})
	return string(raw)
}

func redisCallReplayDirectoryMember(handle string) string {
	raw, _ := json.Marshal(redisCallReplayDirectoryRecord{
		Schema: redisCallReplayDirectorySchema, Version: CallControlVersion,
		HandleDigest: callOpaqueDigest("mknoon.call-replay-directory-handle.v1", handle),
	})
	return string(raw)
}

func (s *redisCallControlStore) tokenKey(device string, kind CallTokenKind) string {
	return s.prefix + "call:v1:token:" + encodeRedisComponent(device) + ":" + string(kind)
}

func (s *redisCallControlStore) tokenGenerationKey(device string, kind CallTokenKind) string {
	return s.prefix + "call:v1:token-generation:" + encodeRedisComponent(device) + ":" + string(kind)
}

func (s *redisCallControlStore) rateKey(sender string) string {
	return s.prefix + "call:v1:rate:" + encodeRedisComponent(sender)
}

func (s *redisCallControlStore) terminalizeTx(
	ctx context.Context,
	tx *redis.Tx,
	keys redisCallKeySet,
	meta *redisCallMeta,
	state string,
	now time.Time,
) error {
	if meta == nil {
		return nil
	}
	claims, err := tx.HVals(ctx, keys.claims).Result()
	if err != nil && !errors.Is(err, redis.Nil) {
		return err
	}
	for _, rawClaim := range claims {
		claim, err := decodeRedisCallWakeClaim(rawClaim)
		if err != nil {
			return err
		}
		if meta.ExpiresAtMs > now.UnixMilli() && redisCallWakeClaimBlocksTerminal(claim, now.UnixMilli()) {
			return ErrCallBackendUnavailable
		}
	}
	tombstone := redisCallTombstone{
		State: state, SenderDigest: callOpaqueDigest("mknoon.call-sender.v1", meta.SenderPeerID),
		ExpiresAtMs: meta.ExpiresAtMs, TerminalAtMs: now.UnixMilli(),
	}
	raw, err := marshalCallRecord(tombstone)
	if err != nil {
		return err
	}
	_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
		pipe.Del(ctx, keys.meta, keys.events, keys.ids, keys.claims)
		pipe.ZRem(ctx, keys.handles, meta.CallHandle)
		pipe.HSet(ctx, keys.tombstone, "record", raw)
		pipe.Expire(ctx, keys.tombstone, CallReplayTombstoneTTL)
		pipe.ZRemRangeByScore(ctx, keys.replays, "-inf", strconv.FormatInt(now.UnixMilli(), 10))
		pipe.ZAdd(ctx, keys.replays, redis.Z{
			Score:  float64(now.Add(CallReplayTombstoneTTL).UnixMilli()),
			Member: redisCallReplayDirectoryMember(meta.CallHandle),
		})
		pipe.Expire(ctx, keys.replays, CallReplayTombstoneTTL+CallMaxPreconnectTTL)
		return nil
	})
	return err
}

func callReceipt(status CallStoreStatus, meta redisCallMeta, pending int) CallStoreReceipt {
	return CallStoreReceipt{
		Schema: CallMailboxSchema, Version: CallControlVersion, StoreStatus: status,
		ReceiptAtMs: meta.ReceiptAtMs, ExpiresAtMs: meta.ExpiresAtMs,
		EventCount: meta.EventCount, TotalBytes: meta.TotalBytes, PendingHandles: pending,
	}
}

type redisCallJSONReader interface {
	HGet(context.Context, string, string) *redis.StringCmd
}

func readRedisCallJSON[T any](ctx context.Context, reader redisCallJSONReader, key string) (*T, error) {
	raw, err := reader.HGet(ctx, key, "record").Bytes()
	if errors.Is(err, redis.Nil) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var value T
	if err := json.Unmarshal(raw, &value); err != nil {
		return nil, ErrCallBackendUnavailable
	}
	return &value, nil
}

func (s *redisCallControlStore) watch(
	ctx context.Context,
	keys []string,
	fn func(*redis.Tx) error,
) error {
	if s == nil || s.client == nil {
		return ErrCallBackendUnavailable
	}
	sorted := append([]string(nil), keys...)
	sort.Strings(sorted)
	var last error
	for range redisWatchRetries {
		err := s.client.Watch(ctx, fn, sorted...)
		if !errors.Is(err, redis.TxFailedErr) {
			return err
		}
		last = err
	}
	if last == nil {
		last = redis.TxFailedErr
	}
	return last
}

func callRedisError(err error) error {
	if err == nil {
		return nil
	}
	for _, sentinel := range []error{
		ErrCallInvalidRequest, ErrCallUnauthorized, ErrCallIdentityConflict, ErrCallReplay,
		ErrCallExpiry, ErrCallEnvelopeTooLarge, ErrCallRecipientCapacity,
		ErrCallEventCapacity, ErrCallByteCapacity, ErrCallRateLimited, ErrCallStaleEpoch,
	} {
		if errors.Is(err, sentinel) {
			return sentinel
		}
	}
	return ErrCallBackendUnavailable
}
