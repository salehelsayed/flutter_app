#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

runner="integration_test/scripts/run_group_reaction_notification_device.dart"
# Ordered census of every scenario `groupReactionNotificationScenarios` exposes.
# Plan 315 added the backgrounded-but-connected row without repinning this
# contract, which left the gate red; keep this list in declaration order.
expected="$({
  printf '%s\n' android_group_message_unread_lifecycle
  printf '%s\n' android_announcement_message_unread_lifecycle
  printf '%s\n' android_group_reaction_recipient
  printf '%s\n' android_announcement_reaction_recipient
  printf '%s\n' android_group_reaction_recipient_background_connected
  printf '%s\n' ios_announcement_reaction_recipient
  printf '%s\n' ios_chat_group_message_and_reaction_recipient
})"

actual="$(
  dart run "$runner" --list-scenarios |
    awk '/^[[:alnum:]_]+$/ { print }'
)"
[ "$actual" = "$expected" ] || {
  printf 'FAIL: Plan 257 scenario listing differs from the pinned scenario census\n' >&2
  exit 1
}

single="$(
  dart run "$runner" \
    --scenario ios_announcement_reaction_recipient \
    --list-scenarios |
    awk '/^[[:alnum:]_]+$/ { print }'
)"
[ "$single" = "ios_announcement_reaction_recipient" ] || {
  printf 'FAIL: --scenario did not isolate the iOS announcement row\n' >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# A stale same-name JSON must never bypass explicit capture mode. Historical
# artifacts are accepted only through --validate-artifacts.
mkdir -p "$tmp_dir/run"
printf '%s\n' '{"status":"passed","generatedBy":"marker-only"}' \
  >"$tmp_dir/run/android_group_reaction_recipient.json"

set +e
env -u MKNOON_257_STAGING_MANIFEST dart run "$runner" \
  --scenario android_group_reaction_recipient \
  --sender emulator-5554 \
  --recipient ANDROIDPHYSICAL123 \
  --artifact-dir "$tmp_dir/run" \
  >"$tmp_dir/run.stdout" 2>"$tmp_dir/run.stderr"
run_status=$?
set -e

[ "$run_status" -ne 0 ] || {
  printf 'FAIL: unconfigured device runner reported success\n' >&2
  exit 1
}
run_verdict="$tmp_dir/run/android_group_reaction_recipient_orchestrator_verdict.json"
[ -f "$run_verdict" ] || {
  printf 'FAIL: unconfigured runner did not persist a failure verdict\n' >&2
  exit 1
}
grep -q '"ok":false' "$run_verdict" || {
  printf 'FAIL: unconfigured runner verdict was not failed\n' >&2
  exit 1
}
grep -q '"status":"configuration_blocked"' "$run_verdict" || {
  printf 'FAIL: missing staging config was not classified honestly\n' >&2
  exit 1
}
grep -q 'staging_manifest_required' "$run_verdict" || {
  printf 'FAIL: missing staging configuration blocker was not explicit\n' >&2
  exit 1
}
[ ! -f "$tmp_dir/run/android_group_reaction_recipient.json" ] || {
  printf 'FAIL: stale artifact survived fresh capture preflight\n' >&2
  exit 1
}

# Existing-state trace failures are sibling evidence. They must never replace
# the authoritative scenario verdict, including failures raised by the capture
# child before it constructs its capture owner.
trace_scenario="ios_chat_group_message_and_reaction_recipient"
trace_recipient="00008030-001A6D2801BB802E"
mkdir -p "$tmp_dir/trace-missing-staging"
trace_authoritative_verdict="$tmp_dir/trace-missing-staging/${trace_scenario}_orchestrator_verdict.json"
trace_authoritative_artifact="$tmp_dir/trace-missing-staging/${trace_scenario}.json"
printf '%s\n' '{"sentinel":"authoritative-verdict-must-survive"}' \
  >"$trace_authoritative_verdict"
printf '%s\n' '{"sentinel":"authoritative-artifact-must-survive"}' \
  >"$trace_authoritative_artifact"
cp "$trace_authoritative_verdict" "$tmp_dir/trace-authoritative-verdict.expected"
cp "$trace_authoritative_artifact" "$tmp_dir/trace-authoritative-artifact.expected"

set +e
env -u MKNOON_257_STAGING_MANIFEST dart run "$runner" \
  --scenario "$trace_scenario" \
  --sender ANDROIDPHYSICAL123 \
  --recipient "$trace_recipient" \
  --artifact-dir "$tmp_dir/trace-missing-staging" \
  --trace-only-existing-state \
  --group-name TC398ExistingGroup \
  --existing-target-marker TC398ExistingTarget \
  >"$tmp_dir/trace-missing-staging.stdout" \
  2>"$tmp_dir/trace-missing-staging.stderr"
trace_missing_staging_status=$?
set -e

[ "$trace_missing_staging_status" -ne 0 ] || {
  printf 'FAIL: trace without staging configuration reported success\n' >&2
  exit 1
}
cmp -s "$trace_authoritative_verdict" \
  "$tmp_dir/trace-authoritative-verdict.expected" || {
  printf 'FAIL: trace child failure replaced the authoritative verdict\n' >&2
  exit 1
}
cmp -s "$trace_authoritative_artifact" \
  "$tmp_dir/trace-authoritative-artifact.expected" || {
  printf 'FAIL: trace child failure replaced the authoritative artifact\n' >&2
  exit 1
}
trace_missing_staging_failure="$tmp_dir/trace-missing-staging/plan398_existing_state_trace_failure.json"
[ -f "$trace_missing_staging_failure" ] || {
  printf 'FAIL: trace child failure did not persist trace-specific evidence\n' >&2
  exit 1
}
grep -q '"status":"configuration_blocked"' "$trace_missing_staging_failure" || {
  printf 'FAIL: trace child failure lost its typed status\n' >&2
  exit 1
}
grep -q 'staging_manifest_required' "$trace_missing_staging_failure" || {
  printf 'FAIL: trace child failure lost its typed detail\n' >&2
  exit 1
}
grep -q '"traceAttemptClaimed":false' "$trace_missing_staging_failure" || {
  printf 'FAIL: trace child pre-claim failure spent the send allowance\n' >&2
  exit 1
}
[ ! -f "$tmp_dir/trace-missing-staging/plan398_existing_state_trace.json" ] || {
  printf 'FAIL: trace child pre-claim failure wrote a trace artifact\n' >&2
  exit 1
}
[ ! -f "$tmp_dir/trace-missing-staging/plan398_existing_state_trace_claim.json" ] || {
  printf 'FAIL: trace child pre-claim failure wrote a trace claim\n' >&2
  exit 1
}

# The outer runner owns topology rejection before the child exists and must
# preserve the authoritative verdict under that failure path as well.
mkdir -p "$tmp_dir/trace-invalid-topology"
trace_topology_verdict="$tmp_dir/trace-invalid-topology/${trace_scenario}_orchestrator_verdict.json"
printf '%s\n' '{"sentinel":"authoritative-topology-verdict"}' \
  >"$trace_topology_verdict"
cp "$trace_topology_verdict" "$tmp_dir/trace-topology-verdict.expected"

set +e
dart run "$runner" \
  --scenario "$trace_scenario" \
  --sender emulator-5554 \
  --recipient "$trace_recipient" \
  --artifact-dir "$tmp_dir/trace-invalid-topology" \
  --trace-only-existing-state \
  --group-name TC398ExistingGroup \
  --existing-target-marker TC398ExistingTarget \
  >"$tmp_dir/trace-invalid-topology.stdout" \
  2>"$tmp_dir/trace-invalid-topology.stderr"
trace_topology_status=$?
set -e

[ "$trace_topology_status" -ne 0 ] || {
  printf 'FAIL: invalid trace topology reported success\n' >&2
  exit 1
}
cmp -s "$trace_topology_verdict" "$tmp_dir/trace-topology-verdict.expected" || {
  printf 'FAIL: trace topology failure replaced the authoritative verdict\n' >&2
  exit 1
}
trace_topology_failure="$tmp_dir/trace-invalid-topology/plan398_existing_state_trace_failure.json"
[ -f "$trace_topology_failure" ] || {
  printf 'FAIL: trace topology failure did not persist trace-specific evidence\n' >&2
  exit 1
}
grep -q '"stage":"topology"' "$trace_topology_failure" || {
  printf 'FAIL: trace topology failure lost its typed stage\n' >&2
  exit 1
}
grep -q '"traceAttemptClaimed":false' "$trace_topology_failure" || {
  printf 'FAIL: trace topology failure spent the send allowance\n' >&2
  exit 1
}

capture_driver="integration_test/scripts/capture_group_reaction_notification_device.dart"
[ -f "$capture_driver" ] || {
  printf 'FAIL: Plan 257 capture driver is missing\n' >&2
  exit 1
}
! grep -Eq 'capture_driver_.*implemented' "$runner" "$capture_driver" || {
  printf 'FAIL: placeholder capture-driver blocker remains\n' >&2
  exit 1
}
! grep -Fq 'physical_ios_announcement_fixture_staging_seam_missing' \
  "$capture_driver" || {
  printf 'FAIL: unconditional physical-iOS fixture blocker remains\n' >&2
  exit 1
}
for required_seam in \
  "'build'" \
  'candidate_install_failed' \
  'recipient process absent before provider delivery' \
  "'uiautomator'" \
  "'journalctl'" \
  'GROUP_REACTION_PUSH_ENABLED' \
  'group_reaction_notification_sqlcipher_probe_test.dart' \
  'testCreateAnnouncementReactionFixture' \
  'testAuthorAnnouncementReactionTarget' \
  'testPrepareWarmNotificationTap' \
  'testAnnouncementReactionNotificationTap' \
  'testCreateChatGroupNotificationFixture' \
  'testAuthorChatGroupReactionTarget' \
  'testChatGroupNotificationTap' \
  "'copy'" \
  'appDataContainer' \
  'idevicesyslog' \
  "'xcodebuild'"; do
  grep -Eq "$required_seam" "$capture_driver" || {
    printf 'FAIL: real capture driver is missing seam: %s\n' "$required_seam" >&2
    exit 1
  }
done

# TC-398-10: the existing-state trace is a sibling of the destructive Plan 397
# campaign, not a shortcut through it. Keep this source contract ahead of the
# device/setup contracts so an absent trace route is the authored RED.
python3 - "$runner" "$capture_driver" \
  "integration_test/scripts/group_reaction_notification_device_criteria.dart" \
  <<'PLAN398_EXISTING_STATE_TRACE_CONTRACT'
import re
import sys

runner_source = open(sys.argv[1], encoding='utf-8').read()
capture_source = open(sys.argv[2], encoding='utf-8').read()
criteria_source = open(sys.argv[3], encoding='utf-8').read()


def fail(message):
    print('FAIL: TC-398-10 existing-state trace contract: ' + message, file=sys.stderr)
    sys.exit(1)


def require(condition, message):
    if not condition:
        fail(message)


def function_body(source, signature, owner, start_at=0):
    start = source.find(signature, start_at)
    if start < 0:
        fail(owner + ' is missing ' + signature)
    opening = source.find('{', start)
    if opening < 0:
        fail(owner + ' has no body for ' + signature)
    depth = 0
    for index in range(opening, len(source)):
        character = source[index]
        if character == '{':
            depth += 1
        elif character == '}':
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    fail(owner + ' has an unterminated body for ' + signature)


trace_flag = '--trace-only-existing-state'
manual_flag = '--manual-send-existing-state'
live_flag = '--live-diagnostic'
group_option = '--group-name'
target_option = '--existing-target-marker'
for option in (trace_flag, manual_flag, live_flag, group_option, target_option):
    require(option in runner_source, 'runner does not route ' + option)
    require(option in capture_source, 'capture driver does not accept ' + option)

runner = function_body(runner_source, 'Future<int> _run(List<String> args) async', 'runner')
require(
    "_requiredValue(args, '--group-name')" in runner
    and "_requiredValue(args, '--existing-target-marker')" in runner,
    'runner does not require the exact existing group and target marker',
)
require(
    re.search(
        r"if\s*\(traceOnlyExistingState\)\s*'--trace-only-existing-state'",
        runner,
    ) is not None,
    'runner does not forward the existing-state trace mode',
)
require(
    "manualSendExistingState && !traceOnlyExistingState" in runner
    and re.search(
        r"if\s*\(manualSendExistingState\)\s*'--manual-send-existing-state'",
        runner,
    ) is not None,
    'runner does not restrict and forward the manual-send sibling mode',
)
require(
    "final liveDiagnostic = args.contains('--live-diagnostic')" in runner
    and "if (liveDiagnostic) '--live-diagnostic'" in runner
    and "expectedAuthorityMode: liveDiagnostic" in runner
    and "plan398LiveDiagnosticAuthorityMode" in runner,
    'runner does not route and independently validate live-diagnostic authority',
)
require(
    re.search(
        r"if\s*\((?:traceOnlyExistingState\s*\|\|\s*"
        r"args\.contains\('--no-child-builds'\)|"
        r"args\.contains\('--no-child-builds'\)\s*\|\|\s*"
        r"traceOnlyExistingState)\)\s*'--no-child-builds'",
        runner,
    ) is not None,
    'runner does not force --no-child-builds for the existing-state trace',
)
require(
    re.search(
        r"if\s*\(!traceOnlyExistingState\)\s*\{\s*"
        r"purgePhysicalDeviceCaptureArtifacts\(",
        runner,
    ) is not None,
    'runner can purge capture artifacts in existing-state trace mode',
)
require(
    re.search(
        r"if\s*\(traceOnlyExistingState\)\s*\.\.\.<String>\[\s*"
        r"'--group-name',\s*groupName,\s*"
        r"'--existing-target-marker',\s*existingTargetMarker,\s*\]",
        runner,
    ) is not None,
    'runner does not forward both required installed-state selectors',
)

capture_main = function_body(
    capture_source,
    'Future<void> main(List<String> args) async',
    'capture driver',
)
require(
    "_requiredValue(args, '--group-name')" in capture_main
    and "_requiredValue(args, '--existing-target-marker')" in capture_main,
    'capture driver does not require both installed-state selectors',
)

capture_class = capture_source.find('class _Plan257Capture')
require(capture_class >= 0, 'capture driver is missing class _Plan257Capture')
capture_run = function_body(
    capture_source,
    'Future<void> run() async',
    'capture driver',
    start_at=capture_class,
)
trace_dispatch = capture_run.find('await _runPlan398ExistingStateTrace()')
diagnostic_authority = capture_run.find('await _preparePlan398DiagnosticAuthority()')
central_artifacts = capture_run.find('await _preparePlan397CentralArtifacts()')
require(
    0 <= trace_dispatch < diagnostic_authority < central_artifacts,
    'existing-state trace does not return before diagnostic authority and central artifacts',
)
trace_dispatch_tail = capture_run[trace_dispatch:diagnostic_authority]
require(
    'return;' in trace_dispatch_tail,
    'existing-state trace can fall through into the destructive campaign',
)

trace = function_body(
    capture_source,
    'Future<void> _runPlan398ExistingStateTrace() async',
    'capture driver',
)
for forbidden in (
    '_buildAndroidCandidate(',
    '_buildIosCandidate(',
    '_installApk(',
    '_installIosCandidate(',
    '_uninstallIosCandidateIfPresent(',
    '_clearAndroidPrivateEntries(',
    '_prepareAndroidIdentity(',
    '_collectAndroidIdentity(',
    '_collectIosIdentity(',
    '_prepopulateContact(',
    '_prepopulateIosContact(',
    '_createAndAcceptGroup(',
    '_preparePlan398DiagnosticAuthority(',
    '_preparePlan397CentralArtifacts(',
    '_runPlan397IosAvailableStages(',
    '_runIosUiSelector(',
    '_iosTapSelector',
    '_tapText(',
    '_tapNotificationCard(',
    '_longPressText(',
    "phase: 'reaction'",
    '_reactionEmoji',
    '_sendGroupText(',
):
    require(forbidden not in trace, 'trace method contains forbidden operation ' + forbidden)

preflight_match = re.search(
    r'await\s+(_[A-Za-z0-9]*[Pp]reflight[A-Za-z0-9]*)\(\)',
    trace,
)
claim_match = re.search(
    r'await\s+(_[A-Za-z0-9]*[Cc]laim[A-Za-z0-9]*)\(\)',
    trace,
)
preflight = -1 if preflight_match is None else preflight_match.start()
claim = -1 if claim_match is None else claim_match.start()
send = trace.find('_sendGroupTextOneTap(')
require(
    0 <= preflight < claim < send,
    'installed-state preflight, durable claim, and send are not strictly ordered',
)
require(
    trace.count('_sendGroupTextOneTap(') == 1,
    'trace method does not own exactly one one-tap send call',
)
manual_send = function_body(
    capture_source,
    'Future<void> _awaitPlan398ManualExistingStateSend() async',
    'capture driver',
)
ready = manual_send.find('PLAN398_MANUAL_SEND_READY')
stdin_read = manual_send.find('stdin')
acknowledgement = manual_send.find("acknowledgement.trim() != 'SENT'")
require(
    0 <= ready < stdin_read < acknowledgement,
    'manual send does not publish readiness before one explicit acknowledgement',
)
for forbidden in ('_sendGroupTextOneTap(', '_sendGroupText(', "'input'", '_openGroup('):
    require(forbidden not in manual_send, 'manual send drives phone UI via ' + forbidden)
require(
    'validatePlan398ExistingStateTraceManifest(manifest)' in capture_source,
    'trace mode does not use its non-mutating manifest authority',
)
topology = function_body(
    capture_source,
    'Future<void> _verifyLiveDeviceTopology() async',
    'capture driver',
)
require(
    "'ddiServices'" in topology
    and "'idevice_id'" in topology
    and "'xctrace'" not in topology,
    'live iOS topology is not DDI-plus-USB bounded',
)

one_tap = function_body(
    capture_source,
    'Future<void> _sendGroupTextOneTap(',
    'capture driver',
)
require(
    '_sendGroupText(' in one_tap
    and 'maximumRecoveryPendingOutcomes: 1' in one_tap,
    'one-tap sender does not delegate to the shared sender with one outcome',
)
for bespoke in ('while (true)', 'enterGroupComposeMarkerOnce(', "'input',\n        'tap'"):
    require(bespoke not in one_tap, 'one-tap wrapper implements a bespoke send loop')

for stable_file in (
    'plan398_existing_state_trace.json',
    'plan398_existing_state_trace_claim.json',
):
    require(
        capture_source.count(stable_file) == 1,
        stable_file + ' is absent or has more than one writer identity',
    )
require(
    trace.count('.exists()') >= 2,
    'trace does not fail before work when either fixed artifact already exists',
)
require(claim_match is not None, 'trace has no named durable claim helper')
claim_writer = function_body(
    capture_source,
    'Future<void> ' + claim_match.group(1) + '() async',
    'capture driver',
)
require(
    'writePlan398PrivateNoReplaceEvidence(' in claim_writer
    and 'stableFile: claim' in claim_writer
    and 'maximumLengthBytes: 4096' in claim_writer,
    'claim does not delegate to the bounded private no-replace publisher',
)
publisher_start = criteria_source.find(
    'Future<Plan398TraceLogFileReference> writePlan398PrivateNoReplaceEvidence('
)
publisher_end = criteria_source.find(
    '\n}\n\nFuture<void> fsyncPlan398Directory(', publisher_start
)
require(
    publisher_start >= 0 and publisher_end > publisher_start,
    'criteria private evidence publisher is missing or unterminated',
)
publisher = criteria_source[publisher_start:publisher_end + 2]
private_temp = publisher.find(".private-temp'")
exclusive_create = publisher.find('create(exclusive: true)', private_temp)
private_mode = publisher.find("Process.run('chmod'", exclusive_create)
write = publisher.find('handle.writeFrom(bytes)', private_mode)
flushed_write = publisher.find('handle.flush()', write)
atomic_link = publisher.find("Process.run('ln'", flushed_write)
mode_verification = publisher.find('(stat.mode & 0x1ff) != 0x180', atomic_link)
directory_fsync = publisher.find('fsyncPlan398Directory(stableFile.parent)', mode_verification)
cleanup = publisher.find('await temporary.delete()', directory_fsync)
require(
    0 <= private_temp < exclusive_create < private_mode < write
    < flushed_write < atomic_link < mode_verification < directory_fsync
    < cleanup,
    'claim does not use an ordered private-temp, flush, link, mode-check, cleanup flow',
)
require(
    'followLinks: false' in publisher
    and re.search(
        r"Process\.run\('chmod',\s*<String>\[\s*'600',\s*"
        r"temporary\.path,?\s*\]\)",
        publisher,
    ) is not None,
    'same-directory temporary claim is not private before publication',
)
link_call = re.search(
    r"Process\.run\('ln',\s*<String>\[\s*temporary\.path,\s*"
    r"stableFile\.path,?\s*\]\)",
    publisher,
)
require(
    link_call is not None and "'-f'" not in publisher,
    'claim does not use atomic non-replacing hard-link publication',
)
require(
    'finally {' in publisher,
    'claim temporary cleanup is not guaranteed by finally',
)
PLAN398_EXISTING_STATE_TRACE_CONTRACT

# Plan 397 physical-iPhone setup must own the Local Network privacy prompt.
# Keep this source contract prompt-scoped: a generic SpringBoard "Allow" tap
# can grant the wrong permission while falsely reporting notification access.
ui_test_driver="ios/RunnerUITests/NotificationTapUITests.swift"
python3 - "$ui_test_driver" <<'IOS_PERMISSION_SEAM'
import sys

source = open(sys.argv[1], encoding='utf-8').read()


def fail(message):
    print('FAIL: ' + message, file=sys.stderr)
    sys.exit(1)


def function_body(signature):
    start = source.find(signature)
    if start < 0:
        fail('iOS UI-test driver is missing ' + signature)
    opening = source.find('{', start)
    if opening < 0:
        fail('iOS UI-test driver has no body for ' + signature)
    depth = 0
    for index in range(opening, len(source)):
        character = source[index]
        if character == '{':
            depth += 1
        elif character == '}':
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    fail('iOS UI-test driver has an unterminated body for ' + signature)


local_network = function_body(
    'private func allowLocalNetworkPromptIfPresent('
)
if 'identifyingText: "Local Network"' not in local_network:
    fail('Local Network automation is not tied to the Local Network alert')
if 'permission: "local_network"' not in local_network:
    fail('Local Network automation does not emit an auditable permission kind')

notifications = function_body(
    'private func allowNotificationPromptIfPresent('
)
if 'identifyingText: "Notifications"' not in notifications:
    fail('notification automation is not tied to the Notifications alert')

scoped_allow = function_body('private func allowPermissionPromptIfPresent(')
for required in (
    'application.alerts',
    'alert.descendants(matching: .staticText)',
    '.matching(identifyingTextPredicate)',
    'alert.buttons["Allow"]',
    'MKNOON_IOS_PERMISSION_AUTOMATED',
):
    if required not in scoped_allow:
        fail('permission automation lacks prompt-scoped seam ' + required)
if '.buttons.matching' in scoped_allow or 'application.buttons["Allow"]' in scoped_allow:
    fail('permission automation can still tap an unscoped Allow button')
if 'NSPredicate { _, _ in !identifyingTextElement.exists }' not in scoped_allow:
    fail(
        'permission automation does not distinguish dismissal of the '
        'identified prompt from an immediately succeeding system alert'
    )
if 'NSPredicate { _, _ in !alert.exists }' in scoped_allow:
    fail(
        'permission automation still waits for every system alert to disappear'
    )

physical_permission = function_body(
    'func testAutomateLocalNetworkPermission()'
)
if '@available(iOS 15.4, *)\n  func testAutomateLocalNetworkPermission()' not in source:
    fail('physical Local Network selector lacks the Apple API availability boundary')
launch_environment_read = physical_permission.find(
    'ProcessInfo.processInfo.environment["MKNOON_397_AUTO_SETUP_USERNAME"]'
)
launch_environment_write = physical_permission.find(
    'app.launchEnvironment["MKNOON_397_AUTO_SETUP_USERNAME"] = autoSetupUsername'
)
reset = physical_permission.find(
    'app.resetAuthorizationStatus(for: .localNetwork)'
)
launched = physical_permission.find('app.launch()')
first_local_allow = physical_permission.find(
    'allowLocalNetworkPromptIfPresent(', launched
)
notification_blocker = physical_permission.find(
    'allowNotificationPromptIfPresent(', first_local_allow
)
second_local_allow = physical_permission.find(
    'allowLocalNetworkPromptIfPresent(', first_local_allow + 1
)
if not (
    0 <= launch_environment_read < launch_environment_write < reset
    < launched < first_local_allow < notification_blocker
    < second_local_allow
):
    fail(
        'physical Local Network selector must inject the exact setup username '
        'before its single launch, then reset and require the real permission '
        'prompt while settling an identified Notifications blocker'
    )

campaign_permission = function_body(
    'func testSettleLocalNetworkPermissionForCampaign()'
)
if 'resetAuthorizationStatus' in campaign_permission:
    fail('campaign permission readiness must not reset an already-settled decision')
campaign_environment_read = campaign_permission.find(
    'ProcessInfo.processInfo.environment["MKNOON_397_AUTO_SETUP_USERNAME"]'
)
campaign_environment_write = campaign_permission.find(
    'app.launchEnvironment["MKNOON_397_AUTO_SETUP_USERNAME"] = autoSetupUsername'
)
campaign_attempt_read = campaign_permission.find(
    '"MKNOON_398_SETUP_READINESS_ATTEMPT"'
)
campaign_attempt_write = campaign_permission.find(
    'app.launchEnvironment["MKNOON_398_SETUP_READINESS_ATTEMPT"] = setupReadinessAttempt'
)
campaign_profile_read = campaign_permission.find(
    '"MKNOON_398_SETUP_ENTRY_PROFILE_ID"'
)
campaign_profile_write = campaign_permission.find(
    'app.launchEnvironment["MKNOON_398_SETUP_ENTRY_PROFILE_ID"] = setupEntryProfileId'
)
campaign_launch = campaign_permission.find('app.launch()')
campaign_first_local = campaign_permission.find(
    'allowLocalNetworkPromptIfPresent(', campaign_launch
)
campaign_notification = campaign_permission.find(
    'allowNotificationPromptIfPresent(', campaign_first_local
)
campaign_second_local = campaign_permission.find(
    'allowLocalNetworkPromptIfPresent(', campaign_first_local + 1
)
if not (
    0 <= campaign_environment_read < campaign_attempt_read
    < campaign_profile_read < campaign_environment_write
    < campaign_attempt_write < campaign_profile_write < campaign_launch
    < campaign_first_local < campaign_notification
    < campaign_second_local
):
    fail(
        'campaign permission readiness must inject the exact setup username '
        'fresh readiness attempt, and exact entry profile, launch once, and '
        'settle only identified Local Network/Notifications prompts'
    )
if 'MKNOON_398_SETUP_READINESS_ATTEMPT' in physical_permission:
    fail('strict permission proof was coupled to the Plan 398 readiness attempt')
if 'MKNOON_398_SETUP_ENTRY_PROFILE_ID' in physical_permission:
    fail('strict permission proof was coupled to the Plan 398 entry profile')
if 'MKNOON_IOS_PERMISSION_STATE permission=local_network action=no_prompt' not in campaign_permission:
    fail('campaign permission readiness does not honestly mark the no-prompt state')
if 'XCTAssertTrue(' in campaign_permission:
    fail('campaign readiness still requires a freshly reset Local Network prompt')

for signature, first_action in (
    ('func testCreateChatGroupNotificationFixture()', 'app.coordinate('),
    ('func testAuthorChatGroupReactionTarget()', 'let group = element('),
):
    body = function_body(signature)
    launched = body.find('app.launch()')
    permission = body.find('allowLocalNetworkPromptIfPresent(')
    action = body.find(first_action)
    if not (0 <= launched < permission < action):
        fail(signature + ' does not settle Local Network permission before UI input')

for signature in (
    'private func prepareWarmNotificationTap()',
    'private func tapExistingNotification(',
):
    body = function_body(signature)
    local_call = body.find('allowLocalNetworkPromptIfPresent(')
    notification_call = body.find('allowNotificationPromptIfPresent(')
    if not (0 <= local_call < notification_call):
        fail(signature + ' does not classify Local Network before Notifications')
IOS_PERMISSION_SEAM

# The physical-iPhone setup uses the XCTest-owned launch as its sole bootstrap
# launch. Its exact runtime username travels through the test process into
# XCUIApplication.launchEnvironment; no container staging or host-side relaunch
# may race the identity export after the permission leg.
python3 - "$capture_driver" <<'IOS_PERMISSION_ORDER'
import re
import sys

source = open(sys.argv[1], encoding='utf-8').read()


def fail(message):
    print('FAIL: ' + message, file=sys.stderr)
    sys.exit(1)


def function_body(signature):
    start = source.find(signature)
    if start < 0:
        fail('capture driver is missing ' + signature)
    opening = source.find('{', start)
    if opening < 0:
        fail('capture driver has no body for ' + signature)
    depth = 0
    for index in range(opening, len(source)):
        character = source[index]
        if character == '{':
            depth += 1
        elif character == '}':
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    fail('capture driver has an unterminated body for ' + signature)


for name, value in (
    ('_iosLocalNetworkPermissionProofSelector', 'testAutomateLocalNetworkPermission'),
    ('_iosLocalNetworkCampaignSelector', 'testSettleLocalNetworkPermissionForCampaign'),
):
    declaration = rf"const\s+{re.escape(name)}\s*=\s*'{re.escape(value)}';"
    if re.search(declaration, source) is None:
        fail('capture driver does not keep strict proof and campaign permission selectors distinct')

lifecycle = function_body(
    'Future<void> _runPlan397IosAvailableStages() async'
)
named = lifecycle.find("_groupName = 'TC397Chat")
configured = lifecycle.find('final setupTapConfig =')
selector_check = lifecycle.find('for (final selector in <String>[')
materialized = lifecycle.find('await _materializePlan397Xctestrun(')
permission = lifecycle.find(
    '_iosLocalNetworkCampaignSelector',
    materialized,
)
identity = lifecycle.find('await _collectIosIdentity(recipient)', permission)

if not (
    0 <= named < configured < selector_check < materialized < permission < identity
):
    fail(
        'physical iPhone setup must materialize its test environment, run the '
        'XCTest-owned permission launch, then collect the exported identity'
    )
if "'auto_setup.json'" in lifecycle:
    fail('Plan 397 iOS setup still stages a container bootstrap file')
if 'await _launchIosCandidate()' in lifecycle[permission:identity]:
    fail('Plan 397 iOS setup still performs a host relaunch before identity')
if '_iosLocalNetworkCampaignSelector,' not in lifecycle[
    selector_check:materialized
]:
    fail('native selector preflight omits idempotent Local Network campaign readiness')
if '_iosLocalNetworkPermissionProofSelector' in lifecycle:
    fail('the campaign still invokes the destructive strict permission-proof selector')

materializer_start = source.find(
    'Future<File> _materializePlan397Xctestrun('
)
selector_runner_start = source.find(
    'Future<String> _runIosUiSelector(', materializer_start
)
if not (0 <= materializer_start < selector_runner_start):
    fail('capture driver has no bounded Plan 397 xctestrun materializer')
materializer = source[materializer_start:selector_runner_start]
selector_runner = function_body(
    'Future<String> _runIosUiSelector('
)
launch_environment_entry = (
    "'MKNOON_397_AUTO_SETUP_USERNAME': recipient.username"
)
readiness_attempt_entry = (
    "'MKNOON_398_SETUP_READINESS_ATTEMPT':"
)
entry_profile_entry = (
    "'MKNOON_398_SETUP_ENTRY_PROFILE_ID':"
)
if launch_environment_entry not in materializer:
    fail('patched xctestrun omits the Plan 397 launch username')
if launch_environment_entry not in selector_runner:
    fail('xcodebuild environment omits the Plan 397 launch username')
if readiness_attempt_entry not in materializer:
    fail('patched xctestrun omits the Plan 398 setup-readiness attempt')
if readiness_attempt_entry not in selector_runner:
    fail('xcodebuild environment omits the Plan 398 setup-readiness attempt')
if entry_profile_entry not in materializer:
    fail('patched xctestrun omits the Plan 398 setup-entry profile')
if entry_profile_entry not in selector_runner:
    fail('xcodebuild environment omits the Plan 398 setup-entry profile')

identity_collector = function_body(
    'Future<void> _collectIosIdentity(_Party party) async'
)
readiness = identity_collector.find('_waitForPlan398SetupReadiness()')
identity_file = identity_collector.find(
    "_readIosAppFile('intro_e2e_identity.json')"
)
identity_binding = identity_collector.find(
    'expectedIdentityExportSha256:'
)
if not (0 <= readiness < identity_file < identity_binding):
    fail(
        'physical iPhone identity collection must close current-launch setup '
        'readiness before accepting and hash-binding the exported identity'
    )
readiness_waiter = function_body(
    '_waitForPlan398SetupReadiness() async'
)
for token in (
    'expectedLaunchAttemptSha256:',
    'plan398_ios_setup_readiness_native_entry_failure',
    'GroupReactionNotificationIosSetupReadinessDisposition.ready',
):
    if token not in readiness_waiter:
        fail('setup-readiness waiter is missing ' + token)
IOS_PERMISSION_ORDER

# ---------------------------------------------------------------------------
# Plan 386 TC-386-05 - every GRADED capture read comes from a live stream with
# byte-offset cursors, never a post-hoc `logcat -d` window.
#
# Deliberately SCOPED rather than the tap-campaign's file-wide seam
# (`notification_tap_campaign_adapter_contract_test.sh:239-252`). Ported
# verbatim that seam is UNSATISFIABLE here: it bans `['logcat', '-c']` outright
# and tests `'logcat',` x `'-d',` co-occurrence across the whole file, while
# this capture legitimately keeps ten `logcat -c` clears and two
# process-scoped `logcat -d --pid=<pid>` readiness polls. A permanent red is
# not a causal red, so the assertions below name the exact graded shapes.
python3 - "$capture_driver" <<'STREAM_SEAM'
import re
import sys

source = open(sys.argv[1], encoding='utf-8').read()


def fail(message):
    print('FAIL: ' + message, file=sys.stderr)
    sys.exit(1)


for required in (
    '_startDeviceLogStream',
    '_deviceLogcatCursor',
    '_deviceLogSince',
):
    if required not in source:
        fail('capture driver lacks the live log stream seam ' + required)

# The exact 4-element post-hoc reads the graded paths used before Plan 386.
# Compared whitespace-insensitively so a reformat cannot smuggle one back.
compact = re.sub(r'\s+', '', source)
for banned in ("'logcat','-d','-v','threadtime'", "'logcat','-d','-v','brief'"):
    if banned in compact:
        fail('a graded capture read still uses a post-hoc logcat -d window')

# The two surviving `logcat -d` reads are process-scoped setup polls: they must
# observe only the CURRENT pid, which a whole-device stream cannot express, and
# they gate fixture readiness rather than producing artifact evidence.
for read in re.findall(r"'logcat',\s*'-d',(.*?)\]", source, re.S):
    if '--pid=' not in read:
        fail('an ungated post-hoc logcat -d read remains on a graded path')

# The clears stay. The stream turns each one into a floor instead of destroying
# evidence, so the destructive-action ban stays green.
#
# Repinned 8 -> 9 by Plan 389 for the reaction kill, then 9 -> 10 by Plan 393
# for the distinct killed-photo message window. Each clear is intercepted by
# the live-stream floor and cannot destroy captured evidence.
if source.count("const <String>['logcat', '-c']") != 10:
    fail('the ten non-destructive log clear sites changed without repinning')

killed_cursor = source.find(
    'final killedPhotoCursor = await _deviceLogcatCursor(recipientId);'
)
killed_send = source.find("phase: 'send_killed_jpeg'", killed_cursor)
killed_flow = source.find(
    'await _deviceLogSince(recipientId, killedPhotoCursor)', killed_send
)
killed_terminal = source.find(
    "flow.contains('PUSH_BACKGROUND_NOTIFICATION_SHOWN')", killed_flow
)
if not (0 <= killed_cursor < killed_send < killed_flow < killed_terminal):
    fail('the killed-photo proof no longer waits on its exact live-stream window')
STREAM_SEAM

set +e
dart run "$runner" \
  --scenario android_group_reaction_recipient \
  --validate-artifacts "$tmp_dir/validation" \
  >"$tmp_dir/validation.stdout" 2>"$tmp_dir/validation.stderr"
validation_status=$?
set -e

[ "$validation_status" -ne 0 ] || {
  printf 'FAIL: missing device artifacts unexpectedly validated\n' >&2
  exit 1
}
validation_verdict="$tmp_dir/validation/android_group_reaction_recipient/android_group_reaction_recipient_orchestrator_verdict.json"
[ -f "$validation_verdict" ] || {
  printf 'FAIL: missing-artifact validation did not persist a verdict\n' >&2
  exit 1
}
grep -q '"ok":false' "$validation_verdict" || {
  printf 'FAIL: missing-artifact validation verdict was not failed\n' >&2
  exit 1
}

printf 'PASS: Plan 257 device runner is discoverable, staged, and fail-closed\n'

printf 'RUN: Plan 398 staging transaction contract\n'

plan398_fake_bin="$tmp_dir/plan398-fake-bin"
mkdir -p "$plan398_fake_bin"

cat >"$plan398_fake_bin/sims" <<'PY'
#!/usr/bin/env python3
import hashlib
import json
import os
import pathlib
import sys

args = sys.argv[1:]
try:
    capability = args[args.index("--only") + 1]
except (ValueError, IndexError):
    raise SystemExit(91)
profiles = {
    "build.android.production_fcm": "android.production_fcm",
    "build.ios.device.production": "ios.device.production",
}
profile = profiles.get(capability)
if profile is None:
    raise SystemExit(92)
expected_relay_addresses = os.environ.get(
    "PLAN398_TEST_EXPECTED_RELAY_ADDRESSES"
)
if (
    expected_relay_addresses is not None
    and os.environ.get("MKNOON_RELAY_ADDRESSES") != expected_relay_addresses
):
    raise SystemExit(93)
variant = os.environ.get("PLAN398_TEST_BUILD_VARIANT", "v1")
sha = lambda value: hashlib.sha256(value.encode()).hexdigest()
input_digest = sha(f"input:{profile}:{variant}")
artifact_digest = sha(f"artifact:{profile}:{variant}")
source_digest = sha(f"report-source:{variant}")
cache = pathlib.Path(os.environ["SIMS_CACHE_DIR"])
entry = cache / profile / input_digest
entry.mkdir(parents=True, exist_ok=True)
report_generation_path = cache / profile / "report-generation"
report_generation = (
    int(report_generation_path.read_text()) + 1
    if report_generation_path.exists()
    else 1
)
report_generation_path.write_text(f"{report_generation}\n")
if profile.startswith("ios."):
    artifact = entry / "ios.device.production.bundle"
    artifact.mkdir(exist_ok=True)
    (artifact / "bundle_manifest.json").write_text(
        json.dumps({"fixture": variant}) + "\n"
    )
else:
    artifact = entry / "artifact.apk"
    artifact.write_text(f"{profile}:{variant}\n")
attestation = entry / "attestation.json"
if not attestation.exists():
    attestation.write_text(json.dumps({
        "schemaVersion": 1,
        "profileId": profile,
        "inputDigest": input_digest,
        "artifactDigest": artifact_digest,
        "artifactPath": str(artifact.resolve()),
        "redactedCommand": ["fixture-build", profile],
        "createdAt": "2026-08-23T12:00:00Z",
    }, sort_keys=True) + "\n")
report = pathlib.Path(os.environ["SIMS_REPORT_PATH"])
report.parent.mkdir(parents=True, exist_ok=True)
report.write_text(json.dumps({
    "schemaVersion": 1,
    "generatedAt": "2026-08-23T12:00:00Z",
    "testReportGeneration": report_generation,
    "sourceDigest": source_digest,
    "builds": {
        "requestedProfiles": 1,
        "actualBuilds": 1,
        "hits": 0,
        "misses": 1,
        "invalidations": [],
        "artifactDigests": {profile: artifact_digest},
        "declaredExceptions": [],
        "builtProfileIds": [profile],
        "cacheHitProfileIds": [],
        "failedProfileIds": [],
        "profileElapsedMs": {profile: 1},
        "totalElapsedMs": 1,
    },
}, sort_keys=True) + "\n")
PY

cat >"$plan398_fake_bin/go" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import sys

args = sys.argv[1:]
try:
    output = pathlib.Path(args[args.index("-o") + 1])
except (ValueError, IndexError):
    raise SystemExit(93)
output.parent.mkdir(parents=True, exist_ok=True)
output.write_bytes(
    ("plan398 deterministic linux relay " +
     os.environ.get("PLAN398_TEST_BUILD_VARIANT", "v1") + "\n").encode()
)
output.chmod(0o755)
PY

cat >"$plan398_fake_bin/xcodebuild" <<'PY'
#!/usr/bin/env python3
import base64
import os
import pathlib
import sys

args = sys.argv[1:]
profile = "ios.device.group_reaction_notification_397"
required = {
    "build-for-testing",
    "-workspace",
    "ios/Runner.xcworkspace",
    "-scheme",
    "Runner",
    "-configuration",
    "Release",
    "ENABLE_TESTABILITY=YES",
    "-destination",
    "generic/platform=iOS",
    "FLUTTER_TARGET=lib/main.dart",
}
if not required.issubset(set(args)):
    raise SystemExit(97)
try:
    derived = pathlib.Path(args[args.index("-derivedDataPath") + 1])
    encoded = next(item.split("=", 1)[1] for item in args if item.startswith("DART_DEFINES="))
except (ValueError, IndexError, StopIteration):
    raise SystemExit(98)
defines = {
    base64.b64decode(item).decode("utf-8")
    for item in encoded.split(",")
}
if not {
    "E2E_TEST_MODE=true",
    f"SIMS_BUILD_PROFILE_ID={profile}",
}.issubset(defines) or not any(
    item.startswith("MKNOON_RELAY_ADDRESSES=") for item in defines
):
    raise SystemExit(99)
output = derived / "Build/Products/Release-iphoneos/Runner.app"
output.mkdir(parents=True)
variant = os.environ.get("PLAN398_TEST_BUILD_VARIANT", "v1")
(output / "Info.plist").write_text(f"setup-profile={profile}\n")
(output / "Runner").write_text(f"signed-setup-fixture={variant}\n")
(output / "Runner").chmod(0o755)
PY

cat >"$plan398_fake_bin/ssh" <<'PY'
#!/usr/bin/env python3
import hashlib
import os
import pathlib
import shlex
import shutil
import sys

remote = pathlib.Path(os.environ["PLAN398_FAKE_REMOTE_DIR"])
installed = remote / "installed-relay"
running = remote / "running-relay"
command = shlex.split(sys.argv[-1])
if command == ["systemctl", "is-active", "relay-server"]:
    print("active")
elif command == ["/usr/local/bin/relay-server", "version"]:
    print("relay-server v1.9.0")
elif command == ["systemctl", "show", "relay-server", "--property=MainPID", "--value"]:
    print("4242")
elif command == ["sha256sum", "/usr/local/bin/relay-server"]:
    print(hashlib.sha256(installed.read_bytes()).hexdigest(), command[1])
elif command == ["sudo", "-n", "sha256sum", "/proc/4242/exe"]:
    print(hashlib.sha256(running.read_bytes()).hexdigest(), command[3])
elif command[:4] == ["sudo", "install", "-m", "0755"]:
    source = remote / "tmp" / pathlib.Path(command[4]).name
    shutil.copyfile(source, installed)
    installed.chmod(0o755)
elif command == ["sudo", "systemctl", "restart", "relay-server"]:
    stale_once = os.environ.get("PLAN398_FAKE_RESTART_STALE_ONCE") == "1"
    sentinel = remote / "stale-restart-consumed"
    if stale_once and not sentinel.exists():
        sentinel.write_text("consumed\n")
    else:
        shutil.copyfile(installed, running)
        running.chmod(0o755)
elif command[:2] == ["rm", "-f"]:
    (remote / "tmp" / pathlib.Path(command[2]).name).unlink(missing_ok=True)
else:
    print("unsupported fake ssh command: " + repr(command), file=sys.stderr)
    raise SystemExit(94)
PY

cat >"$plan398_fake_bin/scp" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import shutil
import sys

remote = pathlib.Path(os.environ["PLAN398_FAKE_REMOTE_DIR"])
source, destination = sys.argv[-2:]
if ":" in source:
    remote_path = source.split(":", 1)[1]
    if remote_path != "/usr/local/bin/relay-server":
        raise SystemExit(95)
    shutil.copyfile(remote / "installed-relay", destination)
elif ":" in destination:
    remote_path = destination.split(":", 1)[1]
    target = remote / "tmp" / pathlib.Path(remote_path).name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
else:
    raise SystemExit(96)
PY

cat >"$plan398_fake_bin/dart" <<'PY'
#!/usr/bin/env python3
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

args = sys.argv[1:]
event_log = pathlib.Path(os.environ["PLAN398_TEST_EVENT_LOG"])
def event(value):
    with event_log.open("a") as output:
        output.write(value + "\n")
        output.flush()
        os.fsync(output.fileno())

if "--validate-artifacts" in args:
    raise SystemExit(int(os.environ.get("PLAN398_FAKE_VALIDATION_EXIT", "0")))

if "--manual-send-existing-state" in args:
    required = {
        "--trace-only-existing-state",
        "--manual-send-existing-state",
        "--no-child-builds",
        "--group-name",
        "--existing-target-marker",
        "--staging-manifest",
    }
    if not required.issubset(set(args)):
        raise SystemExit(51)
    final_options = (
        "--plan398-final-attempt-authorization-id",
        "--plan398-final-runner-product-receipt-sha256",
        "--plan398-final-runner-install-terminal-sha256",
        "--plan398-attempt-02-receipt-sha256",
    )
    final_requested = any(option in args for option in final_options)
    live_diagnostic = "--live-diagnostic" in args
    if live_diagnostic:
        if final_requested:
            raise SystemExit(57)
        if not any(
            value.endswith("run_group_reaction_notification_device.dart")
            for value in args
        ):
            raise SystemExit(58)
        event("live_diagnostic_runner")
    artifact_dir = pathlib.Path(args[args.index("--artifact-dir") + 1])
    terminal = artifact_dir / "plan398_existing_state_trace_terminal_receipt.json"
    if final_requested:
        if not all(option in args for option in final_options):
            raise SystemExit(54)
        if terminal.exists():
            raise SystemExit(55)
        authorities = (
            (
                "--plan398-final-runner-product-receipt-sha256",
                artifact_dir / "final-runner-update/build-terminal-receipt.json",
            ),
            (
                "--plan398-final-runner-install-terminal-sha256",
                artifact_dir / "final-runner-update/install-terminal-receipt.json",
            ),
            (
                "--plan398-attempt-02-receipt-sha256",
                artifact_dir / "preclaim-attempts/attempt-02/receipt.json",
            ),
        )
        if (
            args[args.index("--plan398-final-attempt-authorization-id") + 1]
            != "plan398-reviewed-final-same-container-manual-trace-v1"
            or any(
                hashlib.sha256(path.read_bytes()).hexdigest()
                != args[args.index(option) + 1]
                for option, path in authorities
            )
        ):
            raise SystemExit(56)
        event("manual_runner_final_receipts_bound")
    trace_manifest = pathlib.Path(args[args.index("--staging-manifest") + 1])
    trace_authority = json.loads(trace_manifest.read_text())
    if (
        trace_authority.get("schema")
        != "mknoon.plan398.existing-state-trace-manifest.v1"
        or trace_authority.get("provider") != "apns"
        or trace_authority.get("allowAppDataReset") is not False
        or set(trace_authority.get("iosCapture", {}))
        != {"bundleId", "systemLogExecutable"}
    ):
        raise SystemExit(52)
    manual_exit = int(os.environ.get("PLAN398_FAKE_MANUAL_EXIT", "0"))
    if final_requested:
        terminal.write_text(json.dumps({
            "schema": "mknoon.plan398.existing-state-trace-terminal-receipt.v1",
            "status": "failure" if manual_exit else "success",
            "attempt": "attempt-03",
        }, sort_keys=True) + "\n")
        terminal.chmod(0o600)
    if manual_exit:
        raise SystemExit(manual_exit)
    artifact_dir.mkdir(parents=True, exist_ok=True)
    claim = artifact_dir / "plan398_existing_state_trace_claim.json"
    claim.write_text(json.dumps({
        "schema": "mknoon.plan398.existing-state-trace-claim.v1",
        "ownerRunId": "existing-state-trace",
        "singleOwnerDeclared": True,
        "claimValue": "fixture-manual-trace-claim",
    }, sort_keys=True) + "\n")
    claim.chmod(0o600)
    artifact = artifact_dir / "plan398_existing_state_trace.json"
    if live_diagnostic:
        artifact.write_text(json.dumps({
            "schema": "mknoon.plan398.ios-group-message-existing-state-live-diagnostic.v1",
            "version": 1,
            "authorityMode": "live_diagnostic",
            "status": "trace_complete",
            "closurePassed": False,
            "disposition": "clean_nonreproduction",
            "traceAttemptClaimed": True,
            "traceAttemptClaimSha256": hashlib.sha256(claim.read_bytes()).hexdigest(),
        }, sort_keys=True) + "\n")
        artifact.chmod(0o600)
        terminal_mode = os.environ.get("PLAN398_FAKE_LIVE_TERMINAL_MODE", "valid")
        terminal_payload = {
            "schema": "mknoon.plan398.existing-state-live-diagnostic-terminal-receipt.v1",
            "version": 1,
            "scenario": "ios_chat_group_message_and_reaction_recipient",
            "authorityMode": "live_diagnostic",
            "terminalStatus": "success",
            "captureExitCode": 0,
            "traceAttemptClaimed": True,
        }
        if terminal_mode == "failure":
            terminal_payload["terminalStatus"] = "typed_failure"
            terminal_payload["captureExitCode"] = 1
        elif terminal_mode == "wrong_authority":
            terminal_payload["authorityMode"] = "legacy_final_attempt"
        if terminal_mode == "malformed":
            terminal.write_text("{not-json\n")
            terminal.chmod(0o600)
        elif terminal_mode == "symlink":
            target = artifact_dir / "terminal-target.json"
            target.write_text(json.dumps(terminal_payload) + "\n")
            target.chmod(0o600)
            terminal.symlink_to(target.name)
        elif terminal_mode != "missing":
            terminal.write_text(json.dumps(terminal_payload, sort_keys=True) + "\n")
            terminal.chmod(0o600)
    else:
        artifact.write_text("{}\n")
    event("manual_send")
    raise SystemExit(0)

for option in (
    "--prebuilt-ios-setup-app",
    "--prebuilt-ios-setup-app-sha256",
):
    if option not in args or args.index(option) + 1 >= len(args):
        raise SystemExit(46)
if "--no-child-builds" not in args:
    raise SystemExit(47)

mode = os.environ.get("PLAN398_FAKE_RUNNER_MODE", "normal")
ready = os.environ.get("PLAN398_FAKE_READY_FILE")
artifact_dir = pathlib.Path(args[args.index("--artifact-dir") + 1])
retained_central = artifact_dir / "plan397_androidBuildReport.json"
if mode == "preclaim-fail":
    artifact_dir.mkdir(parents=True, exist_ok=True)
    retained_central.write_text("retained preclaim fixture\n")
    (artifact_dir / "ios_chat_group_message_and_reaction_recipient_capture_failure.json").write_text(
        json.dumps({"status": "environment_blocked"}) + "\n"
    )
    raise SystemExit(41)
if retained_central.exists():
    raise SystemExit(50)
if mode == "pause-before-claim":
    if ready:
        pathlib.Path(ready).write_text("ready\n")
    time.sleep(60)
    raise SystemExit(42)
if mode == "mutate-before-claim":
    with pathlib.Path(os.environ["PLAN398_TEST_SOURCE_FILE"]).open("a") as source:
        source.write("changed at send boundary\n")
if mode == "mutate-target-before-claim":
    os.environ["PLAN398_RELAY_TARGET"] = "alternate@relay"
if mode == "mutate-setup-before-claim":
    setup = pathlib.Path(args[args.index("--prebuilt-ios-setup-app") + 1])
    with (setup / "Runner").open("a") as output:
        output.write("changed at send boundary\n")

helper = pathlib.Path(os.environ["PLAN398_PROJECT_ROOT"]) / \
    "integration_test/scripts/ios_group_message_diagnostic_staging.py"
claim = subprocess.run([sys.executable, str(helper), "claim-send"], check=False)
if claim.returncode != 0:
    raise SystemExit(43)
if mode == "after-claim-wait":
    if ready:
        pathlib.Path(ready).write_text("ready\n")
    time.sleep(60)
    raise SystemExit(44)

receipt_path = pathlib.Path(os.environ["PLAN398_DEPLOYMENT_RECEIPT"])
claim_path = pathlib.Path(os.environ["PLAN398_DIAGNOSTIC_ATTEMPT_MARKER"])
campaign = pathlib.Path(os.environ["PLAN398_ACTIVE_TRANSACTION_LEASE"]).parent
snapshot = json.loads((campaign / "prepared-snapshot.json").read_text())
setup_path = pathlib.Path(args[args.index("--prebuilt-ios-setup-app") + 1])
setup_sha = args[args.index("--prebuilt-ios-setup-app-sha256") + 1]
if setup_path != campaign / "ios-setup-preparation/Runner.app":
    raise SystemExit(48)
if setup_sha != snapshot["iosSetup"]["applicationSha256"]:
    raise SystemExit(49)
artifact_dir.mkdir(parents=True, exist_ok=True)
artifact = artifact_dir / "ios_chat_group_message_and_reaction_recipient.json"
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
artifact.write_text(json.dumps({
    "schema": "mknoon.plan398.ios-group-message-diagnostic.v1",
    "status": "diagnostic_complete",
    "diagnosticOnlyMessageWindow": True,
    "closurePassed": False,
    "singleOwnerDeclared": True,
    "diagnosticAttemptClaimed": True,
    "stagingDeploymentReceiptSha256": sha(receipt_path),
    "diagnosticAttemptClaimSha256": sha(claim_path),
    "buildInputs": {
        "androidProfileId": snapshot["android"]["profileId"],
        "androidInputDigest": snapshot["android"]["inputDigest"],
        "androidArtifactDigest": snapshot["android"]["artifactDigest"],
        "iosProfileId": snapshot["ios"]["profileId"],
        "iosInputDigest": snapshot["ios"]["inputDigest"],
        "iosArtifactDigest": snapshot["ios"]["artifactDigest"],
        "setupProfileId": snapshot["iosSetup"]["profileId"],
        "setupApplicationSha256": snapshot["iosSetup"]["applicationSha256"],
        "setupPreparationCompileCommands": snapshot["iosSetup"]["centralCompileCommands"],
        "captureChildBuildCount": snapshot["iosSetup"]["childBuildCount"],
    },
}, sort_keys=True) + "\n")
if mode == "after-claim-fail":
    raise SystemExit(45)
event("send")
PY

chmod +x "$plan398_fake_bin/sims" "$plan398_fake_bin/go" \
  "$plan398_fake_bin/ssh" "$plan398_fake_bin/scp" \
  "$plan398_fake_bin/dart" "$plan398_fake_bin/xcodebuild"

python3 - "$ROOT_DIR" "$tmp_dir/plan398-contract" "$plan398_fake_bin" <<'PLAN398_CONTRACT'
import hashlib
import json
import os
import pathlib
import shutil
import signal
import stat
import subprocess
import sys
import time
import fcntl

project = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path(sys.argv[2]).resolve()
fake_bin = pathlib.Path(sys.argv[3]).resolve()
helper = project / "integration_test/scripts/ios_group_message_diagnostic_staging.py"
scenario = "ios_chat_group_message_and_reaction_recipient"
restart_authorization = "plan398-reviewed-current-source-restart-v1"
restart_schema = "mknoon.plan398.preclaim-current-source-restart.v1"
final_attempt_authorization = (
    "plan398-reviewed-final-same-container-manual-trace-v1"
)
final_attempt_schema = (
    "mknoon.plan398.final-manual-preclaim-attempt-archive.v2"
)
fixed_attempt01_receipt_sha = (
    "760ac4280f93415845b31c30b7cfbd1e4d0e10efccb4d626ebcd376605295060"
)
fixed_attempt01_hashes = {
    "journalSha256": (
        "f62874be7b49f3593d5d5d72b5aa95ea0b646ebf0426f3dc45011c3bde0b023d"
    ),
    "deviceLogSha256": (
        "553071a186a7d4a69b1c8c54814c1aaddc68d9145b7dcf8f9d8615f39ff5e615"
    ),
    "traceManifestSha256": (
        "65e23da2bffb949f0491fb00ac3de875d56063ef4307fc6f5f78d121ecf7f729"
    ),
    "traceRelayStateSha256": (
        "b0e1d7d2ac2ebf40c827224b7ac124340f11ef4cad0f6f0d00484e2b9bd32d69"
    ),
}


def fail(message):
    raise SystemExit("FAIL: Plan 398 staging transaction contract: " + message)


def require(condition, message):
    if not condition:
        fail(message)


helper_source = helper.read_text()
for literal in (
    final_attempt_authorization,
    final_attempt_schema,
    fixed_attempt01_receipt_sha,
    *fixed_attempt01_hashes.values(),
):
    require(
        literal in helper_source,
        "final attempt helper omits reviewed literal " + literal,
    )
for option in (
    "--final-attempt-authorization-id",
    "--final-attempt-journal-sha256",
    "--final-attempt-device-log-sha256",
    "--final-attempt-trace-manifest-sha256",
    "--final-attempt-trace-relay-state-sha256",
):
    require(option in helper_source, "final attempt helper omits " + option)


def sha_bytes(value):
    return hashlib.sha256(value).hexdigest()


def sha_file(path):
    return sha_bytes(path.read_bytes())


def canonical_json(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def entity_digest(path):
    digest = hashlib.sha256()
    for entry in sorted(path.rglob("*"), key=lambda item: item.relative_to(path).as_posix()):
        relative = entry.relative_to(path).as_posix().encode()
        mode = stat.S_IMODE(entry.stat().st_mode)
        digest.update(b"D\0" if entry.is_dir() else b"F\0")
        digest.update(relative)
        digest.update(b"\0")
        digest.update(f"{mode:o}".encode())
        digest.update(b"\0")
        if entry.is_file():
            digest.update(entry.read_bytes())
    return digest.hexdigest()


class Case:
    pass


def make_case(name):
    case = Case()
    case.root = root / name
    case.root.mkdir(parents=True)
    case.campaign = case.root / "diagnostic"
    case.claim = case.root / "diagnostic-campaign-claimed.json"
    case.staging = case.root / "staging.json"
    case.staging.write_text(json.dumps({
        "schema": "mknoon.plan257.group-reaction-notification-staging.v1",
        "version": 1,
        "environment": "staging",
        "relayActive": True,
        "providerConfigured": True,
        "providerProbeSucceeded": True,
        "productionDeploymentPerformed": False,
        "allowAppDataReset": True,
        "provider": "fcm",
        "candidateRelayRevision": "relay-server v1.9.0",
        "candidateRelaySha256": "0" * 64,
        "relayAddresses": ["/dns4/fixture.invalid/tcp/443/wss/p2p/relay"],
    }, sort_keys=True) + "\n")
    case.prior_manifest_bytes = case.staging.read_bytes()
    case.prior_candidate = case.root / "staging-manifest.candidate-02.json"
    candidate_manifest = json.loads(case.prior_manifest_bytes)
    candidate_manifest["provider"] = "apns"
    candidate_manifest["iosCapture"] = {
        "bundleId": "com.mknoon.app",
        "workspace": "ios/Runner.xcworkspace",
        "scheme": "Runner",
        "systemLogExecutable": "idevicesyslog",
        "fixtureCreateSelector": "fixture-create",
        "fixtureAuthorSelector": "fixture-author",
        "notificationPrepareSelector": "notification-prepare",
        "notificationTapSelector": "notification-tap",
    }
    case.prior_candidate.write_text(
        json.dumps(candidate_manifest, sort_keys=True) + "\n"
    )
    case.remote = case.root / "remote"
    (case.remote / "tmp").mkdir(parents=True)
    case.prior_relay_bytes = b"plan398 prior relay fixture\n"
    (case.remote / "installed-relay").write_bytes(case.prior_relay_bytes)
    (case.remote / "running-relay").write_bytes(case.prior_relay_bytes)
    case.key = case.root / "relay-key"
    case.key.write_text("fixture key\n")
    case.service = case.root / "service-account.json"
    case.service.write_text("{}\n")
    case.source = case.root / "source-sentinel"
    case.source.write_text("source-v1\n")
    case.events = case.root / "events.log"
    case.ready = case.root / "ready"
    case.target = "fixture@relay"
    case.authority = case.root / "deployment-state-02.json"
    case.authority.write_text(json.dumps({
        "schema": "mknoon.plan397.deployment-state.v1",
        "runId": "plan397-fixture",
        "relayTargetSha256": sha_bytes(case.target.encode()),
        "stagingManifestPathSha256": sha_bytes(str(case.staging.resolve()).encode()),
        "priorRelayVersion": "relay-server v1.9.0",
        "priorRelaySha256": sha_bytes(case.prior_relay_bytes),
        "candidateRelaySha256": "1" * 64,
        "priorManifestSha256": sha_bytes(case.prior_manifest_bytes),
        "candidateManifestSha256": sha_file(case.prior_candidate),
    }, sort_keys=True) + "\n")
    return case


def environment(case, mode="normal", variant="v1", **extra):
    value = os.environ.copy()
    value.update({
        "PLAN398_TEST_MODE": "1",
        "PLAN398_CAMPAIGN_ROOT": str(case.campaign),
        "PLAN398_TEST_EVENT_LOG": str(case.events),
        "PLAN398_TEST_SOURCE_FILE": str(case.source),
        "PLAN398_TEST_BUILD_VARIANT": variant,
        "PLAN398_TEST_EXPECTED_RELAY_ADDRESSES":
            "/dns4/fixture.invalid/tcp/443/wss/p2p/relay",
        "MKNOON_RELAY_ADDRESSES": "ambient-caller-value-must-not-win",
        "PLAN398_FAKE_RUNNER_MODE": mode,
        "PLAN398_FAKE_READY_FILE": str(case.ready),
        "PLAN398_FAKE_REMOTE_DIR": str(case.remote),
        "PLAN398_SIMS_COMMAND": str(fake_bin / "sims"),
        "PLAN398_GO_COMMAND": str(fake_bin / "go"),
        "PLAN398_XCODEBUILD_COMMAND": str(fake_bin / "xcodebuild"),
        "PLAN398_SSH_COMMAND": str(fake_bin / "ssh"),
        "PLAN398_SCP_COMMAND": str(fake_bin / "scp"),
        "PLAN398_DART_COMMAND": str(fake_bin / "dart"),
    })
    value.update({key: str(item) for key, item in extra.items()})
    return value


def command(case, run_id="diagnostic"):
    return [
        sys.executable, str(helper), "run",
        "--project-root", str(project),
        "--run-id", run_id,
        "--prior-authority", str(case.authority),
        "--sender", "ANDROIDPHYSICAL398",
        "--recipient", "00008150-001C3C6A3684401C",
        "--staging-manifest", str(case.staging),
        "--relay-target", case.target,
        "--relay-key", str(case.key),
        "--relay-addresses", "/dns4/fixture.invalid/tcp/443/wss/p2p/relay",
        "--service-account", str(case.service),
        "--single-owner",
    ]


def run(case, mode="normal", variant="v1", run_id="diagnostic", **extra):
    return subprocess.run(
        command(case, run_id),
        cwd=project,
        env=environment(case, mode, variant, **extra),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def events(case):
    return case.events.read_text().splitlines() if case.events.exists() else []


def seed_manual_case(name):
    case = make_case(name)
    seeded = run(case, mode="preclaim-fail")
    require(seeded.returncode != 0, name + " unexpectedly completed seed run")
    require(not case.claim.exists(), name + " seed run created a diagnostic claim")
    assert_restored(case)
    case.trace = case.root / "manual-trace"
    case.trace.mkdir()
    case.trace_failure = case.trace / "plan398_existing_state_trace_failure.json"
    case.trace_failure.write_text(json.dumps({
        "schema": "mknoon.plan398.existing-state-trace-failure.v1",
        "status": "configuration_blocked",
        "stage": "configuration",
    }, sort_keys=True) + "\n")
    case.trace_failure.chmod(0o600)
    case.trace_failure_sha = sha_file(case.trace_failure)
    return case


def seed_prior_manual_preclaim_evidence(
    case,
    sender="ANDROIDPHYSICAL398",
):
    receipt = json.loads((case.campaign / "deployment-state.json").read_text())
    candidate = json.loads((case.campaign / "candidate-staging-manifest.json").read_text())
    journal = case.trace / "plan398_existing_state_trace_command_journal.json"
    device_log = case.trace / f"device_logcat_{sender}.log"
    trace_manifest = case.trace / "plan398_existing_state_trace_manifest.json"
    trace_relay_state = case.trace / "plan398_existing_state_trace_relay_state.json"
    journal.write_bytes(canonical_json({
        "schema": "mknoon.plan398.existing-state-trace-command-journal.v1",
        "status": "preclaim_failed",
    }))
    device_log.write_bytes(b"retained manual preclaim device log\n")
    trace_manifest.write_bytes(canonical_json({
        "schema": "mknoon.plan398.existing-state-trace-manifest.v1",
        "version": 1,
        "environment": "staging",
        "relayActive": True,
        "providerConfigured": True,
        "providerProbeSucceeded": True,
        "productionDeploymentPerformed": False,
        "allowAppDataReset": False,
        "candidateRelayRevision": receipt["candidateRelayRevision"],
        "candidateRelaySha256": receipt["candidateRelaySha256"],
        "provider": "apns",
        "relayAddresses": candidate["relayAddresses"],
        "iosCapture": {
            "bundleId": "com.mknoon.app",
            "systemLogExecutable": "idevicesyslog",
        },
    }))
    trace_relay_state.write_bytes(canonical_json({
        "schema": "mknoon.plan398.manual-trace-relay-state.v1",
        "status": "preclaim_failed",
    }))
    for source in (journal, device_log, trace_manifest, trace_relay_state):
        source.chmod(0o600)
    case.prior_manual_preclaim_sources = {
        "journalSha256": journal,
        "deviceLogSha256": device_log,
        "traceManifestSha256": trace_manifest,
        "traceRelayStateSha256": trace_relay_state,
    }
    case.prior_manual_preclaim_hashes = {
        key: sha_file(path)
        for key, path in case.prior_manual_preclaim_sources.items()
    }


def seed_final_attempt_evidence(case):
    pixel = "21071FDF600CSC"
    seed_prior_manual_preclaim_evidence(case, sender=pixel)
    archive_root = case.trace / "preclaim-attempts"
    archive_root.mkdir(mode=0o700)
    archive_root.chmod(0o700)
    attempt01 = archive_root / "attempt-01"
    attempt01.mkdir(mode=0o700)
    attempt01.chmod(0o700)
    for source in case.prior_manual_preclaim_sources.values():
        retained = attempt01 / source.name
        shutil.copyfile(source, retained)
        retained.chmod(0o600)
    attempt01_receipt = attempt01 / "receipt.json"
    attempt01_payload = {
        "schema": "mknoon.plan398.manual-preclaim-attempt-archive.v1",
        "attempt": "attempt-01",
        **case.prior_manual_preclaim_hashes,
    }
    attempt01_receipt.write_bytes(canonical_json(attempt01_payload))
    attempt01_receipt.chmod(0o600)

    journal = case.prior_manual_preclaim_sources["journalSha256"]
    device_log = case.prior_manual_preclaim_sources["deviceLogSha256"]
    journal.write_bytes(canonical_json({
        "schema": "mknoon.plan398.existing-state-trace-command-journal.v1",
        "status": "attempt-02-preclaim-failed",
    }))
    device_log.write_bytes(b"attempt-02 exact Pixel device log bytes\n")
    for key, source in case.prior_manual_preclaim_sources.items():
        source.chmod(0o644 if key == "deviceLogSha256" else 0o600)

    case.final_pixel = pixel
    case.attempt01 = attempt01
    case.attempt01_receipt = attempt01_receipt
    case.attempt01_payload = attempt01_payload
    case.attempt01_hashes = dict(case.prior_manual_preclaim_hashes)
    case.attempt01_receipt_sha = sha_file(attempt01_receipt)
    case.attempt01_entity_sha = entity_digest(attempt01)
    case.final_sources = dict(case.prior_manual_preclaim_sources)
    case.final_hashes = {
        key: sha_file(path) for key, path in case.final_sources.items()
    }
    for source in case.final_sources.values():
        source.chmod(0o600)
    attempt02 = archive_root / "attempt-02"
    attempt02.mkdir(mode=0o700)
    attempt02.chmod(0o700)
    for source in case.final_sources.values():
        retained = attempt02 / source.name
        shutil.copyfile(source, retained)
        retained.chmod(0o600)
    attempt02_receipt = attempt02 / "receipt.json"
    attempt02_receipt.write_bytes(canonical_json({
        "schema": final_attempt_schema,
        "attempt": "attempt-02",
        "authorizationId": final_attempt_authorization,
        "priorAttempt": "attempt-01",
        "priorAttemptReceiptSha256": case.attempt01_receipt_sha,
        "priorAttemptEntitySha256": case.attempt01_entity_sha,
        **case.final_hashes,
    }))
    attempt02_receipt.chmod(0o600)
    case.attempt02 = attempt02
    case.attempt02_receipt = attempt02_receipt
    case.attempt02_receipt_sha = sha_file(attempt02_receipt)
    case.evidence = {
        "attempt01": {
            "entitySha256": case.attempt01_entity_sha,
            "receiptSha256": case.attempt01_receipt_sha,
        },
        "attempt02": {
            "entitySha256": entity_digest(attempt02),
            "receiptSha256": case.attempt02_receipt_sha,
        },
        "retainedFailureSha256": case.trace_failure_sha,
    }

    namespace = case.trace / "final-runner-update"
    namespace.mkdir(mode=0o700)
    namespace.chmod(0o700)
    xcode_build_settings = {
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": (
            "$(inherited) MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP"
        ),
    }
    build_argv = [
        "flutter", "build", "ios", "--release", "--target=lib/main.dart",
        "--dart-define=PRODUCTION_APNS=true", "--build-name=1.2.398",
        "--build-number=39815",
    ]
    build_claim = namespace / "build-claim.json"
    build_claim.write_bytes(canonical_json({
        "schema": "mknoon.plan398.final-runner-build-claim.v1",
        "authorizationId": final_attempt_authorization,
        "recipient": "00008030-001A6D2801BB802E",
        "bundleIdentifier": "com.mknoon.app",
        "configuration": "Release",
        "buildName": "1.2.398",
        "buildNumber": "39815",
        "buildArgv": build_argv,
        "xcodeBuildSettings": xcode_build_settings,
        "evidence": case.evidence,
    }))
    build_claim.chmod(0o600)
    product = {
        "relativePath": "build/ios/iphoneos/Runner.app",
        "entitySha256": "1" * 64,
        "applicationSha256": "2" * 64,
        "runnerExecutableSha256": "3" * 64,
        "infoPlistSha256": "4" * 64,
        "canonicalSignedEntitlementsSha256": "5" * 64,
        "embeddedMobileProvisionSha256": "6" * 64,
        "bundleIdentifier": "com.mknoon.app",
        "executableName": "Runner",
        "bundleShortVersion": "1.2.398",
        "bundleVersion": "39815",
        "configuration": "Release",
        "signedIdentifier": "com.mknoon.app",
        "signedTeamIdentifier": "TEAM123456",
        "profileTeamIdentifier": "TEAM123456",
        "profileApplicationIdentifier": "TEAM123456.com.mknoon.app",
        "profileExpirationUtc": "2099-01-01T00:00:00Z",
        "developerCertificateSha256": ["7" * 64],
    }
    build_receipt = namespace / "build-terminal-receipt.json"
    build_receipt.write_bytes(canonical_json({
        "schema": "mknoon.plan398.final-runner-build-terminal-receipt.v1",
        "status": "succeeded",
        "authorizationId": final_attempt_authorization,
        "recipient": "00008030-001A6D2801BB802E",
        "bundleIdentifier": "com.mknoon.app",
        "claimSha256": sha_file(build_claim),
        "configuration": "Release",
        "buildName": "1.2.398",
        "buildNumber": "39815",
        "buildArgv": build_argv,
        "xcodeBuildSettings": xcode_build_settings,
        "suiteSourceDigestBefore": sha_file(case.source),
        "suiteSourceDigestAfter": sha_file(case.source),
        "evidence": case.evidence,
        "product": product,
    }))
    build_receipt.chmod(0o600)
    build_receipt_sha = sha_file(build_receipt)
    inventory_pre = {
        "appDataContainer": "file:///private/fixed-container",
        "bundleIdentifier": "com.mknoon.app",
        "bundleShortVersion": "1.0.0",
        "bundleVersion": "1",
        "executableName": "Runner",
        "url": "file:///private/bundles/PRE/Runner.app",
    }
    inventory_post = {
        **inventory_pre,
        "bundleShortVersion": product["bundleShortVersion"],
        "bundleVersion": product["bundleVersion"],
        "url": "file:///private/bundles/POST/Runner.app",
    }
    def continuity_sample(inventory, *, size, mtime, digest):
        return {
            "recipient": "00008030-001A6D2801BB802E",
            "bundleIdentifier": "com.mknoon.app",
            "inventory": inventory,
            "afcRoot": {
                "path": "/",
                "st_ifmt": "S_IFDIR",
                "st_birthtime": 1700000000,
            },
            "identityDatabase": {
                "path": "Documents/identity.db",
                "st_ifmt": "S_IFREG",
                "st_birthtime": 1700000100,
                "diagnostics": {
                    "st_nlink": 1,
                    "st_size": size,
                    "st_mtime": mtime,
                    "sha256": digest,
                },
            },
        }
    pre_samples = [
        continuity_sample(
            inventory_pre, size=4096, mtime=1700000200, digest="8" * 64
        ),
        continuity_sample(
            inventory_pre, size=8192, mtime=1700000300, digest="9" * 64
        ),
    ]
    post_sample = continuity_sample(
        inventory_post, size=12288, mtime=1700000400, digest="a" * 64
    )
    install_claim = namespace / "install-claim.json"
    install_claim.write_bytes(canonical_json({
        "schema": "mknoon.plan398.final-runner-install-claim.v1",
        "authorizationId": final_attempt_authorization,
        "recipient": "00008030-001A6D2801BB802E",
        "bundleIdentifier": "com.mknoon.app",
        "buildClaimSha256": sha_file(build_claim),
        "buildReceiptSha256": build_receipt_sha,
        "evidence": case.evidence,
        "productEntitySha256": product["entitySha256"],
        "productApplicationSha256": product["applicationSha256"],
        "preInventory": inventory_pre,
        "preContinuitySamples": pre_samples,
    }))
    install_claim.chmod(0o600)
    install_receipt = namespace / "install-terminal-receipt.json"
    install_receipt.write_bytes(canonical_json({
        "schema": "mknoon.plan398.final-runner-install-terminal-receipt.v1",
        "status": "succeeded",
        "authorizationId": final_attempt_authorization,
        "recipient": "00008030-001A6D2801BB802E",
        "bundleIdentifier": "com.mknoon.app",
        "claimSha256": sha_file(install_claim),
        "buildReceiptSha256": build_receipt_sha,
        "preInventory": inventory_pre,
        "postInventory": inventory_post,
        "preContinuitySamples": pre_samples,
        "postContinuitySample": post_sample,
    }))
    install_receipt.chmod(0o600)
    case.build_receipt = build_receipt
    case.build_receipt_sha = build_receipt_sha
    case.install_receipt = install_receipt
    case.install_receipt_sha = sha_file(install_receipt)


def fixture_final_helper(case, *, wait_for_lock=False):
    replacements = {
        fixed_attempt01_receipt_sha: case.attempt01_receipt_sha,
        "8b0da6ebd454a5696b4971507485b7f2e3f319eef0cb60fc0e25676c60acf2c3": (
            case.final_hashes["journalSha256"]
        ),
        "3c6432e0726599d4143ee4858afccc57c452a47058c95f1564ab59fb3074f0b2": (
            case.final_hashes["deviceLogSha256"]
        ),
        "d160e1e70f53b0651c91dfd45401daf26b0a0c7f001b659ca1c9eb3a3070900a": (
            case.trace_failure_sha
        ),
        **{
            fixed_attempt01_hashes[key]: case.attempt01_hashes[key]
            for key in fixed_attempt01_hashes
        },
    }
    source = helper.read_text()
    for reviewed, fixture in replacements.items():
        require(reviewed in source, "reviewed final-attempt literal is missing")
        source = source.replace(reviewed, fixture)
    if wait_for_lock:
        blocking = "fcntl.LOCK_EX | fcntl.LOCK_NB"
        require(blocking in source, "manual trace lock is no longer nonblocking")
        source = source.replace(blocking, "fcntl.LOCK_EX", 1)
        manual_class = source.index("class ManualTraceTransaction")
        manual_run = source.index("    def run(self) -> int:", manual_class)
        lock_call = source.index("        lock = self.acquire_lock()", manual_run)
        source = (
            source[:lock_call]
            + '        _event("manual_trace_prelock_validated")\n'
            + source[lock_call:]
        )
    patched = case.root / "ios_group_message_diagnostic_staging_fixture.py"
    patched.write_text(source)
    patched.chmod(0o700)
    return patched


def final_manual_command(
    case,
    helper_path,
    authorization=final_attempt_authorization,
    omit=None,
):
    value = manual_command(case)
    value[1] = str(helper_path)
    value[value.index("--sender") + 1] = case.final_pixel
    value[value.index("--recipient") + 1] = "00008030-001A6D2801BB802E"
    final_options = [
        ("--final-attempt-authorization-id", authorization),
        ("--final-attempt-journal-sha256", case.final_hashes["journalSha256"]),
        ("--final-attempt-device-log-sha256", case.final_hashes["deviceLogSha256"]),
        (
            "--final-attempt-trace-manifest-sha256",
            case.final_hashes["traceManifestSha256"],
        ),
        (
            "--final-attempt-trace-relay-state-sha256",
            case.final_hashes["traceRelayStateSha256"],
        ),
        (
            "--plan398-final-runner-product-receipt-sha256",
            case.build_receipt_sha,
        ),
        (
            "--plan398-final-runner-install-terminal-sha256",
            case.install_receipt_sha,
        ),
        (
            "--plan398-attempt-02-receipt-sha256",
            case.attempt02_receipt_sha,
        ),
    ]
    for option, argument in final_options:
        if option != omit:
            value.extend([option, argument])
    return value


def run_final_manual(
    case,
    helper_path,
    authorization=final_attempt_authorization,
    omit=None,
    **extra,
):
    return subprocess.run(
        final_manual_command(case, helper_path, authorization, omit),
        cwd=project,
        env=environment(case, **extra),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def manual_command(case, failure_sha=None, recovery=False):
    command = [
        sys.executable, str(helper), "manual-trace",
        "--project-root", str(project),
        "--prior-authority", str(case.authority),
        "--sender", "ANDROIDPHYSICAL398",
        "--recipient", "00008150-001C3C6A3684401C",
        "--artifact-dir", str(case.trace),
        "--staging-manifest", str(case.staging),
        "--relay-target", case.target,
        "--relay-key", str(case.key),
        "--relay-addresses", "/dns4/fixture.invalid/tcp/443/wss/p2p/relay",
        "--group-name", "Test",
        "--existing-target-marker", "TC398Target-trial2",
        "--retained-failure-sha256", failure_sha or case.trace_failure_sha,
        "--single-owner",
    ]
    if recovery:
        command.extend([
            "--prior-manual-preclaim-journal-sha256",
            case.prior_manual_preclaim_hashes["journalSha256"],
            "--prior-manual-preclaim-device-log-sha256",
            case.prior_manual_preclaim_hashes["deviceLogSha256"],
            "--prior-manual-preclaim-trace-manifest-sha256",
            case.prior_manual_preclaim_hashes["traceManifestSha256"],
            "--prior-manual-preclaim-trace-relay-state-sha256",
            case.prior_manual_preclaim_hashes["traceRelayStateSha256"],
        ])
    return command


def run_manual(case, failure_sha=None, recovery=False, **extra):
    return subprocess.run(
        manual_command(case, failure_sha, recovery),
        cwd=project,
        env=environment(case, **extra),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def run_live_diagnostic(case, **extra):
    command = manual_command(case)
    retained = command.index("--retained-failure-sha256")
    del command[retained:retained + 2]
    command.append("--live-diagnostic")
    return subprocess.run(
        command,
        cwd=project,
        env=environment(case, **extra),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def assert_restored(case):
    require((case.remote / "installed-relay").read_bytes() == case.prior_relay_bytes,
            "installed relay was not restored")
    require((case.remote / "running-relay").read_bytes() == case.prior_relay_bytes,
            "running MainPID executable was not restored")
    require(case.staging.read_bytes() == case.prior_manifest_bytes,
            "staging manifest was not restored by SHA CAS")


def restart_archive_paths(case, retained_digest, current_digest):
    name = (
        "current-source-restart-"
        + retained_digest[:12]
        + "-"
        + current_digest[:12]
    )
    archive = case.root / "preclaim-campaign-archives" / name
    return archive, archive.parent / f"{name}.json"


def restart_command(
    case,
    retained_digest,
    current_digest,
    authorization=restart_authorization,
):
    return [
        sys.executable,
        str(helper),
        "restart-current-source",
        "--project-root",
        str(project),
        "--authorization-id",
        authorization,
        "--retained-source-digest",
        retained_digest,
        "--current-source-digest",
        current_digest,
    ]


def restart(
    case,
    retained_digest,
    current_digest,
    authorization=restart_authorization,
    **extra,
):
    return subprocess.run(
        restart_command(
            case,
            retained_digest,
            current_digest,
            authorization,
        ),
        cwd=project,
        env=environment(case, **extra),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def seed_restart_case(name):
    case = make_case(name)
    retained_digest = sha_file(case.source)
    seeded = run(case, mode="preclaim-fail")
    require(seeded.returncode != 0, name + " unexpectedly completed its seed run")
    require(not case.claim.exists(), name + " seed run created a claim")
    assert_restored(case)
    case.source.write_text("source-v2\n")
    current_digest = sha_file(case.source)
    require(current_digest != retained_digest, name + " source fixture did not change")
    return case, retained_digest, current_digest


proof = (project / "integration_test/group_announcement_reaction_notification_proof_test.dart").read_text()
required_registration = (
    "test(iosChatGroupMessageAndReactionScenarioId" in proof
    and "_validateScenario(iosChatGroupMessageAndReactionScenarioId)" in proof
)
require(required_registration, "exact iOS chat proof is not registered")

# Receipt-free live diagnostics use a fresh output namespace but retain the
# existing relay candidate verification, deploy/run/restore transaction.
live = seed_manual_case("live-diagnostic-complete")
live.trace = live.root / "fresh-live-diagnostic"
live.events.write_text("")
live_result = run_live_diagnostic(live)
require(
    live_result.returncode == 0,
    "live diagnostic did not complete: " + live_result.stderr,
)
live_events = events(live)
candidate_copy = live_events.index("remote_mutation:manual_trace_candidate:copy")
runner_event = live_events.index("live_diagnostic_runner")
restore_copy = live_events.index("remote_mutation:manual_trace_restore:copy")
require(
    candidate_copy < runner_event < restore_copy,
    "live diagnostic did not bracket capture with deploy/restore",
)
assert_restored(live)
require(
    not any(
        token in " ".join(live_events).lower()
        for token in ("build-for-testing", " install ", "uninstall", "clear")
    ),
    "live diagnostic built, installed, uninstalled, or cleared state",
)
require(
    not (live.trace / "preclaim-attempts").exists()
    and not (live.trace / "final-runner-update").exists(),
    "live diagnostic created obsolete attempt/final-runner evidence",
)
require(
    (live.trace / "plan398_existing_state_trace.json").is_file()
    and (live.trace / "plan398_existing_state_trace_claim.json").is_file()
    and (live.trace / "plan398_existing_state_trace_terminal_receipt.json").is_file(),
    "live diagnostic omitted artifact, send claim, or terminal receipt",
)
live_artifact = json.loads(
    (live.trace / "plan398_existing_state_trace.json").read_text()
)
live_terminal = json.loads(
    (live.trace / "plan398_existing_state_trace_terminal_receipt.json").read_text()
)
require(
    live_artifact.get("authorityMode") == "live_diagnostic"
    and live_artifact.get("traceAttemptClaimed") is True
    and live_terminal.get("authorityMode") == "live_diagnostic"
    and live_terminal.get("terminalStatus") == "success"
    and live_terminal.get("traceAttemptClaimed") is True,
    "live diagnostic outputs are not bound to dedicated terminal authority",
)

for terminal_mode in (
    "missing",
    "malformed",
    "failure",
    "wrong_authority",
    "symlink",
):
    invalid = seed_manual_case("live-diagnostic-terminal-" + terminal_mode)
    invalid.trace = invalid.root / "fresh-live-diagnostic"
    invalid.events.write_text("")
    invalid_result = run_live_diagnostic(
        invalid,
        PLAN398_FAKE_LIVE_TERMINAL_MODE=terminal_mode,
    )
    require(
        invalid_result.returncode != 0,
        "live diagnostic accepted " + terminal_mode + " terminal evidence",
    )
    assert_restored(invalid)

symlinked = seed_manual_case("live-diagnostic-symlinked-root")
symlink_target = symlinked.root / "empty-live-target"
symlink_target.mkdir()
symlinked.trace = symlinked.root / "live-artifact-link"
symlinked.trace.symlink_to(symlink_target, target_is_directory=True)
symlinked.events.write_text("")
symlinked_result = run_live_diagnostic(symlinked)
require(
    symlinked_result.returncode != 0
    and not any(event.startswith("remote_mutation:") for event in events(symlinked))
    and not any(symlink_target.iterdir()),
    "live diagnostic followed a symlinked artifact root before mutation",
)

stranded = seed_manual_case("live-diagnostic-stranded-candidate")
stranded.trace = stranded.root / "fresh-live-diagnostic"
candidate_bytes = (stranded.campaign / "relay-server-linux-amd64").read_bytes()
(stranded.remote / "installed-relay").write_bytes(candidate_bytes)
(stranded.remote / "running-relay").write_bytes(candidate_bytes)
stranded.events.write_text("")
stranded_result = run_live_diagnostic(stranded)
require(
    stranded_result.returncode != 0
    and "live_diagnostic_runner" not in events(stranded),
    "live diagnostic resumed capture after recovering a stranded candidate",
)
assert_restored(stranded)

# The manual course change reuses retained relay products and the same outer
# lock, but never rebuilds mobile artifacts or swaps the staging manifest.
manual = seed_manual_case("manual-trace-complete")
manual_before = len(events(manual))
failure_bytes = manual.trace_failure.read_bytes()
staging_bytes = manual.staging.read_bytes()
result = run_manual(manual)
require(result.returncode == 0, "manual trace did not complete: " + result.stderr)
manual_events = events(manual)[manual_before:]
candidate_copy = manual_events.index("remote_mutation:manual_trace_candidate:copy")
send_event = manual_events.index("manual_send")
restore_copy = manual_events.index("remote_mutation:manual_trace_restore:copy")
require(candidate_copy < send_event < restore_copy,
        "manual trace did not bracket the send with deploy/restore")
require(not any(item.startswith(("prepare:", "ios_setup_build", "relay_build", "remote_mutation:manifest")) for item in manual_events),
        "manual trace rebuilt mobile/relay inputs or replaced a manifest")
require(manual.trace_failure.read_bytes() == failure_bytes,
        "manual trace overwrote the retained pre-claim failure")
require(manual.staging.read_bytes() == staging_bytes,
        "manual trace changed the restored staging manifest")
trace_manifest_path = manual.trace / "plan398_existing_state_trace_manifest.json"
trace_manifest = json.loads(trace_manifest_path.read_text())
require(stat.S_IMODE(trace_manifest_path.stat().st_mode) == 0o600,
        "manual trace authority is not mode 0600")
require(
    trace_manifest.get("schema")
        == "mknoon.plan398.existing-state-trace-manifest.v1"
    and trace_manifest.get("allowAppDataReset") is False
    and trace_manifest.get("provider") == "apns"
    and set(trace_manifest.get("iosCapture", {}))
        == {"bundleId", "systemLogExecutable"},
    "manual trace authority is not exact and build-free",
)
relay_state = json.loads(
    (manual.trace / "plan398_existing_state_trace_relay_state.json").read_text()
)
require(relay_state.get("status") == "restored",
        "manual trace did not retain verified relay restoration")
assert_restored(manual)

before = list(events(manual))
second = run_manual(manual)
require(second.returncode != 0 and events(manual) == before,
        "claimed manual trace performed a second deployment or send")

manual_failure = seed_manual_case("manual-trace-runner-failure")
failure_bytes = manual_failure.trace_failure.read_bytes()
result = run_manual(manual_failure, PLAN398_FAKE_MANUAL_EXIT="53")
require(result.returncode != 0 and "manual_send" not in events(manual_failure),
        "failed manual runner recorded a send")
require(manual_failure.trace_failure.read_bytes() == failure_bytes,
        "failed manual trace overwrote the retained failure")
assert_restored(manual_failure)

manual_mismatch = seed_manual_case("manual-trace-failure-mismatch")
before = list(events(manual_mismatch))
result = run_manual(manual_mismatch, failure_sha="f" * 64)
require(result.returncode != 0 and events(manual_mismatch) == before,
        "retained failure mismatch reached relay deployment")
assert_restored(manual_mismatch)

# A failed manual attempt may leave pre-claim journal/log evidence behind.
# The explicit recovery authority must archive those exact bytes before the
# candidate relay is deployed. A later runner failure rewrites trace relay
# state, so a second recovery attempt fails against attempt-01 before deploy.
manual_orphan = seed_manual_case("manual-trace-orphan-relay-state")
orphan_relay_state = (
    manual_orphan.trace / "plan398_existing_state_trace_relay_state.json"
)
orphan_relay_state.write_bytes(canonical_json({
    "schema": "mknoon.plan398.manual-trace-relay-state.v1",
    "status": "restored",
}))
orphan_relay_state.chmod(0o600)
before = list(events(manual_orphan))
orphan = run_manual(manual_orphan)
require(orphan.returncode != 0 and events(manual_orphan) == before,
        "orphan preclaim relay-state evidence reached candidate deployment")
assert_restored(manual_orphan)

manual_public_source = seed_manual_case("manual-trace-public-preclaim-source")
seed_prior_manual_preclaim_evidence(manual_public_source)
public_source = manual_public_source.prior_manual_preclaim_sources[
    "traceManifestSha256"
]
public_source.chmod(0o644)
before = list(events(manual_public_source))
public_source_result = run_manual(manual_public_source, recovery=True)
require(
    public_source_result.returncode != 0
    and events(manual_public_source) == before
    and not (manual_public_source.trace / "preclaim-attempts").exists(),
    "public prior manual preclaim source reached archive or candidate deployment",
)
require(stat.S_IMODE(public_source.stat().st_mode) == 0o644,
        "public prior manual preclaim source was mutated during rejection")
assert_restored(manual_public_source)

manual_recovery = seed_manual_case("manual-trace-preclaim-archive")
seed_prior_manual_preclaim_evidence(manual_recovery)
recovery_failure_bytes = manual_recovery.trace_failure.read_bytes()
before = list(events(manual_recovery))
missing_hashes = run_manual(manual_recovery)
require(missing_hashes.returncode != 0 and events(manual_recovery) == before,
        "preclaim evidence without explicit authority reached relay deployment")
original_preclaim_bytes = {
    key: path.read_bytes()
    for key, path in manual_recovery.prior_manual_preclaim_sources.items()
}
result = run_manual(
    manual_recovery,
    recovery=True,
    PLAN398_FAKE_MANUAL_EXIT="53",
)
require(result.returncode != 0,
        "recovery fixture unexpectedly completed its failing manual trace")
recovery_events = events(manual_recovery)[len(before):]
archive_event = recovery_events.index("manual_trace_prior_manual_preclaim_archived")
candidate_copy = recovery_events.index("remote_mutation:manual_trace_candidate:copy")
require(archive_event < candidate_copy,
        "prior manual preclaim evidence was not archived before candidate deploy")
archive = manual_recovery.trace / "preclaim-attempts" / "attempt-01"
archive_receipt = archive / "receipt.json"
require(archive.is_dir() and stat.S_IMODE(archive.stat().st_mode) == 0o700,
        "preclaim archive directory is not fixed and private")
require(stat.S_IMODE(archive_receipt.stat().st_mode) == 0o600,
        "preclaim archive receipt is not private")
receipt = json.loads(archive_receipt.read_text())
require(
    receipt == {
        "schema": "mknoon.plan398.manual-preclaim-attempt-archive.v1",
        "attempt": "attempt-01",
        **manual_recovery.prior_manual_preclaim_hashes,
    },
    "preclaim archive receipt is not canonical hash-only authority",
)
for key, source in manual_recovery.prior_manual_preclaim_sources.items():
    retained = archive / source.name
    require(
        retained.read_bytes() == original_preclaim_bytes[key]
        and stat.S_IMODE(retained.stat().st_mode) == 0o600,
        "preclaim archive did not preserve private byte-identical " + key,
    )
require(manual_recovery.trace_failure.read_bytes() == recovery_failure_bytes,
        "preclaim archive recovery altered the retained failure")
require(
    manual_recovery.prior_manual_preclaim_sources["traceRelayStateSha256"].read_bytes()
        != original_preclaim_bytes["traceRelayStateSha256"],
    "manual recovery fixture did not overwrite live relay-state evidence",
)
before_second = list(events(manual_recovery))
second = run_manual(manual_recovery, recovery=True)
require(second.returncode != 0 and events(manual_recovery) == before_second,
        "changed live preclaim source reached a second candidate deployment")
require(archive_receipt.read_bytes() == canonical_json(receipt),
        "second recovery attempt changed attempt-01 authority")
assert_restored(manual_recovery)

_superseded_manual_archive_contract = r'''
# TC-398-15: one reviewed final attempt may harden only the exact public Pixel
# log, then commit attempt-02 as a private, no-replace sibling of the sealed
# attempt-01 evidence. The old recovery hashes alone cannot grant this path.
fixed_receipt_mismatch = seed_manual_case(
    "manual-trace-final-fixed-receipt-member-mismatch"
)
seed_final_attempt_evidence(fixed_receipt_mismatch)
fixed_receipt_mismatch.attempt01_receipt.write_bytes(canonical_json({
    "schema": "mknoon.plan398.manual-preclaim-attempt-archive.v1",
    "attempt": "attempt-01",
    **fixed_attempt01_hashes,
}))
fixed_receipt_mismatch.attempt01_receipt.chmod(0o600)
require(
    sha_file(fixed_receipt_mismatch.attempt01_receipt)
        == fixed_attempt01_receipt_sha,
    "fixed attempt-01 receipt fixture is not the reviewed entity",
)
fixed_mismatch_entity = entity_digest(fixed_receipt_mismatch.attempt01)
fixed_mismatch_failure = fixed_receipt_mismatch.trace_failure.read_bytes()
fixed_mismatch_events = list(events(fixed_receipt_mismatch))
fixed_mismatch_result = run_final_manual(fixed_receipt_mismatch, helper)
require(
    fixed_mismatch_result.returncode != 0
    and events(fixed_receipt_mismatch) == fixed_mismatch_events,
    "fixed receipt with mismatched members reached candidate deployment",
)
require(
    entity_digest(fixed_receipt_mismatch.attempt01) == fixed_mismatch_entity
    and fixed_receipt_mismatch.trace_failure.read_bytes() == fixed_mismatch_failure
    and stat.S_IMODE(
        fixed_receipt_mismatch.final_sources["deviceLogSha256"].stat().st_mode
    ) == 0o644
    and not (fixed_receipt_mismatch.trace / "preclaim-attempts/attempt-02").exists(),
    "fixed receipt member rejection mutated retained or attempt-02 evidence",
)
assert_restored(fixed_receipt_mismatch)

final_missing = seed_manual_case("manual-trace-final-missing-authorization-part")
seed_final_attempt_evidence(final_missing)
final_missing_helper = fixture_final_helper(final_missing)
final_missing_events = list(events(final_missing))
missing_final = run_final_manual(
    final_missing,
    final_missing_helper,
    omit="--final-attempt-trace-relay-state-sha256",
)
require(
    missing_final.returncode != 0
    and events(final_missing) == final_missing_events
    and stat.S_IMODE(
        final_missing.final_sources["deviceLogSha256"].stat().st_mode
    ) == 0o644
    and not (final_missing.trace / "preclaim-attempts/attempt-02").exists(),
    "partial final-attempt authority mutated evidence or reached deployment",
)
assert_restored(final_missing)

final_wrong_authority = seed_manual_case("manual-trace-final-wrong-authorization")
seed_final_attempt_evidence(final_wrong_authority)
final_wrong_helper = fixture_final_helper(final_wrong_authority)
wrong_authority_events = list(events(final_wrong_authority))
wrong_authority = run_final_manual(
    final_wrong_authority,
    final_wrong_helper,
    authorization="plan398-unreviewed-final-attempt",
)
require(
    wrong_authority.returncode != 0
    and events(final_wrong_authority) == wrong_authority_events
    and stat.S_IMODE(
        final_wrong_authority.final_sources["deviceLogSha256"].stat().st_mode
    ) == 0o644
    and not (
        final_wrong_authority.trace / "preclaim-attempts/attempt-02"
    ).exists(),
    "wrong final-attempt authorization mutated evidence or reached deployment",
)
assert_restored(final_wrong_authority)

final_owner_only_wrong_mode = seed_manual_case(
    "manual-trace-final-owner-only-wrong-mode"
)
seed_final_attempt_evidence(final_owner_only_wrong_mode)
final_owner_only_helper = fixture_final_helper(final_owner_only_wrong_mode)
owner_only_journal = final_owner_only_wrong_mode.final_sources["journalSha256"]
owner_only_journal.chmod(0o400)
owner_only_events = list(events(final_owner_only_wrong_mode))
owner_only_result = run_final_manual(
    final_owner_only_wrong_mode,
    final_owner_only_helper,
)
require(
    owner_only_result.returncode != 0
    and events(final_owner_only_wrong_mode) == owner_only_events
    and stat.S_IMODE(owner_only_journal.stat().st_mode) == 0o400
    and stat.S_IMODE(
        final_owner_only_wrong_mode.final_sources[
            "deviceLogSha256"
        ].stat().st_mode
    ) == 0o644
    and not (
        final_owner_only_wrong_mode.trace / "preclaim-attempts/attempt-02"
    ).exists(),
    "owner-only non-0600 source was accepted, mutated, or deployed",
)
assert_restored(final_owner_only_wrong_mode)

final_public_other = seed_manual_case("manual-trace-final-public-other-source")
seed_final_attempt_evidence(final_public_other)
final_public_helper = fixture_final_helper(final_public_other)
final_public_other.final_sources["journalSha256"].chmod(0o644)
public_other_events = list(events(final_public_other))
public_other = run_final_manual(final_public_other, final_public_helper)
require(
    public_other.returncode != 0
    and events(final_public_other) == public_other_events
    and stat.S_IMODE(
        final_public_other.final_sources["journalSha256"].stat().st_mode
    ) == 0o644
    and stat.S_IMODE(
        final_public_other.final_sources["deviceLogSha256"].stat().st_mode
    ) == 0o644
    and not (
        final_public_other.trace / "preclaim-attempts/attempt-02"
    ).exists(),
    "public non-Pixel source was hardened or reached attempt-02/deployment",
)
assert_restored(final_public_other)

final_symlink = seed_manual_case("manual-trace-final-symlink-device-log")
seed_final_attempt_evidence(final_symlink)
final_symlink_helper = fixture_final_helper(final_symlink)
symlink_log = final_symlink.final_sources["deviceLogSha256"]
symlink_payload = symlink_log.read_bytes()
symlink_target = final_symlink.root / "outside-device-log"
symlink_target.write_bytes(symlink_payload)
symlink_target.chmod(0o644)
symlink_log.unlink()
symlink_log.symlink_to(symlink_target)
symlink_events = list(events(final_symlink))
symlink_result = run_final_manual(final_symlink, final_symlink_helper)
require(
    symlink_result.returncode != 0
    and events(final_symlink) == symlink_events
    and symlink_log.is_symlink()
    and stat.S_IMODE(symlink_target.stat().st_mode) == 0o644
    and not (final_symlink.trace / "preclaim-attempts/attempt-02").exists(),
    "symlinked Pixel source was followed, mutated, or reached deployment",
)
assert_restored(final_symlink)

final_partial = seed_manual_case("manual-trace-final-receiptless-partial")
seed_final_attempt_evidence(final_partial)
final_partial_helper = fixture_final_helper(final_partial)
partial_archive = final_partial.trace / "preclaim-attempts/attempt-02"
partial_archive.mkdir(mode=0o700)
partial_archive.chmod(0o700)
(partial_archive / "partial-member").write_bytes(b"receipt-less partial\n")
(partial_archive / "partial-member").chmod(0o600)
partial_entity = entity_digest(partial_archive)
partial_events = list(events(final_partial))
partial_result = run_final_manual(final_partial, final_partial_helper)
require(
    partial_result.returncode != 0
    and events(final_partial) == partial_events
    and entity_digest(partial_archive) == partial_entity
    and stat.S_IMODE(
        final_partial.final_sources["deviceLogSha256"].stat().st_mode
    ) == 0o644,
    "receipt-less attempt-02 partial was resumed, replaced, or reached deployment",
)
assert_restored(final_partial)

final_success = seed_manual_case("manual-trace-final-attempt-02-archive")
seed_final_attempt_evidence(final_success)
final_success_helper = fixture_final_helper(final_success)
final_failure_bytes = final_success.trace_failure.read_bytes()
attempt01_receipt_bytes = final_success.attempt01_receipt.read_bytes()
attempt01_entity_before = entity_digest(final_success.attempt01)
final_source_bytes = {
    key: path.read_bytes() for key, path in final_success.final_sources.items()
}
final_before = len(events(final_success))
final_result = run_final_manual(
    final_success,
    final_success_helper,
    PLAN398_FAKE_MANUAL_EXIT="53",
)
require(
    final_result.returncode != 0,
    "final attempt fixture unexpectedly completed its failing manual trace",
)
final_events = events(final_success)[final_before:]
final_archive_event = final_events.index("manual_trace_final_attempt_archived")
final_candidate_copy = final_events.index(
    "remote_mutation:manual_trace_candidate:copy"
)
require(
    final_archive_event < final_candidate_copy,
    "attempt-02 receipt was not committed before candidate deploy",
)
attempt02 = final_success.trace / "preclaim-attempts/attempt-02"
attempt02_receipt = attempt02 / "receipt.json"
require(
    attempt02.is_dir()
    and not attempt02.is_symlink()
    and stat.S_IMODE(attempt02.stat().st_mode) == 0o700,
    "attempt-02 archive is not a fixed private directory",
)
expected_attempt02_receipt = {
    "schema": final_attempt_schema,
    "attempt": "attempt-02",
    "authorizationId": final_attempt_authorization,
    "priorAttempt": "attempt-01",
    "priorAttemptReceiptSha256": final_success.attempt01_receipt_sha,
    "priorAttemptEntitySha256": attempt01_entity_before,
    **final_success.final_hashes,
}
require(
    attempt02_receipt.read_bytes() == canonical_json(expected_attempt02_receipt)
    and stat.S_IMODE(attempt02_receipt.stat().st_mode) == 0o600,
    "attempt-02 receipt is not the canonical receipt-last chain",
)
member_mtimes = []
for key, source in final_success.final_sources.items():
    retained = attempt02 / source.name
    require(
        retained.is_file()
        and not retained.is_symlink()
        and retained.read_bytes() == final_source_bytes[key]
        and stat.S_IMODE(retained.stat().st_mode) == 0o600,
        "attempt-02 did not privately retain byte-identical " + key,
    )
    member_mtimes.append(retained.stat().st_mtime_ns)
require(
    attempt02_receipt.stat().st_mtime_ns >= max(member_mtimes),
    "attempt-02 receipt was not published after every member",
)
require(
    final_success.final_sources["deviceLogSha256"].read_bytes()
        == final_source_bytes["deviceLogSha256"]
    and stat.S_IMODE(
        final_success.final_sources["deviceLogSha256"].stat().st_mode
    ) == 0o600,
    "exact Pixel log was not byte-preserving hardened to mode 0600",
)
require(
    final_success.attempt01_receipt.read_bytes() == attempt01_receipt_bytes
    and entity_digest(final_success.attempt01) == attempt01_entity_before
    and final_success.trace_failure.read_bytes() == final_failure_bytes,
    "final archive changed attempt-01 or the fixed failure evidence",
)
assert_restored(final_success)

attempt02_entity_before = entity_digest(attempt02)
second_final_events = list(events(final_success))
second_final = run_final_manual(final_success, final_success_helper)
require(
    second_final.returncode != 0
    and events(final_success) == second_final_events
    and entity_digest(attempt02) == attempt02_entity_before
    and entity_digest(final_success.attempt01) == attempt01_entity_before,
    "second final invocation replaced evidence or reached candidate deploy",
)
assert_restored(final_success)

'''

# TC-398-16: attempt-02 is already sealed by prepare-final-runner-update.
# The final manual trace is read-only over both attempt archives and both
# successful Runner receipts, forwards their exact hashes, deploys only after
# that revalidation, and is consumed by the attempt-03 terminal receipt.
final_binding = seed_manual_case("manual-trace-final-runner-binding")
seed_final_attempt_evidence(final_binding)
final_binding_helper = fixture_final_helper(final_binding)
attempt01_before = entity_digest(final_binding.attempt01)
attempt02_before = entity_digest(final_binding.attempt02)
build_receipt_before = final_binding.build_receipt.read_bytes()
install_receipt_before = final_binding.install_receipt.read_bytes()
final_start = len(events(final_binding))
final_result = run_final_manual(
    final_binding,
    final_binding_helper,
    PLAN398_FAKE_MANUAL_EXIT="53",
)
require(final_result.returncode != 0,
        "final receipt-bound manual fixture unexpectedly completed")
final_events = events(final_binding)[final_start:]
for required in (
    "remote_mutation:manual_trace_candidate:copy",
    "manual_trace_runner_start",
    "manual_runner_final_receipts_bound",
    "remote_mutation:manual_trace_restore:copy",
):
    require(
        required in final_events,
        "final manual trace omitted " + required + ": " + final_result.stderr,
    )
require(
    final_events.index("remote_mutation:manual_trace_candidate:copy")
        < final_events.index("manual_trace_runner_start")
        < final_events.index("manual_runner_final_receipts_bound")
        < final_events.index("remote_mutation:manual_trace_restore:copy"),
    "final manual trace did not bind receipts between candidate deploy and restore",
)
require(
    entity_digest(final_binding.attempt01) == attempt01_before
    and entity_digest(final_binding.attempt02) == attempt02_before
    and final_binding.build_receipt.read_bytes() == build_receipt_before
    and final_binding.install_receipt.read_bytes() == install_receipt_before,
    "final manual trace changed sealed attempt or Runner receipt evidence",
)
assert_restored(final_binding)
events_before_second = list(events(final_binding))
second_final = run_final_manual(final_binding, final_binding_helper)
require(
    second_final.returncode != 0
    and events(final_binding) == events_before_second
    and entity_digest(final_binding.attempt02) == attempt02_before,
    "attempt-03 terminal receipt permitted a second deploy or evidence replacement",
)
assert_restored(final_binding)

final_receipt_mismatch = seed_manual_case("manual-trace-final-receipt-mismatch")
seed_final_attempt_evidence(final_receipt_mismatch)
final_receipt_helper = fixture_final_helper(final_receipt_mismatch)
final_receipt_mismatch.install_receipt.write_bytes(b"changed receipt\n")
final_receipt_mismatch.install_receipt.chmod(0o600)
mismatch_events = list(events(final_receipt_mismatch))
mismatch_result = run_final_manual(final_receipt_mismatch, final_receipt_helper)
require(
    mismatch_result.returncode != 0
    and events(final_receipt_mismatch) == mismatch_events,
    "changed final Runner receipt reached candidate deploy",
)
assert_restored(final_receipt_mismatch)

final_build_setting_mismatch = seed_manual_case(
    "manual-trace-final-build-setting-mismatch"
)
seed_final_attempt_evidence(final_build_setting_mismatch)
malicious_settings = {
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) POISONED_CONDITION",
}
malicious_claim_path = (
    final_build_setting_mismatch.trace
    / "final-runner-update/build-claim.json"
)
malicious_claim = json.loads(
    malicious_claim_path.read_text()
)
malicious_claim["xcodeBuildSettings"] = malicious_settings
malicious_claim_path.write_bytes(canonical_json(malicious_claim))
malicious_receipt = json.loads(
    final_build_setting_mismatch.build_receipt.read_text()
)
malicious_receipt["claimSha256"] = sha_file(malicious_claim_path)
malicious_receipt["xcodeBuildSettings"] = malicious_settings
final_build_setting_mismatch.build_receipt.write_bytes(
    canonical_json(malicious_receipt)
)
final_build_setting_mismatch.build_receipt_sha = sha_file(
    final_build_setting_mismatch.build_receipt
)
final_build_setting_helper = fixture_final_helper(
    final_build_setting_mismatch
)
setting_mismatch_events = list(events(final_build_setting_mismatch))
setting_mismatch_result = run_final_manual(
    final_build_setting_mismatch,
    final_build_setting_helper,
)
require(
    setting_mismatch_result.returncode != 0
    and events(final_build_setting_mismatch) == setting_mismatch_events,
    "matching but noncanonical Runner build settings reached candidate deploy",
)
assert_restored(final_build_setting_mismatch)

source_changed_after_install = seed_manual_case(
    "manual-trace-source-changed-after-install"
)
seed_final_attempt_evidence(source_changed_after_install)
source_changed_helper = fixture_final_helper(source_changed_after_install)
source_changed_after_install.source.write_text("source-v2-after-install\n")
source_changed_events = list(events(source_changed_after_install))
source_changed_result = run_final_manual(
    source_changed_after_install,
    source_changed_helper,
    PLAN398_FAKE_MANUAL_EXIT="53",
)
require(
    source_changed_result.returncode != 0
    and events(source_changed_after_install) == source_changed_events,
    "source changed after Runner install reached candidate deploy or Popen",
)
assert_restored(source_changed_after_install)

terminal_during_lock = seed_manual_case(
    "manual-trace-terminal-during-lock-wait"
)
seed_final_attempt_evidence(terminal_during_lock)
terminal_lock_helper = fixture_final_helper(
    terminal_during_lock,
    wait_for_lock=True,
)
lock_path = terminal_during_lock.root / "diagnostic-transaction.lock"
lock_descriptor = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
lock_file = os.fdopen(lock_descriptor, "a+")
terminal_process = None
terminal_reached_lock = False
terminal_start = len(events(terminal_during_lock))
try:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    terminal_process = subprocess.Popen(
        final_manual_command(terminal_during_lock, terminal_lock_helper),
        cwd=project,
        env=environment(
            terminal_during_lock,
            PLAN398_FAKE_MANUAL_EXIT="53",
        ),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    deadline = time.time() + 10
    while time.time() < deadline and terminal_process.poll() is None:
        if "manual_trace_prelock_validated" in events(terminal_during_lock):
            terminal_reached_lock = True
            break
        time.sleep(0.02)
    if terminal_reached_lock:
        terminal = (
            terminal_during_lock.trace
            / "plan398_existing_state_trace_terminal_receipt.json"
        )
        terminal.write_bytes(canonical_json({"sentinel": "concurrent-terminal"}))
        terminal.chmod(0o600)
finally:
    lock_file.close()
require(
    terminal_process is not None and terminal_reached_lock,
    "terminal race fixture did not reach the pre-lock validation boundary",
)
try:
    terminal_stdout, terminal_stderr = terminal_process.communicate(timeout=30)
except subprocess.TimeoutExpired:
    terminal_process.kill()
    terminal_process.communicate()
    fail("terminal race fixture did not terminate after lock release")
terminal_events = events(terminal_during_lock)[terminal_start:]
require(
    terminal_process.returncode != 0
    and terminal_events == ["manual_trace_prelock_validated"],
    "terminal published while waiting for the lock reached deploy or Popen: "
    + terminal_stdout
    + terminal_stderr,
)
assert_restored(terminal_during_lock)

# Row 1 (absent/absent), the nested leased claim, claim-before-send ordering,
# complete-artifact binding, and verified restoration.
complete = make_case("complete")
result = run(complete)
require(result.returncode == 0, "fresh row did not complete: " + result.stderr)
complete_events = events(complete)
for required in ("claim_flushed", "send", "lease_revoked", "restored", "standalone_validation"):
    require(required in complete_events, "fresh row omitted " + required)
require(complete_events.index("claim_flushed") < complete_events.index("send"),
        "durable claim did not precede send")
require(complete_events.index("lease_revoked") < complete_events.index("restored") <
        complete_events.index("standalone_validation"),
        "lease/restore/standalone ordering changed")
require(stat.S_IMODE(complete.claim.stat().st_mode) == 0o600,
        "durable claim is not mode 0600")
candidate_manifest = json.loads(
    (complete.campaign / "candidate-staging-manifest.json").read_text()
)
require(candidate_manifest.get("provider") == "apns" and
        set(candidate_manifest.get("iosCapture", {})) == {
            "bundleId", "workspace", "scheme", "systemLogExecutable",
            "fixtureCreateSelector", "fixtureAuthorSelector",
            "notificationPrepareSelector", "notificationTapSelector",
        }, "sealed Plan 397 candidate template was not preserved")
assert_restored(complete)

# Row 3 (claim + exactly complete artifact): an alternate run ID is
# validation-only and reaches no preparation, remote mutation, runner, or send.
before = list(complete_events)
result = run(complete, run_id="alternate-shell")
require(result.returncode == 0, "complete claimed resume did not validate")
after = events(complete)[len(before):]
require(not any(item.startswith(("prepare:", "relay_build", "remote_mutation:", "runner_start", "send")) for item in after),
        "alternate run reached a forbidden preparation/mutation/send owner")

# Row 2 (absent claim + any artifact) fails before preparation or mutation.
orphan = make_case("orphan-artifact")
artifact = orphan.campaign / "physical-proof/diagnostic-message-window" / f"{scenario}.json"
artifact.parent.mkdir(parents=True)
artifact.write_text("{}\n")
result = run(orphan)
require(result.returncode != 0 and not events(orphan),
        "unclaimed artifact did not fail before every action")

# An unleased child cannot manufacture the Plan-398-wide claim.
unleased = make_case("unleased")
result = subprocess.run(
    [sys.executable, str(helper), "claim-send"], cwd=project,
    env=environment(unleased), text=True, stdout=subprocess.PIPE,
    stderr=subprocess.PIPE, check=False,
)
require(result.returncode != 0 and not unleased.claim.exists(),
        "unleased claim-send created a claim")

# Markerless retained products are regenerated and compared. Equal bindings
# send once; a changed mobile/relay binding fails before a second runner.
resume = make_case("markerless-resume")
first = run(resume, mode="preclaim-fail")
require(first.returncode != 0 and not resume.claim.exists(),
        "pre-marker failure unexpectedly claimed")
second = run(resume)
require(second.returncode == 0, "equal markerless resume did not complete")
resume_events = events(resume)
require(resume_events.count("prepare:android.production_fcm") == 2 and
        resume_events.count("prepare:ios.device.production") == 2 and
        resume_events.count("prepare:ios.device.group_reaction_notification_397") == 2 and
        resume_events.count("ios_setup_build") == 1 and
        resume_events.count("relay_build") == 2 and resume_events.count("send") == 1,
        "equal markerless resume did not bind one central setup build and send exactly once")
require(
    json.loads((resume.campaign / "android-preparation-report.json").read_text())
    .get("testReportGeneration") == 2
    and json.loads((resume.campaign / "ios-preparation-report.json").read_text())
    .get("testReportGeneration") == 2,
    "equal markerless resume retained stale build reports",
)
archive = resume.campaign / "preclaim-attempts/attempt-001"
archive_receipt = json.loads(
    (resume.campaign / "preclaim-attempts/attempt-001.json").read_text()
)
require(
    (archive / "plan397_androidBuildReport.json").is_file()
    and archive_receipt.get("schema") == "mknoon.plan398.preclaim-attempt-archive.v1"
    and archive_receipt.get("artifactEntitySha256") == entity_digest(archive)
    and resume_events.count("preclaim_capture_archived") == 1,
    "markerless resume did not retain and hash-bind the preclaim capture residue",
)

mismatch = make_case("markerless-mismatch")
require(run(mismatch, mode="preclaim-fail", variant="v1").returncode != 0,
        "mismatch setup unexpectedly completed")
runner_count = events(mismatch).count("runner_start")
result = run(mismatch, variant="v2")
require(result.returncode != 0 and events(mismatch).count("runner_start") == runner_count and
        not mismatch.claim.exists(),
        "changed retained build/candidate reached a second runner or claim")

# The exact suite source is recomputed by claim-send. A mutation after prepare
# creates neither claim nor send and still restores staging.
source_change = make_case("source-change")
result = run(source_change, mode="mutate-before-claim")
require(result.returncode != 0 and not source_change.claim.exists() and
        "send" not in events(source_change),
        "source mutation at the claim boundary reached send")
assert_restored(source_change)

# The inherited relay target is part of the sealed deployment receipt. A
# target substitution at the exact claim boundary creates neither claim nor
# send, even if the fake remote happens to expose the same binary identity.
target_change = make_case("target-change")
result = run(target_change, mode="mutate-target-before-claim")
require(result.returncode != 0 and not target_change.claim.exists() and
        "send" not in events(target_change),
        "relay-target mutation at the claim boundary reached send")
assert_restored(target_change)

# The centrally prepared setup product remains source/artifact bound through
# the exact claim boundary. A post-prepare mutation cannot create the claim.
setup_change = make_case("setup-change")
result = run(setup_change, mode="mutate-setup-before-claim")
require(result.returncode != 0 and not setup_change.claim.exists() and
        "send" not in events(setup_change),
        "setup-app mutation at the claim boundary reached send")
assert_restored(setup_change)

# A concurrent process loses the nonblocking outer lock before any preparation
# or mutation of its own. Terminating the owner takes the ordered cleanup path.
concurrent = make_case("concurrent")
owner = subprocess.Popen(
    command(concurrent), cwd=project,
    env=environment(concurrent, "pause-before-claim"),
    text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
)
deadline = time.time() + 15
while not concurrent.ready.exists() and owner.poll() is None and time.time() < deadline:
    time.sleep(0.05)
require(concurrent.ready.exists(), "concurrent owner never reached its held-lock fixture")
before = list(events(concurrent))
second = run(concurrent)
require(second.returncode != 0 and events(concurrent) == before,
        "concurrent second process performed work before lock rejection")
owner.send_signal(signal.SIGTERM)
owner.communicate(timeout=20)
assert_restored(concurrent)
require(not (concurrent.campaign / "active-transaction-lease.json").exists(),
        "terminated transaction retained an active lease")

# Interruption after the exclusive fsync leaves the claim, never emits send,
# restores/awaits the runner, and makes every resume non-sending.
interrupted = make_case("after-claim-interruption")
owner = subprocess.Popen(
    command(interrupted), cwd=project,
    env=environment(interrupted, "after-claim-wait"),
    text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
)
deadline = time.time() + 15
while not interrupted.ready.exists() and owner.poll() is None and time.time() < deadline:
    time.sleep(0.05)
require(interrupted.ready.exists() and interrupted.claim.exists(),
        "interruption fixture did not flush the durable claim")
owner.send_signal(signal.SIGTERM)
owner.communicate(timeout=20)
assert_restored(interrupted)
require("send" not in events(interrupted), "interrupted child sent after claim")
before = list(events(interrupted))
result = run(interrupted, run_id="different-after-interruption")
after = events(interrupted)[len(before):]
require(result.returncode != 0 and not any(item.startswith(("prepare:", "relay_build", "remote_mutation:", "runner_start", "send")) for item in after),
        "claim-present/absent-artifact row resent or mutated")

# Installed and MainPID executable identities are independent gates. A stale
# first restart blocks capture, and the restoration restart repairs both.
identity = make_case("running-identity")
result = run(identity, PLAN398_FAKE_RESTART_STALE_ONCE="1")
require(result.returncode != 0 and "runner_start" not in events(identity),
        "installed/running SHA mismatch reached the runner")
assert_restored(identity)

# A representative post-claim capture failure still restores before invoking
# the standalone validator; the valid bound artifact is evidence, not closure.
capture_failure = make_case("capture-failure")
result = run(capture_failure, mode="after-claim-fail")
failure_events = events(capture_failure)
require(result.returncode != 0 and "restored" in failure_events and
        "standalone_validation" in failure_events and
        failure_events.index("restored") < failure_events.index("standalone_validation"),
        "capture failure did not restore before standalone validation")
assert_restored(capture_failure)

# A reviewed current-source restart archives one fully restored, unclaimed
# campaign without performing preparation, deployment, capture, validation,
# claim, or send work. The sealed archive then permits one fresh campaign.
restart_complete, retained_digest, current_digest = seed_restart_case(
    "current-source-restart-complete"
)
before = list(events(restart_complete))
result = restart(restart_complete, retained_digest, current_digest)
require(
    result.returncode == 0,
    "TC-398-08 current-source restart did not complete: " + result.stderr,
)
after = events(restart_complete)[len(before):]
require(
    not any(
        item.startswith(
            (
                "prepare:",
                "ios_setup_build",
                "relay_build",
                "remote_mutation:",
                "runner_start",
                "standalone_validation",
                "claim_flushed",
                "send",
            )
        )
        for item in after
    ),
    "current-source restart executed preparation, mutation, capture, validation, claim, or send",
)
archive, archive_receipt_path = restart_archive_paths(
    restart_complete, retained_digest, current_digest
)
require(not restart_complete.campaign.exists(), "current-source restart retained the live campaign")
require(archive.is_dir() and archive_receipt_path.is_file(),
        "current-source restart did not seal its deterministic archive")
archive_receipt = json.loads(archive_receipt_path.read_text())
require(
    set(archive_receipt) == {
        "schema",
        "authorizationId",
        "ownerRunId",
        "retainedSuiteSourceDigest",
        "currentSuiteSourceDigest",
        "archiveRelativePath",
        "campaignEntitySha256",
        "restorationStatus",
        "restorationReceiptSha256",
        "priorRelaySha256",
        "priorManifestSha256",
        "diagnosticClaimAbsent",
        "authoritativeArtifactAbsent",
        "activeLeaseAbsent",
    }
    and archive_receipt["schema"] == restart_schema
    and archive_receipt["authorizationId"] == restart_authorization
    and archive_receipt["ownerRunId"] == "diagnostic"
    and archive_receipt["retainedSuiteSourceDigest"] == retained_digest
    and archive_receipt["currentSuiteSourceDigest"] == current_digest
    and archive_receipt["archiveRelativePath"]
        == archive.relative_to(restart_complete.root).as_posix()
    and archive_receipt["campaignEntitySha256"] == entity_digest(archive)
    and archive_receipt["restorationStatus"] == "restored"
    and archive_receipt["restorationReceiptSha256"]
        == sha_file(archive / "restoration-state.json")
    and archive_receipt["diagnosticClaimAbsent"] is True
    and archive_receipt["authoritativeArtifactAbsent"] is True
    and archive_receipt["activeLeaseAbsent"] is True,
    "current-source restart receipt is not exact, hash-bound, and fail-closed",
)
require(stat.S_IMODE(archive_receipt_path.stat().st_mode) == 0o600,
        "current-source restart receipt is not mode 0600")
result = run(restart_complete)
require(result.returncode == 0 and events(restart_complete).count("send") == 1,
        "sealed current-source restart did not permit one fresh current-source run")

# An interruption after the atomic move but before receipt creation recovers
# from the exact deterministic archive and remains idempotent once sealed.
restart_crash, retained_digest, current_digest = seed_restart_case(
    "current-source-restart-move-crash"
)
archive, archive_receipt_path = restart_archive_paths(
    restart_crash, retained_digest, current_digest
)
result = restart(
    restart_crash,
    retained_digest,
    current_digest,
    PLAN398_TEST_RESTART_INTERRUPT_AFTER_MOVE="1",
)
require(
    result.returncode != 0
    and not restart_crash.campaign.exists()
    and archive.is_dir()
    and not archive_receipt_path.exists(),
    "current-source restart did not retain the move-before-receipt recovery state",
)
result = restart(restart_crash, retained_digest, current_digest)
require(result.returncode == 0 and archive_receipt_path.is_file(),
        "current-source restart did not recover the move-before-receipt state")
sealed_receipt = archive_receipt_path.read_bytes()
result = restart(restart_crash, retained_digest, current_digest)
require(result.returncode == 0 and archive_receipt_path.read_bytes() == sealed_receipt,
        "sealed current-source restart is not idempotent")

# Every authorization, binding, ownership, restoration, collision, and lock
# precondition fails before the retained campaign is moved.
restart_wrong_auth, old_digest, new_digest = seed_restart_case(
    "current-source-restart-wrong-authorization"
)
result = restart(
    restart_wrong_auth,
    old_digest,
    new_digest,
    authorization="not-reviewed",
)
require(result.returncode != 0 and restart_wrong_auth.campaign.is_dir(),
        "wrong restart authorization moved the retained campaign")

restart_old_mismatch, old_digest, new_digest = seed_restart_case(
    "current-source-restart-old-mismatch"
)
result = restart(restart_old_mismatch, "0" * 64, new_digest)
require(result.returncode != 0 and restart_old_mismatch.campaign.is_dir(),
        "retained source digest mismatch moved the campaign")

restart_current_mismatch, old_digest, new_digest = seed_restart_case(
    "current-source-restart-current-mismatch"
)
result = restart(restart_current_mismatch, old_digest, "f" * 64)
require(result.returncode != 0 and restart_current_mismatch.campaign.is_dir(),
        "current source digest mismatch moved the campaign")

restart_claim, old_digest, new_digest = seed_restart_case(
    "current-source-restart-claim-present"
)
restart_claim.claim.write_text("{}\n")
restart_claim.claim.chmod(0o600)
result = restart(restart_claim, old_digest, new_digest)
require(result.returncode != 0 and restart_claim.campaign.is_dir(),
        "TC-398-08 current-source restart moved a claimed campaign")

restart_artifact, old_digest, new_digest = seed_restart_case(
    "current-source-restart-artifact-present"
)
artifact = restart_artifact.campaign / "physical-proof/diagnostic-message-window" / f"{scenario}.json"
artifact.parent.mkdir(parents=True, exist_ok=True)
artifact.write_text("{}\n")
result = restart(restart_artifact, old_digest, new_digest)
require(result.returncode != 0 and restart_artifact.campaign.is_dir(),
        "current-source restart moved a campaign with an authoritative artifact")

restart_lease, old_digest, new_digest = seed_restart_case(
    "current-source-restart-active-lease"
)
(restart_lease.campaign / "active-transaction-lease.json").write_text("{}\n")
result = restart(restart_lease, old_digest, new_digest)
require(result.returncode != 0 and restart_lease.campaign.is_dir(),
        "current-source restart moved a campaign with an active lease")

restart_unrestored, old_digest, new_digest = seed_restart_case(
    "current-source-restart-unrestored"
)
restoration_path = restart_unrestored.campaign / "restoration-state.json"
restoration = json.loads(restoration_path.read_text())
restoration["status"] = "candidate_active"
restoration_path.write_text(json.dumps(restoration, sort_keys=True) + "\n")
restoration_path.chmod(0o600)
result = restart(restart_unrestored, old_digest, new_digest)
require(result.returncode != 0 and restart_unrestored.campaign.is_dir(),
        "current-source restart moved an unrestored campaign")

restart_collision, old_digest, new_digest = seed_restart_case(
    "current-source-restart-archive-collision"
)
collision, _ = restart_archive_paths(restart_collision, old_digest, new_digest)
collision.mkdir(parents=True)
(collision / "foreign").write_text("collision\n")
result = restart(restart_collision, old_digest, new_digest)
require(result.returncode != 0 and restart_collision.campaign.is_dir(),
        "current-source restart overwrote an archive collision")

restart_locked, old_digest, new_digest = seed_restart_case(
    "current-source-restart-concurrent-lock"
)
lock_path = restart_locked.root / "diagnostic-transaction.lock"
lock_descriptor = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
lock_file = os.fdopen(lock_descriptor, "a+")
try:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    result = restart(restart_locked, old_digest, new_digest)
finally:
    lock_file.close()
require(result.returncode != 0 and restart_locked.campaign.is_dir(),
        "current-source restart moved state while another transaction owned the lock")

print("PASS: Plan 398 staging transaction is exclusive, resumable, and restore-first")
PLAN398_CONTRACT

# TC-398-15: the reviewed final Runner update is a host-only coordinator, not
# another mobile harness.  All commands below resolve to fake binaries.  The
# contract pins the one-build/one-install authority, signed-product evidence,
# same-container filesystem continuity, and terminal consumption semantics.
python3 - "integration_test/scripts/ios_group_message_diagnostic_staging.py" <<'PLAN398_FINAL_RUNNER_UPDATE_CONTRACT'
import datetime as dt
import hashlib
import json
import os
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


helper_source = Path(sys.argv[1]).resolve()
authorization = "plan398-reviewed-final-same-container-manual-trace-v1"
retry_attempt = "authorized-retry-01"
retry_authorization = "plan398-reviewed-authorized-retry-01-v1"
retry_namespace_name = "final-runner-update-authorized-retry-01"
reviewed_original_failed_claim = (
    "b2b3f0aa09d46801fa1c27b00e7a53f23b45b5de5d9f4f9fd14c08130b1e82bb"
)
reviewed_original_failed_receipt = (
    "16a9cddbce4a4d1abc36c15ab29814caa314e1cd0d2e929350ea7ec7834dc5b5"
)
reviewed_first_live_hashes = {
    "device_logcat_21071FDF600CSC.log": "0fbe7bda02513ce1a7ad961deca7af925f54e19b2d2581c82af82876288abd48",
    "plan398_existing_state_trace_claim.json": "61864d4bd82bf6c9b402c5c02aec06cc806a7ffd18cb1620f593def2c55ec28a",
    "plan398_existing_state_trace_command_journal.json": "4c54050ba116bd6293caf90c83c8f78eeb598d63de191c07bebe1e2aaadb2e94",
    "plan398_existing_state_trace_failure.json": "0db67704bbe9524ea5cfa50568e11c8ea7a3e86f229b1ba0b72f279dadd65fbf",
    "plan398_existing_state_trace_ios_stderr.bin": "359e8f7fdd3ccfcfb1e6cbd8673371df921d6e11d4438ef2e0c9179f48198bdb",
    "plan398_existing_state_trace_ios_stdout.bin": "300add8c08636ce75a71c4d0ab29b11d79197918c3585d635b8acd75ce368f31",
    "plan398_existing_state_trace_manifest.json": "65e23da2bffb949f0491fb00ac3de875d56063ef4307fc6f5f78d121ecf7f729",
    "plan398_existing_state_trace_relay_state.json": "2552ac8d08f24015753fde92f32f9037c4ebaa93bace864074c92decfebd4f49",
    "plan398_existing_state_trace_terminal_receipt.json": "c7f2069be321d1615899d50e96789fb3758b2213b78eb8b7e0dd2dd9e069375f",
}
recipient = "00008030-001A6D2801BB802E"
bundle_id = "com.mknoon.app"
build_name = "1.2.398"
build_number = "39815"
scenario = "ios_chat_group_message_and_reaction_recipient"
build_claim_schema = "mknoon.plan398.final-runner-build-claim.v1"
build_receipt_schema = "mknoon.plan398.final-runner-build-terminal-receipt.v1"
install_claim_schema = "mknoon.plan398.final-runner-install-claim.v1"
install_receipt_schema = (
    "mknoon.plan398.final-runner-install-terminal-receipt.v1"
)
receiver_bootstrap_xcode_settings = {
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": (
        "$(inherited) MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP"
    ),
}
receiver_bootstrap_flutter_environment = {
    "FLUTTER_XCODE_SWIFT_ACTIVE_COMPILATION_CONDITIONS": (
        "$(inherited) MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP"
    ),
}
forbidden_inherited_build_environment = (
    "DART_DEFINES",
    "E2E_TEST_MODE",
    "FLUTTER_TARGET",
    "SIMS_BUILD_ENTRYPOINT",
    "SIMS_BUILD_PROFILE",
    "SIMS_BUILD_PROFILE_ID",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
)
reviewed_attempt01_receipt = (
    "760ac4280f93415845b31c30b7cfbd1e4d0e10efccb4d626ebcd376605295060"
)
reviewed_attempt01_hashes = {
    "journalSha256": (
        "f62874be7b49f3593d5d5d72b5aa95ea0b646ebf0426f3dc45011c3bde0b023d"
    ),
    "deviceLogSha256": (
        "553071a186a7d4a69b1c8c54814c1aaddc68d9145b7dcf8f9d8615f39ff5e615"
    ),
    "traceManifestSha256": (
        "65e23da2bffb949f0491fb00ac3de875d56063ef4307fc6f5f78d121ecf7f729"
    ),
    "traceRelayStateSha256": (
        "b0e1d7d2ac2ebf40c827224b7ac124340f11ef4cad0f6f0d00484e2b9bd32d69"
    ),
}
reviewed_attempt02_hashes = {
    "journalSha256": (
        "8b0da6ebd454a5696b4971507485b7f2e3f319eef0cb60fc0e25676c60acf2c3"
    ),
    "deviceLogSha256": (
        "3c6432e0726599d4143ee4858afccc57c452a47058c95f1564ab59fb3074f0b2"
    ),
    "traceManifestSha256": reviewed_attempt01_hashes["traceManifestSha256"],
    "traceRelayStateSha256": reviewed_attempt01_hashes[
        "traceRelayStateSha256"
    ],
}
reviewed_failure = (
    "d160e1e70f53b0651c91dfd45401daf26b0a0c7f001b659ca1c9eb3a3070900a"
)
attempt01_payloads = {
    "journalSha256": b"fixture attempt-01 journal\n",
    "deviceLogSha256": b"fixture attempt-01 Pixel log\n",
    "traceManifestSha256": (
        b'{"schema":"mknoon.plan398.existing-state-trace-manifest.v1"}\n'
    ),
    "traceRelayStateSha256": b"fixture shared relay state\n",
}
attempt02_payloads = {
    "journalSha256": b"fixture attempt-02 journal\n",
    "deviceLogSha256": b"fixture attempt-02 Pixel log\n",
    "traceManifestSha256": attempt01_payloads["traceManifestSha256"],
    "traceRelayStateSha256": attempt01_payloads["traceRelayStateSha256"],
}
failure_payload = b"fixture fixed retained failure\n"
member_names = {
    "journalSha256": "plan398_existing_state_trace_command_journal.json",
    "deviceLogSha256": "device_logcat_21071FDF600CSC.log",
    "traceManifestSha256": "plan398_existing_state_trace_manifest.json",
    "traceRelayStateSha256": "plan398_existing_state_trace_relay_state.json",
}


def fail(message):
    print("FAIL: TC-398-15 final Runner update contract: " + message, file=sys.stderr)
    raise SystemExit(1)


def require(condition, message):
    if not condition:
        fail(message)


def canonical_json(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def sha_bytes(value):
    return hashlib.sha256(value).hexdigest()


def sha_file(path):
    return sha_bytes(path.read_bytes())


def entity_digest(path):
    digest = hashlib.sha256()
    for entry in sorted(path.rglob("*"), key=lambda item: item.relative_to(path).as_posix()):
        relative = entry.relative_to(path).as_posix().encode()
        mode = stat.S_IMODE(entry.stat().st_mode)
        digest.update(b"D\0" if entry.is_dir() else b"F\0")
        digest.update(relative)
        digest.update(b"\0")
        digest.update(f"{mode:o}".encode())
        digest.update(b"\0")
        if entry.is_file():
            digest.update(entry.read_bytes())
    return digest.hexdigest()


def application_digest(path):
    digest = hashlib.sha256()
    files = sorted(
        (entry for entry in path.rglob("*") if entry.is_file()),
        key=lambda item: item.relative_to(path).as_posix(),
    )
    for entry in files:
        digest.update(entry.relative_to(path).as_posix().encode())
        digest.update(b"\0")
        digest.update(entry.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


class Case:
    pass


temporary_root = Path(tempfile.mkdtemp(prefix="plan398-final-runner-contract-"))
fake_bin = temporary_root / "fake-bin"
fake_bin.mkdir(mode=0o700)


def write_executable(name, source):
    path = fake_bin / name
    path.write_text(source)
    path.chmod(0o700)


write_executable(
    "flutter",
    r'''#!/usr/bin/env python3
import datetime as dt
import json, os, plistlib, stat, sys
from pathlib import Path

root = Path(os.environ["FAKE_PROJECT_ROOT"])
log = Path(os.environ["FAKE_COMMAND_LOG"])
with log.open("a", encoding="utf-8") as output:
    output.write(json.dumps({
        "tool": "flutter",
        "argv": sys.argv[1:],
        "xcodeBuildEnvironment": {
            key: os.environ[key]
            for key in sorted(os.environ)
            if key.startswith("FLUTTER_XCODE_")
        },
        "forbiddenInheritedBuildEnvironment": {
            key: os.environ.get(key)
            for key in (
                "DART_DEFINES",
                "E2E_TEST_MODE",
                "FLUTTER_TARGET",
                "SIMS_BUILD_ENTRYPOINT",
                "SIMS_BUILD_PROFILE",
                "SIMS_BUILD_PROFILE_ID",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
            )
        },
        "attempt02ReceiptPresent": (
            root / "build/plan398/tc398-10-existing-state/preclaim-attempts/attempt-02/receipt.json"
        ).is_file(),
        "buildClaimPresent": (
            root / "build/plan398/tc398-10-existing-state/final-runner-update/build-claim.json"
        ).is_file(),
    }) + "\n")
if os.environ.get("FAKE_BUILD_FAIL") == "1":
    raise SystemExit(41)
app = root / "build/ios/iphoneos/Runner.app"
app.mkdir(parents=True, exist_ok=True)
if os.environ.get("FAKE_RETRY_PRODUCT_COLLISION") == "1":
    collision = (
        root
        / "build/plan398/tc398-10-existing-state"
        / "final-runner-update-authorized-retry-01/Runner.app"
    )
    collision.mkdir(mode=0o700)
    marker = collision / "foreign-marker"
    marker.write_bytes(b"foreign retained-product collision\n")
    marker.chmod(0o600)
info = {
    "CFBundleIdentifier": "com.mknoon.app",
    "CFBundleExecutable": "Runner",
    "CFBundleShortVersionString": os.environ["FAKE_BUILD_NAME"],
    "CFBundleVersion": os.environ["FAKE_BUILD_NUMBER"],
}
with (app / "Info.plist").open("wb") as output:
    plistlib.dump(info, output, fmt=plistlib.FMT_BINARY, sort_keys=True)
(app / "Runner").write_bytes(b"fixture signed Runner executable\n")
(app / "Runner").chmod(0o755)
team = "TEAM123456"
profile = {
    "TeamIdentifier": [team],
    "ExpirationDate": dt.datetime(2099, 1, 1),
    "DeveloperCertificates": [b"fixture cert two", b"fixture cert one"],
    "Entitlements": {
        "application-identifier": team + ".com.mknoon.app",
        "com.apple.developer.team-identifier": team,
        "aps-environment": "production",
    },
}
with (app / "embedded.mobileprovision").open("wb") as output:
    plistlib.dump(profile, output, fmt=plistlib.FMT_XML, sort_keys=True)
if os.environ.get("FAKE_MUTATE_SOURCE_DURING_BUILD") == "1":
    Path(os.environ["PLAN398_TEST_SOURCE_FILE"]).write_text("mutated during build\n")
''',
)

write_executable(
    "codesign",
    r'''#!/usr/bin/env python3
import json, os, plistlib, sys
from pathlib import Path

with Path(os.environ["FAKE_COMMAND_LOG"]).open("a", encoding="utf-8") as output:
    output.write(json.dumps({"tool": "codesign", "argv": sys.argv[1:]}) + "\n")
args = sys.argv[1:]
if "--verify" in args:
    raise SystemExit(45 if os.environ.get("FAKE_CODESIGN_VERIFY_FAIL") == "1" else 0)
team = os.environ.get("FAKE_CODESIGN_TEAM", "TEAM123456")
if "-dv" in args:
    sys.stderr.write("Identifier=com.mknoon.app\nTeamIdentifier=" + team + "\n")
    raise SystemExit(0)
if "--entitlements" in args:
    value = {
        "application-identifier": team + ".com.mknoon.app",
        "com.apple.developer.team-identifier": team,
        "aps-environment": os.environ.get("FAKE_CODESIGN_APS", "production"),
    }
    plistlib.dump(value, sys.stdout.buffer, fmt=plistlib.FMT_XML, sort_keys=True)
    raise SystemExit(0)
raise SystemExit(46)
''',
)

write_executable(
    "security",
    r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path

with Path(os.environ["FAKE_COMMAND_LOG"]).open("a", encoding="utf-8") as output:
    output.write(json.dumps({"tool": "security", "argv": sys.argv[1:]}) + "\n")
path = Path(sys.argv[sys.argv.index("-i") + 1])
sys.stdout.buffer.write(path.read_bytes())
''',
)

write_executable(
    "xcrun",
    r'''#!/usr/bin/env python3
import json, os, stat, sys
from pathlib import Path

args = sys.argv[1:]
record = {"tool": "xcrun", "argv": args}
root = Path(os.environ["FAKE_PROJECT_ROOT"])
if args[:4] == ["devicectl", "device", "install", "app"]:
    record["buildReceiptPresent"] = (
        root / "build/plan398/tc398-10-existing-state/final-runner-update/build-terminal-receipt.json"
    ).is_file()
    record["installClaimPresent"] = (
        root / "build/plan398/tc398-10-existing-state/final-runner-update/install-claim.json"
    ).is_file()
if "--json-output" in args:
    output_path = Path(args[args.index("--json-output") + 1])
    record["jsonOutputModeBefore"] = stat.S_IMODE(output_path.stat().st_mode)
if args[:4] == ["devicectl", "device", "copy", "from"]:
    destination = Path(args[args.index("--destination") + 1])
    record["destinationModeBefore"] = stat.S_IMODE(destination.stat().st_mode)
    record["destinationIsFileBefore"] = destination.is_file()
with Path(os.environ["FAKE_COMMAND_LOG"]).open("a", encoding="utf-8") as output:
    output.write(json.dumps(record) + "\n")

state = Path(os.environ["FAKE_INSTALL_STATE"])
installed = state.exists()
if args[:4] == ["devicectl", "device", "info", "apps"]:
    container = "file:///private/var/mobile/Containers/Data/Application/FIXED-CONTAINER"
    if installed and os.environ.get("FAKE_CONTAINER_MISMATCH") == "1":
        container += "-CHANGED"
    if os.environ.get("FAKE_PRIVATE_CONTAINER") == "1":
        container = "<private>"
    already_current = os.environ.get("FAKE_ALREADY_CURRENT") == "1"
    version = (
        os.environ["FAKE_BUILD_NAME"]
        if installed or already_current else "1.0.0"
    )
    build = (
        os.environ["FAKE_BUILD_NUMBER"]
        if installed or already_current else "1"
    )
    app_url_state = "POST" if installed else "PRE"
    if installed and os.environ.get("FAKE_APP_URL_UNCHANGED") == "1":
        app_url_state = "PRE"
    app_url = (
        "file:///private/var/containers/Bundle/Application/"
        + app_url_state
        + "/Runner.app"
    )
    if os.environ.get("FAKE_APP_URL_REDACTED") == "1":
        app_url = "<private>"
    if os.environ.get("FAKE_INVENTORY_SCHEMA") == "legacy":
        app = {
            "bundleIdentifier": "com.mknoon.app",
            "bundleShortVersion": version,
            "bundleVersion": build,
            "executableName": "Runner",
            "appDataContainer": container,
            "url": app_url,
        }
    else:
        app = {
            "bundleIdentifier": "com.mknoon.app",
            "version": version,
            "bundleVersion": build,
            "url": app_url,
        }
    output_path = Path(args[args.index("--json-output") + 1])
    output_path.write_text(json.dumps({"result": {"apps": [app]}}))
    output_path.chmod(0o600)
    raise SystemExit(0)
if args[:4] == ["devicectl", "device", "copy", "from"]:
    destination = Path(args[args.index("--destination") + 1])
    counter = Path(os.environ["FAKE_COPY_COUNTER"])
    generation = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(generation))
    value = b"fixture identity database\n"
    if os.environ.get("FAKE_IDENTITY_BYTE_CHURN") == "1":
        value = f"fixture identity database generation {generation}\n".encode()
    destination.write_bytes(value)
    destination.chmod(0o600)
    raise SystemExit(0)
if args[:4] == ["devicectl", "device", "install", "app"]:
    if os.environ.get("FAKE_INSTALL_FAIL") == "1":
        raise SystemExit(49)
    state.write_text("installed\n")
    raise SystemExit(0)
raise SystemExit(50)
''',
)

write_executable(
    "afcclient",
    r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path

args = sys.argv[1:]
request = sys.stdin.read()
record = {
    "tool": "afcclient",
    "argv": args,
    "stdin": request,
}
with Path(os.environ["FAKE_COMMAND_LOG"]).open("a", encoding="utf-8") as output:
    output.write(json.dumps(record) + "\n")
counter = Path(os.environ["FAKE_AFC_COUNTER"])
sample = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(sample))
installed = Path(os.environ["FAKE_INSTALL_STATE"]).exists()

root_type = "S_IFDIR"
root_birthtime = 1700000000
if os.environ.get("FAKE_AFC_ROOT_TYPE_INVALID") == "1" or (
    installed and os.environ.get("FAKE_AFC_ROOT_TYPE_INVALID_POST") == "1"
):
    root_type = "S_IFREG"
if not installed and sample >= 2 and os.environ.get("FAKE_AFC_ROOT_REPLACED_PRE") == "1":
    root_birthtime += 1
if installed and os.environ.get("FAKE_AFC_ROOT_REPLACED_POST") == "1":
    root_birthtime += 1

database_type = "S_IFREG"
database_birthtime = 1700000100
database_nlink = 1
database_size = 4096 + sample * 512
database_mtime = 1700000200 + sample
if os.environ.get("FAKE_IDENTITY_DB_TYPE_INVALID") == "1" or (
    installed and os.environ.get("FAKE_IDENTITY_DB_TYPE_INVALID_POST") == "1"
):
    database_type = "S_IFDIR"
if not installed and sample >= 2 and os.environ.get("FAKE_IDENTITY_DB_REPLACED_PRE") == "1":
    database_birthtime += 1
if installed and os.environ.get("FAKE_IDENTITY_DB_REPLACED_POST") == "1":
    database_birthtime += 1
if os.environ.get("FAKE_IDENTITY_DB_NLINK_INVALID") == "1" or (
    installed and os.environ.get("FAKE_IDENTITY_DB_NLINK_INVALID_POST") == "1"
):
    database_nlink = 2
if os.environ.get("FAKE_IDENTITY_DB_SIZE_ZERO") == "1" or (
    installed and os.environ.get("FAKE_IDENTITY_DB_SIZE_ZERO_POST") == "1"
):
    database_size = 0

print(json.dumps({
    "st_ifmt": root_type,
    "st_birthtime": root_birthtime,
}))
print(json.dumps({
    "st_ifmt": database_type,
    "st_birthtime": database_birthtime,
    "st_nlink": database_nlink,
    "st_size": database_size,
    "st_mtime": database_mtime,
}))
''',
)


def hashes(payloads):
    return {key: sha_bytes(value) for key, value in payloads.items()}


fixture_attempt01_hashes = hashes(attempt01_payloads)
fixture_attempt02_hashes = hashes(attempt02_payloads)
fixture_failure_hash = sha_bytes(failure_payload)


def seed_evidence(root):
    artifact = root / "build/plan398/tc398-10-existing-state"
    archive_root = artifact / "preclaim-attempts"
    archive_root.mkdir(parents=True, mode=0o700)
    archive_root.chmod(0o700)
    attempt01 = archive_root / "attempt-01"
    attempt01.mkdir(mode=0o700)
    attempt01.chmod(0o700)
    for key, payload in attempt01_payloads.items():
        path = attempt01 / member_names[key]
        path.write_bytes(payload)
        path.chmod(0o600)
    receipt01_payload = {
        "schema": "mknoon.plan398.manual-preclaim-attempt-archive.v1",
        "attempt": "attempt-01",
        **fixture_attempt01_hashes,
    }
    receipt01 = attempt01 / "receipt.json"
    receipt01.write_bytes(canonical_json(receipt01_payload))
    receipt01.chmod(0o600)
    attempt01_entity = entity_digest(attempt01)

    for key, payload in attempt02_payloads.items():
        path = artifact / member_names[key]
        path.write_bytes(payload)
        path.chmod(0o644 if key == "deviceLogSha256" else 0o600)
    failure = artifact / "plan398_existing_state_trace_failure.json"
    failure.write_bytes(failure_payload)
    failure.chmod(0o600)
    artifact.chmod(0o700)
    return artifact, {
        "attempt01": {
            "entitySha256": attempt01_entity,
            "receiptSha256": sha_file(receipt01),
        },
        "retainedFailureSha256": sha_file(failure),
    }


def read_evidence(case):
    attempt01 = case.artifact / "preclaim-attempts/attempt-01"
    attempt02 = case.artifact / "preclaim-attempts/attempt-02"
    receipt01 = attempt01 / "receipt.json"
    receipt02 = attempt02 / "receipt.json"
    return {
        "attempt01": {
            "entitySha256": entity_digest(attempt01),
            "receiptSha256": sha_file(receipt01),
        },
        "attempt02": {
            "entitySha256": entity_digest(attempt02),
            "receiptSha256": sha_file(receipt02),
        },
        "retainedFailureSha256": sha_file(
            case.artifact / "plan398_existing_state_trace_failure.json"
        ),
    }


def make_case(name):
    case = Case()
    case.root = temporary_root / name
    case.root.mkdir()
    case.source = case.root / "source.fixture"
    case.source.write_text("stable fixture source\n")
    case.artifact, case.evidence = seed_evidence(case.root)
    case.namespace = case.artifact / "final-runner-update"
    case.command_log = case.root / "commands.jsonl"
    case.install_state = case.root / "installed.state"
    case.afc_counter = case.root / "afc-count"
    case.copy_counter = case.root / "copy-count"
    return case


template = make_case("template")
source = helper_source.read_text()
replacements = {
    reviewed_attempt01_receipt: template.evidence["attempt01"]["receiptSha256"],
    reviewed_failure: fixture_failure_hash,
    **{
        reviewed_attempt01_hashes[key]: fixture_attempt01_hashes[key]
        for key in reviewed_attempt01_hashes
    },
    **{
        reviewed_attempt02_hashes[key]: fixture_attempt02_hashes[key]
        for key in reviewed_attempt02_hashes
    },
}
for reviewed, fixture in replacements.items():
    require(reviewed in source, "helper is missing a reviewed fixed-evidence literal")
    source = source.replace(reviewed, fixture)
patched_helper = temporary_root / "ios_group_message_diagnostic_staging_fixture.py"
patched_helper.write_text(source)
patched_helper.chmod(0o700)


def environment(case, **overrides):
    value = os.environ.copy()
    value.update({
        "PATH": str(fake_bin) + os.pathsep + value.get("PATH", ""),
        "PLAN398_TEST_MODE": "1",
        "PLAN398_TEST_SOURCE_FILE": str(case.source),
        "FAKE_COMMAND_LOG": str(case.command_log),
        "FAKE_PROJECT_ROOT": str(case.root),
        "FAKE_BUILD_NAME": build_name,
        "FAKE_BUILD_NUMBER": build_number,
        "FAKE_INSTALL_STATE": str(case.install_state),
        "FAKE_AFC_COUNTER": str(case.afc_counter),
        "FAKE_COPY_COUNTER": str(case.copy_counter),
    })
    value.update({key: str(argument) for key, argument in overrides.items()})
    return value


def prepare_command(case, **options):
    values = {
        "authorization": authorization,
        "recipient": recipient,
        "bundle": bundle_id,
        "build_name": build_name,
        "build_number": build_number,
        "journal_sha": fixture_attempt02_hashes["journalSha256"],
        "device_log_sha": fixture_attempt02_hashes["deviceLogSha256"],
        "manifest_sha": fixture_attempt02_hashes["traceManifestSha256"],
        "relay_state_sha": fixture_attempt02_hashes["traceRelayStateSha256"],
    }
    values.update(options)
    return [
        sys.executable,
        str(patched_helper),
        "prepare-final-runner-update",
        "--project-root", str(case.root),
        "--artifact-dir", str(case.artifact),
        "--authorization-id", values["authorization"],
        "--recipient", values["recipient"],
        "--bundle-id", values["bundle"],
        "--build-name", values["build_name"],
        "--build-number", values["build_number"],
        "--final-attempt-journal-sha256",
        values["journal_sha"],
        "--final-attempt-device-log-sha256",
        values["device_log_sha"],
        "--final-attempt-trace-manifest-sha256",
        values["manifest_sha"],
        "--final-attempt-trace-relay-state-sha256",
        values["relay_state_sha"],
    ]


def install_command(case, **options):
    values = {
        "authorization": authorization,
        "recipient": recipient,
        "bundle": bundle_id,
    }
    values.update(options)
    return [
        sys.executable,
        str(patched_helper),
        "install-final-runner-update",
        "--project-root", str(case.root),
        "--artifact-dir", str(case.artifact),
        "--authorization-id", values["authorization"],
        "--recipient", values["recipient"],
        "--bundle-id", values["bundle"],
    ]


def run_command(command, case, **overrides):
    return subprocess.run(
        command,
        cwd=case.root,
        env=environment(case, **overrides),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def command_records(case):
    if not case.command_log.exists():
        return []
    return [json.loads(line) for line in case.command_log.read_text().splitlines()]


def tool_records(case, tool):
    return [record for record in command_records(case) if record["tool"] == tool]


def install_records(case):
    return [
        record for record in tool_records(case, "xcrun")
        if record["argv"][:4] == ["devicectl", "device", "install", "app"]
    ]


def assert_private(path, label):
    require(path.is_file(), label + " is missing")
    require(stat.S_IMODE(path.stat().st_mode) == 0o600, label + " is not mode 0600")
    require(path.stat().st_nlink == 1, label + " is not a distinct file")


def prepare(case, **overrides):
    result = run_command(prepare_command(case), case, **overrides)
    if (
        case.artifact
        / "preclaim-attempts/attempt-02/receipt.json"
    ).is_file():
        case.evidence = read_evidence(case)
    return result


def install(case, **overrides):
    return run_command(install_command(case), case, **overrides)


successful = make_case("successful")
result = prepare(
    successful,
    DART_DEFINES="poisoned-inherited-dart-defines",
    E2E_TEST_MODE="true",
    FLUTTER_TARGET="integration_test/sims_dispatcher.dart",
    FLUTTER_XCODE_DART_DEFINES="poisoned-xcode-dart-defines",
    FLUTTER_XCODE_OTHER_SETTING="poisoned-xcode-setting",
    FLUTTER_XCODE_SWIFT_ACTIVE_COMPILATION_CONDITIONS=(
        "$(inherited) POISONED_CONDITION"
    ),
    SIMS_BUILD_ENTRYPOINT="integration_test/sims_dispatcher.dart",
    SIMS_BUILD_PROFILE="ios.device.group_reaction_notification_397",
    SIMS_BUILD_PROFILE_ID="ios.device.group_reaction_notification_397",
    SWIFT_ACTIVE_COMPILATION_CONDITIONS="$(inherited) POISONED_CONDITION",
)
require(result.returncode == 0, "reviewed prepare failed: " + result.stderr)
build_claim = successful.namespace / "build-claim.json"
build_receipt = successful.namespace / "build-terminal-receipt.json"
assert_private(build_claim, "build claim")
assert_private(build_receipt, "build receipt")
claim = json.loads(build_claim.read_text())
receipt = json.loads(build_receipt.read_text())
expected_build_argv = [
    "flutter", "build", "ios", "--release", "--target=lib/main.dart",
    "--dart-define=PRODUCTION_APNS=true", "--build-name=" + build_name,
    "--build-number=" + build_number,
]
require(
    set(claim) == {
        "schema", "authorizationId", "recipient", "bundleIdentifier",
        "artifactDirectoryRelativePath", "namespaceRelativePath",
        "configuration", "buildName", "buildNumber", "buildArgv",
        "xcodeBuildSettings", "suiteSourceDigestBefore", "evidence",
    }
    and claim["schema"] == build_claim_schema
    and claim["authorizationId"] == authorization
    and claim["recipient"] == recipient
    and claim["bundleIdentifier"] == bundle_id
    and claim["artifactDirectoryRelativePath"] == "build/plan398/tc398-10-existing-state"
    and claim["namespaceRelativePath"] == "build/plan398/tc398-10-existing-state/final-runner-update"
    and claim["configuration"] == "Release"
    and claim["buildName"] == build_name
    and claim["buildNumber"] == build_number
    and claim["buildArgv"] == expected_build_argv
    and claim["xcodeBuildSettings"] == receiver_bootstrap_xcode_settings
    and claim["evidence"] == successful.evidence,
    "build claim omitted or weakened reviewed authority fields",
)
require(
    set(receipt) == {
        "schema", "status", "authorizationId", "recipient",
        "bundleIdentifier", "claimSha256", "configuration", "buildName",
        "buildNumber", "buildArgv", "xcodeBuildSettings",
        "suiteSourceDigestBefore",
        "suiteSourceDigestAfter", "evidence", "product",
    }
    and receipt["schema"] == build_receipt_schema
    and receipt["status"] == "succeeded"
    and receipt["claimSha256"] == sha_file(build_claim)
    and receipt["xcodeBuildSettings"] == receiver_bootstrap_xcode_settings
    and receipt["suiteSourceDigestBefore"] == receipt["suiteSourceDigestAfter"]
    and receipt["evidence"] == successful.evidence,
    "successful build receipt is not receipt-last and source/evidence bound",
)
product = receipt["product"]
expected_product_keys = {
    "relativePath", "entitySha256", "applicationSha256", "fileSha256",
    "runnerExecutableSha256", "infoPlistSha256", "bundleIdentifier",
    "executableName", "bundleShortVersion", "bundleVersion",
    "configuration", "codesignVerifyArgv", "codesignMetadataArgv",
    "codesignEntitlementsArgv", "profileDecodeArgv", "signedIdentifier",
    "signedTeamIdentifier", "canonicalSignedEntitlementsSha256",
    "embeddedMobileProvisionSha256", "profileTeamIdentifier",
    "profileApplicationIdentifier", "profileExpirationUtc",
    "developerCertificateSha256",
}
require(set(product) == expected_product_keys, "signed-product attestation field set drifted")
app = successful.root / "build/ios/iphoneos/Runner.app"
file_hashes = {
    path.relative_to(app).as_posix(): sha_file(path)
    for path in sorted(app.rglob("*")) if path.is_file()
}
require(
    product["relativePath"] == "build/ios/iphoneos/Runner.app"
    and product["entitySha256"] == entity_digest(app)
    and product["applicationSha256"] == application_digest(app)
    and product["fileSha256"] == file_hashes
    and product["runnerExecutableSha256"] == file_hashes["Runner"]
    and product["infoPlistSha256"] == file_hashes["Info.plist"]
    and product["bundleIdentifier"] == bundle_id
    and product["executableName"] == "Runner"
    and product["bundleShortVersion"] == build_name
    and product["bundleVersion"] == build_number
    and product["configuration"] == "Release"
    and product["signedIdentifier"] == bundle_id
    and product["signedTeamIdentifier"] == "TEAM123456"
    and product["profileTeamIdentifier"] == "TEAM123456"
    and product["profileApplicationIdentifier"] == "TEAM123456." + bundle_id
    and product["profileExpirationUtc"] == "2099-01-01T00:00:00Z"
    and product["developerCertificateSha256"]
        == sorted([sha_bytes(b"fixture cert two"), sha_bytes(b"fixture cert one")])
    and product["embeddedMobileProvisionSha256"]
        == file_hashes["embedded.mobileprovision"]
    and len(product["canonicalSignedEntitlementsSha256"]) == 64,
    "signed Release Runner attestation did not bind every product field",
)
require(
    len(tool_records(successful, "flutter")) == 1
    and tool_records(successful, "flutter")[0]["argv"] == expected_build_argv[1:]
    and tool_records(successful, "flutter")[0]["xcodeBuildEnvironment"]
        == receiver_bootstrap_flutter_environment
    and all(
        tool_records(successful, "flutter")[0][
            "forbiddenInheritedBuildEnvironment"
        ][key] is None
        for key in forbidden_inherited_build_environment
    )
    and not any(
        "E2E_TEST_MODE" in argument or "SIMS_BUILD_PROFILE_ID" in argument
        for argument in expected_build_argv
    )
    and tool_records(successful, "flutter")[0]["attempt02ReceiptPresent"] is True
    and tool_records(successful, "flutter")[0]["buildClaimPresent"] is True,
    "prepare did not issue exactly the reviewed Flutter build",
)
attempt02_receipt = (
    successful.artifact / "preclaim-attempts/attempt-02/receipt.json"
)
attempt02_live_log = successful.artifact / member_names["deviceLogSha256"]
require(
    attempt02_receipt.is_file()
    and stat.S_IMODE(attempt02_receipt.stat().st_mode) == 0o600
    and attempt02_receipt.stat().st_mtime_ns <= build_claim.stat().st_mtime_ns
    and attempt02_live_log.read_bytes() == attempt02_payloads["deviceLogSha256"]
    and stat.S_IMODE(attempt02_live_log.stat().st_mode) == 0o600,
    "attempt-02 was not byte-preserved, private, and sealed before build claim",
)
sealed_build_claim = build_claim.read_bytes()
sealed_build_receipt = build_receipt.read_bytes()
second = prepare(successful)
require(
    second.returncode != 0
    and len(tool_records(successful, "flutter")) == 1
    and build_claim.read_bytes() == sealed_build_claim
    and build_receipt.read_bytes() == sealed_build_receipt,
    "second prepare retried or replaced sealed build state",
)

result = install(successful, FAKE_IDENTITY_BYTE_CHURN="1")
require(result.returncode == 0, "reviewed same-container install failed: " + result.stderr)
install_claim = successful.namespace / "install-claim.json"
install_receipt = successful.namespace / "install-terminal-receipt.json"
assert_private(install_claim, "install claim")
assert_private(install_receipt, "install receipt")
install_claim_value = json.loads(install_claim.read_text())
install_receipt_value = json.loads(install_receipt.read_text())
expected_install_argv = [
    "xcrun", "devicectl", "device", "install", "app", "--device",
    recipient, str(app.resolve()),
]
expected_inventory_keys = {
    "bundleIdentifier", "bundleShortVersion", "bundleVersion",
    "executableName", "appDataContainer", "url",
}
require(
    set(install_claim_value) == {
        "schema", "authorizationId", "recipient", "bundleIdentifier",
        "buildClaimSha256", "buildReceiptSha256", "productEntitySha256",
        "productApplicationSha256", "evidence", "installArgv",
        "preInventory", "preContinuitySamples",
    }
    and install_claim_value["schema"] == install_claim_schema
    and install_claim_value["installArgv"] == expected_install_argv
    and install_claim_value["evidence"] == successful.evidence
    and set(install_claim_value["preInventory"]) == expected_inventory_keys
    and install_claim_value["preInventory"]["bundleShortVersion"] == "1.0.0"
    and install_claim_value["preInventory"]["bundleVersion"] == "1"
    and install_claim_value["preInventory"]["executableName"] == "Runner"
    and install_claim_value["preInventory"]["appDataContainer"] is None
    and install_claim_value["preInventory"]["url"].endswith(
        "/PRE/Runner.app"
    )
    and len(install_claim_value["preContinuitySamples"]) == 2,
    "install claim did not bind two pre-mutation continuity samples",
)
pre_samples = install_claim_value["preContinuitySamples"]
for sample in pre_samples:
    require(
        set(sample) == {
            "recipient", "bundleIdentifier", "inventory", "afcRoot",
            "identityDatabase",
        }
        and sample["recipient"] == recipient
        and sample["bundleIdentifier"] == bundle_id
        and sample["inventory"] == install_claim_value["preInventory"]
        and sample["afcRoot"] == {
            "path": "/", "st_ifmt": "S_IFDIR", "st_birthtime": 1700000000,
        }
        and sample["identityDatabase"]["path"] == "Documents/identity.db"
        and sample["identityDatabase"]["st_ifmt"] == "S_IFREG"
        and sample["identityDatabase"]["st_birthtime"] == 1700000100
        and sample["identityDatabase"]["diagnostics"]["st_nlink"] == 1
        and sample["identityDatabase"]["diagnostics"]["st_size"] > 0,
        "pre-claim continuity sample omitted exact AFC metadata",
    )
require(
    pre_samples[0]["identityDatabase"]["diagnostics"]["sha256"]
        != pre_samples[1]["identityDatabase"]["diagnostics"]["sha256"]
    and pre_samples[0]["identityDatabase"]["diagnostics"]["st_size"]
        != pre_samples[1]["identityDatabase"]["diagnostics"]["st_size"]
    and pre_samples[0]["identityDatabase"]["diagnostics"]["st_mtime"]
        != pre_samples[1]["identityDatabase"]["diagnostics"]["st_mtime"],
    "ordinary pre-claim SQLCipher diagnostics did not churn in the fixture",
)
require(
    set(install_receipt_value) == {
        "schema", "status", "authorizationId", "recipient",
        "bundleIdentifier", "claimSha256", "buildReceiptSha256",
        "installArgv", "preInventory", "postInventory",
        "preContinuitySamples", "postContinuitySample",
    }
    and install_receipt_value["schema"] == install_receipt_schema
    and install_receipt_value["status"] == "succeeded"
    and install_receipt_value["claimSha256"] == sha_file(install_claim)
    and set(install_receipt_value["postInventory"]) == expected_inventory_keys
    and install_receipt_value["preInventory"]["appDataContainer"]
        == install_receipt_value["postInventory"]["appDataContainer"]
    and install_receipt_value["preInventory"]["url"]
        != install_receipt_value["postInventory"]["url"]
    and install_receipt_value["postInventory"]["url"].endswith(
        "/POST/Runner.app"
    )
    and install_receipt_value["preContinuitySamples"] == pre_samples
    and install_receipt_value["postContinuitySample"]["afcRoot"]
        == pre_samples[1]["afcRoot"]
    and {
        key: install_receipt_value["postContinuitySample"]["identityDatabase"][key]
        for key in ("path", "st_ifmt", "st_birthtime")
    } == {
        key: pre_samples[1]["identityDatabase"][key]
        for key in ("path", "st_ifmt", "st_birthtime")
    }
    and install_receipt_value["postContinuitySample"]["identityDatabase"]
        ["diagnostics"]["sha256"]
        != pre_samples[1]["identityDatabase"]["diagnostics"]["sha256"]
    and install_receipt_value["postInventory"]["bundleIdentifier"] == bundle_id
    and install_receipt_value["postInventory"]["bundleShortVersion"] == build_name
    and install_receipt_value["postInventory"]["bundleVersion"] == build_number
    and install_receipt_value["postInventory"]["executableName"] == "Runner",
    "terminal install receipt gated filesystem continuity but treated mutable bytes as diagnostics",
)
require(
    len(install_records(successful)) == 1
    and ["xcrun", *install_records(successful)[0]["argv"]]
        == expected_install_argv
    and install_records(successful)[0]["buildReceiptPresent"] is True
    and install_records(successful)[0]["installClaimPresent"] is True,
    "install did not issue exactly one bound CoreDevice command",
)
for record in tool_records(successful, "xcrun"):
    if "jsonOutputModeBefore" in record:
        require(record["jsonOutputModeBefore"] == 0o600, "inventory temp was not private before use")
    if "destinationModeBefore" in record:
        require(
            record["destinationModeBefore"] == 0o600
            and record["destinationIsFileBefore"] is True,
            "copy-from target was not an explicit private file before use",
        )
afc_records = tool_records(successful, "afcclient")
require(
    len(afc_records) == 3
    and all(
        record["argv"] == ["-u", recipient, "--container", bundle_id]
        and record["stdin"]
            == "info /\ninfo Documents/identity.db\nquit\n"
        for record in afc_records
    ),
    "continuity gate did not use two fresh pre-claim and one post-install AFC sessions",
)
sealed_install_claim = install_claim.read_bytes()
sealed_install_receipt = install_receipt.read_bytes()
second = install(successful, FAKE_IDENTITY_BYTE_CHURN="1")
require(
    second.returncode != 0
    and len(install_records(successful)) == 1
    and install_claim.read_bytes() == sealed_install_claim
    and install_receipt.read_bytes() == sealed_install_receipt,
    "second install retried or replaced sealed terminal state",
)


def assert_prepare_consumed(case, **overrides):
    result = prepare(case, **overrides)
    require(result.returncode != 0, case.root.name + " unexpectedly prepared")
    claim_path = case.namespace / "build-claim.json"
    assert_private(claim_path, case.root.name + " build claim")
    terminal = case.namespace / "build-terminal-receipt.json"
    assert_private(terminal, case.root.name + " build receipt")
    claim_value = json.loads(claim_path.read_text())
    terminal_value = json.loads(terminal.read_text())
    require(
        claim_value["buildArgv"] == expected_build_argv
        and claim_value["xcodeBuildSettings"]
            == receiver_bootstrap_xcode_settings
        and terminal_value["status"] == "failed"
        and terminal_value["claimSha256"] == sha_file(claim_path)
        and terminal_value["buildArgv"] == expected_build_argv
        and terminal_value["xcodeBuildSettings"]
            == receiver_bootstrap_xcode_settings,
        case.root.name + " failure lost the exact build contract",
    )
    build_records = tool_records(case, "flutter")
    require(
        len(build_records) == 1
        and build_records[0]["xcodeBuildEnvironment"]
            == receiver_bootstrap_flutter_environment
        and all(
            build_records[0]["forbiddenInheritedBuildEnvironment"][key]
                is None
            for key in forbidden_inherited_build_environment
        ),
        case.root.name + " failure used a contaminated build environment",
    )
    count = len(tool_records(case, "flutter"))
    require(prepare(case, **overrides).returncode != 0 and len(tool_records(case, "flutter")) == count,
            case.root.name + " retried a consumed build")


build_failure = make_case("build-failure")
assert_prepare_consumed(build_failure, FAKE_BUILD_FAIL="1")
source_failure = make_case("source-failure")
assert_prepare_consumed(source_failure, FAKE_MUTATE_SOURCE_DURING_BUILD="1")
signature_failure = make_case("signature-failure")
assert_prepare_consumed(signature_failure, FAKE_CODESIGN_VERIFY_FAIL="1")

collision = make_case("build-collision")
collision.namespace.mkdir(mode=0o700)
collision.namespace.chmod(0o700)
collision_receipt = collision.namespace / "build-terminal-receipt.json"
collision_receipt.write_bytes(b"foreign build receipt\n")
collision_receipt.chmod(0o600)
result = prepare(collision)
require(
    result.returncode != 0
    and not tool_records(collision, "flutter")
    and collision_receipt.read_bytes() == b"foreign build receipt\n"
    and not (collision.namespace / "build-claim.json").exists(),
    "prepare collision was replaced or reached the build command",
)

wrong_endpoint = make_case("wrong-endpoint")
result = run_command(prepare_command(wrong_endpoint, recipient="not-reviewed"), wrong_endpoint)
require(result.returncode != 0 and not tool_records(wrong_endpoint, "flutter") and not wrong_endpoint.namespace.exists(),
        "wrong recipient reached claim or build")

wrong_attempt_hash = make_case("wrong-attempt-hash")
result = run_command(
    prepare_command(wrong_attempt_hash, journal_sha="0" * 64),
    wrong_attempt_hash,
)
require(
    result.returncode != 0
    and not tool_records(wrong_attempt_hash, "flutter")
    and not (wrong_attempt_hash.artifact / "preclaim-attempts/attempt-02").exists()
    and stat.S_IMODE(
        (wrong_attempt_hash.artifact / member_names["deviceLogSha256"]).stat().st_mode
    ) == 0o644,
    "wrong attempt-02 hash mutated evidence or reached build",
)


def prepared_case(name):
    case = make_case(name)
    result = prepare(case)
    require(result.returncode == 0, name + " fixture prepare failed: " + result.stderr)
    return case


legacy_schema = prepared_case("legacy-schema")
result = install(
    legacy_schema,
    FAKE_INVENTORY_SCHEMA="legacy",
    FAKE_INTRO_PRESENT="1",
)
require(result.returncode == 0, "legacy CoreDevice inventory stopped working: " + result.stderr)
legacy_receipt = json.loads(
    (legacy_schema.namespace / "install-terminal-receipt.json").read_text()
)
require(
    legacy_receipt["preInventory"]["appDataContainer"].endswith(
        "/FIXED-CONTAINER"
    )
    and legacy_receipt["preInventory"]["url"]
        != legacy_receipt["postInventory"]["url"],
    "legacy CoreDevice inventory was not normalized without weakening URL continuity",
)

already_current = prepared_case("already-current")
result = install(already_current, FAKE_ALREADY_CURRENT="1")
require(
    result.returncode != 0
    and "final_runner_product_already_installed" in result.stderr
    and not install_records(already_current)
    and not (already_current.namespace / "install-claim.json").exists(),
    "same-version no-op candidate reached install claim or command",
)
second_noop = install(already_current, FAKE_ALREADY_CURRENT="1")
require(
    second_noop.returncode != 0
    and not install_records(already_current)
    and not (already_current.namespace / "install-claim.json").exists(),
    "same-version no-op guard allowed a second install attempt",
)


product_mismatch = prepared_case("product-mismatch")
(product_mismatch.root / "build/ios/iphoneos/Runner.app/Runner").write_bytes(b"changed product\n")
result = install(product_mismatch)
require(result.returncode != 0 and not install_records(product_mismatch)
        and not (product_mismatch.namespace / "install-claim.json").exists(),
        "changed product reached install claim or command")

build_setting_mismatch = prepared_case("install-build-setting-mismatch")
build_setting_claim_path = build_setting_mismatch.namespace / "build-claim.json"
build_setting_receipt_path = (
    build_setting_mismatch.namespace / "build-terminal-receipt.json"
)
build_setting_claim = json.loads(build_setting_claim_path.read_text())
build_setting_claim["xcodeBuildSettings"] = {
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) POISONED_CONDITION",
}
build_setting_claim_path.write_bytes(canonical_json(build_setting_claim))
build_setting_receipt = json.loads(build_setting_receipt_path.read_text())
build_setting_receipt["claimSha256"] = sha_file(build_setting_claim_path)
build_setting_receipt["xcodeBuildSettings"] = build_setting_claim[
    "xcodeBuildSettings"
]
build_setting_receipt_path.write_bytes(canonical_json(build_setting_receipt))
result = install(build_setting_mismatch)
require(
    result.returncode != 0
    and not install_records(build_setting_mismatch)
    and not (build_setting_mismatch.namespace / "install-claim.json").exists(),
    "matching but noncanonical build settings reached install claim or command",
)

source_mismatch = prepared_case("install-source-mismatch")
source_mismatch.source.write_text("changed before install\n")
result = install(source_mismatch)
require(result.returncode != 0 and not install_records(source_mismatch)
        and not (source_mismatch.namespace / "install-claim.json").exists(),
        "changed source reached install claim or command")

evidence_mismatch = prepared_case("install-evidence-mismatch")
(evidence_mismatch.artifact / "preclaim-attempts/attempt-02" / member_names["journalSha256"]).write_bytes(b"changed evidence\n")
result = install(evidence_mismatch)
require(result.returncode != 0 and not install_records(evidence_mismatch)
        and not (evidence_mismatch.namespace / "install-claim.json").exists(),
        "changed attempt evidence reached install claim or command")

install_signature_mismatch = prepared_case("install-signature-mismatch")
result = install(install_signature_mismatch, FAKE_CODESIGN_TEAM="OTHER12345")
require(result.returncode != 0 and not install_records(install_signature_mismatch)
        and not (install_signature_mismatch.namespace / "install-claim.json").exists(),
        "changed product signature reached install claim or command")

private_container = prepared_case("private-container")
result = install(
    private_container,
    FAKE_INVENTORY_SCHEMA="legacy",
    FAKE_PRIVATE_CONTAINER="1",
)
require(result.returncode != 0 and not install_records(private_container)
        and not (private_container.namespace / "install-claim.json").exists(),
        "redacted CoreDevice container reached install claim or command")

redacted_app_url = prepared_case("redacted-app-url")
result = install(redacted_app_url, FAKE_APP_URL_REDACTED="1")
require(
    result.returncode != 0
    and "final_runner_pre-1_url_invalid" in result.stderr
    and not install_records(redacted_app_url)
    and not (redacted_app_url.namespace / "install-claim.json").exists(),
    "non-literal CoreDevice app URL reached install claim or command",
)

trace_collision = prepared_case("trace-collision")
trace_claim = trace_collision.artifact / "plan398_existing_state_trace_claim.json"
trace_claim.write_bytes(b"foreign trace claim\n")
trace_claim.chmod(0o600)
result = install(trace_collision)
require(result.returncode != 0 and not install_records(trace_collision)
        and trace_claim.read_bytes() == b"foreign trace claim\n"
        and not (trace_collision.namespace / "install-claim.json").exists(),
        "trace-state collision reached install claim or command")


def assert_preclaim_continuity_rejected(case, expected_failure, **overrides):
    result = install(case, **overrides)
    require(
        result.returncode != 0
        and expected_failure in result.stderr
        and not install_records(case)
        and not (case.namespace / "install-claim.json").exists()
        and not (case.namespace / "install-terminal-receipt.json").exists(),
        case.root.name + " reached claim/install despite unstable filesystem metadata",
    )


root_type_pre = prepared_case("root-type-invalid-pre")
assert_preclaim_continuity_rejected(
    root_type_pre,
    "final_runner_pre-1_afc_root_invalid",
    FAKE_AFC_ROOT_TYPE_INVALID="1",
)
root_replaced_pre = prepared_case("root-replaced-pre")
assert_preclaim_continuity_rejected(
    root_replaced_pre,
    "final_runner_preinstall_continuity_unstable",
    FAKE_AFC_ROOT_REPLACED_PRE="1",
)
database_type_pre = prepared_case("database-type-invalid-pre")
assert_preclaim_continuity_rejected(
    database_type_pre,
    "final_runner_pre-1_identity_db_type_invalid",
    FAKE_IDENTITY_DB_TYPE_INVALID="1",
)
database_replaced_pre = prepared_case("database-replaced-pre")
assert_preclaim_continuity_rejected(
    database_replaced_pre,
    "final_runner_preinstall_continuity_unstable",
    FAKE_IDENTITY_DB_REPLACED_PRE="1",
)
database_nlink_pre = prepared_case("database-nlink-invalid-pre")
assert_preclaim_continuity_rejected(
    database_nlink_pre,
    "final_runner_pre-1_identity_db_nlink_invalid",
    FAKE_IDENTITY_DB_NLINK_INVALID="1",
)
database_empty_pre = prepared_case("database-empty-pre")
assert_preclaim_continuity_rejected(
    database_empty_pre,
    "final_runner_pre-1_afc_identity_db_size_invalid",
    FAKE_IDENTITY_DB_SIZE_ZERO="1",
)


def assert_install_consumed(case, expected_failure, **overrides):
    result = install(case, **overrides)
    require(result.returncode != 0, case.root.name + " unexpectedly installed cleanly")
    claim_path = case.namespace / "install-claim.json"
    receipt_path = case.namespace / "install-terminal-receipt.json"
    assert_private(claim_path, case.root.name + " install claim")
    assert_private(receipt_path, case.root.name + " install receipt")
    terminal = json.loads(receipt_path.read_text())
    require(
        terminal["status"] == "failed"
        and terminal["failure"] == expected_failure
        and len(install_records(case)) == 1,
        case.root.name + " did not record the exact terminal install failure",
    )
    claim_bytes = claim_path.read_bytes()
    receipt_bytes = receipt_path.read_bytes()
    second = install(case, **overrides)
    require(
        second.returncode != 0
        and len(install_records(case)) == 1
        and claim_path.read_bytes() == claim_bytes
        and receipt_path.read_bytes() == receipt_bytes,
        case.root.name + " retried or replaced consumed install authority",
    )


install_failure = prepared_case("install-command-failure")
assert_install_consumed(install_failure, "final_runner_install_command_failed", FAKE_INSTALL_FAIL="1")
container_mismatch = prepared_case("container-mismatch")
assert_install_consumed(
    container_mismatch,
    "final_runner_data_container_changed",
    FAKE_INVENTORY_SCHEMA="legacy",
    FAKE_CONTAINER_MISMATCH="1",
)
app_url_unchanged = prepared_case("app-url-unchanged")
assert_install_consumed(
    app_url_unchanged,
    "final_runner_app_url_unchanged",
    FAKE_APP_URL_UNCHANGED="1",
)
root_replaced_post = prepared_case("root-replaced-post")
assert_install_consumed(
    root_replaced_post,
    "final_runner_afc_root_changed",
    FAKE_AFC_ROOT_REPLACED_POST="1",
)
database_replaced_post = prepared_case("database-replaced-post")
assert_install_consumed(
    database_replaced_post,
    "final_runner_identity_db_replaced",
    FAKE_IDENTITY_DB_REPLACED_POST="1",
)
database_type_post = prepared_case("database-type-invalid-post")
assert_install_consumed(
    database_type_post,
    "final_runner_post_identity_db_type_invalid",
    FAKE_IDENTITY_DB_TYPE_INVALID_POST="1",
)

# TC-398-17: one literal retry authority gets a sibling namespace and an
# attempt-scoped retained Runner.app.  The consumed original namespace and the
# attempt-01/02/failure authority must remain byte-identical throughout.
first_live_payloads = {
    "device_logcat_21071FDF600CSC.log": b"sealed first live Pixel log\n",
    "plan398_existing_state_trace_claim.json": canonical_json({
        "schema": "mknoon.plan398.existing-state-trace-claim.v1",
        "ownerRunId": "existing-state-trace",
        "singleOwnerDeclared": True,
        "claimValue": "sealed-first-live-claim",
    }),
    "plan398_existing_state_trace_command_journal.json": canonical_json({
        "schema": "mknoon.plan257.command-journal.v1",
        "scenario": scenario,
        "commands": [],
    }),
    "plan398_existing_state_trace_failure.json": canonical_json({
        "schema": "mknoon.plan257.capture-failure.v1",
        "scenario": scenario,
        "status": "environment_blocked",
        "traceAttemptClaimed": True,
    }),
    "plan398_existing_state_trace_ios_stderr.bin": b"sealed first live stderr\n",
    "plan398_existing_state_trace_ios_stdout.bin": b"sealed first live stdout\n",
    "plan398_existing_state_trace_manifest.json": attempt01_payloads[
        "traceManifestSha256"
    ],
    "plan398_existing_state_trace_relay_state.json": canonical_json({
        "schema": "mknoon.plan398.manual-trace-relay-state.v1",
        "status": "restored",
        "authorityMode": "live_diagnostic",
    }),
    "plan398_existing_state_trace_terminal_receipt.json": canonical_json({
        "schema": "mknoon.plan398.existing-state-live-diagnostic-terminal-receipt.v1",
        "terminalStatus": "typed_failure",
        "authorityMode": "live_diagnostic",
        "traceAttemptClaimed": True,
    }),
}


def seed_first_live_trace(case):
    trace = case.root / "build/plan398/direct-live-diagnostic"
    trace.mkdir(parents=True, mode=0o755)
    trace.chmod(0o755)
    for name, payload in first_live_payloads.items():
        path = trace / name
        path.write_bytes(payload)
        path.chmod(0o600)
    case.first_live_trace = trace
    return case


def immutable_retry_authority_snapshot(case):
    original = case.artifact / "final-runner-update"
    attempt01 = case.artifact / "preclaim-attempts/attempt-01"
    attempt02 = case.artifact / "preclaim-attempts/attempt-02"
    return {
        "originalMode": stat.S_IMODE(original.stat().st_mode),
        "originalEntity": entity_digest(original),
        "originalClaim": (original / "build-claim.json").read_bytes(),
        "originalReceipt": (
            original / "build-terminal-receipt.json"
        ).read_bytes(),
        "attempt01Mode": stat.S_IMODE(attempt01.stat().st_mode),
        "attempt01Entity": entity_digest(attempt01),
        "attempt02Mode": stat.S_IMODE(attempt02.stat().st_mode),
        "attempt02Entity": entity_digest(attempt02),
        "failure": (
            case.artifact / "plan398_existing_state_trace_failure.json"
        ).read_bytes(),
        "firstLiveMode": stat.S_IMODE(case.first_live_trace.stat().st_mode),
        "firstLiveEntity": entity_digest(case.first_live_trace),
    }


def seed_consumed_original(case):
    result = prepare(case, FAKE_BUILD_FAIL="1")
    require(
        result.returncode != 0
        and "final_runner_build_command_failed" in result.stderr,
        case.root.name + " did not seed the consumed original failure",
    )
    original = case.artifact / "final-runner-update"
    require(
        set(path.name for path in original.iterdir())
        == {"build-claim.json", "build-terminal-receipt.json"},
        case.root.name + " original failure namespace was not terminal",
    )
    return seed_first_live_trace(case)


retry_hash_template = seed_consumed_original(
    make_case("authorized-retry-hash-template")
)
fixture_original_failed_claim = sha_file(
    retry_hash_template.namespace / "build-claim.json"
)
fixture_original_failed_receipt = sha_file(
    retry_hash_template.namespace / "build-terminal-receipt.json"
)
fixture_first_live_hashes = {
    name: sha_file(retry_hash_template.first_live_trace / name)
    for name in first_live_payloads
}
shared_manifest_name = "plan398_existing_state_trace_manifest.json"
require(
    fixture_first_live_hashes[shared_manifest_name]
        == fixture_attempt02_hashes["traceManifestSha256"],
    "first-live and attempt manifest fixtures no longer share reviewed bytes",
)
retry_source = patched_helper.read_text()
reviewed_retry_hash_replacements = [
    (reviewed_original_failed_claim, fixture_original_failed_claim),
    (reviewed_original_failed_receipt, fixture_original_failed_receipt),
] + [
    (reviewed_first_live_hashes[name], fixture_first_live_hashes[name])
    for name in reviewed_first_live_hashes
    if name != shared_manifest_name
]
for reviewed, fixture in reviewed_retry_hash_replacements:
    require(
        reviewed in retry_source,
        "helper omitted reviewed original-failure hash " + reviewed,
    )
    retry_source = retry_source.replace(reviewed, fixture)
retry_helper = temporary_root / "ios_group_message_diagnostic_retry_fixture.py"
retry_helper.write_text(retry_source)
retry_helper.chmod(0o700)


def retry_prepare_command(case, **options):
    values = {
        "attempt": retry_attempt,
        "authorization": retry_authorization,
        "recipient": recipient,
        "bundle": bundle_id,
    }
    values.update(options)
    command = prepare_command(case)
    command[1] = str(retry_helper)
    command[command.index("--authorization-id") + 1] = values[
        "authorization"
    ]
    command[command.index("--recipient") + 1] = values["recipient"]
    command[command.index("--bundle-id") + 1] = values["bundle"]
    command.extend(["--attempt-namespace", values["attempt"]])
    return command


def retry_install_command(case, **options):
    values = {
        "attempt": retry_attempt,
        "authorization": retry_authorization,
        "recipient": recipient,
        "bundle": bundle_id,
    }
    values.update(options)
    command = install_command(case)
    command[1] = str(retry_helper)
    command[command.index("--authorization-id") + 1] = values[
        "authorization"
    ]
    command[command.index("--recipient") + 1] = values["recipient"]
    command[command.index("--bundle-id") + 1] = values["bundle"]
    command.extend(["--attempt-namespace", values["attempt"]])
    return command


def make_retry_case(name):
    case = seed_consumed_original(make_case(name))
    require(
        sha_file(case.namespace / "build-claim.json")
        == fixture_original_failed_claim
        and sha_file(case.namespace / "build-terminal-receipt.json")
        == fixture_original_failed_receipt,
        name + " did not reproduce the exact consumed original namespace",
    )
    case.retry_namespace = case.artifact / retry_namespace_name
    case.immutable_authority = immutable_retry_authority_snapshot(case)
    return case


def retry_prepare(case, **options):
    return run_command(retry_prepare_command(case, **options), case)


def retry_install(case, **options):
    return run_command(
        retry_install_command(case, **options),
        case,
        FAKE_IDENTITY_BYTE_CHURN="1",
    )


retry_success = make_retry_case("authorized-retry-success")
result = retry_prepare(retry_success)
require(
    result.returncode == 0,
    "authorized retry prepare failed: " + result.stderr,
)
retry_claim = retry_success.retry_namespace / "build-claim.json"
retry_receipt = retry_success.retry_namespace / "build-terminal-receipt.json"
retained_app = retry_success.retry_namespace / "Runner.app"
assert_private(retry_claim, "authorized retry build claim")
assert_private(retry_receipt, "authorized retry build receipt")
require(
    stat.S_IMODE(retry_success.retry_namespace.stat().st_mode) == 0o700
    and stat.S_IMODE(retained_app.stat().st_mode) == 0o700
    and not retained_app.is_symlink()
    and not any(path.is_symlink() for path in retained_app.rglob("*"))
    and {path.name for path in retry_success.retry_namespace.iterdir()}
    == {"build-claim.json", "build-terminal-receipt.json", "Runner.app"},
    "authorized retry product was not privately retained receipt-last",
)
retry_claim_value = json.loads(retry_claim.read_text())
retry_receipt_value = json.loads(retry_receipt.read_text())
retry_authority = retry_claim_value["retryAuthority"]
require(
    retry_claim_value["authorizationId"] == retry_authorization
    and retry_receipt_value["authorizationId"] == retry_authorization
    and retry_claim_value["attemptNamespace"] == retry_attempt
    and retry_receipt_value["attemptNamespace"] == retry_attempt
    and retry_claim_value["namespaceRelativePath"]
    == "build/plan398/tc398-10-existing-state/" + retry_namespace_name
    and retry_receipt_value["retryAuthority"] == retry_authority
    and retry_authority["attemptNamespace"] == retry_attempt
    and retry_authority["authorizationId"] == retry_authorization
    and retry_authority["originalFailedNamespace"]["buildClaimSha256"]
    == fixture_original_failed_claim
    and retry_authority["originalFailedNamespace"]["buildReceiptSha256"]
    == fixture_original_failed_receipt
    and retry_receipt_value["product"]["relativePath"]
    == "build/plan398/tc398-10-existing-state/"
        + retry_namespace_name + "/Runner.app"
    and retry_success.immutable_authority
    == immutable_retry_authority_snapshot(retry_success),
    "authorized retry receipt did not bind its literal namespace and immutable authority",
)
retained_bytes = (retained_app / "Runner").read_bytes()
(retry_success.root / "build/ios/iphoneos/Runner.app/Runner").write_bytes(
    b"unretained root product changed after seal\n"
)
result = retry_install(retry_success)
require(
    result.returncode == 0,
    "authorized retained-product install failed: " + result.stderr,
)
retry_install_claim = retry_success.retry_namespace / "install-claim.json"
retry_install_receipt = (
    retry_success.retry_namespace / "install-terminal-receipt.json"
)
assert_private(retry_install_claim, "authorized retry install claim")
assert_private(retry_install_receipt, "authorized retry install receipt")
retry_install_claim_value = json.loads(retry_install_claim.read_text())
retry_install_receipt_value = json.loads(retry_install_receipt.read_text())
retry_installs = install_records(retry_success)
expected_retry_install_argv = [
    "xcrun", "devicectl", "device", "install", "app", "--device",
    recipient, str(retained_app.resolve()),
]
require(
    len(retry_installs) == 1
    and ["xcrun", *retry_installs[0]["argv"]]
    == expected_retry_install_argv
    and retry_install_claim_value["installArgv"]
    == expected_retry_install_argv
    and retry_install_receipt_value["installArgv"]
    == expected_retry_install_argv
    and retry_install_claim_value["attemptNamespace"] == retry_attempt
    and retry_install_receipt_value["attemptNamespace"] == retry_attempt
    and retry_install_claim_value["retryAuthority"] == retry_authority
    and retry_install_receipt_value["retryAuthority"] == retry_authority
    and (retained_app / "Runner").read_bytes() == retained_bytes
    and retry_success.immutable_authority
    == immutable_retry_authority_snapshot(retry_success),
    "authorized retry installed anything except the sealed retained product",
)
sealed_retry = {
    path.name: path.read_bytes()
    for path in (
        retry_claim,
        retry_receipt,
        retry_install_claim,
        retry_install_receipt,
    )
}
retry_build_count = len(tool_records(retry_success, "flutter"))
require(
    retry_prepare(retry_success).returncode != 0
    and len(tool_records(retry_success, "flutter")) == retry_build_count
    and retry_install(retry_success).returncode != 0
    and len(install_records(retry_success)) == 1
    and all(
        (retry_success.retry_namespace / name).read_bytes() == payload
        for name, payload in sealed_retry.items()
    ),
    "authorized retry replay replaced a receipt or repeated build/install",
)


def assert_retry_prepare_rejected(case, result, message):
    require(
        result.returncode != 0
        and len(tool_records(case, "flutter")) == 1
        and not case.retry_namespace.exists()
        and case.immutable_authority
            == immutable_retry_authority_snapshot(case),
        message,
    )


wrong_retry_attempt = make_retry_case("authorized-retry-wrong-attempt")
assert_retry_prepare_rejected(
    wrong_retry_attempt,
    retry_prepare(wrong_retry_attempt, attempt="authorized-retry-02"),
    "generic or wrong retry attempt reached a claim/build",
)
wrong_retry_authorization = make_retry_case("authorized-retry-wrong-auth")
assert_retry_prepare_rejected(
    wrong_retry_authorization,
    retry_prepare(
        wrong_retry_authorization,
        authorization="plan398-reviewed-authorized-retry-02-v1",
    ),
    "wrong retry authorization reached a claim/build",
)
retry_collision = make_retry_case("authorized-retry-collision")
retry_collision.retry_namespace.mkdir(mode=0o700)
collision_target = retry_collision.root / "foreign-Runner.app"
collision_target.mkdir()
(retry_collision.retry_namespace / "Runner.app").symlink_to(
    collision_target, target_is_directory=True
)
collision_snapshot = immutable_retry_authority_snapshot(retry_collision)
result = retry_prepare(retry_collision)
require(
    result.returncode != 0
    and len(tool_records(retry_collision, "flutter")) == 1
    and (retry_collision.retry_namespace / "Runner.app").is_symlink()
    and collision_snapshot == immutable_retry_authority_snapshot(retry_collision),
    "retry namespace collision/symlink was replaced or reached build",
)
publication_race = make_retry_case("authorized-retry-publication-race")
result = run_command(
    retry_prepare_command(publication_race),
    publication_race,
    FAKE_RETRY_PRODUCT_COLLISION="1",
)
race_product = publication_race.retry_namespace / "Runner.app"
race_marker = race_product / "foreign-marker"
race_terminal = publication_race.retry_namespace / "build-terminal-receipt.json"
require(
    result.returncode != 0
    and len(tool_records(publication_race, "flutter")) == 2
    and race_marker.read_bytes()
        == b"foreign retained-product collision\n"
    and json.loads(race_terminal.read_text())["status"] == "failed"
    and publication_race.immutable_authority
        == immutable_retry_authority_snapshot(publication_race),
    "publication race replaced the exclusive retained-product root",
)

original_drift = make_retry_case("authorized-retry-original-drift")
(original_drift.namespace / "build-claim.json").write_bytes(
    b"changed consumed original claim\n"
)
result = retry_prepare(original_drift)
require(
    result.returncode != 0
    and len(tool_records(original_drift, "flutter")) == 1
    and not original_drift.retry_namespace.exists(),
    "changed consumed original namespace reached retry build",
)
attempt_drift = make_retry_case("authorized-retry-attempt-drift")
(
    attempt_drift.artifact
    / "preclaim-attempts/attempt-02"
    / member_names["journalSha256"]
).write_bytes(b"changed attempt-02 bytes\n")
result = retry_prepare(attempt_drift)
require(
    result.returncode != 0
    and len(tool_records(attempt_drift, "flutter")) == 1
    and not attempt_drift.retry_namespace.exists(),
    "changed attempt authority reached retry build",
)
first_live_drift = make_retry_case("authorized-retry-first-live-drift")
(
    first_live_drift.first_live_trace
    / "plan398_existing_state_trace_ios_stdout.bin"
).write_bytes(b"changed sealed first live output\n")
result = retry_prepare(first_live_drift)
require(
    result.returncode != 0
    and len(tool_records(first_live_drift, "flutter")) == 1
    and not first_live_drift.retry_namespace.exists(),
    "changed first live trace reached retry build",
)


def prepared_retry_case(name):
    case = make_retry_case(name)
    result = retry_prepare(case)
    require(
        result.returncode == 0,
        name + " retry prepare fixture failed: " + result.stderr,
    )
    return case


retry_source_drift = prepared_retry_case("authorized-retry-source-drift")
retry_source_drift.source.write_text("changed after retry build\n")
result = retry_install(retry_source_drift)
require(
    result.returncode != 0
    and not install_records(retry_source_drift)
    and not (retry_source_drift.retry_namespace / "install-claim.json").exists(),
    "source drift reached retry install claim/command",
)
retry_product_drift = prepared_retry_case("authorized-retry-product-drift")
(retry_product_drift.retry_namespace / "Runner.app/Runner").write_bytes(
    b"changed retained product\n"
)
result = retry_install(retry_product_drift)
require(
    result.returncode != 0
    and not install_records(retry_product_drift)
    and not (retry_product_drift.retry_namespace / "install-claim.json").exists(),
    "retained-product drift reached retry install claim/command",
)
retry_product_symlink = prepared_retry_case("authorized-retry-product-symlink")
symlink_product = retry_product_symlink.retry_namespace / "Runner.app"
backup_product = retry_product_symlink.root / "retained-product-backup"
shutil.move(symlink_product, backup_product)
symlink_product.symlink_to(backup_product, target_is_directory=True)
result = retry_install(retry_product_symlink)
require(
    result.returncode != 0
    and not install_records(retry_product_symlink)
    and symlink_product.is_symlink()
    and not (retry_product_symlink.retry_namespace / "install-claim.json").exists(),
    "symlinked retained product reached retry install claim/command",
)
retry_receipt_mix = prepared_retry_case("authorized-retry-receipt-mix")
mixed_receipt = retry_receipt_mix.retry_namespace / "build-terminal-receipt.json"
mixed_receipt.write_bytes(
    (retry_receipt_mix.namespace / "build-terminal-receipt.json").read_bytes()
)
result = retry_install(retry_receipt_mix)
require(
    result.returncode != 0
    and not install_records(retry_receipt_mix)
    and not (retry_receipt_mix.retry_namespace / "install-claim.json").exists(),
    "cross-namespace build receipt reached retry install claim/command",
)

# The live selector binds the installed retry pair from the fixed authority
# root while keeping all new trace output in a fresh, separate directory.
import importlib.util

module_spec = importlib.util.spec_from_file_location(
    "plan398_retry_fixture_module", retry_helper
)
require(module_spec is not None and module_spec.loader is not None,
        "could not load retry fixture module")
retry_module = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(retry_module)
live_output = (
    retry_success.root
    / "build/plan398/direct-live-diagnostic-authorized-retry-01"
)
retry_live_command_log = retry_success.root / "retry-live-command.json"
write_executable(
    "retry-live-dart",
    r'''#!/usr/bin/env python3
import hashlib, json, os, sys
from pathlib import Path
Path(os.environ["PLAN398_RETRY_LIVE_COMMAND_LOG"]).write_text(
    json.dumps(sys.argv[1:])
)
args = sys.argv[1:]
artifact_dir = Path(args[args.index("--artifact-dir") + 1])
artifact_dir.mkdir(parents=True, mode=0o700)
canonical = lambda value: (
    json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n"
).encode()
scenario = "ios_chat_group_message_and_reaction_recipient"
claim = artifact_dir / "plan398_existing_state_trace_claim.json"
claim.write_bytes(canonical({
    "schema": "mknoon.plan398.existing-state-trace-claim.v1",
    "ownerRunId": "existing-state-trace",
    "singleOwnerDeclared": True,
    "claimValue": "authorized-retry-live-claim",
}))
artifact = artifact_dir / "plan398_existing_state_trace.json"
artifact.write_bytes(canonical({
    "schema": "mknoon.plan398.ios-group-message-existing-state-live-diagnostic.v1",
    "version": 1,
    "authorityMode": "live_diagnostic",
    "status": "trace_complete",
    "closurePassed": False,
    "traceAttemptClaimed": True,
    "traceAttemptClaimSha256": hashlib.sha256(claim.read_bytes()).hexdigest(),
    "disposition": "clean_nonreproduction",
}))
terminal = artifact_dir / "plan398_existing_state_trace_terminal_receipt.json"
terminal.write_bytes(canonical({
    "schema": "mknoon.plan398.existing-state-live-diagnostic-terminal-receipt.v1",
    "version": 1,
    "scenario": scenario,
    "authorityMode": "live_diagnostic",
    "terminalStatus": "success",
    "captureExitCode": 0,
    "traceAttemptClaimed": True,
}))
manifest = artifact_dir / "plan398_existing_state_trace_manifest.json"
manifest.write_bytes(canonical({
    "schema": "mknoon.plan398.existing-state-trace-manifest.v1",
}))
relay = artifact_dir / "plan398_existing_state_trace_relay_state.json"
relay.write_bytes(canonical({
    "schema": "mknoon.plan398.manual-trace-relay-state.v1",
    "status": "restored",
}))
for path in (claim, artifact, terminal, manifest, relay):
    path.chmod(0o600)
mutation = os.environ.get("PLAN398_RETRY_MUTATE_PRODUCT")
if mutation:
    Path(mutation).write_bytes(b"mutated during authorized retry user pause\n")
raise SystemExit(int(os.environ.get("PLAN398_RETRY_LIVE_EXIT", "0")))
''',
)
manual_argv = [
    "manual-trace",
    "--project-root", str(retry_success.root),
    "--prior-authority", str(retry_success.root / "unused-authority.json"),
    "--sender", "21071FDF600CSC",
    "--recipient", recipient,
    "--artifact-dir", str(live_output),
    "--staging-manifest", str(retry_success.root / "unused-staging.json"),
    "--relay-target", "relay@example.test",
    "--relay-key", str(retry_success.root / "unused-relay-key"),
    "--relay-addresses", '["https://relay.example.test"]',
    "--group-name", "plan398_retry_group",
    "--existing-target-marker", "plan398_retry_marker",
    "--live-diagnostic",
    "--attempt-namespace", retry_attempt,
    "--plan398-final-runner-product-receipt-sha256", sha_file(retry_receipt),
    "--plan398-final-runner-install-terminal-sha256",
    sha_file(retry_install_receipt),
    "--plan398-attempt-02-receipt-sha256",
    sha_file(retry_success.artifact / "preclaim-attempts/attempt-02/receipt.json"),
    "--single-owner",
]
saved_test_mode = os.environ.get("PLAN398_TEST_MODE")
saved_source_file = os.environ.get("PLAN398_TEST_SOURCE_FILE")
saved_dart_command = os.environ.get("PLAN398_DART_COMMAND")
saved_live_command_log = os.environ.get("PLAN398_RETRY_LIVE_COMMAND_LOG")
os.environ["PLAN398_TEST_MODE"] = "1"
os.environ["PLAN398_TEST_SOURCE_FILE"] = str(retry_success.source)
os.environ["PLAN398_DART_COMMAND"] = str(fake_bin / "retry-live-dart")
os.environ["PLAN398_RETRY_LIVE_COMMAND_LOG"] = str(retry_live_command_log)
try:
    manual_args = retry_module._parser().parse_args(manual_argv)
    manual_transaction = retry_module.ManualTraceTransaction(manual_args)
    manual_transaction._validate_live_artifact_directory_path()
    manual_binding = manual_transaction._validate_selected_runner_binding()
    manual_transaction.final_runner_binding = manual_binding
    live_runner_command = manual_transaction._manual_runner_command()
    forbidden_live_flags = {
        "--plan398-final-attempt-authorization-id",
        "--plan398-final-runner-product-receipt-sha256",
        "--plan398-final-runner-install-terminal-sha256",
        "--plan398-attempt-02-receipt-sha256",
        "--attempt-namespace",
    }
    require(
        manual_binding == {
            "authorizationId": retry_authorization,
            "productReceiptSha256": sha_file(retry_receipt),
            "installTerminalSha256": sha_file(retry_install_receipt),
            "attempt02ReceiptSha256": sha_file(
                retry_success.artifact
                / "preclaim-attempts/attempt-02/receipt.json"
            ),
        }
        and "--live-diagnostic" in live_runner_command
        and live_runner_command[
            live_runner_command.index("--artifact-dir") + 1
        ] == str(live_output.resolve())
        and forbidden_live_flags.isdisjoint(live_runner_command)
        and not live_output.exists(),
        "live retry selector did not bind the sibling pair into a supported live invocation",
    )
    os.environ["PLAN398_RETRY_MUTATE_PRODUCT"] = str(
        retained_app / "Runner"
    )
    mutated_status = manual_transaction._start_manual_runner()
    manual_transaction.restored = True
    try:
        manual_transaction._finalize_manual_runner_after_restoration(
            mutated_status
        )
    except retry_module.IncompleteEvidence:
        pass
    else:
        fail("full post-pause path accepted retained-product mutation")
    outer_receipt = (
        live_output
        / "plan398_authorized_retry_01_live_terminal_receipt.json"
    )
    require(
        not outer_receipt.exists(),
        "post-pause authority mutation produced an outer success receipt",
    )
    (retained_app / "Runner").write_bytes(retained_bytes)
    shutil.rmtree(live_output)
    os.environ.pop("PLAN398_RETRY_MUTATE_PRODUCT", None)

    failed_args = retry_module._parser().parse_args(manual_argv)
    failed_transaction = retry_module.ManualTraceTransaction(failed_args)
    failed_transaction.final_runner_binding = (
        failed_transaction._validate_selected_runner_binding()
    )
    os.environ["PLAN398_RETRY_LIVE_EXIT"] = "7"
    failed_status = failed_transaction._start_manual_runner()
    failed_transaction.restored = True
    try:
        failed_transaction._finalize_manual_runner_after_restoration(
            failed_status
        )
    except retry_module.IncompleteEvidence:
        pass
    else:
        fail("failed live child produced retry success")
    require(
        not outer_receipt.exists(),
        "failed live child produced an outer success receipt",
    )
    shutil.rmtree(live_output)
    os.environ.pop("PLAN398_RETRY_LIVE_EXIT", None)

    manual_args = retry_module._parser().parse_args(manual_argv)
    manual_transaction = retry_module.ManualTraceTransaction(manual_args)
    manual_transaction.final_runner_binding = (
        manual_transaction._validate_selected_runner_binding()
    )
    clean_status = manual_transaction._start_manual_runner()
    manual_transaction.restored = True
    manual_transaction._finalize_manual_runner_after_restoration(
        clean_status
    )
    require(
        retry_live_command_log.is_file()
        and json.loads(retry_live_command_log.read_text())
            == live_runner_command[1:],
        "authorized retry live invocation did not reach the capture command",
    )
    live_claim = live_output / "plan398_existing_state_trace_claim.json"
    live_artifact = live_output / "plan398_existing_state_trace.json"
    live_inner_terminal = (
        live_output / "plan398_existing_state_trace_terminal_receipt.json"
    )
    live_manifest = (
        live_output / "plan398_existing_state_trace_manifest.json"
    )
    live_relay = (
        live_output / "plan398_existing_state_trace_relay_state.json"
    )
    outer_receipt = (
        live_output
        / "plan398_authorized_retry_01_live_terminal_receipt.json"
    )
    assert_private(outer_receipt, "authorized retry outer live receipt")
    outer_value = json.loads(outer_receipt.read_text())
    require(
        outer_value["schema"]
            == "mknoon.plan398.authorized-retry-01-live-terminal-receipt.v1"
        and outer_value["status"] == "success"
        and outer_value["attemptNamespace"] == retry_attempt
        and outer_value["authorizationId"] == retry_authorization
        and outer_value["productReceiptSha256"] == sha_file(retry_receipt)
        and outer_value["installTerminalSha256"]
            == sha_file(retry_install_receipt)
        and outer_value["attempt02ReceiptSha256"]
            == sha_file(
                retry_success.artifact
                / "preclaim-attempts/attempt-02/receipt.json"
            )
        and outer_value["traceClaimSha256"] == sha_file(live_claim)
        and outer_value["traceArtifactSha256"] == sha_file(live_artifact)
        and outer_value["traceTerminalReceiptSha256"]
            == sha_file(live_inner_terminal)
        and outer_value["traceManifestSha256"] == sha_file(live_manifest)
        and outer_value["traceRelayStateSha256"] == sha_file(live_relay)
        and outer_value["relayRestored"] is True
        and outer_value["failureArtifactAbsent"] is True,
        "outer retry receipt omitted durable live-to-install provenance",
    )
    sealed_outer_receipt = outer_receipt.read_bytes()
    try:
        manual_transaction._seal_authorized_retry_live_receipt()
    except retry_module.IncompleteEvidence:
        pass
    else:
        fail("outer retry receipt was replaceable/replayable")
    require(
        outer_receipt.read_bytes() == sealed_outer_receipt,
        "outer retry receipt collision changed sealed bytes",
    )
    (retained_app / "Runner").write_bytes(
        b"mutated during authorized retry user pause\n"
    )
    try:
        manual_transaction._revalidate_runner_binding_after_restoration()
    except retry_module.IncompleteEvidence:
        pass
    else:
        fail("post-restoration binding accepted product mutation during pause")
    require(
        outer_receipt.read_bytes() == sealed_outer_receipt,
        "post-pause mutation replaced durable outer receipt",
    )
    wrong_output_argv = list(manual_argv)
    wrong_output_argv[
        wrong_output_argv.index("--artifact-dir") + 1
    ] = str(retry_success.artifact)
    wrong_output_args = retry_module._parser().parse_args(wrong_output_argv)
    wrong_output_transaction = retry_module.ManualTraceTransaction(
        wrong_output_args
    )
    try:
        wrong_output_transaction._validate_live_artifact_directory_path()
    except retry_module.IncompleteEvidence:
        pass
    else:
        fail("live retry selector accepted the sealed authority root as output")
finally:
    if saved_test_mode is None:
        os.environ.pop("PLAN398_TEST_MODE", None)
    else:
        os.environ["PLAN398_TEST_MODE"] = saved_test_mode
    if saved_source_file is None:
        os.environ.pop("PLAN398_TEST_SOURCE_FILE", None)
    else:
        os.environ["PLAN398_TEST_SOURCE_FILE"] = saved_source_file
    if saved_dart_command is None:
        os.environ.pop("PLAN398_DART_COMMAND", None)
    else:
        os.environ["PLAN398_DART_COMMAND"] = saved_dart_command
    if saved_live_command_log is None:
        os.environ.pop("PLAN398_RETRY_LIVE_COMMAND_LOG", None)
    else:
        os.environ["PLAN398_RETRY_LIVE_COMMAND_LOG"] = saved_live_command_log

for case_root in temporary_root.iterdir():
    if not case_root.is_dir() or case_root == fake_bin:
        continue
    log = case_root / "commands.jsonl"
    if not log.exists():
        continue
    for record in command_records(type("LogCase", (), {"command_log": log})()):
        lowered = " ".join(record["argv"]).lower()
        require("launch" not in lowered, "coordinator launched the app")
        require("uninstall" not in lowered, "coordinator uninstalled the app")
        require("reset" not in lowered, "coordinator reset app/device state")
        require("copy to" not in lowered, "coordinator copied data into the app")
        require("build-for-testing" not in lowered and "xctest" not in lowered,
                "coordinator invoked XCTest/build-for-testing")
        require("flutter drive" not in lowered and "integration_test" not in lowered,
                "coordinator constructed or invoked an E2E harness")
        require(not any(token in record["argv"] for token in ("adb", "apk", "emulator")),
                "coordinator invoked an Android command")

shutil.rmtree(temporary_root)
print("PASS: TC-398-15 final Runner update is signed, one-shot, and same-container")
PLAN398_FINAL_RUNNER_UPDATE_CONTRACT
