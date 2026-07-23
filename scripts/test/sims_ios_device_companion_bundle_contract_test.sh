#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/cache" "$tmp_dir/prepared"
touch "$tmp_dir/xcode-build.log" "$tmp_dir/flutter-build.log" \
  "$tmp_dir/codesign-verify.log"

staging_attestation="$tmp_dir/staging-signing-attestation.json"
provisioning_profile="$tmp_dir/fixture.mobileprovision"
signing_identity="$(printf 'a%.0s' {1..64})"
provisioning_digest="$(printf 'b%.0s' {1..64})"
receiver_device='00008150-001C3C6A3684401C'
signing_expiry='2027-07-15T00:00:00Z'
fixture_team='TEAM-FIXTURE-A'
fixture_source="$(printf 'f%.0s' {1..64})"

write_signing_attestation() {
  python3 - "$staging_attestation" "$signing_identity" \
    "$provisioning_digest" "$receiver_device" "$signing_expiry" <<'PY'
import json
import pathlib
import sys

path, identity, provision, receiver, expiry = sys.argv[1:]
pathlib.Path(path).write_text(json.dumps({
    "schema": "mknoon.sims.ios-payload-fast-path-staging.v1",
    "signingIdentitySha256": identity,
    "provisioningProfileSha256": provision,
    "receiverDeviceId": receiver,
    "signingExpiresAt": expiry,
    "privateFixtureSecret": "must-never-reach-cache-attestation",
}) + "\n")
PY
}

write_signing_attestation
printf 'fixture provisioning profile a\n' >"$provisioning_profile"

cat >"$tmp_dir/bin/flutter" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--version" ]; then
  printf '{"frameworkVersion":"fixture"}\n'
  exit 0
fi
printf '%s\n' "$*" >>"${FLUTTER_BUILD_LOG:?}"
exit 97
SH
chmod +x "$tmp_dir/bin/flutter"

cat >"$tmp_dir/bin/pod" <<'SH'
#!/usr/bin/env bash
printf 'fixture cocoapods\n'
SH
chmod +x "$tmp_dir/bin/pod"

cat >"$tmp_dir/bin/codesign" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 4 ] || exit 81
[ "$1" = '--verify' ] || exit 82
[ "$2" = '--deep' ] || exit 83
[ "$3" = '--strict' ] || exit 84
target="$4"
[ -d "$target" ] || exit 85
printf '%s\n' "$*" >>"${CODESIGN_VERIFY_LOG:?}"
if [ -f "$target/.invalid-signature" ]; then
  printf 'fixture signature rejected: %s\n' "$target" >&2
  exit 86
fi
SH
chmod +x "$tmp_dir/bin/codesign"

cat >"$tmp_dir/bin/xcodebuild" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "-version" ]; then
  printf 'Xcode fixture\nBuild version 1\n'
  exit 0
