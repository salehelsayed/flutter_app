#!/bin/bash
# Read-only: largest children of the main checkout's build/ and .codex-test-logs/ with last-modified dates.
M=/Volumes/CrucialX9/flutter_app
for d in "$M/build" "$M/.codex-test-logs" "$M/build/sims"; do
  echo "== $d"
  for c in $(du -sk "$d"/* "$d"/.[!.]* 2>/dev/null | sort -rn | head -12 | awk '{print $2}'); do
    printf '%8s  %s  %s\n' "$(du -sh "$c" 2>/dev/null | cut -f1)" "$(stat -f %Sm -t %Y-%m-%d "$c")" "${c#$M/}"
  done
done
