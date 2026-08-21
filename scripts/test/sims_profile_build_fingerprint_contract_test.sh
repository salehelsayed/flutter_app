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
mkdir -p "$tmp_dir/bin" "$tmp_dir/cache" "$tmp_dir/artifacts"
touch "$tmp_dir/build.log"

cat >"$tmp_dir/bin/flutter" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--version" ]; then
  printf '{"frameworkVersion":"fixture"}\n'
  exit 0
fi
profile="${SIMS_BUILD_PROFILE:?}"
printf '%s\n' "$profile" >>"${SIMS_BUILD_LOG:?}"
case "$profile" in
  android.e2e.standard)
    artifact="${SIMS_ARTIFACT_ROOT:?}/standard.apk"
    printf 'android fixture\n' >"$artifact"
    ;;
  android.production_fcm)
    artifact="${SIMS_ARTIFACT_ROOT:?}/provider-base.apk"
    printf 'provider base fixture\n' >"$artifact"
    ;;
  android.production_fcm.fixed_wake)
    artifact="${SIMS_ARTIFACT_ROOT:?}/provider-fixed-wake.apk"
    printf 'provider fixed-wake fixture\n' >"$artifact"
    ;;
  ios.simulator.e2e)
    artifact="${SIMS_ARTIFACT_ROOT:?}/Runner.app"
    rm -rf "$artifact"
    mkdir -p "$artifact"
    printf 'ios fixture\n' >"$artifact/Runner"
    chmod 755 "$artifact/Runner"
    ;;
  *) exit 91 ;;
esac
printf 'SIMS_BUILD_ARTIFACT=%s\n' "$artifact"
SH
chmod +x "$tmp_dir/bin/flutter"

cat >"$tmp_dir/bin/xcodebuild" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${SIMS_FAKE_XCODE_VERSION:-xcode-a}"
SH
chmod +x "$tmp_dir/bin/xcodebuild"

cat >"$tmp_dir/bin/pod" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'pod-fixture'
SH
chmod +x "$tmp_dir/bin/pod"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [ "${1:-}" = "version" ]; then' \
  '  printf "%s\n" "${SIMS_FAKE_GO_VERSION:-go-a}"' \
  '  exit 0' \
  'fi' \
  'if [ "${1:-}" = "env" ] && [ "${2:-}" = "GOPATH" ]; then' \
  '  printf "%s\n" "${SIMS_FAKE_GOPATH:?}"' \
  '  exit 0' \
  'fi' \
  'exit 64' \
  >"$tmp_dir/bin/go"
chmod +x "$tmp_dir/bin/go"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "${SIMS_FAKE_GOMOBILE_VERSION:-gomobile-a}"' \
  >"$tmp_dir/bin/gomobile"
chmod +x "$tmp_dir/bin/gomobile"

