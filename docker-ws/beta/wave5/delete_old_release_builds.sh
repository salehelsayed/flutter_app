#!/bin/bash
# User-approved 2026-10-07: delete old release/store/TestFlight build output folders.
M=/Volumes/CrucialX9/flutter_app
for p in build/releases build/store-releases build/testflight-host-validation-20260910 build/test_cache; do
  [ -e "$M/$p" ] && { s=$(du -sh "$M/$p" | cut -f1); rm -rf "$M/$p" && echo "deleted $s $p"; } || echo "not present: $p"
done
df -h /Volumes/CrucialX9 | awk 'NR>1{print "free: "$4" ("$5" used)"}'
