package main

// ServerLimits holds configurable capacity limits for the relay server.
// These replace the infinite relay limits with bounded, observable behavior.
type ServerLimits struct {
	// MaxRelayReservations is the maximum number of concurrent relay
	// circuit reservations the server will accept.
	MaxRelayReservations int

	// MaxInboxMessagesPerPeer is the maximum number of pending inbox
	// messages stored per peer. When exceeded, the oldest are evicted.
	MaxInboxMessagesPerPeer int

	// MaxGroupInboxMessages is the maximum number of messages stored
	// per group inbox. When exceeded, the oldest are evicted.
	MaxGroupInboxMessages int

	// MaxConnectionsPerPeer is the maximum number of concurrent
	// connections allowed from a single peer.
	MaxConnectionsPerPeer int
}

// DefaultServerLimits returns sane default limits for production.
// These are finite but generous enough for typical usage patterns.
func DefaultServerLimits() ServerLimits {
	return ServerLimits{
		MaxRelayReservations:    512,
		MaxInboxMessagesPerPeer: 100,
		MaxGroupInboxMessages:   500,
		MaxConnectionsPerPeer:   8,
	}
}

// --- Inbox backend with configurable limit ---

// newMemoryInboxBackendWithLimits creates an in-memory inbox backend
// that enforces a per-peer message cap. This is used instead of the
// default maxMessagesPerPeer constant for testing configurable limits.
func newMemoryInboxBackendWithLimits(maxPerPeer int) *memoryInboxBackendLimited {
	return &memoryInboxBackendLimited{
		inner:      newMemoryInboxBackend(),
		maxPerPeer: maxPerPeer,
	}
}

// memoryInboxBackendLimited wraps the standard in-memory backend with
// a configurable per-peer limit.
type memoryInboxBackendLimited struct {
	inner      *memoryInboxBackend
	maxPerPeer int
}

func (b *memoryInboxBackendLimited) Store(toPeerId string, entry inboxMessage) {
	// Delegate to inner — its Store already enforces the global cap,
	// but we override the limit.
	b.inner.mu.Lock()
	defer b.inner.mu.Unlock()

	messages := b.inner.pruneExpired(b.inner.store[toPeerId])

	// Enforce configurable cap.
	if len(messages) >= b.maxPerPeer {
		messages = messages[len(messages)-b.maxPerPeer+1:]
	}

	messages = append(messages, entry)
	b.inner.store[toPeerId] = messages
}

func (b *memoryInboxBackendLimited) Retrieve(peerId string, limit int) ([]inboxMessage, bool) {
	return b.inner.Retrieve(peerId, limit)
}

func (b *memoryInboxBackendLimited) Count(peerId string) int {
	return b.inner.Count(peerId)
}

func (b *memoryInboxBackendLimited) Stats() (totalPeers int, totalMessages int) {
	return b.inner.Stats()
}
