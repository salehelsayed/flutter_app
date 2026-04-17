# Phase 3b Foreground AutoRelay Cadence Session Breakdown

## Recommended plan count

1

## Decomposition artifact

- artifact path: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3b-foreground-autorelay-cadence-session-breakdown.md`
- proposal or source doc path: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- scoped phase: `Phase 3b. Foreground AutoRelay cadence and timeout policy`
- downstream workflow rule:
  - detailed planning happens one session at a time
  - execution must stay inside the Phase 3b contract from the source doc
  - start from the instrumentation-first baseline, not from a later experiment
  - no Phase 4 or later production work may be added in this rollout

## Overall closure bar

This Phase 3b-only rollout is good enough only if all of the following are true:

- RED tests for the Phase 3b seam land first and fail before the production change
- foreground recovery uses a lower AutoRelay retry cadence than the current baseline values
- `RefreshRelaySession()` warms configured relays in parallel so one slow warm dial does not serialize the whole foreground attempt
- foreground resume recovery uses a shorter relay dial timeout than the general relay dial path
- the existing long circuit-address wait remains available only as fallback safety behavior when the short foreground path does not win
- Phase 3b attribution remains exposed end-to-end for:
  - `relayWarmParallelism`
  - `foregroundRecoveryPath`
  - `foregroundRelayDialTimeoutMs`
  - `autorelayRetryCadenceMs`
  - `circuitAddressWaitMs`
- the required direct tests, benchmarks, and regression gates from the Phase 3b source row are rerun and recorded
- the experiment results markdown compares before vs after numbers against `05-section-8-instrumentation-first-results-2026-04-17.md`, records the actual cadence and timeout values used, states whether foreground success beat background fallback, and ends with an explicit keep/revert recommendation

## Source of truth

- Proposal: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- Benchmark inventory: `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- Baseline comparison doc: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-section-8-instrumentation-first-results-2026-04-17.md`
- Historical freeze reference: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`
- Named gates: `Test-Flight-Improv/test-gate-definitions.md`
- Current Go seam:
  - `go-mknoon/node/config.go`
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
| `1` | `Phase 3b foreground AutoRelay cadence and timeout policy` | `implementation-ready` | `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3b-foreground-autorelay-cadence-session-1-plan.md` | none | `accepted` | Completed with RED-first Go/Dart coverage, the minimum foreground cadence/timeout retune, rebuilt iOS gomobile bindings, the required benchmark/regression reruns, and a refreshed results doc. Final values stayed at `1s` AutoRelay cadence + `3s` foreground dial timeout, foreground success won all observed degraded recoveries, the results doc recommends `keep`, and the current cadence retune is documented as host-global AutoRelay behavior rather than a strictly foreground-only policy. |

## Ordered session breakdown

### Session 1

- title: Phase 3b foreground AutoRelay cadence and timeout policy
- session id: 1
- session classification: implementation-ready
- intended plan file: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3b-foreground-autorelay-cadence-session-1-plan.md`
- exact scope:
  - add the missing Phase 3b RED tests first for lower foreground retry cadence, parallel relay warm-up, shorter foreground relay dial timeout, fallback safety behavior, and attribution exposure
  - implement only the minimum Go changes needed to retune the foreground recovery experiment to `1s` cadence and `3s` foreground dial timeout unless direct tests prove those values too flaky
  - if direct tests or simulator reruns prove the starting values too flaky, relax only inside this phase to `2s` cadence and/or `4s` foreground dial timeout and record the final values used
  - keep the existing long `10s` circuit-address wait only as fallback safety behavior; do not delete it
  - verify the required Phase 3b fields remain exposed through bridge, Dart, and benchmark harnesses, and add any missing exposure only if current code or tests prove a gap
  - rerun the exact direct tests, benchmarks, and regression gates required by the Phase 3b contract
  - refresh `05-phase-3b-foreground-autorelay-cadence-results.md` with before/after numbers versus `05-section-8-instrumentation-first-results-2026-04-17.md`, the actual cadence and timeout values used, whether foreground success beat background fallback, and a keep/revert recommendation
- why it is its own session:
  - the RED tests, the bounded Go seam, and the experiment evidence all target one timing-policy hypothesis and should stop together once the Phase 3b verdict is known
- likely code-entry files:
  - `go-mknoon/node/config.go`
  - `go-mknoon/node/node.go`
  - `go-mknoon/node/node_test.go`
  - `go-mknoon/bridge/bridge.go`
  - `go-mknoon/bridge/bridge_test.go`
  - `lib/core/services/p2p_service_impl.dart`
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/performance/benchmark_relay_recovery_test.dart`
  - `test/performance/benchmark_background_resume_test.dart`
