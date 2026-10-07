#!/bin/bash
# Analyzes the Orbit prototype sources and its widget test in THIS checkout.
cd "$(dirname "$0")/../.."
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
"$SDK/bin/dart" analyze prototypes/orbit_depth test/features/orbit/prototypes 2>&1 | tail -30
