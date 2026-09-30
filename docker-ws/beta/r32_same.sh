#!/bin/bash
# Read-only: are the W3 fix files in my build copy identical to the live tree now?
S=/Volumes/CrucialX9/flutter_app; C=/Volumes/CrucialX9/flutter_app-beta0924
echo "copy synced: $(sed -n 's/^synced_at=//p' $C/.proof-checkout-provenance.txt)"
for f in android/app/src/main/kotlin/com/mknoon/app/call/HeadlessCallAdmissionWorker.kt \
         lib/features/call/application/headless_call_ringing_reply.dart \
         lib/app/bootstrap/production_headless_call_admission.dart \
         lib/app/bootstrap/production_call_signaling_graph.dart; do
  if cmp -s "$S/$f" "$C/$f"; then r=same; else r=DIFFERENT; fi
  echo "$r  live mtime $(stat -f '%Sm' -t '%m-%d %H:%M' "$S/$f")  $f"
done
echo "app files changed in the live tree since my sync:"
cd "$S" && find lib android/app/src ios/Runner go-mknoon -type f -newer "$C/.proof-checkout-provenance.txt" ! -path '*/build/*' 2>/dev/null | head
