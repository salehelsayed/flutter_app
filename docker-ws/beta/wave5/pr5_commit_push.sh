#!/bin/bash
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
git add lib/core/services/p2p_service_impl.dart test/core/services/p2p_service_impl_test.dart tool/sims/production_performance_criteria.dart test/integration/production_performance_criteria_test.dart
git commit -q -F - <<'MSG'
fix(p2p): report a self-healed relay outage as its own phase

Review follow-up. The first commit closed a self-healed outage with phase
`recovered`, but the original benchmarks read every `recovered` event as an
app-driven reconnect: benchmark_relay_recovery_harness casts
`relayRefreshMs`/`relayWarmMs`/`reserveRpcMs` with `as num`, and
benchmark_background_resume_harness takes the first `recovered` event and
does the same. A self-healed event has none of these fields, so both would
crash with a TypeError whenever the node healed an outage itself.

- Close self-healed outages with phase `self_healed` (one helper, still
  clearing `_outageDetectedAt`, which is the correctness fix).
- Also close the outage when an in-flight reconnect reports failure while
  the node has already healed the relay.
- production_performance_criteria accepts `recovered` or `self_healed` for
  "degraded recovered outage timing".
- Tests: the self-healed test now expects `self_healed` and no `recovered`;
  new tests for the failed in-flight reconnect and for both criteria cases.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
MSG
git log -2 --format='%h %s' | cut -c1-90
git push origin HEAD:fix/relay-outage-self-healed-recovered 2>&1 | tail -2
