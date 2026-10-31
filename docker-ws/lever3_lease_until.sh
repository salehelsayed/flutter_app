#!/bin/bash
# Hold the native lease (run under with_native_lease.py) until <marker> exists or <max-min> passes.
#   host-run docker-ws/with_native_lease.py <log> -- bash /Volumes/CrucialX9/flutter_app/docker-ws/lever3_lease_until.sh <marker> <max-min>
M="${1:?marker}"; MAX="${2:-90}"; end=$(( $(date +%s) + MAX*60 ))
echo "holding until $M (max ${MAX}m) $(date -u +%FT%TZ)"
while [ ! -e "$M" ] && [ "$(date +%s)" -lt "$end" ]; do sleep 10; done
echo "released $( [ -e "$M" ] && echo marker || echo timeout) $(date -u +%FT%TZ)"
