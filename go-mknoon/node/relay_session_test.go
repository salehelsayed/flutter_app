package node

import (
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
)

// fakePeerID generates a deterministic peer ID for tests. This is a lightweight
// test helper that avoids real key generation for pure state-machine tests.
func fakePeerID(name string) peer.ID {
	return peer.ID(name)
}

// --- Phase 4 RED Tests: Relay Session Manager ---

func TestRelaySession_TransitionsToReservedOnReservationOpened(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-1")

	m.InitRelayPeer(pid)
	s := m.GetSession(pid)
	if s == nil {
		t.Fatal("expected session after InitRelayPeer")
	}
	if s.State != RelayStateDisconnected {
		t.Errorf("initial state should be disconnected, got %s", s.State)
	}

	m.OnReservationOpened(pid)
	s = m.GetSession(pid)
	if s.State != RelayStateReserved {
		t.Errorf("state should be reserved after OnReservationOpened, got %s", s.State)
	}
	if s.LastReservedAt.IsZero() {
		t.Error("LastReservedAt should be set after reservation opened")
	}
	if m.AggregateState() != AggregateRelayOnline {
		t.Errorf("aggregate state should be online after reservation, got %s", m.AggregateState())
	}
}

func TestRelaySession_TransitionsToDegradedOnReservationEnded(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-1")

	// Start with a healthy reservation.
	m.OnReservationOpened(pid)
	if m.AggregateState() != AggregateRelayOnline {
		t.Fatalf("expected online after reservation opened, got %s", m.AggregateState())
	}

	// Reservation ends.
	m.OnReservationEnded(pid)
	s := m.GetSession(pid)
	if s.State != RelayStateDegraded {
		t.Errorf("state should be degraded after reservation ended, got %s", s.State)
	}
	if m.AggregateState() == AggregateRelayOnline {
		t.Error("aggregate state should not be online after reservation ended")
	}
}

func TestRelaySession_RequestFailureDoesNotRestartHostImmediately(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-1")

	// Simulate a reservation request failure.
	m.OnRequestFailed(pid, fmt.Errorf("connection refused"))

	s := m.GetSession(pid)
	if s == nil {
		t.Fatal("expected session to be created on failure")
	}
	if s.FailCount != 1 {
		t.Errorf("expected failCount=1, got %d", s.FailCount)
	}

	// The state should NOT be "watchdog_restart" — a single failure
	// does not warrant host replacement.
	if m.AggregateState() == AggregateRelayWatchdogRestart {
		t.Error("single request failure should not trigger watchdog restart")
	}

	// Simulate multiple failures — still should not auto-restart host.
	for i := 0; i < 5; i++ {
		m.OnRequestFailed(pid, fmt.Errorf("failure %d", i))
	}
	if m.AggregateState() == AggregateRelayWatchdogRestart {
		t.Error("multiple request failures should not auto-trigger watchdog restart")
	}
	s = m.GetSession(pid)
	if s.FailCount != 6 { // 1 initial + 5 more
		t.Errorf("expected failCount=6, got %d", s.FailCount)
	}
}

func TestRelaySession_ReportsHealthyWhenReservationAndConnectednessAgree(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-1")

	// Not healthy when no sessions exist.
	if m.IsHealthy() {
		t.Error("should not be healthy with no sessions")
	}

	// Not healthy when connected but no reservation.
	m.OnConnected(pid)
	addrsWithCircuit := []string{"/ip4/1.2.3.4/tcp/1234/p2p/relay-1/p2p-circuit/p2p/self"}
	if m.ReportsHealthyWithReservation(addrsWithCircuit) {
		t.Error("should not report healthy with circuit address but no reservation")
	}

	// Healthy when reserved and circuit address present.
	m.OnReservationOpened(pid)
	if !m.ReportsHealthyWithReservation(addrsWithCircuit) {
		t.Error("should report healthy when reservation and circuit addresses agree")
	}
	if !m.IsHealthy() {
		t.Error("should be healthy when reservation is active")
	}

	// Not healthy if circuit addresses disappear even with reservation.
	addrsNoCircuit := []string{"/ip4/1.2.3.4/tcp/1234"}
	if m.ReportsHealthyWithReservation(addrsNoCircuit) {
		t.Error("should not report healthy without circuit addresses even with reservation")
	}
}

func TestRelaySession_IgnoresStaleCircuitAddressesWithoutReservation(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-peer-id")

	// Initialize without reservation.
	m.InitRelayPeer(pid)

	circuitAddrs := []string{"/ip4/1.2.3.4/tcp/1234/p2p/relay-peer-id/p2p-circuit/p2p/self"}

	// Without reservation, circuit addresses are stale.
	if !m.CircuitAddressesAreStale(circuitAddrs) {
		t.Error("circuit addresses should be considered stale without reservation")
	}

	// After reservation, they are not stale.
	m.OnReservationOpened(pid)
	if m.CircuitAddressesAreStale(circuitAddrs) {
		t.Error("circuit addresses should not be stale after reservation opened")
	}

	// After reservation ends, they become stale again.
	m.OnReservationEnded(pid)
	if !m.CircuitAddressesAreStale(circuitAddrs) {
		t.Error("circuit addresses should be stale after reservation ended")
	}
}

