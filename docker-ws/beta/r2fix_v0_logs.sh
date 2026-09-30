#!/bin/bash
# Read-only: the Pixel's in-memory logcat for the old dissolved group 6b6f74f7 since the fixed app started.
. "$(dirname "$0")/beta_env.sh"
echo "app pid: $($ADB shell pidof $PKG | tr -d '\r')  version: $($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r')"
$ADB logcat -d -v threadtime 2>/dev/null > /tmp/r2fix_v0_dump.txt
echo "dump lines: $(wc -l < /tmp/r2fix_v0_dump.txt)  first: $(head -2 /tmp/r2fix_v0_dump.txt | tail -1 | cut -c1-18)"
grep -E 'SIGNED_AUDIT_REJECTED|GROUP_RECONCILE_DISSOLVES_(CONVERGED|DONE|APPLIED|ERROR)|GROUPS_DB_DISSOLVE|GROUP_[A-Z_]*DISSOLV[A-Z_]*' /tmp/r2fix_v0_dump.txt \
  | sed -E 's/^([0-9-]+ [0-9:.]{12}).*"event":"([A-Z_]+)","details":(.{0,190}).*/\1 \2 \3/' | tail -25
