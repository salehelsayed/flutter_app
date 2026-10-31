#!/bin/bash
# Read-only: print repo path on the Mac and poster/camera lines of an emulator log.
echo "REPO=$(cd "$(dirname "$0")/.." && pwd)"; grep -i "poster\|virtualscene\|camera" "/tmp/emulator_${1:?avd}_${2:?port}.log" | tail -10
