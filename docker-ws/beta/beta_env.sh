# Shared settings for the beta scripts (sourced; macOS bash 3.2).
SRC=/Volumes/CrucialX9/flutter_app
BETA="$SRC/artifacts/beta-20260928"   # R2-1 fix validation (was beta-20260927: round 2)
UDID=FB7E3D88-B92D-4028-9CA7-A9CD9D34615F      # iPhone 15 simulator
# Pixel 7a emulator: found by AVD name (Pixel_7a), because its port changes after reboots (5556 / 5554).
SERIAL=$("$HOME/Library/Android/sdk/platform-tools/adb" devices 2>/dev/null | awk '$1 ~ /^emulator-/ && $2=="device" {print $1}' | while read -r s; do
  [ "$("$HOME/Library/Android/sdk/platform-tools/adb" -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')" = "Pixel_7a" ] && echo "$s"; done | head -1)
SERIAL=${SERIAL:-emulator-5556}
PKG=com.mknoon.app
IOS_NAME="Beta iPhone"
AND_NAME="Beta Pixel"
export ANDROID_HOME=$HOME/Library/Android/sdk
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export MAESTRO_CLI_NO_ANALYTICS=1
export PATH="$HOME/.maestro/bin:$HOME/tools/appium/node_modules/.bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"
ADB="$ANDROID_HOME/platform-tools/adb -s $SERIAL"
BUNDLE=com.mknoon.app
ios_docs() { echo "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Documents"; }
and_write() { # and_write <relative path under app_flutter> ; content on stdin
  $ADB shell "run-as $PKG sh -c 'mkdir -p app_flutter && cat > app_flutter/$1'"
}
and_read() { $ADB shell "run-as $PKG cat app_flutter/$1" 2>/dev/null; }
current_run() { cat "$BETA/current_run.txt"; }
# Emulator is slow under Mac load: give the Maestro drivers 2 min to start (default ~15 s).
export MAESTRO_DRIVER_STARTUP_TIMEOUT=240000   # 120 s was too short for the iOS driver at Mac load 60-90 (round 2)
