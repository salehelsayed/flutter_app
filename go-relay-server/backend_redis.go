package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"sort"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

const redisWatchRetries = 5

type redisRendezvousBackend struct {
	client *redis.Client
	prefix string
}

type redisInboxBackend struct {
	client     *redis.Client
	prefix     string
	maxPerPeer int
	// Test-only clock. Nil is equivalent to time.Now.
	now func() time.Time
	// Test-only failpoints keep atomicity and ambiguous-commit behavior
	// deterministic without changing the production Redis command path.
	ackCustodyBeforeCommit func() error
	ackCustodyAfterCommit  func() error
}

type redisGroupInboxBackend struct {
	client      *redis.Client
	prefix      string
	maxPerGroup int
	ttl         time.Duration
}

type redisPushTokenBackend struct {
	client *redis.Client
	prefix string
}

func newRedisClientFromURL(rawURL string) (*redis.Client, error) {
	opts, err := redis.ParseURL(rawURL)
	if err != nil {
		return nil, fmt.Errorf("parse REDIS_URL: %w", err)
	}

	client := redis.NewClient(opts)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	if err := client.Ping(ctx).Err(); err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("ping Redis: %w", err)
	}

	return client, nil
}

func newRedisRendezvousBackend(client *redis.Client, prefix string) *redisRendezvousBackend {
	return &redisRendezvousBackend{client: client, prefix: prefix}
}

func newRedisInboxBackend(client *redis.Client, prefix string, maxPerPeer int) *redisInboxBackend {
	return &redisInboxBackend{
		client:     client,
		prefix:     prefix,
		maxPerPeer: maxPerPeer,
		now:        time.Now,
	}
}

func (b *redisInboxBackend) nowTime() time.Time {
	if b != nil && b.now != nil {
		return b.now()
	}
	return time.Now()
}

func newRedisGroupInboxBackend(
	client *redis.Client,
	prefix string,
	maxPerGroup int,
	ttl time.Duration,
) *redisGroupInboxBackend {
	return &redisGroupInboxBackend{
		client:      client,
		prefix:      prefix,
		maxPerGroup: maxPerGroup,
		ttl:         ttl,
	}
}

func newRedisPushTokenBackend(client *redis.Client, prefix string) *redisPushTokenBackend {
	return &redisPushTokenBackend{client: client, prefix: prefix}
}

func encodeRedisComponent(value string) string {
	return base64.RawURLEncoding.EncodeToString([]byte(value))
}

func scanRedisKeys(client *redis.Client, pattern string) ([]string, error) {
	ctx := context.Background()
	var (
		cursor uint64
		keys   []string
	)

	for {
		batch, next, err := client.Scan(ctx, cursor, pattern, 100).Result()
		if err != nil {
			return nil, err
		}
		keys = append(keys, batch...)
		cursor = next
		if cursor == 0 {
			sort.Strings(keys)
			return keys, nil
		}
	}
}

func withRedisWatchRetry(
	client *redis.Client,
	key string,
	fn func(tx *redis.Tx) error,
) error {
	return withRedisWatchRetryKeys(client, []string{key}, fn)
}

func withRedisWatchRetryKeys(
	client *redis.Client,
	keys []string,
	fn func(tx *redis.Tx) error,
) error {
	ctx := context.Background()
	var lastErr error

	for range redisWatchRetries {
		err := client.Watch(ctx, fn, keys...)
		if err == nil {
			return nil
		}
		if err != redis.TxFailedErr {
			return err
		}
		lastErr = err
	}

	if lastErr == nil {
		lastErr = redis.TxFailedErr
	}
	return lastErr
}

// redisReplaceLists commits every supplied list replacement in one EXEC. It is
// used by protected custody so a newly accepted authoritative row and its
// legacy compatibility shadow can never become a one-sided known success.
func redisReplaceLists(tx *redis.Tx, replacements map[string][]string) error {
	ctx := context.Background()
	_, err := tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
		keys := make([]string, 0, len(replacements))
		for key := range replacements {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			values := replacements[key]
			pipe.Del(ctx, key)
			if len(values) == 0 {
				continue
			}
			items := make([]interface{}, len(values))
			for i, value := range values {
				items[i] = value
			}
			pipe.RPush(ctx, key, items...)
		}
		return nil
	})
	return err
}

func redisReplaceList(tx *redis.Tx, key string, values []string) error {
	ctx := context.Background()
	_, err := tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
		pipe.Del(ctx, key)
		if len(values) == 0 {
			return nil
		}

		items := make([]interface{}, len(values))
		for i, value := range values {
			items[i] = value
		}
		pipe.RPush(ctx, key, items...)
		return nil
	})
	return err
}

type redisGroupRecord struct {
	From             string   `json:"from"`
	Message          string   `json:"message"`
	Timestamp        int64    `json:"timestamp"`
	ID               string   `json:"id"`
	RecipientPeerIds []string `json:"recipientPeerIds,omitempty"`
}

func (b *redisRendezvousBackend) key(ns string, peerId string) string {
	return b.prefix + "rz:" + encodeRedisComponent(ns) + ":" + encodeRedisComponent(peerId)
}

func (b *redisRendezvousBackend) namespacePattern(ns string) string {
	return b.prefix + "rz:" + encodeRedisComponent(ns) + ":*"
}

func (b *redisRendezvousBackend) allPattern() string {
	return b.prefix + "rz:*"
}

