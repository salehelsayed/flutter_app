#!/bin/bash
# R2-8 validation (2026-09-29): an Android phone must ring when the Mknoon app is in the background or its process was
# killed (FCM call wake), with the caller's name on the notification. Both phones run build-r2-9. Cases (default all):
#  F1  Pixel app open (new process), iPhone calls                        -> V5, V3 (first call after start)
#  B1  Pixel app sent home >= 35 s before the call, iPhone calls         -> V1, V3
#  B2  same again in the same Pixel process                              -> V1, V3 (after several calls)
#  K1  Pixel app process killed (am kill: not force-stopped), iPhone calls -> V2 (+ caller name)
#  P1  Pixel calls the iPhone (iPhone app open)                          -> V5
#  M1  Pixel app process killed, iPhone sends a text: message notification must appear (chat push after the FCM
#      token rotation)
# V3 (relay wake receipts) and V4 (relay addresses) are read from the logs at the end.
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh" > /dev/null
RUN=$(current_run)
cp "$BETA/build-r2-9/build_name.txt" "$BETA/build-r2-9/provenance.txt" "$RUN/" 2>/dev/null
TL="$RUN/timeline.txt"
CASES="${*:-F1 B1 B2 K1 P1 M1}"
F=r2
S=$(date +%H%M)
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$TL"; }
mkdir -p "$RUN/crash" "$RUN/extra" "$RUN/ui"
ls ~/Library/Logs/DiagnosticReports/ > "$RUN/crash/baseline_list.txt" 2>/dev/null
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
echo $! > "$RUN/logcat.pid"
IOS_T0=$(date '+%Y-%m-%d %H:%M:%S')
ios_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>/dev/null; }
log "R29 VALIDATE start cases=[$CASES] builds: android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') ios=$(ios_version) mac_load=$(sysctl -n vm.loadavg | awk '{print $2}') mac_minus_emulator_clock=$(( $(date +%s) - $($ADB shell date +%s | tr -d '\r') ))s"
log "other sessions before the run: $(bash "$H/r28_busy_check.sh" 10 | tr '\n' ' ' | cut -c1-300)"
pid_and() { $ADB shell pidof $PKG 2>/dev/null | tr -d '\r'; }
stopped_flag() { $ADB shell dumpsys package $PKG | grep -m1 -oE 'stopped=(true|false)' | tr -d '\r'; }
emu_now() { $ADB shell date "'+%m-%d %H:%M:%S'" | tr -d '\r'; }
case_on() { case " $CASES " in *" $1 "*) return 0 ;; esac; return 1; }
since() { awk -v s="$1" '($1 " " substr($2,1,8)) >= s' "$RUN/android_logcat_live.txt"; }
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
pixel_to_chat() { bash "$H/run_flow.sh" android ensure_chat.yaml "$1_pixel_prep" > /dev/null; }
pixel_home() { $ADB shell input keyevent KEYCODE_HOME; }
pixel_kill() {  # home, then kill only the process (not force-stop): the package stays unstopped, FCM can start it
  pixel_home; sleep 5
  $ADB shell am kill $PKG; sleep 3
  [ -n "$(pid_and)" ] && { $ADB shell am kill $PKG; sleep 3; }
  log "$1 pixel process after am kill: pid='$(pid_and)' $(stopped_flag)"
}
case_report() {  # case_report <case> <emulator start time>
  local c=$1 start=$2
  log "$c notifications (Mac clock): $(/usr/bin/python3 "$H/r28_notif_seq.py" "$RUN/extra/call_notifications.txt" "$c")"
  log "$c emulator clock: presented $(since "$start" | grep -m1 'MKNOON_CALL_PRESENTATION_DIAG result=PRESENTED' | awk '{print $2}'), answer $(since "$start" | grep -m1 'CALL_ANDROID_ANSWER' | awk '{print $2}'), native refreshes $(since "$start" | grep -c 'refreshed=true')"
  log "$c Pixel token publish: $(since "$start" | grep -oE '"event":"CALL_ANDROID_TOKEN_PUBLISH_RESULT","details":\{"outcome":"[a-z_]+"' | sed 's/.*outcome":"//; s/"$//' | sort | uniq -c | tr '\n' ' ')relay dial failures: $(since "$start" | grep -c 'RELAY_SELECTOR.*failed') wake-related lines: $(since "$start" | grep -ciE 'CALL_ANDROID_WAKE|CALL_SIGNALING_WAKE_RESULT|"stage":"push"|stage=push')"
}
callee_case() {  # callee_case <case> <fg|bg|killed>
  local c=$1 mode=$2 start A r t_home
  bash "$H/run_flow.sh" ios ensure_chat.yaml "${c}_prep" > /dev/null
  echo "--- $c" >> "$RUN/extra/call_notifications.txt"
  rm -f "$RUN/.${c}_stop"; notif_poll "$RUN/.${c}_stop" & POLL=$!
  start=$(emu_now)
  case "$mode" in
    fg) bash "$H/run_flow.sh" android "$F/v26_fg_callee_android.yaml" "${c}_callee" & A=$! ;;
    bg) pixel_to_chat "$c"; pixel_home; t_home=$(date +%s); log "$c pixel app sent home (pid $(pid_and))"
        bash "$H/run_flow.sh" android "$F/v29_callee_android.yaml" "${c}_callee" & A=$! ;;
    killed) pixel_to_chat "$c"; pixel_kill "$c"; t_home=$(date +%s)
        bash "$H/run_flow.sh" android "$F/v29_callee_android.yaml" "${c}_callee" & A=$! ;;
  esac
  r=$(wait_callee_ready "$start" $A); log "$c callee maestro $r"
  if [ "$mode" != fg ]; then
    while [ $(( $(date +%s) - t_home )) -lt 35 ]; do sleep 1; done
    log "$c calling now, $(( $(date +%s) - t_home )) s after the app left the screen; pixel pid='$(pid_and)' $(stopped_flag)"
  fi
  bash "$H/run_flow.sh" ios "$F/v26_caller_ios.yaml" "${c}_caller"
  wait $A
  touch "$RUN/.${c}_stop"; wait $POLL 2>/dev/null
  case_report "$c" "$start"
}
restart_pixel_app() { $ADB shell am force-stop $PKG; sleep 2; $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 25; log "pixel app restarted (pid $(pid_and))"; }

xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
if case_on F1; then
  restart_pixel_app
  log "=== F1 Pixel app open (new process), iPhone calls"
  callee_case F1 fg
fi
if case_on B1; then log "=== B1 Pixel app in the background >= 35 s, iPhone calls"; callee_case B1 bg; fi
if case_on B2; then log "=== B2 same again, same Pixel process"; callee_case B2 bg; fi
if case_on K1; then log "=== K1 Pixel app process killed (not force-stopped), iPhone calls"; callee_case K1 killed; fi
if case_on P1; then
  log "=== P1 Pixel calls the iPhone (iPhone app open)"
  start=$(emu_now)
  bash "$H/run_flow.sh" ios "$F/v29_callee_ios.yaml" "P1_callee" & I=$!
  sleep 25
  bash "$H/run_flow.sh" android "$F/v29_caller_android.yaml" "P1_caller"
  wait $I
  log "P1 Pixel caller: $(since "$start" | grep -oE '"event":"CALL_STATE_TRANSITION","details":\{"trigger":"[a-zA-Z]+","state":"(ringing|connected|ended)"[^}]*' | sed 's/.*"trigger"://' | uniq | head -6 | tr '\n' ' ')"
fi
if case_on M1; then
  log "=== M1 Pixel app process killed, iPhone sends a text (chat push)"
  pixel_to_chat M1; pixel_kill M1
  echo "--- M1" >> "$RUN/extra/call_notifications.txt"
  rm -f "$RUN/.M1_stop"; notif_poll "$RUN/.M1_stop" & POLL=$!
  start=$(emu_now); MSG="R29 push M1 $S"
  bash "$H/run_flow.sh" ios "$F/v29_send_text_ios.yaml" "M1_send" "MSG=$MSG"
  for i in $(seq 1 90); do
    awk '/^--- M1$/{f=1; next} /^--- /{f=0} f' "$RUN/extra/call_notifications.txt" | grep -qF "$MSG" && break
    sleep 1
  done
  touch "$RUN/.M1_stop"; wait $POLL 2>/dev/null
  log "M1 message notification after the send: $(/usr/bin/python3 "$H/r28_notif_seq.py" "$RUN/extra/call_notifications.txt" M1) (waited ${i}s); pixel pid now='$(pid_and)'"
fi
now=$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl spawn "$UDID" log show --style compact --info --debug --start "$IOS_T0" --end "$now" \
  --predicate 'process == "Runner"' > "$RUN/ios_log_validate.txt" 2>&1
log "V3 iPhone invites (relay wake status per call): $(/usr/bin/python3 "$H/r29_receipts.py" "$RUN/ios_log_validate.txt" | tr '\n' ';')"
log "V4 relay addresses: pixel lists with 13.60.250.19: $(grep 'circuit addresses' "$RUN/android_logcat_live.txt" | grep -c '13\.60\.250\.19'), with 51.21.194.144: $(grep 'circuit addresses' "$RUN/android_logcat_live.txt" | grep -c '51\.21\.194\.144'); iphone lists with 13.60.250.19: $(grep 'circuit addresses' "$RUN/ios_log_validate.txt" | grep -c '13\.60\.250\.19'), with 51.21.194.144: $(grep 'circuit addresses' "$RUN/ios_log_validate.txt" | grep -c '51\.21\.194\.144')"
for f in $(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null); do
  grep -qx "$f" "$RUN/crash/baseline_list.txt" || cp ~/Library/Logs/DiagnosticReports/"$f" "$RUN/crash/" 2>/dev/null
done
log "new crash reports: $(ls "$RUN/crash" | grep -v baseline_list | tr '\n' ' ')"
log "Pixel FATAL/ANR for the app: $(grep -cE 'FATAL EXCEPTION|ANR in com\.mknoon' "$RUN/android_logcat_live.txt")"
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
log "other sessions during the run: $(bash "$H/r28_busy_check.sh" $(( ( $(date +%s) - $(date -j -f '%Y-%m-%d %H:%M:%S' "$IOS_T0" +%s) ) / 60 + 1 )) | tr '\n' ' ' | cut -c1-300)"
log "R29 VALIDATE DONE"
