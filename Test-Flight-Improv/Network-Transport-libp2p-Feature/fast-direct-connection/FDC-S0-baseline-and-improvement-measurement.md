# FDC-S0 - Baseline + improvement measurement  (Measurement bookend — run FIRST, re-run at END)

Status: open
Position: runs in **Wave 0 (BASELINE, before FDC-01)** AND **at epic close / per-wave (AFTER)**.
Gates nothing; it **measures** the epic. Reuses **FDC-S1** (cold-start time-to-online) and **FDC-S6**
(libp2p-LAN win-rate soak) outputs rather than duplicating them.
Spec: `Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md` §3 (the cascade), §4 / §4.1
(root causes + the online→inbox mis-route), §6 (goals), §8 (the recommendation table this scorecard
ties each metric to). Roadmap: `FDC-00-roadmap.md` (the "capture green host-gate baseline" tip,
the closure strategy, the recommendation→plan map). **Scope: 1:1 messaging only.**

---

## Why (you cannot claim an improvement without a before+after on the same metric)

The proposal makes strong quantitative promises — "delete the decision window," cut the *worst
perceived path ≈ race(2s) + probe(5s) + dial(2s) + send(2s) + inbox(3s)" (§3), the **~24s** measured
offline trace (§3, `UI-14-Conn-Type/online-inbox.md`), and a *correctness* fix for the online→inbox
mis-route (§4.1). The FDC epic is 6 spikes + 16 plans across 4 phases. **None of that is creditable
unless the same metric is captured on the same vehicle before code lands and again at the end.** Two
failure modes this doc exists to prevent:

1. **Unfalsifiable wins.** A plan lands, the 1:1 gate stays green, and we *assert* "faster" with no
   number. Host-green proves *delivery*, not *the fast path* — the `messageId` dedup means a test can
   pass via the inbox copy even if the live/LAN/direct leg never fired (proposal §9.1; `FDC-00`
   Closure caveat). A scorecard with a transport-label distribution and a wall-clock delta is the
   only honest claim.
2. **Moving the baseline.** If the baseline is captured *after* FDC-01 lands (or on a different
   branch), the delta is meaningless. The baseline MUST be captured on the current `new-orbit` tree
   **before FDC-01**, frozen, and referenced by every after-measurement.

This doc defines **what** to measure (the metric catalog), **how** (existing vehicle + `file:line`),
**when** (Wave-0 baseline + per-wave/at-close after), and produces the **delta scorecard** that is
the epic's closing artifact. It is deliberately honest about which metrics are host-measurable (the
mechanism) vs device-only (the real-network wall-clock UX).

---

## Metric catalog

One row per metric. "Vehicle" cites the EXISTING measurement primitive (verified `file:line`) — no
new instrumentation is invented here; where a metric needs a *tiny* aggregation/sink, the
"What's reusable vs new" section flags it. Direction: ↓ = lower is better, ↑ = higher is better.

