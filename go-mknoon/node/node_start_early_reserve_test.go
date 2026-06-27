package node

import (
	"testing"
	"time"
)

// TestStart_EmitsReserveDispatchAnchor_AtNodeReady locks FDC-07's NEW
// dispatch-time observability anchor.
//
// FDC-S1 proved the relay-warm + auto-register goroutines already dispatch at
// the earliest synchronous point in Node.Start (right after host_ready) and are
// sub-second — there is no slower Go step to move them ahead of. The genuinely
// new, RED-able delta is therefore an OBSERVABLE anchor at the dispatch instant:
// a node:startup_timing{phase:"reserve_dispatch", sinceProcessStartMs} emitted
// when the goroutines are kicked off, ordered strictly BEFORE the existing
// completion-time relay_warm_done.
//
// Vacuity guard: relay_warm_done ALREADY emits and ALREADY carries
// sinceProcessStartMs (FDC-S1), so asserting *that* would pass on HEAD without
// any change. This test asserts the DISTINCT dispatch-time phase, which does not
// exist on HEAD → RED.
func TestStart_EmitsReserveDispatchAnchor_AtNodeReady(t *testing.T) {
	hexKey := generateTestKey(t)
	collector := &testEventCollector{}
	n := New(collector)

	// A syntactically valid but unreachable relay so relayInfos is non-empty and
	// the relay_warm_done goroutine is launched (mirrors the benchmark harness).
	fakeRelay := "/ip4/192.0.2.1/tcp/4001/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
	// A recent process-start epoch so sinceProcessStartMs is positive.
	procStart := time.Now().Add(-500 * time.Millisecond).UnixMilli()

	_, err := n.Start(NodeConfig{
		PrivateKeyHex:       hexKey,
		RelayAddresses:      []string{fakeRelay},
		AutoRegister:        true,
		ProcessStartEpochMs: procStart,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Let the async event dispatcher flush the synchronous Start emits.
	time.Sleep(50 * time.Millisecond)

	events := collector.collectEvents("node:startup_timing")
	var dispatch map[string]interface{}
	for _, ev := range events {
		if phase, _ := ev["phase"].(string); phase == "reserve_dispatch" {
			dispatch = ev
			break
		}
	}
	if dispatch == nil {
		t.Fatal("expected a node:startup_timing{phase:\"reserve_dispatch\"} anchor at " +
			"node-ready; none emitted (FDC-07 dispatch anchor missing)")
	}
	dispatchSince, ok := dispatch["sinceProcessStartMs"].(float64)
	if !ok {
		t.Fatal("reserve_dispatch must carry sinceProcessStartMs")
	}
	if dispatchSince <= 0 {
		t.Fatalf("reserve_dispatch sinceProcessStartMs should be > 0, got %v", dispatchSince)
	}

	// Trigger the completion-time relay_warm_done and assert the dispatch anchor
	// is distinct from it AND ordered strictly before it.
	n.relayReadyOnce.Do(func() { close(n.relayReady) })
	time.Sleep(100 * time.Millisecond)

	events = collector.collectEvents("node:startup_timing")
	dispatchIdx, warmIdx := -1, -1
	var warmDone map[string]interface{}
	for i, ev := range events {
		switch phase, _ := ev["phase"].(string); phase {
		case "reserve_dispatch":
			if dispatchIdx == -1 {
				dispatchIdx = i
			}
		case "relay_warm_done":
			warmDone = ev
			warmIdx = i
		}
	}
	if warmDone == nil {
		t.Fatal("relay_warm_done should be emitted after relayReady closes")
	}
	if dispatchIdx == -1 || warmIdx == -1 || dispatchIdx >= warmIdx {
		t.Fatalf("reserve_dispatch (idx %d) must be emitted strictly before "+
			"relay_warm_done (idx %d) — dispatch precedes completion", dispatchIdx, warmIdx)
	}
	if warmSince, ok := warmDone["sinceProcessStartMs"].(float64); ok {
		if dispatchSince > warmSince {
			t.Fatalf("reserve_dispatch sinceProcessStartMs (%v) must be <= "+
				"relay_warm_done (%v) — dispatch happens before completion",
				dispatchSince, warmSince)
		}
	}
}
