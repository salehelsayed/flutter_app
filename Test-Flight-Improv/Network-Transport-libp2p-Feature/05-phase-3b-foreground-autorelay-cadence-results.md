# Phase 3b Foreground AutoRelay Cadence Results

Source of truth:
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md`

Run date:
- `2026-04-17` (`Europe/Berlin`)

Branch:
- `timing-phase3b`

Primary simulator:
- `iPhone 17 Pro` (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`)

Baseline before:
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/05-section-8-instrumentation-first-results-2026-04-17.md`

## Final values used

- host AutoRelay backoff: `autorelay.WithBackoff(1 * time.Second)`
- host AutoRelay min interval: `autorelay.WithMinInterval(1 * time.Second)`
- foreground resume relay dial timeout: `3 * time.Second`
- foreground circuit-address wait window: `3 * time.Second`
- fallback safety wait retained: remaining `7 * time.Second` of the existing `10 * time.Second` total budget

Relaxation required:
- `no`

Notes:
- The Phase 3b cadence retune currently applies to the node's global AutoRelay host configuration, not to a strictly foreground-only AutoRelay policy.
- The foreground-specific behavior in this phase is the `3s` relay dial timeout plus the short `3s` circuit-address wait window before falling back to the remaining safety budget.
- The first simulator `C-Sim` attempt after the code change still loaded the stale iOS `GoMknoon.xcframework`; it was discarded.
- All benchmark numbers below come from reruns after `./scripts/ensure_go_ios_bindings.sh` rebuilt the iOS gomobile framework at `2026-04-17 18:14:44` local time.

## Commands used

Direct verification:

```bash
cd go-mknoon && go test ./node -run 'TestRefreshRelaySession_' -count=1
cd go-mknoon && go test ./bridge -run '^TestRelayReconnect_ReturnsStructuredRecoveryFields$' -count=1
flutter test test/performance/benchmark_relay_recovery_test.dart
flutter test test/performance/benchmark_background_resume_test.dart
flutter test test/core/services/p2p_service_impl_test.dart
```

Bridge refresh plus simulator evidence:

```bash
./scripts/ensure_go_ios_bindings.sh
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_relay_recovery_harness.dart > /tmp/phase3b_c_rerun_2026-04-17.log 2>&1
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_background_resume_harness.dart > /tmp/phase3b_br_2026-04-17.log 2>&1
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/benchmark_time_to_online_harness.dart > /tmp/phase3b_m_2026-04-17.log 2>&1
flutter test --timeout none -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/background_reconnect_test.dart > /tmp/phase3b_background_reconnect_2026-04-17.log 2>&1
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh transport > /tmp/phase3b_transport_gate_2026-04-17.log 2>&1
```

## Direct test result

Passed:
- `go test ./node -run 'TestRefreshRelaySession_' -count=1`
- `go test ./bridge -run '^TestRelayReconnect_ReturnsStructuredRecoveryFields$' -count=1`
- `flutter test test/performance/benchmark_relay_recovery_test.dart`
- `flutter test test/performance/benchmark_background_resume_test.dart`
- `flutter test test/core/services/p2p_service_impl_test.dart`

## Benchmark before / after

Headline metrics against the instrumentation-first baseline:

| Metric | Before | After | Delta |
| --- | ---: | ---: | ---: |
| `C-Sim p50` | `9100ms` | `1279ms` | `-7821ms` (`-85.9%`) |
| `C-Sim p95` | `9297ms` | `1368ms` | `-7929ms` (`-85.3%`) |
| `BR-Sim degraded` | `9098ms` | `1275ms` | `-7823ms` (`-86.0%`) |
| `BR-Sim healthy` | `108ms` | `90ms` | `-18ms` (`-16.7%`) |
| `BR-Sim extended healthy` | `96ms` | `101ms` | `+5ms` (`+5.2%`) |
| `M cold-start p50` | `155ms` | `159ms` | `+4ms` (`+2.6%`) |
| `M cold-start p95` | `169ms` | `175ms` | `+6ms` (`+3.6%`) |
| `M recovery badge` | `9598ms` | `1751ms` | `-7847ms` (`-81.8%`) |

Supporting rows from the rerun logs:
- `C-Sim-1 recovered outage`: `1752ms`
- `C-Sim-1 recovery badge`: `1761ms`
- `BR-Sim-1 healthy`: `90ms`
- `BR-Sim-3 extended healthy`: `101ms`
- `M-Sim-3 source distribution`: `relay_state_push=5/5`

## Attribution verdict

Foreground success beat background fallback:
- `yes`

Observed counts in rerun logs:
- `foreground_success`: `5`
- `background_fallback`: `0`

Representative `C-Sim-1` rows, normalized where count fields should not be read as durations:

```text
[BENCHMARK] sim_relay_warm_parallelism = 1 (count)
[BENCHMARK] sim_foreground_recovery_path = foreground_success
[BENCHMARK] sim_foreground_relay_dial_timeout_ms = 3000ms
[BENCHMARK] sim_autorelay_retry_cadence_ms = 1000ms
[BENCHMARK] sim_circuit_address_wait_ms = 1612ms
[BENCHMARK] sim_recovery_time_to_online_ms = 1761ms
```

Representative `BR-Sim-2` rows, normalized where count fields should not be read as durations:

```text
[BENCHMARK] sim_background_resume_degraded_ms = 1275ms
[BENCHMARK] sim_background_resume_recovery_start_source = relay_state_push
[BENCHMARK] sim_background_resume_recovery_source = relay_state_push
[BENCHMARK] sim_background_resume_relay_warm_parallelism = 1 (count)
[BENCHMARK] sim_background_resume_foreground_recovery_path = foreground_success
[BENCHMARK] sim_background_resume_foreground_relay_dial_timeout_ms = 3000ms
[BENCHMARK] sim_background_resume_autorelay_retry_cadence_ms = 1000ms
[BENCHMARK] sim_background_resume_circuit_address_wait_ms = 1610ms
```

Interpretation:
- The winning path is now the short foreground window, not the old long fallback wait.
- The cadence retune is currently global AutoRelay behavior on the host. This phase did not land a separate foreground-only AutoRelay cadence policy.
- `reservationPath` still reports `poll_fallback` and `reserveRpcMs` stays `0`, which is expected because Phase 3b explicitly did not add the Phase 3a direct-reservation experiment.
- `relayWarmParallelism` is a relay count, not a duration. Live simulator runs only had one configured relay, so it stayed `1`; the new multi-relay parallel warm behavior is covered by `go test ./node -run 'TestRefreshRelaySession_WarmsRelaysInParallel'`.
- `circuitAddressWaitMs` is no longer the dominant 9-10 second bottleneck; it moved into the ~`0.8s` to `1.8s` range on the reruns.

## Regression result

`integration_test/background_reconnect_test.dart`:
- `All tests skipped.`
- This matches the pre-existing known behavior for the named simulator and is treated as a clean skip, not a failure.

`transport` gate:
- `pass`

Recorded from `/tmp/phase3b_transport_gate_2026-04-17.log`:
- `background_reconnect_test.dart`: clean skip
- `wifi_relay_fallback_smoke_test.dart`: pass
- `transport_e2e_test.dart`: pass
- `media_stable_id_smoke_test.dart`: pass

## Keep / revert recommendation

Recommendation:
- `keep`

Reason:
- The Phase 3b promotion bar is met.
- `C-Sim p50` and `BR-Sim-2` both improved by well over the required `1500ms`.
- Healthy resume stayed below the `150ms` guardrail.
- The foreground-success path won every observed degraded-recovery sample after the rebuilt bridge binary was in use.
- The accepted caveat is that the cadence retune currently affects global AutoRelay behavior, while the shorter dial timeout and short circuit-address wait remain the foreground-specific parts of this phase.
- The starting values of `1s` cadence and `3s` foreground dial timeout were stable enough in direct tests and simulator reruns, so no relaxation to `2s` or `4s` was needed.

Stop point:
- Phase 3b is complete and this report stops here.
