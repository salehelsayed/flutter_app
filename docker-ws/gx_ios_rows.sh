#!/bin/bash
# GX-002 self-leave: structural row check on the iPhone chat screen. Prints only yes/no counts for the M1/M2 texts
# stored in <evidence-dir>/.m1_text and .m2_text; never prints the texts.   bash docker-ws/gx_ios_rows.sh <evidence-dir>
D="$1"; S=$(AP_BASE=${AP_BASE:-http://192.168.65.254:4725} timeout 90 python3 docker-ws/beta/ap.py 13 src 'StaticText')
m1=$(printf '%s' "$S" | grep -cF "$(cat "$D/.m1_text")"); m2=$(printf '%s' "$S" | grep -cF "$(cat "$D/.m2_text")")
chat=$(printf '%s' "$S" | grep -c 'JB-GX002-1030')
echo "$(date -u +%FT%TZ) iPhone screen: group-title=$chat M1_rows=$m1 M2_rows=$m2"
