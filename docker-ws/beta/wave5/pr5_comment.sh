#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app || exit 1
gh pr comment 5 --body-file - <<'BODY'
Review follow-up in 0ae068a99 (the description above still says `phase: "recovered"`; it is now `self_healed`).

**Why:** the original benchmarks read every `RELAY_OUTAGE_TIMING` `recovered` event as an app-driven reconnect. `integration_test/benchmark_relay_recovery_harness.dart` casts `relayRefreshMs`, `relayWarmMs` and `reserveRpcMs` with `as num` for each one, and `benchmark_background_resume_harness.dart` takes the first `recovered` event and does the same. A self-healed event has none of these fields, so both would throw a TypeError whenever the node healed an outage itself. The originals must stay unchanged.

**Changes:**
- Self-healed outages close with `{phase: "self_healed", totalOutageMs, recoveryMode: "node_self_healed", recoverySource}`; `_outageDetectedAt` is still cleared.
- The outage is also closed when an in-flight `relay:reconnect` reports failure after the node has already healed the relay.
- `tool/sims/production_performance_criteria.dart` accepts `recovered` or `self_healed` for "degraded recovered outage timing".
- Tests: the self-healed test expects `self_healed` and no `recovered`; new tests for the failed in-flight reconnect and for both criteria cases.

**Verified:** `flutter test test/core/services/ test/performance/benchmark_relay_recovery_test.dart test/performance/benchmark_background_resume_test.dart test/performance/benchmark_time_to_online_test.dart test/integration/production_performance_criteria_test.dart` 579 passed; graph-affected tests plus `test/integration/` 3,142 passed; `dart analyze` clean. Not re-run on a device after this follow-up.
BODY
