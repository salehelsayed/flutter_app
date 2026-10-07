#!/bin/bash
# Delete leftovers our test runs put in TMPDIR: multi-party case dirs and journey state backups older than 1 day,
# plus sweep dirs. Dry run unless --delete. Then print free space.
T=${TMPDIR:-/tmp}; total=0
for d in $(find "$T" -maxdepth 1 \( -name 'group_multi_party_*' -o -name 'mknoon-journey-*-state-*' -o -name 'gmp_*' \) -mtime +1 2>/dev/null) $(find "$T" -maxdepth 1 -name 'group_multi_party_*' -mmin +120 2>/dev/null); do
  [ -e "$d" ] || continue; k=$(du -sk "$d" | cut -f1); total=$((total+k)); [ "$1" = "--delete" ] && rm -rf "$d"
done
echo "$( [ "$1" = "--delete" ] && echo deleted || echo would delete ) $((total/1024)) MB from TMPDIR"
df -h /Volumes/CrucialX9 / | awk 'NR>1{print $NF": "$4" free ("$5" used)"}'
