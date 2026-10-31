#!/bin/bash
# Provenance of the UI-Update worktree: HEAD, dirty files, diff hash incl. untracked app files.
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app-ui-update
cd "$W" || exit 2
echo "HEAD $(git rev-parse HEAD) branch=$(git rev-parse --abbrev-ref HEAD)"
echo "== pubspec"; grep -E '^version:' pubspec.yaml
echo "== tracked dirty"; git status --short -uno
echo "== untracked app files"
UNTR=$(git ls-files --others --exclude-standard -- lib ios android go-mknoon assets 'pubspec*' | sort)
echo "$UNTR" | sed '/^$/d'
{ git diff HEAD; for f in $UNTR; do echo "UNTRACKED $f"; shasum -a 256 "$f"; done; } > /tmp/uiupdate_diff_material.txt
echo "DIFF_HASH $(shasum -a 256 /tmp/uiupdate_diff_material.txt | cut -d' ' -f1) lines=$(wc -l < /tmp/uiupdate_diff_material.txt | tr -d ' ')"
echo "== libs"; ls -la android/app/libs 2>&1 | head
echo "== GoMknoon aar anywhere"; find android -maxdepth 4 -name 'GoMknoon*.aar' 2>/dev/null | head
echo "== key.properties"; [ -f android/key.properties ] && echo present || echo MISSING
echo "== defines"; ls tool/build/ 2>&1 | head
echo "== scripts release"; ls scripts | grep -i -E 'release|apk|gomknoon|aar|go_android' | head -20
[ -f ios/Runner/GoogleService-Info.plist ] && echo plist-present || echo plist-MISSING
[ -f android/app/google-services.json ] && echo gsj-present || echo gsj-MISSING
[ -f .env ] && echo env-present || echo env-MISSING
