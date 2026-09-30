#!/bin/bash
# R2-8 follow-up checks (2026-09-29), build-r2-9 on both phones: declining from the Android call notification, and
# calls to a locked Pixel (screen off). Cases (default all):
#  D1  Pixel app in the background (unlocked): Decline on the call notification -> the iPhone must see "declined"
#  D2  Pixel app process killed (unlocked): Decline on the call notification  -> same
#  L1  Pixel app in the background, screen off: full-screen incoming screen over the lock screen, answer there
#  L2  Pixel app process killed, screen off: same
#  L3  Pixel app process killed, screen off, WITHOUT the "full-screen notifications" access (appop denied for the case,
#      restored after): record what the user gets, then wake the screen and answer from the lock screen if possible
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh" > /dev/null
RUN=$(current_run)
cp "$BETA/build-r2-9/build_name.txt" "$BETA/build-r2-9/provenance.txt" "$RUN/" 2>/dev/null
TL="$RUN/timeline.txt"
CASES="${*:-D1 D2 L1 L2 L3}"
F=r2
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$TL"; }
mkdir -p "$RUN/crash" "$RUN/extra" "$RUN/ui"
ls ~/Library/Logs/DiagnosticReports/ > "$RUN/crash/baseline_list.txt" 2>/dev/null
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
echo $! > "$RUN/logcat.pid"
IOS_T0=$(date '+%Y-%m-%d %H:%M:%S')
ios_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>/dev/null; }
fsi_mode() { $ADB shell cmd appops get $PKG USE_FULL_SCREEN_INTENT | tr -d '\r' | tr '\n' ' ' | cut -c1-120; }
FSI0=$(fsi_mode)
log "R30 VALIDATE start cases=[$CASES] builds: android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') ios=$(ios_version) mac_load=$(sysctl -n vm.loadavg | awk '{print $2}') full-screen access: $FSI0"
log "other sessions before the run: $(bash "$H/r28_busy_check.sh" 10 | tr '\n' ' ' | cut -c1-300)"
pid_and() { $ADB shell pidof $PKG 2>/dev/null | tr -d '\r'; }
stopped_flag() { $ADB shell dumpsys package $PKG | grep -m1 -oE 'stopped=(true|false)' | tr -d '\r'; }
emu_now() { $ADB shell date "'+%m-%d %H:%M:%S'" | tr -d '\r'; }
case_on() { case " $CASES " in *" $1 "*) return 0 ;; esac; return 1; }
since() { awk -v s="$1" '($1 " " substr($2,1,8)) >= s' "$RUN/android_logcat_live.txt"; }
screen_state() {
  echo "$($ADB shell dumpsys power | grep -m1 -oE 'mWakefulness=[A-Za-z]+' | tr -d '\r') $($ADB shell dumpsys window | grep -m1 -oE 'mShowingLockscreen=[a-z]+|isKeyguardShowing=[a-z]+|mKeyguardShowing=[a-z]+' | tr -d '\r')"
}
top_activity() { $ADB shell dumpsys activity activities | grep -m1 -E 'topResumedActivity' | grep -oE '[a-zA-Z0-9_.]+/[a-zA-Z0-9_.$]+' | head -1 | tr -d '\r'; }
fsi_in_notification() {
  $ADB shell dumpsys notification --noredact | awk '/NotificationRecord\(/ {mk = ($0 ~ /pkg=com\.mknoon\.app/)} mk && /fullscreenIntent=/ {print; exit}' | grep -oE 'fullscreenIntent=[^ ]+' | cut -c1-60 | tr -d '\r'
}
notif_poll() {  # background: record every distinct Mknoon notification in the live list (title/text/flags) until $1 exists
  local last="" cur
  while [ ! -f "$1" ]; do
    cur=$($ADB shell dumpsys notification --noredact 2>/dev/null | awk '
      /Notification List:/ {inlist=1; next}
      /Notification attention state:|mArchive=|Snoozed notifications:/ {inlist=0}
      !inlist {next}
      /NotificationRecord\(/ {if (mk && rec != "") print rec; mk = ($0 ~ /pkg=com\.mknoon\.app/); rec = ""; if (mk) {match($0, /id=[0-9-]+/); rec = substr($0, RSTART, RLENGTH)}; next}
      mk && /android\.title=|android\.text=|android\.callType=|^ *flags=/ {sub(/^ +/, ""); rec = rec " | " $0}
      END {if (mk && rec != "") print rec}' | tr '\n' '#' | cut -c1-900)
    if [ -n "$cur" ] && [ "$cur" != "$last" ]; then echo "[$(date '+%H:%M:%S')] $cur" >> "$RUN/extra/call_notifications.txt"; last="$cur"; fi
    sleep 1
  done
}
wait_callee_ready() {  # wait_callee_ready <emulator start time> <flow pid>
  local i
  for i in $(seq 1 240); do
    tail -c 3000000 "$RUN/android_logcat_live.txt" | grep -E " Maestro *: Requesting view hierarchy" \
      | awk -v s="$1" '($1 " " substr($2,1,8)) >= s' | grep -q . && { echo "ready after ${i}s"; return; }
    kill -0 "$2" 2>/dev/null || { echo "flow ended after ${i}s"; return; }
    sleep 1
  done
  echo "NOT ready after ${i}s"
}
wait_presented() {  # wait_presented <emulator start time>: seconds until the Pixel presents the call (max 45)
  local i
  for i in $(seq 1 45); do
    tail -c 3000000 "$RUN/android_logcat_live.txt" | grep "MKNOON_CALL_PRESENTATION_DIAG result=PRESENTED" \
      | awk -v s="$1" '($1 " " substr($2,1,8)) >= s' | grep -q . && { echo "$i"; return; }
    sleep 1
  done
  echo "none"
}
pixel_to_chat() { bash "$H/run_flow.sh" android ensure_chat.yaml "$1_pixel_prep" > /dev/null; }
pixel_home() { $ADB shell input keyevent KEYCODE_HOME; }
pixel_kill() {  # home, then kill only the process (not force-stop): the package stays unstopped, FCM can start it
  pixel_home; sleep 5
  $ADB shell am kill $PKG; sleep 3
  [ -n "$(pid_and)" ] && { $ADB shell am kill $PKG; sleep 3; }
  log "$1 pixel process after am kill: pid='$(pid_and)' $(stopped_flag)"
}
pixel_unlock() { $ADB shell input keyevent KEYCODE_WAKEUP; sleep 1; $ADB shell wm dismiss-keyguard; sleep 1; }
case_report() {  # case_report <case> <emulator start time>
  local c=$1 start=$2
  log "$c notifications (Mac clock): $(/usr/bin/python3 "$H/r28_notif_seq.py" "$RUN/extra/call_notifications.txt" "$c")"
  log "$c emulator clock: presented $(since "$start" | grep -m1 'MKNOON_CALL_PRESENTATION_DIAG result=PRESENTED' | awk '{print $2}'), answer $(since "$start" | grep -m1 'CALL_ANDROID_ANSWER' | awk '{print $2}'); decline lines: $(since "$start" | grep -iE 'decline' | grep -E 'Mknoon|"event":"CALL_' | sed -E 's/.*(Mknoon[A-Za-z]*: |"event":")//' | cut -c1-90 | sort | uniq -c | head -5 | tr '\n' ';')"
  log "$c Pixel afterwards: pid='$(pid_and)' call notifications left: $($ADB shell dumpsys notification --noredact | grep -c 'android.callType' | tr -d '\r')"
}
begin_case() {  # begin_case <case>: iPhone chat, notification poll, returns the emulator start time in START
  bash "$H/run_flow.sh" ios ensure_chat.yaml "$1_prep" > /dev/null
  echo "--- $1" >> "$RUN/extra/call_notifications.txt"
  rm -f "$RUN/.$1_stop"; notif_poll "$RUN/.$1_stop" & POLL=$!
  START=$(emu_now)
}
end_case() { touch "$RUN/.$1_stop"; wait $POLL 2>/dev/null; case_report "$1" "$START"; }

decline_case() {  # decline_case <case> <bg|killed>
  local c=$1 A r t0 te
  begin_case "$c"
  pixel_to_chat "$c"
  if [ "$2" = bg ]; then pixel_home; log "$c pixel app sent home (pid $(pid_and))"; else pixel_kill "$c"; fi
  t0=$(date +%s); te=$(emu_now)
  bash "$H/run_flow.sh" android "$F/v30_decline_android.yaml" "${c}_callee" & A=$!
  r=$(wait_callee_ready "$te" $A); log "$c callee maestro $r"
  while [ $(( $(date +%s) - t0 )) -lt 35 ]; do sleep 1; done
  log "$c calling now; pixel pid='$(pid_and)' $(stopped_flag)"
  bash "$H/run_flow.sh" ios "$F/v23_call_declined.yaml" "${c}_caller"
  wait $A
  end_case "$c"
}
locked_case() {  # locked_case <case> <bg|killed> <allow|deny>
  local c=$1 A C r t0 te p flow
  begin_case "$c"
  pixel_to_chat "$c"
  if [ "$3" = deny ]; then
    $ADB shell cmd appops set --uid $PKG USE_FULL_SCREEN_INTENT deny
    log "$c full-screen access for this case: $(fsi_mode)"
  fi
  if [ "$2" = bg ]; then pixel_home; log "$c pixel app sent home (pid $(pid_and))"; else pixel_kill "$c"; fi
  t0=$(date +%s)
  if [ "$3" = deny ]; then flow=v30_nofsi_callee_android.yaml; else flow=v30_locked_callee_android.yaml; fi
  te=$(emu_now)
  bash "$H/run_flow.sh" android "$F/$flow" "${c}_callee" & A=$!
  r=$(wait_callee_ready "$te" $A); log "$c callee maestro $r"
  sleep 3; $ADB shell input keyevent KEYCODE_SLEEP; sleep 3
  while [ $(( $(date +%s) - t0 )) -lt 35 ]; do sleep 1; done
  log "$c calling now; screen: $(screen_state); pixel pid='$(pid_and)' $(stopped_flag)"
  bash "$H/run_flow.sh" ios "$F/v26_caller_ios.yaml" "${c}_caller" & C=$!
  p=$(wait_presented "$START"); sleep 3
  log "$c presented after ${p}s of polling; ringing +3 s: $(screen_state) top=$(top_activity) $(fsi_in_notification)"
  bash "$H/r24_snap.sh" "${c}_ringing" > /dev/null 2>&1
  if [ "$3" = deny ]; then
    $ADB shell input keyevent KEYCODE_WAKEUP; sleep 2
    log "$c after waking the screen: $(screen_state) top=$(top_activity)"
    bash "$H/r24_snap.sh" "${c}_after_wake" > /dev/null 2>&1
  fi
  wait $C; wait $A
  end_case "$c"
  if [ "$3" = deny ]; then
    $ADB shell cmd appops set --uid $PKG USE_FULL_SCREEN_INTENT allow
    log "$c full-screen access restored: $(fsi_mode)"
  fi
  pixel_unlock
}

xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
pixel_unlock
case_on D1 && { log "=== D1 Pixel app in the background: Decline on the notification"; decline_case D1 bg; }
case_on D2 && { log "=== D2 Pixel app process killed: Decline on the notification"; decline_case D2 killed; }
case_on L1 && { log "=== L1 Pixel app in the background, screen off: full-screen incoming screen"; locked_case L1 bg allow; }
case_on L2 && { log "=== L2 Pixel app process killed, screen off: full-screen incoming screen"; locked_case L2 killed allow; }
case_on L3 && { log "=== L3 Pixel app process killed, screen off, no full-screen access"; locked_case L3 killed deny; }
now=$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl spawn "$UDID" log show --style compact --info --debug --start "$IOS_T0" --end "$now" \
  --predicate 'process == "Runner"' > "$RUN/ios_log_validate.txt" 2>&1
log "iPhone invites (relay wake status, how each call ended): $(/usr/bin/python3 "$H/r29_receipts.py" "$RUN/ios_log_validate.txt" | tr '\n' ';')"
for f in $(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null); do
  grep -qx "$f" "$RUN/crash/baseline_list.txt" || cp ~/Library/Logs/DiagnosticReports/"$f" "$RUN/crash/" 2>/dev/null
done
log "new crash reports: $(ls "$RUN/crash" | grep -v baseline_list | tr '\n' ' ')"
log "Pixel FATAL/ANR for the app: $(grep -cE 'FATAL EXCEPTION|ANR in com\.mknoon' "$RUN/android_logcat_live.txt")"
log "full-screen access at the end: $(fsi_mode) (start: $FSI0)"
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
log "other sessions during the run: $(bash "$H/r28_busy_check.sh" $(( ( $(date +%s) - $(date -j -f '%Y-%m-%d %H:%M:%S' "$IOS_T0" +%s) ) / 60 + 1 )) | tr '\n' ' ' | cut -c1-300)"
log "R30 VALIDATE DONE"
