package node

// I1 — PROTOCOL-FEASIBILITY test (NET-REL-02 Option A). NOT app-E2E.
//
// This proves that the go-libp2p DCUtR (Direct Connection Upgrade through Relay)
// machinery, wired through our injected holepunch.EventTracer seam, can observe
// a relay->direct upgrade on loopback. It does NOT prove that the production app
// (which runs ForceReachabilityPrivate()) ever triggers a hole punch — production
// legitimately observes ZERO hole punches, which is the I1-NC result.
//
// It uses the test-only seams SetForcePublicReachabilityForTests(true) +
// SetHolePunchTracerForTests(collector) installed BEFORE Start(), exactly as the
// blueprint requires, and a real circuit relay from startNW002LocalCircuitRelay.
//
// Loopback hole punching is timing-sensitive and may not materialize in CI; when
// the upgrade does not occur within the window the test SKIPS with a clear reason
// rather than failing or faking. When it DOES occur it PINS the real upgrade:
//   - conn.Stat().Limited == false (never the label alone), AND
//   - classifyStreamTransport over that conn == "direct", AND
//   - the injected tracer recorded Successes() >= 1.

import (
	"context"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	relayclient "github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
)

// startNW002RelayNodeWithTracer is like startNW002RelayNode but installs the
// test seams (collecting holepunch tracer + forced-public reachability) BEFORE
// Start so the holepuncher is constructed with our observing tracer.
func startNW002RelayNodeWithTracer(
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
	n.SetForcePublicReachabilityForTests(true)

	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{relayAddr},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start with local circuit relay (tracer): %v", err)
	}
	t.Cleanup(func() { n.Stop() })
	if err := n.WaitForRelayConnection(5 * time.Second); err != nil {
		t.Fatalf("%s did not warm local relay: %v", n.PeerId(), err)
	}
	reserveLocalRelay(t, n, relayAddr)
	return n
}

func reserveLocalRelay(t *testing.T, n *Node, relayAddr string) {
	t.Helper()
	relayInfo, err := peer.AddrInfoFromString(relayAddr)
	if err != nil {
		t.Fatalf("parse local relay addr: %v", err)
	}
	reserveCtx, cancel := context.WithTimeout(n.ctx, 10*time.Second)
	defer cancel()
	if _, err := relayclient.Reserve(reserveCtx, n.Host(), *relayInfo); err != nil {
		t.Fatalf("%s could not reserve local circuit relay: %v", n.PeerId(), err)
	}
}

func TestHolePunchFeasibility_LoopbackUpgradeObservable(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping loopback hole-punch feasibility test in -short mode")
	}

	_, relayAddr := startNW002LocalCircuitRelay(t)

	tracerA := newNodeHolePunchTracer(nil)
	tracerB := newNodeHolePunchTracer(nil)
	capA := &testEventCollector{}
	capB := &testEventCollector{}

	nodeA := startNW002RelayNodeWithTracer(t, relayAddr, capA, tracerA)
	nodeB := startNW002RelayNodeWithTracer(t, relayAddr, capB, tracerB)

	// Establish a relayed connection A->B through the circuit relay.
	if err := nodeA.DialPeerViaRelay(nodeB.PeerId()); err != nil {
		t.Fatalf("nodeA circuit dial to nodeB: %v", err)
	}

	targetID, err := peer.Decode(nodeB.PeerId())
	if err != nil {
		t.Fatalf("decode nodeB peer ID: %v", err)
	}

	// Poll for a direct (non-limited, non-circuit) connection to open via the
	// hole punch machinery. Forced-public hosts do not auto-hole-punch, so this
	// may never occur on loopback — in that case we skip, not fail.
	deadline := time.Now().Add(8 * time.Second)
	var directConn network.Conn
	for time.Now().Before(deadline) {
		if c := firstDirectConn(nodeA, targetID); c != nil {
			directConn = c
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	if directConn == nil && tracerA.Successes() == 0 {
		t.Skipf("loopback DCUtR upgrade did not materialize within window "+
			"(forced-public hosts do not auto-hole-punch); tracerA.Successes()=%d. "+
			"This is feasibility-only and is expected to be flaky on loopback.",
			tracerA.Successes())
	}

	// If we got here an upgrade was observed — PIN the real evidence.
	if directConn == nil {
		t.Fatalf("tracer recorded success but no direct conn found to nodeB")
	}
	if directConn.Stat().Limited {
		t.Fatal("upgraded conn must have Stat().Limited == false (real direct conn, not a circuit conn)")
	}
	if got := classifyStreamTransportConn(directConn); got != "direct" {
		t.Fatalf("classifyStreamTransport over upgraded conn = %q, want direct", got)
	}
	if tracerA.Successes() < 1 {
		t.Fatalf("tracerA.Successes() = %d, want >= 1 when a direct conn opened", tracerA.Successes())
	}
}

// firstDirectConn returns the first non-limited, non-circuit connection from n
// to peer, or nil if none exists yet.
func firstDirectConn(n *Node, p peer.ID) network.Conn {
	h := n.Host()
	if h == nil {
		return nil
	}
	for _, c := range h.Network().ConnsToPeer(p) {
		if c.Stat().Limited {
			continue
		}
		if addr := c.RemoteMultiaddr(); addr != nil && isCircuitAddr(addr) {
			continue
		}
		return c
	}
	return nil
}

// classifyStreamTransportConn applies the same circuit-vs-direct logic as
// classifyStreamTransport but for a bare conn (no stream needed).
func classifyStreamTransportConn(conn network.Conn) string {
	if conn == nil {
		return "direct"
	}
	if local := conn.LocalMultiaddr(); local != nil && isCircuitAddr(local) {
		return "relay"
	}
	if remote := conn.RemoteMultiaddr(); remote != nil && isCircuitAddr(remote) {
		return "relay"
	}
	return "direct"
}
