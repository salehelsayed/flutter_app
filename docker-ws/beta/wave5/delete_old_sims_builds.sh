#!/bin/bash
# Delete the main checkout's old SIMS iOS DerivedData folders and prepared bundles (09-21..09-25; rebuildable).
M=/Volumes/CrucialX9/flutter_app/build/sims
for d in ios-device-production-bootstrap-derived ios-device-production-derived ios-device-group-media-269-derived prepared; do
  [ -d "$M/$d" ] && { s=$(du -sh "$M/$d" | cut -f1); rm -rf "$M/$d" && echo "deleted $s build/sims/$d"; }
done
df -h /Volumes/CrucialX9 | awk 'NR>1{print "free: "$4" ("$5" used)"}'
