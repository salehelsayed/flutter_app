#!/bin/bash
# Read-only: grep the private Appium 4725 log for WDA/xcodebuild status lines.   host-run bash docker-ws/tr129_appium_log_grep.sh
L=/Volumes/CrucialX9/flutter_app/.codex-test-logs/move-terminal-20261024T0029Z/appium4725.log
grep -E "xcodebuild|automation mode|WebDriverAgent|Testing failed|error|Session created|ServerSideError" "$L" | grep -v "RemoteXPC\|socket hang" | tail -15 | cut -c1-600
