#!/bin/bash
set -eu
cd /Volumes/CrucialX9/flutter_app
git add pubspec.yaml
git commit -q -m "chore(release): version 1.0.1+122

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git log --oneline -1
