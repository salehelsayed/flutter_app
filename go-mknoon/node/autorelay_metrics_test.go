package node

import (
	"fmt"
	"strings"
	"testing"

	"github.com/libp2p/go-libp2p/core/peer"
)

func testRelayCircuitAddr(pid peer.ID) string {
	return fmt.Sprintf(
		"/ip4/1.2.3.4/tcp/1234/p2p/%s/p2p-circuit/p2p/self",
		pid.String(),
	)
}

func TestRelaySessionRuntimeSync_OpensReservationAndEmitsRelayState(t *testing.T) {
	pid := fakePeerID("relay-1")
	collector := &testEventCollector{}
	n := New(collector)
	n.relayPeerOrder = []peer.ID{pid}
	n.connections[pid.String()] = connectionInfo{PeerId: pid.String()}
	n.relaySessionMgr.InitRelayPeer(pid)

	n.syncRelaySessionFromRuntime("test_open", []string{testRelayCircuitAddr(pid)})

	session := n.relaySessionMgr.GetSession(pid)
	if session == nil {
		t.Fatal("expected relay session after runtime sync")
	}
	if session.State != RelayStateReserved {
		t.Fatalf("expected reserved state, got %s", session.State)
	}
	if n.relaySessionMgr.AggregateState() != AggregateRelayOnline {
		t.Fatalf("expected aggregate relay state online, got %s", n.relaySessionMgr.AggregateState())
	}

	events := collector.snapshot()
	if len(events) == 0 {
		t.Fatal("expected relay:state event to be emitted")
	}
	lastEvent := events[len(events)-1]
	if !strings.Contains(lastEvent, `"event":"relay:state"`) {
		t.Fatalf("expected relay:state event, got %s", lastEvent)
	}
	if !strings.Contains(lastEvent, `"relayState":"online"`) {
		t.Fatalf("expected relayState=online in event, got %s", lastEvent)
	}
	if !strings.Contains(lastEvent, `"reason":"test_open"`) {
		t.Fatalf("expected reason=test_open in event, got %s", lastEvent)
	}
}

func TestRelaySessionRuntimeSync_EndsReservationWhenCircuitAddressDisappears(t *testing.T) {
	pid := fakePeerID("relay-1")
	n := NewNode()
	n.relayPeerOrder = []peer.ID{pid}
	n.connections[pid.String()] = connectionInfo{PeerId: pid.String()}
	n.relaySessionMgr.OnReservationOpened(pid)

	n.syncRelaySessionFromRuntime("test_lost_circuit", nil)

	session := n.relaySessionMgr.GetSession(pid)
	if session == nil {
		t.Fatal("expected relay session after runtime sync")
	}
	if session.State != RelayStateDegraded {
		t.Fatalf("expected degraded state after losing circuit address, got %s", session.State)
	}
}

func TestRelaySessionRuntimeSync_IgnoresStaleCircuitAddressWithoutConnectedRelay(t *testing.T) {
	pid := fakePeerID("relay-1")
	n := NewNode()
	n.relayPeerOrder = []peer.ID{pid}
	n.relaySessionMgr.InitRelayPeer(pid)

	n.syncRelaySessionFromRuntime("test_stale_circuit", []string{testRelayCircuitAddr(pid)})

	session := n.relaySessionMgr.GetSession(pid)
	if session == nil {
		t.Fatal("expected relay session after runtime sync")
	}
	if session.State == RelayStateReserved {
		t.Fatalf("stale circuit address without a connected relay should not mark relay reserved")
	}
	if n.relaySessionMgr.AggregateState() == AggregateRelayOnline {
		t.Fatalf("stale circuit address without a connected relay should not make aggregate state online")
	}
}
