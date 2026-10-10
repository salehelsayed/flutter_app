#!/bin/bash
# Commits the remaining working tree in themed groups (2026-10-10).
set -eu
cd /Volumes/CrucialX9/flutter_app
M=docker-ws/.commit_msgs
c() { msg="$1"; shift; git add -- "$@"; git commit -q -F "$M/$msg" --only -- "$@"; git log --oneline -1; }
c 1.txt lib/features/call/infrastructure/call_signaling_runtime.dart lib/features/call/application/call_coordinator.dart lib/features/call/application/handle_incoming_call_signal.dart test/features/call/infrastructure/call_signaling_runtime_test.dart tool/testing/selection.json
c 2.txt ios/Runner/MknoonCallKitController.swift ios/RunnerTests/MknoonCallKitLifecycleTests.swift ios/RunnerTests/MknoonCallNativeBridgeTests.swift
c 3.txt ios/Runner/MknoonAppDiagnostics.swift lib/core/diagnostics/app_diagnostics.dart test/core/diagnostics/app_diagnostics_test.dart docker-ws/typecheck_app_diagnostics_swift.sh
c 4.txt lib/features/orbit/presentation/screens/orbit_screen.dart lib/features/orbit/presentation/screens/orbit_wired.dart test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart test/features/orbit/presentation/screens/orbit_settings_entry_test.dart test/features/feed/presentation/screens/feed_wired_test.dart
c 5.txt docs/testing/TESTING.md docs/release/ios-builds.md
git add -A
git commit -q -F "$M/6.txt"
git log --oneline -1
echo "=== status ==="
git status --short | head
echo "STATUS_END"
