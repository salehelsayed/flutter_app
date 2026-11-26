package main

import (
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

func checkCallDiagnosticRefusalMetric(t *testing.T, source, cause, outcome string, run func()) {
	t.Helper()
	detail := diagnosticRefusals.WithLabelValues("call", source, cause)
	budget := callDiagnosticEvents.WithLabelValues("budget_exceeded")
	sink := callDiagnosticEvents.WithLabelValues("sink_unavailable")
	detailBefore := testutil.ToFloat64(detail)
	budgetBefore, sinkBefore := testutil.ToFloat64(budget), testutil.ToFloat64(sink)

	run()

	if delta := testutil.ToFloat64(detail) - detailBefore; delta != 1 {
		t.Fatalf("%s/%s refusal delta = %g, want 1", source, cause, delta)
	}
	budgetWant, sinkWant := 1.0, 0.0
	if outcome == "sink_unavailable" {
		budgetWant, sinkWant = 0, 1
	}
	budgetDelta := testutil.ToFloat64(budget) - budgetBefore
	sinkDelta := testutil.ToFloat64(sink) - sinkBefore
	if budgetDelta != budgetWant || sinkDelta != sinkWant {
		t.Fatalf("%s/%s: budget_exceeded delta = %g, sink_unavailable delta = %g; want %g and %g",
			source, cause, budgetDelta, sinkDelta, budgetWant, sinkWant)
	}
}

func awaitCallDiagnosticBudgetJob(t *testing.T, store *callDiagnosticStore) {
	t.Helper()
	done := make(chan struct{})
	store.enqueue(func() { close(done) })
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("timed out waiting for the call diagnostics worker")
	}
}

func TestCallDiagnosticsUploadBudgetRefusalMetrics(t *testing.T) {
	for _, cause := range []string{"owner_bytes", "global_bytes", "persistence"} {
		t.Run(cause, func(t *testing.T) {
			store := hotfixCall(t)
			outcome := "budget_exceeded"
			switch cause {
			case "owner_bytes":
				store.ownerQuota = 1
			case "global_bytes":
				store.quota = 1
			case "persistence":
				store.write = func(string, []byte) error { return errors.New("injected write refusal") }
				outcome = "sink_unavailable"
			}
			event := diagnosticTestEvent(uuid.NewString(), "flutter", "attempt", "start")
			checkCallDiagnosticRefusalMetric(t, "upload", cause, outcome, func() {
				data := hotfixUpload(t, store, "owner", 1, event)
				if len(data["acceptedEventIds"].([]any)) != 0 {
					t.Fatalf("refused upload unexpectedly accepted: %v", data)
				}
				if cause != "owner_bytes" && (data["reason"] != "sink_unavailable" || len(data["rejectedEventIds"].([]any)) != 0) {
					t.Fatalf("legacy retry response changed: %v", data)
				}
			})
		})
	}
}

func TestCallDiagnosticsSpanBudgetRefusalMetrics(t *testing.T) {
	store := hotfixCall(t)
	d := publicationPrepare(t, store, "owner", uuid.NewString())
	store.ownerQuota = 1
	checkCallDiagnosticRefusalMetric(t, "span", "owner_bytes", "budget_exceeded", func() {
		publicationEmit(store, "owner", d)
		awaitCallDiagnosticBudgetJob(t, store)
	})
}

func TestCallDiagnosticsBindingBudgetRefusalMetrics(t *testing.T) {
	for _, name := range []string{"new_trace", "existing_trace"} {
		t.Run(name, func(t *testing.T) {
			store := hotfixCall(t)
			seed := uuid.NewString()
			if !store.appendEvent("owner", diagnosticTestEvent(seed, "flutter", "attempt", "start"), false, 1) {
				t.Fatal("could not seed owner usage")
			}
			trace := seed
			if name == "new_trace" {
				trace = uuid.NewString()
			}
			d := publicationPrepare(t, store, "owner", trace)
			owner := diagnosticPrivateKey("owner")
			store.ownerQuota = store.ownerSizes[owner]
			if name == "existing_trace" {
				// Simulate retained usage above the combined cap. An existing
				// binding can otherwise spend its already charged reservation.
				store.ownerSizes[owner] += 1 << 20
				store.usedBytes += 1 << 20
			}
			checkCallDiagnosticRefusalMetric(t, "binding", "owner_bytes", "budget_exceeded", func() {
				store.bindCommitted("owner", "recipient", "handle", &d)
				awaitCallDiagnosticBudgetJob(t, store)
			})
		})
	}
}
