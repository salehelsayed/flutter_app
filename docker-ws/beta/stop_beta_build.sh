#!/bin/bash
# Stops ONLY the beta build started by build_beta_apps.sh (and its children).
# Never touches the shared Gradle daemon or other flutter commands.
kill_tree() {
  local p=$1 c
  for c in $(pgrep -P "$p"); do kill_tree "$c"; done
  kill "$p" 2>/dev/null && echo "killed $p $(ps -o command= -p "$p" 2>/dev/null | cut -c1-80)"
}
for root in $(pgrep -f "bash docker-ws/beta/build_beta_apps.sh"); do kill_tree "$root"; done
sleep 3
echo "--- remaining"
ps -axo pid,ppid,command | grep -E "build_beta_apps|beta-20260924" | grep -v grep | cut -c1-200
