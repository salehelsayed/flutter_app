#!/bin/bash
# Diff app files between the copy synced for the R2-4 build (13:35Z) and the live tree.
SRC=/Volumes/CrucialX9/flutter_app; OLD=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260928/r2-4b"; mkdir -p "$OUT"; : > "$OUT/app_since_r24.diff"
for f in lib/core/media/image_processor.dart lib/core/widgets/video_processing_notice.dart \
         lib/features/conversation/presentation/screens/conversation_wired.dart \
         lib/features/groups/presentation/screens/group_conversation_wired.dart \
         lib/features/share/application/share_batch_delivery_coordinator.dart lib/l10n/app_en.arb \
         third_party/video_compress/lib/src/video_compress/video_compressor.dart \
         android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallNotificationFactory.kt \
         android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallAndroidRuntime.kt \
         android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallNativeBridge.kt; do
  if [ -f "$OLD/$f" ]; then diff -u "$OLD/$f" "$SRC/$f"; else echo "NEW FILE $f"; cat "$SRC/$f" | sed 's/^/+/'; fi \
    | sed "s#$OLD/##; s#$SRC/##" >> "$OUT/app_since_r24.diff"
done
wc -l "$OUT/app_since_r24.diff"; grep -c "^+++\|^NEW FILE" "$OUT/app_since_r24.diff"
