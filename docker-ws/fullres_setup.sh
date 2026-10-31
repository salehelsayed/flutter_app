#!/bin/bash
# Copy ignored build inputs from the main checkout into the Original full-res worktree (debug Android + dev iOS, no upload key).
# Prints only sha256 prefixes, never contents.
set -euo pipefail
M=/Volumes/CrucialX9/flutter_app; W=$M/build/wt-fullres
cp "$M/.env" "$W/.env"
cp "$M/android/app/google-services.json" "$W/android/app/google-services.json"
cp "$M/android/local.properties" "$W/android/local.properties"
mkdir -p "$W/android/app/libs"
for f in GoMknoon.aar GoMknoon-sources.jar GoMknoon.inputs.sha256; do cp "$M/android/app/libs/$f" "$W/android/app/libs/$f"; done
cp "$M/ios/Runner/GoogleService-Info.plist" "$W/ios/Runner/GoogleService-Info.plist"
cp "$M/ios/Runner/GoMknoon.inputs.sha256" "$W/ios/Runner/GoMknoon.inputs.sha256"
for x in GoMknoon.xcframework GoMknoonNSE.xcframework; do rm -rf "$W/ios/Runner/$x"; cp -R "$M/ios/Runner/$x" "$W/ios/Runner/$x"; done
for f in .env android/app/google-services.json android/app/libs/GoMknoon.aar ios/Runner/GoogleService-Info.plist; do echo "$(shasum -a 256 "$W/$f" | cut -c1-16) $f"; done
cd "$W" && git status --porcelain | wc -l | sed 's/^/dirty=/'
