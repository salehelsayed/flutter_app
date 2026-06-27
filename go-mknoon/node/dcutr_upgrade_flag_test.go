package node

import "testing"

// FDC-12 TC-12-01 — flag OFF preserves ForceReachabilityPrivate + ZERO punches
// (PRESERVATION). EnableDcutrUpgrade is the lone default-false FeatureFlag; with
// it off (and the test seam off) the host must keep the production
// ForceReachabilityPrivate() invariant (holepunch_tracer.go:15-17), so DCUtR
// only observes and never initiates a punch.
//
// The behavioral ZERO-punch-under-private lock (Successes()==Attempts()==0, no
// transport:upgraded emitted) lives in holepunch_negative_control_test.go, which
// already runs under DefaultFeatureFlags() (= private). This test pins the flag
// default and the flag→reachability mapping that keeps that invariant true.
func TestDcutrFlagOff_ForcesPrivate_ZeroPunches(t *testing.T) {
	if DefaultFeatureFlags().EnableDcutrUpgrade {
		t.Fatalf("DefaultFeatureFlags().EnableDcutrUpgrade = true, want false " +
			"(the lone default-false flag — see feature_flags.go doc-comment)")
	}

	// flag OFF + no force-public seam → production ForceReachabilityPrivate().
	if got := dcutrReachabilityMode(false, false); got != "private" {
		t.Fatalf("dcutrReachabilityMode(off, seamOff) = %q, want private "+
			"(holepunch_tracer.go:15-17 ZERO-punch invariant)", got)
	}

	// The PROTOCOL-feasibility force-public test seam still works independently
	// of the flag (it must, for holepunch_feasibility_test.go).
	if got := dcutrReachabilityMode(false, true); got != "public" {
		t.Fatalf("dcutrReachabilityMode(off, seamOn) = %q, want public", got)
	}
}

// FDC-12 TC-12-02 — flag ON selects the upgrade-permitting reachability mode.
// With the flag on, the host opts into ForceReachabilityPublic() so the DCUtR
// holepuncher can actively upgrade a relay conn to direct. FDC-S2 left the
// production flip-safety device-gated, so the flag stays default-off until the
// DCUtR device campaign closes; this test only locks the flag→opt mapping.
func TestDcutrFlagOn_SelectsUpgradeReachability(t *testing.T) {
	if got := dcutrReachabilityMode(true, false); got != "public" {
		t.Fatalf("dcutrReachabilityMode(on, seamOff) = %q, want public "+
			"(upgrade-permitting reachability)", got)
	}
	// flag OFF stays private (preservation, mirrors TC-12-01).
	if got := dcutrReachabilityMode(false, false); got != "private" {
		t.Fatalf("dcutrReachabilityMode(off, seamOff) = %q, want private", got)
	}
}

// FDC-12 TC-12-10 (Go half) — the flag plumbs through NodeConfig.FeatureFlags.
// The Dart half (the feature-flags map handed to the Go bridge defaults the key
// off) lives in p2p_service_dcutr_flag_test.dart. Here we lock that an explicit
// FeatureFlags{EnableDcutrUpgrade:true} survives EffectiveFlags() and that a nil
// FeatureFlags falls back to the default (false for this flag).
func TestDcutrFlag_PlumbsThroughNodeConfig(t *testing.T) {
	cfg := NodeConfig{FeatureFlags: &FeatureFlags{EnableDcutrUpgrade: true}}
	if !cfg.EffectiveFlags().EnableDcutrUpgrade {
		t.Fatalf("explicit FeatureFlags{EnableDcutrUpgrade:true} did not plumb " +
			"through EffectiveFlags()")
	}

	var nilCfg NodeConfig
	if nilCfg.EffectiveFlags().EnableDcutrUpgrade {
		t.Fatalf("nil FeatureFlags → EffectiveFlags().EnableDcutrUpgrade = true, " +
			"want false (default)")
	}
}
