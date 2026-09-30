#!/bin/bash
# Stop run_b8.sh and everything it started (adb install, maestro flows, waits).
kill_tree() { local p=$1 c; for c in $(pgrep -P "$p"); do kill_tree "$c"; done; kill "$p" 2>/dev/null; }
for r in $(pgrep -f "run_b8.sh"); do kill_tree "$r"; done
sleep 2
echo "runner alive: $(pgrep -f run_b8.sh >/dev/null && echo yes || echo no)"
echo "stuck installs left: $(pgrep -f 'adb -s emulator-5556 install' | wc -l | tr -d ' ')"
. "$(dirname "$0")/beta_env.sh"
echo "emulator: $(timeout 20 $ADB shell 'echo up; getprop sys.boot_completed; uptime' 2>&1 | tr '\n' ' ')"
echo "installed: $(timeout 30 $ADB shell dumpsys package $PKG 2>&1 | grep -m1 versionName | tr -d ' ')"
