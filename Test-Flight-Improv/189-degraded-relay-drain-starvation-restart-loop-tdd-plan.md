# 189 - Degraded-relay inbox-drain starvation + no-exit 30s node-restart loop  (Bug)

Status: implemented-host-green (device runsheet = closure gate, pending)
Spec: Test-Flight-Improv/189-degraded-relay-drain-starvation-restart-loop-spec.md

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-02 | Evidence Collector (live 2-device debug + 5-agent RCA workflow + Explore verify) | relay journal/Redis, Pixel logcat, iPhone syslog; p2p_service_impl.dart, node.go, relay_session.go, bridge.go, autorelay v0.39.1 | Both defects field-proven (10-min undelivered repro) | verify→refute |
| 2026-07-02 | Verify→Refute (3-agent adversarial) | same + go_bridge_client.dart, personal_rendezvous_refresh.go, watchdog_failover_test.go, local_relay_harness_test.go | ALL claims SURVIVE; 2 strengthening facts (guard predicate needs `_hasEverBeenOnline`; bridge never serializes `Success`) | build matrix |
| 2026-07-02 | Planner | tier-matrix, harness inventory (run_test_gates.sh arrays, discovery checker, 183 runsheet) | host-first tiers; NO P2PService interface change (31-fakes hazard avoided) | emit plan |
| 2026-07-02 | Reviewer (sufficiency) | this plan vs sufficiency-checklist | matrix has zero empty cells; blind-spot sweep recorded | hand to Arbiter |
| 2026-07-02 | Arbiter | — | no structural blockers; device runsheet = closure gate | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-02 | contract extraction (git status --short) | — (read-only) | dirty tree = 188 session's hunks (`feature_flags_runtime_test.go`, `holepunch_tracer_test.go`, 188 docs, 00-INDEX, info.plist) — 172 already committed bb3ad390; 2 live claude sessions share the tree (pgrep/lsof) | production targets all clean; avoid other session's hunks | RED |
| 2026-07-02 | RED tests added | NEW `test/core/services/p2p_service_impl_health_drain_test.dart` (10 tests), NEW `go-mknoon/integration/no_circuit_recovery_test.go` (4), NEW `go-mknoon/node/reachability_default_guard_test.go` (unit guard) | Dart: 8 RED for documented reasons, TC-05/06 GREEN. Go: 3 wedge tests RED (`Success:false NO_CIRCUIT watchdog_restart`, dial all-dials-failed, cycle-0 restart). TC-189-41 integration RED-on-HEAD against a loopback relay → root-caused (v0.39.1 `cleanupAddressSet` keeps only public/DNS relay addrs) → guard uses `/dns4/localhost` like prod's `/dns/` relay, then GREEN-on-HEAD 0.57s | Group-F diagnostic partially answered on host: loopback/private relay addrs are silently unpublishable; prod relay is DNS ⇒ device trigger is elsewhere | implement |
| 2026-07-02 | implementation | `lib/core/services/p2p_service_impl.dart` (Fix A drain-on-every-tick; Fix B2 `ok && success != false` + `P2P_HEALTH_CHECK_RECOVERY_FAILED`; Fix B3 backoff fields + skip gate + arming, bypass when recoverySource != 'health_check_poll'), `go-mknoon/node/relay_session.go` (`ManualReservationExpiry`, `OnManualReservationOpened`, `HasActiveManualReservation`, holds cleared on disconnect/reservation-end), `go-mknoon/node/autorelay_metrics.go` (sync demote-guard), `go-mknoon/node/node.go` (reserve fan-out captures `*relayclient.Reservation` → mgr; verdict `else if reserveSucceeded` = reservation-truth, `foregroundRecoveryPath=reservation_truth`; watchdog path consults `mgr.HasReservation()`), `go-mknoon/bridge/bridge.go` (`resp["success"]`) | all edits additive; no P2PService interface change; drain internals untouched | — | direct GREEN |
| 2026-07-02 | direct GREEN | — | `flutter test …health_drain_test.dart` 10/10; Go: 4/4 189 tests (in_place recovery ~10s, peer-dialable reservation, 3 cycles → 0 restarts/0 group latch) | — | mutations |
| 2026-07-02 | mutation verification | — | M1 drain-revert → TC-01/02/03/04/07/12/13 red; M2 coalescing-off → TC-05 red; M3 ok-only branch → TC-11/12/13 red; M4 backoff-off → TC-12/13 red; M5 Go verdict revert → TC-10/14/15 red. All restored, suites green | — | preservation |
| 2026-07-02 | preservation GREEN | `test/core/services/p2p_service_impl_test.dart` (ONE fixture update, see below), `scripts/run_test_gates.sh` + `scripts/run_host_test_gates.sh` (189 file appended) | 1to1 gate **1465/1465** (baseline 1454 + 10 new); core-host-all green; full Go integration suite green incl. `watchdog_failover` (`TestAllRelaysUnavailable…` still asserts Success:false — reserve fails there, no over-reach); `go test ./node/... ./bridge/...` green | `'background resume starts a new proof window'` asserted the plan-documented gap (no drain on recovery ticks); Fix A's drain is a legitimate FRESH inbox proof → fixture now fails `retrieve_pending` during the resume tick (test intent = stale-proof reuse, preserved). Scope-guard note: plan said don't edit this file because of 172's then-uncommitted hunks; 172 committed first (bb3ad390), file was clean | named gates |
| 2026-07-02 | named gates | — | `flutter analyze` 0 new (1 pre-existing curly-braces info, line-shifted); `git diff --check` clean; `make test` — `TestGP006PublishWithPartialPeers` FAILS 3/3 **also on a clean-HEAD control worktree** ⇒ pre-existing env failure (pubsub flake family, per Known-Failure protocol), not 189; transport gate host suites green, device leg needed `FLUTTER_DEVICE_ID` (multi-device host) → re-run on iPhone 16e sim | — | runsheet |
| 2026-07-02 | QA (independent code-reviewer agent, read-only) | `lib/core/services/p2p_service_impl.dart`, `…health_drain_test.dart` (+1 test) | ONE Important finding (conf 80): backoff bookkeeping never reset on a PURE self-heal (autorelay flips relay online with no successful Dart reconnect) → next fresh outage inherits a stale skip budget + inflated counter. Fixed RED-first: new test `'backoff resets on pure self-heal…'` (RED: counter stayed 3 after healthy poll) → healthy-poll block now zeroes `_consecutiveRefreshFailures`/`_recoveryBackoffStep`/`_recoveryBackoffSkipsRemaining`. Suite 11/11; impl suite 120/120; 1to1 gate re-run **1466/1466**. All other review dimensions (fan-out concurrency, hold state-machine, coalescing, group-recovery-on-real-restart, budgets) reported clean | half-open-relay note (hold keeps `online` until disconnect/expiry) = documented intentional trade, bounded | bookkeeping |
| 2026-07-02 | QA / bookkeeping | `Test-Flight-Improv/189-degraded-relay-drain-device-runsheet.md` (written, PENDING; TC-189-50 amended to --profile-only per dev_keychain_wipe landmine), 00-INDEX 189 row already added by the planning session's hunk (not duplicated), memory file written, graphs refreshed | device runsheet TC-189-30/31/50 = closure gate, needs Pixel 6 + iPhone 11 + gomobile rebuild (Go changed) | environment: iPhone 11 not attached | hand to device session |

