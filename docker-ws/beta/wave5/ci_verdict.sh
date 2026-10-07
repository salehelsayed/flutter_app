#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"; cd /Volumes/CrucialX9/flutter_app || exit 1
gh run view "$1" --log-failed 2>&1 | grep -E "BLOCKED|FAIL|Error|error" | head -5 | cut -c60-260
