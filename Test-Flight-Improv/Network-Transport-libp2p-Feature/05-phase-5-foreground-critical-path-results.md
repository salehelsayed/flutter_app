# Phase 5 Foreground Critical Path Results

Source of truth:
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`

Run date:
- Local: `2026-04-17` (`Europe/Berlin`)

Branch:
- measured branch: `timing-phase5-new`
- baseline commit: `2c78ae30f76db5faa2d98a667b10b622c6c309d9` (current accepted Phase `3b` baseline)

Devices:
- primary simulator: `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`)

Scope executed:
- add the missing Phase `5` RED tests first and prove they fail against the untouched Phase `3b` baseline
- make only the minimum Dart lifecycle deferral needed so a degraded resume that becomes healthy no longer blocks on noncritical push / inbox / group follow-up
- keep inbox, registration, and group continuity work alive in a fault-isolated deferred lane instead of deleting it
- rerun the exact Phase `5` direct suites, device benchmarks, reconnect regression, and `transport` gate
- stop after reporting the Phase `5` verdict

Execution notes:
- no Go relay timing, reservation, or AutoRelay cadence changes were made in this phase
- the Phase `5` seam is observable in the benchmark output via:
  - `sim_background_resume_handler_ms = 1256ms`
  - `sim_background_resume_deferred_noncritical_follow_up = true`
- raw logs were captured at:
  - `/tmp/phase5_br_2026-04-17.log`
  - `/tmp/phase5_c_2026-04-17.log`
  - `/tmp/phase5_background_reconnect_2026-04-17.log`
  - `/tmp/phase5_transport_gate_2026-04-17.log`

## RED-First Evidence

Targeted RED tests were added first in a clean temporary worktree at the accepted Phase `3b` baseline commit, with only the new test-side changes applied:

- `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'foreground completion does not wait for slow deferred resume follow-up once recovery is healthy'`
  - failed with `TimeoutException` because the pre-fix foreground path still waited on the blocked deferred follow-up
- `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'deferred resume follow-up failure does not bounce recovered state'`
  - failed because the pre-fix resume result became `null` after the drain failure instead of staying recovered
- `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'deferred group recovery still starts after foreground completion and keeps the gate active'`
  - failed with `TimeoutException` because the pre-fix group recovery work still blocked foreground completion

Those same three tests passed on the patched Phase `5` branch.

## Commands Run

Direct verification:

```bash
flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart test/core/lifecycle/background_reconnect_smoke_test.dart test/performance/benchmark_background_resume_test.dart
```

Primary comparison harnesses:

```bash
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_background_resume_harness.dart > /tmp/phase5_br_2026-04-17.log 2>&1
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_relay_recovery_harness.dart > /tmp/phase5_c_2026-04-17.log 2>&1
```

Transport regressions:

```bash
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/background_reconnect_test.dart > /tmp/phase5_background_reconnect_2026-04-17.log 2>&1
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport > /tmp/phase5_transport_gate_2026-04-17.log 2>&1
```

## Benchmark Comparison Against Accepted Phase 3b Baseline

Accepted Phase `3b` source:
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-3b-foreground-autorelay-cadence-results.md`

| Metric | Phase 3b | Phase 5 run | Delta |
| --- | ---: | ---: | ---: |
| `BR-Sim healthy` | `100ms` | `96ms` | `-4ms` (`-4.0%`) |
| `BR-Sim degraded` | `1251ms` | `1255ms` | `+4ms` (`+0.3%`) |
| `BR-Sim extended healthy` | `100ms` | `94ms` | `-6ms` (`-6.0%`) |
| `C-Sim p50` | `455ms` | `1258ms` | `+803ms` (`+176.5%`) |
| `C-Sim p95` | `851ms` | `1357ms` | `+506ms` (`+59.5%`) |
| `Recovery badge` | `1753ms` | `1769ms` | `+16ms` (`+0.9%`) |
| `Circuit-address wait` | `1407ms` | `1609ms` | `+202ms` (`+14.4%`) |

Interpretation against the current accepted baseline:
- degraded resume did **not** improve on top of Phase `3b`
- the already-online resume paths stayed slightly faster
- the accepted Phase `3b` baseline remains better on the degraded `C-Sim` headline metrics
- the measured bottleneck stayed inside relay refresh / circuit-address wait, not inside the new deferred follow-up lane

