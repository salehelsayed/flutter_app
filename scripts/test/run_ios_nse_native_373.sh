#!/usr/bin/env bash

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly GO_ROOT="$REPO_ROOT/go-mknoon"
readonly IOS_WORKSPACE="$REPO_ROOT/ios/Runner.xcworkspace"
readonly IOS_PROJECT="$REPO_ROOT/ios/Runner.xcodeproj/project.pbxproj"
readonly FINAL_EFFECT_SOURCE="$REPO_ROOT/ios/NotificationService/IosLocalNotificationFinalEffect.swift"
readonly NSE_COORDINATOR_SOURCE="$REPO_ROOT/ios/NotificationService/NseMailboxWakeCoordinator.swift"
readonly RUNNER_ENTITLEMENTS="$REPO_ROOT/ios/Runner/Runner.entitlements"
readonly NSE_ENTITLEMENTS="$REPO_ROOT/ios/NotificationService/NotificationService.entitlements"
readonly NSE_INFO="$REPO_ROOT/ios/NotificationService/Info.plist"
readonly RUNNER_PRIVACY="$REPO_ROOT/ios/Runner/PrivacyInfo.xcprivacy"
readonly NSE_PRIVACY="$REPO_ROOT/ios/NotificationService/PrivacyInfo.xcprivacy"
readonly MAILBOX_FIXTURE_RELATIVE="test/shared/fixtures/ios_nse_mailbox_v1.json"
readonly LEDGER_FIXTURE_RELATIVE="test/shared/fixtures/local_notification_ledger_v1.json"
readonly MAILBOX_FIXTURE="$REPO_ROOT/$MAILBOX_FIXTURE_RELATIVE"
readonly LEDGER_FIXTURE="$REPO_ROOT/$LEDGER_FIXTURE_RELATIVE"
readonly FRAMEWORK_ROOT="$REPO_ROOT/ios/Runner/GoMknoonNSE.xcframework"
readonly BINDING_STAMP="$REPO_ROOT/ios/Runner/GoMknoon.inputs.sha256"
readonly BINDING_INPUT_HELPER="$REPO_ROOT/scripts/gomobile_binding_inputs.sh"
readonly BINDING_VERIFY="$REPO_ROOT/scripts/verify_gomobile_bindings.sh"
readonly DEVICE_HEADER="$FRAMEWORK_ROOT/ios-arm64/GoMknoonNSE.framework/Headers/Bridge.objc.h"
readonly SIMULATOR_HEADER="$FRAMEWORK_ROOT/ios-arm64_x86_64-simulator/GoMknoonNSE.framework/Headers/Bridge.objc.h"
readonly TC37305="RunnerTests/IosNseMailboxWakeCoordinatorTests/testTC37305AuthenticatedCandidatesShareOneFinalEffectOwner"
readonly TC39803_PYTHON="scripts.test.ios_receiver_bootstrap_test.IosReceiverBootstrapTest.test_group_observation_recovers_terminal_native_failure_after_final_termination_pull"
readonly RUN_TAG="$(date -u +%Y%m%dT%H%M%SZ)-$$"

readonly -a FOCUSED_GO_TESTS=(
  TestNSEInboxBridgeRejectsIdentityMismatchAndDoesNotUseSingleton
  TestNSEInboxBridgeReturnsStrictBoundedPage
  TestNSEInboxOneShotAuthenticatesPeerAndRetrievesProtectedPage
  TestNSEInboxOneShotBoundsDeadlineClosesHostAndNeverAcknowledges
)
readonly -a PRESERVATION_GO_TESTS=(
  TestInboxAckCustodyReceiveFanoutContract
  TestTC364GroupContentProtectedCustody
  TestDispatchInboxAckCustodyContract
  TestBridgeExportedHandlersUseSharedEntrypoint
)
readonly -a XCODE_TESTS=(
  RunnerTests/IosNseMailboxWakeCoordinatorTests/testTC37303ExactFixedGrammarAndRichCompatibility
  RunnerTests/IosNseMailboxWakeCoordinatorTests/testTC37304OperationalFailureAndExpiryPreserveGenericOnce
  RunnerTests/IosNseMailboxWakeCoordinatorTests/testTC37305AuthenticatedCandidatesShareOneFinalEffectOwner
  RunnerTests/IosNseMailboxWakeCoordinatorTests/testTC37306LegacyGroupAndUnsupportedRowsDoNotInventAuthority
  RunnerTests/NotificationPreviewResolverTests/testDecryptsOneToOneFixturePreview
  RunnerTests/NotificationPreviewResolverTests/testDecryptsGroupFixturePreview
  RunnerTests/NotificationPreviewResolverTests/testGroupReactionUsesProjectedContextAndClaimsOnlyAfterExactParity
  RunnerTests/NotificationPreviewResolverTests/testNotificationServiceCompletionGateExpiryBeforeResolutionRejectsPublisher
  RunnerTests/NotificationPreviewResolverTests/testNotificationServiceCompletionGateRejectsStaleRequestGeneration
  RunnerTests/NotificationPreviewResolverTests/testRejectedNormalAuthMuteDedupeMalformedAndOversizedSanitizeProviderMetadata
  RunnerTests/NotificationPreviewResolverTests/testKeychainReaderUsesEntitledAccessGroupAndRealSecurityQueryKeys
  RunnerTests/NotificationServiceConfigurationTests/testRunnerAndNotificationServiceEntitlementsShareAppGroupAndKeychainGroup
  RunnerTests/NotificationServiceConfigurationTests/testNotificationServiceInfoPlistUsesUserNotificationsServicePoint
  RunnerTests/IosNotificationRecoveryTests/testProductionHandoffSeamClaimsBeforeHandlerAndCommitsAfter
  RunnerTests/IosNotificationRecoveryTests/testTC395ExactGroupInviteRetirementIsSurgicalAndIdempotent
  RunnerTests/IosNotificationRecoveryTests/testTC398GroupInventoryFiltersBeforeBoundAndMapsClosedDiagnostics
  RunnerTests/IosNotificationRecoveryTests/testTC398GroupObservationPassRequiresCanonicalRequestIdentifier
  RunnerTests/IosNotificationRecoveryTests/testTC398GroupFullHorizonLatchesTransientDiagnosticUnion
  RunnerTests/IosReceiverBootstrapHandoffTests/testTC398GroupObservationReceiptPersistsBoundedPerCardDiagnostics
  RunnerTests/IosAppVisibilitySnapshotTests/testTC37106AtomicSnapshotLifecycleAndPrivacyContract
  RunnerTests/IosAppVisibilitySnapshotTests/testTC37106DuplicateUIApplicationAndUISceneActiveDoesNotClearInterleavedRouteCAS
)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command is unavailable: $1"
}

