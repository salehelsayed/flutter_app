#!/bin/bash
# Read-only disk report: df for / and the external drive, then sizes of likely-cleanable dirs (KB).
df -h / /Volumes/CrucialX9 /System/Volumes/Data 2>/dev/null
echo "=== candidates (KB) ==="
cands=(
  "$HOME/Library/Developer/Xcode/DerivedData"
  "$HOME/Library/Developer/CoreSimulator/Devices"
  "$HOME/Library/Developer/Xcode/Archives"
  "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  "$HOME/Library/Caches"
  "$HOME/.gradle/caches"
  "$HOME/.pub-cache"
  "$HOME/Library/Developer/CoreSimulator/Caches"
)
for d in "${cands[@]}"; do [ -e "$d" ] && du -sk "$d" 2>/dev/null; done
for base in /Volumes/CrucialX9/flutter_app/build /Volumes/CrucialX9/flutter_app/.codex-test-logs; do
  for d in "$base"/*; do [ -d "$d" ] && du -sk "$d" 2>/dev/null; done
done
for d in /Volumes/CrucialX9/*; do [ -d "$d" ] && du -sk "$d" 2>/dev/null; done
