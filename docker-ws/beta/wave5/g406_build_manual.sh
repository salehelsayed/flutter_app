#!/bin/bash
# Plan 406: defines-free (no E2E) debug APKs so contact requests show a dialog. Old + new.
# bindings), NEW = go-upgrade-406 worktree (Go 1.27.1 bindings).
#   old.apk / new.apk : E2E debug arm64 APKs (seedable on emulators)
#   NEW iOS release Runner.app for the iPhone 13
# Self-detaches; log g406_build_all.log; artifacts in wave5/g406/.
set -u
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
OUT=$W/g406_build_manual.log
if [ -z "${G406BM_DETACHED:-}" ]; then
  G406BM_DETACHED=1 nohup bash "$0" "$@" >"$OUT" 2>&1 &
  echo "detached pid $! log $OUT"; exit 0
fi
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$HOME/go/bin:$PATH"
export FLUTTER_XCODE_CLANG_ENABLE_EXPLICIT_MODULES=NO
MAIN=/Volumes/CrucialX9/flutter_app
WT=$MAIN/.claude/worktrees/go-upgrade-406
ART=$W/g406; mkdir -p "$ART"
STAMP=$(date +%y%m%d%H%M%S); echo "STAMP=$STAMP" | tee "$ART/stamp.txt"

apk() { # <dir> <label>
  cd "$1" || return 1
  echo "=== $2 APK in $1 ($(git rev-parse --short HEAD))"; date
  flutter build apk --debug --target-platform=android-arm64 -t lib/main.dart \
    --dart-define-from-file=tool/build/voice_call_release_defines.json \
    \
    --android-project-arg=enableAndroidNativeCalls=true \
    --build-name="1.0.1-$2.t$STAMP" 2>&1 | tail -4
  local rc=${PIPESTATUS[0]}; echo "$2 APK exit=$rc"
  [ $rc = 0 ] && cp build/app/outputs/flutter-apk/app-debug.apk "$ART/$2.apk" && ls -la "$ART/$2.apk"
  unzip -p "$ART/$2.apk" lib/arm64-v8a/libgojni.so 2>/dev/null | strings | grep -m1 -oE "go1\.[0-9]+\.[0-9]+" | sed "s/^/$2 libgojni Go: /"
}
apk "$MAIN" old406m
apk "$WT" new406m

echo "BUILD MANUAL DONE"
