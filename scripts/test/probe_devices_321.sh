#!/usr/bin/env bash
# Plan 321 TC-321-12: device availability probe for the staged rollout smoke.
set -uo pipefail
echo "=== adb devices ==="
adb devices -l 2>&1 | head -8
echo "=== battery/screen state of first physical device (if any) ==="
SERIAL=$(adb devices | awk 'NR>1 && $2=="device" {print $1}' | head -1)
if [ -n "${SERIAL:-}" ]; then
  echo "serial: $SERIAL"
  adb -s "$SERIAL" shell getprop ro.product.model 2>/dev/null
  adb -s "$SERIAL" shell dumpsys battery 2>/dev/null | grep -E 'level' | head -1
else
  echo "NO_ANDROID_DEVICE"
fi
