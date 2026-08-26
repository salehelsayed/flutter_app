#!/usr/bin/env python3

from __future__ import annotations

import contextlib
import importlib
import json
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


CODEX_MEMORY_DIR = Path(__file__).resolve().parents[1]
if str(CODEX_MEMORY_DIR) not in sys.path:
    sys.path.insert(0, str(CODEX_MEMORY_DIR))

import memory  # noqa: E402
import codex_memory_reminder as reminder  # noqa: E402


PLAN_901 = """# 901 - Alpha state guard

Status: execution-ready

## Problem and evidence
- Refuted findings:
  - alpha genesis shortcut is unsafe and refuted.
- A device replay remains open → owner: alpha reliability wave.
"""

PLAN_902 = """# 902 - Beta delivery

Status: implemented host-green

## Final Execution Verdict
**PLAN 902 CLOSED** with focused tests.
"""

SPEC = """# Durable Wake Specification

Status: accepted

Introductory contract.

## Delivery acknowledgement is not notification outcome

A durable delivery acknowledgement proves authenticated persistence. It does
not prove that a local notification outcome was completed, so the generic wake
must remain available.

## Privacy contract

Platform payloads contain no sender, conversation, or message content.
"""


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def fixture_config(root: Path) -> Path:
    config = {
        "schema_version": 1,
        "state": {
            "directory": "state",
            "database": "graph.db",
            "manifest": "manifest.json",
            "telemetry": "usage.jsonl",
            "hook_events": "hook-events.jsonl",
        },
        "freshness": {"auto_refresh": True, "check": "stat"},
        "retrieval": {
            "default_budget": 240,
            "hard_cap": 400,
            "max_seeds": 8,
            "max_hops": 1,
            "edges_per_seed": 2,
            "max_facts_per_document": 2,
            "snippet_chars": 220,
            "fts_candidates": 40,
        },
        "documents": {"max_file_bytes": 100000, "section_chunk_chars": 4000},
        "sources": [
            {
                "name": "plans",
                "adapter": "project_memory_plans",
                "root": "plans",
                "include": ["*-tdd-plan.md"],
                "exclude": [],
                "minimum_files": 2,
                "priority": 100,
            },
            {
                "name": "docs",
                "adapter": "markdown_sections",
                "root": ".",
                "include": ["docs/**/*.md"],
                "exclude": [],
                "minimum_files": 1,
                "priority": 70,
            },
        ],
        "evaluation": {},
    }
    path = root / "codex-memory" / "config.json"
    write(path, json.dumps(config))
    return path


def fixture(root: Path) -> memory.Runtime:
    write(root / "plans" / "901-alpha-state-guard-tdd-plan.md", PLAN_901)
    write(root / "plans" / "902-beta-delivery-tdd-plan.md", PLAN_902)
    write(root / "docs" / "durable-wake-spec.md", SPEC)
    return memory.load_runtime(fixture_config(root), root=root)


