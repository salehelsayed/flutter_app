package bridge

import (
	"encoding/json"
	"testing"
)

// 219 B04 (INV-B1 behavioural, MANDATORY) — the ONLY test that exercises the
// actual risky edit through a REAL partial-JSON decode: the bridge.go field-type
// change (*node.FeatureFlags -> map[string]bool) AND the nil-branch wiring
// (nil -> preserve the nil->DefaultFeatureFlags contract, else merge). B01/B02
// test the extracted pure helper in isolation; only this test drives the actual
// decode seam.
//
// It drives node:start with a PARTIAL featureFlags map that OMITS
// enableLibp2pLANDial (a graduated default-TRUE flag) and asserts Status()
// reports it as true — the omitted key resolved to its Go DEFAULT, not the JSON
// zero-value false.
//
// RED on HEAD: HEAD unmarshals wholesale into *node.FeatureFlags, so the omitted
// enableLibp2pLANDial decodes to zero-value false and Status() reports false.
// GREEN after the bridge merge. Mutation: revert the bridge.go merge -> reds.
func TestStartNode_PartialFeatureFlagsMap_KeepsGoDefaults(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	// Partial map: one PRESENT explicit-false override (enableMultiRelayRouting)
	// plus the load-bearing OMISSION of enableLibp2pLANDial (Go default true).
	input, err := json.Marshal(map[string]interface{}{
		"privateKeyHex":  keyHex,
		"relayAddresses": []string{},
		"namespace":      "",
		"autoRegister":   false,
		"listenPort":     0,
		"featureFlags": map[string]bool{
			"enableMultiRelayRouting": false,
		},
	})
	if err != nil {
		t.Fatalf("marshal start params: %v", err)
	}

	startResult := StartNode(string(input))
	startMap := parseJSON(t, startResult)
	assertOk(t, startMap)

	// Status() serializes the effective flags via featureFlagsStatusMap; after
	// the JSON round-trip the bool values arrive as interface{}-boxed bools.
	flags, ok := startMap["featureFlags"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected featureFlags map in node:start status, got %T", startMap["featureFlags"])
	}

	// The OMITTED graduated flag must resolve to its Go DEFAULT (true), NOT the
	// zero-value false a wholesale decode would produce.
	if got, _ := flags["enableLibp2pLANDial"].(bool); !got {
		t.Fatalf("omitted enableLibp2pLANDial must keep Go default true through the real decode seam, got %v (partial map silently darkened it)", flags["enableLibp2pLANDial"])
	}

	// The PRESENT explicit-false override must still win.
	if got, _ := flags["enableMultiRelayRouting"].(bool); got {
		t.Fatalf("present enableMultiRelayRouting=false override must win, got %v", flags["enableMultiRelayRouting"])
	}

	// An independent witness: a second omitted default-true key stays true.
	if got, _ := flags["enableSharedRelayBackend"].(bool); !got {
		t.Fatalf("omitted enableSharedRelayBackend must keep Go default true, got %v", flags["enableSharedRelayBackend"])
	}
}
