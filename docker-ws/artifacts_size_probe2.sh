#!/bin/bash
# Read-only: drill into the largest testflight-crash-investigation subfolders.
cd "$(dirname "$0")/../artifacts/testflight-crash-investigation-20260910"
for d in resume-all release-followup-20260911 voip remaining-20260911; do
  echo "== $d"; du -sh "$d"/* 2>/dev/null | sort -rh | head -5
done
echo "== what kinds (dirs named build/ .dart_tool/ Pods/ DerivedData/ .gradle/)"
for n in build .dart_tool Pods DerivedData .gradle; do
  printf "%-12s " "$n"; find . -type d -name "$n" -prune -print0 2>/dev/null | xargs -0 du -sc 2>/dev/null | tail -1
done
