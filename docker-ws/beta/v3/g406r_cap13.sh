#!/bin/bash
# Plan 406 remaining checks: iPhone 13 syslog capture (unfiltered by process, filtered on the Mac).
#   start | stop | grep <regex> [n] | count <regex>
D=/Volumes/CrucialX9/flutter_app/artifacts/beta-20261011; mkdir -p "$D"
F="$D/iphone13_syslog.txt"; U=00008110-00184D622289801E
case "$1" in
  start)
    pkill -f "idevicesyslog -u $U" 2>/dev/null; sleep 1
    nohup /bin/bash -c "/opt/homebrew/bin/idevicesyslog -u $U | grep --line-buffered -E 'Runner|mknoon' >> '$F'" >/dev/null 2>&1 &
    sleep 3; pgrep -fl idevicesyslog | grep "$U"; ls -la "$F" ;;
  stop) pkill -f "idevicesyslog -u $U"; echo stopped ;;
  grep) grep -aE "$2" "$F" | tail -n "${3:-40}" | cut -c1-400 ;;
  count) grep -acE "$2" "$F" ;;
esac
