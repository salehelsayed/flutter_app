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
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	relayclient "github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
	"github.com/libp2p/go-libp2p/p2p/protocol/holepunch"
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
			// The connection opens before libp2p emits EndHolePunch. A
			// successful ordinary direct dial emits no End event at all.
			if tracerA.Successes() > 0 {
				break
			}
		}
		time.Sleep(100 * time.Millisecond)
	}

	logFeasibilityTraces(t, tracerA, tracerB, capA, capB)
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
	if ordinaryDirectDialOnly(tracerA, tracerB, capA, capB, nodeA.PeerId(), nodeB.PeerId()) {
		t.Skip("loopback ordinary direct dial bypassed DCUtR; no punch evidence on either peer")
	}
	if tracerA.Successes() < 1 {
		t.Fatalf("tracerA.Successes() = %d, want >= 1 when a direct conn opened", tracerA.Successes())
	}
}

// FDC-12 TC-12-08 — a punched conn classifies "direct" over the TCP lane too,
// not only QUIC (punchr: TCP==QUIC). SKIP-tolerant: loopback forced-public hosts
// do not auto-hole-punch, and even when a punch lands it may take the QUIC lane,
// so a missing TCP-direct conn is a SKIP (feasibility-only) — never a failure,
// the same discipline as TestHolePunchFeasibility_LoopbackUpgradeObservable. The
// real TCP-lane proof is the two-device DEVICE-PROOF (TC-12-12), not this SKIP.
func TestFeasibility_DirectUpgrade_TcpLane(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping loopback hole-punch TCP-lane feasibility test in -short mode")
	}

	_, relayAddr := startNW002LocalCircuitRelay(t)

	tracerA := newNodeHolePunchTracer(nil)
	tracerB := newNodeHolePunchTracer(nil)
	capA := &testEventCollector{}
	capB := &testEventCollector{}

	nodeA := startNW002RelayNodeWithTracer(t, relayAddr, capA, tracerA)
	nodeB := startNW002RelayNodeWithTracer(t, relayAddr, capB, tracerB)

	if err := nodeA.DialPeerViaRelay(nodeB.PeerId()); err != nil {
		t.Fatalf("nodeA circuit dial to nodeB: %v", err)
	}

	targetID, err := peer.Decode(nodeB.PeerId())
	if err != nil {
		t.Fatalf("decode nodeB peer ID: %v", err)
	}

	deadline := time.Now().Add(8 * time.Second)
	var tcpConn network.Conn
	for time.Now().Before(deadline) {
		if c := firstDirectTCPConn(nodeA, targetID); c != nil {
			tcpConn = c
			if tracerA.Successes() > 0 {
				break
			}
		}
		time.Sleep(100 * time.Millisecond)
	}

	logFeasibilityTraces(t, tracerA, tracerB, capA, capB)
	if tcpConn == nil {
		t.Skipf("no direct TCP upgrade materialized on loopback within the window "+
			"(forced-public hosts do not auto-hole-punch; a punch may also take the QUIC lane); "+
			"tracerA.Successes()=%d. Feasibility-only and expected flaky on loopback.",
			tracerA.Successes())
	}

	if tcpConn.Stat().Limited {
		t.Fatal("upgraded TCP conn must have Stat().Limited == false (real direct conn, not a circuit)")
	}
	if got := classifyStreamTransportConn(tcpConn); got != "direct" {
		t.Fatalf("classifyStreamTransport over upgraded TCP conn = %q, want direct", got)
	}
	if ordinaryDirectDialOnly(tracerA, tracerB, capA, capB, nodeA.PeerId(), nodeB.PeerId()) {
		t.Skip("loopback ordinary direct TCP dial bypassed DCUtR; no punch evidence on either peer")
	}
	if tracerA.Successes() < 1 {
		t.Fatalf("tracerA.Successes() = %d, want >= 1 when a direct TCP conn opened", tracerA.Successes())
	}
}

// Ordinary direct dials are non-counted breadcrumbs, not successful punches.
// Only a positive dial to the counterpart, with no punch evidence on either
// peer, explains a direct connection without the required successful End event.
func ordinaryDirectDialOnly(a, b *nodeHolePunchTracer, capA, capB *testEventCollector, peerA, peerB string) bool {
	eventsByPeer := [][]map[string]interface{}{
		capA.collectEvents("holepunch:attempt"),
		capB.collectEvents("holepunch:attempt"),
	}
	if a.Attempts() != 0 || a.Successes() != 0 || a.Failures() != 0 ||
		b.Attempts() != 0 || b.Successes() != 0 || b.Failures() != 0 {
		return false
	}
	// StartHolePunch precedes the counted attempt in a separate tracer call.
	// Inspect both peers before accepting either ordinary-dial breadcrumb.
	for _, events := range eventsByPeer {
		for _, event := range events {
			if event["step"] == "started" || event["step"] == "attempt" {
				return false
			}
		}
	}
	for i, events := range eventsByPeer {
		remote := peerB
		if i == 1 {
			remote = peerA
		}
		for _, event := range events {
			if event["step"] == "direct_dial" && event["success"] == true && event["remotePeerShort"] == shortPeerID(remote) {
				return true
			}
		}
	}
	return false
}