| # | Metric | Proves (goal / plan) | How measured (vehicle + file:line) | Baseline source | Host / Device | Target / direction |
|---|---|---|---|---|---|---|
| **1** | **Perceived 1:1 send latency** hit-send→delivered, **per scenario** [same-WiFi / both-online-diff-net / offline] | §3 cascade; §6.2 ranked race; **FDC-02**, **FDC-01**, **FDC-04** | Per-send per-step Go timings `streamOpenMs`/`writeMs`/`ackWaitMs` (`send_message_result.dart:7-9`, read from the Go bridge response at `p2p_service_impl.dart:1993-2013`, emitted as flow-event details at `send_chat_message_use_case.dart:469-472`, `1423-1426`, `1514-1518`) + end-to-end `TransportMetrics.recordSendLatency`/`latencyByTransport()` median+p95 (`transport_metrics.dart:190`, `:243`), bucketed by transport so each scenario reads its own road | proposal §3 worst-path compound; `online-inbox.md` ~24s offline | **Device** (real wall-clock UX); host benchmarks (#1b below) cover the *mechanism* only | ↓ |
| **1b** | **Send mechanism** latency (host) — stream-open + write + ack, and connection-reuse fast-path | §3; §6.1 warm reuse `:447-465`; **FDC-02/04** | Go `TestBenchmark_SendMessage_EmitsPerStepTiming` + `_ConnectionReuse` (`go-mknoon/node/benchmark_send_test.go:8`, `:69`), `TestBenchmark_DirectAck_FastConfirm`/`_MultipleMessages` (`benchmark_ack_test.go:8`, `:66`) — log `BENCHMARK … = Nms` lines | the same benchmarks on `new-orbit` HEAD | **Host** (mechanism, not UX) | ↓ |
| **2** | **Notif-tap → first live message** time (the headline pain) | §4 R6, §6.4; **FDC-05**, **FDC-04**; the 145 notif-tap work | `NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING` flow-event `elapsedMs`/`milestone:live_render` (`notification_tap_timing.dart:43-63`, esp. `:52`/`:57`) + its stale-render twin `NOTIFICATION_TAP_TO_MESSAGE_TIMING` (`:9-31`); drain segments `retrieveMs`/`replayMs` (`p2p_service_impl.dart:1481-1483`, emitted `:1806-1810`) | 145 baseline (memory: project 145/146/147) | **Device** primary (real push + relay); host gives the drain-segment decomposition | ↓ |
| **3** | **Online→inbox MIS-ROUTE rate** — % of sends to an *online* peer that fell to the offline inbox | §4.1 correctness bug; **FDC-01** (target: → 0) | Deterministic host proof = FDC-01's RED catalog (a slow-discover online peer must NOT land `transport:'inbox'`); fleet rate = persisted `transport` column `'inbox'` deliveries (`migrations/012_transport_column.dart:28`) cross-checked against a later live ack for the same `messageId` (dup ⇒ peer was reachable ⇒ mis-route). **No dedicated counter today** — see "needs a small aggregation" | proposal §4.1 (verified-against-source bug; current rate > 0 for slow-online peers) | **Host** (FDC-01 deterministic test) for the fix; **Device** for the fleet rate | ↓ → 0 |
| **4** | **Transport DISTRIBUTION** — % `local`/`wifi` · `direct` · `relay` · `inbox` (fast-path adoption) | §6.1/§6.2 LAN-first & ranked race; **FDC-02**, **FDC-04**, **FDC-11** | `TransportMetrics.transportMix()` over `kTransportBuckets` (`transport_metrics.dart:226`, `:4-10`), fed by `recordTransport` at the receive/deliver sites (`p2p_service_impl.dart:298`, `:328`, `:358`, `:3269`) + the **persisted** `transport` TEXT column (`012_transport_column.dart:28`) aggregated across sends; surfaced in `settings_transport_diagnostics_card.dart` and `TransportMetrics.baselineReport()` (`:292`). Go-side label = `classifyStreamTransport` direct/relay (`node.go:123-136`, used `:1411`,`:1619`) | proposal §3/§4 (relay-first; LAN advantage "routinely missed") | **Host** for the in-session counts; **Device** for the real same-WiFi/cross-net split (sim mDNS off) | ↑ direct/local share, ↓ inbox/relay share |
| **5** | **Cold-start time-to-online** (process-start → node-ready / first circuit / first mDNS resolve) | §6.4 lifecycle, §11 Q3; **FDC-07** (gated S1) | **REUSE FDC-S1** — do NOT duplicate. FDC-S1 lands the epoch-anchored `FDC_COLDSTART_*_TIMING` flow-events + the `node:startup_timing` family (`node.go:417-421`, `:919/931`, `:1697/1707`) and reports median+p90 per device-class (`FDC-S1` Method 1–6, Expected-Output `T_nodeStart`/`T_circuit`/`T_mdns`) | FDC-S1 baseline table | **Device** (S1 is device-run for mDNS); host for the Go startup benchmark `TestBenchmark_NodeStart_EmitsStartupTiming` (`benchmark_startup_test.go:8`) | ↓ |
| **6** | **libp2p-LAN win-rate** same-WiFi (and WS-LAN win-rate baseline) | §6.5 unify LAN-direct; **FDC-11**, **FDC-S6** | **REUSE FDC-S6** — do NOT duplicate. FDC-S6's soak reads the SAME transport labels (`'direct'` non-circuit vs `'wifi'`/`'local'` vs `'relay'`/`'inbox'`) via `transportMix()` and the `node:lan_peer_found`→`EvtPeerIdentificationCompleted`→label trace; headline = `count(direct,non-circuit,same-WiFi)/count(all same-WiFi)` over ≥14 d on both OS | FDC-S6 baseline window (`EnableLibp2pLanDial=false`, WS-only) | **Device-only** (sim shares host mDNS → `DISABLE_LOCAL_DISCOVERY`, `e2e_test_mode.dart:2`) | ↑ |
| **7** | **Resume / network-change reconnect** time | §6.4 lifecycle; **FDC-05**, **FDC-07** | Resume step durations `healthMs`/`reinitMs`/`hcMs`/`drainMs` already computed in `handle_app_resumed.dart:137-191` (currently `debugPrint` only — needs flow-event conversion, see "needs a small aggregation"; FDC-S1 Method 6 converts them to `FDC_RESUME_STEP_TIMING`) | proposal §3/§4 R5 (serial awaited resume) | **Device** (real WiFi↔cellular switch); host for the serial-vs-parallel structure | ↓ |
| **8** | **Reaction-to-offline delivery reliability** | reactions gap; **FDC-18** (mirrors FDC-03 concurrent inbox onto `send_reaction_use_case.dart`) | FDC-18's reaction round-trip RED tests (a reaction to a slow/offline peer must be durably inbox-queued, online peer not demoted to inbox-only); same `transport` bucketing applies | reactions currently inherit none of FDC-01/03's orchestration (roadmap "1:1 reactions SEPARATE path") | **Host** (deterministic round-trip); **Device** smoke for the live leg | ↑ (no dropped/late reactions) |
| **9** | **Inbox durability survives relay restart** (the failover test) — pass/fail | durability guarantee; **FDC-10** (Redis) | `go-relay-server` Go test: a stored message survives a relay bounce when the backend is Redis vs is wiped on the in-memory default; store dedup already exists (`backend_memory.go:121-142`, `backend_redis.go:272-295`, `inbox_store.go:7,14`) — FDC-10 adds the durability + a failover test. Run `cd go-relay-server && go test ./...` | proposal §10 / `FDC-00` durability-ordering hazard (in-mem wiped on bounce) | **Host** (Go failover test) + a **live-relay-env** closure | pass (survives) |
| **10** | **Host-gate regression floor** — `1to1` / `feed` / `transport` test counts | the regression contract; ALL plans | `./scripts/run_test_gates.sh 1to1` (`ONE_TO_ONE_TESTS` `run_test_gates.sh:17-72`), `feed` (`FEED_TESTS` `:74-110`), `transport` (`TRANSPORT_TESTS` `:164-169`) — capture pass-count + 0-fail | this doc's Wave-0 capture (the `FDC-00` tip: fills the plans' `expected: TODO`) | **Host** | = or ↑ count, 0 fail |

