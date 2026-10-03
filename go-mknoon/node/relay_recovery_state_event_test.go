package node

import (
	"fmt"
	"testing"
)

func newRecoveryStateEventNode(t *testing.T) (*Node, *testEventCollector, string) {
	t.Helper()
	collector := &testEventCollector{}
	n := New(collector)
	relayPeer := fakePeerID("relay-recovery-state")

	n.mu.Lock()
	n.relayPeerOrder = append(n.relayPeerOrder[:0], relayPeer)
	n.connections[relayPeer.String()] = connectionInfo{PeerId: relayPeer.String()}
	n.mu.Unlock()
	n.relaySessionMgr.InitRelayPeer(relayPeer)

	circuitAddr := fmt.Sprintf("/ip4/127.0.0.1/tcp/19036/p2p/%s/p2p-circuit/p2p/%s", relayPeer, "self-recovery-state")
	n.syncRelaySessionFromRuntime("addresses_updated", []string{circuitAddr})
	if got := len(collector.collectEvents("relay:state")); got != 1 {
		t.Fatalf("setup relay:state event count = %d, want 1", got)
	}
	return n, collector, circuitAddr
}

// A successful in-place refresh must not report "recovering" to Flutter:
// Flutter treats that state as an outage and starts group recovery passes.
func TestRelayRecoveryReportsOnlySettledState(t *testing.T) {
	n, collector, circuitAddr := newRecoveryStateEventNode(t)
	mgr := n.relaySessionMgr

	recovery, isNew := mgr.BeginRecovery()
	if !isNew {
		t.Fatal("BeginRecovery isNew = false, want true")
	}
	n.runRelayRecovery(mgr, recovery, func() (*RecoveryResult, error) {
		// What refreshRelaySessionOwned does while it still owns recovery.
		n.syncRelaySessionFromRuntime("refresh_relay_session", []string{circuitAddr})
		n.emitRelayStateEvent("group_recovery_acknowledged")
		if got := len(collector.collectEvents("relay:state")); got != 1 {
			t.Fatalf("relay:state events during recovery = %d, want none new", got-1)
		}
		return &RecoveryResult{RecoveryMode: "in_place", Success: true}, nil
	})

	events := collector.collectEvents("relay:state")
	if len(events) != 2 {
		t.Fatalf("relay:state event count = %d, want 2: %v", len(events), events)
	}
	for _, event := range events {
		if event["relayState"] == string(AggregateRelayRecovering) {
			t.Fatalf("relay:state reported recovering: %v", event)
		}
	}
	settled := events[1]
	if settled["reason"] != "relay_recovery_complete" || settled["relayState"] != string(AggregateRelayOnline) {
		t.Fatalf("settled event = %v, want online relay_recovery_complete", settled)
	}
}

// A recovery that ends with the relay gone still reports the real state once.
func TestRelayRecoveryReportsFailedStateAfterCompletion(t *testing.T) {
	n, collector, _ := newRecoveryStateEventNode(t)
	mgr := n.relaySessionMgr
	relayPeer := fakePeerID("relay-recovery-state")

	recovery, _ := mgr.BeginRecovery()
	n.runRelayRecovery(mgr, recovery, func() (*RecoveryResult, error) {
		n.mu.Lock()
		delete(n.connections, relayPeer.String())
		n.mu.Unlock()
		n.syncRelaySessionFromRuntime("refresh_relay_session", nil)
		return &RecoveryResult{RecoveryMode: "in_place", Success: false, ErrorCode: "REFRESH_FAILED"}, nil
	})

	events := collector.collectEvents("relay:state")
	if len(events) != 2 {
		t.Fatalf("relay:state event count = %d, want 2: %v", len(events), events)
	}
	settled := events[1]
	if settled["reason"] != "relay_recovery_complete" {
		t.Fatalf("settled reason = %v, want relay_recovery_complete", settled["reason"])
	}
	// With every relay degraded the aggregate state is also "recovering".
	if state := settled["relayState"]; state != string(AggregateRelayRecovering) {
		t.Fatalf("settled relayState = %v, want recovering (all relays degraded)", state)
	}
	if mgr.HealthyRelayCount() != 0 {
		t.Fatalf("healthy relay count = %d, want 0", mgr.HealthyRelayCount())
	}
}

// A panic in the recovery work still releases recovery and reports state.
func TestRelayRecoveryReportsStateAfterPanic(t *testing.T) {
	n, collector, _ := newRecoveryStateEventNode(t)
	mgr := n.relaySessionMgr

	recovery, _ := mgr.BeginRecovery()
	n.runRelayRecovery(mgr, recovery, func() (*RecoveryResult, error) {
		panic("boom")
	})

	if mgr.IsRecovering() {
		t.Fatal("IsRecovering = true after panic, want false")
	}
	events := collector.collectEvents("relay:state")
	if len(events) != 2 || events[1]["reason"] != "relay_recovery_complete" {
		t.Fatalf("relay:state events = %v, want one settled event after the panic", events)
	}
}
