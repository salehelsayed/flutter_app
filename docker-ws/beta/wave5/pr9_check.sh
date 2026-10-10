#!/bin/bash
# PR 9 check in the wave3-next worktree: main + PR merged (not committed), conversation tests,
# analyzer, then the new test without the lib fix (must fail). Restores the worktree.
set -u
WT=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
SDK=$HOME/development/flutter-3.47.2/bin/flutter
cd "$WT" || exit 1
git checkout -q --detach main && git merge -q --no-commit --no-ff origin/fix/conversation-photo-keyboard-overflow && echo "merged onto $(git rev-parse --short HEAD): ok"
echo "=== analyze"; "$SDK" analyze --no-pub lib/features/conversation/presentation/screens/conversation_screen.dart lib/features/conversation/presentation/widgets/attachment_preview_strip.dart test/features/conversation/presentation/screens/conversation_screen_test.dart 2>&1 | tail -1
echo "=== tests (with fix)"; "$SDK" test --no-pub --concurrency 3 --reporter failures-only test/features/conversation/presentation/screens/conversation_screen_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart test/features/conversation/presentation/widgets/ 2>&1 | grep -v '^\[' | tail -3
echo "=== new test without the lib fix"
git show main:lib/features/conversation/presentation/screens/conversation_screen.dart > lib/features/conversation/presentation/screens/conversation_screen.dart
"$SDK" test --no-pub --reporter failures-only test/features/conversation/presentation/screens/conversation_screen_test.dart --name 'a staged photo and the keyboard still fit a short viewport$|attaching a photo with the keyboard open collapses the chrome$' 2>&1 | grep -E 'overflowed|Expected|Actual|passed|failed' | head -4
git merge --abort 2>/dev/null; git reset -q --hard; git checkout -q wave3-next && echo "restored $(git rev-parse --abbrev-ref HEAD) $(git rev-parse --short HEAD) clean=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
