#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
import re
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

print("PASS: intro E2E accept window contract")
PY
