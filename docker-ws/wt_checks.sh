#!/bin/bash
# Light release checks in the release-126 worktree. Output goes to the evidence dir.
set -uo pipefail
T=${1:?tree}; W=/Volumes/CrucialX9/flutter_app/build/$T
E=$W/.codex-test-logs/$T; mkdir -p "$E"
cd "$W"
{
echo "== defines check (store defines)"
python3 scripts/check_update_check_release_defines.py --dart-define-from-file=tool/build/voice_call_release_defines.json; echo "defines_exit=$?"
python3 scripts/check_update_check_release_defines.py --dart-define-from-file=tool/build/voice_call_release_defines.json --dart-define=PRODUCTION_APNS=true; echo "defines_ios_exit=$?"
echo "== pub get"; flutter pub get >/dev/null 2>&1; echo "pubget_exit=$?"
echo "== analyze"; flutter analyze --no-fatal-infos > "$E/analyze.txt" 2>&1; echo "analyze_exit=$?"
grep -c ' error • ' "$E/analyze.txt" | sed 's/^/errors=/'
grep -c ' warning • ' "$E/analyze.txt" | sed 's/^/warnings=/'
grep -c ' info • ' "$E/analyze.txt" | sed 's/^/infos=/'
} > "$E/checks.txt" 2>&1
cat "$E/checks.txt"