run_logged() {
  local label="$1"
  local log="$2"
  shift 2
  printf 'Running %s\n' "$label"
  if ! "$@" >"$log" 2>&1; then
    tail -n 180 "$log" >&2 || true
    fail "$label failed; full log retained at $log"
  fi
}

for command_name in cmp cp date find flutter go jq plutil python3 rg sed sort tail tr uniq wc xcodebuild xcrun; do
  require_command "$command_name"
done

[[ -f "$BINDING_INPUT_HELPER" ]] ||
  fail "gomobile input helper is missing: $BINDING_INPUT_HELPER"
# shellcheck source=../gomobile_binding_inputs.sh
source "$BINDING_INPUT_HELPER"

if [[ -n "${PLAN373_NATIVE_RESULT_DIR:-}" ]]; then
  result_dir="$PLAN373_NATIVE_RESULT_DIR"
  mkdir -p "$result_dir"
else
  result_dir="$(mktemp -d /tmp/plan373-native.XXXXXX)"
fi
result_dir="$(cd "$result_dir" && pwd)"
readonly RESULT_DIR="$result_dir"

runner_derived=''
mutation_derived=''
xctest_derived=''
mutation_backup=''
mutation_original_sha=''
mutation_active=0

remove_owned_derived_data() {
  local derived_data_dir="$1"
  case "$derived_data_dir" in
    "$RESULT_DIR"/runner-derived.*|\
    "$RESULT_DIR"/mutation-derived.*|\
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

cleanup() {
  local status=$?
  local current_sha=''
  trap - EXIT
  if [[ -n "${mutation_backup:-}" && -f "$mutation_backup" ]]; then
    if [[ -f "$FINAL_EFFECT_SOURCE" ]]; then
      current_sha="$(gomobile_sha256_file "$FINAL_EFFECT_SOURCE" 2>/dev/null || true)"
    fi
    if [[ "$mutation_active" -eq 1 || "$current_sha" != "$mutation_original_sha" ]]; then
      if ! cp "$mutation_backup" "$FINAL_EFFECT_SOURCE"; then
        printf 'FAIL: could not restore mutated Swift source from %s\n' \
          "$mutation_backup" >&2
        status=1
      fi
    fi
  fi
  local derived_data_dir
  for derived_data_dir in \
    "${runner_derived:-}" \
    "${mutation_derived:-}" \
    "${xctest_derived:-}"; do
    if [[ -n "$derived_data_dir" && -e "$derived_data_dir" ]]; then
      case "$derived_data_dir" in
        "$RESULT_DIR"/runner-derived.*|\
        "$RESULT_DIR"/mutation-derived.*|\
        "$RESULT_DIR"/xctest-derived.*)
          find "$derived_data_dir" -depth -delete || status=1
          ;;
        *)
          printf 'FAIL: refusing cleanup of unowned DerivedData: %s\n' \
            "$derived_data_dir" >&2
          status=1
          ;;
      esac
    fi
  done
  exit "$status"
}
trap cleanup EXIT

sorted_lines() {
  LC_ALL=C sort
}

assert_unique_exact_count() {
  local expected_count="$1"
  shift
  local observed_count
  local unique_count
  observed_count="$#"
  unique_count="$(printf '%s\n' "$@" | sorted_lines | uniq | wc -l | tr -d '[:space:]')"
  [[ "$observed_count" -eq "$expected_count" && "$unique_count" -eq "$expected_count" ]] ||
    fail "expected $expected_count unique values, observed $observed_count values / $unique_count unique"
}

assert_unique_exact_count 4 "${FOCUSED_GO_TESTS[@]}"
assert_unique_exact_count 4 "${PRESERVATION_GO_TESTS[@]}"
assert_unique_exact_count 21 "${XCODE_TESTS[@]}"

run_go_test() {
  (
    cd "$GO_ROOT"
    GOTOOLCHAIN=go1.25.0 go test "$@"
  )
}

validate_go_discovery() {
  local log="$1"
  shift
  local expected
  local observed
  expected="$(printf '%s\n' "$@" | sorted_lines)"
  observed="$(rg '^Test[A-Za-z0-9_]+$' "$log" | sorted_lines || true)"
  [[ "$observed" == "$expected" ]] ||
    fail "Go discovery in $log was not the exact frozen root set"
  ! rg -q 'no tests to run|^[[:space:]]*--- SKIP:' "$log" ||
    fail "Go discovery was vacuous or skipped in $log"
}

validate_go_passes() {
  local log="$1"
  shift
  local name
  for name in "$@"; do
    [[ "$(rg -c "^=== RUN[[:space:]]+$name$" "$log" || true)" -eq 1 ]] ||
      fail "$name did not start exactly once in $log"
    [[ "$(rg -c "^--- PASS: $name " "$log" || true)" -eq 1 ]] ||
      fail "$name did not report one root PASS in $log"
  done
  [[ "$(rg -c '^--- PASS: Test' "$log" || true)" -eq "$#" ]] ||
    fail "Go run in $log reported an unexpected root PASS set"
  ! rg -q '^[[:space:]]*--- SKIP:|^--- FAIL:|panic:|build failed|no tests to run' "$log" ||
    fail "Go run failed, skipped, panicked, or was vacuous in $log"
}

