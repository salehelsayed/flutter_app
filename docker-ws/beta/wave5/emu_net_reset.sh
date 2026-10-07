#!/bin/bash
# Toggle airplane mode on the given emulators to reset their network, then recheck DNS/TCP to the relay.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
for s in "$@"; do
  adb -s $s shell cmd connectivity airplane-mode enable; sleep 3; adb -s $s shell cmd connectivity airplane-mode disable
done
sleep 12
for s in "$@"; do
  echo "$s | $(adb -s $s shell 'ping -c1 -W3 mknoun.xyz 2>&1 | head -1' | tr -d '\r' | cut -c1-50) | $(adb -s $s shell 'toybox nc -z -w 4 mknoun.xyz 4001 && echo open4001 || echo closed4001' | tr -d '\r' | tail -1)"
done
