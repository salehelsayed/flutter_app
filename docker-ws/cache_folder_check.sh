#!/bin/bash
# Read-only: disk free, which AVDs live in the two plan407 cache folders, and open handles on them.
F1="$HOME/Library/Caches/mknoon-plan407-headless-avds-20261021"
F2="$HOME/Library/Caches/mknoon-plan407-native-diag-r60a9vdh"
echo "=== df ==="; df -g /Volumes/CrucialX9 "$HOME" 2>/dev/null
echo "=== folder sizes / real paths ==="
for f in "$F1" "$F2"; do echo "$f -> $(cd "$f" 2>/dev/null && pwd -P) $(du -sg "$f" 2>/dev/null | cut -f1)G"; ls "$f" 2>/dev/null | head -20; done
echo "=== AVD ini paths ==="
for i in "$HOME"/.android/avd/*.ini; do echo "$(basename "$i") $(sed -n 's/^path=//p' "$i")"; done
echo "=== symlinks into folders from avd/sdk/gradle ==="
find "$HOME/.android" "$HOME/Library/Android" -maxdepth 3 -type l -exec sh -c 'for l; do t=$(readlink "$l"); case "$t" in *plan407*) echo "$l -> $t";; esac; done' _ {} + 2>/dev/null
echo "=== open handles ==="
lsof -n 2>/dev/null | grep -E 'mknoon-plan407-(headless-avds-20261021|native-diag-r60a9vdh)' | awk '{print $1,$2,$3}' | sort -u | head
echo "=== emulator processes ==="
ps -axo pid,etime,command | grep -E 'qemu-system|emulator ' | grep -v grep | cut -c1-200