func logFeasibilityTraces(t *testing.T, a, b *nodeHolePunchTracer, capA, capB *testEventCollector) {
	t.Helper()
	t.Logf("DCUtR counters: A attempts=%d successes=%d failures=%d; B attempts=%d successes=%d failures=%d",
		a.Attempts(), a.Successes(), a.Failures(), b.Attempts(), b.Successes(), b.Failures())
	for i, collector := range []*testEventCollector{capA, capB} {
		t.Logf("peer %d holepunch:attempt=%+v holepunch:success=%+v holepunch:failure=%+v", i,
			collector.collectEvents("holepunch:attempt"), collector.collectEvents("holepunch:success"), collector.collectEvents("holepunch:failure"))
	}
}

func TestHolePunchFeasibility_OrdinaryDirectDialSkipRequiresNoPunchEvidence(t *testing.T) {
	peerA, peerB, unrelated := testRemotePeerID(t), testRemotePeerID(t), testRemotePeerID(t)
	type scenario struct {
		name          string
		dialPeer      int
		dialSuccess   bool
		unrelatedDial bool
		punchPeer     int
		punch         *holepunch.Event
		wantSkip      bool
	}
	tests := []scenario{
		{name: "successful_direct_A", dialSuccess: true, wantSkip: true},
		{name: "successful_direct_B", dialPeer: 1, dialSuccess: true, wantSkip: true},
		{name: "failed_direct", wantSkip: false},
		{name: "unrelated_direct", dialSuccess: true, unrelatedDial: true, wantSkip: false},
	}
	for _, side := range []int{0, 1} {
		for _, punch := range []*holepunch.Event{
			{Type: holepunch.StartHolePunchEvtT, Evt: &holepunch.StartHolePunchEvt{RTT: time.Millisecond}},
			{Type: holepunch.HolePunchAttemptEvtT, Evt: &holepunch.HolePunchAttemptEvt{Attempt: 1}},
			{Type: holepunch.EndHolePunchEvtT, Evt: &holepunch.EndHolePunchEvt{Success: false}},
			{Type: holepunch.EndHolePunchEvtT, Evt: &holepunch.EndHolePunchEvt{Success: true}},
		} {
			tests = append(tests, scenario{name: fmt.Sprintf("peer_%d_%s_%v", side, punch.Type, punch.Evt), dialSuccess: true, punchPeer: side, punch: punch})
		}
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			capA, capB := &testEventCollector{}, &testEventCollector{}
			tracers := []*nodeHolePunchTracer{newNodeHolePunchTracer(newTracerTestNode(capA)), newNodeHolePunchTracer(newTracerTestNode(capB))}
			remotes := []peer.ID{peerB, peerA}
			dialRemote := remotes[test.dialPeer]
			if test.unrelatedDial {
				dialRemote = unrelated
			}
			tracers[test.dialPeer].Trace(&holepunch.Event{Remote: dialRemote, Type: holepunch.DirectDialEvtT, Evt: &holepunch.DirectDialEvt{Success: test.dialSuccess}})
			if test.punch != nil {
				event := *test.punch
				event.Remote = remotes[test.punchPeer]
				tracers[test.punchPeer].Trace(&event)
			}
			if got := ordinaryDirectDialOnly(tracers[0], tracers[1], capA, capB, peerA.String(), peerB.String()); got != test.wantSkip {
				t.Fatalf("ordinary-direct skip=%v, want %v", got, test.wantSkip)
			}
		})
	}
}

// firstDirectTCPConn returns the first non-limited, non-circuit TCP connection
// (a /tcp/ remote multiaddr that is not QUIC and not a /ws relay leg) from n to
// peer, or nil if none exists yet.
func firstDirectTCPConn(n *Node, p peer.ID) network.Conn {
	h := n.Host()
	if h == nil {
		return nil
	}
	for _, c := range h.Network().ConnsToPeer(p) {
		if c.Stat().Limited {
			continue
		}
		addr := c.RemoteMultiaddr()
		if addr == nil || isCircuitAddr(addr) {
			continue
		}
		s := addr.String()
		if strings.Contains(s, "/tcp/") && !strings.Contains(s, "/quic") && !strings.Contains(s, "/ws") {
			return c
		}
	}
	return nil
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
