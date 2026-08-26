#!/usr/bin/env python3
"""Focused audit regressions for document reads and affected-path debt."""

from __future__ import annotations

import importlib.util
import hashlib
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "graphify-arch" / "tdd_context.py"
SPEC = importlib.util.spec_from_file_location("tdd_context_metrics", TOOL)
assert SPEC and SPEC.loader
CONTEXT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTEXT)


def _meta(session_id: str = "metrics-session") -> dict[str, object]:
    return {"type": "session_meta", "payload": {"id": session_id}}


def _exec(command: str, index: int) -> dict[str, object]:
    return {
        "type": "response_item",
        "payload": {
            "type": "custom_tool_call",
            "name": "exec",
            "call_id": f"call-{index}",
            "input": json.dumps({"cmd": command}),
        },
    }


def _patch(paths: list[str], index: int) -> dict[str, object]:
    patch = "*** Begin Patch\n" + "".join(
        f"*** Update File: {path}\n@@\n-old\n+new\n" for path in paths
    ) + "*** End Patch\n"
    return {
        "type": "response_item",
        "payload": {
            "type": "custom_tool_call",
            "name": "apply_patch",
            "call_id": f"patch-{index}",
            "input": patch,
        },
    }


def _output(index: int, text: str) -> dict[str, object]:
    return {
        "type": "response_item",
        "payload": {
            "type": "custom_tool_call_output",
            "call_id": f"call-{index}",
            "output": [{"type": "input_text", "text": text}],
        },
    }


