#!/bin/bash
# Prove which Go binding the phone builds carry (Mac side).
# Usage: docker-ws/binding_probe.sh <literal>
LIT="${1:?literal}"
echo "--- Runner.app main binary"; B=build/ios/iphoneos/Runner.app/Runner; ls -la "$B" | awk '{print $6" "$7" "$8}'; echo "runner count($LIT)=$(grep -a -c "$LIT" "$B")  count(callStoreV1)=$(grep -a -c 'call_store_v1' "$B")"
echo "--- any GoMknoon binaries in Runner.app / Pods"; find build/ios/iphoneos/Runner.app ios/Pods -iname 'GoMknoon*' -type f 2>/dev/null | head -8
for f in $(find build/ios/iphoneos/Runner.app ios/Pods -name GoMknoon -type f 2>/dev/null); do echo "$f mtime=$(stat -f %Sm "$f") count($LIT)=$(grep -a -c "$LIT" "$f")"; done
echo "--- xcframework"; for f in $(find ios/Runner/GoMknoon.xcframework -name GoMknoon -type f 2>/dev/null); do echo "$f mtime=$(stat -f %Sm "$f") count($LIT)=$(grep -a -c "$LIT" "$f")"; done
echo "--- android aar"; T=$(mktemp -d); unzip -qo android/app/libs/GoMknoon.aar 'jni/arm64-v8a/*' -d "$T" 2>/dev/null && echo "aar so count($LIT)=$(grep -a -c "$LIT" "$T"/jni/arm64-v8a/*.so)"; rm -rf "$T"
