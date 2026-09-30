#!/bin/bash
# Transcoder state on the Pixel: last transcoder log lines + last progress + app threads.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); P=$($ADB shell pidof $PKG | tr -d '\r')
echo "emulator $($ADB shell date '+%H:%M:%S' | tr -d '\r') app pid $P"
grep -E " $P +[0-9]+ [VDIWE] (TranscodeEngine|Pipeline|Decoder\(|Encoder\(|FrameDrawer|FrameDropper|DefaultDataSource|VideoRenderer)" "$RUN/android_logcat_live.txt" | tail -6 | cut -c1-200
grep -E " $P .*got progress" "$RUN/android_logcat_live.txt" | tail -1 | cut -c1-160
