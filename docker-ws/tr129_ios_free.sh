#!/bin/bash
# Build-129 translation test: print iPhone free/total storage bytes (read-only, via ideviceinfo disk domain).
#   host-run bash docker-ws/tr129_ios_free.sh <11|13>
case "$1" in 11) U=00008030-001A6D2801BB802E;; 13) U=00008110-00184D622289801E;; *) echo "usage"; exit 2;; esac
BIN="$(command -v ideviceinfo || echo /opt/homebrew/bin/ideviceinfo)"
timeout 60 "$BIN" -u "$U" -q com.apple.disk_usage 2>&1 | grep -E 'TotalDataAvailable|TotalDataCapacity|AmountDataAvailable'
