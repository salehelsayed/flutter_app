#!/bin/bash
# B8 device smoke test: a presented incoming call survives the app process being
# killed. Android = tested source + B5 + B8 (build/beta-android-b8.apk). R1: the iPhone
# calls; once the Pixel presented the call natively the app process is killed
# (run-as kill -9), then relaunched; the runtime restores the call off the main
# thread and the Pixel answers it. Then a normal call (S05a) as a regression check.
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh"
RUN=$(current_run)
. "$H/gates.sh"
TL="$RUN/timeline.txt"
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$TL"; }
cp "$BETA/build/b8_build_name.txt" "$BETA/build/b8_result.txt" "$RUN/" 2>/dev/null
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
pkill -f "adb -s $SERIAL logcat -T 1 -v threadtime" 2>/dev/null
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
sleep 1; pgrep -f "logcat -T 1 -v threadtime" | tail -1 > "$RUN/logcat.pid"

# The adb client can hang after the install itself finished (2026-09-26 21:23): bound it
# and judge by the installed version.
want=$(cat "$BETA/build/b8_build_name.txt")
have=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r' | sed 's/versionName=//')
if [ "$have" != "$want" ]; then
  log "android install: $(timeout 300 $ADB install -r -d "$BETA/build/beta-android-b8.apk" 2>&1 | tail -1)"
  have=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r' | sed 's/versionName=//')
else
  log "android build already installed: $have"
fi
if [ "$have" != "$want" ]; then log "android install NOT verified: have $have want $want; stopping"; exit 1; fi
$ADB shell am force-stop $PKG
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null; xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
log "builds: android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r')"
bash "$H/dump_ui.sh" warmup > /dev/null 2>&1
log "maestro warm-up done"

utc_now() { date -u '+%H:%M:%S'; }
diag() { bash "$H/call_diag_windows.sh" "$2-$3" > "$RUN/diag_$1.txt" 2>&1; }
ready() {
  $ADB shell svc wifi enable; $ADB shell svc data enable
  $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 25
  bash "$H/pair.sh" ready_$1 cal_ensure.yaml cal_ensure.yaml
  gate "$1"
  log "ready for $1 (app pid $($ADB shell pidof $PKG))"
}
emu_now() { $ADB shell date "'+%m-%d %H:%M:%S'" | tr -d '\r'; }
seen_since() {  # seen_since <emulator time> <regex>: the pattern logged at/after that time
  tail -c 4000000 "$RUN/android_logcat_live.txt" | grep -E "$2" | awk -v s="$1" '($1 " " $2) >= s' | grep -q .
}

# ---------------- R2: restart during a headless (not Dart-adopted) ringing call
# B8's path is reconcilePresented, which restores only calls Dart has NOT adopted; a
# foreground app adopts at once (then a restart ends the call as provider loss, by
# design). So: kill the idle app (no force-stop, FCM still works), let the call wake it
# headless, kill it again while it rings, relaunch, and look for the re-registration.
ready r2
$ADB shell input keyevent KEYCODE_HOME; sleep 2
idle=$($ADB shell pidof $PKG | tr -d '\r')
[ -n "$idle" ] && $ADB shell run-as $PKG kill -9 "$idle"
sleep 3
log "r2 idle app killed (pid $idle); pid now: '$($ADB shell pidof $PKG | tr -d '\r')'"
t0=$(utc_now)
start=$(emu_now)
bash "$H/run_flow.sh" ios connect_ios_caller.yaml r2_call TAG=r2 HOLD=20000 &
P=$!
presented=0
for i in $(seq 1 75); do
  seen_since "$start" "MKNOON_CALL_PRESENTATION_DIAG result=PRESENTED" && { presented=1; break; }
  sleep 1
done
if [ $presented = 1 ]; then
  log "r2 presented headless after ${i}s (worker: $(seen_since "$start" "Starting work for com.mknoon.app.call.HeadlessCallAdmissionWorker" && echo yes || echo no), activity: $(seen_since "$start" "MknoonCallSplash: CALL_ANDROID_SPLASH phase=resume" && echo yes || echo no))"
  sleep 2
  pid=$($ADB shell pidof $PKG | tr -d '\r')
  $ADB shell run-as $PKG kill -9 "$pid"
  sleep 1
  killed=$(emu_now)
  log "r2 killed ringing app pid $pid; pid now: '$($ADB shell pidof $PKG | tr -d '\r')'"
  sleep 2
  $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  log "r2 relaunched (app pid $($ADB shell pidof $PKG | tr -d '\r'))"
  for i in $(seq 1 60); do
    seen_since "$killed" "CallsManager: addCall" && break
    sleep 1
  done
  log "r2 re-registration after the kill: $(seen_since "$killed" "CallsManager: addCall" && echo seen || echo NOT seen) (${i}s); provider_reset/terminal: $(seen_since "$killed" "PROVIDER_REMOVED|provider_reset" && echo yes || echo no)"
  bash "$H/run_flow.sh" android r1_answer_android.yaml r2_answer
else
  log "r2 the Pixel never presented the call within 75 s; no kill"
fi
wait $P
diag r2 "$t0" "$(utc_now)"

# ---------------- regression: a normal incoming call
ready s05a
t0=$(utc_now)
bash "$H/pair_callee_first.sh" s05a s05a_ios.yaml s05a_android.yaml
diag s05a "$t0" "$(utc_now)"

ready end
bash "$H/logs_stop.sh" > /dev/null 2>&1
log "B8 RUN DONE"
