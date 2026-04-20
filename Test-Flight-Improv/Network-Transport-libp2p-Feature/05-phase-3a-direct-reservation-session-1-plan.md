# Phase 3a Direct Reservation Session 1 Plan

## Final verdict

Sufficient with bounded local fallback. The breakdown entry is execution-safe, current repo evidence already exposes the Phase 3a attribution fields, and the remaining gap is a narrow Go-side relay recovery seam plus the required evidence refresh.

## Final plan

### 1. Real scope

This session changes only the Phase 3a direct-reservation seam:

- add the missing Phase 3a RED tests first for direct reservation after warm dial, event-driven circuit-address completion, multi-relay winner attribution, and poll-fallback observability
- make the minimum Go change needed so in-place relay recovery issues direct reservation attempts after successful warm dials
- make the minimum waiting change needed so recovery can finish from `EvtLocalAddressesUpdated` / circuit-address updates when that event path completes, while preserving the existing polling fallback
- verify the existing attribution fields remain exposed through bridge, Dart, and benchmark harnesses; patch exposure only if a concrete gap is found
- rerun the exact Phase 3a direct tests, benchmarks, and regression gates
- refresh `05-phase-3a-direct-reservation-results.md` with before/after numbers against `05-phase-0-relay-recovery-baseline-results.md`, the winning reservation path, and a truthful keep/revert recommendation

This session does not:

- add Phase 4, 5, or 6 behavior
- add recovery coalescing redesign, native lifecycle prewarm, QUIC session-ticket persistence, proactive TTL refresh, or critical-path trimming
- redesign AutoRelay internals beyond the bounded Phase 3a direct reservation and event-driven completion seam
- treat unrelated local Phase 2 worktree edits as part of the Phase 3a acceptance case

### 2. Closure bar

Session 1 is good enough only if:

- the new Phase 3a RED tests are added before the production fix and fail on current code
- the bounded Go change makes those regressions pass without broadening scope
- the in-place recovery result clearly distinguishes `direct_reserve` vs `poll_fallback`, and reports the winning relay peer when one exists
- recovery remains correct when direct reservation fails or event-driven completion does not arrive in time
- the required direct Go/Dart suites pass
- the required benchmark and regression commands are rerun and recorded
- the refreshed Phase 3a results doc compares before/after numbers to the frozen Phase 0 baseline and ends with a keep/revert recommendation tied to the measured promotion rule

### 3. Source of truth

- Active source doc: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- Session breakdown: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-session-breakdown.md`
- Benchmark inventory: `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- Baseline comparison doc: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`
- Instrumentation-first reference: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-section-8-instrumentation-first-results-2026-04-17.md`
- Named gates: `Test-Flight-Improv/test-gate-definitions.md`

On disagreement:

- current code and current tests beat stale prose
- `test-gate-definitions.md` is the execution source of truth for named gates
- the Phase 3a row in `05-relay-recovery-improvement-tdd-plan.md` beats older experiment docs if they conflict
- benchmark outputs from this session beat prior recorded numbers once captured

### 4. Session classification

`implementation-ready`

Reason:

- the missing seam is narrow and localized in Go relay recovery
- likely code-entry files and direct tests are known
- current repo evidence already exposes the attribution fields, so the work is a bounded behavior gap rather than a larger instrumentation project

### 5. Exact problem statement

Current repo evidence shows that in-place relay recovery warms relay connections and then waits for `waitForCircuitAddress(10s)`, which is a polling-only fallback path. The repo already exposes Phase 3a attribution fields, but the refresh path still does not attempt a direct relay reservation RPC after warm dial, and it cannot finish off an address-update event path without the built-in 200ms polling cadence.

What must improve:

- after successful warm dial, recovery should attempt direct reservation instead of only waiting for AutoRelay timing
- when a circuit address becomes visible through `EvtLocalAddressesUpdated`, recovery should complete from that event path without adding an unnecessary polling tail
- the result must report whether `direct_reserve` or `poll_fallback` won and which relay peer won when multiple relays race

