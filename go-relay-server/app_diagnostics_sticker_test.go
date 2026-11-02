package main

import "testing"

func TestAppDiagnosticStickerSchemaCompatibilityAndPrivacy(t *testing.T) {
	for _, sample := range []struct {
		name    string
		sticker any
		count   any
		valid   bool
	}{
		{"bundled", "orbit_crew.planet.hello", 2, true},
		{"custom", "custom", 1, true},
		{"unknown", "unknown", 1, true},
		{"free_text", "PRIVATE_STICKER_TEXT", 1, false},
		{"negative_count", "custom", -1, false},
		{"fractional_count", "custom", 1.5, false},
		{"boolean_count", "custom", true, false},
	} {
		t.Run(sample.name, func(t *testing.T) {
			event := appTestEvent()
			event["feature"] = "stickers"
			event["stage"] = "snapshot"
			event["outcome"] = "ok"
			event["reason"] = "none"
			event["values"] = map[string]any{"sticker": sample.sticker, "count": sample.count, "reportTimeIsIntervalEnd": true}
			_, err := validateAppDiagnosticEvent(appJSON(event), false)
			if (err == nil) != sample.valid {
				t.Fatalf("valid=%v, wanted %v", err == nil, sample.valid)
			}
		})
	}
	if _, err := validateAppDiagnosticEvent(appJSON(appTestEvent()), false); err != nil {
		t.Fatal("old-shape event must remain valid")
	}
}
