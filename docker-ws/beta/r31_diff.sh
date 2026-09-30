#!/bin/bash
# Read-only: app files that differ between the live tree and the isolated copy (still my d519 sync of 06:37 UTC on
# 2026-09-29), with unified diffs. Output: artifacts/beta-20260928/r2-9/{changed_files.txt,since_d519.diff}
SRC=/Volumes/CrucialX9/flutter_app; OLD=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260928/r2-9"; mkdir -p "$OUT"; : > "$OUT/since_d519.diff"
echo "copy provenance: $(tr '\n' ' ' < "$OLD/.proof-checkout-provenance.txt" | cut -c1-200)"
X="-x build -x .dart_tool -x Pods -x .gradle -x .cxx -x .DS_Store -x *.aar -x *.xcframework -x .symlinks -x ephemeral -x Flutter"
: > "$OUT/changed_files.txt"
for d in lib android/app/src android/app/build.gradle android/app/build.gradle.kts android/build.gradle android/settings.gradle \
         ios/Runner ios/Podfile go-mknoon go-relay-server test integration_test third_party pubspec.yaml pubspec.lock \
         tool/build/voice_call_release_defines.json; do
  [ -e "$SRC/$d" ] || [ -e "$OLD/$d" ] || continue
  if [ -d "$SRC/$d" ]; then
    diff -rq $X "$OLD/$d" "$SRC/$d" 2>/dev/null | sed -E "s#^Files $OLD/(.*) and $SRC/.* differ#M \1#; s#^Only in $SRC/(.*): (.*)#A \1/\2#; s#^Only in $OLD/(.*): (.*)#D \1/\2#" >> "$OUT/changed_files.txt"
  else
    cmp -s "$OLD/$d" "$SRC/$d" || echo "M $d" >> "$OUT/changed_files.txt"
  fi
done
sort -o "$OUT/changed_files.txt" "$OUT/changed_files.txt"
while read -r k f; do
  case "$k" in
    M) diff -u "$OLD/$f" "$SRC/$f" | sed "s#$OLD/##; s#$SRC/##" ;;
    A) if [ -f "$SRC/$f" ]; then echo "NEW FILE $f"; sed 's/^/+/' "$SRC/$f"; else echo "NEW DIR $f: $(find "$SRC/$f" -type f | wc -l) files"; fi ;;
    D) echo "REMOVED $f" ;;
  esac >> "$OUT/since_d519.diff"
done < "$OUT/changed_files.txt"
echo "changed: $(wc -l < "$OUT/changed_files.txt" | tr -d ' ')"; cat "$OUT/changed_files.txt"
echo "diff lines: $(wc -l < "$OUT/since_d519.diff" | tr -d ' ')"
