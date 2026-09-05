#!/bin/bash
# Dart from the SDK that matches pubspec.yaml's `flutter:` constraint.
set -euo pipefail
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
if [ ! -x "$SDK/bin/dart" ]; then
  echo "flutter sdk not found at $SDK" >&2
  exit 2
fi
cd /Volumes/CrucialX9/flutter_app
exec "$SDK/bin/dart" "$@"
