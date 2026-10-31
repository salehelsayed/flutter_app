#!/bin/bash
# Read-only: what is inside the WebRTC artifact folder of each DerivedData on the internal disk, plus cache zip check.
for d in "$HOME"/tmp-dd-* "$HOME"/Library/Developer/Xcode/DerivedData/Runner-*; do
  a="$d/SourcePackages/artifacts/flutter_webrtc-1.6.0"; [ -d "$a" ] || continue
  echo "== $a"; ls -laR "$a" | head -14
done
Z="$HOME/Library/Caches/org.swift.swiftpm/artifacts/https___github_com_webrtc_sdk_Specs_releases_download_144_7559_09_WebRTC_xcframework_zip"
echo "== cache zip"; shasum -a 256 "$Z"; unzip -l "$Z" | head -5; unzip -tq "$Z" | tail -1
