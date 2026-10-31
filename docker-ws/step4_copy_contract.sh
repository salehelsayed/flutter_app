#!/bin/bash
# Read-only: copy Codex-UI's Step 4 handoff and acceptance contract from the UI-Update worktree into an evidence dir.
#   host-run bash docker-ws/step4_copy_contract.sh <evidence-dir-relative-to-main-checkout> [space-separated relative files]
U=/Volumes/CrucialX9/flutter_app-ui-update/.codex-test-logs/plan407-step4
D=/Volumes/CrucialX9/flutter_app/$1; mkdir -p "$D"
for f in ${2:-implementation/handoff.md device-acceptance-contract.json}; do
  [ -f "$U/$f" ] && cp "$U/$f" "$D/$(basename "$f")" && echo "copied $f $(wc -c < "$U/$f")" || echo "missing $f"
done
ls "$U" | head -30