## Benchmark Comparison Against Frozen Phase 0 Baseline

Frozen Phase `0` source:
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results-rerun-2026-04-17.md`

| Metric | Phase 0 rerun | Phase 5 run | Delta |
| --- | ---: | ---: | ---: |
| `BR-Sim healthy` | `94ms` | `96ms` | `+2ms` (`+2.1%`) |
| `BR-Sim degraded` | `9114ms` | `1255ms` | `-7859ms` (`-86.2%`) |
| `BR-Sim extended healthy` | `105ms` | `94ms` | `-11ms` (`-10.5%`) |
| `C-Sim detection` | `502ms` | `503ms` | `+1ms` (`+0.2%`) |
| `C-Sim recovery` | `9100ms` | `1269ms` | `-7831ms` (`-86.1%`) |
| `C-Sim recovery badge` | `9598ms` | `1769ms` | `-7829ms` (`-81.6%`) |
| `C-Sim p50` | `9105ms` | `1258ms` | `-7847ms` (`-86.2%`) |
| `C-Sim p95` | `9510ms` | `1357ms` | `-8153ms` (`-85.7%`) |

Interpretation against the frozen historical baseline:
- Phase `5` is still dramatically better than the old `~9s` Phase `0` branch state
- that improvement is inherited from the already-accepted earlier phases, especially Phase `3b`
- Phase `5` itself does not add a measurable win on top of the accepted baseline

## Phase 5 Seam Confirmation

Phase `5`-specific rows from the new background-resume log:

```text
[BENCHMARK] sim_background_resume_degraded_ms = 1255ms
[BENCHMARK] sim_background_resume_handler_ms = 1256ms
[BENCHMARK] sim_background_resume_deferred_noncritical_follow_up = true
[BENCHMARK] sim_background_resume_foreground_recovery_path = foreground_success
[BENCHMARK] sim_background_resume_circuit_address_wait_ms = 1610ms
```

Interpretation:
- the bounded deferral path is definitely active
- once the health check restored relay health, `handleAppResumed()` stopped waiting on the noncritical follow-up lane
- the remaining degraded-resume cost stayed dominated by relay refresh / circuit-address wait, so trimming the noncritical lane did not move the headline bottleneck

## Correctness And Regression Outcome

Direct suites:
- passed: `app_lifecycle_recovery_test.dart`
- passed: `handle_app_resumed_group_recovery_test.dart`
- passed: `handle_app_resumed_group_stuck_sending_test.dart`
- passed: `handle_app_resumed_group_inbox_retry_test.dart`
- passed: `background_reconnect_smoke_test.dart`
- passed: `benchmark_background_resume_test.dart`

Device and named-gate regressions:
- `integration_test/background_reconnect_test.dart`
  - clean simulator skip again (`All tests skipped.`), matching earlier phases rather than a new regression
- `transport` gate
  - `wifi_relay_fallback_smoke_test.dart`: pass
  - `transport_e2e_test.dart`: pass
  - `media_stable_id_smoke_test.dart`: pass
  - `B1` inbox fallback: pass
  - `E2` empty-message rejection: pass

Correctness verdict:
- post-resume correctness stayed green within the available Phase `5` evidence
- inbox, registration, and group continuity protections remained intact in the direct lifecycle suites and the `transport` gate
- the only caveat is unchanged from earlier phases: `background_reconnect_test.dart` still clean-skipped on the named simulator, so it did not add a fresh send-timing row

## Phase 5 Verdict

Did degraded resume improve on top of Phase `3b`?
- `no`

Did post-resume correctness stay green?
- `yes`, within the evidence above and with the same `background_reconnect_test.dart` skip caveat

Recommendation:
- **revert / do not promote Phase `5`**

Reason:
- the Phase `5` promotion bar was not met because degraded resume failed to improve on top of the accepted Phase `3b` baseline
- `BR-Sim degraded` regressed slightly (`1251ms` -> `1255ms`)
- `C-Sim p50` / `p95` regressed materially versus the accepted Phase `3b` report (`455ms` / `851ms` -> `1258ms` / `1357ms`)
- the new deferred lane is live and functionally safe, but the measured bottleneck remained upstream in relay recovery / circuit-address wait
- the Phase `5` change is useful as a validated seam, not as a promotable improvement on top of the current accepted baseline
