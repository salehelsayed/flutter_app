#!/bin/bash
# Read-only: is another session driving the beta devices? Appium, force-stop and package-update lines for
# com.mknoon.app in the Pixel's logcat over the last N minutes (default 10), Appium WebDriverAgent runners for the
# iPhone 15 simulator, and the installed Android build. My own restart_pixel_app also logs one force-stop.
. "$(dirname "$0")/beta_env.sh"
MIN=${1:-10}
now=$($ADB shell date +%s | tr -d '\r')
since=$($ADB shell date -d "@$(( now - MIN * 60 ))" "'+%m-%d %H:%M:%S.000'" | tr -d '\r')
lines=$($ADB logcat -d -v threadtime -T "$since" 2>/dev/null | grep -E 'appium|Force stopping com\.mknoon\.app|killDueToPackageUpdate')
echo "pixel lines in the last ${MIN} min (since $since): $(printf '%s' "$lines" | grep -c .) (appium $(printf '%s' "$lines" | grep -c appium), force-stop $(printf '%s' "$lines" | grep -c 'Force stopping'), package update $(printf '%s' "$lines" | grep -c killDueToPackageUpdate))"
printf '%s\n' "$lines" | grep . | tail -3 | cut -c1-160
echo "iphone WDA runners: $(ps -axo command | grep -E 'WebDriverAgentRunner|WebDriverAgent' | grep "$UDID" | grep -vc grep)"
echo "installed android: $($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r')"
