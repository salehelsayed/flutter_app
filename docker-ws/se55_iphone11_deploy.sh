#!/bin/bash
# SE-55 flow-log build and data-preserving install on explicitly selected iPhones.
# Set IPHONE_UDIDS, or select it in the gitignored local_devices.env file.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || exit 1
. docker-ws/_device_targets.sh
. docker-ws/_host_paths.sh
mknoon_load_iphone_targets "$REPO" || exit 2
EV="${1:?evidence dir}"; OUT="$EV/iphone11_deploy.txt"
mknoon_require_output "$REPO" "$OUT" || exit 2
mkdir -p "$EV" || exit 2
(
  echo "=== start $(date -u +%FT%TZ) head=$(git rev-parse --short HEAD)"
  bash docker-ws/build_ios_flowlog.sh || { echo "SE55 BUILD FAILED"; exit 1; }
  IPHONE_UDIDS="$IPHONE_UDIDS" bash docker-ws/install_iphones_keep_identity.sh
  rc=$?; echo "SE55 DEPLOY EXIT $rc"; exit "$rc"
) > "$OUT" 2>&1
rc=$?; tail -6 "$OUT"; exit "$rc"
