#!/bin/bash
# Read-only: list TCP/UDP listening ports of one PID (lsof), addresses masked to the port.
P="$1"; [[ "$P" =~ ^[0-9]+$ ]] || { echo refused; exit 2; }
lsof -nP -a -p "$P" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{n=split($9,a,":"); print "tcp", a[n]}'
lsof -nP -a -p "$P" -iUDP 2>/dev/null | awk 'NR>1{n=split($9,a,":"); print "udp", a[n]}' | sort -u | head -5
exit 0
