#!/bin/bash
# Read-only: AVDs, running emulators and the Mac's load.
. "$(dirname "$0")/beta_env.sh"
"$ANDROID_HOME/emulator/emulator" -list-avds 2>/dev/null
echo "--- adb"; $ADB devices -l | cut -c1-120
for s in $($ADB devices | awk '/^emulator-/{print $1}'); do echo "$s $($ADB -s $s emu avd name 2>/dev/null | head -1 | tr -d '\r')"; done
echo "--- load: $(sysctl -n vm.loadavg)  cores $(sysctl -n hw.ncpu)  mem $(($(sysctl -n hw.memsize)/1073741824)) GB"
