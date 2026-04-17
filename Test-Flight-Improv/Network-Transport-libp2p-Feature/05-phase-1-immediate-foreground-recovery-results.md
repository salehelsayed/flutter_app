# Phase 1 Immediate Foreground Recovery Trigger

Source of truth: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`

Run date:
- Local: `2026-04-16` (`Europe/Berlin`)

Devices:
- Primary simulator: `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`)
- Two-sim smoke: Alice `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`), Bob `iPhone 17` (`5BA69F1C-B112-47BE-B1FF-8C1003728C8F`)

Scope executed:
- Phase `1` only
- start from the saved instrumentation baseline in
  `05-phase-0-relay-recovery-baseline-results.md`
- Flutter-only change
- minimum resume-time recovery trigger experiment only

Production files changed:
- `lib/core/services/p2p_service_impl.dart`

RED tests added first:
- `test/performance/benchmark_background_resume_test.dart`
  - `BR8`: degraded resume triggers relay refresh immediately on app resume
  - `BR9`: healthy resume does not trigger relay refresh
  - `BR10`: degraded resume does not wait for `node:status` before refresh
  - `BR11`: repeated degraded resume signals coalesce to one refresh

## Direct Test Verification

Direct suites rerun after implementation:

```bash
flutter test test/performance/benchmark_background_resume_test.dart
flutter test test/core/lifecycle/connectivity_lifecycle_test.dart
flutter test test/core/services/p2p_service_impl_test.dart
```

Result:
- all three commands passed

## Exact Benchmark / Regression Commands Run

```bash
dart run integration_test/scripts/run_benchmark_suite.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 --scenarios BR
dart run integration_test/scripts/run_benchmark_suite.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 --scenarios M
flutter test integration_test/background_reconnect_test.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh benchmark
dart run integration_test/scripts/run_routing_smoke_e2e.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Execution notes:
- `background_reconnect_test.dart` built and ran but reported `All tests skipped.` on this simulator invocation.
- `transport` gate passed.
- `benchmark` gate passed.
- the two-simulator routing smoke was stopped after `S4` and `X1` were recorded, matching the Phase `0` baseline-freeze scope.
- raw logs were captured under `/tmp/relay_phase1_immediate_resume_2026-04-16/`

## Benchmark Results

### BR-Sim

Phase `1` rerun:
- `sim_background_resume_healthy_ms = 99ms`
- `sim_background_resume_healthy_source = resume_check`
- `sim_background_resume_degraded_ms = 9128ms`
- `sim_background_resume_degraded_source = health_check_poll`
- `sim_background_resume_recovery_start_source = relay_state_push`
- `sim_background_resume_recovery_source = relay_state_push`
- `sim_background_resume_reused_host = true`
- `sim_background_resume_coalesced_recovery_requests = 0`
- `sim_background_resume_relay_refresh_ms = 9572ms`
- `sim_background_resume_personal_reregister_ms = 50ms`
- `sim_background_resume_extended_ms = 103ms`

Comparison against the saved Phase `0` freeze:
- `BR-Sim-1` healthy resume: `101ms` -> `99ms` (`-2ms`, `-2.0%`)
- `BR-Sim-2` degraded resume: `9103ms` -> `9128ms` (`+25ms`, `+0.3%`)
- `BR-Sim-3` extended resume: `101ms` -> `103ms` (`+2ms`, `+2.0%`)

Comparison against the instrumentation baseline in Phase `0` section `8`:
- `BR-Sim-1` healthy resume: `117ms` -> `99ms` (`-18ms`, `-15.4%`)
- `BR-Sim-2` degraded resume: `9292ms` -> `9128ms` (`-164ms`, `-1.8%`)
- `BR-Sim-3` extended resume: `102ms` -> `103ms` (`+1ms`, `+1.0%`)
- `relayRefreshMs`: `9745ms` -> `9572ms` (`-173ms`, `-1.8%`)
- `personalReregisterMs`: `42ms` -> `50ms` (`+8ms`, `+19.0%`)

Interpretation:
- healthy resume stayed comfortably under the Phase `1` `<150ms` guard
- degraded resume did **not** improve by the required `>=1000ms`
- the winning degraded-resume badge source stayed `health_check_poll`
- recovery start still appeared as `relay_state_push`, not `resume_trigger`

### M-Sim

Phase `1` rerun:
- `sim_time_to_online_badge_ms = 168ms`
- `sim_time_to_online_source = relay_state_push`
- `sim_recovery_to_online_badge_ms = 9623ms`
- `sim_online_source_distribution relay_state_push=5`
- `sim_time_to_online_ms p50=152ms p95=156ms (n=5)`

Comparison against the saved Phase `0` freeze:
- `sim_time_to_online_badge_ms`: `248ms` -> `168ms` (`-80ms`, `-32.3%`)
- `sim_recovery_to_online_badge_ms`: `9611ms` -> `9623ms` (`+12ms`, `+0.1%`)
- `sim_online_source_distribution`: unchanged at `relay_state_push=5`
- `sim_time_to_online_ms p50`: `169ms` -> `152ms` (`-17ms`, `-10.1%`)
- `sim_time_to_online_ms p95`: `197ms` -> `156ms` (`-41ms`, `-20.8%`)

Instrumentation-baseline note:
- Phase `0` section `8` did not record a separate `M-Sim` rerun, so the source-distribution comparison here is against the saved Phase `0` freeze only.

Interpretation:
- Phase `1` did not shift `M-Sim-3` source distribution off `relay_state_push`
- recovery-to-online time remained effectively unchanged

## Two-Simulator Regression Smoke

Captured from the Phase `1` rerun:
- `S4: PASS — send=152ms path=direct e2e=3579ms`
- `X1: PASS — restart: Alice=516ms Bob=519ms send=91ms e2e=3314ms`

Comparison against the saved Phase `0` freeze:
- `S4` send: `135ms` -> `152ms` (`+17ms`, `+12.6%`)
- `S4` e2e: `3562ms` -> `3579ms` (`+17ms`, `+0.5%`)
- `X1` Alice restart: `516ms` -> `516ms` (`0ms`, `0.0%`)
- `X1` Bob restart: `514ms` -> `519ms` (`+5ms`, `+1.0%`)
- `X1` send: `119ms` -> `91ms` (`-28ms`, `-23.5%`)
- `X1` e2e: `3304ms` -> `3314ms` (`+10ms`, `+0.3%`)

Interpretation:
- the reconnect smokes stayed in the same range as the frozen baseline
- no obvious transport regression was introduced by the experiment

## Phase 1 Verdict

Promotion rule from the source-of-truth plan:
- keep only if `BR-Sim-2` improves by at least `1000ms`
- healthy resume must stay under `150ms`

Result:
- healthy resume passed: `99ms`
- degraded resume failed: `9128ms` is worse than the saved Phase `0` freeze and only `164ms` better than the instrumentation baseline
- `M-Sim-3` source distribution did not move off `relay_state_push`

Evidence-backed conclusion:
- Phase `1` did not move the measured bottleneck on device
- the new resume fast-path is real in host tests, but on-device recovery is still already being started from the relay-state push path before foreground resume can become the winning trigger
- this phase therefore fails the experiment promotion bar

## Keep / Revert Recommendation

Recommendation: **revert / do not promote Phase `1` as currently implemented.**

Reason:
- it does not deliver the required `BR-Sim-2` win
- it does not change the observed source distribution in the targeted `M-Sim-3` measurement
- it keeps transport behavior stable, which means the experiment is safe to discard without losing a proven performance win

Suggested next step from this evidence:
- move to the next relay-recovery hypothesis rather than layering more code onto this resume-trigger experiment
