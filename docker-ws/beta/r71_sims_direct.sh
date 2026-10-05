#!/bin/bash
# Run one SIMS capability directly in the worktree with the iOS simulator pins, text output, bounded time.
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
export PATH="$HOME/development/flutter-3.47.2/bin:$HOME/.maestro/bin:/opt/homebrew/bin:$PATH"
A=6597ECAD-38EE-49AF-9A08-B1B0CA4BDD76; B=8E31AD68-4DBF-4336-AEBF-18148DC9FA07; C=DBE8C32E-9F19-4593-860A-B41113791D79
export SIMS_IOS_SIMULATOR_A_DEVICE_ID=$A SIMS_IOS_SIMULATOR_B_DEVICE_ID=$B SIMS_IOS_SIMULATOR_C_DEVICE_ID=$C
export SIMS_IOS_DISPOSABLE_SIMULATOR_IDS="$A,$B,$C"
export SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON="{\"ios-simulator-a\":\"$A\",\"ios-simulator-b\":\"$B\",\"ios-simulator-c\":\"$C\"}"
export SIMS_RESERVED_DEVICE_IDS_JSON='[]'
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/r71_sims_direct.out
timeout ${2:-180} dart tool/sims/sims.dart major --only "$1" --format text > "$OUT" 2>&1
echo "rc=$?" >> "$OUT"; tail -25 "$OUT"
