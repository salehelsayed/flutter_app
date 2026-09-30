#!/bin/bash
# Installs Appium (+ xcuitest, uiautomator2 drivers) and Maestro on the Mac.
export PATH="$HOME/.maestro/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
SDK=$(sed -nE 's/^sdk\.dir=(.*)$/\1/p' "$(dirname "$0")/../../android/local.properties" | tail -1)
export ANDROID_HOME="${ANDROID_HOME:-$SDK}"
echo "ANDROID_HOME=$ANDROID_HOME"
echo "=== appium"
npm install -g appium 2>&1 | tail -3
appium -v
appium driver install xcuitest 2>&1 | tail -3
appium driver install uiautomator2 2>&1 | tail -3
appium driver list --installed 2>&1 | tail -4
echo "=== maestro"
curl -fsSL "https://get.maestro.mobile.dev" | bash 2>&1 | tail -5
maestro --version 2>&1 | tail -2
echo "=== doctor"
npx --yes appium-doctor --version >/dev/null 2>&1 || true
appium driver doctor uiautomator2 2>&1 | tail -8
appium driver doctor xcuitest 2>&1 | tail -8
