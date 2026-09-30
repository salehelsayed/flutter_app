#!/bin/bash
# R2-4 fix verification on the two phones (R2-4 builds installed in place).
#  D1a D1b D1c  Pixel sends 2 photos + the 7 s 1178x2556 video (T02); iPhone must receive it. Three tries, because
#               the round-2 transcode stall was intermittent (1 of 2). A stall now ends after 5 min with
#               "Video processing stopped. Try again." and the flow taps Retry.
#  D2           iPhone sends the same video; Pixel must receive it. A Mac sampler records the simulator's media
#               processes during the transcode (to find one that can be paused to force a real stall).
# Usage: run_r24_validate.sh [case ...]   (default: D1a D1b D1c D2)
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh" > /dev/null
RUN=$(current_run)
cp "$BETA/build-r2-4/build_name.txt" "$BETA/build-r2-4/provenance.txt" "$RUN/" 2>/dev/null
TL="$RUN/timeline.txt"
CASES="${*:-D1a D1b D1c D2}"
S=$(date +%H%M)
F=r2
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$TL"; }
mkdir -p "$RUN/crash" "$RUN/extra" "$RUN/ui"
ls ~/Library/Logs/DiagnosticReports/ > "$RUN/crash/baseline_list.txt" 2>/dev/null
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
echo $! > "$RUN/logcat.pid"
IOS_T0=$(date '+%Y-%m-%d %H:%M:%S')
ios_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>/dev/null; }
log "R24 VALIDATE start cases=[$CASES] builds: android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') ios=$(ios_version) mac_load=$(sysctl -n vm.loadavg | awk '{print $2}')"
pid_and() { $ADB shell pidof $PKG 2>/dev/null | tr -d '\r'; }
ensure_apps() {
  [ -z "$(pid_and)" ] && { $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 20; }
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
}
emu_now() { $ADB shell date "'+%m-%d %H:%M:%S'" | tr -d '\r'; }
case_on() { case " $CASES " in *" $1 "*) return 0 ;; esac; return 1; }
others_since() {  # force-stops / reinstalls of the app on the Pixel since "<MM-DD HH:MM:SS>" (not sent by this run)
  awk -v s="$1" '($1 " " substr($2,1,8)) >= s' "$RUN/android_logcat_live.txt" \
    | grep -cE "Force stopping com\.mknoon\.app|killDueToPackageUpdate|io\.appium.* -> .*com\.mknoon\.app"
}
codec_since() {  # the Pixel transcoder's codec lines since "<MM-DD HH:MM:SS>"
  awk -v s="$1" '($1 " " substr($2,1,8)) >= s' "$RUN/android_logcat_live.txt" \
    | grep -E "Transcoder|TranscodeEngine|VideoCompress|MediaCodec.*(error|Error)|c2\.[a-z.]*(enc|dec).*(error|stop|release)" | tail -4 | cut -c1-200
}
ensure_apps
for C in D1a D1b D1c; do
  if case_on $C; then
    N=$C$S; e0=$(emu_now)
    log "=== $C Pixel sends 2 photos + the 7 s video (R24 album $N)"
    bash "$H/run_flow.sh" android "$F/v24_album_android.yaml" "${C}_send" NONCE=$N
    bash "$H/run_flow.sh" ios "$F/v24_rx.yaml" "${C}_rx" "TEXT=R24 album $N"
    log "$C stall notice shown: $([ -n "$(ls "$RUN/maestro/${C}_send_android" 2>/dev/null)" ] && (find "$RUN/maestro/${C}_send_android" -name '*v24_stall_notice*' | grep -q . && echo YES || echo no))"
    log "$C other-session force-stops/reinstalls on the Pixel during the case: $(others_since "$e0")"
    log "$C transcoder tail: $(codec_since "$e0" | tr '\n' ';')"
  fi
done
if case_on D2; then
  N=D2$S
  log "=== D2 iPhone sends the 7 s video (R24 ivideo $N); sampling the simulator's media processes"
  SIMLD=$(ps -axo pid,command | grep "launchd_sim .*$UDID" | grep -v grep | awk '{print $1}' | head -1)
  ( while [ ! -f "$RUN/.d2_done" ]; do
      echo "--- $(date '+%H:%M:%S')"
      ps -axo pid,ppid,%cpu,command | awk -v p="$SIMLD" '$2 == p' | grep -iE "media|VT|coremedia|avconf|videotool|export|encod" | cut -c1-200
      sleep 2
    done ) > "$RUN/extra/d2_sim_media_procs.txt" 2>&1 &
  bash "$H/run_flow.sh" ios "$F/v24_video_ios.yaml" D2_send NONCE=$N
  touch "$RUN/.d2_done"
  bash "$H/run_flow.sh" android "$F/v24_rx.yaml" D2_rx "TEXT=R24 ivideo $N"
  log "D2 stall notice shown: $(find "$RUN/maestro/D2_send_ios" -name '*v24_stall_notice*' | grep -q . && echo YES || echo no)"
  log "D2 simulator media processes seen: $(grep -v '^---' "$RUN/extra/d2_sim_media_procs.txt" | awk '{print $4}' | sed 's#.*/##' | sort | uniq -c | tr '\n' ';')"
fi
now=$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl spawn "$UDID" log show --style compact --info --debug --start "$IOS_T0" --end "$now" \
  --predicate 'process == "Runner"' > "$RUN/ios_log_validate.txt" 2>&1
log "ios log: $(wc -l < "$RUN/ios_log_validate.txt") lines"
for f in $(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null); do
  grep -qx "$f" "$RUN/crash/baseline_list.txt" || cp ~/Library/Logs/DiagnosticReports/"$f" "$RUN/crash/" 2>/dev/null
done
log "new crash reports: $(ls "$RUN/crash" | grep -v baseline_list | tr '\n' ' ')"
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
log "R24 VALIDATE DONE"
