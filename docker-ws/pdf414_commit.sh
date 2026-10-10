#!/bin/bash
# Plan 414: stage the plan's files and commit in this worktree.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
git checkout -- macos/Runner.xcodeproj/project.pbxproj docker-ws/flutter_sdk.sh
git add -A lib test android ios macos/Flutter/GeneratedPluginRegistrant.swift pubspec.yaml pubspec.lock scripts \
  Test-Flight-Improv/414-pdf-document-attachments-tdd-plan.md
git add Test-Flight-Improv/evidence/414
git reset -q -- 'Test-Flight-Improv/evidence/414/lane_1to1*.txt' 'Test-Flight-Improv/evidence/414/lane_groups*.txt' \
  'Test-Flight-Improv/evidence/414/lane_feed*.txt' 'Test-Flight-Improv/evidence/414/lane_completeness-check.txt' \
  'Test-Flight-Improv/evidence/414/lane_runtime-roots.txt'
git add docker-ws/pdf414_*.sh
git diff --cached --stat | tail -5
git status --short | head -20
git commit -q -F docker-ws/pdf414_commitmsg.txt
git log --oneline -1
