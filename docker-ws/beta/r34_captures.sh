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
start_one() {  # the --process filter stays bound to the old Runner process after an app restart: filter on the Mac
  if true; then
    pkill -f "idevicesyslog -u $1" 2>/dev/null; sleep 1
    nohup /bin/bash -c "/opt/homebrew/bin/idevicesyslog -u $1 | grep --line-buffered -E 'Runner|mknoon' > '$D/$2'" >/dev/null 2>&1 &
  else
    nohup "$D/capture_iphone_syslog_any.sh" "$1" "$2" >/dev/null 2>&1 &
  fi
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
    for p in iphone11 iphone13; do echo "=== $p"; cat "$DIR"/${p}_syslog*.txt 2>/dev/null | grep -E "$2" | tail -"${3:-40}" | cut -c1-320; done ;;
  stop)
    pkill -f "idevicesyslog -u $U11"; pkill -f "idevicesyslog -u $U13"; sleep 1; pgrep -fl idevicesyslog || echo "no captures running" ;;
esac
