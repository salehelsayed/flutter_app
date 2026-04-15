# Fact-Check Implementation Checklist

> **Source:** Audit of `03-timing-and-performance.md` and `03f-benchmark-test-inventory.md` against codebase (2026-04-15).
> **Scope:** Items where documentation describes intended behavior that is not yet implemented in production code. Each item has a concrete implementation path and a traceability section listing exactly what to update in `03.md` and `03f` after implementation.

---

## 1. Implement `INBOX_DELIVERY_TIMING` event

**Status:** Not implemented
**Documented in:** `03.md` Section 1 (Dart events table), `03f` D-Sim-2
**Blocked:** D-Sim-2 baseline metric `sim_inbox_e2e_delivery_ms`, `03f` Baseline Table "Inbox E2E Delivery p50, p95"

### What's missing

The `INBOX_DELIVERY_TIMING` event (fields: `deliveryMs`, `messageId`) is referenced in both docs and the `benchmark_inbox_harness.dart` filters for it, but no production code emits it.

### Where to implement

The event should measure the time from inbox retrieve to message delivery (DB write) on the receiving side. The natural emission point is in the inbox drain path where retrieved messages are processed:

- [ ] **Identify emission site:** `lib/core/services/p2p_service_impl.dart` — `drainOfflineInbox()` or the listener that processes retrieved inbox messages
- [ ] **Add Stopwatch:** Start when `inbox:retrieve` returns messages, stop when each message is persisted to DB
- [ ] **Emit event:** `emitFlowEvent(layer: 'FL', event: 'INBOX_DELIVERY_TIMING', details: {'deliveryMs': ..., 'messageId': ...})`
- [ ] **Unit test:** Add a Phase 1 test (e.g., `test/performance/benchmark_inbox_delivery_timing_test.dart`) verifying the event is emitted with correct fields
- [ ] **Verify D-Sim-2:** Re-run `integration_test/benchmark_inbox_harness.dart` D-Sim-2 scenario and confirm `INBOX_DELIVERY_TIMING` events are now collected

### Existing harness coverage

| Test layer | Pre-wired? | Details |
|---|---|---|
| D-Sim-2 (benchmark) | **Yes** | `benchmark_inbox_harness.dart:108-109` already does `filterEvents(events, 'INBOX_DELIVERY_TIMING')` with `containsKey('deliveryMs')` — currently a no-op, will collect automatically once implemented |
| S3/S9 (two-sim smoke) | **No — gap** | Bob's harness (`routing_smoke_bob_harness.dart`) verifies message arrival in DB but does NOT filter for `INBOX_DELIVERY_TIMING` |

- [ ] **Smoke gap:** Add `INBOX_DELIVERY_TIMING` capture to Bob's receive path in `routing_smoke_bob_harness.dart` for S3 (offline → inbox) and S9 (batch inbox) scenarios

### Traceability: doc updates after implementation

| Document | Location | Current state | Update |
|---|---|---|---|
| `03.md` | Section 1, Dart events table | `INBOX_DELIVERY_TIMING` row says "**not yet implemented** — see `03j`" | Remove the caveat, make it a normal row |
| `03.md` | Section 1, Measured Baseline table | No entry for inbox e2e delivery | Add row: `Inbox E2E Delivery \| p50=Xms \| D-Sim` with real numbers from re-run |
| `03f` | D-Sim-2, Events/Fields column | Says "(**not yet implemented**... see `03j`)" | Remove the caveat |
| `03f` | Baseline Table Mapping, "Inbox E2E Delivery" row | Says "(**blocked**: ... see `03j`)" | Remove the caveat, fill in real numbers |

---

## 2. Forward Go sub-step fields into `CHAT_MSG_SEND_TIMING`

**Status:** Not implemented
**Documented in:** `03.md` Section 1 (claimed `streamOpenMs`, `writeMs`, `ackWaitMs` as sub-steps), `03f` Test A
**Current state:** These fields exist on separate Go-pushed events (`inbox:store_timing` has `streamOpenMs`/`writeMs`; `message:direct_ack_timing` has `waitMs`/`ackWriteMs`) but are NOT forwarded into the Dart `CHAT_MSG_SEND_TIMING` event

