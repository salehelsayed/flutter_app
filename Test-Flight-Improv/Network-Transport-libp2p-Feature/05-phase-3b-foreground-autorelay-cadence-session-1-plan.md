# Phase 3b Foreground AutoRelay Cadence Session 1 Plan

## Final verdict

Sufficient with bounded local fallback. The breakdown entry is execution-safe, the current repo is still close to the instrumentation-first baseline, and the remaining gap is a narrow Go timing-policy change plus the required evidence refresh.

## Final plan

### 1. Real scope

This session changes only the Phase 3b foreground cadence / timeout seam:

- add the missing Phase 3b RED tests first for lower foreground retry cadence, parallel relay warm-up, shorter foreground relay dial timeout, fallback safety behavior, and attribution exposure
- make the minimum Go change needed so in-place relay recovery uses the Phase 3b starting values of `autorelay.WithBackoff(1 * time.Second)`, `autorelay.WithMinInterval(1 * time.Second)`, and a `3 * time.Second` foreground relay dial timeout unless direct tests prove those values too flaky
- if those starting values are too flaky, relax only inside this phase to `2s` cadence and/or `4s` foreground dial timeout and record the final values used
- keep the existing `10s` circuit-address wait only as fallback safety behavior instead of deleting it
- verify the Phase 3b attribution fields remain exposed through bridge, Dart, and benchmark harnesses; patch exposure only if a concrete gap is found
- rerun the exact Phase 3b direct tests, benchmarks, and regression gates
- refresh `05-phase-3b-foreground-autorelay-cadence-results.md` with before/after numbers against `05-section-8-instrumentation-first-results-2026-04-17.md`, the final cadence and timeout values used, whether foreground success beat background fallback, and a truthful keep/revert recommendation

This session does not:

- add Phase 4, 5, or 6 behavior
- add native lifecycle prewarm, QUIC session-ticket persistence, proactive TTL refresh, or critical-path trimming
- redesign watchdog restart, recovery coalescing, or reservation semantics
- treat unrelated local worktree edits or later phase docs as part of the Phase 3b acceptance case

### 2. Closure bar

Session 1 is good enough only if:

- the new Phase 3b RED tests are added before the production fix and fail on current code
- the bounded Go change makes those regressions pass without broadening scope
- the in-place recovery result clearly distinguishes `foreground_success` vs `background_fallback` and reports the configured cadence and timeout values used
- fallback safety remains correct when the short foreground attempt does not win
- the required direct Go/Dart suites pass
- the required benchmark and regression commands are rerun and recorded
- the refreshed Phase 3b results doc compares before/after numbers to the instrumentation-first baseline and ends with a keep/revert recommendation tied to the measured promotion rule

### 3. Source of truth

- Active source doc: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- Session breakdown: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3b-foreground-autorelay-cadence-session-breakdown.md`
- Benchmark inventory: `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- Baseline comparison doc: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-section-8-instrumentation-first-results-2026-04-17.md`
- Historical freeze reference: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`
- Named gates: `Test-Flight-Improv/test-gate-definitions.md`

On disagreement:

- current code and current tests beat stale prose
- `test-gate-definitions.md` is the execution source of truth for named gates
- the Phase 3b row in `05-relay-recovery-improvement-tdd-plan.md` beats older experiment docs if they conflict
- benchmark outputs from this session beat prior recorded numbers once captured

### 4. Session classification

`implementation-ready`

Reason:

- the missing seam is narrow and localized in Go relay recovery timing policy
- likely code-entry files and direct tests are known
- the current repo already exposes most section 8 attribution fields, so the work is a bounded behavior/timing gap rather than a larger instrumentation project

### 5. Exact problem statement

Current repo evidence shows that in-place relay recovery still uses the instrumentation-first baseline behavior: relay warm-up is sequential, the host is configured with `5s` AutoRelay retry cadence, and the refresh path waits on a long poll-style circuit-address window. The repo already exposes the section 8 timing fields, but it does not yet distinguish a foreground-success path from the fallback path, it does not report the configured Phase 3b cadence/timeout values, and it does not parallelize relay warming during foreground recovery.

What must improve:

- foreground recovery should use a lower AutoRelay retry cadence than the current baseline configuration
- relay warm-up during `RefreshRelaySession()` should run in parallel so one slow relay does not serialize the whole attempt
- foreground resume recovery should use a shorter relay dial timeout than the general `DialTimeout`
- the short foreground path should be allowed to win first, while the existing long wait remains available as fallback safety behavior
- the result must report `relayWarmParallelism`, `foregroundRecoveryPath`, `foregroundRelayDialTimeoutMs`, `autorelayRetryCadenceMs`, and `circuitAddressWaitMs`

What must stay unchanged:

- watchdog restart / later recovery modes stay untouched
- no lifecycle prewarm, QUIC ticket persistence, proactive TTL refresh, or Phase 4 coalescing work is introduced
- attribution fields already exposed through bridge, Dart, and benchmark harnesses remain additive and stable

### 6. Files and repos to inspect next

Production:

- `go-mknoon/node/config.go`
- `go-mknoon/node/node.go`
- `go-mknoon/bridge/bridge.go`

Direct tests:

- `go-mknoon/node/node_test.go`
- `go-mknoon/bridge/bridge_test.go`
- `test/performance/benchmark_relay_recovery_test.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `test/core/services/p2p_service_impl_test.dart`

Evidence docs:

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3b-foreground-autorelay-cadence-results.md`

