#!/bin/bash
# Copy the Gemma 4 E2B model into the Mknoon app container on the iPhone 11 (Documents/) and verify its size there.
#   host-run bash docker-ws/iphone11_gemma_copy.sh <evidence dir under repo>
U=00008030-001A6D2801BB802E; B=com.mknoon.app; N=gemma-4-E2B-it.litertlm; WANT=2588147712
SRC=/Volumes/CrucialX9/flutter_app/gemma-ai/$N; E=/Volumes/CrucialX9/flutter_app/${1:?evidence}
echo "src size=$(stat -f %z "$SRC")"
timeout 120 xcrun devicectl device info details --device $U 2>&1 | grep -iE "freeSpace|totalCapacity|capacity" | head -4
echo "copy start $(date -u +%T)"
timeout 1800 xcrun devicectl device copy to --device $U --source "$SRC" --destination "Documents/$N" \
  --domain-type appDataContainer --domain-identifier $B > "$E/gemma_copy.log" 2>&1; echo "copy exit=$? $(date -u +%T)"
tail -3 "$E/gemma_copy.log"
timeout 120 xcrun devicectl device info files --device $U --domain-type appDataContainer --domain-identifier $B \
  --subdirectory Documents > "$E/gemma_files.txt" 2>&1; echo "list exit=$?"
grep -i "$N" "$E/gemma_files.txt" | head -3
grep -i "$N" "$E/gemma_files.txt" | grep -q "$WANT" && echo "SIZE OK $WANT" || echo "SIZE NOT CONFIRMED (see gemma_files.txt)"
