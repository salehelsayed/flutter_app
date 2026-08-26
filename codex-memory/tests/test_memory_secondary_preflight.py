#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


CODEX_MEMORY_DIR = Path(__file__).resolve().parents[1]
if str(CODEX_MEMORY_DIR) not in sys.path:
    sys.path.insert(0, str(CODEX_MEMORY_DIR))

import codex_memory_reminder as reminder  # noqa: E402
import memory  # noqa: E402


PRIMARY = "plans/primary-plan.md"
SECONDARY = "docs/secondary-spec.md"
THIRD = "docs/third-spec.md"


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def document(title: str, phrase: str, lines: int) -> str:
    values = ["# " + title, "", "Status: accepted", "", "## Decisions"]
    values.extend("{} {:04d}".format(phrase, index) for index in range(lines))
    return "\n".join(values) + "\n"


def fixture(root: Path) -> memory.Runtime:
    write(root / PRIMARY, document("Primary Plan", "primary evidence", 760))
    write(root / SECONDARY, document("Secondary Spec", "secondary contract evidence", 500))
    write(root / THIRD, document("Third Spec", "small evidence", 30))
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
            "default_budget": 180,
            "hard_cap": 320,
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
                "name": "documents",
                "adapter": "markdown_sections",
                "root": ".",
                "include": ["plans/*.md", "docs/*.md"],
                "exclude": [],
                "minimum_files": 3,
                "priority": 100,
            }
        ],
        "evaluation": {},
    }
    config_path = root / "codex-memory" / "config.json"
    write(config_path, json.dumps(config))
    runtime = memory.load_runtime(config_path, root=root)
    memory.ensure_fresh(runtime)
    return runtime


def focused(relative: str = SECONDARY) -> tuple[str, str, int, bool, bool]:
    return (
        "- exact secondary decision — {}:1-20 @working-tree".format(relative),
        "focused_hit",
        80,
        True,
        True,
    )


