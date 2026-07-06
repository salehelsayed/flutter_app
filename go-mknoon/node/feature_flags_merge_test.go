package node

import (
	"reflect"
	"strings"
	"testing"
)

// 219 — Feature-Flag Decode-Seam Merge Guard.
//
// These tests pin MergeFeatureFlagsOverDefaults, the decode-seam merge that
// makes "partial map => silent false" structurally impossible. The Go bridge
// decodes the Dart feature-flags map wholesale; a PARTIAL map lets any omitted
// key unmarshal to the zero-value false — NOT the Go default — silently
// darkening e.g. enableLibp2pLANDial fleet-wide. The merge starts from
// DefaultFeatureFlags() and overwrites ONLY the keys actually present in the
// map, so an omitted key keeps its Go default and a present key (including an
// explicit false) still overrides. See feature_flags.go.

// B01 (INV-B1 merge-not-replace): an omitted key keeps the Go DEFAULT, never
// the zero-value false; a present key — including an explicit false — wins.
//
// Mutation that re-reds: start the helper from FeatureFlags{} (zero-value)
// instead of DefaultFeatureFlags() — reproduces HEAD's silent-false and flips
// EnableLibp2pLANDial to false.
func TestMergeFeatureFlagsOverDefaults_OmittedKeyKeepsDefaultNotZeroValue(t *testing.T) {
	merged := MergeFeatureFlagsOverDefaults(map[string]bool{
		"enableMultiRelayRouting": false,
	})

	// Omitted default-true keys keep their Go default (NOT zero-value false).
	if !merged.EnableLibp2pLANDial {
		t.Fatal("omitted enableLibp2pLANDial must keep Go default true — a merge that starts from the zero-value struct silently darkens LAN-direct dial fleet-wide")
	}
	if !merged.EnableSharedRelayBackend {
		t.Fatal("omitted enableSharedRelayBackend must keep Go default true, got false")
	}

	// The single PRESENT key overrides the default (explicit false wins).
	if merged.EnableMultiRelayRouting {
		t.Fatal("present enableMultiRelayRouting=false override must win, got true")
	}

	// Omitted default-FALSE keys stay false (the merge does not spuriously
	// enable a dark flag).
	if merged.EnableDcutrUpgrade {
		t.Fatal("omitted enableDcutrUpgrade must keep Go default false, got true")
	}
	if merged.EnableLibp2pLANMedia {
		t.Fatal("omitted enableLibp2pLANMedia must keep Go default false, got true")
	}
}

// B02 (INV-B2 completeness): every FeatureFlags struct field is reachable by the
// merge. Impl-agnostic — passes for a map-driven OR switch-based merge. It
// iterates the struct by json tag and, for each field, drives Merge with a
// single-key override map {jsonTag: !defaultValue}, asserting THAT field flips.
// A future 10th flag added to the struct but not the merge path fails here (its
// single-key override does not flip). We assert the BEHAVIOUR (field flips), not
// a switch-case count — reflect cannot see source switch cases.
func TestMergeFeatureFlags_EveryStructFieldIsMergeable(t *testing.T) {
	defaults := DefaultFeatureFlags()
	dv := reflect.ValueOf(defaults)
	dt := dv.Type()

	if dt.NumField() == 0 {
		t.Fatal("FeatureFlags has no fields — merge completeness cannot be verified")
	}

	for i := 0; i < dt.NumField(); i++ {
		field := dt.Field(i)

		jsonTag := field.Tag.Get("json")
		if idx := strings.IndexByte(jsonTag, ','); idx >= 0 {
			jsonTag = jsonTag[:idx]
		}
		if jsonTag == "" || jsonTag == "-" {
			t.Fatalf("field %s has no usable json tag; the decode-seam merge is keyed by json tag", field.Name)
		}
		if field.Type.Kind() != reflect.Bool {
			t.Fatalf("field %s is %s, not bool; the merge helper assumes bool flags", field.Name, field.Type.Kind())
		}

		defaultVal := dv.Field(i).Bool()
		override := !defaultVal

		merged := MergeFeatureFlagsOverDefaults(map[string]bool{jsonTag: override})
		got := reflect.ValueOf(merged).Field(i).Bool()
		if got != override {
			t.Fatalf("field %s (json %q): single-key override to %v did not flip it (got %v) — the merge does not handle this field",
				field.Name, jsonTag, override, got)
		}
	}
}
