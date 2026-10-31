#!/bin/bash
# 129 store build setup in build/wt-translate-129 (detached at origin/main <sha>): restore the tracked Package.resolved
# files, put the store signing inputs in place (same as release_store_setup.sh: upload keystore by path, never printed),
# and bump pubspec to <name>+129 as a LOCAL commit on the detached head (never pushed). Prints sha256 prefixes only.
#   host-run bash docker-ws/store129_setup.sh <sha> <N>
set -euo pipefail
SHA=${1:?sha}; N=${2:?build number}
M=/Volumes/CrucialX9/flutter_app; W=$M/build/wt-translate-129
cd "$W"
git checkout -- ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null || true
[ -z "$(git status --porcelain --untracked-files=no)" ] || { git status --porcelain --untracked-files=no; echo "STOP tree dirty"; exit 3; }
git checkout --detach "$SHA" 2>&1 | tail -1
cp "$M/.env" "$W/.env"
cp "$M/android/app/google-services.json" "$W/android/app/google-services.json"
cp "$M/android/local.properties" "$W/android/local.properties"
sed "s|^storeFile=.*|storeFile=$M/android/app/upload-keystore.jks|" "$M/android/key.properties" > "$W/android/key.properties"
chmod 600 "$W/android/key.properties"
cp "$M/ios/Runner/GoogleService-Info.plist" "$W/ios/Runner/GoogleService-Info.plist"
grep -c '^storeFile=/' "$W/android/key.properties" | sed 's/^/abs_storeFile_lines=/'
test -f "$M/android/app/upload-keystore.jks" && echo keystore_present_in_place
CUR=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
if [ "${CUR##*+}" != "$N" ]; then
  sed -i '' -E "s/^version: ([0-9.]+)\+[0-9]+$/version: \1+$N/" pubspec.yaml
  git add pubspec.yaml
  git commit -q -m "chore: bump version to ${CUR%%+*}+$N for store release" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
fi
grep -E '^version:' pubspec.yaml
git log -1 --format='head=%h parent=%p %s'
for f in ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved; do echo "resolved_before $(shasum -a 256 "$f" | cut -c1-64) $f"; done
echo "tracked_dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