class SecondaryPreflightTest(unittest.TestCase):
    def payload(
        self,
        command: str,
        *,
        root: Path,
        tool_id: str,
        agent_id: str | None = None,
        max_output_tokens: int | None = None,
    ) -> dict[str, object]:
        tool_input: dict[str, object] = {"cmd": command}
        if max_output_tokens is not None:
            tool_input["max_output_tokens"] = max_output_tokens
        value: dict[str, object] = {
            "hook_event_name": "PreToolUse",
            "tool_name": "exec_command",
            "tool_input": tool_input,
            "tool_use_id": tool_id,
            "session_id": "secondary-session-secret",
            "cwd": str(root),
        }
        if agent_id is not None:
            value["agent_id"] = agent_id
        return value

    def post_payload(
        self,
        command: str,
        *,
        root: Path,
        tool_id: str | None,
        response: object,
        agent_id: str | None = None,
        tool_name: str = "Bash",
        input_key: str = "command",
    ) -> dict[str, object]:
        value: dict[str, object] = {
            "hook_event_name": "PostToolUse",
            "tool_name": tool_name,
            "tool_input": {input_key: command},
            "tool_response": response,
            "session_id": "secondary-session-secret",
            "cwd": str(root),
        }
        if tool_id is not None:
            value["tool_use_id"] = tool_id
        if agent_id is not None:
            value["agent_id"] = agent_id
        return value

    def run_hook(
        self,
        runtime: memory.Runtime,
        state: Path,
        command: str,
        tool_id: str,
        *,
        agent_id: str | None = None,
        max_output_tokens: int | None = None,
    ) -> dict[str, object] | None:
        return reminder.process_hook(
            self.payload(
                command,
                root=runtime.root,
                tool_id=tool_id,
                agent_id=agent_id,
                max_output_tokens=max_output_tokens,
            ),
            runtime=runtime,
            state_dir=state,
        )

    def events(self, runtime: memory.Runtime, kind: str) -> list[dict[str, object]]:
        return [
            row
            for row in memory._read_jsonl(runtime.hook_events_path)
            if row.get("event") == kind
        ]

    def delivered_output(
        self,
        runtime: memory.Runtime,
        state: Path,
        command: str,
        tool_id: str | None,
        *,
        agent_id: str | None = None,
        tool_name: str = "Bash",
        input_key: str = "command",
        response: object | None = None,
    ) -> None:
        pre = self.payload(
            command,
            root=runtime.root,
            tool_id=tool_id or "temporary-pre-id",
            agent_id=agent_id,
        )
        if tool_id is None:
            pre.pop("tool_use_id", None)
        batch = reminder._document_reads(pre, reminder._commands(pre), runtime)
        pieces: list[str] = []
        for read in batch.reads:
            lines = read.path.read_text(encoding="utf-8").splitlines()
            for start, end in read.ranges:
                pieces.extend(lines[start - 1 : end])
        output = "\n".join(pieces)
        if pieces:
            output += "\n"
        actual_response = (
            {"exit_code": 0, "output": output}
            if response is None
            else response
        )
        self.assertIsNone(
            reminder.process_hook(
                self.post_payload(
                    command,
                    root=runtime.root,
                    tool_id=tool_id,
                    response=actual_response,
                    agent_id=agent_id,
                    tool_name=tool_name,
                    input_key=input_key,
                ),
                runtime=runtime,
                state_dir=state,
            )
        )

    def opportunities(
        self, runtime: memory.Runtime, kind: str = "secondary_read"
    ) -> list[dict[str, object]]:
        return [
            row
            for row in self.events(runtime, "retrieval_opportunity")
            if row.get("kind") == kind
        ]

    def establish_primary(self, runtime: memory.Runtime, state: Path) -> None:
        command = "cat " + PRIMARY
        self.assertIsNone(self.run_hook(runtime, state, command, "primary"))
        self.delivered_output(runtime, state, command, "primary")

    def test_primary_is_exempt_and_secondary_focused_hit_obeys_each_mode(self) -> None:
        for mode, expected_action in (
            ("off", "exempt"),
            ("shadow", "allow"),
            ("inject", "inject"),
            ("enforce", "deny"),
        ):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temporary:
                runtime = fixture(Path(temporary))
                state = runtime.root / "hook-state"
                with mock.patch.dict(
                    os.environ,
                    {
                        "CODEX_MEMORY_SECONDARY_MODE": mode,
                        "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                    },
                    clear=False,
                ), mock.patch.object(
                    reminder, "_secondary_recall", return_value=focused()
                ) as recall:
                    self.establish_primary(runtime, state)
                    result = self.run_hook(
                        runtime, state, "cat " + SECONDARY, "secondary"
                    )
                opportunities = self.opportunities(runtime)
                self.assertEqual(len(opportunities), 1)
                event = opportunities[0]
                self.assertEqual(event["mode"], mode)
                self.assertEqual(event["action"], expected_action)
                self.assertEqual(event["policy_version"], 4)
                self.assertEqual(event["kind"], "secondary_read")
                self.assertEqual(len(self.opportunities(runtime, "primary_read")), 1)
                if mode == "off":
                    recall.assert_not_called()
                    self.assertIsNone(result)
                    self.assertEqual(event["recall_outcome"], "disabled")
                    self.assertFalse(event["eligible"])
                    self.assertEqual(event["exclusion"], "disabled")
                    self.assertFalse(event["grounded"])
                    self.assertEqual(event["delivered_context_tokens"], 0)
                elif mode == "shadow":
                    self.assertIsNone(result)
                    self.assertFalse(event["grounded"])
                    self.assertEqual(event["delivered_context_tokens"], 0)
                elif mode == "inject":
                    self.assertIn(
                        "secondary-document preflight",
                        result["hookSpecificOutput"]["additionalContext"],
                    )
                    self.assertTrue(event["grounded"])
                    self.assertGreater(event["delivered_context_tokens"], 0)
                else:
                    self.assertEqual(
                        result["hookSpecificOutput"]["permissionDecision"], "deny"
                    )
                    self.assertGreater(event["estimated_avoided_tokens"], 0)
                    self.assertGreater(event["delivered_context_tokens"], 0)

    def test_enforce_fail_open_matrix_and_broad_hit_is_advisory(self) -> None:
        cases = (
            ("miss", (None, "miss", 0, False, True), None),
            ("mismatch", (None, "provenance_mismatch", 70, False, True), None),
            ("version", (*focused()[:4], False), "changed"),
            ("broad", (focused()[0], "broad_hit", 80, False, True), None),
        )
        for name, recalled, exclusion in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                runtime = fixture(Path(temporary))
                state = runtime.root / "hook-state"
                with mock.patch.dict(
                    os.environ,
                    {
                        "CODEX_MEMORY_SECONDARY_MODE": "enforce",
                        "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                    },
                    clear=False,
                ), mock.patch.object(
                    reminder, "_secondary_recall", return_value=recalled
                ):
                    self.establish_primary(runtime, state)
                    result = self.run_hook(
                        runtime, state, "cat " + SECONDARY, "secondary"
                    )
                event = self.opportunities(runtime)[0]
                self.assertFalse(event["blocked"])
                if exclusion is not None:
                    self.assertEqual(event["exclusion"], exclusion)
                if name == "broad":
                    self.assertIn("additionalContext", result["hookSpecificOutput"])
                else:
                    self.assertIsNone(result)

        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ, {"CODEX_MEMORY_SECONDARY_MODE": "enforce"}, clear=False
            ), mock.patch.object(
                reminder, "_secondary_recall", side_effect=RuntimeError("boom")
            ):
                self.establish_primary(runtime, state)
                self.assertIsNone(
                    self.run_hook(runtime, state, "cat " + SECONDARY, "error")
                )
            self.assertEqual(
                self.opportunities(runtime)[0]["recall_outcome"],
                "error",
            )

    def test_mixed_unconfirmed_changed_and_bypass_are_fail_open(self) -> None:
        cases = (
            ("mixed", "cat " + SECONDARY + " && echo done", None, False),
            ("unconfirmed", "cat " + SECONDARY, 10, True),
            (
                "bypass",
                "CODEX_MEMORY_SECONDARY_BYPASS=1 cat " + SECONDARY,
                None,
                False,
            ),
        )
        for exclusion, command, cap, recall_expected in cases:
            with self.subTest(exclusion=exclusion), tempfile.TemporaryDirectory() as temporary:
                runtime = fixture(Path(temporary))
                state = runtime.root / "hook-state"
                with mock.patch.dict(
                    os.environ,
                    {"CODEX_MEMORY_SECONDARY_MODE": "enforce"},
                    clear=False,
                ), mock.patch.object(
                    reminder, "_secondary_recall", return_value=focused()
                ) as recall:
                    self.establish_primary(runtime, state)
                    result = self.run_hook(
                        runtime,
                        state,
                        command,
                        exclusion,
                        max_output_tokens=cap,
                    )
                event = self.opportunities(runtime)[0]
                self.assertEqual(event["exclusion"], exclusion)
                self.assertFalse(event["blocked"])
                self.assertEqual(recall.called, recall_expected)
                if exclusion == "unconfirmed":
                    self.assertTrue(event["recall_attempted"])
                    self.assertIn("additionalContext", result["hookSpecificOutput"])
                else:
                    self.assertIsNone(result)

        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ, {"CODEX_MEMORY_SECONDARY_MODE": "inject"}, clear=False
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused()
            ) as recall:
                self.establish_primary(runtime, state)
                self.run_hook(runtime, state, "cat " + SECONDARY, "before-change")
                write(
                    runtime.root / SECONDARY,
                    document("Secondary Spec Changed", "changed evidence", 500),
                )
                changed = self.run_hook(
                    runtime, state, "sed -n '1,9999p' " + SECONDARY, "changed"
                )
            self.assertIsNone(changed)
            self.assertEqual(recall.call_count, 1)
            self.assertEqual(
                self.opportunities(runtime)[-1]["exclusion"],
                "changed",
            )

    def test_session_shared_primary_blocks_cross_agent_repeat_and_cannot_be_stolen(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            self.establish_primary(runtime, state)
            repeat_context = (
                "- primary decision — {}:1-20 @working-tree".format(PRIMARY)
            )
            with mock.patch.object(
                reminder,
                "_repeat_guard_recall",
                return_value=(repeat_context, "grounded"),
            ):
                repeated = self.run_hook(
                    runtime,
                    state,
                    "cat " + PRIMARY,
                    "worker-repeat",
                    agent_id="worker-1",
                )
            self.assertEqual(
                repeated["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            repeat_opportunity = self.opportunities(runtime, "repeat_read")
            self.assertEqual(len(repeat_opportunity), 1)
            self.assertEqual(repeat_opportunity[0]["action"], "deny")

            with mock.patch.dict(
                os.environ,
                {
                    "CODEX_MEMORY_SECONDARY_MODE": "enforce",
                    "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                },
                clear=False,
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused()
            ):
                steal = self.run_hook(
                    runtime,
                    state,
                    "CODEX_MEMORY_PRIMARY_READ=1 cat " + SECONDARY,
                    "worker-steal",
                    agent_id="worker-1",
                )
            self.assertEqual(steal["hookSpecificOutput"]["permissionDecision"], "deny")
            session = memory.session_digest("secondary-session-secret")
            shared = reminder._read_shared_state(
                state / (session + "-shared.json"), session
            )
            self.assertEqual(
                shared["primary"]["document_sha256"], reminder._digest(PRIMARY)
            )

    def test_subagent_before_root_is_provisional_and_never_claims_primary(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ,
                {
                    "CODEX_MEMORY_SECONDARY_MODE": "enforce",
                    "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                },
                clear=False,
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused(PRIMARY)
            ):
                result = self.run_hook(
                    runtime,
                    state,
                    "cat " + PRIMARY,
                    "worker-first",
                    agent_id="worker-1",
                )
            self.assertIn("additionalContext", result["hookSpecificOutput"])
            event = self.opportunities(runtime)[0]
            self.assertEqual(event["exclusion"], "provisional_primary")
            self.assertFalse(event["blocked"])
            session = memory.session_digest("secondary-session-secret")
            shared = reminder._read_shared_state(
                state / (session + "-shared.json"), session
            )
            self.assertIsNone(shared["primary"])

    def test_root_primary_marker_switches_task_and_is_recovery_followup(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            long_recall = (
                focused()[0] + "\n" + ("long recalled body " * 300),
                "focused_hit",
                80,
                True,
                True,
            )
            with mock.patch.dict(
                os.environ,
                {
                    "CODEX_MEMORY_SECONDARY_MODE": "enforce",
                    "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                },
                clear=False,
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=long_recall
            ):
                self.establish_primary(runtime, state)
                self.run_hook(
                    runtime,
                    state,
                    "python3 codex-memory/memory.py query 'old task decision'",
                    "old-task-context",
                )
                denied = self.run_hook(
                    runtime, state, "cat " + SECONDARY, "secondary-denied"
                )
                switched = self.run_hook(
                    runtime,
                    state,
                    "CODEX_MEMORY_PRIMARY_READ=1 cat " + SECONDARY,
                    "primary-switch",
                )
                self.delivered_output(
                    runtime,
                    state,
                    "CODEX_MEMORY_PRIMARY_READ=1 cat " + SECONDARY,
                    "primary-switch",
                )
            reason = denied["hookSpecificOutput"]["permissionDecisionReason"]
            self.assertIn("CODEX_MEMORY_PRIMARY_READ=1", reason)
            self.assertIn("CODEX_MEMORY_SECONDARY_BYPASS=1", reason)
            self.assertLess(
                reason.index("CODEX_MEMORY_PRIMARY_READ=1"),
                reason.index("long recalled body"),
            )
            self.assertLess(
                reason.index("CODEX_MEMORY_SECONDARY_BYPASS=1"),
                reason.index("long recalled body"),
            )
            self.assertIsNone(switched)
            followups = self.events(runtime, "retrieval_followup")
            self.assertEqual(followups[-1]["outcome"], "primary_bypass")
            session = memory.session_digest("secondary-session-secret")
            shared = reminder._read_shared_state(
                state / (session + "-shared.json"), session
            )
            self.assertEqual(
                shared["primary"]["document_sha256"], reminder._digest(SECONDARY)
            )
            root_state = reminder._read_state(
                state / (session + "-root.json"), session, "root"
            )
            self.assertEqual(root_state["context_calls"], 0)

    def test_task_rotation_terminates_other_pending_and_resets_versions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ,
                {
                    "CODEX_MEMORY_SECONDARY_MODE": "enforce",
                    "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                },
                clear=False,
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused()
            ):
                self.establish_primary(runtime, state)
                self.run_hook(runtime, state, "cat " + SECONDARY, "pending-secondary")
                self.run_hook(runtime, state, "cat " + THIRD, "pending-third")
                self.run_hook(
                    runtime,
                    state,
                    "CODEX_MEMORY_PRIMARY_READ=1 cat " + SECONDARY,
                    "rotate",
                )
                self.delivered_output(
                    runtime,
                    state,
                    "CODEX_MEMORY_PRIMARY_READ=1 cat " + SECONDARY,
                    "rotate",
                )
                later = self.run_hook(runtime, state, "cat " + THIRD, "third-new-task")
            outcomes = {
                row["outcome"] for row in self.events(runtime, "retrieval_followup")
            }
            self.assertIn("primary_bypass", outcomes)
            self.assertIn("abandoned", outcomes)
            self.assertEqual(later["hookSpecificOutput"]["permissionDecision"], "deny")
            self.assertNotEqual(self.opportunities(runtime)[-1]["exclusion"], "changed")

    def test_secondary_bypass_does_not_bypass_repeat_guard(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ, {"CODEX_MEMORY_SECONDARY_MODE": "inject"}, clear=False
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused()
            ):
                self.establish_primary(runtime, state)
                self.run_hook(runtime, state, "cat " + SECONDARY, "allowed-secondary")
                self.delivered_output(
                    runtime, state, "cat " + SECONDARY, "allowed-secondary"
                )
            repeated_context = "- repeated — {}:1-20 @working-tree".format(SECONDARY)
            with mock.patch.object(
                reminder,
                "_repeat_guard_recall",
                return_value=(repeated_context, "grounded"),
            ):
                result = self.run_hook(
                    runtime,
                    state,
                    "CODEX_MEMORY_SECONDARY_BYPASS=1 cat " + SECONDARY,
                    "secondary-only-bypass",
                )
            self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")
            self.assertEqual(self.opportunities(runtime)[-1]["exclusion"], "bypass")
            self.assertEqual(self.opportunities(runtime, "repeat_read")[-1]["action"], "deny")

    def test_cached_action_identity_preserves_cross_agent_events(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ,
                {
                    "CODEX_MEMORY_SECONDARY_MODE": "inject",
                    "CODEX_MEMORY_REPEAT_GUARD": "0",
                },
                clear=False,
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused()
            ) as recall:
                self.establish_primary(runtime, state)
                self.run_hook(runtime, state, "cat " + SECONDARY, "root-first")
                self.run_hook(runtime, state, "cat " + SECONDARY, "root-cached")
                self.run_hook(
                    runtime,
                    state,
                    "cat " + SECONDARY,
                    "worker-cached",
                    agent_id="worker-1",
                )
            opportunities = self.opportunities(runtime)
            cached = [
                row for row in opportunities if row["recall_outcome"] == "cached_hit"
            ]
            self.assertEqual(recall.call_count, 1)
            self.assertEqual(len(cached), 2)
            self.assertEqual(
                len({row["raw_read_intent_sha256"] for row in cached}), 1
            )
            self.assertEqual(len({row["opportunity_sha256"] for row in cached}), 2)

    def test_range_identity_dedupes_equivalent_whole_but_keeps_distinct_broad_read(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ,
                {
                    "CODEX_MEMORY_SECONDARY_MODE": "enforce",
                    "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                },
                clear=False,
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused()
            ) as recall:
                self.establish_primary(runtime, state)
                unconfirmed = self.run_hook(
                    runtime,
                    state,
                    "cat " + SECONDARY,
                    "unconfirmed-whole",
                    max_output_tokens=10,
                )
                equivalent = self.run_hook(
                    runtime,
                    state,
                    "sed -n '1,9999p' " + SECONDARY,
                    "equivalent-whole",
                    max_output_tokens=10,
                )
                distinct = self.run_hook(
                    runtime,
                    state,
                    "sed -n '1,250p' " + SECONDARY,
                    "distinct-range",
                )
            self.assertIn("additionalContext", unconfirmed["hookSpecificOutput"])
            self.assertIn("additionalContext", equivalent["hookSpecificOutput"])
            self.assertEqual(distinct["hookSpecificOutput"]["permissionDecision"], "deny")
            opportunities = self.opportunities(runtime)
            self.assertEqual(len(opportunities), 3)
            self.assertEqual(
                len({row["raw_read_intent_sha256"] for row in opportunities}), 2
            )
            self.assertEqual(opportunities[0]["exclusion"], "unconfirmed")
            self.assertEqual(opportunities[-1]["action"], "deny")
            self.assertEqual(opportunities[-1]["recall_outcome"], "cached_hit")
            self.assertEqual(opportunities[-1]["recall_tokens"], 0)
            self.assertTrue(opportunities[-1]["recall_attempted"])
            self.assertEqual(recall.call_count, 1)

    def test_broad_sweep_opportunities_are_joined_and_classified(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            recalled = memory.RecallResult(
                output="- compact plan status",
                hit=True,
                confidence="focused",
                matched_terms=2,
                query_terms=2,
                selected_entities=1,
                source_documents=1,
                truncated=False,
                tokens=25,
            )
            with mock.patch.object(memory, "recall", return_value=recalled):
                result = self.run_hook(
                    runtime,
                    state,
                    "rg -n 'status' plans -g '*.md'",
                    "broad-auto",
                )
            self.assertIn("automatic grounding", result["hookSpecificOutput"]["additionalContext"])
            automatic = self.opportunities(runtime, "broad_sweep")[0]
            self.assertTrue(automatic["eligible"])
            self.assertEqual(automatic["action"], "inject")
            usage = memory._read_jsonl(runtime.telemetry_path)
            self.assertEqual(
                usage[0]["raw_read_intent_sha256"],
                automatic["raw_read_intent_sha256"],
            )

            self.run_hook(
                runtime,
                state,
                "python3 codex-memory/memory.py query 'owner decision'",
                "manual-context",
            )
            self.run_hook(
                runtime,
                state,
                "rg -n 'owner' docs -g '*.md'",
                "already-grounded",
            )
            grounded = self.opportunities(runtime, "broad_sweep")[-1]
            self.assertFalse(grounded["eligible"])
            self.assertEqual(grounded["exclusion"], "already_grounded")

        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ, {"CODEX_MEMORY_AUTO_RECALL": "0"}, clear=False
            ):
                self.run_hook(
                    runtime,
                    state,
                    "rg -n 'status' plans -g '*.md'",
                    "broad-disabled",
                )
            disabled = self.opportunities(runtime, "broad_sweep")[0]
            self.assertEqual(disabled["mode"], "off")
            self.assertEqual(disabled["exclusion"], "disabled")
            self.assertFalse(disabled["recall_attempted"])

    def test_nl_sed_windows_preserve_disjoint_ranges_and_follow_up(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            command = (
                "nl -ba " + PRIMARY
                + " | sed -n '1,180p;181,360p;500,745p'"
            )
            self.assertIsNone(self.run_hook(runtime, state, command, "multi-range"))
            self.delivered_output(runtime, state, command, "multi-range")
            read = self.events(runtime, "document_read")[0]
            coverage = read["coverage"][0]
            self.assertEqual(coverage["added_lines"], 606)
            self.assertFalse(coverage["complete"])

            with mock.patch.dict(
                os.environ,
                {
                    "CODEX_MEMORY_SECONDARY_MODE": "enforce",
                    "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                },
                clear=False,
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused()
            ):
                denied = self.run_hook(
                    runtime, state, "cat " + SECONDARY, "secondary"
                )
                targeted = self.run_hook(
                    runtime,
                    state,
                    "nl -ba " + SECONDARY + " | sed -n '10,30p'",
                    "targeted",
                )
                self.delivered_output(
                    runtime,
                    state,
                    "nl -ba " + SECONDARY + " | sed -n '10,30p'",
                    "targeted",
                )
            self.assertEqual(
                denied["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            self.assertIsNone(targeted)
            self.assertEqual(
                self.events(runtime, "retrieval_followup")[-1]["outcome"],
                "targeted_window",
            )

    def test_cache_dedupes_exact_retry_and_telemetry_is_private_and_joinable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            recalled = memory.RecallResult(
                output="- exact decision — {}:1-20 @working-tree".format(SECONDARY),
                hit=True,
                confidence="focused",
                matched_terms=5,
                query_terms=6,
                selected_entities=1,
                source_documents=1,
                truncated=False,
                tokens=70,
            )
            with mock.patch.dict(
                os.environ,
                {
                    "CODEX_MEMORY_SECONDARY_MODE": "enforce",
                    "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                },
                clear=False,
            ), mock.patch.object(memory, "recall", return_value=recalled) as recall:
                self.establish_primary(runtime, state)
                first = self.run_hook(runtime, state, "cat " + SECONDARY, "first")
                retry = self.run_hook(runtime, state, "cat " + SECONDARY, "retry")
                redelivery = self.run_hook(
                    runtime, state, "cat " + SECONDARY, "retry"
                )
                cached = self.run_hook(
                    runtime,
                    state,
                    "sed -n '1,9999p' " + SECONDARY,
                    "cached-input",
                )
                bypass = self.run_hook(
                    runtime,
                    state,
                    "CODEX_MEMORY_SECONDARY_BYPASS=1 cat " + SECONDARY,
                    "whole-bypass",
                )
                self.delivered_output(
                    runtime,
                    state,
                    "CODEX_MEMORY_SECONDARY_BYPASS=1 cat " + SECONDARY,
                    "whole-bypass",
                )
                self.run_hook(
                    runtime,
                    state,
                    "CODEX_MEMORY_PRIMARY_READ=1 cat " + SECONDARY,
                    "epoch-secondary",
                )
                self.delivered_output(
                    runtime,
                    state,
                    "CODEX_MEMORY_PRIMARY_READ=1 cat " + SECONDARY,
                    "epoch-secondary",
                )
                self.run_hook(
                    runtime,
                    state,
                    "CODEX_MEMORY_PRIMARY_READ=1 cat " + PRIMARY,
                    "epoch-primary",
                )
                self.delivered_output(
                    runtime,
                    state,
                    "CODEX_MEMORY_PRIMARY_READ=1 cat " + PRIMARY,
                    "epoch-primary",
                )
                new_epoch_cached = self.run_hook(
                    runtime, state, "cat " + SECONDARY, "new-epoch-cached"
                )
            self.assertEqual(first["hookSpecificOutput"]["permissionDecision"], "deny")
            self.assertEqual(retry["hookSpecificOutput"]["permissionDecision"], "deny")
            self.assertEqual(
                redelivery["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            self.assertEqual(cached["hookSpecificOutput"]["permissionDecision"], "deny")
            self.assertEqual(
                new_epoch_cached["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            self.assertIsNone(bypass)
            self.assertEqual(recall.call_count, 1)
            opportunities = self.opportunities(runtime)
            self.assertEqual(len(opportunities), 5)
            self.assertEqual(
                len({row["raw_read_intent_sha256"] for row in opportunities}), 2
            )
            self.assertTrue(
                all(
                    row["recall_tokens"] == 0
                    for row in opportunities
                    if row["recall_outcome"] == "cached_hit"
                )
            )
            self.assertEqual(
                len({row["opportunity_sha256"] for row in opportunities}), 5
            )
            self.assertTrue(
                all(
                    row["recall_attempted"]
                    for row in opportunities
                    if row["recall_outcome"] == "cached_hit"
                )
            )
            self.assertEqual(
                self.events(runtime, "retrieval_followup")[-1]["outcome"],
                "whole_read",
            )
            usage = memory._read_jsonl(runtime.telemetry_path)
            self.assertEqual(len(usage), 1)
            self.assertEqual(usage[0]["trigger"], "secondary_preflight")
            self.assertEqual(usage[0]["policy_version"], 4)
            self.assertEqual(usage[0]["mode"], "enforce")
            self.assertEqual(
                usage[0]["raw_read_intent_sha256"],
                opportunities[0]["raw_read_intent_sha256"],
            )
            hook_raw = runtime.hook_events_path.read_text(encoding="utf-8")
            usage_raw = runtime.telemetry_path.read_text(encoding="utf-8")
            for secret in (PRIMARY, SECONDARY, "secondary-session-secret"):
                self.assertNotIn(secret, hook_raw)
                self.assertNotIn(secret, usage_raw)

    def test_post_confirmation_rejects_failure_truncation_and_short_output(self) -> None:
        failures = {
            "missing": None,
            "nonzero": {"exit_code": 1, "output": "failed\n"},
            "structured_nonzero": {
                "structuredContent": {"exit_code": 7, "output": "x\n" * 60}
            },
            "isError": {"isError": True, "output": "x\n" * 60},
            "truncated": {"exit_code": 0, "truncated": True, "output": "x\n" * 60},
            "script_failed": [
                {"type": "input_text", "text": "Script failed\nWall time 0.1s"},
                {"type": "input_text", "text": "Script error: exit 1"},
            ],
            "script_running": [
                {"type": "input_text", "text": "Script running with cell ID 7"},
                {"type": "input_text", "text": "partial output"},
            ],
            "short": {"exit_code": 0, "output": "one line\n"},
        }
        for name, response in failures.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                runtime = fixture(Path(temporary))
                state = runtime.root / "hook-state"
                command = "sed -n '1,60p' " + SECONDARY
                with mock.patch.dict(
                    os.environ,
                    {
                        "CODEX_MEMORY_SECONDARY_MODE": "enforce",
                        "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                    },
                    clear=False,
                ), mock.patch.object(
                    reminder, "_secondary_recall", return_value=focused()
                ):
                    self.establish_primary(runtime, state)
                    denied = self.run_hook(
                        runtime, state, "cat " + SECONDARY, "denied"
                    )
                    self.assertEqual(
                        denied["hookSpecificOutput"]["permissionDecision"], "deny"
                    )
                    self.assertIsNone(
                        self.run_hook(runtime, state, command, "targeted")
                    )
                    post = self.post_payload(
                        command,
                        root=runtime.root,
                        tool_id="targeted",
                        response=response or {},
                    )
                    if name == "missing":
                        post.pop("tool_response")
                    self.assertIsNone(
                        reminder.process_hook(post, runtime=runtime, state_dir=state)
                    )
                    self.assertEqual(self.events(runtime, "retrieval_followup"), [])
                    session = memory.session_digest("secondary-session-secret")
                    agent_state = reminder._read_state(
                        state / (session + "-root.json"), session, "root"
                    )
                    self.assertEqual(
                        len(agent_state["pending_deliveries"]),
                        1 if name == "missing" else 0,
                    )
                    self.assertNotIn(
                        reminder._digest(SECONDARY), agent_state["documents"]
                    )
                    shared = reminder._read_shared_state(
                        state / (session + "-shared.json"), session
                    )
                    self.assertEqual(len(shared["pending_followups"]), 1)
                    retry_id = "targeted" if name == "missing" else "targeted-retry"
                    if name != "missing":
                        self.assertIsNone(
                            self.run_hook(runtime, state, command, retry_id)
                        )
                    self.delivered_output(runtime, state, command, retry_id)
                self.assertEqual(
                    self.events(runtime, "retrieval_followup")[-1]["outcome"],
                    "targeted_window",
                )

        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ, {"CODEX_MEMORY_SECONDARY_MODE": "inject"}, clear=False
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused()
            ):
                self.establish_primary(runtime, state)
                command = "cat " + SECONDARY
                self.run_hook(
                    runtime,
                    state,
                    command,
                    "predicted-unconfirmed",
                    max_output_tokens=10,
                )
                self.delivered_output(
                    runtime, state, command, "predicted-unconfirmed"
                )
            reads = [
                row
                for row in self.events(runtime, "document_read")
                if row["coverage"][0]["document_sha256"] == reminder._digest(SECONDARY)
            ]
            self.assertEqual(len(reads), 1)
            self.assertFalse(reads[0]["coverage"][0]["confirmed"])
            self.assertEqual(reads[0]["coverage"][0]["added_lines"], 0)
            self.assertEqual(reads[0]["whole_documents"], 1)

    def test_post_correlates_shell_aliases_without_tool_use_id(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            command = "CODEX_MEMORY_PRIMARY_READ=1 sed -n '1,60p' " + PRIMARY
            pre = self.payload(
                command,
                root=runtime.root,
                tool_id="unused",
            )
            pre.pop("tool_use_id")
            self.assertIsNone(
                reminder.process_hook(pre, runtime=runtime, state_dir=state)
            )
            self.assertEqual(self.events(runtime, "document_read"), [])
            successful_lines = (
                (runtime.root / PRIMARY)
                .read_text(encoding="utf-8")
                .splitlines()[:60]
            )
            successful_lines[10] = (
                "legitimate prose: script failed once; output truncated was its label"
            )
            self.delivered_output(
                runtime,
                state,
                command,
                None,
                tool_name="Bash",
                input_key="command",
                response={
                    "exit_code": 0,
                    "original_token_count": 60,
                    "content": [
                        {
                            "type": "input_text",
                            "text": "Script completed\nWall time 0.1s\nOutput:\n",
                        },
                        {
                            "type": "input_text",
                            "text": "\n".join(successful_lines) + "\n",
                        },
                    ],
                },
            )
            coverage = self.events(runtime, "document_read")[-1]["coverage"][0]
            self.assertEqual(coverage["covered_lines"], 60)
            self.assertEqual(coverage["total_chunks"], 1)

    def test_cumulative_secondary_windows_recall_once_before_crossing_threshold(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ, {"CODEX_MEMORY_SECONDARY_MODE": "inject"}, clear=False
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused()
            ) as recall:
                self.establish_primary(runtime, state)
                results: list[dict[str, object] | None] = []
                for index, (start, end) in enumerate(
                    ((1, 60), (61, 120), (121, 180), (181, 240)), start=1
                ):
                    command = "sed -n '{},{}p' {}".format(start, end, SECONDARY)
                    tool_id = "window-{}".format(index)
                    results.append(self.run_hook(runtime, state, command, tool_id))
                    self.delivered_output(runtime, state, command, tool_id)
                self.assertIsNone(results[0])
                self.assertIsNone(results[1])
                self.assertIn(
                    "secondary-document preflight",
                    results[2]["hookSpecificOutput"]["additionalContext"],
                )
                self.assertIsNone(results[3])
                self.assertEqual(recall.call_count, 1)
                self.assertEqual(len(self.opportunities(runtime)), 1)

                write(
                    runtime.root / SECONDARY,
                    document("Secondary Changed", "new contract evidence", 500),
                )
                for index, (start, end) in enumerate(
                    ((1, 60), (61, 120), (121, 180)), start=1
                ):
                    command = "sed -n '{},{}p' {}".format(start, end, SECONDARY)
                    tool_id = "changed-window-{}".format(index)
                    changed_result = self.run_hook(runtime, state, command, tool_id)
                    self.delivered_output(runtime, state, command, tool_id)
                self.assertIn(
                    "secondary-document preflight",
                    changed_result["hookSpecificOutput"]["additionalContext"],
                )
                self.assertEqual(recall.call_count, 2)
            latest = self.events(runtime, "document_read")[-1]["coverage"][0]
            self.assertEqual(latest["covered_lines"], 180)
            self.assertEqual(latest["total_chunks"], 3)

    def test_targeted_primary_marker_emits_exemption_and_post_accumulates_chunks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            first = "CODEX_MEMORY_PRIMARY_READ=1 sed -n '1,60p' " + PRIMARY
            self.assertIsNone(self.run_hook(runtime, state, first, "primary-window-1"))
            primary = self.opportunities(runtime, "primary_read")[-1]
            self.assertEqual(primary["exclusion"], "primary_marker")
            self.assertEqual(primary["delivered_context_tokens"], 0)
            self.assertEqual(self.events(runtime, "document_read"), [])
            self.delivered_output(runtime, state, first, "primary-window-1")

            second = "sed -n '61,120p' " + PRIMARY
            self.assertIsNone(self.run_hook(runtime, state, second, "primary-window-2"))
            self.delivered_output(runtime, state, second, "primary-window-2")
            coverage = self.events(runtime, "document_read")[-1]["coverage"][0]
            self.assertEqual(coverage["covered_lines"], 120)
            self.assertEqual(coverage["total_chunks"], 2)

    def test_targeted_lookup_does_not_claim_automatic_primary(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            targeted = "sed -n '1,60p' " + SECONDARY
            self.assertIsNone(self.run_hook(runtime, state, targeted, "lookup"))
            self.delivered_output(runtime, state, targeted, "lookup")
            session = memory.session_digest("secondary-session-secret")
            shared_path = state / (session + "-shared.json")
            shared = reminder._read_shared_state(shared_path, session)
            self.assertIsNone(shared["primary"])

            broad = "cat " + PRIMARY
            self.assertIsNone(self.run_hook(runtime, state, broad, "primary-after-lookup"))
            self.delivered_output(runtime, state, broad, "primary-after-lookup")
            shared = reminder._read_shared_state(shared_path, session)
            self.assertEqual(
                shared["primary"]["document_sha256"], reminder._digest(PRIMARY)
            )

    def test_failed_primary_transitions_do_not_rotate_or_resolve_debt(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            first = "cat " + PRIMARY
            self.assertIsNone(self.run_hook(runtime, state, first, "failed-first"))
            self.assertIsNone(
                reminder.process_hook(
                    self.post_payload(
                        first,
                        root=runtime.root,
                        tool_id="failed-first",
                        response={"exit_code": 1, "output": "failed\n"},
                    ),
                    runtime=runtime,
                    state_dir=state,
                )
            )
            session = memory.session_digest("secondary-session-secret")
            shared_path = state / (session + "-shared.json")
            shared = reminder._read_shared_state(shared_path, session)
            self.assertIsNone(shared["primary"])
            self.assertIsNone(shared["task_epoch_sha256"])

            with mock.patch.dict(
                os.environ,
                {
                    "CODEX_MEMORY_SECONDARY_MODE": "enforce",
                    "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                },
                clear=False,
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused()
            ):
                self.establish_primary(runtime, state)
                before = reminder._read_shared_state(shared_path, session)
                self.run_hook(runtime, state, "cat " + SECONDARY, "debt")
                marker = "CODEX_MEMORY_PRIMARY_READ=1 cat " + SECONDARY
                self.assertIsNone(
                    self.run_hook(runtime, state, marker, "failed-marker")
                )
                reminder.process_hook(
                    self.post_payload(
                        marker,
                        root=runtime.root,
                        tool_id="failed-marker",
                        response={"exit_code": 1, "output": "failed\n"},
                    ),
                    runtime=runtime,
                    state_dir=state,
                )
            after = reminder._read_shared_state(shared_path, session)
            self.assertEqual(after["task_epoch_sha256"], before["task_epoch_sha256"])
            self.assertEqual(
                after["primary"]["document_sha256"], reminder._digest(PRIMARY)
            )
            self.assertEqual(len(after["pending_followups"]), 1)
            self.assertEqual(self.events(runtime, "retrieval_followup"), [])

    def test_subagent_state_lazily_resets_on_confirmed_task_rotation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            self.establish_primary(runtime, state)
            self.run_hook(
                runtime,
                state,
                "python3 codex-memory/memory.py query 'worker old task'",
                "worker-context",
                agent_id="worker-1",
            )
            session = memory.session_digest("secondary-session-secret")
            worker = reminder._digest("worker-1")
            worker_path = state / (session + "-" + worker + ".json")
            worker_state = reminder._read_state(worker_path, session, worker)
            old_epoch = worker_state["task_epoch_sha256"]
            worker_state["broad_since_context"] = 7
            worker_state["denied_repeat_inputs"] = {"stale": {"context": "private"}}
            worker_state["documents"] = {"stale": {"ranges": [[1, 2]]}}
            reminder._write_state(worker_path, worker_state)

            marker = "CODEX_MEMORY_PRIMARY_READ=1 cat " + SECONDARY
            self.run_hook(runtime, state, marker, "root-rotate")
            self.delivered_output(runtime, state, marker, "root-rotate")
            shared = reminder._read_shared_state(
                state / (session + "-shared.json"), session
            )
            self.assertNotEqual(shared["task_epoch_sha256"], old_epoch)

            self.run_hook(
                runtime,
                state,
                "rg -n 'owner' " + PRIMARY,
                "worker-new-task",
                agent_id="worker-1",
            )
            worker_state = reminder._read_state(worker_path, session, worker)
            self.assertEqual(
                worker_state["task_epoch_sha256"], shared["task_epoch_sha256"]
            )
            self.assertEqual(worker_state["context_calls"], 0)
            self.assertEqual(worker_state["broad_since_context"], 0)
            self.assertEqual(worker_state["documents"], {})
            self.assertEqual(worker_state["denied_repeat_inputs"], {})

    def test_broad_preflight_service_prevents_chunked_redelivery(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ, {"CODEX_MEMORY_SECONDARY_MODE": "inject"}, clear=False
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused()
            ) as recall:
                self.establish_primary(runtime, state)
                broad = self.run_hook(
                    runtime, state, "cat " + SECONDARY, "broad-service"
                )
                self.assertIn(
                    "secondary-document preflight",
                    broad["hookSpecificOutput"]["additionalContext"],
                )
                for index, (start, end) in enumerate(
                    ((1, 60), (61, 120), (121, 180)), start=1
                ):
                    command = "sed -n '{},{}p' {}".format(start, end, SECONDARY)
                    tool_id = "served-window-{}".format(index)
                    self.assertIsNone(
                        self.run_hook(runtime, state, command, tool_id)
                    )
                    self.delivered_output(runtime, state, command, tool_id)
            self.assertEqual(recall.call_count, 1)
            self.assertEqual(len(self.opportunities(runtime)), 1)

    def test_distinct_pending_raw_intents_resolve_latest_then_whole(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ,
                {
                    "CODEX_MEMORY_SECONDARY_MODE": "enforce",
                    "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                },
                clear=False,
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused()
            ):
                self.establish_primary(runtime, state)
                for command, tool_id in (
                    ("sed -n '1,250p' " + SECONDARY, "deny-first"),
                    ("sed -n '251,500p' " + SECONDARY, "deny-second"),
                ):
                    result = self.run_hook(runtime, state, command, tool_id)
                    self.assertEqual(
                        result["hookSpecificOutput"]["permissionDecision"], "deny"
                    )
                session = memory.session_digest("secondary-session-secret")
                shared_path = state / (session + "-shared.json")
                shared = reminder._read_shared_state(shared_path, session)
                self.assertEqual(len(shared["pending_followups"]), 2)

                targeted = "sed -n '260,280p' " + SECONDARY
                self.assertIsNone(
                    self.run_hook(runtime, state, targeted, "target-latest")
                )
                self.delivered_output(runtime, state, targeted, "target-latest")
                shared = reminder._read_shared_state(shared_path, session)
                self.assertEqual(len(shared["pending_followups"]), 1)

                whole = "CODEX_MEMORY_SECONDARY_BYPASS=1 cat " + SECONDARY
                self.assertIsNone(self.run_hook(runtime, state, whole, "whole"))
                self.delivered_output(runtime, state, whole, "whole")
            shared = reminder._read_shared_state(shared_path, session)
            self.assertEqual(shared["pending_followups"], {})
            self.assertEqual(
                [row["outcome"] for row in self.events(runtime, "retrieval_followup")],
                ["targeted_window", "whole_read"],
            )

    def test_empty_normalized_targeted_search_keeps_fallback_debt(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ,
                {
                    "CODEX_MEMORY_SECONDARY_MODE": "enforce",
                    "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                },
                clear=False,
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=focused()
            ):
                self.establish_primary(runtime, state)
                self.run_hook(runtime, state, "cat " + SECONDARY, "search-debt")
                search = "rg -n 'owner' " + SECONDARY
                self.assertIsNone(
                    self.run_hook(runtime, state, search, "empty-search")
                )
                empty = self.post_payload(
                    search,
                    root=runtime.root,
                    tool_id="empty-search",
                    response={
                        "exit_code": 0,
                        "content": [
                            {
                                "type": "input_text",
                                "text": "Script completed\nWall time 0.1s\nOutput:\n",
                            },
                            {"type": "input_text", "text": ""},
                        ],
                    },
                )
                reminder.process_hook(empty, runtime=runtime, state_dir=state)
                session = memory.session_digest("secondary-session-secret")
                shared_path = state / (session + "-shared.json")
                shared = reminder._read_shared_state(shared_path, session)
                self.assertEqual(len(shared["pending_followups"]), 1)
                self.assertEqual(self.events(runtime, "retrieval_followup"), [])

                self.assertIsNone(
                    self.run_hook(runtime, state, search, "grounded-search")
                )
                grounded = self.post_payload(
                    search,
                    root=runtime.root,
                    tool_id="grounded-search",
                    response={"exit_code": 0, "output": "owner: alice\n"},
                )
                reminder.process_hook(grounded, runtime=runtime, state_dir=state)
            followup = self.events(runtime, "retrieval_followup")[-1]
            self.assertEqual(followup["outcome"], "targeted_search")
            self.assertGreater(followup["estimated_raw_tokens"], 0)
            shared = reminder._read_shared_state(shared_path, session)
            self.assertEqual(shared["pending_followups"], {})

    def test_broad_or_truncated_advisory_is_not_cached(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            broad = (focused()[0], "broad_hit", 80, False, True)
            with mock.patch.dict(
                os.environ, {"CODEX_MEMORY_SECONDARY_MODE": "inject"}, clear=False
            ), mock.patch.object(
                reminder, "_secondary_recall", return_value=broad
            ) as recall:
                self.establish_primary(runtime, state)
                for tool_id in ("broad-1", "broad-2"):
                    result = self.run_hook(
                        runtime, state, "cat " + SECONDARY, tool_id
                    )
                    self.assertIn(
                        "broad/truncated advisory",
                        result["hookSpecificOutput"]["additionalContext"],
                    )
                self.assertEqual(recall.call_count, 2)
            self.assertTrue(
                all(row["delivered_context_tokens"] > 0 for row in self.opportunities(runtime))
            )

    def test_oversized_root_marker_is_output_blocked_without_precredit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            state.mkdir(parents=True, exist_ok=True)
            session = memory.session_digest("secondary-session-secret")
            shared_path = state / (session + "-shared.json")
            seeded_shared = reminder._default_shared_state(session)
            seeded_shared["pending_followups"] = {
                "pending-intent-hash": {
                    "opportunity_sha256": "opportunity-hash",
                    "raw_read_intent_sha256": "pending-intent-hash",
                    "document_sha256": reminder._digest(PRIMARY),
                    "version_sha256": "prior-version-hash",
                    "estimated_raw_tokens": 123,
                    "updated_at": "2026-01-01T00:00:00+00:00",
                }
            }
            reminder._write_state(shared_path, seeded_shared)
            command = "CODEX_MEMORY_PRIMARY_READ=1 cat " + PRIMARY
            result = self.run_hook(
                runtime,
                state,
                command,
                "oversized-root-marker",
                max_output_tokens=10,
            )
            output = result["hookSpecificOutput"]
            self.assertEqual(output["permissionDecision"], "deny")
            reason = output["permissionDecisionReason"]
            self.assertIn("primary output-safety gate", reason)
            self.assertIn("CODEX_MEMORY_PRIMARY_READ=1 sed -n", reason)
            self.assertIn("CODEX_MEMORY_PRIMARY_OUTPUT_BYPASS=1", reason)
            self.assertIn("only its successful matching PostToolUse", reason)

            opportunity = self.opportunities(runtime, "primary_read")[-1]
            self.assertTrue(opportunity["guided"])
            self.assertEqual(opportunity["guidance_reason"], "output_cap")
            self.assertEqual(opportunity["guidance_action"], "deny")
            self.assertTrue(opportunity["output_safety_blocked"])
            self.assertFalse(opportunity["eligible"])
            self.assertFalse(opportunity["blocked"])
            self.assertEqual(opportunity["action"], "exempt")
            self.assertEqual(opportunity["estimated_avoided_tokens"], 0)
            self.assertEqual(opportunity["shared_covered_lines"], 0)
            self.assertEqual(opportunity["missing_lines"], 765)
            self.assertEqual(opportunity["suggested_range_count"], 1)

            shared = reminder._read_shared_state(shared_path, session)
            self.assertIsNone(shared["primary"])
            self.assertIsNone(shared["task_epoch_sha256"])
            self.assertEqual(
                set(shared["pending_followups"]), {"pending-intent-hash"}
            )
            self.assertEqual(self.events(runtime, "retrieval_followup"), [])
            root_state = reminder._read_state(
                state / (session + "-root.json"), session, "root"
            )
            self.assertEqual(root_state["pending_deliveries"], {})
            self.assertEqual(root_state["recent_tool_use_hashes"], [])
            self.assertEqual(self.events(runtime, "document_read"), [])

            exact_retry = self.run_hook(
                runtime,
                state,
                command,
                "oversized-root-marker",
                max_output_tokens=10,
            )
            self.assertEqual(
                exact_retry["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            self.assertEqual(len(self.opportunities(runtime, "primary_read")), 1)
            shared = reminder._read_shared_state(shared_path, session)
            self.assertEqual(
                set(shared["pending_followups"]), {"pending-intent-hash"}
            )

            # A Post event for a denied call cannot manufacture coverage or commit
            # the pending candidate primary.
            self.delivered_output(
                runtime, state, command, "oversized-root-marker"
            )
            shared = reminder._read_shared_state(shared_path, session)
            self.assertIsNone(shared["primary"])
            self.assertEqual(self.events(runtime, "document_read"), [])
            serialized = json.dumps(memory._read_jsonl(runtime.hook_events_path))
            self.assertNotIn(PRIMARY, serialized)
            self.assertNotIn(str(runtime.root), serialized)

    def test_automatic_primary_can_retry_with_the_reported_higher_cap(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            command = "cat " + PRIMARY
            denied = self.run_hook(
                runtime,
                state,
                command,
                "automatic-primary-small-cap",
                max_output_tokens=10,
            )
            reason = denied["hookSpecificOutput"]["permissionDecisionReason"]
            self.assertIn("CODEX_MEMORY_PRIMARY_READ=1", reason)
            event = self.opportunities(runtime, "primary_read")[-1]
            self.assertEqual(event["exclusion"], "primary_first_pass")
            minimum_cap = int(event["minimum_output_cap_tokens"])

            marked = "CODEX_MEMORY_PRIMARY_READ=1 " + command
            self.assertIsNone(
                self.run_hook(
                    runtime,
                    state,
                    marked,
                    "automatic-primary-higher-cap",
                    max_output_tokens=minimum_cap,
                )
            )
            self.delivered_output(
                runtime, state, marked, "automatic-primary-higher-cap"
            )
            session = memory.session_digest("secondary-session-secret")
            shared = reminder._read_shared_state(
                state / (session + "-shared.json"), session
            )
            self.assertEqual(shared["primary"]["ranges"], [[1, 765]])
            confirmed = self.events(runtime, "document_read")[-1]
            self.assertEqual(confirmed["coverage"][0]["ranges"], [[1, 765]])
            self.assertEqual(
                confirmed["task_epoch_sha256"], shared["task_epoch_sha256"]
            )

    def test_subagent_output_gate_uses_shared_missing_range_and_keeps_targeted_access(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            write(
                runtime.root / PRIMARY,
                document("Long Primary", "primary evidence", 1481),
            )
            state = runtime.root / "hook-state"
            tail = "CODEX_MEMORY_PRIMARY_READ=1 sed -n '328,1486p' " + PRIMARY
            self.assertIsNone(self.run_hook(runtime, state, tail, "root-tail"))
            self.delivered_output(runtime, state, tail, "root-tail")

            session = memory.session_digest("secondary-session-secret")
            shared_path = state / (session + "-shared.json")
            shared = reminder._read_shared_state(shared_path, session)
            self.assertEqual(shared["primary"]["ranges"], [[328, 1486]])
            root_coverage = self.events(runtime, "document_read")[-1]["coverage"][0]
            self.assertEqual(root_coverage["ranges"], [[328, 1486]])

            missing = reminder._read_measurement(
                runtime.root / PRIMARY,
                [(1, 327)],
                runtime=runtime,
                output_cap_tokens=100_000,
            )
            self.assertIsNotNone(missing)
            cap = reminder._minimum_output_cap_tokens(missing.estimated_tokens)
            result = self.run_hook(
                runtime,
                state,
                "cat " + PRIMARY,
                "child-whole",
                agent_id="child-secret",
                max_output_tokens=cap,
            )
            reason = result["hookSpecificOutput"]["permissionDecisionReason"]
            self.assertIn("sed -n 1,327p", reason)
            self.assertIn("parent's context packet", reason)
            self.assertIn("targeted rereads remain allowed", reason)
            self.assertNotIn("CODEX_MEMORY_PRIMARY_READ=1 sed -n 1,327p", reason)
            opportunity = self.opportunities(runtime, "primary_read")[-1]
            self.assertEqual(opportunity["exclusion"], "primary_continuation")
            self.assertEqual(opportunity["shared_covered_lines"], 1159)
            self.assertEqual(opportunity["missing_lines"], 327)
            self.assertEqual(opportunity["suggested_start_line"], 1)
            self.assertEqual(opportunity["suggested_end_line"], 327)

            child = reminder._digest("child-secret")
            child_state = reminder._read_state(
                state / (session + "-" + child + ".json"), session, child
            )
            self.assertEqual(child_state["pending_deliveries"], {})
            targeted = self.run_hook(
                runtime,
                state,
                "sed -n '400,450p' " + PRIMARY,
                "child-targeted",
                agent_id="child-secret",
                max_output_tokens=cap,
            )
            self.assertIsNone(targeted)
            shared = reminder._read_shared_state(shared_path, session)
            self.assertEqual(shared["primary"]["ranges"], [[328, 1486]])
            serialized = json.dumps(memory._read_jsonl(runtime.hook_events_path))
            self.assertNotIn(PRIMARY, serialized)
            self.assertNotIn(str(runtime.root), serialized)

    def test_primary_output_bypass_is_one_shot_and_never_precredits(self) -> None:
        for direct_flag in (False, True):
            with self.subTest(direct_flag=direct_flag), tempfile.TemporaryDirectory() as temporary:
                runtime = fixture(Path(temporary))
                state = runtime.root / "hook-state"
                command = "CODEX_MEMORY_PRIMARY_READ=1 "
                if not direct_flag:
                    command += "CODEX_MEMORY_PRIMARY_OUTPUT_BYPASS=1 "
                command += "cat " + PRIMARY
                payload = self.payload(
                    command,
                    root=runtime.root,
                    tool_id="primary-output-bypass",
                    max_output_tokens=10,
                )
                if direct_flag:
                    payload["tool_input"]["codex_memory_primary_output_bypass"] = True
                result = reminder.process_hook(
                    payload, runtime=runtime, state_dir=state
                )
                output = result["hookSpecificOutput"]
                self.assertNotIn("permissionDecision", output)
                self.assertIn("primary output-cap bypass", output["additionalContext"])
                opportunity = self.opportunities(runtime, "primary_read")[-1]
                self.assertEqual(opportunity["guidance_action"], "bypass")
                self.assertFalse(opportunity["output_safety_blocked"])
                self.assertEqual(opportunity["estimated_avoided_tokens"], 0)
                attempt = self.events(runtime, "document_read")[-1]["coverage"][0]
                self.assertFalse(attempt["confirmed"])
                self.assertEqual(attempt["covered_lines"], 0)
                self.assertEqual(attempt["ranges"], [])
                session = memory.session_digest("secondary-session-secret")
                shared = reminder._read_shared_state(
                    state / (session + "-shared.json"), session
                )
                self.assertIsNone(shared["primary"])

    def test_changed_primary_version_resets_output_guidance_coverage(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            self.establish_primary(runtime, state)
            session = memory.session_digest("secondary-session-secret")
            shared_path = state / (session + "-shared.json")
            before = reminder._read_shared_state(shared_path, session)["primary"]
            self.assertEqual(before["ranges"], [[1, 765]])

            write(
                runtime.root / PRIMARY,
                document("Changed Primary", "replacement evidence", 760),
            )
            result = self.run_hook(
                runtime,
                state,
                "cat " + PRIMARY,
                "changed-primary-small-cap",
                max_output_tokens=10,
            )
            self.assertEqual(
                result["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            event = self.opportunities(runtime, "primary_read")[-1]
            self.assertEqual(event["guidance_reason"], "output_cap")
            self.assertEqual(event["shared_covered_lines"], 0)
            self.assertEqual(event["missing_lines"], 765)
            after = reminder._read_shared_state(shared_path, session)["primary"]
            self.assertEqual(after["version_sha256"], before["version_sha256"])
            self.assertEqual(after["ranges"], [[1, 765]])

            root_state_path = state / (session + "-root.json")
            root_state = reminder._read_state(root_state_path, session, "root")
            root_state["denied_repeat_inputs"] = {
                "sentinel-cache-key": {
                    "document_sha256": reminder._digest(PRIMARY),
                    "version_sha256": before["version_sha256"],
                    "context": "hashed-state-sentinel",
                    "updated_at": "2026-01-01T00:00:00+00:00",
                }
            }
            reminder._write_state(root_state_path, root_state)
            redelivered = self.run_hook(
                runtime,
                state,
                "cat " + PRIMARY,
                "changed-primary-small-cap",
                max_output_tokens=10,
            )
            self.assertEqual(
                redelivered["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            guided = [
                row
                for row in self.opportunities(runtime, "primary_read")
                if row.get("guided")
            ]
            self.assertEqual(len(guided), 1)
            self.assertEqual(self.events(runtime, "repeat_guard"), [])
            root_state = reminder._read_state(root_state_path, session, "root")
            self.assertEqual(
                set(root_state["denied_repeat_inputs"]), {"sentinel-cache-key"}
            )

            first = "sed -n '1,60p' " + PRIMARY
            self.assertIsNone(
                self.run_hook(runtime, state, first, "changed-primary-first")
            )
            self.delivered_output(
                runtime, state, first, "changed-primary-first"
            )
            changed = reminder._read_measurement(
                runtime.root / PRIMARY,
                [(1, 60)],
                runtime=runtime,
                output_cap_tokens=10_000,
            )
            self.assertIsNotNone(changed)
            after_first = reminder._read_shared_state(shared_path, session)["primary"]
            self.assertEqual(after_first["version_sha256"], changed.version_sha256)
            self.assertEqual(after_first["ranges"], [[1, 60]])

            second = "sed -n '61,120p' " + PRIMARY
            self.assertIsNone(
                self.run_hook(runtime, state, second, "changed-primary-second")
            )
            self.delivered_output(
                runtime, state, second, "changed-primary-second"
            )
            after_second = reminder._read_shared_state(shared_path, session)["primary"]
            self.assertEqual(after_second["version_sha256"], changed.version_sha256)
            self.assertEqual(after_second["ranges"], [[1, 120]])

    def test_direct_read_output_gate_and_bypass_remain_post_conservative(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            base_input: dict[str, object] = {
                "path": PRIMARY,
                "start_line": 1,
                "limit": 765,
                "max_output_tokens": 10,
                "codex_memory_primary_read": True,
            }

            denied_payload: dict[str, object] = {
                "hook_event_name": "PreToolUse",
                "tool_name": "Read",
                "tool_input": dict(base_input),
                "tool_use_id": "direct-read-denied",
                "session_id": "secondary-session-secret",
                "cwd": str(runtime.root),
            }
            denied = reminder.process_hook(
                denied_payload, runtime=runtime, state_dir=state
            )
            self.assertEqual(
                denied["hookSpecificOutput"]["permissionDecision"], "deny"
            )

            bypass_payload = dict(denied_payload)
            bypass_payload["tool_use_id"] = "direct-read-bypass"
            bypass_payload["tool_input"] = {
                **base_input,
                "codex_memory_primary_output_bypass": True,
            }
            allowed = reminder.process_hook(
                bypass_payload, runtime=runtime, state_dir=state
            )
            self.assertNotIn(
                "permissionDecision", allowed["hookSpecificOutput"]
            )
            self.assertEqual(
                self.opportunities(runtime, "primary_read")[-1]["guidance_action"],
                "bypass",
            )

            post = dict(bypass_payload)
            post["hook_event_name"] = "PostToolUse"
            post["tool_response"] = {
                "exit_code": 0,
                "output": (runtime.root / PRIMARY).read_text(encoding="utf-8"),
            }
            self.assertIsNone(
                reminder.process_hook(post, runtime=runtime, state_dir=state)
            )
            session = memory.session_digest("secondary-session-secret")
            shared = reminder._read_shared_state(
                state / (session + "-shared.json"), session
            )
            self.assertIsNone(shared["primary"])
            attempts = self.events(runtime, "document_read")
            self.assertEqual(len(attempts), 1)
            self.assertFalse(attempts[0]["coverage"][0]["confirmed"])
            self.assertEqual(attempts[0]["coverage"][0]["ranges"], [])
            serialized = json.dumps(memory._read_jsonl(runtime.hook_events_path))
            self.assertNotIn(PRIMARY, serialized)
            self.assertNotIn(str(runtime.root), serialized)

    def test_numbered_output_overhead_can_block_when_plain_sed_would_fit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            write(
                runtime.root / PRIMARY,
                document("Short Lines", "x", 995),
            )
            state = runtime.root / "hook-state"
            plain_measurement = reminder._read_measurement(
                runtime.root / PRIMARY,
                [(1, 1000)],
                runtime=runtime,
                output_cap_tokens=100_000,
            )
            numbered_measurement = reminder._read_measurement(
                runtime.root / PRIMARY,
                [(1, 1000)],
                runtime=runtime,
                output_cap_tokens=100_000,
                line_numbered=True,
            )
            self.assertIsNotNone(plain_measurement)
            self.assertIsNotNone(numbered_measurement)
            self.assertGreater(
                numbered_measurement.estimated_tokens,
                plain_measurement.estimated_tokens,
            )
            cap = reminder._minimum_output_cap_tokens(
                plain_measurement.estimated_tokens
            )
            plain_payload = self.payload(
                "CODEX_MEMORY_PRIMARY_READ=1 sed -n '1,1000p' " + PRIMARY,
                root=runtime.root,
                tool_id="plain-sizing-probe",
                max_output_tokens=cap,
            )
            plain_batch = reminder._document_reads(
                plain_payload, reminder._commands(plain_payload), runtime
            )
            self.assertTrue(plain_batch.reads[0].confirmed)

            numbered_command = (
                "CODEX_MEMORY_PRIMARY_READ=1 nl -ba {} | "
                "sed -n '1,1000p'"
            ).format(PRIMARY)
            denied = self.run_hook(
                runtime,
                state,
                numbered_command,
                "numbered-output-risk",
                max_output_tokens=cap,
            )
            reason = denied["hookSpecificOutput"]["permissionDecisionReason"]
            self.assertIn("primary output-safety gate", reason)
            self.assertIn("nl -ba", reason)
            event = self.opportunities(runtime, "primary_read")[-1]
            self.assertEqual(
                event["estimated_raw_tokens"],
                numbered_measurement.estimated_tokens,
            )
            self.assertTrue(event["output_safety_blocked"])
            self.assertEqual(self.events(runtime, "document_read"), [])

    def test_mixed_oversized_primary_candidate_stays_fail_open(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            state = runtime.root / "hook-state"
            result = self.run_hook(
                runtime,
                state,
                "CODEX_MEMORY_PRIMARY_READ=1 cat {} ; true".format(PRIMARY),
                "mixed-primary",
                max_output_tokens=10,
            )
            if result is not None:
                self.assertNotIn(
                    "permissionDecision", result.get("hookSpecificOutput", {})
                )
            guided = [
                row
                for row in self.opportunities(runtime, "primary_read")
                if row.get("guided")
            ]
            self.assertEqual(guided, [])
            session = memory.session_digest("secondary-session-secret")
            shared = reminder._read_shared_state(
                state / (session + "-shared.json"), session
            )
            self.assertIsNone(shared["primary"])

    def test_real_exact_nontruncated_recall_can_enforce(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = fixture(Path(temporary))
            runtime.config["retrieval"]["hard_cap"] = 1000
            runtime.config["adoption"] = {"secondary_budget": 800}
            state = runtime.root / "hook-state"
            with mock.patch.dict(
                os.environ,
                {
                    "CODEX_MEMORY_SECONDARY_MODE": "enforce",
                    "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "1",
                },
                clear=False,
            ):
                self.establish_primary(runtime, state)
                result = self.run_hook(
                    runtime, state, "cat " + SECONDARY, "real-exact"
                )
            self.assertEqual(
                result["hookSpecificOutput"]["permissionDecision"], "deny"
            )
            event = self.opportunities(runtime)[-1]
            self.assertEqual(event["recall_outcome"], "focused_hit")
            query = memory._read_jsonl(runtime.telemetry_path)[-1]
            self.assertEqual(query["confidence"], "exact")
            self.assertFalse(query["truncated"])


if __name__ == "__main__":
    unittest.main()