**Coverage note:** metrics 1–4 are the headline send-path wins (Phase 0, FDC-01/02/03/04); 5 + 7 are
lifecycle (FDC-05/07, gated S1); 6 is the LAN end-state (FDC-11/S6, device-only); 8 is reactions
(FDC-18); 9 is durability (FDC-10); 10 is the always-on regression floor. Every Phase-0 plan has at
least one host-measurable row; every device-only win (1, 6) is explicitly flagged and paired with a
host-measurable mechanism proxy (1b, 4).

---

## Baseline capture procedure (run on current `new-orbit`, BEFORE FDC-01)

Freeze a baseline commit hash; record it at the top of the scorecard. Do every capture below against
that tree. **No production edits** — these are all read-only runs of existing vehicles, except the
two tiny aggregations flagged in their own section (those land WITH FDC-S1, additive/observation-only).

**A. Go mechanism benchmarks (host, now — no device needed).**
```
cd go-mknoon && go test ./node/ -run TestBenchmark -v 2>&1 | grep BENCHMARK
```
Records (read the `BENCHMARK … = Nms` log lines): startup host-ready
(`benchmark_startup_test.go:8`,`:131`), send per-step + reuse (`benchmark_send_test.go:8`,`:69`),
direct-ack confirm (`benchmark_ack_test.go:8`,`:66`), inbox store/retrieve
(`benchmark_inbox_test.go:7`,`:40`), relay warm/recovery (`benchmark_relay_recovery_test.go:7`,`:33`),
timeout accuracy (`benchmark_timeout_accuracy_test.go:8`,`:28`,`:55`). These are the **metric-1b /
metric-9-adjacent** mechanism numbers; capture median of ≥5 runs (cold-start is heavy-tailed).

