#!/bin/bash
# Read-only: locate physical-idevicesyslog.log files modified in the last day (paths + sizes only).
for r in /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run "${TMPDIR:-/tmp}"; do
  find "$r" -name 'physical-idevicesyslog.log' -mtime -1 2>/dev/null | xargs ls -l 2>/dev/null
done
