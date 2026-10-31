#!/bin/bash
# Copy ignored build inputs from the main checkout into build/<tree> (no version change). Prints sha prefixes only.
# then bump pubspec to <name>+<N> as a local commit. Prints sha256 prefixes only, never contents.
#   host-run bash docker-ws/wt_inputs_setup.sh <tree under build/> [binding source tree under build/, default: main checkout]
set -euo pipefail
T=${1:?tree}
M=/Volumes/CrucialX9/flutter_app; W=$M/build/$T; B=$M${2:+/build/$2}
test -d "$W" || { echo "missing worktree $W"; exit 2; }
cp "$M/.env" "$W/.env"
cp "$M/android/app/google-services.json" "$W/android/app/google-services.json"
cp "$M/android/local.properties" "$W/android/local.properties"
sed "s|^storeFile=.*|storeFile=$M/android/app/upload-keystore.jks|" "$M/android/key.properties" > "$W/android/key.properties"
chmod 600 "$W/android/key.properties"
mkdir -p "$W/android/app/libs"
for f in GoMknoon.aar GoMknoon-sources.jar GoMknoon.inputs.sha256; do cp "$B/android/app/libs/$f" "$W/android/app/libs/$f"; done
cp "$M/ios/Runner/GoogleService-Info.plist" "$W/ios/Runner/GoogleService-Info.plist"
cp "$B/ios/Runner/GoMknoon.inputs.sha256" "$W/ios/Runner/GoMknoon.inputs.sha256"
for x in GoMknoon.xcframework GoMknoonNSE.xcframework; do rm -rf "$W/ios/Runner/$x"; cp -R "$B/ios/Runner/$x" "$W/ios/Runner/$x"; done
# The CV-14 wake-token freshness test also checks the macOS slice.
rm -rf "$W/macos/Runner/GoMknoon.xcframework"; cp -R "$B/macos/Runner/GoMknoon.xcframework" "$W/macos/Runner/GoMknoon.xcframework"
for f in .env android/app/google-services.json android/local.properties android/app/libs/GoMknoon.aar ios/Runner/GoogleService-Info.plist ios/Runner/GoMknoon.inputs.sha256; do echo "$(shasum -a 256 "$W/$f" | cut -c1-16) $f"; done
grep -c '^storeFile=/' "$W/android/key.properties" | sed 's/^/abs_storeFile_lines=/'
test -f "$M/android/app/upload-keystore.jks" && echo keystore_present_in_place
cd "$W"
grep -E '^version:' pubspec.yaml
git log -1 --format='head=%h %s'
git status --porcelain | wc -l | sed 's/^/dirty_tracked_or_untracked=/'
