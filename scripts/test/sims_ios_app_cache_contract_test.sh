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

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [ "${1:-}" = "--version" ]; then printf "fixture flutter\n"; exit 0; fi' \
  '[ "${SIMS_BUILD_PROFILE-}" = "ios.simulator.e2e" ] || exit 91' \
  'printf "build\n" >>"${SIMS_BUILD_LOG:?}"' \
  'app="${SIMS_ARTIFACT_ROOT:?}/Runner.app"' \
  'rm -rf "$app"' \
  'mkdir -p "$app/Frameworks/App.framework"' \
  'printf "executable\n" >"$app/Frameworks/App.framework/App"' \
  'printf "plist\n" >"$app/Info.plist"' \
  'chmod 755 "$app" "$app/Frameworks" "$app/Frameworks/App.framework" "$app/Frameworks/App.framework/App"' \
  'chmod 644 "$app/Info.plist"' \
  'printf "SIMS_BUILD_ARTIFACT=%s\n" "$app"' \
  >"$tmp_dir/bin/flutter"
chmod +x "$tmp_dir/bin/flutter"

for executable in xcodebuild pod; do
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "fixture toolchain\n"' \
    >"$tmp_dir/bin/$executable"
  chmod +x "$tmp_dir/bin/$executable"
done

manifest="$tmp_dir/manifest.json"
cat >"$manifest" <<JSON
{
  "schemaVersion": 1,
  "buildProfiles": [
    {
      "id": "ios.simulator.e2e",
      "platform": "ios",
      "artifactKind": "app",
      "buildRequired": true,
      "compileDefines": {},
      "declaredException": false
    }
  ],
  "capabilities": [
    {
      "id": "build.ios.simulator",
      "owner": "fixture-build",
      "proofBoundary": "fixture.build.ios.app.attestation",
      "assertions": ["fixture.build.ios.app.digest"],
      "lane": "build",
      "modes": ["major"],
      "families": ["fixture"],
      "required": true,
      "command": ["@prepare-build", "ios.simulator.e2e"],
      "buildProfile": "ios.simulator.e2e",
      "dependencies": [],
      "resources": [
        {"name": "build:ios.simulator.e2e", "access": "write"}
      ],
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
  PATH="$tmp_dir/bin:$PATH" \
    SIMS_MANIFEST="$manifest" \
    SIMS_REPORT_PATH="$report" \
    SIMS_CACHE_DIR="$tmp_dir/cache" \
    SIMS_BUILD_LOG="$tmp_dir/build.log" \
    SIMS_ARTIFACT_ROOT="$tmp_dir/artifacts" \
    SIMS_SOURCE_DIGEST=fixture-source \
    SIMS_TEST_ALLOW_SOURCE_DIGEST_OVERRIDE=1 \
    ./scripts/run_test_gates.sh sims major --prepare-builds --list --format json \
      >"$report.stdout"
}

first_report="$tmp_dir/first.json"
run_prepare "$first_report"
cached_executable="$(find "$tmp_dir/cache" -type f -path '*/Runner.app/Frameworks/App.framework/App' -print -quit)"
[ -n "$cached_executable" ] || fail 'cached Runner.app executable is missing'
[ -x "$cached_executable" ] || fail 'Runner.app executable mode was not preserved'
[ "$(wc -l <"$tmp_dir/build.log" | tr -d ' ')" -eq 1 ] ||
  fail 'first preparation did not build once'

second_report="$tmp_dir/second.json"
run_prepare "$second_report"
[ "$(wc -l <"$tmp_dir/build.log" | tr -d ' ')" -eq 1 ] ||
  fail 'identical Runner.app preparation rebuilt instead of hitting cache'
python3 - "$second_report" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    report = json.load(stream)
builds = report["builds"]
if builds["actualBuilds"] != 0 or builds["hits"] != 1:
    raise SystemExit("FAIL: second Runner.app preparation was not a cache hit")
PY

chmod 644 "$cached_executable"
third_report="$tmp_dir/third.json"
run_prepare "$third_report"
[ "$(wc -l <"$tmp_dir/build.log" | tr -d ' ')" -eq 2 ] ||
  fail 'mode-corrupt Runner.app did not cause exactly one rebuild'
[ -x "$(find "$tmp_dir/cache" -type f -path '*/Runner.app/Frameworks/App.framework/App' -print -quit)" ] ||
  fail 'rebuilt Runner.app executable mode was not restored'
python3 - "$third_report" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    report = json.load(stream)
builds = report["builds"]
if builds["actualBuilds"] != 1 or not builds["invalidations"]:
    raise SystemExit("FAIL: mode corruption was not reported as a cache invalidation")
PY

printf 'PASS: sims Runner.app cache preserves and attests executable modes\n'
