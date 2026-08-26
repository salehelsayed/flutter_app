#!/usr/bin/env python3
"""Output-boundary tests for Graphify and Codex-memory shadow hooks."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:  # pragma: no cover - import invariant.
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


GRAPHIFY = _load_module(
    "observe_only_graphify_reminder",
    ROOT / "graphify-arch" / "codex_graphify_reminder.py",
)
MEMORY = _load_module(
    "observe_only_memory_reminder",
    ROOT / "codex-memory" / "codex_memory_reminder.py",
)


class ObserveOnlyHookTest(unittest.TestCase):
    _RAW_SENTINEL = "RAW-PAYLOAD-MUST-NOT-LEAK"

    def _invoke_main(self, module, *, flag: str, flag_value: str, result: dict):
        payload = {
            "hook_event_name": "PreToolUse",
            "session_id": self._RAW_SENTINEL,
            "tool_name": "exec_command",
            "tool_input": {"cmd": f"read {self._RAW_SENTINEL}"},
        }
        calls: list[dict] = []

        def fake_process_hook(received):
            calls.append(received)
            return result

        stdout = io.StringIO()
        stderr = io.StringIO()
        reminder_flag = (
            "GRAPHIFY_CODEX_REMINDER"
            if module is GRAPHIFY
            else "CODEX_MEMORY_REMINDER"
        )
        debug_flag = (
            "GRAPHIFY_CODEX_REMINDER_DEBUG"
            if module is GRAPHIFY
            else "CODEX_MEMORY_REMINDER_DEBUG"
        )
        with mock.patch.dict(
            os.environ,
            {flag: flag_value, reminder_flag: "1", debug_flag: "0"},
            clear=False,
        ), mock.patch.object(
            module, "process_hook", side_effect=fake_process_hook
        ), mock.patch.object(
            sys, "stdin", io.StringIO(json.dumps(payload))
        ), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            exit_code = module.main()
        return exit_code, calls, stdout.getvalue(), stderr.getvalue(), payload

    def test_observe_only_suppresses_context_and_denial_after_processing(self):
        modules = (
            (GRAPHIFY, "GRAPHIFY_CODEX_OBSERVE_ONLY"),
            (MEMORY, "CODEX_MEMORY_OBSERVE_ONLY"),
        )
        results = (
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "additionalContext": self._RAW_SENTINEL,
                }
            },
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": self._RAW_SENTINEL,
                }
            },
        )
        for module, flag in modules:
            for result in results:
                with self.subTest(module=module.__name__, result=result):
                    exit_code, calls, stdout, stderr, payload = self._invoke_main(
                        module, flag=flag, flag_value="1", result=result
                    )
                    self.assertEqual(exit_code, 0)
                    self.assertEqual(calls, [payload])
                    self.assertEqual(stdout, "")
                    self.assertEqual(stderr, "")
                    self.assertNotIn(self._RAW_SENTINEL, stdout + stderr)

    def test_false_values_preserve_normal_hook_output(self):
        modules = (
            (GRAPHIFY, "GRAPHIFY_CODEX_OBSERVE_ONLY"),
            (MEMORY, "CODEX_MEMORY_OBSERVE_ONLY"),
        )
        result = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "additionalContext": "normal output",
            }
        }
        for module, flag in modules:
            for false_value in ("0", "false", "no", "off"):
                with self.subTest(module=module.__name__, false_value=false_value):
                    exit_code, calls, stdout, stderr, payload = self._invoke_main(
                        module,
                        flag=flag,
                        flag_value=false_value,
                        result=result,
                    )
                    self.assertEqual(exit_code, 0)
                    self.assertEqual(calls, [payload])
                    self.assertEqual(json.loads(stdout), result)
                    self.assertEqual(stderr, "")

    def test_observe_only_telemetry_is_labeled_without_raw_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            graphify_events = temp / "graphify.jsonl"
            with mock.patch.dict(
                os.environ, {"GRAPHIFY_CODEX_OBSERVE_ONLY": "1"}, clear=False
            ):
                GRAPHIFY._append_event(graphify_events, {"event": "unit"})
            graphify_event = json.loads(graphify_events.read_text(encoding="utf-8"))

            memory_events = temp / "memory.jsonl"
            with mock.patch.dict(
                os.environ, {"CODEX_MEMORY_OBSERVE_ONLY": "1"}, clear=False
            ):
                MEMORY._append_events(
                    SimpleNamespace(hook_events_path=memory_events),
                    [{"event": "unit"}],
                    timestamp="2026-08-23T00:00:00+00:00",
                    session_sha256="session-hash",
                    agent_sha256="agent-hash",
                    tool_use_sha256="tool-hash",
                    identity_fields={},
                    batch_sha256=None,
                )
            memory_event = json.loads(memory_events.read_text(encoding="utf-8"))

        self.assertIs(graphify_event["observe_only"], True)
        self.assertIs(memory_event["observe_only"], True)
        self.assertNotIn(self._RAW_SENTINEL, json.dumps(graphify_event))
        self.assertNotIn(self._RAW_SENTINEL, json.dumps(memory_event))


if __name__ == "__main__":
    unittest.main()
