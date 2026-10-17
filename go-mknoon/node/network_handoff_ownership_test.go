package node

import (
	"context"
	"errors"
	"runtime"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
)

type restartObservingHost struct {
	host.Host
	onClose func()
}

func (h *restartObservingHost) Close() error {
	h.onClose()
	return nil
}

// Task 15 finding 1: the restart decision, lease admission and the Stop/Start
// commit are one fenced unit. The test lets the recovery lane decide the full
// restart, then holds the node's read lock so Stop() waits at its write lock
// (TryRLock fails once a writer is queued), and acquires the lease in that
// window. Either the lease is refused with restart_in_progress, or, if it
// were granted, the host must not close while protection is held.
func TestCallMediaProtection_AcquireAfterRestartDecisionIsRefused_HostNeverClosesProtected(t *testing.T) {
	n := NewNode()
	n.ctx, n.cancel = context.WithCancel(context.Background())
	defer n.cancel()
	n.isStarted = true
	n.relaySessionMgr.hostStarted()
	n.lastConfig = &NodeConfig{PrivateKeyHex: generateTestKey(t), FeatureFlags: &FeatureFlags{EnableInPlaceRelayRecovery: false}}
	n.newHost = func(NodeConfig, []libp2p.Option) (host.Host, error) {
		return nil, errors.New("probe stops after observed shutdown")
	}
	stoppedWithProtection := make(chan bool, 1)
	n.host = &restartObservingHost{onClose: func() { stoppedWithProtection <- n.relaySessionMgr.CallMediaProtected() }}
	recovery, _ := n.relaySessionMgr.BeginRecovery()

	n.mu.RLock()
	locked := true
	defer func() {
		if locked {
			n.mu.RUnlock()
		}
	}()
	done := make(chan struct{})
	go func() {
		defer close(done)
		_, _ = n.reconnectRelaysOwned(context.Background(), n.relaySessionMgr, recovery)
	}()
	waiting := false
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if !n.mu.TryRLock() {
			waiting = true
			break
		}
		n.mu.RUnlock()
		runtime.Gosched()
	}
	if !waiting {
		t.Fatal("precondition: Stop did not reach its write-lock boundary")
	}
	reply := n.AcquireCallMediaProtection(99)
	if !reply.Held && reply.Reason != CallMediaProtectionRestartInProgress {
		t.Fatalf("lease refused for %q while a decided restart is stopping the host, want %s", reply.Reason, CallMediaProtectionRestartInProgress)
	}
	n.mu.RUnlock()
	locked = false
	select {
	case protected := <-stoppedWithProtection:
		if protected {
			t.Error("full recovery closed the host after acknowledging a live call's protection lease")
		}
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("recovery did not settle")
	}
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("recovery cleanup did not settle")
	}
	if reply.Held {
		t.Fatalf("lease %+v was granted after the restart decision; the fence must refuse it", reply)
	}
	// Start failed, so the host is down: the refusal reason moves on from
	// restart_in_progress once the Stop/Start commit is over.
	if after := n.AcquireCallMediaProtection(100); after.Reason != CallMediaProtectionNotStarted {
		t.Fatalf("acquire after the restart settled = %+v, want not_started", after)
	}
}

// Task 15 open item (b): Stop clears the lease and moves the host
// incarnation. A release that carries the old incarnation can never clear a
// lease granted after the restart, even with the same generation.
func TestCallMediaProtection_StopMovesIncarnation_OldReleaseIsNoOp(t *testing.T) {
	n := NewNode()
	n.hermeticLocalNetworkForTests = true
	cfg := NodeConfig{PrivateKeyHex: generateTestKey(t), RelayAddresses: []string{}}
	if _, err := n.Start(cfg); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = n.Stop() })

	first := n.AcquireCallMediaProtection(1)
	if !first.Held || first.Incarnation == 0 {
		t.Fatalf("first acquire = %+v, want a grant", first)
	}
	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	if n.relaySessionMgr.CallMediaProtected() {
		t.Fatal("Stop left the lease held")
	}
	if stopped := n.AcquireCallMediaProtection(1); stopped.Held || stopped.Reason != CallMediaProtectionNotStarted {
		t.Fatalf("acquire on a stopped node = %+v, want not_started", stopped)
	}
	if _, err := n.Start(cfg); err != nil {
		t.Fatalf("second Start: %v", err)
	}
	second := n.AcquireCallMediaProtection(1)
	if !second.Held || second.Incarnation == first.Incarnation {
		t.Fatalf("acquire after restart = %+v, want a grant in a new incarnation (first was %d)", second, first.Incarnation)
	}
	if old := n.ReleaseCallMediaProtection(1, first.Incarnation); old.Released || !n.relaySessionMgr.CallMediaProtected() {
		t.Fatalf("old-incarnation release = %+v, want no-op with the new lease kept", old)
	}
	if cur := n.ReleaseCallMediaProtection(1, second.Incarnation); !cur.Released || n.relaySessionMgr.CallMediaProtected() {
		t.Fatalf("current release = %+v, want the lease cleared", cur)
	}
}

