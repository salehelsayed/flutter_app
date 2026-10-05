#!/bin/bash
# Read-only: iOS simulator runtimes and devices (booted first), plus Maestro version.
xcrun simctl list runtimes 2>/dev/null | grep -i ios
echo "--- booted"; xcrun simctl list devices booted 2>/dev/null | grep -v "^==" | head
echo "--- iOS 26.2 devices"; xcrun simctl list devices 2>/dev/null | sed -n '/-- iOS 26.2 --/,/^--/p' | head -20
echo "--- maestro $(~/.maestro/bin/maestro --version 2>/dev/null)"
