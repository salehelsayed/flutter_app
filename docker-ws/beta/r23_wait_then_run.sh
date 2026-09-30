#!/bin/bash
# R2-3 device check, polite start: wait until no other session has driven the two beta devices for 10 minutes
# (Pixel: Appium lines, force-stops or package updates of com.mknoon.app in the live logcat; iPhone 15: an Appium
# WebDriverAgent runner), re-check the installed R2-3 builds (reinstall if replaced), then run the 5 cases.
# The watch stays on during the run and counts overlapping activity. Gives up after MAXWAIT seconds (default 3 h).
# Output: $BETA/r23_wait/wait.log (+ the run folder written by run_r23_validate.sh).
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
OUT="$BETA/r23_wait"; mkdir -p "$OUT"
LOG="$OUT/wait.log"; W="$OUT/watch.txt"; : > "$W"
MAXWAIT=${1:-10800}; IDLE=${2:-600}
note() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash -c \
  "$ANDROID_HOME/platform-tools/adb -s $SERIAL logcat -T 1 -v threadtime | grep --line-buffered -E 'appium|Force stopping com\.mknoon\.app|killDueToPackageUpdate' > '$W'" \
  > /dev/null 2>&1 < /dev/null &
sleep 2
ios_wda() { ps -axo command | grep -E "WebDriverAgentRunner|WebDriverAgent" | grep "$UDID" | grep -vc grep; }
note "watch start (idle needed ${IDLE}s, give up after ${MAXWAIT}s)"
t0=$(date +%s); last=$t0; prev=0
while :; do
  sleep 30
  n=$(wc -l < "$W" | tr -d ' '); i=$(ios_wda)
  if [ "$n" != "$prev" ] || [ "$i" -gt 0 ]; then
    last=$(date +%s); note "activity: pixel_lines=$n (+$((n-prev))) iphone_wda=$i last: $(tail -1 "$W" | cut -c1-140)"; prev=$n
  fi
  idle=$(( $(date +%s) - last ))
  [ $idle -ge "$IDLE" ] && { note "quiet for ${idle}s: starting"; break; }
  [ $(( $(date +%s) - t0 )) -ge "$MAXWAIT" ] && { note "GAVE UP: devices still busy after ${MAXWAIT}s"; pkill -f "logcat -T 1 -v threadtime | grep --line-buffered -E 'appium"; exit 3; }
done
want=$(cat "$BETA/build-r2-3/build_name.txt"); stamp=${want##*.t}
and_v=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r' | sed 's/versionName=//')
ios_v=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>/dev/null)
note "installed: android=$and_v ios=$ios_v (want $want)"
if [ "$and_v" != "$want" ] || [ "$ios_v" != "$stamp" ]; then note "reinstalling"; bash "$H/install_r23.sh" >> "$LOG" 2>&1; fi
n_before=$(wc -l < "$W" | tr -d ' ')
note "run start"
bash "$H/run_r23_validate.sh"
n_after=$(wc -l < "$W" | tr -d ' ')
note "run done: other-session Pixel lines during the run: $((n_after - n_before)); iphone_wda now: $(ios_wda)"
tail -n +$((n_before + 1)) "$W" | head -20 >> "$LOG"
pkill -f "logcat -T 1 -v threadtime | grep --line-buffered -E 'appium"
note "R23 WAIT DONE"
