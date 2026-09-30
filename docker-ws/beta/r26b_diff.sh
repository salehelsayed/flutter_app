#!/bin/bash
# Diff files changed since the r2-5 build (copy synced 16:51Z) against the live tree.
SRC=/Volumes/CrucialX9/flutter_app; OLD=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260928/r2-6b"; mkdir -p "$OUT"; : > "$OUT/since_r25.diff"
VC=third_party/video_compress/android/src/main/kotlin/com/example/video_compress
for f in $VC/VideoCompressPlugin.kt $VC/TranscodeOutputGuard.kt $VC/Utility.kt $VC/ThumbnailUtility.kt \
         lib/features/call/presentation/locked_call_projection.dart \
         lib/features/call/infrastructure/android_call_lifecycle_adapter.dart \
         android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallNativeBridge.kt; do
  if [ -f "$OLD/$f" ]; then diff -u "$OLD/$f" "$SRC/$f"; else echo "NEW FILE $f"; sed 's/^/+/' "$SRC/$f"; fi \
    | sed "s#$OLD/##; s#$SRC/##" >> "$OUT/since_r25.diff"
done
wc -l "$OUT/since_r25.diff"; grep -c "^+++\|^NEW FILE" "$OUT/since_r25.diff"
