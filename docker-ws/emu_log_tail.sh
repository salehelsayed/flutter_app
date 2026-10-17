#!/bin/bash
# Read-only: last lines of an emulator launch log written by start_emulator.sh / start_second_avd.sh.
#   host-run bash docker-ws/emu_log_tail.sh <avd> [port] [lines]
AVD="${1:?avd}"; PORT="${2:-}"; N="${3:-25}"
F="/tmp/emulator_${AVD}${PORT:+_$PORT}.log"
ls -la "$F" && tail -n "$N" "$F"
