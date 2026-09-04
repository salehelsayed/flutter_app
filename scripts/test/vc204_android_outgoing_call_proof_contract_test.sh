#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTRUMENTATION="$ROOT_DIR/android/app/src/vc204AndroidTest/kotlin/com/mknoon/app/call/Vc204AndroidCallLifecycleInstrumentationTest.kt"
RUNNER="$ROOT_DIR/scripts/run_vc204_android_call_lifecycle_e2e.sh"

python3 - "$INSTRUMENTATION" "$RUNNER" <<'PY'
from pathlib import Path
import sys


instrumentation_path = Path(sys.argv[1])
runner_path = Path(sys.argv[2])
instrumentation = instrumentation_path.read_text(encoding="utf-8")
runner = runner_path.read_text(encoding="utf-8")


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def function_body(source: str, signature: str) -> str:
    if source.count(signature) != 1:
        fail(f"expected exactly one {signature}")
    start = source.index(signature)
    open_brace = source.find("{", start)
    if open_brace < 0:
        fail(f"missing body for {signature}")
    depth = 0
    for index in range(open_brace, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[start : index + 1]
    fail(f"unterminated body for {signature}")
    raise AssertionError("unreachable")


method_name = "testVc204OutgoingAuthenticatedCoreTelecomLifecycle"
body = function_body(instrumentation, f"fun {method_name}()")

required_instrumentation = (
    "runtime.registerOutgoingAuthenticated(",
    "PendingNativeCallDirection.OUTGOING",
    "coreTelecomDirection(descriptor.direction)",
    "CallAttributesCompat.DIRECTION_OUTGOING",
    "runtime.controller.activateAudio(",
    "runtime.controller.endFromDart(",
    "activeCallNotificationCount() == 0",
    "isCallForegroundServiceRunning()",
    "events.count { it.type == PendingNativeCallEventType.END_REQUESTED }",
    "outgoing terminal acknowledgement leaves no descriptor",
)
for required in required_instrumentation:
    if required not in body:
        fail(f"outgoing device proof omits {required!r}")

if "runtime.controller.registerOutgoing(" in body or "runtime.present(" in body:
    fail("outgoing device proof bypasses the authenticated production registration seam")
if body.count("runtime.registerOutgoingAuthenticated(") != 2:
    fail("outgoing device proof must register once and retry once through the authenticated seam")

registered = body.index("runtime.registerOutgoingAuthenticated(")
direction = body.index("coreTelecomDirection(descriptor.direction)")
activated = body.index("runtime.controller.activateAudio(")
ended = body.index("runtime.controller.endFromDart(")
deleted = body.index(
    "outgoing terminal acknowledgement leaves no descriptor",
)
if not registered < direction < activated < ended < deleted:
    fail("outgoing proof does not preserve register -> direction -> audio -> cleanup -> delete order")

helper = function_body(instrumentation, "private fun isCallForegroundServiceRunning()")
for required in (
    "ActivityManager::class.java",
    "getRunningServices",
    "MknoonCallForegroundService::class.java.name",
):
    if required not in helper:
        fail(f"foreground-service residue helper omits {required!r}")

if "const val SLOT_OUTGOING" not in instrumentation:
    fail("outgoing device proof has no independent deterministic fixture slot")

phase_declaration = (
    'readonly PHASE_OUTGOING="testVc204OutgoingAuthenticatedCoreTelecomLifecycle"'
)
phase_invocation = 'run_phase "$PHASE_OUTGOING" outgoing-authenticated-core-telecom'
summary_claim = "printf 'outgoingAuthenticatedCoreTelecomLifecycle=PASS\\n'"
residue_claim = "printf 'outgoingCleanupResidue=NONE\\n'"
for required in (phase_declaration, phase_invocation, summary_claim, residue_claim):
    if runner.count(required) != 1:
        fail(f"runner must contain exactly one {required!r}")

phase_block = "\n".join(
    (
        "reset_app_data",
        "set_notification_allowed",
        "set_microphone_granted",
        phase_invocation,
    ),
)
if phase_block not in runner:
    fail("outgoing phase is not independently reset with notification and microphone grants")

print("PASS: VC2-04 outgoing device proof is authenticated, Core-Telecom-bound, and residue-free")
PY

bash -n "$RUNNER"
bash -n "$0"
