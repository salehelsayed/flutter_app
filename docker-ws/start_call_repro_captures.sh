#!/bin/bash
# Start detached iPhone syslog captures (Runner process) for a call repro and
# return immediately. Output dir: docker-ws/deploy-captures/callrepro-<stamp>/
# Stop with docker-ws/kill_stray_syslog_captures.sh. Pixel logcat is streamed
# separately from the container via adb.
set -uo pipefail
cd "$(dirname "$0")/.."
IPHONE_UDIDS="${IPHONE_UDIDS:-00008030-001A6D2801BB802E 00008110-00184D622289801E}"
STAMP=$(date +%y%m%d%H%M%S)
CAP_REL="deploy-captures/callrepro-$STAMP"
mkdir -p "docker-ws/$CAP_REL"
pkill -f idevicesyslog 2>/dev/null; sleep 1
for UDID in $IPHONE_UDIDS; do
  nohup docker-ws/capture_iphone_syslog_any.sh "$UDID" "$CAP_REL/iphone_${UDID:0:8}_syslog.txt" >/dev/null 2>&1 &
  echo "started syslog capture $UDID pid=$! -> docker-ws/$CAP_REL/iphone_${UDID:0:8}_syslog.txt"
done
sleep 3
pgrep -fl idevicesyslog || echo "WARNING: no idevicesyslog running"
echo "CAPTURE_DIR=docker-ws/$CAP_REL"
