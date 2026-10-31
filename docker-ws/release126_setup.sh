#!/bin/bash
# Copy ignored build inputs from the main checkout into the release-126 worktree.
# The upload keystore stays in place: key.properties gets an absolute storeFile.
# Prints only sha256 prefixes, never contents.
set -euo pipefail
M=/Volumes/CrucialX9/flutter_app; W=$M/build/wt-release-126
cp "$M/.env" "$W/.env"
cp "$M/android/app/google-services.json" "$W/android/app/google-services.json"
cp "$M/android/local.properties" "$W/android/local.properties"
sed "s|^storeFile=.*|storeFile=$M/android/app/upload-keystore.jks|" "$M/android/key.properties" > "$W/android/key.properties"
chmod 600 "$W/android/key.properties"
mkdir -p "$W/android/app/libs"
for f in GoMknoon.aar GoMknoon-sources.jar GoMknoon.inputs.sha256; do cp "$M/android/app/libs/$f" "$W/android/app/libs/$f"; done
cp "$M/ios/Runner/GoogleService-Info.plist" "$W/ios/Runner/GoogleService-Info.plist"
cp "$M/ios/Runner/GoMknoon.inputs.sha256" "$W/ios/Runner/GoMknoon.inputs.sha256"
for x in GoMknoon.xcframework GoMknoonNSE.xcframework; do rm -rf "$W/ios/Runner/$x"; cp -R "$M/ios/Runner/$x" "$W/ios/Runner/$x"; done
for f in .env android/app/google-services.json android/local.properties android/app/libs/GoMknoon.aar ios/Runner/GoogleService-Info.plist ios/Runner/GoMknoon.inputs.sha256; do echo "$(shasum -a 256 "$W/$f" | cut -c1-16) $f"; done
grep -c '^storeFile=/' "$W/android/key.properties" | sed 's/^/abs_storeFile_lines=/'
test -f "$M/android/app/upload-keystore.jks" && echo keystore_present_in_place
cd "$W" && git status --porcelain | wc -l | sed 's/^/dirty_tracked_or_untracked=/'
