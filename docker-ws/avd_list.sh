#!/bin/bash
# Read-only: list AVD names with their dir, system image and userdata size.
E="$HOME/Library/Android/sdk/emulator/emulator"
for a in $("$E" -list-avds); do
  d=$(sed -n 's/^path=//p' "$HOME/.android/avd/$a.ini" 2>/dev/null); [ -n "$d" ] || d="$HOME/.android/avd/$a.avd"
  img=$(sed -n 's/^image.sysdir.1=//p' "$d/config.ini" 2>/dev/null)
  sz=$(du -sk "$d" 2>/dev/null | cut -f1)
  echo "$a dir=$d img=$img size_mb=$((sz/1024))"
done
