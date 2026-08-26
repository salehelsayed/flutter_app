#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/verify_gomobile_bindings.sh [all|ios|macos|android]

Checks that the native platform wrappers only call methods exported by the
generated gomobile artifacts:
- ios/Runner/GoBridge.swift against ios/Runner/GoMknoon.xcframework
- ios/NotificationService/*.swift against ios/Runner/GoMknoonNSE.xcframework
- macos/Runner/MainFlutterWindow.swift against macos/Runner/GoMknoon.xcframework
- android/app/src/main/kotlin/.../GoBridge.kt against android/app/libs/GoMknoon.aar
EOF
}

extract_swift_bridge_calls() {
  awk '!/^[[:space:]]*\/\//' "$repo_root/ios/Runner/GoBridge.swift" \
    | perl -ne 'while (/(Bridge[A-Za-z0-9_]+)\s*\(/g) { print "$1\n" }' \
    | sort -u
}

extract_nse_bridge_calls() {
  awk '!/^[[:space:]]*\/\//' \
    "$repo_root/ios/NotificationService/NotificationPreviewResolver.swift" \
    "$repo_root/ios/NotificationService/NseMailboxWakeCoordinator.swift" \
    | perl -ne 'while (/(Bridge[A-Za-z0-9_]+)\s*\(/g) { print "$1\n" }' \
    | sort -u
}

extract_ios_header_exports() {
  local header="$1"
  sed -nE 's/^FOUNDATION_EXPORT .* (Bridge[A-Za-z0-9_]+)\(.*/\1/p' "$header" | sort -u
}

extract_macos_bridge_calls() {
  awk '!/^[[:space:]]*\/\//' "$repo_root/macos/Runner/MainFlutterWindow.swift" \
    | perl -ne 'while (/(Bridge[A-Za-z0-9_]+)\s*\(/g) { print "$1\n" }' \
    | sort -u
}

extract_kotlin_bridge_calls() {
  local bridge_file
  bridge_file="$(find "$repo_root/android/app/src/main/kotlin" -name 'GoBridge.kt' | head -n 1)"
  if [[ -z "$bridge_file" ]]; then
    echo "Android binding check failed: missing GoBridge.kt under android/app/src/main/kotlin" >&2
    return 1
  fi

  perl -ne 'while (/GoMknoon\.([A-Za-z0-9_]+)\s*\(/g) { print "$1\n" }' \
    "$bridge_file" | sort -u
}

extract_android_aar_exports() {
  local classes_jar="$1"
  javap -classpath "$classes_jar" bridge.Bridge 2>/dev/null \
    | sed -nE 's/^  public static (native )?[^ ]+ ([A-Za-z0-9_]+)\(.*/\2/p' \
    | sort -u
}

check_ios() {
  local header="$repo_root/ios/Runner/GoMknoon.xcframework/ios-arm64_x86_64-simulator/GoMknoon.framework/Headers/Bridge.objc.h"
  local nse_header="$repo_root/ios/Runner/GoMknoonNSE.xcframework/ios-arm64_x86_64-simulator/GoMknoonNSE.framework/Headers/Bridge.objc.h"
  local nse_device_binary="$repo_root/ios/Runner/GoMknoonNSE.xcframework/ios-arm64/GoMknoonNSE.framework/GoMknoonNSE"
  if [[ ! -f "$header" ]]; then
    echo "iOS binding check failed: missing header $header" >&2
    return 1
  fi

  local missing
  missing="$(
    comm -23 \
      <(extract_swift_bridge_calls) \
      <(extract_ios_header_exports "$header")
  )"

  if [[ -n "$missing" ]]; then
    echo "iOS binding check failed: GoBridge.swift references missing GoMknoon exports:" >&2
    echo "$missing" >&2
    return 1
  fi

  if [[ ! -f "$nse_header" || ! -f "$nse_device_binary" ]]; then
    echo "iOS NSE binding check failed: missing GoMknoonNSE artifact" >&2
    return 1
  fi
  missing="$(
    comm -23 \
      <(extract_nse_bridge_calls) \
      <(extract_ios_header_exports "$nse_header")
  )"
  if [[ -n "$missing" ]]; then
    echo "iOS NSE binding check failed: notification service references missing exports:" >&2
    echo "$missing" >&2
    return 1
  fi

  # Apple constrains the entire notification extension to 24 MB. Reserve most
  # of that for Swift/system runtime by keeping the generated Go device archive
  # below 8 MiB. The bounded bridge is ~3.2 MiB; the app bridge is ~68 MiB.
  local nse_max_device_bytes=$((8 * 1024 * 1024))
  local nse_device_bytes
  nse_device_bytes="$(stat -f '%z' "$nse_device_binary")"
  if (( nse_device_bytes > nse_max_device_bytes )); then
    echo "iOS NSE binding check failed: Go archive is ${nse_device_bytes} bytes (max ${nse_max_device_bytes})" >&2
    return 1
  fi
}

check_android() {
  local aar="$repo_root/android/app/libs/GoMknoon.aar"
  if [[ ! -f "$aar" ]]; then
    echo "Android binding check failed: missing AAR $aar" >&2
    return 1
  fi
  if ! command -v javap >/dev/null 2>&1; then
    echo "Android binding check failed: javap not found in PATH" >&2
    return 1
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN
  unzip -p "$aar" classes.jar >"$tmp_dir/classes.jar"

  local missing
  missing="$(
    comm -23 \
      <(extract_kotlin_bridge_calls) \
      <(extract_android_aar_exports "$tmp_dir/classes.jar")
  )"

  if [[ -n "$missing" ]]; then
    echo "Android binding check failed: GoBridge.kt references missing GoMknoon exports:" >&2
    echo "$missing" >&2
    return 1
  fi
}

check_macos() {
  local header="$repo_root/macos/Runner/GoMknoon.xcframework/macos-arm64_x86_64/GoMknoon.framework/Headers/Bridge.objc.h"
  if [[ ! -f "$header" ]]; then
    echo "macOS binding check failed: missing header $header" >&2
    return 1
  fi

  local missing
  missing="$(
    comm -23 \
      <(extract_macos_bridge_calls) \
      <(extract_ios_header_exports "$header")
  )"

  if [[ -n "$missing" ]]; then
    echo "macOS binding check failed: MainFlutterWindow.swift references missing GoMknoon exports:" >&2
    echo "$missing" >&2
    return 1
  fi
}

target="${1:-all}"
case "$target" in
  all)
    check_ios
    check_macos
    check_android
    ;;
  ios)
    check_ios
    ;;
  macos)
    check_macos
    ;;
  android)
    check_android
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
