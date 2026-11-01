#!/bin/bash
# A1 proof (Kayan m-d9d9131b): Hetzner Android APK from <sha> in build/wt-translate-129 (checks, then the APK), plus a copy of
# Codex's native-proof-steps.md into the evidence dir. Run under the native-build lease.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/a1_apk_build.sh <sha> <evidence dir under repo> <build-number>
set -uo pipefail
SHA=${1:?sha}; EV=${2:?evidence}; BN=${3:?bn}; REPO=/Volumes/CrucialX9/flutter_app; E="$REPO/$EV"; mkdir -p "$E"
cp /Users/I560101/.codex/worktrees/a1-migration-discovery-queue-20261101/.codex-test-logs/a1-20261101/native-proof-steps.md "$E/native-proof-steps.md" 2>/dev/null && echo "steps copied" || echo "steps NOT found"
bash "$REPO/docker-ws/wt129_checkout.sh" "$SHA"
bash "$REPO/docker-ws/wt_checks.sh" wt-translate-129 > "$E/wt_checks.log" 2>&1; echo "wt_checks exit=$?"; grep -E "errors=|warnings=" "$E/wt_checks.log"
bash "$REPO/docker-ws/translate129_pixel_apk.sh" "$EV/apk" "$BN" > "$E/apk.log" 2>&1; echo "apk exit=$?"; grep -E "^APK|libapp" "$E/apk.log"
echo "done $(date +%H:%M:%S)"
