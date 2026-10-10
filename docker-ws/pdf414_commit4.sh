#!/bin/bash
# Plan 414: commit the three device-proof finding fixes.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
git checkout -- info.plist docker-ws/install_iphones_keep_identity_result.txt 2>/dev/null || true
git add -A lib test android Test-Flight-Improv/414-pdf-document-attachments-tdd-plan.md \
  Test-Flight-Improv/evidence/414/e2e/E2E_RESULTS.md Test-Flight-Improv/evidence/414/e2e/ui \
  Test-Flight-Improv/evidence/414/findings_dart_names.txt Test-Flight-Improv/evidence/414/findings_kotlin.txt docker-ws/pdf414_*.sh
git commit -q -F - <<'MSG'
fix(414): PDF device-proof findings: viewer name, share crash, share text

- F1: the received-media provider reports the document's clean name to the
  viewer app (only when it keeps the stored extension), so Drive shows
  "Invoice-414.pdf" instead of the blob id.
- F2: ShareIntentReadabilityGuard drops shared files the app cannot read
  before receive_sharing_intent opens them; an unreadable share no longer
  crashes the app with SecurityException.
- F3: refused shared documents get their own count and text instead of
  "Failed for N targets" or "oversized attachments".

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
git status --short | grep -v '^??' || echo "tracked tree clean"
