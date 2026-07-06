#!/usr/bin/env bash
#
# 217 A18 / §B4 — CV-14 wake-token binary-freshness gate.
#
# `params.WakeToken` at go-mknoon/bridge/bridge.go changes NO exported header
# symbol, so a stale gomobile rebuild would silently drop the sender-attached
# wake-token with ZERO failing functional test. This gate asserts the checked-in
# binaries carry the wake-token symbols, converting that silent-failure path into
# a hard gate. Both symbols must be present in every shipped binary:
#   - InboxStoreDetailedWithWakeToken  (the send-side attach seam)
#   - RegisterWakeTokens               (the recipient register seam)
#
# Exits 0 when all present; non-zero (with the missing symbol/binary) otherwise.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

readonly REQUIRED_SYMBOLS=(
  "InboxStoreDetailedWithWakeToken"
  "RegisterWakeTokens"
)

readonly IOS_DEVICE="ios/Runner/GoMknoon.xcframework/ios-arm64/GoMknoon.framework/GoMknoon"
readonly IOS_SIM="ios/Runner/GoMknoon.xcframework/ios-arm64_x86_64-simulator/GoMknoon.framework/GoMknoon"
readonly MACOS="macos/Runner/GoMknoon.xcframework/macos-arm64_x86_64/GoMknoon.framework/Versions/A/GoMknoon"
readonly ANDROID_AAR="android/app/libs/GoMknoon.aar"
readonly ANDROID_JNI="jni/arm64-v8a/libgojni.so"

failures=0

fail() {
  printf '  ✗ %s\n' "$1" >&2
  failures=$((failures + 1))
}

# Assert both symbols are present in a Mach-O / ELF binary via `strings`.
check_binary() {
  local label="$1" path="$2"
  if [ ! -f "$path" ]; then
    fail "$label: binary not found at $path"
    return
  fi
  local dump
  dump="$(strings -a "$path")"
  for sym in "${REQUIRED_SYMBOLS[@]}"; do
    if ! grep -q "$sym" <<<"$dump"; then
      fail "$label: MISSING symbol '$sym' (stale gomobile build — rebuild before shipping)"
    fi
  done
  printf '  ✓ %s\n' "$label"
}

# Android: the symbols live inside libgojni.so packed in the AAR (a zip).
check_android_aar() {
  local label="Android AAR ($ANDROID_JNI)"
  if [ ! -f "$ANDROID_AAR" ]; then
    fail "$label: AAR not found at $ANDROID_AAR"
    return
  fi
  local dump
  dump="$(unzip -p "$ANDROID_AAR" "$ANDROID_JNI" 2>/dev/null | strings -a || true)"
  if [ -z "$dump" ]; then
    fail "$label: could not extract $ANDROID_JNI from the AAR"
    return
  fi
  for sym in "${REQUIRED_SYMBOLS[@]}"; do
    if ! grep -q "$sym" <<<"$dump"; then
      fail "$label: MISSING symbol '$sym' (stale gomobile build — rebuild before shipping)"
    fi
  done
  printf '  ✓ %s\n' "$label"
}

printf 'CV-14 wake-token binary-freshness gate\n'
check_binary "iOS device (ios-arm64)" "$IOS_DEVICE"
check_binary "iOS simulator" "$IOS_SIM"
check_binary "macOS" "$MACOS"
check_android_aar

if [ "$failures" -ne 0 ]; then
  printf '\nFAILED: %d wake-token symbol check(s) missing — the shipped binaries are stale.\n' "$failures" >&2
  exit 1
fi

printf '\nOK: all shipped binaries carry the CV-14 wake-token symbols.\n'
