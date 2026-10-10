#!/bin/bash
# User-approved 2026-10-07: PR 9 comment-placement fix. Analyze + format + the screen
# tests, commit on the PR branch, push it, rebase-merge PR 9 on GitHub, sync local
# main and wave3-baseline-20260930, restore the worktree to wave3-next.
export PATH="/opt/homebrew/bin:$PATH"
set -u
WT=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
SDK=$HOME/development/flutter-3.47.2/bin
F=lib/features/conversation/presentation/screens/conversation_screen.dart
cd "$WT" || exit 1
git diff --stat
"$SDK/flutter" analyze --no-pub $F 2>&1 | tail -1
"$SDK/dart" format --output=none --set-exit-if-changed $F >/dev/null 2>&1 && echo "format ok" || { echo "FORMAT CHANGED - stop"; exit 1; }
"$SDK/flutter" test --no-pub --reporter failures-only test/features/conversation/presentation/screens/conversation_screen_test.dart 2>&1 | grep -v '^\[' | tail -1 | grep -q 'All tests passed' && echo "screen tests ok" || { echo "TESTS FAILED - stop"; exit 1; }
git commit -q -am "docs(conversation): keep ConversationScreen's doc comment on the class

The compact-keyboard constants were inserted between the class and its doc
comment, so the class lost its description. Move them above it.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git log --oneline -2
git push -q origin HEAD:fix/conversation-photo-keyboard-overflow && echo "pushed PR branch"
git checkout -q wave3-next && git branch -D pr9-docfix >/dev/null
cd /Volumes/CrucialX9/flutter_app
sleep 5
gh pr merge 9 --rebase 2>&1 | tail -2
gh pr view 9 --json state,mergedAt --jq '.state+" "+.mergedAt'
git fetch -q origin main
git log --oneline -4 origin/main
git merge --ff-only origin/main | tail -1
git branch -f main origin/main && echo "local main -> $(git rev-parse --short main)"
git push origin wave3-baseline-20260930 2>&1 | tail -1
git ls-remote origin refs/heads/main refs/heads/wave3-baseline-20260930
