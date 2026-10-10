#!/bin/bash
# Plan 414: commit the iOS export-name fix and iPhone proof.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
git checkout -- info.plist docker-ws/install_iphones_keep_identity_result.txt 2>/dev/null || true
git add ios/Runner/ReceivedMediaEgressCoordinator.swift Test-Flight-Improv/414-pdf-document-attachments-tdd-plan.md \
  Test-Flight-Improv/evidence/414/e2e/E2E_RESULTS.md docker-ws/pdf414_*.sh
git add -f Test-Flight-Improv/evidence/414/e2e/shots/i2_quicklook_13.png Test-Flight-Improv/evidence/414/e2e/shots/i3_quicklook_named_13.png Test-Flight-Improv/evidence/414/e2e/shots/i7_save_named_13.png
git commit -q -F - <<'MSG'
fix(414): iOS Save to Files and Share use the document's name

Export a temporary copy named with the display name (one folder per item),
removed when the export or share ends; the stored file is used if copying
fails. Proven on the iPhone 13 with the full iPhone UI round trip.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