// Task 15 finding 5: a second path request can arrive before the runner
// goroutine of the first has initialized its attempt. Admission must not call
// a nil cancel. GOMAXPROCS(1) keeps the just-created runner queued until both
// real API calls return.
func TestNetworkPathChanged_SecondPathBeforeRunnerStartsDoesNotPanic(t *testing.T) {
	prior := runtime.GOMAXPROCS(1)
	defer runtime.GOMAXPROCS(prior)
	n := NewNode()
	n.ctx, n.cancel = context.WithCancel(context.Background())
	n.isStarted = true
	n.networkPath.hostStarted(n.hostGeneration)
	defer func() {
		n.cancel()
		n.mu.Lock()
		n.isStarted = false
		n.networkPath.hostStopped()
		n.mu.Unlock()
	}()
	defer func() {
		if r := recover(); r != nil {
			t.Errorf("new path panicked before runner initialization: %v", r)
		}
	}()
	a := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 1, Usable: true})
	if !a.Accepted {
		t.Fatalf("first admission %+v", a)
	}
	b := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 2, Usable: true})
	if !b.Accepted {
		t.Errorf("second admission %+v", b)
	}
}

// Task 15 finding 2: the listener rollover (new transport generation, Listen
// and ListenClose) is a host mutation. It must wait behind the shared recovery
// owner like every other handoff mutation. The previous owner is cancelled but
// still unreleased when the listen addresses are inspected.
func TestNetworkHandoff_ListenerMutationsWaitForRecoveryOwnership(t *testing.T) {
	if testing.Short() {
		t.Skip("real relay + proxy fixture; skipped in -short")
	}
	_, _, relayAddr := startHandoffRelayFixture(t)
	relay := relayPeerOf(t, relayAddr)
	n, collector := startHandoffNode(t, relayAddr)
	waitForEpoch1Reservation(t, n, relay)
	before := make(map[string]bool)
	for _, a := range n.Host().Network().ListenAddresses() {
		before[a.String()] = true
	}
	mgr := n.relaySessionMgr
	recovery, isNew := mgr.BeginRecovery()
	if !isNew {
		t.Fatal("precondition: cannot own recovery")
	}
	completed := false
	defer func() {
		if !completed {
			mgr.CompleteRecovery(recovery, &RecoveryResult{RecoveryMode: "in_place", Success: true, ReusedHost: true}, nil)
		}
	}()
	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 3, Epoch: 2, Usable: true}); !adm.Accepted {
		t.Fatalf("admission %+v", adm)
	}
	deadline := time.Now().Add(2 * time.Second)
	for recovery.Context().Err() == nil && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if recovery.Context().Err() == nil {
		t.Fatal("precondition: handoff did not reach shared recovery gate")
	}
	for _, a := range n.Host().Network().ListenAddresses() {
		if !before[a.String()] {
			t.Errorf("listener mutated while previous recovery still owned the host: new %s", a)
		}
	}
	mgr.CompleteRecovery(recovery, &RecoveryResult{RecoveryMode: "in_place", Success: true, ReusedHost: true}, nil)
	completed = true
	name, _ := waitHandoffTerminal(t, collector, 2, NetworkHandoffBudget+2*time.Second)
	if name != "network:relay_ready" {
		t.Fatalf("terminal after owner release = %s, want relay_ready", name)
	}
	after := make(map[string]bool)
	for _, a := range n.Host().Network().ListenAddresses() {
		after[a.String()] = true
	}
	moved := false
	for a := range before {
		if !after[a] {
			moved = true
		}
	}
	if !moved {
		t.Fatal("listeners never moved once the handoff owned recovery")
	}
}

