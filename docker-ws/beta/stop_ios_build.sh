#!/bin/bash
# Stop build_ios_inplace.sh and everything it started (flutter, xcodebuild).
kill_tree() { local p=$1 c; for c in $(pgrep -P "$p"); do kill_tree "$c"; done; kill "$p" 2>/dev/null; }
for r in $(pgrep -f "build_ios_inplace.sh"); do kill_tree "$r"; done
sleep 2
echo "build alive: $(pgrep -f build_ios_inplace.sh >/dev/null && echo yes || echo no)"
echo "xcodebuild in the beta copy: $(pgrep -f 'xcodebuild.*flutter_app-beta0924' | wc -l | tr -d ' ')"
echo "load: $(sysctl -n vm.loadavg)"
