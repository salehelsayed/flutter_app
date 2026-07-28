#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
import hashlib
import json
from pathlib import Path


def read(path: str) -> str:
    candidate = Path(path)
    assert candidate.is_file(), f"required DTR-13 contract source is missing: {path}"
    return candidate.read_text(encoding="utf-8")


def require(source: str, fragment: str, owner: str) -> None:
    assert fragment in source, f"{owner} lost exact contract fragment: {fragment}"


manifest = json.loads(read("tool/sims/critical_features.json"))
actual_profiles = manifest["buildProfiles"]
expected_profiles = [
    {
        "id": "host.process",
        "platform": "host",
        "artifactKind": "none",
        "buildRequired": False,
        "compileDefines": {},
        "declaredException": False,
    },
    {
        "id": "host.flutter_tester",
        "platform": "host",
        "artifactKind": "flutter-tester",
        "buildRequired": False,
        "compileDefines": {},
        "declaredException": False,
    },
    {
        "id": "android.e2e.standard",
        "platform": "android",
        "artifactKind": "universal-debug-apk",
        "buildRequired": True,
        "compileDefines": {"E2E_TEST_MODE": "true"},
        "declaredException": False,
    },
    {
        "id": "android.e2e.main",
        "platform": "android",
        "artifactKind": "universal-debug-apk",
        "buildRequired": True,
        "compileDefines": {"E2E_TEST_MODE": "true"},
        "declaredException": False,
    },
    {
        "id": "android.e2e.group_media_269",
        "platform": "android",
        "artifactKind": "universal-debug-apk",
        "buildRequired": True,
        "compileDefines": {
            "E2E_TEST_MODE": "true",
            "SIMS_ANDROID_DISPOSABLE_PACKAGE_ID":
                "com.mknoon.sims.groupmedia269",
        },
        "declaredException": False,
    },
    {
        "id": "android.production_fcm",
        "platform": "android",
        "artifactKind": "provider-configured-debug-apk",
        "buildRequired": True,
        "compileDefines": {
            "E2E_TEST_MODE": "true",
            "PRODUCTION_FCM": "true",
            "MKNOON_EMIT_WAKE_TOKEN": "true",
        },
        "declaredException": False,
    },
    {
        "id": "android.e2e.wake_token",
        "platform": "android",
        "artifactKind": "wake-token-debug-apk",
        "buildRequired": True,
        "compileDefines": {
            "E2E_TEST_MODE": "true",
            "MKNOON_EMIT_WAKE_TOKEN": "true",
        },
        "declaredException": False,
    },
    {
        "id": "ios.simulator.e2e",
        "platform": "ios",
        "artifactKind": "simulator-runner-app",
        "buildRequired": True,
        "compileDefines": {"E2E_TEST_MODE": "true"},
        "declaredException": False,
    },
    {
        "id": "ios.device.production",
        "platform": "ios",
        "artifactKind": "signed-physical-app-xctest-bundle",
        "buildRequired": True,
        "compileDefines": {"PRODUCTION_APNS": "true"},
        "declaredException": False,
    },
    {
        "id": "ios.device.group_media_269",
        "platform": "ios",
        "artifactKind": "signed-physical-app-xctest-bundle",
        "buildRequired": True,
        "compileDefines": {
            "E2E_TEST_MODE": "true",
            "PRODUCTION_APNS": "true",
            "SIMS_IOS_DISPOSABLE_BUNDLE_ID":
                "com.mknoon.sims.groupmedia269",
        },
        "declaredException": False,
    },
]
assert actual_profiles == expected_profiles, (
    "DTR-13 must preserve the exact ordered ten-row Sims build-profile table"
)

