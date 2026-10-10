#!/bin/bash
# PR 10 check in the wave3-next worktree: main + PR merged (not committed), conversation tests,
# analyzer, then the new test without the lib fix (must fail). Restores the worktree.
set -u
WT=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
SDK=$HOME/development/flutter-3.47.2/bin/flutter
cd "$WT" || exit 1
git checkout -q --detach main && git merge -q --no-commit --no-ff origin/fix/group-info-leave-confirmation && echo "merged onto $(git rev-parse --short HEAD): ok"
echo "=== analyze"; "$SDK" analyze --no-pub lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/presentation/group_info_wired_test.dart 2>&1 | tail -1
echo "=== tests (with fix)"; "$SDK" test --no-pub --concurrency 3 --reporter failures-only test/features/groups/presentation/group_info_wired_test.dart 2>&1 | grep -v '^\[' | tail -3
echo "=== new test without the lib fix"
git show main:lib/features/groups/presentation/screens/group_info_wired.dart > lib/features/groups/presentation/screens/group_info_wired.dart
"$SDK" test --no-pub --reporter failures-only test/features/groups/presentation/group_info_wired_test.dart --name 'Group Info asks before leaving and Cancel keeps the group$' 2>&1 | grep -E 'Timed out|overflowed|Expected|Actual|passed|failed' | head -4
git merge --abort 2>/dev/null; git reset -q --hard; git checkout -q wave3-next && echo "restored $(git rev-parse --abbrev-ref HEAD) $(git rev-parse --short HEAD) clean=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
