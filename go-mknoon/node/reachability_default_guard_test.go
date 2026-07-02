package node

import "testing"

// TC-189-41 (unit half): the DEFAULT flag map must keep libp2p reachability
// Private. Under Private, autorelay's relayFinder is the sole publisher of
// /p2p-circuit addresses; forcing Public (the 188 EnableDcutrUpgrade coupling,
// node.go dcutrReachabilityMode seam) stops it and re-creates the NO_CIRCUIT
// wedge of spec 189 fleet-wide. A default-flag flip must fail here, not in
// field debugging. (dcutr_upgrade_flag_test.go covers the function table;
// this pins the DEFAULTS feeding it.)
func TestDefaultFlagsKeepPrivateReachability(t *testing.T) {
	flags := DefaultFeatureFlags()
	if flags.EnableDcutrUpgrade {
		t.Fatal("default EnableDcutrUpgrade must stay false — ON forces Public reachability and kills autorelay circuit publishing (188 coupling)")
	}
	if got := dcutrReachabilityMode(flags.EnableDcutrUpgrade, false); got != "private" {
		t.Fatalf("default-flag reachability = %q, want private (autorelay must stay eligible to publish /p2p-circuit)", got)
	}
}
