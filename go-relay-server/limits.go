package main

import (
	"os"
	"strconv"
	"strings"

	"github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/relay"
)

const (
	relayMaxReservationsEnv       = "RELAY_MAX_RESERVATIONS"
	relayMaxConnectionsPerPeerEnv = "RELAY_MAX_CONNECTIONS_PER_PEER"
	relayMaxInboxMessagesEnv      = "RELAY_MAX_INBOX_MESSAGES_PER_PEER"
	relayMaxGroupInboxMessagesEnv = "RELAY_MAX_GROUP_INBOX_MESSAGES"
)

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

	// MaxConnectionsPerPeer is the maximum number of concurrent relayed
	// circuits allowed from a single peer.
	MaxConnectionsPerPeer int
}

// DefaultServerLimits returns sane default limits for production.
// These are finite but generous enough for typical usage patterns.
func DefaultServerLimits() ServerLimits {
	return ServerLimits{
		MaxRelayReservations:    512,
		MaxInboxMessagesPerPeer: maxMessagesPerPeer,
		MaxGroupInboxMessages:   maxMessagesPerGroup,
		MaxConnectionsPerPeer:   8,
	}
}

// loadServerLimitsFromEnv reads the finite relay and store limits from
// environment variables, falling back to DefaultServerLimits().
func loadServerLimitsFromEnv() ServerLimits {
	defaults := DefaultServerLimits()

	return ServerLimits{
		MaxRelayReservations:    envIntOrDefault(relayMaxReservationsEnv, defaults.MaxRelayReservations),
		MaxInboxMessagesPerPeer: envIntOrDefault(relayMaxInboxMessagesEnv, defaults.MaxInboxMessagesPerPeer),
		MaxGroupInboxMessages:   envIntOrDefault(relayMaxGroupInboxMessagesEnv, defaults.MaxGroupInboxMessages),
		MaxConnectionsPerPeer:   envIntOrDefault(relayMaxConnectionsPerPeerEnv, defaults.MaxConnectionsPerPeer),
	}
}

func envIntOrDefault(key string, fallback int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}

	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		return fallback
	}
	return value
}

// relayResourcesFromServerLimits translates the rollout config into the live
// libp2p relay-service resource envelope.
func relayResourcesFromServerLimits(limits ServerLimits) relay.Resources {
	resources := relay.DefaultResources()
	resources.Limit = relay.DefaultLimit()
	resources.MaxReservations = limits.MaxRelayReservations
	resources.MaxCircuits = limits.MaxConnectionsPerPeer
	resources.MaxReservationsPerPeer = 1
	return resources
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

func (b *memoryInboxBackendLimited) Store(toPeerId string, entry inboxMessage) bool {
	// Delegate to inner — its Store already enforces the global cap,
	// but we override the limit.
	b.inner.mu.Lock()
	defer b.inner.mu.Unlock()

	entry = ensureInboxMessageID(entry)

	// Extract messageId for dedup.
	msgId := extractMessageId(entry.Message)
	if msgId != "" {
		if ids, ok := b.inner.messageIds[toPeerId]; ok && ids[msgId] {
			return false
		}
	}

	messages := b.inner.pruneExpired(b.inner.store[toPeerId])

	// Enforce configurable cap.
	if len(messages) >= b.maxPerPeer {
		messages = messages[len(messages)-b.maxPerPeer+1:]
		b.inner.rebuildMessageIds(toPeerId, messages)
	}

	messages = append(messages, entry)
	b.inner.store[toPeerId] = messages

	// Track messageId
	if msgId != "" {
		if b.inner.messageIds[toPeerId] == nil {
			b.inner.messageIds[toPeerId] = make(map[string]bool)
		}
		b.inner.messageIds[toPeerId][msgId] = true
	}

	return true
}

func (b *memoryInboxBackendLimited) Retrieve(peerId string, limit int) ([]inboxMessage, bool) {
	return b.inner.Retrieve(peerId, limit)
}

func (b *memoryInboxBackendLimited) RetrievePending(peerId string, limit int) ([]inboxMessage, bool) {
	return b.inner.RetrievePending(peerId, limit)
}

func (b *memoryInboxBackendLimited) Ack(peerId string, entryIDs []string) (int, error) {
	return b.inner.Ack(peerId, entryIDs)
}

func (b *memoryInboxBackendLimited) Count(peerId string) int {
	return b.inner.Count(peerId)
}

func (b *memoryInboxBackendLimited) Stats() (totalPeers int, totalMessages int) {
	return b.inner.Stats()
}
