# Relay Recovery Improvement — Experiment-Driven TDD Plan

> **Scope:** Test-driven, measurement-first plan to reduce relay recovery and degraded background resume from the current `~9.1s` range to a user-acceptable target without merging unproven recovery behavior.
> **Depends on:** `03c-reflections.md`, `03b-benchmark-test-inventory.md`, `03-timing-and-performance.md`, `04-transport-routing-strategy.md`, `Network-Arch/Resilient-libp2p-TDD-Plan.md`.
> **Does not cover:** server-side multi-relay rollout, large group-recovery redesign, or unrelated 1:1 routing work from `04b-routing-improvement-plan.md`.

---

## Final Verdict

Yes, this is possible.

The safe way to do it is:

1. freeze the current baseline
2. add any missing recovery sub-step instrumentation first
3. implement **one** relay-recovery hypothesis at a time on an experiment branch or behind a temporary flag
4. run the same recovery benchmarks and transport regressions after each change
5. keep only the changes that move the measured bottleneck without creating regressions

This plan is therefore **evidence-gated**, not implementation-ready in one pass.

---

## 1. Real Scope

This plan covers only the client-side work most likely to reduce:

- `C-Sim` relay recovery: `p50=9136ms p95=9320ms`
- `BR-Sim-2` degraded background resume: `9166ms`
- related reconnect fallout seen in `S4` and `X1`

This plan does **not** attempt to:

- redesign the entire transport stack
- solve group continuity beyond regression protection
- mix relay-recovery work with inbox-budget or group-discovery work
- ship all proposed recovery ideas together

The goal is to make relay recovery measurable, isolate the biggest wait, and evaluate one recovery change at a time.

---

## 2. Closure Bar

This area is "good enough" for the current architecture when all of the following are true:

- degraded resume is no longer in the `~9s` range
- relay recovery no longer depends on poll/timer alignment for foreground recovery
- healthy resume remains fast
- recovery does not restart the full host in the normal successful case
- recovery callers cannot create overlapping recovery storms
- existing send, startup, and group smoke gates stay green

Target outcome for the full sequence:

- `BR-Sim-2 < 4s`
- `C-Sim p50 < 4s`

Promotion bar for an individual experiment:

- at least `1000ms` improvement or `15%` improvement on the primary target metric for that experiment
- no regression greater than `10%` in healthy resume, cold start, or post-resume send smoke

---

## 3. Source of Truth

Authoritative docs for this plan:

- [03c-reflections.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Network-Transport-libp2p-Feature/03c-reflections.md:40)
- [03b-benchmark-test-inventory.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md:503)
- [03-timing-and-performance.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Network-Transport-libp2p-Feature/03-timing-and-performance.md:204)
- [04-transport-routing-strategy.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Network-Transport-libp2p-Feature/04-transport-routing-strategy.md:1)
- [Network-Arch/Resilient-libp2p-TDD-Plan.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Network-Arch/Resilient-libp2p-TDD-Plan.md:286)

Rules on disagreement:

- current code and current tests beat stale prose
- the benchmark harnesses and benchmark inventory define the timing contract
- this document only governs the relay-recovery experiment sequence

---

## 4. Session Classification

`evidence-gated`

Reason:

- we already know relay recovery is slow
- we do **not** yet know which sub-step consumes most of the `~9.1s`
- multiple proposed fixes touch the same area, so stacking them would hide causality

---

## 5. Exact Problem Statement

The current data says:

- recovery detection is already fast: about `504ms`
- degraded resume is slow: `9166ms`
- recovery is sourced from `health_check_poll` in the degraded case
- healthy resume is only `100-103ms`
- post-recovery send itself is fast, but reconnect and restart scenarios still show long end-to-end delay

That implies the main problem is not bridge cost, crypto, or steady-state send.

The likely problem is one or more of:

- foreground resume waits for polling instead of starting recovery immediately
- relay health truth is derived too indirectly
- recovery uses a heavyweight restart path instead of targeted session refresh
- overlapping recovery callers serialize badly or duplicate work
- noncritical work remains on the foreground critical path after the relay is usable

What must improve:

- user-visible time from degraded resume to usable relay recovery

What must stay unchanged:

- healthy resume path
- warm send path
- startup path outside recovery
- durable inbox fallback behavior

---

## 6. Files and Repos to Inspect Next

Likely production files:

- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/p2p/domain/models/node_state.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `go-mknoon/node/relay_session.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/config.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/events.go`

Likely direct test files:

