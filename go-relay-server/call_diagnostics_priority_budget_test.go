package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/google/uuid"
)

func readCallDiagnosticBudgetRecord(t *testing.T, store *callDiagnosticStore, trace string) []byte {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(store.dir, trace+".json"))
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func callDiagnosticBudgetEventID(t *testing.T, raw json.RawMessage) string {
	t.Helper()
	var event struct {
		ID string `json:"eventId"`
	}
	if err := json.Unmarshal(raw, &event); err != nil || event.ID == "" {
		t.Fatalf("missing event ID: %v", err)
	}
	return event.ID
}

func TestCallDiagnosticsPriorityBudgetRejectsOrdinaryAtOwnerCap(t *testing.T) {
	for _, traceState := range []string{"existing", "fresh"} {
		t.Run(traceState, func(t *testing.T) {
			store := hotfixCall(t)
			seedTrace := uuid.NewString()
			if !store.appendEvent("owner", diagnosticTestEvent(seedTrace, "flutter", "attempt", "start"), false, 1) {
				t.Fatal("could not seed owner usage")
			}
			before := readCallDiagnosticBudgetRecord(t, store, seedTrace)
			store.ownerQuota = len(before)
			trace := seedTrace
			if traceState == "fresh" {
				trace = uuid.NewString()
			}
			event := diagnosticTestEvent(trace, "flutter", "attempt", "start")
			id := callDiagnosticBudgetEventID(t, event)
			checkCallDiagnosticRefusalMetric(t, "upload", "owner_bytes", "budget_exceeded", func() {
				data := hotfixUpload(t, store, "owner", 1, event)
				if accepted, rejected := data["acceptedEventIds"].([]any), data["rejectedEventIds"].([]any); len(accepted) != 0 || !slices.Equal(rejected, []any{id}) || data["reason"] != "quota_exceeded" {
					t.Fatalf("owner budget refusal did not settle the ordinary event: %v", data)
				}
			})
			if after := readCallDiagnosticBudgetRecord(t, store, seedTrace); !bytes.Equal(before, after) {
				t.Fatal("ordinary refusal changed retained evidence")
			}
			if traceState == "fresh" {
				if _, err := os.Stat(filepath.Join(store.dir, trace+".json")); !os.IsNotExist(err) {
					t.Fatalf("ordinary refusal created a fresh trace or its absence could not be verified: %v", err)
				}
			}
		})
	}
}

func TestCallDiagnosticsPriorityBudgetRetainsEvidenceAtOwnerCap(t *testing.T) {
	for _, traceState := range []string{"existing", "fresh"} {
		t.Run(traceState, func(t *testing.T) {
			store := hotfixCall(t)
			seedTrace := uuid.NewString()
			seed := diagnosticTestEvent(seedTrace, "flutter", "attempt", "start")
			if !store.appendEvent("owner", seed, false, 1) {
				t.Fatal("could not seed owner usage")
			}
			trace, mediaActor, mediaRole := seedTrace, "recipient", "callee"
			if traceState == "fresh" {
				trace, mediaActor, mediaRole = uuid.NewString(), "owner", "caller"
			} else {
				if err := store.configure(mediaActor, true, false, 1); err != nil {
					t.Fatal(err)
				}
				d := publicationPrepare(t, store, "owner", trace)
				store.bindCommitted("owner", mediaActor, "handle", &d)
				awaitCallDiagnosticBudgetJob(t, store)
			}
			before := readCallDiagnosticBudgetRecord(t, store, seedTrace)
			store.ownerQuota = len(before)

			finish := diagnosticTestEvent(trace, "flutter", "terminal", "finish")
			var cause, media map[string]any
			if err := json.Unmarshal(diagnosticTestEvent(trace, "flutter", "terminal", "snapshot"), &cause); err != nil {
				t.Fatal(err)
			}
			cause["values"] = map[string]any{"endCause": "local_hangup", "endCauseStage": "runtime"}
			if err := json.Unmarshal(diagnosticTestEvent(trace, "flutter", "media", "snapshot"), &media); err != nil {
				t.Fatal(err)
			}
			media["role"], media["outcome"] = mediaRole, "media_flow_verified"
			causeRaw, mediaRaw := mustDiagnosticJSON(cause), mustDiagnosticJSON(media)
			wantSummaries := []string{
				callDiagnosticBudgetEventID(t, finish),
				callDiagnosticBudgetEventID(t, causeRaw),
				callDiagnosticBudgetEventID(t, mediaRaw),
			}
			for _, upload := range []struct {
				actor string
				raw   json.RawMessage
			}{{"owner", finish}, {"owner", causeRaw}, {mediaActor, mediaRaw}} {
				id := callDiagnosticBudgetEventID(t, upload.raw)
				data := hotfixUpload(t, store, upload.actor, 1, upload.raw)
				if accepted, rejected := data["acceptedEventIds"].([]any), data["rejectedEventIds"].([]any); !slices.Equal(accepted, []any{id}) || len(rejected) != 0 {
					t.Errorf("priority upload by %s was refused: %v", upload.actor, data)
				}
			}
			if t.Failed() {
				return
			}
			var retained callDiagnosticRecord
			if err := json.Unmarshal(readCallDiagnosticBudgetRecord(t, store, trace), &retained); err != nil {
				t.Fatal(err)
			}
			var summaries []string
			for _, row := range retained.Summaries {
				summaries = append(summaries, callDiagnosticBudgetEventID(t, row.Event))
			}
			slices.Sort(summaries)
			slices.Sort(wantSummaries)
			if !slices.Equal(summaries, wantSummaries) {
				t.Fatalf("durable summaries = %v, want %v", summaries, wantSummaries)
			}
			if traceState == "fresh" {
				if after := readCallDiagnosticBudgetRecord(t, store, seedTrace); !bytes.Equal(before, after) {
					t.Fatal("fresh priority trace changed unrelated retained evidence")
				}
			} else {
				seedID := callDiagnosticBudgetEventID(t, seed)
				if !slices.ContainsFunc(retained.Events, func(row callDiagnosticStoredEvent) bool {
					return callDiagnosticBudgetEventID(t, row.Event) == seedID
				}) {
					t.Fatal("priority writes evicted the retained ordinary event")
				}
			}
		})
	}
}

