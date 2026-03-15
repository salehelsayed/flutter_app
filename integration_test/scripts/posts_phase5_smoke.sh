#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export HOME="${ROOT}/.codex-home"
export DART_SUPPRESS_ANALYTICS=true
export FLUTTER_SUPPRESS_ANALYTICS=true

xcrun simctl shutdown all >/dev/null 2>&1 || true
"${ROOT}/.codex-bin/flutter" test \
  test/features/posts/phase5 \
  test/core/services/incoming_message_router_posts_pins_test.dart \
  test/core/database/migrations/031_posts_pins_test.dart
"${ROOT}/.codex-bin/flutter" test -d macos integration_test/posts_phase5_fake_test.dart
