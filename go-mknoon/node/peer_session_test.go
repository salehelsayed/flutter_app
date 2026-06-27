package node

import (
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/p2p/protocol/holepunch"
	ma "github.com/multiformats/go-multiaddr"
)

// psCircuitAddr / psQuicAddr / psTcpAddr are the three address shapes the
// FDC-12 best-conn selector must rank: a /p2p-circuit relay leg (limited) and
// two equal-rank direct legs (QUIC over UDP, TCP).
func psCircuitAddr(t *testing.T) ma.Multiaddr {
	return psMustMultiaddr(t, "/ip4/203.0.113.10/tcp/4001/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g/p2p-circuit")
}
func psQuicAddr(t *testing.T) ma.Multiaddr {
	return psMustMultiaddr(t, "/ip4/192.168.1.55/udp/4001/quic-v1")
}
func psTcpAddr(t *testing.T) ma.Multiaddr {
	return psMustMultiaddr(t, "/ip4/192.168.1.55/tcp/4001")
}
func psMustMultiaddr(t *testing.T, s string) ma.Multiaddr {
	t.Helper()
	a, err := ma.NewMultiaddr(s)
	if err != nil {
		t.Fatalf("multiaddr %q: %v", s, err)
	}
	return a
}

// FDC-12 TC-12-03 — the session Notifiee re-points connections[peer] onto the
// direct conn INDEPENDENTLY of the holepunch tracer. libp2p does not re-fire
// EvtPeerConnectednessChanged when a punch opens a second (direct) conn to an
// already-connected peer, so the EventBus map goes stale on /p2p-circuit; the
// Notifiee closes that gap.
func TestPeerSession_RepointsToDirectConn(t *testing.T) {
	collector := &testEventCollector{}
	n := New(collector)
	remote := testRemotePeerID(t)
	key := remote.String()

	// Stale circuit entry, exactly as watchConnectionEvents seeds it on the
	// initial relay connect.
	n.connections[key] = connectionInfo{
		PeerId:  key,
		Address: psCircuitAddr(t).String(),
		Limited: true,
	}

	// A second, NON-circuit (direct QUIC) conn appears. Drive the re-point WITHOUT
	// firing any tracer EndHolePunchEvt — the distinct-trigger discriminator that
	// proves this is the Notifiee path, not markPeerUpgradedToDirect's tracer hook.
	conns := []network.Conn{&stubStreamConn{remotePeer: remote, remoteMultiaddr: psQuicAddr(t)}}
	n.repointPeerToBestConn(remote, conns)

	info := n.connections[key]
	if info.Limited {
		t.Fatalf("connections[peer].Limited = true after upgrade, want false")
	}
	if info.Address != psQuicAddr(t).String() {
		t.Fatalf("connections[peer].Address = %q, want the direct QUIC addr %q", info.Address, psQuicAddr(t).String())
	}

	upgrades := collector.collectEvents("transport:upgraded")
	if len(upgrades) != 1 {
		t.Fatalf("expected exactly 1 transport:upgraded, got %d: %+v", len(upgrades), upgrades)
	}
	if u := upgrades[0]; u["fromTransport"] != "relay" || u["toTransport"] != "direct" {
		t.Fatalf("transport:upgraded from/to = %v/%v, want relay/direct", u["fromTransport"], u["toTransport"])
	}

	// Discriminator: the re-point must NOT go through the tracer success path, and
	// must NOT masquerade as an initial peer:connected.
	if got := collector.collectEvents("holepunch:success"); len(got) != 0 {
		t.Fatalf("holepunch:success emitted (%d) — re-point must be independent of the tracer", len(got))
	}
	if got := collector.collectEvents("peer:connected"); len(got) != 0 {
		t.Fatalf("repoint emitted peer:connected (%d), want none (initial conns own that event)", len(got))
	}
}

