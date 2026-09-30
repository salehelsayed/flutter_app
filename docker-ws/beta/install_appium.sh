#!/bin/bash
# User-owned Appium install (global npm prefix ~/.local/lib is root-owned).
export PATH="$HOME/tools/appium/node_modules/.bin:$HOME/.local/bin:/opt/homebrew/bin:$PATH"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export ANDROID_HOME=$HOME/Library/Android/sdk
export APPIUM_HOME=$HOME/.appium
mkdir -p "$HOME/tools/appium"
npm install --prefix "$HOME/tools/appium" appium 2>&1 | tail -3
appium -v
appium driver install xcuitest 2>&1 | tail -3
appium driver install uiautomator2 2>&1 | tail -3
appium driver list --installed 2>&1 | tail -4
echo "=== doctor uiautomator2"; appium driver doctor uiautomator2 2>&1 | grep -vE "^\s*$" | tail -8
echo "=== doctor xcuitest"; appium driver doctor xcuitest 2>&1 | grep -vE "^\s*$" | tail -8
