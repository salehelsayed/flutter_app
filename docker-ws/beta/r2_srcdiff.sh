#!/bin/bash
# Read-only: app source that differs between the isolated beta copy (what the phones run)
# and the live checkout (merged main + uncommitted work).
A=/Volumes/CrucialX9/flutter_app-beta0924
B=/Volumes/CrucialX9/flutter_app
for d in lib android/app/src/main ios/Runner pubspec.yaml pubspec.lock; do
  [ -e "$B/$d" ] || continue
  n=$(diff -rq -x "build" "$A/$d" "$B/$d" 2>/dev/null | wc -l | tr -d " ")
  echo "$d: $n differing files"
  diff -rq -x "build" "$A/$d" "$B/$d" 2>/dev/null | sed -E "s#$A/##; s#$B/##" | head -40
done
echo "=== go-mknoon top dirs"; ls "$B/go-mknoon" | head -30
echo "=== aar dates"; ls -la "$A/android/app/libs/GoMknoon.aar" "$B/android/app/libs/GoMknoon.aar"
echo "=== ios frameworks"; ls -la "$A/ios/Frameworks" "$B/ios/Frameworks" 2>/dev/null | head -12
echo "=== provenance of isolated copy"; cat "$A/.beta-provenance.txt" 2>/dev/null; ls -la "$A" | head -8
