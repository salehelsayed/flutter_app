#!/bin/bash
kill_tree() { local p=$1 c; for c in $(pgrep -P "$p"); do kill_tree "$c"; done; kill "$p" 2>/dev/null; }
for r in $(pgrep -f "run_fixed3.sh"); do kill_tree "$r"; done
sleep 1; echo "runner alive: $(pgrep -f run_fixed3.sh >/dev/null && echo yes || echo no)"
