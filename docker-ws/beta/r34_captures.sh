#!/bin/bash
# iPhone 11 + 13 syslog captures (Runner process) for the R2 open-issues validation. Never touches Android devices.
#   r34_captures.sh start            new capture dir, one idevicesyslog per iPhone (prints CAPTURE_DIR)
#   r34_captures.sh restart          restart both captures into the same dir (needed after a devicectl install/launch)
#   r34_captures.sh status           file sizes, [FLOW] counts, running captures
#   r34_captures.sh grep <regex> [n] last n matching lines per iPhone (default 40)
#   r34_captures.sh stop             stop both captures
set -u
B="$(cd "$(dirname "$0")" && pwd)"; D="$(cd "$B/.." && pwd)"
CUR="$B/r34_capture_dir.txt"
U11=00008030-001A6D2801BB802E; U13=00008110-00184D622289801E
stop_one() {  # by exact PID from the pid file, only if that PID is still idevicesyslog for this phone (no pattern kills)
  local f="$B/r34_capture_$1.pid" p
  [ -f "$f" ] || return 0
  p=$(cat "$f")
  case "$(ps -o args= -p "$p" 2>/dev/null)" in *"idevicesyslog -u $1"*) kill "$p" && echo "stopped $p";; esac
  rm -f "$f"
}
start_one() {  # unfiltered capture straight into the file, so $! is idevicesyslog itself; the grep command filters on read
  stop_one "$1"; sleep 1
  nohup /opt/homebrew/bin/idevicesyslog -u "$1" > "$D/$2" 2>/dev/null &
  echo $! > "$B/r34_capture_$1.pid"
}
case "${1:-status}" in
  start)
    REL="deploy-captures/r2o-$(date +%y%m%d%H%M%S)"; mkdir -p "$D/$REL"; echo "$D/$REL" > "$CUR"
    start_one $U11 "$REL/iphone11_syslog.txt"; start_one $U13 "$REL/iphone13_syslog.txt"
    sleep 3; echo "CAPTURE_DIR=$D/$REL"; pgrep -fl idevicesyslog ;;
  restart)
    DIR=$(cat "$CUR"); REL=${DIR#$D/}
    n=$(date +%H%M%S)
    start_one $U11 "$REL/iphone11_syslog_$n.txt"; start_one $U13 "$REL/iphone13_syslog_$n.txt"
    sleep 3; echo "restarted into $DIR (suffix $n)"; pgrep -fl idevicesyslog ;;
  status)
    DIR=$(cat "$CUR"); for f in "$DIR"/*.txt; do echo "$(basename "$f") $(stat -f %z "$f") bytes, FLOW $(grep -c '\[FLOW\]' "$f")"; done
    pgrep -fl idevicesyslog ;;
  grep)
    DIR=$(cat "$CUR")
    for p in iphone11 iphone13; do echo "=== $p"; cat "$DIR"/${p}_syslog*.txt 2>/dev/null | grep -E 'Runner|mknoon' | grep -E "$2" | tail -"${3:-40}" | cut -c1-320; done ;;
  stop)
    stop_one $U11; stop_one $U13; sleep 1; pgrep -fl idevicesyslog || echo "no captures running" ;;
esac
