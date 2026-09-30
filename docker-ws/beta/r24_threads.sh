#!/bin/bash
# The app's threads that look like video transcoding / codec work (is the stuck transcode still alive?).
. "$(dirname "$0")/beta_env.sh"
P=$($ADB shell pidof $PKG | tr -d '\r')
echo "emulator $($ADB shell date '+%H:%M:%S' | tr -d '\r') app pid $P threads $($ADB shell ps -T -p $P | wc -l | tr -d ' ')"
$ADB shell ps -T -o TID,STAT,WCHAN,TIME,CMD -p $P 2>/dev/null | grep -iE "transc|codec|media|video|pool|thread-|Async|Executor" | head -25
echo "--- codec services"
$ADB shell dumpsys media.codec 2>/dev/null | grep -iE "component|codec|instances|owner" | head -8