func (b *redisRendezvousBackend) Register(ns string, peerId string, signedPeerRecord []byte, ttlSeconds uint64) {
	ctx := context.Background()
	ttl := time.Duration(ttlSeconds) * time.Second
	if ttl <= 0 {
		ttl = time.Second
	}
	if err := b.client.Set(ctx, b.key(ns, peerId), signedPeerRecord, ttl).Err(); err != nil {
		log.Printf("[REDIS][RENDEZVOUS] register failed: %v", err)
	}
}

func (b *redisRendezvousBackend) Unregister(ns string, peerId string) {
	ctx := context.Background()
	if err := b.client.Del(ctx, b.key(ns, peerId)).Err(); err != nil {
		log.Printf("[REDIS][RENDEZVOUS] unregister failed: %v", err)
	}
}

func (b *redisRendezvousBackend) Discover(ns string, requestingPeer string, limit uint64) []Registration {
	keys, err := scanRedisKeys(b.client, b.namespacePattern(ns))
	if err != nil {
		log.Printf("[REDIS][RENDEZVOUS] discover scan failed: %v", err)
		return nil
	}

	requesterSuffix := ":" + encodeRedisComponent(requestingPeer)
	ctx := context.Background()
	results := make([]Registration, 0, minInt(len(keys), int(limit)))

	for _, key := range keys {
		if strings.HasSuffix(key, requesterSuffix) {
			continue
		}

		recordBytes, err := b.client.Get(ctx, key).Bytes()
		if err == redis.Nil {
			continue
		}
		if err != nil {
			log.Printf("[REDIS][RENDEZVOUS] discover get failed: %v", err)
			continue
		}

		results = append(results, Registration{
			Ns:               ns,
			SignedPeerRecord: recordBytes,
		})
		if uint64(len(results)) >= limit {
			break
		}
	}

	return results
}

func (b *redisRendezvousBackend) Cleanup() {}

func (b *redisRendezvousBackend) Stats() (namespaces int, totalPeers int) {
	keys, err := scanRedisKeys(b.client, b.allPattern())
	if err != nil {
		log.Printf("[REDIS][RENDEZVOUS] stats scan failed: %v", err)
		return 0, 0
	}

	namespaceSet := make(map[string]struct{})
	for _, key := range keys {
		rest := strings.TrimPrefix(key, b.prefix+"rz:")
		parts := strings.SplitN(rest, ":", 2)
		if len(parts) != 2 {
			continue
		}
		namespaceSet[parts[0]] = struct{}{}
		totalPeers++
	}

	return len(namespaceSet), totalPeers
}

func (b *redisInboxBackend) key(peerId string) string {
	return b.prefix + "inbox:" + encodeRedisComponent(peerId)
}

func (b *redisInboxBackend) allPattern() string {
	return b.prefix + "inbox:*"
}

func (b *redisInboxBackend) Store(toPeerId string, entry inboxMessage) (InboxStoreResult, error) {
	entry = ensureInboxMessageID(entry)
	payload, err := json.Marshal(entry)
	if err != nil {
		return "", fmt.Errorf("encode inbox message: %w", err)
	}

	key := b.key(toPeerId)
	cutoff := b.nowTime().Add(-maxMessageAge).UnixMilli()
	dedupeKey := extractDirectInboxDedupeKey(entry.Message)
	var result InboxStoreResult
	pruned := 0
	evicted := 0

	err = withRedisWatchRetry(b.client, key, func(tx *redis.Tx) error {
		rawEntries, err := tx.LRange(context.Background(), key, 0, -1).Result()
		if err == redis.Nil {
			rawEntries = nil
		} else if err != nil {
			return err
		}

		validRaw, validMessages, prunedInTx := normalizeInboxEntries(rawEntries, cutoff)
		pruned = prunedInTx
		evicted = 0

		if dedupeKey != "" {
			for _, message := range validMessages {
				if extractDirectInboxDedupeKey(message.Message) == dedupeKey {
					if len(validRaw) != len(rawEntries) {
						if err := redisReplaceList(tx, key, validRaw); err != nil {
							return err
						}
					}
					result = InboxStoreResultDuplicate
					return nil
				}
			}
		}

		// At cap: evict the OLDEST and store the newest (build-106 contract,
		// NET-REL-07 — shipped clients hard-fail any non-OK store). Counted
		// after the transaction commits (retry-safe, same pattern as pruned).
		if len(validRaw) >= b.maxPerPeer {
			evicted = len(validRaw) - b.maxPerPeer + 1
			validRaw = validRaw[evicted:]
		}

		values := append([]string(nil), validRaw...)
		values = append(values, string(payload))

		if err := redisReplaceList(tx, key, values); err != nil {
			return err
		}
		result = InboxStoreResultStored
		return nil
	})
	if err != nil {
		return "", fmt.Errorf("store redis inbox message: %w", err)
	}
	recordInboxExpiredPruned(pruned)
	if evicted > 0 {
		inboxCappedCounter.Add(float64(evicted))
	}
	return result, nil
}

