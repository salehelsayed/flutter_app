#!/bin/bash
# Runs the Flutter SDK that matches pubspec.yaml's `flutter:` constraint.
# The Mac's PATH still points at 3.41.4 while the checkout was migrated to
# 3.47.2, so `flutter` on PATH compiles 3.47.2 framework sources with a 3.41.4
# engine and every run dies inside flutter/lib/src. Always go through this.
set -euo pipefail
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
if [ ! -x "$SDK/bin/flutter" ]; then
  echo "flutter sdk not found at $SDK" >&2
  exit 2
fi
cd /Volumes/CrucialX9/flutter_app
exec "$SDK/bin/flutter" "$@"