What must stay unchanged:

- poll fallback remains correct when direct reservation or event-driven completion does not win
- watchdog restart / later recovery modes stay untouched
- attribution fields already exposed through bridge, Dart, and benchmark harnesses remain additive and stable

### 6. Files and repos to inspect next

Production:

- `go-mknoon/node/node.go`
- `go-mknoon/bridge/bridge.go`

Direct tests:

- `go-mknoon/node/node_test.go`
- `go-mknoon/bridge/bridge_test.go`
- `test/performance/benchmark_relay_recovery_test.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `test/core/services/p2p_service_impl_test.dart`

Evidence docs:

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-results.md`

### 7. Existing tests covering this area

Already present:

- `go-mknoon/node/node_test.go`
  - in-place refresh preserves host
  - in-place refresh preserves pubsub maps
  - in-place refresh reports timing and reservation-path fields
- `go-mknoon/bridge/bridge_test.go`
  - structured recovery fields exist on `relay:reconnect`
- `test/performance/benchmark_relay_recovery_test.dart`
  - recovered outage events expose relay timing and reservation-path fields
- `test/performance/benchmark_background_resume_test.dart`
  - recovered background-resume events expose relay timing and reservation-path fields

Missing or insufficient:

- a direct RED regression that proves refresh issues a reservation RPC after warm dial
- a direct RED regression that proves event-driven address updates can satisfy recovery without requiring the polling-only wait path
- a direct RED regression for multiple relays where the first successful reservation path wins and is attributed once
- a direct RED regression that proves poll fallback remains observable when direct reservation fails

### 8. Regression/tests to add first

Add first:

- `go-mknoon/node/node_test.go`
  - direct reservation starts after successful warm dial
  - event-driven circuit-address completion can satisfy recovery without using the poll wait hook
  - first successful relay wins and populates `reservationWinnerPeer`
  - direct-reservation failure falls back to `poll_fallback` observably

Why this proves the seam:

- the missing behavior is in Go relay recovery, not in Flutter wiring
- these tests can pin the precise reservation / event / fallback contract before any production change

### 9. Step-by-step implementation plan

1. Add the Phase 3a RED tests in `go-mknoon/node/node_test.go`.
2. Run the new targeted Go tests alone and confirm they fail on current code.
3. Patch `go-mknoon/node/node.go` minimally to:
   - warm configured relays
   - issue direct reservation attempts after successful warm dials
   - wait on event-driven circuit-address updates first when possible
   - preserve and report fallback behavior when that path does not complete
4. Re-run the targeted Go tests until green.
5. Re-run the existing bridge and Dart direct suites that cover the exposed recovery fields.
6. Run the required benchmark commands and named gates for Phase 3a.
7. Refresh `05-phase-3a-direct-reservation-results.md` with before/after numbers versus Phase 0, the winning reservation path, and a keep/revert recommendation.
8. Stop after closure/reporting.

Stop rule:

- if the RED tests cannot be made green without redesigning AutoRelay publication or expanding into Phase 4+ behavior, stop and mark the session blocked instead of broadening scope

### 10. Risks and edge cases

- direct reservation success must not double-count recovery success or duplicate side effects when AutoRelay later converges on the same relay
- event-driven completion must not race into a false positive before a circuit address is actually present
- multi-relay attempts must not produce ambiguous winner attribution or duplicate registration/recovery bookkeeping
- a direct reservation failure must not break the existing recovery fallback path
- benchmark attribution must stay stable even if the headline latency does not improve enough to keep the phase

### 11. Exact tests and gates to run

RED-first direct tests:

```bash
cd go-mknoon && go test ./node -run 'TestRefreshRelaySession_(DirectReservationAfterWarmDial|EventDrivenCircuitAddressUpdateCompletesRecovery|MultipleRelaysFirstSuccessWins|DirectReservationFailureFallsBackToPoll)$' -count=1
```

