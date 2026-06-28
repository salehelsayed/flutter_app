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
	if !flags.EnableDeferredDirectAck {
		t.Fatal("EnableDeferredDirectAck should default to true")
	}
}

// FDC-16 (CV-09 / CV-13 / FDC-15) — the Fast-Direct-Connection transport flags
// ship DARK: they default to false and may flip to true ONLY after their
// device-proof gate closes (FDC-16 Scope Guard — never flip a prod flag ahead of
// its device proof). This is the PARKED pre-flip polarity of the staged
// flag-flip locks: it pins the current dark default so an accidental EARLY flip
// re-reds here. When a gate closes, the matching CV inverts its assertion:
//
//	EnableLibp2pLANDial  -> true after FDC-11 D1 two-phone proof (CV-08 -> CV-09)
//	EnableDcutrUpgrade   -> true after the FDC-12 DCUtR campaign  (CV-11/12 -> CV-13)
//	EnableLibp2pLANMedia -> true after FDC-15 D1 LAN-media proof  (CV-34)
func TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof(t *testing.T) {
	flags := DefaultFeatureFlags()
	if flags.EnableLibp2pLANDial {
		t.Fatal("EnableLibp2pLANDial must default false (dark) until FDC-11 D1 device-proof closes (CV-08 -> CV-09); do not flip ahead of device proof")
	}
	if flags.EnableDcutrUpgrade {
		t.Fatal("EnableDcutrUpgrade must default false (dark) until the FDC-12 DCUtR device campaign closes (CV-11/12 -> CV-13)")
	}
	if flags.EnableLibp2pLANMedia {
		t.Fatal("EnableLibp2pLANMedia must default false (dark) until FDC-15 D1 LAN-media device-proof closes (CV-34)")
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
			EnableDeferredDirectAck:      true,
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
			EnableDeferredDirectAck:      true,
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