## Source Of Truth
- Spec: Test-Flight-Improv/189-degraded-relay-drain-starvation-restart-loop-spec.md
- Gate definitions: scripts/run_test_gates.sh (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md (NOTE: index has drifted — nothing indexed past 178; add the 189 row, backfill is out of scope)

## Session Classification
implementation-ready

## Exact Problem Statement
A device whose relay session is chronically degraded never pulls its relay durable inbox: the 30s health check's recovery branch (`p2p_service_impl.dart:3757-3871`) returns at `:3871` before the only periodic drain (`:3888`), and the Go node is locked in a permanent 30s full-restart loop (`waitForCircuitAddress` polls `h.Addrs()` for `/p2p-circuit` with 3s/10s budgets while only autorelay's relayFinder — 20s IdentifyWait, reset by every restart — can publish one). Field result (2026-07-02, Pixel→iPhone): store→ack 86–368 s and a >10-minute undelivered controlled repro, while iPhone→Pixel is 0–1 s.

What must improve: (1) every health-check tick — recovery or not, success or not — issues an inbox drain; (2) a node whose manual relay reservation succeeds exits the restart loop (reservation = circuit truth) and reports recovery truthfully (`phase=recovered` only when real); (3) consecutive failed recoveries back off instead of hard-restarting every 30 s forever.
What must stay unchanged (→ preserved-green sentinels): send-path budgets & FDC-01/02 race shape, 185/187 semantics, drain pipeline internals (paging/coalescing), 141/145/182/183 drain triggers, group recovery semantics on REAL restarts, default-flag Private reachability.

