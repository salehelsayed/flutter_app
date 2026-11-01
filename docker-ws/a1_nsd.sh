#!/bin/bash
# a1_nsd.sh <serial> <out>: append `dumpsys servicediscovery` with IPv4/IPv6 addresses removed, stamped with UTC time.
# Note: the dumpsys timestamps are emulator local time (CET, UTC+1).
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
{ echo "##### sample $(date -u +%FT%TZ) $1"
  timeout 20 adb -s "$1" shell dumpsys servicediscovery 2>/dev/null \
  | sed -E 's/[0-9]{1,3}(\.[0-9]{1,3}){3}/<ip>/g; s/\[[^]]*:[^]]*\]/[<ip6>]/g; s/([0-9a-f]{1,4}:){4,}[0-9a-f]{1,4}/<ip6>/g; s/[0-9a-f]{0,4}::[0-9a-f:]*/<ip6>/g; s/(peerId=)[^,} ]+/\1<redacted>/g; s/12D3Koo[1-9A-HJ-NP-Za-km-z]+/<peer>/g'; } >> "$2"
