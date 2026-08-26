#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any


CODEX_MEMORY_DIR = Path(__file__).resolve().parents[1]
if str(CODEX_MEMORY_DIR) not in sys.path:
    sys.path.insert(0, str(CODEX_MEMORY_DIR))

import memory  # noqa: E402


SESSION = "5" * 16
DOCUMENT = "d" * 16
VERSION_ONE = "1" * 16
VERSION_TWO = "2" * 16
VERSION_THREE = "3" * 16
MISSING = object()


def runtime_for(root: Path) -> memory.Runtime:
    state = root / "state"
    return memory.Runtime(
        root=root,
        config_path=root / "config.json",
        config={},
        config_sha256="fixture",
        state_dir=state,
        db_path=state / "graph.db",
        manifest_path=state / "manifest.json",
        telemetry_path=state / "usage.jsonl",
        hook_events_path=state / "hook-events.jsonl",
    )


def append_read(
    runtime: memory.Runtime,
    *,
    agent: str,
    session: str = SESSION,
    version: str = VERSION_ONE,
    total_lines: int = 1000,
    covered_lines: int = 0,
    ranges: object = MISSING,
    confirmed: bool = True,
    estimated_tokens: int = 10,
) -> None:
    detail: dict[str, Any] = {
        "document_sha256": DOCUMENT,
        "version_sha256": version,
        "covered_lines": covered_lines,
        "total_lines": total_lines,
        "complete": covered_lines >= total_lines,
        "confirmed": confirmed,
        "estimated_tokens": estimated_tokens,
    }
    if ranges is not MISSING:
        detail["ranges"] = ranges
    memory._append_jsonl(
        runtime.hook_events_path,
        {
            "schema_version": 1,
            "ts": memory.dt.datetime.now(memory.dt.timezone.utc).isoformat(),
            "codex_session_sha256": session,
            "agent_sha256": agent,
            "event": "document_read",
            "documents": 1,
            "whole_documents": 0,
            "estimated_tokens": estimated_tokens,
            "coverage": [detail],
        },
    )


def write_state(runtime: memory.Runtime, name: str, value: dict[str, Any]) -> None:
    path = runtime.state_dir / "hook-state" / (SESSION + "-" + name + ".json")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


