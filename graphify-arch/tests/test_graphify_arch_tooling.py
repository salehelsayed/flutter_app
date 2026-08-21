#!/usr/bin/env python3
"""Focused regression tests for compact Graphify/TDD integration."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "graphify-arch" / "tdd_context.py"
SPEC = importlib.util.spec_from_file_location("graphify_tdd_context", TOOL)
assert SPEC and SPEC.loader
CONTEXT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTEXT)

GRAPHIFY_PYTHON = Path.home() / ".local/share/uv/tools/graphifyy/bin/python"


class GraphifyArchToolingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        os.environ["GRAPHIFY_CONTEXT_LOG"] = "0"
        cls.graph = CONTEXT._load_graph()
        cls.overlay = CONTEXT.load_overlay()

    def _ranked_tests(self, question: str, profile: str = "tdd"):
        seeds, _, terms = self.graph.seeds(question, profile)
        files, _ = self.graph.context_files(seeds, terms)
        primary = [
            source
            for nid in seeds
            if (source := CONTEXT._source_file(self.graph.nodes[nid]))
            and CONTEXT._category(source)
            not in {"test", "integration_test", "scripts", "unknown"}
        ]
        production = [
            path
            for path in files
            if CONTEXT._category(path)
            not in {"test", "integration_test", "scripts", "unknown"}
        ]
        return CONTEXT._tests_for_files(
            self.overlay, primary, production[:10], files, terms
        )

    def test_overlay_models_named_tests_and_gate_membership(self):
        self.assertEqual(self.overlay["version"], CONTEXT.OVERLAY_VERSION)
        record = self.overlay["test_files"][
            "test/features/conversation/application/delete_message_use_case_test.dart"
        ]
        self.assertGreater(len(record["tests"]), 0)
        self.assertIn(
            "lib/features/conversation/application/delete_message_use_case.dart",
            record["imports"],
        )
        self.assertIn("ONE_TO_ONE_TESTS", {gate["name"] for gate in record["gates"]})
        self.assertIn(
            "ONE_TO_ONE_HOST_TESTS", {gate["name"] for gate in record["gates"]}
        )

    def test_direct_production_test_outranks_shared_model_tests(self):
        ranked = self._ranked_tests("deleteMessageForMe cleanup attachments")
        self.assertEqual(
            ranked[0]["path"],
            "test/features/conversation/application/delete_message_use_case_test.dart",
        )
        ranked = self._ranked_tests(
            "GroupMediaIntegrityPolicy group media delete", profile="review"
        )
        self.assertEqual(
            ranked[0]["path"], "test/core/media/group_media_integrity_policy_test.dart"
        )

    def test_compact_tdd_output_contains_direct_proof_and_gate(self):
        lines, meta = CONTEXT._compact_lines(
            self.graph,
            self.overlay,
            "deleteMessageForMe cleanup attachments",
            "tdd",
        )
        output = CONTEXT._bounded(lines, 900)
        self.assertEqual(meta["confidence"], "anchored")
        self.assertIn("delete_message_use_case_test.dart", output)
        self.assertIn("ONE_TO_ONE_TESTS", output)
        self.assertLessEqual(len(output), 900 * 3 + 120)

    def test_review_budget_keeps_counterexample_section(self):
        lines, _ = CONTEXT._compact_lines(
            self.graph,
            self.overlay,
            "GroupMediaIntegrityPolicy group media delete",
            "review",
        )
        output = CONTEXT._bounded(lines, 800)
        self.assertIn("Caller/bypass candidates:", output)
        self.assertIn("group_media_integrity_policy_test.dart", output)

    def test_code_level_anchors_carry_community_membership(self):
        lines, meta = CONTEXT._compact_lines(
            self.graph,
            self.overlay,
            "deleteMessageForMe cleanup attachments",
            "tdd",
        )
        self.assertEqual(meta["confidence"], "anchored")
        anchor_lines = [line for line in lines if line.startswith("- ") and " [" in line]
        self.assertTrue(
            any(" ∈ " in line for line in anchor_lines),
            f"no anchor carries a community label: {anchor_lines[:3]}",
        )

    def test_component_level_renders_labeled_map_with_relationships(self):
        lines, meta = CONTEXT._component_lines(
            self.graph, "group media download pipeline", "general", 500
        )
        output = CONTEXT._bounded(lines, 500)
        self.assertTrue(lines[0].startswith("Component context: level=component"))
        self.assertEqual(meta["level"], "component")
        component_lines = [line for line in lines if line.startswith("- [")]
        self.assertGreaterEqual(len(component_lines), 3)
        self.assertLessEqual(len(component_lines), 5)
        for line in component_lines:
            self.assertNotRegex(line, r"\[\d+\] Community \d+")
        self.assertIn("Component relationships:", output)
        self.assertLessEqual(len(output), 500 * 3 + 120)

    def test_component_level_budget_scales_component_cap(self):
        _, meta_small = CONTEXT._component_lines(
            self.graph, "group media download pipeline", "general", 400
        )
        _, meta_large = CONTEXT._component_lines(
            self.graph, "group media download pipeline", "general", 800
        )
        self.assertLessEqual(meta_small["components"], 4)
        self.assertGreaterEqual(meta_large["components"], meta_small["components"])

    def test_component_level_reports_no_match_for_gibberish(self):
        lines, meta = CONTEXT._component_lines(
            self.graph, "zzqqxxblorp frobnicate", "general", 500
        )
        self.assertEqual(meta["components"], 0)
        self.assertIn("No matching components.", lines[1])

    def test_miss_path_suggests_close_symbol_for_typo(self):
        # 'deleteMesageForMe' (missing 's') matches nothing as a substring,
        # so seeds() misses — the did-you-mean pass must surface the real
        # symbol with its source location instead of dead-ending.
        lines, meta = CONTEXT._compact_lines(
            self.graph, self.overlay, "deleteMesageForMe", "general"
        )
        self.assertEqual(meta["confidence"], "none")
        self.assertGreaterEqual(meta["suggestions"], 1)
        self.assertIn("Did you mean:", lines)
        suggestion_text = "\n".join(lines)
        self.assertIn("deleteMessageForMe", suggestion_text)
        self.assertIn("close to 'deletemesageforme'", suggestion_text)

    def test_broad_query_with_typo_symbol_gets_suggestions(self):
        # A typo'd symbol next to a common word lands in confidence=broad
        # (the common word substring-matches), NOT the total-miss path.
        # The did-you-mean pass must still fire for the missed
        # symbol-shaped term.
        lines, meta = CONTEXT._compact_lines(
            self.graph, self.overlay,
            "GroupConversatoinWired construction", "general",
        )
        self.assertEqual(meta["confidence"], "broad")
        self.assertGreaterEqual(meta["suggestions"], 1)
        text = "\n".join(lines)
        self.assertIn("Did you mean:", text)
        self.assertIn("GroupConversationWired", text)

    def test_anchored_query_reports_zero_suggestions(self):
        _, meta = CONTEXT._compact_lines(
            self.graph, self.overlay,
            "deleteMessageForMe cleanup attachments", "tdd",
        )
        self.assertEqual(meta["suggestions"], 0)

    def test_miss_path_stays_quiet_for_true_gibberish(self):
        lines, meta = CONTEXT._compact_lines(
            self.graph, self.overlay, "zzqqxwyblorp", "general"
        )
        self.assertEqual(meta["confidence"], "none")
        self.assertEqual(meta["suggestions"], 0)
        self.assertNotIn("Did you mean:", lines)

    def test_affected_adds_direct_tests(self):
        tests = self.overlay["production_to_tests"][
            "lib/features/conversation/application/delete_message_use_case.dart"
        ]
        self.assertIn(
            "test/features/conversation/application/delete_message_use_case_test.dart",
            tests,
        )

    def test_query_stats_report_budget_utilization_without_question_text(self):
        lines = CONTEXT._stats_summary(
            [
                {
                    "profile": "tdd",
                    "question_sha256": "abc",
                    "budget": 700,
                    "result_chars": 1400,
                    "confidence": "anchored",
                },
                {
                    "profile": "review",
                    "question_sha256": "def",
                    "budget": 800,
                    "result_chars": 1600,
                    "confidence": "broad",
                },
            ]
        )
        output = "\n".join(lines)
        self.assertIn("avg 375 estimated tokens", output)
        self.assertIn("query anchoring: 1/2", output)
        self.assertNotIn("abc", output)

    def test_full_repository_path_is_an_exact_anchor(self):
        seeds, confidence, _ = self.graph.seeds(
            "lib/features/conversation/application/delete_message_use_case.dart",
            "general",
        )
        self.assertEqual(confidence, "anchored")
        self.assertTrue(seeds)
        self.assertEqual(
            CONTEXT._source_file(self.graph.nodes[seeds[0]]),
            "lib/features/conversation/application/delete_message_use_case.dart",
        )

    def test_scope_route_uses_full_graph_for_architecture_miss(self):
        route = CONTEXT._scope_route(
            "inspect graphify-arch/tdd_context.py logging",
            "broad",
            arch_sources={"lib/main.dart"},
            full_sources={"lib/main.dart", "graphify-arch/tdd_context.py"},
        )
        self.assertEqual(route["route"], "full_graph_fallback")
        self.assertEqual(
            route["fallback_targets"], ["graphify-arch/tdd_context.py"]
        )

    def test_scope_route_requires_direct_document_handoff(self):
        route = CONTEXT._scope_route(
            "implement Test-Flight-Improv/392-notification-plan.md with "
            "lib/features/push/application/request_push_permission_use_case.dart",
            "anchored",
            arch_sources={
                "lib/features/push/application/request_push_permission_use_case.dart"
            },
            full_sources={
                "Test-Flight-Improv/392-notification-plan.md",
                "lib/features/push/application/request_push_permission_use_case.dart",
            },
        )
        self.assertEqual(route["route"], "document_handoff")
        self.assertEqual(route["fallback_targets"], [])
        self.assertEqual(
            route["document_targets"],
            ["Test-Flight-Improv/392-notification-plan.md"],
        )

    def test_document_handoff_skips_even_anchored_architecture_context(self):
        lines, meta = CONTEXT._compact_lines(
            self.graph,
            self.overlay,
            "UI-23-notification/notification-spec.md requestPushPermission",
            "tdd",
        )
        output = "\n".join(lines)
        self.assertEqual(meta["route"], "document_handoff")
        self.assertEqual(meta["selected_files"], [])
        self.assertIn("plans/specifications are intentionally outside", output)
        self.assertIn("document-to-code handoff", output)
        self.assertNotIn("Production/related files:", output)

    def test_document_handoff_does_not_load_or_refresh_a_graph(self):
        output = io.StringIO()
        with (
            mock.patch.object(
                CONTEXT,
                "_load_graph",
                side_effect=AssertionError("document query loaded the code graph"),
            ),
            mock.patch.object(
                CONTEXT,
                "_ensure_fresh",
                side_effect=AssertionError("document query refreshed the code graph"),
            ),
            redirect_stdout(output),
        ):
            CONTEXT.query(
                "implement plans/example-spec.md with requestPushPermission",
                profile="tdd",
                budget=300,
                ensure_fresh=True,
            )
        self.assertIn("fingerprint=not_queried", output.getvalue())

    def test_scope_route_uses_raw_search_for_unindexed_existing_path(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            target = root / "tools" / "new_probe.py"
            target.parent.mkdir()
            target.write_text("print('probe')\n")
            route = CONTEXT._scope_route(
                "inspect tools/new_probe.py",
                "broad",
                arch_sources=set(),
                full_sources=set(),
                root=root,
            )
        self.assertEqual(route["route"], "raw_search_fallback")
        self.assertEqual(route["route_reason"], "exact_target_not_indexed")

    def test_scope_fallback_skips_unrelated_broad_shortlist(self):
        routed = {
            "route": "full_graph_fallback",
            "route_reason": "exact_target_outside_architecture_graph",
            "fallback_targets": ["graphify-arch/tdd_context.py"],
        }
        with mock.patch.object(CONTEXT, "_scope_route", return_value=routed):
            lines, meta = CONTEXT._compact_lines(
                self.graph,
                self.overlay,
                "graphify-arch/tdd_context.py logging",
                "general",
            )
        output = "\n".join(lines)
        self.assertEqual(meta["route"], "full_graph_fallback")
        self.assertEqual(meta["selected_files"], [])
        self.assertIn("Architecture context skipped", output)
        self.assertNotIn("Production/related files:", output)

    def test_full_graph_fallback_prints_measured_followup_command(self):
        output = io.StringIO()
        with redirect_stdout(output):
            CONTEXT.query(
                "graphify-arch/tdd_context.py logging",
                profile="general",
                budget=300,
                ensure_fresh=False,
            )
        rendered = output.getvalue()
        self.assertIn("evidence_digest=", rendered)
        self.assertRegex(
            rendered,
            r"tdd_context\.py native .* --follows [0-9a-f]{16}",
        )
        self.assertEqual(rendered.count("Next:"), 1)
        self.assertIn("Architecture context skipped", rendered)

    def test_usage_record_hashes_codex_ids_and_tracks_refinement(self):
        with mock.patch.dict(
            os.environ,
            {
                "CODEX_SESSION_ID": "raw-session-secret",
                "CODEX_THREAD_ID": "raw-thread-secret",
            },
            clear=False,
        ):
            record = CONTEXT._usage_record(
                operation="query",
                profile="general",
                input_text="private question text",
                budget=600,
                result="answer\n... truncated at ~600 tokens",
                meta={
                    "confidence": "anchored",
                    "route": "architecture",
                    "selected_files": ["lib/main.dart"],
                    "proof_files": ["test/main_test.dart"],
                    "fallback_targets": [],
                },
                duration_ms=12.5,
                query_id="query-2",
                query_stage="refinement",
                refinement_of="query-1",
            )
        serialized = json.dumps(record)
        self.assertEqual(record["schema_version"], 3)
        self.assertEqual(record["refinement_of"], "query-1")
        self.assertRegex(record["evidence_digest"], r"^[0-9a-f]{16}$")
        self.assertTrue(record["truncated"])
        self.assertEqual(record["selected_file_count"], 1)
        self.assertEqual(record["proof_file_count"], 1)
        self.assertNotIn("private question text", serialized)
        self.assertNotIn("raw-session-secret", serialized)
        self.assertNotIn("raw-thread-secret", serialized)
        self.assertIn("codex_session_sha256", record)
        self.assertIn("codex_thread_sha256", record)

    def test_refinement_cli_requires_parent_query_id(self):
        proc = subprocess.run(
            [
                sys.executable,
                str(TOOL),
                "query",
                "deleteMessageForMe",
                "--stage",
                "refinement",
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            env={**os.environ, "GRAPHIFY_CONTEXT_LOG": "0"},
            timeout=30,
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("requires --refines", proc.stderr)

    def test_exec_parser_counts_bare_quoted_and_direct_cmd_keys(self):
        tool_input = """
