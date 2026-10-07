#!/bin/bash
# Repair tool links broken by the 2026-10-06 deletion of .codex-test-logs/all-tests-y227gs8x (detached; log: repair_links.out).
if [ -z "${RL_DETACHED:-}" ]; then RL_DETACHED=1 nohup bash "$0" >/dev/null 2>&1 & echo "started detached (pid $!)"; exit 0; fi
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/repair_links.out
{
S=$HOME/development/flutter-3.47.2; MD=/Volumes/CrucialX9/mac-development
A=$MD/flutter-3.47.2-engine-artifacts; mkdir -p "$A"
rm "$S/bin/cache/artifacts" && ln -s "$A" "$S/bin/cache/artifacts" && echo "flutter artifacts -> $A"
rm -f "$HOME/Library/Developer/Xcode/iOS DeviceSupport/iPhone14,5 26.5 (23F77)" && echo "removed broken iPhone14,5 DeviceSupport link"
rm -f "$HOME/Library/Developer/Xcode/DerivedData/Runner-bbonzqbmiscotnephxgpuzbtzrhe" && echo "removed broken DerivedData link"
mkdir -p "$MD/huggingface-cache"; rm -f "$HOME/.cache/huggingface" && ln -s "$MD/huggingface-cache" "$HOME/.cache/huggingface" && echo "huggingface -> $MD/huggingface-cache"
# Force a fresh artifact download: the stamps still claim the old artifacts are present.
rm -f "$S/bin/cache/"*.stamp
export PATH="$S/bin:$PATH"
echo "precache start $(date -u +%T)"
flutter precache --android --ios --macos 2>&1 | tail -15
echo "precache rc=$? $(date -u +%T)"
flutter --version 2>&1 | head -2
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next && timeout 120 flutter devices --machine 2>&1 | head -c 300; echo
echo "end"
} > "$OUT" 2>&1
