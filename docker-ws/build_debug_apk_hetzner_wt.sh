#!/bin/bash
# Build a debug APK for the Hetzner TEST relay (update check off) inside a prepared worktree under build/.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/build_debug_apk_hetzner_wt.sh <tree under build/> <log-file-in-repo> [build-number]
# The optional build number lets the APK install over a newer debug build on a test phone (local flag, no source change).
set -uo pipefail
REPO=/Volumes/CrucialX9/flutter_app; WT="$REPO/build/${1:?tree}"; LOG="$REPO/${2:?log}"; BN=${3:+--build-number=$3}; XD=${4:-}
export ANDROID_HOME="$HOME/Library/Android/sdk" JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export PATH="$HOME/development/flutter-3.47.2/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$WT" || exit 2
{ flutter pub get --offline --enforce-lockfile && \
  flutter build apk --debug --no-pub --dart-define-from-file=tool/build/voice_call_release_defines.json \
    --android-project-arg=enableAndroidNativeCalls=true $BN \
    --dart-define=MKNOON_UPDATE_CHECK=off $XD \
    --dart-define=MKNOON_RELAY_ADDRESSES=/dns4/2-29-62-121.sslip.io/tcp/4001/wss/p2p/12D3KooWB2HGqKUNt9sXigsrM3oxHsHRbqsx5TCNaBghSiebiwXM,/dns4/2-29-62-121.sslip.io/udp/4002/quic-v1/p2p/12D3KooWB2HGqKUNt9sXigsrM3oxHsHRbqsx5TCNaBghSiebiwXM; } >> "$LOG" 2>&1
rc=$?; echo "exit=$rc" >> "$LOG"; ls -l build/app/outputs/flutter-apk/app-debug.apk >> "$LOG" 2>&1; exit "$rc"
