#!/bin/bash
# Read-only: the Pixel's lock-screen settings and current keyguard state.
. "$(dirname "$0")/beta_env.sh"
echo "locksettings get-disabled: $($ADB shell locksettings get-disabled 2>&1 | tr -d '\r')"
echo "secure lockscreen.disabled: $($ADB shell settings get secure lockscreen.disabled | tr -d '\r')  lock_screen_lock_after_timeout: $($ADB shell settings get secure lock_screen_lock_after_timeout | tr -d '\r')  power_button_instantly_locks: $($ADB shell settings get secure lockscreen.power_button_instantly_locks | tr -d '\r')"
echo "power: $($ADB shell dumpsys power | grep -m1 -oE 'mWakefulness=[A-Za-z]+' | tr -d '\r')"
$ADB shell dumpsys window | grep -iE 'keyguard|Lockscreen' | head -12 | tr -d '\r'
$ADB shell dumpsys activity service com.android.systemui/.keyguard.KeyguardService 2>/dev/null | grep -iE 'mShowing|mExternallyEnabled|mNeedToReshowWhenReenabled|mOccluded|mDeviceInteractive|mGoingToSleep|mPendingLock|mDelayedShowingSequence|mLockLater' | head -12 | tr -d '\r'
