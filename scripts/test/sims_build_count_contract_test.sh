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

fake_bin="$tmp_dir/bin"
cache_dir="$tmp_dir/cache"
artifact_dir="$tmp_dir/artifacts"
build_log="$tmp_dir/build.log"
runner="$tmp_dir/row_fixture.sh"
mkdir -p "$fake_bin" "$cache_dir" "$artifact_dir"
touch "$build_log"

# Central preparation identifies the profile explicitly. A build reached from
# a child row has no authority marker and fails; this is the process boundary
# that prevents hidden flutter/Gradle/Xcode rebuilds.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [ "${1:-}" = "--version" ]; then' \
  '  printf "%s\n" "${SIMS_FAKE_FLUTTER_VERSION:-fixture-flutter-v1}"' \
  '  exit 0' \
  'fi' \
  'if [ -z "${SIMS_BUILD_PROFILE-}" ]; then' \
  '  printf "UNDECLARED\t%s\n" "$*" >>"${SIMS_BUILD_LOG:?}"' \
  '  printf "undeclared child build\n" >&2' \
  '  exit 91' \
  'fi' \
  'printf "CENTRAL\t%s\t%s\n" "$SIMS_BUILD_PROFILE" "$*" >>"${SIMS_BUILD_LOG:?}"' \
  'if [ "${SIMS_FAKE_FAIL_BUILD_PROFILE:-}" = "$SIMS_BUILD_PROFILE" ]; then' \
  '  printf "fixture central failure for %s\n" "$SIMS_BUILD_PROFILE" >&2' \
  '  exit 92' \
  'fi' \
  'artifact="${SIMS_FAKE_ARTIFACT_DIR:?}/${SIMS_BUILD_PROFILE}.apk"' \
  'printf "fixture artifact for %s\n" "$SIMS_BUILD_PROFILE" >"$artifact"' \
  'printf "SIMS_BUILD_ARTIFACT=%s\n" "$artifact"' \
  >"$fake_bin/flutter"
chmod +x "$fake_bin/flutter"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'case "${1:?missing row case}" in' \
  '  pass)' \
  '    printf '\''SIMS_RESULT_JSON=%s\n'\'' '\''{"status":"PASS","assertionsAttempted":1,"artifactPresent":true,"printOnly":false}'\''' \
  '    ;;' \
  '  undeclared)' \
  '    flutter build apk --debug' \
  '    printf '\''SIMS_RESULT_JSON=%s\n'\'' '\''{"status":"PASS","assertionsAttempted":1,"artifactPresent":true,"printOnly":false}'\''' \
  '    ;;' \
  '  *) exit 64 ;;' \
  'esac' \
  >"$runner"
chmod +x "$runner"

