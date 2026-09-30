#!/bin/bash
# R2-9 validation (2026-09-29), build-r2-10 on both phones: calls to a killed Android app on a locked phone.
# Cases run in the order given. A case name is its type plus an optional suffix, so a type can repeat (L2a L2b ...).
#  L2*   Pixel app process killed, screen off >= 35 s: full-screen incoming screen, answer there        (W1)
#  L2u*  same, but no UI automation and no notification polling on the Pixel until the call is presented (W1 control)
#  L3*   Pixel app process killed, screen off >= 35 s, WITHOUT full-screen access (appop denied for the case, restored
#        after): record what the user gets, wake the screen, answer from the lock screen if an Answer button shows (W2)
#  L1*   Pixel app in the background, screen off >= 35 s                                                    (W4)
#  K1*   Pixel app process killed, screen on and unlocked: answer from the notification                    (W4)
#  B1*   Pixel app in the background, screen on: answer from the notification                              (W4)
#  D1*   Pixel app in the background: Decline on the notification                                          (W4)
#  D2*   Pixel app process killed: Decline on the notification                                             (W4)
#  F1*   Pixel app open                                                                                    (W4)
# Caller ringing (W3) and all timings come from r31_report.py at the end (iPhone FLOW ts vs Pixel logcat, clock offset
# measured per case). The runner installs nothing and never uninstalls.
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh" > /dev/null
RUN=$(current_run)
cp "$BETA/build-r2-10/build_name.txt" "$BETA/build-r2-10/provenance.txt" "$RUN/" 2>/dev/null
TL="$RUN/timeline.txt"
CASES="${*:-L2a L2b L2c L3 L2ua L1 K1 B1 D1 D2 F1 L2d L2e}"
F=r2
IDLE=35
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
log "R31 VALIDATE start cases=[$CASES] builds: android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') ios=$(ios_version) mac_load=$(sysctl -n vm.loadavg | awk '{print $2}') emulator_uptime_s=$($ADB shell cat /proc/uptime | tr -d '\r' | awk '{printf "%.0f", $1}') full-screen access: $FSI0"
log "other sessions before the run: $(bash "$H/r28_busy_check.sh" 10 | tr '\n' ' ' | cut -c1-300)"
pid_and() { $ADB shell pidof $PKG 2>/dev/null | tr -d '\r'; }
stopped_flag() { $ADB shell dumpsys package $PKG | grep -m1 -oE 'stopped=(true|false)' | tr -d '\r'; }
emu_now() { $ADB shell date "'+%m-%d %H:%M:%S'" | tr -d '\r'; }
emu_offset() {  # emulator clock minus Mac clock in seconds, bracketed by two Mac readings
  local a e b
  a=$(/usr/bin/python3 -c 'import time; print("%.3f" % time.time())')
  e=$($ADB shell date +%s.%N | tr -d '\r' | cut -c1-14)
  b=$(/usr/bin/python3 -c 'import time; print("%.3f" % time.time())')
  /usr/bin/python3 -c 'import sys; a,e,b=map(float,sys.argv[1:]); print("%+.2f rt=%.2f" % (e-(a+b)/2, b-a))' "$a" "$e" "$b"
}
screen_state() {
  echo "$($ADB shell dumpsys power | grep -m1 -oE 'mWakefulness=[A-Za-z]+' | tr -d '\r') $($ADB shell dumpsys window | grep -m1 -oE 'mShowingLockscreen=[a-z]+|isKeyguardShowing=[a-z]+|mKeyguardShowing=[a-z]+' | tr -d '\r')"
}
top_activity() { $ADB shell dumpsys activity activities | grep -m1 -E 'topResumedActivity' | grep -oE '[a-zA-Z0-9_.]+/[a-zA-Z0-9_.$]+' | head -1 | tr -d '\r'; }
fsi_in_notification() {
  $ADB shell dumpsys notification --noredact | awk '/NotificationRecord\(/ {mk = ($0 ~ /pkg=com\.mknoon\.app/)} mk && /fullscreenIntent=/ {print; exit}' | grep -oE 'fullscreenIntent=[^ ]+' | cut -c1-60 | tr -d '\r'
}
sound_state() {  # what is making sound right now: started audio players (usage) and the notification alert keys
  echo "players: $($ADB shell dumpsys audio | grep -E 'AudioPlaybackConfiguration.*state:started' | grep -oE 'usage=[A-Z_]+' | sort | uniq -c | tr '\n' ' ' | tr -s ' ') alerts: $($ADB shell dumpsys notification | grep -E 'mSoundNotificationKey|mVibrateNotificationKey' | tr -d '\r' | sed -E 's/^ +//' | tr '\n' ' ' | cut -c1-200)"
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
wait_presented() {  # wait_presented <emulator time>: seconds of polling until the Pixel presents the call (max 45)
  local i
  for i in $(seq 1 45); do
    tail -c 3000000 "$RUN/android_logcat_live.txt" | grep "MKNOON_CALL_PRESENTATION_DIAG result=PRESENTED" \
      | awk -v s="$1" '($1 " " substr($2,1,8)) >= s' | grep -q . && { echo "$i"; return; }
    sleep 1
  done
  echo "none"
}
since() { awk -v s="$1" '($1 " " substr($2,1,8)) >= s' "$RUN/android_logcat_live.txt"; }
pixel_to_chat() { bash "$H/run_flow.sh" android ensure_chat.yaml "$1_pixel_prep" > /dev/null; }
pixel_home() { $ADB shell input keyevent KEYCODE_HOME; }
pixel_kill() {  # home, then kill only the process (not force-stop): the package stays unstopped, FCM can start it
  pixel_home; sleep 5
  $ADB shell am kill $PKG; sleep 3
  [ -n "$(pid_and)" ] && { $ADB shell am kill $PKG; sleep 3; }
  T_KILL=$(date +%s)
  log "$1 pixel process after am kill: pid='$(pid_and)' $(stopped_flag)"
}
pixel_unlock() { $ADB shell input keyevent KEYCODE_WAKEUP; sleep 1; $ADB shell wm dismiss-keyguard; sleep 1; }
restart_pixel_app() { $ADB shell am force-stop $PKG; sleep 2; $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 25; log "pixel app restarted (pid $(pid_and))"; }
calling_now() {  # calling_now <case> <extra>: one line with the state right before the iPhone places the call
  CALL_EMU=$(emu_now)
  log "$1 calling now; mac_epoch=$(date +%s) offset=$(emu_offset) emu=$CALL_EMU; screen: $(screen_state); pixel pid='$(pid_and)' $(stopped_flag); $2"
}
case_report() {  # case_report <case> <emulator start time>
  local c=$1 start=$2
  log "$c notifications (Mac clock): $(/usr/bin/python3 "$H/r28_notif_seq.py" "$RUN/extra/call_notifications.txt" "$c")"
  log "$c emulator clock: presented $(since "$start" | grep -m1 'MKNOON_CALL_PRESENTATION_DIAG result=PRESENTED' | awk '{print $2}'), answer $(since "$start" | grep -m1 'CALL_ANDROID_ANSWER' | awk '{print $2}'), admission timeouts $(since "$start" | grep -c 'CALL_ANDROID_ADMISSION event=timeout_applied')"
  log "$c Pixel afterwards: pid='$(pid_and)' call notifications left: $($ADB shell dumpsys notification --noredact | grep -c 'android.callType' | tr -d '\r')"
}
begin_case() {  # begin_case <case> [nopoll]: iPhone chat, notification poll, emulator start time in START
  bash "$H/run_flow.sh" ios ensure_chat.yaml "$1_prep" > /dev/null
  echo "--- $1" >> "$RUN/extra/call_notifications.txt"
  rm -f "$RUN/.$1_stop"; POLL=""
  [ "${2:-}" = nopoll ] || { notif_poll "$RUN/.$1_stop" & POLL=$!; }
  START=$(emu_now)
}
end_case() { touch "$RUN/.$1_stop"; [ -n "$POLL" ] && wait $POLL 2>/dev/null; case_report "$1" "$START"; }
wait_idle() {  # wait until the screen has been off and the app away for at least IDLE seconds
  while [ $(( $(date +%s) - T_SLEEP )) -lt $IDLE ] || [ $(( $(date +%s) - T_AWAY )) -lt $IDLE ]; do sleep 1; done
}

decline_case() {  # decline_case <case> <bg|killed>
  local c=$1 A r te
  begin_case "$c"
  pixel_to_chat "$c"
  if [ "$2" = bg ]; then pixel_home; T_AWAY=$(date +%s); log "$c pixel app sent home (pid $(pid_and))"; else pixel_kill "$c"; T_AWAY=$T_KILL; fi
  te=$(emu_now)
  bash "$H/run_flow.sh" android "$F/v30_decline_android.yaml" "${c}_callee" & A=$!
  r=$(wait_callee_ready "$te" $A); log "$c callee maestro $r"
  T_SLEEP=0; wait_idle
  calling_now "$c" "away $(( $(date +%s) - T_AWAY )) s"
  bash "$H/run_flow.sh" ios "$F/v23_call_declined.yaml" "${c}_caller"
  wait $A
  end_case "$c"
}
locked_case() {  # locked_case <case> <bg|killed> <allow|deny>
  local c=$1 A C r te p flow
  begin_case "$c"
  pixel_to_chat "$c"
  if [ "$3" = deny ]; then
    $ADB shell cmd appops set --uid $PKG USE_FULL_SCREEN_INTENT deny
    log "$c full-screen access for this case: $(fsi_mode)"
  fi
  if [ "$2" = bg ]; then pixel_home; T_AWAY=$(date +%s); log "$c pixel app sent home (pid $(pid_and))"; else pixel_kill "$c"; T_AWAY=$T_KILL; fi
  if [ "$3" = deny ]; then flow=v30_nofsi_callee_android.yaml; else flow=v30_locked_callee_android.yaml; fi
  te=$(emu_now)
  bash "$H/run_flow.sh" android "$F/$flow" "${c}_callee" & A=$!
  r=$(wait_callee_ready "$te" $A); log "$c callee maestro $r"
  sleep 3; $ADB shell input keyevent KEYCODE_SLEEP; T_SLEEP=$(date +%s); sleep 3
  wait_idle
  calling_now "$c" "screen off $(( $(date +%s) - T_SLEEP )) s, app away $(( $(date +%s) - T_AWAY )) s"
  bash "$H/run_flow.sh" ios "$F/v26_caller_ios.yaml" "${c}_caller" & C=$!
  p=$(wait_presented "$CALL_EMU"); sleep 3
  log "$c presented after ${p}s of polling; ringing +3 s: $(screen_state) top=$(top_activity) $(fsi_in_notification); $(sound_state)"
  bash "$H/r24_snap.sh" "${c}_ringing" > /dev/null 2>&1
  if [ "$3" = deny ]; then
    $ADB shell dumpsys notification --noredact | awk '/NotificationRecord\(/ {mk = ($0 ~ /pkg=com\.mknoon\.app/)} mk' | head -120 > "$RUN/extra/${c}_notification_dump.txt"
    $ADB shell input keyevent KEYCODE_WAKEUP; sleep 2
    log "$c after waking the screen: $(screen_state) top=$(top_activity); $(sound_state)"
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
unattended_case() {  # unattended_case <case>: killed + locked, nothing touches the Pixel until the call is presented
  local c=$1 A C p te
  begin_case "$c" nopoll
  pixel_to_chat "$c"
  pixel_kill "$c"; T_AWAY=$T_KILL
  $ADB shell input keyevent KEYCODE_SLEEP; T_SLEEP=$(date +%s)
  wait_idle
  calling_now "$c" "screen off $(( $(date +%s) - T_SLEEP )) s, app away $(( $(date +%s) - T_AWAY )) s, no automation"
  bash "$H/run_flow.sh" ios "$F/v26_caller_ios.yaml" "${c}_caller" & C=$!
  p=$(wait_presented "$CALL_EMU")
  log "$c presented after ${p}s of polling; starting the Pixel answer flow now"
  notif_poll "$RUN/.${c}_stop" & POLL=$!
  te=$(emu_now)
  bash "$H/run_flow.sh" android "$F/v30_locked_callee_android.yaml" "${c}_callee" & A=$!
  sleep 2
  log "$c ringing: $(screen_state) top=$(top_activity) $(fsi_in_notification); $(sound_state)"
  bash "$H/r24_snap.sh" "${c}_ringing" > /dev/null 2>&1
  wait $C; wait $A
  end_case "$c"
  pixel_unlock
}
callee_case() {  # callee_case <case> <fg|bg|killed>
  local c=$1 mode=$2 A r
  begin_case "$c"
  case "$mode" in
    fg) bash "$H/run_flow.sh" android "$F/v26_fg_callee_android.yaml" "${c}_callee" & A=$! ;;
    bg) pixel_to_chat "$c"; pixel_home; T_AWAY=$(date +%s); log "$c pixel app sent home (pid $(pid_and))"
        bash "$H/run_flow.sh" android "$F/v29_callee_android.yaml" "${c}_callee" & A=$! ;;
    killed) pixel_to_chat "$c"; pixel_kill "$c"; T_AWAY=$T_KILL
        bash "$H/run_flow.sh" android "$F/v29_callee_android.yaml" "${c}_callee" & A=$! ;;
  esac
  r=$(wait_callee_ready "$START" $A); log "$c callee maestro $r"
  T_SLEEP=0
  [ "$mode" = fg ] && T_AWAY=0
  wait_idle
  calling_now "$c" "mode $mode"
  bash "$H/run_flow.sh" ios "$F/v26_caller_ios.yaml" "${c}_caller"
  wait $A
  end_case "$c"
}

xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
pixel_unlock
for c in $CASES; do
  case "$c" in
    L2u*) log "=== $c W1 control: Pixel app process killed, screen off, no automation until presented"; unattended_case "$c" ;;
    L2*) log "=== $c W1: Pixel app process killed, screen off: full-screen incoming screen"; locked_case "$c" killed allow ;;
    L3*) log "=== $c W2: Pixel app process killed, screen off, no full-screen access"; locked_case "$c" killed deny ;;
    L1*) log "=== $c W4: Pixel app in the background, screen off"; locked_case "$c" bg allow ;;
    K1*) log "=== $c W4: Pixel app process killed, screen on"; callee_case "$c" killed ;;
    B1*) log "=== $c W4: Pixel app in the background, screen on"; callee_case "$c" bg ;;
    D1*) log "=== $c W4: Pixel app in the background: Decline on the notification"; decline_case "$c" bg ;;
    D2*) log "=== $c W4: Pixel app process killed: Decline on the notification"; decline_case "$c" killed ;;
    F1*) restart_pixel_app; log "=== $c W4: Pixel app open"; callee_case "$c" fg ;;
    *) log "unknown case $c" ;;
  esac
done
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
/usr/bin/python3 "$H/r31_report.py" "$RUN" > "$RUN/report.txt" 2>&1
log "report: $(wc -l < "$RUN/report.txt" | tr -d ' ') lines in report.txt"
log "other sessions during the run: $(bash "$H/r28_busy_check.sh" $(( ( $(date +%s) - $(date -j -f '%Y-%m-%d %H:%M:%S' "$IOS_T0" +%s) ) / 60 + 1 )) | tr '\n' ' ' | cut -c1-300)"
log "R31 VALIDATE DONE"
