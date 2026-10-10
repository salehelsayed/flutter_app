#!/bin/bash
# Release 1.0.1+123: tracked-file dirt + Go version inside the AAB and the IPA.
cd /Volumes/CrucialX9/flutter_app || exit 1
echo "tracked changes:"; git status --porcelain --untracked-files=no
echo "untracked count: $(git status --porcelain | grep -c '^??')"
T=$(mktemp -d)
unzip -p build/app/outputs/bundle/release/app-release.aab base/lib/arm64-v8a/libgojni.so > "$T/libgojni.so" 2>/dev/null
echo "AAB libgojni Go: $(strings "$T/libgojni.so" | grep -m1 -oE 'go1\.[0-9]+\.[0-9]+')"
unzip -q -o build/ios/ipa/mknoon.ipa -d "$T/ipa" >/dev/null 2>&1
echo "IPA Runner Go: $(strings "$T/ipa/Payload/Runner.app/Runner" | grep -m1 -oE 'go1\.[0-9]+\.[0-9]+')"
NSE=$(find "$T/ipa/Payload/Runner.app/PlugIns" -name '*.appex' -maxdepth 1 | head -1)
[ -n "$NSE" ] && echo "IPA NSE Go: $(find "$NSE" -type f -perm -u+x | head -1 | xargs strings 2>/dev/null | grep -m1 -oE 'go1\.[0-9]+\.[0-9]+')"
rm -rf "$T"
