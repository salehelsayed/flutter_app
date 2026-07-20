#!/bin/bash
# Reset the user-level CoreDevice stack: kill lingering devicectl calls and the
# user-owned CoreDeviceService / remotepairingd XPC daemons (launchd respawns
# them on demand with fresh tunnel state). Fixes a zombied per-device tunnel
# that reports "connected" while every RPC hangs (iPhone 13, 2026-07-20).
pkill -f 'devicectl device' && echo "killed lingering devicectl calls" || echo "no lingering devicectl calls"
pkill -x CoreDeviceService && echo "killed CoreDeviceService" || echo "CoreDeviceService not running"
if [ "${RESET_REMOTEPAIRING:-0}" = "1" ]; then
  pkill -x remotepairingd && echo "killed remotepairingd" || echo "remotepairingd not running"
fi
exit 0