func (b *redisInboxBackend) Retrieve(peerId string, limit int) ([]inboxMessage, bool) {
	if limit <= 0 {
		return nil, false
	}

	key := b.key(peerId)
	cutoff := b.nowTime().Add(-maxMessageAge).UnixMilli()

	var (
		result  []inboxMessage
		hasMore bool
		pruned  int
	)

	err := withRedisWatchRetry(b.client, key, func(tx *redis.Tx) error {
		rawEntries, err := tx.LRange(context.Background(), key, 0, -1).Result()
		if err == redis.Nil {
			result = nil
			hasMore = false
			return nil
		}
		if err != nil {
			return err
		}

		validRaw, validMessages, prunedInTx := normalizeInboxEntries(rawEntries, cutoff)
		pruned = prunedInTx
		if len(validRaw) == 0 {
			result = nil
			hasMore = false
			return redisReplaceList(tx, key, nil)
		}

		pageSize := minInt(limit, len(validMessages))
		result = append([]inboxMessage(nil), validMessages[:pageSize]...)
		remaining := append([]string(nil), validRaw[pageSize:]...)
		hasMore = len(remaining) > 0
		return redisReplaceList(tx, key, remaining)
	})
	if err != nil {
		log.Printf("[REDIS][INBOX] retrieve failed: %v", err)
		return nil, false
	}
	recordInboxExpiredPruned(pruned)

	return result, hasMore
}

func (b *redisInboxBackend) RetrievePending(peerId string, limit int) ([]inboxMessage, bool) {
	if limit <= 0 {
		return nil, false
	}

	key := b.key(peerId)
	cutoff := b.nowTime().Add(-maxMessageAge).UnixMilli()

	var (
		result  []inboxMessage
		hasMore bool
		pruned  int
	)

	err := withRedisWatchRetry(b.client, key, func(tx *redis.Tx) error {
		rawEntries, err := tx.LRange(context.Background(), key, 0, -1).Result()
		if err == redis.Nil {
			result = nil
			hasMore = false
			return nil
		}
		if err != nil {
			return err
		}

		validRaw, validMessages, prunedInTx := normalizeInboxEntries(rawEntries, cutoff)
		pruned = prunedInTx
		if len(validRaw) == 0 {
			result = nil
			hasMore = false
			return redisReplaceList(tx, key, nil)
		}

		pageSize := minInt(limit, len(validMessages))
		result = append([]inboxMessage(nil), validMessages[:pageSize]...)
		hasMore = len(validMessages) > pageSize
		return redisReplaceList(tx, key, validRaw)
	})
	if err != nil {
		log.Printf("[REDIS][INBOX] retrieve pending failed: %v", err)
		return nil, false
	}
	recordInboxExpiredPruned(pruned)

	return result, hasMore
}

func (b *redisInboxBackend) Ack(peerId string, entryIDs []string) (int, error) {
	if len(entryIDs) == 0 {
		return 0, nil
	}

	targets := make(map[string]struct{}, len(entryIDs))
	for _, entryID := range entryIDs {
		if entryID == "" {
			continue
		}
		targets[entryID] = struct{}{}
	}
	if len(targets) == 0 {
		return 0, nil
	}

	key := b.key(peerId)
	cutoff := b.nowTime().Add(-maxMessageAge).UnixMilli()
	removed := 0
	pruned := 0

	err := withRedisWatchRetry(b.client, key, func(tx *redis.Tx) error {
		rawEntries, err := tx.LRange(context.Background(), key, 0, -1).Result()
		if err == redis.Nil {
			removed = 0
			return nil
		}
		if err != nil {
			return err
		}

		validRaw, validMessages, prunedInTx := normalizeInboxEntries(rawEntries, cutoff)
		pruned = prunedInTx
		if len(validRaw) == 0 {
			removed = 0
			return redisReplaceList(tx, key, nil)
		}

		remainingRaw := make([]string, 0, len(validRaw))
		removed = 0
		for i, message := range validMessages {
			if _, ok := targets[message.ID]; ok {
				removed++
				continue
			}
			remainingRaw = append(remainingRaw, validRaw[i])
		}
		return redisReplaceList(tx, key, remainingRaw)
	})
	if err != nil {
		log.Printf("[REDIS][INBOX] ack failed: %v", err)
		return 0, err
	}
	recordInboxExpiredPruned(pruned)

	return removed, nil
}

func (b *redisInboxBackend) Count(peerId string) int {
	rawEntries, err := b.client.LRange(context.Background(), b.key(peerId), 0, -1).Result()
	if err == redis.Nil {
		return 0
	}
	if err != nil {
		log.Printf("[REDIS][INBOX] count failed: %v", err)
		return 0
	}

	_, validMessages := filterInboxEntries(rawEntries, b.nowTime().Add(-maxMessageAge).UnixMilli())
	return len(validMessages)
}

func (b *redisInboxBackend) Stats() (totalPeers int, totalMessages int) {
	keys, err := scanRedisKeys(b.client, b.allPattern())
	if err != nil {
		log.Printf("[REDIS][INBOX] stats scan failed: %v", err)
		return 0, 0
	}

	cutoff := b.nowTime().Add(-maxMessageAge).UnixMilli()
	for _, key := range keys {
		rawEntries, err := b.client.LRange(context.Background(), key, 0, -1).Result()
		if err == redis.Nil {
			continue
		}
		if err != nil {
			log.Printf("[REDIS][INBOX] stats read failed: %v", err)
			continue
		}

		_, validMessages := filterInboxEntries(rawEntries, cutoff)
		if len(validMessages) == 0 {
			continue
		}
		totalPeers++
		totalMessages += len(validMessages)
	}

	return totalPeers, totalMessages
}

func (b *redisInboxBackend) ackCustodyKey(peerID string) string {
	return b.prefix + "custody_inbox:" + encodeRedisComponent(peerID)
}

func (b *redisInboxBackend) ackCustodyPattern() string {
	return b.prefix + "custody_inbox:*"
}

