#!/bin/bash
# Probe: build the E2E debug APK in a tree with full output to a log (to see errors the sims summary truncates).
#   host-run bash docker-ws/debug_e2e_build_probe.sh <tree under build/> <log under repo> [applicationId]
M=/Volumes/CrucialX9/flutter_app; W=$M/build/${1:?tree}; L=$M/${2:?log}
export ANDROID_HOME="$HOME/Library/Android/sdk"; export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export PATH="$HOME/development/flutter-3.47.2/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$W" || exit 2
[ -n "${3:-}" ] && export ORG_GRADLE_PROJECT_androidApplicationId="$3"
flutter build apk --debug --dart-define=E2E_TEST_MODE=true > "$L" 2>&1; rc=$?; echo "exit=$rc" >> "$L"; echo "exit=$rc"
grep -n -i -E "error|what went wrong|failed|exception" "$L" | head -25
