#!/bin/bash
# Plan 414: screenshot the iPhone 13 without XCUITest (libimobiledevice / pymobiledevice3).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTF="$ROOT/Test-Flight-Improv/evidence/414/e2e/shots/ios13_${1:-shot}.png"
U=00008110-00184D622289801E
ls /opt/homebrew/bin/idevicescreenshot 2>/dev/null && /opt/homebrew/bin/idevicescreenshot -u $U "$OUTF" && { echo "OK $OUTF"; exit 0; }
command -v pymobiledevice3 && pymobiledevice3 developer dvt screenshot --udid $U "$OUTF" && { echo "OK $OUTF"; exit 0; }
ls ~/.local/bin/pymobiledevice3 2>/dev/null && ~/.local/bin/pymobiledevice3 developer dvt screenshot --udid $U "$OUTF" && echo "OK $OUTF"
