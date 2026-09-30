#!/bin/bash
# Smoke check: Maestro can read the UI tree on both target devices.
export PATH="$HOME/.maestro/bin:$HOME/tools/appium/node_modules/.bin:/opt/homebrew/bin:$HOME/Library/Android/sdk/platform-tools:$PATH"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export ANDROID_HOME=$HOME/Library/Android/sdk
export MAESTRO_CLI_NO_ANALYTICS=1
IOS=FB7E3D88-B92D-4028-9CA7-A9CD9D34615F
AND=emulator-5556
echo "=== maestro android ($AND)"
timeout 240 maestro --device "$AND" hierarchy 2>&1 | head -c 600; echo; echo "exit=$?"
echo "=== maestro ios ($IOS)"
timeout 400 maestro --device "$IOS" hierarchy 2>&1 | head -c 600; echo; echo "exit=$?"
