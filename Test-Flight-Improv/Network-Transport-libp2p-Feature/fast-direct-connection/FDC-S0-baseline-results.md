# FDC-S0 — Wave-0 BASELINE results (the populated delta scorecard)

> Companion to `FDC-S0-baseline-and-improvement-measurement.md` (the spec/template). This file is the
> **executed Wave-0 baseline**: every host-measurable metric captured against a frozen `new-orbit`
> commit **before FDC-01**, every device-only metric marked *deferred-not-waived* with its reuse
> pointer, and every metric tied to the plan(s) it credits. The **After** column is intentionally
> empty — it is populated at epic close (and per-wave for the cheap host rows) per the spec's
> "After / re-measure procedure".

---

## Freeze

| Field | Value |
|---|---|
| **Frozen baseline commit** | `17a32bef7ea454340c728b89b95bf8db3232e0df` (`new-orbit`, "design-v1") |
| **Captured** | 2026-06-26, **before FDC-01 lands** (Wave 0) |
| **Flutter toolchain** | 3.41.4 stable (`ff37bef603`), Dart bundled |
| **Go toolchain (used for capture)** | **go1.25.0** (the `go.mod`-declared toolchain) — see toolchain caveat below |
| **Working-tree state at freeze** | NOT clean. Uncommitted edits: `go-mknoon/Makefile`, `go-mknoon/node/{benchmark_crypto_test.go,config.go,holepunch_tracer_test.go,transport_label_test.go}`, `go-relay-server/Makefile`, `graphify-arch/*` (graph meta only). Untracked: the FDC docs + `s0-baseline-raw/`. **None of these touch the app send-path or relay production code**; the `go-mknoon/node` edits compile and run clean (the node tests reach the QUIC handshake before the toolchain panic, and under go1.25.0 all node/bridge tests pass — see metric 1b / 10). The baseline is therefore representative of pre-FDC-01 behavior. |
| **Raw capture logs** | `s0-baseline-raw/` (this directory) — every run's full stdout, re-readable. |

**Toolchain caveat (load-bearing — read before trusting the Go numbers).** The local default Go is
**1.26.4**; `go.mod` declares `go 1.25.0` with `GOTOOLCHAIN=auto` (so `auto` runs the *newer local*
1.26.4). Under **Go 1.26.4**, the libp2p QUIC tests (`node` + `bridge` packages, and every
`TestBenchmark_*` that starts a real node) **panic**: `panic: crypto/tls bug: where's my session
ticket?` at `quic-go@v0.49.0/internal/handshake/crypto_setup.go:366` — a known
**toolchain-ahead-of-dependency** break (Go 1.26's `crypto/tls` session-ticket change vs quic-go
v0.49.0, which predates the fix). This is **not** a code regression and **not** caused by the
uncommitted edits. The baseline is captured on the **declared** toolchain `GOTOOLCHAIN=go1.25.0`,
which quic-go v0.49.0 supports — the honest, ship-representative mechanism baseline. Raw evidence of
the 1.26.4 panic is preserved in `s0-baseline-raw/go_benchmarks.log` and `go_mknoon_fulltest.log`;
the clean 1.25.0 capture is in `go_benchmarks_125.log` / `go_mknoon_fulltest_125.log`.

---

## Executive summary of the baseline

- **The Go send/ack/startup MECHANISM is sub-millisecond on loopback** (metric 1b): `startup_host_ready
  ≈ 1ms`, `direct_send p50/p95 = 0ms`, `relay_warm = 0ms`, `mlkem_keygen p50/p95 = 0ms`. **This is the
  most important baseline finding**: the multi-second / ~24s perceived paths the proposal targets (§3)
  are **orchestration overhead** (decision windows, serial cascade, relay RTT, bridge/Flutter framing),
  **not** the Go transport mechanism. FDC-01..04 attack exactly that orchestration layer; 1b is the
  floor proving the mechanism itself has the headroom.
