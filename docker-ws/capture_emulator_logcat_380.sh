#!/bin/bash
# Bounded receiver-side logcat capture for the plan 380 campaign.
#
# Run HOST-side (the container->Mac bridge does not forward env vars and
# refuses `bash -c`):
#   /claude-host-bin/host-run bash docker-ws/capture_emulator_logcat_380.sh
#
# Capped at 800 MB so an unattended capture can never repeat the 17.9 GB
# iphone13_syslog.txt runaway. The stream survives the campaign's own
# `logcat -c` calls: clearing the ring does not close a live reader.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/docker-ws/plan380_emu_logcat_run.txt"
adb -s emulator-5554 logcat -c 2>/dev/null || true
adb -s emulator-5554 logcat -v time 2>&1 | head -c 800000000 > "$OUT"