Direct verification after the fix:

```bash
cd go-mknoon && go test ./node -run 'TestRefreshRelaySession_' -count=1
cd go-mknoon && go test ./bridge -run '^TestRelayReconnect_ReturnsStructuredRecoveryFields$' -count=1
flutter test test/performance/benchmark_relay_recovery_test.dart
flutter test test/performance/benchmark_background_resume_test.dart
flutter test test/core/services/p2p_service_impl_test.dart
```

Required benchmark / regression commands:

```bash
dart run integration_test/scripts/run_benchmark_suite.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 --scenarios C
dart run integration_test/scripts/run_benchmark_suite.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 --scenarios BR
dart run integration_test/scripts/run_benchmark_suite.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 --scenarios M
flutter test integration_test/benchmark_relay_recovery_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
flutter test integration_test/benchmark_background_resume_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
flutter test integration_test/benchmark_time_to_online_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
flutter test integration_test/background_reconnect_test.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh benchmark
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh benchmark-sim
```

### 12. Known-failure interpretation

- `integration_test/background_reconnect_test.dart` has previously built and then reported `All tests skipped.` on the named simulator; treat another clean skip the same way unless the command now fails or crashes
- benchmark deltas alone do not justify acceptance; the Phase 3a promotion rule from the source doc still controls the keep/revert recommendation
- if attribution fields are already present and tests pass, do not invent extra exposure work to make the session look larger

### 13. Done criteria

- the new RED Go regressions exist, fail first, and are green after the bounded fix
- the direct Go, bridge, and Dart suites listed above pass
- the required benchmark/regression commands above are executed and their outcomes recorded
- `05-phase-3a-direct-reservation-results.md` is refreshed with current before/after numbers, winning reservation path, and a keep/revert recommendation

### 14. Scope guard

- do not add Phase 4 coalescing, storm prevention, or broad refresh singleflight work
- do not add native lifecycle prewarm, QUIC session-ticket persistence, proactive TTL refresh, or deferred foreground/background work
- do not redesign AutoRelay address publication beyond what is minimally required for direct reservation attribution and event-driven completion
- do not treat unrelated local Phase 2 edits as acceptable evidence that Phase 3a already happened

### 15. Accepted differences / intentionally out of scope

- existing attribution field exposure is reused if already correct
- if the benchmark results still say Phase 3a should be reverted, that is an acceptable session outcome
- later-phase work may still be needed even if Phase 3a is measurable, but this session does not pre-authorize any of it

### 16. Dependency impact

- later relay-recovery experiments should use this session’s refreshed Phase 3a results doc as the comparison point for whether direct reservation changed the bottleneck
- if the final recommendation remains revert, later phases should not assume direct reservation is a proven win to stack on top of

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- no extra benchmark suites beyond the named Phase 3a set unless a direct failure proves necessary

## Accepted differences intentionally left unchanged

- the plan assumes the existing Dart and harness exposure for Phase 3a fields is sufficient unless direct verification proves otherwise
- the session remains a Go-first behavior fix even though Dart tests and benchmarks verify the end-to-end reporting

## Exact docs/files used as evidence

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3a-direct-reservation-session-breakdown.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-section-8-instrumentation-first-results-2026-04-17.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `go-mknoon/node/node.go`
- `go-mknoon/node/node_test.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`
- `lib/core/services/p2p_service_impl.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/performance/benchmark_relay_recovery_test.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `integration_test/benchmark_relay_recovery_harness.dart`
- `integration_test/benchmark_background_resume_harness.dart`
- `integration_test/benchmark_time_to_online_harness.dart`

## Why the plan is safe to implement now

- it narrows execution to one already-localized relay recovery seam
- it enforces RED-first work and explicit benchmark reruns
- it blocks later-phase drift while still allowing an honest revert recommendation if the numbers stay flat