// FDC-12 TC-12-04 — TCP-direct and QUIC-direct rank equal, both above circuit
// (punchr: TCP==QUIC). The best-conn selector prefers any non-circuit conn over
// the limited relay leg.
func TestPeerSession_PrefersTcpOrQuicOverCircuit(t *testing.T) {
	remote := testRemotePeerID(t)
	circuitConn := &stubStreamConn{remotePeer: remote, remoteMultiaddr: psCircuitAddr(t)}
	tcpConn := &stubStreamConn{remotePeer: remote, remoteMultiaddr: psTcpAddr(t)}
	quicConn := &stubStreamConn{remotePeer: remote, remoteMultiaddr: psQuicAddr(t)}

	// circuit + TCP + QUIC → a non-circuit conn wins, never the circuit.
	addr, limited, ok := selectBestConnAddr([]network.Conn{circuitConn, tcpConn, quicConn})
	if !ok || limited || addr == psCircuitAddr(t).String() {
		t.Fatalf("selectBestConnAddr(circuit,tcp,quic) → addr=%q limited=%v ok=%v, want a direct (non-circuit) addr", addr, limited, ok)
	}

	// circuit + TCP only → TCP (a direct leg) chosen, proving TCP is accepted
	// equal-rank to QUIC (a QUIC-only selector would keep the circuit).
	addr2, limited2, ok2 := selectBestConnAddr([]network.Conn{circuitConn, tcpConn})
	if !ok2 || limited2 || addr2 != psTcpAddr(t).String() {
		t.Fatalf("selectBestConnAddr(circuit,tcp) → %q limited=%v, want the TCP direct addr %q", addr2, limited2, psTcpAddr(t).String())
	}

	// circuit only → circuit, limited=true (no direct available).
	addr3, limited3, ok3 := selectBestConnAddr([]network.Conn{circuitConn})
	if !ok3 || !limited3 || addr3 != psCircuitAddr(t).String() {
		t.Fatalf("selectBestConnAddr(circuit) → %q limited=%v ok=%v, want the circuit addr limited=true", addr3, limited3, ok3)
	}

	// no conns → ok=false (deletion is the EventBus's job, not the selector's).
	if _, _, ok4 := selectBestConnAddr(nil); ok4 {
		t.Fatalf("selectBestConnAddr(nil) ok=true, want false")
	}
}

// FDC-12 TC-12-05 — when the direct conn closes but a circuit survives, the
// session re-points to the relay (graceful downgrade) and emits exactly one
// transport:downgraded. The peer is NOT deleted (delete only on last conn,
// preserving the watchConnectionEvents semantics).
func TestPeerSession_DirectClose_FallsBackToRelay(t *testing.T) {
	collector := &testEventCollector{}
	n := New(collector)
	remote := testRemotePeerID(t)
	key := remote.String()

	// Post-upgrade state: on the direct leg.
	n.connections[key] = connectionInfo{PeerId: key, Address: psQuicAddr(t).String(), Limited: false}

	// Direct conn dies; only the circuit survives.
	conns := []network.Conn{&stubStreamConn{remotePeer: remote, remoteMultiaddr: psCircuitAddr(t)}}
	n.repointPeerToBestConn(remote, conns)

	info, ok := n.connections[key]
	if !ok {
		t.Fatalf("peer deleted on direct-close, want re-point to surviving circuit (delete only on last conn)")
	}
	if !info.Limited {
		t.Fatalf("connections[peer].Limited = false after downgrade, want true (back on circuit)")
	}
	if info.Address != psCircuitAddr(t).String() {
		t.Fatalf("connections[peer].Address = %q, want the surviving circuit addr", info.Address)
	}

	downgrades := collector.collectEvents("transport:downgraded")
	if len(downgrades) != 1 {
		t.Fatalf("expected exactly 1 transport:downgraded, got %d: %+v", len(downgrades), downgrades)
	}
	if got := collector.collectEvents("peer:disconnected"); len(got) != 0 {
		t.Fatalf("downgrade emitted peer:disconnected (%d), want none (peer still connected via circuit)", len(got))
	}
}

// FDC-12 TC-12-06 — no phantom upgrade/downgrade thrash. Repeated identical
// Connected callbacks for the SAME direct conn emit exactly ONE transport:upgraded
// (idempotent: one event per real circuit<->direct transition). Mirrors the
// holepunch_negative_control_test.go stability invariant for the new Notifiee.
func TestPeerSession_NoThrash_StableConnCount(t *testing.T) {
	collector := &testEventCollector{}
	n := New(collector)
	remote := testRemotePeerID(t)
	key := remote.String()
	n.connections[key] = connectionInfo{PeerId: key, Address: psCircuitAddr(t).String(), Limited: true}

	conns := []network.Conn{&stubStreamConn{remotePeer: remote, remoteMultiaddr: psQuicAddr(t)}}
	for i := 0; i < 5; i++ {
		n.repointPeerToBestConn(remote, conns)
	}

	if got := collector.collectEvents("transport:upgraded"); len(got) != 1 {
		t.Fatalf("expected exactly 1 transport:upgraded across 5 identical callbacks, got %d", len(got))
	}
	if info := n.connections[key]; info.Limited {
		t.Fatalf("connections[peer].Limited = true after idempotent upgrades, want false")
	}
}

