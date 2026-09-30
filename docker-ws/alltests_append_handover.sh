#!/bin/bash
# Append the session handover section to the run root HANDOVER.md (backup first).
run=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run
cp "$run/HANDOVER.md" "$run/HANDOVER.before-claude-20260926.md"
cat /Volumes/CrucialX9/flutter_app/docker-ws/alltests_handover_20260926.md >> "$run/HANDOVER.md"
wc -l "$run/HANDOVER.md"; tail -3 "$run/HANDOVER.md"
