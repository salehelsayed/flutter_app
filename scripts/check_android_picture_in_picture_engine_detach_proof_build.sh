#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

apk="build/app/outputs/apk/debug/app-debug.apk"
evidence_dir="${1:-build/received-video-pip-proof/engine-detach-build-boundary}"
receiver="PictureInPictureEngineDetachProofReceiver"
proof_id="com.mknoon.app.pipproof"
production_id="com.mknoon.app"
proof_property="enablePictureInPictureEngineDetachProof"
android_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
apkanalyzer="$(find "$android_sdk/cmdline-tools" -type f -name apkanalyzer -perm -111 2>/dev/null | sort | tail -n 1)"

if [[ -z "$apkanalyzer" ]]; then
  echo "apkanalyzer is required for proof APK manifest inspection." >&2
  exit 1
fi
mkdir -p "$evidence_dir"

ORG_GRADLE_PROJECT_androidApplicationId="$production_id" \
ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true \
ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false \
  ./android/gradlew -p android app:assembleDebug \
  >"$evidence_dir/default-build.log" 2>&1
cp "$apk" "$evidence_dir/default-debug.apk"
"$apkanalyzer" manifest print "$evidence_dir/default-debug.apk" \
  >"$evidence_dir/default-manifest.xml"
unzip -p "$evidence_dir/default-debug.apk" 'classes*.dex' | strings \
  >"$evidence_dir/default-dex-strings.txt"
if grep -Fq "$receiver" "$evidence_dir/default-manifest.xml" || \
   grep -Fq "$receiver" "$evidence_dir/default-dex-strings.txt"; then
  echo "default APK unexpectedly contains the proof receiver or class." >&2
  exit 1
fi

ORG_GRADLE_PROJECT_androidApplicationId="$proof_id" \
ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true \
ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=true \
  ./android/gradlew -p android app:assembleDebug \
  >"$evidence_dir/proof-build.log" 2>&1
cp "$apk" "$evidence_dir/proof-debug.apk"
"$apkanalyzer" manifest print "$evidence_dir/proof-debug.apk" \
  >"$evidence_dir/proof-manifest.xml"
unzip -p "$evidence_dir/proof-debug.apk" 'classes*.dex' | strings \
  >"$evidence_dir/proof-dex-strings.txt"
if ! grep -Fq "$receiver" "$evidence_dir/proof-manifest.xml" || \
   ! grep -Fq "$receiver" "$evidence_dir/proof-dex-strings.txt" || \
   ! grep -Fq 'android.permission.DUMP' "$evidence_dir/proof-manifest.xml" || \
   ! grep -Fq "package=\"$proof_id\"" "$evidence_dir/proof-manifest.xml"; then
  echo "proof APK did not contain the exact disposable receiver boundary." >&2
  exit 1
fi

set +e
ORG_GRADLE_PROJECT_androidApplicationId="$production_id" \
ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true \
ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=true \
  ./android/gradlew -p android app:help \
  >"$evidence_dir/production-id-rejection.log" 2>&1
rejection_status=$?
set -e
if [[ "$rejection_status" == 0 ]] || \
   ! grep -Fq \
     'proof sources require the exact disposable application ID' \
     "$evidence_dir/production-id-rejection.log"; then
  echo "proof source set did not refuse the production application ID." >&2
  exit 1
fi

printf 'PASS defaultReceiverAbsent=true proofReceiverPresent=true proofDumpGuard=true productionIdRejected=true\n'
