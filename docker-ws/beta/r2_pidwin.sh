#!/bin/bash
# Read-only: W/E/F lines of one pid (default: the app) in a window, minus codec config dumps.
# Usage: r2_pidwin.sh <from> <to> [pid] [max]
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); L="$RUN/android_logcat_live.txt"
P=${3:-$($ADB shell pidof $PKG | tr -d '\r')}
awk -v a="$1" -v b="$2" -v p="$P" 'substr($2,1,8)>=a && substr($2,1,8)<=b && $3==p && ($5=="W"||$5=="E"||$5=="F")' "$L" \
  | grep -vE "CCodecConfig|MediaCodecList|PEER_PING|remoteIce" | cut -c1-230 | head -${4:-60}
echo "--- codec / transcoder info lines (last 25)"
awk -v a="$1" -v b="$2" -v p="$P" 'substr($2,1,8)>=a && substr($2,1,8)<=b && $3==p' "$L" \
  | grep -E " (CCodec|MediaCodec|CCodecBufferChannel|MediaMuxer|MPEG4Writer|VideoCompress[A-Za-z]*|Transcoder[A-Za-z]*|LightCompressor|MediaExtractor|NdkMediaCodec|AVCEncoder|C2SoftAvcEnc)[A-Za-z]* *:" \
  | grep -v CCodecConfig | tail -25 | cut -c1-220
