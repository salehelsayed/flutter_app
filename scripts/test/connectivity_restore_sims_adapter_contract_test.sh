#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

adapter='integration_test/scripts/run_connectivity_restore_sims.dart'
manifest='tool/sims/critical_features.json'
observer='lib/core/debug/intro_e2e_runner.dart'
builder='tool/sims/build_orchestrator.dart'

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

rg -q 'SIMS_ARTIFACT_ANDROID_E2E_MAIN' "$adapter" ||
  fail 'adapter does not consume the centrally prepared main APK'
rg -q "connectivityRestoreObserveAction" "$adapter" ||
  fail 'adapter does not arm the dedicated pre-generic observer'
rg -q "airplane-mode" "$adapter" ||
  fail 'adapter does not drive Android network loss/restore'
rg -q "uiautomator" "$adapter" ||
  fail 'adapter does not independently prove UI rendering'
rg -q "childFlutterBuilds.*0" "$adapter" ||
  fail 'durable evidence does not attest zero child Flutter builds'
if rg -q "Process\.(run|start)\(['\"]flutter|flutter (build|drive|run)" "$adapter"; then
  fail 'adapter contains a child Flutter invocation'
fi
python3 - "$adapter" <<'PY'
import sys

source = open(sys.argv[1], encoding='utf-8').read()
start = source.index('Future<void> _launch(String device)')
end = source.index('Future<_Identity> _identity', start)
launch = source[start:end]
assert "'am'" in launch and "'start'" in launch and "'-W'" in launch
assert "'-n'" in launch and "'$packageName/.MainActivity'" in launch
assert 'result.exitCode != 0' in launch
assert r"r'^Status:[ \t]+ok[ \t]*\r?$'" in launch
assert 'monkey' not in launch
PY

python3 - "$manifest" <<'PY'
import json, sys

with open(sys.argv[1], encoding='utf-8') as handle:
    manifest = json.load(handle)

profiles = {profile['id']: profile for profile in manifest['buildProfiles']}
main = profiles.get('android.e2e.main')
assert main is not None and main['compileDefines'] == {'E2E_TEST_MODE': 'true'}

rows = {row['id']: row for row in manifest['capabilities']}
build = rows['build.android.e2e.main']
campaign = rows['android.connectivity_restore_inbox_drain']
assert build['command'] == ['@prepare-build', 'android.e2e.main']
assert campaign['command'] == [
    'dart', 'run', 'integration_test/scripts/run_connectivity_restore_sims.dart'
]
assert campaign['buildProfile'] == 'android.e2e.main'
assert campaign['dependencies'] == ['build.android.e2e.main']
assert campaign['automationReady'] is True
assert campaign['artifactValidator'] == 'validateConnectivityRestoreArtifact'
PY

python3 - "$observer" <<'PY'
import sys

source = open(sys.argv[1], encoding='utf-8').read()
action_start = source.index('Future<void> _runConnectivityRestoreObservation')
poller_start = source.index('void startIntroE2EPoller', action_start)
action = source[action_start:poller_start]
assert 'getMessagesForContact' in action
assert 'setE2EFlowEventSink' in action
assert 'drainOfflineInbox' not in action
assert 'performImmediateHealthCheck' not in action
branch = source.index(
    "config['transport_action'] == connectivityRestoreObserveAction",
    poller_start,
)
generic = source.index('await runIntroE2EActions(', poller_start)
assert branch < generic
PY

rg -q "'android.e2e.main' => 'lib/main.dart'" "$builder" ||
  fail 'central builder does not bind android.e2e.main to lib/main.dart'

set +e
output="$(env -u SIMS_ARTIFACT_ANDROID_E2E_MAIN \
  dart run "$adapter" 2>&1)"
status=$?
set -e
[[ $status -eq 78 ]] || fail "missing prepared APK returned $status, expected 78"
[[ "$output" == *'"status":"BLOCKED"'* ]] ||
  fail 'missing prepared APK did not emit a typed BLOCKED sentinel'

printf 'PASS: connectivity restore adapter is build-free and main-profile bound\n'
