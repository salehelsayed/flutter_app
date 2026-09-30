#!/bin/bash
# R2-2 validation load test (macOS bash 3.2). Runs r22_gen.py (fake Mknoon services, LocalOnly = this Mac only)
# against the iPhone simulator app, relaunches the app after every exit, records every new Runner crash report,
# and samples the app's CPU, memory, open files and unix sockets (DNS-SD handles) every 30 s.
# Stops early after MAXCRASH crash reports (0 = never), at the deadline, when $OUT/.stop exists, or at once
# if a Mknoon app runs anywhere else on this Mac (another simulator or a macOS build would see the fake services).
# Usage: r22_stress.sh <label> <seconds> [maxcrash=0] [quiet=4] [update=6] [churn=6] [ifaces=lo0 | lo0,local]
# Output: $BETA/r2-2/<label>-<HHMMSS>/{stress.log,gen.log,gen_counts.txt,services.txt,ios_log.txt,summary.txt,crash/}
. "$(dirname "$0")/beta_env.sh"
H="$(cd "$(dirname "$0")" && pwd)"
LABEL=${1:?label}; DUR=${2:?seconds}; MAXCRASH=${3:-0}; NQ=${4:-4}; NU=${5:-6}; NC=${6:-6}; IFS_=${7:-lo0}
OUT="$BETA/r2-2/$LABEL-$(date +%H%M%S)"; mkdir -p "$OUT/crash"; echo "$OUT" > "$BETA/r2-2/current.txt"
LOG="$OUT/stress.log"
note() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }
app_pid() { xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | awk '/UIKitApplication:com.mknoon.app/ {print $1; exit}'; }
others() { ps -axo pid=,command= | grep -iE '/Runner[^/ ]*\.app/Runner( |$)|\.app/Contents/MacOS/(runner|mknoon)' | grep -v -e "$UDID" -e grep | cut -c1-200; }
APPV=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist")
note "start label=$LABEL dur=${DUR}s maxcrash=$MAXCRASH quiet=$NQ update=$NU churn=$NC ifaces=$IFS_ app_build=$APPV load=$(sysctl -n vm.loadavg)"
o=$(others); if [ -n "$o" ]; then note "ABORT before start: another Mknoon app is running: $o"; echo ABORTED > "$OUT/summary.txt"; echo "R22 STRESS DONE" >> "$LOG"; exit 3; fi
p=$(app_pid); if [ -z "$p" ] || [ "$p" = "-" ]; then xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1; note "app was not running: launched"; sleep 20; fi
note "app pid $(app_pid)"
touch "$OUT/.mark"; START=$(date '+%Y-%m-%d %H:%M:%S'); T0=$(date +%s)
R22_IF=$IFS_ /usr/bin/python3 "$H/r22_gen.py" "$OUT" "$DUR" "$NQ" "$NU" "$NC" > "$OUT/gen.log" 2>&1 &
GEN=$!
crashes=0; launches=0; last_sample=0
scan() {
  for f in $(find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'Runner-*.ips' -newer "$OUT/.mark" 2>/dev/null); do
    b=$(basename "$f"); [ -f "$OUT/crash/$b" ] && continue
    cp "$f" "$OUT/crash/"; crashes=$((crashes+1)); note "CRASH REPORT $b | $(/usr/bin/python3 "$H/r22_sig.py" "$f" 2>&1)"
  done
}
while kill -0 $GEN 2>/dev/null; do
  sleep 3
  scan
  p=$(app_pid)
  if [ -z "$p" ] || [ "$p" = "-" ]; then
    note "app not running"; sleep 8; scan
    xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1; launches=$((launches+1)); note "relaunched (#$launches) pid $(app_pid)"
  elif [ $(( $(date +%s) - last_sample )) -ge 30 ]; then
    last_sample=$(date +%s); lsof -p "$p" > "$OUT/.lsof" 2>/dev/null
    note "sample pid=$p $(ps -o %cpu=,rss= -p "$p" | awk '{printf "cpu=%s%% rss=%dMB", $1, $2/1024}') fds=$(wc -l < "$OUT/.lsof" | tr -d ' ') unix_socks=$(awk '$5=="unix"' "$OUT/.lsof" | wc -l | tr -d ' ') gen: $(tail -1 "$OUT/gen_counts.txt" 2>/dev/null | cut -d' ' -f1-5)"
  fi
  o=$(others); if [ -n "$o" ]; then note "STOP: another Mknoon app is running: $o"; touch "$OUT/.stop"; fi
  if [ "$MAXCRASH" -gt 0 ] && [ "$crashes" -ge "$MAXCRASH" ]; then note "STOP: $crashes crash reports"; touch "$OUT/.stop"; fi
done
wait $GEN; note "generator ended: $(tail -1 "$OUT/gen_counts.txt" 2>/dev/null)"
sleep 20; scan
END=$(date '+%Y-%m-%d %H:%M:%S'); T1=$(date +%s)
note "collecting the app log $START .. $END"
xcrun simctl spawn "$UDID" log show --start "$START" --end "$END" --predicate 'process == "Runner"' --style compact > "$OUT/ios_log.txt" 2>&1
/usr/bin/python3 "$H/r22_summary.py" "$OUT" "$((T1-T0))" "$crashes" "$launches" > "$OUT/summary.txt" 2>&1
note "DONE crashes=$crashes relaunches=$launches"
echo "R22 STRESS DONE" >> "$LOG"
