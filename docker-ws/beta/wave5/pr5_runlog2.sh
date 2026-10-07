#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app || exit 1
gh run view 37611674565 --log-failed 2>&1 | grep -E "^metadata" | grep -E "FAIL:|ERROR:|AssertionError|Error:|Traceback|File \"|!=|expected" | head -20 | cut -c60-300
echo "=== main 10-04 run"
id=$(gh run list --branch main --limit 1 --json databaseId --jq '.[0].databaseId'); gh run view $id --log-failed 2>&1 | grep -E "FAIL:|ERROR:|BLOCKED" | head -6 | cut -c60-260
