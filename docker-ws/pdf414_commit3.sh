#!/bin/bash
# Plan 414: commit the iOS SwiftPM pins added by file_picker; drop machine-specific build edits.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
git checkout -- info.plist docker-ws/install_iphones_keep_identity_result.txt
git add ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved docker-ws/pdf414_commit3.sh
git commit -q -m "chore(414): pin iOS SwiftPM packages pulled in by file_picker

file_picker 11 on iOS resolves DKImagePickerController, DKCamera,
DKPhotoGallery, SDWebImage, SwiftyGif and TOCropViewController.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log --oneline -3
git status --short | grep -v '^??' || echo "tracked tree clean"
