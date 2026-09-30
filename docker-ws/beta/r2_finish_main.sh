#!/bin/bash
# Stop the main round 2 run after phase E (the Pixel still blocks the iPhone: the unblock
# flow could not reach the hidden chat), save the phase E iPhone log, crash reports and
# Android crash/ANR records into the run folder, then unblock from the chat list.
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
RUN=$BETA/run-20260927-174851
TL="$RUN/timeline.txt"
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$TL"; }
bash "$H/stop_round2.sh" > /dev/null 2>&1
sleep 3
log "main run stopped by hand after phase E (phase F runs separately after an unblock from the chat list)"
now=$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl spawn "$UDID" log show --style compact --info --debug --start "2026-09-27 20:38:16" --end "$now" \
  --predicate 'process == "Runner"' > "$RUN/ios_log_E.txt" 2>&1
log "ios log chunk E: $(wc -l < "$RUN/ios_log_E.txt") lines (2026-09-27 20:38:16 .. $now)"
for f in $(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null); do
  grep -qx "$f" "$RUN/crash/baseline_list.txt" || cp ~/Library/Logs/DiagnosticReports/"$f" "$RUN/crash/" 2>/dev/null
done
log "new crash reports: $(ls "$RUN/crash" | grep -v baseline_list | tr '\n' ' ')"
$ADB shell dumpsys dropbox --print data_app_crash > "$RUN/extra/android_dropbox_crash.txt" 2>&1
$ADB shell dumpsys dropbox --print data_app_anr > "$RUN/extra/android_dropbox_anr.txt" 2>&1
$ADB shell dumpsys dropbox --print data_app_native_crash > "$RUN/extra/android_dropbox_native_crash.txt" 2>&1
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
pkill -f "adb -s $SERIAL logcat -T 1 -v threadtime" 2>/dev/null
echo "$RUN" > "$BETA/current_run.txt"
bash "$H/run_flow.sh" android r2/t15_unblock_list_android.yaml t15_unblock_by_hand
log "ROUND2 MAIN RUN DONE (phases A-E)"
tail -6 "$TL"
