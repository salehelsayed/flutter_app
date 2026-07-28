#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ADAPTER="$ROOT_DIR/.claude/skills/sims/scripts/run_with_devices.sh"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# The public no-argument spelling is the release-safe major plan. Compare the
# machine-readable documents, rather than presentation text, so a wrapper
# cannot silently select a smaller mode.
./scripts/run_test_gates.sh sims --list --format json \
  >"$tmp_dir/default.json"
./scripts/run_test_gates.sh sims major --list --format json \
  >"$tmp_dir/major.json"
cmp -s "$tmp_dir/default.json" "$tmp_dir/major.json" ||
  fail 'sims without a mode did not compile the exact major plan'

./scripts/run_test_gates.sh sims full --list --format json \
  >"$tmp_dir/full.json"
./scripts/run_test_gates.sh sims smoke --list --format json \
  >"$tmp_dir/smoke.json"
./scripts/run_test_gates.sh sims major --family 1to1 --list --format json \
  >"$tmp_dir/family.json"

python3 - \
  "$tmp_dir/major.json" "$tmp_dir/full.json" \
  "$tmp_dir/smoke.json" "$tmp_dir/family.json" <<'PY'
import json
import sys

major, full, smoke, family = [json.load(open(path, encoding="utf-8")) for path in sys.argv[1:]]

def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")

require(major.get("mode") == "major", "default document is not mode=major")
require(major.get("releaseEligibleCandidate") is True,
        "unfiltered major plan is not the sole release-eligible candidate")
require(full.get("mode") == "full" and full.get("releaseEligibleCandidate") is False,
        "full mode incorrectly claims release eligibility")
require(smoke.get("mode") == "smoke" and smoke.get("releaseEligibleCandidate") is False,
        "smoke mode incorrectly claims release eligibility")
require(family.get("family") == "1to1" and family.get("releaseEligibleCandidate") is False,
        "a diagnostic family filter incorrectly claims release eligibility")

rows = major.get("rows")
selected = major.get("selectedIds")
require(isinstance(rows, list) and rows, "major plan has no typed rows")
require(isinstance(selected, list), "major plan omitted selectedIds")
row_ids = [row.get("id") for row in rows]
require(selected == row_ids, "selectedIds are not the ordered executable rows")
require(len(row_ids) == len(set(row_ids)), "major plan contains duplicate capability IDs")

for key, label in (("proofBoundary", "proof boundaries"),):
    values = [row.get(key) for row in rows]
    require(all(isinstance(value, str) and value for value in values),
            f"major plan has incomplete {label}")
    require(len(values) == len(set(values)), f"major plan contains duplicate {label}")

commands = [json.dumps(row.get("command"), separators=(",", ":")) for row in rows]
require(all(command != "null" for command in commands), "major plan has a row without a command")
require(len(commands) == len(set(commands)), "major plan contains duplicate executable commands")

host_row = next((row for row in rows if row.get("id") == "host.dart.all"), None)
require(host_row is not None, "major plan omitted host.dart.all")
require(host_row.get("command") == [
    "./scripts/run_host_test_gates.sh", "host-all", "--dart-only",
    "--batch-flutter", "--concurrency", "4", "--reporter", "failures-only",
], "host.dart.all does not batch exact paths with bounded concurrency")

ios_runner_row = next((row for row in rows if row.get("id") == "native.ios.runner_tests"), None)
require(ios_runner_row is not None, "major plan omitted native.ios.runner_tests")
require(ios_runner_row.get("command") == [
    "xcodebuild", "test", "-workspace", "ios/Runner.xcworkspace",
    "-scheme", "Runner", "-destination",
    "platform=iOS Simulator,id=${SIMS_IOS_SIMULATOR_ID}",
    "CODE_SIGNING_ALLOWED=NO", "-parallel-testing-enabled", "NO",
    "-only-testing:RunnerTests",
], "native.ios.runner_tests does not keep Simulator A lifecycle serial")

required_lanes = {
    "analyzer", "host-dart", "go-node", "go-relay", "native-android",
    "native-ios", "nested-package", "reliability", "performance",
    "performance-device",
}
lanes = {row.get("lane") for row in rows}
missing = sorted(required_lanes - lanes)
require(not missing, f"major plan is missing required lanes: {', '.join(missing)}")