focused_regex='^(TestNSEInboxBridgeRejectsIdentityMismatchAndDoesNotUseSingleton|TestNSEInboxBridgeReturnsStrictBoundedPage|TestNSEInboxOneShotAuthenticatesPeerAndRetrievesProtectedPage|TestNSEInboxOneShotBoundsDeadlineClosesHostAndNeverAcknowledges)$'
preservation_regex='^(TestInboxAckCustodyReceiveFanoutContract|TestTC364GroupContentProtectedCustody|TestDispatchInboxAckCustodyContract|TestBridgeExportedHandlersUseSharedEntrypoint)$'

readonly GO_FOCUSED_DISCOVERY_LOG="$RESULT_DIR/go-focused-discovery.log"
readonly GO_FOCUSED_LOG="$RESULT_DIR/go-focused.log"
readonly GO_FOCUSED_RACE_LOG="$RESULT_DIR/go-focused-race.log"
readonly GO_PRESERVATION_DISCOVERY_LOG="$RESULT_DIR/go-preservation-discovery.log"
readonly GO_PRESERVATION_LOG="$RESULT_DIR/go-preservation.log"

run_logged "the exact four TC-373-01 Go roots discovery" \
  "$GO_FOCUSED_DISCOVERY_LOG" \
  run_go_test ./node ./bridge -list "$focused_regex"
validate_go_discovery "$GO_FOCUSED_DISCOVERY_LOG" "${FOCUSED_GO_TESTS[@]}"
run_logged "the exact four TC-373-01 Go roots" \
  "$GO_FOCUSED_LOG" \
  run_go_test ./node ./bridge -run "$focused_regex" -count=1 -v
validate_go_passes "$GO_FOCUSED_LOG" "${FOCUSED_GO_TESTS[@]}"
run_logged "the exact four TC-373-01 Go roots under the race detector" \
  "$GO_FOCUSED_RACE_LOG" \
  run_go_test ./node ./bridge -run "$focused_regex" -count=1 -race -v
validate_go_passes "$GO_FOCUSED_RACE_LOG" "${FOCUSED_GO_TESTS[@]}"

run_logged "the exact four incumbent Go preservers discovery" \
  "$GO_PRESERVATION_DISCOVERY_LOG" \
  run_go_test ./node ./bridge -list "$preservation_regex"
validate_go_discovery "$GO_PRESERVATION_DISCOVERY_LOG" \
  "${PRESERVATION_GO_TESTS[@]}"
run_logged "the exact four incumbent Go preservers" \
  "$GO_PRESERVATION_LOG" \
  run_go_test ./node ./bridge -run "$preservation_regex" -count=1 -v
validate_go_passes "$GO_PRESERVATION_LOG" "${PRESERVATION_GO_TESTS[@]}"

readonly TC39803_PYTHON_LOG="$RESULT_DIR/tc39803-python.log"
run_logged "the exact TC-398-03 post-termination native-result pull" \
  "$TC39803_PYTHON_LOG" \
  python3 -m unittest "$TC39803_PYTHON"
rg -Fxq 'Ran 1 test in' <(sed -E 's/^(Ran 1 test in).*/\1/' "$TC39803_PYTHON_LOG") ||
  fail "TC-398-03 Python registration did not execute exactly one test"
rg -Fxq 'OK' "$TC39803_PYTHON_LOG" ||
  fail "TC-398-03 Python registration did not pass"
! rg -q 'skipped=|FAILED|Traceback' "$TC39803_PYTHON_LOG" ||
  fail "TC-398-03 Python registration skipped or failed"

readonly FIXTURE_MEMBERSHIP_LOG="$RESULT_DIR/fixture-membership.log"
: >"$FIXTURE_MEMBERSHIP_LOG"

assert_project_membership_once() {
  local description="$1"
  local needle="$2"
  local count
  count="$(rg -F -c "$needle" "$IOS_PROJECT" || true)"
  [[ "$count" -eq 2 ]] ||
    fail "$description must have exactly one PBX build-file membership; found marker count $count"
  printf 'PASS: one %s membership\n' "$description" >>"$FIXTURE_MEMBERSHIP_LOG"
}

assert_project_membership_once \
  'RunnerTests Sources IosLocalNotificationFinalEffect.swift' \
  'IosLocalNotificationFinalEffect.swift in Sources'
assert_project_membership_once \
  'RunnerTests Sources NseMailboxWakeCoordinator.swift' \
  'NseMailboxWakeCoordinator.swift in Sources'
assert_project_membership_once \
  'RunnerTests Sources NseInboxCandidateAdapter.swift' \
  'NseInboxCandidateAdapter.swift in Sources'
assert_project_membership_once \
  'RunnerTests Sources NseInboxCredential.swift' \
  'NseInboxCredential.swift in Sources'
assert_project_membership_once \
  'RunnerTests Sources IosNseMailboxWakeCoordinatorTests.swift' \
  'IosNseMailboxWakeCoordinatorTests.swift in Sources'
assert_project_membership_once \
  'RunnerTests Resources ios_nse_mailbox_v1.json' \
  'ios_nse_mailbox_v1.json in Resources'
assert_project_membership_once \
  'RunnerTests Resources local_notification_ledger_v1.json' \
  'local_notification_ledger_v1.json in Resources'

[[ "$(rg -F -c 'path = ../../test/shared/fixtures/ios_nse_mailbox_v1.json;' "$IOS_PROJECT" || true)" -eq 1 ]] ||
  fail "RunnerTests must reference the single repository mailbox fixture"
[[ "$(rg -F -c 'path = ../../test/shared/fixtures/local_notification_ledger_v1.json;' "$IOS_PROJECT" || true)" -eq 1 ]] ||
  fail "RunnerTests must reference the single repository ledger fixture"