fi
[ "${1:-}" = "build-for-testing" ] || exit 92
derived=''
previous=''
bootstrap_condition_seen=false
group_media_condition_seen=false
testability_seen=false
release_seen=false
allow_provisioning_updates_seen=false
automatic_signing_seen=false
blank_entitlements_seen=false
runner_entitlements_seen=false
runner_ui_tests_entitlements_seen=false
share_entitlements_seen=false
notification_service_entitlements_seen=false
dedicated_group_seen=false
runner_bundle_seen=false
runner_tests_bundle_seen=false
runner_ui_tests_bundle_seen=false
share_bundle_seen=false
notification_service_bundle_seen=false
for argument in "$@"; do
  if [ "$previous" = "-derivedDataPath" ]; then derived="$argument"; fi
  if [ "$argument" = 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP' ]; then
    bootstrap_condition_seen=true
  fi
  if [ "$argument" = 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) MKNOON_SIMS_GROUP_MEDIA_269' ]; then
    group_media_condition_seen=true
  fi
  if [ "$argument" = 'ENABLE_TESTABILITY=YES' ]; then
    testability_seen=true
  fi
  if [ "$previous" = '-configuration' ] && [ "$argument" = 'Release' ]; then
    release_seen=true
  fi
  if [ "$argument" = '-allowProvisioningUpdates' ]; then
    allow_provisioning_updates_seen=true
  fi
  if [ "$argument" = 'CODE_SIGN_STYLE=Automatic' ]; then
    automatic_signing_seen=true
  fi
  if [ "$argument" = 'CODE_SIGN_ENTITLEMENTS=' ]; then
    blank_entitlements_seen=true
  fi
  if [ "$argument" = 'MKNOON_RUNNER_CODE_SIGN_ENTITLEMENTS=Runner/GroupMedia269.empty.entitlements' ]; then
    runner_entitlements_seen=true
  fi
  if [ "$argument" = 'MKNOON_RUNNER_UI_TESTS_CODE_SIGN_ENTITLEMENTS=Runner/GroupMedia269.empty.entitlements' ]; then
    runner_ui_tests_entitlements_seen=true
  fi
  if [ "$argument" = 'MKNOON_SHARE_EXTENSION_CODE_SIGN_ENTITLEMENTS=Runner/GroupMedia269.empty.entitlements' ]; then
    share_entitlements_seen=true
  fi
  if [ "$argument" = 'MKNOON_NOTIFICATION_SERVICE_CODE_SIGN_ENTITLEMENTS=Runner/GroupMedia269.empty.entitlements' ]; then
    notification_service_entitlements_seen=true
  fi
  if [ "$argument" = 'CUSTOM_GROUP_ID=group.com.mknoon.sims.groupmedia269.share' ]; then
    dedicated_group_seen=true
  fi
  if [ "$argument" = 'MKNOON_RUNNER_BUNDLE_IDENTIFIER=com.mknoon.sims.groupmedia269' ]; then
    runner_bundle_seen=true
  fi
  if [ "$argument" = 'MKNOON_RUNNER_TESTS_BUNDLE_IDENTIFIER=com.mknoon.sims.groupmedia269.RunnerTests' ]; then
    runner_tests_bundle_seen=true
  fi
  if [ "$argument" = 'MKNOON_RUNNER_UI_TESTS_BUNDLE_IDENTIFIER=com.mknoon.sims.groupmedia269.RunnerUITests' ]; then
    runner_ui_tests_bundle_seen=true
  fi
  if [ "$argument" = 'MKNOON_SHARE_EXTENSION_BUNDLE_IDENTIFIER=com.mknoon.sims.groupmedia269.ShareExtension' ]; then
    share_bundle_seen=true
  fi
  if [ "$argument" = 'MKNOON_NOTIFICATION_SERVICE_BUNDLE_IDENTIFIER=com.mknoon.sims.groupmedia269.NotificationService' ]; then
    notification_service_bundle_seen=true
  fi
  case "$argument" in
    PRODUCT_BUNDLE_IDENTIFIER=*) exit 96 ;;
  esac
  previous="$argument"
done
[ -n "$derived" ] || exit 93
[ "$testability_seen" = true ] || exit 95
[ "$release_seen" = true ] || exit 97
case "${SIMS_BUILD_PROFILE:-}" in
  ios.device.production)
    [ "$bootstrap_condition_seen" = true ] || exit 94
    [ "$group_media_condition_seen" = false ] || exit 98
    [ "$allow_provisioning_updates_seen" = false ] || exit 99
    [ "$automatic_signing_seen" = false ] || exit 100
    [ "$blank_entitlements_seen" = false ] || exit 101
    [ "$runner_entitlements_seen" = false ] || exit 115
    [ "$runner_ui_tests_entitlements_seen" = false ] || exit 116
    [ "$share_entitlements_seen" = false ] || exit 117
    [ "$notification_service_entitlements_seen" = false ] || exit 118
    [ "$runner_bundle_seen" = false ] || exit 102
    ;;
  ios.device.group_media_269)
    [ "$bootstrap_condition_seen" = false ] || exit 114
    [ "$group_media_condition_seen" = true ] || exit 103
    [ "$allow_provisioning_updates_seen" = true ] || exit 104
    [ "$automatic_signing_seen" = true ] || exit 105
    [ "$blank_entitlements_seen" = false ] || exit 106
    [ "$runner_entitlements_seen" = true ] || exit 119
    [ "$runner_ui_tests_entitlements_seen" = true ] || exit 120
    [ "$share_entitlements_seen" = true ] || exit 121
    [ "$notification_service_entitlements_seen" = true ] || exit 122
    [ "$dedicated_group_seen" = true ] || exit 107
    [ "$runner_bundle_seen" = true ] || exit 108
    [ "$runner_tests_bundle_seen" = true ] || exit 109
    [ "$runner_ui_tests_bundle_seen" = true ] || exit 110
    [ "$share_bundle_seen" = true ] || exit 111
    [ "$notification_service_bundle_seen" = true ] || exit 112
    ;;
  *) exit 113 ;;