## Root Cause (verify → refute confirmed)
- **Defect A** — `_performHealthCheck` recovery branch `p2p_service_impl.dart:3757-3871`: awaits `_attemptRelayRecovery` (`:3812`, internal try/catch `:3323-3331` never rethrows) → re-poll → `return;` `:3871`. Drain `:3888` unreachable on every degraded tick once `_hasEverBeenOnline` is true (`:3743-3746`). No covert drain anywhere in the recovery window: `relay:warm_timing`/`relay:reservation_timing`/`circuit_address:timing` are no-op cases (`go_bridge_client.dart:717-730`); `relay:state`/`addresses:updated` handlers re-register tokens / funnel back into the same skip (`p2p_service_impl.dart:4340-4449`, `:4160-4283`); `_emitState` one-shot needs an `isStarted` false→true edge + externally-latched drain (`:3369-3371`). `performImmediateHealthCheck` (`:4713`→`:4746`) inherits the skip. Re-entrancy guard `_isHealthChecking` (`:3712-3719`) makes slow recovery ticks swallow the next periodic tick.
- **Defect B (Go)** — manual `relayclient.Reserve` success (node.go:995-1049) never reaches advertised addrs: app AddrsFactory only filters (node.go:203, :389); zero `/p2p-circuit` append sites in go-mknoon; only autorelay's relayFinder publishes (v0.39.1 `autorelay.go:63`), and it needs `ReachabilityPrivate` and time the 3s/10s waits (`config.go:41,:46`; node.go:1054-1073, :1217) don't give it. Full restart (`reconnectRelaysOwned` node.go:1161-1245) resets relayFinder; no counter/cooldown anywhere.
- **Defect B (bookkeeping)** — `ReconnectRelays` returns `Success:false, ErrorCode:"NO_CIRCUIT", err=nil` (node.go:1229-1245); bridge sets `"ok": true` whenever err==nil and **never serializes `Success`** (bridge/bridge.go:821-862); Dart branches on `ok==true` alone (`:3257`) → false `RELAY_OUTAGE_TIMING phase=recovered` (`:3284-3310`) + `_consecutiveRefreshFailures=0` (`:3311-3312`). `refreshFailureThreshold=3` (`:352`) and `RecordWatchdogRestart` (relay_session.go:661-666) are dead; `watchdogRestartCount` (relay_session.go:391) is reported, never acted on.

Refuted / do-NOT-re-introduce:
- "Send drains the inbox" — REFUTED as a direct path; the field correlation is the relayState flip making the *next* tick take the normal branch. Do not add a send→drain hack.
- "Push events during recovery drain" — REFUTED (`go_bridge_client.dart:717-730` no-ops). A degraded→online `relay:state` flip does NOT drain today either (`:4398-4412`) — fixed transitively by A.
- "Netlink denial causes the Pixel loop" — co-symptom only (blocks LAN addrs, not circuit addrs); owned by the separate netlink/anet spec (not yet numbered).
- "The startup `else if` fall-through saves some ticks" — reachable only <15 s after a prior attempt while `_hasEverBeenOnline` is still false (`:3554-3570`); never on the 30 s cadence. Not a mitigation.

## Real Scope
In scope: (1) drain-on-every-tick in `_performHealthCheck`; (2) Go: accept manual-reservation truth in the circuit-address verdict (`relaySessionMgr` session state → `waitForCircuitAddress`/recovery verdict + `relayState` aggregate); (3) bridge serializes `success`/`errorCode`; Dart consumes them for truthful `phase=recovered` + failure accounting; (4) Dart backoff on consecutive failed recoveries (makes `refreshFailureThreshold` load-bearing); (5) reachability-default guard test.
Out of scope: iOS push→drain (separate spec, needs unredacted-log diagnosis); Android netlink/anet (separate spec); relay-server changes; go-libp2p upgrade; DCUtR flag work (188 owns); group-drain redesign; keepalive redesign (183 owns).

## Files To Inspect Next
Production: `lib/core/services/p2p_service_impl.dart` (`_performHealthCheck` :3711-3945, `_attemptRelayRecovery` :3211-3335, `:3257/:3284-3312` bookkeeping, `:352` threshold), `go-mknoon/node/node.go` (:995-1073, :1146-1245, :1798-1835, :373-376), `go-mknoon/node/relay_session.go` (session state, `StatusFields` :503-509, `CircuitAddressesAreStale` :522-545), `go-mknoon/bridge/bridge.go` (:821-862), `go-mknoon/node/peer_session.go` (:20-25).
Direct tests: `test/core/services/p2p_service_impl_test.dart` (fake-bridge pattern :60-114, status builder :246-279, `performImmediateHealthCheck` seam, `_captureFlowEvents` :29-57), `go-mknoon/integration/watchdog_failover_test.go`, `go-mknoon/integration/local_relay_harness_test.go` (:169-367).
Dependency-only: `lib/core/bridge/go_bridge_client.dart` (:703-730), `go-mknoon/node/personal_rendezvous_refresh.go` (:126-156), `test/core/bridge/fake_bridge.dart`.

## Existing Tests Covering This Area
- `test/core/services/p2p_service_impl_test.dart` :4948-5031/:5140-5170 — recovery attribution + `relay:reconnect` called (exists; asserts NO drain behavior on recovery ticks — the gap).
- `test/core/inbox/inbox_round_trip_test.dart`, `test/core/lifecycle/*` — manual drain triggers (exist; none periodic).
- `go-mknoon/integration/watchdog_failover_test.go` — `ReconnectRelays` + `RecoveryResult` + status metrics (exists; asserts `Success==false` on HEAD in one case — will need updating ONLY if its fixture matches the reserve-ok/no-publish shape; verify at execution).
- MISSING: drain-on-recovery-tick; chronic-degradation starvation; restart backoff/cap; truthful `phase=recovered`; reservation-truth loop exit; peer-dials-reservation proof.
Already in curated arrays: `p2p_service_impl_test.dart` in `ONE_TO_ONE_TESTS` (run_test_gates.sh:52) + `ONE_TO_ONE_HOST_TESTS` (run_host_test_gates.sh:41). `test/core/**` is NOT auto-globbed into curated 1to1 (in-array comment precedent :104-131) — new core tests must be appended explicitly.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