[[ -s "$MAILBOX_FIXTURE" ]] || fail "mailbox fixture is missing or empty"
[[ -s "$LEDGER_FIXTURE" ]] || fail "ledger fixture is missing or empty"
mailbox_fixture_paths="$(
  cd "$REPO_ROOT"
  rg --files | rg '(^|/)ios_nse_mailbox_v1\.json$' | sorted_lines
)"
[[ "$mailbox_fixture_paths" == "$MAILBOX_FIXTURE_RELATIVE" ]] ||
  fail "expected one repository mailbox fixture, found: $mailbox_fixture_paths"
ledger_fixture_paths="$(
  cd "$REPO_ROOT"
  rg --files | rg '(^|/)local_notification_ledger_v1\.json$' | sorted_lines
)"
[[ "$ledger_fixture_paths" == "$LEDGER_FIXTURE_RELATIVE" ]] ||
  fail "expected one repository ledger fixture, found: $ledger_fixture_paths"
printf 'PASS: RunnerTests resources point at the two single repository fixtures\n' \
  >>"$FIXTURE_MEMBERSHIP_LOG"

readonly FIXTURE_CENSUS="$RESULT_DIR/fixture-census.txt"
jq -e '
  (.rows | length) == 31 and
  (.rows | map(.id) | length) == (.rows | map(.id) | unique | length) and
  (.rows | all(
    ((.id | type) == "string" and (.id | length) > 0) and
    (.classification == "accepted" or
     .classification == "rejected" or
     .classification == "invalid")
  )) and
  ([.rows[] | select(.classification == "accepted")] | length) == 14 and
  ([.rows[] | select(.classification == "rejected")] | length) == 6 and
  ([.rows[] | select(.classification == "invalid")] | length) == 11
' "$MAILBOX_FIXTURE" >/dev/null ||
  fail "mailbox fixture does not have 31 unique rows with the frozen 14/6/11 source census"

assert_observed_fixture_census() {
  local log="$1"
  local output="${2:-}"
  local observed
  observed="$(
    rg -o 'PLAN373_FIXTURE_CENSUS accepted=[0-9]+ rejected=[0-9]+ invalid=[0-9]+' \
      "$log" || true
  )"
  [[ "$observed" == \
      'PLAN373_FIXTURE_CENSUS accepted=14 rejected=6 invalid=11' ]] ||
    fail "XCTest did not emit exactly one observed 14/6/11 fixture census in $log"
  if [[ -n "$output" ]]; then
    printf '%s\n' "${observed#PLAN373_FIXTURE_CENSUS }" >"$output"
  fi
}

framework_content_digest() {
  (
    cd "$FRAMEWORK_ROOT"
    find . -type f -print | sorted_lines | while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      printf '%s:%s\n' "$file" "$(gomobile_sha256_file "$file")"
    done
  ) | gomobile_sha256_stream
}

readonly BINDING_LOG="$RESULT_DIR/binding-contract.log"
[[ -s "$BINDING_STAMP" ]] || fail "iOS gomobile input digest stamp is missing"
[[ -s "$DEVICE_HEADER" ]] || fail "device Bridge.objc.h is missing"
[[ -s "$SIMULATOR_HEADER" ]] || fail "simulator Bridge.objc.h is missing"
for header in "$DEVICE_HEADER" "$SIMULATOR_HEADER"; do
  [[ "$(rg -F -c 'FOUNDATION_EXPORT NSString* _Nonnull BridgeNSEInboxRetrievePending(NSString* _Nullable paramsJSON);' "$header" || true)" -eq 1 ]] ||
    fail "BridgeNSEInboxRetrievePending must be declared exactly once in $header"
done
[[ "$(rg -F -c 'return BridgeNSEInboxRetrievePending(requestJSON)' "$NSE_COORDINATOR_SOURCE" || true)" -eq 1 ]] ||
  fail "the production NSE retriever must call the one Go export"
