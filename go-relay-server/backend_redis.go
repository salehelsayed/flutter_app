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
	}
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
	ctx := context.Background()
	var lastErr error

	for range redisWatchRetries {
		err := client.Watch(ctx, fn, key)
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
	From      string `json:"from"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
	ID        string `json:"id"`
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

func (b *redisInboxBackend) Store(toPeerId string, entry inboxMessage) bool {
	entry = ensureInboxMessageID(entry)
	payload, err := json.Marshal(entry)
	if err != nil {
		log.Printf("[REDIS][INBOX] encode failed: %v", err)
		return false
	}

	key := b.key(toPeerId)
	cutoff := time.Now().Add(-maxMessageAge).UnixMilli()
	msgID := extractMessageId(entry.Message)
	stored := false

	err = withRedisWatchRetry(b.client, key, func(tx *redis.Tx) error {
		rawEntries, err := tx.LRange(context.Background(), key, 0, -1).Result()
		if err == redis.Nil {
			rawEntries = nil
		} else if err != nil {
			return err
		}

		validRaw, validMessages := normalizeInboxEntries(rawEntries, cutoff)

		if msgID != "" {
			for _, message := range validMessages {
				if extractMessageId(message.Message) == msgID {
					if len(validRaw) != len(rawEntries) {
						return redisReplaceList(tx, key, validRaw)
					}
					stored = false
					return nil
				}
			}
		}

		values := append([]string(nil), validRaw...)
		values = append(values, string(payload))
		if len(values) > b.maxPerPeer {
			values = values[len(values)-b.maxPerPeer:]
		}

		stored = true
		return redisReplaceList(tx, key, values)
	})
	if err != nil {
		log.Printf("[REDIS][INBOX] store failed: %v", err)
		return false
	}
	return stored
}

func (b *redisInboxBackend) Retrieve(peerId string, limit int) ([]inboxMessage, bool) {
	if limit <= 0 {
		return nil, false
	}

	key := b.key(peerId)
	cutoff := time.Now().Add(-maxMessageAge).UnixMilli()

	var (
		result  []inboxMessage
		hasMore bool
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

		validRaw, validMessages := normalizeInboxEntries(rawEntries, cutoff)
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

	return result, hasMore
}

func (b *redisInboxBackend) RetrievePending(peerId string, limit int) ([]inboxMessage, bool) {
	if limit <= 0 {
		return nil, false
	}

	key := b.key(peerId)
	cutoff := time.Now().Add(-maxMessageAge).UnixMilli()

	var (
		result  []inboxMessage
		hasMore bool
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

		validRaw, validMessages := normalizeInboxEntries(rawEntries, cutoff)
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
	cutoff := time.Now().Add(-maxMessageAge).UnixMilli()
	removed := 0

	err := withRedisWatchRetry(b.client, key, func(tx *redis.Tx) error {
		rawEntries, err := tx.LRange(context.Background(), key, 0, -1).Result()
		if err == redis.Nil {
			removed = 0
			return nil
		}
		if err != nil {
			return err
		}

		validRaw, validMessages := normalizeInboxEntries(rawEntries, cutoff)
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

	_, validMessages := filterInboxEntries(rawEntries, time.Now().Add(-maxMessageAge).UnixMilli())
	return len(validMessages)
}

func (b *redisInboxBackend) Stats() (totalPeers int, totalMessages int) {
	keys, err := scanRedisKeys(b.client, b.allPattern())
	if err != nil {
		log.Printf("[REDIS][INBOX] stats scan failed: %v", err)
		return 0, 0
	}

	cutoff := time.Now().Add(-maxMessageAge).UnixMilli()
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

func filterInboxEntries(rawEntries []string, cutoff int64) ([]string, []inboxMessage) {
	validRaw := make([]string, 0, len(rawEntries))
	validMessages := make([]inboxMessage, 0, len(rawEntries))

	for _, raw := range rawEntries {
		var message inboxMessage
		if err := json.Unmarshal([]byte(raw), &message); err != nil {
			log.Printf("[REDIS][INBOX] decode failed: %v", err)
			continue
		}
		if message.Timestamp <= cutoff {
			continue
		}
		validRaw = append(validRaw, raw)
		validMessages = append(validMessages, message)
	}

	return validRaw, validMessages
}

func normalizeInboxEntries(rawEntries []string, cutoff int64) ([]string, []inboxMessage) {
	validRaw := make([]string, 0, len(rawEntries))
	validMessages := make([]inboxMessage, 0, len(rawEntries))

	for _, raw := range rawEntries {
		var message inboxMessage
		if err := json.Unmarshal([]byte(raw), &message); err != nil {
			log.Printf("[REDIS][INBOX] decode failed: %v", err)
			continue
		}
		if message.Timestamp <= cutoff {
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

	return validRaw, validMessages
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
	ctx := context.Background()
	id, err := b.client.Incr(ctx, b.sequenceKey()).Result()
	if err != nil {
		return fmt.Errorf("allocate group inbox id: %w", err)
	}

	record := redisGroupRecord{
		From:      from,
		Message:   message,
		Timestamp: time.Now().UnixMilli(),
		ID:        fmt.Sprintf("%d", id),
	}

	payload, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("encode group inbox message: %w", err)
	}

	if _, err := b.client.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
		pipe.RPush(ctx, b.key(groupId), payload)
		pipe.LTrim(ctx, b.key(groupId), int64(-b.maxPerGroup), -1)
		return nil
	}); err != nil {
		return fmt.Errorf("store group inbox message: %w", err)
	}

	return nil
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

func (b *redisGroupInboxBackend) RetrieveCursor(groupId string, cursor string, limit int) ([]groupInboxMessage, string) {
	if limit <= 0 {
		return nil, ""
	}

	rawEntries, err := b.client.LRange(context.Background(), b.key(groupId), 0, -1).Result()
	if err == redis.Nil {
		return nil, ""
	}
	if err != nil {
		log.Printf("[REDIS][GROUP_INBOX] retrieve cursor failed: %v", err)
		return nil, ""
	}

	decoded := decodeGroupInboxEntries(rawEntries)
	if len(decoded) == 0 {
		return nil, ""
	}

	startIdx := 0
	if cursor != "" {
		found := false
		for i, message := range decoded {
			if message.ID == cursor {
				startIdx = i + 1
				found = true
				break
			}
		}
		if !found {
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
		return nil, ""
	}

	nextCursor := ""
	for i := lastReturnedIndex + 1; i < len(decoded); i++ {
		if decoded[i].Timestamp > cutoff {
			nextCursor = result[len(result)-1].ID
			break
		}
	}

	return result, nextCursor
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

func decodeGroupInboxEntries(rawEntries []string) []groupInboxMessage {
	results := make([]groupInboxMessage, 0, len(rawEntries))

	for _, raw := range rawEntries {
		var message redisGroupRecord
		if err := json.Unmarshal([]byte(raw), &message); err != nil {
			log.Printf("[REDIS][GROUP_INBOX] decode failed: %v", err)
			continue
		}
		results = append(results, groupInboxMessage{
			From:      message.From,
			Message:   message.Message,
			Timestamp: message.Timestamp,
			ID:        message.ID,
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

func (b *redisPushTokenBackend) RegisterToken(peerId string, token string, platform string) {
	entry := tokenEntry{
		Token:     token,
		Platform:  platform,
		UpdatedAt: time.Now(),
	}

	payload, err := json.Marshal(entry)
	if err != nil {
		log.Printf("[REDIS][PUSH] encode failed: %v", err)
		return
	}

	if err := b.client.Set(context.Background(), b.key(peerId), payload, 0).Err(); err != nil {
		log.Printf("[REDIS][PUSH] register failed: %v", err)
	}
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
