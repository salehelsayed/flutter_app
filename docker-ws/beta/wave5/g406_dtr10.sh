#!/bin/bash
# DTR-10 census fix check on the main checkout.
export PATH="$HOME/development/flutter-3.47.2/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app || exit 1
flutter test --no-pub --reporter failures-only test/unit/runtime_root_inventory_test.dart 2>&1 | grep -vE "^\[FLOW\]" | tail -4
dart format --output=none --set-exit-if-changed test/unit/runtime_root_inventory_test.dart >/dev/null && echo "format ok"
