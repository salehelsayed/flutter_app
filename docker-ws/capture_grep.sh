#!/bin/bash
# Grep the live phone captures ON THE MAC (the container's view of the shared
# checkout lags behind by minutes). Usage: docker-ws/capture_grep.sh <CAPTURE_DIR> [<pattern>] [<max lines>]
DIR="${1:?capture dir}"
PATTERN="${2:-CALL_STATE_TRANSITION|CALL_RINGBACK_RESULT|ringback=|ringback stage|MknoonCallRingback|MKNOON_CALLKIT_DIAG|CALL_CONTROL_SIGNAL_SEND|CALL_AUDIO_START_RESULT}"
MAX="${3:-40}"
WIDTH="${4:-230}"
echo "now: $(date -u +%H:%M:%SZ)"
for f in "$DIR"/*.txt; do
  echo "=== $(basename "$f") ($(wc -l < "$f" | tr -d ' ') lines, last: $(tail -1 "$f" | cut -c1-24))"
  grep -E "$PATTERN" "$f" | tail -n "$MAX" | cut -c1-"$WIDTH"
done