nested_row = next((row for row in rows if row.get("id") == "nested.background_push_crypto"), None)
require(nested_row is not None, "major plan omitted nested package")
require(nested_row.get("command") == [
    "bash", "-lc",
    "cd packages/background_push_crypto && flutter test && dart analyze",
], "nested package row does not run both tests and analyzer")

analyzer_rows = [row for row in rows if row.get("id") == "analyzer.flutter"]
require(len(analyzer_rows) == 1,
        "major plan must contain analyzer.flutter exactly once")
analyzer_row = analyzer_rows[0]
require(analyzer_row.get("owner") == "platform",
        "analyzer row owner drifted")
require(analyzer_row.get("proofBoundary") == "host.analyzer.repo",
        "analyzer proof boundary drifted")
require(analyzer_row.get("assertions") == [
    "analyzer.no_errors",
    "analyzer.no_warnings_or_infos",
    "analyzer.production_unused_suppressions_ratcheted",
], "analyzer assertion contract drifted")
require(analyzer_row.get("lane") == "analyzer",
        "analyzer lane drifted")
require(analyzer_row.get("modes") == ["major"],
        "analyzer modes drifted")
require(analyzer_row.get("families") == ["infra"],
        "analyzer families drifted")
require(analyzer_row.get("required") is True,
        "analyzer row is not required")
require(analyzer_row.get("command") == [
    "./scripts/check_flutter_analyze_strict.sh",
], "analyzer command is not the strict gate")
require(analyzer_row.get("buildProfile") == "host.process",
        "analyzer build profile drifted")
require(analyzer_row.get("dependencies") == [],
        "analyzer dependencies must remain empty")
require(analyzer_row.get("resources") == [
    {"name": "host.cpu", "access": "read"},
], "analyzer resource contract drifted")
require(analyzer_row.get("targetCapabilities") == [
    "host.flutter-sdk", "host.bash", "host.git",
], "analyzer target requirements drifted")
require(analyzer_row.get("artifactRequired") is False,
        "analyzer row must not require an artifact")
require(analyzer_row.get("artifactValidators", []) == [],
        "analyzer row must not declare artifact validators")
require(analyzer_row.get("allowedNaReason") is None,
        "analyzer row must not allow N/A")
require(analyzer_row.get("active") is True,
        "analyzer row is inactive")
require(analyzer_row.get("automationReady", True) is True,
        "analyzer row is not automation-ready")
require(analyzer_row.get("declaredBuildException") is False,
        "analyzer row declared an unexpected build exception")

runtime_rows = [row for row in rows if row.get("id") == "runtime.roots.advisory"]
require(len(runtime_rows) == 1,
        "major plan must contain runtime.roots.advisory exactly once")
runtime_row = runtime_rows[0]
require(runtime_row.get("owner") == "flutter-app",
        "runtime-root row owner drifted")
require(runtime_row.get("proofBoundary") == "host.runtime-roots.advisory",
        "runtime-root proof boundary drifted")
require(runtime_row.get("assertions") == ["runtime_roots.inventory_accounted"],
        "runtime-root assertion contract drifted")
require(runtime_row.get("lane") == "host-dart",
        "runtime-root lane drifted")
require(runtime_row.get("modes") == ["major"],
        "runtime-root modes drifted")
require(runtime_row.get("families") == ["infra"],
        "runtime-root families drifted")
require(runtime_row.get("required") is True,
        "runtime-root row is not required")
require(runtime_row.get("command") == [
    "./scripts/run_test_gates.sh", "runtime-roots",
], "runtime-root command drifted")
require(runtime_row.get("buildProfile") == "host.flutter_tester",
        "runtime-root build profile drifted")
require(runtime_row.get("dependencies") == [],
        "runtime-root dependencies must remain empty")
require(runtime_row.get("resources") == [
    {"name": "host.cpu", "access": "read"},
], "runtime-root resource contract drifted")
require(runtime_row.get("targetCapabilities") == [
    "host.flutter-tester", "host.bash", "host.git",
], "runtime-root target requirements drifted")
require(runtime_row.get("artifactRequired") is False,
        "runtime-root row must not require an artifact")
require(runtime_row.get("artifactValidators", []) == [],
        "runtime-root row must not declare artifact validators")
require(runtime_row.get("allowedNaReason") is None,
        "runtime-root row must not allow N/A")
