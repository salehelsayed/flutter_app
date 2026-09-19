package node

import (
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
)

func TestRecoveryDeadline_OwnerReturnsWithoutStartingConcurrentMutation(t *testing.T) {
	for _, reconnect := range []bool{false, true} {
		name := "refresh"
		if reconnect {
			name = "reconnect"
		}
		t.Run(name, func(t *testing.T) {
			n := NewNode()
			n.hermeticLocalNetworkForTests = true
			n.relaySessionMgr.recoveryWaitTimeout = 20 * time.Millisecond
			n.warmRelayConnectionHook = func(peer.AddrInfo) error { return nil }
			n.waitForCircuitAddressHook = func(time.Duration) bool { return true }
			started := make(chan struct{})
			release := make(chan struct{})
			var releaseOnce sync.Once
			var startedOnce sync.Once
			n.refreshRelaySessionHook = func() *RecoveryResult {
				startedOnce.Do(func() { close(started) })
				<-release
				return &RecoveryResult{RecoveryMode: "in_place", Success: true}
			}
			if _, err := n.Start(NodeConfig{
				PrivateKeyHex:  generateTestKey(t),
				RelayAddresses: []string{generateFakeRelayAddr(t, 19045)},
			}); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() {
				releaseOnce.Do(func() { close(release) })
				deadline := time.Now().Add(time.Second)
				for n.relaySessionMgr.IsRecovering() && time.Now().Before(deadline) {
					time.Sleep(time.Millisecond)
				}
				_ = n.Stop()
			})
			call := func() *RecoveryResult {
				if reconnect {
					result, _ := n.ReconnectRelays()
					return result
				}
				return n.RefreshRelaySession()
			}
			outcome := make(chan *RecoveryResult, 1)
			go func() { outcome <- call() }()
			select {
			case <-started:
			case <-time.After(time.Second):
				t.Fatal("owned recovery did not start")
			}
			select {
			case result := <-outcome:
				if result == nil || result.Success || result.ErrorCode != "RECOVERY_TIMEOUT" {
					t.Fatalf("owner outcome = %+v, want structured timeout", result)
				}
			case <-time.After(250 * time.Millisecond):
				t.Fatal("the owning API caller remained blocked after its recovery deadline")
			}
			if !n.relaySessionMgr.IsRecovering() {
				t.Fatal("deadline released mutation ownership while the recovery still runs")
			}
			go func() { outcome <- call() }()
			select {
			case result := <-outcome:
				if result == nil || result.ErrorCode != "RECOVERY_TIMEOUT" {
					t.Fatalf("retry outcome = %+v, want the existing owner's timeout", result)
				}
			case <-time.After(250 * time.Millisecond):
				t.Fatal("retry started a second blocked recovery instead of joining the expired owner")
			}
			releaseOnce.Do(func() { close(release) })
			deadline := time.Now().Add(time.Second)
			for n.relaySessionMgr.IsRecovering() && time.Now().Before(deadline) {
				time.Sleep(time.Millisecond)
			}
			if n.relaySessionMgr.IsRecovering() {
				t.Fatal("completed owner retained mutation ownership")
			}
			if result := call(); result == nil || !result.Success {
				t.Fatalf("fresh recovery after owner completion = %+v, want success", result)
			}
		})
	}
}

func TestRecoveryDeadline_PanicReleasesOwnerAndAllowsRetry(t *testing.T) {
	for _, reconnect := range []bool{false, true} {
		name := "refresh"
		if reconnect {
			name = "reconnect"
		}
		t.Run(name, func(t *testing.T) {
			n := NewNode()
			n.hermeticLocalNetworkForTests = true
			n.warmRelayConnectionHook = func(peer.AddrInfo) error { return nil }
			n.waitForCircuitAddressHook = func(time.Duration) bool { return true }
			var attempts atomic.Int32
			n.refreshRelaySessionHook = func() *RecoveryResult {
				if attempts.Add(1) == 1 {
					panic("injected recovery failure")
				}
				return &RecoveryResult{RecoveryMode: "in_place", Success: true}
			}
			if _, err := n.Start(NodeConfig{
				PrivateKeyHex:  generateTestKey(t),
				RelayAddresses: []string{generateFakeRelayAddr(t, 19046)},
			}); err != nil {
				t.Fatal(err)
			}
			defer n.Stop()
			call := func() *RecoveryResult {
				if reconnect {
					result, _ := n.ReconnectRelays()
					return result
				}
				return n.RefreshRelaySession()
			}
			if result := call(); result == nil || result.Success || result.ErrorCode != "RECOVERY_PANIC" {
				t.Fatalf("panicking owner = %+v, want structured failure", result)
			}
			if n.relaySessionMgr.IsRecovering() {
				t.Fatal("panic retained recovery ownership")
			}
			if result := call(); result == nil || !result.Success {
				t.Fatalf("retry after panic = %+v, want success", result)
			}
		})
	}
}

func TestRecoveryDeadline_WaiterTimeoutKeepsOwnerGate(t *testing.T) {
	m := NewRelaySessionManager()
	// Leave enough scheduling margin to distinguish an already-expired shared
	// deadline from granting this later caller an entire new wait budget.
	m.recoveryWaitTimeout = 200 * time.Millisecond
	owner, _ := m.BeginRecovery()
	waiter, _ := m.BeginRecovery()
	if _, err := waiter.Wait(); err == nil || err.Error() != "RECOVERY_TIMEOUT" {
		t.Fatalf("Wait() = %v, want RECOVERY_TIMEOUT", err)
	}
	if !m.IsRecovering() {
		t.Fatal("waiter timeout allowed a second owner while the first can still mutate the host")
	}
	joined, isNew := m.BeginRecovery()
	if isNew || joined != owner {
		t.Fatal("retry must share the outstanding native owner")
	}
	start := time.Now()
	_, err := joined.Wait()
	if err == nil || err.Error() != "RECOVERY_TIMEOUT" {
		t.Fatalf("late joiner error = %v, want RECOVERY_TIMEOUT", err)
	}
	if elapsed := time.Since(start); elapsed >= m.recoveryWaitTimeout/2 {
		t.Fatalf("late joiner received a new timeout budget (%v)", elapsed)
	}
}
