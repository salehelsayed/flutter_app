#!/usr/bin/env bash

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly GRADLEW="$REPO_ROOT/android/gradlew"
readonly IOS_WORKSPACE="$REPO_ROOT/ios/Runner.xcworkspace"
readonly IOS_PROJECT="$REPO_ROOT/ios/Runner.xcodeproj/project.pbxproj"
readonly FIXTURE_RELATIVE="test/shared/fixtures/app_visibility_snapshot_v1.json"
readonly FIXTURE="$REPO_ROOT/$FIXTURE_RELATIVE"
readonly SWIFT_TEST="$REPO_ROOT/ios/RunnerTests/IosAppVisibilitySnapshotTests.swift"
readonly KOTLIN_STORE_TEST="$REPO_ROOT/android/app/src/test/kotlin/com/mknoon/app/AppVisibilitySnapshotStoreTest.kt"
readonly ANDROID_BUILD="$REPO_ROOT/android/app/build.gradle.kts"
readonly RUNNER_PRIVACY="$REPO_ROOT/ios/Runner/PrivacyInfo.xcprivacy"
readonly NSE_PRIVACY="$REPO_ROOT/ios/NotificationService/PrivacyInfo.xcprivacy"
readonly XCODE_TEST_CLASS="RunnerTests/IosAppVisibilitySnapshotTests"
readonly XCODE_TEST_ATOMIC="testTC37106AtomicSnapshotLifecycleAndPrivacyContract"
readonly XCODE_TEST_COALESCING="testTC37106DuplicateUIApplicationAndUISceneActiveDoesNotClearInterleavedRouteCAS"
readonly JVM_STORE_PATTERN="com.mknoon.app.AppVisibilitySnapshotStoreTest.TC-371-07 v1 store is atomic fresh and fail-notify"
readonly JVM_LIFECYCLE_PATTERN="com.mknoon.app.MainActivityAppVisibilityTest.TC-371-07 lifecycle and stale route CAS preserve newest state"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

run_logged() {
  local label="$1"
  local log="$2"
  shift 2
  printf 'Running %s\n' "$label"
  if ! "$@" >"$log" 2>&1; then
    tail -n 160 "$log" >&2 || true
    fail "$label failed; full log retained at $log"
  fi
}

for command_name in ditto find jq plutil python3 rg xcodebuild xcrun; do
  require_command "$command_name"
done
[[ -x "$GRADLEW" ]] || fail "Gradle wrapper is not executable: $GRADLEW"

if [[ -n "${PLAN371_NATIVE_RESULT_DIR:-}" ]]; then
  result_dir="$PLAN371_NATIVE_RESULT_DIR"
  mkdir -p "$result_dir"
else
  result_dir="$(mktemp -d /tmp/plan371-native.XXXXXX)"
fi
result_dir="$(cd "$result_dir" && pwd)"
readonly RESULT_DIR="$result_dir"

remove_owned_derived_data() {
  local derived_data_dir="$1"
  case "$derived_data_dir" in
    "$RESULT_DIR"/runner-derived.*|\
    "$RESULT_DIR"/nse-derived.*|\
    "$RESULT_DIR"/xctest-derived.*)
      ;;
    *)
      fail "refusing to remove an unowned DerivedData directory: $derived_data_dir"
      ;;
  esac
  if [[ -e "$derived_data_dir" ]]; then
    find "$derived_data_dir" -depth -delete
  fi
  [[ ! -e "$derived_data_dir" ]] ||
    fail "could not remove runner-owned DerivedData: $derived_data_dir"
}

cleanup_owned_derived_data() {
  local derived_data_dir
  for derived_data_dir in \
    "${runner_derived:-}" \
    "${nse_derived:-}" \
    "${xctest_derived:-}"; do
    if [[ -n "$derived_data_dir" ]]; then
      remove_owned_derived_data "$derived_data_dir"
    fi
  done
}
trap cleanup_owned_derived_data EXIT