write_manifest() {
  local wake_define="$1"
  local first_row_case="$2"
  local manifest_path="$3"

  printf '%s\n' \
    '{' \
    '  "schemaVersion": 1,' \
    '  "buildProfiles": [' \
    '    {' \
    '      "id": "android.e2e.standard",' \
    '      "platform": "android",' \
    '      "artifactKind": "apk",' \
    '      "buildRequired": true,' \
    '      "compileDefines": {},' \
    '      "declaredException": false' \
    '    },' \
    '    {' \
    '      "id": "android.e2e.wake_token",' \
    '      "platform": "android",' \
    '      "artifactKind": "apk",' \
    '      "buildRequired": true,' \
    "      \"compileDefines\": {\"MKNOON_EMIT_WAKE_TOKEN\": \"$wake_define\"}," \
    '      "declaredException": false' \
    '    }' \
    '  ],' \
    '  "capabilities": [' \
    '    {' \
    '      "id": "build.android.standard",' \
    '      "owner": "fixture-build",' \
    '      "proofBoundary": "fixture.build.standard.attestation",' \
    '      "assertions": ["fixture.build.standard.digest"],' \
    '      "lane": "build",' \
    '      "modes": ["major"],' \
    '      "families": ["fixture"],' \
    '      "required": true,' \
    '      "command": ["@prepare-build", "android.e2e.standard"],' \
    '      "buildProfile": "android.e2e.standard",' \
    '      "dependencies": [],' \
    '      "resources": [{"name": "build:android.e2e.standard", "access": "write"}],' \
    '      "targetCapabilities": [],' \
    '      "artifactRequired": true,' \
    '      "artifactValidator": "build.attestation",' \
    '      "active": true,' \
    '      "declaredBuildException": false' \
    '    },' \
    '    {' \
    '      "id": "build.android.wake",' \
    '      "owner": "fixture-build",' \
    '      "proofBoundary": "fixture.build.wake.attestation",' \
    '      "assertions": ["fixture.build.wake.digest"],' \
    '      "lane": "build",' \
    '      "modes": ["major"],' \
    '      "families": ["fixture"],' \
    '      "required": true,' \
    '      "command": ["@prepare-build", "android.e2e.wake_token"],' \
    '      "buildProfile": "android.e2e.wake_token",' \
    '      "dependencies": [],' \
    '      "resources": [{"name": "build:android.e2e.wake_token", "access": "write"}],' \
    '      "targetCapabilities": [],' \
    '      "artifactRequired": true,' \
    '      "artifactValidator": "build.attestation",' \
    '      "active": true,' \
    '      "declaredBuildException": false' \
    '    },' \
    '    {' \
    '      "id": "fixture.standard.a",' \
    '      "owner": "fixture",' \
    '      "proofBoundary": "fixture.standard.a.boundary",' \
    '      "assertions": ["fixture.standard.a.assertion"],' \
    '      "lane": "reliability",' \
    '      "modes": ["major"],' \
    '      "families": ["fixture"],' \
    '      "required": true,' \
    "      \"command\": [\"bash\", \"$runner\", \"$first_row_case\"]," \
    '      "buildProfile": "android.e2e.standard",' \
    '      "dependencies": ["build.android.standard"],' \
    '      "resources": [{"name": "build:android.e2e.standard", "access": "read"}],' \
    '      "targetCapabilities": [],' \
    '      "artifactRequired": true,' \
    '      "artifactValidator": "fixture.sentinel",' \
    '      "active": true,' \
    '      "declaredBuildException": false' \
    '    },' \
    '    {' \
    '      "id": "fixture.standard.b",' \
    '      "owner": "fixture",' \
    '      "proofBoundary": "fixture.standard.b.boundary",' \
    '      "assertions": ["fixture.standard.b.assertion"],' \
    '      "lane": "reliability",' \
    '      "modes": ["major"],' \
    '      "families": ["fixture"],' \
    '      "required": true,' \
    "      \"command\": [\"bash\", \"$runner\", \"pass\", \"b\"]," \
    '      "buildProfile": "android.e2e.standard",' \
    '      "dependencies": ["build.android.standard"],' \
    '      "resources": [{"name": "build:android.e2e.standard", "access": "read"}],' \
    '      "targetCapabilities": [],' \
    '      "artifactRequired": true,' \
    '      "artifactValidator": "fixture.sentinel",' \
    '      "active": true,' \
    '      "declaredBuildException": false' \
    '    },' \
    '    {' \
    '      "id": "fixture.wake",' \
    '      "owner": "fixture",' \
    '      "proofBoundary": "fixture.wake.boundary",' \
    '      "assertions": ["fixture.wake.assertion"],' \
    '      "lane": "reliability",' \
    '      "modes": ["major"],' \
    '      "families": ["fixture"],' \
    '      "required": true,' \
    "      \"command\": [\"bash\", \"$runner\", \"pass\", \"wake\"]," \
    '      "buildProfile": "android.e2e.wake_token",' \
    '      "dependencies": ["build.android.wake"],' \
    '      "resources": [{"name": "build:android.e2e.wake_token", "access": "read"}],' \
    '      "targetCapabilities": [],' \
    '      "artifactRequired": true,' \
    '      "artifactValidator": "fixture.sentinel",' \
    '      "active": true,' \
    '      "declaredBuildException": false' \
    '    }' \
    '  ],' \
    '  "ownership": []' \
    '}' \
    >"$manifest_path"
}

