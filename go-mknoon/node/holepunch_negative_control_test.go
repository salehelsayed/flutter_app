package node

// I1-NC — PRIMARY E2E negative control (NET-REL-02 Option A).
//
// This is the dominant REAL case: two nodes that can only reach each other
// through a circuit relay (no reachable direct address). Production runs
// ForceReachabilityPrivate(), so DCUtR never initiates and the relay->direct
// upgrade never happens. We prove the instrumentation does NOT manufacture a
// false upgrade by asserting, across a polled wall-clock window:
//
//  (1) assertNW002LimitedCircuitConn holds THROUGHOUT (re-polled, not once) —
//      the connection is a genuine relay route (conn.Stat().Limited == true),
//      not a defaulted label.
//  (2) tracer.Successes() == 0 AND tracer.Attempts() == 0 (EXACT, not bounded
//      > 0) — without a reachable address DCUtR never even initiates — and no
//      "transport:upgraded" event was ever captured.
//  (3) ConnsToPeer(peer) count is stable across the window (no oscillation /
//      thrash from a phantom upgrade/downgrade loop).
//
// Depends on the tracer counters introduced for U1.

import (
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
)

// startNW002RelayNodeWithTracerNoForce installs a collecting tracer (to count
// attempts/successes) but leaves reachability at the production default
// (ForceReachabilityPrivate via the untouched seam = false). This mirrors the
// real app: relay-only, no forced-public.
func startNW002RelayNodeWithTracerNoForce(
	t *testing.T,
	relayAddr string,
	collector *testEventCollector,
	tracer *nodeHolePunchTracer,
) *Node {
	t.Helper()
	hexKey := generateTestKey(t)
	n := New(collector)
	tracer.n = n
	n.SetHolePunchTracerForTests(tracer)
	// NOTE: do NOT force public reachability — this is the relay-only real case.

	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{relayAddr},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start with local circuit relay (nc tracer): %v", err)
	}
	t.Cleanup(func() { n.Stop() })
	if err := n.WaitForRelayConnection(5 * time.Second); err != nil {
		t.Fatalf("%s did not warm local relay: %v", n.PeerId(), err)
	}
	reserveLocalRelay(t, n, relayAddr)
	return n
}

func TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping relay-only negative-control test in -short mode")
	}

	_, relayAddr := startNW002LocalCircuitRelay(t)

	tracerA := newNodeHolePunchTracer(nil)
	tracerB := newNodeHolePunchTracer(nil)
	capA := &testEventCollector{}
	capB := &testEventCollector{}

	nodeA := startNW002RelayNodeWithTracerNoForce(t, relayAddr, capA, tracerA)
	nodeB := startNW002RelayNodeWithTracerNoForce(t, relayAddr, capB, tracerB)

	// Force relay-only: drop any direct route state, then dial via the circuit.
	clearNW002DirectRouteState(t, nodeA, nodeB)
	assertNW002NoDirectPeerstoreAddrs(t, nodeA, nodeB)
	if err := nodeA.DialPeerViaRelay(nodeB.PeerId()); err != nil {
		t.Fatalf("nodeA circuit dial to nodeB: %v", err)
	}
	// The connection must be a genuine limited/circuit conn right after dial.
	assertNW002LimitedCircuitConn(t, nodeA, nodeB)

	// Send a real chat message over the circuit so the path is exercised, not idle.
	message := "I1-NC relay-only ping"
	result, err := nodeA.SendMessageWithTransport(nodeB.PeerId(), message, 5000)
	if err != nil {
		t.Fatalf("nodeA SendMessageWithTransport over forced circuit: %v", err)
	}
	if result.Transport != "relay" {
		t.Fatalf("SendMessageWithTransport transport = %q, want relay", result.Transport)
	}
	received := waitForCollectedEvent(t, capB, "message:received", 5*time.Second)
	if got, _ := received["content"].(string); got != message {
		t.Fatalf("receiver message content = %q, want %q", got, message)
	}
	if got, _ := received["transport"].(string); got != "relay" {
		t.Fatalf("receiver message transport = %q, want relay", got)
	}

	targetID, err := peer.Decode(nodeB.PeerId())
	if err != nil {
		t.Fatalf("decode nodeB peer ID: %v", err)
	}

	// Snapshot the initial connection count, then poll the window.
	host := nodeA.Host()
	if host == nil {
		t.Fatal("nodeA host is nil")
	}
	initialConnCount := len(host.Network().ConnsToPeer(targetID))
	if initialConnCount == 0 {
		t.Fatal("nodeA has no connection to nodeB after circuit dial")
	}

	deadline := time.Now().Add(4 * time.Second)
	for time.Now().Before(deadline) {
		// (1) Limited circuit conn must hold THROUGHOUT the window.
		assertNW002LimitedCircuitConn(t, nodeA, nodeB)

		// (2) No success/attempt counted, ever.
		if got := tracerA.Successes(); got != 0 {
			t.Fatalf("tracerA.Successes() = %d, want EXACTLY 0 (relay-only, no reachable addr)", got)
		}
		if got := tracerA.Attempts(); got != 0 {
			t.Fatalf("tracerA.Attempts() = %d, want EXACTLY 0 (DCUtR never initiates without a reachable addr)", got)
		}
		if got := tracerB.Successes(); got != 0 {
			t.Fatalf("tracerB.Successes() = %d, want EXACTLY 0 (relay-only, no reachable addr)", got)
		}
		if got := tracerB.Attempts(); got != 0 {
			t.Fatalf("tracerB.Attempts() = %d, want EXACTLY 0 (DCUtR never initiates without a reachable addr)", got)
		}
		if got := capA.collectEvents("transport:upgraded"); len(got) != 0 {
			t.Fatalf("captured %d transport:upgraded events, want 0: %+v", len(got), got)
		}
		if got := capB.collectEvents("transport:upgraded"); len(got) != 0 {
			t.Fatalf("nodeB captured %d transport:upgraded events, want 0: %+v", len(got), got)
		}

		// (3) Connection count is stable — no oscillation/thrash.
		if got := len(host.Network().ConnsToPeer(targetID)); got != initialConnCount {
			t.Fatalf("ConnsToPeer count oscillated: initial=%d now=%d (phantom upgrade/downgrade thrash)", initialConnCount, got)
		}

		time.Sleep(100 * time.Millisecond)
	}

	// Final EXACT assertions after the window.
	if got := tracerA.Attempts(); got != 0 {
		t.Fatalf("final tracerA.Attempts() = %d, want 0", got)
	}
	if got := tracerA.Successes(); got != 0 {
		t.Fatalf("final tracerA.Successes() = %d, want 0", got)
	}
	if got := tracerB.Attempts(); got != 0 {
		t.Fatalf("final tracerB.Attempts() = %d, want 0", got)
	}
	if got := tracerB.Successes(); got != 0 {
		t.Fatalf("final tracerB.Successes() = %d, want 0", got)
	}
	if got := capA.collectEvents("holepunch:success"); len(got) != 0 {
		t.Fatalf("final: nodeA captured %d holepunch:success events, want 0", len(got))
	}
	if got := capB.collectEvents("holepunch:success"); len(got) != 0 {
		t.Fatalf("final: nodeB captured %d holepunch:success events, want 0", len(got))
	}
	if got := capA.collectEvents("transport:upgraded"); len(got) != 0 {
		t.Fatalf("final: nodeA captured %d transport:upgraded events, want 0", len(got))
	}
	if got := capB.collectEvents("transport:upgraded"); len(got) != 0 {
		t.Fatalf("final: nodeB captured %d transport:upgraded events, want 0", len(got))
	}
}
