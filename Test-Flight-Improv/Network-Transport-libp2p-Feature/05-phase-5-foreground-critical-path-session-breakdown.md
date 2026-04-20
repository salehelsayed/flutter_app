# Phase 5 Foreground Critical Path Session Breakdown

## Recommended plan count

1

## Decomposition artifact

- artifact path: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-5-foreground-critical-path-session-breakdown.md`
- proposal or source doc path: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- scoped phase: `Phase 5. Remove noncritical work from the foreground recovery critical path`
- downstream workflow rule:
  - detailed planning happens one session at a time
  - execution must stay inside the Phase 5 contract from the source doc
  - no Phase 6 product-semantics work or unrelated transport changes may be added in this rollout

## Overall closure bar

This Phase 5-only rollout is good enough only if all of the following are true:

- RED tests for the Phase 5 seam land first and fail before the production change
- the foreground recovery path completes once relay reservation and required personal discoverability are restored
- push registration, long direct-inbox continuation, and group rejoin / group inbox follow-up do not block foreground recovery completion on the successful resume path
- deferred background follow-up failures do not bounce the app from recovered back to degraded
- inbox, registration, and group continuity protections stay covered by direct tests and the required regression pass
- the required direct tests, benchmarks, and regression gates from the Phase 5 contract are rerun and recorded
- the experiment results markdown compares before vs after numbers against `05-phase-0-relay-recovery-baseline-results-rerun-2026-04-17.md` and ends with an explicit keep/revert recommendation

## Source of truth

- Proposal: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- Benchmark inventory: `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- Baseline comparison doc: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results-rerun-2026-04-17.md`
- Prior instrumentation / relay-recovery references:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-section-8-instrumentation-first-results-2026-04-17.md`
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-results.md`
- Named gates: `Test-Flight-Improv/test-gate-definitions.md`
- Current Dart / lifecycle seam:
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/core/services/p2p_service_impl.dart`
  - `test/core/lifecycle/app_lifecycle_recovery_test.dart`
  - `test/core/lifecycle/background_reconnect_smoke_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
  - `test/core/services/fake_p2p_service.dart`
  - `test/performance/benchmark_background_resume_test.dart`
  - `integration_test/benchmark_background_resume_harness.dart`
  - `integration_test/benchmark_relay_recovery_harness.dart`
  - `integration_test/background_reconnect_test.dart`

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `1` | `Phase 5 foreground critical path deferral` | `implementation-ready` | `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-5-foreground-critical-path-session-1-plan.md` | none | `accepted_with_explicit_follow_up` | Completed with RED-first lifecycle regressions, the minimum Dart-only deferred follow-up seam, the required direct/device regressions, and a refreshed results doc. Explicit follow-up: `05-phase-5-foreground-critical-path-results.md` recommends revert / do not promote because degraded resume did not improve on top of the accepted Phase `3b` baseline and the dominant cost stayed in relay refresh / circuit-address wait. |

## Ordered session breakdown

### Session 1

- title: Phase 5 foreground critical path deferral
- session id: 1
- session classification: implementation-ready
- intended plan file: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-5-foreground-critical-path-session-1-plan.md`
- exact scope:
  - add the missing Phase 5 RED tests first for successful foreground recovery completion, non-blocking deferred resume follow-up, and "stay recovered even if deferred work fails"
  - implement only the minimum Dart lifecycle deferral needed so the successful resume path stops blocking on noncritical work after `performImmediateHealthCheck()` has already restored the relay and personal discoverability
  - keep the direct inbox, push-registration, and group-recovery follow-up work running in the background with fault isolation instead of deleting it
  - preserve inbox, registration, and group continuity protections by updating or adding only the direct tests needed to prove the deferred path still runs and failures do not regress state
  - rerun the exact direct tests, benchmarks, and regression gates required by the Phase 5 contract
  - refresh `05-phase-5-foreground-critical-path-results.md` with before/after numbers versus `05-phase-0-relay-recovery-baseline-results-rerun-2026-04-17.md` and a keep/revert recommendation
- why it is its own session:
  - the RED tests, bounded lifecycle deferral, and experiment evidence all target one foreground-critical-path hypothesis and should stop together once the Phase 5 verdict is known