assert_build_report() {
  local report_path="$1"
  local expected_actual="$2"
  local expected_hits="$3"
  local expected_misses="$4"
  local require_invalidation="$5"

  python3 - "$report_path" "$expected_actual" "$expected_hits" \
    "$expected_misses" "$require_invalidation" <<'PY'
import json
import sys

path, actual, hits, misses, require_invalidation = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    report = json.load(stream)
builds = report.get("builds", {})

def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")

require(builds.get("requestedProfiles") == 2, "build report did not deduplicate two selected profiles")
require(builds.get("actualBuilds") == int(actual),
        f"expected {actual} actual builds, got {builds.get('actualBuilds')}")
require(builds.get("hits") == int(hits), f"expected {hits} cache hits")
require(builds.get("misses") == int(misses), f"expected {misses} cache misses")
expected_profiles = {"android.e2e.standard", "android.e2e.wake_token"}
built_ids = builds.get("builtProfileIds")
hit_ids = builds.get("cacheHitProfileIds")
failed_ids = builds.get("failedProfileIds")
require(isinstance(built_ids, list) and len(built_ids) == int(actual),
        "build report omitted exact built profile outcomes")
require(isinstance(hit_ids, list) and len(hit_ids) == int(hits),
        "build report omitted exact cache-hit profile outcomes")
require(isinstance(failed_ids, list) and len(failed_ids) == int(misses) - int(actual),
        "build report omitted exact failed profile outcomes")
require(set(built_ids + hit_ids + failed_ids) == expected_profiles,
        "build outcomes did not cover the two requested profiles exactly once")
profile_elapsed = builds.get("profileElapsedMs")
require(isinstance(profile_elapsed, dict) and set(profile_elapsed) == expected_profiles,
        "build report omitted per-profile elapsed times")
require(all(isinstance(value, int) and value >= 0 for value in profile_elapsed.values()),
        "build profile elapsed times must be non-negative integers")
require(isinstance(builds.get("totalElapsedMs"), int) and builds["totalElapsedMs"] >= 0,
        "build report omitted the total preparation elapsed time")
digests = builds.get("artifactDigests")
require(isinstance(digests, dict) and set(digests) == expected_profiles,
        "build report omitted profile artifact digests")
if require_invalidation == "yes":
    require(builds.get("invalidations"), "stale profile input did not report an invalidation")
serialized = json.dumps(report)
require("fixture artifact for" not in serialized, "report leaked artifact bytes")
PY
}

run_prepare() {
  local manifest_path="$1"
  local report_path="$2"
  local process_status

  rm -f "$report_path"
  set +e
  PATH="$fake_bin:$PATH" \
    SIMS_MANIFEST="$manifest_path" \
    SIMS_REPORT_PATH="$report_path" \
    SIMS_CACHE_DIR="$cache_dir" \
    SIMS_BUILD_LOG="$build_log" \
    SIMS_FAKE_ARTIFACT_DIR="$artifact_dir" \
    SIMS_SOURCE_DIGEST=fixture-source-v1 \
    SIMS_TEST_ALLOW_SOURCE_DIGEST_OVERRIDE=1 \
    ./scripts/run_test_gates.sh sims major --prepare-builds --list --format json \
      >"$report_path.stdout" 2>"$report_path.stderr"
  process_status=$?
  set -e

  if [ ! -f "$report_path" ]; then
    fail "sims build-cache seam missing: --prepare-builds did not honor SIMS_CACHE_DIR/SIMS_REPORT_PATH (required protocol: one central flutter build per unique profile, attested artifact cache, typed build report)"
  fi
  [ "$process_status" -eq 0 ] ||
    fail "build preparation exited with $process_status instead of 0"
}

manifest="$tmp_dir/manifest.json"
write_manifest true pass "$manifest"

first_report="$tmp_dir/first.report.json"
run_prepare "$manifest" "$first_report"
assert_build_report "$first_report" 2 0 2 no
[ "$(awk -F '\t' '$1 == "CENTRAL" {count++} END {print count+0}' "$build_log")" -eq 2 ] ||
  fail 'first preparation did not build exactly two unique profiles'
