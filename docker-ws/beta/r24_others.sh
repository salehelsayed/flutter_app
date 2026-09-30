#!/bin/bash
# Read-only: force-stops / reinstalls / Appium interactions with the app in the current run's Pixel logcat.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
grep -E "Force stopping com\.mknoon\.app|killDueToPackageUpdate|io\.appium.* -> .*com\.mknoon\.app|adbd service requested .*com\.mknoon" "$RUN/android_logcat_live.txt" | cut -c1-200 | head -10
