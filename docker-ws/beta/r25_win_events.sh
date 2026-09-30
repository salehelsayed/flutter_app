#!/bin/bash
# App events in a window of the current run's Pixel log. Usage: r25_win_events.sh <from HH:MM:SS> <to HH:MM:SS>
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); L="$RUN/android_logcat_live.txt"
awk -v a="$1" -v b="$2" '($2 >= a && $2 <= b)' "$L" | grep -oE '"event":"CONV_FL_[A-Z_]*"[^}]*|VideoProcessing[A-Za-z]*Exception|Bad state[^"]*' | sort | uniq -c | head -15 | cut -c1-220
echo "--- transcoder threads started in the window"
awk -v a="$1" -v b="$2" '($2 >= a && $2 <= b)' "$L" | grep -oE "Creating OpenGL context on Thread\[TranscoderThread #[0-9]+" | sort | uniq -c
