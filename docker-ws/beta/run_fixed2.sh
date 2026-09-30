#!/bin/bash
# Second fixed-build pass: S09 (F4 Back), S10 (F2 network drop), S12 (F3 recents swipe).
# Before each scenario the Pixel app is relaunched and given time to get online.
H="$(dirname "$0")"
. "$H/beta_env.sh"
bash "$H/logs_start.sh"
RUN=$(current_run)
cp "$BETA/build/provenance.txt" "$BETA/build/build_name.txt" "$RUN/" 2>/dev/null
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
sleep 1; pgrep -f "logcat -T 1 -v threadtime" | tail -1 > "$RUN/logcat.pid"
bash "$H/install_fixed.sh" rel
bash "$H/install_fixed.sh" nock
bash "$H/dump_ui.sh" warmup > /dev/null 2>&1
echo "[$(date '+%H:%M:%S')] maestro warm-up done" >> "$RUN/timeline.txt"
ready() {
  $ADB shell svc wifi enable; $ADB shell svc data enable
  $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 25
  bash "$H/pair.sh" ready_$1 cal_ensure.yaml cal_ensure.yaml
  echo "[$(date '+%H:%M:%S')] ready for $1 (app pid $($ADB shell pidof $PKG))" >> "$RUN/timeline.txt"
}
ready s09
bash "$H/pair.sh" s09_back s09_back_ios.yaml s09_back_android.yaml
ready s10
echo "[$(date '+%H:%M:%S')] s10 start" >> "$RUN/timeline.txt"
bash "$H/pair.sh" s10_netdrop connect_ios_caller.yaml connect_android_callee.yaml TAG=s10 HOLD=75000 &
P=$!
for i in $(seq 1 60); do grep -q '"trigger":"mediaConnected"' <(tail -c 3000000 "$RUN/android_logcat_live.txt" | awk -v t="$(date -v-2M '+%H:%M:%S')" '$2>=t') && break; sleep 2; done
sleep 10
echo "[$(date '+%H:%M:%S')] s10 pixel network OFF" >> "$RUN/timeline.txt"
$ADB shell svc wifi disable; $ADB shell svc data disable
sleep 50
$ADB shell svc wifi enable; $ADB shell svc data enable
echo "[$(date '+%H:%M:%S')] s10 pixel network ON" >> "$RUN/timeline.txt"
wait $P
ready s12
echo "[$(date '+%H:%M:%S')] s12 start" >> "$RUN/timeline.txt"
bash "$H/pair.sh" s12_recents connect_ios_caller.yaml connect_android_callee.yaml TAG=s12 HOLD=60000 &
P=$!
for i in $(seq 1 60); do grep -q '"trigger":"mediaConnected"' <(tail -c 3000000 "$RUN/android_logcat_live.txt" | awk -v t="$(date -v-2M '+%H:%M:%S')" '$2>=t') && break; sleep 2; done
sleep 10
echo "[$(date '+%H:%M:%S')] s12 pixel HOME + recents swipe" >> "$RUN/timeline.txt"
$ADB shell input keyevent KEYCODE_HOME; sleep 2
$ADB shell input keyevent KEYCODE_APP_SWITCH; sleep 3
$ADB exec-out screencap -p > "$RUN/screens/s12_recents.png"
$ADB shell input swipe 540 1300 540 150 300
sleep 2; $ADB exec-out screencap -p > "$RUN/screens/s12_after_swipe.png"
echo "[$(date '+%H:%M:%S')] s12 swiped; app pid now: $($ADB shell pidof $PKG)" >> "$RUN/timeline.txt"
wait $P
ready end
bash "$H/logs_stop.sh" > /dev/null 2>&1
echo "FIXED2 RUN DONE $(date '+%H:%M:%S')" >> "$RUN/timeline.txt"
