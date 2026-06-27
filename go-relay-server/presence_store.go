package main

import (
	"sync"
	"time"

	"github.com/libp2p/go-libp2p/core/event"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

// Coarse presence values served by the additive `presence_get` inbox action.
// They are "online-ish, TTL-lagged" answers derived from socket connectedness
// and a last-seen map — NEVER a foreground/background claim (the relay provably
// cannot infer that; only FDC-09's `presence_set` self-publish can, and even
// then this read surface stays coarse). See FDC-S3 canonical schema.
const (
	presenceReachable   = "reachable"
	presenceUnreachable = "unreachable"
	presenceUnknown     = "unknown"
)

// relayPresenceTTL bounds how long a connectedness-seeded last-seen entry (or a
// self-published presence_set state) is treated as fresh. Past it the relay
// reports `unknown` rather than silently `unreachable` (FDC-S3 freshness rule:
// `reachable` requires age < TTL; otherwise `unknown`). Device-tunable; starts
// ≈180 s (inherited from FDC-S3, closes on device-tuning).
const relayPresenceTTL = 180 * time.Second

// presenceEntry is one peer's coarse presence state in the relay's net-new
// last-seen map. It carries (a) a connectedness-seeded last-seen timestamp
// (written by FDC-08's connectedness handler via RecordSeen) and (b) an
// OPTIONAL self-published foreground/background state with its own set-time +
// TTL (written by FDC-09's `presence_set` via SetSelfPublished). FDC-08 reads
// both, preferring a fresh self-published state; FDC-09 co-owns the write side
// of (b). RecordPeerSeen (business_metrics.go) is HLL-only and discards the
// peer ID, so this map is genuinely net-new state, not a reuse.
type presenceEntry struct {
	lastSeen        time.Time     // connectedness-seeded (FDC-08)
	selfState       string        // "" | "foreground" | "background" (FDC-09 presence_set)
	selfPublishedAt time.Time     // when the self-published state was recorded (FDC-09)
	selfTTL         time.Duration // self-published freshness window (FDC-09)
}

// freshest returns the most recent timestamp this entry carries (last-seen or
// self-published), used to report `ageMs`.
func (e presenceEntry) freshest() time.Time {
	if e.selfPublishedAt.After(e.lastSeen) {
		return e.selfPublishedAt
	}
	return e.lastSeen
}

// presenceResolution is the coarse answer Lookup returns.
type presenceResolution struct {
	presence string // reachable | unreachable | unknown
	ageMs    int64  // age of the freshest record in ms; -1 when nothing is known
}

// PresenceStore is the shared, concurrency-safe per-peer presence map backing
// the additive `presence_get` (FDC-08 read) and `presence_set` (FDC-09 write)
// inbox actions. It is WRITTEN by the libp2p connectedness event goroutine
// (RecordSeen) and the future presence_set handler (SetSelfPublished), and READ
// by the per-stream presence handler (Lookup) — concurrent access across
// goroutines is the reason it is mutex-guarded and covered by `go test -race`
// (R6 / LAST_SEEN_MAP_RACE_SAFE). FDC-08 owns its creation (read + last-seen
// write); FDC-09 co-owns the self-published write into the SAME map (one map,
// not two).
type PresenceStore struct {
	mu      sync.RWMutex
	entries map[peer.ID]presenceEntry
	ttl     time.Duration
	now     func() time.Time // injectable so the freshness TTL is testable (R5)
}

// NewPresenceStore creates an empty presence store with the default relay TTL.
func NewPresenceStore() *PresenceStore {
	return &PresenceStore{
		entries: make(map[peer.ID]presenceEntry),
		ttl:     relayPresenceTTL,
		now:     time.Now,
	}
}

// RecordSeen stamps a peer's connectedness-seeded last-seen at the current time.
// Called from the relay's EvtPeerConnectednessChanged handler on Connected
// (via recordConnectednessPresence). This is the net-new last-seen WRITE seam.
func (ps *PresenceStore) RecordSeen(pid peer.ID) {
	ps.mu.Lock()
	defer ps.mu.Unlock()
	e := ps.entries[pid]
	e.lastSeen = ps.now()
	ps.entries[pid] = e
}

// SetSelfPublished records a peer's self-published foreground/background state
// with a freshness TTL. This is the WRITE seam FDC-09's `presence_set` action
// consumes; FDC-08 already prefers a fresh self-published state in Lookup, so
// FDC-09 only needs to wire the action to this method (no resolver change).
func (ps *PresenceStore) SetSelfPublished(pid peer.ID, state string, ttl time.Duration) {
	ps.mu.Lock()
	defer ps.mu.Unlock()
	e := ps.entries[pid]
	e.selfState = state
	e.selfPublishedAt = ps.now()
	e.selfTTL = ttl
	ps.entries[pid] = e
}

// Lookup resolves a peer's coarse presence WITHOUT dialing a circuit, given the
// peer's live socket connectedness. Resolution order (FDC-S3 read contract):
//
//  1. a FRESH self-published presence_set state (preferred)   -> reachable
//  2. a live socket connection (connected == true)           -> reachable
//  3. a FRESH connectedness-seeded last-seen (age < TTL)      -> reachable
//  4. a STALE last-seen (age >= TTL)                          -> unknown (never silently unreachable)
//  5. nothing known and not connected                        -> unreachable
//
// The answer is "online-ish, TTL-lagged" — it is never a foreground/background
// claim (PRESENCE_IS_ONLINE_ISH_NOT_FOREGROUND).
func (ps *PresenceStore) Lookup(pid peer.ID, connected bool) presenceResolution {
	ps.mu.RLock()
	e, ok := ps.entries[pid]
	now := ps.now()
	ps.mu.RUnlock()

	ageMs := int64(-1)
	if ok {
		if t := e.freshest(); !t.IsZero() {
			ageMs = now.Sub(t).Milliseconds()
			if ageMs < 0 {
				ageMs = 0
			}
		}
	}

	// (1) Prefer a fresh self-published state (FDC-09 writes it; before FDC-09
	// lands selfState is always "", so this falls through to connectedness).
	if ok && e.selfState != "" && now.Sub(e.selfPublishedAt) < e.selfTTL {
		return presenceResolution{presence: presenceReachable, ageMs: ageMs}
	}

	// (2) A live socket connection is the authoritative "online-ish" signal.
	if connected {
		if ageMs < 0 {
			ageMs = 0
		}
		return presenceResolution{presence: presenceReachable, ageMs: ageMs}
	}

	// (3)/(4) Connectedness-seeded last-seen, gated by the freshness TTL.
	if ok && !e.lastSeen.IsZero() {
		if now.Sub(e.lastSeen) < ps.ttl {
			return presenceResolution{presence: presenceReachable, ageMs: ageMs}
		}
		// Stale -> unknown, NEVER silently unreachable (R5 freshness rule).
		return presenceResolution{presence: presenceUnknown, ageMs: ageMs}
	}

	// (5) Nothing known and not currently connected.
	return presenceResolution{presence: presenceUnreachable, ageMs: ageMs}
}

// recordConnectednessPresence seeds the shared presence store from a libp2p
// connectedness event. Extracted from main.go's event loop so the last-seen
// seeding (R6) is unit-testable. On Connected it stamps the peer's last-seen;
// other transitions are intentionally left to TTL expiry — a lingering socket
// should not erase the entry the instant it drops, and the freshness TTL bounds
// the resulting "online-ish" lie.
func recordConnectednessPresence(presence *PresenceStore, e event.EvtPeerConnectednessChanged) {
	if presence == nil {
		return
	}
	if e.Connectedness == network.Connected {
		presence.RecordSeen(e.Peer)
	}
}
