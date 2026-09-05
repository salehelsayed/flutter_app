#!/bin/bash
# Show whether the phone log captures of start_phone_log_captures.sh are still
# alive and growing. Usage (Mac or host-run): docker-ws/capture_status.sh <CAPTURE_DIR>
DIR="${1:?capture dir}"
echo "now: $(date -u +%H:%M:%SZ)"
echo "--- capture processes"
pgrep -fl "idevicesyslog|adb -s .* logcat" | grep -v pgrep
echo "--- files"
ls -la "$DIR" | grep -v '^total'
for f in "$DIR"/*.txt; do
  printf '%s: last line at: ' "$(basename "$f")"; tail -1 "$f" | cut -c1-40
done
