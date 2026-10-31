#!/bin/bash
# Live iPhone 13 syslog capture of Mknoon (Runner + NotificationService extension) lines, into a repo file. Detached.
#   host-run bash docker-ws/ios11_flow_capture.sh start <out-file-in-repo>
#   host-run bash docker-ws/ios11_flow_capture.sh stop <pid>     (pid printed by start; checked before kill)
U=00008110-00184D622289801E
IDS="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
R=/Volumes/CrucialX9/flutter_app
case "$1" in
  start)
    OUT="$R/$2"; mkdir -p "$(dirname "$OUT")"
    nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' bash -c "\"$IDS\" -u $U --no-colors | grep --line-buffered -a -E ' (Runner|NotificationService)(\\(|\\[)'" > "$OUT" 2>&1 < /dev/null &
    echo "capture pid $!" ;;
  stop)
    P="$2"; [[ "$P" =~ ^[0-9]+$ ]] || { echo refused; exit 2; }
    case "$(ps -o args= -p "$P")" in *idevicesyslog*"$U"*) pkill -TERM -g "$(ps -o pgid= -p "$P" | tr -d ' ')" && echo "TERM group of $P";; *) echo "refused: $(ps -o args= -p "$P" | cut -c1-60)";; esac ;;
esac