// Task 15 open item (a): a usable path refused with not_started while the
// node is stopped is the owner's latest truth about the network. The next
// Start replays it on the new host without a second native call. The refusal
// itself never starts a node.
func TestNetworkPathChanged_RefusedPathIsReplayedAfterStart(t *testing.T) {
	collector := &testEventCollector{}
	n := New(collector)
	n.hermeticLocalNetworkForTests = true
	adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 1, Usable: true})
	if adm.Accepted || adm.Reason != handoffReasonNotStarted {
		t.Fatalf("stopped node admission = %+v, want not_started", adm)
	}
	time.Sleep(50 * time.Millisecond)
	if n.Host() != nil {
		t.Fatal("a refused path event started the node")
	}
	if _, err := n.Start(NodeConfig{PrivateKeyHex: generateTestKey(t), RelayAddresses: []string{}}); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = n.Stop() })

	name, data := waitHandoffTerminal(t, collector, 1, 3*time.Second)
	if name != "network:relay_failed" || data["errorCode"] != handoffReasonNoRelays {
		t.Fatalf("replayed epoch 1 terminal = %s %v, want relay_failed/no_relays on the started host", name, data)
	}
	if got := len(eventsForEpoch(collector, "network:path_changing", 1)); got != 1 {
		t.Fatalf("path_changing events for the replayed epoch = %d, want 1", got)
	}
	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 1, Usable: true}); adm.Accepted || adm.Reason != handoffReasonDuplicateEpoch {
		t.Fatalf("resend of the replayed epoch = %+v, want duplicate_epoch", adm)
	}
}

// Task 15 open item (a), the internal watchdog case: ReconnectRelays falls
// back to Stop/Start, which emits no native nodeStart reply. A path event that
// arrives while that Start is in flight answers not_started and is replayed
// under the new host once Start commits. Nothing but the restart starts a host.
func TestNetworkPathChanged_PathArrivingDuringWatchdogStartIsReplayed(t *testing.T) {
	collector := &testEventCollector{}
	n := New(collector)
	n.hermeticLocalNetworkForTests = true
	n.waitForCircuitAddressHook = func(time.Duration) bool { return true }
	n.refreshRelaySessionHook = func() *RecoveryResult {
		return &RecoveryResult{RecoveryMode: "in_place", Success: false, ErrorCode: "REFRESH_FAILED", Reason: "forced"}
	}
	inStart := make(chan struct{})
	release := make(chan struct{})
	starts := 0
	n.newHost = func(cfg NodeConfig, opts []libp2p.Option) (host.Host, error) {
		starts++
		if starts == 2 {
			close(inStart)
			<-release
		}
		return defaultNewHost(cfg, opts)
	}
	if _, err := n.Start(NodeConfig{PrivateKeyHex: generateTestKey(t), RelayAddresses: []string{}}); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = n.Stop() })
	h0 := n.Host()

	done := make(chan *RecoveryResult, 1)
	go func() {
		result, _ := n.ReconnectRelays()
		done <- result
	}()
	select {
	case <-inStart:
	case <-time.After(5 * time.Second):
		t.Fatal("watchdog restart did not reach Start")
	}
	adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 4, Usable: true})
	if adm.Accepted || adm.Reason != handoffReasonNotStarted {
		t.Fatalf("admission while Start is in flight = %+v, want not_started", adm)
	}
	close(release)
	select {
	case result := <-done:
		if result == nil || result.RecoveryMode != "watchdog_restart" {
			t.Fatalf("reconnect result = %+v, want watchdog_restart", result)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("watchdog restart did not finish")
	}
	if n.Host() == h0 || n.Host() == nil {
		t.Fatal("precondition: the watchdog restart did not replace the host")
	}
	name, data := waitHandoffTerminal(t, collector, 4, 3*time.Second)
	if name != "network:relay_failed" || data["errorCode"] != handoffReasonNoRelays {
		t.Fatalf("replayed epoch 4 terminal = %s %v, want relay_failed/no_relays on the restarted host", name, data)
	}
	if got := len(handoffEventsWithPhase(collector, "host_ready")); got != 2 {
		t.Fatalf("host_ready events = %d, want 2 (first Start and the watchdog restart only)", got)
	}
}
