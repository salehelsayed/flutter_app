#!/bin/bash
# Mac-side logcat capture straight to a file (the host bridge buffers streamed output until exit,
# so a container-side `adb logcat > file` that gets stopped writes nothing).
#   host-run bash docker-ws/logcat_capture.sh <serial> <out-file-in-repo> <max-seconds>
# Stops early when <out-file>.stop exists.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="${1:?serial}"; OUT="$REPO/${2:?out}"; MAX="${3:?seconds}"
export PATH="$HOME/Library/Android/sdk/platform-tools:/opt/homebrew/bin:/usr/bin:/bin"
mkdir -p "$(dirname "$OUT")"
adb -s "$S" logcat -c
adb -s "$S" logcat -v threadtime > "$OUT" 2>&1 &
P=$!
echo "capturing $S pid=$P"
t=0; while kill -0 "$P" 2>/dev/null && [ "$t" -lt "$MAX" ] && [ ! -f "$OUT.stop" ]; do sleep 5; t=$((t+5)); done
kill "$P" 2>/dev/null; wait "$P" 2>/dev/null
rm -f "$OUT.stop"; echo "done $S bytes=$(wc -c < "$OUT")"
