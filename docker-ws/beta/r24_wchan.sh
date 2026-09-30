#!/bin/bash
# Where the stuck transcoder thread waits (kernel wait channel via run-as, debug build) + which codecs it uses.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); P=$($ADB shell pidof $PKG | tr -d '\r')
TID=$($ADB shell ps -T -p $P | grep TranscoderThrea | awk '{print $2}' | head -1 | tr -d '\r')
echo "app $P transcoder tid $TID"
for f in wchan syscall status; do echo "--- /proc/$P/task/$TID/$f"; $ADB shell run-as $PKG cat /proc/$P/task/$TID/$f 2>&1 | head -12; done
echo "--- codec components allocated by the app"
grep -E " $P .*(allocate\(|CCodec: allocate|Created component|component name|c2\.[a-z0-9.]+\.(encoder|decoder))" "$RUN/android_logcat_live.txt" | grep -oE "c2\.[a-zA-Z0-9._]+" | sort | uniq -c
echo "--- codec process lines (not the app) near the last transcoder frame"
LAST=$(grep -E " $P .*FrameDropper: RENDERING" "$RUN/android_logcat_live.txt" | tail -1 | awk '{print $2}')
echo "last RENDERING at $LAST"
awk -v t="$LAST" '($2 >= t)' "$RUN/android_logcat_live.txt" | grep -v " $P " | grep -iE "c2|codec|avc|h264|BufferQueue|GraphicBuffer|InputSurface|bufferpool|gralloc|gfxstream|goldfish" | head -20 | cut -c1-220
