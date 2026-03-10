package node

import (
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
)

func TestFeatureFlags_DefaultsRemainBackwardCompatible(t *testing.T) {
	cfg := NodeConfig{}
	flags := cfg.EffectiveFlags()

	if !flags.EnableSharedRelayBackend {
		t.Fatal("EnableSharedRelayBackend should default to true")
	}
	if !flags.EnableMultiRelayRouting {
		t.Fatal("EnableMultiRelayRouting should default to true")
	}
	if !flags.EnableReservationAwareHealth {
		t.Fatal("EnableReservationAwareHealth should default to true")
	}
	if !flags.EnableInPlaceRelayRecovery {
		t.Fatal("EnableInPlaceRelayRecovery should default to true")
	}
	if !flags.EnableResumeGroupRecovery {
		t.Fatal("EnableResumeGroupRecovery should default to true")
	}
}

func TestStartNode_DisablesMultiRelayRoutingWhenFlagFalse(t *testing.T) {
	addr1 := generateFakeRelayAddr(t, 19011)
	addr2 := generateFakeRelayAddr(t, 19012)

	n := NewNode()
	defer func() { _ = n.Stop() }()

	cfg := NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{addr1, addr2},
		FeatureFlags: &FeatureFlags{
			EnableSharedRelayBackend:     true,
			EnableMultiRelayRouting:      false,
			EnableReservationAwareHealth: true,
			EnableInPlaceRelayRecovery:   true,
			EnableResumeGroupRecovery:    true,
		},
	}

	if _, err := n.Start(cfg); err != nil {
		t.Fatalf("Start() error: %v", err)
	}

	if len(n.relayAddresses) != 1 {
		t.Fatalf("expected single relay address when multi-relay routing disabled, got %d", len(n.relayAddresses))
	}
	if rs := n.buildRelaySelector(nil); rs.Len() != 1 {
		t.Fatalf("expected relay selector to use one relay, got %d", rs.Len())
	}

	status := n.Status()
	flags, ok := status["featureFlags"].(map[string]bool)
	if !ok {
		t.Fatalf("expected featureFlags map in status, got %T", status["featureFlags"])
	}
	if flags["enableMultiRelayRouting"] {
		t.Fatal("expected enableMultiRelayRouting=false in node status")
	}
}

func TestReconnectRelays_DisablesInPlaceRecoveryWhenFlagFalse(t *testing.T) {
	n := NewNode()
	defer func() { _ = n.Stop() }()

	refreshCalled := false
	n.refreshRelaySessionHook = func() *RecoveryResult {
		refreshCalled = true
		return &RecoveryResult{
			RecoveryMode: "in_place",
			Success:      true,
		}
	}
	n.waitForCircuitAddressHook = func(timeoutMs time.Duration) bool {
		return true
	}

	cfg := NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{generateFakeRelayAddr(t, 19021)},
		FeatureFlags: &FeatureFlags{
			EnableSharedRelayBackend:     true,
			EnableMultiRelayRouting:      true,
			EnableReservationAwareHealth: true,
			EnableInPlaceRelayRecovery:   false,
			EnableResumeGroupRecovery:    true,
		},
	}

	if _, err := n.Start(cfg); err != nil {
		t.Fatalf("Start() error: %v", err)
	}

	result, err := n.ReconnectRelays()
	if err != nil {
		t.Fatalf("ReconnectRelays() error: %v", err)
	}
	if refreshCalled {
		t.Fatal("ReconnectRelays() should not attempt in-place recovery when disabled")
	}
	if result.RecoveryMode != "watchdog_restart" {
		t.Fatalf("expected watchdog_restart, got %q", result.RecoveryMode)
	}

	status := n.Status()
	if got := status["watchdogRestartCount"]; got != 1 {
		t.Fatalf("expected watchdogRestartCount=1 after full restart fallback, got %v", got)
	}
	if got := status["needsGroupRecovery"]; got != true {
		t.Fatalf("expected needsGroupRecovery=true after full restart fallback, got %v", got)
	}
}

func TestNodeStatus_DisablesReservationAwareHealthWhenFlagFalse(t *testing.T) {
	n := NewNode()
	flags := DefaultFeatureFlags()
	flags.EnableReservationAwareHealth = false
	n.featureFlags = &flags

	pid, err := peer.Decode("12D3KooWC5qe3PPm2x8nCGx3kkM1Q2VdGs14Q6gttxyPjdJawVSK")
	if err != nil {
		t.Fatalf("peer.Decode(): %v", err)
	}
	n.relaySessionMgr.InitRelayPeer(pid)
	n.relaySessionMgr.OnReservationOpened(pid)

	status := n.Status()
	if _, ok := status["relayState"]; ok {
		t.Fatal("relayState should be omitted when reservation-aware health is disabled")
	}

	statusFlags, ok := status["featureFlags"].(map[string]bool)
	if !ok {
		t.Fatalf("expected featureFlags map in status, got %T", status["featureFlags"])
	}
	if statusFlags["enableReservationAwareHealth"] {
		t.Fatal("expected enableReservationAwareHealth=false in node status")
	}
}
