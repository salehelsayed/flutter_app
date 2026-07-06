# 216 - Cold-start "connecting"→"online" inbox-proof kick on send-proof store  (Bug)

Status: IMPLEMENTED (host-green) 2026-07-06 — TC-01..03 GREEN + mutation-verified; 189 drain (11/11), benchmark_time_to_online (6/6), core-host-all (277 suites) preserved; 3-dimension adversarial review clean. Device-proof TC-07 DEFERRED (no device attached this session).
Spec: free-text intent (no formal spec) — grounded from the device-measured RCA in memory `project_time_to_online_30s_inbox_proof_healthcheck_gate` (2026-07-06) and an 8-agent source-verified workflow.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-06 | Evidence Collector | p2p_service_impl.dart, node_state.dart, benchmark_time_to_online_harness.dart, cold_start_sendable_no_user_action_test.dart, p2p_service_impl_health_drain_test.dart, benchmark_helpers.dart, _support/node_readiness.dart | RC confirmed (verify→refute, 8 agents): send/inbox asymmetry; sim hides the race | build matrix |
| 2026-07-06 | Planner | above | host floor reproduces via controlled fake-bridge race; sim benchmark is preservation (doesn't repro); device-proof is closure | emit plan |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-06 | contract extraction (git status --short) | — | dirty baseline = startup_router.dart, first_time_experience_wired.dart (prior session), graphify-arch/* (graph regen), 00-INDEX.md, 216 plan | scope confirmed; those files NOT reverted/committed | RED |
| 2026-07-06 | RED tests added | `test/core/services/p2p_service_impl_inbox_proof_kick_test.dart` (new, own _FakeBridge) | `flutter test` → TC-01 & TC-03 RED (inboxCapabilityReady stays false, badge connecting); TC-02 GREEN-on-HEAD (post-fix guard lock) | RED for the documented reason | implement |
| 2026-07-06 | implementation | `lib/core/services/p2p_service_impl.dart` (+15, the :3175 store-branch seam) | guarded `if (!_currentState.inboxCapabilityReady) unawaited(_drainOfflineInbox());` after recordSuccessfulSendProof | single scoped seam; performImmediateHealthCheck/recovery untouched | GREEN |
| 2026-07-06 | direct GREEN | above | `flutter test …inbox_proof_kick_test.dart` → 3/3 pass | reds now green | mutation |
| 2026-07-06 | mutation-verify | (temp) | remove `!inboxCapabilityReady` guard → TC-02 RED (drains() 0→1); revert kick → TC-01/03 RED (== HEAD run) | both levers proven; restored | preservation |
| 2026-07-06 | preservation GREEN | — | `p2p_service_impl_health_drain_test.dart` 11/11; `benchmark_time_to_online_test.dart` 6/6 (sendable<6s); `run_host_test_gates.sh core-host-all` 277 suites, 0 fail (incl. #244 p2p_service_impl_test.dart) | sentinels green | gates |
| 2026-07-06 | named gates + hygiene | `scripts/run_test_gates.sh` (:149), `scripts/run_host_test_gates.sh` (:57) | new test pinned beside 189 drain in both curated 1to1 arrays; auto-globs core-host-all; `flutter analyze` 0 new; `git diff --check` clean; graphs refreshed | gate green | QA |
| 2026-07-06 | QA (independent) | — | 3-dimension adversarial Workflow (production-correctness / test-validity / scope-regression), each finding adversarially verified → 0 findings raised | blocking: none | verdict: host-closed; device TC-07 deferred |

## Source Of Truth
- Spec / intent: inline below + memory `project_time_to_online_30s_inbox_proof_healthcheck_gate`
- Gate definitions: `scripts/run_test_gates.sh` / `scripts/run_host_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`
- Numbering / index: `Test-Flight-Improv/00-INDEX.md`

## Session Classification
implementation-ready

## Exact Problem Statement
On a cold start, the connection badge sits on **"connecting"** for ~30 seconds before flipping to **"online"**, even though the relay is actually reachable in ~1.5s. Device-measured on Pixel 6 (2026-07-06): `[RELAY_SESSION] Reservation opened` at t+1.5s, the send self-proof stores at t+1.5s, then **30s of silence**, then the first `[INBOX] Retrieved pending` at t+31.6s — which is exactly the first `Timer.periodic(30s)` health-check tick. Cross-platform (shared Dart), so both iPhones and the Pixel are affected.

The badge is `connecting` until `usabilityReady = isStarted && sendCapabilityReady && inboxCapabilityReady` (`lib/features/p2p/domain/models/node_state.dart:158`, `badgeReadinessState` :161). `sendCapabilityReady` proves fast; `inboxCapabilityReady` only flips via `_recordSuccessfulInboxProof`, which on cold start doesn't happen until the first 30s health-check tick.

**What must improve:** connecting→online collapses from ~30s to ~1.5s on device — the inbox capability proof is kicked as soon as the relay is healthy and the send-proof stores, not deferred to the first periodic tick.
**What must stay unchanged (→ preserved-green sentinels):** the 189 "drain-on-every-tick" invariants (`p2p_service_impl_health_drain_test.dart`); the `benchmark_time_to_online` sendable<6s bound; `cold_start_sendable_no_user_action_test`; inbox drain coalescing and its retrieve/ack/delete semantics.

## Root Cause (verify → refute confirmed)
**Send/inbox asymmetry on the relay-became-healthy transition.** When the relay first becomes healthy (`!wasHealthy && nowHealthy`) the handler kicks the SEND proof — `_retryProactiveSendProofIfNeeded('addresses_became_healthy')` at `p2p_service_impl.dart:4340` and `('relay_became_healthy')` at `:4508` — but there is **no inbox counterpart**. `performImmediateHealthCheck()` (:4810), which does drain, is wired only to the degradation branch (:4544) and app-resume (`handle_app_resumed.dart:194`). So `inboxCapabilityReady` falls through to the first `Timer.periodic(healthCheckInterval=Duration(seconds:30))` tick (`_startHealthCheck` :768, `Timer.periodic` :2746, interval :368).

Why the cold-start startup drain (`warmBackground` :813 / `_pendingStartupDrain` :3418) doesn't cover it: on a real device it races ahead of the relay reservation (relay not yet healthy → retrieve fails / records an inbox proof **failure**), and nothing retries the inbox proof until the periodic tick. The codebase already has the mirror in ONE direction — `_recordSuccessfulInboxProof` tail-calls `_retryProactiveSendProofIfNeeded('inbox_proof_success')` at :3066. **The send→inbox mirror is the missing half.**

Verified (8-agent verify→refute, 2026-07-06): `_drainOfflineInbox()` alone deterministically records the inbox proof (`:2182` → `inboxCapabilityReady:true` :3056), self-coalesces via `_drainInProgress`, no recovery side effects; `performImmediateHealthCheck` is heavyweight (relay re-dial, 189 backoff, possible watchdog restart, mDNS re-advertise) and can NO-OP the proof via the `_isHealthChecking` (:3750) / `_recoveryInProgress` (:4824) guards. The send-proof-store branch (private probe, :3175) guarantees the just-stored self-proof envelope is present for the retrieve.

**Refuted / do-NOT-re-introduce:**
- "Plan 189 (`c18ed7de`, drain-on-every-tick) already fixed this." **False** — 189 targets chronically-degraded-relay drain *starvation*; its diff has zero hunks on the cold-start / `nowHealthy` path and the first periodic tick is still 30s out.
- "Use `performImmediateHealthCheck()` on the became-healthy branch." **Rejected** — heavyweight + can be guard-NO-OP'd; a targeted `_drainOfflineInbox()` is deterministic and side-effect-free.
- "The reservation-opened Go event gives an earlier Dart hook." **False** — `relay:warm_timing` / `relay:reservation_timing` / `circuit_address:timing` are no-op telemetry passthroughs in `go_bridge_client.dart`; the `relay:state` "became healthy" push IS the earliest Dart-visible signal (same Go tick as reservation-open).

## Real Scope
**In scope:** add the missing send→inbox readiness mirror — when the proactive send-proof stores in an active readiness window, kick a targeted `_drainOfflineInbox()` guarded on `!inboxCapabilityReady`. One production seam in `p2p_service_impl.dart`. Host + device tests.
**Out of scope (owned by follow-up work):** a delayed-relay-ready *simulator* scenario that reproduces the race in CI (harness knob); any change to `performImmediateHealthCheck`, the 30s interval, or the recovery/backoff machine; any badge-UI change.

## Files To Inspect Next
- Production: `lib/core/services/p2p_service_impl.dart` — `_attemptProactiveSendProofIfNeeded` (:3143, the `if (stored)` probe-success branch :3175-3180), `recordSuccessfulSendProof` (:3003, public @override — do NOT hook here), `_drainOfflineInbox` (:2037) → `_recordSuccessfulInboxProof` (:2182 → `inboxCapabilityReady:true` :3056), `_stateWithReadinessProjection` (:2758), `_beginReadinessProofWindow` (:2793, resets both proofs :2835-2836), the became-healthy branches (:4340/:4508) as the alternate seam.
- Model (unchanged, read-only): `lib/features/p2p/domain/models/node_state.dart:158-171`.
- Direct/integration tests: `test/core/services/p2p_service_impl_health_drain_test.dart` (fake-bridge pattern to copy), `integration_test/cold_start_sendable_no_user_action_test.dart`, `integration_test/benchmark_time_to_online_harness.dart` + `test/performance/benchmark_time_to_online_test.dart`, `integration_test/_support/node_readiness.dart`, `integration_test/benchmark_helpers.dart`.
- Dependency-only context: `test/core/services/node_readiness_predicates_test.dart`, `test/features/p2p/domain/models/node_state_test.dart`.

## Existing Tests Covering This Area
- `test/core/services/p2p_service_impl_health_drain_test.dart` — 189 drain-per-tick invariants (**exists**; preservation sentinel; provides the `_FakeBridge`/`_captureFlowEvents`/`drains()` pattern to copy).
- `integration_test/cold_start_sendable_no_user_action_test.dart` — cold start reaches sendable, source `system_inbox_store_probe`, timeout 30s (**exists**; asserts REACHED, **not FAST** — the 30s bug slips under it).
- `integration_test/benchmark_time_to_online_harness.dart` / `test/performance/benchmark_time_to_online_test.dart` — asserts `sendable totalMs < 6000` (**exists**; passes today → **the sim does NOT reproduce the device race**; fast localhost relay lets the startup drain win).
- `test/core/services/node_readiness_predicates_test.dart`, `test/features/p2p/domain/models/node_state_test.dart` — `usabilityReady`/`badgeReadinessState` (**exist**; model unchanged).
- **MISSING:** any test asserting the inbox proof is kicked *promptly* (without a periodic tick) once the relay is healthy and the send-proof stores. This is the coverage gap this plan fills.
- Already in curated family arrays?: `p2p_service_impl_health_drain_test.dart` is listed in `run_test_gates.sh:149` and `run_host_test_gates.sh:57`; `cold_start_sendable_no_user_action_test.dart` at `run_test_gates.sh:349`. New host test auto-globs into `core-host-all`; add it to the same curated array that lists the 189 drain test.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
New file: `test/core/services/p2p_service_impl_inbox_proof_kick_test.dart` (own `_FakeBridge` copy per the health-drain precedent; **do not edit** the dirty `p2p_service_impl_test.dart`).

1. `p2p_service_impl_inbox_proof_kick_test.dart::"send-proof store kicks an immediate inbox drain — inboxCapabilityReady flips without a periodic health-check tick"`
   - Tier: unit/application host (FakeBridge; no real bridge/relay needed — the fix is pure Dart wiring).
   - Shape/setup: `startNodeCore(key,'self-peer')` with relay initially **not** healthy so the startup drain does **not** record the inbox proof (stub `inbox:retrieve_pending` → `ok:false` for the pre-healthy phase, OR assert `inboxCapabilityReady==false` after start). Ensure an active readiness window. Stub `inbox:store` (the cmd `callP2PInboxStore` issues, :4643) → `ok:true` so the probe stores. Drive `bridge.onRelayStateChanged?.call({relayState:'online', healthyRelayCount:1})` → `!wasHealthy && nowHealthy` fires the send-proof retry → probe stores. Now flip the `inbox:retrieve_pending` stub to `ok:true, messages:[<the self-probe>]`. Do **not** call `performImmediateHealthCheck` and do **not** advance any 30s timer.
   - RED on HEAD because: no send→inbox kick exists; after the store, `inbox:retrieve_pending` is not re-issued, `inboxCapabilityReady` stays false, `currentState.badgeReadinessState == connecting`.
   - GREEN after fix asserts: `service.currentState.inboxCapabilityReady == true`; `isSendableBadgeState(service.currentState) == true` (badge left `connecting`); `drains()` incremented by exactly one attributable to the store; and **zero** `performImmediateHealthCheck` invocations occurred (the test never calls it) — proving the proof came from the seam, not a tick.
   - Mutation that re-reds: revert the `unawaited(_drainOfflineInbox())` kick at the send-proof-store branch → this test red.
   - Distinct-event discriminator (shared drain result): assert the settle-order — badge reaches online driven by the store settling, with **no** `RELAY_RECOVERY_START` / health-tick FLOW events between store and online (distinguishes seam-kick from the periodic-tick drain).

2. `p2p_service_impl_inbox_proof_kick_test.dart::"inbox kick fires at most once per readiness window (guarded on !inboxCapabilityReady)"`
   - Tier: unit host.
   - Shape/setup: reach inbox-proven via the kick (test 1 preamble); then trigger a second send-proof path in the SAME window (`onRelayStateChanged` online again / a second store) and assert no additional `inbox:retrieve_pending` beyond coalescing.
   - RED on HEAD because: locks post-fix guard behavior — its mutation is the RED lever (see below).
   - GREEN after fix asserts: `drains()` does not increase on the second same-window trigger (guard short-circuits); `inboxCapabilityReady` stays true.
   - Mutation that re-reds: remove the `!_currentState.inboxCapabilityReady` guard → kick re-fires per retry → `drains()` exceeds expected → red.

3. `p2p_service_impl_inbox_proof_kick_test.dart::"a fresh readiness window (offline→online) re-arms the inbox kick"`
   - Tier: unit host.
   - Shape/setup: prove inbox in window 1; drive relay degraded then healthy so `_beginReadinessProofWindow` resets `sendCapabilityReady`/`inboxCapabilityReady` to false (:2835-2836); the send-proof re-runs and stores; assert the kick fires again.
   - RED on HEAD because: after the new window, inbox proof again waits for a tick — badge `connecting` after the store, no immediate re-prove.
   - GREEN after fix asserts: `inboxCapabilityReady` re-flips true within the new window off the store, `drains()` incremented again.
   - Mutation that re-reds: revert the kick → red.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 kick-on-store | pure Dart wiring / capability state | unit host | `p2p_service_impl_inbox_proof_kick_test.dart::send-proof store kicks an immediate inbox drain…` | no send→inbox kick; inboxCapabilityReady stays false, badge connecting | revert `unawaited(_drainOfflineInbox())` kick → RED | `flutter test test/core/services/p2p_service_impl_inbox_proof_kick_test.dart` | AUTO (`test/core/**` glob) + append to `ONE_TO_ONE_TESTS` (`run_test_gates.sh:149`, beside the 189 drain test) |
| TC-02 once-per-window guard | idempotence latch | unit host | `…::inbox kick fires at most once per readiness window` | (post-fix guard lock) | remove `!inboxCapabilityReady` guard → re-fires → RED | `flutter test test/core/services/p2p_service_impl_inbox_proof_kick_test.dart` | AUTO (glob) |
| TC-03 re-arm on new window | derived-state re-arm across transition | unit host | `…::a fresh readiness window re-arms the inbox kick` | new window's inbox proof again waits for a tick | revert kick → RED | `flutter test test/core/services/p2p_service_impl_inbox_proof_kick_test.dart` | AUTO (glob) |
| TC-04 189 drain-per-tick preserved | preservation sentinel | unit host | `p2p_service_impl_health_drain_test.dart::*` (all TC-189-*) | (stays GREEN) | n/a (preservation) | `flutter test test/core/services/p2p_service_impl_health_drain_test.dart` | already in array (`run_test_gates.sh:149`) |
| TC-05 sendable<6s preserved | perf bound, guard-safe no-op in sim | simulator/perf | `test/performance/benchmark_time_to_online_test.dart` (drives `benchmark_time_to_online_harness.dart`) | (stays GREEN; guard makes kick a no-op when startup drain already proved) | n/a (preservation) | `flutter test test/performance/benchmark_time_to_online_test.dart` | in perf harness (`run_benchmark_suite.dart`) |
| TC-06 cold-start sendable reached | integration preservation | integration_test (device-tagged) | `integration_test/cold_start_sendable_no_user_action_test.dart` | (stays GREEN) | n/a (preservation) | `/sims` (device-tagged) — array `run_test_gates.sh:349` | already registered (array line 349) |
| TC-07 connecting→online FAST on device | real-relay race — **PROD-CRITICAL** closure | device-proof | on-device measurement (adb logcat: `Reservation opened`→first `Retrieved pending` gap) | HEAD ≈ 30s; fix ≈ ≤3s | revert kick → device gap returns to ~30s | device capture recipe below (Pixel 6 + iPhone) | manual device-proof; optional delayed-relay sim scenario is a follow-up |

## Blind-Spot Sweep  (evergreen classes — row added OR justified N/A)
- **Lifecycle / derived-state durability:** `inboxCapabilityReady` is in-memory derived state that resets on process restart. A fresh cold start = a fresh readiness window, so the kick must fire again to reconstruct the online badge — **covered by TC-03** (new-window re-arm) and TC-01 (fresh start). No persisted state added; no DB change.
- **Sibling-surface consistency:** the two capability proofs are SEND and INBOX; the SEND kick already exists (:4340/:4508/:3066), the INBOX kick is the missing mirror. This plan *is* the sibling-consistency fix — **locked by TC-01**. No other parallel gate exists → no further sibling to align.
- **Destructive-action side-effects:** the kick calls the SAME `_drainOfflineInbox` (retrieve → ack → server-side delete) as the 30s tick — only earlier; no new deletion path. **TC-01 asserts a message present at kick time is delivered (drain result processed), not dropped**; drain coalescing/ack semantics remain covered by `p2p_service_impl_health_drain_test.dart` (TC-189-05).
- **Invariant re-verification under new transitions:** the new send-proof→inbox-drain transition must not break (a) the once-per-window guard (**TC-02**), (b) 189 drain-per-tick (**TC-04**), (c) drain coalescing (existing TC-189-05). All locked.

## Invariants (locked by tests)
- INV-1: on an active readiness window, a successful send-proof store proves inbox capability WITHOUT a periodic health-check tick → **TC-01**.
- INV-2: the inbox kick fires at most once per readiness window → **TC-02**.
- INV-3: a fresh readiness window (recovery/cold-start) re-arms the kick → **TC-03**.
- INV-4 (preservation): every health-check tick still drains (189 INV-1) → **TC-04**.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every TC-01..03 row.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short` (dirty-tree baseline: `startup_router.dart`, `first_time_experience_wired.dart` from prior 216-adjacent session work are unrelated — do not revert).
2. Add RED tests TC-01..03 in `test/core/services/p2p_service_impl_inbox_proof_kick_test.dart`; run focused → confirm they FAIL for the documented reasons (badge stays `connecting`, no immediate drain).
3. Production edit — `lib/core/services/p2p_service_impl.dart`, inside `_attemptProactiveSendProofIfNeeded`, the `if (stored)` branch at :3175, immediately after `recordSuccessfulSendProof(...)`:
   ```dart
   // 216: mirror the inbox→send readiness kick (:3066) in the send→inbox
   // direction. The self-proof envelope we just stored is guaranteed
   // retrievable, so prove inbox capability now instead of waiting for the
   // first 30s periodic health-check tick. Guarded on !inboxCapabilityReady
   // (mirrors the send side's !sendCapabilityReady guard :3147) → fires at most
   // once per readiness window, re-arms per _beginReadinessProofWindow.
   if (!_currentState.inboxCapabilityReady) {
     unawaited(_drainOfflineInbox());
   }
   ```
   Alternate seam (if TC-01 exposes a store-timing gap): add the same guarded `unawaited(_drainOfflineInbox())` to the `!wasHealthy && nowHealthy` branches at :4340 and :4508 alongside the existing `_retryProactiveSendProofIfNeeded` — the tests assert observable behavior and pass under either seam. Prefer the single :3175 seam.
   Stop-if: `_drainOfflineInbox` requires a param or the `unawaited` import is absent → add `import 'dart:async';` if needed; do NOT reach for `performImmediateHealthCheck` (rejected in RC).
4. Rerun TC-01..03 → GREEN. Then preservation (TC-04/05/06) → green. Then `flutter analyze` (0 new) + `git diff --check`.
5. Graph hygiene: `graphify update .` then `./graphify-arch/refresh_arch_graph.sh` (app-owned code changed).
6. Device closure (TC-07): rebuild+install (see memory `feedback_flutter_install_wipes_data_use_adb_install_r`), cold-start, capture the `Reservation opened`→first `Retrieved pending` gap on Pixel 6 + an iPhone; confirm ≤3s.

## Risks And Edge Cases
- **Draining the self-proof envelope early** — the kicked drain retrieves the readiness send-probe we just stored. This is the SAME message the 30s tick retrieves today, through the SAME `_drainOfflineInbox` → incoming router path; the fix only changes *when*. Pinned by TC-01 (message delivered, not dropped) + existing router/drain tests.
- **Double drain (startup drain + kick)** racing → coalesced by `_drainInProgress` (:2042-2054); pinned by existing TC-189-05.
- **Guard prevents re-fire storms** on repeated send-proof retries within a window → TC-02.
- **Sim does not reproduce the race** (fast relay) → the guard makes the kick a no-op there; TC-05 stays green; genuine closure is TC-07 device-proof.
- **Concurrency:** `unawaited` fire-and-forget must not block send-proof completion or its `finally` retry chain (:3198-3204) — kick is placed inside the `if (stored)` success arm, before the `finally`, and is non-awaited.

## Device/Relay Proof Profile
**Requires device for closure** (the race is device-manifest; host proves the logic deterministically, sim does not reproduce).
Closure scenario: on-device cold start; measure `[RELAY_SESSION] Reservation opened` → first `[INBOX] Retrieved pending` gap via `adb logcat -v time` (Pixel) — HEAD ≈ 30s, fix ≈ ≤3s. iPhone via `xcrun devicectl` install + the same GoLog markers (note: `emitFlowEvent(layer:'FL')` badge lines do NOT appear in release logcat — use the GoLog `[INBOX]`/`[RELAY_SESSION]` markers).
Deferred device work → follow-up: an automated delayed-relay-ready simulator scenario that reproduces the race in CI (harness knob to defer the relay reservation past the startup drain).
Relay defaults if needed: see `/sims` (`/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooW…`).

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/core/services/p2p_service_impl_inbox_proof_kick_test.dart
#   expect: TC-01..03 FAIL (badge stays connecting / no immediate drain)

# Direct GREEN (after fix)
flutter test test/core/services/p2p_service_impl_inbox_proof_kick_test.dart
#   expect: 3/3 pass

# Preservation sentinels (must stay green)
flutter test test/core/services/p2p_service_impl_health_drain_test.dart      # expect: 11/11 pass (189 invariants)
flutter test test/performance/benchmark_time_to_online_test.dart             # expect: pass, sendable totalMs < 6000
./scripts/run_host_test_gates.sh core-host-all                               # expect: all green (new test auto-globbed)

# Named curated gate for the touched subsystem
# The 189 drain test lives in ONE_TO_ONE_TESTS (run_test_gates.sh:149); add the new
# test to that same array so the curated 1to1 gate lists it too.
./scripts/run_test_gates.sh 1to1                                             # expect: NNNN/NNNN pass (fill count from a clean run)

# Device closure (TC-07, PROD-CRITICAL) — manual, both platforms
#   adb -s 21071FDF600CSC logcat -c && <cold start> && adb -s 21071FDF600CSC logcat -v time | grep -E "Reservation opened|Retrieved pending"
#   expect: gap ≤ ~3s (was ~30s)

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: TC-01..03 before the fix.
- Pre-existing dirty: `lib/features/identity/presentation/startup_router.dart`, `lib/features/home/presentation/screens/first_time_experience_wired.dart` (prior-session compile-fix, unrelated) — do NOT revert.
- Environment blocker (NOT product): missing device/sim for TC-07 → host TC-01..03 still gate the logic.
- Scope drift (BLOCKING): any failure in `performImmediateHealthCheck`, recovery/backoff, or badge-UI code — this fix touches none of it.

## Done Criteria
- [x] RED TC-01..03 added first, failed for the expected reason (TC-01/03 RED on HEAD; TC-02 = post-fix guard lock).
- [x] Mutation-verified (revert kick → TC-01/03 red; remove `!inboxCapabilityReady` guard → TC-02 red, drains() 0→1).
- [x] Direct GREEN + preservation sentinels (TC-04 189 11/11 / TC-05 benchmark 6/6 / core-host-all 277) + named gate pass.
- [x] No DB schema change (no migration test needed — confirmed).
- [ ] Device-proof TC-07: connecting→online ≤3s on Pixel 6 + iPhone (was ~30s). **DEFERRED — no device attached this session; host TC-01..03 gate the logic.**
- [x] New test's harness-registration done (auto-glob verified in `core-host-all`; added to both curated 1to1 arrays beside the 189 drain test).
- [x] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations (production edit is the single :3175 seam); graphs refreshed (full 108965 nodes + arch 43234 nodes).

## Scope Guard (hard "Do not")
- Do not modify `performImmediateHealthCheck`, `_performHealthCheck`, `healthCheckInterval`, or the recovery/backoff machine (owned by plan 189).
- Do not hook the public `recordSuccessfulSendProof` @override (:3003) — a future real-send caller would trigger a per-message drain.
- Do not edit `test/core/services/p2p_service_impl_test.dart` (dirty-suite Scope Guard) — new tests go in the dedicated file.
- Do not change badge/UI code or `node_state.dart`.

## Accepted Differences / Intentionally Out Of Scope
- Automated CI reproduction of the race (delayed-relay-ready sim scenario) — a harness knob; follow-up owns it. Host TC-01..03 + device TC-07 are sufficient closure.
- Belt-and-suspenders inbox kick at the became-healthy branches (:4340/:4508) — the single :3175 seam is sufficient; documented as the alternate.

## Dependency Impact
- None outward. This restores an internal readiness-proof symmetry; the badge contract (`usabilityReady`) is unchanged, so orbit/feed connection-indicator consumers see only a faster transition.

## Reviewer Findings
3-dimension adversarial review Workflow (production-correctness / test-validity / scope-and-regression), each raised finding adversarially verified (refute-by-default): **0 findings** across all dimensions (68 tool-uses, ~258k tokens, ~10min of investigation → genuinely clean, not spurious-empty). No concurrency defect in the fire-and-forget kick (coalesced by `_drainInProgress`; the send-proof `finally` retry chain is unaffected — the kick is non-awaited); no false-green / non-mutation-sensitive test; no Scope Guard violation.

## Arbiter Decision
Host-closed. The single :3175 seam is the correct minimal fix; the guard makes it a no-op on the fast-relay/sim path (TC-05 preserved) and re-arms per readiness window (TC-03). Ship dark relative to any UI contract — only the connecting→online transition gets faster.

## Final Execution Verdict
IMPLEMENTED + host-green + adversarially-reviewed, committed 2026-07-06. Production: one guarded `unawaited(_drainOfflineInbox())` at `p2p_service_impl.dart` (send-proof store branch). Tests: `p2p_service_impl_inbox_proof_kick_test.dart` TC-01..03 (RED-first, mutation-verified). Preservation: 189 drain 11/11, benchmark 6/6, core-host-all 277/277. **Remaining for full closure: device-proof TC-07 (Pixel 6 + iPhone, `Reservation opened`→first `Retrieved pending` gap ≤3s) — deferred, no device this session.**