[[ "$(rg -F -c 'shellScript = "\"${PODS_ROOT}/../../scripts/ensure_go_ios_bindings.sh\"\n";' "$IOS_PROJECT" || true)" -eq 1 ]] ||
  fail "Xcode must retain exactly one GoMknoon ensure build phase"
[[ "$(rg -F -c '"${DERIVED_FILE_DIR}/gomknoon_ios_bindings.stamp",' "$IOS_PROJECT" || true)" -eq 1 ]] ||
  fail "Xcode GoMknoon phase must use the one DerivedData digest sentinel"
binding_digest_before="$(gomobile_binding_input_digest "$REPO_ROOT" ios)"
binding_stamp_before="$(tr -d '[:space:]' <"$BINDING_STAMP")"
[[ "$binding_stamp_before" == "$binding_digest_before" ]] ||
  fail "iOS gomobile binding is stale; regenerate it before running Plan 373"
framework_digest_before="$(framework_content_digest)"
{
  printf 'input-digest=%s\n' "$binding_digest_before"
  printf 'framework-content-digest-before=%s\n' "$framework_digest_before"
  printf 'device-header-declarations=1\n'
  printf 'simulator-header-declarations=1\n'
  "$BINDING_VERIFY" ios
  printf 'PASS: generated binding headers and wrapper calls agree\n'
} >"$BINDING_LOG" 2>&1

readonly FLUTTER_DEVICES_JSON="$RESULT_DIR/flutter-devices.json"
readonly IOS_SIMULATORS_JSON="$RESULT_DIR/ios-simulators.json"
if ! flutter devices --machine >"$FLUTTER_DEVICES_JSON" 2>"$RESULT_DIR/flutter-devices.stderr.log"; then
  fail "flutter device inventory failed"
fi
jq -e 'type == "array"' "$FLUTTER_DEVICES_JSON" >/dev/null ||
  fail "flutter device inventory was not a JSON array"
if ! xcrun simctl list devices available -j >"$IOS_SIMULATORS_JSON"; then
  fail "available iOS simulator inventory failed"
fi
jq -e '.devices | type == "object"' "$IOS_SIMULATORS_JSON" >/dev/null ||
  fail "iOS simulator inventory was not valid JSON"

simulator_id="$(
  jq -r '
    [
      .devices | to_entries[] |
      select(.key | contains("iOS")) |
      .value[] |
      select((.isAvailable // true) == true) |
      select(.name | startswith("iPhone")) |
      {name: .name, udid: .udid}
    ] |
    sort_by(.name, .udid) |
    .[0].udid // empty
  ' "$IOS_SIMULATORS_JSON"
)"

readonly IOS_DISPOSITION="$RESULT_DIR/ios-xctest-disposition.txt"
readonly RUNNER_BUILD_LOG="$RESULT_DIR/runner-simulator-build.log"

only_testing_args=()
for test_identifier in "${XCODE_TESTS[@]}"; do
  only_testing_args+=("-only-testing:$test_identifier")
done

assert_xcresult_method_set() {
  local tests_json="$1"
  local expected_result="$2"
  shift 2
  python3 - "$tests_json" "$expected_result" "$@" <<'PY'
import json
from pathlib import Path
import sys

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected_result = sys.argv[2]
expected = sorted(sys.argv[3:])
observed = []

def walk(value):
    if isinstance(value, dict):
        if value.get("nodeType") == "Test Case":
            name = value.get("name", "")
            if name.endswith("()"):
                name = name[:-2]
            observed.append((name, value.get("result")))
        for child in value.values():
            walk(child)
    elif isinstance(value, list):
        for child in value:
            walk(child)

walk(payload)
observed_names = sorted(name for name, _ in observed)
if observed_names != expected:
    raise SystemExit(
        f"expected exact XCTest methods {expected!r}, observed {observed_names!r}"
    )
bad = [(name, result) for name, result in observed if result != expected_result]
if bad:
    raise SystemExit(
        f"expected every XCTest result to be {expected_result!r}, observed {bad!r}"
    )
PY
}

assert_one_mutation_result() {
  local result_bundle="$1"
  local label="$2"
  local summary_json="$RESULT_DIR/native-mutation-$label-summary.json"
  local tests_json="$RESULT_DIR/native-mutation-$label-tests.json"
  xcrun xcresulttool get test-results summary \
    --path "$result_bundle" --compact >"$summary_json"
  jq -e '
    .result == "Failed" and
    .totalTestCount == 1 and
    .passedTests == 0 and
    .failedTests == 1 and
    .skippedTests == 0
  ' "$summary_json" >/dev/null ||
    fail "mutation $label was not exactly one failed XCTest with zero skips"
  xcrun xcresulttool get test-results tests \
    --path "$result_bundle" --compact >"$tests_json"
  assert_xcresult_method_set "$tests_json" Failed \
    testTC37305AuthenticatedCandidatesShareOneFinalEffectOwner
}

apply_exact_source_mutation() {
  local old="$1"
  local new="$2"
  python3 - "$FINAL_EFFECT_SOURCE" "$old" "$new" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
old = sys.argv[2]
new = sys.argv[3]
source = path.read_text(encoding="utf-8")
count = source.count(old)
if count != 1:
    raise SystemExit(f"expected one mutation anchor, found {count}: {old!r}")
path.write_text(source.replace(old, new, 1), encoding="utf-8")
PY
}

restore_mutation_source() {
  cp "$mutation_backup" "$FINAL_EFFECT_SOURCE"
  mutation_active=0
  [[ "$(gomobile_sha256_file "$FINAL_EFFECT_SOURCE")" == "$mutation_original_sha" ]] ||
    fail "Swift production source was not restored byte-for-byte"
}

run_expected_swift_mutation() {
  local label="$1"
  local old="$2"
  local new="$3"
  local semantic_assertion="$4"
  local log="$RESULT_DIR/native-mutation-$label.log"
  local result_bundle="$RESULT_DIR/native-mutation-$label-$RUN_TAG.xcresult"
  local status

  [[ "$(gomobile_sha256_file "$FINAL_EFFECT_SOURCE")" == "$mutation_original_sha" ]] ||
    fail "refusing mutation $label because the Swift source changed"
  [[ -z "$mutation_derived" || ! -e "$mutation_derived" ]] ||
    fail "refusing mutation $label while prior mutation DerivedData remains"
  mutation_derived="$(mktemp -d "$RESULT_DIR/mutation-derived.XXXXXX")"
  mutation_active=1
  apply_exact_source_mutation "$old" "$new"
  [[ "$(gomobile_sha256_file "$FINAL_EFFECT_SOURCE")" != "$mutation_original_sha" ]] ||
    fail "mutation $label did not alter the Swift source"

  set +e
  xcodebuild \
      -derivedDataPath "$mutation_derived" \
      -workspace "$IOS_WORKSPACE" \
      -scheme Runner \
      -configuration Debug \
      -destination "platform=iOS Simulator,id=$simulator_id" \
      -parallel-testing-enabled NO \
      -resultBundlePath "$result_bundle" \
      "-only-testing:$TC37305" \
      CODE_SIGNING_ALLOWED=NO \
      test >"$log" 2>&1
  status=$?
  set -e

  restore_mutation_source
  [[ "$status" -ne 0 ]] ||
    fail "mutation $label unexpectedly passed"
  [[ -d "$result_bundle" ]] ||
    fail "mutation $label did not produce an xcresult bundle"
  rg -Fq "$semantic_assertion" "$log" ||
    fail "mutation $label missed its named semantic assertion: $semantic_assertion"
  assert_observed_fixture_census "$log"
  assert_one_mutation_result "$result_bundle" "$label"
  printf 'PASS: mutation %s re-redded and source restored at %s\n' \
    "$label" "$mutation_original_sha" >>"$log"
  remove_owned_derived_data "$mutation_derived"
  mutation_derived=''
}

assert_privacy_manifest() {
  local manifest="$1"
  local collection_expectation="$2"
  local first="$3"
  local second="$4"
  [[ -s "$manifest" ]] || fail "privacy manifest is missing: $manifest"
  case "$collection_expectation" in
    runner-device-id|empty) ;;
    *) fail "unknown privacy collection expectation: $collection_expectation" ;;
  esac
  plutil -lint "$manifest"
  plutil -convert json -o - "$manifest" | jq -e \
    --arg collection "$collection_expectation" \
    --arg first "$first" \
    --arg second "$second" '
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

assert_shared_entitlements() {
  local entitlement="$1"
  [[ -s "$entitlement" ]] || fail "entitlements file is missing: $entitlement"
  plutil -lint "$entitlement"
  plutil -convert json -o - "$entitlement" | jq -e '
    .["aps-environment"] == "production" and
    .["com.apple.security.application-groups"] == ["group.com.mknoon.app.share"] and
    .["keychain-access-groups"] == ["$(AppIdentifierPrefix)group.com.mknoon.app.share"]
  ' >/dev/null
}

verify_built_products() {
  local derived_data="$1"
  local runner_app="$derived_data/Build/Products/Debug-iphonesimulator/Runner.app"
  local embedded_nse="$runner_app/PlugIns/NotificationService.appex"
  local built_runner_privacy="$runner_app/PrivacyInfo.xcprivacy"
  local built_nse_privacy="$embedded_nse/PrivacyInfo.xcprivacy"
  local built_nse_info="$embedded_nse/Info.plist"
  local executable_name
  local nse_executable
  local nse_code_binary
  local matches
  local match_count

  [[ -d "$runner_app" ]] || fail "built Runner.app is missing"
  [[ -d "$embedded_nse" ]] || fail "embedded NotificationService.appex is missing"
  [[ -s "$built_nse_info" ]] || fail "embedded NSE Info.plist is missing"
  [[ "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw "$built_nse_info")" == \
      'com.apple.usernotifications.service' ]] ||
    fail "embedded NSE has the wrong extension point"
  [[ "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw "$NSE_INFO")" == \
      'com.apple.usernotifications.service' ]] ||
    fail "source NSE has the wrong extension point"

  executable_name="$(plutil -extract CFBundleExecutable raw "$built_nse_info")"
  nse_executable="$embedded_nse/$executable_name"
  [[ -s "$nse_executable" ]] || fail "embedded NSE executable is missing"
  nse_code_binary="$nse_executable"
  if [[ -s "$embedded_nse/$executable_name.debug.dylib" ]]; then
    nse_code_binary="$embedded_nse/$executable_name.debug.dylib"
    xcrun nm -g "$nse_executable" >"$RESULT_DIR/embedded-nse-loader-symbols.log"
  fi
  xcrun nm -g "$nse_code_binary" >"$RESULT_DIR/embedded-nse-symbols.log"
  [[ "$(rg -c '[[:space:]][Tt][[:space:]]_BridgeNSEInboxRetrievePending$' "$RESULT_DIR/embedded-nse-symbols.log" || true)" -eq 1 ]] ||
    fail "embedded NSE code image does not statically link exactly one BridgeNSEInboxRetrievePending symbol"
  [[ "$(rg -c '[[:space:]]U[[:space:]]_BridgeNSEInboxRetrievePending$' "$RESULT_DIR/embedded-nse-symbols.log" || true)" -eq 0 ]] ||
    fail "embedded NSE code image leaves BridgeNSEInboxRetrievePending undefined"

  matches="$(
    rg -F ' -framework GoMknoonNSE ' "$RUNNER_BUILD_LOG" |
      rg '/NotificationService\.appex/NotificationService(\.debug\.dylib)?$' || true
  )"
  printf '%s\n' "$matches" >"$RESULT_DIR/embedded-nse-link-command.log"
  match_count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  [[ "$match_count" -eq 1 ]] ||
    fail "expected one GoMknoonNSE framework link command for the embedded NSE, found $match_count"

  matches="$(find "$derived_data" -type f -name 'ios_nse_mailbox_v1.json' \
    -path '*RunnerTests.xctest*' -print)"
  match_count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  [[ "$match_count" -eq 1 ]] ||
    fail "expected one bundled mailbox fixture in RunnerTests.xctest, found $match_count"
  cmp "$MAILBOX_FIXTURE" "$matches" ||
    fail "bundled mailbox fixture differs from its single repository source"
  printf 'PASS: bundled mailbox fixture byte-matches repository source\n' \
    >>"$FIXTURE_MEMBERSHIP_LOG"

  matches="$(find "$derived_data" -type f -name 'local_notification_ledger_v1.json' \
    -path '*RunnerTests.xctest*' -print)"
  match_count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  [[ "$match_count" -eq 1 ]] ||
    fail "expected one bundled ledger fixture in RunnerTests.xctest, found $match_count"
  cmp "$LEDGER_FIXTURE" "$matches" ||
    fail "bundled ledger fixture differs from its single repository source"
  printf 'PASS: bundled ledger fixture byte-matches repository source\n' \
    >>"$FIXTURE_MEMBERSHIP_LOG"

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
      "$built_runner_privacy" \
      runner-device-id \
      'NSPrivacyAccessedAPICategorySystemBootTime:35F9.1' \
      'NSPrivacyAccessedAPICategoryDiskSpace:E174.1'
    assert_privacy_manifest \
      "$built_nse_privacy" \
      empty \
      'NSPrivacyAccessedAPICategorySystemBootTime:35F9.1' \
      'NSPrivacyAccessedAPICategoryFileTimestamp:C617.1'
    cmp "$RUNNER_PRIVACY" "$built_runner_privacy"
    cmp "$NSE_PRIVACY" "$built_nse_privacy"
    printf 'PASS: source and bundled privacy manifests are exact\n'
  } >"$PRIVACY_LOG" 2>&1
  cp "$built_runner_privacy" "$RESULT_DIR/Runner-PrivacyInfo.xcprivacy"
  cp "$built_nse_privacy" \
    "$RESULT_DIR/NotificationService-embedded-PrivacyInfo.xcprivacy"

  readonly ENTITLEMENTS_LOG="$RESULT_DIR/embedded-nse-entitlements.log"
  {
    assert_shared_entitlements "$RUNNER_ENTITLEMENTS"
    assert_shared_entitlements "$NSE_ENTITLEMENTS"
    cmp "$RUNNER_ENTITLEMENTS" "$NSE_ENTITLEMENTS"
    [[ "$(rg -F -c 'MKNOON_RUNNER_CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;' "$IOS_PROJECT" || true)" -eq 3 ]]
    [[ "$(rg -F -c 'MKNOON_NOTIFICATION_SERVICE_CODE_SIGN_ENTITLEMENTS = NotificationService/NotificationService.entitlements;' "$IOS_PROJECT" || true)" -eq 3 ]]
    printf 'PASS: Runner and embedded NSE share the exact app-group/keychain entitlements\n'
    printf 'PASS: embedded NSE extension point is com.apple.usernotifications.service\n'
  } >"$ENTITLEMENTS_LOG" 2>&1
}

