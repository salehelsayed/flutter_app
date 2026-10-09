#!/bin/bash
# Read-only Mac state before the round-3 Android validation (2026-10-08).
. "$(dirname "$0")/../beta_env.sh"
echo "mac load: $(sysctl -n vm.loadavg)  swap: $(sysctl -n vm.swapusage | cut -c1-80)"
echo "disk: $(df -h /Volumes/CrucialX9 | tail -1)"
echo "avds: $("$ANDROID_HOME/emulator/emulator" -list-avds 2>/dev/null | tr '\n' ' ')"
echo "qemu: $(ps -axo pid,pri,command | grep qemu-system | grep -v grep | cut -c1-160)"
echo "adb: $("$ANDROID_HOME/platform-tools/adb" devices | tr '\n' ' ')"
echo "sim: $(xcrun simctl list devices | grep -E "$UDID|Booted" | tr -s ' ' | head -5)"
for d in /Volumes/CrucialX9/flutter_app-beta0924 /Volumes/CrucialX9/flutter_app-r2val; do
  [ -d "$d" ] && echo "copy $d exists: $(cat "$d/.proof-checkout-provenance.txt" 2>/dev/null | tr '\n' ' ' | cut -c1-200)" || echo "copy $d missing"
done
ls "$SRC/docker-ws/prepare_proof_checkout_5556.sh" 2>&1
echo "flutter 3.47.2: $(ls -d $HOME/development/flutter-3.47.2 2>&1)"
echo "busy procs:"; ps -axo pid,etime,command | grep -E 'maestro|appium|flutter_tools|xcodebuild|gradle|run_sims|mknoon_checks|WebDriverAgent' | grep -v grep | cut -c1-170 | head -20
echo "defines: $(cat "$SRC/tool/build/voice_call_release_defines.json" 2>&1 | tr -d '\n' | cut -c1-300)"