esac
printf '%s\n' "$*" >>"${XCODE_BUILD_LOG:?}"
products="$derived/Build/Products"
app="$products/Release-iphoneos/Runner.app"
share="$app/PlugIns/Share Extension.appex"
notification="$app/PlugIns/NotificationService.appex"
framework="$app/Frameworks/Fixture.framework"
ui_host="$products/Release-iphoneos/RunnerUITests-Runner.app"
tests="$ui_host/PlugIns/RunnerUITests.xctest"
mkdir -p "$share" "$notification" "$framework" "$tests"
printf 'signed runner fixture\n' >"$app/Runner"
printf 'plist fixture\n' >"$app/Info.plist"
printf 'signed share fixture\n' >"$share/Share Extension"
printf 'share plist fixture\n' >"$share/Info.plist"
printf 'signed notification fixture\n' >"$notification/NotificationService"
printf 'notification plist fixture\n' >"$notification/Info.plist"
printf 'signed framework fixture\n' >"$framework/Fixture"
printf 'framework plist fixture\n' >"$framework/Info.plist"
printf 'ui host fixture\n' >"$ui_host/RunnerUITests-Runner"
printf 'ui host plist fixture\n' >"$ui_host/Info.plist"
printf 'ui test fixture\n' >"$tests/RunnerUITests"
printf 'ui test plist fixture\n' >"$tests/Info.plist"
chmod 755 "$app/Runner" "$share/Share Extension" \
  "$notification/NotificationService" "$framework/Fixture" \
  "$ui_host/RunnerUITests-Runner" "$tests/RunnerUITests"
cat >"$products/Runner_iphoneos.xctestrun" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>RunnerUITests</key><dict>
    <key>TestBundlePath</key><string>__TESTROOT__/Release-iphoneos/RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest</string>
    <key>UITargetAppPath</key><string>$products/Release-iphoneos/Runner.app</string>
  </dict>
</dict></plist>
PLIST
case "${SIMS_TEST_IOS_ARTIFACT_FAULT:-}" in
  '') ;;
  missing-runner-plist) rm -f "$app/Info.plist" ;;
  missing-ui-host-executable) rm -f "$ui_host/RunnerUITests-Runner" ;;
  second-xctestrun) cp "$products/Runner_iphoneos.xctestrun" \
    "$products/Second.xctestrun" ;;
  invalid-ui-test-signature) : >"$tests/.invalid-signature" ;;
  *) exit 123 ;;
esac
SH
chmod +x "$tmp_dir/bin/xcodebuild"

manifest="$tmp_dir/manifest.json"
cat >"$manifest" <<'JSON'
{
  "schemaVersion": 1,
  "buildProfiles": [
    {
      "id": "ios.device.production",
      "platform": "ios",
      "artifactKind": "signed-physical-app-xctest-bundle",
      "buildRequired": true,
      "compileDefines": {"PRODUCTION_APNS": "true"},
      "declaredException": false
    }
  ],
  "capabilities": [
    {
      "id": "fixture.ios.device.bundle",
      "owner": "fixture-build",
      "proofBoundary": "fixture.ios.physical.bundle",
      "assertions": ["single.central.compile", "relocatable.test.products"],
      "lane": "build",
      "modes": ["major"],
      "families": ["fixture"],
      "required": true,
      "command": ["@prepare-build", "ios.device.production"],
      "buildProfile": "ios.device.production",
      "dependencies": [],
      "resources": [{"name": "build:ios.device.production", "access": "write"}],
      "targetCapabilities": [],
      "artifactRequired": true,
      "artifactValidator": "build.attestation",
      "active": true,
      "declaredBuildException": false
    }
  ],
  "ownership": []
}
JSON

