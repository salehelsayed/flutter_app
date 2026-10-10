#!/bin/bash
# Plan 414: whole-project analyzer run in this worktree.
cd "$(cd "$(dirname "$0")/.." && pwd)"
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
"$SDK/bin/flutter" analyze --no-pub lib test integration_test > Test-Flight-Improv/evidence/414/analyze_all.txt 2>&1
echo "ANALYZE_EXIT=$?" >> Test-Flight-Improv/evidence/414/analyze_all.txt
grep -c "error •" Test-Flight-Improv/evidence/414/analyze_all.txt
grep "error •\|warning •" Test-Flight-Improv/evidence/414/analyze_all.txt | head -30
tail -2 Test-Flight-Improv/evidence/414/analyze_all.txt
