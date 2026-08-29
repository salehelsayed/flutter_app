#!/bin/bash
# Read-only USB/device probe for the phone fleet. Answers "is the phone actually
# on the bus?" — distinct from "does adb/devicectl see it?", because the iPhones
# stay reachable over the CoreDevice network tunnel even with USB down.
set -uo pipefail
echo "=== IOKit USB device count ==="
ioreg -p IOUSB -w0 2>/dev/null | grep -c '+-o' || echo 0
echo "=== IOKit USB names ==="
ioreg -p IOUSB -w0 2>/dev/null | grep '+-o' | sed 's/^[ |]*//' | head -20
echo "=== adb ==="
adb devices -l 2>&1 | tail -6
echo "=== idevice_id -l (USB-attached iPhones) ==="
idevice_id -l 2>&1 | head -5
echo "=== devicectl ==="
xcrun devicectl list devices 2>&1 | tail -6
