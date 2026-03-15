#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export HOME="${ROOT}/.codex-home"
export DART_SUPPRESS_ANALYTICS=true
export FLUTTER_SUPPRESS_ANALYTICS=true

xcrun simctl shutdown all >/dev/null 2>&1 || true
"${ROOT}/.codex-bin/flutter" test \
  test/features/posts/phase3/nearby_location_service_test.dart \
  test/features/posts/phase3/publish_post_presence_update_use_case_test.dart \
  test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart
"${ROOT}/.codex-bin/flutter" test -d macos integration_test/posts_phase3_fake_test.dart
