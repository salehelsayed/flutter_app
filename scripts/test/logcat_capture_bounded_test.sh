#!/bin/bash
# The bounded capture streams to the file, stops itself after the given seconds, and refuses unknown serials.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/adb" <<'FAKE'
#!/bin/bash
while true; do echo "10-16 12:00:00.000 I/flutter: line"; sleep 0.1; done
FAKE
chmod +x "$TMP/adb"
fail=0
start=$(date +%s)
PATH="$TMP:$PATH" bash "$REPO/docker-ws/logcat_capture_bounded.sh" emulator-5554 "$TMP/out.log" 2
elapsed=$(( $(date +%s) - start ))
lines=$(grep -c "I/flutter" "$TMP/out.log" 2>/dev/null || echo 0)
[ "$elapsed" -le 4 ] || { echo "FAIL: did not stop in time ($elapsed s)"; fail=1; }
[ "$lines" -ge 5 ] || { echo "FAIL: too few streamed lines ($lines)"; fail=1; }
grep -q "^capture ended" "$TMP/out.log" 2>/dev/null || { echo "FAIL: no end marker"; fail=1; }
sleep 1; pgrep -f "$TMP/adb" >/dev/null && { echo "FAIL: fake adb still running"; fail=1; }
PATH="$TMP:$PATH" bash "$REPO/docker-ws/logcat_capture_bounded.sh" SOMEPHONE "$TMP/x.log" 2 >/dev/null 2>&1
[ $? -eq 2 ] || { echo "FAIL: unknown serial not refused"; fail=1; }
[ $fail -eq 0 ] && echo "PASS 5/5" || exit 1
