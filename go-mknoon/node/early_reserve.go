package node

// FDC-07: cold-start early relay-reserve observability.
//
// FDC-S1 proved the relay-warm + auto-register goroutines already dispatch at
// the earliest synchronous point in Node.Start (right after host_ready) and are
// sub-second on real devices, so FDC-07's Go-side lever is OBSERVABILITY, not
// latency: surface a dispatch-time anchor so FDC-S1-style instrumentation can
// prove the reserve fires early. This lives in its own file (not inlined into
// the already-oversized Start) per the FDC-07 Scope Guard.

// emitReserveDispatchAnchor emits the node:startup_timing{phase:"reserve_dispatch"}
// anchor at the instant the relay-warm / auto-register goroutines are dispatched
// (immediately after host_ready). It carries sinceProcessStartMs so the
// dispatch instant shares the Dart process-start clock, and is ordered strictly
// before the existing completion-time relay_warm_done emit. Pure passthrough
// over emitEvent — it never re-acquires n.mu, so it is safe to call while
// Start still holds the write lock.
func (n *Node) emitReserveDispatchAnchor() {
	n.emitEvent("node:startup_timing", map[string]interface{}{
		"phase":               "reserve_dispatch",
		"sinceProcessStartMs": n.sinceProcessStartMs(),
	})
}
