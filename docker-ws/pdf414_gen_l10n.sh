#!/bin/bash
# Plan 414: regenerate localizations in this worktree.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
"$SDK/bin/flutter" gen-l10n
echo GEN_DONE
