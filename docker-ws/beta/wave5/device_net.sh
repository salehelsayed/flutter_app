#!/bin/bash
# Read-only: DNS + TCP 443/4001 reachability of the relay from each Android device.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
for s in 21071FDF600CSC emulator-5554 emulator-5556 emulator-5558; do
  dns=$(adb -s $s shell "ping -c1 -W3 mknoun.xyz 2>&1 | head -1" | tr -d '\r' | cut -c1-60)
  t=$(adb -s $s shell "toybox nc -z -w 4 mknoun.xyz 4001 && echo open4001 || echo closed4001" 2>&1 | tr -d '\r' | tail -1)
  w=$(adb -s $s shell "settings get global airplane_mode_on; dumpsys connectivity | grep -m1 -oE 'NetworkAgentInfo\{[^ ]+ network\{[0-9]+\}[^}]*\} *.*VALIDATED' | head -c 60" 2>/dev/null | tr -d '\r' | tr '\n' ' ')
  echo "$s | $dns | $t | airplane/validated: $w"
done
