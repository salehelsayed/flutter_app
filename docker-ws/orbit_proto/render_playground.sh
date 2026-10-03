#!/bin/bash
# Headless screenshot of the depth playground on the Mac (for checking it).
# Uses a throwaway profile so it never touches the user's running Chrome.
cd "$(dirname "$0")/../.."
OUT=docker-ws/orbit_proto
pkill -f "depth_playground.html" 2>/dev/null
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo NO_CHROME; exit 1; }
PROFILE=$(mktemp -d /tmp/pgprofile.XXXX)
FILE="file://$(pwd)/prototypes/orbit_depth/depth_playground.html"
shot() {
  "$CHROME" --headless=new --user-data-dir="$PROFILE" --no-first-run --disable-gpu \
    --hide-scrollbars --window-size="$1" --timeout=2500 \
    --screenshot="$OUT/$2" "$FILE" >>"$OUT/pg_console.log" 2>&1 &
  local pid=$!
  for i in $(seq 1 20); do sleep 1; kill -0 $pid 2>/dev/null || break; done
  kill $pid 2>/dev/null
}
: > "$OUT/pg_console.log"
rm -f "$OUT"/pg_*.png
shot 1280,900 pg_desktop.png
shot 390,844 pg_mobile.png
rm -rf "$PROFILE"
ls -la "$OUT"/pg_*.png 2>&1
grep -iE "uncaught|referenceerror|typeerror|syntaxerror" "$OUT/pg_console.log" | head -5
