#!/bin/bash
# DIAG ONLY: debug APK from build/wt-diag with LAN dial off (the relay-only default lives in that
# throwaway worktree). Logs to a file.  host-run bash docker-ws/build_diag_relay_only_apk.sh <log under build/kayan-safe/>
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; LOG="$REPO/${1:?log}"
cd "$REPO/build/wt-diag" || exit 2
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
{ echo "head $(git rev-parse --short HEAD) dirty=$(git status --porcelain | wc -l | tr -d ' ')"; git diff --stat
  flutter pub get --offline --enforce-lockfile && flutter build apk --debug --no-pub \
    --dart-define-from-file=tool/build/voice_call_release_defines.json --dart-define=MKNOON_ENABLE_LIBP2P_LAN_DIAL=false \
    --android-project-arg=enableAndroidNativeCalls=true; echo "exit=$?"; } > "$LOG" 2>&1
tail -1 "$LOG"
