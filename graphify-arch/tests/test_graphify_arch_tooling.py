#!/usr/bin/env python3
"""Focused regression tests for compact Graphify/TDD integration."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path


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
        self.assertIn("anchored: 1/2", output)
        self.assertNotIn("abc", output)

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