class MemoryCoverageMetricsTest(unittest.TestCase):
    def test_cross_agent_ranges_union_and_unconfirmed_tail_does_not_erase(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_read(
                runtime,
                agent="root",
                covered_lines=500,
                ranges=[[1, 500]],
                estimated_tokens=10,
            )
            append_read(
                runtime,
                agent="a" * 16,
                covered_lines=300,
                ranges=[[401, 700]],
                estimated_tokens=20,
            )
            append_read(
                runtime,
                agent="b" * 16,
                covered_lines=150,
                ranges=[[701, 850]],
                estimated_tokens=30,
            )
            append_read(
                runtime,
                agent="b" * 16,
                covered_lines=150,
                ranges=[[701, 850]],
                confirmed=False,
                estimated_tokens=40,
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["document_read_calls"], 4)
            self.assertEqual(value["estimated_document_read_tokens"], 100)
            self.assertEqual(value["estimated_confirmed_document_tokens"], 60)
            self.assertEqual(value["estimated_unconfirmed_document_tokens"], 40)
            self.assertEqual(value["unique_documents"], 1)
            self.assertEqual(value["first_pass_covered_lines"], 850)
            self.assertEqual(value["first_pass_total_lines"], 1000)
            self.assertEqual(value["first_pass_coverage"], 0.85)
            self.assertTrue(value["first_pass_coverage_exact"])
            self.assertEqual(value["first_pass_coverage_source"], "event_ranges")
            self.assertEqual(value["cross_agent_document_overlap_lines"], 100)
            self.assertEqual(value["cross_agent_overlapping_documents"], 1)
            self.assertEqual(value["cross_agent_multi_agent_documents"], 1)
            self.assertTrue(value["cross_agent_overlap_exact"])

    def test_duplicate_overlapping_snapshots_do_not_double_count(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_read(runtime, agent="root", covered_lines=400, ranges=[[1, 400]])
            append_read(runtime, agent="root", covered_lines=400, ranges=[[1, 400]])
            append_read(
                runtime,
                agent="a" * 16,
                covered_lines=401,
                ranges=[[300, 700]],
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["first_pass_covered_lines"], 700)
            self.assertEqual(value["completed_first_pass_documents"], 0)
            self.assertEqual(value["cross_agent_document_overlap_lines"], 101)

    def test_latest_task_epoch_prevents_same_version_rotation_overstatement(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_read(runtime, agent="root", covered_lines=100, ranges=[[1, 100]])
            rows = memory._read_jsonl(runtime.hook_events_path)
            rows[0]["task_epoch_sha256"] = "a" * 16
            runtime.hook_events_path.write_text(
                "".join(memory._canonical_json(row) + "\n" for row in rows),
                encoding="utf-8",
            )
            append_read(runtime, agent="root", covered_lines=20, ranges=[[1, 20]])
            rows = memory._read_jsonl(runtime.hook_events_path)
            rows[-1]["task_epoch_sha256"] = "b" * 16
            runtime.hook_events_path.write_text(
                "".join(memory._canonical_json(row) + "\n" for row in rows),
                encoding="utf-8",
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["document_read_calls"], 2)
            self.assertEqual(value["first_pass_covered_lines"], 20)
            self.assertEqual(value["first_pass_total_lines"], 1000)
            self.assertEqual(value["first_pass_coverage"], 0.02)

    def test_all_selector_does_not_apply_one_sessions_latest_epoch_globally(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_read(
                runtime,
                agent="root",
                session="6" * 16,
                covered_lines=100,
                ranges=[[1, 100]],
            )
            append_read(
                runtime,
                agent="root",
                session="7" * 16,
                covered_lines=100,
                ranges=[[101, 200]],
            )
            rows = memory._read_jsonl(runtime.hook_events_path)
            rows[0]["task_epoch_sha256"] = "a" * 16
            rows[1]["task_epoch_sha256"] = "b" * 16
            runtime.hook_events_path.write_text(
                "".join(memory._canonical_json(row) + "\n" for row in rows),
                encoding="utf-8",
            )

            value = memory.stats(runtime, selector="all")

            self.assertEqual(value["document_read_calls"], 2)
            self.assertEqual(value["first_pass_covered_lines"], 200)
            self.assertEqual(value["first_pass_total_lines"], 1000)

    def test_latest_observed_version_never_merges_incompatible_ranges(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_read(
                runtime,
                agent="root",
                version=VERSION_ONE,
                total_lines=100,
                covered_lines=100,
                ranges=[[1, 100]],
            )
            append_read(
                runtime,
                agent="root",
                version=VERSION_TWO,
                total_lines=100,
                covered_lines=20,
                ranges=[[81, 100]],
            )
            append_read(
                runtime,
                agent="root",
                version=VERSION_TWO,
                total_lines=100,
                covered_lines=20,
                ranges=[[81, 100]],
                confirmed=False,
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["first_pass_covered_lines"], 20)
            self.assertEqual(value["first_pass_total_lines"], 100)
            self.assertEqual(value["completed_first_pass_documents"], 0)

            append_read(
                runtime,
                agent="root",
                version=VERSION_THREE,
                total_lines=120,
                covered_lines=0,
                ranges=[],
                confirmed=False,
            )
            changed = memory.stats(runtime, selector=SESSION)
            self.assertEqual(changed["first_pass_covered_lines"], 0)
            self.assertEqual(changed["first_pass_total_lines"], 120)

    def test_legacy_events_use_current_epoch_hook_state_for_exact_union(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_read(runtime, agent="root", total_lines=1486, covered_lines=1026)
            append_read(
                runtime,
                agent="a" * 16,
                total_lines=1486,
                covered_lines=786,
            )
            append_read(
                runtime,
                agent="a" * 16,
                total_lines=1486,
                covered_lines=786,
                confirmed=False,
            )
            epoch = "e" * 16
            write_state(
                runtime,
                "root",
                {
                    "session_sha256": SESSION,
                    "agent_sha256": "root",
                    "task_epoch_sha256": epoch,
                    "documents": {
                        DOCUMENT: {
                            "version_sha256": VERSION_ONE,
                            "total_lines": 1486,
                            "ranges": [[328, 1353]],
                        }
                    },
                },
            )
            write_state(
                runtime,
                "agent",
                {
                    "session_sha256": SESSION,
                    "agent_sha256": "a" * 16,
                    "task_epoch_sha256": epoch,
                    "documents": {
                        DOCUMENT: {
                            "version_sha256": VERSION_ONE,
                            "total_lines": 1486,
                            "ranges": [[701, 1486]],
                        }
                    },
                },
            )
            write_state(
                runtime,
                "stale",
                {
                    "session_sha256": SESSION,
                    "agent_sha256": "b" * 16,
                    "task_epoch_sha256": "stale",
                    "documents": {
                        DOCUMENT: {
                            "version_sha256": VERSION_ONE,
                            "total_lines": 1486,
                            "ranges": [[1, 1486]],
                        }
                    },
                },
            )
            write_state(
                runtime,
                "shared",
                {
                    "session_sha256": SESSION,
                    "task_epoch_sha256": epoch,
                    "primary": {
                        "document_sha256": DOCUMENT,
                        "version_sha256": VERSION_ONE,
                        "total_lines": 1486,
                        "ranges": [[328, 1486]],
                    },
                },
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["first_pass_covered_lines"], 1159)
            self.assertEqual(value["first_pass_total_lines"], 1486)
            self.assertEqual(value["first_pass_coverage"], 0.78)
            self.assertTrue(value["first_pass_coverage_exact"])
            self.assertEqual(value["first_pass_coverage_source"], "hook_state")

    def test_legacy_rows_without_state_are_conservative_and_explicit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_read(runtime, agent="root", covered_lines=700)
            append_read(runtime, agent="a" * 16, covered_lines=600)

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["first_pass_covered_lines"], 700)
            self.assertFalse(value["first_pass_coverage_exact"])
            self.assertEqual(
                value["first_pass_coverage_source"], "legacy_conservative"
            )

    def test_overlap_is_unknown_when_shared_union_lacks_per_agent_attribution(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_read(
                runtime,
                agent="root",
                total_lines=100,
                covered_lines=50,
                ranges=[[1, 50]],
            )
            epoch = "e" * 16
            write_state(
                runtime,
                "root",
                {
                    "session_sha256": SESSION,
                    "agent_sha256": "root",
                    "task_epoch_sha256": epoch,
                    "documents": {
                        DOCUMENT: {
                            "version_sha256": VERSION_ONE,
                            "total_lines": 100,
                            "ranges": [[1, 50]],
                        }
                    },
                },
            )
            write_state(
                runtime,
                "shared",
                {
                    "session_sha256": SESSION,
                    "task_epoch_sha256": epoch,
                    "primary": {
                        "document_sha256": DOCUMENT,
                        "version_sha256": VERSION_ONE,
                        "total_lines": 100,
                        "ranges": [[1, 100]],
                    },
                },
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["first_pass_covered_lines"], 100)
            self.assertTrue(value["first_pass_coverage_exact"])
            self.assertEqual(value["cross_agent_document_overlap_lines"], 0)
            self.assertFalse(value["cross_agent_overlap_exact"])

    def test_malformed_ranges_are_clamped_without_overstatement(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_read(
                runtime,
                agent="root",
                total_lines=100,
                covered_lines=21,
                ranges=[[0, 20], [80, 120], [70, 60], "not-a-range"],
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["first_pass_covered_lines"], 21)
            self.assertLessEqual(
                value["first_pass_covered_lines"], value["first_pass_total_lines"]
            )

    def test_primary_output_guidance_is_not_retrieval_savings(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            memory._append_jsonl(
                runtime.hook_events_path,
                {
                    "schema_version": 4,
                    "policy_version": 4,
                    "ts": memory.dt.datetime.now(memory.dt.timezone.utc).isoformat(),
                    "codex_session_sha256": SESSION,
                    "event": "retrieval_opportunity",
                    "opportunity_sha256": "a" * 16,
                    "raw_read_intent_sha256": "b" * 16,
                    "kind": "primary_read",
                    "eligible": False,
                    "exclusion": "primary_output_cap",
                    "mode": "inject",
                    "recall_attempted": False,
                    "recall_outcome": "not_attempted",
                    "grounded": False,
                    "action": "exempt",
                    "blocked": False,
                    "estimated_raw_tokens": 9000,
                    "estimated_avoided_tokens": 0,
                    "delivered_context_tokens": 0,
                    "guided": True,
                    "guidance_reason": "output_cap",
                    "guidance_action": "deny",
                    "output_safety_blocked": True,
                    "guidance_context_tokens": 80,
                    "shared_covered_lines": 400,
                    "missing_lines": 600,
                    "suggested_range_count": 1,
                },
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["primary_guidance_events"], 1)
            self.assertEqual(value["primary_guidance_actions"], {"deny": 1})
            self.assertEqual(value["primary_guidance_reasons"], {"output_cap": 1})
            self.assertEqual(value["primary_guidance_output_safety_blocks"], 1)
            self.assertEqual(value["primary_guidance_context_tokens"], 80)
            self.assertEqual(value["retrieval_attempted_opportunities"], 0)
            self.assertEqual(value["retrieval_grounded_blocks"], 0)
            self.assertEqual(value["retrieval_unique_blocked_intents"], 0)
            self.assertEqual(value["retrieval_gross_avoided_tokens"], 0)
            self.assertEqual(value["retrieval_direct_net_avoided_tokens"], 0)
            rendered = memory._render_stats(value)
            self.assertIn("Primary range guidance: 1 events/1", rendered)
            self.assertIn("actions {'deny': 1}", rendered)


if __name__ == "__main__":
    unittest.main()
