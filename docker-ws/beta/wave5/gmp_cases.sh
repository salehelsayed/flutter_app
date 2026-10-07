#!/bin/bash
# Read-only: multi-party case dirs created in the last N minutes, oldest first, with pass/fail markers.
for d in $(ls -dtr "${TMPDIR:-/tmp}"/group_multi_party_* 2>/dev/null); do
  m=$(( ( $(date +%s) - $(stat -f %B "$d") ) / 60 )); [ $m -gt "${1:-40}" ] && continue
  s=$(grep -alE "end of failure|Some tests failed" "$d"/*.log 2>/dev/null | wc -l | tr -d " ")
  p=$(grep -alE "All tests passed|tests passed" "$d"/*.log 2>/dev/null | wc -l | tr -d " ")
  echo "$(stat -f %SB -t %H:%M "$d") $(basename "$d" | sed "s/group_multi_party_//; s/_[A-Za-z0-9]*$//") fail_logs=$s pass_logs=$p"
done
