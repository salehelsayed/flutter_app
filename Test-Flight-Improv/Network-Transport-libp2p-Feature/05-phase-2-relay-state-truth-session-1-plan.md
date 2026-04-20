# Phase 2 Relay-State Truth Session 1 Plan

## Final verdict

Sufficient with bounded local fallback. The breakdown entry is execution-safe, the current repo already contains most Phase 2 seams, and the missing work is a narrow Dart-side regression plus the required evidence refresh.

## Final plan

### 1. Real scope

This session changes only the Phase 2 relay-state truth seam:

- add the missing Dart RED regression first for duplicate outage detection after a `relay:state` degradation push
- make the minimum `P2PServiceImpl` change needed so a push-established outage does not emit an extra poll-detected outage start
- rerun the Phase 2 direct tests, required benchmarks, and required regression gates
- refresh `05-phase-2-relay-state-truth-results.md` with before/after numbers against `05-phase-0-relay-recovery-baseline-results.md`

This session does not:

- add Phase 3, 3a, 4, 5, or 6 behavior
- redesign host refresh / reservation-path behavior
- change Go production logic unless a direct Phase 2 seam proves missing
- widen into unrelated startup, inbox-budget, or group-recovery work

### 2. Closure bar

Session 1 is good enough only if:

- the new RED regression is added before the production fix and fails on current code
- the bounded fix makes that regression pass without broadening scope
- the existing Go reservation-opened / reservation-ended tests still pass
- the required benchmark and regression commands are rerun and recorded
- the refreshed Phase 2 results doc compares before/after numbers to the frozen Phase 0 baseline and ends with a truthful keep/revert recommendation

### 3. Source of truth

- Active plan doc: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- Session breakdown: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-2-relay-state-truth-session-breakdown.md`
- Benchmark inventory: `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- Baseline comparison doc: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`
- Named gates: `Test-Flight-Improv/test-gate-definitions.md`

On disagreement:

- current code and current tests beat stale prose
- the named source doc above beats the older Phase 2 results doc if they conflict
- benchmark outputs from this session beat prior recorded numbers once captured

### 4. Session classification

`implementation-ready`

Reason:

- the missing seam is narrow and already localized in `P2PServiceImpl`
- likely code-entry files and direct tests are known
- the user requested immediate execution rather than further decomposition

### 5. Exact problem statement

Current repo evidence shows that a `relay:state` degradation push can start immediate recovery, but the service still emits a second poll-detected outage start once `_performHealthCheck()` re-polls `node:status`. That makes the Phase 2 truth seam noisy and undermines the experiment contract that relay-state push, not poll fallback, should establish the outage once that push has already fired.

What must improve:

- once a `relay:state` degradation push establishes the outage, the same outage must not emit another `RELAY_OUTAGE_TIMING phase='detected'` event with `detectionSource='poll'`

What must stay unchanged:

- relay-state push still updates `NodeState` immediately
- push-driven recovery completion still works
- Go reservation truth stays unchanged
- later-phase recovery modes and structured fields stay untouched

### 6. Files and repos to inspect next

Production:

- `lib/core/services/p2p_service_impl.dart`

Direct tests:

- `test/performance/benchmark_relay_recovery_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `go-mknoon/node/relay_session_test.go`
- `go-mknoon/bridge/bridge_test.go`

