package node

import (
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

// dcutrReachabilityMode returns the libp2p reachability policy the host should be
// built with, given the FDC-12 DCUtR upgrade flag and the test-only force-public
// seam:
//
//   - "public"  → ForceReachabilityPublic(): lets the DCUtR holepuncher actively
//     upgrade a relay conn to direct (FDC-12 flag ON, or a feasibility test).
//   - "private" → ForceReachabilityPrivate(): the production default — DCUtR only
//     OBSERVES, zero punches fire (the holepunch_tracer.go ZERO-punch invariant).
//
// Either opt-in (the flag or the test seam) is sufficient; with both off the host
// stays private, byte-identical to HEAD.
func dcutrReachabilityMode(enableDcutrUpgrade, forcePublicForTests bool) string {
	if enableDcutrUpgrade || forcePublicForTests {
		return "public"
	}
	return "private"
}

// peerSessionNotifiee maintains a stable peer-IDENTITY session across the DCUtR
// relay->direct second-connection swap. On a successful hole punch libp2p opens a
// SECOND (direct) connection to the same peer ID and does NOT re-fire
// EvtPeerConnectednessChanged (it only fires on connectedness STATE changes, not
// on an extra conn to an already-connected peer), so the EventBus-driven
// watchConnectionEvents path would keep connections[peer] pointing at the stale
// /p2p-circuit leg. This per-conn Notifiee closes that gap: it re-points onto the
// best live conn on Connected and onto the best surviving conn on Disconnected.
type peerSessionNotifiee struct {
	n *Node
}

// newPeerSessionNotifiee binds a session Notifiee to its Node.
func newPeerSessionNotifiee(n *Node) *peerSessionNotifiee {
	return &peerSessionNotifiee{n: n}
}

// Connected re-points connections[peer] onto the best live conn when a new conn
// (e.g. a DCUtR-punched direct conn) opens to an already-tracked peer.
//
// libp2p calls Connected SYNCHRONOUSLY on the dialing goroutine (swarm
// notifyAll), which may already hold n.mu (a node dial path that opened this
// conn). repointPeerToBestConn re-acquires n.mu, so doing it inline would be a
// re-entrant deadlock. We defer to a goroutine — the same discipline libp2p
// itself uses for close notifications ("do this in a goroutine to avoid
// deadlocking if we call close in an open notification").
func (s *peerSessionNotifiee) Connected(net network.Network, conn network.Conn) {
	if s == nil || s.n == nil || net == nil || conn == nil {
		return
	}
	remote := conn.RemotePeer()
	go func() {
		s.n.repointPeerToBestConn(remote, net.ConnsToPeer(remote))
	}()
}

// Disconnected re-points connections[peer] onto the best SURVIVING conn when a
// conn closes (e.g. the direct leg dies, falling back to the relay leg). When no
// conn survives, the re-point is a no-op and the EventBus owns the deletion.
// Deferred to a goroutine for the same re-entrancy reason as Connected.
func (s *peerSessionNotifiee) Disconnected(net network.Network, conn network.Conn) {
	if s == nil || s.n == nil || net == nil || conn == nil {
		return
	}
	remote := conn.RemotePeer()
	go func() {
		s.n.repointPeerToBestConn(remote, net.ConnsToPeer(remote))
	}()
}

// Listen and ListenClose are required by network.Notifiee but are no-ops: the
// session layer reacts only to per-peer conn open/close.
func (s *peerSessionNotifiee) Listen(network.Network, ma.Multiaddr)      {}
func (s *peerSessionNotifiee) ListenClose(network.Network, ma.Multiaddr) {}

// selectBestConnAddr picks the best live conn's remote multiaddr for a peer: a
// non-circuit (direct TCP or QUIC) conn outranks a /p2p-circuit relay conn, and
// TCP and QUIC direct conns are equal-rank (punchr: TCP==QUIC), so the first
// non-circuit conn wins. It returns the chosen address string, whether that conn
// is circuit-limited, and ok=false when no usable conn exists (deletion of the
// map entry is owned by watchConnectionEvents, not this selector).
func selectBestConnAddr(conns []network.Conn) (addr string, limited bool, ok bool) {
	var circuitAddr string
	haveCircuit := false
	for _, c := range conns {
		if c == nil {
			continue
		}
		ra := c.RemoteMultiaddr()
		if ra == nil {
			continue
		}
		if isCircuitAddr(ra) {
			if !haveCircuit {
				circuitAddr = ra.String()
				haveCircuit = true
			}
			continue
		}
		// First non-circuit (direct) conn wins — TCP and QUIC equal-rank.
		return ra.String(), false, true
	}
	if haveCircuit {
		return circuitAddr, true, true
	}
	return "", false, false
}

// repointPeerToBestConn recomputes connections[remote] from the given live conns
// and emits a single transport:upgraded / transport:downgraded on a real
// circuit<->direct transition. It is the authoritative session re-point shared by
// the Notifiee's Connected/Disconnected callbacks. It is idempotent — duplicate
// callbacks for the same conn set re-point to the same state and emit nothing the
// second time, so there is no upgrade/downgrade thrash.
//
// It ONLY mutates an EXISTING connections entry: entry creation (on initial
// connect) and deletion (on last disconnect) stay owned by the EventBus-driven
// watchConnectionEvents, so the two paths never race the map's lifecycle. The
// map mutation takes n.mu only briefly; the emit happens OUTSIDE the lock (like
// the holepunch tracer) so the libp2p callback never blocks on the single Go
// bridge or re-acquires the host-construction lock.
func (n *Node) repointPeerToBestConn(remote peer.ID, conns []network.Conn) {
	key := remote.String()

	bestAddr, limited, found := selectBestConnAddr(conns)

	var emitUpgrade, emitDowngrade bool

	n.mu.Lock()
	info, ok := n.connections[key]
	if !ok || !found {
		// Unknown peer (EventBus owns creation) or no live conns supplied
		// (EventBus owns deletion) — nothing for the session layer to re-point.
		n.mu.Unlock()
		return
	}
	wasLimited := info.Limited
	info.Limited = limited
	info.Address = bestAddr
	n.connections[key] = info
	switch {
	case wasLimited && !limited:
		emitUpgrade = true
	case !wasLimited && limited:
		emitDowngrade = true
	}
	n.mu.Unlock()

	switch {
	case emitUpgrade:
		n.emitEvent("transport:upgraded", map[string]interface{}{
			"remotePeerShort": shortPeerID(key),
			"fromTransport":   "relay",
			"toTransport":     "direct",
		})
	case emitDowngrade:
		n.emitEvent("transport:downgraded", map[string]interface{}{
			"remotePeerShort": shortPeerID(key),
			"fromTransport":   "direct",
			"toTransport":     "relay",
		})
	}
}