- `test/performance/benchmark_background_resume_test.dart`
- `test/performance/benchmark_relay_recovery_test.dart`
- `test/core/lifecycle`
- `test/core/services`
- `go-mknoon/node/relay_session_test.go`
- `go-mknoon/node/node_test.go`
- `go-mknoon/bridge/bridge_test.go`
- `integration_test/benchmark_background_resume_harness.dart`
- `integration_test/benchmark_relay_recovery_harness.dart`
- `integration_test/background_reconnect_test.dart`

---

## 7. Existing Tests Covering This Area

Already in place:

- `C-Sim` relay recovery benchmark records detection, recovery, total outage, recovery mode, and `RecoveryWaitTimeout`
- `BR-Sim` background resume benchmark distinguishes healthy vs degraded resume
- `M-Sim-3` records which source wins the online badge race
- `S4` reconnect and `X1` both-sides restart expose downstream user-visible impact
- host-side benchmark/unit coverage already exists for relay recovery event emission and timeout accuracy

What is still missing for decision-quality benchmarking:

- explicit measurement of **resume-to-recovery-start**
- explicit measurement of **relay-session refresh duration**
- explicit measurement of **registration refresh duration**
- proof that recovery completion came from immediate resume/push logic instead of poll fallback
- proof that in-place refresh reused the host instead of restarting it

---

## 8. Regression / Tests to Add First

Before changing recovery behavior, add the minimum instrumentation and tests needed to attribute wins correctly.

### 8a. Instrumentation-first additions

Add additive fields or benchmark rows for:

- `resumeToRecoveryStartMs`
- `relayRefreshMs`
- `relayWarmMs`
- `relayWarmParallelism`
- `reserveRpcMs`
- `circuitAddressWaitMs`
- `foregroundRecoveryPath` with distinct values for `foreground_success`, `background_fallback`
- `foregroundRelayDialTimeoutMs`
- `autorelayRetryCadenceMs`
- `personalReregisterMs`
- `groupReregisterMs` if executed on the foreground path
- `recoverySource` with distinct values for `resume_trigger`, `relay_state_push`, `health_check_poll`, `watchdog_restart`
- `reservationPath` with distinct values for `direct_reserve`, `autorelay_scheduler`, `poll_fallback`
- `reservationWinnerPeer` when multiple relays are configured
- `reusedHost` or equivalent boolean
- `coalescedRecoveryRequests`

### 8b. RED tests for the instrumentation phase

**Dart**

- degraded resume emits a recovery-start event immediately when the app resumes
- healthy resume does not emit recovery-start
- `TIME_TO_ONLINE_BADGE` source remains distinguishable from recovery-start source

**Go**

- recovery result includes `recoveryMode` and host-reuse information
- concurrent recovery requests increment a coalescing counter instead of starting separate refreshes

### 8c. Instrumentation acceptance rule

This phase is accepted only if:

- the old headline metrics stay within `±5%` of the known baseline
- no recovery behavior changes yet
- the new sub-step numbers make later experiments attributable

---

## 9. Step-by-Step Implementation Plan

Each experiment below must be run **alone**. Do not stack phases before measuring them.

### Phase 0. Freeze the baseline

1. Re-run the current baseline on the primary simulator.
2. Save the exact output rows for `C`, `BR`, `M`, and the two-simulator reconnect smoke.
3. Do not start code changes until the baseline reproduces within expected range.

Baseline to freeze:

- `C-Sim` relay recovery: `p50=9136ms p95=9320ms`
- `BR-Sim-2`: `9166ms`
- healthy resume: `100-103ms`
- `S4`: `send=105ms e2e=3561ms`
- `X1`: `send=142ms e2e=3310ms`

Stop rule:

- if the baseline cannot be reproduced, stop and fix benchmark stability first

Comparison rule after accepted phases:

- `Phase 0` plus the accepted instrumentation pass remain the frozen historical baseline for the whole program
- once any later phase is accepted, subsequent phases may be rerun on top of the current accepted branch if that accepted phase materially changed the bottleneck
- when a later phase is rerun on top of an accepted branch, its results doc must report both:
  - delta vs the current accepted baseline
  - delta vs the frozen `Phase 0` baseline
- do not treat an earlier rejected phase as permanently closed if an accepted earlier phase changed which sub-step dominates the user-visible path

### Phase 1. Immediate foreground recovery trigger

Hypothesis:

- degraded resume is slow because recovery starts from `health_check_poll` instead of being kicked off immediately on resume

Likely files:

- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/core/services/p2p_service_impl.dart`

RED tests:

- degraded resume calls relay refresh immediately on app resume
- healthy resume does not trigger refresh
- degraded resume no longer waits for poll to start recovery
- repeated resume signals while one refresh is in flight do not enqueue duplicate work

Benchmark to compare:

- `BR-Sim-2`
- `M-Sim-3` source distribution

Promotion rule:

- keep only if `BR-Sim-2` improves by at least `1000ms` and healthy resume stays under `150ms`

Abort condition:

- if this phase only changes the source label and does not move `BR-Sim-2`, stop and move to the next hypothesis

### Phase 2. Relay-state truth and push-driven recovery completion

Hypothesis:

- the app is still depending too much on timer/poll state instead of explicit relay-session truth

Likely files:

- `go-mknoon/node/relay_session.go`
- `go-mknoon/bridge/events.go`
- `go-mknoon/bridge/bridge.go`
- `lib/core/services/p2p_service_impl.dart`

RED tests:

- reservation opened transitions relay state to healthy/reserved
- reservation ended transitions relay state to degraded
- Dart receives `relay:state` updates without waiting for poll
- badge/recovery completion can be driven by relay-state push rather than `health_check_poll`

Benchmark to compare:

- `C-Sim`
- `BR-Sim-2`
- `M-Sim-3`

Promotion rule:

- keep only if degraded recovery source shifts off `health_check_poll` and either `C-Sim p50` or `BR-Sim-2` improves by `15%+`

Abort condition:

- if the relay-state model adds complexity without moving headline recovery time, do not continue layering more push logic on top

### Phase 3. In-place relay session refresh instead of host restart

Hypothesis:

- restart-heavy recovery is the main reason reconnect scenarios still show multi-second e2e delay even though post-recovery send is fast

Likely files:

- `go-mknoon/node/relay_session.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/bridge/bridge.go`

RED tests:

- refresh relay session does not replace the host
- refresh preserves pubsub maps and active chat state
- refresh re-registers personal rendezvous only when needed
- successful refresh reports `recoveryMode='refresh'` rather than `restart`

Benchmark to compare:

- `C-Sim`
- `S4`
- `X1`
- `X2`

Promotion rule:

- keep only if `C-Sim p50` drops by at least `2000ms` or `S4/X1 e2e` drops by `20%+` with no healthy-path regression

Abort condition:

- if in-place refresh creates state corruption, duplicate subscriptions, or group regressions, revert and treat it as not yet safe

### Phase 3a. Direct reservation after warm dial

Hypothesis:

- host-preserving refresh may still stay slow because it warms the relay connection and then waits for AutoRelay's reservation scheduler instead of issuing the reservation RPC immediately

Likely files:

- `go-mknoon/node/node.go`
- `go-mknoon/node/relay_session.go`
- `go-mknoon/node/node_test.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`

RED tests:

- after a successful warm dial, refresh issues a direct reservation attempt instead of only waiting for AutoRelay timing
- a successful direct reservation can complete recovery without depending on the polling-only `waitForCircuitAddress` path
- relay/local-address update events can complete recovery as soon as a circuit address appears, without adding a 200ms polling tail
- when multiple relays are configured, reservation attempts can race and the first success wins without duplicate registration or duplicate recovery side effects
- if direct reservation fails, the existing AutoRelay fallback path remains correct and observable in instrumentation

Benchmark to compare:

- `C-Sim`
- `BR-Sim-2`
- `M-Sim-3`

Promotion rule:

- keep only if the winning reservation path shifts to `direct_reserve` and either `C-Sim p50` or `BR-Sim-2` improves by at least `1500ms` with no healthy-resume regression

Abort condition:

- if direct reservation only changes labels or sub-step timings but does not move headline recovery time, do not stack native lifecycle or QUIC work on top of it yet
- if this experiment introduces duplicate reservations, stale relay state, or bridge/reporting ambiguity, revert and tighten the seam before any follow-on optimization

### Phase 3b. Foreground AutoRelay cadence and timeout policy

Hypothesis:

- after direct reservation proved fast, foreground recovery may still stay slow because AutoRelay retry cadence, sequential relay warm-up, and generic relay dial/wait budgets are tuned for background healing instead of "resume and make the badge green quickly"

Starting values for this experiment:

- `autorelay.WithBackoff(1 * time.Second)`
- `autorelay.WithMinInterval(1 * time.Second)`
- foreground resume relay dial timeout target: `3 * time.Second`
- keep the existing `10s` circuit-address wait only as fallback safety behavior, not as the intended foreground-success path

Likely files:

- `go-mknoon/node/node.go`
- `go-mknoon/node/config.go`
- `go-mknoon/node/relay_session.go`
- `go-mknoon/node/node_test.go`
- `go-mknoon/bridge/bridge.go`

RED tests:

- foreground recovery uses a shorter AutoRelay retry cadence than the default/background cadence
- `RefreshRelaySession()` warms configured relays in parallel so one slow relay does not block the others
- foreground resume recovery uses a shorter relay dial timeout than the general relay dial path
- if the short foreground budget fails, recovery falls back to the existing longer wait path without leaving the node stuck or misreporting success
- instrumentation distinguishes a foreground-success path from background fallback and records the configured cadence/timeout values that were used

Benchmark to compare:

- `C-Sim`
- `BR-Sim-2`
- `M-Sim-3`

Promotion rule:

- keep only if either `C-Sim p50` or `BR-Sim-2` improves by at least `1500ms`, healthy resume stays under `150ms`, and the foreground-success path wins often enough to explain the headline improvement

Abort condition:

- if `1s` AutoRelay cadence or `3s` foreground dial timeout is too flaky in the direct tests or simulator harnesses, relax to `2s` and/or `4s` inside this phase and record the final values used
- if cadence/timeout tuning plus parallel warm-up still leaves `circuitAddressWaitMs` as the dominant bottleneck without moving headline recovery time, stop and do not keep tuning numbers blindly

### Phase 4. Recovery coalescing and storm prevention

Hypothesis:

- overlapping callers from resume, poll, watchdog, and manual reconnect add wasted work and widen recovery cost

Likely files:

- `go-mknoon/node/relay_session.go`
- `lib/core/services/p2p_service_impl.dart`

RED tests:

- concurrent recovery requests share one in-flight refresh
- only one relay refresh starts when resume and poll arrive together
- stalled recovery gate clears correctly
- duplicate recovery attempts do not create duplicate registrations or inbox drains

Benchmark to compare:

- `C-Sim-2` repeated cycles
- `BR-Sim-2` repeated 3-run sample

Promotion rule:

- keep only if recovery event count drops, repeated-cycle variance stays tight, and no new stalls are introduced

Note:

- this phase is mainly about correctness and protecting p95/regression risk; it may not be the biggest single latency win

### Phase 5. Remove noncritical work from the foreground recovery critical path

Hypothesis:

- relay recovery may be waiting on follow-up work that does not need to block the foreground "usable again" moment

Likely files:

- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/core/services/p2p_service_impl.dart`
- `go-mknoon/node/rendezvous.go`
- any resume-driven inbox/group-recovery entry points