- **Host-gate floor is green** (metric 10): `1to1` **1226**/0-fail, `feed` **279**/0-fail, `groups`
  **896**/0-fail, `core-host-all` **249/249 files**/0-fail, `baseline` **112** host (pure host).
  `go-relay-server` `./...` **191** pass / 0 fail / 2 skip; `go-mknoon` `./...` all 6 pkgs PASS / 0 fail
  (go1.25.0). `transport` + `baseline`'s integration files are device/sim-gated (deferred-not-waived).
- **Durability (metric 9)** is at the expected baseline: the **Redis** cross-process-restart durability
  proof EXISTS and passes; the **in-memory-loses-on-restart** RED proof does **NOT** exist yet — every
  current in-memory "restart" test reuses the same backend object and asserts *survival*. FDC-10 must
  author the loss proof. Baseline verdict for the failover test = **fail (in-mem)**, as the template
  predicts.
- **Mis-route correctness (metric 3)** baseline proof = FDC-01's RED catalog (TC-01..04 verified to
  exist in the plan; RED-on-baseline because the fix has not landed).
- **All device-only wins (1, 2, 4-real-split, 5, 6, 7) are deferred-not-waived** with verified vehicles
  + reuse pointers (FDC-S1 #5/#7, FDC-S6 #6).
- **Vehicle-anchor honesty audit: PASS.** All cited `file:line` measurement vehicles verified real at
  (or within ±2 of) the cited lines; a handful of immaterial nuances recorded below.

---

## The delta scorecard (Before column populated)

Frozen baseline commit: `17a32bef` · Close commit: `__________` (at epic close) · Date: 2026-06-26

| # | Metric | Proposal/baseline reference | Before (baseline) | After | Δ | Plan(s) credited | Verdict |
|---|---|---|---|---|---|---|---|
| 1 | Perceived send latency — same-WiFi (med/p95) | §3 cascade | **device-deferred** (real mDNS/RTT; host proxy = 1b) | | | FDC-02/04/11 | deferred-not-waived |
| 1 | Perceived send latency — both-online diff-net | §3 cascade; 2s race window | **device-deferred** (real cross-net RTT) | | | FDC-02/01 | deferred-not-waived |
| 1 | Perceived send latency — offline | §3 ~24s offline trace | **device-deferred** (real relay wire) | | | FDC-03/01 | deferred-not-waived |
| 1b | Send mechanism (host benchmark, go1.25.0, med of 5) | new-orbit HEAD benchmarks | **host_ready≈1ms · direct_send p50/p95=0ms · relay_warm=0ms · send_unreachable=0ms (1000ms budget) · mlkem_keygen p50/p95=0ms** — 135 pass/0 fail/0 panic | | | FDC-02/04 | ✅ captured (loopback floor; bounds the possible, not the perceived) |
| 2 | Notif-tap → live message (med/p90) | §4 R6; 145 baseline | **device-deferred** (real push+relay); vehicle verified `notification_tap_timing.dart:43-63` | | | FDC-05/04 | deferred-not-waived |
| 3 | Online→inbox mis-route rate | §4.1 (>0 baseline) | **RED on baseline** — FDC-01 TC-01..04 (deterministic host proof present in plan; fix not landed ⇒ slow-online peer mis-routes to inbox today) | | → 0 | FDC-01 | ✅ baseline-RED established (host); fleet rate device-deferred (no counter today) |
| 4 | Transport distribution (local/direct/relay/inbox %) | §3/§4 relay-first | **device-deferred for the real split** (sim mDNS off); host vehicle verified (`transportMix()`, `classifyStreamTransport` node.go:123-136) | | | FDC-02/04/11 | deferred-not-waived |
| 5 | Cold-start time-to-online (REUSE S1) | FDC-S1 table | **device-deferred → REUSE FDC-S1** (S1 baseline table; verified S1 defines `T_nodeStart`/`T_circuit`/`T_mdns`) | | | FDC-07 | deferred-not-waived (S1-owned) |
| 6 | libp2p-LAN win-rate same-WiFi (REUSE S6) | FDC-S6 soak | **device-deferred → REUSE FDC-S6** (`EnableLibp2pLanDial=false` WS-only window; verified S6 reads same labels) | | | FDC-11 | deferred-not-waived (S6-owned) |
| 7 | Resume / network-change reconnect | §3/§4 R5 (serial) | **device-deferred**; step durations `healthMs/reinitMs/hcMs/drainMs` confirmed computed (debugPrint-only) `handle_app_resumed.dart:137-191`; FDC-S1 Method-6 converts to flow-event | | | FDC-05/07 | deferred-not-waived |
| 8 | Reaction-to-offline reliability | reactions gap | **RED on baseline** — FDC-18 reaction round-trip RED catalog (FDC-18-01..06b); `send_reaction_use_case.dart` exists, inherits no FDC-01/03 orchestration yet | | | FDC-18 | ✅ baseline state established (host, deterministic once authored) |
| 9 | Inbox durability survives relay restart | §10 / durability hazard | **fail (in-mem)** — Redis cross-process restart proof passes (`redis_failover_integration_test.go`); **no** in-mem loss-on-restart test exists (FDC-10 must author). go-relay `./...` = 191 pass/0 fail/2 skip | | | FDC-10 | ✅ fail-on-baseline confirmed (as predicted) |
| 10 | Host-gate floor 1to1 / feed / transport | this doc Wave-0 capture | **1to1 1226 · feed 279 · groups 896** (0 fail, host) · go-relay 191/0/2 · go-mknoon `./...` PASS (go1.25.0; 6 pkgs, 0 fail, ~1171 tests; node 434s, bridge 196s) · transport device/fixture-gated — suites SKIP on a lone sim (`background_reconnect` → "All tests skipped"); needs the 2-device+relay matrix (deferred-not-waived) · baseline 112 host (+2 integration device) · core-host-all **249/249 core files PASS, 0 fail** | | | ALL | ✅ host floor captured; device/sim gates noted |

---

## Per-metric baseline detail

### Metric 1b — send mechanism (HOST, captured) ✅
- **Vehicle:** `go-mknoon/node/benchmark_send_test.go:8`/`:69`, `benchmark_ack_test.go:8`/`:66`,
  `benchmark_startup_test.go:8` (all verified exact). Run: `go test ./node/ -run TestBenchmark -count=5 -v`.
- **Captured (median of 5, go1.25.0):** `startup_host_ready_ms = 1ms`; `direct_send_elapsed_ms = 0`,
  `direct_send_ms p50=0 p95=0 (n=10)`; `relay_warm_done relayWarmMs=0`; `send_unreachable_actual_ms =
  0ms` (timeout budget 1000ms — timeout accuracy is exact); `mlkem_keygen_go_ms p50=0 p95=0`.
  Tally: **135 pass / 0 fail / 0 panic**.
- **Honesty:** loopback host → sub-millisecond; these **bound what's possible**, not what's perceived
  (no OS scheduling, real radio RTT, bridge serialization, or relay wire). Per the spec's metric-1b
  caveat. Raw: `s0-baseline-raw/go_benchmarks_125.log`.

### Metric 9 — inbox durability survives relay restart (HOST, captured) ✅ fail-on-baseline
- **Vehicle:** `go-relay-server` `go test ./...` → **191 pass / 0 fail / 2 skip** (`ok …/relay-server
  13.952s`).
- **Durability state:** `redis_failover_integration_test.go` (`TestRedisControlPlaneSharedAcrossProcesses`,
  spawns separate processes over one miniredis, asserts push-tokens *survive process restart*) is a
  genuine cross-process durability proof for the **Redis** backend — PASS. `failover_test.go`'s
  `TestTwoRelayServers_Shared*` family boots two relay instances over **the same shared in-memory
  object** and asserts consistency — it does **NOT** restart a process / drop the map, so it does not
  prove in-memory loss. **No test demonstrates the in-memory default losing queued messages on
  restart** → the FDC-10 baseline RED proof is **absent and must be authored by FDC-10**. Baseline
  verdict = **fail (in-mem)**, matching the template's pre-filled cell. Raw:
  `s0-baseline-raw/go_relay_fulltest.log`, `go_relay_failover.log`.

### Metric 10 — host-gate regression floor (HOST + sim, captured) ✅
- **Vehicle:** `./scripts/run_test_gates.sh {1to1,feed,groups,baseline,transport}` + `go test ./...`.
- **Pure-host (deterministic, 0-fail):** `1to1` = **1226**, `feed` = **279**, `groups` = **896**
  (`All tests passed!`, EXIT 0). These three gates contain no `integration_test/*` and run fully
  headless.
- **Device-gated (need a booted simulator):** `transport` = 4 `integration_test/*` files
  (`background_reconnect`, `wifi_relay_fallback_smoke`, `transport_e2e`, `media_stable_id_smoke`) and
  `baseline`'s 2 `integration_test/*` files (`loading_states_smoke`, `posts_phase1_fake`). `baseline`'s
  4 **host** files = **112** pass. Sim capture: device/fixture-gated — suites SKIP on a lone sim (`background_reconnect` → "All tests skipped"); needs the 2-device+relay matrix (deferred-not-waived) / device-gated (2 integration files, not run on a lone sim)
  (iPhone 16e, see `s0-baseline-raw/device_*.log`).
- **Go floors:** go-relay `./...` 191/0/2; go-mknoon `./...` PASS (go1.25.0; 6 pkgs, 0 fail, ~1171 tests; node 434s, bridge 196s) (go1.25.0).
- **core-host-all** (`test/core/**`): **249/249 core files PASS, 0 fail**.

### Metrics 1, 2, 4, 5, 6, 7 — device-only, deferred-not-waived
- **1 (perceived latency):** real mDNS/RTT/relay-wire — host fake can't reproduce. Proxy = 1b. Run the
  3-scenario device capture (same-WiFi / diff-net / offline, ≥20 sends) at Phase-0 close (FDC-04).
- **2 (notif-tap→live):** real push + relay drain. Vehicle `notification_tap_timing.dart:43-63`
  verified. Reuse the 145 capture harness; report med+p90.
- **4 (transport distribution real split):** sim mDNS is host-shared → forced off
  (`DISABLE_LOCAL_DISCOVERY`, `e2e_test_mode.dart:2`). Host in-session counts need a live send session
  (`TransportMetrics` is in-memory). Aggregate the persisted `transport` column (`012_…:28`) on device.
- **5 (cold-start):** **REUSE FDC-S1** — do not duplicate. S1 owns `T_nodeStart/T_circuit/T_mdns`.
- **6 (LAN win-rate):** **REUSE FDC-S6** — device-only soak, `EnableLibp2pLanDial=false` WS baseline.
- **7 (resume):** real WiFi↔cellular switch. `handle_app_resumed.dart:137-191` computes the step
  durations (debugPrint-only today); FDC-S1 Method-6 converts to `FDC_RESUME_STEP_TIMING`.

### Metrics 3, 8 — host-deterministic, baseline-RED
- **3 (mis-route):** FDC-01 TC-01..04 — a slow-but-online peer must NOT land `transport:'inbox'`. On
  the baseline tree the fix is absent ⇒ the RED test fails ⇒ that failing test *is* the proof the
  mis-route exists (§4.1). Fleet rate needs a small one-line flow-event at the `direct_timeout`→inbox
  decision (land with FDC-01 if a fleet number is wanted; else rely on the deterministic test).
- **8 (reactions):** FDC-18 reaction round-trip RED catalog; `send_reaction_use_case.dart` exists but
  inherits none of FDC-01/03's orchestration. Host-deterministic once FDC-18 authors the tests.

---

## Vehicle-anchor honesty audit (7-agent verification — PASS)

Every metric-catalog `file:line` vehicle was read against real source. **All exist at (or within ±2
of) the cited line.** Immaterial nuances, recorded for honesty:

| Anchor | Nuance (does not affect the metric) |
|---|---|
| `transport_metrics.dart:87` | Cited line is the `class TransportMetrics` header; the constructor body is at `:118`. |
| `node.go:919/931` | Emits `relay:reservation_timing` (not `node:startup_timing`). |
| `node.go:1697/1707` | Emits `circuit_address:timing` (matches "first circuit"; not an mDNS-timing emit). The catalog loosely folds both under the "startup family / first mDNS resolve" — there is **no mDNS-timing emit at those exact lines**. (Metric 5 REUSES FDC-S1 regardless.) |
| `notification_tap_timing.dart:52` | `elapsedMs` is actually at `:54` (off-by-2); `milestone:'live_render'` at `:57` exact. |
| `p2p_service_impl.dart:1481-1483` | These are the record-type field **declarations** (`retrieveMs/ackMs/replayMs`), not the compute site; values computed via `Stopwatch` and emitted at `:1806-1810` (verified). |
| `inbox_store.go:14` | The interface is named **`InboxBackend`**, not `InboxStore` (a separate `InboxStore` struct wrapper exists). Dedup contract present at the cited lines. |

Confirmed exact (no nuance): all of metric 1/4 send-path Dart (`send_message_result.dart:7-9`,
`p2p_service_impl.dart:1993-2013`, `send_chat_message_use_case.dart:469-472/1423-1426/1514-1518`,
`transport_metrics.dart:190/226/243/292/4-10`); metric 1b/4/5 Go (`benchmark_*`,
`classifyStreamTransport` + uses `:1411`/`:1619`, `node:startup_timing` emit `:417-421`); metric 3/4/6
persistence+diagnostics (`012_transport_column.dart:28`, recordTransport `:298/:328/:358/:3269`,
`settings_transport_diagnostics_card.dart`, `e2e_test_mode.dart:2`); metric 9 dedup
(`backend_memory.go:121-142`, `backend_redis.go:272-295`, `inbox_store.go:7`); and the reuse pointers
(FDC-S1 cold-start tables, FDC-S6 LAN soak, FDC-18 reaction RED, FDC-01 mis-route RED).

---

## Honesty / limits (carried from the spec, plus this run's findings)

- **Go toolchain:** baseline captured under **go1.25.0** (declared); local default **go1.26.4** panics
  in quic-go v0.49.0 QUIC handshake (`crypto/tls … session ticket`). Recorded above. The After column
  MUST be captured under the same `GOTOOLCHAIN=go1.25.0` for apples-to-apples (or after the quic-go
  bump that fixes 1.26).
- **Host benchmarks measure the MECHANISM, not the wall-clock UX** — 1b is ~0–1ms on loopback.
- **Perceived latency (1) and LAN-win (6) are DEVICE-ONLY, real-network.** Sim mDNS host-shared, off.
- **Dedup false-positive guard:** every fast-path metric (1, 4, 6) must read the **transport label of
  the committing leg**, never "did it deliver" (§9.1).
- **`TransportMetrics` is in-memory + session-scoped** — for a fleet number aggregate the persisted
  `transport` column (012), not the in-session counters.
- **Metric 3's fleet rate is approximate** without the small aggregation; the *correctness* claim rests
  on FDC-01's deterministic RED→GREEN, which is exact.
- **Cold-start (5) is heavy-tailed** — report median+p90, never mean.

---

## Exit-gate status (FDC-S0 §Exit gate)

1. **Wave-0 baseline column populated against a frozen commit BEFORE FDC-01** — ✅ done for host
   metrics 1b/9/10; device metrics 1/2/4 + S1 #5 + S6 #6 marked deferred-not-waived with reuse
   pointers + verified vehicles. (Frozen `17a32bef`.)
2. **Host-gate floor counts recorded + back-filled into the plans' `expected: TODO`** — ✅ (see the
   back-fill applied across FDC-01..18 + FDC-00; 1to1 1226 / feed 279 / groups 896 / baseline 112 /
   go-relay 191 / go-mknoon PASS (go1.25.0; 6 pkgs, 0 fail, ~1171 tests; node 434s, bridge 196s) / transport device/fixture-gated — suites SKIP on a lone sim (`background_reconnect` → "All tests skipped"); needs the 2-device+relay matrix (deferred-not-waived)).
3. **After column + per-metric Δ/verdict** — ⏳ epic close (with explicit "device-only,
   deferred-not-waived" marks for metrics 1 same-WiFi and 6).
4. **Every metric ties to the plan(s) it credits** — ✅ ("Plan(s) credited" column above).
