#!/bin/bash
# Run only the payload network-restore selector on the iPhone 11 (turns airplane mode off).
#   host-run bash docker-ws/cui_ios_automation_probe.sh <evidence-dir-relative-to-worktree> <label>
W=/Volumes/CrucialX9/flutter_app/build/wt-cui-b376
EV="$W/$1"; mkdir -p "$EV"; L="$2"
X="$(ls "$W"/build/sims/prepared/ios.device.production.bundle/TestProducts/*.xctestrun | head -1)"
R="$EV/restore-$L.xcresult"; rm -rf "$R"
{ echo "start $(date -u +%FT%TZ)"
  /usr/bin/xcrun xcodebuild test-without-building -xctestrun "$X" -destination id=00008030-001A6D2801BB802E \
    -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath "$R" \
    -only-testing:RunnerUITests/NotificationTapUITests/testRestorePayloadFastPathNetwork
  rc=$?; echo "exit=$rc end=$(date -u +%FT%TZ)"; exit $rc; } > "$EV/restore-$L.log" 2>&1
