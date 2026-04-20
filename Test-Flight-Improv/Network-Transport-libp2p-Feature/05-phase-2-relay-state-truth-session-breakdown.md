# Decomposition Artifact Updated

## Recommended plan count

1

## Decomposition artifact

- artifact path: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-2-relay-state-truth-session-breakdown.md`
- proposal or source doc path: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- scoped phase: `Phase 2. Relay-state truth and push-driven recovery completion`
- downstream workflow rule:
  - detailed planning happens one session at a time
  - execution must stay inside the Phase 2 contract from the source doc
  - no Phase 3 or later production work may be added in this rollout

## Overall closure bar

This Phase 2-only rollout is good enough only if all of the following are true:

- relay reservation truth stays the authoritative health signal across Go and Dart
- degraded recovery no longer records duplicate poll-detected outage starts once a `relay:state` degradation push has already established the outage
- Dart can reach recovery completion from `relay:state` push without requiring a second poll-only truth change in the covered unit seam
- the required direct tests, benchmarks, and regression gates from the source doc are rerun and recorded
- the experiment results markdown compares before vs after numbers against `05-phase-0-relay-recovery-baseline-results.md` and ends with an explicit keep/revert recommendation

## Source of truth

- Proposal: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- Benchmark inventory: `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- Baseline comparison doc: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`
- Existing experiment doc to refresh: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-2-relay-state-truth-results.md`
- Named gates: `Test-Flight-Improv/test-gate-definitions.md`
- Current Dart seam:
  - `lib/core/services/p2p_service_impl.dart`
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/performance/benchmark_relay_recovery_test.dart`
  - `test/performance/benchmark_background_resume_test.dart`
- Current Go seam:
  - `go-mknoon/node/relay_session.go`
  - `go-mknoon/node/relay_session_test.go`
  - `go-mknoon/node/autorelay_metrics_test.go`
  - `go-mknoon/bridge/bridge.go`
  - `go-mknoon/bridge/events.go`
  - `go-mknoon/bridge/bridge_test.go`

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `1` | `Phase 2 relay-state push truth and experiment rerun` | `implementation-ready` | `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-2-relay-state-truth-session-1-plan.md` | none | `accepted_with_explicit_follow_up` | Completed with the new `C7` RED-first regression, the minimum Dart-side duplicate-detection fix, the required direct tests, the required benchmark/regression reruns, and a refreshed results doc. Explicit follow-up: `05-phase-2-relay-state-truth-results.md` recommends revert / do not promote because the Phase 2 promotion bar was not met. |

## Ordered session breakdown

### Session 1

- title: Phase 2 relay-state push truth and experiment rerun
- session id: 1
- session classification: implementation-ready
- intended plan file: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-2-relay-state-truth-session-1-plan.md`
- exact scope:
  - add the missing Phase 2 RED test coverage first for the Dart seam where a `relay:state` degradation push can currently be followed by an extra poll-detected outage event
  - keep the Go reservation-opened and reservation-ended truth tests in scope by rerunning the existing Go suites, not by broadening the implementation
  - implement only the minimum production change needed to stop duplicate poll-detected outage starts after a push-established outage while preserving push-driven recovery completion
  - rerun the exact direct tests, benchmarks, and regression gates required by the Phase 2 contract
  - refresh `05-phase-2-relay-state-truth-results.md` with before/after numbers versus `05-phase-0-relay-recovery-baseline-results.md` and a keep/revert recommendation
- why it is its own session:
  - the missing regression, the bounded fix, and the experiment evidence all target one relay-recovery seam and should stop together once the Phase 2 verdict is known
- likely code-entry files:
  - `lib/core/services/p2p_service_impl.dart`
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/performance/benchmark_relay_recovery_test.dart`
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-2-relay-state-truth-results.md`
- likely direct tests/regressions:
  - `flutter test test/performance/benchmark_relay_recovery_test.dart`
  - `flutter test test/core/services/p2p_service_impl_test.dart`
  - `cd go-mknoon && go test ./node -run 'TestRelaySession_(TransitionsToReservedOnReservationOpened|TransitionsToDegradedOnReservationEnded)$' -count=1`
  - `cd go-mknoon && go test ./bridge -run '^TestRelayReconnect_ReturnsStructuredRecoveryFields$' -count=1`
