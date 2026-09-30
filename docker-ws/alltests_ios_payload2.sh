#!/bin/bash
# Read-only: list iOS payload capture files and grep log files for failure lines.
d=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/notifications.ios_payload_fast_path/capture-1790387538756897-75720
find "$d" -type f | sed "s|$d/||" | head -30
grep -rhE "request_not_staged|failureCode|Exceeded|timed out|timeout|error|Error|failed" "$d" --include='*.log' --include='*.txt' 2>/dev/null | cut -c1-220 | sort | uniq -c | sort -rn | head -15
