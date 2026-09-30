#!/bin/bash
# Read-only: the bonsoir_darwin plugin source used by the build (pub cache), resolveService part.
V=$(awk '/^  bonsoir_darwin:/{f=1} f&&/version:/{gsub(/"/,"",$2); print $2; exit}' /Volumes/CrucialX9/flutter_app/pubspec.lock)
D=$(ls -d ~/.pub-cache/hosted/pub.dev/bonsoir_darwin-$V 2>/dev/null)
echo "bonsoir_darwin $V at $D"
F=$(grep -rl "func resolveService" "$D" 2>/dev/null | head -1)
echo "file: $F"
grep -n "func resolveService" -A70 "$F" | head -110
