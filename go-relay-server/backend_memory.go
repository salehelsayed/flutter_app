package main

import (
	"fmt"
	"strconv"
	"sync"
	"time"
)

// --- In-memory RendezvousBackend ---

type memoryRendezvousBackend struct {
	mu            sync.RWMutex
	registrations map[string]map[string]*peerRegistration // namespace -> peerId -> registration
}

func newMemoryRendezvousBackend() *memoryRendezvousBackend {
	return &memoryRendezvousBackend{
		registrations: make(map[string]map[string]*peerRegistration),
	}
}

func (b *memoryRendezvousBackend) Register(ns string, peerId string, signedPeerRecord []byte, ttlSeconds uint64) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if _, ok := b.registrations[ns]; !ok {
		b.registrations[ns] = make(map[string]*peerRegistration)
	}
	b.registrations[ns][peerId] = &peerRegistration{
		signedPeerRecord: signedPeerRecord,
		expiresAt:        time.Now().Add(time.Duration(ttlSeconds) * time.Second),
	}
}

func (b *memoryRendezvousBackend) Unregister(ns string, peerId string) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if peers, ok := b.registrations[ns]; ok {
		delete(peers, peerId)
		if len(peers) == 0 {
			delete(b.registrations, ns)
		}
	}
}

func (b *memoryRendezvousBackend) Discover(ns string, requestingPeer string, limit uint64) []Registration {
	b.mu.RLock()
	defer b.mu.RUnlock()

	var results []Registration
	peers, ok := b.registrations[ns]
	if !ok {
		return results
	}

	now := time.Now()
	var count uint64
	for pid, reg := range peers {
		if count >= limit {
			break
		}
		if reg.expiresAt.After(now) && pid != requestingPeer {
			results = append(results, Registration{
				Ns:               ns,
				SignedPeerRecord: reg.signedPeerRecord,
			})
			count++
		}
	}
	return results
}

func (b *memoryRendezvousBackend) Cleanup() {
	b.mu.Lock()
	defer b.mu.Unlock()
	now := time.Now()
	for ns, peers := range b.registrations {
		for pid, reg := range peers {
			if reg.expiresAt.Before(now) {
				delete(peers, pid)
			}
		}
		if len(peers) == 0 {
			delete(b.registrations, ns)
		}
	}
}

func (b *memoryRendezvousBackend) Stats() (namespaces int, totalPeers int) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	namespaces = len(b.registrations)
	for _, peers := range b.registrations {
		totalPeers += len(peers)
	}
	return
}

// --- In-memory InboxBackend ---

type memoryInboxBackend struct {
	mu         sync.Mutex
	store      map[string][]inboxMessage  // peerId -> messages
	messageIds map[string]map[string]bool // peerId -> set of messageIds
}

func newMemoryInboxBackend() *memoryInboxBackend {
	return &memoryInboxBackend{
		store:      make(map[string][]inboxMessage),
		messageIds: make(map[string]map[string]bool),
	}
}

func (b *memoryInboxBackend) Store(toPeerId string, entry inboxMessage) bool {
	b.mu.Lock()
	defer b.mu.Unlock()

	entry = ensureInboxMessageID(entry)

	// Extract messageId for dedup.
	msgId := extractMessageId(entry.Message)
	if msgId != "" {
		if ids, ok := b.messageIds[toPeerId]; ok && ids[msgId] {
			// Duplicate — skip store and push.
			return false
		}
	}

	messages := b.pruneExpired(b.store[toPeerId])

	// Cap at max
	if len(messages) >= maxMessagesPerPeer {
		messages = messages[len(messages)-maxMessagesPerPeer+1:]
		// Also prune messageIds for evicted messages
		b.rebuildMessageIds(toPeerId, messages)
	}

	messages = append(messages, entry)
	b.store[toPeerId] = messages

	// Track messageId
	if msgId != "" {
		if b.messageIds[toPeerId] == nil {
			b.messageIds[toPeerId] = make(map[string]bool)
		}
		b.messageIds[toPeerId][msgId] = true
	}

	return true
}

