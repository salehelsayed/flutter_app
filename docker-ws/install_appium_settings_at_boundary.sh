#!/bin/bash
# At the next C1 row boundary: install Appium Settings 8.0.8 (-r) on emulator-5556 and -5558, keep Gboard default.
#   host-run bash docker-ws/install_appium_settings_at_boundary.sh <logs dir> <current row id>
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; LOGS="$REPO/${1:?logs}"; ROW="${2:?row}"
SRC=/Volumes/CrucialX9/flutter_app_codex_pr15_t3elbg1o/.codex-test-logs/C1-gboard-readonly-20261019/working-appium-settings-8.0.8.apk
APK="$REPO/build/kayan-safe/f10/appium-settings-8.0.8.apk"; ADB="$HOME/Library/Android/sdk/platform-tools/adb"
cp "$SRC" "$APK" || exit 2
sha=$(shasum -a 256 "$APK" | awk '{print $1}'); size=$(wc -c < "$APK" | tr -d ' ')
echo "sha=$sha size=$size"
[ "$sha" = a55d2657cda821f78e4c48b6b8173ec0e947370012bb0771e7961a3a9c0c8546 ] && [ "$size" = 3076282 ] || { echo "FAIL apk check"; exit 3; }
for i in $(seq 1 1800); do grep -q '^exitCode=' "$LOGS/$ROW.log" 2>/dev/null && break; sleep 1; done
grep -q '^exitCode=' "$LOGS/$ROW.log" || { echo "FAIL row did not end in 30 min"; exit 4; }
echo "boundary $(date -u +%T) after $ROW"
"$ADB" devices | awk '/emulator-/'
for S in emulator-5556 emulator-5558; do
  "$ADB" -s "$S" install -r "$APK" 2>&1 | tail -1
  echo "$S $("$ADB" -s "$S" shell dumpsys package io.appium.settings | grep -m2 -E 'versionName|versionCode' | tr -s ' ' | tr '\n' ' ')"
  echo "$S ime_listed=$("$ADB" -s "$S" shell ime list -a -s | grep -c 'io.appium.settings/.AppiumIME')"
  echo "$S default=$("$ADB" -s "$S" shell settings get secure default_input_method)"
done
echo "next rows: $(ls -t "$LOGS" | head -2 | tr '\n' ' ') $(date -u +%T)"