fixture_paths="$(
  cd "$REPO_ROOT"
  rg --files test ios android -g 'app_visibility_snapshot_v1.json' | sort
)"
[[ "$fixture_paths" == "$FIXTURE_RELATIVE" ]] ||
  fail "expected exactly one repository app-visibility fixture, found: $fixture_paths"
[[ -s "$FIXTURE" ]] || fail "shared fixture is missing or empty: $FIXTURE"
rg -Fq "$FIXTURE_RELATIVE" "$SWIFT_TEST" ||
  fail "Runner XCTest does not resolve the single repository fixture"
rg -Fq 'resources.srcDir("../../test/shared/fixtures")' "$ANDROID_BUILD" ||
  fail "Gradle test resources do not include the single repository fixture"
rg -Fq 'app_visibility_snapshot_v1.json' "$KOTLIN_STORE_TEST" ||
  fail "Android store XCTest equivalent does not consume the shared fixture"
rg -Fq '@testable import Runner' "$SWIFT_TEST" ||
  fail "RunnerTests must import Runner instead of recompiling the shared source"
[[ "$(rg -F -c 'IosAppVisibilitySnapshot.swift in Sources' "$IOS_PROJECT")" -eq 2 ]] ||
  fail "shared Swift source must have one explicit Runner build-file membership"
[[ "$(rg -F -c 'app_visibility_snapshot_v1.json in Resources' "$IOS_PROJECT")" -eq 2 ]] ||
  fail "the single repository fixture must have one RunnerTests resource membership"

readonly -a PROOF_FLAGS=(
  -PenableAppVisibility371Proof=true
  -PandroidApplicationId=com.mknoon.app.visibilityproof
  -PdisableGoogleServicesForDisposableProof=true
)

readonly JVM_LOG="$RESULT_DIR/android-jvm.log"
run_logged \
  "the two exact TC-371-07 JVM tests" \
  "$JVM_LOG" \
  "$GRADLEW" -p "$REPO_ROOT/android" --console=plain --info \
    :app:testDebugUnitTest \
    "${PROOF_FLAGS[@]}" \
    --tests "$JVM_STORE_PATTERN" \
    --tests "$JVM_LIFECYCLE_PATTERN"
rg -Fq 'BUILD SUCCESSFUL' "$JVM_LOG" ||
  fail "the exact JVM Gradle invocation did not report BUILD SUCCESSFUL"

readonly JVM_RESULTS="$REPO_ROOT/build/app/test-results/testDebugUnitTest"
python3 - "$JVM_RESULTS" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

result_dir = Path(sys.argv[1])
expected = {
    (
        "com.mknoon.app.AppVisibilitySnapshotStoreTest",
        "TC-371-07 v1 store is atomic fresh and fail-notify",
    ),
    (
        "com.mknoon.app.MainActivityAppVisibilityTest",
        "TC-371-07 lifecycle and stale route CAS preserve newest state",
    ),
}
observed = set()
for path in sorted(result_dir.glob("TEST-*.xml")):
    root = ET.parse(path).getroot()
    if any(int(root.attrib.get(key, "0")) != 0 for key in ("failures", "errors", "skipped")):
        raise SystemExit(f"{path} contains a failed, errored, or skipped test")
    for case in root.findall(".//testcase"):
        if case.find("failure") is not None or case.find("error") is not None or case.find("skipped") is not None:
            raise SystemExit(f"{path} contains a non-passing testcase")
        observed.add((case.attrib.get("classname", ""), case.attrib.get("name", "")))
if observed != expected:
    raise SystemExit(f"expected exactly the two TC-371-07 JVM tests, observed {sorted(observed)!r}")
PY
mkdir -p "$RESULT_DIR/android-jvm-results"
cp "$JVM_RESULTS"/TEST-*.xml "$RESULT_DIR/android-jvm-results/"

readonly ANDROID_COMPILE_LOG="$RESULT_DIR/android-compile.log"
run_logged \
  "Plan 371 debug and Android-test Kotlin compilation" \
  "$ANDROID_COMPILE_LOG" \
  "$GRADLEW" -p "$REPO_ROOT/android" --console=plain \
    :app:compileDebugKotlin \
    :app:compileDebugAndroidTestKotlin \
    "${PROOF_FLAGS[@]}"
