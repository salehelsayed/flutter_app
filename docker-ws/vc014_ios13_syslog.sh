#!/bin/bash
# VC-014: read-only call/push line capture from the iPhone 13 syslog. Unlike calls28_ios13_syslog.sh it tracks the
# idevicesyslog PID itself (filter via process substitution), so stopping it leaves no orphan reader.
# Also writes a heartbeat line (count of all device lines) every 60 s to <out>.hb so a dead stream is visible.
#   host-run bash docker-ws/vc014_ios13_syslog.sh <out-file-in-repo> <max-secs>   (stops early when <out>.stop exists)
REPO="$(cd "$(dirname "$0")/.." && pwd)"; O="$REPO/$1"; N="${2:-3600}"; U=00008110-00184D622289801E
BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
mkdir -p "$(dirname "$O")"; C="$O.count"; : > "$C"
"$BIN" -u "$U" --no-colors 2>/dev/null > >(tee >(wc -l > "$C.final") | awk -v c="$C" '{n++; if (n%200==0){print n > c; close(c)}} 1' \
  | grep --line-buffered -E '"event":"CALL_|MKNOON_CALL|CXProvider|reportNewIncoming|didReceiveIncomingPush|PushKit|pushkit|apsd.*(voip|VoIP|com.mknoon)|callservicesd.*(com.mknoon|mknoon)|ApplePushService|Received add incoming call|apsd\[[0-9]+\] <Notice>' > "$O") &
P=$!; echo "capturing idevicesyslog pid=$P"
t=0; while [ "$t" -lt "$N" ] && [ ! -f "$O.stop" ] && kill -0 "$P" 2>/dev/null; do
  sleep 5; t=$((t+5)); [ $((t%60)) -eq 0 ] && echo "$(date -u +%FT%TZ) all_lines=$(cat "$C" 2>/dev/null)" >> "$O.hb"
done
kill "$P" 2>/dev/null; rm -f "$O.stop"; sleep 2
echo "done pid=$P lines=$(wc -l < "$O")"; ps -o pid= -p "$P" >/dev/null && echo "WARN pid $P still alive"
