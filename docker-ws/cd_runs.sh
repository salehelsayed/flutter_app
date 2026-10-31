#!/bin/bash
# Cold and warm resume runs on the Pixel for the call-advertisement dedup measure; dumps logcat per run.
#   host-run bash docker-ws/cd_runs.sh <evidence dir under repo>
set -u
R=/Volumes/CrucialX9/flutter_app; E="$R/$1"; S=21071FDF600CSC; P=com.mknoon.app
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
launch() { adb -s $S shell monkey -p $P -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; }
dump() { adb -s $S logcat -d -v time > "$E/$1.txt"; echo "$(date -u +%H:%M:%S) $1 dumped $(grep -c 'DIAG_ADV_CALL' "$E/$1.txt") DIAG_ADV_CALL" >> "$E/progress.txt"; }
for i in 1 2; do
  adb -s $S shell am force-stop $P; sleep 3; adb -s $S logcat -c
  echo "$(date -u +%H:%M:%S) cold$i launch" >> "$E/progress.txt"; launch; sleep 45; dump cold$i
done
for i in 1 2 3 4 5; do
  adb -s $S logcat -c; adb -s $S shell input keyevent KEYCODE_HOME
  echo "$(date -u +%H:%M:%S) warm$i home" >> "$E/progress.txt"; sleep 30; launch; sleep 30; dump warm$i
done
echo "RUNS DONE" >> "$E/progress.txt"