**New Dart file: `test/core/services/p2p_service_impl_health_drain_test.dart`** (own local `_FakeBridge extends Bridge` copy of the :60-114 pattern + `_captureFlowEvents`; do NOT edit `p2p_service_impl_test.dart` — it carries another session's uncommitted 172 changes). Common fixture: `node:start` ok → one tick with `relayState:'online'` (latches `_hasEverBeenOnline`, drains once) → status handler flips to sequenced `'degraded'`; `relay:reconnect` handler configurable; ticks driven via `await service.performImmediateHealthCheck()`.

1. `…health_drain_test.dart::'recovery tick still drains — 3 degraded ticks issue 3 inbox:retrieve_pending'` (TC-189-01)
   - Tier: unit/application host
   - RED on HEAD: recovery branch returns at :3871 → `retrieve_pending` count stays 1 (the healthy tick) while `RELAY_RECOVERY_START` FLOW count == 3.
   - GREEN: count ≥ 4 (1 healthy + 3 recovery ticks) AND `RELAY_RECOVERY_START` == 3 (discriminator proving the ticks were recovery ticks, not healthy-path drains).
   - Mutation that re-reds: restore the early `return;` before the drain.
2. `…health_drain_test.dart::'drain fires even when recovery fails (reconnect ok but retry status degraded)'` (TC-189-02) — RED: 0 drains on that tick. GREEN: drain issued after the failed recovery. Mutation: same revert.
3. `…health_drain_test.dart::'drain fires and tick survives when relay:reconnect throws'` (TC-189-03) — bridge handler throws. RED: no drain. GREEN: drain issued, no exception escapes, a subsequent tick still runs. Mutation: same revert.
4. `…health_drain_test.dart::'degraded relay:state push → immediate health check → drain'` (TC-189-04) — trigger via `bridge.onRelayStateChanged?.call({...degraded})` + settle. RED: recovery runs (`relay:reconnect` called), 0 drains. GREEN: drain issued. Mutation: same revert.
5. `…health_drain_test.dart::'healthy tick drains exactly once; concurrent manual drain coalesces'` (TC-189-05, preservation) — GREEN on HEAD and must stay GREEN: healthy tick → +1 `retrieve_pending`; slow retrieve handler + concurrent `drainOfflineInbox()` → single in-flight (coalescing `:2029-2052`). Guards the fix against double-drain regressions. Mutation that re-reds: remove the coalescing guard.
6. `…health_drain_test.dart::'starvation lock: 5 consecutive degraded ticks → 5 recovery starts AND ≥5 drains'` (TC-189-07) — RED: drains == 0 in the window. GREEN: per-tick pairing holds. Mutation: same revert as #1.
7. `…health_drain_test.dart::'phase=recovered emitted ONLY on truthful recovery; failure counter not reset on NO_CIRCUIT'` (TC-189-11 Dart half) — `relay:reconnect` returns `{'ok': true, 'errorCode': 'NO_CIRCUIT', 'success': false}` + retry status degraded. RED on HEAD: `RELAY_OUTAGE_TIMING phase=recovered` IS emitted (Dart branches on `ok` alone :3257) and `service.consecutiveRefreshFailures` (getter :4710) resets to 0. GREEN: no `phase=recovered`; counter increments. Discriminator: assert `RELAY_OUTAGE_TIMING{phase:'recovered'}` NOT emitted AND recovery-failure FLOW/counter IS. Mutation: revert Dart to `ok`-only branching.
8. `…health_drain_test.dart::'failed-recovery backoff: N degraded ticks → sublinear relay:reconnect count, drains stay per-tick'` (TC-189-12) — 6 degraded ticks with failing recovery. RED on HEAD: `relay:reconnect` called 6× . GREEN: recovery attempts follow the backoff schedule (≥3rd consecutive failure starts skipping; exact schedule = implementation constant, assert count ≤ 4 and monotone spacing) while `retrieve_pending` count == 6+1. Mutation: remove the backoff gate.
9. `…health_drain_test.dart::'backoff resets on truthful recovery; exactly one phase=recovered on convergence'` (TC-189-13) — failing recoveries ×3 then handler flips to `{'ok':true,'success':true}` + healthy retry status. GREEN: next allowed tick recovers, ONE `phase=recovered`, counter 0, push-token re-register hook fires (`:3858-3862` — invariant re-verification), subsequent ticks take the normal branch. RED on HEAD: `phase=recovered` on every tick. Mutation: revert truthfulness or backoff.

**New Go file: `go-mknoon/integration/no_circuit_recovery_test.go`** (`//go:build integration`; uses `local_relay_harness_test.go` helpers; run with `GOTOOLCHAIN=go1.25.0`).

10. `TestReserveSuccessCountsAsCircuitTruth_NoRestartLoop` (TC-189-10) — node via `startNodeWithRelays` with `n.SetForcePublicReachabilityForTests(true)` set pre-Start (node.go:2087-2093; deterministic: autorelay's publisher is STOPPED under Public — v0.39.1 autorelay.go:63,:108-110 — while warm+manual-Reserve succeed against the harness's real hop service). Call `n.ReconnectRelays()`. RED on HEAD: `RecoveryResult{Success:false, ErrorCode:"NO_CIRCUIT", RecoveryMode:"watchdog_restart"}`, `WatchdogRestartCount()` incremented. GREEN: `Success:true`, `RecoveryMode:"in_place"`, restart count unchanged, `relayState` aggregate reaches `online` (reservation-truth accepted). Mutation: revert the verdict change → red.
11. `TestPeerCanDialReservationAfterRecovery` (TC-189-14, **PROD-CRITICAL wire leg**) — same wedged node A + second node B (default flags) on the same local relay; after A's `ReconnectRelays`, B opens a stream to A via `<relayAddr>/p2p-circuit/p2p/<A>`. RED on HEAD: dial fails NO_RESERVATION (post-restart relayFinder stopped ⇒ no reservation). GREEN: stream opens. Mutation: revert reservation-truth → red.
12. `TestNoCircuitCyclesDoNotChurnGroupsOrRestartUnbounded` (TC-189-15) — 3 consecutive `ReconnectRelays` on the wedged node. RED on HEAD: `WatchdogRestartCount()` +3 and `NeedsGroupRecovery()` latched each cycle. GREEN: +0, no group-recovery latch on reserve-ok cycles. Mutation: revert → red.
13. `TestDefaultFlagsKeepPrivateReachability` (TC-189-41, guard) — unit-tier Go: `dcutrReachabilityMode(false, false) == "private"` (peer_session.go:20-25) + integration: default-flag node against the local relay eventually shows `/p2p-circuit` in `n.Status()` addresses (autorelay alive). RED-check: flipping the default or forcing Public turns it red. (GREEN on HEAD — a guard, not a fix test.)

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-189-01 | wiring/logic | unit host | health_drain_test::'recovery tick still drains…' | `return;` :3871 precedes drain :3888 | restore early return | `flutter test test/core/services/p2p_service_impl_health_drain_test.dart` | AUTO (core-host-all) + **append to ONE_TO_ONE_TESTS** |
| TC-189-02 | wiring | unit host | same::'drain fires even when recovery fails…' | same | same | same | same file (one registration) |
| TC-189-03 | error path | unit host | same::'…relay:reconnect throws' | same (catch :3323-3331 then return) | same | same | same |
| TC-189-04 | push funnel | unit host | same::'degraded relay:state push → drain' | `performImmediateHealthCheck` inherits skip (:4746) | same | same | same |
| TC-189-05 | preservation | unit host | same::'healthy tick drains once; coalesces' | n/a (GREEN sentinel) | remove coalescing :2029-2052 | same | same |
| TC-189-06 | outcome bound | unit host + device | derived: TC-189-01 + `healthCheckInterval==30s` const lock; closure = runsheet TC-189-30 | drain never fires ⇒ bound unbounded | restore early return | same + runsheet | same + runsheet (manual) |
| TC-189-07 | starvation lock | unit host | same::'5 degraded ticks → ≥5 drains' | drains==0 in window | restore early return | same | same |
| TC-189-10 | Go recovery verdict | Go integration | no_circuit_recovery_test::TestReserveSuccessCountsAsCircuitTruth… | verdict polls only autorelay-published addrs (node.go:1814) | revert reservation-truth | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -tags integration -run NoCircuit ./integration/...)` | manual Go gate (documented in test-gate-definitions.md:211; NOT in Flutter gates — noted in Known-Failure Interpretation) |
| TC-189-11 | truthful bookkeeping | unit host (Dart) + Go field | health_drain_test::'phase=recovered ONLY truthful…' (+ bridge serializes `success` asserted in TC-189-10's result) | bridge omits Success (bridge.go:821-862); Dart branches on ok (:3257) | revert ok-only branching | `flutter test …health_drain_test.dart` | AUTO + array (same file) |
| TC-189-12 | backoff | unit host | same::'failed-recovery backoff…' | no comparison of failure counters anywhere | remove backoff gate | same | same |
| TC-189-13 | convergence | unit host | same::'backoff resets on truthful recovery…' | phase=recovered every tick on HEAD | revert truthfulness/backoff | same | same |
| TC-189-14 | real relay, 2 nodes | Go integration | no_circuit_recovery_test::TestPeerCanDialReservationAfterRecovery | post-restart no reservation ⇒ NO_RESERVATION | revert reservation-truth | Go integration cmd above | manual Go gate |
| TC-189-15 | collateral bound | Go integration | no_circuit_recovery_test::TestNoCircuitCyclesDoNotChurn… | restart+group-latch per cycle (relay_session.go:390-393) | revert | Go integration cmd above | manual Go gate |
| TC-189-20 | cross-defect E2E | Go integration + device | TC-189-10+14 jointly (Go); closure = runsheet | both defects live | either revert | Go cmd + runsheet | Go gate + runsheet |
| TC-189-21 | sender invariants | preservation | existing 1to1 suites (no new test) | n/a (sentinel) | n/a | `./scripts/run_test_gates.sh 1to1` — all pass (baseline 2026-07-02: 1454/1454) | already registered |
| TC-189-30/31 | device measurement | device-proof (manual runsheet) | Test-Flight-Improv/189-degraded-relay-drain-device-runsheet.md (write at execution; clone 183 runsheet shape; Pixel `21071FDF600CSC`, iPhone 11 `00008030-001A6D2801BB802E`) | field repro (store→ack 86–368s+) | any revert | manual runsheet PASS log | runsheet (manual; no classify_path needed — no new integration_test file) |
| TC-189-40 | trigger preservation | preservation | existing lifecycle/keepalive/182 suites | n/a (sentinel) | n/a | `./scripts/run_host_test_gates.sh core-host-all` + `1to1` gate | already registered |
| TC-189-41 | reachability guard | Go unit + integration | no_circuit_recovery_test::TestDefaultFlagsKeepPrivateReachability | n/a (guard, GREEN on HEAD) | flip default to Public | Go cmds above (unit half: `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -run DefaultFlagsKeepPrivate ./node/...)`) | manual Go gate |
| TC-189-42 | dead scaffolding | unit host | TC-189-12's test makes `refreshFailureThreshold` load-bearing | never compared on HEAD | remove backoff gate | `flutter test …health_drain_test.dart` | AUTO + array |
| TC-189-50 | diagnostic | device (carried) | runsheet step: capture `GOLOG_LOG_LEVEL=autorelay=debug` run on Pixel; attach to closure | n/a | n/a | runsheet | runsheet |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability**: backoff counter + `_hasEverBeenOnline` are in-memory by design — a process restart resetting backoff is CORRECT (fresh process deserves fresh attempts). Justified N/A; the 30s-loop exit itself is the durability fix.
- **Sibling-surface consistency**: the fix moves the EXISTING drain call site, so whatever the healthy tick drains today (1:1 offline inbox) the recovery tick drains identically — parity by construction, locked by TC-189-01's discriminator (same `inbox:retrieve_pending` verb both branches). Group inbox drains are event-driven (out of scope, unchanged) — asymmetry pre-exists and is 06/182 territory, noted not hidden.
- **Destructive-action side-effects**: backoff SKIPS a recovery action — TC-189-12 explicitly asserts the drain still runs on skipped-recovery ticks (nothing else is removed). Full-restart teardown itself unchanged (out of scope); TC-189-15 bounds its frequency.
- **Invariant re-verification under new transitions**: reservation-truth creates a new "usable relay without advertised circuit addr" state — TC-189-10 asserts `relayState` aggregate reaches online (so Defect-A normal branch resumes), TC-189-13 asserts push-token re-register fires on the truthful healthy transition (`:3858-3862`), TC-189-14 asserts peers can actually dial the reservation (the invariant that matters).

## Invariants (locked by tests)
- INV-1 every health-check tick issues ≥1 drain regardless of branch/outcome → TC-189-01/02/03/07.
- INV-2 `phase=recovered` ⇔ retry state actually healthy/usable → TC-189-11/13.
- INV-3 reserve-success ⇒ no full-restart cycle AND peers can dial the circuit → TC-189-10/14/15.
- INV-4 recovery attempts back off; drains never do → TC-189-12.
- INV-5 default flags keep Private reachability → TC-189-41.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (dirty tree carries another session's uncommitted 172 work in `p2p_service_impl.dart`/`p2p_service_impl_test.dart`/`c4_partial_drain_test.dart` — do not touch their hunks; coordinate before rebasing anything).
2. Add all Dart REDs (`test/core/services/p2p_service_impl_health_drain_test.dart`) + Go REDs (`go-mknoon/integration/no_circuit_recovery_test.go`); run the RED gates; confirm each fails for its documented reason.
3. **Fix A (Dart)**: in `_performHealthCheck`, guarantee the drain on every tick — execute `_drainOfflineInbox()` after the recovery attempt in the recovery branch (post-re-poll, before `return;` at :3871) or restructure with try/finally so `:3888` is unconditional. Keep drain AFTER `_attemptRelayRecovery` so it rides the freshly re-dialed session. Do not touch `_drainOfflineInbox` internals.
4. **Fix B1 (Go)**: reservation-truth — in the recovery verdict path (in-place `:1054-1073` and post-restart `:1217`), treat `relaySessionMgr`'s reserve-success state as circuit-ok (the node already constructs the dialable circuit addr deterministically, node.go:1357); sync `relayState` aggregate to online on reservation-truth. Seam: `waitForCircuitAddress` callers consult the session manager; do NOT patch go-libp2p.
5. **Fix B2 (bridge+Dart truthfulness)**: serialize `success` (+ keep `errorCode`) in `RelayReconnect` response (bridge.go:830-860); Dart `:3257` requires `ok && success != false` (tolerate absent `success` for bridge-version skew) before `phase=recovered`/counter-reset; else increment `_consecutiveRefreshFailures`.
6. **Fix B3 (Dart backoff)**: when `_consecutiveRefreshFailures >= refreshFailureThreshold` (:352 becomes load-bearing), skip `_attemptRelayRecovery` on an escalating tick schedule (e.g. skip 1, 2, 4… ticks, capped ≈8 ≙ 4 min) — still drain (Fix A) and still poll status; reset schedule on truthful success. Stop-if: backoff interacts badly with resume-triggered `performImmediateHealthCheck` (user-visible refresh must bypass the backoff once) → allow explicit-source bypass, replan if messier.
7. Rerun: direct GREEN → preservation sentinels → named gates → hygiene.
8. Write `189-degraded-relay-drain-device-runsheet.md` (183 shape) and execute TC-189-30/31/50 on the phones; log PASS/metrics.

## Risks And Edge Cases
- Slow recovery + re-entrancy guard (`:3712-3719`) swallowing ticks → drains still bounded by tick cadence; TC-189-07 pins per-tick pairing.
- Double-drain when recovery flips state and `relay:state` push also arrives → coalescing (`:2029-2052`) pinned GREEN by TC-189-05.
- Reservation-truth masking a genuinely dead relay link → TC-189-13 (genuine outage converges; truth requires reserve SUCCESS, not just warm), TC-189-14 (dialability proven).
- Bridge/Dart version skew on new `success` field → Dart tolerates absent field (step 5); TC-189-11 fixture covers present-and-false.
- Go 1.26 quic-go panic → all Go cmds use `GOTOOLCHAIN=go1.25.0` (Makefile:11 precedent).
- `-race` flake `pubsub_delivery_test.go:966` is pre-existing (memory: run clean-HEAD control before attributing).

## Device/Relay Proof Profile
Host-green is NOT closure. Closure = device runsheet TC-189-30/31 on Pixel 6 (`21071FDF600CSC`, cellular) + iPhone 11 (`00008030-001A6D2801BB802E`, WiFi): Pixel→iPhone store→ack p95 ≤35 s, no 30 s relay flap over 10 min, `watchdogRestartCount` Δ≤2/30 min, reverse direction still 0–2 s. Plus TC-189-50 autorelay-debug capture (Group-F diagnostic).
Relay defaults: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYj…` (live prod — observe read-only via `ssh -i se.pem ubuntu@13.60.15.36`, journal recipe in memory).

