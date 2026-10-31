#!/bin/bash
# Exit on DONE (regex in file), STALL (no mtime change under a dir for STALL_SECS, default 240) or TIMEOUT (max secs).
#   evid_watchdog.sh <watch-dir> <done-file> <done-regex> <max-secs>
D="$1"; F="$2"; RX="$3"; MAX="$4"; ST="${STALL_SECS:-240}"
t0=$(date +%s); last=""; lc=$t0
while :; do
  now=$(date +%s)
  if [ -f "$F" ] && grep -q -E "$RX" "$F" 2>/dev/null; then echo "DONE after $((now-t0))s"; tail -3 "$F"; exit 0; fi
  m=$(find "$D" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
  [ "$m" != "$last" ] && { last="$m"; lc=$now; }
  [ $((now-lc)) -ge "$ST" ] && { echo "STALL no change for $((now-lc))s"; find "$D" -type f -printf '%T@ %p\n' | sort -n | tail -2; exit 3; }
  [ $((now-t0)) -ge "$MAX" ] && { echo "TIMEOUT after $((now-t0))s"; exit 4; }
  sleep 15
done