rg -Fq 'BUILD SUCCESSFUL' "$ANDROID_COMPILE_LOG" ||
  fail "the flagged Android compile invocation did not report BUILD SUCCESSFUL"

runner_derived="$(mktemp -d "$RESULT_DIR/runner-derived.XXXXXX")"
nse_derived="$(mktemp -d "$RESULT_DIR/nse-derived.XXXXXX")"
readonly RUNNER_BUILD_LOG="$RESULT_DIR/runner-simulator-build.log"
readonly NSE_BUILD_LOG="$RESULT_DIR/nse-simulator-build.log"
run_logged \
  "generic Runner simulator build" \
  "$RUNNER_BUILD_LOG" \
  xcodebuild -quiet \
    -derivedDataPath "$runner_derived" \
    -workspace "$IOS_WORKSPACE" \
    -scheme Runner \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO \
    build

# Runner's shared scheme prepares Flutter.framework before SwiftPM compiles its
# plugins. Xcode's autogenerated extension scheme also schedules the host's
# plugins, but does not run that scheme pre-action. Seed only the same prepared
# engine in this independent DerivedData directory; the extension and its host
# dependencies must still compile here, and no engine is linked into the NSE.
readonly RUNNER_FLUTTER_FRAMEWORK="$runner_derived/Build/Products/Debug-iphonesimulator/Flutter.framework"
readonly NSE_FLUTTER_FRAMEWORK="$nse_derived/Build/Products/Debug-iphonesimulator/Flutter.framework"
for engine_file in Flutter Headers/Flutter.h Modules/module.modulemap; do
  [[ -s "$RUNNER_FLUTTER_FRAMEWORK/$engine_file" ]] ||
    fail "Runner's prepared simulator Flutter framework is incomplete: $engine_file"
done
run_logged \
  "standalone NSE Flutter SwiftPM engine preparation" \
  "$RESULT_DIR/nse-flutter-engine-prepare.log" \
  ditto "$RUNNER_FLUTTER_FRAMEWORK" "$NSE_FLUTTER_FRAMEWORK"

run_logged \
  "generic NotificationService simulator build" \
  "$NSE_BUILD_LOG" \
  xcodebuild -quiet \
    -derivedDataPath "$nse_derived" \
    -workspace "$IOS_WORKSPACE" \
    -scheme NotificationService \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO \
    build

readonly BUILT_RUNNER_PRIVACY="$runner_derived/Build/Products/Debug-iphonesimulator/Runner.app/PrivacyInfo.xcprivacy"
readonly BUILT_EMBEDDED_NSE_PRIVACY="$runner_derived/Build/Products/Debug-iphonesimulator/Runner.app/PlugIns/NotificationService.appex/PrivacyInfo.xcprivacy"
readonly BUILT_STANDALONE_NSE_PRIVACY="$nse_derived/Build/Products/Debug-iphonesimulator/NotificationService.appex/PrivacyInfo.xcprivacy"

assert_privacy_manifest() {
  local manifest="$1"
  local collection_expectation="$2"
  local expected_first="$3"
  local expected_second="$4"
  [[ -s "$manifest" ]] || fail "privacy manifest is missing or empty: $manifest"
  case "$collection_expectation" in
    runner-device-id|empty) ;;
    *) fail "unknown privacy collection expectation: $collection_expectation" ;;
  esac
  plutil -lint "$manifest"
  plutil -convert json -o - "$manifest" | jq -e \
    --arg collection "$collection_expectation" \
    --arg first "$expected_first" \
    --arg second "$expected_second" '
      .NSPrivacyTracking == false and
      .NSPrivacyTrackingDomains == [] and
      (
        ($collection == "runner-device-id" and
          .NSPrivacyCollectedDataTypes == [{
            NSPrivacyCollectedDataType: "NSPrivacyCollectedDataTypeDeviceID",
            NSPrivacyCollectedDataTypeLinked: true,
            NSPrivacyCollectedDataTypeTracking: false,
            NSPrivacyCollectedDataTypePurposes: [
              "NSPrivacyCollectedDataTypePurposeAppFunctionality"
            ]
          }]) or
        ($collection == "empty" and .NSPrivacyCollectedDataTypes == [])
      ) and
      ([.NSPrivacyAccessedAPITypes[] |
        "\(.NSPrivacyAccessedAPIType):\(.NSPrivacyAccessedAPITypeReasons | sort | join(","))"
      ] | sort) == ([$first, $second] | sort)
    ' >/dev/null
}