- likely code-entry files:
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `test/core/lifecycle/app_lifecycle_recovery_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
  - `test/core/services/fake_p2p_service.dart`
  - `test/performance/benchmark_background_resume_test.dart`
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-5-foreground-critical-path-results.md`
- likely direct tests/regressions:
  - `flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart`
  - `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
  - `flutter test test/core/lifecycle/background_reconnect_smoke_test.dart`
  - `flutter test test/performance/benchmark_background_resume_test.dart`
- likely named gates:
  - `transport`
- matrix/closure docs to update when done:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-5-foreground-critical-path-results.md`
  - this breakdown artifact ledger
- dependency on earlier sessions:
  - none
- execution-safety corrections that must be carried into the session plan:
  - treat `05-relay-recovery-improvement-tdd-plan.md` Phase 5 as the only active scope, even if nearby code or docs mention earlier or later experiments
  - RED tests must land before the fix
  - do not add Phase 6 sendable-before-green semantics, new Go relay timing tweaks, or broader lifecycle redesign
  - defer only follow-up work that is not needed for the foreground "usable again" moment after relay recovery already succeeded
  - results must be reported honestly even if the recommendation remains revert

## Why this is not fewer sessions

- The user explicitly scoped this rollout to Phase 5 only, and the remaining work is one bounded foreground-lifecycle seam plus its evidence refresh.

## Why this is not more sessions

- Splitting RED-test work from the bounded lifecycle change would add bookkeeping without changing the gate or closure bar.
- The benchmark/reporting step is inseparable from the experiment verdict because the user explicitly asked to stop after reporting.

## Regression and gate contract

- RED tests first for the missing Phase 5 seam.
- Required benchmark/regression commands for this session:
  - `flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart`
  - `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
  - `flutter test test/core/lifecycle/background_reconnect_smoke_test.dart`
  - `flutter test test/performance/benchmark_background_resume_test.dart`
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_background_resume_harness.dart`
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_relay_recovery_harness.dart`
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/background_reconnect_test.dart`
  - `FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport`

## Matrix update contract

- Create and reuse `05-phase-5-foreground-critical-path-results.md` as the stable experiment record.
- This session owns both the evidence refresh and the final keep/revert recommendation.

## Downstream execution path

- Session 1 should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- Existing Go relay recovery timing and personal-discoverability behavior are treated as upstream prerequisites already covered by earlier phases, not as new Phase 5 implementation scope.
- Existing unrelated local worktree edits are treated as background context, not as proof that Phase 5 should stack on top of other experiments.
- This rollout does not create any new follow-on rollout docs beyond the refreshed Phase 5 results record and this breakdown artifact.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results-rerun-2026-04-17.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-section-8-instrumentation-first-results-2026-04-17.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-results.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/core/services/p2p_service_impl.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
- `test/core/services/fake_p2p_service.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `integration_test/benchmark_background_resume_harness.dart`
- `integration_test/benchmark_relay_recovery_harness.dart`
- `integration_test/background_reconnect_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The source doc already defines one bounded foreground-critical-path experiment with exact RED targets, benchmark obligations, and a clear stop rule.
- Current repo evidence shows the recovery seam is concentrated in `handle_app_resumed.dart` after `performImmediateHealthCheck()`, so the safe next step is a narrow lifecycle deferral rather than a broader transport redesign.
- The breakdown explicitly blocks later-phase product-semantics drift while preserving the requirement to report an honest revert recommendation if the measured win does not materialize.

## Program rollout ledger

- Breakdown artifact used:
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-5-foreground-critical-path-session-breakdown.md`
- Spawned-agent isolation used:
  `attempted_then_local_fallback`
- Sessions processed:
  `1/1`
- Sessions accepted:
  `0`
- Sessions accepted_with_explicit_follow_up:
  `1`
- Sessions blocked:
  `0`
- Sessions skipped_due_to_dependency:
  `0`
- Plan fallbacks used:
  `0`
- Execution fallbacks used:
  `1`
- Closure fallbacks used:
  `1`
- Final acceptance fallbacks used:
  `1`
- Final program acceptance verdict:
  `accepted_with_explicit_follow_up`
- Stable docs updated:
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-5-foreground-critical-path-results.md`
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-5-foreground-critical-path-session-breakdown.md`
- Final blocker note:
  Phase 5 execution is complete, but the stable results doc records a revert / do not promote recommendation because degraded resume did not improve on top of the accepted Phase `3b` baseline and the measured bottleneck stayed upstream in relay refresh / circuit-address wait.
