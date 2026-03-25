#!/usr/bin/env bash

set -euo pipefail

# Flutter currently reuses build/native_assets/ios across iOS simulator and
# device builds. Clearing that cache before iphoneos builds prevents stale
# simulator frameworks from being embedded into release archives.
if [[ "${PLATFORM_NAME:-}" != "iphoneos" ]]; then
  exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_build_dir="build"
flutter_env="$repo_root/ios/Flutter/flutter_export_environment.sh"

if [[ -f "$flutter_env" ]]; then
  # shellcheck disable=SC1090
  . "$flutter_env"
  if [[ -n "${FLUTTER_BUILD_DIR:-}" ]]; then
    flutter_build_dir="$FLUTTER_BUILD_DIR"
  fi
fi

native_assets_root="$repo_root/$flutter_build_dir/native_assets/ios"
if [[ -d "$native_assets_root" ]]; then
  echo "Removing stale iOS native asset cache at $native_assets_root"
  rm -rf "$native_assets_root"
fi
