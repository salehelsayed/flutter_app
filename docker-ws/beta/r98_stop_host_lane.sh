#!/bin/bash
# Stop this session's detached host-all lane (r92) with its process tree.
kill_tree() { for c in $(pgrep -P "$1"); do kill_tree "$c"; done; kill "$1" 2>/dev/null; }
for p in $(pgrep -f "run_host_test_gates.sh host-all --batch-flutter"); do
  case "$(ps -o command= -p "$p")" in *wave3-next*|*run_host_test_gates*) echo "stopping $p"; kill_tree "$p";; esac
done
for p in $(pgrep -f "r92_wt_host_all.sh"); do kill_tree "$p"; done
sleep 2; pgrep -fl "run_host_test_gates.sh host-all" || echo "no host lane left"
