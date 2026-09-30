#!/bin/bash
# R2-3 fix verification on the two phones (R2-3 builds installed in place). The callee records a voice note
# when the call comes in:
#  V1 Pixel records (1:1), iPhone calls, Pixel answers  -> call connects; the clip is kept as a draft; Pixel sends it
#  V3 Pixel records (1:1), iPhone calls, Pixel declines -> recording goes on; Pixel stops and sends it
#  V5 Pixel records (1:1), iPhone calls, then cancels   -> recording goes on; Pixel stops and sends it
#  V2 iPhone records (1:1), Pixel calls, iPhone answers -> call connects; draft kept; iPhone sends it
#  V4 Pixel records in a new group, iPhone calls, Pixel answers -> call connects; group draft kept and sent
# Oracles: flow results, CALL_AUDIO_START_RESULT / RECORD events, Android RecordActivityMonitor (MIC must stop
# before VOICE_COMMUNICATION starts), voice bubbles on the receiver's screen.
# Usage: run_r23_validate.sh [case ...]   (default: V1 V3 V5 V2 V4)
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh" > /dev/null
RUN=$(current_run)
cp "$BETA/build-r2-3/build_name.txt" "$BETA/build-r2-3/provenance.txt" "$RUN/" 2>/dev/null
TL="$RUN/timeline.txt"
CASES="${*:-V1 V3 V5 V2 V4}"
S=$(date +%H%M)
F=r2
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$TL"; }
mkdir -p "$RUN/crash" "$RUN/extra" "$RUN/ui"
ls ~/Library/Logs/DiagnosticReports/ > "$RUN/crash/baseline_list.txt" 2>/dev/null
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null   # only this run's own capture (a watcher may stream logcat too)
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
echo $! > "$RUN/logcat.pid"
IOS_T0=$(date '+%Y-%m-%d %H:%M:%S')
ios_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>/dev/null; }
log "R23 VALIDATE start cases=[$CASES] builds: android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') ios=$(ios_version) mac_load=$(sysctl -n vm.loadavg | awk '{print $2}')"
pid_and() { $ADB shell pidof $PKG 2>/dev/null | tr -d '\r'; }
ensure_apps() {
  [ -z "$(pid_and)" ] && { $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 20; }
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
}
emu_now() { $ADB shell date "'+%m-%d %H:%M:%S'" | tr -d '\r'; }
ios_now() { date '+%Y-%m-%d %H:%M:%S'; }
case_on() { case " $CASES " in *" $1 "*) return 0 ;; esac; return 1; }
rec_activity_since() {  # Android RecordActivityMonitor lines for the app since "<MM-DD HH:MM:SS>"
  $ADB shell dumpsys audio 2>/dev/null | awk '/### Recording Activity/{f=1;next} f&&/^ *$/{exit} f' \
    | grep "pack:$PKG" | awk -v s="$1" '($1 " " substr($2,1,8)) >= s' | sed 's/^ *//'
}
wait_rec_android() {  # wait_rec_android <since> <seconds>: a voice-note capture started on the Pixel
  # 1:1 chats log CONV_FL_RECORD_STARTED; group chats log nothing, so also accept a MIC capture start/update
  # in RecordActivityMonitor (its history does not always keep the "rec start" line).
  local i
  for i in $(seq 1 $(( $2 / 3 ))); do
    tail -c 5000000 "$RUN/android_logcat_live.txt" | awk -v s="$1" '($1 " " substr($2,1,8)) >= s' \
      | grep -q 'CONV_FL_RECORD_STARTED' && return 0
    rec_activity_since "$1" | grep -E "rec (start|update)" | grep -vq "src:VOICE_COMMUNICATION" && return 0
    sleep 3
  done
  return 1
}
wait_rec_ios() {  # wait_rec_ios <since "YYYY-MM-DD HH:MM:SS"> <seconds>: CONV_FL_RECORD_STARTED on the iPhone
  local i
  for i in $(seq 1 $(( $2 / 6 ))); do
    xcrun simctl spawn "$UDID" log show --start "$1" --style compact --predicate 'process == "Runner"' 2>/dev/null \
      | grep -q 'CONV_FL_RECORD_STARTED' && return 0
    sleep 3
  done
  return 1
}
and_events_since() {  # the app's R2-3 related flow events on the Pixel since "<MM-DD HH:MM:SS>"
  awk -v s="$1" '($1 " " substr($2,1,8)) >= s' "$RUN/android_logcat_live.txt" \
    | grep -oE '"event":"((GROUP_)?CONV_FL_RECORD_[A-Z_]+|CALL_AUDIO_START_RESULT|CALL_MEDIA_[A-Z_]+|CALL_STATE[A-Z_]*|CALL_[A-Z_]*ENDED[A-Z_]*)","details":\{[^}]*' \
    | sed 's/"event"://; s/"details"://' | uniq -c | head -30
}
ios_events_since() {
  xcrun simctl spawn "$UDID" log show --start "$1" --style compact --predicate 'process == "Runner"' 2>/dev/null \
    | grep -oE '"event":"((GROUP_)?CONV_FL_RECORD_[A-Z_]+|CALL_AUDIO_START_RESULT|CALL_MEDIA_[A-Z_]+|CALL_STATE[A-Z_]*|CALL_[A-Z_]*ENDED[A-Z_]*)","details":\{[^}]*' \
    | sed 's/"event"://; s/"details"://' | uniq -c | head -30
}
voice_nodes() {  # voice_nodes <label> <ios|android>: voice bubbles on screen
  bash "$H/dump_ui.sh" "$1" "$2" > /dev/null 2>&1
  /usr/bin/python3 "$H/r23_voice_nodes.py" "$RUN/ui/$1_$2.json" 2>&1 | tail -8
}
report_case() {  # report_case <case> <callee dev> <since-android> <since-ios>
  log "$1 Pixel events: $(and_events_since "$3" | tr '\n' ';' | cut -c1-1500)"
  log "$1 iPhone events: $(ios_events_since "$4" | tr '\n' ';' | cut -c1-1500)"
  log "$1 Pixel RecordActivityMonitor: $(rec_activity_since "$3" | awk '{print $2, $4, $5, $8, $9, $10}' | tr '\n' ';')"
}
pixel_callee() {  # pixel_callee <case> <callee flow> <caller flow> [KEY=VAL ...]
  local c=$1 cf=$2 kf=$3; shift 3
  bash "$H/run_flow.sh" ios ensure_chat.yaml "${c}_prep" > /dev/null
  local e0 i0; e0=$(emu_now); i0=$(ios_now)
  bash "$H/run_flow.sh" android "$F/$cf" "${c}_callee" "$@" &
  local A=$!
  if wait_rec_android "$e0" 300; then log "$c Pixel recording started (RecordActivityMonitor)"; else log "$c Pixel recording start NOT seen in 300 s"; fi
  bash "$H/run_flow.sh" ios "$F/$kf" "${c}_caller" "$@"
  wait $A
  report_case "$c" android "$e0" "$i0"
}

