#!/bin/bash
# Third fixed-build pass: S09 (F4 Back), S10 (F2 network drop), S12 (F3 recents swipe).
# Differences from run_fixed2.sh:
#  * readiness gate before each call (adb latency, real clock skew, Pixel Dart
#    isolate alive, fresh Pixel->iPhone ping); result goes to the timeline
#  * native + Dart call diagnostics captured for each scenario window
#  * timestamps compared with the date part, so a run can cross midnight
#  * optional install: run_fixed3.sh [install]  (installs $BETA/build rel + nock first)
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh"
RUN=$(current_run)
. "$H/gates.sh"
cp "$BETA/build/provenance.txt" "$BETA/build/build_name.txt" "$RUN/" 2>/dev/null
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
pkill -f "adb -s $SERIAL logcat -T 1 -v threadtime" 2>/dev/null   # stray streams of stopped runs
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
sleep 1; pgrep -f "logcat -T 1 -v threadtime" | tail -1 > "$RUN/logcat.pid"
if [ "${1:-}" = "install" ]; then
  bash "$H/install_fixed.sh" rel
  bash "$H/install_fixed.sh" nock
fi
echo "[$(date '+%H:%M:%S')] builds: android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' ')" >> "$RUN/timeline.txt"
bash "$H/dump_ui.sh" warmup > /dev/null 2>&1
echo "[$(date '+%H:%M:%S')] maestro warm-up done" >> "$RUN/timeline.txt"

utc_now() { date -u '+%H:%M:%S'; }
diag() {  # diag <label> <utc start> <utc end>
  bash "$H/call_diag_windows.sh" "$2-$3" > "$RUN/diag_$1.txt" 2>&1
}
ready() {
  $ADB shell svc wifi enable; $ADB shell svc data enable
  $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 25
  bash "$H/pair.sh" ready_$1 cal_ensure.yaml cal_ensure.yaml
  gate "$1"
  echo "[$(date '+%H:%M:%S')] ready for $1 (app pid $($ADB shell pidof $PKG))" >> "$RUN/timeline.txt"
}
wait_media_connected() {  # up to 120 s for a mediaConnected transition in the last 2 min
  local since i
  for i in $(seq 1 60); do
    since=$($ADB shell date -d "@\$((\$(date +%s)-120))" "'+%m-%d %H:%M:%S'" 2>/dev/null | tr -d '\r')
    [ -z "$since" ] && since="00-00 00:00:00"
    tail -c 3000000 "$RUN/android_logcat_live.txt" | grep '"trigger":"mediaConnected"' \
      | awk -v s="$since" '($1 " " $2) >= s' | grep -q . && return 0
    sleep 2
  done
  return 1
}

ready s09
t0=$(utc_now)
bash "$H/pair_callee_first.sh" s09_back s09_back_ios.yaml s09_back_android.yaml
diag s09 "$t0" "$(utc_now)"

ready s10
t0=$(utc_now)
echo "[$(date '+%H:%M:%S')] s10 start" >> "$RUN/timeline.txt"
bash "$H/pair_callee_first.sh" s10_netdrop connect_ios_caller.yaml connect_android_callee.yaml TAG=s10 HOLD=75000 &
P=$!
if wait_media_connected; then
  sleep 10
  echo "[$(date '+%H:%M:%S')] s10 pixel network OFF" >> "$RUN/timeline.txt"
  $ADB shell svc wifi disable; $ADB shell svc data disable
  sleep 50
  $ADB shell svc wifi enable; $ADB shell svc data enable
  echo "[$(date '+%H:%M:%S')] s10 pixel network ON" >> "$RUN/timeline.txt"
else
  echo "[$(date '+%H:%M:%S')] s10 no mediaConnected within 120 s; network left on" >> "$RUN/timeline.txt"
fi
wait $P
diag s10 "$t0" "$(utc_now)"

ready s12
t0=$(utc_now)
echo "[$(date '+%H:%M:%S')] s12 start" >> "$RUN/timeline.txt"
bash "$H/pair_callee_first.sh" s12_recents connect_ios_caller.yaml connect_android_callee.yaml TAG=s12 HOLD=60000 &
P=$!
if wait_media_connected; then
  sleep 10
  echo "[$(date '+%H:%M:%S')] s12 pixel HOME + recents swipe" >> "$RUN/timeline.txt"
  $ADB shell input keyevent KEYCODE_HOME; sleep 2
  $ADB shell input keyevent KEYCODE_APP_SWITCH; sleep 3
  $ADB exec-out screencap -p > "$RUN/screens/s12_recents.png"
  $ADB shell input swipe 540 1300 540 150 300
  sleep 2; $ADB exec-out screencap -p > "$RUN/screens/s12_after_swipe.png"
  echo "[$(date '+%H:%M:%S')] s12 swiped; app pid now: $($ADB shell pidof $PKG)" >> "$RUN/timeline.txt"
else
  echo "[$(date '+%H:%M:%S')] s12 no mediaConnected within 120 s; no swipe" >> "$RUN/timeline.txt"
fi
wait $P
diag s12 "$t0" "$(utc_now)"

ready end
bash "$H/logs_stop.sh" > /dev/null 2>&1
echo "FIXED3 RUN DONE $(date '+%H:%M:%S')" >> "$RUN/timeline.txt"
