#!/bin/bash
# Read-only: inspect xcresult blobs, diagnostics, prior captures, and crash logs. Bounded output.
W=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree
P=$W/build/sims/proofs/groups.media_send_reliability_ios
d=$(ls -td "$P"/ios-p269-* | head -1)
X=$d/p269-ios.xcresult
echo "=== Staging tree"; find "$X/Staging" -exec ls -ldT {} \; | awk '{print $5,$6,$7,$8,$10}' | sed "s#$X/##" | head
echo "=== blob types"; for b in "$X"/Data/data.*; do printf '%s ' "$(stat -f %z "$b")"; file -b "$b" | cut -c1-80; done
echo "=== zstd?"; which zstd; ls /opt/homebrew/bin/zstd /usr/local/bin/zstd 2>/dev/null
Z=$(which zstd 2>/dev/null || ls /opt/homebrew/bin/zstd 2>/dev/null)
if [ -n "$Z" ]; then for b in "$X"/Data/data.*; do s=$(stat -f %z "$b"); [ "$s" -gt 30000 ] && continue; echo "--- $(basename "$b" | cut -c1-20) ($s)"; "$Z" -dc "$b" 2>/dev/null | strings -n 6 | grep -v -i -E 'token|secret|password' | head -60 | cut -c1-200; done; fi
echo "=== prior captures"; for p in $(ls -td "$P"/ios-p269-* | sed -n 2,3p); do echo "--- $p"; ls -lT "$p" | awk '{print $6,$7,$8,$10}' | tail -n +2 | tr '\n' ';' | cut -c1-900; echo; ls -lT "$p/p269-ios.xcresult" 2>/dev/null | awk '{print $8,$10}' | tr '\n' ' '; echo; done
echo "=== crash logs 2026-09-26"; for c in ~/Library/Logs/DiagnosticReports ~/Library/Logs/CrashReporter/MobileDevice; do find "$c" -newermt '2026-09-26 11:00' -type f 2>/dev/null | head -20; done
echo "=== xcode test logs"; find ~/Library/Developer/Xcode/DerivedData -maxdepth 4 -path '*Logs/Test*' -newermt '2026-09-26 14:20' 2>/dev/null | head
