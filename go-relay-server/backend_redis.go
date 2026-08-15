package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"slices"
	"sort"
	"strings"
	"sync"
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

	configMu    sync.Mutex
	vaultConfig *pushTokenVaultConfig
	entropy     io.Reader
	now         func() time.Time

	// Test-only interleaving seams. Nil is the production behavior.
	legacyMutationBeforeCommit         func() error
	legacyResolveAfterRead             func()
	encryptedDeleteBeforeCommit        func() error
	encryptedResolveAfterDirectoryRead func()
	migrationBeforeCutover             func(revision uint64) error
	migrationVerificationAfterScans    func()
	startupValidationBetweenSnapshots  func()
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
	return &redisPushTokenBackend{
		client:  client,
		prefix:  prefix,
		entropy: rand.Reader,
		now:     time.Now,
	}
}

func encodeRedisComponent(value string) string {
	return base64.RawURLEncoding.EncodeToString([]byte(value))
}

func scanRedisKeys(client *redis.Client, pattern string) ([]string, error) {
	ctx := context.Background()
	var (
		cursor uint64
		keys   []string
		seen   = make(map[string]struct{})
	)

	for {
		batch, next, err := client.Scan(ctx, cursor, pattern, 100).Result()
		if err != nil {
			return nil, err
		}
		for _, key := range batch {
			if _, duplicate := seen[key]; duplicate {
				continue
			}
			seen[key] = struct{}{}
			keys = append(keys, key)
		}
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
				messageKey := extractStoredAckCustodyDedupeKey(
					protectedMessages[i].Message,
					protectedMessages[i].From,
					toPeerID,
				)
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
					if extractStoredAckCustodyDedupeKey(
						legacyMessages[i].Message,
						legacyMessages[i].From,
						toPeerID,
					) != dedupeKey {
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
	return escapeRedisMatchLiteral(b.prefix+"push:") + "*"
}

func (b *redisPushTokenBackend) markerKey() string {
	return b.prefix + "push-token-state"
}

func (b *redisPushTokenBackend) directoryKey(peerID string) string {
	return b.prefix + "push-token-directory:" + encodeRedisComponent(peerID)
}

func (b *redisPushTokenBackend) directoryPattern() string {
	return escapeRedisMatchLiteral(b.prefix+"push-token-directory:") + "*"
}

func (b *redisPushTokenBackend) vaultKey(handle string) string {
	return b.prefix + "push-token-vault:" + handle
}

func (b *redisPushTokenBackend) vaultPattern() string {
	return escapeRedisMatchLiteral(b.prefix+"push-token-vault:") + "*"
}

func escapeRedisMatchLiteral(value string) string {
	replacer := strings.NewReplacer(
		`\`, `\\`,
		`*`, `\*`,
		`?`, `\?`,
		`[`, `\[`,
		`]`, `\]`,
	)
	return replacer.Replace(value)
}

type pushTokenRedisGetter interface {
	Get(context.Context, string) *redis.StringCmd
}

var errPushTokenStateChanged = errors.New("push token state changed during operation")
var errPushTokenRetrySnapshot = errors.New("push token snapshot changed during operation")

func optionalRedisBytes(getter pushTokenRedisGetter, key string) ([]byte, error) {
	payload, err := getter.Get(context.Background(), key).Bytes()
	if err == redis.Nil {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return payload, nil
}

func (b *redisPushTokenBackend) readState(getter pushTokenRedisGetter) (pushTokenStateMarker, error) {
	payload, err := optionalRedisBytes(getter, b.markerKey())
	if err != nil {
		return pushTokenStateMarker{}, fmt.Errorf("read push token state: %w", err)
	}
	if payload == nil {
		return pushTokenStateMarker{State: pushTokenStateAbsent}, nil
	}
	marker, err := decodePushTokenStateMarker(payload)
	if err != nil {
		return pushTokenStateMarker{}, fmt.Errorf("decode push token state: %w", err)
	}
	return marker, nil
}

func samePushTokenState(left, right pushTokenStateMarker) bool {
	return left.State == right.State &&
		left.Revision == right.Revision &&
		left.FleetReceiptSHA256 == right.FleetReceiptSHA256
}

func nextPushTokenMarkerRevision(marker pushTokenStateMarker) (pushTokenStateMarker, []byte, error) {
	if marker.State != pushTokenStateMigrating {
		return pushTokenStateMarker{}, nil, errors.New("push token revision requires migrating state")
	}
	if marker.Revision == math.MaxUint64 {
		return pushTokenStateMarker{}, nil, errors.New("push token migration revision overflow")
	}
	marker.Revision++
	payload, err := encodePushTokenStateMarker(marker)
	if err != nil {
		return pushTokenStateMarker{}, nil, err
	}
	return marker, payload, nil
}

func decodeLegacyPushTokenRecord(payload []byte) (tokenEntry, error) {
	fields, err := decodePushTokenJSONObject(payload, nil, pushTokenJSONMaxBytes)
	if err != nil {
		return tokenEntry{}, errors.New("decode legacy push token record")
	}
	for field := range fields {
		switch field {
		case "Token", "Platform", "Capabilities", "UpdatedAt":
		default:
			return tokenEntry{}, errors.New("decode legacy push token record")
		}
	}
	for _, required := range []string{"Token", "Platform", "UpdatedAt"} {
		if _, ok := fields[required]; !ok {
			return tokenEntry{}, errors.New("decode legacy push token record")
		}
	}
	var entry tokenEntry
	if decodePushTokenJSONField(fields["Token"], &entry.Token) != nil ||
		decodePushTokenJSONField(fields["Platform"], &entry.Platform) != nil ||
		decodePushTokenJSONField(fields["UpdatedAt"], &entry.UpdatedAt) != nil {
		return tokenEntry{}, errors.New("decode legacy push token record")
	}
	if capabilities, ok := fields["Capabilities"]; ok {
		if bytes.Equal(bytes.TrimSpace(capabilities), []byte("null")) ||
			decodePushTokenJSONField(capabilities, &entry.Capabilities) != nil {
			return tokenEntry{}, errors.New("decode legacy push token record")
		}
	}
	if entry.Token == "" || entry.Platform == "" {
		return tokenEntry{}, errors.New("legacy push token record is incomplete")
	}
	entry.Capabilities = canonicalPushTokenVaultCapabilities(entry.Capabilities)
	if err := validateCanonicalPushCapabilities(entry.Capabilities); err != nil {
		return tokenEntry{}, errors.New("decode legacy push token record")
	}
	return entry, nil
}

func encodeLegacyPushTokenRecord(entry tokenEntry) ([]byte, error) {
	entry.Capabilities = canonicalPushTokenVaultCapabilities(entry.Capabilities)
	payload, err := json.Marshal(entry)
	if err != nil {
		return nil, fmt.Errorf("encode push token: %w", err)
	}
	return payload, nil
}

func pushRouteLegacyDigestBytes(payload []byte) [32]byte {
	digest, err := parsePushTokenLegacyDigest(pushTokenLegacyDigest(payload))
	if err != nil {
		panic("push token legacy digest invariant")
	}
	return digest
}

func pushRouteLegacyDigestHex(route pushRouteLease) string {
	return fmt.Sprintf("%x", route.legacyDigest[:])
}

func (b *redisPushTokenBackend) peerFromLegacyKey(key string) (string, error) {
	return decodePushTokenPeerComponent(key, b.prefix+"push:")
}

func (b *redisPushTokenBackend) peerFromDirectoryKey(key string) (string, error) {
	return decodePushTokenPeerComponent(key, b.prefix+"push-token-directory:")
}

func decodePushTokenPeerComponent(key, prefix string) (string, error) {
	if !strings.HasPrefix(key, prefix) {
		return "", errors.New("push token lookup key is outside its namespace")
	}
	component := strings.TrimPrefix(key, prefix)
	decoded, err := base64.RawURLEncoding.Strict().DecodeString(component)
	if err != nil || len(decoded) == 0 || encodeRedisComponent(string(decoded)) != component {
		return "", errors.New("push token lookup key has an invalid peer component")
	}
	return string(decoded), nil
}

func (b *redisPushTokenBackend) directoryKeyFromLegacyKey(key string) (string, string, error) {
	peerID, err := b.peerFromLegacyKey(key)
	if err != nil {
		return "", "", err
	}
	return b.directoryKey(peerID), peerID, nil
}

func uniqueRedisKeys(keys ...string) []string {
	seen := make(map[string]struct{}, len(keys))
	unique := make([]string, 0, len(keys))
	for _, key := range keys {
		if key == "" {
			continue
		}
		if _, exists := seen[key]; exists {
			continue
		}
		seen[key] = struct{}{}
		unique = append(unique, key)
	}
	sort.Strings(unique)
	return unique
}

func (b *redisPushTokenBackend) ensureVaultConfig() (*pushTokenVaultConfig, error) {
	b.configMu.Lock()
	defer b.configMu.Unlock()
	if b.vaultConfig != nil {
		if err := b.vaultConfig.validate(); err != nil {
			return nil, err
		}
		return b.vaultConfig, nil
	}
	config, err := loadPushTokenVaultConfigFromEnv()
	if err != nil {
		return nil, err
	}
	b.vaultConfig = config
	return config, nil
}

func (b *redisPushTokenBackend) nowTime() time.Time {
	if b != nil && b.now != nil {
		return b.now()
	}
	return time.Now()
}

func (b *redisPushTokenBackend) RegisterToken(
	peerId string,
	token string,
	platform string,
	capabilities ...string,
) error {
	if peerId == "" || token == "" || platform == "" {
		return errors.New("push token registration is incomplete")
	}
	entry := tokenEntry{
		Token:        token,
		Platform:     platform,
		Capabilities: canonicalPushTokenVaultCapabilities(capabilities),
		UpdatedAt:    b.nowTime(),
	}
	payload, err := encodeLegacyPushTokenRecord(entry)
	if err != nil {
		return err
	}

	for range redisWatchRetries {
		marker, err := b.readState(b.client)
		if err != nil {
			return fmt.Errorf("store push token: %w", err)
		}
		if marker.State == pushTokenStateEncrypted {
			return b.registerEncrypted(peerId, token, platform, entry.Capabilities)
		}
		err = b.registerLegacy(peerId, payload)
		if errors.Is(err, errPushTokenStateChanged) {
			continue
		}
		return err
	}
	return fmt.Errorf("store push token: %w", redis.TxFailedErr)
}

func (b *redisPushTokenBackend) registerLegacy(peerID string, payload []byte) error {
	legacyKey := b.key(peerID)
	err := withRedisWatchRetryKeys(
		b.client,
		[]string{b.markerKey(), legacyKey},
		func(tx *redis.Tx) error {
			marker, err := b.readState(tx)
			if err != nil {
				return err
			}
			if marker.State == pushTokenStateEncrypted {
				return errPushTokenStateChanged
			}
			var markerPayload []byte
			if marker.State == pushTokenStateMigrating {
				_, markerPayload, err = nextPushTokenMarkerRevision(marker)
				if err != nil {
					return err
				}
			}
			if b.legacyMutationBeforeCommit != nil {
				if err := b.legacyMutationBeforeCommit(); err != nil {
					return err
				}
			}
			_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
				pipe.Set(context.Background(), legacyKey, payload, 0)
				if markerPayload != nil {
					pipe.Set(context.Background(), b.markerKey(), markerPayload, 0)
				}
				return nil
			})
			return err
		},
	)
	if err != nil {
		if errors.Is(err, errPushTokenStateChanged) {
			return err
		}
		return fmt.Errorf("store push token: %w", err)
	}
	return nil
}

func (b *redisPushTokenBackend) UnregisterToken(peerId string) error {
	if peerId == "" {
		return errors.New("push token unregister peer is empty")
	}
	for range redisWatchRetries {
		marker, err := b.readState(b.client)
		if err != nil {
			return err
		}
		if marker.State == pushTokenStateEncrypted {
			return b.unregisterEncrypted(peerId)
		}
		err = b.unregisterLegacy(peerId)
		if errors.Is(err, errPushTokenStateChanged) {
			continue
		}
		return err
	}
	return fmt.Errorf("delete push token: %w", redis.TxFailedErr)
}

func (b *redisPushTokenBackend) unregisterLegacy(peerID string) error {
	legacyKey := b.key(peerID)
	err := withRedisWatchRetryKeys(
		b.client,
		[]string{b.markerKey(), legacyKey},
		func(tx *redis.Tx) error {
			marker, err := b.readState(tx)
			if err != nil {
				return err
			}
			if marker.State == pushTokenStateEncrypted {
				return errPushTokenStateChanged
			}
			var markerPayload []byte
			if marker.State == pushTokenStateMigrating {
				_, markerPayload, err = nextPushTokenMarkerRevision(marker)
				if err != nil {
					return err
				}
			}
			if b.legacyMutationBeforeCommit != nil {
				if err := b.legacyMutationBeforeCommit(); err != nil {
					return err
				}
			}
			_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
				pipe.Del(context.Background(), legacyKey)
				if markerPayload != nil {
					pipe.Set(context.Background(), b.markerKey(), markerPayload, 0)
				}
				return nil
			})
			return err
		},
	)
	if err != nil {
		if errors.Is(err, errPushTokenStateChanged) {
			return err
		}
		return fmt.Errorf("delete push token: %w", err)
	}
	return nil
}

func (b *redisPushTokenBackend) LookupRoute(peerId string) (*pushRouteLease, error) {
	if peerId == "" {
		return nil, errors.New("push route peer is empty")
	}
	for range redisWatchRetries {
		before, err := b.readState(b.client)
		if err != nil {
			return nil, err
		}
		var route *pushRouteLease
		switch before.State {
		case pushTokenStateAbsent, pushTokenStateMigrating:
			route, err = b.lookupLegacyRoute(peerId)
		case pushTokenStateEncrypted:
			route, err = b.lookupEncryptedRoute(peerId)
		default:
			err = errors.New("push token state is invalid")
		}
		if err != nil {
			if errors.Is(err, ErrPushRouteStale) {
				continue
			}
			return nil, err
		}
		after, err := b.readState(b.client)
		if err != nil {
			return nil, err
		}
		if samePushTokenState(before, after) {
			return route, nil
		}
	}
	return nil, fmt.Errorf("lookup push route: %w", redis.TxFailedErr)
}

func (b *redisPushTokenBackend) lookupLegacyRoute(peerID string) (*pushRouteLease, error) {
	legacyKey := b.key(peerID)
	payload, err := optionalRedisBytes(b.client, legacyKey)
	if err != nil {
		return nil, fmt.Errorf("read legacy push route: %w", err)
	}
	if payload == nil {
		return nil, nil
	}
	entry, err := decodeLegacyPushTokenRecord(payload)
	if err != nil {
		return nil, err
	}
	return &pushRouteLease{
		Capabilities: append([]string(nil), entry.Capabilities...),
		lookupKey:    legacyKey,
		legacyDigest: pushRouteLegacyDigestBytes(payload),
	}, nil
}

func (b *redisPushTokenBackend) lookupEncryptedRoute(peerID string) (*pushRouteLease, error) {
	directoryKey := b.directoryKey(peerID)
	payload, err := optionalRedisBytes(b.client, directoryKey)
	if err != nil {
		return nil, fmt.Errorf("read push route directory: %w", err)
	}
	if payload == nil {
		return nil, nil
	}
	record, err := decodePushTokenDirectoryRecord(payload)
	if err != nil {
		return nil, err
	}
	route := &pushRouteLease{
		Handle:       record.Handle,
		Generation:   record.Generation,
		Capabilities: append([]string(nil), record.Capabilities...),
		lookupKey:    directoryKey,
	}
	if _, err := b.resolveEncryptedRoute(*route, directoryKey, peerID); err != nil {
		return nil, err
	}
	return route, nil
}

func (b *redisPushTokenBackend) ResolveRoute(route pushRouteLease) (*resolvedPushTarget, error) {
	if route.Generation == 0 {
		for range redisWatchRetries {
			before, err := b.readState(b.client)
			if err != nil {
				return nil, err
			}
			switch before.State {
			case pushTokenStateEncrypted:
				directoryKey, peerID, err := b.directoryKeyFromLegacyKey(route.lookupKey)
				if err != nil {
					return nil, ErrPushRouteStale
				}
				return b.resolveEncryptedRoute(route, directoryKey, peerID)
			case pushTokenStateAbsent, pushTokenStateMigrating:
				target, resolveErr := b.resolveLegacyRoute(route)
				after, stateErr := b.readState(b.client)
				if stateErr != nil {
					return nil, stateErr
				}
				if samePushTokenState(before, after) {
					return target, resolveErr
				}
			default:
				return nil, errors.New("push token state is invalid")
			}
		}
		return nil, fmt.Errorf("resolve legacy push route: %w", redis.TxFailedErr)
	}
	marker, err := b.readState(b.client)
	if err != nil {
		return nil, err
	}
	if marker.State != pushTokenStateEncrypted {
		return nil, ErrPushRouteStale
	}
	peerID, err := b.peerFromDirectoryKey(route.lookupKey)
	if err != nil {
		return nil, ErrPushRouteStale
	}
	return b.resolveEncryptedRoute(route, route.lookupKey, peerID)
}

func (b *redisPushTokenBackend) resolveLegacyRoute(route pushRouteLease) (*resolvedPushTarget, error) {
	if route.lookupKey == "" || route.legacyDigest == ([32]byte{}) {
		return nil, ErrPushRouteStale
	}
	if _, err := b.peerFromLegacyKey(route.lookupKey); err != nil {
		return nil, ErrPushRouteStale
	}
	payload, err := optionalRedisBytes(b.client, route.lookupKey)
	if err != nil {
		return nil, fmt.Errorf("read legacy push route: %w", err)
	}
	if payload == nil || pushRouteLegacyDigestBytes(payload) != route.legacyDigest {
		return nil, ErrPushRouteStale
	}
	if b.legacyResolveAfterRead != nil {
		b.legacyResolveAfterRead()
	}
	entry, err := decodeLegacyPushTokenRecord(payload)
	if err != nil {
		return nil, err
	}
	if !slices.Equal(entry.Capabilities, canonicalPushTokenVaultCapabilities(route.Capabilities)) {
		return nil, ErrPushRouteStale
	}
	return &resolvedPushTarget{
		Route:    copyPushRouteLease(route),
		Token:    entry.Token,
		Platform: entry.Platform,
	}, nil
}

func encryptedDirectoryMatchesRoute(record pushTokenDirectoryRecord, route pushRouteLease) bool {
	capabilities := canonicalPushTokenVaultCapabilities(route.Capabilities)
	if !slices.Equal(record.Capabilities, capabilities) {
		return false
	}
	if route.Generation == 0 {
		return record.SourceLegacyDigest != "" &&
			record.SourceLegacyDigest == pushRouteLegacyDigestHex(route)
	}
	return route.Handle != "" && route.Generation > 0 &&
		record.Handle == route.Handle && record.Generation == route.Generation
}

func (b *redisPushTokenBackend) resolveEncryptedRoute(
	route pushRouteLease,
	directoryKey string,
	peerID string,
) (*resolvedPushTarget, error) {
	config, err := b.ensureVaultConfig()
	if err != nil {
		return nil, err
	}
	for range redisWatchRetries {
		directoryPayload, err := optionalRedisBytes(b.client, directoryKey)
		if err != nil {
			return nil, fmt.Errorf("read push route directory: %w", err)
		}
		if directoryPayload == nil {
			return nil, ErrPushRouteStale
		}
		directory, err := decodePushTokenDirectoryRecord(directoryPayload)
		if err != nil {
			return nil, err
		}
		if !encryptedDirectoryMatchesRoute(directory, route) {
			return nil, ErrPushRouteStale
		}
		if b.encryptedResolveAfterDirectoryRead != nil {
			b.encryptedResolveAfterDirectoryRead()
		}
		vaultKey := b.vaultKey(directory.Handle)
		vaultPayload, err := optionalRedisBytes(b.client, vaultKey)
		if err != nil {
			return nil, fmt.Errorf("read push token vault: %w", err)
		}
		if vaultPayload == nil {
			currentDirectory, readErr := optionalRedisBytes(b.client, directoryKey)
			if readErr != nil {
				return nil, readErr
			}
			if !bytes.Equal(currentDirectory, directoryPayload) {
				continue
			}
			return nil, errors.New("push token vault row is missing")
		}
		vault, err := decodePushTokenVaultEnvelope(vaultPayload)
		if err != nil {
			currentDirectory, readErr := optionalRedisBytes(b.client, directoryKey)
			if readErr != nil {
				return nil, readErr
			}
			if !bytes.Equal(currentDirectory, directoryPayload) {
				continue
			}
			return nil, err
		}
		token, err := config.openPushToken(peerID, directory, vault)
		if err != nil {
			currentDirectory, readErr := optionalRedisBytes(b.client, directoryKey)
			if readErr != nil {
				return nil, readErr
			}
			if !bytes.Equal(currentDirectory, directoryPayload) {
				continue
			}
			return nil, err
		}
		currentDirectory, err := optionalRedisBytes(b.client, directoryKey)
		if err != nil {
			return nil, err
		}
		if !bytes.Equal(currentDirectory, directoryPayload) {
			continue
		}
		if vault.KeyID != config.activeKeyID {
			if err := b.rewrapEncryptedRoute(
				config,
				peerID,
				directoryKey,
				directoryPayload,
				directory,
				vaultKey,
				vaultPayload,
				token,
			); err != nil {
				return nil, err
			}
		}
		return &resolvedPushTarget{
			Route:    copyPushRouteLease(route),
			Token:    token,
			Platform: directory.Platform,
		}, nil
	}
	return nil, ErrPushRouteStale
}

func (b *redisPushTokenBackend) rewrapEncryptedRoute(
	config *pushTokenVaultConfig,
	peerID string,
	directoryKey string,
	directoryPayload []byte,
	directory pushTokenDirectoryRecord,
	vaultKey string,
	vaultPayload []byte,
	token string,
) error {
	rewrapped, err := config.sealPushToken(peerID, directory, token, b.entropy)
	if err != nil {
		return err
	}
	rewrappedPayload, err := encodePushTokenVaultEnvelope(rewrapped)
	if err != nil {
		return err
	}
	return withRedisWatchRetryKeys(
		b.client,
		uniqueRedisKeys(b.markerKey(), directoryKey, vaultKey),
		func(tx *redis.Tx) error {
			marker, err := b.readState(tx)
			if err != nil {
				return err
			}
			if marker.State != pushTokenStateEncrypted {
				return ErrPushRouteStale
			}
			currentDirectory, err := optionalRedisBytes(tx, directoryKey)
			if err != nil {
				return err
			}
			currentVault, err := optionalRedisBytes(tx, vaultKey)
			if err != nil {
				return err
			}
			if !bytes.Equal(currentDirectory, directoryPayload) ||
				!bytes.Equal(currentVault, vaultPayload) {
				return ErrPushRouteStale
			}
			_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
				pipe.Set(context.Background(), vaultKey, rewrappedPayload, 0)
				return nil
			})
			return err
		},
	)
}

func (b *redisPushTokenBackend) registerEncrypted(
	peerID string,
	token string,
	platform string,
	capabilities []string,
) error {
	config, err := b.ensureVaultConfig()
	if err != nil {
		return err
	}
	capabilities = canonicalPushTokenVaultCapabilities(capabilities)
	directoryKey := b.directoryKey(peerID)

	for range redisWatchRetries * 2 {
		marker, err := b.readState(b.client)
		if err != nil {
			return err
		}
		if marker.State != pushTokenStateEncrypted {
			return errPushTokenStateChanged
		}

		currentDirectoryPayload, err := optionalRedisBytes(b.client, directoryKey)
		if err != nil {
			return fmt.Errorf("read current push route directory: %w", err)
		}
		var (
			currentDirectory pushTokenDirectoryRecord
			currentVaultKey  string
			currentVaultRaw  []byte
			rotate           = currentDirectoryPayload == nil
		)
		if currentDirectoryPayload != nil {
			currentDirectory, err = decodePushTokenDirectoryRecord(currentDirectoryPayload)
			if err != nil {
				return err
			}
			currentVaultKey = b.vaultKey(currentDirectory.Handle)
			currentVaultRaw, err = optionalRedisBytes(b.client, currentVaultKey)
			if err != nil {
				return fmt.Errorf("read current push token vault: %w", err)
			}
			if currentDirectory.ProviderEnvironment != config.providerEnvironment {
				rotate = true
			} else {
				if currentVaultRaw == nil {
					return errors.New("current push token vault row is missing")
				}
				currentVault, err := decodePushTokenVaultEnvelope(currentVaultRaw)
				if err != nil {
					return err
				}
				currentToken, err := config.openPushToken(peerID, currentDirectory, currentVault)
				if err != nil {
					return err
				}
				rotate = currentToken != token || currentDirectory.Platform != platform
			}
		}

		handle := currentDirectory.Handle
		generation := currentDirectory.Generation
		if rotate {
			handle, err = newOpaquePushHandle(b.entropy)
			if err != nil {
				return fmt.Errorf("create push route handle: %w", err)
			}
			if currentDirectoryPayload == nil {
				generation = 1
			} else {
				if generation == math.MaxUint64 {
					return errors.New("push route generation overflow")
				}
				generation++
			}
		}
		directory := pushTokenDirectoryRecord{
			Handle:              handle,
			Generation:          generation,
			Platform:            platform,
			Capabilities:        append([]string(nil), capabilities...),
			ProviderEnvironment: config.providerEnvironment,
			SourceLegacyDigest:  "",
		}
		directoryPayload, err := encodePushTokenDirectoryRecord(directory)
		if err != nil {
			return err
		}
		vault, err := config.sealPushToken(peerID, directory, token, b.entropy)
		if err != nil {
			return err
		}
		vaultPayload, err := encodePushTokenVaultEnvelope(vault)
		if err != nil {
			return err
		}
		newVaultKey := b.vaultKey(directory.Handle)

		err = withRedisWatchRetryKeys(
			b.client,
			uniqueRedisKeys(
				b.markerKey(),
				directoryKey,
				currentVaultKey,
				newVaultKey,
			),
			func(tx *redis.Tx) error {
				actualMarker, err := b.readState(tx)
				if err != nil {
					return err
				}
				if actualMarker.State != pushTokenStateEncrypted {
					return errPushTokenStateChanged
				}
				actualDirectory, err := optionalRedisBytes(tx, directoryKey)
				if err != nil {
					return err
				}
				if !bytes.Equal(actualDirectory, currentDirectoryPayload) {
					return errPushTokenRetrySnapshot
				}
				if currentVaultKey != "" {
					actualVault, err := optionalRedisBytes(tx, currentVaultKey)
					if err != nil {
						return err
					}
					if !bytes.Equal(actualVault, currentVaultRaw) {
						return errPushTokenRetrySnapshot
					}
				}
				if newVaultKey != currentVaultKey {
					collision, err := optionalRedisBytes(tx, newVaultKey)
					if err != nil {
						return err
					}
					if collision != nil {
						return errPushTokenRetrySnapshot
					}
				}
				_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
					pipe.Set(context.Background(), newVaultKey, vaultPayload, 0)
					pipe.Set(context.Background(), directoryKey, directoryPayload, 0)
					if currentVaultKey != "" && currentVaultKey != newVaultKey {
						pipe.Del(context.Background(), currentVaultKey)
					}
					return nil
				})
				return err
			},
		)
		if errors.Is(err, errPushTokenRetrySnapshot) ||
			errors.Is(err, redis.TxFailedErr) {
			continue
		}
		if err != nil {
			return fmt.Errorf("store encrypted push route: %w", err)
		}
		return nil
	}
	return fmt.Errorf("store encrypted push route: %w", redis.TxFailedErr)
}

func (b *redisPushTokenBackend) unregisterEncrypted(peerID string) error {
	directoryKey := b.directoryKey(peerID)
	for range redisWatchRetries * 2 {
		marker, err := b.readState(b.client)
		if err != nil {
			return err
		}
		if marker.State != pushTokenStateEncrypted {
			return errPushTokenStateChanged
		}
		directoryPayload, err := optionalRedisBytes(b.client, directoryKey)
		if err != nil {
			return fmt.Errorf("read push route for delete: %w", err)
		}
		if directoryPayload == nil {
			return nil
		}
		directory, err := decodePushTokenDirectoryRecord(directoryPayload)
		if err != nil {
			return err
		}
		vaultKey := b.vaultKey(directory.Handle)
		err = withRedisWatchRetryKeys(
			b.client,
			uniqueRedisKeys(b.markerKey(), directoryKey, vaultKey),
			func(tx *redis.Tx) error {
				actualMarker, err := b.readState(tx)
				if err != nil {
					return err
				}
				if actualMarker.State != pushTokenStateEncrypted {
					return errPushTokenStateChanged
				}
				actualDirectory, err := optionalRedisBytes(tx, directoryKey)
				if err != nil {
					return err
				}
				if !bytes.Equal(actualDirectory, directoryPayload) {
					return errPushTokenRetrySnapshot
				}
				if b.encryptedDeleteBeforeCommit != nil {
					if err := b.encryptedDeleteBeforeCommit(); err != nil {
						return err
					}
				}
				_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
					pipe.Del(context.Background(), directoryKey, vaultKey)
					return nil
				})
				return err
			},
		)
		if errors.Is(err, errPushTokenRetrySnapshot) || errors.Is(err, redis.TxFailedErr) {
			continue
		}
		if err != nil {
			return fmt.Errorf("delete encrypted push route: %w", err)
		}
		return nil
	}
	return fmt.Errorf("delete encrypted push route: %w", redis.TxFailedErr)
}

func (b *redisPushTokenBackend) revokeEncrypted(route pushRouteLease) (bool, error) {
	var (
		directoryKey string
		peerID       string
		err          error
	)
	if route.Generation == 0 {
		directoryKey, peerID, err = b.directoryKeyFromLegacyKey(route.lookupKey)
	} else {
		directoryKey = route.lookupKey
		peerID, err = b.peerFromDirectoryKey(directoryKey)
	}
	if err != nil || peerID == "" {
		return false, nil
	}

	directoryPayload, err := optionalRedisBytes(b.client, directoryKey)
	if err != nil {
		return false, fmt.Errorf("read push route for conditional revoke: %w", err)
	}
	if directoryPayload == nil {
		return false, nil
	}
	directory, err := decodePushTokenDirectoryRecord(directoryPayload)
	if err != nil {
		return false, err
	}
	if !encryptedDirectoryMatchesRoute(directory, route) {
		return false, nil
	}
	vaultKey := b.vaultKey(directory.Handle)
	revoked := false
	err = withRedisWatchRetryKeys(
		b.client,
		uniqueRedisKeys(b.markerKey(), directoryKey, vaultKey),
		func(tx *redis.Tx) error {
			revoked = false
			marker, err := b.readState(tx)
			if err != nil {
				return err
			}
			if marker.State != pushTokenStateEncrypted {
				return nil
			}
			actualPayload, err := optionalRedisBytes(tx, directoryKey)
			if err != nil {
				return err
			}
			if actualPayload == nil {
				return nil
			}
			actual, err := decodePushTokenDirectoryRecord(actualPayload)
			if err != nil {
				return err
			}
			if !encryptedDirectoryMatchesRoute(actual, route) {
				return nil
			}
			actualVaultKey := b.vaultKey(actual.Handle)
			if actualVaultKey != vaultKey {
				return nil
			}
			_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
				pipe.Del(context.Background(), directoryKey, vaultKey)
				return nil
			})
			if err == nil {
				revoked = true
			}
			return err
		},
	)
	if err != nil {
		return false, fmt.Errorf("conditionally revoke encrypted push route: %w", err)
	}
	return revoked, nil
}

func (b *redisPushTokenBackend) RevokeIfCurrent(route pushRouteLease) (bool, error) {
	marker, err := b.readState(b.client)
	if err != nil {
		return false, err
	}
	if marker.State == pushTokenStateEncrypted {
		return b.revokeEncrypted(route)
	}
	if route.Generation != 0 {
		return false, nil
	}
	return b.revokeLegacy(route)
}

func (b *redisPushTokenBackend) revokeLegacy(route pushRouteLease) (bool, error) {
	if route.lookupKey == "" || route.legacyDigest == ([32]byte{}) {
		return false, nil
	}
	if _, err := b.peerFromLegacyKey(route.lookupKey); err != nil {
		return false, nil
	}
	revoked := false
	err := withRedisWatchRetryKeys(
		b.client,
		[]string{b.markerKey(), route.lookupKey},
		func(tx *redis.Tx) error {
			revoked = false
			marker, err := b.readState(tx)
			if err != nil {
				return err
			}
			if marker.State == pushTokenStateEncrypted {
				return errPushTokenStateChanged
			}
			payload, err := optionalRedisBytes(tx, route.lookupKey)
			if err != nil {
				return err
			}
			if payload == nil || pushRouteLegacyDigestBytes(payload) != route.legacyDigest {
				return nil
			}
			var markerPayload []byte
			if marker.State == pushTokenStateMigrating {
				_, markerPayload, err = nextPushTokenMarkerRevision(marker)
				if err != nil {
					return err
				}
			}
			if b.legacyMutationBeforeCommit != nil {
				if err := b.legacyMutationBeforeCommit(); err != nil {
					return err
				}
			}
			_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
				pipe.Del(context.Background(), route.lookupKey)
				if markerPayload != nil {
					pipe.Set(context.Background(), b.markerKey(), markerPayload, 0)
				}
				return nil
			})
			if err == nil {
				revoked = true
			}
			return err
		},
	)
	if errors.Is(err, errPushTokenStateChanged) {
		return b.revokeEncrypted(route)
	}
	if err != nil {
		return false, fmt.Errorf("conditionally revoke legacy push route: %w", err)
	}
	return revoked, nil
}

func (b *redisPushTokenBackend) TokenCount() int {
	marker, err := b.readState(b.client)
	if err != nil {
		log.Printf("[REDIS][PUSH] outcome=count_state_read_failed")
		return 0
	}
	pattern := b.allPattern()
	exactPrefix := b.prefix + "push:"
	if marker.State == pushTokenStateEncrypted {
		pattern = b.directoryPattern()
		exactPrefix = b.prefix + "push-token-directory:"
	}
	keys, err := scanRedisKeys(b.client, pattern)
	if err != nil {
		log.Printf("[REDIS][PUSH] outcome=count_scan_failed")
		return 0
	}
	count := 0
	for _, key := range keys {
		if strings.HasPrefix(key, exactPrefix) && len(key) > len(exactPrefix) {
			count++
		}
	}
	return count
}

func (b *redisPushTokenBackend) PlatformCounts() map[string]int {
	marker, err := b.readState(b.client)
	if err != nil {
		log.Printf("[REDIS][PUSH] outcome=platform_count_state_read_failed")
		return nil
	}
	pattern := b.allPattern()
	exactPrefix := b.prefix + "push:"
	encrypted := false
	if marker.State == pushTokenStateEncrypted {
		pattern = b.directoryPattern()
		exactPrefix = b.prefix + "push-token-directory:"
		encrypted = true
	}
	keys, err := scanRedisKeys(b.client, pattern)
	if err != nil {
		log.Printf("[REDIS][PUSH] outcome=platform_count_scan_failed")
		return nil
	}
	counts := make(map[string]int)
	for _, key := range keys {
		if !strings.HasPrefix(key, exactPrefix) || len(key) <= len(exactPrefix) {
			continue
		}
		payload, err := optionalRedisBytes(b.client, key)
		if err != nil || payload == nil {
			continue
		}
		if encrypted {
			record, decodeErr := decodePushTokenDirectoryRecord(payload)
			if decodeErr == nil {
				counts[record.Platform]++
			}
			continue
		}
		entry, decodeErr := decodeLegacyPushTokenRecord(payload)
		if decodeErr == nil {
			counts[entry.Platform]++
		}
	}
	return counts
}

func (b *redisPushTokenBackend) Migrate(fleetReceiptSHA256 string) error {
	if err := validateFleetReceiptSHA256(fleetReceiptSHA256); err != nil {
		return err
	}
	config, err := b.ensureVaultConfig()
	if err != nil {
		return err
	}
	if err := b.admitPushTokenMigration(fleetReceiptSHA256); err != nil {
		return err
	}

	for attempt := 0; attempt < 256; attempt++ {
		marker, err := b.readState(b.client)
		if err != nil {
			return err
		}
		if marker.FleetReceiptSHA256 != fleetReceiptSHA256 {
			return errors.New("push token migration receipt does not match durable state")
		}
		if marker.State == pushTokenStateEncrypted {
			return nil
		}
		if marker.State != pushTokenStateMigrating {
			return errors.New("push token migration state is invalid")
		}

		if err := b.reconcilePushTokenMigration(marker, config); err != nil {
			if errors.Is(err, errPushTokenRetrySnapshot) ||
				errors.Is(err, redis.TxFailedErr) {
				continue
			}
			return err
		}
		if err := b.verifyPushTokenMigrationSnapshot(marker, config); err != nil {
			if errors.Is(err, errPushTokenRetrySnapshot) {
				continue
			}
			return err
		}
		if b.migrationBeforeCutover != nil {
			if err := b.migrationBeforeCutover(marker.Revision); err != nil {
				return err
			}
		}
		if err := b.cutOverPushTokenMigration(marker); err != nil {
			if errors.Is(err, errPushTokenRetrySnapshot) ||
				errors.Is(err, redis.TxFailedErr) {
				continue
			}
			return err
		}
		return nil
	}
	return errors.New("push token migration did not reach a stable revision")
}

func (b *redisPushTokenBackend) admitPushTokenMigration(fleetReceiptSHA256 string) error {
	markerKey := b.markerKey()
	return withRedisWatchRetryKeys(b.client, []string{markerKey}, func(tx *redis.Tx) error {
		marker, err := b.readState(tx)
		if err != nil {
			return err
		}
		switch marker.State {
		case pushTokenStateAbsent:
			marker = pushTokenStateMarker{
				State:              pushTokenStateMigrating,
				Revision:           0,
				FleetReceiptSHA256: fleetReceiptSHA256,
			}
			payload, err := encodePushTokenStateMarker(marker)
			if err != nil {
				return err
			}
			_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
				pipe.Set(context.Background(), markerKey, payload, 0)
				return nil
			})
			return err
		case pushTokenStateMigrating, pushTokenStateEncrypted:
			if marker.FleetReceiptSHA256 != fleetReceiptSHA256 {
				return errors.New("push token migration receipt does not match durable state")
			}
			return nil
		default:
			return errors.New("push token migration state is invalid")
		}
	})
}

func (b *redisPushTokenBackend) exactKeys(pattern, exactPrefix string) ([]string, error) {
	keys, err := scanRedisKeys(b.client, pattern)
	if err != nil {
		return nil, err
	}
	exact := keys[:0]
	for _, key := range keys {
		if strings.HasPrefix(key, exactPrefix) && len(key) > len(exactPrefix) {
			exact = append(exact, key)
		}
	}
	return exact, nil
}

func (b *redisPushTokenBackend) reconcilePushTokenMigration(
	marker pushTokenStateMarker,
	config *pushTokenVaultConfig,
) error {
	legacyKeys, err := b.exactKeys(b.allPattern(), b.prefix+"push:")
	if err != nil {
		return fmt.Errorf("scan legacy push token rows: %w", err)
	}
	for _, legacyKey := range legacyKeys {
		payload, err := optionalRedisBytes(b.client, legacyKey)
		if err != nil {
			return err
		}
		if payload == nil {
			continue
		}
		if err := b.reconcilePushTokenMigrationRow(marker, config, legacyKey, payload); err != nil {
			return err
		}
	}

	directoryKeys, err := b.exactKeys(
		b.directoryPattern(),
		b.prefix+"push-token-directory:",
	)
	if err != nil {
		return fmt.Errorf("scan push token directories: %w", err)
	}
	for _, directoryKey := range directoryKeys {
		peerID, err := b.peerFromDirectoryKey(directoryKey)
		if err != nil {
			return err
		}
		legacyKey := b.key(peerID)
		legacyPayload, err := optionalRedisBytes(b.client, legacyKey)
		if err != nil {
			return err
		}
		if legacyPayload != nil {
			continue
		}
		if err := b.deleteMigratingDirectoryIfLegacyAbsent(marker, legacyKey, directoryKey); err != nil {
			return err
		}
	}
	return b.deleteUnreferencedMigratingVaults(marker)
}

func (b *redisPushTokenBackend) reconcilePushTokenMigrationRow(
	marker pushTokenStateMarker,
	config *pushTokenVaultConfig,
	legacyKey string,
	legacyPayload []byte,
) error {
	peerID, err := b.peerFromLegacyKey(legacyKey)
	if err != nil {
		return err
	}
	legacyEntry, err := decodeLegacyPushTokenRecord(legacyPayload)
	if err != nil {
		return err
	}
	directoryKey := b.directoryKey(peerID)
	currentDirectoryPayload, err := optionalRedisBytes(b.client, directoryKey)
	if err != nil {
		return err
	}
	var (
		currentDirectory pushTokenDirectoryRecord
		currentVaultKey  string
		currentVaultRaw  []byte
		rotate           = currentDirectoryPayload == nil
	)
	if currentDirectoryPayload != nil {
		currentDirectory, err = decodePushTokenDirectoryRecord(currentDirectoryPayload)
		if err != nil {
			return err
		}
		if currentDirectory.ProviderEnvironment != config.providerEnvironment {
			return errors.New("migrating push token directory environment does not match configuration")
		}
		currentVaultKey = b.vaultKey(currentDirectory.Handle)
		currentVaultRaw, err = optionalRedisBytes(b.client, currentVaultKey)
		if err != nil {
			return err
		}
		if currentVaultRaw == nil {
			return errors.New("migrating push token vault row is missing")
		}
		currentVault, err := decodePushTokenVaultEnvelope(currentVaultRaw)
		if err != nil {
			return err
		}
		currentToken, err := config.openPushToken(peerID, currentDirectory, currentVault)
		if err != nil {
			return err
		}
		rotate = currentToken != legacyEntry.Token ||
			currentDirectory.Platform != legacyEntry.Platform
	}

	handle := currentDirectory.Handle
	generation := currentDirectory.Generation
	if rotate {
		handle, err = newOpaquePushHandle(b.entropy)
		if err != nil {
			return err
		}
		if currentDirectoryPayload == nil {
			generation = 1
		} else {
			if generation == math.MaxUint64 {
				return errors.New("push route generation overflow")
			}
			generation++
		}
	}
	directory := pushTokenDirectoryRecord{
		Handle:              handle,
		Generation:          generation,
		Platform:            legacyEntry.Platform,
		Capabilities:        append([]string(nil), legacyEntry.Capabilities...),
		ProviderEnvironment: config.providerEnvironment,
		SourceLegacyDigest:  pushTokenLegacyDigest(legacyPayload),
	}
	directoryPayload, err := encodePushTokenDirectoryRecord(directory)
	if err != nil {
		return err
	}
	vault, err := config.sealPushToken(peerID, directory, legacyEntry.Token, b.entropy)
	if err != nil {
		return err
	}
	vaultPayload, err := encodePushTokenVaultEnvelope(vault)
	if err != nil {
		return err
	}
	newVaultKey := b.vaultKey(directory.Handle)

	return withRedisWatchRetryKeys(
		b.client,
		uniqueRedisKeys(
			b.markerKey(),
			legacyKey,
			directoryKey,
			currentVaultKey,
			newVaultKey,
		),
		func(tx *redis.Tx) error {
			actualMarker, err := b.readState(tx)
			if err != nil {
				return err
			}
			if !samePushTokenState(actualMarker, marker) ||
				actualMarker.State != pushTokenStateMigrating {
				return errPushTokenRetrySnapshot
			}
			actualLegacy, err := optionalRedisBytes(tx, legacyKey)
			if err != nil {
				return err
			}
			actualDirectory, err := optionalRedisBytes(tx, directoryKey)
			if err != nil {
				return err
			}
			if !bytes.Equal(actualLegacy, legacyPayload) ||
				!bytes.Equal(actualDirectory, currentDirectoryPayload) {
				return errPushTokenRetrySnapshot
			}
			if currentVaultKey != "" {
				actualVault, err := optionalRedisBytes(tx, currentVaultKey)
				if err != nil {
					return err
				}
				if !bytes.Equal(actualVault, currentVaultRaw) {
					return errPushTokenRetrySnapshot
				}
			}
			if newVaultKey != currentVaultKey {
				collision, err := optionalRedisBytes(tx, newVaultKey)
				if err != nil {
					return err
				}
				if collision != nil {
					return errPushTokenRetrySnapshot
				}
			}
			_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
				pipe.Set(context.Background(), newVaultKey, vaultPayload, 0)
				pipe.Set(context.Background(), directoryKey, directoryPayload, 0)
				if currentVaultKey != "" && currentVaultKey != newVaultKey {
					pipe.Del(context.Background(), currentVaultKey)
				}
				return nil
			})
			return err
		},
	)
}

func (b *redisPushTokenBackend) deleteMigratingDirectoryIfLegacyAbsent(
	marker pushTokenStateMarker,
	legacyKey string,
	directoryKey string,
) error {
	directoryPayload, err := optionalRedisBytes(b.client, directoryKey)
	if err != nil || directoryPayload == nil {
		return err
	}
	directory, err := decodePushTokenDirectoryRecord(directoryPayload)
	if err != nil {
		return err
	}
	vaultKey := b.vaultKey(directory.Handle)
	return withRedisWatchRetryKeys(
		b.client,
		uniqueRedisKeys(b.markerKey(), legacyKey, directoryKey, vaultKey),
		func(tx *redis.Tx) error {
			actualMarker, err := b.readState(tx)
			if err != nil {
				return err
			}
			if !samePushTokenState(actualMarker, marker) ||
				actualMarker.State != pushTokenStateMigrating {
				return errPushTokenRetrySnapshot
			}
			legacyPayload, err := optionalRedisBytes(tx, legacyKey)
			if err != nil {
				return err
			}
			actualDirectory, err := optionalRedisBytes(tx, directoryKey)
			if err != nil {
				return err
			}
			if legacyPayload != nil || !bytes.Equal(actualDirectory, directoryPayload) {
				return errPushTokenRetrySnapshot
			}
			_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
				pipe.Del(context.Background(), directoryKey, vaultKey)
				return nil
			})
			return err
		},
	)
}

func (b *redisPushTokenBackend) deleteUnreferencedMigratingVaults(
	marker pushTokenStateMarker,
) error {
	directoryKeys, err := b.exactKeys(
		b.directoryPattern(),
		b.prefix+"push-token-directory:",
	)
	if err != nil {
		return err
	}
	referenced := make(map[string]struct{}, len(directoryKeys))
	for _, directoryKey := range directoryKeys {
		payload, err := optionalRedisBytes(b.client, directoryKey)
		if err != nil || payload == nil {
			return err
		}
		directory, err := decodePushTokenDirectoryRecord(payload)
		if err != nil {
			return err
		}
		referenced[b.vaultKey(directory.Handle)] = struct{}{}
	}
	vaultKeys, err := b.exactKeys(b.vaultPattern(), b.prefix+"push-token-vault:")
	if err != nil {
		return err
	}
	for _, vaultKey := range vaultKeys {
		if _, ok := referenced[vaultKey]; ok {
			continue
		}
		if err := withRedisWatchRetryKeys(
			b.client,
			[]string{b.markerKey(), vaultKey},
			func(tx *redis.Tx) error {
				actualMarker, err := b.readState(tx)
				if err != nil {
					return err
				}
				if !samePushTokenState(actualMarker, marker) ||
					actualMarker.State != pushTokenStateMigrating {
					return errPushTokenRetrySnapshot
				}
				_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
					pipe.Del(context.Background(), vaultKey)
					return nil
				})
				return err
			},
		); err != nil {
			return err
		}
	}
	return nil
}

func (b *redisPushTokenBackend) pushTokenMigrationSnapshotFault(
	marker pushTokenStateMarker,
	fault error,
) error {
	current, err := b.readState(b.client)
	if err != nil {
		return err
	}
	if !samePushTokenState(current, marker) {
		return errPushTokenRetrySnapshot
	}
	return fault
}

func (b *redisPushTokenBackend) verifyPushTokenMigrationSnapshot(
	marker pushTokenStateMarker,
	config *pushTokenVaultConfig,
) error {
	before, err := b.readState(b.client)
	if err != nil {
		return err
	}
	if !samePushTokenState(before, marker) || before.State != pushTokenStateMigrating {
		return errPushTokenRetrySnapshot
	}
	legacyKeys, err := b.exactKeys(b.allPattern(), b.prefix+"push:")
	if err != nil {
		return err
	}
	directoryKeys, err := b.exactKeys(
		b.directoryPattern(),
		b.prefix+"push-token-directory:",
	)
	if err != nil {
		return err
	}
	vaultKeys, err := b.exactKeys(b.vaultPattern(), b.prefix+"push-token-vault:")
	if err != nil {
		return err
	}
	if b.migrationVerificationAfterScans != nil {
		b.migrationVerificationAfterScans()
	}
	if len(legacyKeys) != len(directoryKeys) || len(directoryKeys) != len(vaultKeys) {
		return b.pushTokenMigrationSnapshotFault(
			marker,
			errors.New("push token migration rows are not an exact bijection"),
		)
	}
	referencedVaults := make(map[string]struct{}, len(vaultKeys))
	for _, legacyKey := range legacyKeys {
		peerID, err := b.peerFromLegacyKey(legacyKey)
		if err != nil {
			return b.pushTokenMigrationSnapshotFault(marker, err)
		}
		legacyPayload, err := optionalRedisBytes(b.client, legacyKey)
		if err != nil {
			return err
		}
		if legacyPayload == nil {
			return b.pushTokenMigrationSnapshotFault(
				marker,
				errors.New("push token migration legacy row is missing"),
			)
		}
		legacyEntry, err := decodeLegacyPushTokenRecord(legacyPayload)
		if err != nil {
			return b.pushTokenMigrationSnapshotFault(marker, err)
		}
		directoryPayload, err := optionalRedisBytes(b.client, b.directoryKey(peerID))
		if err != nil {
			return err
		}
		if directoryPayload == nil {
			return b.pushTokenMigrationSnapshotFault(
				marker,
				errors.New("push token migration directory row is missing"),
			)
		}
		directory, err := decodePushTokenDirectoryRecord(directoryPayload)
		if err != nil {
			return b.pushTokenMigrationSnapshotFault(marker, err)
		}
		if directory.SourceLegacyDigest != pushTokenLegacyDigest(legacyPayload) ||
			directory.ProviderEnvironment != config.providerEnvironment ||
			directory.Platform != legacyEntry.Platform ||
			!slices.Equal(directory.Capabilities, legacyEntry.Capabilities) {
			return b.pushTokenMigrationSnapshotFault(
				marker,
				errors.New("push token migration directory does not match legacy authority"),
			)
		}
		vaultKey := b.vaultKey(directory.Handle)
		vaultPayload, err := optionalRedisBytes(b.client, vaultKey)
		if err != nil {
			return err
		}
		if vaultPayload == nil {
			return b.pushTokenMigrationSnapshotFault(
				marker,
				errors.New("push token migration vault row is missing"),
			)
		}
		vault, err := decodePushTokenVaultEnvelope(vaultPayload)
		if err != nil {
			return b.pushTokenMigrationSnapshotFault(marker, err)
		}
		resolved, err := config.openPushToken(peerID, directory, vault)
		if err != nil || resolved != legacyEntry.Token {
			return b.pushTokenMigrationSnapshotFault(
				marker,
				errors.New("push token migration vault does not match legacy authority"),
			)
		}
		referencedVaults[vaultKey] = struct{}{}
	}
	for _, vaultKey := range vaultKeys {
		if _, ok := referencedVaults[vaultKey]; !ok {
			return b.pushTokenMigrationSnapshotFault(
				marker,
				errors.New("push token migration contains an orphan vault row"),
			)
		}
	}
	after, err := b.readState(b.client)
	if err != nil {
		return err
	}
	if !samePushTokenState(after, marker) {
		return errPushTokenRetrySnapshot
	}
	return nil
}

func (b *redisPushTokenBackend) cutOverPushTokenMigration(marker pushTokenStateMarker) error {
	return withRedisWatchRetryKeys(
		b.client,
		[]string{b.markerKey()},
		func(tx *redis.Tx) error {
			actual, err := b.readState(tx)
			if err != nil {
				return err
			}
			if !samePushTokenState(actual, marker) || actual.State != pushTokenStateMigrating {
				return errPushTokenRetrySnapshot
			}
			encrypted := actual
			encrypted.State = pushTokenStateEncrypted
			payload, err := encodePushTokenStateMarker(encrypted)
			if err != nil {
				return err
			}
			_, err = tx.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
				pipe.Set(context.Background(), b.markerKey(), payload, 0)
				return nil
			})
			return err
		},
	)
}

func (b *redisPushTokenBackend) CleanupLegacy() error {
	marker, err := b.readState(b.client)
	if err != nil {
		return err
	}
	if marker.State != pushTokenStateEncrypted {
		return errors.New("legacy push token cleanup requires encrypted state")
	}
	keys, err := b.exactKeys(b.allPattern(), b.prefix+"push:")
	if err != nil {
		return fmt.Errorf("scan legacy push token rows for cleanup: %w", err)
	}
	if len(keys) == 0 {
		return nil
	}
	arguments := make([]string, len(keys))
	copy(arguments, keys)
	if err := b.client.Del(context.Background(), arguments...).Err(); err != nil {
		return fmt.Errorf("delete legacy push token rows: %w", err)
	}
	return nil
}

type pushTokenStartupSnapshot struct {
	marker      pushTokenStateMarker
	directories map[string][]byte
	vaults      map[string][]byte
}

func (b *redisPushTokenBackend) collectPushTokenStartupSnapshot() (pushTokenStartupSnapshot, error) {
	marker, err := b.readState(b.client)
	if err != nil {
		return pushTokenStartupSnapshot{}, err
	}
	snapshot := pushTokenStartupSnapshot{
		marker:      marker,
		directories: make(map[string][]byte),
		vaults:      make(map[string][]byte),
	}
	directoryKeys, err := b.exactKeys(
		b.directoryPattern(),
		b.prefix+"push-token-directory:",
	)
	if err != nil {
		return pushTokenStartupSnapshot{}, err
	}
	for _, key := range directoryKeys {
		payload, err := optionalRedisBytes(b.client, key)
		if err != nil {
			return pushTokenStartupSnapshot{}, err
		}
		snapshot.directories[key] = payload
	}
	if b.startupValidationBetweenSnapshots != nil {
		b.startupValidationBetweenSnapshots()
	}
	vaultKeys, err := b.exactKeys(b.vaultPattern(), b.prefix+"push-token-vault:")
	if err != nil {
		return pushTokenStartupSnapshot{}, err
	}
	for _, key := range vaultKeys {
		payload, err := optionalRedisBytes(b.client, key)
		if err != nil {
			return pushTokenStartupSnapshot{}, err
		}
		snapshot.vaults[key] = payload
	}
	return snapshot, nil
}
func (b *redisPushTokenBackend) validatePushTokenStartupSnapshot(
	snapshot pushTokenStartupSnapshot,
	config *pushTokenVaultConfig,
) error {
	if snapshot.marker.State == pushTokenStateAbsent {
		return nil
	}
	for directoryKey, directoryPayload := range snapshot.directories {
		if _, err := b.peerFromDirectoryKey(directoryKey); err != nil {
			return err
		}
		if directoryPayload == nil {
			continue
		}
		if _, err := decodePushTokenDirectoryRecord(directoryPayload); err != nil {
			return err
		}
	}
	for vaultKey, payload := range snapshot.vaults {
		handle := strings.TrimPrefix(vaultKey, b.prefix+"push-token-vault:")
		if validateOpaquePushHandle(handle) != nil {
			return errors.New("push token vault key contains an invalid handle")
		}
		if payload == nil {
			continue
		}
		vault, err := decodePushTokenVaultEnvelope(payload)
		if err != nil {
			return err
		}
		if _, ok := config.keys[vault.KeyID]; !ok {
			return errors.New("push token vault references an unretained key")
		}
	}
	return nil
}

func (b *redisPushTokenBackend) ValidateStartup() error {
	marker, err := b.readState(b.client)
	if err != nil {
		return err
	}
	if marker.State == pushTokenStateAbsent {
		return nil
	}
	config, err := b.ensureVaultConfig()
	if err != nil {
		return err
	}
	snapshot, err := b.collectPushTokenStartupSnapshot()
	if err != nil {
		return err
	}
	return b.validatePushTokenStartupSnapshot(snapshot, config)
}

func minInt(a int, b int) int {
	if a < b {
		return a
	}
	return b
}
