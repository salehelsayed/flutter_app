#!/bin/bash
# VC-014: build a universal APK from the store 128 AAB on the Mac (arm64 aapt2), signed with a scratch key (disposable emulator only).
#   host-run bash docker-ws/vc014_universal_apk.sh
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"; D="$R/build/vc014-bt"
JAVA=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home/bin/java
AAPT2=$(ls -d "$HOME/Library/Android/sdk/build-tools/"*/aapt2 | sort -V | tail -1)
echo "aapt2=$AAPT2"
rm -f "$D/u.apks" "$D/universal.apk"
"$JAVA" -jar "$D/bundletool.jar" build-apks --bundle="$R/build/wt-release-128/build/app/outputs/bundle/release/app-release.aab" \
  --output="$D/u.apks" --mode=universal --aapt2="$AAPT2" --ks="$D/scratch.jks" --ks-pass=pass:vc014pass \
  --ks-key-alias=vc014 --key-pass=pass:vc014pass
cd "$D" && unzip -o u.apks universal.apk >/dev/null && ls -la universal.apk && shasum -a 256 universal.apk
