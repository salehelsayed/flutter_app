#!/bin/bash
# O10 iPhone 13 syslog capture: app, notification service extension and SpringBoard notification lines.
#   r48_o10_capture.sh start | stop | grep <regex> [n]
D=/Volumes/CrucialX9/flutter_app; REL=docker-ws/deploy-captures/o10-20261004; U=00008110-00184D622289801E
mkdir -p "$D/$REL"; F="$D/$REL/iphone13_syslog.txt"
case "$1" in
  start) pkill -f "idevicesyslog -u $U" 2>/dev/null; sleep 1
    nohup /bin/bash -c "/opt/homebrew/bin/idevicesyslog -u $U | grep --line-buffered -E 'Runner|mknoon|NotificationService|com.mknoon|SpringBoard.*(mknoon|Mknoon)' >> '$F'" >/dev/null 2>&1 &
    sleep 3; echo "capturing to $F"; pgrep -fl "idevicesyslog -u $U" ;;
  stop) pkill -f "idevicesyslog -u $U"; echo stopped ;;
  grep) grep -E "$2" "$F" | tail -n "${3:-40}" | cut -c1-400; echo "--- lines total: $(wc -l < "$F")" ;;
esac