run_prepare() {
  local report="$1"
  if ! PATH="$tmp_dir/bin:$PATH" \
    SIMS_MANIFEST="$manifest" \
    SIMS_REPORT_PATH="$report" \
    SIMS_CACHE_DIR="$tmp_dir/cache" \
    SIMS_IOS_DEVICE_PRODUCTION_DERIVED_DATA="$tmp_dir/derived" \
    SIMS_IOS_DEVICE_PRODUCTION_BUNDLE_PATH="$tmp_dir/prepared/bundle" \
    SIMS_IOS_DEVICE_GROUP_MEDIA_269_DERIVED_DATA="$tmp_dir/group-media-derived" \
    SIMS_IOS_DEVICE_GROUP_MEDIA_269_BUNDLE_PATH="$tmp_dir/prepared/group-media-bundle" \
    SIMS_IOS_NOTIFICATION_STAGING_MANIFEST="$staging_attestation" \
    SIMS_IOS_PROVISIONING_PROFILE_PATH="$provisioning_profile" \
    SIMS_IOS_PHYSICAL_DEVICE_ID="$receiver_device" \
    DEVELOPMENT_TEAM="$fixture_team" \
    PROVISIONING_PROFILE_SPECIFIER='fixture-profile' \
    SIMS_SOURCE_DIGEST="$fixture_source" \
    SIMS_TEST_ALLOW_SOURCE_DIGEST_OVERRIDE=1 \
    XCODE_BUILD_LOG="$tmp_dir/xcode-build.log" \
    FLUTTER_BUILD_LOG="$tmp_dir/flutter-build.log" \
    CODESIGN_VERIFY_LOG="$tmp_dir/codesign-verify.log" \
    ./scripts/run_test_gates.sh sims major --prepare-builds --list --format json \
      >"$report.stdout"; then
    cat "$report.stdout" >&2
    return 1
  fi
}

first_report="$tmp_dir/first.json"
run_prepare "$first_report"
[ "$(wc -l <"$tmp_dir/xcode-build.log" | tr -d ' ')" -eq 1 ] ||
  fail 'first preparation did not execute exactly one central Xcode compile'
[ ! -s "$tmp_dir/flutter-build.log" ] ||
  fail 'ios.device.production invoked a duplicate Flutter build'

cached_bundle="$(find "$tmp_dir/cache" -type d -name 'ios.device.production.bundle' -print -quit)"
[ -n "$cached_bundle" ] || fail 'cached companion bundle is missing'
[ -x "$cached_bundle/TestProducts/Release-iphoneos/Runner.app/Runner" ] ||
  fail 'cached signed Runner.app executable is missing or lost its mode'
[ -s "$cached_bundle/TestProducts/Release-iphoneos/Runner.app/Info.plist" ] ||
  fail 'cached signed Runner.app Info.plist is missing'
[ -x "$cached_bundle/TestProducts/Release-iphoneos/Runner.app/PlugIns/Share Extension.appex/Share Extension" ] ||
  fail 'cached Share Extension executable is missing or lost its mode'
[ -s "$cached_bundle/TestProducts/Release-iphoneos/Runner.app/PlugIns/Share Extension.appex/Info.plist" ] ||
  fail 'cached Share Extension Info.plist is missing'
[ -x "$cached_bundle/TestProducts/Release-iphoneos/Runner.app/PlugIns/NotificationService.appex/NotificationService" ] ||
  fail 'cached NotificationService executable is missing or lost its mode'
[ -s "$cached_bundle/TestProducts/Release-iphoneos/Runner.app/PlugIns/NotificationService.appex/Info.plist" ] ||
  fail 'cached NotificationService Info.plist is missing'
[ -x "$cached_bundle/TestProducts/Release-iphoneos/RunnerUITests-Runner.app/RunnerUITests-Runner" ] ||
  fail 'cached UI test host executable is missing or lost its mode'
[ -s "$cached_bundle/TestProducts/Release-iphoneos/RunnerUITests-Runner.app/Info.plist" ] ||
  fail 'cached UI test host Info.plist is missing'
[ -f "$cached_bundle/RunnerUITests.xctestrun" ] ||
  fail 'cached xctestrun is missing'
[ -x "$cached_bundle/TestProducts/Release-iphoneos/RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest/RunnerUITests" ] ||
  fail 'cached UI test product is missing'
[ -s "$cached_bundle/TestProducts/Release-iphoneos/RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest/Info.plist" ] ||
  fail 'cached UI test product Info.plist is missing'
