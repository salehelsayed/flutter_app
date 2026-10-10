#!/bin/bash
# User-approved 2026-10-07: delete other sessions' old logs/APKs and two old build folders.
M=/Volumes/CrucialX9/flutter_app
for p in .codex-test-logs/notification-lock-fix-20261004 .codex-test-logs/r29-call-diagnostic-20260929 .codex-test-logs/r29-w3-startup-20260929 .codex-test-logs/r2-4-r2-6-final-android.apk .codex-test-logs/r2-4-fix3-android.apk build/plan374 build/test_cache; do
  [ -e "$M/$p" ] && { s=$(du -sh "$M/$p" | cut -f1); rm -rf "$M/$p" && echo "deleted $s $p"; }
done
df -h /Volumes/CrucialX9 | awk 'NR>1{print "free: "$4" ("$5" used)"}'
