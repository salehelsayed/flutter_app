#!/bin/bash
# Run flutter test or analyze inside a Codex-UI worktree with the pinned SDK.
#   host-run bash docker-ws/cui_wt_flutter_test.sh <worktree-dir-under-build> <test|analyze> <paths...>
set -uo pipefail
W="$(cd "$(dirname "$0")/.." && pwd)/build/$1"; shift
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
cd "$W" || exit 3
if [ "${1:-}" = dart ]; then shift; exec "$SDK/bin/dart" "$@"; fi
exec "$SDK/bin/flutter" "$@"
