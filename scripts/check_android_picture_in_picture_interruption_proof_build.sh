#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_dir="${1:-build/picture-in-picture-interruption-proof-build}"
mkdir -p "$output_dir"

aapt_bin="$(command -v aapt 2>/dev/null || true)"
if [[ -z "$aapt_bin" ]]; then
  android_sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -n "$android_sdk_root" && -d "$android_sdk_root/build-tools" ]]; then
    aapt_bin="$(find "$android_sdk_root/build-tools" -type f -name aapt 2>/dev/null | sort | tail -n 1)"
  fi
fi
if [[ -z "$aapt_bin" ]]; then
  echo "Android aapt is required for the interruption proof build boundary." >&2
  exit 1
fi

helper_class="com.mknoon.app.pipproof.PictureInPictureAudioFocusInterruptionProofActivity"
proof_application_id="com.mknoon.app.pipproof"
proof_test_application_id="${proof_application_id}.test"
base_apk="build/app/outputs/apk/debug/app-debug.apk"
test_apk="build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk"

build_android_test() {
  local enabled="$1"
  local log="$2"
  ORG_GRADLE_PROJECT_androidApplicationId="$proof_application_id" \
  ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true \
  ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false \
  ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof="$enabled" \
  ./android/gradlew -p android :app:assembleDebugAndroidTest >"$log" 2>&1
  if [[ ! -s "$base_apk" || ! -s "$test_apk" ]]; then
    echo "Android interruption boundary did not produce both base and test APKs." >&2
    exit 1
  fi
}

build_android_test false "$output_dir/default-build.log"
"$aapt_bin" dump xmltree "$base_apk" AndroidManifest.xml \
  >"$output_dir/default-base-manifest.txt"
"$aapt_bin" dump xmltree "$test_apk" AndroidManifest.xml \
  >"$output_dir/default-test-manifest.txt"
if grep -Fq "$helper_class" "$output_dir/default-base-manifest.txt" || \
   grep -Fq "$helper_class" "$output_dir/default-test-manifest.txt"; then
  echo "Default APKs unexpectedly contain the interruption proof Activity." >&2
  exit 1
fi

build_android_test true "$output_dir/proof-build.log"
"$aapt_bin" dump xmltree "$base_apk" AndroidManifest.xml \
  >"$output_dir/proof-base-manifest.txt"
"$aapt_bin" dump xmltree "$test_apk" AndroidManifest.xml \
  >"$output_dir/proof-test-manifest.txt"
"$aapt_bin" dump badging "$test_apk" >"$output_dir/proof-test-badging.txt"
if grep -Fq "$helper_class" "$output_dir/proof-base-manifest.txt"; then
  echo "Base proof APK unexpectedly contains the interruption helper." >&2
  exit 1
fi
if [[ "$(grep -Fc "$helper_class" "$output_dir/proof-test-manifest.txt")" != "1" ]] || \
   ! grep -Fq "package: name='$proof_test_application_id'" \
     "$output_dir/proof-test-badging.txt" || \
   grep -Fq 'E: intent-filter' "$output_dir/proof-test-manifest.txt" || \
   grep -Eqi 'ResolverActivity|ChooserActivity' \
     "$output_dir/proof-test-manifest.txt"; then
  echo "Proof androidTest APK did not contain one exact safe helper Activity." >&2
  exit 1
fi

set +e
ORG_GRADLE_PROJECT_androidApplicationId=com.mknoon.app \
ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true \
ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false \
ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=true \
./android/gradlew -p android :app:assembleDebugAndroidTest \
  >"$output_dir/production-refusal.log" 2>&1
production_status=$?
set -e
if [[ "$production_status" == "0" ]] || \
   ! grep -Fq \
     'Picture-in-picture interruption proof sources require the exact' \
     "$output_dir/production-refusal.log"; then
  echo "Interruption proof build did not refuse the production application ID." >&2
  exit 1
fi

printf 'defaultBaseHelper=false defaultTestHelper=false proofBaseHelper=false proofTestHelper=true proofTestPackage=%s productionRefused=true\n' \
  "$proof_test_application_id"
