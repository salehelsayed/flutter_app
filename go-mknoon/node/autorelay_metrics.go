package node

import (
	"strings"

	"github.com/libp2p/go-libp2p/core/peer"
)

// syncRelaySessionFromRuntime reconciles relay session state from the runtime
// signals we can observe in this libp2p version: relay peer connectedness and
// the host's current circuit address set.
//
// go-libp2p v0.39.x exposes autorelay.WithMetricsTracer, but the tracer
// interface includes unexported parameter types, so it cannot be implemented
// outside the autorelay package. This runtime sync path is therefore the
// honest Phase 4 hook point that keeps relay-session state aligned with
// reservation truth visible from the host.
func (n *Node) syncRelaySessionFromRuntime(reason string, circuitAddrs []string) {
	if n == nil || n.relaySessionMgr == nil || !n.reservationAwareHealthEnabled() {
		return
	}

	n.mu.RLock()
	relayPeerOrder := append([]peer.ID(nil), n.relayPeerOrder...)
	connectedPeers := make(map[string]struct{}, len(n.connections))
	for peerID := range n.connections {
		connectedPeers[peerID] = struct{}{}
	}
	n.mu.RUnlock()

	for _, relayPeerID := range relayPeerOrder {
		_, connected := connectedPeers[relayPeerID.String()]
		session := n.relaySessionMgr.GetSession(relayPeerID)
		hasCircuitAddr := relayPeerHasCircuitAddress(relayPeerID, circuitAddrs)

		switch {
		case connected && hasCircuitAddr:
			n.relaySessionMgr.OnReservationOpened(relayPeerID)
		case connected && session != nil && session.State == RelayStateReserved:
			n.relaySessionMgr.OnReservationEnded(relayPeerID)
		case connected:
			n.relaySessionMgr.OnConnected(relayPeerID)
		case session != nil:
			n.relaySessionMgr.OnDisconnected(relayPeerID)
		}
	}

	n.emitRelayStateEvent(reason)
}

func relayPeerHasCircuitAddress(relayPeerID peer.ID, circuitAddrs []string) bool {
	if relayPeerID == "" {
		return false
	}

	relayPeerIDStr := relayPeerID.String()
	for _, addr := range circuitAddrs {
		if strings.Contains(addr, relayPeerIDStr) ||
			strings.Contains(addr, "/p2p/"+relayPeerIDStr+"/") {
			return true
		}
	}
	return false
}
