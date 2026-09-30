#!/bin/bash
# Read-only one-liner: what this Mac resolves mknoun.xyz to right now (system cache,
# router answer with remaining TTL), whether the old address still takes connections,
# and the Mac load.
. "$(dirname "$0")/beta_env.sh"
sys=$(dscacheutil -q host -a name mknoun.xyz | awk '/ip_address/ {print $2}' | tr '\n' ' ')
rtr=$(dig +noall +answer A mknoun.xyz | awk '{printf "%s ttl=%s", $5, $2}')
old=closed; nc -z -G 5 -w 5 13.60.250.19 4001 >/dev/null 2>&1 && old=open
echo "$(date '+%H:%M:%S') system=${sys}router=${rtr} old_13.60.250.19:4001=$old load=$(sysctl -n vm.loadavg | awk '{print $2}')"