func TestCallDiagnosticsPriorityBudgetRetriesAtHardCaps(t *testing.T) {
	for _, capKind := range []string{"owner_bytes", "global_bytes"} {
		t.Run(capKind, func(t *testing.T) {
			store := hotfixCall(t)
			trace := uuid.NewString()
			if !store.appendEvent("owner", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
				t.Fatal("could not seed owner usage")
			}
			before := readCallDiagnosticBudgetRecord(t, store, trace)
			if capKind == "owner_bytes" {
				store.ownerQuota = len(before)
				// Simulate the same owner holding the full 1 MiB priority allowance
				// in other retained traces without writing megabytes of fixture data.
				store.ownerSizes[diagnosticPrivateKey("owner")] += 1 << 20
				store.usedBytes += 1 << 20
			} else {
				store.quota = len(before)
			}
			event := diagnosticTestEvent(trace, "flutter", "terminal", "finish")
			checkCallDiagnosticRefusalMetric(t, "upload", capKind, "budget_exceeded", func() {
				data := hotfixUpload(t, store, "owner", 1, event)
				if accepted, rejected := data["acceptedEventIds"].([]any), data["rejectedEventIds"].([]any); len(accepted) != 0 || len(rejected) != 0 || data["reason"] != "sink_unavailable" {
					t.Fatalf("priority evidence must stay retryable at the hard cap: %v", data)
				}
			})
			if after := readCallDiagnosticBudgetRecord(t, store, trace); !bytes.Equal(before, after) {
				t.Fatal("priority refusal changed retained evidence")
			}
		})
	}
}

func TestCallDiagnosticsPriorityBudgetPreservesAlreadyReservedBinding(t *testing.T) {
	store := hotfixCall(t)
	trace := uuid.NewString()
	if !store.appendEvent("owner", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
		t.Fatal("could not seed owner usage")
	}
	owner := diagnosticPrivateKey("owner")
	store.ownerQuota = store.ownerSizes[owner]
	before := store.ownerSizes[owner] + store.ownerBindingReserves[owner]
	d := publicationPrepare(t, store, "owner", trace)
	store.bindCommitted("owner", "recipient", "handle", &d)
	awaitCallDiagnosticBudgetJob(t, store)

	var record callDiagnosticRecord
	if err := json.Unmarshal(readCallDiagnosticBudgetRecord(t, store, trace), &record); err != nil {
		t.Fatal(err)
	}
	if len(record.Bindings) != 2 || store.ownerSizes[owner]+store.ownerBindingReserves[owner] != before {
		t.Fatal("binding did not publish from its already charged reservation")
	}
}
