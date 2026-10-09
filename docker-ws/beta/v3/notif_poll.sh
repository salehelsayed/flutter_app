#!/bin/bash
# notif_poll.sh <out file> <seconds>: record every change of the Mknoon notification list (title/text) with a UTC
# timestamp, polling as fast as adb allows (~0.3-0.5 s per read).
. "$(dirname "$0")/lib.sh"
F=$1; END=$(( $(date +%s) + ${2:-30} )); last=""
: > "$F"
while [ "$(date +%s)" -lt "$END" ]; do
  cur=$(p_notifs | tr '\n' '#')
  if [ "$cur" != "$last" ]; then echo "$(date -u '+%H:%M:%S.%3N') $cur" >> "$F"; last="$cur"; fi
done
