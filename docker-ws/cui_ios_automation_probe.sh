#!/bin/bash
# One cheap UI-test selector on the iPhone 11 to check that UI automation mode can start.
#   host-run bash docker-ws/cui_ios_automation_probe.sh <evidence-dir-relative-to-worktree> <label>
W=/Volumes/CrucialX9/flutter_app/build/wt-cui-b376
EV="$W/$1"; mkdir -p "$EV"; L="$2"
X="$(ls "$W"/build/sims/prepared/ios.device.production.bundle/TestProducts/*.xctestrun | head -1)"
R="$EV/probe-$L.xcresult"; rm -rf "$R"
{ echo "start $(date -u +%FT%TZ)"
  /usr/bin/xcrun xcodebuild test-without-building -xctestrun "$X" -destination id=00008030-001A6D2801BB802E \
    -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath "$R" \
    -only-testing:RunnerUITests/NotificationTapUITests/testAirplaneToggleStateDecoderContract
  rc=$?; echo "exit=$rc end=$(date -u +%FT%TZ)"; exit $rc; } > "$EV/probe-$L.log" 2>&1
