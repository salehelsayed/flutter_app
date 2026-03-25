#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Flutter's install_code_assets target only declares native_assets.json as its
# output. If build/native_assets/ios is removed out-of-band, the target can be
# skipped on the next archive and xcode_backend.dart later crashes while trying
# to embed frameworks that no longer exist.
#
# Invalidate Flutter's incremental cache instead of deleting build/native_assets
# directly. That forces install_code_assets to recreate both the manifest and
# the bundled iOS frameworks during the current archive.
find "${PROJECT_ROOT}/.dart_tool/flutter_build" \
  -type f \
  \( \
    -name "install_code_assets.stamp" -o \
    -name "install_code_assets.d" -o \
    -name "native_assets.json" \
  \) \
  -delete 2>/dev/null || true

rm -rf "${PROJECT_ROOT}/build/native_assets/ios"