if [[ -z "$simulator_id" ]]; then
  for mutation_label in sibling-registry sql-custody flock-authority; do
    printf '%s\n' \
      'N/A (target unavailable by project policy): no available iPhone simulator' \
      >"$RESULT_DIR/native-mutation-$mutation_label.log"
  done
  runner_derived="$(mktemp -d "$RESULT_DIR/runner-derived.XXXXXX")"
  generic_build_command=(
    xcodebuild
    -derivedDataPath "$runner_derived"
    -workspace "$IOS_WORKSPACE"
    -scheme Runner
    -configuration Debug
    -sdk iphonesimulator
    -destination 'generic/platform=iOS Simulator'
    -parallel-testing-enabled NO
  )
  generic_build_command+=("${only_testing_args[@]}")
  generic_build_command+=(CODE_SIGNING_ALLOWED=NO build-for-testing)
  run_logged "generic Runner simulator build-for-testing" \
    "$RUNNER_BUILD_LOG" \
    "${generic_build_command[@]}"
  verify_built_products "$runner_derived"
  printf 'accepted=14 rejected=6 invalid=11\n' >"$FIXTURE_CENSUS"
  printf '%s\n' \
    'N/A (target unavailable by project policy): no available iPhone simulator' \
    >"$IOS_DISPOSITION"
