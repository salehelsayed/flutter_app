#!/bin/bash
# Full beta rerun on the fix build. Android and iOS are built from the same source:
# working tree synced 2026-09-26 00:05Z + patch 237e88dd5..362d930e2 (all fixes).
# Fix checks first, while the Mac is quiet: S09 (F4 Back), S10 (F2 network drop),
# S12 (F3 recents swipe). Then the call suite S05a-e, messaging S01-S04 (F5 label),
# offline delivery S06, restart S07, group S08, and S11 (F1 native end, CallKit build).
# Usage: run_full4.sh [install]   (install = put the new iOS nock app on the iPhone first)
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh"
RUN=$(current_run)
. "$H/gates.sh"
N=v26
TL="$RUN/timeline.txt"
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$TL"; }
cp "$BETA/build/ios_build_name.txt" "$BETA/build/ios_result.txt" "$RUN/" 2>/dev/null
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
pkill -f "adb -s $SERIAL logcat -T 1 -v threadtime" 2>/dev/null   # stray streams of stopped runs
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
sleep 1; pgrep -f "logcat -T 1 -v threadtime" | tail -1 > "$RUN/logcat.pid"

ios_version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>/dev/null
}
ios_install() {  # ios_install <nock|rel>: in-place install, data kept (identity + friendship)
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
  if xcrun simctl install "$UDID" "$BETA/build/Runner-$1.app"; then log "ios installed $1: $(ios_version)"
  else log "ios install $1 FAILED"; fi
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
}
if [ "${1:-}" = "install" ]; then ios_install nock
else xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null; xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1; fi
# Fresh app processes: the relay moved to a new address (51.21.194.144) on 2026-09-26.
$ADB shell am force-stop $PKG
log "apps restarted (relay address change); mknoun.xyz -> mac/ios-sim: $(dscacheutil -q host -a name mknoun.xyz | awk '/ip_address/ {print $2}' | tr '\n' ' ') emulator: $($ADB shell 'ping -c 1 -W 3 mknoun.xyz 2>&1 | head -1' | tr -d '\r')"
log "builds:android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') ios=$(ios_version)"
bash "$H/dump_ui.sh" warmup > /dev/null 2>&1
log "maestro warm-up done"

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
  log "ready for $1 (app pid $($ADB shell pidof $PKG))"
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

# ---------------- fix checks (the Pixel is the callee)
ready s09
t0=$(utc_now)
bash "$H/pair_callee_first.sh" s09_back s09_back_ios.yaml s09_back_android.yaml
diag s09 "$t0" "$(utc_now)"

ready s10
t0=$(utc_now)
log "s10 start"
bash "$H/pair_callee_first.sh" s10_netdrop connect_ios_caller.yaml connect_android_callee.yaml TAG=s10 HOLD=75000 &
P=$!
if wait_media_connected; then
  sleep 10
  log "s10 pixel network OFF"
  $ADB shell svc wifi disable; $ADB shell svc data disable
  sleep 50
  $ADB shell svc wifi enable; $ADB shell svc data enable
  log "s10 pixel network ON"
else
  log "s10 no mediaConnected within 120 s; network left on"
fi
wait $P
diag s10 "$t0" "$(utc_now)"

ready s12
bash "$H/dump_ui.sh" after_s10 > /dev/null 2>&1
t0=$(utc_now)
log "s12 start"
bash "$H/pair_callee_first.sh" s12_recents connect_ios_caller.yaml connect_android_callee.yaml TAG=s12 HOLD=60000 &
P=$!
if wait_media_connected; then
  sleep 10
  log "s12 pixel HOME + recents swipe"
  $ADB shell input keyevent KEYCODE_HOME; sleep 2
  $ADB shell input keyevent KEYCODE_APP_SWITCH; sleep 3
  $ADB exec-out screencap -p > "$RUN/screens/s12_recents.png"
  $ADB shell input swipe 540 1300 540 150 300
  sleep 2; $ADB exec-out screencap -p > "$RUN/screens/s12_after_swipe.png"
  log "s12 swiped; app pid now: $($ADB shell pidof $PKG)"
else
  log "s12 no mediaConnected within 120 s; no swipe"
fi
wait $P
diag s12 "$t0" "$(utc_now)"

# ---------------- call suite
ready s05
bash "$H/dump_ui.sh" after_s12 > /dev/null 2>&1
t0=$(utc_now)
bash "$H/pair_callee_first.sh" s05a s05a_ios.yaml s05a_android.yaml; sleep 10
bash "$H/pair.sh" s05b s05b_ios.yaml s05b_android.yaml; sleep 10
bash "$H/pair.sh" s05c s05c_ios.yaml s05c_android.yaml; sleep 10
bash "$H/pair_callee_first.sh" s05d s05d_ios.yaml s05d_android.yaml; sleep 10
bash "$H/pair.sh" s05e s05e_ios.yaml s05e_android.yaml
diag s05 "$t0" "$(utc_now)"

# ---------------- messaging, F5 voice label, F6 identifiers
ready msg
bash "$H/pair.sh" s01_text s01_text_ios.yaml s01_text_android.yaml NONCE=$N
bash "$H/pair.sh" s02_react s02_react_ios.yaml s02_react_android.yaml NONCE=$N
bash "$H/pair.sh" s03_edit s03_edit_ios.yaml s03_edit_android.yaml NONCE=$N
bash "$H/pair.sh" s04_voice s04_voice_ios.yaml s04_voice_android.yaml \
  'IOS_VOICE_RX=(Voice message.)?Beta iPhone.(Voice message.)?0:[0-9][0-9].*' \
  'ANDROID_VOICE_RX=(Voice message.)?Beta Pixel.(Voice message.)?0:[0-9][0-9].*'
bash "$H/dump_ui.sh" after_s04 > /dev/null 2>&1

# ---------------- offline delivery, cold restart, group
bash "$H/pair.sh" s06a_stop - stop_app.yaml
bash "$H/pair.sh" s06a_send send_many.yaml - NONCE=$N P=OFFI
sleep 20
bash "$H/pair.sh" s06a_recv - relaunch_wait.yaml NONCE=$N P=OFFI
bash "$H/pair.sh" s06b_stop stop_app.yaml -
bash "$H/pair.sh" s06b_send - send_many.yaml NONCE=$N P=OFFA
sleep 20
bash "$H/pair.sh" s06b_recv relaunch_wait.yaml - NONCE=$N P=OFFA
bash "$H/pair.sh" s07_restart s07_restart_h.yaml s07_restart_h.yaml NONCE=$N "HIST=OFFA3 offline msg $N"
bash "$H/pair.sh" s08_group s08_create_ios.yaml s08_accept_android.yaml NONCE=$N

# ---------------- S11: F1, native end of an unanswered call (CallKit build on the iPhone)
bash "$H/pair.sh" to_chat - to_chat.yaml
# CallKit app from fix c8be267bd: same iPhone call code as 362d930e2 (the later fixes are
# Android-only plus incoming-side logging), so it is valid for this caller-side check.
ios_install rel-c8be267bd
sleep 20
t0=$(utc_now)
bash "$H/pair_callee_first.sh" s11_callkit s11_callkit_ios.yaml s11_callkit_android.yaml
diag s11 "$t0" "$(utc_now)"
bash "$H/dump_ui.sh" after_s11 android > /dev/null 2>&1
ios_install nock
sleep 20

ready end
bash "$H/dump_ui.sh" final > /dev/null 2>&1
bash "$H/logs_stop.sh" > /dev/null 2>&1
log "FULL4 RUN DONE"
