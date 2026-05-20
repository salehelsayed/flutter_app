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

func TestNW009RelayProbeFailureKeepsReservationHealth(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-nw009")

	m.OnReservationOpened(pid)
	if !m.HasReservation() {
		t.Fatal("expected reservation before relay probe failure")
	}
	if m.AggregateState() != AggregateRelayOnline {
		t.Fatalf("aggregate state before failure = %s, want %s", m.AggregateState(), AggregateRelayOnline)
	}

	probeErr := fmt.Errorf("NO_RESERVATION: relay probe failed for active member")
	m.OnRequestFailed(pid, probeErr)

	s := m.GetSession(pid)
	if s == nil {
		t.Fatal("expected relay session after probe failure")
	}
	if s.State != RelayStateReserved {
		t.Fatalf("relay probe failure changed state to %s, want %s", s.State, RelayStateReserved)
	}
	if s.FailCount != 1 {
		t.Fatalf("failCount = %d, want 1", s.FailCount)
	}
	if s.LastError != probeErr.Error() {
		t.Fatalf("lastError = %q, want %q", s.LastError, probeErr.Error())
	}
	if m.AggregateState() != AggregateRelayOnline {
		t.Fatalf("aggregate state after failure = %s, want %s", m.AggregateState(), AggregateRelayOnline)
	}
	if !m.IsHealthy() || !m.HasReservation() {
		t.Fatal("relay probe failure must not clear healthy reservation state")
	}
	if got := m.HealthyRelayCount(); got != 1 {
		t.Fatalf("healthy relay count = %d, want 1", got)
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

func TestGR012StaleCircuitAddressesDoNotReportHealthyWithoutReservation(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-gr012")
	circuitAddrs := []string{
		fmt.Sprintf("/ip4/1.2.3.4/tcp/1234/p2p/%s/p2p-circuit/p2p/self", pid),
	}

	m.InitRelayPeer(pid)

	if !m.CircuitAddressesAreStale(circuitAddrs) {
		t.Fatal("host-reported circuit address without reservation should be stale")
	}
	if m.ReportsHealthyWithReservation(circuitAddrs) {
		t.Fatal("stale circuit address without reservation reported healthy")
	}
	if trusted := m.IgnoresStaleCircuitAddresses(circuitAddrs); len(trusted) != 0 {
		t.Fatalf("stale circuit addresses were trusted without reservation: %v", trusted)
	}
	fields := m.StatusFields()
	if fields["relayState"] == string(AggregateRelayOnline) {
		t.Fatalf("status relayState = %v without reservation, want not online", fields["relayState"])
	}
	if fields["healthyRelayCount"] != 0 {
		t.Fatalf("status healthyRelayCount = %v without reservation, want 0", fields["healthyRelayCount"])
	}
	if _, ok := fields["lastReservationAt"]; ok {
		t.Fatalf("status exposed lastReservationAt without reservation: %v", fields["lastReservationAt"])
	}

	m.OnReservationOpened(pid)
	if m.CircuitAddressesAreStale(circuitAddrs) {
		t.Fatal("circuit address should not be stale once reservation is active")
	}
	if !m.ReportsHealthyWithReservation(circuitAddrs) {
		t.Fatal("active reservation with circuit address should report healthy")
	}
	if trusted := m.IgnoresStaleCircuitAddresses(circuitAddrs); len(trusted) != 1 || trusted[0] != circuitAddrs[0] {
		t.Fatalf("trusted circuit addresses with active reservation = %v, want %v", trusted, circuitAddrs)
	}
	fields = m.StatusFields()
	if fields["relayState"] != string(AggregateRelayOnline) {
		t.Fatalf("status relayState with reservation = %v, want online", fields["relayState"])
	}
	if fields["healthyRelayCount"] != 1 {
		t.Fatalf("status healthyRelayCount with reservation = %v, want 1", fields["healthyRelayCount"])
	}

	m.OnReservationEnded(pid)
	if !m.CircuitAddressesAreStale(circuitAddrs) {
		t.Fatal("circuit address should become stale after reservation ends")
	}
	if m.ReportsHealthyWithReservation(circuitAddrs) {
		t.Fatal("ended reservation with circuit address reported healthy")
	}
	if trusted := m.IgnoresStaleCircuitAddresses(circuitAddrs); len(trusted) != 0 {
		t.Fatalf("stale circuit addresses were trusted after reservation ended: %v", trusted)
	}
	fields = m.StatusFields()
	if fields["relayState"] == string(AggregateRelayOnline) {
		t.Fatalf("status relayState after reservation ended = %v, want not online", fields["relayState"])
	}
	if fields["healthyRelayCount"] != 0 {
		t.Fatalf("status healthyRelayCount after reservation ended = %v, want 0", fields["healthyRelayCount"])
	}
}

func TestRelaySession_CoalescesConcurrentRecoveryRequests(t *testing.T) {
	m := NewRelaySessionManager()

	// First caller gets the recovery lock.
	recovery1, isNew1 := m.BeginRecovery()
	if !isNew1 {
		t.Fatal("first caller should get isNew=true")
	}
	if recovery1 == nil {
		t.Fatal("first caller should get a non-nil recovery promise")
	}
	if !m.IsRecovering() {
		t.Error("should be recovering after BeginRecovery")
	}

	// Second concurrent caller should share the same recovery.
	recovery2, isNew2 := m.BeginRecovery()
	if isNew2 {
		t.Error("second caller should get isNew=false (coalesced)")
	}
	if recovery2 != recovery1 {
		t.Error("second caller should get the same recovery promise as first")
	}

	// Third caller — same behavior.
	recovery3, isNew3 := m.BeginRecovery()
	if isNew3 {
		t.Error("third caller should get isNew=false")
	}
	if recovery3 != recovery1 {
		t.Error("third caller should share the same recovery promise")
	}

	result := &RecoveryResult{
		RecoveryMode:      "in_place",
		Success:           true,
		RelayState:        "online",
		HealthyRelayCount: 1,
	}

	m.CompleteRecovery(result, nil)

	r1, err1 := recovery1.Wait()
	if err1 != nil {
		t.Fatalf("first waiter should not receive an error: %v", err1)
	}
	r2, err2 := recovery2.Wait()
	if err2 != nil {
		t.Fatalf("second waiter should not receive an error: %v", err2)
	}
	r3, err3 := recovery3.Wait()
	if err3 != nil {
		t.Fatalf("third waiter should not receive an error: %v", err3)
	}

	for idx, got := range []*RecoveryResult{r1, r2, r3} {
		if got == nil {
			t.Fatalf("waiter %d should have received the result", idx+1)
		}
		if got.RecoveryMode != "in_place" {
			t.Fatalf("waiter %d recoveryMode=%s, want in_place", idx+1, got.RecoveryMode)
		}
	}

	// After completion, should not be recovering.
	if m.IsRecovering() {
		t.Error("should not be recovering after CompleteRecovery")
	}

	// A new call should get a fresh recovery.
	recovery4, isNew4 := m.BeginRecovery()
	if !isNew4 {
		t.Error("after CompleteRecovery, next call should get isNew=true")
	}
	if recovery4 == recovery1 {
		t.Error("new recovery should use a different promise")
	}

	m.CompleteRecovery(&RecoveryResult{
		RecoveryMode: "in_place",
		Success:      true,
		RelayState:   "online",
	}, nil)
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
		_, _ = ch.Wait()
		atomic.AddInt32(&count, 1)
	}()

	m.CompleteRecovery(&RecoveryResult{
		RecoveryMode: "watchdog_restart",
		Success:      true,
	}, nil)

	time.Sleep(50 * time.Millisecond)

	if m.WatchdogRestartCount() != 1 {
		t.Errorf("expected watchdogRestartCount=1, got %d", m.WatchdogRestartCount())
	}
	if !m.NeedsGroupRecovery() {
		t.Error("watchdog recovery should mark needsGroupRecovery")
	}

	// In-place recovery should NOT increment.
	ch2, _ := m.BeginRecovery()
	go func() { _, _ = ch2.Wait() }()
	m.CompleteRecovery(&RecoveryResult{
		RecoveryMode: "in_place",
		Success:      true,
	}, nil)

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

func TestGR008RecordWatchdogRestartPreservesRecoverySignalAcrossReset(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-1")

	m.OnReservationOpened(pid)
	m.RecordWatchdogRestart()

	if got := m.WatchdogRestartCount(); got != 1 {
		t.Fatalf("watchdog restart count before reset = %d, want 1", got)
	}
	if !m.NeedsGroupRecovery() {
		t.Fatal("needsGroupRecovery should be true immediately after watchdog restart")
	}

	m.Reset()

	if got := m.WatchdogRestartCount(); got != 1 {
		t.Fatalf("watchdog restart count after reset = %d, want 1", got)
	}
	if !m.NeedsGroupRecovery() {
		t.Fatal("needsGroupRecovery should survive Reset until Flutter acknowledges")
	}
	if got := m.HealthyRelayCount(); got != 0 {
		t.Fatalf("healthy relay count after reset = %d, want 0", got)
	}
	if got := m.AggregateState(); got != AggregateRelayStarting {
		t.Fatalf("aggregate state after reset = %s, want %s", got, AggregateRelayStarting)
	}

	fields := m.StatusFields()
	if got := fields["watchdogRestartCount"]; got != 1 {
		t.Fatalf("status watchdogRestartCount after reset = %v, want 1", got)
	}
	if got := fields["needsGroupRecovery"]; got != true {
		t.Fatalf("status needsGroupRecovery after reset = %v, want true", got)
	}
	if got := fields["healthyRelayCount"]; got != 0 {
		t.Fatalf("status healthyRelayCount after reset = %v, want 0", got)
	}

	m.AcknowledgeGroupRecovery()
	if m.NeedsGroupRecovery() {
		t.Fatal("needsGroupRecovery should clear only after acknowledgement")
	}
}

func TestRelaySession_ResetPreservesInFlightRecovery(t *testing.T) {
	m := NewRelaySessionManager()

	recovery, isNew := m.BeginRecovery()
	if !isNew {
		t.Fatal("expected new recovery")
	}

	m.Reset()

	if !m.IsRecovering() {
		t.Fatal("reset should preserve an in-flight recovery promise")
	}
	if m.AggregateState() != AggregateRelayRecovering {
		t.Fatalf("expected recovering state during reset, got %s", m.AggregateState())
	}

	expected := &RecoveryResult{
		RecoveryMode:      "watchdog_restart",
		Success:           true,
		RelayState:        "online",
		HealthyRelayCount: 1,
	}
	m.CompleteRecovery(expected, nil)

	got, err := recovery.Wait()
	if err != nil {
		t.Fatalf("Wait() error: %v", err)
	}
	if got == nil || got.RecoveryMode != expected.RecoveryMode {
		t.Fatalf("Wait() = %+v, want %+v", got, expected)
	}
}

// --- §4: Recovery Promise Timeout Tests ---

func TestRecoveryPromise_StalledRecoveryTimesOut(t *testing.T) {
	m := NewRelaySessionManager()

	// Goroutine A starts recovery but NEVER completes it.
	_, isNew := m.BeginRecovery()
	if !isNew {
		t.Fatal("expected new recovery")
	}

	// Goroutine B joins the recovery and waits.
	recovery2, isNew2 := m.BeginRecovery()
	if isNew2 {
		t.Fatal("expected coalesced recovery")
	}

	start := time.Now()
	result, err := recovery2.Wait()
	elapsed := time.Since(start)

	// Should time out with RECOVERY_TIMEOUT error.
	if err == nil || err.Error() != "RECOVERY_TIMEOUT" {
		t.Fatalf("expected RECOVERY_TIMEOUT error, got: %v", err)
	}
	if result == nil || result.RecoveryMode != "timeout" {
		t.Fatalf("expected RecoveryResult with RecoveryMode=timeout, got: %+v", result)
	}

	// Should have taken roughly RecoveryWaitTimeout (30s), with margin.
	if elapsed < RecoveryWaitTimeout-time.Second || elapsed > RecoveryWaitTimeout+2*time.Second {
		t.Errorf("timeout took %v, expected ~%v", elapsed, RecoveryWaitTimeout)
	}
}

func TestGR003RelaySessionStalledRecoveryClearsGateAfterTimeout(t *testing.T) {
	m := NewRelaySessionManager()
	m.recoveryWaitTimeout = 20 * time.Millisecond

	stalled, isNew := m.BeginRecovery()
	if !isNew {
		t.Fatal("first BeginRecovery should start a new recovery")
	}
	if stalled == nil {
		t.Fatal("first BeginRecovery returned nil promise")
	}

	waiter, isNew := m.BeginRecovery()
	if isNew {
		t.Fatal("second BeginRecovery should coalesce onto the stalled recovery")
	}
	if waiter != stalled {
		t.Fatal("waiter should share the stalled recovery promise")
	}

	result, err := waiter.Wait()
	if err == nil || err.Error() != "RECOVERY_TIMEOUT" {
		t.Fatalf("Wait() error = %v, want RECOVERY_TIMEOUT", err)
	}
	if result == nil {
		t.Fatal("Wait() returned nil timeout result")
	}
	if result.RecoveryMode != "timeout" {
		t.Fatalf("RecoveryMode = %q, want timeout", result.RecoveryMode)
	}
	if m.IsRecovering() {
		t.Fatal("timeout did not clear the stalled recovery gate")
	}

	fresh, isNew := m.BeginRecovery()
	if !isNew {
		t.Fatal("BeginRecovery after timeout should start a fresh recovery")
	}
	if fresh == nil {
		t.Fatal("fresh recovery promise is nil")
	}
	if fresh == stalled {
		t.Fatal("fresh recovery reused the stalled promise")
	}

	m.CompleteRecovery(&RecoveryResult{
		RecoveryMode: "in_place",
		Success:      true,
		RelayState:   string(AggregateRelayOnline),
	}, nil)

	freshResult, freshErr := fresh.Wait()
	if freshErr != nil {
		t.Fatalf("fresh recovery should complete without error: %v", freshErr)
	}
	if freshResult == nil || !freshResult.Success || freshResult.RecoveryMode != "in_place" {
		t.Fatalf("fresh recovery result = %+v, want successful in_place", freshResult)
	}
}

func TestRecoveryPromise_TimeoutClearsRecoveryGate(t *testing.T) {
	m := NewRelaySessionManager()

	// Start recovery, never complete.
	_, isNew := m.BeginRecovery()
	if !isNew {
		t.Fatal("expected new recovery")
	}

	// Wait for timeout on a second promise.
	recovery2, _ := m.BeginRecovery()
	_, err := recovery2.Wait()
	if err == nil || err.Error() != "RECOVERY_TIMEOUT" {
		t.Fatalf("expected RECOVERY_TIMEOUT, got: %v", err)
	}

	// After timeout, recovery gate should be cleared.
	// A new call should get isNew=true.
	recovery3, isNew3 := m.BeginRecovery()
	if !isNew3 {
		t.Error("after timeout, next BeginRecovery should get isNew=true (gate cleared)")
	}
	if recovery3 == nil {
		t.Fatal("recovery3 should not be nil")
	}

	// Clean up.
	m.CompleteRecovery(&RecoveryResult{RecoveryMode: "in_place", Success: true}, nil)
}

func TestRecoveryPromise_LateCompletionAfterTimeoutIsIgnored(t *testing.T) {
	m := NewRelaySessionManager()

	// Start recovery, never complete within timeout.
	_, isNew := m.BeginRecovery()
	if !isNew {
		t.Fatal("expected new recovery")
	}

	// Wait for timeout.
	recovery2, _ := m.BeginRecovery()
	_, err := recovery2.Wait()
	if err == nil || err.Error() != "RECOVERY_TIMEOUT" {
		t.Fatalf("expected RECOVERY_TIMEOUT, got: %v", err)
	}

	// Late completion: should NOT panic or crash.
	m.CompleteRecovery(&RecoveryResult{RecoveryMode: "in_place", Success: true}, nil)

	// Start a new recovery — should work fine.
	recovery3, isNew3 := m.BeginRecovery()
	if !isNew3 {
		t.Error("expected new recovery after late completion")
	}
	m.CompleteRecovery(&RecoveryResult{RecoveryMode: "in_place", Success: true}, nil)
	result, err := recovery3.Wait()
	if err != nil {
		t.Fatalf("new recovery should succeed: %v", err)
	}
	if result.RecoveryMode != "in_place" {
		t.Errorf("expected in_place, got %s", result.RecoveryMode)
	}
}

func TestRecoveryPromise_ConcurrentWaitersAllReceiveTimeout(t *testing.T) {
	m := NewRelaySessionManager()

	// Start recovery, never complete.
	_, isNew := m.BeginRecovery()
	if !isNew {
		t.Fatal("expected new recovery")
	}

	type waitResult struct {
		result *RecoveryResult
		err    error
		at     time.Time
	}

	results := make(chan waitResult, 3)

	// Launch 3 concurrent waiters.
	for i := 0; i < 3; i++ {
		go func() {
			p, _ := m.BeginRecovery()
			r, e := p.Wait()
			results <- waitResult{r, e, time.Now()}
		}()
	}

	// Collect all results.
	var wr []waitResult
	for i := 0; i < 3; i++ {
		wr = append(wr, <-results)
	}

	// All should have timed out.
	for i, w := range wr {
		if w.err == nil || w.err.Error() != "RECOVERY_TIMEOUT" {
			t.Errorf("waiter %d: expected RECOVERY_TIMEOUT, got: %v", i, w.err)
		}
	}

	// All should have fired within 2s of each other (not sequential).
	earliest := wr[0].at
	latest := wr[0].at
	for _, w := range wr[1:] {
		if w.at.Before(earliest) {
			earliest = w.at
		}
		if w.at.After(latest) {
			latest = w.at
		}
	}
	if latest.Sub(earliest) > 2*time.Second {
		t.Errorf("waiters should all time out within 2s of each other, spread was %v", latest.Sub(earliest))
	}
}

func TestRecoveryPromise_NormalRecoveryStillWorks(t *testing.T) {
	m := NewRelaySessionManager()

	promise, isNew := m.BeginRecovery()
	if !isNew {
		t.Fatal("expected new recovery")
	}

	// Second and third waiters coalesce.
	promise2, _ := m.BeginRecovery()
	promise3, _ := m.BeginRecovery()

	expected := &RecoveryResult{
		RecoveryMode:      "in_place",
		Success:           true,
		RelayState:        "online",
		HealthyRelayCount: 1,
	}

	// Complete before timeout fires.
	go func() {
		time.Sleep(100 * time.Millisecond)
		m.CompleteRecovery(expected, nil)
	}()

	r1, err1 := promise.Wait()
	r2, err2 := promise2.Wait()
	r3, err3 := promise3.Wait()

	for i, pair := range []struct {
		r   *RecoveryResult
		err error
	}{{r1, err1}, {r2, err2}, {r3, err3}} {
		if pair.err != nil {
			t.Errorf("waiter %d: unexpected error: %v", i, pair.err)
		}
		if pair.r == nil || pair.r.RecoveryMode != "in_place" {
			t.Errorf("waiter %d: expected in_place result, got %+v", i, pair.r)
		}
	}
}

// --- Phase 7 RED Tests: Watchdog Policy ---

func TestWatchdog_TriggersAfterNConsecutiveRefreshFailures(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-1")

	// Start with a healthy reservation so we have a session.
	m.OnReservationOpened(pid)
	if m.AggregateState() != AggregateRelayOnline {
		t.Fatalf("expected online, got %s", m.AggregateState())
	}

	// Reservation ends — relay is degraded.
	m.OnReservationEnded(pid)

	// Simulate WatchdogMaxConsecutiveFailures consecutive refresh failures.
	for i := 0; i < WatchdogMaxConsecutiveFailures; i++ {
		m.OnRefreshFailed(pid, fmt.Errorf("refresh failure %d", i))
	}

	// After N consecutive failures, the watchdog should mark needsGroupRecovery
	// and transition to watchdog_restart.
	if !m.NeedsGroupRecovery() {
		t.Error("watchdog should set needsGroupRecovery after max consecutive failures")
	}
	if m.AggregateState() != AggregateRelayWatchdogRestart {
		t.Errorf("expected watchdog_restart state, got %s", m.AggregateState())
	}
}

func TestGR009RefreshFailuresTriggerWatchdogOnlyAfterAllRelaysReachThreshold(t *testing.T) {
	m := NewRelaySessionManager()
	relayA := fakePeerID("relay-a")
	relayB := fakePeerID("relay-b")

	m.OnReservationOpened(relayA)
	m.OnReservationOpened(relayB)
	if got := m.HealthyRelayCount(); got != 2 {
		t.Fatalf("healthy relay count after reservations = %d, want 2", got)
	}

	for i := 0; i < WatchdogMaxConsecutiveFailures-1; i++ {
		m.OnRefreshFailed(relayA, fmt.Errorf("relay-a failure %d", i))
	}
	if m.NeedsGroupRecovery() {
		t.Fatal("watchdog triggered before the first relay reached threshold")
	}
	if got := m.AggregateState(); got == AggregateRelayWatchdogRestart {
		t.Fatalf("aggregate state = %s before first relay threshold, want not watchdog_restart", got)
	}

	m.OnRefreshFailed(relayA, fmt.Errorf("relay-a threshold failure"))
	if m.NeedsGroupRecovery() {
		t.Fatal("watchdog triggered while relay-b remained reserved below threshold")
	}
	if got := m.AggregateState(); got == AggregateRelayWatchdogRestart {
		t.Fatalf("aggregate state = %s while relay-b remained below threshold, want not watchdog_restart", got)
	}

	if s := m.GetSession(relayA); s == nil || s.ConsecutiveRefreshFailures != WatchdogMaxConsecutiveFailures {
		t.Fatalf("relay-a consecutive failures = %+v, want %d", s, WatchdogMaxConsecutiveFailures)
	}
	if s := m.GetSession(relayB); s == nil || s.ConsecutiveRefreshFailures != 0 || s.State != RelayStateReserved {
		t.Fatalf("relay-b state before failures = %+v, want reserved with 0 failures", s)
	}

	for i := 0; i < WatchdogMaxConsecutiveFailures-1; i++ {
		m.OnRefreshFailed(relayB, fmt.Errorf("relay-b failure %d", i))
	}
	if m.NeedsGroupRecovery() {
		t.Fatal("watchdog triggered before relay-b reached threshold")
	}
	if got := m.AggregateState(); got == AggregateRelayWatchdogRestart {
		t.Fatalf("aggregate state = %s before all relays reached threshold, want not watchdog_restart", got)
	}

	m.OnRefreshFailed(relayB, fmt.Errorf("relay-b threshold failure"))
	if !m.NeedsGroupRecovery() {
		t.Fatal("watchdog did not trigger after all tracked relays reached threshold")
	}
	if got := m.AggregateState(); got != AggregateRelayWatchdogRestart {
		t.Fatalf("aggregate state after all relays reached threshold = %s, want watchdog_restart", got)
	}

	fields := m.StatusFields()
	if fields["needsGroupRecovery"] != true {
		t.Fatalf("status needsGroupRecovery = %v, want true", fields["needsGroupRecovery"])
	}
	if fields["relayState"] != string(AggregateRelayWatchdogRestart) {
		t.Fatalf("status relayState = %v, want %s", fields["relayState"], AggregateRelayWatchdogRestart)
	}
}

func TestWatchdog_SingleSuccessfulRefreshResetsFailureCounter(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-1")

	// Start with a healthy reservation.
	m.OnReservationOpened(pid)
	m.OnReservationEnded(pid)

	// Accumulate failures just below the threshold.
	for i := 0; i < WatchdogMaxConsecutiveFailures-1; i++ {
		m.OnRefreshFailed(pid, fmt.Errorf("failure %d", i))
	}

	s := m.GetSession(pid)
	if s == nil {
		t.Fatal("expected session")
	}
	if s.ConsecutiveRefreshFailures != WatchdogMaxConsecutiveFailures-1 {
		t.Errorf("expected %d consecutive failures, got %d",
			WatchdogMaxConsecutiveFailures-1, s.ConsecutiveRefreshFailures)
	}

	// A single successful refresh should reset the counter.
	m.OnRefreshSucceeded(pid)

	s = m.GetSession(pid)
	if s.ConsecutiveRefreshFailures != 0 {
		t.Errorf("expected 0 consecutive failures after success, got %d", s.ConsecutiveRefreshFailures)
	}

	// needsGroupRecovery should NOT be set since we never crossed the threshold.
	if m.NeedsGroupRecovery() {
		t.Error("needsGroupRecovery should be false when threshold was not crossed")
	}
}

func TestGR010RefreshSuccessResetsFailureCounterAndStaleError(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-gr010")

	m.OnReservationOpened(pid)
	for i := 0; i < WatchdogMaxConsecutiveFailures-1; i++ {
		m.OnRefreshFailed(pid, fmt.Errorf("gr010 failure %d", i))
	}

	before := m.GetSession(pid)
	if before == nil {
		t.Fatal("expected relay session before successful refresh")
	}
	if got := before.ConsecutiveRefreshFailures; got != WatchdogMaxConsecutiveFailures-1 {
		t.Fatalf("consecutive failures before success = %d, want %d", got, WatchdogMaxConsecutiveFailures-1)
	}
	if before.LastError == "" {
		t.Fatal("expected failed refresh streak to record a last error before success")
	}

	m.OnRefreshSucceeded(pid)

	after := m.GetSession(pid)
	if after == nil {
		t.Fatal("expected relay session after successful refresh")
	}
	if after.ConsecutiveRefreshFailures != 0 {
		t.Fatalf("consecutive failures after success = %d, want 0", after.ConsecutiveRefreshFailures)
	}
	if after.State != RelayStateReserved {
		t.Fatalf("state after success = %s, want reserved", after.State)
	}
	if after.LastError != "" {
		t.Fatalf("last error after success = %q, want empty", after.LastError)
	}
	if after.LastReservedAt.IsZero() {
		t.Fatal("last reserved timestamp should be set after successful refresh")
	}
	if m.NeedsGroupRecovery() {
		t.Fatal("successful refresh below threshold should not require group recovery")
	}
	if got := m.AggregateState(); got != AggregateRelayOnline {
		t.Fatalf("aggregate state after success = %s, want online", got)
	}

	fields := m.StatusFields()
	if fields["relayState"] != string(AggregateRelayOnline) {
		t.Fatalf("status relayState = %v, want %s", fields["relayState"], AggregateRelayOnline)
	}
	if fields["healthyRelayCount"] != 1 {
		t.Fatalf("status healthyRelayCount = %v, want 1", fields["healthyRelayCount"])
	}
	relayStates, ok := fields["relayStates"].([]map[string]interface{})
	if !ok {
		t.Fatalf("status relayStates has type %T, want []map[string]interface{}", fields["relayStates"])
	}
	if len(relayStates) != 1 {
		t.Fatalf("status relayStates length = %d, want 1", len(relayStates))
	}
	if relayStates[0]["state"] != string(RelayStateReserved) {
		t.Fatalf("status relay state = %v, want reserved", relayStates[0]["state"])
	}
	if _, ok := relayStates[0]["lastError"]; ok {
		t.Fatalf("status relay state still exposes stale lastError: %v", relayStates[0]["lastError"])
	}
}

func TestWatchdog_MarksNeedsGroupRecoveryForFlutter(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-1")

	// Start with a healthy reservation.
	m.OnReservationOpened(pid)
	m.OnReservationEnded(pid)

	// Initially no group recovery needed.
	if m.NeedsGroupRecovery() {
		t.Error("needsGroupRecovery should be false initially")
	}

	// Cross the watchdog threshold.
	for i := 0; i < WatchdogMaxConsecutiveFailures; i++ {
		m.OnRefreshFailed(pid, fmt.Errorf("failure %d", i))
	}

	// Watchdog should mark needsGroupRecovery.
	if !m.NeedsGroupRecovery() {
		t.Error("needsGroupRecovery should be true after watchdog triggers")
	}

	// Acknowledge the recovery.
	m.AcknowledgeGroupRecovery()

	// After acknowledgement, the flag should be cleared.
	if m.NeedsGroupRecovery() {
		t.Error("needsGroupRecovery should be false after acknowledgement")
	}

	// The watchdog state should be reported in status fields.
	fields := m.StatusFields()
	if fields["needsGroupRecovery"] != false {
		t.Errorf("expected needsGroupRecovery=false in status after ack, got %v", fields["needsGroupRecovery"])
	}
}

func TestNW004WatchdogRestartSignalsGroupRecoveryUntilFlutterAck(t *testing.T) {
	m := NewRelaySessionManager()
	pid := fakePeerID("relay-1")

	m.OnReservationOpened(pid)
	m.OnReservationEnded(pid)
	for i := 0; i < WatchdogMaxConsecutiveFailures; i++ {
		m.OnRefreshFailed(pid, fmt.Errorf("NW-004 refresh failure %d", i))
	}
	m.RecordWatchdogRestart()

	if m.AggregateState() != AggregateRelayWatchdogRestart {
		t.Fatalf("aggregate state = %s, want watchdog_restart", m.AggregateState())
	}
	if m.WatchdogRestartCount() != 1 {
		t.Fatalf("watchdogRestartCount = %d, want 1", m.WatchdogRestartCount())
	}
	fields := m.StatusFields()
	if fields["needsGroupRecovery"] != true {
		t.Fatalf("needsGroupRecovery status = %v, want true before Flutter repair", fields["needsGroupRecovery"])
	}
	if !m.NeedsGroupRecovery() {
		t.Fatal("needsGroupRecovery should remain true until Flutter ack")
	}

	m.AcknowledgeGroupRecovery()

	if m.NeedsGroupRecovery() {
		t.Fatal("needsGroupRecovery should clear only after Flutter ack")
	}
	fields = m.StatusFields()
	if fields["needsGroupRecovery"] != false {
		t.Fatalf("needsGroupRecovery status = %v, want false after Flutter ack", fields["needsGroupRecovery"])
	}
}

// --- Phase 7 RED Tests: Feature Flags ---

func TestFeatureFlags_DefaultAllTrue(t *testing.T) {
	flags := DefaultFeatureFlags()

	if !flags.EnableSharedRelayBackend {
		t.Error("EnableSharedRelayBackend should default to true")
	}
	if !flags.EnableMultiRelayRouting {
		t.Error("EnableMultiRelayRouting should default to true")
	}
	if !flags.EnableReservationAwareHealth {
		t.Error("EnableReservationAwareHealth should default to true")
	}
	if !flags.EnableInPlaceRelayRecovery {
		t.Error("EnableInPlaceRelayRecovery should default to true")
	}
	if !flags.EnableResumeGroupRecovery {
		t.Error("EnableResumeGroupRecovery should default to true")
	}
}

func TestFeatureFlags_ThreadedThroughNodeConfig(t *testing.T) {
	cfg := NodeConfig{
		PrivateKeyHex:  "abc123",
		RelayAddresses: []string{"/ip4/127.0.0.1/tcp/4001"},
		FeatureFlags:   &FeatureFlags{EnableMultiRelayRouting: false},
	}

	if cfg.FeatureFlags == nil {
		t.Fatal("FeatureFlags should be set on NodeConfig")
	}
	if cfg.FeatureFlags.EnableMultiRelayRouting {
		t.Error("EnableMultiRelayRouting should be false when explicitly set")
	}

	// EffectiveFlags should return the configured flags.
	effective := cfg.EffectiveFlags()
	if effective.EnableMultiRelayRouting {
		t.Error("EffectiveFlags should respect configured value")
	}
	// Unset flags should retain their zero value (false in this case),
	// not be overridden to true.
}

func TestFeatureFlags_NilDefaultsToAllEnabled(t *testing.T) {
	cfg := NodeConfig{
		PrivateKeyHex:  "abc123",
		RelayAddresses: []string{"/ip4/127.0.0.1/tcp/4001"},
	}

	// When FeatureFlags is nil, EffectiveFlags should return defaults (all true).
	effective := cfg.EffectiveFlags()
	if !effective.EnableSharedRelayBackend {
		t.Error("nil FeatureFlags should default EnableSharedRelayBackend to true")
	}
	if !effective.EnableMultiRelayRouting {
		t.Error("nil FeatureFlags should default EnableMultiRelayRouting to true")
	}
}
