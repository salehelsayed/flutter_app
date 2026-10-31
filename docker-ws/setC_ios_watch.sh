#!/bin/bash
# Poll the iPhone 13 Mknoon labels every ~10 s until <HHMMSS UTC>, printing a timestamped line only when the label set changes (text only).
#   setC_ios_watch.sh <until-HHMMSS>
cd "$(dirname "$0")/.." || exit 2
prev=""
while [ "$(date -u +%H%M%S)" -lt "$1" ]; do
  cur=$(bash docker-ws/setC_ios_labels.sh 2>&1 | grep -vE 'RG003|^label="mknoon"' | paste -sd'|')
  [ "$cur" != "$prev" ] && echo "$(date -u +%T) $cur" && prev="$cur"
  sleep 5
done
echo "$(date -u +%T) watch end"
