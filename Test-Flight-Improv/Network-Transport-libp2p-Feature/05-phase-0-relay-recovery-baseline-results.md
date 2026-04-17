# Phase 0 Baseline Freeze

Source of truth: `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`

Run date:
- Local: `2026-04-16` (`Europe/Berlin`)
- Log timestamps: UTC `2026-04-15T22:48:47Z` through `2026-04-15T22:59:40Z`

Devices:
- Primary simulator: `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`)
- Two-sim smoke: Alice `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`), Bob `iPhone 17` (`5BA69F1C-B112-47BE-B1FF-8C1003728C8F`)

No production code was changed in this phase.

## Commands Used

```bash
flutter test integration_test/benchmark_time_to_online_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
flutter test integration_test/benchmark_background_resume_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
flutter test integration_test/benchmark_relay_recovery_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
dart run integration_test/scripts/run_routing_smoke_e2e.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Execution notes:
- Raw logs were captured during the run under `/tmp/relay_phase0_baseline_2026-04-16/`.
- The two-simulator orchestrator was stopped at `2026-04-15T22:59:40Z` after `S4` and `X1` had been recorded and the script had already advanced into Phase 2 group scenarios, which are out of scope for Phase 0.

## Exact Emitted Rows

```text
[BENCHMARK] sim_time_to_online_badge_ms = 248ms
[BENCHMARK] sim_time_to_online_source = relay_state_push
[BENCHMARK] sim_time_to_online_phase = cold_start
[BENCHMARK] sim_recovery_to_online_badge_ms = 9611ms
[BENCHMARK] sim_online_source_distribution relay_state_push=5
[BENCHMARK] sim_time_to_online_ms p50=169ms p95=197ms (n=5)

[BENCHMARK] sim_background_resume_healthy_ms = 101ms
[BENCHMARK] sim_background_resume_healthy_phase = background_resume_already_online
[BENCHMARK] sim_background_resume_healthy_source = resume_check
[BENCHMARK] sim_background_resume_degraded_ms = 9103ms
[BENCHMARK] sim_background_resume_degraded_phase = background_resume
[BENCHMARK] sim_background_resume_degraded_source = health_check_poll
[BENCHMARK] sim_background_resume_extended_ms = 101ms
[BENCHMARK] sim_background_resume_extended_phase = background_resume_already_online
[BENCHMARK] sim_background_resume_extended_source = resume_check

[BENCHMARK] sim_relay_detection_ms = 506ms
[BENCHMARK] sim_relay_recovery_ms = 9145ms
[BENCHMARK] sim_relay_outage_phase=recovered ms=9638
[BENCHMARK] sim_recovery_time_to_online_ms = 9644ms
[BENCHMARK] sim_relay_recovery_ms p50=9119ms p95=9322ms (n=3)

