#!/bin/bash
# Read-only: flutter/xcode/dart build processes with parent pid, cpu and elapsed time.
ps -axo pid,ppid,etime,pcpu,command | grep -E "flutter_tools|xcodebuild|xcbuild|XCBBuildService|clang|swift-frontend|dart.*sims|build_ios|hooks_runner|native_assets" \
  | grep -v grep | grep -v appium | cut -c1-220 | head -30
