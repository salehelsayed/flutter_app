package node

// FDC-11 — bonsoir-fed libp2p LAN-direct dial.
//
// Discovery is bonsoir on BOTH iOS and Android (no native mdns.NewMdnsService
// is registered on either platform). A resolved same-WiFi peer's libp2p QUIC
// (+TCP) multiaddr is bridged to Go as a lan:peer_found command (bridge_lan.go)
// and handed to Node.HandleLANPeerFound, which seeds the peerstore durably and
// host.Connects so DefaultDialRanker prefers the private/LAN leg (~30ms) over
// the relay leg (RelayDelay ~500ms). identify keeps the LAN addr hot; a known
// LAN addr also upgrades an existing relay circuit to direct via
// WithForceDirectDial (the upgrade DCUtR cannot deliver under
// ForceReachabilityPrivate).
//
// HandleLANPeerFound WRAPS the existing DialPeerWithTimeout connect core
// (decode/parse/ctx-from-n.ctx/h.Connect); the genuinely-new behaviors are
// self-skip, the per-peer cooldown, the durable AddressTTL peerstore seed, the
// WithForceDirectDial relay→direct upgrade, and the lan_* flow events.

import (
	"context"
	"log"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	ma "github.com/multiformats/go-multiaddr"
)

// lanDialHandler owns the FDC-11 LAN-direct dial state for a started Node: the
// per-peer warm cooldown (guarded by mu) plus test seams. It is created in
// Start() once n.host is set and torn down in Stop().
type lanDialHandler struct {
	node *Node

	mu       sync.Mutex
	cooldown map[peer.ID]time.Time // last warm-dial time per peer; debounce window

	// Test seams (nil in production).
	dialHook        func(context.Context, peer.AddrInfo) error // override the host.Connect dial
	circuitConnHook func(peer.ID) bool                         // simulate an existing circuit conn (T7)
	nowFunc         func() time.Time                           // controllable clock for the cooldown (T6)
}

func newLANDialHandler(n *Node) *lanDialHandler {
	return &lanDialHandler{
		node:     n,
		cooldown: make(map[peer.ID]time.Time),
	}
}

func (lh *lanDialHandler) now() time.Time {
	if lh.nowFunc != nil {
		return lh.nowFunc()
	}
	return time.Now()
}

// hasCircuitConn reports whether a circuit/limited conn to pid is already held —
// the precondition for a relay→direct upgrade.
func (lh *lanDialHandler) hasCircuitConn(h host.Host, pid peer.ID) bool {
	if lh.circuitConnHook != nil {
		return lh.circuitConnHook(pid)
	}
	for _, c := range h.Network().ConnsToPeer(pid) {
		if c.Stat().Limited {
			return true
		}
		if addr := c.RemoteMultiaddr(); addr != nil && isCircuitAddr(addr) {
			return true
		}
	}
	return false
}

// dial issues the LAN-direct dial, honoring the test seam.
func (lh *lanDialHandler) dial(ctx context.Context, h host.Host, pi peer.AddrInfo) error {
	if lh.dialHook != nil {
		return lh.dialHook(ctx, pi)
	}
	return h.Connect(ctx, pi)
}

// hasNonCircuitAddr reports whether any address is a raw (non-circuit) addr —
// i.e. a real LAN addr we can dial directly.
func hasNonCircuitAddr(addrs []ma.Multiaddr) bool {
	for _, a := range addrs {
		if a != nil && !isCircuitAddr(a) {
			return true
		}
	}
	return false
}

// HandleLANPeerFound consumes a bonsoir-discovered same-WiFi peer.AddrInfo
// (carrying the remote's libp2p QUIC/TCP multiaddr) and, when the
// EnableLibp2pLANDial flag is on, seeds the peerstore and issues a LAN-direct
// dial that DefaultDialRanker ranks ahead of the relay. Self is skipped;
// repeated finds for the same peer are debounced by LANDialWarmCooldown; a
// known LAN addr upgrades an existing relay circuit to direct via
// WithForceDirectDial. Safe to call concurrently from the bonsoir bridge
// goroutine. No-op until Start() wires the handler / after Stop() tears it down.
func (n *Node) HandleLANPeerFound(pi peer.AddrInfo) {
	n.mu.RLock()
	lh := n.lanDialHandler
	n.mu.RUnlock()
	if lh == nil {
		return
	}
	lh.handle(pi)
}

