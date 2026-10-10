#!/bin/bash
# Plan 414: commit the device proof evidence.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
git add Test-Flight-Improv/414-pdf-document-attachments-tdd-plan.md Test-Flight-Improv/evidence/414/e2e docker-ws/pdf414_*.sh
git reset -q -- 'Test-Flight-Improv/evidence/414/e2e/shots'
git commit -q -m "docs(414): device proof for PDF attachments (Pixel 6 + iPhone 13, partial)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log --oneline -2
git status --short | head