**B. Host-gate regression floor (host, now — metric 10).**
```
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh transport
```
Record pass-count + 0-fail for each. (Prior 1:1 runs were ~1226 per MEMORY; capture the real green
count to fill the plans' `expected: TODO`.) This is the `FDC-00` host-gate baseline tip, executed.

**C. Transport distribution + send-latency snapshot (device, per scenario — metrics 1, 4).**
Run a real 1:1 pair through each scenario ≥20 sends: **(i) same-WiFi**, **(ii) both-online
different-network**, **(iii) recipient offline**. Read `TransportMetrics.baselineReport()`
(`transport_metrics.dart:292`) from the debug `settings_transport_diagnostics_card`, OR aggregate the
persisted `transport` column directly:
```
SELECT transport, COUNT(*) FROM messages GROUP BY transport;   -- migration 012 column
```
Capture `transportMix()` percentages + `latencyByTransport()` median/p95 per scenario.

**D. Notif-tap → live-message (device — metric 2).** Force-quit recipient, push from sender, tap the
notification ≥10 trials. Capture `NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING.elapsedMs` (and the
`stale_render` twin) from the flow-event sink; report median + p90. (Reuse the 145 capture harness.)

**E. Online→inbox mis-route (host + device — metric 3).** Host: FDC-01's RED test on the baseline tree
*fails* (the bug is present) — that failing test IS the baseline proof the mis-route exists. Device:
count `transport:'inbox'` deliveries to a peer that was demonstrably online (later live-ack dup on the
same `messageId`).

**F. Cold-start (device — metric 5): REUSE FDC-S1.** Do not re-run here; cite FDC-S1's baseline table
(`T_nodeStart`/`T_circuit`/`T_mdns` median+p90 per device-class).

**G. LAN win-rate (device — metric 6): REUSE FDC-S6.** The baseline is FDC-S6's `EnableLibp2pLanDial=false`
WS-only window. Do not re-run here.

**H. Resume / network-change (device — metric 7).** Foreground after background + WiFi↔cellular switch,
≥10 trials; capture the `handle_app_resumed.dart:137-191` step durations (via the FDC-S1 Method-6
`FDC_RESUME_STEP_TIMING` conversion).

**I. Durability failover (host — metric 9).** `cd go-relay-server && go test ./...` baseline: confirm
the in-memory default loses queued messages on restart (the FDC-10 failover test, RED on baseline).

Record every number into the **delta scorecard** "Before" column with the frozen baseline commit hash.

---

## After / re-measure procedure (per wave + at epic close)

Use the **same vehicle, same scenario, same device-class** as the matching baseline row — only the
tree changes. Re-measure cadence:

- **Per-wave (incremental signal):** after each Phase-0 plan lands and re-greens `1to1`, re-run the
  cheap host captures (A, B) and the deterministic host proofs (E-host FDC-01, metric 8 FDC-18,
  metric 9 FDC-10) so a regression is caught at the plan boundary, not at close.
- **Per-phase (device):** after Phase 0 completes (FDC-04), run the **device** captures C, D, H on the
  same real pair + device-class as baseline — this is the MVP-cut "do not proceed on host-green alone"
  device smoke (`FDC-00` MVP cut).
- **At epic close (full):** re-run ALL of A–I, plus pull FDC-S1 (5) and FDC-S6 (6) final numbers, and
  populate the full "After" column of the scorecard.

**Apples-to-apples rules:** same scenario set (same-WiFi / diff-net / offline), same ≥N trials, same
device-class pairing, report median+p90/p95 (never mean — heavy-tailed), and for every device latency
row read the **transport label of the winning leg**, not merely "did it deliver" (the dedup
false-positive guard, proposal §9.1).

---

## Delta scorecard template (the closing artifact)

Frozen baseline commit: `__________`  ·  Close commit: `__________`  ·  Date: `__________`

| # | Metric | Proposal/baseline reference | Before | After | Δ | Plan(s) credited | Verdict |
|---|---|---|---|---|---|---|---|
| 1 | Perceived send latency — same-WiFi (med/p95) | §3 cascade | | | | FDC-02/04/11 | |
| 1 | Perceived send latency — both-online diff-net | §3 cascade; 2s race window | | | | FDC-02/01 | |
| 1 | Perceived send latency — offline | §3 ~24s offline trace | | | | FDC-03/01 | |
| 1b | Send mechanism (host benchmark) | new-orbit HEAD benchmarks | | | | FDC-02/04 | |
| 2 | Notif-tap → live message (med/p90) | §4 R6; 145 baseline | | | | FDC-05/04 | |
| 3 | Online→inbox mis-route rate | §4.1 (>0 baseline) | | | → 0 | FDC-01 | |
| 4 | Transport distribution (local/direct/relay/inbox %) | §3/§4 relay-first | | | | FDC-02/04/11 | |
| 5 | Cold-start time-to-online (REUSE S1) | FDC-S1 table | | | | FDC-07 | |
| 6 | libp2p-LAN win-rate same-WiFi (REUSE S6) | FDC-S6 soak | | | | FDC-11 | |
| 7 | Resume / network-change reconnect | §3/§4 R5 (serial) | | | | FDC-05/07 | |
| 8 | Reaction-to-offline reliability | reactions gap | | | | FDC-18 | |
| 9 | Inbox durability survives relay restart | §10 / durability hazard | fail (in-mem) | | | FDC-10 | pass? |
| 10 | Host-gate floor 1to1 / feed / transport | this doc Wave-0 capture | | | | ALL | 0-fail |

The reference column anchors every "Before" to the proposal's own stated baseline (the cascade, ~24s
offline, the 2s+5s serial windows, relay-first distribution) so the delta is reconciled against the
design's claims, not just against an arbitrary measurement.

