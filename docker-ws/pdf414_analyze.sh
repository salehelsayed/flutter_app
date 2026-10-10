#!/bin/bash
# Plan 414: flutter analyze + dart format check on the worktree's changed Dart files.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
FILES=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | grep -E '\.dart$' | sort -u)
echo "files: $(echo "$FILES" | wc -l)"
if [ "${1:-}" = "--fix-format" ]; then
  "$SDK/bin/dart" format $FILES; echo "FORMAT_APPLIED=$?"
else
  "$SDK/bin/dart" format --output=none --set-exit-if-changed $FILES; echo "FORMAT_EXIT=$?"
fi
"$SDK/bin/flutter" analyze --no-pub $FILES; echo "ANALYZE_EXIT=$?"