RED tests:

- relay recovery completes once reservation and required personal discoverability are restored
- group rejoin, group rendezvous refresh, and long inbox continuation do not block foreground recovery completion
- if deferred background work fails, the app remains recovered instead of bouncing back to degraded

Benchmark to compare:

- `BR-Sim-2`
- `C-Sim`
- post-resume send timing via `background_reconnect_test.dart`

Promotion rule:

- keep only if degraded resume improves and post-resume send remains correct without delivery loss

Rerun note:

- the first Phase `5` verdict against the original `~9s` baseline does not permanently close this hypothesis
- if an earlier accepted phase collapses relay or circuit-address wait enough that deferred follow-up work may now be visible in the foreground path, rerun Phase `5` on top of that accepted branch
- for that rerun, the primary decision baseline is the current accepted branch, not only frozen `Phase 0`

Abort condition:

- if this phase risks silent backlog loss, duplicate drain, or group continuity breakage, stop and split the deferred work more narrowly

### Phase 6. Optional product-policy experiment: sendable-before-green

Hypothesis:

- if the green badge must remain strict, user-perceived latency can still improve by making the app sendable before full relay cosmetics finish

This phase is optional because it changes product semantics, not just recovery mechanics.

Detailed product contract and verification matrix:

- `06-sendable-online-badge-spec.md`

RED tests:

- degraded resume allows deterministic inbox/direct fallback before green badge return
- UI state distinguishes `recovering but send-capable` from `fully online`
- queued sends do not block on the full recovery badge path

Benchmark to compare:

- new metric: `resume_to_sendable_ms`
- existing `BR-Sim-2` remains a secondary metric

Promotion rule:

- only pursue if earlier phases fail to bring `BR-Sim-2` close to target and product is willing to change readiness semantics

---

## 10. Risks and Edge Cases

- healthy resume must not get slower while fixing degraded resume
- resume, watchdog, and manual reconnect may overlap
- successful relay refresh must not silently lose personal or group discoverability
- recovery must not duplicate inbox drains or group catch-up
- host-preserving refresh must not break pubsub or active connections
- new push events must not block hot network goroutines
- simulator-only wins must be verified against at least one real reconnect smoke

---

## 11. Exact Tests and Gates to Run

Baseline and per-experiment host tests:

```bash
flutter test test/performance
flutter test test/core/lifecycle
flutter test test/core/services
go test ./go-mknoon/node/...
go test ./go-mknoon/bridge/...
```

Primary benchmark runs:

```bash
dart run integration_test/scripts/run_benchmark_suite.dart -d <DEVICE_ID> --scenarios C
dart run integration_test/scripts/run_benchmark_suite.dart -d <DEVICE_ID> --scenarios BR
dart run integration_test/scripts/run_benchmark_suite.dart -d <DEVICE_ID> --scenarios M
flutter test integration_test/benchmark_relay_recovery_harness.dart -d <DEVICE_ID>
flutter test integration_test/benchmark_background_resume_harness.dart -d <DEVICE_ID>
```

Transport regression checks:

```bash
flutter test integration_test/background_reconnect_test.dart -d <DEVICE_ID>
./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh benchmark
./scripts/run_test_gates.sh benchmark-sim
dart run integration_test/scripts/run_routing_smoke_e2e.dart -d <ALICE_ID>,<BOB_ID>
```

Recommended minimum rerun set after each accepted experiment:

- `BR-Sim`
- `C-Sim`
- `background_reconnect_test.dart`
- transport gate
- when the next phase is evaluated on top of an accepted branch, compare the rerun first against that accepted branch and second against frozen `Phase 0`

---

## 12. Known-Failure Interpretation

- if a benchmark number moves by less than normal run-to-run noise, treat it as "no evidence of improvement"
- if healthy resume regresses while degraded resume improves, the experiment is not accepted
- if a change improves `BR-Sim-2` but breaks `S4`, `X1`, or transport-gate tests, treat it as a regression, not a win
- if an experiment only changes labeling or instrumentation but not the headline timings, keep it only if it was explicitly the instrumentation phase

---

## 13. Done Criteria

This plan is complete when:

- the repo has a stable baseline record for current relay recovery
- recovery sub-step instrumentation exists to attribute wins
- each shortlisted relay-recovery hypothesis has a named RED-test set
- each experiment has a benchmark comparison and promotion bar
- the team can decide per experiment: keep, revert, or defer

This plan is fully successful when the accepted experiments collectively bring:

- `BR-Sim-2 < 4s`
- `C-Sim p50 < 4s`

without transport regressions.

---

## 14. Scope Guard

Do not let this plan expand into:

- inbox-budget optimization from `04b`
- group peer-discovery settle-wait work
- multi-relay server/storage rollout
- generic UI redesign
- media/profile transport work

Do not bundle multiple relay-recovery ideas in one experiment branch.

Do not claim a win from anecdotal app feel alone. The benchmark delta must justify promotion.

---

## 15. Accepted Differences / Intentionally Out of Scope

- strict badge semantics versus sendable-before-green is intentionally separated as an optional product-policy phase
- full group continuity redesign remains in the broader resilient-libp2p plan, not this relay-recovery sequence
- server-side shared-state or multi-relay deployment is a separate prerequisite stream, not part of this client-only benchmark plan

---

## 16. Dependency Impact

Work that depends on this plan:

- any later relay-session implementation work in `go-mknoon/node`
- resume orchestration changes in Flutter
- follow-on group continuity work after recovery

Work that should wait until this plan produces evidence:

- large recovery refactors
- changing badge semantics by default
- rolling multiple recovery changes into one branch

If the instrumentation phase shows the `~9.1s` is dominated by a different sub-step than expected, this document should be revised before implementation starts.

---

## Structural Blockers Remaining

None for creating the experiment plan itself.

There is still one evidence gap before implementation:

- the current benchmarks need recovery sub-step breakdown fields so later wins can be attributed confidently

---

## Incremental Details Intentionally Deferred

- exact field names for new recovery instrumentation
- whether experiment isolation uses short-lived feature flags or separate branches
- whether the final target should be `<4s` or `<3s` once the first successful experiment lands
- native lifecycle prewarm, QUIC session-ticket persistence, and proactive TTL refresh until the repo tests foreground AutoRelay cadence/timeouts and still cannot move the post-reservation `circuitAddressWaitMs` bottleneck

---

## Accepted Differences Intentionally Left Unchanged

- healthy resume remains sourced by the existing fast path unless a recovery experiment proves a better mechanism without regression
- existing `RecoveryWaitTimeout` safety behavior remains in place unless a dedicated experiment shows it is on the foreground critical path

---

## Why This Plan Is Safe To Implement Now

It is narrow, evidence-backed, and reversible.

It does not assume one preferred solution. It forces the repo to prove, with the existing benchmark harnesses plus a small amount of added instrumentation, which relay-recovery change actually buys user-visible improvement.
