#!/bin/bash
# Diff the vendored video_compress fork against pub.dev video_compress 3.1.4 (excluding example/).
ORIG=$HOME/.pub-cache/hosted/pub.dev/video_compress-3.1.4
FORK=/Volumes/CrucialX9/flutter_app/third_party/video_compress
OUT=/Volumes/CrucialX9/flutter_app/artifacts/beta-20260928/r2-4b; mkdir -p "$OUT"
diff -ruN -x example -x .dart_tool -x build -x '.gradle' "$ORIG" "$FORK" | sed "s#$ORIG#a#g; s#$FORK#b#g" > "$OUT/video_compress_fork.diff"
echo "diff lines: $(wc -l < "$OUT/video_compress_fork.diff")"
grep "^diff \|^Only in" "$OUT/video_compress_fork.diff" | head -30
