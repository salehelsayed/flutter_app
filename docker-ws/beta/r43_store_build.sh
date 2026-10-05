#!/bin/bash
# Build the Play .aab and the TestFlight .ipa from the frozen store snapshot, then copy them out.
DST=/Volumes/CrucialX9/flutter_app-store-20261001
REC=/Volumes/CrucialX9/flutter_app/artifacts/store-build-20261001
cd "$DST" || exit 1
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export PATH="$HOME/development/flutter-3.47.2/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"
echo "flutter: $(flutter --version 2>/dev/null | head -1)"
bash docker-ws/build_store_release.sh; rc=$?
cp docker-ws/build_store_release_result.txt "$REC/build_result.txt"
AAB=build/app/outputs/bundle/release/app-release.aab
IPA=$(ls build/ios/ipa/*.ipa 2>/dev/null | head -1)
[ -f "$AAB" ] && cp "$AAB" "$REC/mknoon-1.0.1-121.aab"
[ -n "$IPA" ] && cp "$IPA" "$REC/mknoon-1.0.1-121.ipa"
(cd "$REC" && shasum -a 256 mknoon-1.0.1-121.* 2>/dev/null > artifacts.sha256; ls -la mknoon-1.0.1-121.* 2>/dev/null)
echo "R43 EXIT $rc"
