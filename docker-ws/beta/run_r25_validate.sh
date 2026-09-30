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
# Usage: run_r25_validate.sh [case ...]   (default: M0 A1 A2 A3 A4 A5 A6 N1 N2)
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh" > /dev/null
RUN=$(current_run)
cp "$BETA/build-r2-5/build_name.txt" "$BETA/build-r2-5/provenance.txt" "$RUN/" 2>/dev/null
TL="$RUN/timeline.txt"
CASES="${*:-M0 A1 A2 A3 A4 A5 A6 N1 N2}"
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
log "R25 VALIDATE start cases=[$CASES] builds: android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') ios=$(ios_version) mac_load=$(sysctl -n vm.loadavg | awk '{print $2}')"
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
ensure_apps

if case_on M0; then
  log "=== M0 test media"
  [ -f "$MEDIA/r25_motion.mp4" ] || $FF -hide_banner -loglevel error -f lavfi -i testsrc=size=720x1280:rate=30 -t 6 \
      -c:v libx264 -profile:v high -bf 3 -g 60 -pix_fmt yuv420p -movflags +faststart "$MEDIA/r25_motion.mp4"
  [ -f "$MEDIA/r25_bad_video.mp4" ] || $FF -hide_banner -loglevel error -f lavfi -i testsrc=size=640x480:rate=30 -t 3 \
      -c:v libx264 -profile:v high444 -pix_fmt yuv444p -movflags +faststart "$MEDIA/r25_bad_video.mp4"
  log "M0 motion: $($FP -v error -select_streams v -show_entries stream=codec_name,profile,width,height,has_b_frames,nb_frames -of csv=p=0 "$MEDIA/r25_motion.mp4")"
  log "M0 bad: $($FP -v error -select_streams v -show_entries stream=codec_name,profile,pix_fmt -of csv=p=0 "$MEDIA/r25_bad_video.mp4")"
  for f in r25_motion.mp4 r25_bad_video.mp4; do
    $ADB push "$MEDIA/$f" /sdcard/Movies/ > /dev/null 2>&1
    $ADB shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file:///sdcard/Movies/$f" > /dev/null 2>&1
  done
  sleep 3
  log "M0 pixel videos indexed: $($ADB shell content query --uri content://media/external/video/media --projection _display_name 2>&1 | grep -oE '(r2_video_1|r25_motion|r25_bad_video)\.mp4' | sort -u | tr '\n' ' ')"
fi

for C in A1 A2 A3; do
  if case_on $C; then
    N=$C$S; e0=$(emu_now)
    log "=== $C Pixel sends 2 photos + r2_video_1.mp4 (R25 album $N)"
    bash "$H/run_flow.sh" android "$F/v25_album_android.yaml" "${C}_send" NONCE=$N VIDEO=r2_video_1.mp4
    bash "$H/run_flow.sh" ios "$F/v25_rx.yaml" "${C}_rx" "TEXT=R25 album $N"
    log "$C iPhone video nodes: $(rx_video_nodes ${C}_rx ios)"
    log "$C Pixel app events: $(app_events_since "$e0")"
    log "$C last transcoder line: $(stall_signs_since "$e0")"
  fi
done

