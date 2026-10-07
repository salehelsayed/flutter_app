#!/bin/bash
# Runs the Orbit prototype widget tests in THIS checkout (flutter_sdk.sh
# always cds into the main checkout).
cd "$(dirname "$0")/../.."
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
"$SDK/bin/flutter" test test/features/orbit/prototypes/orbit_depth_prototype_screen_test.dart "$@" 2>&1 | grep -v "available)\|^  [a-z_]* [0-9]" | tail -80
