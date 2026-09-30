#!/bin/bash
# Read-only: app files changed in the live tree since my build-r2-8 sync (2026-09-28 23:06:58 local), with diffs
# against the isolated copy when the copy still holds that sync. Output: artifacts/beta-20260928/r2-8/
SRC=/Volumes/CrucialX9/flutter_app; OLD=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260928/r2-8"; mkdir -p "$OUT"; : > "$OUT/since_r28.diff"
echo "copy provenance: $(tr '\n' ' ' < "$OLD/.proof-checkout-provenance.txt" | cut -c1-200)"
cd "$SRC" || exit 1
find lib android/app/src test integration_test third_party ios/Runner go-mknoon go-relay-server -type f \
  -newermt '2026-09-28 23:06:58' ! -path '*/build/*' ! -path '*/.dart_tool/*' ! -path '*/Pods/*' 2>/dev/null \
  | sort > "$OUT/changed_files.txt"
while read -r f; do
  if [ -f "$OLD/$f" ]; then diff -u "$OLD/$f" "$f" | sed "s#$OLD/##"; else echo "NEW FILE $f"; sed 's/^/+/' "$f"; fi >> "$OUT/since_r28.diff"
done < "$OUT/changed_files.txt"
echo "changed files: $(wc -l < "$OUT/changed_files.txt" | tr -d ' ')"; cat "$OUT/changed_files.txt"
echo "diff lines: $(wc -l < "$OUT/since_r28.diff" | tr -d ' ')"
