#!/bin/bash
# Plan 414: commit the review fixes, then the Go binding contract test fix, separately.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
git checkout -- info.plist macos/Runner.xcodeproj/project.pbxproj docker-ws/install_iphones_keep_identity_result.txt 2>/dev/null || true
git add lib test Test-Flight-Improv/evidence/414/e2e/E2E_RESULTS.md Test-Flight-Improv/evidence/414/e2e/timeline.txt \
  Test-Flight-Improv/evidence/414/e2e/ui docker-ws/pdf414_*.sh
git reset -q -- scripts/test/go_binding_staleness_contract_test.sh docker-ws/pdf414_go_binding_check.sh
git commit -q -F - <<'MSG'
fix(414): share sheet obeys the PDF send switch; manual Download for pending media

- The OS share sheet and in-app Forward refuse PDFs while
  MKNOON_ENABLE_DOCUMENT_ATTACHMENTS is off, so the receive-first rollout
  cannot be bypassed (older group clients drop the whole message).
- A received photo, video, voice message or PDF left `pending` (automatic
  download refused by settings) shows a Download button wired to the
  existing explicit download callback instead of an endless loader.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git add scripts/test/go_binding_staleness_contract_test.sh docker-ws/pdf414_go_binding_check.sh
git commit -q -F - <<'MSG'
test(go): teach the binding staleness contract the gomobile-tools step

Plan 406 (f80d3578a) made both ensure scripts run `make -s gomobile-tools`
first. The contract's fake make only knew `android`/`ios` as its first
argument, saw `-s` and exited 64, so the 1:1 lane always failed after its
Flutter tests. The fake now skips flags, treats gomobile-tools as a
non-rebuild setup step (logged apart from the rebuild log), and the test
asserts both scripts still install the pinned tools.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --oneline -3
git status --short | grep -v '^??' || echo "tracked tree clean"
