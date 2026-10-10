#!/bin/bash
# Plan 406: settle the three host-all reds. Copy the git-ignored iOS Firebase
# plist into the worktree, build the macOS binding, rerun the three tests in
# the worktree, and run DTR-10 on the main checkout (baseline). Self-detaches.
set -u
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
OUT=$W/g406_three.log
if [ -z "${G406T_DETACHED:-}" ]; then
  G406T_DETACHED=1 nohup bash "$0" "$@" >"$OUT" 2>&1 &
  echo "detached pid $! log $OUT"; exit 0
fi
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$PATH"
MAIN=/Volumes/CrucialX9/flutter_app
WT=$MAIN/.claude/worktrees/go-upgrade-406
cp -n "$MAIN/ios/Runner/GoogleService-Info.plist" "$WT/ios/Runner/GoogleService-Info.plist" && echo "plist copied"
cd "$WT" || exit 1
bash scripts/ensure_go_macos_bindings.sh 2>&1 | tail -3; echo "MACOS EXIT=${PIPESTATUS[0]}"
flutter test --no-pub --reporter failures-only test/core/bridge/wake_token_binary_freshness_test.dart test/features/push/application/ios_push_project_config_test.dart test/unit/runtime_root_inventory_test.dart 2>&1 | grep -vE "^\[FLOW\]" | tail -12
echo "WORKTREE EXIT=${PIPESTATUS[0]}"
echo "######## main checkout DTR-10"
cd "$MAIN" && git log --oneline -1 && flutter test --no-pub --reporter failures-only test/unit/runtime_root_inventory_test.dart --plain-name 'DTR-10' 2>&1 | grep -vE "^\[FLOW\]" | tail -8
echo "MAIN EXIT=${PIPESTATUS[0]}"
echo "THREE DONE"
