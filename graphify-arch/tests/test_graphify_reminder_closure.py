#!/usr/bin/env python3
"""Focused tests for consolidated post-edit Graphify affected coverage."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "graphify-arch" / "codex_graphify_reminder.py"
SPEC = importlib.util.spec_from_file_location("graphify_reminder_closure", TOOL)
assert SPEC and SPEC.loader
REMINDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REMINDER)


class GraphifyReminderClosureTest(unittest.TestCase):
    def payload(
        self,
        tool_use_id: str,
        tool_name: str,
        tool_input,
        *,
        session_id: str = "impact-session",
        agent_id: str | None = None,
    ) -> dict:
        result = {
            "session_id": session_id,
            "cwd": str(ROOT),
            "hook_event_name": "PreToolUse",
            "tool_name": tool_name,
            "tool_input": tool_input,
            "tool_use_id": tool_use_id,
        }
        if agent_id:
            result["agent_id"] = agent_id
        return result

    def patch(self, tool_use_id: str, *paths: str, agent_id: str | None = None):
        body = ["*** Begin Patch"]
        for path in paths:
            body.extend((f"*** Update File: {path}", "@@", "+change"))
        body.append("*** End Patch")
        return self.payload(
            tool_use_id,
            "apply_patch",
            "\n".join(body),
            agent_id=agent_id,
        )

    def command(self, tool_use_id: str, command: str, *, agent_id: str | None = None):
        return self.payload(
            tool_use_id,
            "exec_command",
            {"cmd": command},
            agent_id=agent_id,
        )

    def impact_state(self, state_dir: Path, session_id: str = "impact-session"):
        digest = REMINDER.context._session_digest(session_id)
        return json.loads(
            (state_dir / f"{digest}-affected.json").read_text(encoding="utf-8")
        )

    def ledger(self, state_dir: Path):
        return [
            json.loads(line)
            for line in (state_dir / "events.jsonl").read_text(encoding="utf-8").splitlines()
        ]

    def record_affected_success(
        self,
        usage_path: Path,
        paths: list[str],
        *,
        timestamp: str,
        session_id: str = "impact-session",
    ) -> None:
        question_sha256 = hashlib.sha256(
            "\n".join(sorted(paths)).encode()
        ).hexdigest()[:16]
        row = {
            "operation": "affected",
            "question_sha256": question_sha256,
            "ts": timestamp,
            "codex_thread_sha256": REMINDER.context._session_digest(session_id),
        }
        with usage_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(row) + "\n")

    def test_tracks_only_app_owned_patch_paths_in_session_shared_state(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory)
            patch = self.patch(
                "patch-1",
                "lib/a.dart",
                "test/a_test.dart",
                "android/app/src/main/kotlin/App.kt",
                "scripts/run_test_gates.sh",
                "tool/helper.dart",
                "pubspec.yaml",
                "graphify-arch/codex_graphify_reminder.py",
                "codex-memory/memory.py",
                ".codex/hooks.json",
                "docs/plans/example.md",
                "AGENTS.md",
                agent_id="worker-one",
            )
            self.assertIsNone(REMINDER.process_hook(patch, state_dir=state_dir))

            nested_patch = self.payload(
                "patch-2",
                "functions.exec",
                'const patch = "*** Begin Patch\\n*** Update File: '
                'lib/b.dart\\n@@\\n+change\\n*** End Patch"; '
                "await tools.apply_patch(patch);",
                agent_id="worker-two",
            )
            self.assertIsNone(
                REMINDER.process_hook(nested_patch, state_dir=state_dir)
            )

            state = self.impact_state(state_dir)
            self.assertEqual(
                state["pending_paths"],
                [
                    "android/app/src/main/kotlin/App.kt",
                    "lib/a.dart",
                    "lib/b.dart",
                    "scripts/run_test_gates.sh",
                    "test/a_test.dart",
                    "tool/helper.dart",
                ],
            )
            digest = REMINDER.context._session_digest("impact-session")
            self.assertEqual(
                stat.S_IMODE((state_dir / f"{digest}-affected.json").stat().st_mode),
                0o600,
            )
            rows = self.ledger(state_dir)
            self.assertEqual(
                [row["pending_affected_count"] for row in rows], [5, 6]
            )
            serialized = "\n".join(json.dumps(row) for row in rows)
            self.assertNotIn("lib/a.dart", serialized)
            self.assertNotIn("App.kt", serialized)
            self.assertNotIn("docs/plans", serialized)

    def test_affected_clears_only_named_paths_and_later_edits_readd_them(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory)
            usage_path = state_dir / "usage.jsonl"
            self.assertIsNone(
                REMINDER.process_hook(
                    self.patch("patch-1", "lib/a.dart", "lib/b.dart"),
                    state_dir=state_dir,
                    usage_path=usage_path,
                    timestamp="2026-08-23T01:00:00+00:00",
                )
            )
            self.assertIsNone(
                REMINDER.process_hook(
                    self.command(
                        "affected-a",
                        "python3 graphify-arch/tdd_context.py affected "
                        "lib/a.dart --budget 600",
                    ),
                    state_dir=state_dir,
                    usage_path=usage_path,
                    timestamp="2026-08-23T01:00:01+00:00",
                )
            )
            self.assertEqual(
                self.impact_state(state_dir)["pending_paths"],
                ["lib/a.dart", "lib/b.dart"],
            )
            self.record_affected_success(
                usage_path,
                ["lib/a.dart"],
                timestamp="2026-08-23T01:00:02+00:00",
            )
            self.assertIsNone(
                REMINDER.process_hook(
                    self.payload("confirm-a", "web.search", {"q": "noop"}),
                    state_dir=state_dir,
                    usage_path=usage_path,
                    timestamp="2026-08-23T01:00:03+00:00",
                )
            )
            self.assertEqual(
                self.impact_state(state_dir)["pending_paths"], ["lib/b.dart"]
            )

            self.assertIsNone(
                REMINDER.process_hook(
                    self.patch("patch-2", "lib/a.dart"),
                    state_dir=state_dir,
                    usage_path=usage_path,
                    timestamp="2026-08-23T01:00:04+00:00",
                )
            )
            self.assertEqual(
                self.impact_state(state_dir)["pending_paths"],
                ["lib/a.dart", "lib/b.dart"],
            )
            self.assertIsNone(
                REMINDER.process_hook(
                    self.command(
                        "affected-both",
                        "python3 graphify-arch/tdd_context.py affected "
                        "lib/b.dart lib/a.dart --budget 600",
                    ),
                    state_dir=state_dir,
                    usage_path=usage_path,
                    timestamp="2026-08-23T01:00:05+00:00",
                )
            )
            self.assertEqual(
                self.impact_state(state_dir)["pending_paths"],
                ["lib/a.dart", "lib/b.dart"],
            )
            self.record_affected_success(
                usage_path,
                ["lib/a.dart", "lib/b.dart"],
                timestamp="2026-08-23T01:00:06+00:00",
            )
            self.assertIsNone(
                REMINDER.process_hook(
                    self.payload("confirm-both", "web.search", {"q": "noop"}),
                    state_dir=state_dir,
                    usage_path=usage_path,
                    timestamp="2026-08-23T01:00:07+00:00",
                )
            )
            self.assertEqual(self.impact_state(state_dir)["pending_paths"], [])
            coverage = [
                row for row in self.ledger(state_dir) if row["event"] == "affected_coverage"
            ]
            self.assertEqual(
                [row["covered_file_count"] for row in coverage], [1, 2]
            )
            attempts = [
                row for row in self.ledger(state_dir) if row["event"] == "affected_attempt"
            ]
            self.assertTrue(all(not row["confirmed"] for row in attempts))

    def test_closure_blocks_until_complete_affected_recovery(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory)
            usage_path = state_dir / "usage.jsonl"
            self.assertIsNone(
                REMINDER.process_hook(
                    self.patch(
                        "patch-child", "lib/a.dart", "test/a_test.dart", agent_id="child"
                    ),
                    state_dir=state_dir,
                )
            )
            focused = self.command(
                "focused", "flutter test test/a_test.dart --plain-name exact"
            )
            self.assertIsNone(REMINDER.process_hook(focused, state_dir=state_dir))

            commit = self.command("commit", "git commit -m implementation")
            denied = REMINDER.process_hook(commit, state_dir=state_dir)
            self.assertEqual(
                denied["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            reason = denied["hookSpecificOutput"]["permissionDecisionReason"]
            self.assertIn(
                "python3 graphify-arch/tdd_context.py affected lib/a.dart "
                "test/a_test.dart --budget 600",
                reason,
            )
            self.assertEqual(
                REMINDER.process_hook(commit, state_dir=state_dir), denied
            )

            query = self.command(
                "query",
                "python3 graphify-arch/tdd_context.py query a.dart "
                "--profile general --budget 600",
            )
            self.assertIsNone(REMINDER.process_hook(query, state_dir=state_dir))
            self.assertEqual(
                REMINDER.process_hook(commit, state_dir=state_dir), denied
            )

            partial = self.command(
                "partial",
                "python3 graphify-arch/tdd_context.py affected lib/a.dart --budget 600",
            )
            self.assertIsNone(
                REMINDER.process_hook(
                    partial,
                    state_dir=state_dir,
                    usage_path=usage_path,
                    timestamp="2026-08-23T02:00:00+00:00",
                )
            )
            self.record_affected_success(
                usage_path,
                ["lib/a.dart"],
                timestamp="2026-08-23T02:00:01+00:00",
            )
            partial_denial = REMINDER.process_hook(
                commit,
                state_dir=state_dir,
                usage_path=usage_path,
                timestamp="2026-08-23T02:00:02+00:00",
            )
            self.assertEqual(
                partial_denial["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            self.assertIn("test/a_test.dart --budget 600", json.dumps(partial_denial))
            self.assertNotIn("lib/a.dart test/a_test.dart", json.dumps(partial_denial))

            complete = self.command(
                "complete",
                "python3 graphify-arch/tdd_context.py affected "
                "test/a_test.dart --budget 600",
            )
            self.assertIsNone(
                REMINDER.process_hook(
                    complete,
                    state_dir=state_dir,
                    usage_path=usage_path,
                    timestamp="2026-08-23T02:00:03+00:00",
                )
            )
            self.record_affected_success(
                usage_path,
                ["test/a_test.dart"],
                timestamp="2026-08-23T02:00:04+00:00",
            )
            self.assertIsNone(
                REMINDER.process_hook(
                    commit,
                    state_dir=state_dir,
                    usage_path=usage_path,
                    timestamp="2026-08-23T02:00:05+00:00",
                )
            )

            self.assertIsNone(
                REMINDER.process_hook(
                    self.patch("patch-later", "lib/a.dart"), state_dir=state_dir
                )
            )
            gate = self.command("gate", "./scripts/run_test_gates.sh 1to1")
            self.assertEqual(
                REMINDER.process_hook(gate, state_dir=state_dir)[
                    "hookSpecificOutput"
                ]["permissionDecision"],
                "deny",
            )

            state = self.impact_state(state_dir)
            self.assertEqual(state["closure_blocks"], 2)
            self.assertEqual(state["recoveries"], 1)
            rows = self.ledger(state_dir)
            closure_rows = [row for row in rows if row["event"] == "closure"]
            self.assertEqual(
                [row["blocked"] for row in closure_rows],
                [True, True, False, True],
            )
            recovered = [
                row
                for row in rows
                if row["event"] == "affected_coverage" and row["recovered"]
            ]
            self.assertEqual(len(recovered), 1)

    def test_explicit_env_bypass_releases_exact_retry_without_clearing_debt(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory)
            self.assertIsNone(
                REMINDER.process_hook(
                    self.patch("patch", "lib/a.dart"), state_dir=state_dir
                )
            )
            commit = self.command("commit", "git commit -m implementation")
            denied = REMINDER.process_hook(commit, state_dir=state_dir)
            self.assertEqual(
                denied["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            with mock.patch.dict(
                os.environ, {"GRAPHIFY_CODEX_AFFECTED_ENFORCE": "0"}
            ):
                self.assertIsNone(
                    REMINDER.process_hook(commit, state_dir=state_dir)
                )
            self.assertEqual(
                self.impact_state(state_dir)["pending_paths"], ["lib/a.dart"]
            )

    def test_failed_or_wrong_session_affected_attempt_keeps_closure_debt(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory)
            usage_path = state_dir / "usage.jsonl"
            self.assertIsNone(
                REMINDER.process_hook(
                    self.patch("patch", "lib/a.dart"),
                    state_dir=state_dir,
                    usage_path=usage_path,
                    timestamp="2026-08-23T03:00:00+00:00",
                )
            )
            attempt = self.command(
                "affected",
                "python3 graphify-arch/tdd_context.py affected "
                "lib/a.dart --budget 600",
            )
            self.assertIsNone(
                REMINDER.process_hook(
                    attempt,
                    state_dir=state_dir,
                    usage_path=usage_path,
                    timestamp="2026-08-23T03:00:01+00:00",
                )
            )
            self.record_affected_success(
                usage_path,
                ["lib/a.dart"],
                timestamp="2026-08-23T03:00:02+00:00",
                session_id="different-session",
            )

            denied = REMINDER.process_hook(
                self.command("commit", "git commit -m implementation"),
                state_dir=state_dir,
                usage_path=usage_path,
                timestamp="2026-08-23T03:00:03+00:00",
            )
            self.assertEqual(
                denied["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            impact = self.impact_state(state_dir)
            self.assertEqual(impact["pending_paths"], ["lib/a.dart"])
            self.assertEqual(impact["awaiting_confirmations"], [])
            rows = self.ledger(state_dir)
            self.assertFalse(
                any(row["event"] == "affected_coverage" for row in rows)
            )
            misses = [
                row for row in rows if row["event"] == "affected_confirmation"
            ]
            self.assertEqual(len(misses), 1)
            self.assertFalse(misses[0]["confirmed"])

    def test_closure_classifier_keeps_focused_iterations_open(self):
        focused = [
            "flutter test test/a_test.dart",
            "dart test test/a_test.dart",
            "pytest graphify-arch/tests/test_x.py::Case::test_one",
            "python3 -m pytest graphify-arch/tests/test_x.py -k exact",
            "python3 -m unittest package.Case.test_one",
            "go test ./pkg -run TestOne",
        ]
        broad = [
            "git -C . commit -m result",
            "./scripts/run_host_test_gates.sh feature-host-all",
            "bash scripts/run_test_gates.sh 1to1",
            "flutter test",
            "pytest",
            "python3 -m unittest discover",
            "go test ./...",
        ]
        self.assertTrue(all(REMINDER._closure_kind([command]) is None for command in focused))
        self.assertTrue(all(REMINDER._closure_kind([command]) for command in broad))


if __name__ == "__main__":
    unittest.main()