### 7. Existing tests covering this area

Already present:

- `go-mknoon/node/node_test.go`
  - in-place refresh preserves host
  - in-place refresh preserves pubsub maps
  - in-place refresh reports baseline timing and reservation-path fields
- `go-mknoon/bridge/bridge_test.go`
  - structured recovery fields exist on `relay:reconnect`
- `test/performance/benchmark_relay_recovery_test.dart`
  - recovered outage events expose relay timing and reservation-path fields
- `test/performance/benchmark_background_resume_test.dart`
  - recovered background-resume events expose relay timing and reservation-path fields

Missing or insufficient:

- a RED regression that proves foreground recovery reports a lower cadence and shorter dial timeout than the baseline
- a RED regression that proves `RefreshRelaySession()` warms relays in parallel
- a RED regression that proves the short foreground path falls back to the existing long wait without getting stuck or misreporting success
- bridge / Dart coverage for the new Phase 3b attribution fields if they are not already exposed

### 8. Implementation sketch

1. Add Go RED tests for:
   - configured foreground cadence / timeout values
   - parallel relay warm-up during `RefreshRelaySession()`
   - fallback safety path and `foregroundRecoveryPath` attribution
   - end-to-end Phase 3b attribution exposure
2. Implement the minimum Go changes:
   - introduce Phase 3b constants for default cadence, foreground cadence, and foreground dial timeout
   - retune host AutoRelay configuration to the foreground cadence values for this experiment
   - warm refresh relays in parallel with the shorter foreground dial timeout
   - split the circuit-address wait into a short foreground phase plus the remaining fallback budget while keeping total fallback safety intact
   - populate the new attribution fields on `RecoveryResult`
3. Patch bridge / Dart / benchmark exposure only if tests prove a concrete gap.
4. Rerun the named direct tests and the required simulator benchmarks / transport gate.
5. Refresh the Phase 3b results doc and then stop.

Stop rule:

- if the RED tests cannot be made green without redesigning AutoRelay publication, adding Phase 4 coalescing, or expanding into later-phase behavior, stop and mark the session blocked instead of broadening scope

### 9. Risks and edge cases

- short foreground values may be too flaky on simulator runs; if so, relax only to `2s` cadence and/or `4s` timeout and record the final values used
- parallel warm-up must not race into duplicate reporting or hide the last error when all relays fail
- fallback safety must not extend the total wait beyond the existing safety envelope
- benchmark attribution must stay stable even if the headline latency does not improve enough to keep the phase

### 10. Exact tests and gates to run

RED-first direct tests:

```bash
cd go-mknoon && go test ./node -run 'TestRefreshRelaySession_(UsesForegroundCadenceAndDialTimeout|WarmsRelaysInParallel|ForegroundFallbackKeepsLongCircuitWait|ReportsForegroundRecoveryAttribution)$' -count=1
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
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_relay_recovery_harness.dart
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_background_resume_harness.dart
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_time_to_online_harness.dart
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/background_reconnect_test.dart
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport
```

### 11. Known-failure interpretation

- if the starting values `1s` / `3s` make the direct tests or simulator harnesses flaky, relax only inside this phase and record the final values used in the results doc
- `integration_test/background_reconnect_test.dart` has previously built and then reported `All tests skipped.` on the named simulator; treat another clean skip the same way unless the command now fails or crashes
- benchmark deltas alone do not justify acceptance; the Phase 3b promotion rule from the source doc still controls the keep/revert recommendation

### 12. Done criteria

- the new RED Go regressions exist, fail first, and are green after the bounded fix
- the direct Go, bridge, and Dart suites listed above pass
- the required benchmark/regression commands above are executed and their outcomes recorded
- `05-phase-3b-foreground-autorelay-cadence-results.md` is refreshed with current before/after numbers, the actual cadence and timeout values used, whether foreground success beat background fallback, and a keep/revert recommendation

### 13. Scope guard

- do not add Phase 4 recovery coalescing, storm prevention, or broader singleflight redesign
- do not add native lifecycle prewarm, QUIC session-ticket persistence, proactive TTL refresh, or later foreground-critical-path deferral work
- do not redesign reservation semantics or later event-driven completion work beyond what is minimally required for the Phase 3b timing-policy seam
- do not treat unrelated local worktree docs as acceptable evidence that Phase 3b already happened

### 14. Accepted differences / intentionally out of scope

- existing section 8 attribution field exposure is reused if already correct
- if the benchmark results still say Phase 3b should be reverted, that is an acceptable session outcome
- later-phase work may still be needed even if Phase 3b is measurable, but this session does not pre-authorize any of it

### 15. Dependency impact

- later relay-recovery experiments should use this session’s refreshed Phase 3b results doc as the comparison point for whether cadence / timeout tuning moved the bottleneck
- if the final recommendation remains revert, later phases should not assume Phase 3b is a proven win to stack on top of

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- no extra benchmark suites beyond the named Phase 3b set unless a direct failure proves necessary

## Accepted differences intentionally left unchanged

- the plan assumes the existing Dart and harness exposure for section 8 fields is sufficient unless direct verification proves otherwise
- the session remains a Go-first timing-policy change even though Dart tests and benchmarks verify the end-to-end reporting

## Exact docs/files used as evidence

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3b-foreground-autorelay-cadence-session-breakdown.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/03b-benchmark-test-inventory.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-section-8-instrumentation-first-results-2026-04-17.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `go-mknoon/node/config.go`
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
