#!/bin/bash
# Read-only: diff the R2-4 files between the copy synced for the R2-3 build (10:53Z) and the live tree.
SRC=/Volumes/CrucialX9/flutter_app; OLD=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260928/r2-4"; mkdir -p "$OUT"
: > "$OUT/r24_since_r23.diff"
for f in lib/core/media/image_processor.dart lib/features/share/application/share_batch_delivery_coordinator.dart \
         lib/features/conversation/presentation/screens/conversation_wired.dart \
         lib/features/groups/presentation/screens/group_conversation_wired.dart lib/l10n/app_en.arb; do
  diff -u "$OLD/$f" "$SRC/$f" | sed "s#$OLD/##; s#$SRC/##" >> "$OUT/r24_since_r23.diff"
done
wc -l "$OUT/r24_since_r23.diff"
