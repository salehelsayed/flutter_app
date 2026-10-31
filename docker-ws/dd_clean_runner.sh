#!/bin/bash
# Delete stale Runner-* DerivedData folders on CrucialX9. Keeps the symlink, WebDriverAgent-*, ModuleCache, SDKStatCaches.
# Refuses if any Runner xcodebuild/flutter build is live.
set -u
DD=/Volumes/CrucialX9/mac-development/xcode-derived-data
if ps -axo command | grep -E 'xcodebuild' | grep -v grep | grep -qv 'WebDriverAgent'; then echo "REFUSE: non-WDA xcodebuild running"; exit 3; fi
df -g /Volumes/CrucialX9 | tail -1
for d in "$DD"/Runner-*; do
  [ -d "$d" ] || continue
  case "$d" in "$DD"/Runner-*) rm -rf "$d" && echo "removed $(basename "$d")";; esac
done
df -g /Volumes/CrucialX9 | tail -1
