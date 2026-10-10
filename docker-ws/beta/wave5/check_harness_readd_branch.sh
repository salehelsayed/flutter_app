#!/bin/bash
# Read-only check of fix/original-multi-party-harness-readd in the wave3-next worktree:
# analyzer on the changed Dart files + the affected host tests. Restores the branch after.
set -u
WT=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
SDK=$HOME/development/flutter-3.47.2/bin/flutter
cd "$WT" || exit 1
echo "=== worktree status ==="; git status --short | grep -v '^?? ' | head
git checkout -q --detach 7a4551998 || exit 1
echo "HEAD $(git rev-parse --short HEAD)"
echo "=== analyze ==="
"$SDK" analyze --no-pub integration_test/group_multi_device_real_harness.dart \
  integration_test/group_multi_party_device_real_harness.dart \
  integration_test/scripts/run_group_multi_party_device_real.dart \
  test/integration/group_multi_party_launch_spec_test.dart 2>&1 | tail -8
echo "=== tests ==="
"$SDK" test --no-pub --reporter failures-only \
  test/integration/group_multi_party_launch_spec_test.dart \
  test/integration/group_multi_device_shared_path_test.dart \
  test/integration/group_multi_party_sweep_continue_test.dart \
  test/core/database/helpers/group_messages_db_helpers_reliability_test.dart \
  test/features/orbit/presentation/screens/orbit_wired_test.dart 2>&1 | tail -15
echo "exit=$?"
git checkout -q wave3-next && echo "restored $(git rev-parse --abbrev-ref HEAD) $(git rev-parse --short HEAD)"