orchestrator = read("tool/sims/build_orchestrator.dart")
entrypoint_method = orchestrator[
    orchestrator.index("String _entrypointFor(BuildProfileSpec profile)"):
    orchestrator.index(
        "Map<String, String> _effectiveCompileDefines",
        orchestrator.index("String _entrypointFor(BuildProfileSpec profile)"),
    )
]
expected_entrypoint_method = """
String _entrypointFor(BuildProfileSpec profile) => switch (profile.id) {
  'android.e2e.standard' => 'integration_test/sims_dispatcher.dart',
  'android.e2e.main' => 'lib/main.dart',
  _androidGroupMedia269ProfileId => 'lib/main.dart',
  'ios.simulator.e2e' =>
    'integration_test/group_multi_party_device_real_harness.dart',
  _ => 'lib/main.dart',
};
"""
assert "".join(entrypoint_method.split()) == "".join(
    expected_entrypoint_method.split()
), "the exact profile-to-entrypoint switch changed"
for fragment in (
    "'android.e2e.standard' => 'integration_test/sims_dispatcher.dart'",
    "'android.e2e.main' => 'lib/main.dart'",
    "_androidGroupMedia269ProfileId => 'lib/main.dart'",
    "'ios.simulator.e2e' =>\n"
    "      'integration_test/group_multi_party_device_real_harness.dart'",
    "_ => 'lib/main.dart'",
    "environment['SIMS_BUILD_ENTRYPOINT'] ?? _entrypointFor(profile)",
    "defines['SIMS_BUILD_PROFILE_ID'] = profile.id",
    "defines.remove('SIMS_BUILD_PROFILE_ID')",
    "defines['MKNOON_RELAY_ADDRESSES'] = relayAddresses",
    "defines['MKNOON_KEY_ROTATION_GRACE_PERIOD_MS'] = '1500'",
    "--android-project-arg=disableGoogleServicesForDisposableProof=true",
    "--android-project-arg=enableGroupMedia269DisposableProof=true",
    "'FLUTTER_TARGET=${environment['SIMS_BUILD_ENTRYPOINT'] ?? "
    "_entrypointFor(profile)}'",
    "'DART_DEFINES=$encodedDefines'",
    r"$(inherited) MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP",
    r"$(inherited) MKNOON_SIMS_GROUP_MEDIA_269",
    "'CODE_SIGN_STYLE=Automatic'",
    "'PROVISIONING_PROFILE='",
    "'PROVISIONING_PROFILE_SPECIFIER='",
    "'CUSTOM_GROUP_ID=group.com.mknoon.sims.groupmedia269.share'",
    "'MKNOON_RUNNER_CODE_SIGN_ENTITLEMENTS='",
    "'Runner/GroupMedia269.empty.entitlements'",
    "'MKNOON_RUNNER_BUNDLE_IDENTIFIER=com.mknoon.sims.groupmedia269'",
    "'MKNOON_RUNNER_TESTS_BUNDLE_IDENTIFIER='",
    "'com.mknoon.sims.groupmedia269.RunnerTests'",
    "'MKNOON_RUNNER_UI_TESTS_BUNDLE_IDENTIFIER='",
    "'com.mknoon.sims.groupmedia269.RunnerUITests'",
    "'MKNOON_SHARE_EXTENSION_BUNDLE_IDENTIFIER='",
    "'com.mknoon.sims.groupmedia269.ShareExtension'",
    "'MKNOON_NOTIFICATION_SERVICE_BUNDLE_IDENTIFIER='",
    "'com.mknoon.sims.groupmedia269.NotificationService'",
):
    require(orchestrator, fragment, "tool/sims/build_orchestrator.dart")

# The three registered manual roots and the retained, uncalled runner are
# owner-pinned byte-for-byte for DTR13-AUTH-01.
expected_hashes = {
    "lib/smoke_test_main.dart":
        "522bc158c34ce53e83381ac6d7efd6139585c67de2c27df39180eef815115d27",
    "lib/smoke_test_messages.dart":
        "94e604dbe2184b13efa483ad4ce57667d99f90d063beadf8ce2cd9f87934884e",
    "lib/smoke_test_restore.dart":
        "09cefe37417ee283ab20d764ecb5d3067b4c5117c1e42d1a294defc33db7e6ab",
    "lib/core/debug/smoke_test_runner.dart":
        "852b835a5e7ecaa267005ae648475fcf0c9fbb5d0eec2a4819cb2c98b857e673",
}
for path, expected_hash in expected_hashes.items():
    actual_hash = hashlib.sha256(Path(path).read_bytes()).hexdigest()
    assert actual_hash == expected_hash, f"DTR13-AUTH-01 byte lock changed: {path}"
for path in (
    "lib/smoke_test_main.dart",
    "lib/smoke_test_messages.dart",
    "lib/smoke_test_restore.dart",
):
    require(read(path), f"flutter run -t {path}", path)
for candidate in Path("lib").rglob("*.dart"):
    if candidate.as_posix() == "lib/core/debug/smoke_test_runner.dart":
        continue
    source = candidate.read_text(encoding="utf-8")
    assert "smoke_test_runner.dart" not in source, (
        f"retained smoke_test_runner.dart was newly imported by {candidate}"
    )

runtime_roots = json.loads(read("tool/runtime_roots/runtime_roots.json"))
manual_paths = [row["path"] for row in runtime_roots["manualRoots"]]
assert manual_paths == [
    "lib/smoke_test_main.dart",
    "lib/smoke_test_messages.dart",
    "lib/smoke_test_restore.dart",
]
runner_rows = [
    row for row in runtime_roots["declarations"]
    if row["path"] == "lib/core/debug/smoke_test_runner.dart"
]
assert len(runner_rows) == 1
assert runner_rows[0]["rootKinds"] == []
assert runner_rows[0]["disposition"] == "retained-unresolved"
assert runner_rows[0]["evidence"] == []

# The separate composition root is structural only. It is not an entrypoint
# and every production/Sims command continues to target the same public root.
main = read("lib/main.dart")
composition = read("lib/debug/debug_e2e_composition_root.dart")
require(main, "debug_e2e_composition_root.dart", "lib/main.dart")
assert "main.dart" not in "\n".join(
    line for line in composition.splitlines() if line.lstrip().startswith("import ")
), "the debug/E2E composition root must not import the production entrypoint"

ios_tap = read("scripts/run_ios_notification_tap_ui_smoke.sh")
require(ios_tap, "--target lib/main.dart", "iOS notification tap smoke")
require(ios_tap, "FLUTTER_TARGET=lib/main.dart", "iOS notification tap smoke")
require(
    ios_tap,
    "flutter build ios --simulator --debug",
    "iOS notification tap smoke",
)

