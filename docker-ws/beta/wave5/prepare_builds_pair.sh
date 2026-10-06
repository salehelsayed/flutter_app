#!/bin/bash
# Wave 5 step 3: build-only SIMS (--prepare-builds --list: no device preparation, no tests) for one capability
# per replacement build profile, twice on the unchanged wave3-next worktree. Pass 1 may build; pass 2 must
# report zero builds and only attested cache hits. Detached. Log + reports: docker-ws/beta/wave5/builds/
if [ -z "${PBP_DETACHED:-}" ]; then
  PBP_DETACHED=1 nohup bash "$0" "$@" >/dev/null 2>&1 &
  echo "started detached (pid $!)"; exit 0
fi
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/builds
mkdir -p "$OUT"
cd "$W" || exit 1
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
SIGNING=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave4/private/ios-signing-attestation.json
[ -f "$SIGNING" ] && export SIMS_IOS_NOTIFICATION_STAGING_MANIFEST="$SIGNING"
export PATH="$HOME/development/flutter-3.47.2/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"
CAPS="production.notification_open production.startup_resume_performance production.group_catalog.private_partition_readd_heal production.shared_xctest"
{
  echo "start $(date -u +%T) $(git log -1 --format=%h) status_lines=$(git status --short | wc -l | tr -d ' ')"
  for pass in 1 2; do
    for cap in $CAPS; do
      t0=$(date +%s)
      SIMS_REPORT_PATH="$OUT/pass$pass-$cap.json" dart run tool/sims/sims.dart full --only "$cap" --prepare-builds --list \
        > "$OUT/pass$pass-$cap.log" 2>&1
      rc=$?
      echo "pass $pass $cap rc=$rc $(( $(date +%s) - t0 ))s $(grep -m1 'Builds: actual' "$OUT/pass$pass-$cap.log")"
    done
  done
  echo "end $(date -u +%T) status_lines=$(git status --short | wc -l | tr -d ' ')"
} > "$OUT/run.log" 2>&1