func equalStringSlices(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for i := range left {
		if left[i] != right[i] {
			return false
		}
	}
	return true
}

func inboxIdentityMatches(entry inboxMessage, from string, message string) bool {
	return entry.From == from && entry.Message == message
}

func inboxCustodyIdentityMatches(entry inboxMessage, candidate inboxMessage) bool {
	return inboxIdentityMatches(entry, candidate.From, candidate.Message) &&
		entry.ExpiresAtMs == candidate.ExpiresAtMs
}

// StoreAckCustody atomically writes the protected authority and legacy shadow.
// Duplicate and identity-conflict decisions precede the capacity check so an
// exact retry remains accepting at cap and preserves the original expiry.
func (b *redisInboxBackend) StoreAckCustody(
	toPeerID string,
	entry inboxMessage,
	dedupeKey string,
) (InboxStoreResult, inboxMessage, error) {
	entry = ensureInboxMessageID(entry)
	protectedKey := b.ackCustodyKey(toPeerID)
	legacyKey := b.key(toPeerID)
	cutoff := b.nowTime().Add(-maxMessageAge).UnixMilli()
	capacity := b.maxPerPeer
	if capacity <= 0 {
		capacity = maxMessagesPerPeer
	}

	var (
		result          InboxStoreResult
		storedEntry     inboxMessage
		decisionErr     error
		protectedPruned int
		legacyPruned    int
		legacyEvicted   int
		acceptedCommit  bool
	)

	err := withRedisWatchRetryKeys(
		b.client,
		[]string{protectedKey, legacyKey},
		func(tx *redis.Tx) error {
			ctx := context.Background()
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

			var protectedMatch *inboxMessage
			for i := range protectedMessages {
				messageKey := extractDirectInboxDedupeKey(protectedMessages[i].Message)
				if messageKey != dedupeKey {
					continue
				}
				if !inboxCustodyIdentityMatches(protectedMessages[i], entry) {
					decisionErr = errAckCustodyIdentityConflict
					break
				}
				matched := protectedMessages[i]
				protectedMatch = &matched
			}

			if decisionErr == nil && protectedMatch != nil {
				result = InboxStoreResultDuplicate
				storedEntry = *protectedMatch
			} else if decisionErr == nil {
				var legacyMatch *inboxMessage
				for i := range legacyMessages {
					if extractDirectInboxDedupeKey(legacyMessages[i].Message) != dedupeKey {
						continue
					}
					if !inboxCustodyIdentityMatches(legacyMessages[i], entry) {
						decisionErr = errAckCustodyIdentityConflict
						break
					}
					matched := legacyMessages[i]
					legacyMatch = &matched
				}

				if decisionErr == nil && legacyMatch != nil && entry.ExpiresAtMs > 0 {
					// A ceiling-bearing retry may only converge against the protected
					// authority that accepted that exact ceiling. A lone legacy shadow
					// cannot be promoted into new media custody authority.
					decisionErr = errAckCustodyIdentityConflict
				} else if decisionErr == nil && len(protectedMessages) >= capacity {
					result = InboxStoreResultRejectedFull
				} else if decisionErr == nil && legacyMatch != nil {
					// Promote the already-accepted legacy identity without extending
					// its timestamp/expiry or minting a second relay entry ID.
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

					// The shadow obeys the frozen legacy evict-oldest capacity
					// contract. Its eviction never touches the protected list.
					if len(validLegacyRaw) >= capacity {
						legacyEvicted = len(validLegacyRaw) - capacity + 1
						validLegacyRaw = validLegacyRaw[legacyEvicted:]
					}
					validLegacyRaw = append(validLegacyRaw, string(payload))
					result = InboxStoreResultStored
					acceptedCommit = true
				}
			}

			needsWrite := !equalStringSlices(protectedRaw, validProtectedRaw) ||
				!equalStringSlices(legacyRaw, validLegacyRaw)
			if !needsWrite {
				return nil
			}
			if acceptedCommit && b.ackCustodyBeforeCommit != nil {
				if err := b.ackCustodyBeforeCommit(); err != nil {
					return err
				}
			}
			return redisReplaceLists(tx, map[string][]string{
				protectedKey: validProtectedRaw,
				legacyKey:    validLegacyRaw,
			})
		},
	)
	if err != nil {
		return "", inboxMessage{}, fmt.Errorf("atomic protected/shadow store: %w", err)
	}

	recordAckCustodyExpired(protectedPruned)
	recordInboxExpiredPruned(legacyPruned)
	if legacyEvicted > 0 {
		inboxCappedCounter.Add(float64(legacyEvicted))
	}
	if decisionErr != nil {
		return "", inboxMessage{}, decisionErr
	}
	if acceptedCommit && b.ackCustodyAfterCommit != nil {
		if err := b.ackCustodyAfterCommit(); err != nil {
			return "", inboxMessage{}, fmt.Errorf("ack custody response after commit: %w", err)
		}
	}
	return result, storedEntry, nil
}

func ackCustodyShadowSignature(message inboxMessage) string {
	return fmt.Sprintf(
		"%s\x00%s\x00%s\x00%d",
		message.ID,
		message.From,
		message.Message,
		message.ExpiresAtMs,
	)
}

