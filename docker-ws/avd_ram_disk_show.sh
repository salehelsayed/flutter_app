#!/bin/bash
# Read-only: hw.ramSize and data partition size for named AVDs (dir from avd ini path=).
for a in "$@"; do
  ini="$HOME/.android/avd/$a.ini"; d=$(sed -n 's/^path=//p' "$ini")
  echo "== $a"; sed -n -E '/^(hw.ramSize|disk.dataPartition.size|hw.cpu.ncore)/p' "$d/config.ini"
done