### What's missing

The Dart send use case emits `CHAT_MSG_SEND_TIMING` with `discoverMs`, `dialMs`, `sendMs`, `encryptMs` — all measured on the Dart side. The Go bridge response from `sendMessageWithReply` may include additional sub-step timing fields, but the Dart code does not extract and forward them.

### Where to implement

- [ ] **Check Go bridge response:** Verify whether `SendMessage` / `SendMessageWithTransport` response includes `streamOpenMs`, `writeMs`, `ackWaitMs` fields
- [ ] **If present:** In `send_chat_message_use_case.dart`, extract these fields from the bridge response map and include them in the `CHAT_MSG_SEND_TIMING` event details
- [ ] **If not present in response:** Add them to the Go-side `SendMessage` response in `go-mknoon/node/node.go` (measure stream open, write, and ACK wait durations during send)
- [ ] **Update Test A:** Extend `test/performance/benchmark_1_1_send_test.dart` to verify the new sub-step fields are present
- [ ] **Update A-Sim:** Extend `integration_test/benchmark_1_1_send_harness.dart` to print the sub-step breakdown

### Existing harness coverage

| Test layer | Pre-wired? | Details |
|---|---|---|
| A-Sim-1 (benchmark) | **Yes** | `benchmark_1_1_send_harness.dart:102` already iterates `['discoverMs', 'dialMs', 'sendMs', 'encryptMs', 'streamOpenMs', 'writeMs', 'ackWaitMs']` with `containsKey` guards. Lines 123-132 print dedicated `[BENCHMARK]` lines for each. Zero harness changes needed. |
| S1-S8 (two-sim smoke) | **Partially** | Alice's harness captures `CHAT_MSG_SEND_TIMING` details maps — new fields will land in the map. But the harness only prints `elapsedMs`, `sendPath`, `outcome`, `connectionReused`. Sub-steps are captured but not reported. |

- [ ] **Optional smoke enhancement:** Add sub-step printing to Alice's send helper in `routing_smoke_alice_harness.dart` (low priority — A-Sim-1 already covers it)

### Traceability: doc updates after implementation

| Document | Location | Current state | Update |
|---|---|---|---|
| `03.md` | Section 1, Dart events table, `CHAT_MSG_SEND_TIMING` row | Sub-steps: `discoverMs`, `dialMs`, `sendMs`, `encryptMs` | Add back: `streamOpenMs`, `writeMs`, `ackWaitMs` |
| `03.md` | Path A diagram | No measured values for these sub-steps | Add measured values from A-Sim re-run |
| `03f` | Test A, sub-step note | Says "Note: `streamOpenMs`, `writeMs`, `ackWaitMs` are **not** fields... see `03j`" | Remove the note, restore them to the sub-step list |
| `03f` | A-Sim-1 baseline output | Lists `sim_1_1_stream_open_ms` etc. as outputs (already scaffolded) | Fill in real numbers from re-run |

---

## 3. Add `relayWarmMs` to `node:startup_timing` event

**Status:** Not implemented (field documented but never emitted)
**Documented in:** `03.md` Section 1 (Go events table — now corrected to show actual fields)

### What's missing

The `node:startup_timing` event has two phases:
- `host_ready`: emits `libp2pNewMs`, `pubsubInitMs`
- `discoverable`: emits `circuitAddressMs`, `circuitAddressOutcome`, `rendezvousRegisterMs`, `totalToDiscoverableMs`

Relay warm duration is captured separately via `relay:warm_timing` per relay, but there is no aggregate `relayWarmMs` rolled into `node:startup_timing`.

### Where to implement

- [ ] **In `go-mknoon/node/node.go`:** After all relay warm goroutines complete (when `relayReady` channel closes), compute aggregate `relayWarmMs = time.Since(relayWarmStart)`
- [ ] **Emit additional phase:** `n.emitEvent("node:startup_timing", map[string]interface{}{"phase": "relay_warm_done", "relayWarmMs": relayWarmMs})`
- [ ] **Update B-Go test:** Verify `benchmark_startup_test.go` checks for the new phase
- [ ] **Update B-Sim:** Extend `integration_test/benchmark_node_startup_harness.dart` to collect and print `relayWarmMs`