class TddContextMetricsTest(unittest.TestCase):
    def _audit(
        self,
        root: Path,
        rows: list[dict[str, object]],
        *,
        usage_rows: list[dict[str, object]] | None = None,
        reminder_rows: list[dict[str, object]] | None = None,
    ):
        rollout = root / "rollout.jsonl"
        rollout.write_text(
            "".join(json.dumps(row) + "\n" for row in [_meta(), *rows]),
            encoding="utf-8",
        )
        usage_path = root / "usage.jsonl"
        if usage_rows is not None:
            usage_path.write_text(
                "".join(json.dumps(row) + "\n" for row in usage_rows),
                encoding="utf-8",
            )
        reminder_path = root / "reminders.jsonl"
        if reminder_rows is not None:
            reminder_path.write_text(
                "".join(json.dumps(row) + "\n" for row in reminder_rows),
                encoding="utf-8",
            )
        return CONTEXT._session_audit(
            rollout,
            root=root,
            usage_path=usage_path,
            reminder_path=reminder_path,
        )

    def _app_root(self, root: Path) -> None:
        (root / "lib").mkdir(exist_ok=True)
        for name in ("a.dart", "b.dart", "c.dart"):
            (root / "lib" / name).write_text(f"class {name[0].upper()} {{}}\n")

    def test_document_metrics_separate_unique_first_pass_revisits_and_truncation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "plans").mkdir()
            plan = root / "plans" / "implementation-plan.md"
            plan.write_text(
                "".join(f"line {number}\n" for number in range(1, 101)),
                encoding="utf-8",
            )
            truncated = (
                "Warning: truncated output (original token count: 12000)\n"
                "Total output lines: 40\n\n"
                + "".join(f"line {number}\n" for number in range(1, 41))
            )
            rows = [
                _exec("sed -n '1,100p' plans/implementation-plan.md", 1),
                _output(1, truncated),
                _exec("sed -n '1,60p' plans/implementation-plan.md", 2),
                _output(2, "".join(f"line {n}\n" for n in range(1, 61))),
                _exec("sed -n '61,100p' plans/implementation-plan.md", 3),
                _output(3, "".join(f"line {n}\n" for n in range(61, 101))),
                _exec("sed -n '10,20p' plans/implementation-plan.md", 4),
                _output(4, "".join(f"line {n}\n" for n in range(10, 21))),
                _exec("cat plans/implementation-plan.md", 5),
                _output(5, plan.read_text(encoding="utf-8")),
            ]
            audit = self._audit(root, rows)

            self.assertEqual(audit["document_read_calls"], 5)
            self.assertEqual(audit["document_read_target_count"], 5)
            self.assertEqual(audit["document_unique_file_count"], 1)
            self.assertEqual(audit["document_first_pass_read_calls"], 2)
            self.assertEqual(audit["document_first_pass_lines"], 100)
            self.assertEqual(audit["covered_document_file_count"], 1)
            self.assertEqual(audit["document_targeted_revisit_calls"], 1)
            self.assertEqual(audit["document_redundant_read_calls"], 1)
            self.assertEqual(audit["document_overlap_lines"], 111)
            self.assertEqual(audit["document_truncated_read_calls"], 1)
            self.assertGreater(
                audit["document_truncation_waste_tokens_estimate"], 0
            )
            self.assertGreater(
                audit["document_truncation_dropped_tokens_estimate"], 0
            )
            self.assertEqual(audit["whole_document_read_calls"], 1)

            output = "\n".join(CONTEXT._session_audit_lines(audit))
            self.assertIn("unique=1; read-calls=5; read-targets=5", output)
            self.assertIn("targeted-revisits=1", output)
            self.assertIn("document truncation: 1 calls", output)

    def test_combined_affected_clears_only_the_named_pending_set(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._app_root(root)
            audit = self._audit(
                root,
                [
                    _patch(["lib/a.dart", "lib/b.dart"], 1),
                    _exec(
                        "python3 graphify-arch/tdd_context.py affected "
                        "lib/a.dart \\\n+lib/b.dart --budget 600",
                        2,
                    ),
                    _output(2, "Exit code: 0\nAffected context\n"),
                ],
            )

            self.assertEqual(audit["code_change_path_occurrences"], 2)
            self.assertEqual(audit["affected_coverage_status"], "full")
            self.assertEqual(audit["affected_pending_path_count"], 0)
            self.assertEqual(audit["affected_full_coverage_calls"], 1)
            self.assertTrue(audit["affected_after_latest_change"])

    def test_partial_and_unrelated_affected_leave_exact_path_debt(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._app_root(root)
            audit = self._audit(
                root,
                [
                    _patch(["lib/a.dart", "lib/b.dart"], 1),
                    _exec(
                        "python3 graphify-arch/tdd_context.py affected lib/c.dart",
                        2,
                    ),
                    _output(2, "Exit code: 0\nAffected context\n"),
                    _exec(
                        "python3 graphify-arch/tdd_context.py affected lib/a.dart",
                        3,
                    ),
                    _output(3, "Exit code: 0\nAffected context\n"),
                ],
            )

            self.assertEqual(audit["affected_coverage_status"], "partial")
            self.assertEqual(audit["affected_pending_paths"], ["lib/b.dart"])
            self.assertEqual(audit["affected_partial_coverage_calls"], 1)
            self.assertEqual(audit["affected_unrelated_calls"], 1)
            self.assertFalse(audit["affected_after_latest_change"])

    def test_edit_after_affected_readds_path_and_non_app_changes_are_na(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._app_root(root)
            audit = self._audit(
                root,
                [
                    _patch(["lib/a.dart"], 1),
                    _exec(
                        "python3 graphify-arch/tdd_context.py affected lib/a.dart",
                        2,
                    ),
                    _output(2, "Exit code: 0\nAffected context\n"),
                    _patch(["lib/a.dart"], 3),
                ],
            )
            self.assertEqual(audit["affected_coverage_status"], "partial")
            self.assertEqual(audit["affected_pending_paths"], ["lib/a.dart"])
            self.assertEqual(audit["code_change_path_occurrences"], 2)

            (root / "plans").mkdir()
            document_only = self._audit(
                root,
                [_patch(["plans/implementation-plan.md"], 1)],
            )
            self.assertEqual(document_only["code_change_calls"], 0)
            self.assertEqual(
                document_only["affected_coverage_status"], "not_applicable"
            )

            tooling_only = self._audit(
                root,
                [_patch(["graphify-arch/tdd_context.py"], 1)],
            )
            self.assertEqual(tooling_only["code_change_calls"], 0)
            self.assertEqual(
                tooling_only["affected_coverage_status"], "not_applicable"
            )

    def test_active_affected_debt_is_pending_but_closure_assessment_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._app_root(root)
            audit = self._audit(root, [_patch(["lib/a.dart"], 1)])

            active_lines, active_passed = CONTEXT._workflow_benchmark_lines(
                audit,
                max_raw_gap=10,
            )
            self.assertTrue(active_passed)
            self.assertIn(
                "PENDING post-edit affected",
                "\n".join(active_lines),
            )

            closure_lines, closure_passed = CONTEXT._workflow_benchmark_lines(
                audit,
                max_raw_gap=10,
                enforce_closure=True,
            )
            self.assertFalse(closure_passed)
            self.assertIn(
                "FAIL post-edit affected",
                "\n".join(closure_lines),
            )
            parser = CONTEXT._parser()
            parsed = parser.parse_args(["workflow-benchmark", "--closure"])
            self.assertTrue(parsed.closure)

    def test_failed_affected_call_does_not_clear_pending_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._app_root(root)
            audit = self._audit(
                root,
                [
                    _patch(["lib/a.dart"], 1),
                    _exec(
                        "python3 graphify-arch/tdd_context.py affected lib/a.dart",
                        2,
                    ),
                    _output(2, "Exit code: 1\nGraph load failed\n"),
                ],
            )

            self.assertEqual(audit["affected_successful_calls"], 0)
            self.assertEqual(audit["affected_failed_calls"], 1)
            self.assertEqual(audit["affected_pending_paths"], ["lib/a.dart"])
            self.assertEqual(audit["affected_coverage_status"], "none")
            _, closure_passed = CONTEXT._workflow_benchmark_lines(
                audit,
                max_raw_gap=10,
                enforce_closure=True,
            )
            self.assertFalse(closure_passed)

    def test_canonical_affected_usage_proves_success_without_exit_status(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._app_root(root)
            session_sha = CONTEXT._session_digest("metrics-session")
            path_digest = hashlib.sha256(b"lib/a.dart").hexdigest()[:16]
            audit = self._audit(
                root,
                [
                    _patch(["lib/a.dart"], 1),
                    _exec(
                        "python3 graphify-arch/tdd_context.py affected lib/a.dart",
                        2,
                    ),
                    _output(2, "Affected context\n"),
                ],
                usage_rows=[
                    {
                        "operation": "affected",
                        "question_sha256": path_digest,
                        "codex_session_sha256": session_sha,
                    }
                ],
            )

            self.assertEqual(audit["affected_successful_calls"], 1)
            self.assertEqual(audit["affected_pending_path_count"], 0)
            self.assertEqual(audit["affected_coverage_status"], "full")

    def test_hook_metrics_report_affected_closure_block_and_recovery(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            session_sha = CONTEXT._session_digest("metrics-session")
            base = {
                "schema_version": 1,
                "session_sha256": session_sha,
                "agent_sha256": "root",
            }
            audit = self._audit(
                root,
                [],
                reminder_rows=[
                    {
                        **base,
                        "event": "closure",
                        "blocked": True,
                        "gate": "affected_closure",
                        "pending_affected_count": 2,
                        "closure_blocks": 1,
                        "recoveries": 0,
                    },
                    {
                        **base,
                        "event": "affected_coverage",
                        "confirmed_attempt_count": 1,
                        "pending_affected_count": 0,
                        "recovered": True,
                        "recoveries": 1,
                    },
                    {
                        **base,
                        "event": "closure",
                        "blocked": False,
                        "gate": None,
                        "pending_affected_count": 0,
                        "closure_blocks": 1,
                        "recoveries": 1,
                    },
                ],
            )

            self.assertEqual(audit["hook_blocks"], 1)
            self.assertEqual(audit["hook_affected_closure_attempts"], 2)
            self.assertEqual(audit["hook_affected_closure_blocks"], 1)
            self.assertEqual(audit["hook_affected_closure_passes"], 1)
            self.assertEqual(audit["hook_affected_closure_recoveries"], 1)
            self.assertEqual(audit["hook_affected_coverage_events"], 1)
            self.assertEqual(audit["hook_latest_pending_affected_count"], 0)

            exact = "\n".join(CONTEXT._session_audit_lines(audit))
            self.assertIn("affected-closure=1", exact)
            self.assertIn(
                "affected closure hook: attempts=2; blocks=1 (counter=1); "
                "passes=1; coverage-events=1; recoveries=1; latest-pending=0",
                exact,
            )
            aggregate = "\n".join(CONTEXT._aggregate_session_audit_lines([audit]))
            self.assertIn(
                "affected-closure=attempts=2 blocks=1 recoveries=1 pending=0",
                aggregate,
            )


if __name__ == "__main__":
    unittest.main()
