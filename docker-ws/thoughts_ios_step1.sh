#!/bin/bash
# Thoughts branch step 1 (call under with_native_lease.py): iOS simulator debug build (Runner + NotificationService
# extension) for the Hetzner relay, then RunnerTests on a simulator. Writes into the evidence dir.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/thoughts_ios_step1.sh <tree under build/> <evidence dir under repo>
set -uo pipefail
REPO=/Volumes/CrucialX9/flutter_app; W="$REPO/build/${1:?tree}"; E="$REPO/${2:?evidence}"; mkdir -p "$E"
# A clean worktree races [CP] Embed Pods Frameworks ahead of the pod framework targets; build the pods first
# into the same SYMROOT Flutter uses (harness only, no project change).
( cd "$W" && export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" && \
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Pods-Runner -configuration Debug -sdk iphonesimulator \
    SYMROOT="$W/build/ios" build > "$E/pods_prebuild.log" 2>&1; echo "pods_prebuild exit=$?" )
bash "$REPO/docker-ws/build_ios_sim_debug_hetzner_wt.sh" "$W" > "$E/ios_build.log" 2>&1
B=$(grep -oE 'build exit=[0-9]+' "$E/ios_build.log" | tail -1); echo "$B"
[ "$B" = "build exit=0" ] || { echo "STEP1 BUILD FAILED"; exit 3; }
cd "$W" && export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
bash scripts/test/run_runner_tests_321.sh RunnerTests > "$E/runner_tests.log" 2>&1; rc=$?
echo "runner_tests exit=$rc"; tail -6 "$E/runner_tests.log"
exit $rc
