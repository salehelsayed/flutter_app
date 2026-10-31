#!/bin/bash
# Read-only: recent swift-frontend / clang crash reports (names, times, exception lines only).
#   host-run bash docker-ws/swift_crash_check.sh
for d in "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports; do
  ls -lt "$d" 2>/dev/null | grep -iE "swift|clang" | head -5
done
f=$(ls -t "$HOME/Library/Logs/DiagnosticReports"/swift-frontend* 2>/dev/null | head -1)
if [ -n "$f" ]; then
  echo "== $f"
  grep -m6 -E "exception|Exception Type|termination|Termination Reason|namespace|signal" "$f" | cut -c1-160
fi
