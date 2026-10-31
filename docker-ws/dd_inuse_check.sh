#!/bin/bash
# Read-only: is the CrucialX9 Xcode DerivedData in use? Lists build processes and open handles, plus per-project sizes.
DD=/Volumes/CrucialX9/mac-development/xcode-derived-data
echo "=== build processes ==="
ps -axo pid,etime,user,command | grep -E 'xcodebuild|swift-frontend|XCBBuildService|clang |ld64|flutter_tools.snapshot (build|run|test)' | grep -v grep | cut -c1-180
echo "=== open handles in DD ==="
lsof -n +D "$DD" 2>/dev/null | awk 'NR>1{print $1,$2}' | sort -u | head -20
echo "=== DD entries (GB, newest mtime) ==="
for d in "$DD"/*; do echo "$(du -sg "$d" 2>/dev/null | cut -f1)G $(stat -f %Sm -t %m-%dT%H:%M "$d") $(basename "$d")"; done | sort -rn | head -30
