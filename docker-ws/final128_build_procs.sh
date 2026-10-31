#!/bin/bash
# List (and with "kill", stop) my two final128 phone builds: each root matched by exact script + tree, plus its
# descendants by parent pid. Never signals a process group (the group is shared with the Claude session).
set -u
desc() { local c; for c in $(pgrep -P "$1"); do echo "$c"; desc "$c"; done; }
roots=$(pgrep -f 'docker-ws/(build_debug_apk_hetzner_wt|ios_device_build_internal)\.sh wt-final128')
for r in $roots; do
  # include the native-lease wrapper parent if it is the direct parent
  pp=$(ps -o ppid= -p "$r" | tr -d ' '); case "$(ps -o command= -p "$pp")" in *with_native_lease.py*) r2=$pp;; *) r2=$r;; esac
  list="$r2 $(desc "$r2")"
  for p in $list; do echo "$p $(ps -o etime=,command= -p $p | cut -c1-120)"; done
  [ "${1:-}" = kill ] && { for p in $(echo $list | tr ' ' '\n' | sort -rn); do kill -TERM "$p" 2>/dev/null; done; echo "TERM sent to root $r2 and descendants"; }
done
