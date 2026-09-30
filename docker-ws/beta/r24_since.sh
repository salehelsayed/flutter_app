#!/bin/bash
# Read-only: app log lines about a failed video start since "<MM-DD HH:MM:SS>" (the live logcat on the Mac).
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
awk -v s="$1" '($1 " " substr($2,1,8)) >= s' "$RUN/android_logcat_live.txt" \
  | grep -E "Already have a compression|VideoCompress|CONV_FL_[A-Z_]*(ERROR|FAIL)|PICK|Bad state" | grep -v Maestro | head -8 | cut -c1-330