const results = await Promise.all([
  tools.exec_command({cmd: "python3 graphify-arch/tdd_context.py query one"}),
  tools.exec_command({"cmd": "python3 graphify-arch/tdd_context.py query two"}),
  tools.exec_command({'cmd': 'rg ExactSymbol lib'})
]);
"""
        commands = CONTEXT._exec_commands_from_tool_input(tool_input)
        self.assertEqual(len(commands), 3)
        self.assertIn("query two", commands[1])
        self.assertEqual(
            CONTEXT._exec_commands_from_tool_input(json.dumps({"cmd": "rg Foo lib"})),
            ["rg Foo lib"],
        )
        nested_command = "jq 'contains(\"{\\\"cmd\\\":\\\"fake\\\"}\")' log.jsonl"
        nested_text = (
            "const r = await tools.exec_command("
            + json.dumps({"cmd": nested_command})
            + ");"
        )
        self.assertEqual(len(CONTEXT._exec_commands_from_tool_input(nested_text)), 1)
        self.assertEqual(
            CONTEXT._helper_invocations(
                "rg 'graphify-arch/tdd_context.py query' graphify-arch"
            ),
            [],
        )
        chained = (
            "/usr/bin/time -p python3 graphify-arch/tdd_context.py query "
            "'plans/example.md' --budget 300 && "
            "python3 graphify-arch/tdd_context.py query ExactSymbol --budget 600"
        )
        self.assertEqual(
            [operation for operation, _ in CONTEXT._helper_invocations(chained)],
            ["query", "query"],
        )
        patch_input = (
            'const patch = "*** Begin Patch\\n*** Update File: '
            'lib/example.dart\\n@@\\n"; await tools.apply_patch(patch);'
        )
        self.assertEqual(
            CONTEXT._patch_paths_from_tool_input(patch_input),
            {"lib/example.dart"},
        )

    def test_usage_join_prefers_thread_over_process_session(self):
        with tempfile.TemporaryDirectory() as temp:
            usage = Path(temp) / "usage.jsonl"
            rows = [
                {
                    "query_id": "thread-a",
                    "codex_session_sha256": "process",
                    "codex_thread_sha256": "wanted",
                },
                {
                    "query_id": "thread-b",
                    "codex_session_sha256": "process",
                    "codex_thread_sha256": "different",
                },
            ]
            usage.write_text("".join(json.dumps(row) + "\n" for row in rows))
            matched = CONTEXT._usage_records_for_session("wanted", path=usage)
        self.assertEqual([row["query_id"] for row in matched], ["thread-a"])

    def test_native_wrapper_logs_linked_full_graph_followup(self):
        captured: list[dict[str, object]] = []
        output = io.StringIO()
        completed = subprocess.CompletedProcess(
            args=["graphify"],
            returncode=0,
            stdout="NODE ExampleService\n",
            stderr="",
        )
        with (
            mock.patch.object(CONTEXT.subprocess, "run", return_value=completed),
            mock.patch.object(CONTEXT, "_append_usage", side_effect=captured.append),
            redirect_stdout(output),
        ):
            CONTEXT.native(
                "lib/example.dart",
                budget=800,
                follows="fallback-query",
            )
        self.assertEqual(captured[0]["operation"], "native_query")
        self.assertEqual(captured[0]["followup_of"], "fallback-query")
        self.assertEqual(captured[0]["graph_scope"], "full")
        self.assertIn("follows=fallback-query", output.getvalue())

    def test_stats_report_routes_refinements_and_truncation(self):
        rows = [
            {
                "operation": "query",
                "profile": "general",
                "result_chars": 800,
                "budget": 600,
                "confidence": "broad",
                "route": "architecture",
                "query_stage": "initial",
                "truncated": False,
            },
            {
                "operation": "query",
                "profile": "general",
                "result_chars": 900,
                "budget": 600,
                "confidence": "anchored",
                "route": "architecture",
                "query_stage": "refinement",
                "refinement_of": "query-1",
                "truncated": True,
            },
            {
                "operation": "affected",
                "profile": "affected",
                "result_chars": 200,
                "budget": 600,
                "confidence": "not_applicable",
                "route": "architecture",
                "query_stage": "impact",
                "truncated": False,
            },
        ]
        output = "\n".join(CONTEXT._stats_summary(rows))
        self.assertIn("operations: affected=1, query=2", output)
        self.assertIn("first-query anchoring: 0/1", output)
        self.assertIn("refinement anchoring: 1/1", output)
        self.assertIn("declared_links=1", output)
        self.assertIn("truncation: 1/3", output)

    def test_session_audit_separates_documents_and_enforces_code_handoff(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "plans").mkdir()
            (root / "lib").mkdir()
            (root / "test").mkdir()
            (root / "plans" / "implementation-plan.md").write_text(
                "# Plan\n\nUse `ExampleService`.\n"
            )
            (root / "lib" / "example.dart").write_text(
                "class ExampleService {}\n"
            )
            (root / "test" / "example_test.dart").write_text(
                "void main() {}\n"
            )
            rollout = root / "rollout.jsonl"

            def tool_row(command: str, index: int) -> dict[str, object]:
                tool_input = (
                    "const r = await tools.exec_command({cmd:"
                    + json.dumps(command)
                    + "}); text(r.output);"
                )
                return {
                    "type": "response_item",
                    "payload": {
                        "type": "custom_tool_call",
                        "name": "exec",
                        "call_id": f"call-{index}",
                        "input": tool_input,
                    },
                }

            rows = [
                {"type": "session_meta", "payload": {"id": "audit-session"}},
                tool_row("sed -n '1,20p' plans/implementation-plan.md", 1),
                tool_row(
                    "python3 graphify-arch/tdd_context.py query "
                    "\"ExampleService lib/example.dart\" --profile tdd --budget 700",
                    2,
                ),
                tool_row(
                    "sed -n '1,20p' lib/example.dart && "
                    "cat test/example_test.dart",
                    3,
                ),
            ]
            rollout.write_text("".join(json.dumps(row) + "\n" for row in rows))
            audit = CONTEXT._session_audit(rollout, root=root)

            self.assertEqual(audit["tool_calls"], 3)
            self.assertEqual(audit["document_read_calls"], 1)
            self.assertEqual(audit["whole_document_file_count"], 1)
            self.assertEqual(audit["code_browse_calls"], 1)
            self.assertEqual(audit["whole_code_read_calls"], 1)
            self.assertEqual(audit["whole_code_file_count"], 2)
            self.assertEqual(audit["compact_code_queries"], 1)
            self.assertEqual(audit["compact_document_queries"], 0)
            self.assertEqual(audit["handoff_status"], "pass")

            failing_rows = [
                rows[0],
                rows[1],
                tool_row(
                    "python3 graphify-arch/tdd_context.py query "
                    "\"plans/implementation-plan.md ExampleService\" "
                    "--profile tdd --budget 700",
                    2,
                ),
                rows[3],
            ]
            rollout.write_text(
                "".join(json.dumps(row) + "\n" for row in failing_rows)
            )
            failing = CONTEXT._session_audit(rollout, root=root)
            self.assertEqual(failing["compact_code_queries"], 0)
            self.assertEqual(failing["compact_document_queries"], 1)
            self.assertEqual(failing["handoff_status"], "fail")

    def test_session_audit_joins_canonical_usage_and_scores_workflow(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "lib").mkdir()
            (root / "lib" / "example.dart").write_text("class Example {}\n")
            rollout = root / "rollout.jsonl"
            session_id = "workflow-session"
            session_sha = CONTEXT._session_digest(session_id)

            def tool_row(
                command: str,
                index: int,
                timestamp: str | None = None,
            ) -> dict[str, object]:
                row: dict[str, object] = {
                    "type": "response_item",
                    "payload": {
                        "type": "custom_tool_call",
                        "name": "exec",
                        "call_id": f"call-{index}",
                        "input": (
                            "const r = await tools.exec_command({\"cmd\":"
                            + json.dumps(command)
                            + "}); text(r.output);"
                        ),
                    },
                }
                if timestamp:
                    row["timestamp"] = timestamp
                return row

            rows = [
                {"type": "session_meta", "payload": {"id": session_id}},
                tool_row(
                    "python3 graphify-arch/tdd_context.py query LegacyAnchor",
                    0,
                    "2025-01-01T00:00:00Z",
                ),
                tool_row(
                    "python3 graphify-arch/tdd_context.py checkpoint "
                    "--session current --new-branch",
                    1,
                    "2026-01-01T00:01:00Z",
                ),
                tool_row(
                    "python3 graphify-arch/tdd_context.py query Example "
                    "--profile general --budget 600",
                    2,
                    "2026-01-01T00:02:00Z",
                ),
                tool_row(
                    "sed -n '1,1p' lib/example.dart",
                    3,
                    "2026-01-01T00:03:00Z",
                ),
                {
                    "type": "response_item",
                    "payload": {
                        "type": "custom_tool_call_output",
                        "call_id": "call-3",
                        "output": [{"type": "input_text", "text": "class Example {}\n"}],
                    },
                },
            ]
            rollout.write_text("".join(json.dumps(row) + "\n" for row in rows))
            usage = root / "usage.jsonl"
            usage.write_text(
                json.dumps(
                    {
                        "schema_version": 3,
                        "ts": "2026-01-01T00:00:00+00:00",
                        "operation": "query",
                        "query_id": "query-1",
                        "query_stage": "initial",
                        "confidence": "anchored",
                        "route": "architecture",
                        "result_tokens_estimate": 100,
                        "codex_session_sha256": session_sha,
                        "evidence_digest": "abc123",
                    }
                )
                + "\n"
            )
            audit = CONTEXT._session_audit(
                rollout,
                root=root,
                usage_path=usage,
            )
            self.assertEqual(audit["compact_code_queries"], 1)
            self.assertEqual(audit["compact_code_queries_parsed"], 1)
            self.assertEqual(audit["compact_code_queries_executed"], 2)
            self.assertEqual(audit["compact_code_queries_pretelemetry"], 1)
            self.assertEqual(audit["branch_graphify_first"], 1)
            self.assertEqual(audit["raw_browse_current_gap"], 1)
            self.assertGreater(audit["code_output_tokens_estimate"], 0)
            lines, passed = CONTEXT._workflow_benchmark_lines(
                audit,
                max_raw_gap=20,
            )
            self.assertTrue(passed, "\n".join(lines))
            self.assertIn("telemetry parity", "\n".join(lines))

    def test_checkpoint_requests_query_for_new_branch_or_read_ceiling(self):
        audit = {
            "session_sha256": "session",
            "code_browse_calls": 25,
            "compact_code_queries": 1,
            "compact_code_queries_parsed": 1,
            "canonical_usage_linked": True,
            "raw_browse_current_gap": 20,
            "raw_browse_p95_gap": 20,
            "broad_refined_queries": 1,
            "broad_initial_queries": 1,
            "fallback_followups": 1,
            "fallback_queries": 1,
            "code_change_calls": 0,
            "affected_after_latest_change": True,
            "latest_query_id": "query-1",
            "latest_evidence_digest": "digest-1",
        }
        output = "\n".join(
            CONTEXT._checkpoint_lines(
                audit,
                max_raw_gap=20,
                new_branch=True,
            )
        )
        self.assertIn("REQUERY_REQUIRED", output)
        self.assertIn("new investigation branch", output)
        self.assertIn("20-call ceiling", output)

    def test_precision_benchmark_fixture_passes(self):
        output = io.StringIO()
        with redirect_stdout(output):
            passed = CONTEXT.benchmark()
        self.assertTrue(passed, output.getvalue())
        self.assertIn("expected-source hit", output.getvalue())
        self.assertIn("truncation:", output.getvalue())

    def test_refresh_contract_is_incremental_by_default(self):
        text = (ROOT / "graphify-arch" / "refresh_arch_graph.sh").read_text()
        self.assertIn("refresh_graph.py", text)
        self.assertIn("tdd_context.py build", text)
        self.assertNotIn("rm -rf", text)
        self.assertNotIn("graphify extract", text)
        self.assertIn("--incremental|--full|--rebuild", text)

        merger = (ROOT / "graphify-arch" / "refresh_graph.py").read_text()
        self.assertIn("detect_incremental", merger)
        self.assertIn("_load_existing_without", merger)
        self.assertIn("os.replace", merger)

    def test_incremental_merger_replaces_complete_changed_source(self):
        script = """