[ORCH] S4: PASS — send=135ms path=direct e2e=3562ms
[ORCH] X1: Both restarted (Alice=516ms Bob=514ms)
[ORCH] X1: PASS — restart: Alice=516ms Bob=514ms send=119ms e2e=3304ms
```

## Baseline Comparison

- `C-Sim` relay recovery: rerun `p50=9119ms p95=9322ms`; plan baseline `p50=9136ms p95=9320ms`.
- `BR-Sim-2` degraded background resume: rerun `9103ms`; plan baseline `9166ms`.
- Healthy resume: rerun `101ms`; plan baseline `100-103ms`.
- `S4` reconnect: rerun `send=135ms e2e=3562ms`; plan baseline `send=105ms e2e=3561ms`.
- `X1` both-sides restart: rerun `restart=516ms/514ms send=119ms e2e=3304ms`; plan baseline `restart=513ms/515ms send=142ms e2e=3310ms`.

## Phase 0 Status

Headline relay-recovery and degraded-resume numbers reproduced closely enough to freeze the baseline:
- `C-Sim p50`: `-17ms` vs plan baseline
- `C-Sim p95`: `+2ms` vs plan baseline
- `BR-Sim-2`: `-63ms` vs plan baseline
- Healthy resume stayed inside the documented `100-103ms` band

Two-simulator reconnect smoke stayed in the same range:
- `S4 e2e`: `+1ms` vs plan baseline
- `X1 e2e`: `-6ms` vs plan baseline

Phase 0 stopped here, after baseline capture.

## Section 8 Instrumentation-First Pass

Run date:
- Local: `2026-04-16` (`Europe/Berlin`)
- Primary simulator: `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`)

Scope executed from `05-relay-recovery-improvement-tdd-plan.md` section `8` only:
- additive instrumentation only
- RED tests for new attribution fields/events
- no intentional relay recovery behavior change

### New Fields / Events Added

Flutter flow events:
- `RELAY_RECOVERY_START`
  - `recoverySource`
  - `resumeToRecoveryStartMs` when the start is observed inside a resume-triggered path
- `RELAY_OUTAGE_TIMING` `phase='recovered'` now also carries:
  - `recoverySource`
  - `recoveryTriggerSource`
  - `reusedHost`
  - `coalescedRecoveryRequests`
  - `relayRefreshMs`
  - `personalReregisterMs`
- `APP_LIFECYCLE_RESUME_COMPLETE` now optionally carries:
  - `groupReregisterMs`

Go `relay:reconnect` bridge response now also carries:
- `reusedHost`
- `coalescedRecoveryRequests`
- `relayRefreshMs`
- `personalReregisterMs`

Benchmark rows added:
- `sim_background_resume_to_recovery_start_ms`
- `sim_background_resume_recovery_start_source`
- `sim_background_resume_recovery_source`
- `sim_background_resume_reused_host`
- `sim_background_resume_coalesced_recovery_requests`
- `sim_background_resume_relay_refresh_ms`
- `sim_background_resume_personal_reregister_ms`
- `sim_recovery_source`
- `sim_recovery_trigger_source`
- `sim_reused_host`
- `sim_coalesced_recovery_requests`
- `sim_relay_refresh_ms`
- `sim_personal_reregister_ms`

### Tests Run

Host tests:

```bash
cd go-mknoon
go test ./node -run 'Test(RefreshRelaySession_DoesNotReplaceHost|RecoveryCoalescing_PerformsSinglePersonalReregister|RelaySession_CoalescesConcurrentRecoveryRequests)$' -count=1
go test ./bridge -run '^TestRelayReconnect_ReturnsRecoveryMode$' -count=1 -v -timeout 60s
go test ./bridge -run '^TestRelayReconnect_ReturnsStructuredRecoveryFields$' -count=1 -v -timeout 60s
```

Result:
- `node`: PASS
- `bridge`: PASS

Dart RED tests:

```bash
flutter test test/performance/benchmark_background_resume_test.dart
flutter test test/performance/benchmark_relay_recovery_test.dart
```

Result:
- `benchmark_background_resume_test.dart`: PASS
- `benchmark_relay_recovery_test.dart`: PASS

Benchmark subset:

```bash
flutter test --no-pub integration_test/benchmark_background_resume_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
flutter test --no-pub integration_test/benchmark_relay_recovery_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469
```

Result:
- `BR-Sim`: PASS
- `C-Sim`: PASS

### Baseline Before / After

Comparison uses the Phase 0 freeze above as the baseline before instrumentation.

Primary recovery headlines:
- `BR-Sim-2` degraded background resume: `9103ms` -> `9292ms` (`+189ms`, `+2.1%`)
- `C-Sim` relay recovery `p50`: `9119ms` -> `9100ms` (`-19ms`, `-0.2%`)
- `C-Sim` relay recovery `p95`: `9322ms` -> `9198ms` (`-124ms`, `-1.3%`)
- `C-Sim-1` single recovery wall-clock: `9145ms` -> `9092ms` (`-53ms`, `-0.6%`)
- `C-Sim-1` recovery badge: `9644ms` -> `9593ms` (`-51ms`, `-0.5%`)

Healthy / already-online resume checks:
- `BR-Sim-1` healthy resume: `101ms` -> `117ms` (`+16ms`, `+15.8%`)
- `BR-Sim-3` extended resume: `101ms` -> `102ms` (`+1ms`, `+1.0%`)

New attribution values observed on the simulator reruns:
- `BR-Sim-2`
  - `recovery_start_source=relay_state_push`
  - `recovery_source=relay_state_push`
  - `reused_host=true`
  - `coalesced_recovery_requests=0`
  - `relay_refresh_ms=9745`
  - `personal_reregister_ms=42`
  - `resume_to_recovery_start_ms` was **not captured** in the resume window because recovery had already started from the earlier relay-state push before the resume benchmark began
- `C-Sim-1`
  - `recovery_source=relay_state_push`
  - `recovery_trigger_source=relay_state_push`
  - `reused_host=true`
  - `coalesced_recovery_requests=0`
  - `relay_refresh_ms=9544`
  - `personal_reregister_ms=42`

### Instrumentation Acceptance

Strict section `8c` verdict: **not accepted yet**.

Reason:
- the primary degraded-recovery headlines stayed within the required `±5%` range
- however `BR-Sim-1` healthy resume moved from `101ms` to `117ms`, which is outside the prior `100-103ms` band and outside a strict `±5%` interpretation

Interpretation:
- the instrumentation itself is additive and the new attribution fields are working
- the recovery behavior was not intentionally changed
- a strict promotion under section `8c` should wait for a healthy-resume rerun that lands back inside the documented range
