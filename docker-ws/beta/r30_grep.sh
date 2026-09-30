#!/bin/bash
# Read-only: lines of the current run's Pixel logcat between two emulator times that match an extended regex.
# Usage: r30_grep.sh <HH:MM:SS from> <HH:MM:SS to> <regex> [exclude-regex] [max lines]
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
awk -v a="$1" -v b="$2" '$1 ~ /^[0-9][0-9]-[0-9][0-9]$/ && substr($2,1,8) >= a && substr($2,1,8) <= b' "$RUN/android_logcat_live.txt" \
  | grep -E "$3" | { if [ -n "${4:-}" ]; then grep -vE "$4"; else cat; fi; } \
  | sed -E 's/"ts":"[^"]*","milestone":"[^"]*",//' | cut -c1-240 | head -"${5:-60}"