func coalesceAndSortAckCustodyMessages(
	protectedMessages []inboxMessage,
	legacyMessages []inboxMessage,
) []inboxMessage {
	logical := make([]inboxMessage, 0, len(protectedMessages)+len(legacyMessages))
	protectedSignatures := make(map[string]struct{}, len(protectedMessages))
	for _, message := range protectedMessages {
		logical = append(logical, message)
		protectedSignatures[ackCustodyShadowSignature(message)] = struct{}{}
	}
	for _, message := range legacyMessages {
		if _, isExactShadow := protectedSignatures[ackCustodyShadowSignature(message)]; isExactShadow {
			continue
		}
		logical = append(logical, message)
	}

	sort.SliceStable(logical, func(i, j int) bool {
		if logical[i].Timestamp != logical[j].Timestamp {
			return logical[i].Timestamp < logical[j].Timestamp
		}
		if logical[i].ID != logical[j].ID {
			return logical[i].ID < logical[j].ID
		}
		if logical[i].From != logical[j].From {
			return logical[i].From < logical[j].From
		}
		return logical[i].Message < logical[j].Message
	})
	return logical
}

func (b *redisInboxBackend) RetrieveAckCustodyPending(
	peerID string,
	limit int,
) ([]inboxMessage, bool, error) {
	if limit <= 0 {
		return nil, false, nil
	}
	protectedKey := b.ackCustodyKey(peerID)
	legacyKey := b.key(peerID)
	cutoff := b.nowTime().Add(-maxMessageAge).UnixMilli()
	var (
		logical         []inboxMessage
		protectedPruned int
		legacyPruned    int
	)

	err := withRedisWatchRetryKeys(
		b.client,
		[]string{protectedKey, legacyKey},
		func(tx *redis.Tx) error {
			ctx := context.Background()
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
			logical = coalesceAndSortAckCustodyMessages(protectedMessages, legacyMessages)

			if equalStringSlices(protectedRaw, validProtectedRaw) &&
				equalStringSlices(legacyRaw, validLegacyRaw) {
				return nil
			}
			return redisReplaceLists(tx, map[string][]string{
				protectedKey: validProtectedRaw,
				legacyKey:    validLegacyRaw,
			})
		},
	)
	if err != nil {
		return nil, false, fmt.Errorf("retrieve ack custody pending: %w", err)
	}
	recordAckCustodyExpired(protectedPruned)
	recordInboxExpiredPruned(legacyPruned)

	pageSize := minInt(limit, len(logical))
	return append([]inboxMessage(nil), logical[:pageSize]...), len(logical) > pageSize, nil
}

func ackCustodyTargets(entryIDs []string) map[string]struct{} {
	targets := make(map[string]struct{}, len(entryIDs))
	for _, entryID := range entryIDs {
		if entryID != "" {
			targets[entryID] = struct{}{}
		}
	}
	return targets
}

func filterAckCustodyTargets(
	raw []string,
	messages []inboxMessage,
	targets map[string]struct{},
	found map[string]struct{},
) []string {
	remaining := make([]string, 0, len(raw))
	for i, message := range messages {
		if _, remove := targets[message.ID]; remove {
			found[message.ID] = struct{}{}
			continue
		}
		remaining = append(remaining, raw[i])
	}
	return remaining
}

func (b *redisInboxBackend) AckAckCustody(peerID string, entryIDs []string) (int, error) {
	targets := ackCustodyTargets(entryIDs)
	if len(targets) == 0 {
		return 0, nil
	}
	protectedKey := b.ackCustodyKey(peerID)
	legacyKey := b.key(peerID)
	cutoff := b.nowTime().Add(-maxMessageAge).UnixMilli()
	var (
		found           map[string]struct{}
		protectedPruned int
		legacyPruned    int
	)

	err := withRedisWatchRetryKeys(
		b.client,
		[]string{protectedKey, legacyKey},
		func(tx *redis.Tx) error {
			ctx := context.Background()
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
			found = make(map[string]struct{}, len(targets))
			remainingProtected := filterAckCustodyTargets(
				validProtectedRaw,
				protectedMessages,
				targets,
				found,
			)
			remainingLegacy := filterAckCustodyTargets(
				validLegacyRaw,
				legacyMessages,
				targets,
				found,
			)
			if equalStringSlices(protectedRaw, remainingProtected) &&
				equalStringSlices(legacyRaw, remainingLegacy) {
				return nil
			}
			return redisReplaceLists(tx, map[string][]string{
				protectedKey: remainingProtected,
				legacyKey:    remainingLegacy,
			})
		},
	)
	if err != nil {
		return 0, fmt.Errorf("ack custody: %w", err)
	}
	recordAckCustodyExpired(protectedPruned)
	recordInboxExpiredPruned(legacyPruned)
	return len(found), nil
}

func (b *redisInboxBackend) CountAckCustody(peerID string) int {
	rawEntries, err := b.client.LRange(
		context.Background(),
		b.ackCustodyKey(peerID),
		0,
		-1,
	).Result()
	if err == redis.Nil {
		return 0
	}
	if err != nil {
		log.Printf("[REDIS][ACK_CUSTODY] count failed: %v", err)
		return 0
	}
	_, validMessages := filterInboxEntries(
		rawEntries,
		b.nowTime().Add(-maxMessageAge).UnixMilli(),
	)
	return len(validMessages)
}

