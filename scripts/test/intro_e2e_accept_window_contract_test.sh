#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

source = Path("smoke_test_friends.sh").read_text()


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def function_body(name: str, next_name: str) -> str:
    pattern = rf"^{name}\(\) \{{(?P<body>.*?)^{next_name}\(\) \{{"
    match = re.search(pattern, source, flags=re.MULTILINE | re.DOTALL)
    if not match:
        fail(f"could not extract {name}")
    return match.group("body")


def device_config(body: str, device: str) -> str:
    pattern = rf'write_config "\${device}" "\$\(cat <<EOF\n(?P<json>.*?)\nEOF\n\)"'
    match = re.search(pattern, body, flags=re.DOTALL)
    if not match:
        fail(f"could not extract config for {device}")
    return match.group("json")


def require_accept_window(
    body: str,
    *,
    device: str,
    scenario: str,
    min_poll_cycles: int,
    min_idle_cycles_after_seen: int,
) -> None:
    config = device_config(body, device)
    def require(pattern: str, description: str) -> re.Match[str]:
        match = re.search(pattern, config)
        if not match:
            fail(f"{scenario} {device}: missing {description}")
        return match

    require(r'"introduction_action": "accept_all"', "accept_all action")
    poll_cycles = int(
        require(r'"poll_cycles":\s*(\d+)', "poll_cycles").group(1)
    )
    if poll_cycles < min_poll_cycles:
        fail(
            f"{scenario} {device}: poll_cycles={poll_cycles}, "
            f"expected >= {min_poll_cycles}"
        )

    idle_cycles = int(
        require(
            r'"idle_cycles_after_seen":\s*(\d+)',
            "idle_cycles_after_seen",
        ).group(1)
    )
    if idle_cycles < min_idle_cycles_after_seen:
        fail(
            f"{scenario} {device}: idle_cycles_after_seen={idle_cycles}, "
            f"expected >= {min_idle_cycles_after_seen}"
        )


partial_recovery = function_body(
    "run_partial_fanout_recovery_phase",
    "run_partition_divergent_accept_phase",
)
partition_divergent = function_body(
    "run_partition_divergent_accept_phase",
    "run_partition_heal_phase",
)

require_accept_window(
    partial_recovery,
    device="DEVICE_C",
    scenario="partial fan-out recovery",
    min_poll_cycles=90,
    min_idle_cycles_after_seen=12,
)
for device in ("DEVICE_B", "DEVICE_C"):
    require_accept_window(
        partition_divergent,
        device=device,
        scenario="partition divergent accepts",
        min_poll_cycles=90,
        min_idle_cycles_after_seen=12,
    )

split_brain = function_body(
    "scenario_split_brain_mutual_acceptance_recovery",
    "scenario_folded_duplicate",
).rsplit("}", 1)[0]
# Execute the scenario with device operations replaced by trace-only seams.
# Accepting must act on the original invitation, not race a second send.
trace = subprocess.check_output([
    "bash", "-c", '''
prepare_devices() { :; }
run_handshake_phase() { :; }
run_intro_phase() { echo send; }
run_intro_action_phase() { echo "accept:$2:$3"; }
run_split_brain_second_accept_phase() { echo second_accept; }
assert_split_brain_mid_state() { echo assert_split; }
run_split_brain_recovery_phase() { echo recover; }
run_settle_phase() { :; }
assert_pair_state() { echo "assert_final:$1:$2"; }
''' + split_brain,
], text=True).splitlines()
actions = [line for line in trace if line and not line.startswith("===")]
expected = ["send", "accept:accept_all:none", "second_accept", "assert_split",
            "recover", "assert_final:mutual_accepted:yes"]
if actions != expected:
    fail(f"split-brain fixture must preserve one introduction: {actions}")

folded_send = function_body(
    "run_folded_duplicate_send_phase", "run_folded_duplicate_accept_phase",
)
for device in ("DEVICE_B", "DEVICE_C"):
    config = json.loads(device_config(folded_send, device))
    messages = config.get("expected_chat_messages", [])
    if (len(messages) != 2 or
            {m.get("contactPeerId") for m in messages} != {"$PEER_A", "$PEER_D"} or
            any(m.get("transport") != "system" for m in messages)):
        fail(f"folded send {device}: snapshot must wait for both introducers")
    if config.get("chat_poll_cycles") != config["poll_cycles"]:
        fail(f"folded send {device}: readiness must use the existing poll budget")

print("PASS: intro E2E acceptance, sequencing and folded-readiness contracts")
PY
