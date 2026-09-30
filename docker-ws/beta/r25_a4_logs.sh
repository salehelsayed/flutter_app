#!/bin/bash
# How did A4's transcode end? App-process lines 19:14:40-19:22 (emulator time) about the transcoder / errors.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); L="$RUN/android_logcat_live.txt"
P=$(awk '($2 >= "19:14:40") && / flutter : \[FLOW\]/ {print $3}' "$L" | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
echo "app pid $P"
awk -v p="$P" '($2 >= "19:14:40" && $2 <= "19:22:30") && $3 == p' "$L" > /tmp/r25_a4_win.txt
echo "--- transcoder/codec lines (tags tally)"; grep -v " flutter : " /tmp/r25_a4_win.txt | awk '{print $6}' | sort | uniq -c | sort -rn | head -12
echo "--- errors/warnings from the transcoder or codecs"; grep -v " flutter : " /tmp/r25_a4_win.txt | grep -E " [EW] " | grep -iE "transcod|codec|muxer|mediacodec|pipeline|interpol|timestamp|exception|error" | head -15 | cut -c1-230
echo "--- last 12 transcoder lines"; grep -E "Transcod|Pipeline|Encoder|Decoder|Muxer|DataSink|Codecs" /tmp/r25_a4_win.txt | tail -12 | cut -c1-230
echo "--- app video events"; grep -oE '"event":"[A-Z_]*(VIDEO|PICK|MEDIA_PROC|ATTACH)[A-Z_]*"[^}]*' /tmp/r25_a4_win.txt | sort | uniq -c | head -10 | cut -c1-230
