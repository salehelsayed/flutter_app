#!/bin/bash
# User-approved 2026-10-06: delete old plan build outputs and pre-2026-09-27 test logs (not migration evidence).
#   delete_old_outputs.sh [--delete]   (default: dry run listing)
M=/Volumes/CrucialX9/flutter_app; total=0
list(){
  for d in build/plan398 build/relay-diagnostics-review build/notification-review-ios build/notification-review-20260907 build/ios-cross-platform-derived build/macos; do [ -e "$M/$d" ] && echo "$M/$d"; done
  find "$M/.codex-test-logs" -mindepth 1 -maxdepth 1 ! -name 'production-bootstrap-migration-*' ! -newermt 2026-09-27 2>/dev/null
}
for d in $(list); do
  k=$(du -sk "$d" 2>/dev/null | cut -f1); total=$((total+k))
  [ "$1" = "--delete" ] && rm -rf "$d" || printf '%7s MB  %s\n' "$((k/1024))" "${d#$M/}"
done | sort -rn | head -60
echo "$( [ "$1" = "--delete" ] && echo deleted || echo would delete ) total: $(for d in $(list); do du -sk "$d" 2>/dev/null | cut -f1; done | awk '{s+=$1} END {printf "%.1f GB", s/1048576}')"