Evidence docs:

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-2-relay-state-truth-results.md`

### 7. Existing tests covering this area

Already present:

- Go reservation-opened and reservation-ended state-machine coverage in `go-mknoon/node/relay_session_test.go`
- Go relay-state emission coverage in `go-mknoon/node/autorelay_metrics_test.go`
- Dart relay-state push state update coverage in `test/core/services/p2p_service_impl_test.dart`
- recovery badge/source coverage in `test/performance/benchmark_relay_recovery_test.dart` and `test/performance/benchmark_background_resume_test.dart`

Missing or insufficient:

- a direct RED regression that proves a push-established outage does not get a second poll-detected `detected` event before recovery completes

### 8. Regression/tests to add first

Add first:

- `test/performance/benchmark_relay_recovery_test.dart`
  - new Phase 2 regression asserting a `relay:state` degradation push yields exactly one `RELAY_OUTAGE_TIMING phase='detected'` event and that its `detectionSource` remains `push` even after the follow-on health check starts

Why this proves the seam:

- it isolates the exact overlap between push-established relay truth and the later poll path without dragging in later-phase behavior

### 9. Step-by-step implementation plan

1. Add the missing relay-recovery benchmark/unit regression first.
2. Run the new targeted test alone and confirm it fails on current code.
3. Patch `lib/core/services/p2p_service_impl.dart` minimally so a currently open outage does not emit a duplicate poll-detected start event after a push-established degradation.
4. Re-run the targeted Dart suites until green.
5. Re-run the targeted Go suites already named by the Phase 2 source doc.
6. Run the required benchmark commands and required regression gates for Phase 2.
7. Refresh `05-phase-2-relay-state-truth-results.md` with before/after numbers versus Phase 0 and record the keep/revert recommendation honestly.
8. Stop after closure/reporting.

Stop rule:

- if the RED test cannot be made green without widening scope into later-phase behavior, stop and mark the session blocked instead of redesigning recovery

### 10. Risks and edge cases

- suppressing duplicate detected events must not suppress the first valid poll-detected outage when no push event fired
- recovery completion badges must keep their existing source attribution
- asynchronous unawaited health checks can race with push callbacks, so the fix must key off an existing outage boundary rather than timing guesses

### 11. Exact tests and gates to run

RED-first direct tests:

```bash
flutter test test/performance/benchmark_relay_recovery_test.dart --plain-name "C7: relay-state push does not emit duplicate poll detection before recovery"
```

Direct verification after the fix:

```bash
flutter test test/performance/benchmark_relay_recovery_test.dart
flutter test test/core/services/p2p_service_impl_test.dart
cd go-mknoon && go test ./node -run 'TestRelaySession_(TransitionsToReservedOnReservationOpened|TransitionsToDegradedOnReservationEnded)$' -count=1
cd go-mknoon && go test ./bridge -run '^TestRelayReconnect_ReturnsStructuredRecoveryFields$' -count=1
```

Required benchmark / regression commands:

```bash
dart run integration_test/scripts/run_benchmark_suite.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 --scenarios C
dart run integration_test/scripts/run_benchmark_suite.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 --scenarios BR
dart run integration_test/scripts/run_benchmark_suite.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 --scenarios M
flutter test integration_test/benchmark_relay_recovery_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
flutter test integration_test/benchmark_background_resume_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
flutter test integration_test/background_reconnect_test.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh benchmark
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh benchmark-sim
dart run integration_test/scripts/run_routing_smoke_e2e.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

### 12. Known-failure interpretation

- `background_reconnect_test.dart` has recently built and then reported `All tests skipped.` on the named simulator in prior Phase 1/2 reruns; treat another clean skip the same way unless the command now fails or crashes
- benchmark deltas alone do not justify acceptance; the source doc’s Phase 2 promotion rule still controls the keep/revert recommendation

### 13. Done criteria

- the new RED regression exists, failed first, and is green after the bounded fix
- the direct Dart and Go suites listed above pass
- the required benchmark/regression commands above are executed and their outcomes recorded
- `05-phase-2-relay-state-truth-results.md` is refreshed with current before/after numbers and a keep/revert recommendation

### 14. Scope guard

- do not add new recovery modes
- do not touch host refresh / restart semantics
- do not add direct reservation, reservation racing, or coalescing redesign
- do not convert this into a larger cleanup of relay instrumentation wording

### 15. Accepted differences / intentionally out of scope

- existing repo comments that mention later phases stay untouched unless the bounded fix requires a tiny accuracy update in the same file
- if the benchmark results still say Phase 2 should be reverted, that is an acceptable session outcome

### 16. Dependency impact

- later relay-recovery experiments should use this session’s refreshed results doc as the updated comparison point for whether push-truth cleanup alone moved the needle
- no later session should be started from this plan if the final experiment recommendation remains revert

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- no extra direct suite beyond the named tests unless a failure proves necessary

## Accepted differences intentionally left unchanged

- existing Go Phase 2 RED coverage is reused rather than rewritten
- the session may legitimately conclude that the experiment still should not be promoted

## Exact docs/files used as evidence

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-2-relay-state-truth-session-breakdown.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/core/services/p2p_service_impl.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/performance/benchmark_relay_recovery_test.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `go-mknoon/node/relay_session_test.go`
- `go-mknoon/node/autorelay_metrics_test.go`
- `go-mknoon/bridge/bridge_test.go`

## Why the plan is safe to implement now

- it narrows execution to one already-localized seam
- it enforces RED-first work and explicit benchmark reruns
- it blocks later-phase scope creep while still allowing an honest revert recommendation if the numbers stay flat
