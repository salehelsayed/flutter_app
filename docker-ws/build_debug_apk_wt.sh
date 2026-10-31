#!/bin/bash
# Build a plain debug APK (default debug signing key) inside an existing prepared worktree under build/.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/build_debug_apk_wt.sh <tree under build/> <log-file-in-repo>
set -uo pipefail
REPO=/Volumes/CrucialX9/flutter_app; WT="$REPO/build/${1:?tree}"; LOG="$REPO/${2:?log}"
export ANDROID_HOME="$HOME/Library/Android/sdk" JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export PATH="$HOME/development/flutter-3.47.2/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$WT" || exit 2
{ flutter pub get --offline --enforce-lockfile && \
  flutter build apk --debug --no-pub --dart-define-from-file=tool/build/voice_call_release_defines.json \
    --android-project-arg=enableAndroidNativeCalls=true; } >> "$LOG" 2>&1
rc=$?; echo "exit=$rc" >> "$LOG"; ls -l build/app/outputs/flutter-apk/app-debug.apk >> "$LOG" 2>&1; exit "$rc"
