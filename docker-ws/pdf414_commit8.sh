#!/bin/bash
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
git add Test-Flight-Improv/evidence/414/lane_summary.txt docker-ws/pdf414_commit8.sh
git commit -q -m "docs(414): 1:1 lane green end to end after the binding test fix

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log --oneline -1