- likely direct tests / regressions:
  - `cd go-mknoon && go test ./node -run 'TestRefreshRelaySession_(UsesForegroundCadenceAndDialTimeout|WarmsRelaysInParallel|ForegroundFallbackKeepsLongCircuitWait|ReportsForegroundRecoveryAttribution)$' -count=1`
  - `cd go-mknoon && go test ./node -run 'TestRefreshRelaySession_' -count=1`
  - `cd go-mknoon && go test ./bridge -run '^TestRelayReconnect_ReturnsStructuredRecoveryFields$' -count=1`
  - `flutter test test/performance/benchmark_relay_recovery_test.dart`
  - `flutter test test/performance/benchmark_background_resume_test.dart`
  - `flutter test test/core/services/p2p_service_impl_test.dart`
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_relay_recovery_harness.dart`
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_background_resume_harness.dart`
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_time_to_online_harness.dart`
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/background_reconnect_test.dart`
  - `FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport`
- named gates:
  - `transport`
- dependency state:
  - no explicit repo-local dependency; execute against the current instrumentation-first baseline state in the branch
- matrix / closure docs this session must update:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3b-foreground-autorelay-cadence-results.md`
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3b-foreground-autorelay-cadence-session-breakdown.md`
- scope guard:
  - do not include Phase 4 or later work
  - do not add native lifecycle prewarm, QUIC session-ticket persistence, or proactive TTL refresh
  - do not redesign watchdog restart, recovery coalescing, or later foreground-critical-path work
  - do not treat prior phase result docs as proof that later experiments already landed in production code

## Why this is not fewer sessions

- The user explicitly scoped this rollout to Phase 3b only, and the remaining work is one bounded foreground cadence / timeout experiment plus its evidence update.

## Why this is not more sessions

- Splitting RED-test work from the bounded Go change would add bookkeeping without changing the gate or closure bar.
- The benchmark/reporting step is inseparable from the experiment verdict because the user explicitly asked to stop after reporting.

## Regression and gate contract

- RED tests first for the missing Phase 3b seam.
- Required benchmark/regression commands for this session:
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_relay_recovery_harness.dart`
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_background_resume_harness.dart`
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_time_to_online_harness.dart`
  - `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/background_reconnect_test.dart`
  - `FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport`

## Matrix update contract

- Create and reuse `05-phase-3b-foreground-autorelay-cadence-results.md` as the stable experiment record.
- This session owns both the evidence refresh and the final keep/revert recommendation.

## Intended downstream execution path

- Session 1 should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- Existing instrumentation-first attribution fields from section 8 remain the starting point instead of being rewritten.
- Existing unrelated local worktree edits are treated as background context, not as proof that Phase 3b should stack on later experiments.
- The Phase 3b cadence retune currently configures the host's global AutoRelay behavior; it is not isolated to a strictly foreground-only AutoRelay policy in the landed code.
- This rollout does not create any new follow-on rollout docs beyond the refreshed Phase 3b results record and this breakdown artifact.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-section-8-instrumentation-first-results-2026-04-17.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `go-mknoon/node/config.go`
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

- The source doc already defines one bounded foreground cadence / timeout experiment with exact RED targets, benchmark obligations, and a clear stop rule.
- Current repo evidence shows the live recovery seam is still essentially the instrumentation baseline: sequential warm-up, `5s` AutoRelay cadence, and a long poll-style circuit wait.
- The breakdown explicitly blocks later-phase drift while preserving the requirement to report an honest revert recommendation if the measured win does not materialize.

## Program rollout ledger

- Breakdown artifact used:
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3b-foreground-autorelay-cadence-session-breakdown.md`
- Sessions processed:
  `1/1`
- Sessions accepted:
  `1`
- Sessions accepted_with_explicit_follow_up:
  `0`
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
  `closed`
- Stable docs updated:
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3b-foreground-autorelay-cadence-results.md`
  `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3b-foreground-autorelay-cadence-session-breakdown.md`
- Why the rollout is safe to complete:
  The bounded Phase 3b RED tests are green, the required benchmarks/regressions were rerun on the rebuilt iOS bridge binary, the `1s` / `3s` starting values were stable enough to keep, and the measured promotion bar was exceeded with the foreground-success path winning every observed degraded recovery sample.