[ "$(wc -l <"$tmp_dir/codesign-verify.log" | tr -d ' ')" -eq 12 ] ||
  fail 'complete production products were not codesign-verified before packaging and success'
if awk '
  $1 != "--verify" || $2 != "--deep" || $3 != "--strict" { exit 1 }
' "$tmp_dir/codesign-verify.log"; then
  :
else
  fail 'central builder issued a non-strict codesign verification command'
fi
for signed_product in \
  'Runner.app' \
  'Share Extension.appex' \
  'NotificationService.appex' \
  'RunnerUITests-Runner.app' \
  'RunnerUITests.xctest' \
  'Fixture.framework'; do
  grep -Fq "$signed_product" "$tmp_dir/codesign-verify.log" ||
    fail "central builder skipped codesign verification for $signed_product"
done
python3 - "$cached_bundle/bundle_manifest.json" "$first_report" "$tmp_dir/cache" <<'PY'
import json
import pathlib
import sys

bundle_manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
if bundle_manifest != {
    "schema": "mknoon.sims.ios-device-production-bundle.v1",
    "profileId": "ios.device.production",
    "applicationApp": "TestProducts/Release-iphoneos/Runner.app",
    "xctestrun": "RunnerUITests.xctestrun",
    "testProducts": "TestProducts",
    "centralCompileCommands": 1,
    "logicalBuildCount": 1,
    "childBuildCount": 0,
}:
    raise SystemExit("FAIL: companion manifest is not exact")
report = json.loads(pathlib.Path(sys.argv[2]).read_text())
if report["builds"]["actualBuilds"] != 1:
    raise SystemExit("FAIL: first report did not record one logical build")
attestations = list(pathlib.Path(sys.argv[3]).rglob("attestation.json"))
if len(attestations) != 1:
    raise SystemExit("FAIL: expected one companion attestation")
command = json.loads(attestations[0].read_text())["redactedCommand"]
if not command or command[0] != "xcodebuild" or "flutter" in command:
    raise SystemExit("FAIL: attestation does not report the one-pass Xcode command")
serialized = json.dumps(json.loads(attestations[0].read_text()))
for forbidden in (
    "must-never-reach-cache-attestation",
    "TEAM-FIXTURE-A",
    "fixture-profile",
    "00008150-001C3C6A3684401C",
    str(pathlib.Path(sys.argv[3]).parent / "staging-signing-attestation.json"),
):
    if forbidden in serialized:
        raise SystemExit("FAIL: signing input leaked into the cache attestation")
PY

rm -rf "$tmp_dir/derived" "$tmp_dir/prepared/bundle"
second_report="$tmp_dir/second.json"
run_prepare "$second_report"
[ "$(wc -l <"$tmp_dir/xcode-build.log" | tr -d ' ')" -eq 1 ] ||
  fail 'relocated cached bundle rebuilt after original DerivedData was deleted'
[ "$(wc -l <"$tmp_dir/codesign-verify.log" | tr -d ' ')" -eq 12 ] ||
  fail 'cache hit reran or bypassed the attested build-time codesign set'
python3 - "$second_report" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text())
if report["builds"]["actualBuilds"] != 0 or report["builds"]["hits"] != 1:
    raise SystemExit("FAIL: relocated companion bundle was not a cache hit")
PY

printf 'corrupt\n' >"$cached_bundle/TestProducts/Release-iphoneos/Runner.app/Runner"
third_report="$tmp_dir/third.json"
run_prepare "$third_report"
[ "$(wc -l <"$tmp_dir/xcode-build.log" | tr -d ' ')" -eq 2 ] ||
  fail 'corrupt cached app did not cause exactly one central rebuild'
python3 - "$third_report" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text())
builds = report["builds"]
if builds["actualBuilds"] != 1 or not builds["invalidations"]:
    raise SystemExit("FAIL: corrupt companion was not reported as invalidated")
PY

assert_fingerprint_rebuild() {
  local report="$1"
  local expected_compiles="$2"
  run_prepare "$report"
  [ "$(wc -l <"$tmp_dir/xcode-build.log" | tr -d ' ')" -eq "$expected_compiles" ] ||
    fail "signed input mutation did not cause exactly one central rebuild"
  python3 - "$report" <<'PY'
import json
import pathlib
import sys

builds = json.loads(pathlib.Path(sys.argv[1]).read_text())["builds"]
if builds["actualBuilds"] != 1 or builds["hits"] != 0:
    raise SystemExit("FAIL: signed input mutation reused an incompatible cache entry")
PY
}

