#!/bin/bash
# Build-129 translation test: read-only iPhone syslog capture of Mknoon flutter lines (TRANSLATION_CAPABILITY,
# GEMMA_PREVIEW, downloader) plus memory-kill lines. Tracks its own idevicesyslog PID.
#   host-run bash docker-ws/tr129_ios_syslog.sh <11|13> <out-file-in-repo> <max-secs>   (stops early when <out>.stop exists)
case "$1" in 11) U=00008030-001A6D2801BB802E;; 13) U=00008110-00184D622289801E;; *) echo "usage"; exit 2;; esac
REPO="$(cd "$(dirname "$0")/.." && pwd)"; O="$REPO/$2"; N="${3:-3600}"
BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
mkdir -p "$(dirname "$O")"
"$BIN" -u "$U" --no-colors 2>/dev/null > >(grep --line-buffered -E 'TRANSLATION_CAPABILITY|GEMMA_PREVIEW|Runner\[[0-9]+\].*(flutter: |[Tt]erminat|crash|[Dd]ownload|URLSession)|[Jj]etsam|nsurlsessiond.*mknoon|com\.mknoon\.app.*([Tt]erminat|jetsam|memory limit)' > "$O") &
P=$!; echo "capturing idevicesyslog pid=$P"
t=0; while [ "$t" -lt "$N" ] && [ ! -f "$O.stop" ] && kill -0 "$P" 2>/dev/null; do sleep 5; t=$((t+5)); done
kill "$P" 2>/dev/null; rm -f "$O.stop"; sleep 2
echo "done pid=$P lines=$(wc -l < "$O")"; ps -o pid= -p "$P" >/dev/null && echo "WARN pid $P still alive"
