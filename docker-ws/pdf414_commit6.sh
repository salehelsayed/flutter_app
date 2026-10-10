#!/bin/bash
# Plan 414: commit the remaining small evidence; keep big lane logs and machine-specific files out.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
git checkout -- macos/Runner.xcodeproj/project.pbxproj
git add Test-Flight-Improv/evidence/414/lane_summary.txt Test-Flight-Improv/evidence/414/deploy_ios13.txt \
  Test-Flight-Improv/evidence/414/deploy_pixel_result.txt Test-Flight-Improv/evidence/414/e2e/timeline.txt \
  Test-Flight-Improv/evidence/414/e2e/ap_open_step1.txt Test-Flight-Improv/evidence/414/e2e/*_t0.txt \
  Test-Flight-Improv/evidence/414/e2e/ui docker-ws/pdf414_*.sh
git commit -q -m "docs(414): final device evidence and lane summary

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log --oneline -1
echo "--- left uncommitted (on purpose):"
git status --short | sed -n '1,8p'
