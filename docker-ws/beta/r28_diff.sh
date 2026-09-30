#!/bin/bash
# Read-only: app files changed in the live tree since the build-r2-7 copy was synced (19:09Z), with diffs against the copy.
SRC=/Volumes/CrucialX9/flutter_app; OLD=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260928/r2-6c"; mkdir -p "$OUT"; : > "$OUT/since_r27.diff"
REF="$OLD/.proof-checkout-provenance.txt"
cd "$SRC" || exit 1
echo "ref: $(stat -f '%Sm' "$REF")"
find lib android/app/src test integration_test third_party ios/Runner -type f -newer "$REF" \
  ! -path '*/build/*' ! -path '*/.dart_tool/*' ! -path '*/Pods/*' 2>/dev/null | sort > "$OUT/changed_files.txt"
while read -r f; do
  if [ -f "$OLD/$f" ]; then diff -u "$OLD/$f" "$f" | sed "s#$OLD/##"; else echo "NEW FILE $f"; sed 's/^/+/' "$f"; fi >> "$OUT/since_r27.diff"
done < "$OUT/changed_files.txt"
echo "changed files: $(wc -l < "$OUT/changed_files.txt" | tr -d ' ')"; cat "$OUT/changed_files.txt"
echo "diff lines: $(wc -l < "$OUT/since_r27.diff" | tr -d ' ')"
