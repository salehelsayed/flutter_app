#!/bin/bash
# Run one python test file on the Mac in the given directory; print failures only.
cd "$1" || exit 2
python3 "$2" 2>&1 | grep -E -B2 -A25 '^(FAIL|ERROR):' | head -120
python3 "$2" 2>&1 | tail -3
