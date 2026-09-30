#!/bin/bash
# Run the six private-media / protected-viewer / secure-window proof files on
# emulator-5556 from the isolated checkout prepared by
# docker-ws/prepare_proof_checkout_5556.sh.
#
# Each command is the one pinned in tool/testing/legacy_target_contracts.json
# for that target, with {device:android-physical} resolved to emulator-5556 and
# {config:relay_addresses} resolved to the sims default relay pair. No suite
# runner is involved: six individual `flutter test` invocations, serial.
#
# Run ON THE MAC (long; run it in the background):
#   /claude-host-bin/host-run bash docker-ws/run_private_media_proofs_5556.sh
#
# Optional args select a subset by short name, e.g.
#   run_private_media_proofs_5556.sh direct_lifecycle group_platform
#
# Env:
#   PROOF_DST          isolated checkout (default /Volumes/CrucialX9/flutter_app-proof5556)
#   PROOF_DEVICE       device id (default emulator-5556)
#   PROOF_DEVICE_FORCE 1 to allow a device other than emulator-5556
#   MKNOON_TRIAGE      1 to ask the advisory TypeSafe triage note about red logs
set -uo pipefail

DST="${PROOF_DST:-/Volumes/CrucialX9/flutter_app-proof5556}"
DEVICE="${PROOF_DEVICE:-emulator-5556}"

if [ "$DEVICE" != "emulator-5556" ] && [ "${PROOF_DEVICE_FORCE:-0}" != "1" ]; then
  echo "refusing device $DEVICE (5554 and the Pixel belong to another session); set PROOF_DEVICE_FORCE=1 to override" >&2
  exit 2
fi
if [ ! -f "$DST/.dart_tool/package_config.json" ]; then
  echo "checkout not prepared: $DST (run prepare_proof_checkout_5556.sh first)" >&2
  exit 2
fi

SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
FLUTTER="$SDK/bin/flutter"
if [ ! -x "$FLUTTER" ]; then
  echo "flutter sdk not found at $SDK" >&2
  exit 2
fi

state="$(adb -s "$DEVICE" get-state 2>&1)"
if [ "$state" != "device" ]; then
  echo "device $DEVICE not ready: $state" >&2
  exit 2
fi

RELAY_ADDRESSES="/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"

ALL_ENTRIES="direct_lifecycle:integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart \
group_lifecycle:integration_test/group_private_media_lifecycle_db_proof_test.dart \
direct_platform:integration_test/direct_private_media_platform_protection_proof_test.dart \
group_platform:integration_test/group_private_media_platform_proof_test.dart \
announcement_platform:integration_test/announcement_private_media_platform_proof_test.dart \
thumbnail_secure_window:integration_test/protected_photo_thumbnail_secure_window_proof_test.dart"

if [ "$#" -gt 0 ]; then
  ENTRIES=""
  for want in "$@"; do
    for entry in $ALL_ENTRIES; do
      if [ "${entry%%:*}" = "$want" ]; then ENTRIES="$ENTRIES $entry"; fi
    done
  done
  if [ -z "$ENTRIES" ]; then
    echo "no target matched: $*" >&2
    exit 2
  fi
else
  ENTRIES="$ALL_ENTRIES"
fi

cd "$DST" || exit 2
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$DST/.proof-runs/$STAMP"
mkdir -p "$OUT" || exit 2

echo "CHECKOUT=$DST"
echo "LOGDIR=$OUT"
echo "DEVICE=$DEVICE"
echo "SDK=$("$FLUTTER" --version 2>&1 | head -1)"
[ -f "$DST/.proof-checkout-provenance.txt" ] && cat "$DST/.proof-checkout-provenance.txt"
echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

SUMMARY="$OUT/summary.txt"
overall=0

for entry in $ENTRIES; do
  name="${entry%%:*}"
  path="${entry#*:}"
  log="$OUT/$name.log"
  echo "=== RUN $name ($path) $(date -u +%H:%M:%SZ) ==="
  "$FLUTTER" test \
    --no-pub \
    -d "$DEVICE" \
    --reporter expanded \
    --dart-define=MKNOON_RELAY_ADDRESSES="$RELAY_ADDRESSES" \
    "$path" > "$log" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    verdict=PASS
  else
    verdict="FAILED(rc=$rc)"
    overall=1
  fi
  printf '%-24s %-8s %s\n' "$name" "$verdict" "$log" >> "$SUMMARY"
  echo "--- $name $verdict; log tail ---"
  tail -12 "$log"
  if [ "$rc" -ne 0 ] && [ "${MKNOON_TRIAGE:-1}" = "1" ]; then
    echo "--- advisory triage ($name) ---"
    MKNOON_TRIAGE=1 python3 "$DST/scripts/triage_red_run.py" "$log" 2>&1 | tail -5
  fi
done

echo "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=== SUMMARY ==="
cat "$SUMMARY"
if [ "$overall" -ne 0 ]; then
  echo "OVERALL=FAILED"
else
  echo "OVERALL=PASS"
fi
exit "$overall"