readonly PRIVACY_LOG="$RESULT_DIR/privacy-manifests.log"
{
  assert_privacy_manifest \
    "$RUNNER_PRIVACY" \
    runner-device-id \
    'NSPrivacyAccessedAPICategorySystemBootTime:35F9.1' \
    'NSPrivacyAccessedAPICategoryDiskSpace:E174.1'
  assert_privacy_manifest \
    "$NSE_PRIVACY" \
    empty \
    'NSPrivacyAccessedAPICategorySystemBootTime:35F9.1' \
    'NSPrivacyAccessedAPICategoryFileTimestamp:C617.1'
  assert_privacy_manifest \
    "$BUILT_RUNNER_PRIVACY" \
    runner-device-id \
    'NSPrivacyAccessedAPICategorySystemBootTime:35F9.1' \
    'NSPrivacyAccessedAPICategoryDiskSpace:E174.1'
  assert_privacy_manifest \
    "$BUILT_EMBEDDED_NSE_PRIVACY" \
    empty \
    'NSPrivacyAccessedAPICategorySystemBootTime:35F9.1' \
    'NSPrivacyAccessedAPICategoryFileTimestamp:C617.1'
  assert_privacy_manifest \
    "$BUILT_STANDALONE_NSE_PRIVACY" \
    empty \
    'NSPrivacyAccessedAPICategorySystemBootTime:35F9.1' \
    'NSPrivacyAccessedAPICategoryFileTimestamp:C617.1'
  cmp "$RUNNER_PRIVACY" "$BUILT_RUNNER_PRIVACY"
  cmp "$NSE_PRIVACY" "$BUILT_EMBEDDED_NSE_PRIVACY"
  cmp "$NSE_PRIVACY" "$BUILT_STANDALONE_NSE_PRIVACY"
} >"$PRIVACY_LOG" 2>&1
cp "$BUILT_RUNNER_PRIVACY" "$RESULT_DIR/Runner-PrivacyInfo.xcprivacy"
cp "$BUILT_EMBEDDED_NSE_PRIVACY" \
  "$RESULT_DIR/NotificationService-embedded-PrivacyInfo.xcprivacy"
cp "$BUILT_STANDALONE_NSE_PRIVACY" \
  "$RESULT_DIR/NotificationService-standalone-PrivacyInfo.xcprivacy"
remove_owned_derived_data "$runner_derived"
remove_owned_derived_data "$nse_derived"