// FDC-12 — exactly one transport:upgraded across the tracer + Notifiee paths.
// On a real punch BOTH the holepunch tracer (EndHolePunchEvt{Success}) and the
// session Notifiee observe the same upgrade. The tracer gates its emit on
// markPeerUpgradedToDirect actually flipping the circuit entry, and the Notifiee
// gates on the wasLimited transition, so whichever flips it first emits and the
// other is suppressed — exactly once, in either arrival order.
func TestPeerSession_TracerAndNotifiee_NoDoubleUpgradeEmit(t *testing.T) {
	seedCircuit := func(n *Node, key string) {
		n.connections[key] = connectionInfo{
			PeerId:  key,
			Address: psCircuitAddr(t).String(),
			Limited: true,
		}
	}

	t.Run("notifiee_then_tracer", func(t *testing.T) {
		collector := &testEventCollector{}
		n := New(collector)
		tracer := newNodeHolePunchTracer(n)
		remote := testRemotePeerID(t)
		seedCircuit(n, remote.String())

		// Notifiee observes the new direct conn first (flips circuit->direct, emits).
		n.repointPeerToBestConn(remote, []network.Conn{&stubStreamConn{remotePeer: remote, remoteMultiaddr: psQuicAddr(t)}})
		// Then the tracer fires for the SAME punch — must NOT double-emit.
		tracer.Trace(&holepunch.Event{
			Remote: remote,
			Type:   holepunch.EndHolePunchEvtT,
			Evt:    &holepunch.EndHolePunchEvt{Success: true, EllapsedTime: 5 * time.Millisecond},
		})

		if got := collector.collectEvents("transport:upgraded"); len(got) != 1 {
			t.Fatalf("notifiee-then-tracer: expected exactly 1 transport:upgraded, got %d: %+v", len(got), got)
		}
	})

	t.Run("tracer_then_notifiee", func(t *testing.T) {
		collector := &testEventCollector{}
		n := New(collector)
		tracer := newNodeHolePunchTracer(n)
		remote := testRemotePeerID(t)
		seedCircuit(n, remote.String())

		// Tracer flips circuit->direct first (emits, with rttMs/elapsedMs).
		tracer.Trace(&holepunch.Event{
			Remote: remote,
			Type:   holepunch.EndHolePunchEvtT,
			Evt:    &holepunch.EndHolePunchEvt{Success: true, EllapsedTime: 5 * time.Millisecond},
		})
		// Then the Notifiee observes the direct conn — already direct, must NOT re-emit.
		n.repointPeerToBestConn(remote, []network.Conn{&stubStreamConn{remotePeer: remote, remoteMultiaddr: psQuicAddr(t)}})

		if got := collector.collectEvents("transport:upgraded"); len(got) != 1 {
			t.Fatalf("tracer-then-notifiee: expected exactly 1 transport:upgraded, got %d: %+v", len(got), got)
		}
	})
}

// FDC-12 — the session Notifiee never CREATES a connections entry; entry
// lifecycle (create on connect, delete on last disconnect) stays owned by the
// EventBus watchConnectionEvents path. Re-pointing an unknown peer is a no-op so
// the two paths never race the map's lifecycle.
func TestPeerSession_UnknownPeer_NoCreate(t *testing.T) {
	collector := &testEventCollector{}
	n := New(collector)
	remote := testRemotePeerID(t)

	conns := []network.Conn{&stubStreamConn{remotePeer: remote, remoteMultiaddr: psQuicAddr(t)}}
	n.repointPeerToBestConn(remote, conns)

	if _, ok := n.connections[remote.String()]; ok {
		t.Fatalf("repoint created a connections entry for an unknown peer, want no-op (EventBus owns creation)")
	}
	if got := collector.collectEvents("transport:upgraded"); len(got) != 0 {
		t.Fatalf("repoint emitted transport:upgraded (%d) for an unknown peer, want none", len(got))
	}
}
