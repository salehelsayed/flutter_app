#!/bin/bash
# Run scripts/mknoon_checks.py inside the store snapshot. Args are passed through.
DST=/Volumes/CrucialX9/flutter_app-store-20261001
cd "$DST" || exit 1
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export PATH="$HOME/development/flutter-3.47.2/bin:$HOME/.maestro/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"
python3 scripts/mknoon_checks.py "$@"
echo "R41 EXIT $?"
