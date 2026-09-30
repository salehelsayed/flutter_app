#!/bin/bash
# Read-only: R2-2 build and load-test progress.
. "$(dirname "$0")/beta_env.sh"
echo "now $(date '+%H:%M:%S') load $(sysctl -n vm.loadavg)"
echo "--- build"; tail -6 "$BETA/build-r2-2/result.txt" 2>/dev/null
pgrep -f build_r22.sh >/dev/null && echo "(build running)"
C=$(cat "$BETA/r2-2/current.txt" 2>/dev/null)
[ -n "$C" ] && { echo "--- stress $C"; grep -v ' sample ' "$C/stress.log" | tail -12; grep ' sample ' "$C/stress.log" | tail -2; }
pgrep -f r22_stress.sh >/dev/null && echo "#STRESS_ALIVE" || echo "#STRESS_DEAD"
[ -n "$C" ] && [ -f "$C/summary.txt" ] && { echo "--- summary"; cat "$C/summary.txt"; }
