#!/bin/bash
# Read-only: tail the headless emulator log written by start_avd_headless.sh.
#   host-run bash docker-ws/emulator_log_tail.sh <avd> <port> [lines]
[[ "$1" =~ ^[A-Za-z0-9_]+$ && "$2" =~ ^[0-9]+$ ]] || exit 2
tail -n "${3:-30}" "/tmp/emulator_$1_$2.log"
