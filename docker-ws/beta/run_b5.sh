#!/bin/bash
# B5 device regression. Android = the source that passed run-20260926-185802 + B5
# (f150d96d6, build/beta-android-b5.apk); iPhone unchanged (nock, fix-362d930e2).
# Calls only: S05a-e (incoming and outgoing registration paths) and S09 (Back).
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh"
RUN=$(current_run)
. "$H/gates.sh"
TL="$RUN/timeline.txt"
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$TL"; }
cp "$BETA/build/b5_build_name.txt" "$BETA/build/b5_result.txt" "$RUN/" 2>/dev/null
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
pkill -f "adb -s $SERIAL logcat -T 1 -v threadtime" 2>/dev/null
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
sleep 1; pgrep -f "logcat -T 1 -v threadtime" | tail -1 > "$RUN/logcat.pid"

log "android install: $($ADB install -r -d "$BETA/build/beta-android-b5.apk" 2>&1 | tail -1)"
$ADB shell am force-stop $PKG
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null; xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
ios_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>/dev/null)
log "builds: android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') ios=$ios_version"
log "mknoun.xyz -> mac/ios-sim: $(dscacheutil -q host -a name mknoun.xyz | awk '/ip_address/ {print $2}' | tr '\n' ' ') emulator: $($ADB shell 'ping -c 1 -W 3 mknoun.xyz 2>&1 | head -1' | tr -d '\r')"
bash "$H/dump_ui.sh" warmup > /dev/null 2>&1
log "maestro warm-up done"

utc_now() { date -u '+%H:%M:%S'; }
diag() { bash "$H/call_diag_windows.sh" "$2-$3" > "$RUN/diag_$1.txt" 2>&1; }
ready() {
  $ADB shell svc wifi enable; $ADB shell svc data enable
  $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 25
  bash "$H/pair.sh" ready_$1 cal_ensure.yaml cal_ensure.yaml
  gate "$1"
  log "ready for $1 (app pid $($ADB shell pidof $PKG))"
}

ready s05
t0=$(utc_now)
bash "$H/pair_callee_first.sh" s05a s05a_ios.yaml s05a_android.yaml; sleep 10
bash "$H/pair.sh" s05b s05b_ios.yaml s05b_android.yaml; sleep 10
bash "$H/pair.sh" s05c s05c_ios.yaml s05c_android.yaml; sleep 10
bash "$H/pair_callee_first.sh" s05d s05d_ios.yaml s05d_android.yaml; sleep 10
bash "$H/pair.sh" s05e s05e_ios.yaml s05e_android.yaml
diag s05 "$t0" "$(utc_now)"

ready s09
t0=$(utc_now)
bash "$H/pair_callee_first.sh" s09_back s09_back_ios.yaml s09_back_android.yaml
diag s09 "$t0" "$(utc_now)"

ready end
bash "$H/dump_ui.sh" final > /dev/null 2>&1
bash "$H/logs_stop.sh" > /dev/null 2>&1
log "B5 RUN DONE"
