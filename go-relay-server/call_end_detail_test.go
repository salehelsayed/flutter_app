package main

import (
	"bytes"
	"encoding/json"
	"testing"

	"github.com/google/uuid"
)

func TestCallDiagnosticsCallEndDetailClosedVocabulary(t *testing.T) {
	base := diagnosticTestEvent(uuid.NewString(), "flutter", "terminal", "snapshot")
	var event map[string]any
	if err := json.Unmarshal(base, &event); err != nil {
		t.Fatal(err)
	}
	event["values"] = map[string]any{
		"endCause": "recovery_denied", "endCauseStage": "authority",
		"recoveryCheck": "preference_epoch", "durationMs": 2000,
	}
	raw, err := json.Marshal(event)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := validateCallDiagnosticEvent(raw, false); err != nil {
		t.Fatalf("closed detail rejected: %v", err)
	}
	for _, key := range []string{"endCause", "endCauseStage", "recoveryCheck"} {
		t.Run(key, func(t *testing.T) {
			var invalid map[string]any
			if err := json.Unmarshal(raw, &invalid); err != nil {
				t.Fatal(err)
			}
			invalid["values"].(map[string]any)[key] = "PRIVATE_PEER_OR_ERROR"
			encoded, err := json.Marshal(invalid)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := validateCallDiagnosticEvent(encoded, false); err == nil {
				t.Fatal("arbitrary identifying string accepted")
			}
		})
	}
}

func TestCallDiagnosticsCallEndDetailPreservesOriginalSummary(t *testing.T) {
	s := diagnosticTestStore(t)
	if err := s.configure("caller", true, false, 1); err != nil {
		t.Fatal(err)
	}
	trace := uuid.NewString()
	final := diagnosticTestEvent(trace, "flutter", "terminal", "finish")
	if !s.appendEvent("caller", final, false) {
		t.Fatal("original final rejected")
	}
	var detail map[string]any
	if err := json.Unmarshal(diagnosticTestEvent(trace, "flutter", "terminal", "snapshot"), &detail); err != nil {
		t.Fatal(err)
	}
	detail["values"] = map[string]any{
		"endCause": "ice_failed", "endCauseStage": "media", "durationMs": 2000,
	}
	raw, err := json.Marshal(detail)
	if err != nil {
		t.Fatal(err)
	}
	if !s.appendEvent("caller", raw, false) {
		t.Fatal("separate detail rejected")
	}
	record := s.records[trace]
	if len(record.Summaries) != 1 || len(record.Events) != 2 {
		t.Fatal("detail displaced the authoritative terminal summary")
	}
	for _, summary := range record.Summaries {
		if !bytes.Equal(summary.Event, final) {
			t.Fatal("detail replaced the original final bytes")
		}
	}
}