func TestRelaySession_CoalescesConcurrentRecoveryRequests(t *testing.T) {
	m := NewRelaySessionManager()

	// First caller gets the recovery lock.
	ch1, isNew1 := m.BeginRecovery()
	if !isNew1 {
		t.Fatal("first caller should get isNew=true")
	}
	if ch1 == nil {
		t.Fatal("first caller should get a non-nil channel")
	}
	if !m.IsRecovering() {
		t.Error("should be recovering after BeginRecovery")
	}

	// Second concurrent caller should share the same recovery.
	ch2, isNew2 := m.BeginRecovery()
	if isNew2 {
		t.Error("second caller should get isNew=false (coalesced)")
	}
	if ch2 != ch1 {
		t.Error("second caller should get the same channel as first")
	}

	// Third caller — same behavior.
	ch3, isNew3 := m.BeginRecovery()
	if isNew3 {
		t.Error("third caller should get isNew=false")
	}
	if ch3 != ch1 {
		t.Error("third caller should share the same channel")
	}

	// Complete recovery — the result is sent on the buffered channel.
	result := &RecoveryResult{
		RecoveryMode:    "in_place",
		Success:         true,
		RelayState:      "online",
		HealthyRelayCount: 1,
	}

	m.CompleteRecovery(result)

	// Since ch1 == ch2 == ch3 (same channel), and the channel is
	// buffered(1) + closed, the first read gets the result and
	// subsequent reads from the closed channel get nil.
	r1 := <-ch1
	if r1 == nil {
		t.Fatal("first reader should have received the result")
	}
	if r1.RecoveryMode != "in_place" {
		t.Errorf("expected recoveryMode=in_place, got %s", r1.RecoveryMode)
	}

	// After completion, should not be recovering.
	if m.IsRecovering() {
		t.Error("should not be recovering after CompleteRecovery")
	}

	// A new call should get a fresh recovery.
	ch4, isNew4 := m.BeginRecovery()
	if !isNew4 {
		t.Error("after CompleteRecovery, next call should get isNew=true")
	}
	if ch4 == ch1 {
		t.Error("new recovery should use a different channel")
	}

	m.CompleteRecovery(&RecoveryResult{
		RecoveryMode: "in_place",
		Success:      true,
		RelayState:   "online",
	})
}

// --- Additional relay session state tests ---

func TestRelaySession_HealthyRelayCount(t *testing.T) {
	m := NewRelaySessionManager()
	pid1 := fakePeerID("relay-1")
	pid2 := fakePeerID("relay-2")

	if m.HealthyRelayCount() != 0 {
		t.Error("expected 0 healthy relays initially")
	}

	m.OnReservationOpened(pid1)
	if m.HealthyRelayCount() != 1 {
		t.Errorf("expected 1 healthy relay, got %d", m.HealthyRelayCount())
	}

	m.OnReservationOpened(pid2)
	if m.HealthyRelayCount() != 2 {
		t.Errorf("expected 2 healthy relays, got %d", m.HealthyRelayCount())
	}

	m.OnReservationEnded(pid1)
	if m.HealthyRelayCount() != 1 {
		t.Errorf("expected 1 healthy relay after one ended, got %d", m.HealthyRelayCount())
	}
}

func TestRelaySession_StatusFields(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-1")

	m.OnReservationOpened(pid)

	fields := m.StatusFields()

	if fields["relayState"] != "online" {
		t.Errorf("expected relayState=online, got %v", fields["relayState"])
	}
	if fields["healthyRelayCount"] != 1 {
		t.Errorf("expected healthyRelayCount=1, got %v", fields["healthyRelayCount"])
	}
	if fields["watchdogRestartCount"] != 0 {
		t.Errorf("expected watchdogRestartCount=0, got %v", fields["watchdogRestartCount"])
	}

	relayStates, ok := fields["relayStates"].([]map[string]interface{})
	if !ok || len(relayStates) != 1 {
		t.Fatalf("expected 1 relay state entry, got %v", fields["relayStates"])
	}
	if relayStates[0]["state"] != "reserved" {
		t.Errorf("expected relay state=reserved, got %v", relayStates[0]["state"])
	}
}

func TestRelaySession_WatchdogRestartCountIncrementsOnWatchdogRecovery(t *testing.T) {
	m := NewRelaySessionManager()

	ch, isNew := m.BeginRecovery()
	if !isNew {
		t.Fatal("expected new recovery")
	}

	var count int32
	go func() {
		<-ch
		atomic.AddInt32(&count, 1)
	}()

	m.CompleteRecovery(&RecoveryResult{
		RecoveryMode: "watchdog_restart",
		Success:      true,
	})

	time.Sleep(50 * time.Millisecond)

	if m.WatchdogRestartCount() != 1 {
		t.Errorf("expected watchdogRestartCount=1, got %d", m.WatchdogRestartCount())
	}

	// In-place recovery should NOT increment.
	ch2, _ := m.BeginRecovery()
	go func() { <-ch2 }()
	m.CompleteRecovery(&RecoveryResult{
		RecoveryMode: "in_place",
		Success:      true,
	})

	time.Sleep(50 * time.Millisecond)

	if m.WatchdogRestartCount() != 1 {
		t.Errorf("expected watchdogRestartCount still 1 after in_place, got %d", m.WatchdogRestartCount())
	}
}

func TestRelaySession_Reset(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-1")

	m.OnReservationOpened(pid)
	if m.HealthyRelayCount() != 1 {
		t.Fatal("expected 1 healthy relay before reset")
	}

	m.Reset()

	if m.HealthyRelayCount() != 0 {
		t.Error("expected 0 healthy relays after reset")
	}
	if m.AggregateState() != AggregateRelayStarting {
		t.Errorf("expected starting state after reset, got %s", m.AggregateState())
	}
	if len(m.AllSessions()) != 0 {
		t.Error("expected 0 sessions after reset")
	}
}
