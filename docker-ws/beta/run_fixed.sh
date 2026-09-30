#!/bin/bash
# Rerun of the call suite on the FIXED build + fix-specific checks.
H="$(dirname "$0")"
. "$H/beta_env.sh"
bash "$H/logs_start.sh"
RUN=$(current_run)
cp "$BETA/build/provenance.txt" "$BETA/build/build_name.txt" "$RUN/" 2>/dev/null
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
sleep 1; kill "$(cat "$RUN/logcat.pid")" 2>/dev/null; pgrep -f "logcat -T 1 -v threadtime" | tail -1 > "$RUN/logcat.pid"
bash "$H/install_fixed.sh" rel
sleep 25
# --- F1: CallKit build, simulator CallKit ends the outgoing call natively
bash "$H/pair.sh" s11_callkit s11_callkit_ios.yaml s11_callkit_android.yaml
# --- switch iPhone to the in-app call UI build
bash "$H/install_fixed.sh" nock
sleep 25
for s in s05a s05b s05c s05d s05e; do bash "$H/pair.sh" ${s}_fixed ${s}_ios.yaml ${s}_android.yaml; done
bash "$H/dump_ui.sh" chat_fixed
# --- F4: Back x3 during a connected call
bash "$H/pair.sh" s09_back s09_back_ios.yaml s09_back_android.yaml
# --- F2: network drop on the Pixel during a connected call
echo "[$(date '+%H:%M:%S')] s10 start" >> "$RUN/timeline.txt"
bash "$H/pair.sh" s10_netdrop connect_ios_caller.yaml connect_android_callee.yaml TAG=s10 HOLD=75000 &
P=$!; sleep 45
echo "[$(date '+%H:%M:%S')] s10 pixel network OFF" >> "$RUN/timeline.txt"
$ADB shell svc wifi disable; $ADB shell svc data disable
sleep 60
$ADB shell svc wifi enable; $ADB shell svc data enable
echo "[$(date '+%H:%M:%S')] s10 pixel network ON" >> "$RUN/timeline.txt"
wait $P
sleep 20
bash "$H/pair.sh" s10_after cal_ensure.yaml cal_ensure.yaml
# --- F3: Pixel app swiped away from Recents during a connected call
echo "[$(date '+%H:%M:%S')] s12 start" >> "$RUN/timeline.txt"
bash "$H/pair.sh" s12_recents connect_ios_caller.yaml connect_android_callee.yaml TAG=s12 HOLD=60000 &
P=$!; sleep 45
echo "[$(date '+%H:%M:%S')] s12 pixel HOME + recents swipe" >> "$RUN/timeline.txt"
$ADB shell input keyevent KEYCODE_HOME; sleep 2
$ADB shell input keyevent KEYCODE_APP_SWITCH; sleep 3
$ADB exec-out screencap -p > "$RUN/screens/s12_recents.png"
$ADB shell input swipe 540 1300 540 150 300
sleep 2; $ADB exec-out screencap -p > "$RUN/screens/s12_after_swipe.png"
echo "[$(date '+%H:%M:%S')] s12 swiped; app pid now: $($ADB shell pidof $PKG)" >> "$RUN/timeline.txt"
wait $P
$ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 20
bash "$H/pair.sh" s12_after cal_ensure.yaml cal_ensure.yaml
bash "$H/logs_stop.sh" > /dev/null 2>&1
echo "FIXED RUN DONE $(date '+%H:%M:%S')" >> "$RUN/timeline.txt"
