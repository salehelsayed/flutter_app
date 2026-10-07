#!/bin/bash
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
$HOME/development/flutter-3.47.2/bin/flutter test test/core/bootstrap/production_canonical_group_replay_application_test.dart test/core/bootstrap/production_canonical_group_replay_transport_test.dart test/core/bridge/go_bridge_client_test.dart test/integration/ 2>&1 | grep -E "All tests passed|Some tests failed|\[E\]" | tail -5
