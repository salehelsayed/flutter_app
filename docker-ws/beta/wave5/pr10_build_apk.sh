#!/bin/bash
# PR 10 device proof: debug APK of main + PR 10 (merged, not committed) in the
# wave3-next worktree. Self-detaches; restores the worktree after.
set -u
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
OUT=$W/pr10_build.log
if [ -z "${PR10_BUILD_DETACHED:-}" ]; then
  PR10_BUILD_DETACHED=1 nohup bash "$0" "$@" >"$OUT" 2>&1 &
  echo "detached pid $! log $OUT"; exit 0
fi
WT=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
cd "$WT" || exit 1
git checkout -q --detach main && git merge -q --no-commit --no-ff origin/fix/group-info-leave-confirmation && echo "merged onto $(git rev-parse --short HEAD)"
date
"$HOME/development/flutter-3.47.2/bin/flutter" build apk --debug --target-platform=android-arm64 -t lib/main.dart \
  --dart-define-from-file=tool/build/voice_call_release_defines.json \
  --dart-define=E2E_TEST_MODE=true --dart-define=PRODUCTION_FCM=true \
  --android-project-arg=enableAndroidNativeCalls=true --build-name="1.0.0-pr10" 2>&1 | tail -3
echo "build exit=${PIPESTATUS[0]}"; date
cp build/app/outputs/flutter-apk/app-debug.apk $W/voice/app.apk && ls -la $W/voice/app.apk
git merge --abort 2>/dev/null; git reset -q --hard; git checkout -q wave3-next && echo "restored $(git rev-parse --abbrev-ref HEAD) clean=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