push_capture = read(
    "integration_test/scripts/capture_android_push_relay_registration.dart"
)
require(push_capture, "'lib/main.dart'", "Android push relay capture")
require(
    push_capture,
    "'--dart-define=MKNOON_PUSH_RELAY_REGISTRATION_PROOF=true'",
    "Android push relay capture",
)
require(push_capture, "'entrypoint': 'lib/main.dart'", "Android push metadata")
require(
    push_capture,
    "'compileGate': 'MKNOON_PUSH_RELAY_REGISTRATION_PROOF'",
    "Android push metadata",
)

one_to_one = read(
    "integration_test/scripts/capture_1to1_reaction_head_provenance.dart"
)
for fragment in (
    "'--dart-define=E2E_TEST_MODE=true'",
    "'--dart-define=E2E_TEST_MODE=false'",
    "'--dart-define=MKNOON_EMIT_WAKE_TOKEN=true'",
    "'--dart-define=MKNOON_DIRECT_TEXT_RELAY_TOKEN_PROOF=true'",
):
    require(one_to_one, fragment, "1:1 reaction capture")
clean_build = one_to_one[
    one_to_one.index("Future<_BuildArtifacts> _buildCleanHeadApks()"):
    one_to_one.index("Future<_BuildArtifacts> _buildWorkingTreeApks()")
]
working_build = one_to_one[
    one_to_one.index("Future<_BuildArtifacts> _buildWorkingTreeApks()"):
    one_to_one.index("Future<_BuildArtifacts> _reuseWorkingTreeApks()")
]
for build in (clean_build, working_build):
    assert "'--target'," not in build and "'-t'," not in build, (
        "1:1 reaction APK variants must retain default lib/main.dart targeting"
    )

group_reaction = read(
    "integration_test/scripts/capture_group_reaction_notification_device.dart"
)
for fragment in (
    "'build',\n      'ios'",
    "'build',\n      'apk'",
    "'--dart-define=E2E_TEST_MODE=$e2eMode'",
    "'--dart-define=E2E_TEST_MODE=true'",
    "'--dart-define=E2E_TEST_MODE=false'",
):
    require(group_reaction, fragment, "group reaction capture")
ios_build = group_reaction[
    group_reaction.index("Future<Directory> _buildIosCandidate("):
    group_reaction.index("Future<void> _installIosCandidate(")
]
android_build = group_reaction[
    group_reaction.index("Future<_AndroidBuilds> _buildAndroidCandidate()"):
    group_reaction.index("Future<_AndroidBuilds> _loadPreparedAndroidCandidate(")
]
for build in (ios_build, android_build):
    assert "'--target'," not in build and "'-t'," not in build, (
        "group reaction app variants must retain default lib/main.dart targeting"
    )

proof_support = read(
    "integration_test/scripts/reaction_notification_proof_support.dart"
)
assert proof_support.count("production['entrypoint'] != 'lib/main.dart'") == 2
assert proof_support.count(
    "production['compileGate'] != "
    "'MKNOON_PUSH_RELAY_REGISTRATION_PROOF'"
) == 2

reset = read("reset_simulators.sh")
for fragment in (
    "flutter build ios --simulator --no-pub",
    "--dart-define=E2E_TEST_MODE=true",
    "--dart-define=DISABLE_LOCAL_DISCOVERY=true",
):
    require(reset, fragment, "reset_simulators.sh")
assert "--target" not in reset and " -t " not in reset, (
    "reset_simulators.sh must retain its default lib/main.dart target"
)
friends = read("smoke_test_friends.sh")
require(friends, "./reset_simulators.sh", "smoke_test_friends.sh")
require(
    friends,
    "INTRO_E2E_DEVICE_SET=four ./reset_simulators.sh",
    "smoke_test_friends.sh",
)

for path in (
    "docker-ws/run_fresh_all_phones.sh",
    "docker-ws/run_fresh_three_phones.sh",
    "docker-ws/deploy_all_phones.sh",
):
    source = read(path)
    require(source, "--target=lib/main.dart", path)
    require(source, "--dart-define=PRODUCTION_APNS=true", path)
    assert "E2E_TEST_MODE" not in source
pixel = read("docker-ws/build_pixel_production.sh")
require(pixel, "--target=lib/main.dart", "docker-ws/build_pixel_production.sh")
assert "--dart-define=E2E_TEST_MODE" not in pixel

app_store = read("scripts/build_ios_appstore_ipa.sh")
require(
    app_store,
    'flutter build ipa --release --export-options-plist="$EXPORT_PLIST" "$@"',
    "scripts/build_ios_appstore_ipa.sh",
)
assert "--target" not in app_store and "lib/main.dart" not in app_store
require(read(".metadata"), "- 'lib/main.dart'", ".metadata")

print(
    "PASS: DTR-13 preserves every Sims profile, entrypoint, define, manual "
    "root, and enumerated headless/default-main workflow"
)
PY
