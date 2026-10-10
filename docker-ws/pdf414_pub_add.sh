#!/bin/bash
# Plan 414: add the document picker dependency in this worktree.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
"$SDK/bin/flutter" pub add file_picker
grep -n "file_picker" pubspec.yaml
grep -n -A3 "^  file_picker:" pubspec.lock
echo PUB_ADD_DONE