- likely named gates:
  - `transport`
  - `benchmark`
  - `benchmark-sim`
- matrix/closure docs to update when done:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-2-relay-state-truth-results.md`
  - this breakdown artifact ledger
- dependency on earlier sessions:
  - none
- execution-safety corrections that must be carried into the session plan:
  - treat `05-relay-recovery-improvement-tdd-plan.md` Phase 2 as the only active scope, even if nearby code contains later-phase experiments
  - RED test must land before the fix
  - the fix must not broaden into host-refresh, reservation-path racing, coalescing redesign, or deferred foreground/background work from Phases 3-5
  - the experiment doc must report measured results honestly even if the recommendation remains revert

## Why this is not fewer sessions

- The user explicitly scoped this rollout to Phase 2 only, and the remaining work is one bounded relay-truth seam plus its evidence update.

## Why this is not more sessions

- Splitting RED-test work from the bounded fix would add bookkeeping without changing the gate or closure bar.
- The benchmark/reporting step is inseparable from the experiment verdict because the user explicitly asked to stop after reporting.

## Regression and gate contract

- RED test first for the missing Phase 2 Dart seam.
- Re-run the existing Go reservation-opened / reservation-ended tests because the source Phase 2 contract names them.
- Required benchmark/regression commands for this session:
  - `dart run integration_test/scripts/run_benchmark_suite.dart -d <DEVICE_ID> --scenarios C`
  - `dart run integration_test/scripts/run_benchmark_suite.dart -d <DEVICE_ID> --scenarios BR`
  - `dart run integration_test/scripts/run_benchmark_suite.dart -d <DEVICE_ID> --scenarios M`
  - `flutter test integration_test/benchmark_relay_recovery_harness.dart -d <DEVICE_ID>`
  - `flutter test integration_test/benchmark_background_resume_harness.dart -d <DEVICE_ID>`
  - `flutter test integration_test/background_reconnect_test.dart -d <DEVICE_ID>`
  - `./scripts/run_test_gates.sh transport`
  - `./scripts/run_test_gates.sh benchmark`
  - `./scripts/run_test_gates.sh benchmark-sim`
  - `dart run integration_test/scripts/run_routing_smoke_e2e.dart -d <ALICE_ID>,<BOB_ID>`

## Matrix update contract

- Reuse `05-phase-2-relay-state-truth-results.md` as the stable experiment record.
- This session owns both the evidence refresh and the final keep/revert recommendation.

## Downstream execution path

- Session 1 should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- This rollout does not attempt to make Phase 2 pass its promotion bar up front; it only implements the minimum bounded fix and then measures the outcome honestly.
- Existing later-phase code/comments in the repo are treated as background context, not execution scope for this session.
- This rollout does not create a new closure doc beyond the refreshed Phase 2 results record and this breakdown artifact.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-2-relay-state-truth-results.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/core/services/p2p_service_impl.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/performance/benchmark_relay_recovery_test.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `go-mknoon/node/relay_session.go`
- `go-mknoon/node/relay_session_test.go`
- `go-mknoon/node/autorelay_metrics_test.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/events.go`
- `go-mknoon/bridge/bridge_test.go`

## Why the decomposition is safe to send into downstream planning/execution

- The source doc already defines one bounded experiment with exact RED targets, benchmark obligations, and a clear stop rule.
- Existing code and tests show the repo already has most Phase 2 plumbing, so the safe next step is a narrow gap-closing session rather than a larger redesign.
- The breakdown explicitly blocks Phase 3+ drift and requires the results doc to stay honest even if the answer is still "revert."

## Program rollout ledger

- Breakdown artifact used:
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-2-relay-state-truth-session-breakdown.md`
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
  `1`
- Execution fallbacks used:
  `1`
- Closure fallbacks used:
  `1`
- Final acceptance fallbacks used:
  `1`
- Final program acceptance verdict:
  `accepted_with_explicit_follow_up`
- Stable docs updated:
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-2-relay-state-truth-results.md`
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-2-relay-state-truth-session-breakdown.md`
- Final blocker note:
  Phase 2 session scope is complete, but the refreshed results doc records a revert / do not promote recommendation because the required benchmark gate was not met.
