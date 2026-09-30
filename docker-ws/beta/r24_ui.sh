#!/bin/bash
# Pixel UI tree via uiautomator (fast); prints the nodes about video processing / retry / snackbar.
# Usage: r24_ui.sh <label>
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); L=${1:-ui}
$ADB shell uiautomator dump /sdcard/r24_ui.xml > /dev/null 2>&1
$ADB shell cat /sdcard/r24_ui.xml > "$RUN/ui/pixel_$L.xml" 2>/dev/null
echo "emulator $($ADB shell date '+%H:%M:%S' | tr -d '\r') xml $(wc -c < "$RUN/ui/pixel_$L.xml") bytes"
/usr/bin/python3 - "$RUN/ui/pixel_$L.xml" <<'PY'
import re, sys
s = open(sys.argv[1], errors="replace").read()
for m in re.finditer(r'<node [^>]*>', s):
    n = m.group(0)
    t = (re.search(r' text="([^"]*)"', n) or [None, ""])[1]
    d = (re.search(r' content-desc="([^"]*)"', n) or [None, ""])[1]
    b = (re.search(r' bounds="([^"]*)"', n) or [None, ""])[1]
    c = (re.search(r' clickable="([^"]*)"', n) or [None, ""])[1]
    txt = (t + " | " + d).strip(" |")
    if re.search(r"(?i)retry|video processing|processing|try again|snack|unavailable", txt):
        print("%-28s clickable=%s  %s" % (b, c, txt.replace("&#10;", " / ")[:140]))
PY
