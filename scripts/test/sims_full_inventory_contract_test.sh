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

./scripts/run_test_gates.sh reliability-sim all --list \
  >"$tmp_dir/legacy-all.txt"
./scripts/run_reliability_simulations.sh all --continue-on-failure \
  --exclude-path integration_test/voice_message_e2e_test.dart \
  --exclude-path integration_test/scripts/run_group_multi_party_device_real.dart \
  --exclude-path integration_test/scripts/run_group_reaction_notification_device.dart \
  --exclude-path integration_test/scripts/run_intro_accept_notification_android.dart \
  --exclude-path integration_test/scripts/run_media_delivery_ui_smoke.dart \
  --list >"$tmp_dir/legacy-owned.txt"
./scripts/run_test_gates.sh sims full --list --format json \
  >"$tmp_dir/full.json"

python3 - "$tmp_dir/legacy-all.txt" "$tmp_dir/legacy-owned.txt" \
  "$tmp_dir/full.json" <<'PY'
import json
import re
import sys

all_text, owned_text = [open(path, encoding="utf-8").read() for path in sys.argv[1:3]]
with open(sys.argv[3], encoding="utf-8") as stream:
    full = json.load(stream)

def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")

def planned_count(text):
    return sum(1 for line in text.splitlines() if re.match(r"^\s+\d+\. ", line))

excluded = {
    "integration_test/voice_message_e2e_test.dart": "android.voice_recorder_native_smoke",
    "integration_test/scripts/run_group_multi_party_device_real.dart": "groups.multi_party_release",
    "integration_test/scripts/run_group_reaction_notification_device.dart": "groups.reaction_notification_campaign",
    "integration_test/scripts/run_intro_accept_notification_android.dart": "intro.accept_notification_campaign",
}
duplicates = {
    "integration_test/scripts/run_media_delivery_ui_smoke.dart":
        "integration_test/scripts/run_media_stable_id_smoke.dart",
}

all_count = planned_count(all_text)
owned_count = planned_count(owned_text)
require(all_count > 0, "legacy cleaned inventory is empty")
expected_owned = all_count - len(excluded) - len(duplicates)
require(owned_count == expected_owned,
        f"typed exclusions and dedup changed {all_count} rows to {owned_count}, expected {expected_owned}")

rows = {row["id"]: row for row in full["rows"]}
aggregate = rows.get("reliability.full.cleaned_legacy")
require(aggregate is not None, "typed full omitted the cleaned legacy aggregate")
require(aggregate.get("resources") == [{"name": "unknown", "access": "exclusive"}],
        "unmigrated legacy aggregate is not fail-closed/exclusive")
command = aggregate.get("command", [])
for path, typed_id in excluded.items():
    require(path in all_text, f"baseline legacy inventory omitted expected path {path}")
    require(path not in owned_text, f"legacy aggregate still duplicates {path}")
    require(typed_id in rows, f"typed full does not replace excluded {path} with {typed_id}")
    require(path in command, f"aggregate command does not declare exclusion {path}")
for duplicate, canonical in duplicates.items():
    require(duplicate in all_text, f"baseline legacy inventory omitted duplicate {duplicate}")
    require(canonical in all_text, f"baseline legacy inventory omitted canonical owner {canonical}")
    require(duplicate not in owned_text, f"legacy aggregate still runs duplicate {duplicate}")
    require(canonical in owned_text, f"legacy aggregate removed canonical owner {canonical}")
    require(duplicate in command, f"aggregate command does not declare duplicate exclusion {duplicate}")
PY

printf 'PASS: typed full preserves the cleaned legacy inventory without duplicate owners\n'
