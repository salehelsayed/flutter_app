#!/bin/bash
# Build-165 Gemma preview smoke: read-only iPhone 11 syslog capture of GEMMA_PREVIEW lines plus Mknoon/jetsam
# memory-kill lines. Tracks the idevicesyslog PID itself (like vc014_ios13_syslog.sh) so stopping leaves no orphan.
# Heartbeat (count of all device lines) every 60 s to <out>.hb so a dead stream is visible.
#   host-run bash docker-ws/gemma165_ios11_syslog.sh <out-file-in-repo> <max-secs>   (stops early when <out>.stop exists)
REPO="$(cd "$(dirname "$0")/.." && pwd)"; O="$REPO/$1"; N="${2:-3600}"; U=00008030-001A6D2801BB802E
BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
mkdir -p "$(dirname "$O")"; C="$O.count"; : > "$C"
"$BIN" -u "$U" --no-colors 2>/dev/null > >(awk -v c="$C" '{n++; if (n%200==0){print n > c; close(c)}} 1' \
  | grep --line-buffered -E 'GEMMA_PREVIEW|[Jj]etsam|memorystatus|EXC_RESOURCE|per-process-limit|highwater|ReportCrash.*(Runner|mknoon)|runningboardd.*(com\.mknoon\.app|Runner).*([Tt]erminat|exit|kill|jetsam|memory)|Runner\[[0-9]+\].*(flutter: |[Tt]erminat|crash|LiteRt|litert|Gemma|gemma)|com\.mknoon\.app.*([Tt]erminat|jetsam|memory limit)' > "$O") &
P=$!; echo "capturing idevicesyslog pid=$P"
t=0; while [ "$t" -lt "$N" ] && [ ! -f "$O.stop" ] && kill -0 "$P" 2>/dev/null; do
  sleep 5; t=$((t+5)); [ $((t%60)) -eq 0 ] && echo "$(date -u +%FT%TZ) all_lines=$(cat "$C" 2>/dev/null)" >> "$O.hb"
done
kill "$P" 2>/dev/null; rm -f "$O.stop"; sleep 2
echo "done pid=$P lines=$(wc -l < "$O")"; ps -o pid= -p "$P" >/dev/null && echo "WARN pid $P still alive"
