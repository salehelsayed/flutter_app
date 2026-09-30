#!/bin/bash
# Read-only: show where flutter_tools strips xattrs before an iOS build.
SDK="$HOME/development/flutter-3.47.2/packages/flutter_tools/lib"
grep -rn "com.apple.provenance\|com.apple.FinderInfo" "$SDK" | head
F=$(grep -rln "com.apple.provenance" "$SDK" | head -1)
[ -n "$F" ] && { L=$(grep -n "com.apple.provenance" "$F" | head -1 | cut -d: -f1); sed -n "$((L-40)),$((L+25))p" "$F"; }
