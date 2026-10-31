#!/bin/bash
# Read-only: browse _mknoon._tcp on the Mac's LAN for N seconds (default 6), print instance count and names only.
dns-sd -B _mknoon._tcp local. > /tmp/sc_mdns_$$.txt 2>&1 &
P=$!; sleep "${1:-6}"; kill "$P" 2>/dev/null
grep -E " Add " /tmp/sc_mdns_$$.txt | awk '{print $3, $4, $NF}' | sort -u; echo "adds=$(grep -c ' Add ' /tmp/sc_mdns_$$.txt)"; rm -f /tmp/sc_mdns_$$.txt