if case_on A4; then
  N=A4$S; e0=$(emu_now)
  log "=== A4 Pixel sends r25_motion.mp4 (R25 video $N)"
  $ADB shell run-as $PKG touch cache/.r25_a4_mark > /dev/null 2>&1
  bash "$H/run_flow.sh" android "$F/v25_video_android.yaml" A4_send NONCE=$N VIDEO=r25_motion.mp4
  bash "$H/run_flow.sh" ios "$F/v25_rx.yaml" A4_rx "TEXT=R25 video $N"
  log "A4 iPhone video nodes: $(rx_video_nodes A4_rx ios)"
  OUTF=$($ADB shell "run-as $PKG sh -c 'find /sdcard/Android/data/$PKG /data/data/$PKG/cache /data/user/0/$PKG -name \"*.mp4\" -newer cache/.r25_a4_mark 2>/dev/null'" | tr -d '\r' | head -3)
  log "A4 processed candidates: $(echo $OUTF)"
  P1=$(echo "$OUTF" | head -1)
  if [ -n "$P1" ]; then
    $ADB exec-out run-as $PKG cat "$P1" > "$RUN/extra/a4_processed.mp4"
    log "A4 processed: $($FP -v error -select_streams v -show_entries stream=codec_name,width,height,nb_frames,duration -of csv=p=0 "$RUN/extra/a4_processed.mp4")"
    $FP -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 "$RUN/extra/a4_processed.mp4" > "$RUN/extra/a4_pts.txt"
    log "A4 frame pts: $(wc -l < "$RUN/extra/a4_pts.txt" | tr -d ' ') frames, non-increasing steps: $(awk 'NR>1 && $1<=p {n++} {p=$1} END {print n+0}' "$RUN/extra/a4_pts.txt")"
    SW=$($FP -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$MEDIA/r25_motion.mp4")
    $FF -hide_banner -loglevel error -i "$RUN/extra/a4_processed.mp4" -i "$MEDIA/r25_motion.mp4" -lavfi \
      "[0:v]scale=${SW%,*}:${SW#*,}:flags=bicubic,setpts=PTS-STARTPTS[a];[1:v]setpts=PTS-STARTPTS[b];[a][b]ssim=stats_file=$RUN/extra/a4_ssim.log" -f null - 2>> "$RUN/extra/a4_ffmpeg.err"
    log "A4 per-frame SSIM vs source: $(awk '{for(i=1;i<=NF;i++) if($i ~ /^All:/){split($i,a,":"); v=a[2]; n++; s+=v; if(n==1||v<m)m=v; if(v<0.80)low++}} END {printf "frames=%d mean=%.3f min=%.3f below0.80=%d", n, s/n, m, low+0}' "$RUN/extra/a4_ssim.log")"
  fi
fi

if case_on A5; then
  N=A5$S; e0=$(emu_now)
  log "=== A5 Pixel picks r2_photo_4.png + r25_bad_video.mp4 (R25 badvideo $N)"
  bash "$H/run_flow.sh" android "$F/v25_bad_video_android.yaml" A5_send NONCE=$N
  bash "$H/run_flow.sh" ios "$F/v25_rx.yaml" A5_rx "TEXT=R25 badvideo $N"
  log "A5 iPhone video nodes (expect none for this message): $(rx_video_nodes A5_rx ios)"
  log "A5 Pixel app events: $(app_events_since "$e0")"
  log "A5 transcoder errors: $(since "$e0" | grep -iE 'Transcode.*(fail|error)|onTranscodeFailed|Exception' | grep -v Maestro | head -3 | cut -c1-200 | tr '\n' ';')"
fi

if case_on A6; then
  N=A6$S
  log "=== A6 iPhone sends r2_video_1.mp4 (R25 ivideo $N)"
  bash "$H/run_flow.sh" ios "$F/v25_video_ios.yaml" A6_send NONCE=$N
  bash "$H/run_flow.sh" android "$F/v25_rx.yaml" A6_rx "TEXT=R25 ivideo $N"
  log "A6 Pixel video nodes: $(rx_video_nodes A6_rx android)"
fi

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
if case_on N1; then
  log "=== N1 R2-6: Pixel app in the background, iPhone calls"
  ensure_apps; sleep 5
  $ADB shell input keyevent KEYCODE_HOME; sleep 2
  echo "--- N1" >> "$RUN/extra/call_notifications.txt"
  call_case N1 v26_bg_callee_android.yaml
fi
if case_on N2; then
  log "=== N2 R2-6: Pixel app killed, iPhone calls"
  $ADB shell am force-stop $PKG; sleep 2
  log "N2 pixel pid after force-stop: '$(pid_and)'"
  echo "--- N2" >> "$RUN/extra/call_notifications.txt"
  call_case N2 v26_bg_callee_android.yaml
fi

now=$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl spawn "$UDID" log show --style compact --info --debug --start "$IOS_T0" --end "$now" \
  --predicate 'process == "Runner"' > "$RUN/ios_log_validate.txt" 2>&1
log "ios log: $(wc -l < "$RUN/ios_log_validate.txt") lines"
for f in $(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null); do
  grep -qx "$f" "$RUN/crash/baseline_list.txt" || cp ~/Library/Logs/DiagnosticReports/"$f" "$RUN/crash/" 2>/dev/null
done
log "new crash reports: $(ls "$RUN/crash" | grep -v baseline_list | tr '\n' ' ')"
log "Pixel FATAL/ANR for the app: $(grep -cE 'FATAL EXCEPTION|ANR in com\.mknoon' "$RUN/android_logcat_live.txt")"
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
log "R25 VALIDATE DONE"
