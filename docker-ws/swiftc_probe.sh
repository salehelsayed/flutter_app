#!/bin/bash
# Read-only probe: does swiftc compile a one-line file for the iOS simulator and for macOS?
#   host-run bash docker-ws/swiftc_probe.sh
T=$(mktemp -d); echo 'let x = 1; print(x)' > "$T/p.swift"
xcrun --show-sdk-version --sdk iphonesimulator; xcodebuild -version | head -1
xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk "$(xcrun --show-sdk-path --sdk iphonesimulator)" -c "$T/p.swift" -o "$T/p.o"; echo "sim_exit=$? obj=$(ls "$T/p.o" 2>/dev/null | wc -l | tr -d ' ')"
xcrun swiftc -c "$T/p.swift" -o "$T/m.o"; echo "mac_exit=$? obj=$(ls "$T/m.o" 2>/dev/null | wc -l | tr -d ' ')"
rm -rf "$T"
