#!/bin/bash
# Build the simulator app WITH local signing (entitlements embedded), check its App Group entitlement. Detached.
if [ -z "${R87_DETACHED:-}" ]; then R87_DETACHED=1 nohup bash "$0" "$@" >/dev/null 2>&1 & echo "started"; exit 0; fi
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next; cd "$W"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:$PATH"
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/r87.out
{ echo "start $(date -u +%T)"
  flutter build ios --simulator --debug --target=lib/main.dart --dart-define=E2E_TEST_MODE=true \
    --dart-define=SIMS_BUILD_PROFILE_ID=ios.simulator.app > /tmp/r87_build.log 2>&1 < /dev/null
  echo "build rc=$? $(date -u +%T)"; tail -3 /tmp/r87_build.log
  echo "--- entitlements:"; codesign -d --entitlements - build/ios/iphonesimulator/Runner.app 2>&1 | grep -i -A3 "application-groups" | head -6
  echo "end"
} > "$OUT" 2>&1
# The flutter tool can leave idle helpers holding the output: clear them.
bash /Volumes/CrucialX9/flutter_app/docker-ws/beta/r78_kill_build_orphans.sh >> "$OUT" 2>&1