func (b *redisInboxBackend) AckCustodyStats() (totalPeers int, totalMessages int) {
	keys, err := scanRedisKeys(b.client, b.ackCustodyPattern())
	if err != nil {
		log.Printf("[REDIS][ACK_CUSTODY] stats scan failed: %v", err)
		return 0, 0
	}
	cutoff := b.nowTime().Add(-maxMessageAge).UnixMilli()
	for _, key := range keys {
		rawEntries, err := b.client.LRange(context.Background(), key, 0, -1).Result()
		if err == redis.Nil {
			continue
		}
		if err != nil {
			log.Printf("[REDIS][ACK_CUSTODY] stats read failed: %v", err)
			continue
		}
		_, validMessages := filterInboxEntries(rawEntries, cutoff)
		if len(validMessages) == 0 {
			continue
		}
		totalPeers++
		totalMessages += len(validMessages)
	}
	return totalPeers, totalMessages
}

func filterInboxEntries(rawEntries []string, cutoff int64) ([]string, []inboxMessage) {
	validRaw := make([]string, 0, len(rawEntries))
	validMessages := make([]inboxMessage, 0, len(rawEntries))

	for _, raw := range rawEntries {
		var message inboxMessage
		if err := json.Unmarshal([]byte(raw), &message); err != nil {
			log.Printf("[REDIS][INBOX] decode failed: %v", err)
			continue
		}
		if inboxMessageExpiredAtCutoff(message, cutoff) {
			continue
		}
		validRaw = append(validRaw, raw)
		validMessages = append(validMessages, message)
	}

	return validRaw, validMessages
}

func normalizeInboxEntries(
	rawEntries []string,
	cutoff int64,
) ([]string, []inboxMessage, int) {
	validRaw := make([]string, 0, len(rawEntries))
	validMessages := make([]inboxMessage, 0, len(rawEntries))
	pruned := 0

	for _, raw := range rawEntries {
		var message inboxMessage
		if err := json.Unmarshal([]byte(raw), &message); err != nil {
			log.Printf("[REDIS][INBOX] decode failed: %v", err)
			continue
		}
		if inboxMessageExpiredAtCutoff(message, cutoff) {
			pruned++
			continue
		}

		message = ensureInboxMessageID(message)
		payload, err := json.Marshal(message)
		if err != nil {
			log.Printf("[REDIS][INBOX] encode normalized message failed: %v", err)
			continue
		}

		validRaw = append(validRaw, string(payload))
		validMessages = append(validMessages, message)
	}

	return validRaw, validMessages, pruned
}

func inboxMessageExpiredAtCutoff(message inboxMessage, cutoff int64) bool {
	if message.ExpiresAtMs != 0 {
		return message.ExpiresAtMs <= cutoff+maxMessageAge.Milliseconds()
	}
	return message.Timestamp <= cutoff
}

func (b *redisGroupInboxBackend) key(groupId string) string {
	return b.prefix + "ginbox:" + encodeRedisComponent(groupId)
}

func (b *redisGroupInboxBackend) allPattern() string {
	return b.prefix + "ginbox:*"
}

func (b *redisGroupInboxBackend) sequenceKey() string {
	return b.prefix + "ginbox:idseq"
}

func (b *redisGroupInboxBackend) Store(groupId string, from string, message string) error {
	_, err := b.StoreWithRecipients(groupId, from, message, []string{from})
	return err
}

func (b *redisGroupInboxBackend) StoreWithRecipients(
	groupId string,
	from string,
	message string,
	recipientPeerIds []string,
) (GroupInboxStoreResult, error) {
	normalizedRecipients := normalizePeerIds(recipientPeerIds)
	if len(normalizedRecipients) == 0 {
		return "", fmt.Errorf("recipientPeerIds required")
	}

	ctx := context.Background()
	key := b.key(groupId)
	cutoff := time.Now().Add(-b.ttl).UnixMilli()
	messageID := extractMessageId(message)
	var result GroupInboxStoreResult
	var droppedByCap int

	err := withRedisWatchRetry(b.client, key, func(tx *redis.Tx) error {
		droppedByCap = 0
		rawEntries, err := tx.LRange(ctx, key, 0, -1).Result()
		if err == redis.Nil {
			rawEntries = nil
		} else if err != nil {
			return err
		}

		validRaw, validMessages, err := normalizeRedisGroupInboxRecords(rawEntries, cutoff)
		if err != nil {
			return err
		}

		if messageID != "" {
			for i := range validMessages {
				if extractMessageId(validMessages[i].Message) != messageID {
					continue
				}
				if validMessages[i].From != from || validMessages[i].Message != message {
					return fmt.Errorf("conflicting group inbox messageId %q", messageID)
				}

				validMessages[i].RecipientPeerIds = mergePeerIds(
					validMessages[i].RecipientPeerIds,
					normalizedRecipients,
				)
				nextRaw, err := encodeRedisGroupInboxRecords(validMessages)
				if err != nil {
					return err
				}
				if !stringSlicesEqual(rawEntries, nextRaw) {
					if err := redisReplaceList(tx, key, nextRaw); err != nil {
						return err
					}
				}
				result = GroupInboxStoreResultDuplicate
				return nil
			}
		}

		id, err := tx.Incr(ctx, b.sequenceKey()).Result()
		if err != nil {
			return fmt.Errorf("allocate group inbox id: %w", err)
		}

		record := redisGroupRecord{
			From:             from,
			Message:          message,
			Timestamp:        time.Now().UnixMilli(),
			ID:               fmt.Sprintf("%d", id),
			RecipientPeerIds: normalizedRecipients,
		}
		payload, err := json.Marshal(record)
		if err != nil {
			return fmt.Errorf("encode group inbox message: %w", err)
		}

		values := append([]string(nil), validRaw...)
		values = append(values, string(payload))
		if len(values) > b.maxPerGroup {
			droppedByCap = len(values) - b.maxPerGroup
			values = values[len(values)-b.maxPerGroup:]
		}
		if err := redisReplaceList(tx, key, values); err != nil {
			return err
		}
		result = GroupInboxStoreResultStored
		return nil
	})
	if err != nil {
		return "", fmt.Errorf("store redis group inbox message: %w", err)
	}
	// Increment the cap-eviction counter only after the transaction commits, so
	// optimistic-retry replays of the closure do not double-count (finding 06
	// Phase 2). droppedByCap reflects the final (successful) attempt.
	if droppedByCap > 0 {
		groupInboxCappedCounter.Add(float64(droppedByCap))
	}
	return result, nil
}

