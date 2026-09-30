#!/bin/bash
# Read-only sanity check of the isolated proof checkout before the runs start.
#   /claude-host-bin/host-run bash docker-ws/verify_proof_checkout_5556.sh
set -uo pipefail
DST="${PROOF_DST:-/Volumes/CrucialX9/flutter_app-proof5556}"
cd "$DST" || exit 2

echo "=== provenance ==="
cat .proof-checkout-provenance.txt 2>/dev/null

echo "=== required build inputs ==="
for f in \
  .dart_tool/package_config.json \
  pubspec.yaml \
  android/local.properties \
  android/key.properties \
  android/app/google-services.json \
  android/app/libs/GoMknoon.aar \
  scripts/triage_red_run.py \
  .env
do
  if [ -e "$f" ]; then
    echo "ok   $f ($(wc -c < "$f" | tr -d ' ') bytes)"
  else
    echo "MISS $f"
  fi
done

echo "=== the six proof files (size + sha256 vs live checkout) ==="
for f in \
  integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart \
  integration_test/group_private_media_lifecycle_db_proof_test.dart \
  integration_test/direct_private_media_platform_protection_proof_test.dart \
  integration_test/group_private_media_platform_proof_test.dart \
  integration_test/announcement_private_media_platform_proof_test.dart \
  integration_test/protected_photo_thumbnail_secure_window_proof_test.dart \
  integration_test/integration_test.dart
do
  if [ -f "$f" ]; then
    here="$(shasum -a 256 "$f" | awk '{print $1}')"
    there="$(shasum -a 256 "/Volumes/CrucialX9/flutter_app/$f" 2>/dev/null | awk '{print $1}')"
    if [ "$here" = "$there" ]; then match=same; else match="DIFFERS(live=$there)"; fi
    echo "ok   $f ${here:0:12} $match"
  else
    echo "MISS $f"
  fi
done
