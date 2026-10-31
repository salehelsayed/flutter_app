#!/bin/bash
# DC-023 recheck: notification FLOW lines in the Pixel capture after a local time (MM-DD HH:MM:SS).
#   dc023_flow.sh <capture-file> <"10-28 18:40:00">
awk -v t="$2" 'substr($0,1,14) >= t' "$1" | grep -F '[FLOW]' | grep -E 'NOTIFICATION_(SHOWN|DEFERRED|SUPPRESS|TAPPED)|PUSH_BACKGROUND_NOTIFICATION_SHOWN|SUPPRESS|cachedScreenRelation|FOREGROUND_SUPPRESS' | cut -c1-420