[ "$(awk -F '\t' '$1 == "CENTRAL" && $2 == "android.e2e.standard" {count++} END {print count+0}' "$build_log")" -eq 1 ] ||
  fail 'two compatible standard rows built the same profile more than once'
standard_build="$(awk -F '\t' '$1 == "CENTRAL" && $2 == "android.e2e.standard" {print $3}' "$build_log")"
case "$standard_build" in
  *'--target=integration_test/sims_dispatcher.dart'*) ;;
  *) fail 'android.e2e.standard did not compile the universal sims dispatcher' ;;
esac
case "$standard_build" in
  *'--target-platform=android-arm64'*) ;;
  *) fail 'android.e2e.standard did not compile the live-matrix arm64 ABI' ;;
esac
case "$standard_build" in
  *'--android-project-arg=simsAndroidAbi=arm64-v8a'*) ;;
  *) fail 'android.e2e.standard did not filter transitive native libraries to arm64' ;;
esac
case "$standard_build" in
  *'--dart-define=SIMS_BUILD_PROFILE_ID=android.e2e.standard'*) ;;
  *) fail 'android.e2e.standard omitted its compile-time profile handshake' ;;
esac
wake_build="$(awk -F '\t' '$1 == "CENTRAL" && $2 == "android.e2e.wake_token" {print $3}' "$build_log")"
case "$wake_build" in
  *'--target-platform=android-arm64'*) ;;
  *) fail 'android.e2e.wake_token did not compile the live-matrix arm64 ABI' ;;
esac
case "$wake_build" in
  *'--android-project-arg=simsAndroidAbi=arm64-v8a'*) ;;
  *) fail 'android.e2e.wake_token did not filter transitive native libraries to arm64' ;;
esac
case "$wake_build" in
  *'--dart-define=SIMS_BUILD_PROFILE_ID=android.e2e.wake_token'*) ;;
  *) fail 'android.e2e.wake_token omitted its exact compile-time profile handshake' ;;
esac

second_report="$tmp_dir/second.report.json"
run_prepare "$manifest" "$second_report"
assert_build_report "$second_report" 0 2 0 no
[ "$(awk -F '\t' '$1 == "CENTRAL" {count++} END {print count+0}' "$build_log")" -eq 2 ] ||
  fail 'identical second preparation rebuilt a cache hit'

# A compile-time profile input is part of the digest. Only the changed profile
# rebuilds; ordinary runtime row arguments are deliberately outside the key.
write_manifest false pass "$manifest"
stale_report="$tmp_dir/stale.report.json"
run_prepare "$manifest" "$stale_report"
assert_build_report "$stale_report" 1 1 1 yes
[ "$(awk -F '\t' '$1 == "CENTRAL" {count++} END {print count+0}' "$build_log")" -eq 3 ] ||
  fail 'one stale profile did not cause exactly one additional build'

# The real toolchain identity participates in every profile key. A Flutter
# version change invalidates both otherwise-identical Android artifacts.
export SIMS_FAKE_FLUTTER_VERSION=fixture-flutter-v2
toolchain_report="$tmp_dir/toolchain.report.json"
run_prepare "$manifest" "$toolchain_report"
assert_build_report "$toolchain_report" 2 0 2 yes
[ "$(awk -F '\t' '$1 == "CENTRAL" {count++} END {print count+0}' "$build_log")" -eq 5 ] ||
  fail 'toolchain version change did not rebuild both selected profiles'

