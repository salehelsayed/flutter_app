# Section 8 Instrumentation-First Results

Source of truth:
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`

Run date:
- `2026-04-17` (`Europe/Berlin`)

Branch:
- `Test-Flight-Improv`

Primary simulator:
- `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`)

Scope:
- Execute only the additive instrumentation and RED coverage from section `8`
- Do not intentionally change relay recovery behavior
- Recheck the headline metrics against the frozen Phase `0` rerun baseline

## Commands Used

Host tests:

```bash
flutter test test/performance/benchmark_background_resume_test.dart
flutter test test/core/services/p2p_service_impl_test.dart
flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart
go test ./bridge -run 'TestRelayReconnect_ReturnsRecoveryMode|TestRelayReconnect_ReturnsStructuredRecoveryFields'
go test ./node -run 'TestReconnectRelays_WatchdogRestart_ReRegistersPersonalNamespace|TestRecoveryCoalescing_PerformsSinglePersonalReregister|TestRefreshRelaySession_DoesNotReplaceHost'
```

Benchmark subset:

```bash
flutter test integration_test/benchmark_time_to_online_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 > /tmp/phase8_m_2026-04-17.log 2>&1
flutter test integration_test/benchmark_background_resume_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 > /tmp/phase8_br_2026-04-17.log 2>&1
flutter test integration_test/benchmark_relay_recovery_harness.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 > /tmp/phase8_c_2026-04-17.log 2>&1
```

Notes:
- A broad `go test ./bridge ./node` run was attempted first, but it did not converge in a reasonable window in this repo's long node suite, so the verification was narrowed to the directly affected Go tests above.
- Raw logs used for this report:
  - `/tmp/phase8_m_2026-04-17.log`
  - `/tmp/phase8_br_2026-04-17.log`
  - `/tmp/phase8_c_2026-04-17.log`
  - `/tmp/phase0_m_2026-04-17.log`
  - `/tmp/phase0_br_2026-04-17.log`
  - `/tmp/phase0_c_2026-04-17.log`

## New Fields And Events Added

Flutter flow events:
- New `RELAY_RECOVERY_START` event with `recoverySource` and `resumeToRecoveryStartMs` when a resume marker is available.
- `RELAY_OUTAGE_TIMING` `phase=recovered` now carries:
  - `recoverySource`
  - `recoveryTriggerSource`
  - `reusedHost`
  - `coalescedRecoveryRequests`
  - `relayRefreshMs`
  - `relayWarmMs`
  - `reserveRpcMs`
  - `circuitAddressWaitMs`
  - `reservationPath`
  - `reservationWinnerPeer`
  - `personalReregisterMs`
- `APP_LIFECYCLE_RESUME_COMPLETE` now carries `groupReregisterMs` when the foreground path actually performs group rejoin work.
- `P2P_SERVICE_RECOVERY_COALESCED` now includes the active recovery source when available.

Go recovery response:
- `relay:reconnect` now returns additive recovery attribution fields for the same breakdown above, including `reusedHost` and `coalescedRecoveryRequests`.

RED coverage:
- `test/performance/benchmark_background_resume_test.dart`
  - degraded resume emits `RELAY_RECOVERY_START`
  - healthy resume does not emit it
  - badge source remains distinct from recovery-start source
- `test/core/services/p2p_service_impl_test.dart`
  - relay-state push recovery is attributed as `relay_state_push`
- `go-mknoon/node/node_test.go`
  - watchdog restart reports host replacement
  - coalesced recovery requests are counted
  - in-place refresh reports host reuse and recovery attribution fields
- `go-mknoon/bridge/bridge_test.go`
  - `RelayReconnect` exposes the structured host-reuse and timing fields

## Host Test Result

Passed:
- `flutter test test/performance/benchmark_background_resume_test.dart`
- `flutter test test/core/services/p2p_service_impl_test.dart`
- `flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `go test ./bridge -run 'TestRelayReconnect_ReturnsRecoveryMode|TestRelayReconnect_ReturnsStructuredRecoveryFields'`
- `go test ./node -run 'TestReconnectRelays_WatchdogRestart_ReRegistersPersonalNamespace|TestRecoveryCoalescing_PerformsSinglePersonalReregister|TestRefreshRelaySession_DoesNotReplaceHost'`