---

## What's reusable vs new

**Already exists — reuse as-is (zero new code):**
- `emitFlowEvent` spine (`flow_event_emitter.dart:202`) and the `NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING`
  / stale-render events (`notification_tap_timing.dart:43-63`, `:9-31`) — metric 2.
- Per-send Go step timings `streamOpenMs`/`writeMs`/`ackWaitMs` (`send_message_result.dart:7-9`,
  emitted at `send_chat_message_use_case.dart:469-472` etc.) and drain `retrieveMs`/`replayMs`
  (`p2p_service_impl.dart:1481-1483`, `:1806-1810`) — metrics 1, 2.
- `TransportMetrics` aggregator + `baselineReport()` + `latencyByTransport()` + `transportMix()`
  (`transport_metrics.dart:87`, `:292`, `:243`, `:226`) and the persisted `transport` TEXT column
  (`012_transport_column.dart:28`) + `settings_transport_diagnostics_card` debug surface + the Go
  `classifyStreamTransport` label (`node.go:123-136`) — metrics 1, 3, 4, 6.
- The 10 Go `TestBenchmark_*` families (`go-mknoon/node/benchmark_*_test.go`) — metric 1b + mechanism.
- The host-gate arrays (`run_test_gates.sh:17/74/164`) — metric 10.
- **FDC-S1** cold-start tables — metric 5 (do not duplicate; cite). **FDC-S6** LAN soak — metric 6
  (do not duplicate; cite). This doc's metric rows 5 & 6 are pure REUSE pointers.

**Needs a small additive aggregation/sink (additive, observation-only — note the 145 telemetry is
`kDebugMode`-gated, `flow_event_emitter.dart:6` `flowEventLoggingEnabled = kDebugMode`):**
- **Metric 3 (mis-route rate)** has **no dedicated counter** today. The deterministic host proof is
  FDC-01's RED test (sufficient for the fix); a *fleet rate* needs either a one-line flow-event at the
  `direct_timeout`→inbox decision in `send_chat_message_use_case.dart`, or post-hoc reconciliation of
  `transport:'inbox'` rows against later live-ack dups. Small; land it with FDC-01's instrumentation
  if a fleet number is wanted (else rely on the deterministic test).
