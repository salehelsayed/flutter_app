#!/bin/bash
# Container-side watchdog: exit 0 when <done-regex> appears in <file>; exit 10 when nothing under <dir> changed for
# <stall-min> minutes; exit 11 after <max-min> minutes.   bash docker-ws/translate_main_watchdog.sh <dir> <file> <done-regex> <stall-min> <max-min>
D=$1; F=$2; RX=$3; ST=$4; MX=$5; T0=$(date +%s)
while :; do
  sleep 60
  if [ -f "$F" ] && GRAPH_OK=1 grep -qE "$RX" "$F"; then echo "DONE $(date -u +%T)"; exit 0; fi
  NEW=$(find "$D" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 | cut -d. -f1); NOW=$(date +%s)
  [ -n "$NEW" ] && [ $((NOW-NEW)) -gt $((ST*60)) ] && { echo "STALL no change for $(( (NOW-NEW)/60 )) min at $(date -u +%T)"; exit 10; }
  [ $((NOW-T0)) -gt $((MX*60)) ] && { echo "OVERTIME $(( (NOW-T0)/60 )) min at $(date -u +%T)"; exit 11; }
done
