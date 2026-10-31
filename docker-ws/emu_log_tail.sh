#!/bin/bash
# Read-only: tail the host log of one disposable emulator started by mlkit_start_avd_image.sh, plus load and memory.
#   host-run bash docker-ws/emu_log_tail.sh <avd> <port> [lines]
tail -n "${3:-20}" "/tmp/emulator_${1}_${2}.log"
sysctl -n vm.loadavg; memory_pressure 2>/dev/null | tail -1
