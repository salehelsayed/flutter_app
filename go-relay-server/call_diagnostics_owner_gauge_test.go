package main

import (
	"encoding/json"
	"strconv"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/prometheus/client_golang/prometheus"
)

func TestCallDiagnosticsOwnersAtLimitGauge(t *testing.T) {
	const actor = "gauge-test-owner"
	dir := t.TempDir()
	events := []json.RawMessage{
		diagnosticTestEvent(uuid.NewString(), "flutter", "attempt", "start"),
		diagnosticTestEvent(uuid.NewString(), "flutter", "attempt", "start"),
	}
	limit := func() int {
		store, err := newCallDiagnosticStore(dir, 0, time.Now)
		if err != nil {
			t.Fatal(err)
		}
		defer store.close()
		if err := store.configure(actor, true, false, 1); err != nil {
			t.Fatal(err)
		}
		for _, event := range events {
			if !store.appendEvent(actor, event, false, 1) {
				t.Fatal("could not seed retained usage")
			}
		}
		owner := diagnosticPrivateKey(actor)
		reserved := store.ownerBindingReserves[owner]
		if reserved == 0 {
			t.Fatal("seeded traces must have binding reservations")
		}
		return store.ownerSizes[owner] + reserved
	}()

	t.Setenv("CALL_DIAGNOSTICS_DIR", dir)
	t.Setenv("CALL_DIAGNOSTICS_OWNER_MAX_BYTES", strconv.Itoa(limit))
	store := initCallDiagnosticsFromEnvironment()
	if store == nil {
		t.Fatal("could not reopen call diagnostics store")
	}
	defer store.close()

	assertGauge := func(step string, want float64) {
		t.Helper()
		families, err := prometheus.DefaultGatherer.Gather()
		if err != nil {
			t.Fatal(err)
		}
		for _, family := range families {
			if family.GetName() != "relay_diagnostics_owners_at_limit" {
				continue
			}
			metrics := family.GetMetric()
			if len(metrics) != 1 || metrics[0].GetGauge() == nil {
				t.Fatalf("%s: expected one owners-at-limit gauge series", step)
			}
			labels := metrics[0].GetLabel()
			if len(labels) != 1 || labels[0].GetName() != "store" || labels[0].GetValue() != "call" {
				t.Fatalf("%s: owners-at-limit gauge must expose only store=call", step)
			}
			if got := metrics[0].GetGauge().GetValue(); got != want {
				t.Fatalf("%s: owners at limit = %g, want %g", step, got, want)
			}
			return
		}
		t.Fatalf("%s: missing relay_diagnostics_owners_at_limit", step)
	}

	assertGauge("reopened at the ordinary cap", 1)
	if err := store.clearActor(actor, 2); err != nil {
		t.Fatal(err)
	}
	assertGauge("after clear", 0)
	if !store.appendEvent(actor, events[0], false, 2) {
		t.Fatal("could not append the first trace after clear")
	}
	assertGauge("below the ordinary cap", 0)
	if !store.appendEvent(actor, events[1], false, 2) {
		t.Fatal("could not append the second trace after clear")
	}
	assertGauge("at the ordinary cap after append", 1)
}