func (b *memoryInboxBackend) RetrievePending(peerId string, limit int) ([]inboxMessage, bool) {
	b.mu.Lock()
	defer b.mu.Unlock()

	messages := b.pruneExpired(b.store[peerId])
	if len(messages) == 0 {
		delete(b.store, peerId)
		delete(b.messageIds, peerId)
		return nil, false
	}

	changed := false
	for i := range messages {
		normalized := ensureInboxMessageID(messages[i])
		if normalized.ID != messages[i].ID {
			messages[i] = normalized
			changed = true
		}
	}
	if changed || len(messages) != len(b.store[peerId]) {
		b.store[peerId] = messages
	}

	if limit > len(messages) {
		limit = len(messages)
	}

	result := make([]inboxMessage, limit)
	copy(result, messages[:limit])
	return result, len(messages) > limit
}

func (b *memoryInboxBackend) Retrieve(peerId string, limit int) ([]inboxMessage, bool) {
	b.mu.Lock()
	defer b.mu.Unlock()

	messages := b.pruneExpired(b.store[peerId])
	b.store[peerId] = messages

	if len(messages) == 0 {
		delete(b.store, peerId)
		delete(b.messageIds, peerId)
		return nil, false
	}

	if limit > len(messages) {
		limit = len(messages)
	}

	result := make([]inboxMessage, limit)
	copy(result, messages[:limit])

	remaining := messages[limit:]
	if len(remaining) > 0 {
		b.store[peerId] = remaining
		b.rebuildMessageIds(peerId, remaining)
		return result, true
	}

	delete(b.store, peerId)
	delete(b.messageIds, peerId)
	return result, false
}

func (b *memoryInboxBackend) Ack(peerId string, entryIDs []string) (int, error) {
	if len(entryIDs) == 0 {
		return 0, nil
	}

	b.mu.Lock()
	defer b.mu.Unlock()

	messages := b.pruneExpired(b.store[peerId])
	if len(messages) == 0 {
		delete(b.store, peerId)
		delete(b.messageIds, peerId)
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

	remaining := make([]inboxMessage, 0, len(messages))
	removed := 0
	for _, message := range messages {
		message = ensureInboxMessageID(message)
		if _, ok := targets[message.ID]; ok {
			removed++
			continue
		}
		remaining = append(remaining, message)
	}

	if len(remaining) == 0 {
		delete(b.store, peerId)
		delete(b.messageIds, peerId)
		return removed, nil
	}

	b.store[peerId] = remaining
	b.rebuildMessageIds(peerId, remaining)
	return removed, nil
}

func (b *memoryInboxBackend) rebuildMessageIds(peerId string, messages []inboxMessage) {
	ids := make(map[string]bool, len(messages))
	for _, m := range messages {
		if msgId := extractMessageId(m.Message); msgId != "" {
			ids[msgId] = true
		}
	}
	if len(ids) > 0 {
		b.messageIds[peerId] = ids
	} else {
		delete(b.messageIds, peerId)
	}
}

func (b *memoryInboxBackend) Count(peerId string) int {
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.store[peerId])
}

func (b *memoryInboxBackend) Stats() (totalPeers int, totalMessages int) {
	b.mu.Lock()
	defer b.mu.Unlock()
	totalPeers = len(b.store)
	for _, msgs := range b.store {
		totalMessages += len(msgs)
	}
	return
}

func (b *memoryInboxBackend) pruneExpired(messages []inboxMessage) []inboxMessage {
	if len(messages) == 0 {
		return messages
	}
	cutoff := time.Now().Add(-maxMessageAge).UnixMilli()
	var result []inboxMessage
	for _, m := range messages {
		if m.Timestamp > cutoff {
			result = append(result, m)
		}
	}
	return result
}

// --- In-memory GroupInboxBackend ---

type memoryGroupInboxBackend struct {
	mu          sync.RWMutex
	messages    map[string][]groupInboxMessage // groupId -> messages
	idCounter   int64
	maxPerGroup int
	ttl         time.Duration
}

