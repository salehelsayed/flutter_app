# Phase 3a Direct Reservation Session Breakdown

## Recommended plan count

1

## Decomposition artifact

- artifact path: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-session-breakdown.md`
- proposal or source doc path: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- scoped phase: `Phase 3a. Direct reservation after warm dial`
- downstream workflow rule:
  - detailed planning happens one session at a time
  - execution must stay inside the Phase 3a contract from the source doc
  - no Phase 4 or later production work may be added in this rollout

## Overall closure bar

This Phase 3a-only rollout is good enough only if all of the following are true:

- RED tests for the Phase 3a seam land first and fail before the production change
- the in-place recovery path issues direct reservation attempts after successful warm dials
- recovery can finish from event-driven circuit-address updates when they arrive, without requiring a polling-only tail in the successful path
- the existing poll fallback remains correct and observable when direct reservation or event-driven completion does not win
- Phase 3a attribution remains exposed end-to-end for:
  - `relayWarmMs`
  - `reserveRpcMs`
  - `circuitAddressWaitMs`
  - `reservationPath`
  - `reservationWinnerPeer`
- the required direct tests, benchmarks, and regression gates from the Phase 3a source row are rerun and recorded
- the experiment results markdown compares before vs after numbers against `05-phase-0-relay-recovery-baseline-results.md`, records the winning reservation path, and ends with an explicit keep/revert recommendation

## Source of truth

- Proposal: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- Benchmark inventory: `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- Baseline comparison doc: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`
- Instrumentation-first reference: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-section-8-instrumentation-first-results-2026-04-17.md`
- Named gates: `Test-Flight-Improv/test-gate-definitions.md`
- Current Go seam:
  - `go-mknoon/node/node.go`
  - `go-mknoon/node/node_test.go`
  - `go-mknoon/node/relay_session.go`
  - `go-mknoon/bridge/bridge.go`
  - `go-mknoon/bridge/bridge_test.go`
- Current Dart / benchmark seam:
  - `lib/core/services/p2p_service_impl.dart`
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/performance/benchmark_relay_recovery_test.dart`
  - `test/performance/benchmark_background_resume_test.dart`
  - `integration_test/benchmark_relay_recovery_harness.dart`
  - `integration_test/benchmark_background_resume_harness.dart`
  - `integration_test/benchmark_time_to_online_harness.dart`

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `1` | `Phase 3a direct reservation after warm dial` | `implementation-ready` | `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-session-1-plan.md` | none | `accepted_with_explicit_follow_up` | Completed with the new RED-first direct-reservation regressions, the minimum Go recovery seam update, the required benchmark/regression reruns, and a refreshed results doc. Explicit follow-up: `05-phase-3a-direct-reservation-results.md` recommends revert / do not promote because the Phase 3a promotion bar was not met. |

## Ordered session breakdown

### Session 1

- title: Phase 3a direct reservation after warm dial
- session id: 1
- session classification: implementation-ready
- intended plan file: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-session-1-plan.md`
- exact scope:
  - add the missing Phase 3a RED tests first for direct reservation after warm dial, event-driven circuit-address completion, multi-relay winner attribution, and poll-fallback observability
  - implement only the minimum Go changes needed to issue direct reservation attempts after warm relay dials
  - implement only the minimum waiting logic needed so recovery can finish from `EvtLocalAddressesUpdated` / circuit-address updates when those updates arrive in time, while preserving the existing poll fallback
  - verify the Phase 3a attribution fields remain exposed end-to-end and add any missing field exposure only if current code or tests prove a gap
  - rerun the exact direct tests, benchmarks, and regression gates required by the Phase 3a contract
  - refresh `05-phase-3a-direct-reservation-results.md` with before/after numbers versus `05-phase-0-relay-recovery-baseline-results.md`, the winning reservation path, and a keep/revert recommendation
- why it is its own session:
  - the RED tests, the bounded Go seam, and the experiment evidence all target one relay-recovery hypothesis and should stop together once the Phase 3a verdict is known
