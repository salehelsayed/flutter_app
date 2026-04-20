# Phase 3a Direct Reservation Results

Source of truth:
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`

Run date:
- Local: `2026-04-17` (`Europe/Berlin`)

Branch:
- measured branch: `timing-phase3a`

Devices:
- primary simulator: `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`)

Scope executed:
- start from the instrumentation-first baseline seam already present on this branch tip, not from a later experiment doc
- add the missing Phase 3a RED tests first
- make only the minimum Go change needed to issue direct reservation after warm dial and finish from event-driven circuit-address updates when possible
- rerun the exact Phase 3a benchmark trio and the required transport regressions
- stop after reporting the Phase 3a verdict

Execution notes:
- the `run_benchmark_suite.dart` wrapper was not used for final evidence because it stalled before producing benchmark rows; the exact harness commands from the Phase 3a source row were run directly instead
- `C-Sim-2` needed `flutter test --timeout none` because the default runner timeout stopped the repeated-cycle harness at `00:20` even though the same harness passed under an explicit timeout override
- no Phase 4+ behavior, native lifecycle prewarm, QUIC session-ticket persistence, or proactive TTL refresh was added in this phase

## Commands Run

Direct verification:

```bash
cd go-mknoon && go test ./node -run 'TestRefreshRelaySession_(DirectReservationAfterWarmDial|EventDrivenCircuitAddressUpdateCompletesRecovery|MultipleRelaysFirstSuccessWins|DirectReservationFailureFallsBackToPoll)$' -count=1 -timeout 20s
cd go-mknoon && go test ./node -run 'TestRefreshRelaySession_' -count=1
cd go-mknoon && go test ./bridge -run '^TestRelayReconnect_ReturnsStructuredRecoveryFields$' -count=1
flutter test test/performance/benchmark_background_resume_test.dart
flutter test test/performance/benchmark_relay_recovery_test.dart
flutter test test/core/services/p2p_service_impl_test.dart
```

Primary comparison harnesses:

```bash
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_relay_recovery_harness.dart
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_background_resume_harness.dart
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_time_to_online_harness.dart
```

Transport regressions:

```bash
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/background_reconnect_test.dart
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport
```

## Benchmark Comparison Against Phase 0 Freeze

Phase `0` benchmark source:
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-phase-0-relay-recovery-baseline-results.md`

### C-Sim

- `sim_relay_detection_ms`: `506ms` -> `502ms` (`-4ms`, `-0.8%`)
- `sim_relay_recovery_ms`: `9145ms` -> `9153ms` (`+8ms`, `+0.1%`)
- `sim_relay_outage_phase=recovered`: `9638ms` -> `9644ms` (`+6ms`, `+0.1%`)
- `sim_recovery_time_to_online_ms`: `9644ms` -> `9651ms` (`+7ms`, `+0.1%`)
- `sim_relay_recovery_ms p50`: `9119ms` -> `9165ms` (`+46ms`, `+0.5%`)
- `sim_relay_recovery_ms p95`: `9322ms` -> `9370ms` (`+48ms`, `+0.5%`)
- recovered outage attribution still reported `recovery_source=relay_state_push` and `recovery_trigger_source=relay_state_push`
- the winning reservation path did not change: `reservationPath=poll_fallback`
- the direct reservation RPC was measured, but it did not win the critical path: `relayWarmMs=92`, `reserveRpcMs=42`, `circuitAddressWaitMs=9506`
- `reservationWinnerPeer` stayed `12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`

Measured rows:

```text
[BENCHMARK] sim_relay_detection_ms = 502ms
[BENCHMARK] sim_relay_recovery_ms = 9153ms
[BENCHMARK] sim_relay_outage_phase=recovered ms=9644
[BENCHMARK] sim_recovery_source = relay_state_push
[BENCHMARK] sim_recovery_trigger_source = relay_state_push
[BENCHMARK] sim_reused_host = true
[BENCHMARK] sim_coalesced_recovery_requests = 0
[BENCHMARK] sim_relay_refresh_ms = 9599ms
[BENCHMARK] sim_relay_warm_ms = 92ms
[BENCHMARK] sim_reserve_rpc_ms = 42ms
[BENCHMARK] sim_circuit_address_wait_ms = 9506ms
[BENCHMARK] sim_reservation_path = poll_fallback
[BENCHMARK] sim_reservation_winner_peer = 12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
[BENCHMARK] sim_personal_reregister_ms = 44ms
[BENCHMARK] sim_recovery_time_to_online_ms = 9651ms
[BENCHMARK] sim_relay_recovery_ms p50=9165ms p95=9370ms (n=3)
```

### BR-Sim

- `sim_background_resume_healthy_ms`: `101ms` -> `96ms` (`-5ms`, `-5.0%`)
- `sim_background_resume_degraded_ms`: `9103ms` -> `9156ms` (`+53ms`, `+0.6%`)
- `sim_background_resume_extended_ms`: `101ms` -> `105ms` (`+4ms`, `+4.0%`)
- the degraded badge source still returned `health_check_poll`
- the recovered outage attribution still reported `recovery_start_source=relay_state_push` and `recovery_source=relay_state_push`
- the winning reservation path again stayed `poll_fallback`
- the direct reservation RPC was visible but non-winning: `relayWarmMs=99`, `reserveRpcMs=43`, `circuitAddressWaitMs=9505`
- `reservationWinnerPeer` stayed `12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`

Measured rows:

```text
[BENCHMARK] sim_background_resume_healthy_ms = 96ms
[BENCHMARK] sim_background_resume_healthy_phase = background_resume_already_online
[BENCHMARK] sim_background_resume_healthy_source = resume_check
[BENCHMARK] sim_background_resume_degraded_ms = 9156ms
[BENCHMARK] sim_background_resume_degraded_phase = background_resume
[BENCHMARK] sim_background_resume_degraded_source = health_check_poll
[BENCHMARK] sim_background_resume_recovery_start_source = relay_state_push
[BENCHMARK] sim_background_resume_recovery_source = relay_state_push
[BENCHMARK] sim_background_resume_reused_host = true
[BENCHMARK] sim_background_resume_coalesced_recovery_requests = 0
[BENCHMARK] sim_background_resume_relay_refresh_ms = 9606ms
[BENCHMARK] sim_background_resume_relay_warm_ms = 99ms
[BENCHMARK] sim_background_resume_reserve_rpc_ms = 43ms
[BENCHMARK] sim_background_resume_circuit_address_wait_ms = 9505ms
[BENCHMARK] sim_background_resume_reservation_path = poll_fallback
[BENCHMARK] sim_background_resume_reservation_winner_peer = 12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
[BENCHMARK] sim_background_resume_personal_reregister_ms = 43ms
[BENCHMARK] sim_background_resume_extended_ms = 105ms
[BENCHMARK] sim_background_resume_extended_phase = background_resume_already_online
[BENCHMARK] sim_background_resume_extended_source = resume_check
```

### M-Sim

- `sim_time_to_online_badge_ms`: `248ms` -> `267ms` (`+19ms`, `+7.7%`)
- `sim_time_to_online_ms p50`: `169ms` -> `157ms` (`-12ms`, `-7.1%`)
- `sim_time_to_online_ms p95`: `197ms` -> `166ms` (`-31ms`, `-15.7%`)
- `sim_recovery_to_online_badge_ms`: `9611ms` -> `9653ms` (`+42ms`, `+0.4%`)
- source distribution stayed `relay_state_push=5`

Measured rows:

```text
[BENCHMARK] sim_time_to_online_badge_ms = 267ms
[BENCHMARK] sim_time_to_online_source = relay_state_push
[BENCHMARK] sim_time_to_online_phase = cold_start
[BENCHMARK] sim_recovery_to_online_badge_ms = 9653ms
[BENCHMARK] sim_online_source_distribution relay_state_push=5
[BENCHMARK] sim_time_to_online_ms p50=157ms p95=166ms (n=5)
```

## Winning Reservation Path

Observed winner:
- `poll_fallback`

Observed winning peer:
- `12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`

Interpretation:
- the direct reservation RPC is now observable and consistently fast at roughly `42-43ms`
- relay warm-up is also fast at roughly `92-99ms`
- the measured bottleneck stayed the post-reservation circuit-address availability window at roughly `9505-9506ms`
- this means Phase 3a changed sub-step attribution, but it did not shift the winning path to `direct_reserve`

## Regression Checks

Passed:
- `go test ./node -run 'TestRefreshRelaySession_(DirectReservationAfterWarmDial|EventDrivenCircuitAddressUpdateCompletesRecovery|MultipleRelaysFirstSuccessWins|DirectReservationFailureFallsBackToPoll)$' -count=1 -timeout 20s`
- `go test ./node -run 'TestRefreshRelaySession_' -count=1`
- `go test ./bridge -run '^TestRelayReconnect_ReturnsStructuredRecoveryFields$' -count=1`
- `flutter test test/performance/benchmark_background_resume_test.dart`
- `flutter test test/performance/benchmark_relay_recovery_test.dart`
- `flutter test test/core/services/p2p_service_impl_test.dart`
- `flutter test --timeout none ... benchmark_relay_recovery_harness.dart`
- `flutter test --timeout none ... benchmark_background_resume_harness.dart`
- `flutter test --timeout none ... benchmark_time_to_online_harness.dart`
- `FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport`
  - `wifi_relay_fallback_smoke_test.dart`: PASS
  - `transport_e2e_test.dart`: PASS
  - `media_stable_id_smoke_test.dart`: PASS

Skipped:
- `flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/background_reconnect_test.dart`
  - clean simulator skip, matching prior baseline behavior
- the transport gate included the same file and reported it as skipped rather than failed

## Phase 3a Verdict

Promotion rule from the Phase `3a` source-of-truth section:
- keep only if the winning reservation path shifts to `direct_reserve`
- and either `C-Sim p50` or `BR-Sim-2` improves by at least `1500ms`
- with no healthy-resume regression

Measured outcome:
- the winning reservation path did not shift; it stayed `poll_fallback`
- `C-Sim p50` slightly worsened: `9119ms` -> `9165ms`
- `BR-Sim-2` slightly worsened: `9103ms` -> `9156ms`
- healthy resume did not regress materially: `101ms` -> `96ms`

Interpretation:
- the Phase 3a seam is now measurable and the required attribution fields are present end-to-end
- the direct reservation RPC itself is not the dominant cost in the measured environment
- the measured bottleneck remains the long wait for circuit-address publication or visibility after the reservation RPC
- this experiment changed labels and sub-step timing visibility, but not the user-visible recovery headline

## Keep / Revert Recommendation

Recommendation: **revert / do not promote Phase `3a` yet.**

Reason:
- the Phase `3a` promotion bar was not met
- the winning reservation path stayed `poll_fallback`
- neither `C-Sim p50` nor `BR-Sim-2` improved by the required `1500ms`
- the experiment does not justify stacking later native lifecycle or QUIC work on top of it as if direct reservation already solved the relay-recovery bottleneck