func newMemoryGroupInboxBackend(maxPerGroup int, ttl time.Duration) *memoryGroupInboxBackend {
	return &memoryGroupInboxBackend{
		messages:    make(map[string][]groupInboxMessage),
		maxPerGroup: maxPerGroup,
		ttl:         ttl,
	}
}

func (b *memoryGroupInboxBackend) Store(groupId string, from string, message string) error {
	b.mu.Lock()
	defer b.mu.Unlock()

	msgs := b.pruneExpiredLocked(b.messages[groupId])

	// Cap enforcement
	if len(msgs) >= b.maxPerGroup {
		overflow := len(msgs) - b.maxPerGroup + 1
		_ = overflow
		msgs = msgs[overflow:]
	}

	b.idCounter++
	msgs = append(msgs, groupInboxMessage{
		From:      from,
		Message:   message,
		Timestamp: time.Now().UnixMilli(),
		ID:        fmt.Sprintf("%d", b.idCounter),
	})
	b.messages[groupId] = msgs
	return nil
}

func (b *memoryGroupInboxBackend) RetrieveSince(groupId string, sinceTimestamp int64) []groupInboxMessage {
	b.mu.RLock()
	defer b.mu.RUnlock()

	msgs := b.messages[groupId]
	if len(msgs) == 0 {
		return nil
	}

	var result []groupInboxMessage
	cutoff := time.Now().Add(-b.ttl).UnixMilli()
	for _, m := range msgs {
		if m.Timestamp <= cutoff {
			continue // expired
		}
		if sinceTimestamp > 0 && m.Timestamp <= sinceTimestamp {
			continue
		}
		result = append(result, m)
	}
	return result
}

func (b *memoryGroupInboxBackend) RetrieveCursor(groupId string, cursor string, limit int) ([]groupInboxMessage, string) {
	b.mu.RLock()
	defer b.mu.RUnlock()

	msgs := b.messages[groupId]
	if len(msgs) == 0 {
		return nil, ""
	}

	// Parse cursor — the cursor is the ID of the last seen message.
	var startIdx int
	if cursor != "" {
		found := false
		for i, m := range msgs {
			if m.ID == cursor {
				startIdx = i + 1
				found = true
				break
			}
		}
		if !found {
			// Cursor not found: start from beginning.
			startIdx = 0
		}
	}

	cutoff := time.Now().Add(-b.ttl).UnixMilli()
	var result []groupInboxMessage
	for i := startIdx; i < len(msgs) && len(result) < limit; i++ {
		m := msgs[i]
		if m.Timestamp <= cutoff {
			continue
		}
		result = append(result, m)
	}

	var nextCursor string
	if len(result) > 0 {
		lastID := result[len(result)-1].ID
		// Check if there are more messages after the last returned.
		lastIDInt, _ := strconv.ParseInt(lastID, 10, 64)
		for i := len(msgs) - 1; i >= 0; i-- {
			msgIDInt, _ := strconv.ParseInt(msgs[i].ID, 10, 64)
			if msgIDInt > lastIDInt && msgs[i].Timestamp > cutoff {
				nextCursor = lastID
				break
			}
		}
	}

	return result, nextCursor
}

func (b *memoryGroupInboxBackend) Prune() {
	b.mu.Lock()
	defer b.mu.Unlock()

	for groupId, msgs := range b.messages {
		pruned := b.pruneExpiredLocked(msgs)
		if len(pruned) == 0 {
			delete(b.messages, groupId)
		} else {
			b.messages[groupId] = pruned
		}
	}
}

func (b *memoryGroupInboxBackend) Stats() (groups int, totalMessages int) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	groups = len(b.messages)
	for _, msgs := range b.messages {
		totalMessages += len(msgs)
	}
	return
}

func (b *memoryGroupInboxBackend) pruneExpiredLocked(messages []groupInboxMessage) []groupInboxMessage {
	if len(messages) == 0 {
		return messages
	}
	cutoff := time.Now().Add(-b.ttl).UnixMilli()
	var result []groupInboxMessage
	for _, m := range messages {
		if m.Timestamp > cutoff {
			result = append(result, m)
		}
	}
	return result
}
