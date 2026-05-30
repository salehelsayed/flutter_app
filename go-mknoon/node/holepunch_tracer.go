package node

import (
	"sync/atomic"

	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/holepunch"
)

// nodeHolePunchTracer is the production holepunch.EventTracer (NET-REL-02
// Option A, instrument-only). It surfaces DCUtR attempt/success/failure
// telemetry through the node's emitEvent path and keeps lightweight atomic
// counters for tests. It changes NO connection policy — it is pure observation.
//
// NOTE: in production the host runs with ForceReachabilityPrivate(), so this
// tracer legitimately observes ZERO hole punches — that is the expected
// I1-NC result, not a bug.
type nodeHolePunchTracer struct {
	n         *Node
	attempts  atomic.Int64
	successes atomic.Int64
	failures  atomic.Int64
}

func newNodeHolePunchTracer(n *Node) *nodeHolePunchTracer {
	return &nodeHolePunchTracer{n: n}
}

// Trace implements holepunch.EventTracer. It is invoked on libp2p goroutines
// (NOT under n.mu), so it must never re-acquire the host-construction lock; it
// emits via the concurrency-safe emitEvent and only takes n.mu inside the
// dedicated markPeerUpgradedToDirect helper.
func (t *nodeHolePunchTracer) Trace(evt *holepunch.Event) {
	if t == nil || t.n == nil || evt == nil {
		return
	}

	remoteShort := shortPeerID(evt.Remote.String())

	switch e := evt.Evt.(type) {
	case *holepunch.HolePunchAttemptEvt:
		t.attempts.Add(1)
		t.n.emitEvent("holepunch:attempt", map[string]interface{}{
			"step":            "attempt",
			"attempt":         e.Attempt,
			"remotePeerShort": remoteShort,
		})

	case *holepunch.StartHolePunchEvt:
		t.n.emitEvent("holepunch:attempt", map[string]interface{}{
			"step":            "started",
			"rttMs":           e.RTT.Milliseconds(),
			"remotePeerShort": remoteShort,
		})

	case *holepunch.EndHolePunchEvt:
		if e.Success {
			t.successes.Add(1)
			t.n.emitEvent("holepunch:success", map[string]interface{}{
				"step":            "succeeded",
				"fromTransport":   "relay",
				"toTransport":     "direct",
				"elapsedMs":       e.EllapsedTime.Milliseconds(),
				"remotePeerShort": remoteShort,
			})
			// Relay->direct upgrade signal. libp2p does NOT re-fire
			// EvtPeerConnectednessChanged on an upgrade, so this dedicated event
			// (and the connections-map correction below) is the only observation
			// of the transition.
			t.n.emitEvent("transport:upgraded", map[string]interface{}{
				"remotePeerShort": remoteShort,
				"fromTransport":   "relay",
				"toTransport":     "direct",
				"elapsedMs":       e.EllapsedTime.Milliseconds(),
			})
			t.n.markPeerUpgradedToDirect(evt.Remote)
		} else {
			t.failures.Add(1)
			t.n.emitEvent("holepunch:failure", map[string]interface{}{
				"step":            "failed",
				"error":           sanitizeTracerErr(e.Error),
				"elapsedMs":       e.EllapsedTime.Milliseconds(),
				"remotePeerShort": remoteShort,
			})
		}

	case *holepunch.ProtocolErrorEvt:
		t.failures.Add(1)
		t.n.emitEvent("holepunch:failure", map[string]interface{}{
			"step":            "protocol_error",
			"error":           sanitizeTracerErr(e.Error),
			"remotePeerShort": remoteShort,
		})

	case *holepunch.DirectDialEvt:
		// Optional debug breadcrumb; not counted as an attempt/success/failure.
		t.n.emitEvent("holepunch:attempt", map[string]interface{}{
			"step":            "direct_dial",
			"success":         e.Success,
			"elapsedMs":       e.EllapsedTime.Milliseconds(),
			"remotePeerShort": remoteShort,
		})
	}
}

// Attempts returns the number of HolePunchAttemptEvt observed.
func (t *nodeHolePunchTracer) Attempts() int64 { return t.attempts.Load() }

// Successes returns the number of successful EndHolePunchEvt observed.
func (t *nodeHolePunchTracer) Successes() int64 { return t.successes.Load() }

// Failures returns the number of failed EndHolePunchEvt / ProtocolErrorEvt observed.
func (t *nodeHolePunchTracer) Failures() int64 { return t.failures.Load() }

// shortPeerID returns the last 8 characters of a peer ID for sanitization-safe
// telemetry (never the raw full peer ID).
func shortPeerID(id string) string {
	if len(id) <= 8 {
		return id
	}
	return id[len(id)-8:]
}

// sanitizeTracerErr truncates a tracer error string to ~80 chars.
func sanitizeTracerErr(s string) string {
	const max = 80
	if len(s) <= max {
		return s
	}
	return s[:max]
}

// markPeerUpgradedToDirect corrects the one-shot-stale connections map after a
// relay->direct hole-punch upgrade: under n.mu it clears Limited and re-samples
// Address from the first non-circuit connection to the peer (best-effort).
func (n *Node) markPeerUpgradedToDirect(remote peer.ID) {
	n.mu.Lock()
	defer n.mu.Unlock()

	key := remote.String()
	info, ok := n.connections[key]
	if !ok {
		return
	}
	info.Limited = false
	if n.host != nil {
		for _, conn := range n.host.Network().ConnsToPeer(remote) {
			if addr := conn.RemoteMultiaddr(); addr != nil && !isCircuitAddr(addr) {
				info.Address = addr.String()
				break
			}
		}
	}
	n.connections[key] = info
}
