#!/bin/bash
# Read-only: UWB framework state and HAL service state on emulator-5556, emulator uptime.
. "$(dirname "$0")/beta_env.sh"
$ADB shell 'cmd uwb get-uwb-state 2>&1 | head -2; settings get global uwb_enabled; getprop init.svc.vendor.uwb_hal; getprop | grep -i uwb | head -5; uptime; pm list packages -d | grep -i nfc'