class CodexMemoryBuildAndRecallTest(unittest.TestCase):
    def test_build_and_recall_cover_typed_plans_and_markdown_sections(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            refreshed, report, _elapsed = memory.ensure_fresh(runtime)
            self.assertTrue(refreshed)
            self.assertIsNotNone(report)
            self.assertGreater(report.entities, 3)

            plan = memory.recall(runtime, "what is plan 901 alpha state guard status")
            self.assertIn("PLAN 901-alpha-state-guard [execution-ready]", plan.output)
            self.assertIn("plans/901-alpha-state-guard-tdd-plan.md", plan.output)

            document = memory.recall(
                runtime,
                "why is delivery acknowledgement not notification outcome",
                budget=300,
            )
            self.assertIn("Delivery acknowledgement is not notification outcome", document.output)
            self.assertIn("docs/durable-wake-spec.md", document.output)
            self.assertIn("authenticated persistence", document.output)

    def test_graph_contains_only_configured_markdown_and_owns_its_database(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            write(root / "lib" / "ignored.dart", "class MustNotEnterDocumentGraph {}")
            memory.ensure_fresh(runtime)
            connection = sqlite3.connect(runtime.db_path)
            try:
                docs = [row[0] for row in connection.execute("SELECT DISTINCT source_doc FROM entities")]
                body_hits = connection.execute(
                    "SELECT count(*) FROM entities WHERE body LIKE '%MustNotEnterDocumentGraph%'"
                ).fetchone()[0]
            finally:
                connection.close()
            self.assertTrue(all(value.endswith(".md") for value in docs))
            self.assertEqual(body_hits, 0)
            self.assertEqual(runtime.db_path.parent, (root / "state").resolve())

    def test_recall_is_deterministic_and_hard_budget_bounded(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            memory.ensure_fresh(runtime)
            question = "alpha genesis shortcut unsafe refuted owner reliability"
            first = memory.recall(runtime, question, budget=9999)
            second = memory.recall(runtime, question, budget=9999)
            self.assertEqual(first.output, second.output)
            self.assertLessEqual(first.tokens, 400)
            self.assertIn("refuted", first.output.lower())

    def test_multi_plan_anchors_emit_entities_before_relationship_tails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            memory.ensure_fresh(runtime)
            result = memory.recall(runtime, "status plan 901 and plan 902", budget=150)
            self.assertIn("PLAN 901-", result.output)
            self.assertIn("PLAN 902-", result.output)

    def test_honest_miss_does_not_guess(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            memory.ensure_fresh(runtime)
            result = memory.recall(runtime, "zzzqqq utterlynonexistent")
            self.assertFalse(result.hit)
            self.assertEqual(
                result.output,
                "No Codex-memory facts found for: zzzqqq utterlynonexistent",
            )


class CodexMemoryFreshnessTest(unittest.TestCase):
    def test_stat_change_marks_stale_and_refresh_surfaces_new_fact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            memory.ensure_fresh(runtime)
            fresh, reasons, _files, _counts = memory.freshness(runtime)
            self.assertTrue(fresh, reasons)
            path = root / "docs" / "durable-wake-spec.md"
            write(path, SPEC + "\n## Recovery\nQuasar recovery is mandatory.\n")
            fresh, reasons, _files, _counts = memory.freshness(runtime)
            self.assertFalse(fresh)
            self.assertTrue(any(value.startswith("changed:") for value in reasons))
            refreshed, _report, _elapsed = memory.ensure_fresh(runtime)
            self.assertTrue(refreshed)
            self.assertIn("Quasar recovery", memory.recall(runtime, "quasar recovery").output)

    def test_content_audit_catches_same_stat_content_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            memory.ensure_fresh(runtime)
            path = root / "docs" / "durable-wake-spec.md"
            before = path.stat()
            original = path.read_text(encoding="utf-8")
            changed = original.replace("sender", "reader")
            self.assertEqual(len(original), len(changed))
            write(path, changed)
            os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
            stat_fresh, _reasons, _files, _counts = memory.freshness(runtime)
            hash_fresh, hash_reasons, _files, _counts = memory.freshness(
                runtime, verify_content=True
            )
            self.assertTrue(stat_fresh)
            self.assertFalse(hash_fresh)
            self.assertTrue(any(value.startswith("changed:") for value in hash_reasons))

    def test_implementation_change_marks_graph_stale(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            memory.ensure_fresh(runtime)
            with mock.patch.object(memory, "_implementation_sha256", return_value="changed"):
                fresh, reasons, _files, _counts = memory.freshness(runtime)
            self.assertFalse(fresh)
            self.assertIn("implementation", reasons)

    def test_local_config_patches_named_source_and_retrieval(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = fixture_config(root)
            write(
                path.with_name("config.local.json"),
                json.dumps(
                    {
                        "retrieval": {"default_budget": 180},
                        "sources": [{"name": "docs", "priority": 88}],
                    }
                ),
            )
            runtime = memory.load_runtime(path, root=root)
            self.assertEqual(runtime.config["retrieval"]["default_budget"], 180)
            docs = next(row for row in runtime.config["sources"] if row["name"] == "docs")
            self.assertEqual(docs["priority"], 88)
            self.assertEqual(docs["adapter"], "markdown_sections")

    def test_source_floor_fails_loudly(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            (root / "plans" / "902-beta-delivery-tdd-plan.md").unlink()
            with self.assertRaisesRegex(ValueError, "below minimum_files"):
                memory.collect_sources(runtime)


class CodexMemoryTelemetryTest(unittest.TestCase):
    def test_query_telemetry_hashes_question_and_session(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            memory.ensure_fresh(runtime)
            question = "private secret-shaped test question"
            result = memory.recall(runtime, "plan 901")
            with mock.patch.dict(
                os.environ,
                {"CODEX_SESSION_ID": "session-secret", "CODEX_THREAD_ID": "thread-secret"},
                clear=False,
            ):
                memory.log_query(
                    runtime,
                    question,
                    240,
                    result,
                    duration_ms=2.5,
                    refreshed=False,
                    refresh_ms=0,
                )
            raw = runtime.telemetry_path.read_text(encoding="utf-8")
            row = json.loads(raw)
            self.assertNotIn(question, raw)
            self.assertNotIn("session-secret", raw)
            self.assertEqual(row["codex_session_sha256"], memory.session_digest("session-secret"))
            self.assertIn("coverage", row)

    def test_stats_join_query_and_hook_adoption_ledgers(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            digest = memory.session_digest("session-a")
            now = memory.dt.datetime.now(memory.dt.timezone.utc).isoformat()
            memory._append_jsonl(
                runtime.telemetry_path,
                {
                    "ts": now,
                    "codex_session_sha256": digest,
                    "hit": True,
                    "confidence": "focused",
                    "tokens": 120,
                    "coverage": 0.8,
                    "duration_ms": 4,
                    "auto_refreshed": False,
                },
            )
            memory._append_jsonl(
                runtime.hook_events_path,
                {
                    "ts": now,
                    "codex_session_sha256": digest,
                    "event": "document_browse",
                    "grounded": False,
                    "reminder": "initial",
                },
            )
            with mock.patch.dict(os.environ, {"CODEX_SESSION_ID": "session-a"}, clear=False):
                value = memory.stats(runtime, selector="current")
            self.assertEqual(value["queries"], 1)
            self.assertEqual(value["ungrounded_document_browses"], 1)
            self.assertEqual(value["reminders"], 1)


class CodexMemoryReminderTest(unittest.TestCase):
    def payload(self, command: str, *, tool_id: str, root: Path) -> dict[str, object]:
        return {
            "hook_event_name": "PreToolUse",
            "tool_name": "exec_command",
            "tool_input": {"cmd": command},
            "tool_use_id": tool_id,
            "session_id": "hook-session",
            "cwd": str(root),
        }

    def functions_payload(
        self,
        command: str,
        *,
        tool_id: str,
        root: Path,
        max_output_tokens: int | None = None,
    ) -> dict[str, object]:
        pragma = (
            '// @exec: {"max_output_tokens": %d}\n' % max_output_tokens
            if max_output_tokens is not None
            else ""
        )
        encoded = json.dumps(command)
        return {
            "hook_event_name": "PreToolUse",
            "tool_name": "functions.exec",
            "tool_input": (
                pragma
                + 'const r = await tools.exec_command({"cmd": '
                + encoded
                + "}); text(r.output);"
            ),
            "tool_use_id": tool_id,
            "session_id": "hook-session",
            "cwd": str(root),
        }

    def confirm_payload(
        self,
        payload: dict[str, object],
        *,
        runtime: memory.Runtime,
        state_dir: Path,
        response: object | None = None,
    ) -> None:
        batch = reminder._document_reads(
            payload, reminder._commands(payload), runtime
        )
        pieces: list[str] = []
        for read in batch.reads:
            lines = read.path.read_text(encoding="utf-8").splitlines()
            for start, end in read.ranges:
                pieces.extend(lines[start - 1 : end])
        output = "\n".join(pieces) + ("\n" if pieces else "")
        post = dict(payload)
        post["hook_event_name"] = "PostToolUse"
        post["tool_response"] = (
            {"exit_code": 0, "output": output}
            if response is None
            else response
        )
        self.assertIsNone(
            reminder.process_hook(post, runtime=runtime, state_dir=state_dir)
        )

    def test_ungrounded_broad_search_reminds_but_named_read_does_not(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            state = root / "hook-state"
            direct_payload = self.payload(
                "sed -n '1,999p' plans/901-alpha-state-guard-tdd-plan.md",
                tool_id="1",
                root=root,
            )
            direct = reminder.process_hook(
                direct_payload,
                runtime=runtime,
                state_dir=state,
                auto_recall=False,
            )
            self.confirm_payload(direct_payload, runtime=runtime, state_dir=state)
            broad = reminder.process_hook(
                self.payload("rg -n 'status' plans -g '*.md'", tool_id="2", root=root),
                runtime=runtime,
                state_dir=state,
                auto_recall=False,
            )
            repeated = reminder.process_hook(
                self.payload("rg -n 'owner' plans -g '*.md'", tool_id="3", root=root),
                runtime=runtime,
                state_dir=state,
                auto_recall=False,
            )
            self.assertIsNone(direct)
            self.assertIn("Codex-memory advisory", broad["hookSpecificOutput"]["additionalContext"])
            self.assertIn(
                'memory.py query "status plans"',
                broad["hookSpecificOutput"]["additionalContext"],
            )
            self.assertIn(
                "advisory repeated",
                repeated["hookSpecificOutput"]["additionalContext"],
            )
            reads = [
                row for row in memory._read_jsonl(runtime.hook_events_path)
                if row.get("event") == "document_read"
            ]
            self.assertEqual(len(reads), 1)
            self.assertEqual(reads[0]["whole_documents"], 1)
            self.assertGreater(reads[0]["estimated_tokens"], 0)
            browses = [
                row for row in memory._read_jsonl(runtime.hook_events_path)
                if row.get("event") == "document_browse"
            ]
            self.assertEqual(
                [row["reminder"] for row in browses], ["initial", "ungrounded"]
            )
            self.assertTrue(all(row.get("tool_use_sha256") for row in browses))
            adoption = memory.stats(
                runtime, selector=memory.session_digest("hook-session")
            )
            self.assertEqual(adoption["initial_reminders"], 1)
            self.assertEqual(adoption["repeated_ungrounded_reminders"], 1)
            self.assertEqual(adoption["hook_agents"], 1)
            self.assertEqual(adoption["hook_tool_identity_events"], 3)

    def test_query_then_broad_search_is_recorded_as_grounded(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            state = root / "hook-state"
            context = reminder.process_hook(
                self.payload(
                    "python3 codex-memory/memory.py query 'plan 901 status'",
                    tool_id="1",
                    root=root,
                ),
                runtime=runtime,
                state_dir=state,
            )
            broad = reminder.process_hook(
                self.payload("rg -n 'status' Test-Flight-Improv -g '*.md'", tool_id="2", root=root),
                runtime=runtime,
                state_dir=state,
            )
            self.assertIsNone(context)
            self.assertIsNone(broad)
            events = memory._read_jsonl(runtime.hook_events_path)
            browse = [row for row in events if row.get("event") == "document_browse"]
            self.assertEqual(len(browse), 1)
            self.assertTrue(browse[0]["grounded"])

    def test_broad_search_is_automatically_grounded_and_measured(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            result = reminder.process_hook(
                self.payload(
                    "rg -n 'status' plans -g '*.md'",
                    tool_id="automatic",
                    root=root,
                ),
                runtime=runtime,
                state_dir=root / "hook-state",
            )
            context = result["hookSpecificOutput"]["additionalContext"]
            self.assertIn("Codex-memory automatic grounding", context)
            self.assertIn("execution-ready", context)

            events = memory._read_jsonl(runtime.hook_events_path)
            automatic_contexts = [
                row
                for row in events
                if row.get("event") == "context" and row.get("automatic")
            ]
            browses = [
                row for row in events if row.get("event") == "document_browse"
            ]
            self.assertEqual(len(automatic_contexts), 1)
            self.assertEqual(len(browses), 1)
            self.assertTrue(browses[0]["grounded"])
            self.assertTrue(browses[0]["auto_grounded"])
            self.assertTrue(browses[0]["tool_input_sha256"])

            usage = memory._read_jsonl(runtime.telemetry_path)
            self.assertEqual(len(usage), 1)
            self.assertEqual(usage[0]["trigger"], "pre_tool_use")
            self.assertEqual(
                usage[0]["codex_session_sha256"],
                memory.session_digest("hook-session"),
            )
            adoption = memory.stats(
                runtime, selector=memory.session_digest("hook-session")
            )
            self.assertEqual(adoption["queries"], 1)
            self.assertEqual(adoption["automatic_queries"], 1)
            self.assertEqual(adoption["auto_grounded_document_browses"], 1)
            self.assertEqual(adoption["ungrounded_document_browses"], 0)

    def test_duplicate_tool_event_is_deduplicated(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            state = root / "hook-state"
            payload = self.payload(
                "rg -n 'status' Test-Flight-Improv -g '*.md'", tool_id="same", root=root
            )
            reminder.process_hook(
                payload, runtime=runtime, state_dir=state, auto_recall=False
            )
            reminder.process_hook(
                payload, runtime=runtime, state_dir=state, auto_recall=False
            )
            events = memory._read_jsonl(runtime.hook_events_path)
            self.assertEqual(sum(row.get("event") == "document_browse" for row in events), 1)

    def test_functions_exec_javascript_payload_is_classified(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            payload = {
                "hook_event_name": "PreToolUse",
                "tool_name": "functions.exec",
                "tool_input": (
                    "const r = await tools.exec_command({"
                    "cmd: \"rg -n 'status' Test-Flight-Improv -g '*.md'\"}); text(r.output);"
                ),
                "tool_use_id": "javascript",
                "session_id": "hook-session",
                "cwd": str(root),
            }
            result = reminder.process_hook(
                payload,
                runtime=runtime,
                state_dir=root / "hook-state",
                auto_recall=False,
            )
            self.assertIsNotNone(result)
            self.assertIn(
                "broad plan/spec/document search",
                result["hookSpecificOutput"]["additionalContext"],
            )

    def test_complete_first_pass_then_repeat_is_grounded_and_blocked(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            state = root / "hook-state"
            path = "plans/901-alpha-state-guard-tdd-plan.md"

            first_payload = self.payload("cat " + path, tool_id="first", root=root)
            first = reminder.process_hook(
                first_payload,
                runtime=runtime,
                state_dir=state,
            )
            self.confirm_payload(first_payload, runtime=runtime, state_dir=state)
            blocked = reminder.process_hook(
                self.payload("cat " + path, tool_id="repeat", root=root),
                runtime=runtime,
                state_dir=state,
            )
            blocked_retry = reminder.process_hook(
                self.payload("cat " + path, tool_id="repeat", root=root),
                runtime=runtime,
                state_dir=state,
            )
            targeted_payload = self.payload(
                "sed -n '2,3p' " + path,
                tool_id="targeted",
                root=root,
            )
            targeted = reminder.process_hook(
                targeted_payload,
                runtime=runtime,
                state_dir=state,
            )
            self.confirm_payload(targeted_payload, runtime=runtime, state_dir=state)
            targeted_search = reminder.process_hook(
                self.payload(
                    "rg -n 'owner' " + path,
                    tool_id="targeted-search",
                    root=root,
                ),
                runtime=runtime,
                state_dir=state,
            )
            bypassed = reminder.process_hook(
                self.payload(
                    "CODEX_MEMORY_REPEAT_GUARD_BYPASS=1 cat " + path,
                    tool_id="bypass",
                    root=root,
                ),
                runtime=runtime,
                state_dir=state,
            )

            self.assertIsNone(first)
            self.assertEqual(
                blocked["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            self.assertIn(
                path,
                blocked["hookSpecificOutput"]["permissionDecisionReason"],
            )
            self.assertEqual(
                blocked_retry["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            self.assertIsNone(targeted)
            self.assertIsNone(targeted_search)
            self.assertIsNone(bypassed)

            adoption = memory.stats(
                runtime, selector=memory.session_digest("hook-session")
            )
            self.assertEqual(adoption["unique_documents"], 1)
            self.assertEqual(adoption["completed_first_pass_documents"], 1)
            self.assertEqual(adoption["first_pass_coverage"], 1.0)
            self.assertEqual(adoption["targeted_document_revisits"], 1)
            self.assertEqual(adoption["redundant_broad_attempts"], 3)
            self.assertEqual(adoption["repeat_guard_grounded_blocks"], 2)
            self.assertEqual(adoption["repeat_guard_cached_blocks"], 1)
            self.assertEqual(adoption["repeat_guard_bypasses"], 1)
            self.assertEqual(adoption["repeat_guard_automatic_queries"], 1)
            self.assertGreater(adoption["estimated_avoided_document_tokens"], 0)
            self.assertNotIn(
                path, runtime.hook_events_path.read_text(encoding="utf-8")
            )
            self.assertNotIn(
                path, runtime.telemetry_path.read_text(encoding="utf-8")
            )

    def test_denied_exact_retry_with_same_tool_id_precedes_recent_dedupe(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            state_dir = root / "hook-state"
            relative = "plans/901-alpha-state-guard-tdd-plan.md"
            first_payload = self.payload(
                "cat " + relative, tool_id="first", root=root
            )
            reminder.process_hook(
                first_payload,
                runtime=runtime,
                state_dir=state_dir,
            )
            self.confirm_payload(first_payload, runtime=runtime, state_dir=state_dir)
            denied_payload = self.payload(
                "cat " + relative, tool_id="same-denied-id", root=root
            )
            first_denial = reminder.process_hook(
                denied_payload,
                runtime=runtime,
                state_dir=state_dir,
            )
            self.assertEqual(
                first_denial["hookSpecificOutput"]["permissionDecision"], "deny"
            )

            session = memory.session_digest("hook-session")
            state_path = state_dir / (session + "-root.json")
            state = reminder._read_state(state_path, session, "root")
            state["recent_tool_use_hashes"] = [
                *state.get("recent_tool_use_hashes", []),
                reminder._digest("same-denied-id"),
            ]
            reminder._write_state(state_path, state)

            exact_retry = reminder.process_hook(
                denied_payload,
                runtime=runtime,
                state_dir=state_dir,
            )
            self.assertEqual(
                exact_retry["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            adoption = memory.stats(
                runtime, selector=memory.session_digest("hook-session")
            )
            self.assertEqual(adoption["repeat_guard_automatic_queries"], 1)
            self.assertEqual(adoption["repeat_guard_grounded_blocks"], 2)
            self.assertEqual(adoption["repeat_guard_cached_blocks"], 1)

    def test_oversized_primary_is_output_blocked_without_precredit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            path = root / "plans" / "901-alpha-state-guard-tdd-plan.md"
            lines = ["# 901 - Alpha state guard", "Status: execution-ready"]
            lines.extend("line {:04d} ".format(index) + "x" * 100 for index in range(1, 801))
            write(path, "\n".join(lines) + "\n")
            state = root / "hook-state"
            relative = "plans/901-alpha-state-guard-tdd-plan.md"

            oversized_payload = self.functions_payload(
                "sed -n '1,760p' " + relative,
                tool_id="oversized",
                root=root,
            )
            oversized = reminder.process_hook(
                oversized_payload,
                runtime=runtime,
                state_dir=state,
            )
            self.confirm_payload(oversized_payload, runtime=runtime, state_dir=state)
            required_payload = self.functions_payload(
                "sed -n '1,250p' " + relative,
                tool_id="required",
                root=root,
            )
            required_reread = reminder.process_hook(
                required_payload,
                runtime=runtime,
                state_dir=state,
            )
            self.confirm_payload(required_payload, runtime=runtime, state_dir=state)

            self.assertEqual(
                oversized["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            self.assertIn(
                "primary output-safety gate",
                oversized["hookSpecificOutput"]["permissionDecisionReason"],
            )
            self.assertIsNone(required_reread)
            adoption = memory.stats(
                runtime, selector=memory.session_digest("hook-session")
            )
            self.assertEqual(adoption["repeat_guard_grounded_blocks"], 0)
            self.assertEqual(adoption["unconfirmed_document_ranges"], 0)
            self.assertEqual(adoption["primary_guidance_events"], 1)
            self.assertEqual(
                adoption["primary_guidance_output_safety_blocks"], 1
            )
            self.assertEqual(adoption["first_pass_covered_lines"], 250)
            self.assertLess(adoption["first_pass_coverage"], 1.0)

    def test_sequential_ranges_complete_first_pass_before_guarding_overlap(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            relative = "plans/901-alpha-state-guard-tdd-plan.md"
            lines = ["# 901 - Alpha state guard", "Status: execution-ready"]
            lines.extend(
                "decision {:04d} keeps cumulative coverage deterministic".format(index)
                for index in range(1, 361)
            )
            write(root / relative, "\n".join(lines) + "\n")
            state = root / "hook-state"

            for index, line_range in enumerate(("1,120", "121,240", "241,999")):
                command = "sed -n '{}p' {}".format(line_range, relative)
                if index == 0:
                    command = "CODEX_MEMORY_PRIMARY_READ=1 " + command
                chunk_payload = self.payload(
                    command,
                    tool_id="chunk-{}".format(index),
                    root=root,
                )
                result = reminder.process_hook(
                    chunk_payload,
                    runtime=runtime,
                    state_dir=state,
                )
                self.assertIsNone(result)
                self.confirm_payload(chunk_payload, runtime=runtime, state_dir=state)
            blocked = reminder.process_hook(
                self.payload(
                    "sed -n '1,200p' " + relative,
                    tool_id="overlap",
                    root=root,
                ),
                runtime=runtime,
                state_dir=state,
            )

            self.assertEqual(
                blocked["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            adoption = memory.stats(
                runtime, selector=memory.session_digest("hook-session")
            )
            self.assertEqual(adoption["document_read_calls"], 3)
            self.assertEqual(adoption["first_pass_coverage"], 1.0)
            self.assertEqual(adoption["repeat_guard_grounded_blocks"], 1)

    def test_mixed_repeat_and_changed_document_both_fail_open(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            state = root / "hook-state"
            relative = "plans/901-alpha-state-guard-tdd-plan.md"
            first_payload = self.payload(
                "cat " + relative, tool_id="first", root=root
            )
            reminder.process_hook(
                first_payload,
                runtime=runtime,
                state_dir=state,
            )
            self.confirm_payload(first_payload, runtime=runtime, state_dir=state)
            mixed = reminder.process_hook(
                self.payload(
                    "cat " + relative + " && echo done",
                    tool_id="mixed",
                    root=root,
                ),
                runtime=runtime,
                state_dir=state,
            )
            write(root / relative, PLAN_901 + "\nNew changed decision.\n")
            changed = reminder.process_hook(
                self.payload("cat " + relative, tool_id="changed", root=root),
                runtime=runtime,
                state_dir=state,
            )

            self.assertIsNone(mixed)
            self.assertIsNone(changed)
            adoption = memory.stats(
                runtime, selector=memory.session_digest("hook-session")
            )
            self.assertEqual(adoption["repeat_guard_grounded_blocks"], 0)
            self.assertEqual(adoption["repeat_guard_fail_opens"], 2)
            self.assertEqual(adoption["repeat_guard_automatic_queries"], 0)

    def test_repeat_recall_miss_error_and_permanent_opt_out_fail_open(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = fixture(root)
            state = root / "hook-state"
            relative = "plans/901-alpha-state-guard-tdd-plan.md"
            first_payload = self.payload(
                "cat " + relative, tool_id="first", root=root
            )
            reminder.process_hook(
                first_payload,
                runtime=runtime,
                state_dir=state,
            )
            self.confirm_payload(first_payload, runtime=runtime, state_dir=state)
            with mock.patch.object(
                reminder, "_repeat_guard_recall", return_value=(None, "miss")
            ):
                missed = reminder.process_hook(
                    self.payload("cat " + relative, tool_id="miss", root=root),
                    runtime=runtime,
                    state_dir=state,
                )
            with mock.patch.object(
                reminder, "_repeat_guard_recall", side_effect=RuntimeError("boom")
            ):
                errored = reminder.process_hook(
                    self.payload(
                        "sed -n '1,999p' " + relative,
                        tool_id="error",
                        root=root,
                    ),
                    runtime=runtime,
                    state_dir=state,
                )
            with mock.patch.dict(
                os.environ, {"CODEX_MEMORY_REPEAT_GUARD": "0"}, clear=False
            ):
                opted_out = reminder.process_hook(
                    self.payload(
                        "head -n 999 " + relative,
                        tool_id="opt-out",
                        root=root,
                    ),
                    runtime=runtime,
                    state_dir=state,
                )

            self.assertIsNone(missed)
            self.assertIsNone(errored)
            self.assertIsNone(opted_out)
            adoption = memory.stats(
                runtime, selector=memory.session_digest("hook-session")
            )
            self.assertEqual(adoption["repeat_guard_fail_opens"], 2)
            self.assertEqual(adoption["repeat_guard_opt_outs"], 1)
            self.assertEqual(adoption["repeat_guard_grounded_blocks"], 0)


if __name__ == "__main__":
    unittest.main()