signing_identity="$(printf 'c%.0s' {1..64})"
write_signing_attestation
assert_fingerprint_rebuild "$tmp_dir/identity-change.json" 3

provisioning_digest="$(printf 'd%.0s' {1..64})"
write_signing_attestation
assert_fingerprint_rebuild "$tmp_dir/provision-change.json" 4

receiver_device='00008150-001C3C6A3684402D'
write_signing_attestation
assert_fingerprint_rebuild "$tmp_dir/device-change.json" 5

signing_expiry='2028-07-15T00:00:00Z'
write_signing_attestation
assert_fingerprint_rebuild "$tmp_dir/expiry-change.json" 6

printf 'fixture provisioning profile b\n' >"$provisioning_profile"
assert_fingerprint_rebuild "$tmp_dir/profile-contents-change.json" 7

fixture_team='TEAM-FIXTURE-B'
assert_fingerprint_rebuild "$tmp_dir/team-change.json" 8

cat >"$manifest" <<'JSON'
{
  "schemaVersion": 1,
  "buildProfiles": [
    {
      "id": "ios.device.group_media_269",
      "platform": "ios",
      "artifactKind": "signed-physical-app-xctest-bundle",
      "buildRequired": true,
      "compileDefines": {
        "E2E_TEST_MODE": "true",
        "PRODUCTION_APNS": "true",
        "SIMS_IOS_DISPOSABLE_BUNDLE_ID": "com.mknoon.sims.groupmedia269"
      },
      "declaredException": false
    }
  ],
  "capabilities": [
    {
      "id": "fixture.ios.device.group-media-269-bundle",
      "owner": "fixture-build",
      "proofBoundary": "fixture.ios.group-media-269.bundle",
      "assertions": ["single.central.compile", "relocatable.test.products"],
      "lane": "build",
      "modes": ["major"],
      "families": ["group", "media", "transport"],
      "required": true,
      "command": ["@prepare-build", "ios.device.group_media_269"],
      "buildProfile": "ios.device.group_media_269",
      "dependencies": [],
      "resources": [{"name": "build:ios.device.group_media_269", "access": "write"}],
      "targetCapabilities": ["host.xcode"],
      "artifactRequired": true,
      "artifactValidator": "build.attestation",
      "active": true,
      "declaredBuildException": false
    }
  ],
  "ownership": []
}
JSON

dedicated_compiles_before="$(wc -l <"$tmp_dir/xcode-build.log" | tr -d ' ')"
dedicated_codesign_before="$(wc -l <"$tmp_dir/codesign-verify.log" | tr -d ' ')"
dedicated_first_report="$tmp_dir/group-media-first.json"
run_prepare "$dedicated_first_report"
[ "$(wc -l <"$tmp_dir/xcode-build.log" | tr -d ' ')" -eq "$((dedicated_compiles_before + 1))" ] ||
  fail 'TC-269 preparation did not execute exactly one central Xcode compile'
[ ! -s "$tmp_dir/flutter-build.log" ] ||
  fail 'ios.device.group_media_269 invoked a duplicate Flutter build'

dedicated_cached_bundle="$(find "$tmp_dir/cache" -type d -name 'ios.device.group_media_269.bundle' -print -quit)"
[ -n "$dedicated_cached_bundle" ] || fail 'cached TC-269 companion bundle is missing'
[ -x "$dedicated_cached_bundle/TestProducts/Release-iphoneos/Runner.app/Runner" ] ||
  fail 'cached TC-269 Runner.app executable is missing or lost its mode'
[ -s "$dedicated_cached_bundle/TestProducts/Release-iphoneos/Runner.app/Info.plist" ] ||
  fail 'cached TC-269 Runner.app Info.plist is missing'
[ -x "$dedicated_cached_bundle/TestProducts/Release-iphoneos/Runner.app/PlugIns/Share Extension.appex/Share Extension" ] ||
  fail 'cached TC-269 Share Extension executable is missing'