- **Metric 7 (resume)**: `handle_app_resumed.dart:137-191` already *computes* `healthMs`/`reinitMs`/
  `hcMs`/`drainMs` but only `debugPrint`s them — FDC-S1 Method 6 already plans the `FDC_RESUME_STEP_TIMING`
  flow-event conversion; reuse that, don't author a second one.
- **Sink for release builds:** all flow-events are `kDebugMode`-gated, so the device captures (2, 3,
  7) run on a **debug/profile build with the flow-event sink attached** (`debugSetFlowEventSink`,
  `flow_event_emitter.dart:38`), or via the existing debug diagnostics card. No new persistent telemetry
  pipeline is required for the spike — only a capture harness around the existing sink.

**No new measurement primitive is needed for the headline distribution/win-rate metrics** — the
transport labels, the persisted column, and the aggregator are all already live.

---

## Honesty / limits

- **Perceived-latency (metric 1) and LAN-win (metric 6) are DEVICE-ONLY, real-network.** A host fake
  cannot reproduce mDNS, real RTT, iOS multicast/background, or relay wire latency. Sim mDNS is
  host-shared and forced off (`DISABLE_LOCAL_DISCOVERY`, `e2e_test_mode.dart:2`; proposal §6.5).
- **Host benchmarks measure the MECHANISM, not the wall-clock UX.** Metric 1b's `streamOpenMs`/`ackWaitMs`
  are real numbers for the Go send path but exclude OS scheduling, Flutter frame cost, real radio
  latency, and the bridge serialization the user actually feels. They bound *what's possible*, not
  *what's perceived*.
- **Host-fake "live-wins" has the dedup false-positive caveat.** Because the receiver dedupes by
  `messageId` (proposal §10 L397-398), a green *delivery* can be satisfied by the inbox copy even if
  the live/LAN/direct leg never fired (proposal §9.1; `FDC-00` Closure caveat). Every fast-path
  metric (1, 4, 6) must read the **transport label of the committing leg**, never "did it deliver."
- **Cross-sender clock skew.** Notif-tap (metric 2) and any cross-device latency span two device
  clocks; `elapsedMs` from a single `tappedAt`→now on ONE device is safe, but any sender-timestamp vs
  receiver-timestamp delta is skew-contaminated — anchor each metric to a single-device monotonic span
  (as `notification_tap_timing.dart` already does) and never subtract two devices' wall clocks. Same
  caveat FDC-S1 carries for Dart↔Go.
- **`TransportMetrics` is in-memory + session-scoped** (`transport_metrics.dart:81-87`) — a relaunch
  resets it. For a fleet/soak number aggregate the **persisted** `transport` column (012), not the
  in-session counters, or capture per-session and sum externally.
- **Metric 3's fleet rate is approximate** without the small aggregation above; the *correctness* claim
  rests on FDC-01's deterministic RED→GREEN, which is exact.
- **Cold-start (5) is heavy-tailed** — report median+p90, never mean (FDC-S1's own rule).

---

## Exit gate

FDC-S0 is **done** when:
1. The **Wave-0 baseline** column of the delta scorecard is fully populated against a frozen
   `new-orbit` commit hash (host metrics 1b/9/10 + device metrics 1/2/4 + FDC-S1 #5 + FDC-S6 #6
   references), captured BEFORE FDC-01 lands.
2. The host-gate floor counts (metric 10: `1to1`/`feed`/`transport`) are recorded and back-filled into
   the plans' `expected: TODO` slots (the `FDC-00` host-gate baseline tip closed).
3. At epic close, the **After** column is populated via the same vehicles/scenarios, and a
   per-metric **Δ + verdict** is written — including an explicit "device-only, deferred-not-waived" mark
   for any metric (1 same-WiFi, 6) whose device-proof the available hardware/relay env could not capture.
4. Every metric in the scorecard ties to the plan(s) it credits (the "Plan(s) credited" column),
   so the epic's claimed improvement is reconciled, row by row, against the proposal §3/§4 baseline.