require(runtime_row.get("active") is True,
        "runtime-root row is inactive")
require(runtime_row.get("automationReady") is True,
        "runtime-root row is not automation-ready")
require(runtime_row.get("declaredBuildException") is False,
        "runtime-root row declared an unexpected build exception")

architecture_rows = [row for row in rows if row.get("id") == "architecture.boundaries"]
require(len(architecture_rows) == 1,
        "major plan must contain architecture.boundaries exactly once")
architecture_row = architecture_rows[0]
require(architecture_row.get("owner") == "flutter-app",
        "architecture-boundary row owner drifted")
require(architecture_row.get("proofBoundary") ==
        "host.architecture-boundaries.enforced",
        "architecture-boundary proof boundary drifted")
require(architecture_row.get("assertions") == [
    "architecture_boundaries.current_exceptions_exact",
], "architecture-boundary assertion contract drifted")
require(architecture_row.get("lane") == "host-dart",
        "architecture-boundary lane drifted")
require(architecture_row.get("modes") == ["major"],
        "architecture-boundary modes drifted")
require(architecture_row.get("families") == ["infra"],
        "architecture-boundary families drifted")
require(architecture_row.get("required") is True,
        "architecture-boundary row is not required")
require(architecture_row.get("command") == [
    "./scripts/run_test_gates.sh", "architecture-boundaries",
], "architecture-boundary command drifted")
require(architecture_row.get("buildProfile") == "host.flutter_tester",
        "architecture-boundary build profile drifted")
require(architecture_row.get("dependencies") == [],
        "architecture-boundary dependencies must remain empty")
require(architecture_row.get("resources") == [
    {"name": "host.cpu", "access": "read"},
], "architecture-boundary resource contract drifted")
require(architecture_row.get("targetCapabilities") == [
    "host.flutter-tester", "host.bash", "host.git",
], "architecture-boundary target requirements drifted")
require(architecture_row.get("artifactRequired") is False,
        "architecture-boundary row must not require an artifact")
require(architecture_row.get("artifactValidators", []) == [],
        "architecture-boundary row must not declare artifact validators")
require(architecture_row.get("allowedNaReason") is None,
        "architecture-boundary row must not allow N/A")
require(architecture_row.get("active") is True,
        "architecture-boundary row is inactive")
require(architecture_row.get("automationReady") is True,
        "architecture-boundary row is not automation-ready")
require(architecture_row.get("declaredBuildException") is False,
        "architecture-boundary row declared an unexpected build exception")

device_perf = next((row for row in rows if row.get("id") == "performance.device.critical"), None)
require(device_perf is not None, "major plan omitted device performance boundary")
require(device_perf.get("required") is True and device_perf.get("automationReady") is True,
        "automated device performance boundary is not release-required and ready")
require(device_perf.get("command") == [
    "dart", "run", "integration_test/scripts/run_1to1_device_real.dart",
    "--scenario", "performance.device.critical",
], "device performance boundary does not use the build-free prebuilt adapter")

required_fields = (
    "id", "owner", "proofBoundary", "assertions", "lane", "modes",
    "families", "required", "command", "buildProfile", "resources",
)
for row in rows:
    missing_fields = [field for field in required_fields if field not in row]
    require(not missing_fields,
            f"{row.get('id', '<unknown>')} lacks typed fields: {missing_fields}")
PY

# The skill is an adapter, not a second planner. A fake repository makes this
# assertion deterministic and proves the exact argument vector without running
# any app or device work.
fake_repo="$tmp_dir/repo"
adapter_log="$tmp_dir/adapter.args"
mkdir -p "$fake_repo/scripts"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "$@" >"${SIMS_ADAPTER_LOG:?}"' \
  >"$fake_repo/scripts/run_test_gates.sh"
chmod +x "$fake_repo/scripts/run_test_gates.sh"

SIMS_ADAPTER_LOG="$adapter_log" "$ADAPTER" --repo "$fake_repo" \
  --list --simultaneous --format json >/dev/null 2>"$tmp_dir/adapter.stderr"
expected_adapter_args="$({
  printf '%s\n' sims major --list --simultaneous --format json
})"
[ "$(cat "$adapter_log")" = "$expected_adapter_args" ] ||
  fail 'the sims skill adapter did not delegate the exact default-major plan flags'

printf 'PASS: sims major plan/default/dedup/adapter contract\n'