# Build-only preparation is an inventory operation. A failed independent
# profile must be reported as failed without turning a later successful build
# into a synthetic dependency blocker.
failure_cache_dir="$tmp_dir/failure-cache"
failure_report="$tmp_dir/failure.report.json"
mkdir -p "$failure_cache_dir"
set +e
PATH="$fake_bin:$PATH" \
  SIMS_MANIFEST="$manifest" \
  SIMS_REPORT_PATH="$failure_report" \
  SIMS_CACHE_DIR="$failure_cache_dir" \
  SIMS_BUILD_LOG="$build_log" \
  SIMS_FAKE_ARTIFACT_DIR="$artifact_dir" \
  SIMS_FAKE_FAIL_BUILD_PROFILE=android.e2e.standard \
  SIMS_SOURCE_DIGEST=fixture-source-prepare-failure \
  SIMS_TEST_ALLOW_SOURCE_DIGEST_OVERRIDE=1 \
  ./scripts/run_test_gates.sh sims major --prepare-builds --list --format json \
    >"$failure_report.stdout" 2>"$failure_report.stderr"
failure_status=$?
set -e
[ "$failure_status" -ne 0 ] ||
  fail 'one failed build profile incorrectly produced a green preparation'
[ -f "$failure_report" ] ||
  fail 'failed build preparation did not leave a typed report'
python3 - "$failure_report" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    report = json.load(stream)

verdicts = {item["capabilityId"]: item for item in report["verdicts"]}
standard = verdicts.get("build.android.standard", {})
wake = verdicts.get("build.android.wake", {})
if standard.get("status") != "BLOCKED":
    raise SystemExit("FAIL: failed standard profile was not typed BLOCKED")
if wake.get("status") != "PASS":
    raise SystemExit(
        "FAIL: independent wake profile was not classified PASS after a build failure"
    )
if "dependency" in wake.get("detail", "").lower():
    raise SystemExit("FAIL: independent wake profile retained a synthetic dependency blocker")

builds = report.get("builds", {})
if builds.get("requestedProfiles") != 2:
    raise SystemExit("FAIL: failed preparation did not classify both requested profiles")
if builds.get("actualBuilds") != 1:
    raise SystemExit("FAIL: independent wake profile was not built exactly once")
if builds.get("failedProfileIds") != ["android.e2e.standard"]:
    raise SystemExit("FAIL: failed build profile outcome was not exact")
if builds.get("builtProfileIds") != ["android.e2e.wake_token"]:
    raise SystemExit("FAIL: successful build profile outcome was not exact")
PY

# Reuse the attested standard artifact, then inject a forbidden build from the
# row process. The PATH shim exits 91 and the aggregate must remain non-green.
write_manifest false undeclared "$manifest"
undeclared_report="$tmp_dir/undeclared.report.json"
set +e
PATH="$fake_bin:$PATH" \
  SIMS_MANIFEST="$manifest" \
  SIMS_REPORT_PATH="$undeclared_report" \
  SIMS_CACHE_DIR="$cache_dir" \
  SIMS_BUILD_LOG="$build_log" \
  SIMS_FAKE_ARTIFACT_DIR="$artifact_dir" \
  SIMS_SOURCE_DIGEST=fixture-source-v1 \
  SIMS_TEST_ALLOW_SOURCE_DIGEST_OVERRIDE=1 \
  ./scripts/run_test_gates.sh sims major --only fixture.standard.a --format json \
    >"$tmp_dir/undeclared.stdout" 2>"$tmp_dir/undeclared.stderr"
undeclared_status=$?
set -e
[ "$undeclared_status" -ne 0 ] ||
  fail 'undeclared child flutter build incorrectly exited 0'
[ -f "$undeclared_report" ] ||
  fail 'undeclared child build did not leave a typed failure report'
python3 - "$undeclared_report" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    report = json.load(stream)
verdict = next(
    item for item in report["verdicts"]
    if item.get("capabilityId") == "fixture.standard.a"
)
if verdict.get("status") == "PASS":
    raise SystemExit("FAIL: undeclared child build was typed PASS")
if "Undeclared child build command rejected: flutter build apk --debug" not in verdict.get("detail", ""):
    raise SystemExit("FAIL: production executor build guard did not identify the child command")
if report.get("assessment", {}).get("releaseEligible") is not False:
    raise SystemExit("FAIL: undeclared child build produced release green")
if report.get("builds", {}).get("actualBuilds") != 0:
    raise SystemExit("FAIL: child attempt was counted as an authorized central build")
PY

printf 'PASS: sims build count/cache/authority process contract\n'
