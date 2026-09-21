#!/bin/bash
# Show the real descendant process tree of the running sims gate, so a phase
# reading cannot be faked by an orphaned build child left over from a reaped
# run. Read-only.
set -uo pipefail

descendants() {
  local p="$1" c
  for c in $(pgrep -P "$p" 2>/dev/null); do
    echo "$c"
    descendants "$c"
  done
}

root="$(pgrep -f 'tool/sims/sims.dart' 2>/dev/null | head -1)"
echo "sims.dart root pid: ${root:-<none>}"
if [ -n "$root" ]; then
  kids="$(descendants "$root" | tr '\n' ' ')"
  echo "descendants: ${kids:-<none>}"
  if [ -n "${kids// /}" ]; then
    ps -o pid,ppid,etime,time,%cpu,command -p $(echo $kids | tr ' ' ',') 2>/dev/null | cut -c1-200
  fi
fi
echo "--- ALL build-ish processes on this Mac (orphans included)"
ps -axo pid,ppid,etime,time,%cpu,command 2>/dev/null \
  | grep -E 'gradle|kotlin-daemon|xcodebuild|frontend_server|flutter_tools|dart .*sims|[a]db -s' \
  | grep -v grep | cut -c1-180
echo "--- newest files under build/ (last 10 min)"
find build -type f -mmin -10 2>/dev/null | head -12
echo "--- newest files under build/ overall"
ls -lat build 2>/dev/null | head -6