readonly IOS_DEVICES_JSON="$RESULT_DIR/ios-devices.json"
xcrun simctl list devices available -j >"$IOS_DEVICES_JSON"
simulator_id="$(
  jq -r '
    [
      .devices | to_entries[] |
      select(.key | contains("iOS")) |
      .value[] |
      select((.isAvailable // true) == true) |
      select(.name | startswith("iPhone"))
    ][0].udid // empty
  ' "$IOS_DEVICES_JSON"
)"

readonly IOS_DISPOSITION="$RESULT_DIR/ios-xctest-disposition.txt"
if [[ -z "$simulator_id" ]]; then
  printf '%s\n' \
    'N/A (target unavailable by project policy): no available iPhone simulator' \
    >"$IOS_DISPOSITION"
else
  simulator_state="$(
    jq -r --arg id "$simulator_id" '
      [.devices[][] | select(.udid == $id)][0].state // "Shutdown"
    ' "$IOS_DEVICES_JSON"
  )"
  if [[ "$simulator_state" != "Booted" ]]; then
    xcrun simctl boot "$simulator_id" >"$RESULT_DIR/ios-simulator-boot.log" 2>&1 || true
    xcrun simctl bootstatus "$simulator_id" -b \
      >>"$RESULT_DIR/ios-simulator-boot.log" 2>&1 ||
      fail "available iPhone simulator did not finish booting: $simulator_id"
  fi
  xcrun simctl list devices booted -j | jq -e --arg id "$simulator_id" '
    any(.devices[][]; .udid == $id and (.isAvailable // true) == true)
  ' >/dev/null || fail "selected iPhone simulator is not booted: $simulator_id"

  xctest_derived="$(mktemp -d "$RESULT_DIR/xctest-derived.XXXXXX")"
  xctest_result="$RESULT_DIR/ios-xctest-$(date -u +%Y%m%dT%H%M%SZ)-$$.xcresult"
  xctest_log="$RESULT_DIR/ios-xctest.log"
  run_logged \
    "the exact two-method TC-371-06 XCTest owner on $simulator_id" \
    "$xctest_log" \
    xcodebuild -quiet \
      -derivedDataPath "$xctest_derived" \
      -workspace "$IOS_WORKSPACE" \
      -scheme Runner \
      -configuration Debug \
      -destination "platform=iOS Simulator,id=$simulator_id" \
      -parallel-testing-enabled NO \
      -resultBundlePath "$xctest_result" \
      -only-testing:"$XCODE_TEST_CLASS/$XCODE_TEST_ATOMIC" \
      -only-testing:"$XCODE_TEST_CLASS/$XCODE_TEST_COALESCING" \
      CODE_SIGNING_ALLOWED=NO \
      test

  built_test_fixture_matches="$(
    find "$xctest_derived" \
      -type f \
      -path '*/RunnerTests.xctest/app_visibility_snapshot_v1.json' \
      -print
  )"
  built_test_fixture_count="$(
    printf '%s\n' "$built_test_fixture_matches" |
      sed '/^$/d' |
      wc -l |
      tr -d '[:space:]'
  )"
  [[ "$built_test_fixture_count" -eq 1 ]] ||
    fail "expected one built RunnerTests fixture, found $built_test_fixture_count: $built_test_fixture_matches"
  built_test_fixture="$built_test_fixture_matches"
  [[ -s "$built_test_fixture" ]] ||
    fail "the unique RunnerTests fixture is empty: $built_test_fixture"
  cmp "$FIXTURE" "$built_test_fixture" ||
    fail "RunnerTests bundled fixture differs from the single repository fixture"
  cp "$built_test_fixture" "$RESULT_DIR/app_visibility_snapshot_v1.bundled.json"

  xcrun xcresulttool get test-results summary \
    --path "$xctest_result" --compact \
    >"$RESULT_DIR/ios-xctest-summary.json"
  jq -e '
    .result == "Passed" and
    .totalTestCount == 2 and
    .passedTests == 2 and
    .failedTests == 0 and
    .skippedTests == 0
  ' "$RESULT_DIR/ios-xctest-summary.json" >/dev/null ||
    fail "TC-371-06 XCTest summary was not exactly two passes and zero skips"

  xcrun xcresulttool get test-results tests \
    --path "$xctest_result" --compact \
    >"$RESULT_DIR/ios-xctest-tests.json"
  jq -e \
    --arg atomic "$XCODE_TEST_ATOMIC" \
    --arg coalescing "$XCODE_TEST_COALESCING" '
      [
        .. | objects |
        select(.nodeType? == "Test Case") |
        {name: (.name | sub("\\(\\)$"; "")), result}
      ] | sort_by(.name) == (
        [
          {name: $atomic, result: "Passed"},
          {name: $coalescing, result: "Passed"}
        ] | sort_by(.name)
      )
    ' "$RESULT_DIR/ios-xctest-tests.json" >/dev/null ||
    fail "XCTest result did not contain exactly the two named TC-371-06 methods"
  remove_owned_derived_data "$xctest_derived"
  printf 'PASS: exact TC-371-06 XCTest owner on %s\n' "$simulator_id" \
    >"$IOS_DISPOSITION"
fi

printf 'PASS: Plan 371 native host contract; evidence: %s\n' "$RESULT_DIR"
