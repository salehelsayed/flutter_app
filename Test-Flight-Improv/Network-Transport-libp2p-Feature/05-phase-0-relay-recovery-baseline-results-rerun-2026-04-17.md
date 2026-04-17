# Phase 0 Baseline Freeze Rerun

Source of truth: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`

Run date:
- Local: `2026-04-17` (`Europe/Berlin`)

Branch:
- `Test-Flight-Improv`

Devices:
- Primary simulator: `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`)
- Two-sim smoke: Alice `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`), Bob `iPhone 17` (`5BA69F1C-B112-47BE-B1FF-8C1003728C8F`)

No production code was changed in this phase.

## Commands Used

```bash
flutter test integration_test/benchmark_time_to_online_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 > /tmp/phase0_m_2026-04-17.log 2>&1
flutter test integration_test/benchmark_background_resume_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 > /tmp/phase0_br_2026-04-17.log 2>&1
flutter test integration_test/benchmark_relay_recovery_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 > /tmp/phase0_c_2026-04-17.log 2>&1
dart run integration_test/scripts/run_routing_smoke_e2e.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,5BA69F1C-B112-47BE-B1FF-8C1003728C8F > /tmp/phase0_routing_2026-04-17.log 2>&1
```

## Execution Notes

- The three single-simulator harnesses completed with `All tests passed!`.
- The routing orchestrator captured the required `S4` and `X1` rows, then continued through later nongating scenarios into the group phase before it was terminated to keep the run bounded to Phase `0` needs.
- Raw logs were captured at:
  - `/tmp/phase0_m_2026-04-17.log`
  - `/tmp/phase0_br_2026-04-17.log`
  - `/tmp/phase0_c_2026-04-17.log`
  - `/tmp/phase0_routing_2026-04-17.log`

## Exact Emitted Rows

```text
[BENCHMARK] sim_time_to_online_badge_ms = 208ms
[BENCHMARK] sim_time_to_online_source = relay_state_push
[BENCHMARK] sim_time_to_online_phase = cold_start
[BENCHMARK] sim_recovery_to_online_badge_ms = 9607ms
[BENCHMARK] sim_online_source_distribution relay_state_push=5
[BENCHMARK] sim_time_to_online_ms p50=158ms p95=168ms (n=5)

[BENCHMARK] sim_background_resume_healthy_ms = 94ms
[BENCHMARK] sim_background_resume_healthy_phase = background_resume_already_online
[BENCHMARK] sim_background_resume_healthy_source = resume_check
[BENCHMARK] sim_background_resume_degraded_ms = 9114ms
[BENCHMARK] sim_background_resume_degraded_phase = background_resume
[BENCHMARK] sim_background_resume_degraded_source = health_check_poll
[BENCHMARK] sim_background_resume_extended_ms = 105ms
[BENCHMARK] sim_background_resume_extended_phase = background_resume_already_online
[BENCHMARK] sim_background_resume_extended_source = resume_check

[BENCHMARK] sim_relay_detection_ms = 502ms
[BENCHMARK] sim_relay_recovery_ms = 9100ms
[BENCHMARK] sim_relay_outage_phase=recovered ms=9593
[BENCHMARK] sim_recovery_time_to_online_ms = 9598ms
[BENCHMARK] sim_relay_recovery_ms p50=9105ms p95=9510ms (n=3)

[08:32:05.722] [ORCH] S4: PASS — send=188ms path=direct e2e=3575ms
[08:33:35.530] [ORCH] X1: Both restarted (Alice=518ms Bob=518ms)
[08:33:39.338] [ORCH] X1: PASS — restart: Alice=518ms Bob=518ms send=126ms e2e=3586ms
```

## Comparison Against Plan Baseline

- `C-Sim` relay recovery: rerun `p50=9105ms p95=9510ms`; plan baseline `p50=9136ms p95=9320ms`
- `BR-Sim-2` degraded background resume: rerun `9114ms`; plan baseline `9166ms`
- Healthy resume: rerun `94ms`; plan baseline `100-103ms`
- `S4` reconnect: rerun `send=188ms e2e=3575ms`; plan baseline `send=105ms e2e=3561ms`
- `X1` both-sides restart: rerun `restart=518ms/518ms send=126ms e2e=3586ms`; plan baseline `send=142ms e2e=3310ms`

## Phase 0 Status

Baseline capture completed on the current branch.

Headline comparison against the plan targets:
- `C-Sim p50`: `-31ms` vs plan baseline
- `C-Sim p95`: `+190ms` vs plan baseline
- `BR-Sim-2`: `-52ms` vs plan baseline
- Healthy resume: `94ms`, which is `6-9ms` faster than the documented `100-103ms` band
- `S4 send`: `+83ms` vs plan baseline
- `S4 e2e`: `+14ms` vs plan baseline
- `X1 send`: `-16ms` vs plan baseline
- `X1 e2e`: `+276ms` vs plan baseline

Phase `0` stopped here after baseline capture.