import json, sys
sys.path.insert(0, 'graphify-arch')
from refresh_graph import _without_sources
data = {
  'nodes': [
    {'id': 'keep', 'source_file': 'lib/keep.dart'},
    {'id': 'old', 'source_file': 'lib/changed.dart'},
  ],
  'links': [
    {'source': 'keep', 'target': 'old', 'source_file': 'lib/keep.dart'},
    {'source': 'keep', 'target': 'keep', 'source_file': 'lib/changed.dart'},
  ],
  'hyperedges': [],
}
print(json.dumps(_without_sources(data, {'lib/changed.dart'})))
"""
        proc = subprocess.run(
            [str(GRAPHIFY_PYTHON), "-c", script],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
            check=True,
        )
        result = json.loads(proc.stdout)
        self.assertEqual([node["id"] for node in result["nodes"]], ["keep"])
        self.assertEqual(result["edges"], [])

    def test_fast_path_skill_is_compact_and_uses_context_tool(self):
        skill = ROOT / ".agents" / "skills" / "graphify" / "SKILL.md"
        text = skill.read_text()
        self.assertLess(len(text), 10_000)
        self.assertIn("tdd_context.py query", text)
        self.assertNotIn("close_agent", text)

    def test_tdd_skills_share_compact_profiles(self):
        home = Path.home() / ".codex" / "skills"
        plan = (home / "tdd-plan" / "SKILL.md").read_text()
        review = (home / "tdd-review" / "SKILL.md").read_text()
        execution = (
            home / "implementation-execution-qa-orchestrator" / "SKILL.md"
        ).read_text()
        self.assertIn("--profile tdd --budget 700", plan)
        self.assertIn("Graph Grounding Snapshot", plan)
        self.assertIn("--profile review --budget 800", review)
        self.assertIn("tdd_context.py affected", execution)

    def test_local_hook_configuration_is_enforcing(self):
        codex = json.loads((ROOT / ".codex" / "hooks.json").read_text())
        self.assertEqual(codex, {"hooks": {}})
        claude = json.loads((ROOT / ".claude" / "settings.json").read_text())
        self.assertNotIn("permissions", claude)
        commands = [
            hook["command"]
            for entry in claude["hooks"]["PreToolUse"]
            for hook in entry["hooks"]
        ]
        self.assertTrue(commands)
        # Enforcing since 2026-08-17: bypass mode doubled raw-grep volume
        # with no query uptake, so it must stay out of the hook commands.
        self.assertTrue(
            all("GRAPHIFY_LOCAL_DEV_BYPASS" not in command for command in commands)
        )

        # The bypass MODE itself must keep working (explicit env only):
        # telemetry without any deny/advisory payload.
        payloads = [
            {
                "tool_name": "Bash",
                "tool_input": {"command": 'graphify query "unbudgeted local query"'},
            },
            {
                "tool_name": "Read",
                "tool_input": {"file_path": str(ROOT / "lib" / "main.dart")},
            },
        ]
        for payload in payloads:
            proc = subprocess.run(
                ["python3", str(ROOT / ".claude" / "hooks" / "graphify_grep_gate.py")],
                input=json.dumps(payload),
                capture_output=True,
                text=True,
                env={**os.environ, "GRAPHIFY_LOCAL_DEV_BYPASS": "1"},
                timeout=30,
            )
            self.assertEqual(proc.returncode, 0)
            self.assertEqual(proc.stdout.strip(), "")


if __name__ == "__main__":
    unittest.main()
