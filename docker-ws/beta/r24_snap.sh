#!/bin/bash
# Pixel screenshot into the current run's extra/ folder + the app's recent video/transcode log lines.
# Usage: r24_snap.sh <label>
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); L=${1:-snap}
$ADB exec-out screencap -p > "$RUN/extra/pixel_$L.png"
echo "emulator $($ADB shell date '+%H:%M:%S' | tr -d '\r') shot $(stat -f %z "$RUN/extra/pixel_$L.png") bytes"
P=$($ADB shell pidof $PKG | tr -d '\r'); echo "app pid $P"
grep -E " $P +[0-9]+ [VDIWEF] " "$RUN/android_logcat_live.txt" | grep -iE "transcod|compress|codec|video|mp4|muxer|extractor|FLOW.*(MEDIA|VIDEO|PROCESS)" | grep -v Maestro | tail -8 | cut -c1-220
