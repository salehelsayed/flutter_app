#!/bin/bash
# Build the call-enabled debug APK inside a worktree under build/ (copies the git-ignored Android inputs from main first).
#   host-run bash docker-ws/build_android_calls_debug_wt.sh <worktree-rel-path> <log-file-in-repo>
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WT="$REPO/${1:?worktree}"; LOG="$REPO/${2:?log}"
case "$WT" in "$REPO"/build/wt-*) ;; *) echo "refused: worktree must be build/wt-*"; exit 2;; esac
for f in android/app/libs/GoMknoon.aar android/app/libs/GoMknoon-sources.jar android/app/google-services.json android/local.properties android/key.properties; do
  [ -f "$REPO/$f" ] && mkdir -p "$(dirname "$WT/$f")" && cp -p "$REPO/$f" "$WT/$f"
done
cd "$WT" || exit 2
{ flutter pub get --offline --enforce-lockfile && \
  flutter build apk --debug --no-pub --dart-define-from-file=tool/build/voice_call_release_defines.json \
    --android-project-arg=enableAndroidNativeCalls=true; } > "$LOG" 2>&1
rc=$?; echo "exit=$rc" >> "$LOG"; exit "$rc"
