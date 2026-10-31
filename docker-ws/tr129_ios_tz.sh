#!/bin/bash
# Read-only: iPhone time zone and clock.   host-run bash docker-ws/tr129_ios_tz.sh <11|13>
case "$1" in 11) U=00008030-001A6D2801BB802E;; 13) U=00008110-00184D622289801E;; *) echo usage; exit 2;; esac
B="$(command -v ideviceinfo || echo /opt/homebrew/bin/ideviceinfo)"
timeout 30 "$B" -u "$U" -k TimeZone; timeout 30 "$B" -u "$U" -k TimeIntervalSince1970
