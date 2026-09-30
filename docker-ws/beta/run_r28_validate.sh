#!/bin/bash
# R2-6 follow-up 3 validation (2026-09-28): the Android incoming-call notification must name the caller while it
# rings. The Pixel (callee) runs build-r2-8; the iPhone (caller) keeps build d505 (the fix is Android native + callee
# Dart). Cases (default all):
#  N3a, N3b  Pixel app in the foreground with the chat open; the iPhone calls; the Pixel answers after ~10 s
#  N4        Pixel app sent to the background just before the call (reaches the Pixel only if its relay link survives)
# Evidence: Mknoon notifications polled from `dumpsys notification` (Mac clock), native
# `updatePresentation ... refreshed=` lines, shade screenshots taken by the flows.
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh" > /dev/null
RUN=$(current_run)
cp "$BETA/build-r2-8/build_name.txt" "$BETA/build-r2-8/provenance.txt" "$RUN/" 2>/dev/null
TL="$RUN/timeline.txt"
CASES="${*:-N3a N3b N4}"
F=r2
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$TL"; }
mkdir -p "$RUN/crash" "$RUN/extra" "$RUN/ui"
ls ~/Library/Logs/DiagnosticReports/ > "$RUN/crash/baseline_list.txt" 2>/dev/null
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
echo $! > "$RUN/logcat.pid"
IOS_T0=$(date '+%Y-%m-%d %H:%M:%S')
ios_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>/dev/null; }
log "R28 VALIDATE start cases=[$CASES] builds: android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') ios=$(ios_version) mac_load=$(sysctl -n vm.loadavg | awk '{print $2}') mac_minus_emulator_clock=$(( $(date +%s) - $($ADB shell date +%s | tr -d '\r') ))s"
pid_and() { $ADB shell pidof $PKG 2>/dev/null | tr -d '\r'; }
ensure_apps() {
  [ -z "$(pid_and)" ] && { $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 20; }
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
}
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
call_case() {  # call_case <case> <android flow>
  local c=$1 af=$2 start ready i A
  bash "$H/run_flow.sh" ios ensure_chat.yaml "${c}_prep" > /dev/null
  echo "--- $c" >> "$RUN/extra/call_notifications.txt"
  rm -f "$RUN/.${c}_stop"; notif_poll "$RUN/.${c}_stop" & POLL=$!
  start=$(emu_now)
  bash "$H/run_flow.sh" android "$F/$af" "${c}_callee" &
  A=$!
  ready=0
  for i in $(seq 1 240); do
    tail -c 3000000 "$RUN/android_logcat_live.txt" | grep -E " Maestro *: Requesting view hierarchy" \
      | awk -v s="$start" '($1 " " substr($2,1,8)) >= s' | grep -q . && { ready=1; break; }
    kill -0 $A 2>/dev/null || break
    sleep 1
  done
  log "$c callee maestro $([ $ready = 1 ] && echo ready || echo NOT ready) after ${i}s"
  bash "$H/run_flow.sh" ios "$F/v26_caller_ios.yaml" "${c}_caller"
  wait $A
  touch "$RUN/.${c}_stop"; wait $POLL 2>/dev/null
  log "$c notifications (Mac clock): $(/usr/bin/python3 "$H/r28_notif_seq.py" "$RUN/extra/call_notifications.txt" "$c")"
  log "$c native lines: $(since "$start" | grep -oE 'updatePresentation accepted=[a-z]+ state=[a-z]+ named=[a-z]+ refreshed=[a-z]+' | sort | uniq -c | tr '\n' ';')"
  log "$c emulator clock: presented $(since "$start" | grep -m1 'MKNOON_CALL_PRESENTATION_DIAG result=PRESENTED' | awk '{print $2}'), first refreshed=true $(since "$start" | grep -m1 'refreshed=true' | awk '{print $2}'), answer $(since "$start" | grep -m1 'CALL_ANDROID_ANSWER' | awk '{print $2}')"
  log "$c Pixel relay dial failures: $(since "$start" | grep -c 'RELAY_SELECTOR.*failed')"
}
restart_pixel_app() { $ADB shell am force-stop $PKG; sleep 2; $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 25; log "pixel app restarted (pid $(pid_and))"; }

log "other sessions before the run: $(bash "$H/r28_busy_check.sh" 10 | tr '\n' ' ' | cut -c1-400)"
ensure_apps
if case_on N3a; then
  restart_pixel_app
  log "=== N3a Pixel app in the foreground (chat open), iPhone calls"
  call_case N3a v26_fg_callee_android.yaml
fi
if case_on N3b; then
  log "=== N3b same again, same app process"
  call_case N3b v26_fg_callee_android.yaml
fi
if case_on N4; then
  log "=== N4 Pixel app goes to the background just before the call"
  call_case N4 v26_quickbg_callee_android.yaml
fi
now=$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl spawn "$UDID" log show --style compact --info --debug --start "$IOS_T0" --end "$now" \
  --predicate 'process == "Runner"' > "$RUN/ios_log_validate.txt" 2>&1
for f in $(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null); do
  grep -qx "$f" "$RUN/crash/baseline_list.txt" || cp ~/Library/Logs/DiagnosticReports/"$f" "$RUN/crash/" 2>/dev/null
done
log "new crash reports: $(ls "$RUN/crash" | grep -v baseline_list | tr '\n' ' ')"
log "Pixel FATAL/ANR for the app: $(grep -cE 'FATAL EXCEPTION|ANR in com\.mknoon' "$RUN/android_logcat_live.txt")"
log "other sessions during the run: $(bash "$H/r28_busy_check.sh" $(( ( $(date +%s) - $(date -j -f '%Y-%m-%d %H:%M:%S' "$IOS_T0" +%s) ) / 60 + 1 )) | tr '\n' ' ' | cut -c1-400)"
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
log "R28 VALIDATE DONE"
