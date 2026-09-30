#!/bin/bash
# Read-only: the video_compress plugin sources that decide whether a new compression can start after a cancel.
P=$(ls -d $HOME/.pub-cache/hosted/pub.dev/video_compress-3.* 2>/dev/null | tail -1)
echo "pkg: $P"
OUT=/Volumes/CrucialX9/flutter_app/artifacts/beta-20260928/r2-4/video_compress_src; mkdir -p "$OUT"
cp "$P/lib/src/video_compress/video_compressor.dart" "$OUT/" 2>/dev/null
cp "$P/lib/src/progress_callback/compress_mixin.dart" "$OUT/" 2>/dev/null
find "$P/android" -name "VideoCompressPlugin.kt" -exec cp {} "$OUT/" \;
find "$P/ios" -name "SwiftVideoCompressPlugin.swift" -exec cp {} "$OUT/" \;
ls -la "$OUT"