## Benchmark Before/After

Baseline before:
- Phase `0` rerun recorded in `05-phase-0-relay-recovery-baseline-results-rerun-2026-04-17.md`

Headline metrics:

| Metric | Before | After | Delta | Within ±5% |
| --- | ---: | ---: | ---: | --- |
| `C-Sim p50` | `9105ms` | `9088ms` | `-17ms` (`-0.2%`) | `yes` |
| `C-Sim p95` | `9510ms` | `9295ms` | `-215ms` (`-2.3%`) | `yes` |
| `BR-Sim degraded` | `9114ms` | `9298ms` | `+184ms` (`+2.0%`) | `yes` |
| `BR-Sim healthy` | `94ms` | `94ms` | `0ms` (`0.0%`) | `yes` |

Supporting subset rows:

| Metric | Before | After | Delta |
| --- | ---: | ---: | ---: |
| `M cold-start p50` | `158ms` | `153ms` | `-5ms` |
| `M cold-start p95` | `168ms` | `157ms` | `-11ms` |
| `M recovery badge` | `9607ms` | `9792ms` | `+185ms` |
| `C single-run recovery` | `9100ms` | `9118ms` | `+18ms` |
| `C recovered outage` | `9593ms` | `9612ms` | `+19ms` |
| `C recovery badge` | `9598ms` | `9617ms` | `+19ms` |
| `BR extended healthy` | `105ms` | `95ms` | `-10ms` |

## Exact New Attribution Rows

`C-Sim`:

```text
[BENCHMARK] sim_recovery_source = relay_state_push
[BENCHMARK] sim_recovery_trigger_source = relay_state_push
[BENCHMARK] sim_reused_host = true
[BENCHMARK] sim_coalesced_recovery_requests = 0
[BENCHMARK] sim_relay_refresh_ms = 9564ms
[BENCHMARK] sim_relay_warm_ms = 110ms
[BENCHMARK] sim_reserve_rpc_ms = 0ms
[BENCHMARK] sim_circuit_address_wait_ms = 9453ms
[BENCHMARK] sim_reservation_path = poll_fallback
[BENCHMARK] sim_reservation_winner_peer = 12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
[BENCHMARK] sim_personal_reregister_ms = 45ms
```

`BR-Sim degraded`:

```text
[BENCHMARK] sim_background_resume_recovery_start_source = relay_state_push
[BENCHMARK] sim_background_resume_recovery_source = relay_state_push
[BENCHMARK] sim_background_resume_reused_host = true
[BENCHMARK] sim_background_resume_coalesced_recovery_requests = 0
[BENCHMARK] sim_background_resume_relay_refresh_ms = 9750ms
[BENCHMARK] sim_background_resume_relay_warm_ms = 95ms
[BENCHMARK] sim_background_resume_reserve_rpc_ms = 0ms
[BENCHMARK] sim_background_resume_circuit_address_wait_ms = 9654ms
[BENCHMARK] sim_background_resume_reservation_path = poll_fallback
[BENCHMARK] sim_background_resume_reservation_winner_peer = 12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
[BENCHMARK] sim_background_resume_personal_reregister_ms = 44ms
```

Observation:
- `sim_background_resume_to_recovery_start_ms` was not emitted in the live degraded-resume rerun because the current branch had already begun recovery from the degraded `relay:state` push before the captured foreground resume window. That is an attribution finding about existing behavior on this branch, not a new behavioral change introduced by this instrumentation pass.
- `groupReregisterMs` was added to the lifecycle completion event, but it was not exercised by the benchmark subset because these harnesses do not pass group repositories into `handleAppResumed`.

## Acceptance Verdict

Instrumentation accepted:
- `yes`

Reason:
- The headline recovery metrics stayed within the section `8` `±5%` allowance against the frozen Phase `0` rerun baseline.
- The work stayed additive: it exposed recovery-start attribution, host reuse, coalescing, and sub-step timings without intentionally changing the recovery algorithm.
- The new rows now show that the current branch's relay recovery time is dominated by the circuit-address wait path, not by relay warm-up or personal rendezvous re-registration.

Stop point:
- This report stops after the section `8` instrumentation-first pass.
