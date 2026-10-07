#!/bin/bash
cd /Volumes/CrucialX9/flutter_app || exit 1
$HOME/development/flutter-3.47.2/bin/flutter test "$1" --plain-name "$2" 2>&1 | grep -vE "^\[FLOW\]" | grep -E "Expected|Actual|Which|Error|Exception|test_.*dart [0-9]+:[0-9]+|reason|StateError|Bad state" | head -20 | cut -c1-200
