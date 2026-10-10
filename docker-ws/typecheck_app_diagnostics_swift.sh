#!/bin/bash
# Type-check the app diagnostics Swift files for iOS without a full Xcode build.
# Run on the Mac: host-run bash docker-ws/typecheck_app_diagnostics_swift.sh
set -eu
cd "$(dirname "$0")/.."
stub="$(mktemp -d)/stub.swift"
# GoBridge.swift's registry logs through this AppDelegate function.
printf 'func logGroupMediaNativeProof(_ message: String) {}\n' > "$stub"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos swiftc -typecheck -swift-version 5 \
  -sdk "$sdk" -target arm64-apple-ios16.0 \
  ios/Runner/MknoonAppDiagnostics.swift \
  ios/Runner/MknoonAppDiagnosticSchema.swift \
  ios/NotificationService/MknoonNseAppDiagnostics.swift \
  ios/Runner/GoBridge.swift \
  "$stub"
echo "TYPECHECK_OK"