### Existing harness coverage

| Test layer | Pre-wired? | Details |
|---|---|---|
| B-Sim-1 (benchmark) | **Yes** | `benchmark_node_startup_harness.dart:69` already does `if (d.containsKey('relayWarmMs'))` and prints `sim_startup_relay_warm_ms`. Waiting for the field to exist. |
| Two-sim smoke | **N/A** | Smoke tests don't capture `node:startup_timing`. Startup timing is a single-node concern — no smoke gap. |

### Traceability: doc updates after implementation

| Document | Location | Current state | Update |
|---|---|---|---|
| `03.md` | Section 1, Go events table, `node:startup_timing` row | Shows `host_ready` and `discoverable` phases | Add `relay_warm_done` phase with `relayWarmMs` |
| `03.md` | Path B diagram | Says "warmRelayConnection ... 200-800 ms typical" referencing `relay:warm_timing` | Add measured aggregate `relayWarmMs` from B-Sim re-run |
| `03f` | B-Sim-1 baseline output | Lists `sim_startup_relay_warm_ms` (already scaffolded, `containsKey` guard) | Fill in real number from re-run |

---

## 4. Wire `InteractiveInboxTimeout` into 1:1 send-path inbox fallback

**Status:** Not wired (architectural observation from `03.md` Section 4)
**Documented in:** `03.md` Section 4 ("Inbox Store Fallback Uses Default 15s Timeout"), `03f` "Where They Diverge" table (now corrected)

### What's missing

The 1:1 inbox-store fallback in `send_chat_message_use_case.dart` calls `callP2PInboxStore` without passing a `timeoutMs` parameter. This defaults to Go's `InboxTimeout = 15s`. The `InteractiveInboxTimeout = 3s` constant exists in Go config but is only available to retrieve/ack call sites that pass explicit timeouts.

### Decision needed

- [ ] **Evaluate risk:** Inbox store measured at 104ms warm (D-Sim). The 15s ceiling rarely matters, but a 3s cap would make the interactive path more predictable
- [ ] **If yes:** Pass `timeoutMs: 3000` (or a Dart constant) to `callP2PInboxStore` in the send use case
- [ ] **If no:** Document the deliberate choice in `03.md` Section 4 as "accepted risk"

### Existing harness coverage

| Test layer | Pre-wired? | Details |
|---|---|---|
| All (behavioral) | **Yes** | This changes a timeout value, not an event. Existing inbox-path tests (S3, S9, R-Sim-4) will observe faster timeout behavior. No new collection needed. |

### Traceability: doc updates after implementation

**If wired (3s):**

| Document | Location | Current state | Update |
|---|---|---|---|
| `03.md` | Section 4, "Inbox Store Fallback Uses Default 15s Timeout" | Describes the 15s default as an architectural observation | Rewrite to reflect the new 3s cap; remove the observation |
| `03.md` | Section 3, Dart Constants table, `callP2PInboxStore` row | Says 15s | Change to 3s |
| `03f` | "Where They Diverge" table, Timeout budget row | Says "15s inbox (Go `InboxTimeout` default; `InteractiveInboxTimeout` 3s exists but is not wired...)" | Change to "3s inbox" |

**If deliberately kept at 15s:**

| Document | Location | Update |
|---|---|---|
| `03.md` | Section 4 | Change "architectural observation" to "accepted: 15s ceiling is intentional because..." |

---

## Verification

After implementing items 1-3, re-run the following to confirm:

```bash
# Phase 1 unit tests
flutter test test/performance/

# Go unit tests
cd go-mknoon && go test ./node/ -run Benchmark -v

# Phase 4 simulator (inbox harness)
flutter test integration_test/benchmark_inbox_harness.dart -d <DEVICE_ID>

# Phase 5 two-sim smoke (verifies Item 1 smoke gap fix)
dart run integration_test/scripts/run_routing_smoke_e2e.dart \
  -d <DEVICE_1>,<DEVICE_2>
```

After all pass, apply the doc updates from each item's traceability table, then remove the `03j` caveats from `03.md` and `03f`.
