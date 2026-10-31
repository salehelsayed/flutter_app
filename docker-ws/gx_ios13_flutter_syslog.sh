#!/bin/bash
# GX-002 rerun: read-only iPhone 13 syslog capture of every Mknoon flutter line (Runner(Flutter)[pid] ... flutter:) plus Runner
# native notices. Tracks its own idevicesyslog PID; stops early when <out>.stop exists.
#   host-run bash docker-ws/gx_ios13_flutter_syslog.sh <out-file-in-repo> <max-secs>
REPO="$(cd "$(dirname "$0")/.." && pwd)"; O="$REPO/$1"; N="${2:-3600}"; U=00008110-00184D622289801E
BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
mkdir -p "$(dirname "$O")"
"$BIN" -u "$U" --no-colors 2>/dev/null > >(grep --line-buffered -E 'Runner(\(Flutter\))?\[[0-9]+\]' > "$O") &
P=$!; echo "capturing idevicesyslog pid=$P"
t=0; while [ "$t" -lt "$N" ] && [ ! -f "$O.stop" ] && kill -0 "$P" 2>/dev/null; do sleep 5; t=$((t+5)); done
kill "$P" 2>/dev/null; rm -f "$O.stop"; sleep 2
echo "done pid=$P lines=$(wc -l < "$O")"
