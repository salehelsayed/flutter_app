#!/bin/bash
# Read-only: the app's log lines (flutter + app native tags) in a time window of the live logcat,
# excluding the chatty ping/ICE/group-drain noise. Usage: r2_window.sh <from> <to> [grep regex] [max]
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); L="$RUN/android_logcat_live.txt"
awk -v a="$1" -v b="$2" 'substr($2,1,8)>=a && substr($2,1,8)<=b' "$L" \
  | grep -E " (flutter|Mknoon[A-Za-z]*|GoLog|VideoCompress[A-Za-z]*|MediaCodec[A-Za-z]*|CCodec[A-Za-z]*|Codec2[A-Za-z]*|LightCompressor|Transcoder|AndroidRuntime|ExoPlayer[A-Za-z]*) *:" \
  | grep -vE "PEER_PING|remoteIce|iceCandidate|GROUP_DRAIN|GROUP_FL_BRIDGE_INBOX|INBOX_STAGING_DB_LOAD|RETRY_FAILED_GROUP|GO_BRIDGE_SEND|BRIDGE_CALL_TIMING|PRESENCE|P2P_PUSH_EVENT" \
  | grep -E "${3:-.}" | cut -c1-260 | head -${4:-80}
