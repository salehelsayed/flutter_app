#!/bin/bash
# Read-only: the Pixel's Doze (device idle) state and settings, battery/charging state, and the app's standby bucket.
. "$(dirname "$0")/beta_env.sh"
echo "emulator time: $($ADB shell date '+%H:%M:%S' | tr -d '\r')  power: $($ADB shell dumpsys power | grep -m1 -oE 'mWakefulness=[A-Za-z]+' | tr -d '\r')"
$ADB shell dumpsys deviceidle | grep -E 'mState=|mLightState=|mScreenOn|mCharging|mForceIdle|mDeepEnabled|mLightEnabled|mNextLightIdleDelay|mNextIdleDelay|mCurLightIdleBudget|mMaintenanceStartTime|light_after_inactive_to|light_idle_to|light_max_idle_to|light_idle_maintenance|inactive_to=|sensing_to|locating_to|idle_after_inactive|min_light_maintenance' | tr -d '\r' | sed -E 's/^ +//' | head -30
echo "battery: $($ADB shell dumpsys battery | grep -E 'AC powered|USB powered|status|level' | tr -d '\r' | tr -s ' ' | tr '\n' ' ')"
echo "standby bucket: $($ADB shell am get-standby-bucket $PKG | tr -d '\r')  doze whitelist has app: $($ADB shell dumpsys deviceidle whitelist | grep -c "$PKG")"