## Acceptance Gates  (literal — copy/paste)
```bash
# RED (before production edits) — must FAIL for the documented reasons
flutter test test/core/services/p2p_service_impl_health_drain_test.dart          # expect: TC-01/02/03/04/07/11/12/13 shapes RED; TC-05 GREEN
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -tags integration -run 'NoCircuit|PeerCanDialReservation' ./integration/...)   # expect: FAIL (Success:false / NO_RESERVATION)

# Direct GREEN (after fix)
flutter test test/core/services/p2p_service_impl_health_drain_test.dart          # expect: all pass
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -tags integration ./integration/...)   # expect: all pass (incl. existing watchdog_failover suite — see Known-Failure notes)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -run DefaultFlagsKeepPrivate ./node/...)  # guard: pass

# Preservation sentinels
./scripts/run_host_test_gates.sh core-host-all                                   # expect: all pass, 0 new failures vs HEAD baseline
./scripts/run_test_gates.sh 1to1                                                 # expect: all pass (2026-07-02 baseline 1454/1454; new file appended → count grows)
./scripts/run_test_gates.sh transport                                            # expect: all pass
(cd go-mknoon && make test)                                                      # Go unit sweep (GOTOOLCHAIN pinned by Makefile)

# Registration verification (after appending the new file to ONE_TO_ONE_TESTS)
./scripts/run_test_gates.sh 1to1 2>&1 | grep p2p_service_impl_health_drain       # must list

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED (pre-fix): the 8 Dart shapes + 2 Go tests above, each for its documented mechanism.
- Existing `watchdog_failover_test.go` asserts `Success==false` in `TestAllRelaysUnavailable…` — that fixture is *relay unreachable* (reserve FAILS), so reservation-truth must NOT flip it; if it reds, the fix over-reached (treat as scope drift, BLOCKING).
- Pre-existing dirty tree: 172 session's uncommitted hunks in `p2p_service_impl.dart`, `p2p_service_impl_test.dart`, `c4_partial_drain_test.dart`, inbox staging files — do not revert; do not edit those files' 172 hunks.
- Environment blockers (NOT product): missing physical devices for the runsheet; Go 1.26 toolchain panic (pin 1.25.0); `-race` pubsub flake (clean-HEAD control first).
- Scope drift (BLOCKING): any red outside Scope Guard, esp. FDC-01/02 or 185/187 suites.

## Done Criteria
- [x] REDs added first, failed for documented reasons (Dart 8 shapes + 1 QA-round shape, Go 3 wedge tests; TC-05/06 + Go guards GREEN sentinels).
- [x] Mutation-verified: each fix's revert re-reds its named tests (M1 drain, M2 coalescing, M3 ok-only, M4 backoff, M5 Go verdict; self-heal reset proven RED-first).
- [x] Direct GREEN + preservation sentinels + named gates pass; new file listed in 1to1 gate output (1to1 1466/1466; core-host-all PASS; transport PASS on iPhone 16e sim with FLUTTER_DEVICE_ID; full Go integration + node/bridge unit green; `make test` GP006 failure = pre-existing, clean-HEAD control reproduced 3/3).
- [x] No DB migration needed (none — verified).
- [ ] Device runsheet TC-189-30/31 PASS logged with metrics; TC-189-50 debug capture attached (**PENDING — closure gate**; runsheet written, needs gomobile rebuild + both phones).
- [x] flutter analyze 0 new; git diff --check clean; other session's dirty hunks untouched (188 files + info.plist verified unmodified by this session).
- [x] 00-INDEX.md row for 189 present (added by the planning session's uncommitted hunk — not duplicated).

## Scope Guard (hard "Do not")
- Do not add methods to the base `P2PService` interface (33 fakes break — use the established side-interface pattern only if unavoidable).
- Do not modify `_drainOfflineInbox` internals, paging, or coalescing.
- Do not change FDC-01/02 budgets, 185/187 send semantics, or re-baseline their suites.
- Do not flip `enableDcutrUpgrade` or alter DCUtR behavior (188 owns it; `SetForcePublicReachabilityForTests` is a test seam only).
- Do not patch/upgrade go-libp2p or the relay server.
- Do not edit the 172 session's uncommitted hunks; do not modify `p2p_service_impl_test.dart` (new test file instead).

## Accepted Differences / Intentionally Out Of Scope
- iOS push→drain dead path (stale FCM token slot, foreground onMessage) — needs a debug-build/logging-profile diagnosis session first; own spec after.
- Android netlink SELinux / anet root fix — own spec; FDC-11 port-mining keeps LAN adverts alive meanwhile.
- Sibling-device identity clone (Pixel peerId registered ios+android tokens) — ops investigation, not code.
- Why relayFinder never publishes on-device under default flags — Group-F diagnostic (TC-189-50) informs a follow-up; reservation-truth makes the system robust to it either way.
- 00-INDEX backfill for 179-188 (index drift) — separate housekeeping.

## Dependency Impact
- FDC epic close (soak+device campaign) depends on this: the restart loop invalidates any soak run on affected devices.
- 172/173's relay redeploy (other session) is independent; but TC-189-30 measurements should run AFTER any relay redeploy to avoid attributing relay-side changes.
- 183 keepalive benefits transitively: loop exit → pings succeed → drop latch re-arms correctly.

## Reviewer Findings
Sufficiency self-check (2026-07-02): matrix zero empty cells in tier/mutation/gate/registration ✓; every spec TC-ID mapped (01-07, 10-15, 20, 21, 30/31, 40, 41, 42, 50) ✓; every INV test-locked ✓; REDs documented with HEAD mechanisms from the adversarial pass ✓; PROD-CRITICAL leg named (TC-189-14) ✓; preservation sentinels with commands ✓; no DB migration ✓; device closure gate named ✓; blind-spot sweep recorded (2 rows, 2 justified N/A) ✓; refuted findings recorded ✓; dirty-tree snapshot step present ✓. Residual risk: Go integration tests run in no Flutter gate (manual `go test -tags integration`) — documented, matches existing repo practice; the discovery checker does not cover Go tests.

## Arbiter Decision
Structural blockers: none. Deferred details: exact backoff schedule constant (implementation freedom inside TC-189-12's monotone/cap envelope); whether bridge-version skew tolerance stays permanent (follow-up). Accepted differences: as listed. Hand off to execution.

## Final Execution Verdict
**implemented — host+Go-integration GREEN, mutation-verified, independently reviewed (2026-07-02). Device runsheet = the remaining closure gate.**

- Fix A/B1/B2/B3 all landed additively; scope guard held (no P2PService interface change, drain internals untouched, FDC-01/02/185/187 suites un-rebaselined, DCUtR flags untouched, no libp2p/relay-server patches).
- One deliberate deviation: ONE fixture update in `p2p_service_impl_test.dart` (`'background resume starts a new proof window…'` — it asserted the plan-documented gap; Fix A's drain is a legitimate fresh inbox proof, so the fixture now fails `retrieve_pending` on the resume tick, preserving the test's stale-proof-reuse intent). The plan's do-not-edit guard existed for 172's uncommitted hunks, which had already landed as bb3ad390.
- QA round added a 5th behavior: backoff/failure-streak reset on observed-healthy polls (pure autorelay self-heal), RED-first.
- Group-F diagnostic partially answered at host tier: go-libp2p v0.39.1 `cleanupAddressSet` publishes circuit addrs only for public/DNS relay addrs (loopback/private relay ⇒ reservation-ok/no-publish forever). Prod relay is DNS, so the on-device trigger remains open — TC-189-50 capture stays carried in the runsheet.
- Deferred-not-waived: TC-189-30/31/50 (device), 173-interlock (run after any relay redeploy).
