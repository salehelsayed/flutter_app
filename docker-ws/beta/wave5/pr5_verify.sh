#!/bin/bash
# Verify the PR 5 follow-up in the wave3-next worktree: format only files that were clean before, analyze, test.
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next; SDK=$HOME/development/flutter-3.47.2
cd "$W" || exit 1
for f in lib/core/services/p2p_service_impl.dart tool/sims/production_performance_criteria.dart test/integration/production_performance_criteria_test.dart test/core/services/p2p_service_impl_test.dart; do
  if git show HEAD:"$f" | "$SDK/bin/dart" format --output=none --set-exit-if-changed --stdin-name="$f" >/dev/null 2>&1; then
    "$SDK/bin/dart" format "$f" | tail -1
  else echo "skip format (not clean before): $f"; fi
done
"$SDK/bin/dart" analyze lib/core/services/p2p_service_impl.dart tool/sims/production_performance_criteria.dart test/integration/production_performance_criteria_test.dart test/core/services/p2p_service_impl_test.dart 2>&1 | tail -3
"$SDK/bin/flutter" test test/core/services/ test/performance/benchmark_relay_recovery_test.dart test/performance/benchmark_background_resume_test.dart test/performance/benchmark_time_to_online_test.dart test/integration/production_performance_criteria_test.dart 2>&1 | grep -E "All tests passed|Some tests failed|\[E\]" | tail -6
git status --short
