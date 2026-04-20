# Phase 5 Foreground Critical Path Session 1 Plan

## Final verdict

Sufficient with bounded local fallback. The breakdown entry is execution-safe, the current repo seam is concentrated in `handle_app_resumed.dart` after `performImmediateHealthCheck()`, and the remaining gap is a narrow Dart lifecycle deferral plus the required evidence refresh.

## Final plan

### 1. Real scope

This session changes only the Phase 5 foreground-critical-path seam:

- add the missing Phase 5 RED tests first for foreground completion after successful relay recovery, non-blocking deferred resume follow-up, and "stay recovered if deferred work fails"
- make the minimum Dart lifecycle change needed so `handleAppResumed()` stops awaiting noncritical work after `performImmediateHealthCheck()` has already restored relay health and personal discoverability
- keep deferred push registration, direct inbox drain, and group continuity work running in the background with fault isolation rather than deleting it
- preserve the existing ordering of the deferred group follow-up steps inside that background lane
- rerun the exact Phase 5 direct tests, benchmarks, and regression gate
- refresh `05-phase-5-foreground-critical-path-results.md` with before/after numbers against `05-phase-0-relay-recovery-baseline-results-rerun-2026-04-17.md` and a truthful keep/revert recommendation

This session does not:

- add Phase 6 sendable-before-green semantics
- retune Go relay timing, AutoRelay cadence, or reservation logic
- redesign all resume-time sweeps or background workers
- widen the implementation into a general lifecycle scheduler beyond the bounded Phase 5 follow-up deferral seam

### 2. Closure bar

Session 1 is good enough only if:

- the new Phase 5 RED tests are added before the production fix and fail on current code
- the bounded lifecycle change makes those regressions pass without broadening scope
- `handleAppResumed()` can return after successful relay recovery without blocking on push registration, direct inbox drain, or group continuity follow-up
- deferred follow-up still runs, and failures there do not bounce the app out of its recovered state
- the required direct Flutter suites pass
- the required benchmark and regression commands are rerun and recorded
- the refreshed Phase 5 results doc compares before/after numbers to the frozen rerun baseline and ends with a keep/revert recommendation tied to the Phase 5 promotion rule

### 3. Source of truth

- Active source doc: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- Session breakdown: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-5-foreground-critical-path-session-breakdown.md`
- Benchmark inventory: `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- Baseline comparison doc: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results-rerun-2026-04-17.md`
- Prior relay-recovery references:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-section-8-instrumentation-first-results-2026-04-17.md`
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-results.md`
- Named gates: `Test-Flight-Improv/test-gate-definitions.md`

On disagreement:

- current code and current tests beat stale prose
- `test-gate-definitions.md` is the execution source of truth for named gates
- the Phase 5 row in `05-relay-recovery-improvement-tdd-plan.md` beats older experiment docs if they conflict
- benchmark outputs from this session beat prior recorded numbers once captured

### 4. Session classification

`implementation-ready`

Reason:

- the missing seam is narrow and localized in the Dart resume lifecycle path
- likely code-entry files and direct tests are known
- no new Go behavior is required for the minimum Phase 5 deferral

### 5. Exact problem statement

Current repo evidence shows that `handleAppResumed()` still awaits follow-up work after `performImmediateHealthCheck()`: push-registration retry, direct inbox drain, group topic rejoin, and group inbox drain all remain on the same awaited foreground path even when the relay is already healthy again. The Go recovery result already includes personal discoverability re-registration, so the remaining latency is in Dart-side post-recovery follow-up rather than in the relay recovery seam itself.

What must improve:

- on the successful resume path, foreground recovery should complete once relay reservation and required personal discoverability are restored
- push registration, direct inbox follow-up, and group continuity work should continue in the background instead of blocking the successful foreground completion point
- deferred follow-up failures must not incorrectly mark the app degraded again

What must stay unchanged:

- the successful recovery still requires the relay to be healthy first
- direct inbox drain still happens; it is not removed
- group rejoin and group inbox replay still happen and keep their ordering
- healthy resume and degraded-but-not-yet-recovered behavior stay honest

### 6. Files and repos to inspect next

Production:

- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/core/services/p2p_service_impl.dart`

Direct tests:

- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`
- `test/core/services/fake_p2p_service.dart`
- `test/performance/benchmark_background_resume_test.dart`

Evidence docs / harnesses:

- `integration_test/benchmark_background_resume_harness.dart`
- `integration_test/benchmark_relay_recovery_harness.dart`
- `integration_test/background_reconnect_test.dart`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-5-foreground-critical-path-results.md`

### 7. Existing tests covering this area

Already present:

- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
  - resume calls bridge health check, immediate health check, direct inbox drain, and resume retry hooks
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - group rejoin / drain / retry ordering and gate behavior
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
  - group recovery callbacks stay ordered
- `test/core/lifecycle/background_reconnect_smoke_test.dart`
  - successful resume recovery returns online without host restart
- `test/performance/benchmark_background_resume_test.dart`
  - degraded resume emits recovery-start and background-resume badge timing

Missing or insufficient:

- a RED regression that proves `handleAppResumed()` can finish before a long noncritical follow-up future resolves once recovery is already healthy
- a RED regression that proves deferred group continuity work still starts and remains gated even after foreground completion returns
- a RED regression that proves deferred follow-up failure does not bounce the recovered state back to degraded

### 8. Regression/tests to add first

Add first:

- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
  - foreground completion does not wait for a slow deferred resume follow-up once recovery is healthy
  - deferred follow-up failure is isolated from the recovered state
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - deferred group recovery still starts after foreground completion and keeps the gate active until it settles
- `test/performance/benchmark_background_resume_test.dart`
  - background-resume completion still emits the recovery badge correctly after the deferred foreground path change

Why this proves the seam:

- the missing behavior is in the Dart resume lifecycle, not in Go relay recovery
- these tests can pin the exact deferral contract before any production change

### 9. Step-by-step implementation plan

1. Add the Phase 5 RED tests in the lifecycle / benchmark suites.
2. Run the new targeted Flutter tests alone and confirm they fail on current code.
3. Patch `lib/core/lifecycle/handle_app_resumed.dart` minimally to:
   - detect when the health check has already restored the relay
   - move only the noncritical push / inbox / group follow-up lane onto a fault-isolated background future
   - keep ordering inside that deferred lane
   - keep the completion event honest for the faster foreground path
4. Re-run the targeted lifecycle and benchmark tests until green.
5. Re-run the broader direct lifecycle suite and smoke test that cover resume recovery behavior.
6. Run the required benchmark commands and named gate for Phase 5.
7. Refresh `05-phase-5-foreground-critical-path-results.md` with before/after numbers versus Phase 0 rerun and a keep/revert recommendation.
8. Stop after closure/reporting.

Stop rule:

- if the RED tests cannot be made green without redesigning the whole resume scheduler or breaking group/inbox continuity guarantees, stop and mark the session blocked instead of broadening scope

### 10. Risks and edge cases

- foreground completion must not claim success before the relay is actually healthy
- deferred direct inbox drain must not silently disappear or create duplicate drain behavior
- deferred group recovery must not leave admin-only operations ungated while replay is still in progress
- deferred push-registration failure must stay isolated and not surface as a false transport recovery failure
- concurrent resumes must not spin duplicate deferred lanes that corrupt continuity work

### 11. Exact tests and gates to run

RED-first direct tests:

```bash
flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'foreground completion does not wait for slow deferred resume follow-up once recovery is healthy'
flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'deferred resume follow-up failure does not bounce recovered state'
flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'deferred group recovery still starts after foreground completion and keeps the gate active'
```

Direct verification after the fix:

```bash
flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart
flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart
flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart
flutter test test/core/lifecycle/background_reconnect_smoke_test.dart
flutter test test/performance/benchmark_background_resume_test.dart
```

Required benchmark / regression commands:

```bash
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_background_resume_harness.dart
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_relay_recovery_harness.dart
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/background_reconnect_test.dart
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport
```

### 12. Known-failure interpretation

- `integration_test/background_reconnect_test.dart` has previously built and then reported `All tests skipped.` on the named simulator; treat another clean skip the same way unless the command now fails or crashes
- benchmark deltas alone do not justify acceptance; the Phase 5 promotion rule from the source doc still controls the keep/revert recommendation
- if the direct lifecycle suites prove the deferred path is safe but the benchmark win is too small, report that honestly instead of stretching the recommendation

### 13. Done criteria

- the new RED lifecycle regressions exist, fail first, and are green after the bounded fix
- the direct Flutter suites listed above pass
- the required benchmark/regression commands above are executed and their outcomes recorded
- `05-phase-5-foreground-critical-path-results.md` is refreshed with current before/after numbers and a keep/revert recommendation

### 14. Scope guard

- do not add Phase 6 semantics, optimistic "sendable" behavior, or badge-policy changes
- do not retune Go relay budgets, AutoRelay cadence, or reservation timing
- do not refactor all resume callbacks into a new task framework
- do not remove inbox/group follow-up; only defer it after successful recovery
- do not treat unrelated local transport edits as acceptable evidence that Phase 5 already happened

### 15. Accepted differences / intentionally out of scope

- if the benchmark results still say Phase 5 should be reverted, that is an acceptable session outcome
- the plan assumes Go-side personal discoverability remains the recovery prerequisite and does not reopen that seam in this session
- remaining non-group resume sweeps outside the named push / inbox / group lane stay as-is unless a direct test proves they are part of the measured bottleneck

### 16. Dependency impact

- later relay-recovery experiments should use this session’s refreshed Phase 5 results doc to decide whether lifecycle deferral meaningfully moved the remaining bottleneck
- if the final recommendation remains revert, later work should not assume the Dart critical-path trim is a proven win to stack on top of

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- no extra benchmark suites beyond the named Phase 5 set unless a direct failure proves necessary

## Accepted differences intentionally left unchanged

- the plan keeps the direct inbox and group continuation implementation style intact instead of introducing a brand-new scheduler abstraction
- the session remains a Dart-first lifecycle fix even though the existing Go recovery metrics are reused in the evidence

## Exact docs/files used as evidence

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-5-foreground-critical-path-session-breakdown.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results-rerun-2026-04-17.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-section-8-instrumentation-first-results-2026-04-17.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-results.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/core/services/p2p_service_impl.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`
- `test/core/services/fake_p2p_service.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `integration_test/benchmark_background_resume_harness.dart`
- `integration_test/benchmark_relay_recovery_harness.dart`
- `integration_test/background_reconnect_test.dart`

## Why the plan is safe or unsafe to implement now

The plan is safe to implement now because the source doc already defines the exact Phase 5 hypothesis, the current code pinpoints a narrow post-health-check seam, and the missing proof can be added with direct lifecycle RED tests before any production change. The scope guard blocks Go retuning and product-semantics drift, so the session can stop cleanly once the benchmark verdict is known.
