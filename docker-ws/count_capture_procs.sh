#!/bin/bash
# Read-only: count running idevicesyslog and adb logcat processes on the Mac (any owner session).
#   host-run bash docker-ws/count_capture_procs.sh
echo "idevicesyslog=$(ps -axo args= | grep -c '^[^ ]*idevicesyslog')"
echo "adb_logcat=$(ps -axo args= | grep -E '^[^ ]*adb .*logcat' | grep -vc grep)"