// HandleLANPeerFoundAddrs is the bonsoir-bridge string entrypoint: it decodes a
// peer ID + libp2p multiaddr strings (the remote's QUIC/TCP LAN addrs) into a
// peer.AddrInfo and forwards to HandleLANPeerFound. Mirrors the
// DialPeerWithTimeout decode/parse core; invalid inputs are skipped.
func (n *Node) HandleLANPeerFoundAddrs(peerIdStr string, addresses []string) {
	pid, err := peer.Decode(peerIdStr)
	if err != nil {
		log.Printf("[NODE] LAN peer-found: invalid peer ID %q: %v", peerIdStr, err)
		return
	}
	var addrs []ma.Multiaddr
	for _, a := range addresses {
		maddr, err := ma.NewMultiaddr(a)
		if err != nil {
			log.Printf("[NODE] LAN peer-found: skip invalid address %s: %v", a, err)
			continue
		}
		addrs = append(addrs, maddr)
	}
	n.HandleLANPeerFound(peer.AddrInfo{ID: pid, Addrs: addrs})
}

func (lh *lanDialHandler) handle(pi peer.AddrInfo) {
	n := lh.node

	// Flag gate (T2): the LAN-direct dial is gated for safe rollout.
	if !n.currentFeatureFlags().EnableLibp2pLANDial {
		return
	}

	n.mu.RLock()
	h := n.host
	baseCtx := n.ctx
	n.mu.RUnlock()
	if h == nil || baseCtx == nil {
		return
	}

	// Self-skip (T5): never dial ourselves.
	if pi.ID == h.ID() {
		return
	}

	// Per-peer cooldown (T6 / T10): at most one warm dial per peer per window so
	// a flapping/offline LAN peer cannot tight-loop the swarm into 5s→5m backoff.
	now := lh.now()
	lh.mu.Lock()
	if lh.cooldown == nil {
		lh.cooldown = make(map[peer.ID]time.Time)
	}
	if last, seen := lh.cooldown[pi.ID]; seen && now.Sub(last) < LANDialWarmCooldown {
		lh.mu.Unlock()
		return
	}
	lh.cooldown[pi.ID] = now
	lh.mu.Unlock()

	// Durably seed the peerstore (T4): AddressTTL (1h) survives a failed dial for
	// a later ranked race. h.Connect's own add uses TempAddrTTL (2min, cleared on
	// disconnect) — too short — so the explicit AddAddrs is load-bearing.
	if len(pi.Addrs) > 0 {
		h.Peerstore().AddAddrs(pi.ID, pi.Addrs, peerstore.AddressTTL)
	}

	// A same-WiFi find was accepted (non-self, off-cooldown).
	n.emitEvent("node:lan_peer_found", map[string]interface{}{
		"peer":      pi.ID.String(),
		"addrCount": len(pi.Addrs),
	})

	// Derive the dial ctx from n.ctx so Stop()'s n.cancel() cancels any in-flight
	// LAN dial; bound it by the per-leg LAN identify budget.
	dialCtx, cancel := context.WithTimeout(baseCtx, LANDirectIdentifyBudget)
	defer cancel()
	dialCtx = network.WithDialPeerTimeout(dialCtx, LANDirectIdentifyBudget)

	// Relay→direct upgrade (T7): if we already hold a circuit conn and now know a
	// non-circuit LAN addr, force a direct dial (DCUtR cannot deliver this under
	// ForceReachabilityPrivate).
	if lh.hasCircuitConn(h, pi.ID) && hasNonCircuitAddr(pi.Addrs) {
		dialCtx = network.WithForceDirectDial(dialCtx, "lan-upgrade")
	}

	// Issuing the LAN-direct dial (T1).
	n.emitEvent("node:lan_dial_ready", map[string]interface{}{
		"peer": pi.ID.String(),
	})

	if err := lh.dial(dialCtx, h, pi); err != nil {
		log.Printf("[NODE] LAN-direct dial to %s failed: %v", pi.ID, err)
	}
}
