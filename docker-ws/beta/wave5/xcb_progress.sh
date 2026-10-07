#!/bin/bash
# Read-only: the running xcodebuild, its newest child, CPU over 20 s, and newest DerivedData write.
x=$(pgrep -f "xcodebuild build-for-testing" | head -1); [ -z "$x" ] && { echo "no xcodebuild"; exit; }
ps -o pid=,etime=,time= -p $x
c1=$(ps -axo time=,comm= | awk '/SWBBuildService|clang|swift-frontend|ld|dsymutil|codesign/ {split($1,a,":"); s+=(length(a)==3)?a[1]*3600+a[2]*60+a[3]:a[1]*60+a[2]} END {printf "%.1f", s}')
sleep 20
c2=$(ps -axo time=,comm= | awk '/SWBBuildService|clang|swift-frontend|ld|dsymutil|codesign/ {split($1,a,":"); s+=(length(a)==3)?a[1]*3600+a[2]*60+a[3]:a[1]*60+a[2]} END {printf "%.1f", s}')
echo "build-tool cpu: $c1 -> $c2 s"
ps -axo pid,etime,pcpu,comm | grep -E "clang|swift-frontend|/ld$|dsymutil|codesign|SWBBuildService" | grep -v grep | sort -k3 -nr | head -4 | cut -c1-120
D=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next/build/sims/ios-device-production-derived
f=$(find "$D/Build/Intermediates.noindex" -maxdepth 4 -type f -mmin -5 2>/dev/null | wc -l | tr -d ' '); echo "derived files written in last 5 min: $f"
