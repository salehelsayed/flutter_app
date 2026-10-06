#!/bin/bash
# Read-only: find earlier reaction staging/capture manifests and fixture files (names only).
cd /Volumes/CrucialX9/flutter_app || exit 1
find private docker-ws .codex-test-logs -maxdepth 4 -type f \( -iname '*staging*.json' -o -iname '*capture-manifest*.json' -o -iname '*capture_manifest*.json' -o -iname '*ios-ui-fixtures*.json' -o -iname '*direct-capture*.json' \) 2>/dev/null | head -30
ls -la se.pem 2>/dev/null | cut -c1-60; git check-ignore -q se.pem && echo "se.pem is git-ignored"