manifest="$tmp_dir/manifest.json"
cat >"$manifest" <<'JSON'
{
  "schemaVersion": 1,
  "buildProfiles": [
    {
      "id": "android.e2e.standard",
      "platform": "android",
      "artifactKind": "universal-debug-apk",
      "buildRequired": true,
      "compileDefines": {},
      "declaredException": false
    },
    {
      "id": "ios.simulator.e2e",
      "platform": "ios",
      "artifactKind": "simulator-runner-app",
      "buildRequired": true,
      "compileDefines": {},
      "declaredException": false
    },
    {
      "id": "android.production_fcm",
      "platform": "android",
      "artifactKind": "provider-configured-debug-apk",
      "buildRequired": true,
      "compileDefines": {"E2E_TEST_MODE": "true", "PRODUCTION_FCM": "true", "MKNOON_EMIT_WAKE_TOKEN": "true"},
      "declaredException": false
    },
    {
      "id": "android.production_fcm.fixed_wake",
      "platform": "android",
      "artifactKind": "provider-configured-debug-apk",
      "buildRequired": true,
      "compileDefines": {"E2E_TEST_MODE": "true", "PRODUCTION_FCM": "true", "MKNOON_EMIT_WAKE_TOKEN": "true", "MKNOON_ENABLE_WAKE_OUTCOME_COORDINATOR": "true"},
      "declaredException": false
    }
  ],
  "capabilities": [
    {
      "id": "build.android.fixture",
      "owner": "fixture-build",
      "proofBoundary": "fixture.android.profile-fingerprint",
      "assertions": ["android.profile.inputs.attested"],
      "lane": "build",
      "modes": ["major"],
      "families": ["fixture"],
      "required": true,
      "command": ["@prepare-build", "android.e2e.standard"],
      "buildProfile": "android.e2e.standard",
      "dependencies": [],
      "resources": [{"name": "build:android.e2e.standard", "access": "write"}],
      "targetCapabilities": [],
      "artifactRequired": true,
      "artifactValidator": "build.attestation",
      "active": true,
      "declaredBuildException": false
    },
    {
      "id": "build.ios.fixture",
      "owner": "fixture-build",
      "proofBoundary": "fixture.ios.profile-fingerprint",
      "assertions": ["ios.profile.inputs.attested"],
      "lane": "build",
      "modes": ["major"],
      "families": ["fixture"],
      "required": true,
      "command": ["@prepare-build", "ios.simulator.e2e"],
      "buildProfile": "ios.simulator.e2e",
      "dependencies": [],
      "resources": [{"name": "build:ios.simulator.e2e", "access": "write"}],
      "targetCapabilities": [],
      "artifactRequired": true,
      "artifactValidator": "build.attestation",
      "active": true,
      "declaredBuildException": false
    },
    {
      "id": "build.android.provider-base.fixture",
      "owner": "fixture-build",
      "proofBoundary": "fixture.android.provider-base-fingerprint",
      "assertions": ["android.provider.inputs.attested"],
      "lane": "build",
      "modes": ["major"],
      "families": ["fixture"],
      "required": true,
      "command": ["@prepare-build", "android.production_fcm"],
      "buildProfile": "android.production_fcm",
      "dependencies": [],
      "resources": [{"name": "build:android.production_fcm", "access": "write"}],
      "targetCapabilities": [],
      "artifactRequired": true,
      "artifactValidator": "build.attestation",
      "active": true,
      "declaredBuildException": false
    },
    {
      "id": "build.android.provider-fixed.fixture",
      "owner": "fixture-build",
      "proofBoundary": "fixture.android.provider-fixed-fingerprint",
      "assertions": ["android.provider.fixed.inputs.attested"],
      "lane": "build",
      "modes": ["major"],
      "families": ["fixture"],
      "required": true,
      "command": ["@prepare-build", "android.production_fcm.fixed_wake"],
      "buildProfile": "android.production_fcm.fixed_wake",
      "dependencies": [],
      "resources": [{"name": "build:android.production_fcm.fixed_wake", "access": "write"}],
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

source_digest="$(printf 'e%.0s' {1..64})"
xcode_version='xcode-a'
go_version='go-a'
gomobile_version='gomobile-a'
provider_version='provider-a'

run_prepare() {
  local report="$1"
  PATH="$tmp_dir/bin:$PATH" \
    SIMS_MANIFEST="$manifest" \
    SIMS_REPORT_PATH="$report" \
    SIMS_CACHE_DIR="$tmp_dir/cache" \
    SIMS_BUILD_LOG="$tmp_dir/build.log" \
    SIMS_ARTIFACT_ROOT="$tmp_dir/artifacts" \
    SIMS_FAKE_XCODE_VERSION="$xcode_version" \
    SIMS_FAKE_GO_VERSION="$go_version" \
    SIMS_FAKE_GOMOBILE_VERSION="$gomobile_version" \
    SIMS_PROVIDER_FCM_CREDENTIAL_DIGEST="$provider_version" \
    SIMS_FAKE_GOPATH="$tmp_dir/gopath" \
    SIMS_SOURCE_DIGEST="$source_digest" \
    SIMS_TEST_ALLOW_SOURCE_DIGEST_OVERRIDE=1 \
    ./scripts/run_test_gates.sh sims major --prepare-builds --list --format json \
      >"$report.stdout"
}

assert_report() {
  local report="$1"
  local builds="$2"
  local hits="$3"
  python3 - "$report" "$builds" "$hits" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text())
actual, hits = int(sys.argv[2]), int(sys.argv[3])
observed = report["builds"]
if observed["actualBuilds"] != actual or observed["hits"] != hits:
    raise SystemExit(
        f"FAIL: expected builds/hits {actual}/{hits}, got "
        f"{observed['actualBuilds']}/{observed['hits']}"
    )
PY
}

run_prepare "$tmp_dir/first.json"
assert_report "$tmp_dir/first.json" 4 0
[ "$(wc -l <"$tmp_dir/build.log" | tr -d ' ')" -eq 4 ] ||
  fail 'first preparation did not build all profiles once'

run_prepare "$tmp_dir/second.json"
assert_report "$tmp_dir/second.json" 0 4
[ "$(wc -l <"$tmp_dir/build.log" | tr -d ' ')" -eq 4 ] ||
  fail 'identical profile inputs did not hit all cache entries'

gomobile_version='gomobile-b'
run_prepare "$tmp_dir/gomobile-change.json"
assert_report "$tmp_dir/gomobile-change.json" 4 0
[ "$(wc -l <"$tmp_dir/build.log" | tr -d ' ')" -eq 8 ] ||
  fail 'gomobile identity change did not rebuild all mobile profiles once'

gomobile_version='gomobile-a'
xcode_version='xcode-b'
run_prepare "$tmp_dir/xcode-change.json"
assert_report "$tmp_dir/xcode-change.json" 1 3
[ "$(tail -n 1 "$tmp_dir/build.log")" = 'ios.simulator.e2e' ] ||
  fail 'an iOS-only toolchain change rebuilt the Android profile'

provider_version='provider-b'
run_prepare "$tmp_dir/provider-change.json"
assert_report "$tmp_dir/provider-change.json" 2 2
provider_rebuilds="$(tail -n 2 "$tmp_dir/build.log" | sort)"
[ "$provider_rebuilds" = $'android.production_fcm\nandroid.production_fcm.fixed_wake' ] ||
  fail 'provider credential change did not rebuild both isolated provider cohorts'

printf 'PASS: sims build fingerprints isolate platform toolchains and provider cohorts by profile\n'