func (b *redisGroupInboxBackend) RetrieveSince(groupId string, sinceTimestamp int64) []groupInboxMessage {
	rawEntries, err := b.client.LRange(context.Background(), b.key(groupId), 0, -1).Result()
	if err == redis.Nil {
		return nil
	}
	if err != nil {
		log.Printf("[REDIS][GROUP_INBOX] retrieve since failed: %v", err)
		return nil
	}

	cutoff := time.Now().Add(-b.ttl).UnixMilli()
	decoded := decodeGroupInboxEntries(rawEntries)
	results := make([]groupInboxMessage, 0, len(decoded))
	for _, message := range decoded {
		if message.Timestamp <= cutoff {
			continue
		}
		if sinceTimestamp > 0 && message.Timestamp <= sinceTimestamp {
			continue
		}
		results = append(results, message)
	}

	return results
}

func (b *redisGroupInboxBackend) RetrieveCursor(groupId string, cursor string, limit int) ([]groupInboxMessage, string, []groupInboxHistoryGap) {
	if limit <= 0 {
		return nil, "", nil
	}

	rawEntries, err := b.client.LRange(context.Background(), b.key(groupId), 0, -1).Result()
	if err == redis.Nil {
		return nil, "", nil
	}
	if err != nil {
		log.Printf("[REDIS][GROUP_INBOX] retrieve cursor failed: %v", err)
		return nil, "", nil
	}

	decoded := decodeGroupInboxEntries(rawEntries)
	if len(decoded) == 0 {
		return nil, "", nil
	}

	startIdx := 0
	cursorFound := cursor == ""
	if cursor != "" {
		for i, message := range decoded {
			if message.ID == cursor {
				startIdx = i + 1
				cursorFound = true
				break
			}
		}
		if !cursorFound {
			startIdx = 0
		}
	}

	cutoff := time.Now().Add(-b.ttl).UnixMilli()
	result := make([]groupInboxMessage, 0, minInt(limit, len(decoded)))
	lastReturnedIndex := -1

	for i := startIdx; i < len(decoded) && len(result) < limit; i++ {
		message := decoded[i]
		if message.Timestamp <= cutoff {
			continue
		}
		result = append(result, message)
		lastReturnedIndex = i
	}

	if len(result) == 0 {
		return nil, "", nil
	}

	nextCursor := ""
	for i := lastReturnedIndex + 1; i < len(decoded); i++ {
		if decoded[i].Timestamp > cutoff {
			nextCursor = result[len(result)-1].ID
			break
		}
	}

	return result, nextCursor, buildGroupInboxHistoryGaps(groupId, cursor, cursorFound, result)
}

func (b *redisGroupInboxBackend) Prune() {
	keys, err := scanRedisKeys(b.client, b.allPattern())
	if err != nil {
		log.Printf("[REDIS][GROUP_INBOX] prune scan failed: %v", err)
		return
	}

	for _, key := range keys {
		if key == b.sequenceKey() {
			continue
		}
		if err := b.pruneKey(key); err != nil {
			log.Printf("[REDIS][GROUP_INBOX] prune key failed: %v", err)
		}
	}
}

func (b *redisGroupInboxBackend) Stats() (groups int, totalMessages int) {
	keys, err := scanRedisKeys(b.client, b.allPattern())
	if err != nil {
		log.Printf("[REDIS][GROUP_INBOX] stats scan failed: %v", err)
		return 0, 0
	}

	cutoff := time.Now().Add(-b.ttl).UnixMilli()
	for _, key := range keys {
		if key == b.sequenceKey() {
			continue
		}

		rawEntries, err := b.client.LRange(context.Background(), key, 0, -1).Result()
		if err == redis.Nil {
			continue
		}
		if err != nil {
			log.Printf("[REDIS][GROUP_INBOX] stats read failed: %v", err)
			continue
		}

		count := 0
		for _, message := range decodeGroupInboxEntries(rawEntries) {
			if message.Timestamp > cutoff {
				count++
			}
		}
		if count == 0 {
			continue
		}
		groups++
		totalMessages += count
	}

	return groups, totalMessages
}

func (b *redisGroupInboxBackend) pruneKey(key string) error {
	cutoff := time.Now().Add(-b.ttl).UnixMilli()

	return withRedisWatchRetry(b.client, key, func(tx *redis.Tx) error {
		rawEntries, err := tx.LRange(context.Background(), key, 0, -1).Result()
		if err == redis.Nil {
			return nil
		}
		if err != nil {
			return err
		}

		validRaw := make([]string, 0, len(rawEntries))
		for _, raw := range rawEntries {
			var message redisGroupRecord
			if err := json.Unmarshal([]byte(raw), &message); err != nil {
				log.Printf("[REDIS][GROUP_INBOX] decode failed during prune: %v", err)
				continue
			}
			if message.Timestamp <= cutoff {
				continue
			}
			validRaw = append(validRaw, raw)
		}

		if len(validRaw) == len(rawEntries) {
			return nil
		}
		return redisReplaceList(tx, key, validRaw)
	})
}