[ -x "$dedicated_cached_bundle/TestProducts/Release-iphoneos/Runner.app/PlugIns/NotificationService.appex/NotificationService" ] ||
  fail 'cached TC-269 NotificationService executable is missing'
[ -x "$dedicated_cached_bundle/TestProducts/Release-iphoneos/RunnerUITests-Runner.app/RunnerUITests-Runner" ] ||
  fail 'cached TC-269 UI test host executable is missing'
[ -x "$dedicated_cached_bundle/TestProducts/Release-iphoneos/RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest/RunnerUITests" ] ||
  fail 'cached TC-269 UI test bundle executable is missing'
[ "$(wc -l <"$tmp_dir/codesign-verify.log" | tr -d ' ')" -eq "$((dedicated_codesign_before + 12))" ] ||
  fail 'TC-269 products were not codesign-verified before packaging and success'
python3 - "$dedicated_cached_bundle/bundle_manifest.json" "$dedicated_first_report" "$tmp_dir/xcode-build.log" <<'PY'
import json
import pathlib
import sys

bundle_manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
if bundle_manifest != {
    "schema": "mknoon.sims.ios-device-group-media-269-bundle.v1",
    "profileId": "ios.device.group_media_269",
    "applicationApp": "TestProducts/Release-iphoneos/Runner.app",
    "xctestrun": "RunnerUITests.xctestrun",
    "testProducts": "TestProducts",
    "centralCompileCommands": 1,
    "logicalBuildCount": 1,
    "childBuildCount": 0,
}:
    raise SystemExit("FAIL: TC-269 companion manifest is not exact")
report = json.loads(pathlib.Path(sys.argv[2]).read_text())
if report["builds"]["actualBuilds"] != 1:
    raise SystemExit("FAIL: TC-269 report did not record one logical build")
command = pathlib.Path(sys.argv[3]).read_text().splitlines()[-1]
required = (
    "-configuration Release",
    "-allowProvisioningUpdates",
    "ENABLE_TESTABILITY=YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) MKNOON_SIMS_GROUP_MEDIA_269",
    "CODE_SIGN_STYLE=Automatic",
    "PROVISIONING_PROFILE=",
    "PROVISIONING_PROFILE_SPECIFIER=",
    "MKNOON_RUNNER_CODE_SIGN_ENTITLEMENTS=Runner/GroupMedia269.empty.entitlements",
    "MKNOON_RUNNER_UI_TESTS_CODE_SIGN_ENTITLEMENTS=Runner/GroupMedia269.empty.entitlements",
    "MKNOON_SHARE_EXTENSION_CODE_SIGN_ENTITLEMENTS=Runner/GroupMedia269.empty.entitlements",
    "MKNOON_NOTIFICATION_SERVICE_CODE_SIGN_ENTITLEMENTS=Runner/GroupMedia269.empty.entitlements",
    "CUSTOM_GROUP_ID=group.com.mknoon.sims.groupmedia269.share",
    "MKNOON_RUNNER_BUNDLE_IDENTIFIER=com.mknoon.sims.groupmedia269",
    "MKNOON_RUNNER_TESTS_BUNDLE_IDENTIFIER=com.mknoon.sims.groupmedia269.RunnerTests",
    "MKNOON_RUNNER_UI_TESTS_BUNDLE_IDENTIFIER=com.mknoon.sims.groupmedia269.RunnerUITests",
    "MKNOON_SHARE_EXTENSION_BUNDLE_IDENTIFIER=com.mknoon.sims.groupmedia269.ShareExtension",
    "MKNOON_NOTIFICATION_SERVICE_BUNDLE_IDENTIFIER=com.mknoon.sims.groupmedia269.NotificationService",
)
for value in required:
    if value not in command:
        raise SystemExit(f"FAIL: TC-269 Xcode command lacks {value}")
if "CODE_SIGN_ENTITLEMENTS=" in command.split():
    raise SystemExit("FAIL: TC-269 command relies on a global entitlement override")
if "PRODUCT_BUNDLE_IDENTIFIER=" in command or " com.mknoon.app" in command:
    raise SystemExit("FAIL: TC-269 command can override or target the production bundle")
PY

