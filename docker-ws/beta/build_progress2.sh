#!/bin/bash
# Read-only: is the Xcode build of the fixed copy doing work?
echo "now: $(date '+%H:%M:%S')"
echo "runner: $(pgrep -f build_beta_fixed.sh | tr '\n' ' ')"
ps -axo pid,etime,%cpu,command | grep -E "xcodebuild|XCBBuildService|SWBBuildService|swift-frontend|clang" | grep -v grep \
  | awk '{printf "%s %s cpu=%s %s\n",$1,$2,$3,substr($4,1,70)}' | head -10
D=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Runner-* 2>/dev/null | head -1)
echo "derived: $D"
echo "files written in last 2 min: $(find "$D/Build" -type f -newermt "-2 minutes" 2>/dev/null | wc -l)"