func normalizeRedisGroupInboxRecords(rawEntries []string, cutoff int64) ([]string, []groupInboxMessage, error) {
	validRaw := make([]string, 0, len(rawEntries))
	validMessages := make([]groupInboxMessage, 0, len(rawEntries))

	for _, raw := range rawEntries {
		var record redisGroupRecord
		if err := json.Unmarshal([]byte(raw), &record); err != nil {
			log.Printf("[REDIS][GROUP_INBOX] decode failed during normalize: %v", err)
			continue
		}
		if record.Timestamp <= cutoff {
			continue
		}

		message := groupInboxMessage{
			From:             record.From,
			Message:          record.Message,
			Timestamp:        record.Timestamp,
			ID:               record.ID,
			RecipientPeerIds: normalizePeerIds(record.RecipientPeerIds),
		}
		normalizedRaw, err := encodeRedisGroupInboxRecord(message)
		if err != nil {
			return nil, nil, err
		}
		validRaw = append(validRaw, normalizedRaw)
		validMessages = append(validMessages, message)
	}

	return validRaw, validMessages, nil
}

func encodeRedisGroupInboxRecords(messages []groupInboxMessage) ([]string, error) {
	raw := make([]string, 0, len(messages))
	for _, message := range messages {
		encoded, err := encodeRedisGroupInboxRecord(message)
		if err != nil {
			return nil, err
		}
		raw = append(raw, encoded)
	}
	return raw, nil
}

func encodeRedisGroupInboxRecord(message groupInboxMessage) (string, error) {
	record := redisGroupRecord{
		From:             message.From,
		Message:          message.Message,
		Timestamp:        message.Timestamp,
		ID:               message.ID,
		RecipientPeerIds: normalizePeerIds(message.RecipientPeerIds),
	}
	payload, err := json.Marshal(record)
	if err != nil {
		return "", fmt.Errorf("encode group inbox message: %w", err)
	}
	return string(payload), nil
}

func decodeGroupInboxEntries(rawEntries []string) []groupInboxMessage {
	results := make([]groupInboxMessage, 0, len(rawEntries))

	for _, raw := range rawEntries {
		var message redisGroupRecord
		if err := json.Unmarshal([]byte(raw), &message); err != nil {
			log.Printf("[REDIS][GROUP_INBOX] decode failed: %v", err)
			continue
		}
		results = append(results, groupInboxMessage{
			From:             message.From,
			Message:          message.Message,
			Timestamp:        message.Timestamp,
			ID:               message.ID,
			RecipientPeerIds: normalizePeerIds(message.RecipientPeerIds),
		})
	}

	return results
}

func (b *redisPushTokenBackend) key(peerId string) string {
	return b.prefix + "push:" + encodeRedisComponent(peerId)
}

func (b *redisPushTokenBackend) allPattern() string {
	return b.prefix + "push:*"
}

func (b *redisPushTokenBackend) RegisterToken(
	peerId string,
	token string,
	platform string,
	capabilities ...string,
) error {
	entry := tokenEntry{
		Token:        token,
		Platform:     platform,
		Capabilities: normalizeCapabilities(capabilities),
		UpdatedAt:    time.Now(),
	}

	payload, err := json.Marshal(entry)
	if err != nil {
		return fmt.Errorf("encode push token: %w", err)
	}

	if err := b.client.Set(context.Background(), b.key(peerId), payload, 0).Err(); err != nil {
		return fmt.Errorf("store push token: %w", err)
	}
	return nil
}

func (b *redisPushTokenBackend) UnregisterToken(peerId string) {
	if err := b.client.Del(context.Background(), b.key(peerId)).Err(); err != nil {
		log.Printf("[REDIS][PUSH] unregister failed: %v", err)
	}
}

func (b *redisPushTokenBackend) LookupToken(peerId string) *tokenEntry {
	payload, err := b.client.Get(context.Background(), b.key(peerId)).Bytes()
	if err == redis.Nil {
		return nil
	}
	if err != nil {
		log.Printf("[REDIS][PUSH] lookup failed: %v", err)
		return nil
	}

	var entry tokenEntry
	if err := json.Unmarshal(payload, &entry); err != nil {
		log.Printf("[REDIS][PUSH] decode failed: %v", err)
		return nil
	}

	return &entry
}

func (b *redisPushTokenBackend) TokenCount() int {
	keys, err := scanRedisKeys(b.client, b.allPattern())
	if err != nil {
		log.Printf("[REDIS][PUSH] count scan failed: %v", err)
		return 0
	}
	return len(keys)
}

func (b *redisPushTokenBackend) PlatformCounts() map[string]int {
	keys, err := scanRedisKeys(b.client, b.allPattern())
	if err != nil {
		log.Printf("[REDIS][PUSH] platform counts scan failed: %v", err)
		return nil
	}
	counts := make(map[string]int)
	ctx := context.Background()
	for _, key := range keys {
		payload, err := b.client.Get(ctx, key).Bytes()
		if err != nil {
			continue
		}
		var entry tokenEntry
		if err := json.Unmarshal(payload, &entry); err != nil {
			continue
		}
		counts[entry.Platform]++
	}
	return counts
}

func minInt(a int, b int) int {
	if a < b {
		return a
	}
	return b
}
