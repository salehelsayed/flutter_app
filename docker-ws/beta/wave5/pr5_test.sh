#!/bin/bash
# Run PR 5's unit test and the related test files at the PR commit in the wave3-next worktree, then restore the worktree.
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next; SDK=$HOME/development/flutter-3.47.2
cd "$W" || exit 1
orig=$(git rev-parse --abbrev-ref HEAD)
git checkout -q --detach origin/fix/relay-outage-self-healed-recovered && echo "at $(git log -1 --format=%h)"
"$SDK/bin/flutter" test test/core/services/p2p_service_impl_test.dart --plain-name "self-healed outage" 2>&1 | grep -E "All tests passed|Some tests failed|\[E\]" | tail -2
"$SDK/bin/flutter" test test/core/services/p2p_service_impl_test.dart test/performance/benchmark_relay_recovery_test.dart test/performance/benchmark_background_resume_test.dart test/integration/production_performance_criteria_test.dart 2>&1 | grep -E "All tests passed|Some tests failed|\[E\]" | tail -4
git checkout -q "$orig" && echo "restored $(git log -1 --format=%h) on $orig"
