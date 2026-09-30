#!/bin/bash
# R2-4 follow-up + R2-6 validation on the two phones (build-r2-5 installed in place).
#  M0  test media: r25_motion.mp4 (testsrc, 720x1280, 30 fps, H.264 with B-frames) and r25_bad_video.mp4 (H.264 High
#      4:4:4, which Android cannot decode) pushed to the Pixel gallery
#  A1-A3 Pixel sends 2 photos + r2_video_1.mp4 (the R2-4 clip); the iPhone must receive it (3 tries)
#  A4  Pixel sends r25_motion.mp4; the iPhone must receive it; the processed output is pulled and compared to the
#      source frame by frame (SSIM), to check the timestamp interpolator did not scramble frames
#  A5  Pixel picks a photo + r25_bad_video.mp4: "Media unavailable" notice, photo kept, video not attached
#  A6  iPhone sends r2_video_1.mp4; the Pixel must receive it
#  N1  R2-6: Pixel app in the background, iPhone calls; the call notification must name the caller (ringing + ongoing)
#  N2  R2-6: Pixel app killed, iPhone calls; same check if the call rings
# R2-4 follow-up 2 (15 fps cap) + R2-6 follow-up 2 validation (run_r27_validate.sh). One app process for C1-C5:
#  C1-C3 r25_motion.mp4 (30 fps, B-frames) x3 | C4 r25_bad_video.mp4 (4:4:4) | C5 album with r2_video_1.mp4
#  N3 R2-6 call with the Pixel app in the foreground | N4 app sent to the background just before the call
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh" > /dev/null
RUN=$(current_run)
cp "$BETA/build-r2-7/build_name.txt" "$BETA/build-r2-7/provenance.txt" "$RUN/" 2>/dev/null
TL="$RUN/timeline.txt"
CASES="${*:-C1 C2 C3 C4 C5 N3 N4}"
S=$(date +%H%M)
F=r2
FF=/opt/homebrew/bin/ffmpeg; FP=/opt/homebrew/bin/ffprobe
MEDIA="$BETA/r2-5-media"; mkdir -p "$MEDIA"
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$TL"; }
mkdir -p "$RUN/crash" "$RUN/extra" "$RUN/ui"
ls ~/Library/Logs/DiagnosticReports/ > "$RUN/crash/baseline_list.txt" 2>/dev/null
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
echo $! > "$RUN/logcat.pid"
IOS_T0=$(date '+%Y-%m-%d %H:%M:%S')
ios_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>/dev/null; }
log "R27 VALIDATE start cases=[$CASES] builds: android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') ios=$(ios_version) mac_load=$(sysctl -n vm.loadavg | awk '{print $2}')"
pid_and() { $ADB shell pidof $PKG 2>/dev/null | tr -d '\r'; }
ensure_apps() {
  [ -z "$(pid_and)" ] && { $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 20; }
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
}
emu_now() { $ADB shell date "'+%m-%d %H:%M:%S'" | tr -d '\r'; }
case_on() { case " $CASES " in *" $1 "*) return 0 ;; esac; return 1; }
since() { awk -v s="$1" '($1 " " substr($2,1,8)) >= s' "$RUN/android_logcat_live.txt"; }
app_events_since() {  # video / notice related app events on the Pixel since "<MM-DD HH:MM:SS>"
  since "$1" | grep -oE '"event":"[A-Z_]*(PICK_GALLERY_ERROR|RETRY_VIDEO|VIDEO|MEDIA_PROCESS)[A-Z_]*"[^}]*' | sort | uniq -c | head -8 | tr '\n' ';'
}
stall_signs_since() {  # last transcoder progress + any 5-minute gap without transcoder lines
  since "$1" | grep -E "TranscodeEngine|Transcoder" | tail -1 | cut -c1-160
}
rx_video_nodes() {  # rx_video_nodes <label> <ios|android>: nodes that look like a video tile duration (m:ss)
  bash "$H/dump_ui.sh" "$1" "$2" > /dev/null 2>&1
  /usr/bin/python3 - "$RUN/ui/$1_$2.json" <<'PY'
import json, re, sys
raw = open(sys.argv[1]).read(); i = raw.find("{")
if i < 0: print("no hierarchy"); sys.exit(0)
root = json.loads(raw[i:]); hits = []
def walk(n):
    a = n.get("attributes", {})
    t = " | ".join(x for x in (a.get("accessibilityText"), a.get("text")) if x)
    if re.search(r"(?i)video|\b0:0[0-9]\b|play", t): hits.append(t.replace("\n", " / ")[:120])
    for c in n.get("children", []): walk(c)
walk(root)
print("; ".join(hits[:8]) or "none")
PY
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
call_case() {  # call_case <case> <android flow>
  local c=$1 af=$2 start ready i
  bash "$H/run_flow.sh" ios ensure_chat.yaml "${c}_prep" > /dev/null
  rm -f "$RUN/.${c}_stop"; notif_poll "$RUN/.${c}_stop" & POLL=$!
  start=$(emu_now)
  bash "$H/run_flow.sh" android "$F/$af" "${c}_callee" &
  local A=$!
  ready=0
  for i in $(seq 1 240); do
    since "$start" | grep -qE " Maestro *: Requesting view hierarchy" && { ready=1; break; }
    kill -0 $A 2>/dev/null || break
    sleep 1
  done
  log "$c callee maestro $([ $ready = 1 ] && echo ready || echo NOT ready) after ${i}s"
  bash "$H/run_flow.sh" ios "$F/v26_caller_ios.yaml" "${c}_caller"
  wait $A
  touch "$RUN/.${c}_stop"; wait $POLL 2>/dev/null
  log "$c call notifications seen: $(grep -oE 'android\.title=String \([^)]*\)|android\.text=String \([^)]*\)' "$RUN/extra/call_notifications.txt" | sort | uniq -c | tr '\n' ';')"
}
restart_pixel_app() { $ADB shell am force-stop $PKG; sleep 2; $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 25; log "pixel app restarted (pid $(pid_and))"; }
newest_output_check() {  # newest transcoder output since "<HH-MM-SS name prefix after>": duration/frames or "unfinished"
  local D=/sdcard/Android/data/$PKG/files/video_compress f
  f=$($ADB shell "ls $D" | tr -d '\r' | grep "VID_$(date +%Y-%m-%d).*\.mp4" | sort | tail -1)
  [ -z "$f" ] && { echo "no output"; return; }
  $ADB pull "$D/$f" "$RUN/extra/$f" > /dev/null 2>&1
  echo "$f: $($FP -v error -select_streams v -show_entries stream=width,height,nb_frames:format=duration -of csv=p=0 "$RUN/extra/$f" 2>&1 | tr '\n' ' ' | cut -c1-120)"
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
call_case() {  # call_case <case> <android flow>
  local c=$1 af=$2 start ready i
  bash "$H/run_flow.sh" ios ensure_chat.yaml "${c}_prep" > /dev/null
  rm -f "$RUN/.${c}_stop"; notif_poll "$RUN/.${c}_stop" & POLL=$!
  start=$(emu_now)
  bash "$H/run_flow.sh" android "$F/$af" "${c}_callee" &
  local A=$!
  ready=0
  for i in $(seq 1 240); do
    since "$start" | grep -qE " Maestro *: Requesting view hierarchy" && { ready=1; break; }
    kill -0 $A 2>/dev/null || break
    sleep 1
  done
  log "$c callee maestro $([ $ready = 1 ] && echo ready || echo NOT ready) after ${i}s"
  bash "$H/run_flow.sh" ios "$F/v26_caller_ios.yaml" "${c}_caller"
  wait $A
  touch "$RUN/.${c}_stop"; wait $POLL 2>/dev/null
  log "$c call notifications seen: $(grep -oE 'android\.title=String \([^)]*\)|android\.text=String \([^)]*\)' "$RUN/extra/call_notifications.txt" | sort | uniq -c | tr '\n' ';')"
}
restart_pixel_app() { $ADB shell am force-stop $PKG; sleep 2; $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 25; log "pixel app restarted (pid $(pid_and))"; }
newest_output_check() {  # newest transcoder output (by mtime): frames/fps/duration, or "unfinished"
  local D=/sdcard/Android/data/$PKG/files/video_compress f
  f=$($ADB shell "ls -t $D" | tr -d '\r' | grep "^VID_.*\.mp4$" | head -1)
  [ -z "$f" ] && { echo "no output"; return; }
  $ADB pull "$D/$f" "$RUN/extra/$f" > /dev/null 2>&1
  echo "$f: $($FP -v error -select_streams v -show_entries stream=width,height,nb_frames,r_frame_rate,avg_frame_rate:format=duration -of csv=p=0 "$RUN/extra/$f" 2>&1 | tr '\n' ' ' | cut -c1-140)"
}
output_dir_listing() { $ADB shell "ls -l /sdcard/Android/data/$PKG/files/video_compress" | tr -d '\r' | awk '/\.mp4/ {print $5, $NF}' | tail -40; }
ensure_apps
restart_pixel_app
output_dir_listing > "$RUN/extra/video_compress_before.txt"
log "video_compress dir before: $(wc -l < "$RUN/extra/video_compress_before.txt" | tr -d ' ') mp4 files"
case_video() {  # case_video <case> <flow> <video> <caption prefix for the receiver>
  local c=$1 fl=$2 v=$3 cap=$4 N=$1$S e0
  e0=$(emu_now)
  log "=== $c Pixel sends $v ($cap $N)"
  bash "$H/run_flow.sh" android "$F/$fl" "${c}_send" NONCE=$N VIDEO=$v
  log "$c output: $(newest_output_check)"
  log "$c transcoder threads: $(since "$e0" | grep -oE 'TranscoderThread #[0-9]+' | sort -u | tr '\n' ' ')"
  bash "$H/run_flow.sh" ios "$F/v25_rx.yaml" "${c}_rx" "TEXT=$cap $N"
  log "$c iPhone video nodes: $(rx_video_nodes ${c}_rx ios)"
}
case_on C1 && case_video C1 v27_video_android.yaml r25_motion.mp4 "R27 video"
case_on C2 && case_video C2 v27_video_android.yaml r25_motion.mp4 "R27 video"
case_on C3 && case_video C3 v27_video_android.yaml r25_motion.mp4 "R27 video"
case_on C4 && case_video C4 v27_video_android.yaml r25_bad_video.mp4 "R27 video"
case_on C5 && case_video C5 v27_album_android.yaml r2_video_1.mp4 "R27 album"
output_dir_listing > "$RUN/extra/video_compress_after.txt"
log "video_compress dir after: $(wc -l < "$RUN/extra/video_compress_after.txt" | tr -d ' ') mp4 files; new: $(comm -13 <(sort "$RUN/extra/video_compress_before.txt") <(sort "$RUN/extra/video_compress_after.txt") | tr '\n' ';' | cut -c1-400)"
if case_on N3; then
  restart_pixel_app
  log "=== N3 R2-6: Pixel app in the foreground (chat open), iPhone calls"
  echo "--- N3" >> "$RUN/extra/call_notifications.txt"; e0=$(emu_now)
  call_case N3 v26_fg_callee_android.yaml
  log "N3 native updatePresentation lines: $(since "$e0" | grep -oE 'updatePresentation accepted=[a-z]+ state=[a-z]+ named=[a-z]+ refreshed=[a-z]+' | uniq -c | tr '\n' ';')"
fi
if case_on N4; then
  log "=== N4 R2-6: Pixel app goes to the background just before the call"
  echo "--- N4" >> "$RUN/extra/call_notifications.txt"; e0=$(emu_now)
  call_case N4 v26_quickbg_callee_android.yaml
  log "N4 native updatePresentation lines: $(since "$e0" | grep -oE 'updatePresentation accepted=[a-z]+ state=[a-z]+ named=[a-z]+ refreshed=[a-z]+' | uniq -c | tr '\n' ';')"
fi
now=$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl spawn "$UDID" log show --style compact --info --debug --start "$IOS_T0" --end "$now" \
  --predicate 'process == "Runner"' > "$RUN/ios_log_validate.txt" 2>&1
for f in $(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null); do
  grep -qx "$f" "$RUN/crash/baseline_list.txt" || cp ~/Library/Logs/DiagnosticReports/"$f" "$RUN/crash/" 2>/dev/null
done
log "new crash reports: $(ls "$RUN/crash" | grep -v baseline_list | tr '\n' ' ')"
log "Pixel FATAL/ANR for the app: $(grep -cE 'FATAL EXCEPTION|ANR in com\.mknoon' "$RUN/android_logcat_live.txt")"
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
log "R27 VALIDATE DONE"
