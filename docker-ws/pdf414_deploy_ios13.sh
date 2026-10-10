#!/bin/bash
# Plan 414: build the PDF-enabled flowlog iOS app from this worktree and install it on the
# iPhone 13 only, keeping app data (user approved 2026-10-10).
cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 1
OUT=Test-Flight-Improv/evidence/414/deploy_ios13.txt
{
  echo "=== start $(date -u +%FT%TZ)"
  bash docker-ws/pdf414_build_ios.sh || { echo "PDF414 IOS BUILD FAILED"; exit 1; }
  IPHONE_UDIDS=00008110-00184D622289801E bash docker-ws/install_iphones_keep_identity.sh
  echo "PDF414 IOS EXIT $?"
} > "$OUT" 2>&1
tail -8 "$OUT"
