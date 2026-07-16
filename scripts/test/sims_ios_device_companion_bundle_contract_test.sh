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
touch "$tmp_dir/xcode-build.log" "$tmp_dir/flutter-build.log"

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
testability_seen=false
for argument in "$@"; do
  if [ "$previous" = "-derivedDataPath" ]; then derived="$argument"; fi
  if [ "$argument" = 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP' ]; then
    bootstrap_condition_seen=true
  fi
  if [ "$argument" = 'ENABLE_TESTABILITY=YES' ]; then
    testability_seen=true
  fi
  previous="$argument"
done
[ -n "$derived" ] || exit 93
[ "$bootstrap_condition_seen" = true ] || exit 94
[ "$testability_seen" = true ] || exit 95
printf '%s\n' "$*" >>"${XCODE_BUILD_LOG:?}"
products="$derived/Build/Products"
app="$products/Release-iphoneos/Runner.app"
tests="$products/Release-iphoneos/RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest"
mkdir -p "$app/Frameworks" "$tests"
printf 'signed runner fixture\n' >"$app/Runner"
printf 'plist fixture\n' >"$app/Info.plist"
printf 'ui test fixture\n' >"$tests/RunnerUITests"
chmod 755 "$app/Runner" "$tests/RunnerUITests"
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
    SIMS_IOS_NOTIFICATION_STAGING_MANIFEST="$staging_attestation" \
    SIMS_IOS_PROVISIONING_PROFILE_PATH="$provisioning_profile" \
    SIMS_IOS_PHYSICAL_DEVICE_ID="$receiver_device" \
    DEVELOPMENT_TEAM="$fixture_team" \
    PROVISIONING_PROFILE_SPECIFIER='fixture-profile' \
    SIMS_SOURCE_DIGEST="$fixture_source" \
    SIMS_TEST_ALLOW_SOURCE_DIGEST_OVERRIDE=1 \
    XCODE_BUILD_LOG="$tmp_dir/xcode-build.log" \
    FLUTTER_BUILD_LOG="$tmp_dir/flutter-build.log" \
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
[ -f "$cached_bundle/RunnerUITests.xctestrun" ] ||
  fail 'cached xctestrun is missing'
[ -f "$cached_bundle/TestProducts/Release-iphoneos/RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest/RunnerUITests" ] ||
  fail 'cached UI test product is missing'
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

printf 'PASS: iOS physical companion bundle cache binds source, signing, provisioning, device, and expiry inputs\n'
