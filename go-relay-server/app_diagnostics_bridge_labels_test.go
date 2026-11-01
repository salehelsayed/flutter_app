package main

import "testing"

func TestAppDiagnosticBridgeLabelsCompatibilityAndPrivacy(t *testing.T) {
	for _, sample := range []struct {
		name   string
		values map[string]any
		valid  bool
	}{
		{"old_shape", map[string]any{"operation": "other"}, true},
		{"new_shape", map[string]any{"operation": "other", "bridgeCommandFamily": "messaging", "bridgeRejectionKind": "not_ready"}, true},
		{"unknown_classification", map[string]any{"bridgeCommandFamily": "unknown", "bridgeRejectionKind": "unknown"}, true},
		{"free_form_family", map[string]any{"bridgeCommandFamily": "private.command", "bridgeRejectionKind": "unknown"}, false},
		{"free_form_rejection", map[string]any{"bridgeCommandFamily": "messaging", "bridgeRejectionKind": "private error text"}, false},
	} {
		t.Run(sample.name, func(t *testing.T) {
			event := appTestEvent()
			event["feature"] = "runtime"
			event["stage"] = "bridge"
			event["outcome"] = "failed"
			event["reason"] = "bridge_rejected"
			event["values"] = sample.values
			_, err := validateAppDiagnosticEvent(appJSON(event), false)
			if (err == nil) != sample.valid {
				t.Fatalf("valid=%v, wanted %v", err == nil, sample.valid)
			}
		})
	}
}