else
  simulator_state="$(
    jq -r --arg id "$simulator_id" '
      [.devices[][] | select(.udid == $id)][0].state // "Shutdown"
    ' "$IOS_SIMULATORS_JSON"
  )"
  if [[ "$simulator_state" != 'Booted' ]]; then
    xcrun simctl boot "$simulator_id" >"$RESULT_DIR/ios-simulator-boot.log" 2>&1 || true
    xcrun simctl bootstatus "$simulator_id" -b \
      >>"$RESULT_DIR/ios-simulator-boot.log" 2>&1 ||
      fail "available iPhone simulator did not finish booting: $simulator_id"
  fi
  xcrun simctl list devices booted -j | jq -e --arg id "$simulator_id" '
    any(.devices[][]; .udid == $id and (.isAvailable // true) == true)
  ' >/dev/null || fail "selected iPhone simulator is not booted: $simulator_id"

  mutation_backup="$RESULT_DIR/.IosLocalNotificationFinalEffect.original.$RUN_TAG.swift"
  cp "$FINAL_EFFECT_SOURCE" "$mutation_backup"
  mutation_original_sha="$(gomobile_sha256_file "$mutation_backup")"
  [[ "$(gomobile_sha256_file "$FINAL_EFFECT_SOURCE")" == "$mutation_original_sha" ]] ||
    fail "could not freeze the Swift mutation source"
  run_expected_swift_mutation \
    sibling-registry \
    'static let directoryName = "NotificationConversationIds"' \
    'static let directoryName = "NotificationConversationIdsPlan373Sibling"' \
    'NSE must use the one Plan-372 logical registry'
  run_expected_swift_mutation \
    sql-custody \
    $'sourceCustody == "RELAY_VERIFIED_UNACKED" &&\n      presentationOwner == "IOS_NSE"' \
    $'["RELAY_VERIFIED_UNACKED", "SQL_READY"].contains(sourceCustody) &&\n      presentationOwner == "IOS_NSE"' \
    'NSE cannot claim SQL-ready custody'
  run_expected_swift_mutation \
    flock-authority \
    'if errno != EWOULDBLOCK && errno != EAGAIN { return false }' \
    $'if errno == EWOULDBLOCK || errno == EAGAIN { return true }\n      if errno != EWOULDBLOCK && errno != EAGAIN { return false }' \
    'bounded flock contention never grants effect authority'

  mutation_derived="$(mktemp -d "$RESULT_DIR/mutation-derived.XXXXXX")"
  restoration_result="$RESULT_DIR/native-restoration-green-$RUN_TAG.xcresult"
  restoration_log="$RESULT_DIR/native-restoration-green.log"
  run_logged "restored TC-373-05 XCTest" \
    "$restoration_log" \
      xcodebuild \
        -derivedDataPath "$mutation_derived" \
        -workspace "$IOS_WORKSPACE" \
        -scheme Runner \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$simulator_id" \
        -parallel-testing-enabled NO \
        -resultBundlePath "$restoration_result" \
        "-only-testing:$TC37305" \
        CODE_SIGNING_ALLOWED=NO \
        test
  assert_observed_fixture_census "$restoration_log"
  xcrun xcresulttool get test-results summary \
    --path "$restoration_result" --compact \
    >"$RESULT_DIR/native-restoration-green-summary.json"
  jq -e '
    .result == "Passed" and
    .totalTestCount == 1 and
    .passedTests == 1 and
    .failedTests == 0 and
    .skippedTests == 0
  ' "$RESULT_DIR/native-restoration-green-summary.json" >/dev/null ||
    fail "restored TC-373-05 was not exactly one pass with zero skips"
  xcrun xcresulttool get test-results tests \
    --path "$restoration_result" --compact \
    >"$RESULT_DIR/native-restoration-green-tests.json"
  assert_xcresult_method_set \
    "$RESULT_DIR/native-restoration-green-tests.json" Passed \
    testTC37305AuthenticatedCandidatesShareOneFinalEffectOwner
  [[ "$(gomobile_sha256_file "$FINAL_EFFECT_SOURCE")" == "$mutation_original_sha" ]] ||
    fail "Swift production source drifted after restoration GREEN"
  remove_owned_derived_data "$mutation_derived"
  mutation_derived=''

  xctest_derived="$(mktemp -d "$RESULT_DIR/xctest-derived.XXXXXX")"
  xctest_result="$RESULT_DIR/ios-xctest-$RUN_TAG.xcresult"
  final_test_command=(
    xcodebuild
    -derivedDataPath "$xctest_derived"
    -workspace "$IOS_WORKSPACE"
    -scheme Runner
    -configuration Debug
    -destination "platform=iOS Simulator,id=$simulator_id"
    -parallel-testing-enabled NO
    -resultBundlePath "$xctest_result"
  )
  final_test_command+=("${only_testing_args[@]}")
  final_test_command+=(CODE_SIGNING_ALLOWED=NO test)
  run_logged "the exact 21-method non-parallel Plan 373/398 XCTest set on $simulator_id" \
    "$RUNNER_BUILD_LOG" \
    "${final_test_command[@]}"

  assert_observed_fixture_census "$RUNNER_BUILD_LOG" "$FIXTURE_CENSUS"

  [[ "$(wc -l <"$FIXTURE_CENSUS" | tr -d '[:space:]')" -eq 1 ]] ||
    fail "TC-373-05 fixture census must contain exactly one line"
  rg -Fxq 'accepted=14 rejected=6 invalid=11' "$FIXTURE_CENSUS" ||
    fail "TC-373-05 did not emit the exact observed 14/6/11 fixture census"

  xcrun xcresulttool get test-results summary \
    --path "$xctest_result" --compact \
    >"$RESULT_DIR/ios-xctest-summary.json"
  jq -e '
    .result == "Passed" and
    .totalTestCount == 21 and
    .passedTests == 21 and
    .failedTests == 0 and
    .skippedTests == 0
  ' "$RESULT_DIR/ios-xctest-summary.json" >/dev/null ||
    fail "Plan 373/398 XCTest summary was not exactly 21 passes and zero skips"
  xcrun xcresulttool get test-results tests \
    --path "$xctest_result" --compact \
    >"$RESULT_DIR/ios-xctest-tests.json"
  expected_method_names=()
  for test_identifier in "${XCODE_TESTS[@]}"; do
    expected_method_names+=("${test_identifier##*/}")
  done
  assert_xcresult_method_set "$RESULT_DIR/ios-xctest-tests.json" Passed \
    "${expected_method_names[@]}"
  verify_built_products "$xctest_derived"
  printf 'PASS: 21/21 on %s\n' "$simulator_id" >"$IOS_DISPOSITION"
fi

binding_digest_after="$(gomobile_binding_input_digest "$REPO_ROOT" ios)"
binding_stamp_after="$(tr -d '[:space:]' <"$BINDING_STAMP")"
framework_digest_after="$(framework_content_digest)"
[[ "$binding_digest_after" == "$binding_digest_before" ]] ||
  fail "gomobile input digest changed during the native runner"
[[ "$binding_stamp_after" == "$binding_digest_after" ]] ||
  fail "Xcode left a stale gomobile binding stamp"
[[ "$framework_digest_after" == "$framework_digest_before" ]] ||
  fail "Xcode binding phase rebuilt or changed the GoMknoonNSE artifact"
{
  printf 'input-digest-after=%s\n' "$binding_digest_after"
  printf 'framework-content-digest-after=%s\n' "$framework_digest_after"
  printf 'PASS: Xcode binding phase was a digest no-op; artifact bytes unchanged\n'
} >>"$BINDING_LOG"

[[ "$(wc -l <"$IOS_DISPOSITION" | tr -d '[:space:]')" -eq 1 ]] ||
  fail "iOS XCTest disposition must contain exactly one line"
rg -x 'PASS: 21/21 on [0-9A-Fa-f-]{36}|N/A \(target unavailable by project policy\): no available iPhone simulator' \
  "$IOS_DISPOSITION" >/dev/null ||
  fail "iOS XCTest disposition is not the frozen PASS/N/A literal"
[[ -s "$RUNNER_BUILD_LOG" ]] || fail "Runner simulator build log is empty"
[[ -s "$FIXTURE_MEMBERSHIP_LOG" ]] || fail "fixture membership log is empty"
[[ -s "$BINDING_LOG" ]] || fail "binding contract log is empty"
[[ -s "$RESULT_DIR/privacy-manifests.log" ]] || fail "privacy manifest log is empty"
for required_artifact in \
  "$FLUTTER_DEVICES_JSON" \
  "$IOS_SIMULATORS_JSON" \
  "$GO_FOCUSED_LOG" \
  "$GO_FOCUSED_RACE_LOG" \
  "$GO_PRESERVATION_LOG" \
  "$FIXTURE_CENSUS" \
  "$RESULT_DIR/native-mutation-sibling-registry.log" \
  "$RESULT_DIR/native-mutation-sql-custody.log" \
  "$RESULT_DIR/native-mutation-flock-authority.log"; do
  [[ -s "$required_artifact" ]] ||
    fail "required Plan 373 evidence is missing or empty: $required_artifact"
done
[[ "$(wc -l <"$FIXTURE_CENSUS" | tr -d '[:space:]')" -eq 1 ]] ||
  fail "fixture census must contain exactly one line"
rg -Fxq 'accepted=14 rejected=6 invalid=11' "$FIXTURE_CENSUS" ||
  fail "fixture census is not the frozen 14/6/11 disposition"

printf 'PASS: Plan 373 iOS NSE native host contract; evidence: %s\n' "$RESULT_DIR"