- likely code-entry files:
  - `go-mknoon/node/node.go`
  - `go-mknoon/node/node_test.go`
  - `go-mknoon/bridge/bridge.go`
  - `go-mknoon/bridge/bridge_test.go`
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-results.md`
- likely direct tests/regressions:
  - `cd go-mknoon && go test ./node -run 'TestRefreshRelaySession_' -count=1`
  - `cd go-mknoon && go test ./bridge -run '^TestRelayReconnect_ReturnsStructuredRecoveryFields$' -count=1`
  - `flutter test test/performance/benchmark_relay_recovery_test.dart`
  - `flutter test test/performance/benchmark_background_resume_test.dart`
  - `flutter test test/core/services/p2p_service_impl_test.dart`
- likely named gates:
  - `transport`
- matrix/closure docs to update when done:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-results.md`
  - this breakdown artifact ledger
- dependency on earlier sessions:
  - none
- execution-safety corrections that must be carried into the session plan:
  - treat `05-relay-recovery-improvement-tdd-plan.md` Phase 3a as the only active scope, even if nearby code or docs mention later-phase experiments
  - RED tests must land before the fix
  - do not add Phase 4 coalescing, native lifecycle prewarm, QUIC session-ticket persistence, proactive TTL refresh, or foreground/background critical-path trimming from later phases
  - do not widen the implementation into a larger AutoRelay redesign beyond direct reservation attempts plus event-driven completion and fallback observability
  - results must be reported honestly even if the recommendation remains revert

## Why this is not fewer sessions

- The user explicitly scoped this rollout to Phase 3a only, and the remaining work is one bounded relay-reservation seam plus its evidence update.

## Why this is not more sessions

- Splitting RED-test work from the bounded Go change would add bookkeeping without changing the gate or closure bar.
- The benchmark/reporting step is inseparable from the experiment verdict because the user explicitly asked to stop after reporting.

## Regression and gate contract

- RED tests first for the missing Phase 3a seam.
- Required benchmark/regression commands for this session:
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_relay_recovery_harness.dart`
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_background_resume_harness.dart`
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_time_to_online_harness.dart`
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/background_reconnect_test.dart`
  - `FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport`

## Matrix update contract

- Create and reuse `05-phase-3a-direct-reservation-results.md` as the stable experiment record.
- This session owns both the evidence refresh and the final keep/revert recommendation.

## Downstream execution path

- Session 1 should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- Existing attribution field exposure in Go, bridge, Dart, and benchmark harnesses is reused rather than rewritten if it already satisfies the Phase 3a contract.
- Existing unrelated local worktree edits are treated as background context, not as proof that Phase 3a should stack on top of another experiment.
- This rollout does not create any new follow-on rollout docs beyond the refreshed Phase 3a results record and this breakdown artifact.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-section-8-instrumentation-first-results-2026-04-17.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `go-mknoon/node/node.go`
- `go-mknoon/node/node_test.go`
- `go-mknoon/node/relay_session.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`
- `lib/core/services/p2p_service_impl.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/performance/benchmark_relay_recovery_test.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `integration_test/benchmark_relay_recovery_harness.dart`
- `integration_test/benchmark_background_resume_harness.dart`
- `integration_test/benchmark_time_to_online_harness.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The source doc already defines one bounded experiment with exact RED targets, benchmark obligations, and a clear stop rule.
- Current repo evidence shows the instrumentation/attribution seam already exists, so the safe next step is a narrow direct-reservation gap closure instead of a larger redesign.
- The breakdown explicitly blocks later-phase drift while preserving the requirement to report an honest revert recommendation if the measured win does not materialize.

## Program rollout ledger

- Breakdown artifact used:
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-session-breakdown.md`
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
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-results.md`
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-session-breakdown.md`
- Final blocker note:
  Phase 3a session scope is complete, but the refreshed results doc records a revert / do not promote recommendation because the winning reservation path stayed `poll_fallback` and neither `C-Sim p50` nor `BR-Sim-2` improved by the required `1500ms`.