rm -rf "$tmp_dir/group-media-derived" "$tmp_dir/prepared/group-media-bundle"
signing_identity="$(printf 'e%.0s' {1..64})"
write_signing_attestation
dedicated_second_report="$tmp_dir/group-media-second.json"
run_prepare "$dedicated_second_report"
[ "$(wc -l <"$tmp_dir/xcode-build.log" | tr -d ' ')" -eq "$((dedicated_compiles_before + 1))" ] ||
  fail 'TC-269 bundle depended on notification signing inputs or rebuilt after relocation'
[ "$(wc -l <"$tmp_dir/codesign-verify.log" | tr -d ' ')" -eq "$((dedicated_codesign_before + 12))" ] ||
  fail 'TC-269 cache hit reran or bypassed the attested codesign set'
python3 - "$dedicated_second_report" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text())
if report["builds"]["actualBuilds"] != 0 or report["builds"]["hits"] != 1:
    raise SystemExit("FAIL: relocated TC-269 companion bundle was not a cache hit")
PY

assert_ios_artifact_fault_rejected() {
  local fault="$1"
  local expected="$2"
  local case_root="$tmp_dir/fault-$fault"
  mkdir -p "$case_root/cache" "$case_root/prepared"
  : >"$case_root/xcode.log"
  : >"$case_root/flutter.log"
  : >"$case_root/codesign.log"
  if PATH="$tmp_dir/bin:$PATH" \
    SIMS_MANIFEST="$manifest" \
    SIMS_REPORT_PATH="$case_root/report.json" \
    SIMS_CACHE_DIR="$case_root/cache" \
    SIMS_IOS_DEVICE_GROUP_MEDIA_269_DERIVED_DATA="$case_root/derived" \
    SIMS_IOS_DEVICE_GROUP_MEDIA_269_BUNDLE_PATH="$case_root/prepared/bundle" \
    SIMS_SOURCE_DIGEST="$fixture_source" \
    SIMS_TEST_ALLOW_SOURCE_DIGEST_OVERRIDE=1 \
    SIMS_TEST_IOS_ARTIFACT_FAULT="$fault" \
    XCODE_BUILD_LOG="$case_root/xcode.log" \
    FLUTTER_BUILD_LOG="$case_root/flutter.log" \
    CODESIGN_VERIFY_LOG="$case_root/codesign.log" \
    ./scripts/run_test_gates.sh sims major --prepare-builds --list --format json \
      >"$case_root/stdout" 2>"$case_root/stderr"; then
    fail "$fault artifact unexpectedly received a successful build attestation"
  fi
  if ! grep -Fq "$expected" "$case_root/stdout" "$case_root/stderr"; then
    cat "$case_root/stdout" "$case_root/stderr" >&2
    fail "$fault failure did not report the exact rejected artifact member"
  fi
  [ "$(wc -l <"$case_root/xcode.log" | tr -d ' ')" -eq 1 ] ||
    fail "$fault did not execute exactly one central Xcode attempt"
  [ ! -s "$case_root/flutter.log" ] ||
    fail "$fault invoked a duplicate Flutter build"
  [ -z "$(find "$case_root/cache" -name attestation.json -print -quit)" ] ||
    fail "$fault wrote a cache attestation for an invalid artifact"
  [ ! -d "$case_root/prepared/bundle" ] ||
    fail "$fault packaged an invalid artifact"
  if [ "$fault" = 'invalid-ui-test-signature' ]; then
    [ -s "$case_root/codesign.log" ] ||
      fail 'invalid nested signature was rejected without a codesign check'
    grep -Fq 'RunnerUITests.xctest' "$case_root/codesign.log" ||
      fail 'invalid nested UI-test signature was not checked directly'
  else
    [ ! -s "$case_root/codesign.log" ] ||
      fail "$fault reached codesign before structural validation failed"
  fi
}

assert_ios_artifact_fault_rejected \
  missing-runner-plist 'Runner.app/Info.plist'
assert_ios_artifact_fault_rejected \
  missing-ui-host-executable 'RunnerUITests host executable'
assert_ios_artifact_fault_rejected \
  second-xctestrun 'exactly one non-empty .xctestrun'
assert_ios_artifact_fault_rejected \
  invalid-ui-test-signature 'codesign verification failed for RunnerUITests.xctest'

printf 'PASS: iOS physical companion profiles preserve production signing and isolate TC-269 bundle IDs, entitlements, and cache\n'