ensure_apps
if case_on V1; then
  log "=== V1 Pixel records in the 1:1 chat, iPhone calls, Pixel answers"
  pixel_callee V1 v23_rec_answer.yaml v23_call.yaml
  bash "$H/run_flow.sh" ios ensure_chat.yaml V1_rx > /dev/null
  log "V1 iPhone voice bubbles: $(voice_nodes V1_rx ios | tr '\n' ';')"
fi
if case_on V3; then
  log "=== V3 Pixel records, iPhone calls, Pixel declines"
  pixel_callee V3 v23_rec_decline.yaml v23_call_declined.yaml
  bash "$H/run_flow.sh" ios ensure_chat.yaml V3_rx > /dev/null
  log "V3 iPhone voice bubbles: $(voice_nodes V3_rx ios | tr '\n' ';')"
fi
if case_on V5; then
  log "=== V5 Pixel records, iPhone calls and cancels before an answer"
  pixel_callee V5 v23_rec_unanswered.yaml v23_call_cancel.yaml
  bash "$H/run_flow.sh" ios ensure_chat.yaml V5_rx > /dev/null
  log "V5 iPhone voice bubbles: $(voice_nodes V5_rx ios | tr '\n' ';')"
fi
if case_on V2; then
  log "=== V2 iPhone records in the 1:1 chat, Pixel calls, iPhone answers"
  bash "$H/run_flow.sh" android ensure_chat.yaml V2_prep > /dev/null
  e0=$(emu_now); i0=$(ios_now)
  bash "$H/run_flow.sh" ios "$F/v23_rec_answer.yaml" V2_callee &
  I=$!
  if wait_rec_ios "$i0" 360; then log "V2 iPhone recording started (CONV_FL_RECORD_STARTED)"; else log "V2 iPhone recording start NOT seen in 360 s"; fi
  bash "$H/run_flow.sh" android "$F/v23_call.yaml" V2_caller
  wait $I
  report_case V2 ios "$e0" "$i0"
  bash "$H/run_flow.sh" android ensure_chat.yaml V2_rx > /dev/null
  log "V2 Pixel voice bubbles: $(voice_nodes V2_rx android | tr '\n' ';')"
fi
if case_on V4; then
  N=v4$S
  log "=== V4 group R2 Group $N: Pixel records in the group, iPhone calls (1:1), Pixel answers"
  bash "$H/pair.sh" V4_create $F/t16_create_ios.yaml $F/t16_accept_android.yaml NONCE=$N
  pixel_callee V4 v23_rec_answer_group.yaml v23_call.yaml "GROUP=R2 Group $N"
  bash "$H/run_flow.sh" ios "$F/open_group.yaml" V4_rx "GROUP=R2 Group $N" "GTIMEOUT=60000" > /dev/null
  log "V4 iPhone group voice bubbles: $(voice_nodes V4_rx ios | tr '\n' ';')"
fi

now=$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl spawn "$UDID" log show --style compact --info --debug --start "$IOS_T0" --end "$now" \
  --predicate 'process == "Runner"' > "$RUN/ios_log_validate.txt" 2>&1
log "ios log: $(wc -l < "$RUN/ios_log_validate.txt") lines"
log "mediaConflict whole run: Pixel $(grep -c 'mediaConflict' "$RUN/android_logcat_live.txt"), iPhone $(grep -c 'mediaConflict' "$RUN/ios_log_validate.txt")"
for f in $(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null); do
  grep -qx "$f" "$RUN/crash/baseline_list.txt" || cp ~/Library/Logs/DiagnosticReports/"$f" "$RUN/crash/" 2>/dev/null
done
log "new crash reports: $(ls "$RUN/crash" | grep -v baseline_list | tr '\n' ' ')"
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
log "R23 VALIDATE DONE"
