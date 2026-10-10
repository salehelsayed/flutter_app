#!/bin/bash
# Plan 406: build the iOS (app + NSE) and Android gomobile bindings in the
# go-upgrade-406 worktree with go1.27.1 + the pinned gomobile, then run the iOS
# binary gate. Self-detaches; log in g406_bindings.log.
set -u
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
OUT=$W/g406_bindings.log
if [ -z "${G406B_DETACHED:-}" ]; then
  G406B_DETACHED=1 nohup bash "$0" "$@" >"$OUT" 2>&1 &
  echo "detached pid $! log $OUT"; exit 0
fi
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$HOME/go/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
WT=/Volumes/CrucialX9/flutter_app/.claude/worktrees/go-upgrade-406
cd "$WT" || exit 1
date; sw_vers -productVersion; go version; GOTOOLCHAIN=go1.27.1 go version
echo "=== ios"
bash scripts/ensure_go_ios_bindings.sh; echo "IOS EXIT=$?"
echo "=== android"
bash scripts/ensure_go_android_bindings.sh; echo "ANDROID EXIT=$?"
echo "=== tools"
go-mknoon/bin/tools/gomobile version 2>&1 | head -2
echo "=== artifacts"
ls -la ios/Runner/GoMknoon.xcframework ios/Runner/GoMknoonNSE.xcframework android/app/libs/GoMknoon.aar 2>&1 | head -12
for f in ios/Runner/GoMknoon.xcframework/ios-arm64/GoMknoon.framework/GoMknoon; do
  [ -f "$f" ] && echo "go version in $f: $(go version "$f" 2>&1 | head -1)"
done
unzip -l android/app/libs/GoMknoon.aar 2>/dev/null | grep -E "jni/.*\.so" | head -5
date; echo "BINDINGS DONE"
