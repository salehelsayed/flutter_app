# Phase 3 In-Place Relay Session Refresh Results

Source of truth:
- `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`

Run date:
- Local: `2026-04-16` (`Europe/Berlin`)

Branch:
- measurable branch: `codex/phase-3-in-place-refresh`

Devices:
- primary simulator: `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`)
- two-sim smoke: Alice `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`), Bob `iPhone 17` (`5BA69F1C-B112-47BE-B1FF-8C1003728C8F`)

Scope executed:
- rerun Phase `3` on the measurable branch so it can be compared directly against the frozen Phase `0` benchmark doc
- use the exact benchmark harnesses for `M-Sim`, `BR-Sim`, and `C-Sim`
- run reconnect/routing regression scenarios through `S4`, `X1`, and `X2`
- run the surrounding host and transport regression suites needed to judge whether the branch is safe enough to measure

Note:
- this supersedes the earlier isolated-base blocker report for this file
- the earlier isolated branch proved the Go seam; this rerun answers the measurement question on the benchmark-capable checkout

## Commands Run

Host and regression suites:

```bash
cd go-mknoon
go test ./node/...
go test ./bridge/...

cd ..
flutter test test/core/lifecycle
flutter test test/core/services
./scripts/run_test_gates.sh benchmark

flutter test integration_test/background_reconnect_test.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
env FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport
dart run integration_test/scripts/run_routing_smoke_e2e.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Primary comparison harnesses:

```bash
flutter test integration_test/benchmark_time_to_online_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
flutter test integration_test/benchmark_background_resume_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
flutter test integration_test/benchmark_relay_recovery_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
```

Execution notes:
- `benchmark-sim` was started, but it fans out across `17` unrelated simulator harnesses before the Phase `3` metrics. It was stopped in favor of the exact Phase `0` comparison trio above.
- `background_reconnect_test.dart` still skipped on this simulator run; the transport gate therefore counted it as skipped rather than failed.
- the routing orchestrator was allowed to run through `X2` and into later scenarios. After the required `S4`, `X1`, and `X2` rows were captured, it was stopped manually because the Phase `3` bar does not depend on the later group scenarios.
- `go test -count=1` reruns were attempted after the main validation pass, but both processes wedged idle with no output and were killed. The earlier package runs still returned `ok` on this branch.

## Benchmark Comparison Against Phase 0 Freeze

Phase `0` benchmark source:
- `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`

### M-Sim

- `sim_time_to_online_badge_ms`: `248ms` -> `185ms` (`-63ms`, `-25.4%`)
- `sim_time_to_online_ms p50`: `169ms` -> `172ms` (`+3ms`, `+1.8%`)
- `sim_time_to_online_ms p95`: `197ms` -> `186ms` (`-11ms`, `-5.6%`)
- `sim_recovery_to_online_badge_ms`: `9611ms` -> `9594ms` (`-17ms`, `-0.2%`)
- source distribution stayed `relay_state_push=5`

Measured rows:

```text
[BENCHMARK] sim_time_to_online_badge_ms = 185ms
[BENCHMARK] sim_time_to_online_source = relay_state_push
[BENCHMARK] sim_time_to_online_phase = cold_start
[BENCHMARK] sim_recovery_to_online_badge_ms = 9594ms
[BENCHMARK] sim_online_source_distribution relay_state_push=5
[BENCHMARK] sim_time_to_online_ms p50=172ms p95=186ms (n=5)
```

### BR-Sim

- `sim_background_resume_healthy_ms`: `101ms` -> `93ms` (`-8ms`, `-7.9%`)
- `sim_background_resume_degraded_ms`: `9103ms` -> `9126ms` (`+23ms`, `+0.3%`)
- `sim_background_resume_extended_ms`: `101ms` -> `99ms` (`-2ms`, `-2.0%`)
- degraded recovery source stayed `health_check_poll`
- `reused_host=true`
- `relay_refresh_ms=9578`
- `personal_reregister_ms=42`

Measured rows:

```text
[BENCHMARK] sim_background_resume_healthy_ms = 93ms
[BENCHMARK] sim_background_resume_healthy_phase = background_resume_already_online
[BENCHMARK] sim_background_resume_healthy_source = resume_check
[BENCHMARK] sim_background_resume_degraded_ms = 9126ms
[BENCHMARK] sim_background_resume_degraded_phase = background_resume
[BENCHMARK] sim_background_resume_degraded_source = health_check_poll
[BENCHMARK] sim_background_resume_recovery_start_source = health_check_poll
[BENCHMARK] sim_background_resume_recovery_source = health_check_poll
[BENCHMARK] sim_background_resume_reused_host = true
[BENCHMARK] sim_background_resume_coalesced_recovery_requests = 0
[BENCHMARK] sim_background_resume_relay_refresh_ms = 9578ms
[BENCHMARK] sim_background_resume_personal_reregister_ms = 42ms
[BENCHMARK] sim_background_resume_extended_ms = 99ms
[BENCHMARK] sim_background_resume_extended_phase = background_resume_already_online
[BENCHMARK] sim_background_resume_extended_source = resume_check
```

### C-Sim

- `sim_relay_detection_ms`: `506ms` -> `502ms` (`-4ms`, `-0.8%`)
- `sim_relay_recovery_ms`: `9145ms` -> `9102ms` (`-43ms`, `-0.5%`)
- `sim_relay_outage_phase=recovered`: `9638ms` -> `9597ms` (`-41ms`, `-0.4%`)
- `sim_recovery_time_to_online_ms`: `9644ms` -> `9602ms` (`-42ms`, `-0.4%`)
- `sim_relay_recovery_ms p50`: `9119ms` -> `9118ms` (`-1ms`, `-0.0%`)
- `sim_relay_recovery_ms p95`: `9322ms` -> `9313ms` (`-9ms`, `-0.1%`)
- recovery source stayed `health_check_poll`
- `reused_host=true`
- `relay_refresh_ms=9553`
- `personal_reregister_ms=42`

Measured rows:

```text
[BENCHMARK] sim_relay_detection_ms = 502ms
[BENCHMARK] sim_relay_recovery_ms = 9102ms
[BENCHMARK] sim_relay_outage_phase=recovered ms=9597
[BENCHMARK] sim_recovery_source = health_check_poll
[BENCHMARK] sim_recovery_trigger_source = health_check_poll
[BENCHMARK] sim_reused_host = true
[BENCHMARK] sim_coalesced_recovery_requests = 0
[BENCHMARK] sim_relay_refresh_ms = 9553ms
[BENCHMARK] sim_personal_reregister_ms = 42ms
[BENCHMARK] sim_recovery_time_to_online_ms = 9602ms
[BENCHMARK] sim_relay_recovery_ms p50=9118ms p95=9313ms (n=3)
```

### Routing Smoke

Using the frozen Phase `0` rerun rows from `05-phase-0-relay-recovery-baseline-results.md`:

- `S4`: `send=135ms e2e=3562ms` -> `send=185ms e2e=3574ms`
  delta: `send +50ms` (`+37.0%`), `e2e +12ms` (`+0.3%`)
- `X1`: `restart=516ms/514ms send=119ms e2e=3304ms` -> `restart=507ms/513ms send=91ms e2e=3306ms`
  delta: `restart -9ms/-1ms`, `send -28ms` (`-23.5%`), `e2e +2ms` (`+0.1%`)
- `X2`: no exact row exists in the Phase `0` freeze doc
  current measurement: `resume: Alice=112ms Bob=108ms e2e=0ms`

Measured rows:

```text
[ORCH] S4: PASS — send=185ms path=direct e2e=3574ms
[ORCH] X1: Both restarted (Alice=507ms Bob=513ms)
[ORCH] X1: PASS — restart: Alice=507ms Bob=513ms send=91ms e2e=3306ms
[ORCH] X2: Both resumed (Alice=112ms Bob=108ms)
[ORCH] X2: PASS — resume: Alice=112ms Bob=108ms e2e=0ms
```

## Regression Checks

Passed:
- `go test ./node/...` -> `ok`
- `go test ./bridge/...` -> `ok`
- `flutter test test/core/lifecycle` -> PASS
- `flutter test test/core/services` -> PASS
- `./scripts/run_test_gates.sh benchmark` -> PASS
- `flutter test integration_test/benchmark_time_to_online_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469` -> PASS
- `flutter test integration_test/benchmark_background_resume_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469` -> PASS
- `flutter test integration_test/benchmark_relay_recovery_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469` -> PASS
- `env FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport` -> PASS
  - `wifi_relay_fallback_smoke_test.dart`: PASS
  - `transport_e2e_test.dart`: PASS
  - `media_stable_id_smoke_test.dart`: PASS

Skipped:
- `flutter test integration_test/background_reconnect_test.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469`
- transport gate includes the same file and also reported it as skipped

Passed through the required reconnect scenarios:
- routing smoke reached and passed `S4`, `X1`, `X2`, and also continued through `X3` before the run was stopped manually

Residual caveat:
- the non-cached Go reruns were inconclusive because the processes wedged idle; the earlier package results and all Flutter-side regressions above are the usable evidence from this branch

## Phase 3 Verdict

Promotion rule from the Phase `3` source-of-truth section:
- keep only if `C-Sim p50` drops by at least `2000ms`
- or `S4/X1 e2e` drops by `20%+`
- with no healthy-path regression

Measured outcome:
- `C-Sim p50` was effectively flat: `9119ms` -> `9118ms`
- `S4 e2e` slightly worsened: `3562ms` -> `3574ms`
- `X1 e2e` was effectively flat: `3304ms` -> `3306ms`
- `BR-Sim-2` degraded resume slightly worsened: `9103ms` -> `9126ms`
- recovery attribution still points at `health_check_poll`, not a materially faster new trigger path

Interpretation:
- the branch is not obviously unsafe: `reused_host=true`, the routing smoke passed through `X2`, and the transport gate stayed green
- but the measurable user-visible recovery time did not move
- the only clear wins were outside the Phase `3` promotion bar, such as `M-Sim` cold-start badge and `X1` send latency

## Keep / Revert Recommendation

Recommendation: **revert / do not promote Phase `3` yet.**

Reason:
- the Phase `3` acceptance bar is not met
- `C-Sim` headline recovery remained flat
- `S4` and `X1` end-to-end timings did not improve by the required margin
- degraded background-resume recovery did not improve
- this branch proves the in-place path can survive the transport regressions, but it does not prove a user-visible relay-recovery win against the frozen Phase `0` benchmark
