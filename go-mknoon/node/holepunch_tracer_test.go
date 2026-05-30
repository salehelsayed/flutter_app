package node

// NET-REL-02 Option A unit tests for the holepunch EventTracer (instrument-only).
//
// These drive nodeHolePunchTracer.Trace() directly with synthesized
// *holepunch.Event values. No real libp2p host is required: we attach the
// tracer to a bare Node that has only an EventCallback wired so emitEvent
// surfaces telemetry synchronously into a testEventCollector.

import (
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/crypto"
	crand "crypto/rand"

	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/holepunch"
)

// newTracerTestNode returns a minimal Node wired to the given collector so the
// tracer's emitEvent calls land synchronously in the collector (no dispatcher,
// no host). It is safe because Trace()/markPeerUpgradedToDirect only touch
// n.connections (initialized here) and never the unstarted host.
func newTracerTestNode(cb EventCallback) *Node {
	n := New(cb)
	n.peerId = "self-peer"
	return n
}

// testRemotePeerID returns a deterministic-enough valid peer.ID for tracer events.
func testRemotePeerID(t *testing.T) peer.ID {
	t.Helper()
	priv, _, err := crypto.GenerateEd25519Key(crand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	pid, err := peer.IDFromPrivateKey(priv)
	if err != nil {
		t.Fatalf("peer ID from key: %v", err)
	}
	return pid
}

// U1: attempt + success are counted AND surfaced as telemetry with the expected
// step/fromTransport/toTransport fields.
func TestHolePunchTracer_AttemptThenSuccess_CountsAndEmits(t *testing.T) {
	collector := &testEventCollector{}
	n := newTracerTestNode(collector)
	tracer := newNodeHolePunchTracer(n)

	remote := testRemotePeerID(t)

	tracer.Trace(&holepunch.Event{
		Remote: remote,
		Type:   holepunch.HolePunchAttemptEvtT,
		Evt:    &holepunch.HolePunchAttemptEvt{Attempt: 1},
	})
	tracer.Trace(&holepunch.Event{
		Remote: remote,
		Type:   holepunch.EndHolePunchEvtT,
		Evt: &holepunch.EndHolePunchEvt{
			Success:      true,
			EllapsedTime: 42 * time.Millisecond,
		},
	})

	if got := tracer.Attempts(); got != 1 {
		t.Fatalf("Attempts() = %d, want 1", got)
	}
	if got := tracer.Successes(); got != 1 {
		t.Fatalf("Successes() = %d, want 1", got)
	}
	if got := tracer.Failures(); got != 0 {
		t.Fatalf("Failures() = %d, want 0", got)
	}

	// holepunch:attempt with step=attempt was surfaced.
	attempts := collector.collectEvents("holepunch:attempt")
	if !hasEventWithStep(attempts, "attempt") {
		t.Fatalf("expected holepunch:attempt step=attempt event, got %+v", attempts)
	}

	// holepunch:success with the expected from/to transport labels was surfaced.
	successes := collector.collectEvents("holepunch:success")
	if len(successes) != 1 {
		t.Fatalf("expected exactly 1 holepunch:success event, got %d: %+v", len(successes), successes)
	}
	s := successes[0]
	if s["step"] != "succeeded" {
		t.Fatalf("holepunch:success step = %v, want succeeded", s["step"])
	}
	if s["fromTransport"] != "relay" {
		t.Fatalf("holepunch:success fromTransport = %v, want relay", s["fromTransport"])
	}
	if s["toTransport"] != "direct" {
		t.Fatalf("holepunch:success toTransport = %v, want direct", s["toTransport"])
	}

	// The dedicated relay->direct upgrade signal was also surfaced.
	upgrades := collector.collectEvents("transport:upgraded")
	if len(upgrades) != 1 {
		t.Fatalf("expected exactly 1 transport:upgraded event, got %d: %+v", len(upgrades), upgrades)
	}
}

func TestHolePunchTracer_SuccessClearsStaleLimitedConnectionState(t *testing.T) {
	collector := &testEventCollector{}
	n := newTracerTestNode(collector)
	tracer := newNodeHolePunchTracer(n)
	remote := testRemotePeerID(t)

	staleCircuitAddr := "/ip4/203.0.113.10/tcp/4001/p2p/relay/p2p-circuit/p2p/" + remote.String()
	n.connections[remote.String()] = connectionInfo{
		PeerId:    remote.String(),
		Address:   staleCircuitAddr,
		Direction: "outbound",
		Limited:   true,
	}

	tracer.Trace(&holepunch.Event{
		Remote: remote,
		Type:   holepunch.EndHolePunchEvtT,
		Evt: &holepunch.EndHolePunchEvt{
			Success:      true,
			EllapsedTime: 42 * time.Millisecond,
		},
	})

	if got := tracer.Successes(); got != 1 {
		t.Fatalf("Successes() = %d, want 1", got)
	}
	upgrades := collector.collectEvents("transport:upgraded")
	if len(upgrades) != 1 {
		t.Fatalf("expected exactly 1 transport:upgraded event, got %d: %+v", len(upgrades), upgrades)
	}

	n.mu.RLock()
	info := n.connections[remote.String()]
	n.mu.RUnlock()
	if info.Limited {
		t.Fatalf("connection Limited = true after tracer success, want false: %+v", info)
	}
	if info.Address != staleCircuitAddr {
		t.Fatalf("connection address = %q, want unchanged stale address without a real host conn %q", info.Address, staleCircuitAddr)
	}
}

// U-N1: negative control at the unit level. An attempt followed by a FAILED
// EndHolePunchEvt (and a separate "no End at all" case) must NOT count as a
// success and must NOT emit holepunch:success / transport:upgraded. Proves the
// success detector is not always-true.
func TestHolePunchTracer_FailureAndNoEnd_NoSuccessEmitted(t *testing.T) {
	t.Run("explicit_failure", func(t *testing.T) {
		collector := &testEventCollector{}
		n := newTracerTestNode(collector)
		tracer := newNodeHolePunchTracer(n)
		remote := testRemotePeerID(t)

		tracer.Trace(&holepunch.Event{
			Remote: remote,
			Type:   holepunch.StartHolePunchEvtT,
			Evt:    &holepunch.StartHolePunchEvt{RTT: 10 * time.Millisecond},
		})
		tracer.Trace(&holepunch.Event{
			Remote: remote,
			Type:   holepunch.HolePunchAttemptEvtT,
			Evt:    &holepunch.HolePunchAttemptEvt{Attempt: 1},
		})
		tracer.Trace(&holepunch.Event{
			Remote: remote,
			Type:   holepunch.EndHolePunchEvtT,
			Evt: &holepunch.EndHolePunchEvt{
				Success:      false,
				EllapsedTime: 7 * time.Millisecond,
				Error:        "no good addresses",
			},
		})

		if got := tracer.Successes(); got != 0 {
			t.Fatalf("Successes() = %d, want 0", got)
		}
		if got := tracer.Failures(); got != 1 {
			t.Fatalf("Failures() = %d, want 1", got)
		}
		if got := collector.collectEvents("holepunch:success"); len(got) != 0 {
			t.Fatalf("expected no holepunch:success events, got %+v", got)
		}
		if got := collector.collectEvents("transport:upgraded"); len(got) != 0 {
			t.Fatalf("expected no transport:upgraded events, got %+v", got)
		}
		if got := collector.collectEvents("holepunch:failure"); len(got) != 1 {
			t.Fatalf("expected exactly 1 holepunch:failure event, got %+v", got)
		}
	})

	t.Run("attempt_without_end", func(t *testing.T) {
		collector := &testEventCollector{}
		n := newTracerTestNode(collector)
		tracer := newNodeHolePunchTracer(n)
		remote := testRemotePeerID(t)

		tracer.Trace(&holepunch.Event{
			Remote: remote,
			Type:   holepunch.HolePunchAttemptEvtT,
			Evt:    &holepunch.HolePunchAttemptEvt{Attempt: 1},
		})

		if got := tracer.Successes(); got != 0 {
			t.Fatalf("Successes() = %d, want 0 (no End event observed)", got)
		}
		if got := collector.collectEvents("holepunch:success"); len(got) != 0 {
			t.Fatalf("expected no holepunch:success events, got %+v", got)
		}
		if got := collector.collectEvents("transport:upgraded"); len(got) != 0 {
			t.Fatalf("expected no transport:upgraded events, got %+v", got)
		}
	})
}

func hasEventWithStep(events []map[string]interface{}, step string) bool {
	for _, e := range events {
		if e["step"] == step {
			return true
		}
	}
	return false
}
