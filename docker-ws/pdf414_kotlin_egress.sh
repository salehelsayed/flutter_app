#!/bin/bash
# Plan 414: Android received-media egress JVM tests in this worktree.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/Test-Flight-Improv/evidence/414/${1:-kotlin_egress.txt}"
"$ROOT/android/gradlew" -p "$ROOT/android" --console=plain :app:testDebugUnitTest \
  --tests 'com.mknoon.app.ReceivedMediaEgressNativeTest' --tests 'com.mknoon.app.ShareIntentReadabilityGuardTest' --tests 'com.mknoon.app.MainActivityOnNewIntentTest' > "$LOG.full" 2>&1
status=$?
grep -E "^(> Task :app:testDebugUnitTest|BUILD |.*FAILED|.*tests completed)|^e: |Test >" "$LOG.full" > "$LOG"
echo "gradle exit: $status" >> "$LOG"
tail -15 "$LOG"
