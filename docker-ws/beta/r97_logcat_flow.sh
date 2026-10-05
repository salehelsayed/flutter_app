#!/bin/bash
# Read-only: [FLOW] lines (and FCM/inbox errors) from one Android device's logcat buffer, filtered by a regex.
#   r97_logcat_flow.sh <serial> <regex> [max-lines]
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
S=$1; R=$2; N=${3:-80}
adb -s "$S" logcat -d -v time 2>/dev/null | grep -E "$R" | tail -"$N" | cut -c1-330
