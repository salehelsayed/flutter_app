#!/bin/bash
# Check the 0xdead10cc fix (abfb8ca3f) on the USB iPhone 13: cycle Mknoon between
# foreground and background, capture syslog per phase, then look for diagnostics
# grants, RunningBoard suspensions and 0xdead10cc kills.
# Run on the Mac: host-run bash docker-ws/beta/v3/dead10cc_verify.sh [cycles] [bg_seconds]
U=00008110-00184D622289801E
CYCLES=${1:-4}
BG=${2:-90}
cd /Volumes/CrucialX9/flutter_app || exit 1
OUT=docker-ws/beta/v3/dead10cc_verify
rm -rf "$OUT"; mkdir -p "$OUT/crash"
SYSLOG=/opt/homebrew/bin/idevicesyslog

phase() { # name seconds
  "$SYSLOG" -u $U > "$OUT/$1.log" 2>/dev/null &
  local pid=$!
  sleep "$2"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
}
launch() { xcrun devicectl device process launch --device $U "$@" > /dev/null 2>&1; }

echo "=== start $(date '+%F %T %z')"
launch --terminate-existing com.mknoon.app
phase fg0 45
i=1
while [ $i -le $CYCLES ]; do
  launch com.apple.Preferences
  phase bg$i "$BG"
  launch com.mknoon.app
  phase fg$i 30
  i=$((i+1))
done
xcrun devicectl device info processes --device $U 2>/dev/null | grep -i "Runner.app" > "$OUT/processes.txt"
/opt/homebrew/bin/idevicecrashreport -u $U -e -k "$OUT/crash" > /dev/null 2>&1

echo "=== per phase: Runner BG_TASK lines / mknoon suspensions / dead10cc"
for f in "$OUT"/fg*.log "$OUT"/bg*.log; do
  n=$(basename "$f" .log)
  bg=$(grep -c "Runner.*BG_TASK" "$f")
  sus=$(grep -ciE "runningboardd.*com\.mknoon\.app.*suspend" "$f")
  dl=$(grep -ci "dead10cc" "$f")
  echo "$n bg_task=$bg suspend=$sus dead10cc=$dl"
done
echo "=== Runner process now"; cat "$OUT/processes.txt"
echo "=== newest Runner crash reports on the phone (the name holds the date)"
find "$OUT/crash" -type f -iname "*Runner*" | sort | tail -5
echo "=== of those, with dead10cc"
grep -l "dead10cc" $(find "$OUT/crash" -type f -iname "*Runner*" | sort | tail -5) /dev/null 2>/dev/null
echo "=== end $(date '+%F %T %z')"
