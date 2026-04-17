# Phase 2 Relay-State Truth and Push-Driven Recovery Completion

Source of truth: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`

Run date:
- Local: `2026-04-16` (`Europe/Berlin`)

Devices:
- Primary simulator: `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`)
- Two-sim smoke: Alice `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`), Bob `iPhone 17` (`5BA69F1C-B112-47BE-B1FF-8C1003728C8F`)

Scope executed:
- Phase `2` only
- start from the saved Phase `0` baseline freeze in
  `05-phase-0-relay-recovery-baseline-results.md`
- do not include Phase `3` or later production work
- Flutter-only minimum change to move degraded recovery off relay poll truth where possible

Production files changed:
- `lib/core/services/p2p_service_impl.dart`

RED tests added first:
- `test/core/services/p2p_service_impl_test.dart`
  - `relay state degradation push starts reconnect before status polling`
- `test/performance/benchmark_relay_recovery_test.dart`
  - `C8`: relay-state push emits one detected event without poll fallback

## Direct Test Verification

Targeted RED-first verification:

```bash
flutter test test/core/services/p2p_service_impl_test.dart --plain-name "relay state degradation push starts reconnect before status polling"
flutter test test/performance/benchmark_relay_recovery_test.dart --plain-name "C8: relay-state push emits one detected event without poll fallback"
```

RED result before implementation:
- `p2p_service_impl_test.dart`: failed because the first recovery command was still `node:status` instead of `relay:reconnect`
- `benchmark_relay_recovery_test.dart`: failed because the detected outage event still duplicated with `detectionSource='poll'`

Green reruns after implementation:

```bash
flutter test test/core/services/p2p_service_impl_test.dart
flutter test test/performance
flutter test test/core/lifecycle
flutter test test/core/services/pending_message_retrier_stuck_sending_test.dart
flutter test test/core/services/pending_message_retrier_test.dart
flutter test test/core/services/p2p_service_fault_injection_test.dart
cd go-mknoon && go test ./node/... ./bridge/...
```

Result:
- all commands above passed

## Exact Benchmark / Regression Commands Run

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

Execution notes:
- `background_reconnect_test.dart` built and ran but reported `All tests skipped.` on this simulator invocation
- `transport` gate passed
- `benchmark` gate passed
- `benchmark-sim` gate passed
- the two-simulator routing smoke was stopped after `S4` and `X1` were recorded, matching the earlier baseline-freeze scope
- raw logs were captured under `/tmp/relay_phase2_relay_state_truth_2026-04-16/`

## Benchmark Results

### BR-Sim

Dedicated Phase `2` suite rerun:
- `sim_background_resume_healthy_ms = 115ms`
- `sim_background_resume_healthy_source = resume_check`
- `sim_background_resume_degraded_ms = 9108ms`
- `sim_background_resume_degraded_source = relay_state_push`
- `sim_background_resume_recovery_start_source = relay_state_push`
- `sim_background_resume_recovery_source = relay_state_push`
- `sim_background_resume_reused_host = true`
- `sim_background_resume_coalesced_recovery_requests = 1`
- `sim_background_resume_relay_refresh_ms = 9552ms`
- `sim_background_resume_personal_reregister_ms = 50ms`
- `sim_background_resume_extended_ms = 105ms`

Comparison against the saved Phase `0` freeze:
- `BR-Sim-1` healthy resume: `101ms` -> `115ms` (`+14ms`, `+13.9%`)
- `BR-Sim-2` degraded resume: `9103ms` -> `9108ms` (`+5ms`, `+0.1%`)
- `BR-Sim-3` extended resume: `101ms` -> `105ms` (`+4ms`, `+4.0%`)

Interpretation:
- the headline degraded-resume time did not materially move
- the Phase `2` promotion bar required a `15%+` improvement in either `C-Sim p50` or `BR-Sim-2`; this run delivered neither
- the plan-level regression guard also says not to accept regressions over `10%` on healthy or cold-start paths; healthy resume regressed by `13.9%`
- on the dedicated suite rerun, degraded recovery source did shift off `health_check_poll`

Harness rerun sanity check:
- the direct `benchmark_background_resume_harness.dart` rerun still emitted
  `sim_background_resume_degraded_source = health_check_poll`
  at `9125ms`
- this means the source shift is not stable across reruns on the same branch even though the headline timing remains flat

### C-Sim

Dedicated Phase `2` suite rerun:
- `sim_relay_detection_ms = 503ms`
- `sim_relay_recovery_ms = 9115ms`
- `sim_recovery_source = relay_state_push`
- `sim_recovery_trigger_source = relay_state_push`
- `sim_reused_host = true`
- `sim_coalesced_recovery_requests = 1`
- `sim_relay_refresh_ms = 9560ms`
- `sim_personal_reregister_ms = 42ms`
- `sim_recovery_time_to_online_ms = 9612ms`
- `sim_relay_recovery_ms p50=9134ms p95=9327ms (n=3)`

Comparison against the saved Phase `0` freeze:
- `sim_relay_detection_ms`: `506ms` -> `503ms` (`-3ms`, `-0.6%`)
- `sim_relay_recovery_ms`: `9145ms` -> `9115ms` (`-30ms`, `-0.3%`)
- `sim_recovery_time_to_online_ms`: `9644ms` -> `9612ms` (`-32ms`, `-0.3%`)
- `C-Sim p50`: `9119ms` -> `9134ms` (`+15ms`, `+0.2%`)
- `C-Sim p95`: `9322ms` -> `9327ms` (`+5ms`, `+0.1%`)

Interpretation:
- the dedicated suite rerun shows no meaningful headline improvement
- `C-Sim p50` is slightly worse than the frozen baseline, so Phase `2` clearly misses its quantitative promotion rule
- the only reliable improvement here is attribution richness: coalesced recovery now reports `1` and recovery source stays `relay_state_push`

Harness rerun sanity check:
- the direct `benchmark_relay_recovery_harness.dart` rerun stayed flat at
  `p50=9125ms p95=9321ms`
- the harness flow log still showed a second detected outage event with
  `detectionSource="poll"` during repeated-cycle recovery, so the on-device path still falls back into poll detection even after the push trigger lands

### M-Sim

Dedicated Phase `2` suite rerun:
- `sim_time_to_online_badge_ms = 2555ms`
- `sim_time_to_online_source = relay_state_push`
- `sim_time_to_online_phase = cold_start`
- `sim_recovery_to_online_badge_ms = 9613ms`
- `sim_online_source_distribution relay_state_push=5`
- `sim_time_to_online_ms p50=276ms p95=296ms (n=5)`

Comparison against the saved Phase `0` freeze:
- `sim_time_to_online_badge_ms`: `248ms` -> `2555ms` (`+2307ms`, `+930.2%`)
- `sim_recovery_to_online_badge_ms`: `9611ms` -> `9613ms` (`+2ms`, `+0.0%`)
- `sim_online_source_distribution`: unchanged at `relay_state_push=5`
- `sim_time_to_online_ms p50`: `169ms` -> `276ms` (`+107ms`, `+63.3%`)
- `sim_time_to_online_ms p95`: `197ms` -> `296ms` (`+99ms`, `+50.3%`)

Interpretation:
- Phase `2` introduced a severe cold-start badge regression on this rerun
- recovery-to-online time stayed flat, so the experiment did not buy a visible recovery win to offset the regression
- source distribution did not move because Phase `0` was already winning that badge from `relay_state_push`

## Regression Checks

Required regression status:
- `background_reconnect_test.dart`: skipped on this simulator invocation
- `transport` gate: PASS
- `benchmark` gate: PASS
- `benchmark-sim` gate: PASS

Two-simulator routing smoke:
- `S4: PASS — send=108ms path=direct e2e=3567ms`
- `X1: PASS — restart: Alice=512ms Bob=511ms send=92ms e2e=3301ms`

Comparison against the saved Phase `0` freeze:
- `S4` send: `135ms` -> `108ms` (`-27ms`, `-20.0%`)
- `S4` e2e: `3562ms` -> `3567ms` (`+5ms`, `+0.1%`)
- `X1` Alice restart: `516ms` -> `512ms` (`-4ms`, `-0.8%`)
- `X1` Bob restart: `514ms` -> `511ms` (`-3ms`, `-0.6%`)
- `X1` send: `119ms` -> `92ms` (`-27ms`, `-22.7%`)
- `X1` e2e: `3304ms` -> `3301ms` (`-3ms`, `-0.1%`)

Interpretation:
- the transport reconnect smoke stayed in the same e2e range as the frozen baseline
- no new transport regression was introduced by the Phase `2` experiment

## Phase 2 Verdict

Promotion rule from the source-of-truth plan:
- keep only if degraded recovery source shifts off `health_check_poll`
- and either `C-Sim p50` or `BR-Sim-2` improves by `15%+`

Result:
- the dedicated `BR-Sim` rerun did show `relay_state_push` as the degraded source
- `C-Sim p50` failed: `9119ms` -> `9134ms`
- `BR-Sim-2` failed: `9103ms` -> `9108ms`
- healthy resume also regressed by more than the plan's `10%` general regression guard
- `M-Sim` cold-start badge regressed sharply
- the direct harness rerun still reported `health_check_poll` for degraded background-resume source, so the source shift is not stable enough to treat as a proven behavioral win

Evidence-backed conclusion:
- Phase `2` changes attribution and trigger ordering, but they do not move the measured relay-recovery bottleneck
- the on-device system still falls back into poll-driven detection on repeated recovery paths
- the experiment fails both the promotion rule and the broader regression bar

## Keep / Revert Recommendation

Recommendation: **revert / do not promote Phase `2` as currently implemented.**

Reason:
- no `15%+` improvement on either required headline benchmark
- source attribution is inconsistent across reruns
- healthy resume regressed past the acceptable guard
- `M-Sim` cold-start badge regressed badly enough to disqualify the change on its own
