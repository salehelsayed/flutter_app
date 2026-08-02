#!/usr/bin/env bash
# Plan 321: independent USB/OS-level iPhone inventory — bypasses devicectl's
# CoreDevice cache so a physically-connected phone that CoreDevice cannot see
# is still visible (system_profiler + idevice tooling + Finder-level pairing).
set -uo pipefail
echo "=== system_profiler USB (Apple mobile devices) ==="
system_profiler SPUSBDataType 2>/dev/null | grep -A6 -iE 'iPhone|Apple Mobile Device' | head -40
echo
echo "=== idevice_id -l (libimobiledevice, if installed) ==="
if command -v idevice_id >/dev/null 2>&1; then
  idevice_id -l
  for u in $(idevice_id -l); do
    echo "--- $u ---"
    ideviceinfo -u "$u" -k DeviceName 2>/dev/null
    ideviceinfo -u "$u" -k ProductVersion 2>/dev/null
  done
else
  echo "idevice_id not installed"
fi
echo
echo "=== xcrun xctrace list devices ==="
xcrun xctrace list devices 2>/dev/null | head -20
