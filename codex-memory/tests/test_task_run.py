#!/usr/bin/env python3

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import stat
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


CODEX_MEMORY_DIR = Path(__file__).resolve().parents[1]
if str(CODEX_MEMORY_DIR) not in sys.path:
    sys.path.insert(0, str(CODEX_MEMORY_DIR))

import task_run  # noqa: E402


UTC = dt.timezone.utc
BASE = dt.datetime(2026, 1, 2, 12, 0, tzinfo=UTC)
MISSING = object()
REQUEST_IDENTITY = {
    "task_request_sha256": "f" * 32,
    "task_request_count": 1,
    "task_request_key_sha256": "e" * 32,
}


def at(minutes: float = 0) -> dt.datetime:
    return BASE + dt.timedelta(minutes=minutes)


def vector(
    input_tokens: int,
    output_tokens: int,
    *,
    cached_input_tokens: int = 0,
    cache_write_input_tokens: int | object = 0,
    reasoning_output_tokens: int = 0,
    total_tokens: int | None = None,
) -> dict[str, int]:
    result = {
        "input_tokens": input_tokens,
        "cached_input_tokens": cached_input_tokens,
        "output_tokens": output_tokens,
        "reasoning_output_tokens": reasoning_output_tokens,
        "total_tokens": input_tokens + output_tokens if total_tokens is None else total_tokens,
    }
    if cache_write_input_tokens is not MISSING:
        result["cache_write_input_tokens"] = int(cache_write_input_tokens)
    return result


def token_event(
    when: dt.datetime,
    total: dict[str, int],
    last: dict[str, int],
) -> dict[str, object]:
    return {
        "timestamp": when.isoformat(),
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "info": {"total_token_usage": total, "last_token_usage": last},
        },
    }


def task_event(
    when: dt.datetime,
    turn_id: str,
    *,
    ordinal: int | None = None,
) -> dict[str, object]:
    result: dict[str, object] = {
        "timestamp": when.isoformat(),
        "type": "event_msg",
        "payload": {
            "type": "task_started",
            "turn_id": turn_id,
            "started_at": when.isoformat(),
        },
    }
    if ordinal is not None:
        result["ordinal"] = ordinal
    return result


def terminal_event(
    when: dt.datetime,
    turn_id: str,
    *,
    ordinal: int | None = None,
    kind: str = "task_complete",
) -> dict[str, object]:
    result: dict[str, object] = {
        "timestamp": when.isoformat(),
        "type": "event_msg",
        "payload": {
            "type": kind,
            "turn_id": turn_id,
            "completed_at": when.isoformat(),
        },
    }
    if ordinal is not None:
        result["ordinal"] = ordinal
    return result


def user_message_event(
    when: dt.datetime,
    text: str,
    *,
    ordinal: int | None = None,
) -> dict[str, object]:
    result: dict[str, object] = {
        "timestamp": when.isoformat(),
        "type": "response_item",
        "payload": {
            "type": "message",
            "role": "user",
            "content": [{"type": "input_text", "text": text}],
        },
    }
    if ordinal is not None:
        result["ordinal"] = ordinal
    return result


def meta_event(
    when: dt.datetime,
    thread_id: str,
    session_id: str,
    **lineage: object,
) -> dict[str, object]:
    payload: dict[str, object] = {
        "id": thread_id,
        "session_id": session_id,
        "timestamp": when.isoformat(),
        "cli_version": "0.test",
        "thread_source": "user",
    }
    payload.update(lineage)
    return {"timestamp": when.isoformat(), "type": "session_meta", "payload": payload}


def write_jsonl(path: Path, rows: list[dict[str, object]], *, truncated: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = "".join(json.dumps(row, sort_keys=True) + "\n" for row in rows)
    if truncated:
        text += '{"timestamp":"unterminated"'
    path.write_text(text, encoding="utf-8")


def exact_metrics(input_tokens: int, total_tokens: int, *, estimate: int = 0) -> dict[str, object]:
    return {
        "tokens": {
            "combined": {
                "exact": True,
                "input": input_tokens,
                "cached_input": 0,
                "uncached_input": input_tokens,
                "cache_write_input": 0,
                "output": total_tokens - input_tokens,
                "reasoning_output": 0,
                "total": total_tokens,
                "request_count": 1,
                "errors": [],
            }
        },
        "memory": {
            "opportunity": {"retrieval_direct_net_avoided_tokens": estimate},
        },
        "graphify": {
            "shared_usage": {"result_tokens_estimate": estimate},
            "estimates_are_diagnostic_only": True,
        },
        "rollout_boundary": {"terminal_kind": "task_complete"},
    }


def frozen_gate_evidence(
    *,
    unit_definition: str = "1" * 16,
    held_definition: str = "2" * 16,
    unit_source: str = "executed",
    held_source: str = "executed",
) -> dict[str, object]:
    gates = {
        "unit": {
            "source": unit_source,
            "definition_sha256": unit_definition,
            "result_sha256": "a" * 16,
        },
        "heldout": {
            "source": held_source,
            "definition_sha256": held_definition,
            "result_sha256": "b" * 16,
        },
    }
    comparable = {
        gate_id: {
            "source": value["source"],
            "definition_sha256": value["definition_sha256"],
        }
        for gate_id, value in gates.items()
    }
    return {
        "complete": True,
        "gates": gates,
        "definition_set_sha256": task_run._digest(task_run._canonical(comparable)),
    }


def start_row(
    run_id: str,
    variant: str,
    replicate: int,
    *,
    task_hash: str = "taskhash",
    model: str = "gpt-test",
    effort: str = "high",
    worktree: str = "worktree",
    memory_config: str = "memory-config",
    hooks: str = "hooks",
    provider: str = "provider",
    context_window: str = "context-window",
    policy_tuning: str = "policy-tuning",
    profile_match: bool = True,
) -> dict[str, object]:
    return {
        "type": "start",
        "run_sha256": run_id,
        "task_sha256": task_hash,
        **REQUEST_IDENTITY,
        "variant": variant,
        "replicate": replicate,
        "profile_match": profile_match,
        "fresh_session_eligible": True,
        "diagnostic_only": False,
        "repo_start": {"head_sha256": "head", "worktree_sha256": worktree},
        "environment": {
            "model": model,
            "reasoning_effort": effort,
            "cli_version": "0.test",
            "service_tier": "priority",
            "model_provider_sha256": provider,
            "context_window_sha256": context_window,
            "cwd_sha256": "c" * 32,
            "workspace_roots_sha256": "d" * 32,
            "cwd_available": True,
            "workspace_roots_available": True,
        },
        "tool_start": {"memory_config": memory_config, "hooks": hooks},
        "device_matrix_sha256": "device",
        "gate_set_sha256": "gates",
        "required_gates": ["unit"],
        "held_out_gates": ["heldout"],
        "allow_na_gates": [],
        "review_rubric_sha256": "none",
        "policy": {"mode": variant},
        "policy_tuning_sha256": policy_tuning,
        "started_at": BASE.isoformat(),
    }


def finish_row(
    run_id: str,
    input_tokens: int,
    total_tokens: int,
    *,
    quality: str = "pass",
    estimate: int = 0,
    policy_intact: bool = True,
) -> dict[str, object]:
    return {
        "type": "finish",
        "run_sha256": run_id,
        **REQUEST_IDENTITY,
        "ended_at": at(10).isoformat(),
        "quality": {
            "status": quality,
            "defects": {"critical": 0, "major": 0, "minor": 0},
            "policy_intact": policy_intact,
            "comparison_quality_evidence": True,
            "gates": {"statuses": {"unit": "pass", "heldout": "pass"}},
        },
        "gate_evidence": frozen_gate_evidence(),
        "metrics": exact_metrics(input_tokens, total_tokens, estimate=estimate),
        "complete": True,
    }


class TokenAccountingTest(unittest.TestCase):
    def test_start_ordinal_separates_equal_timestamp_snapshots(self) -> None:
        before = token_event(at(), vector(100, 20), vector(100, 20))
        before["ordinal"] = 1_000_000_000_000
        boundary = task_event(at(), "measured-turn", ordinal=1_000_000_000_010)
        after = token_event(at(), vector(130, 26), vector(30, 6))
        after["ordinal"] = 1_000_000_000_020
        rows = [before, boundary, after]

        result = task_run.token_interval(
            rows,
            at(),
            at(1),
            require_baseline=True,
            start_ordinal=1_000_000_000_010,
        )

        self.assertTrue(result["exact"], result["errors"])
        self.assertEqual(result["input"], 30)
        self.assertEqual(result["output"], 6)
        self.assertEqual(result["total"], 36)

    def test_first_in_scope_snapshot_uses_total_minus_last_then_deltas(self) -> None:
        first_total = vector(
            150, 30, cached_input_tokens=60, cache_write_input_tokens=6,
            reasoning_output_tokens=7,
        )
        first_last = vector(
            50, 10, cached_input_tokens=20, cache_write_input_tokens=2,
            reasoning_output_tokens=2,
        )
        second_total = vector(
            180, 36, cached_input_tokens=75, cache_write_input_tokens=9,
            reasoning_output_tokens=9,
        )
        second_last = vector(
            30, 6, cached_input_tokens=15, cache_write_input_tokens=3,
            reasoning_output_tokens=2,
        )
        rows = [
            task_event(at(-30), "prior-turn"),
            task_event(at(), "measured-turn"),
            token_event(at(1), first_total, first_last),
            token_event(at(2), second_total, second_last),
            # Codex can repeat the cumulative snapshot while leaving a
            # non-zero last_token_usage attached. It must add zero.
            token_event(at(3), second_total, second_last),
        ]

        result = task_run.token_interval(rows, at(), at(5), require_baseline=True)

        self.assertTrue(result["exact"], result["errors"])
        self.assertEqual(result["input"], 80)
        self.assertEqual(result["cached_input"], 35)
        self.assertEqual(result["uncached_input"], 45)
        self.assertEqual(result["cache_write_input"], 5)
        self.assertEqual(result["output"], 16)
        self.assertEqual(result["reasoning_output"], 4)
        self.assertEqual(result["total"], 96)
        self.assertEqual(result["request_count"], 2)
        self.assertEqual(result["duplicate_snapshots"], 1)

    def test_counter_reset_inside_task_begins_a_new_epoch(self) -> None:
        rows = [
            token_event(at(-1), vector(100, 20, cached_input_tokens=40), vector(100, 20, cached_input_tokens=40)),
            token_event(at(1), vector(150, 30, cached_input_tokens=60), vector(50, 10, cached_input_tokens=20)),
            token_event(at(2), vector(10, 2, cached_input_tokens=2), vector(10, 2, cached_input_tokens=2)),
        ]

        result = task_run.token_interval(rows, at(), at(5), require_baseline=True)

        self.assertTrue(result["exact"], result["errors"])
        self.assertEqual(result["input"], 60)
        self.assertEqual(result["cached_input"], 22)
        self.assertEqual(result["uncached_input"], 38)
        self.assertEqual(result["output"], 12)
        self.assertEqual(result["total"], 72)
        self.assertEqual(result["reset_epochs"], 1)
        self.assertEqual(result["request_count"], 2)

    def test_subset_counters_are_reported_without_double_counting(self) -> None:
        rows = [
            token_event(
                at(-1),
                vector(100, 20, cached_input_tokens=60, cache_write_input_tokens=30, reasoning_output_tokens=5),
                vector(100, 20, cached_input_tokens=60, cache_write_input_tokens=30, reasoning_output_tokens=5),
            ),
            token_event(
                at(1),
                vector(160, 30, cached_input_tokens=90, cache_write_input_tokens=45, reasoning_output_tokens=7),
                vector(60, 10, cached_input_tokens=30, cache_write_input_tokens=15, reasoning_output_tokens=2),
            ),
        ]
        result = task_run.token_interval(rows, at(), at(2))

        self.assertTrue(result["exact"], result["errors"])
        self.assertEqual(result["input"], 60)
        self.assertEqual(result["cached_input"], 30)
        self.assertEqual(result["uncached_input"], 30)
        self.assertEqual(result["cache_write_input"], 15)
        self.assertEqual(result["output"], 10)
        self.assertEqual(result["reasoning_output"], 2)
        # Cached, cache-write, and reasoning are subsets, not extra spend.
        self.assertEqual(result["total"], 70)

    def test_historical_missing_cache_write_stays_unavailable_but_exact(self) -> None:
        rows = [
            token_event(
                at(-1),
                vector(100, 20, cached_input_tokens=40, cache_write_input_tokens=MISSING),
                vector(100, 20, cached_input_tokens=40, cache_write_input_tokens=MISSING),
            ),
            token_event(
                at(1),
                vector(130, 25, cached_input_tokens=50, cache_write_input_tokens=MISSING),
                vector(30, 5, cached_input_tokens=10, cache_write_input_tokens=MISSING),
            ),
        ]

        result = task_run.token_interval(rows, at(), at(2))

        self.assertTrue(result["exact"], result["errors"])
        self.assertIsNone(result["cache_write_input"])
        self.assertEqual(result["uncached_input"], 20)
        self.assertEqual(result["total"], 35)

    def test_zero_snapshot_does_not_turn_absent_cache_write_into_zero(self) -> None:
        zero_without_cache_write = vector(
            0,
            0,
            cached_input_tokens=0,
            cache_write_input_tokens=MISSING,
            reasoning_output_tokens=0,
        )

        result = task_run.token_interval(
            [token_event(at(1), zero_without_cache_write, zero_without_cache_write)],
            at(),
            at(2),
            require_baseline=True,
        )

        self.assertTrue(result["exact"], result["errors"])
        self.assertEqual(result["input"], 0)
        self.assertEqual(result["total"], 0)
        self.assertIsNone(result["cache_write_input"])

    def test_malformed_or_inconsistent_usage_is_never_exact(self) -> None:
        inconsistent = token_event(
            at(1),
            vector(50, 10, cached_input_tokens=5, total_tokens=999),
            vector(10, 2, cached_input_tokens=1),
        )
        missing_total = token_event(
            at(2),
            {
                "input_tokens": 70,
                "cached_input_tokens": 7,
                "output_tokens": 14,
                "reasoning_output_tokens": 2,
            },
            {
                "input_tokens": 20,
                "cached_input_tokens": 2,
                "output_tokens": 4,
                "reasoning_output_tokens": 0,
            },
        )

        bad_invariant = task_run.token_interval([inconsistent], at(), at(3))
        unavailable_essential = task_run.token_interval([missing_total], at(), at(3))

        self.assertFalse(bad_invariant["exact"])
        self.assertIn("invalid_token_invariants", bad_invariant["errors"])
        self.assertFalse(unavailable_essential["exact"])
        self.assertIsNone(unavailable_essential["total"])


class SessionSelectionTest(unittest.TestCase):
    def test_first_session_meta_wins_and_lineage_forms_are_supported(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "rollout.jsonl"
            write_jsonl(
                path,
                [
                    meta_event(at(-2), "first-id", "first-id"),
                    meta_event(at(-1), "forged-later-id", "forged-later-id"),
                ],
            )

            self.assertEqual(task_run._first_meta(path)["id"], "first-id")
            self.assertEqual(task_run._parent_thread({"parent_thread_id": "parent-a"}), "parent-a")
            self.assertEqual(task_run._parent_thread({"forked_from_id": "parent-b"}), "parent-b")
            self.assertEqual(task_run._parent_thread({"forked_from": "parent-c"}), "parent-c")
            self.assertEqual(
                task_run._parent_thread(
                    {"source": {"subagent": {"thread_spawn": {"parent_thread_id": "parent-d"}}}}
                ),
                "parent-d",
            )

    def test_date_bounded_catalog_never_opens_unrelated_history(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            sessions_root = Path(temporary)
            in_window = sessions_root / "2026" / "01" / "02" / "in-window.jsonl"
            root_day = sessions_root / "2025" / "12" / "20" / "long-lived-root.jsonl"
            historical = sessions_root / "2001" / "01" / "01" / "must-not-open.jsonl"
            write_jsonl(in_window, [meta_event(at(), "in-window", "in-window")])
            write_jsonl(root_day, [meta_event(at(-60), "long-lived", "long-lived")])
            write_jsonl(historical, [meta_event(at(-60), "historical", "historical")])
            original_first_meta = task_run._first_meta

            def guarded_first_meta(path: Path) -> dict[str, object] | None:
                if path == historical:
                    raise AssertionError("date-bounded catalog opened unrelated history")
                return original_first_meta(path)

            with mock.patch.object(task_run, "_first_meta", side_effect=guarded_first_meta):
                catalog = task_run._session_catalog(
                    sessions_root,
                    start=at(),
                    end=at(10),
                    extra_dates=[dt.date(2025, 12, 20)],
                )

            self.assertEqual({item["id"] for item in catalog}, {"in-window", "long-lived"})

    def test_root_and_recursive_subagent_lanes_exclude_prior_later_and_other_siblings(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root_dir = Path(temporary)
            session = "root-thread"
            fixtures = {
                "root": (
                    meta_event(at(-60), session, session),
                    [
                        token_event(at(-1), vector(100, 20), vector(100, 20)),
                        task_event(at(), "measured"),
                        token_event(at(1), vector(110, 22), vector(10, 2)),
                    ],
                ),
                "child": (
                    meta_event(at(1), "child", session, parent_thread_id=session),
                    [token_event(at(1.5), vector(5, 1), vector(5, 1))],
                ),
                "grandchild": (
                    meta_event(at(2), "grandchild", session, forked_from="child"),
                    [token_event(at(2.5), vector(7, 2), vector(7, 2))],
                ),
                "prior": (
                    meta_event(at(-1), "prior", session, forked_from_id=session),
                    [token_event(at(3), vector(500, 100), vector(500, 100))],
                ),
                "later": (
                    meta_event(
                        at(11),
                        "later",
                        session,
                        source={"subagent": {"thread_spawn": {"parent_thread_id": session}}},
                    ),
                    [token_event(at(12), vector(600, 120), vector(600, 120))],
                ),
                "other-session": (
                    meta_event(at(1), "other", "other-session", parent_thread_id=session),
                    [token_event(at(2), vector(700, 140), vector(700, 140))],
                ),
            }
            for name, (meta, rows) in fixtures.items():
                write_jsonl(root_dir / f"{name}.jsonl", [meta, *rows])

            catalog = task_run._session_catalog(root_dir)
            root_session = next(item for item in catalog if item["id"] == session)
            tokens, included = task_run.collect_tokens(root_session, catalog, at(), at(10))

            self.assertEqual({item["id"] for item in included}, {session, "child", "grandchild"})
            self.assertEqual(tokens["included_threads"], {"root": 1, "subagent": 2, "combined": 3})
            self.assertEqual(tokens["root"]["total"], 12)
            self.assertEqual(tokens["subagent"]["total"], 15)
            self.assertEqual(tokens["combined"]["total"], 27)
            self.assertTrue(tokens["combined"]["exact"], tokens["combined"]["errors"])

    def test_reused_descendant_requires_new_task_and_its_matching_terminal(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root_dir = Path(temporary)
            session = "root-reused"
            root_path = root_dir / "root.jsonl"
            reused_path = root_dir / "reused.jsonl"
            background_path = root_dir / "background.jsonl"
            bad_path = root_dir / "unterminated.jsonl"
            root_before = token_event(at(-1), vector(100, 20), vector(100, 20))
            root_before["ordinal"] = 10
            root_after = token_event(at(1), vector(110, 22), vector(10, 2))
            root_after["ordinal"] = 30
            write_jsonl(
                root_path,
                [
                    meta_event(at(-200), session, session),
                    root_before,
                    task_event(at(), "root-turn", ordinal=20),
                    root_after,
                    terminal_event(at(9), "root-turn", ordinal=40),
                ],
            )
            reused_tokens = token_event(at(2), vector(8, 2), vector(8, 2))
            reused_tokens["ordinal"] = 110
            write_jsonl(
                reused_path,
                [
                    meta_event(at(-100), "reused", session, parent_thread_id=session),
                    task_event(at(1), "reused-current", ordinal=100),
                    reused_tokens,
                    terminal_event(at(3), "reused-current", ordinal=120),
                ],
            )
            background_tokens = token_event(at(2), vector(900, 100), vector(900, 100))
            background_tokens["ordinal"] = 210
            write_jsonl(
                background_path,
                [
                    meta_event(at(-100), "old-background", session, parent_thread_id=session),
                    background_tokens,
                ],
            )

            catalog = task_run._session_catalog(root_dir)
            root_session = next(item for item in catalog if item["id"] == session)
            tokens, included = task_run.collect_tokens(
                root_session,
                catalog,
                at(),
                at(10),
                root_start_ordinal=20,
                root_end_ordinal=40,
                require_complete_logs=True,
            )

            self.assertEqual({item["id"] for item in included}, {session, "reused"})
            self.assertEqual(tokens["subagent"]["total"], 10)
            self.assertTrue(tokens["combined"]["exact"], tokens["combined"]["errors"])

            bad_tokens = token_event(at(2), vector(9, 2), vector(9, 2))
            bad_tokens["ordinal"] = 310
            write_jsonl(
                bad_path,
                [
                    meta_event(at(-100), "unterminated", session, parent_thread_id=session),
                    task_event(at(1), "current-without-terminal", ordinal=300),
                    bad_tokens,
                    terminal_event(at(3), "different-turn", ordinal=320),
                ],
            )
            catalog = task_run._session_catalog(root_dir)
            tokens, included = task_run.collect_tokens(
                root_session,
                catalog,
                at(),
                at(10),
                root_start_ordinal=20,
                root_end_ordinal=40,
                require_complete_logs=True,
            )

            self.assertIn("unterminated", {item["id"] for item in included})
            self.assertFalse(tokens["combined"]["exact"])
            self.assertIn("unterminated_descendant", tokens["combined"]["errors"])

    def test_completed_descendant_without_token_snapshot_makes_total_inexact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root_dir = Path(temporary)
            session = "root-zero-child"
            root_path = root_dir / "root.jsonl"
            child_path = root_dir / "child.jsonl"
            root_tokens = token_event(at(1), vector(10, 2), vector(10, 2))
            root_tokens["ordinal"] = 20
            write_jsonl(
                root_path,
                [
                    meta_event(at(-1), session, session),
                    task_event(at(), "root-turn", ordinal=10),
                    root_tokens,
                    terminal_event(at(5), "root-turn", ordinal=30),
                ],
            )
            write_jsonl(
                child_path,
                [
                    meta_event(at(1), "child-no-tokens", session, parent_thread_id=session),
                    task_event(at(1.1), "child-turn", ordinal=10),
                    terminal_event(at(2), "child-turn", ordinal=20),
                ],
            )

            catalog = task_run._session_catalog(root_dir)
            root_session = next(item for item in catalog if item["id"] == session)
            tokens, included = task_run.collect_tokens(
                root_session,
                catalog,
                at(),
                at(5),
                root_start_ordinal=10,
                root_end_ordinal=30,
                require_complete_logs=True,
            )

            self.assertEqual({item["id"] for item in included}, {session, "child-no-tokens"})
            self.assertFalse(tokens["subagent"]["exact"])
            self.assertFalse(tokens["combined"]["exact"])
            self.assertIn("no_token_snapshot_in_interval", tokens["combined"]["errors"])

    def test_completed_root_with_only_zero_snapshot_is_not_exact_usage(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root_dir = Path(temporary)
            session = "root-zero-usage"
            root_path = root_dir / "root.jsonl"
            zero = token_event(at(1), vector(0, 0), vector(0, 0))
            zero["ordinal"] = 20
            write_jsonl(
                root_path,
                [
                    meta_event(at(-1), session, session),
                    task_event(at(), "root-turn", ordinal=10),
                    zero,
                    terminal_event(at(2), "root-turn", ordinal=30),
                ],
            )

            catalog = task_run._session_catalog(root_dir)
            root_session = next(item for item in catalog if item["id"] == session)
            tokens, _ = task_run.collect_tokens(
                root_session,
                catalog,
                at(),
                at(2),
                root_start_ordinal=10,
                root_end_ordinal=30,
                require_complete_logs=True,
            )

            self.assertEqual(tokens["root"]["request_count"], 0)
            self.assertFalse(tokens["root"]["exact"])
            self.assertFalse(tokens["combined"]["exact"])
            self.assertIn("no_model_request_usage", tokens["combined"]["errors"])

    def test_terminal_boundary_returns_explicit_numeric_ordinal(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "rollout.jsonl"
            turn = "numeric-boundary-turn"
            write_jsonl(
                path,
                [
                    meta_event(at(-1), "root", "root"),
                    task_event(at(), turn, ordinal=7_000_000_000),
                    terminal_event(at(1), turn, ordinal=7_000_000_099),
                ],
            )
            result = task_run._terminal_boundary(
                path,
                {
                    "start_ordinal": 7_000_000_000,
                    "task_turn_sha256": task_run._digest(turn),
                },
            )

            self.assertIsNotNone(result)
            self.assertEqual(result["ordinal"], 7_000_000_099)
            self.assertIsInstance(result["ordinal"], int)

    def test_task_environment_comes_from_actual_turn_not_config_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "rollout.jsonl"
            write_jsonl(
                path,
                [
                    meta_event(
                        at(-1),
                        "environment-root",
                        "environment-root",
                        model_provider="openai-live",
                        context_window=200_000,
                    ),
                    {
                        "timestamp": at().isoformat(),
                        "type": "turn_context",
                        "payload": {
                            "turn_id": "wanted",
                            "model": "rollout-model",
                            "effort": "xhigh",
                            "cwd": "/private/project",
                            "workspace_roots": ["/private/project"],
                        },
                    },
                    {
                        "timestamp": at(1).isoformat(),
                        "type": "turn_context",
                        "payload": {"turn_id": "other", "model": "wrong-model", "effort": "low"},
                    },
                ],
            )
            with mock.patch.object(
                task_run,
                "_codex_config",
                return_value={"model": "config-model", "reasoning_effort": "medium", "service_tier": "priority"},
            ):
                result = task_run._task_environment(
                    path,
                    "wanted",
                    "0.999",
                    100,
                    request_key_path=Path(temporary) / "request.key",
                )

            self.assertEqual(result["model"], "rollout-model")
            self.assertEqual(result["reasoning_effort"], "xhigh")
            self.assertEqual(result["service_tier"], "priority")
            self.assertEqual(result["cli_version"], "0.999")
            self.assertEqual(result["model_provider_sha256"], task_run._digest("openai-live"))
            self.assertEqual(
                result["context_window_sha256"],
                task_run._digest(task_run._canonical(200_000)),
            )
            self.assertTrue(result["cwd_available"])
            self.assertTrue(result["workspace_roots_available"])
            serialized = task_run._canonical(result)
            self.assertNotIn("/private/project", serialized)

    def test_real_integer_payload_timestamps_prefer_precise_top_level_iso(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "rollout.jsonl"
            turn = "real-schema-turn"
            started = BASE.replace(microsecond=123_456)
            completed = at(2).replace(microsecond=654_321)
            start_row_value = task_event(started, turn, ordinal=100)
            start_row_value["payload"]["started_at"] = int(BASE.timestamp())
            write_jsonl(path, [meta_event(at(-1), "root", "root"), start_row_value])

            selected = task_run._latest_task_started(path, before=at(5))

            self.assertEqual(selected["timestamp"], started)
            self.assertEqual(selected["index"], 100)

            terminal_row = terminal_event(completed, turn, ordinal=200)
            terminal_row["payload"]["completed_at"] = int(at(2).timestamp())
            write_jsonl(
                path,
                [meta_event(at(-1), "root", "root"), start_row_value, terminal_row],
            )
            terminal = task_run._terminal_boundary(
                path,
                {"start_ordinal": 100, "task_turn_sha256": task_run._digest(turn)},
            )

            self.assertIsNotNone(terminal)
            self.assertEqual(terminal["timestamp"], completed)
            self.assertEqual(terminal["ordinal"], 200)

    def test_truncated_or_other_turn_terminal_does_not_close_measured_turn(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "rollout.jsonl"
            measured_turn = "measured-turn"
            write_jsonl(
                path,
                [
                    meta_event(at(-1), "root", "root"),
                    task_event(at(), measured_turn),
                    {
                        "timestamp": at(1).isoformat(),
                        "type": "event_msg",
                        "payload": {"type": "task_complete", "turn_id": "other-turn"},
                    },
                ],
                truncated=True,
            )
            start = {
                "start_ordinal": 1,
                "task_turn_sha256": task_run._digest(measured_turn),
            }

            self.assertIsNone(task_run._terminal_boundary(path, start))


class DiagnosticsTest(unittest.TestCase):
    def test_memory_diagnostics_use_only_interval_events_and_never_live_state(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            telemetry = root / "usage.jsonl"
            hooks = root / "hook-events.jsonl"
            state = root / "hook-state.json"
            session = "s" * 16
            document = "d" * 16
            version = "v" * 16
            write_jsonl(
                telemetry,
                [
                    {"ts": at(-1).isoformat(), "codex_session_sha256": session, "operation": "query"},
                    {"ts": at(1).isoformat(), "codex_session_sha256": session, "operation": "query"},
                    {"ts": at(2).isoformat(), "codex_session_sha256": "other", "operation": "query"},
                    {"ts": at(11).isoformat(), "codex_session_sha256": session, "operation": "query"},
                ],
                truncated=True,
            )
            write_jsonl(
                hooks,
                [
                    {
                        "ts": at(-1).isoformat(),
                        "codex_session_sha256": session,
                        "event": "document_read",
                        "coverage": [{"document_sha256": document, "version_sha256": version, "ranges": [[1, 99]], "added_lines": 99, "total_lines": 100}],
                    },
                    {
                        "ts": at(1).isoformat(),
                        "codex_session_sha256": session,
                        "event": "document_read",
                        "coverage": [{"document_sha256": document, "version_sha256": version, "ranges": [[1, 10]], "added_lines": 10, "total_lines": 100}],
                    },
                    {
                        "ts": at(2).isoformat(),
                        "codex_session_sha256": session,
                        "event": "document_read",
                        "coverage": [{"document_sha256": document, "version_sha256": version, "ranges": [[8, 15]], "added_lines": 5, "total_lines": 100}],
                    },
                    {
                        "ts": at(11).isoformat(),
                        "codex_session_sha256": session,
                        "event": "document_read",
                        "coverage": [{"document_sha256": document, "version_sha256": version, "ranges": [[16, 100]], "added_lines": 85, "total_lines": 100}],
                    },
                ],
            )
            state.write_text(json.dumps({"coverage": [[1, 100]]}), encoding="utf-8")
            runtime = SimpleNamespace(
                telemetry_path=telemetry,
                hook_events_path=hooks,
                hook_state_path=state,
            )
            fake_memory = SimpleNamespace(
                load_runtime=lambda: runtime,
                _retrieval_opportunity_metrics=lambda usage, events: {
                    "usage_rows": len(usage),
                    "event_rows": len(events),
                },
            )
            with mock.patch.object(task_run, "_load_memory_module", return_value=fake_memory):
                result = task_run.memory_diagnostics(session, at(), at(10))

            self.assertEqual(result["query_count"], 1)
            self.assertEqual(result["hook_event_count"], 2)
            self.assertEqual(result["opportunity"], {"usage_rows": 1, "event_rows": 2})
            self.assertEqual(result["coverage"]["source"], "interval_event_ranges_only")
            self.assertFalse(result["coverage"]["hook_state_supplementation"])
            self.assertTrue(result["coverage"]["exact"])
            self.assertEqual(result["coverage"]["documents"], 1)
            self.assertEqual(result["coverage"]["covered_lines"], 15)
            self.assertEqual(result["coverage"]["total_lines"], 100)
            self.assertEqual(result["coverage"]["cross_agent_overlap_lines"], 0)

    def test_graphify_diagnostics_filter_rollout_and_shared_logs_to_interval(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            root_rollout = root / "root.jsonl"
            child_rollout = root / "child.jsonl"
            write_jsonl(
                root_rollout,
                [
                    {
                        "timestamp": at(-1).isoformat(),
                        "payload": {"type": "function_call", "call_id": "old", "input": {"cmd": "python3 graphify-arch/tdd_context.py query old"}},
                    },
                    {
                        "timestamp": at(1).isoformat(),
                        "payload": {"type": "function_call", "call_id": "root-q", "input": {"cmd": "python3 graphify-arch/tdd_context.py query focused"}},
                    },
                    {
                        "timestamp": at(1.1).isoformat(),
                        "payload": {"type": "function_call_output", "call_id": "root-q", "output": "compact context"},
                    },
                    {
                        "timestamp": at(1.2).isoformat(),
                        "payload": {
                            "type": "function_call",
                            "call_id": "root-code",
                            "input": {"cmd": "sed -n '1,20p' lib/a.dart; sed -n '1,20p' test/a_test.dart"},
                        },
                    },
                    {
                        "timestamp": at(1.3).isoformat(),
                        "payload": {"type": "function_call_output", "call_id": "root-code", "output": "code context"},
                    },
                ],
            )
            write_jsonl(
                child_rollout,
                [
                    {
                        "timestamp": at(2).isoformat(),
                        "payload": {"type": "custom_tool_call", "call_id": "child-native", "input": {"cmd": "python3 graphify-arch/tdd_context.py native Symbol"}},
                    },
                    {
                        "timestamp": at(2.1).isoformat(),
                        "payload": {"type": "custom_tool_call_output", "call_id": "child-native", "output": "native context"},
                    },
                    {
                        "timestamp": at(2.2).isoformat(),
                        "payload": {
                            "type": "custom_tool_call",
                            "call_id": "child-document",
                            "input": {"cmd": "sed -n '1,20p' docs/spec.md"},
                        },
                    },
                    {
                        "timestamp": at(2.3).isoformat(),
                        "payload": {"type": "custom_tool_call_output", "call_id": "child-document", "output": "document context"},
                    },
                    {
                        "timestamp": at(11).isoformat(),
                        "payload": {"type": "function_call", "call_id": "late", "input": {"cmd": "python3 graphify-arch/tdd_context.py affected lib/a.dart"}},
                    },
                ],
            )
            usage_path = root / "graphify-out" / "context_query_stats.jsonl"
            reminder_path = root / "graphify-arch" / "graphify-out" / "cache" / "codex-reminder" / "events.jsonl"
            session = "g" * 16
            root_id = "root-thread"
            child_id = "child-thread"
            write_jsonl(
                usage_path,
                [
                    {"ts": at(-1).isoformat(), "codex_session_sha256": session, "codex_thread_sha256": task_run._digest(root_id), "operation": "query", "result_tokens_estimate": 999},
                    {"ts": at(1).isoformat(), "codex_session_sha256": session, "codex_thread_sha256": task_run._digest(root_id), "operation": "query", "result_tokens_estimate": 10},
                    {"ts": at(2).isoformat(), "codex_session_sha256": session, "codex_thread_sha256": task_run._digest(child_id), "operation": "native", "result_tokens_estimate": 20, "truncated": True},
                    {"ts": at(11).isoformat(), "codex_session_sha256": session, "codex_thread_sha256": task_run._digest(root_id), "operation": "affected", "result_tokens_estimate": 999},
                ],
            )
            write_jsonl(
                reminder_path,
                [
                    {"ts": at(1).isoformat(), "codex_session_sha256": session, "event": "pre_tool", "blocked": True},
                    {"ts": at(11).isoformat(), "codex_session_sha256": session, "event": "pre_tool", "blocked": True},
                ],
            )
            included = [
                {"id": root_id, "path": root_rollout},
                {"id": child_id, "path": child_rollout},
            ]
            with mock.patch.object(task_run, "ROOT", root):
                result = task_run.graphify_diagnostics(session, included, root_id, at(), at(10))

            self.assertEqual(result["rollout"]["combined"]["tool_calls"], 2)
            self.assertEqual(result["rollout"]["combined"]["compact_queries"], 1)
            self.assertEqual(result["rollout"]["combined"]["native_queries"], 1)
            self.assertEqual(result["rollout"]["combined"]["affected_queries"], 0)
            self.assertEqual(result["rollout"]["combined"]["raw_code_tool_cells"], 1)
            self.assertEqual(result["rollout"]["combined"]["raw_document_tool_cells"], 1)
            self.assertNotIn("raw_code_read_calls", result["rollout"]["combined"])
            self.assertNotIn("raw_document_read_calls", result["rollout"]["combined"])
            self.assertEqual(result["shared_usage"]["count"], 2)
            self.assertEqual(result["shared_usage"]["root"], 1)
            self.assertEqual(result["shared_usage"]["subagent"], 1)
            self.assertEqual(result["shared_usage"]["result_tokens_estimate"], 30)
            self.assertEqual(result["shared_usage"]["truncated"], 1)
            self.assertEqual(result["shared_reminders"]["count"], 1)
            self.assertEqual(result["shared_reminders"]["blocked"], 1)
            self.assertTrue(result["estimates_are_diagnostic_only"])


class QualityAndComparisonTest(unittest.TestCase):
    def setUp(self) -> None:
        self.defects = {"critical": 0, "major": 0, "minor": 0}
        self.metrics = exact_metrics(100, 120)

    def test_gate_failure_is_permanent_even_when_latest_retry_passes(self) -> None:
        start = {
            "required_gates": ["unit"],
            "held_out_gates": ["held"],
            "allow_na_gates": ["held"],
        }
        passing_events = [
            {"type": "gate", "gate_id": "unit", "status": "fail"},
            {"type": "gate", "gate_id": "unit", "status": "pass"},
            {"type": "gate", "gate_id": "held", "status": "na"},
        ]
        assessed = task_run._gate_assessment(start, passing_events)
        self.assertFalse(assessed["pass"])
        self.assertEqual(assessed["statuses"], {"unit": "pass", "held": "na"})
        self.assertEqual(assessed["historical_failures"], ["unit"])
        self.assertEqual(assessed["attempt_counts"], {"unit": 2, "held": 1})
        self.assertEqual(
            task_run._quality(start, passing_events, self.metrics, "pass", self.defects, True)["status"],
            "fail",
        )

        missing = task_run._quality(start, [], self.metrics, "pass", self.defects, True)
        self.assertEqual(missing["status"], "incomplete")
        self.assertEqual(missing["gates"]["missing"], ["unit", "held"])

        failed_events = [
            {"type": "gate", "gate_id": "unit", "status": "fail"},
            {"type": "gate", "gate_id": "held", "status": "na"},
        ]
        self.assertEqual(
            task_run._quality(start, failed_events, self.metrics, "pass", self.defects, True)["status"],
            "fail",
        )

        no_gates = {"required_gates": [], "held_out_gates": [], "allow_na_gates": []}
        no_gate_quality = task_run._quality(no_gates, [], self.metrics, "pass", self.defects, True)
        self.assertFalse(no_gate_quality["gates"]["pass"])
        self.assertEqual(no_gate_quality["status"], "incomplete")

    def test_policy_mismatch_cannot_become_quality_pass_or_comparable(self) -> None:
        start = {"required_gates": ["unit"], "held_out_gates": [], "allow_na_gates": []}
        gates = [{"type": "gate", "gate_id": "unit", "status": "pass"}]
        policy_quality = task_run._quality(start, gates, self.metrics, "pass", self.defects, False)
        self.assertEqual(policy_quality["status"], "incomplete")
        self.assertFalse(policy_quality["policy_intact"])

        off_start = start_row("off-1", "off", 1)
        active_start = start_row("active-1", "active", 1, profile_match=False)
        off_finish = finish_row("off-1", 1000, 1200)
        active_finish = finish_row("active-1", 700, 840, quality="incomplete", policy_intact=False)
        result = task_run.compare_events(
            [off_start, active_start, off_finish, active_finish], "taskhash", 20,
        )["comparisons"]["off_to_active"]

        self.assertEqual(result["verdict"], "insufficient")
        self.assertEqual(result["comparable_quality_pass_pairs"], 0)
        self.assertEqual(result["mismatch_reasons"].get("policy_not_intact"), 1)

    def test_stored_pass_cannot_hide_rollover_liveness_failure(self) -> None:
        off_start = start_row("off-liveness", "off", 1)
        active_start = start_row("active-liveness", "active", 1)
        off_finish = finish_row("off-liveness", 1000, 1200)
        active_finish = finish_row("active-liveness", 700, 840)
        active_finish["metrics"]["rollover"] = {
            "combined": {"terminal_after_not_ready": 1}
        }

        result = task_run.compare_events(
            [off_start, active_start, off_finish, active_finish],
            "taskhash",
            20,
        )["comparisons"]["off_to_active"]

        self.assertEqual(result["comparable_quality_pass_pairs"], 0)
        self.assertEqual(result["mismatch_reasons"]["rollover_liveness_failure"], 1)
        self.assertEqual(result["mismatch_reasons"]["intervention_quality_failure"], 1)

    def test_environment_worktree_and_tool_mismatches_are_not_compared(self) -> None:
        off = start_row("off-mismatch", "off", 1)
        active = start_row(
            "active-mismatch",
            "active",
            1,
            model="different-model",
            worktree="different-worktree",
            memory_config="different-memory-config",
            provider="different-provider",
            context_window="different-context-window",
            policy_tuning="different-policy-tuning",
        )
        result = task_run.compare_events(
            [off, active, finish_row("off-mismatch", 1000, 1200), finish_row("active-mismatch", 500, 600)],
            "taskhash",
            20,
        )["comparisons"]["off_to_active"]

        self.assertEqual(result["verdict"], "insufficient")
        self.assertEqual(result["comparable_quality_pass_pairs"], 0)
        self.assertEqual(result["mismatch_reasons"]["model"], 1)
        self.assertEqual(result["mismatch_reasons"]["start_worktree"], 1)
        self.assertEqual(result["mismatch_reasons"]["memory_config"], 1)
        self.assertEqual(result["mismatch_reasons"]["model_provider"], 1)
        self.assertEqual(result["mismatch_reasons"]["context_window"], 1)
        self.assertEqual(result["mismatch_reasons"]["policy_tuning"], 1)

    def test_active_enforce_mode_is_rejected_from_the_causal_profile(self) -> None:
        policy = PrivacyAndDispatchTest._active_policy()
        self.assertEqual(task_run.profile_mismatches("active", policy), [])

        enforce = dict(policy)
        enforce["memory_secondary_mode"] = "enforce"

        self.assertIn("memory_secondary_mode", task_run.profile_mismatches("active", enforce))

    def test_graph_manifest_refresh_is_allowed_but_policy_code_changes_are_not(self) -> None:
        policy = PrivacyAndDispatchTest._active_policy()
        start = {
            "profile_match": True,
            "fresh_session_eligible": True,
            "policy": policy,
            "tool_start": {
                "memory_config": "memory-config",
                "hooks": "hooks",
                "policy_code_sha256": "policy-code",
                "memory_graph": "memory-graph-before",
                "graphify_arch": "arch-before",
                "graphify_full": "full-before",
            },
        }
        refreshed_graphs = {
            **start["tool_start"],
            "memory_graph": "memory-graph-after",
            "graphify_arch": "arch-after",
            "graphify_full": "full-after",
        }
        with mock.patch.object(task_run, "effective_policy", return_value=policy):
            intact, reasons = task_run._policy_intact(start, refreshed_graphs)
            self.assertTrue(intact, reasons)

            changed_hook = {**refreshed_graphs, "hooks": "changed-hooks"}
            intact, reasons = task_run._policy_intact(start, changed_hook)
            self.assertFalse(intact)
            self.assertIn("hooks_changed", reasons)

            changed_code = {**refreshed_graphs, "policy_code_sha256": "changed-policy-code"}
            intact, reasons = task_run._policy_intact(start, changed_code)
            self.assertFalse(intact)
            self.assertIn("policy_code_sha256_changed", reasons)

    def test_same_gate_id_with_different_executed_argv_is_not_comparable(self) -> None:
        off_start = start_row("off-gate-evidence", "off", 1)
        active_start = start_row("active-gate-evidence", "active", 1)
        off_finish = finish_row("off-gate-evidence", 1000, 1200)
        active_finish = finish_row("active-gate-evidence", 700, 840)
        start = {
            "required_gates": ["unit"],
            "held_out_gates": ["heldout"],
        }
        off_finish["gate_evidence"] = task_run._gate_evidence(
            start,
            [
                {"type": "gate", "gate_id": "unit", "source": "executed", "argv_sha256": "1" * 16, "output_sha256": "a" * 16},
                {"type": "gate", "gate_id": "heldout", "source": "executed", "argv_sha256": "2" * 16, "output_sha256": "b" * 16},
            ],
        )
        active_finish["gate_evidence"] = task_run._gate_evidence(
            start,
            [
                {"type": "gate", "gate_id": "unit", "source": "executed", "argv_sha256": "3" * 16, "output_sha256": "c" * 16},
                {"type": "gate", "gate_id": "heldout", "source": "executed", "argv_sha256": "2" * 16, "output_sha256": "d" * 16},
            ],
        )

        result = task_run.compare_events(
            [off_start, active_start, off_finish, active_finish],
            "taskhash",
            20,
        )["comparisons"]["off_to_active"]

        self.assertEqual(result["comparable_quality_pass_pairs"], 0)
        self.assertEqual(result["mismatch_reasons"]["gate_evidence_mismatch"], 1)

    def test_heldout_na_and_unbound_rubric_cannot_supply_quality_evidence(self) -> None:
        rubric = task_run._digest("manual-review-rubric-v1")
        off_start = start_row("off-na", "off", 1)
        active_start = start_row("active-na", "active", 1)
        for start in (off_start, active_start):
            start["allow_na_gates"] = ["heldout"]
            start["review_rubric_sha256"] = rubric
        off_finish = finish_row("off-na", 1000, 1200)
        active_finish = finish_row("active-na", 700, 840)
        off_finish["quality"]["gates"]["statuses"]["heldout"] = "na"
        active_finish["quality"]["gates"]["statuses"]["heldout"] = "na"

        result = task_run.compare_events(
            [off_start, active_start, off_finish, active_finish],
            "taskhash",
            20,
        )["comparisons"]["off_to_active"]

        self.assertEqual(result["comparable_quality_pass_pairs"], 0)
        self.assertEqual(result["mismatch_reasons"]["quality_evidence_missing"], 1)

    def test_properly_bound_recorded_review_is_comparable_quality_evidence(self) -> None:
        rubric = task_run._digest("manual-review-rubric-v2")
        off_start = start_row("off-recorded", "off", 1)
        active_start = start_row("active-recorded", "active", 1)
        for start in (off_start, active_start):
            start["review_rubric_sha256"] = rubric
        comparable = {
            "unit": {"source": "executed", "definition_sha256": "1" * 16},
            "heldout": {"source": "recorded", "definition_sha256": rubric},
        }
        evidence = {
            "complete": True,
            "gates": {
                "unit": {
                    "source": "executed",
                    "definition_sha256": "1" * 16,
                    "result_sha256": "a" * 16,
                },
                "heldout": {
                    "source": "recorded",
                    "definition_sha256": rubric,
                    "result_sha256": rubric,
                },
            },
            "definition_set_sha256": task_run._digest(task_run._canonical(comparable)),
        }
        off_finish = finish_row("off-recorded", 1000, 1200)
        active_finish = finish_row("active-recorded", 700, 840)
        for finish in (off_finish, active_finish):
            finish["quality"]["gates"]["statuses"] = {"unit": "pass", "heldout": "pass"}
            finish["gate_evidence"] = evidence

        result = task_run.compare_events(
            [off_start, active_start, off_finish, active_finish],
            "taskhash",
            20,
        )["comparisons"]["off_to_active"]

        self.assertEqual(result["comparable_quality_pass_pairs"], 1)
        self.assertNotIn("quality_evidence_missing", result["mismatch_reasons"])

    def test_failed_active_run_never_receives_a_savings_claim(self) -> None:
        rows = [
            start_row("off-fail", "off", 1),
            start_row("active-fail", "active", 1),
            finish_row("off-fail", 1000, 1200),
            finish_row("active-fail", 10, 12, quality="fail", estimate=999_999),
        ]

        comparison = task_run.compare_events(rows, "taskhash", 20)
        result = comparison["comparisons"]["off_to_active"]

        self.assertEqual(result["verdict"], "regressed")
        self.assertEqual(result["quality_verdict"], "regressed")
        self.assertEqual(result["comparable_quality_pass_pairs"], 0)
        self.assertEqual(result["pairs"], [])
        self.assertEqual(result["mismatch_reasons"]["quality_not_pass"], 1)
        self.assertEqual(result["mismatch_reasons"]["intervention_quality_failure"], 1)
        self.assertFalse(comparison["estimates_used_in_exact_tokens"])

    def test_one_failed_intervention_blocks_proof_from_three_passing_pairs(self) -> None:
        rows: list[dict[str, object]] = []
        for replicate in range(1, 5):
            off_id = f"off-survivorship-{replicate}"
            active_id = f"active-survivorship-{replicate}"
            active_quality = "fail" if replicate == 4 else "pass"
            rows.extend(
                [
                    start_row(off_id, "off", replicate),
                    start_row(active_id, "active", replicate),
                    finish_row(off_id, 1000, 1200),
                    finish_row(active_id, 700, 840, quality=active_quality),
                ]
            )

        result = task_run.compare_events(rows, "taskhash", 20)["comparisons"]["off_to_active"]

        self.assertEqual(result["comparable_quality_pass_pairs"], 3)
        self.assertEqual(result["mismatch_reasons"]["intervention_quality_failure"], 1)
        self.assertEqual(result["quality_verdict"], "regressed")
        self.assertEqual(result["verdict"], "regressed")

    def test_unmatched_failed_intervention_replicate_blocks_existing_proof(self) -> None:
        rows: list[dict[str, object]] = []
        for replicate in range(1, 4):
            off_id = f"off-unmatched-{replicate}"
            shadow_id = f"shadow-unmatched-{replicate}"
            active_id = f"active-unmatched-{replicate}"
            rows.extend(
                [
                    start_row(off_id, "off", replicate),
                    start_row(shadow_id, "shadow", replicate),
                    start_row(active_id, "active", replicate),
                    finish_row(off_id, 1000, 1200),
                    finish_row(shadow_id, 1000, 1200),
                    finish_row(active_id, 700, 840),
                ]
            )
        rows.extend(
            [
                start_row("active-unmatched-4", "active", 4),
                finish_row("active-unmatched-4", 10, 12, quality="fail"),
            ]
        )

        comparison = task_run.compare_events(rows, "taskhash", 20)

        self.assertEqual(comparison["negative_control"]["verdict"], "pass")
        for name in ("shadow_to_active", "off_to_active"):
            result = comparison["comparisons"][name]
            self.assertEqual(result["mismatch_reasons"]["missing_baseline_replicate"], 1)
            self.assertEqual(result["mismatch_reasons"]["intervention_quality_failure"], 1)
            self.assertEqual(result["quality_verdict"], "regressed")
            self.assertEqual(result["verdict"], "regressed")

    def test_one_incomplete_intervention_blocks_proof_from_three_passing_pairs(self) -> None:
        rows: list[dict[str, object]] = []
        for replicate in range(1, 5):
            off_id = f"off-incomplete-{replicate}"
            active_id = f"active-incomplete-{replicate}"
            active_quality = "incomplete" if replicate == 4 else "pass"
            rows.extend(
                [
                    start_row(off_id, "off", replicate),
                    start_row(active_id, "active", replicate),
                    finish_row(off_id, 1000, 1200),
                    finish_row(active_id, 700, 840, quality=active_quality),
                ]
            )

        result = task_run.compare_events(rows, "taskhash", 20)["comparisons"]["off_to_active"]

        self.assertEqual(result["comparable_quality_pass_pairs"], 3)
        self.assertEqual(result["mismatch_reasons"]["intervention_quality_incomplete"], 1)
        self.assertEqual(result["quality_verdict"], "insufficient")
        self.assertEqual(result["verdict"], "insufficient")

    def test_new_defects_or_more_repair_turns_invalidate_savings_pairs(self) -> None:
        off_one = finish_row("off-quality-1", 1000, 1200)
        active_one = finish_row("active-quality-1", 700, 840)
        active_one["quality"]["defects"]["major"] = 1
        off_two = finish_row("off-quality-2", 1000, 1200)
        active_two = finish_row("active-quality-2", 700, 840)
        off_two["repair_turns"] = 0
        active_two["repair_turns"] = 1
        rows = [
            start_row("off-quality-1", "off", 1),
            start_row("active-quality-1", "active", 1),
            off_one,
            active_one,
            start_row("off-quality-2", "off", 2),
            start_row("active-quality-2", "active", 2),
            off_two,
            active_two,
        ]

        result = task_run.compare_events(rows, "taskhash", 20)["comparisons"]["off_to_active"]

        self.assertEqual(result["comparable_quality_pass_pairs"], 0)
        self.assertEqual(result["mismatch_reasons"]["quality_regression"], 1)
        self.assertEqual(result["mismatch_reasons"]["new_major_defects"], 1)
        self.assertEqual(result["mismatch_reasons"]["repair_turn_increase"], 1)

    def test_executed_heldout_tests_cannot_claim_quality_improvement(self) -> None:
        rows: list[dict[str, object]] = []
        for replicate in range(1, 4):
            off_id = f"off-quality-evidence-{replicate}"
            active_id = f"active-quality-evidence-{replicate}"
            off_finish = finish_row(off_id, 1000, 1200)
            active_finish = finish_row(active_id, 700, 840)
            off_finish["quality"]["defects"]["major"] = 1
            rows.extend(
                [
                    start_row(off_id, "off", replicate),
                    start_row(active_id, "active", replicate),
                    off_finish,
                    active_finish,
                ]
            )

        result = task_run.compare_events(rows, "taskhash", 20)["comparisons"]["off_to_active"]

        self.assertEqual(result["quality_improved_pairs"], 3)
        self.assertEqual(result["blinded_quality_pairs"], 0)
        self.assertEqual(result["quality_verdict"], "noninferior")

    def test_three_quality_pass_pairs_use_exact_median_and_threshold(self) -> None:
        rows: list[dict[str, object]] = []
        active_inputs = [700, 750, 800]
        active_totals = [840, 900, 960]
        for replicate, (active_input, active_total) in enumerate(zip(active_inputs, active_totals), start=1):
            off_id = f"off-{replicate}"
            shadow_id = f"shadow-{replicate}"
            active_id = f"active-{replicate}"
            rows.extend(
                [
                    start_row(off_id, "off", replicate),
                    start_row(shadow_id, "shadow", replicate),
                    start_row(active_id, "active", replicate),
                    finish_row(off_id, 1000, 1200, estimate=1),
                    finish_row(shadow_id, 1000, 1200, estimate=1),
                    finish_row(active_id, active_input, active_total, estimate=900_000),
                ]
            )

        comparison = task_run.compare_events(rows, "taskhash", 20)
        result = comparison["comparisons"]["off_to_active"]

        self.assertEqual(comparison["negative_control"]["verdict"], "pass")
        self.assertEqual(result["verdict"], "proven")
        self.assertEqual(result["comparable_quality_pass_pairs"], 3)
        self.assertEqual(result["median_input_reduction_percent"], 25.0)
        self.assertEqual(result["median_total_reduction_percent"], 25.0)
        self.assertEqual([pair["input_reduction_percent"] for pair in result["pairs"]], [30.0, 25.0, 20.0])
        self.assertFalse(comparison["estimates_used_in_exact_tokens"])

        stricter = task_run.compare_events(rows, "taskhash", 26)["comparisons"]["off_to_active"]
        self.assertEqual(stricter["verdict"], "not_proven")

        first_two = [row for row in rows if not str(row.get("run_sha256", "")).endswith("-3")]
        insufficient = task_run.compare_events(first_two, "taskhash", 20)["comparisons"]["off_to_active"]
        self.assertEqual(insufficient["verdict"], "insufficient")

    def test_material_shadow_shift_confounds_every_active_savings_claim(self) -> None:
        rows: list[dict[str, object]] = []
        for replicate in range(1, 4):
            off_id = f"off-negative-control-{replicate}"
            shadow_id = f"shadow-negative-control-{replicate}"
            active_id = f"active-negative-control-{replicate}"
            rows.extend(
                [
                    start_row(off_id, "off", replicate),
                    start_row(shadow_id, "shadow", replicate),
                    start_row(active_id, "active", replicate),
                    finish_row(off_id, 1000, 1200),
                    finish_row(shadow_id, 700, 840),
                    finish_row(active_id, 700, 840),
                ]
            )

        comparison = task_run.compare_events(rows, "taskhash", 20)

        self.assertEqual(comparison["negative_control"]["verdict"], "failed")
        self.assertIn("input_token_shift", comparison["negative_control"]["reasons"])
        off_active = comparison["comparisons"]["off_to_active"]
        shadow_active = comparison["comparisons"]["shadow_to_active"]
        self.assertEqual(off_active["paired_token_verdict"], "proven")
        self.assertEqual(off_active["verdict"], "confounded")
        self.assertEqual(shadow_active["paired_token_verdict"], "not_proven")
        self.assertEqual(shadow_active["verdict"], "confounded")

    def test_finish_request_stream_mismatch_prevents_pairing(self) -> None:
        off_start = start_row("off-steering", "off", 1)
        active_start = start_row("active-steering", "active", 1)
        off_finish = finish_row("off-steering", 1000, 1200)
        active_finish = finish_row("active-steering", 700, 840)
        active_finish["task_request_sha256"] = "a" * 32

        result = task_run.compare_events(
            [off_start, active_start, off_finish, active_finish],
            "taskhash",
            20,
        )["comparisons"]["off_to_active"]

        self.assertEqual(result["comparable_quality_pass_pairs"], 0)
        self.assertEqual(result["mismatch_reasons"]["task_request"], 1)

    def test_active_report_is_provisional_even_when_live_counters_look_exact(self) -> None:
        start = start_row("active-live", "active", 1)
        with mock.patch.object(task_run, "_calculate_run", return_value=exact_metrics(100, 120)):
            report = task_run._public_report([start], live=True)

        self.assertFalse(report["complete"])
        self.assertTrue(report["provisional"])
        self.assertFalse(report["savings_eligible"])
        self.assertEqual(report["quality"]["status"], "incomplete")

    def test_completed_pass_without_comparison_quality_evidence_cannot_claim_savings(self) -> None:
        start = start_row("active-no-quality-evidence", "active", 1)
        finish = finish_row("active-no-quality-evidence", 700, 840)
        finish["quality"]["comparison_quality_evidence"] = False

        report = task_run._public_report([start, finish])

        self.assertTrue(report["complete"])
        self.assertEqual(report["quality"]["status"], "pass")
        self.assertFalse(report["comparison_eligible"])
        self.assertFalse(report["savings_eligible"])

    def test_completed_pass_is_only_a_pair_candidate_until_task_comparison(self) -> None:
        start = start_row("active-pair-candidate", "active", 1)
        finish = finish_row("active-pair-candidate", 700, 840)

        report = task_run._public_report([start, finish])

        self.assertTrue(report["comparison_eligible"])
        self.assertTrue(report["pair_candidate"])
        self.assertFalse(report["savings_eligible"])
        self.assertTrue(report["savings_requires_task_comparison"])

    def test_report_exposes_finish_policy_drift_and_diagnostic_state(self) -> None:
        start = start_row("active-policy-drift", "active", 1)
        start["diagnostic_only"] = True
        finish = finish_row(
            "active-policy-drift",
            700,
            840,
            quality="incomplete",
            policy_intact=False,
        )
        finish["comparability_environment_intact"] = False
        finish["comparability_environment_reasons"] = ["effective_policy_changed"]
        finish["metrics"]["tokens"]["root"] = {
            "total": 840,
            "request_count": 1,
        }
        finish["metrics"]["tokens"]["subagent"] = {
            "total": 0,
            "request_count": 0,
        }

        report = task_run._public_report([start, finish])
        rendered = task_run._render_report(report)

        self.assertTrue(report["diagnostic_only"])
        self.assertFalse(report["comparability_environment_intact"])
        self.assertEqual(
            report["comparability_environment_reasons"],
            ["effective_policy_changed"],
        )
        self.assertIn("diagnostic only: True", rendered)
        self.assertIn("effective_policy_changed", rendered)


class PolicyConfigurationTest(unittest.TestCase):
    def test_memory_experiment_profiles_keep_retired_codex_graph_gates_off(self) -> None:
        switches = (
            "GRAPHIFY_CODEX_REMINDER", "GRAPHIFY_CODEX_ENFORCE",
            "GRAPHIFY_CODEX_AFFECTED_ENFORCE", "GRAPHIFY_CODEX_OBSERVE_ONLY",
            "GRAPHIFY_CONTEXT_LOG",
        )
        for variant in ("off", "shadow", "active"):
            with self.subTest(variant=variant):
                profile = task_run.profile_environment(variant)
                self.assertEqual({key: profile[key] for key in switches},
                                 dict.fromkeys(switches, "0"))

    def test_profile_uses_canonical_config_and_alternate_path_content_is_hashed_only(self) -> None:
        canonical_path = (task_run.MEMORY_DIR / "config.json").resolve()
        profile = task_run.profile_environment("active")
        self.assertEqual(profile["CODEX_MEMORY_CONFIG"], str(canonical_path))
        self.assertTrue(Path(profile["CODEX_MEMORY_CONFIG"]).is_absolute())

        with mock.patch.dict(os.environ, profile, clear=True):
            canonical_policy = task_run.effective_policy()
        self.assertEqual(task_run.profile_mismatches("active", canonical_policy), [])

        with tempfile.TemporaryDirectory() as temporary:
            alternate_path = Path(temporary) / "private-machine-config.json"
            alternate_config = json.loads(canonical_path.read_text(encoding="utf-8"))
            alternate_config["retrieval"]["snippet_chars"] += 1
            alternate_path.write_text(json.dumps(alternate_config), encoding="utf-8")
            alternate_profile = {**profile, "CODEX_MEMORY_CONFIG": str(alternate_path)}
            with mock.patch.dict(os.environ, alternate_profile, clear=True):
                alternate_policy = task_run.effective_policy()

        self.assertNotEqual(
            canonical_policy["memory_config_path_sha256"],
            alternate_policy["memory_config_path_sha256"],
        )
        self.assertNotEqual(
            canonical_policy["memory_config_content_sha256"],
            alternate_policy["memory_config_content_sha256"],
        )
        self.assertIn(
            "memory_config_path_sha256",
            task_run.profile_mismatches("active", alternate_policy),
        )
        serialized = task_run._canonical(alternate_policy)
        self.assertNotIn(str(alternate_path), serialized)
        self.assertNotIn(alternate_path.name, serialized)

        off = start_row(
            "off-alternate-config",
            "off",
            1,
            policy_tuning=task_run._policy_tuning_sha256(canonical_policy),
        )
        active = start_row(
            "active-alternate-config",
            "active",
            1,
            policy_tuning=task_run._policy_tuning_sha256(alternate_policy),
        )
        result = task_run.compare_events(
            [
                off,
                active,
                finish_row("off-alternate-config", 1000, 1200),
                finish_row("active-alternate-config", 700, 840),
            ],
            "taskhash",
            20,
        )["comparisons"]["off_to_active"]
        self.assertEqual(result["comparable_quality_pass_pairs"], 0)
        self.assertEqual(result["mismatch_reasons"]["policy_tuning"], 1)

    def test_raw_out_of_range_secondary_budget_never_normalizes_to_profile(self) -> None:
        canonical_environment = task_run.profile_environment("active")
        with mock.patch.dict(os.environ, canonical_environment, clear=True):
            canonical_policy = task_run.effective_policy()
        out_of_range = {
            **canonical_environment,
            "CODEX_MEMORY_SECONDARY_BUDGET": "1000",
        }
        with mock.patch.dict(os.environ, out_of_range, clear=True):
            observed = task_run.effective_policy()

        self.assertEqual(observed["memory_secondary_budget"], 1000)
        self.assertIn(
            "memory_secondary_budget",
            task_run.profile_mismatches("active", observed),
        )
        self.assertNotEqual(
            task_run._policy_tuning_sha256(canonical_policy),
            task_run._policy_tuning_sha256(observed),
        )


class PrivacyAndDispatchTest(unittest.TestCase):
    @staticmethod
    def _active_policy() -> dict[str, object]:
        return {
            "task_run_variant": "active",
            "graphify_reminder": False,
            "graphify_enforce": False,
            "graphify_affected_enforce": False,
            "graphify_telemetry": False,
            "memory_reminder": True,
            "memory_auto_recall": True,
            "memory_repeat_guard": True,
            "memory_telemetry": True,
            "memory_secondary_mode": "inject",
            "graphify_observe_only": False,
            "memory_observe_only": False,
            "graphify_debug": False,
            "memory_debug": False,
        }

    def test_start_and_ledger_serialize_only_hashes_and_file_is_private(self) -> None:
        raw_task = "secret task prompt with customer@example.test"
        raw_root = "019f-secret-root-thread"
        raw_session = "019f-secret-session-group"
        raw_turn = "019f-secret-turn"
        raw_device = "usb-device-serial-secret"
        raw_path = Path("/private/secret/rollout.jsonl")
        args = argparse.Namespace(
            session=raw_session,
            task_id=raw_task,
            variant=None,
            replicate=1,
            required_gate=["unit"],
            held_out_gate=["heldout"],
            allow_na_gate=[],
            device_matrix=raw_device,
            allow_policy_mismatch=False,
        )
        root_session = {
            "id": raw_root,
            "session_id": raw_session,
            "path": raw_path,
            "cli_version": "0.test",
        }
        with (
            mock.patch.dict(os.environ, {"CODEX_TASK_RUN_VARIANT": "active"}, clear=False),
            mock.patch.object(task_run, "_resolve_root_session", return_value=root_session),
            mock.patch.object(task_run, "_latest_task_started", return_value={"timestamp": BASE, "turn_id": raw_turn, "index": 7}),
            mock.patch.object(task_run, "_task_request_identity", return_value=REQUEST_IDENTITY),
            mock.patch.object(task_run, "effective_policy", return_value=self._active_policy()),
            mock.patch.object(task_run, "repo_fingerprint", return_value={"head_sha256": "a" * 16, "worktree_sha256": "b" * 16}),
            mock.patch.object(task_run, "tool_fingerprints", return_value={"memory_config": "c" * 16, "hooks": "d" * 16}),
            mock.patch.object(
                task_run,
                "_task_environment",
                return_value={"model": "model", "reasoning_effort": "high", "service_tier": "priority", "cli_version": "0.test"},
            ),
        ):
            row = task_run._start_event(args)

        with tempfile.TemporaryDirectory() as temporary:
            ledger = Path(temporary) / "private" / "task-runs.jsonl"
            task_run._append_event(ledger, row)
            serialized = ledger.read_text(encoding="utf-8")
            mode = stat.S_IMODE(ledger.stat().st_mode)

        self.assertEqual(mode, 0o600)
        for secret in (raw_task, raw_root, raw_session, raw_turn, raw_device, str(raw_path)):
            self.assertNotIn(secret, serialized)
        self.assertEqual(row["task_sha256"], task_run._digest(raw_task))
        self.assertEqual(row["variant"], "active")
        self.assertEqual(row["root_thread_sha256"], task_run._digest(raw_root))
        self.assertEqual(row["session_group_sha256"], task_run._digest(raw_session))
        self.assertEqual(row["task_turn_sha256"], task_run._digest(raw_turn))
        self.assertEqual(row["device_matrix_sha256"], task_run._digest(raw_device))
        forbidden_keys = {"prompt", "command", "path", "task_id", "session_id", "turn_id", "device_matrix"}
        self.assertTrue(forbidden_keys.isdisjoint(row))

    def test_request_hmac_covers_ordered_steering_and_uses_private_shared_key(self) -> None:
        first_secret = "customer secret initial request"
        steering_secret = "customer secret steering correction"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            rollout = root / "rollout.jsonl"
            equivalent_rollout = root / "equivalent-rollout.jsonl"
            key_path = root / "task-runs.jsonl.key"
            first_message = user_message_event(at(0.01), first_secret, ordinal=11)
            first_message["payload"]["id"] = "volatile-message-one"
            first_message["payload"]["content"][0]["id"] = "volatile-block-one"
            write_jsonl(
                rollout,
                [
                    task_event(at(), "turn", ordinal=10),
                    first_message,
                    user_message_event(at(0.02), steering_secret, ordinal=12),
                    terminal_event(at(1), "turn", ordinal=20),
                ],
            )
            equivalent_first = user_message_event(at(0.01), first_secret, ordinal=11)
            equivalent_first["payload"]["id"] = "volatile-message-two"
            equivalent_first["payload"]["content"][0]["id"] = "volatile-block-two"
            write_jsonl(
                equivalent_rollout,
                [
                    task_event(at(), "different-turn-id", ordinal=10),
                    equivalent_first,
                    user_message_event(at(0.02), steering_secret, ordinal=12),
                    terminal_event(at(1), "different-turn-id", ordinal=20),
                ],
            )

            initial = task_run._task_request_identity(
                rollout,
                10,
                end_ordinal=12,
                key_path=key_path,
            )
            complete = task_run._task_request_identity(
                rollout,
                10,
                end_ordinal=20,
                key_path=key_path,
                create_key=False,
            )
            repeated = task_run._task_request_identity(
                rollout,
                10,
                end_ordinal=20,
                key_path=key_path,
                create_key=False,
            )
            equivalent = task_run._task_request_identity(
                equivalent_rollout,
                10,
                end_ordinal=20,
                key_path=key_path,
                create_key=False,
            )

            self.assertEqual(initial["task_request_count"], 1)
            self.assertEqual(complete["task_request_count"], 2)
            self.assertNotEqual(initial["task_request_sha256"], complete["task_request_sha256"])
            self.assertEqual(complete, repeated)
            self.assertEqual(complete, equivalent)
            self.assertEqual(len(complete["task_request_sha256"]), 32)
            self.assertEqual(stat.S_IMODE(key_path.stat().st_mode), 0o600)
            self.assertEqual(
                stat.S_IMODE(key_path.with_name(key_path.name + ".lock").stat().st_mode),
                0o600,
            )
            serialized = task_run._canonical(complete)
            self.assertNotIn(first_secret, serialized)
            self.assertNotIn(steering_secret, serialized)

            key_path.unlink()
            with self.assertRaisesRegex(ValueError, "privacy key is unavailable"):
                task_run._task_request_identity(
                    rollout,
                    10,
                    end_ordinal=20,
                    key_path=key_path,
                    create_key=False,
                )

    def test_reused_session_requires_override_and_remains_savings_ineligible(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            rollout = Path(temporary) / "rollout.jsonl"
            root_id = "reused-root"
            prior_turn = "prior-turn"
            current_turn = "current-turn"
            write_jsonl(
                rollout,
                [
                    meta_event(at(-60), root_id, root_id),
                    task_event(at(-20), prior_turn, ordinal=10),
                    terminal_event(at(-19), prior_turn, ordinal=20),
                    task_event(at(), current_turn, ordinal=30),
                    user_message_event(at(0.01), "same benchmark request", ordinal=31),
                ],
            )
            root_session = {
                "id": root_id,
                "session_id": root_id,
                "path": rollout,
                "cli_version": "0.test",
                "started_at": at(-60).isoformat(),
            }
            args = argparse.Namespace(
                session=root_id,
                task_id="reused diagnostic",
                variant="active",
                replicate=1,
                required_gate=["unit"],
                held_out_gate=["heldout"],
                allow_na_gate=[],
                device_matrix=None,
                review_rubric_id=None,
                allow_policy_mismatch=False,
                allow_reused_session=False,
            )
            with mock.patch.object(task_run, "_resolve_root_session", return_value=root_session):
                with self.assertRaisesRegex(ValueError, "fresh Codex rollout"):
                    task_run._start_event(args)

            args.allow_reused_session = True
            policy = self._active_policy()
            tools = {
                "memory_config": "c" * 16,
                "hooks": "d" * 16,
                "policy_code_sha256": "e" * 16,
            }
            with (
                mock.patch.object(task_run, "_resolve_root_session", return_value=root_session),
                mock.patch.object(task_run, "effective_policy", return_value=policy),
                mock.patch.object(task_run, "repo_fingerprint", return_value={"head_sha256": "a" * 16, "worktree_sha256": "b" * 16}),
                mock.patch.object(task_run, "tool_fingerprints", return_value=tools),
                mock.patch.object(
                    task_run,
                    "_task_environment",
                    return_value={"model": "model", "reasoning_effort": "high", "service_tier": "priority", "cli_version": "0.test"},
                ),
            ):
                start = task_run._start_event(
                    args,
                    request_key_path=Path(temporary) / "request.key",
                )

            self.assertEqual(start["prior_task_count"], 1)
            self.assertEqual(start["prior_completed_turns"], 1)
            self.assertFalse(start["fresh_session_eligible"])
            self.assertTrue(start["reused_session_override"])
            self.assertTrue(start["diagnostic_only"])
            with mock.patch.object(task_run, "effective_policy", return_value=policy):
                intact, reasons = task_run._policy_intact(start, tools)
            self.assertFalse(intact)
            self.assertIn("reused_session_history", reasons)

            off_start = start_row("off-reused", "off", 1)
            active_start = start_row("active-reused", "active", 1)
            active_start["fresh_session_eligible"] = False
            off_finish = finish_row("off-reused", 1000, 1200)
            active_finish = finish_row(
                "active-reused",
                700,
                840,
                quality="incomplete",
                policy_intact=False,
            )
            comparison = task_run.compare_events(
                [off_start, active_start, off_finish, active_finish],
                "taskhash",
                20,
            )["comparisons"]["off_to_active"]
            self.assertEqual(comparison["comparable_quality_pass_pairs"], 0)
            self.assertEqual(comparison["mismatch_reasons"]["policy_not_intact"], 1)

    def test_missing_heldout_requires_diagnostic_mode_and_diagnostics_never_save(self) -> None:
        args = argparse.Namespace(
            session="fresh-root",
            task_id="diagnostic task",
            variant="active",
            replicate=1,
            required_gate=["unit"],
            held_out_gate=[],
            allow_na_gate=[],
            device_matrix=None,
            review_rubric_id=None,
            allow_policy_mismatch=False,
            allow_reused_session=False,
            diagnostic_only=False,
        )
        root_session = {
            "id": "fresh-root",
            "session_id": "fresh-root",
            "path": Path("/private/fresh-rollout.jsonl"),
            "cli_version": "0.test",
            "started_at": BASE.isoformat(),
        }
        boundary = {
            "timestamp": BASE,
            "turn_id": "fresh-turn",
            "index": 1,
            "prior_task_count": 0,
            "prior_completed_turns": 0,
        }
        policy = self._active_policy()
        tools = {
            "memory_config": "c" * 16,
            "hooks": "d" * 16,
            "policy_code_sha256": "e" * 16,
        }
        patches = (
            mock.patch.object(task_run, "_resolve_root_session", return_value=root_session),
            mock.patch.object(task_run, "_latest_task_started", return_value=boundary),
            mock.patch.object(task_run, "_task_request_identity", return_value=REQUEST_IDENTITY),
            mock.patch.object(task_run, "effective_policy", return_value=policy),
            mock.patch.object(task_run, "repo_fingerprint", return_value={"head_sha256": "a" * 16, "worktree_sha256": "b" * 16}),
            mock.patch.object(task_run, "tool_fingerprints", return_value=tools),
            mock.patch.object(
                task_run,
                "_task_environment",
                return_value={"model": "model", "reasoning_effort": "high", "service_tier": "priority", "cli_version": "0.test"},
            ),
        )
        with patches[0], patches[1], patches[2], patches[3], patches[4], patches[5], patches[6]:
            with self.assertRaisesRegex(ValueError, "held-out-gate"):
                task_run._start_event(args)
            args.held_out_gate = ["unit"]
            with self.assertRaisesRegex(ValueError, "must be disjoint"):
                task_run._start_event(args)

        args.held_out_gate = []
        args.diagnostic_only = True
        patches = (
            mock.patch.object(task_run, "_resolve_root_session", return_value=root_session),
            mock.patch.object(task_run, "_latest_task_started", return_value=boundary),
            mock.patch.object(task_run, "_task_request_identity", return_value=REQUEST_IDENTITY),
            mock.patch.object(task_run, "effective_policy", return_value=policy),
            mock.patch.object(task_run, "repo_fingerprint", return_value={"head_sha256": "a" * 16, "worktree_sha256": "b" * 16}),
            mock.patch.object(task_run, "tool_fingerprints", return_value=tools),
            mock.patch.object(
                task_run,
                "_task_environment",
                return_value={"model": "model", "reasoning_effort": "high", "service_tier": "priority", "cli_version": "0.test"},
            ),
        )
        with patches[0], patches[1], patches[2], patches[3], patches[4], patches[5], patches[6]:
            diagnostic = task_run._start_event(args)

        self.assertTrue(diagnostic["diagnostic_only"])
        with mock.patch.object(task_run, "effective_policy", return_value=policy):
            intact, reasons = task_run._policy_intact(diagnostic, tools)
        self.assertFalse(intact)
        self.assertIn("diagnostic_only", reasons)

        off_start = start_row("off-diagnostic", "off", 1)
        active_start = start_row("active-diagnostic", "active", 1)
        active_start["diagnostic_only"] = True
        off_finish = finish_row("off-diagnostic", 1000, 1200)
        active_finish = finish_row("active-diagnostic", 700, 840)
        comparison = task_run.compare_events(
            [off_start, active_start, off_finish, active_finish],
            "taskhash",
            20,
        )["comparisons"]["off_to_active"]
        self.assertEqual(comparison["comparable_quality_pass_pairs"], 0)
        self.assertEqual(comparison["mismatch_reasons"]["diagnostic_only"], 1)

        report = task_run._public_report([active_start, active_finish])
        self.assertFalse(report["comparison_eligible"])
        self.assertFalse(report["savings_eligible"])

    def test_repo_fingerprint_hashes_real_content_without_binary_diff_or_derived_graphs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            untracked = root / "new.txt"
            derived = root / "graphify-out" / "graph.json"
            untracked.write_text("alpha", encoding="utf-8")
            derived.parent.mkdir(parents=True)
            derived.write_text("derived-one", encoding="utf-8")
            calls: list[tuple[str, ...]] = []

            def git_result(*args: str) -> str:
                calls.append(args)
                values = {
                    ("rev-parse", "HEAD"): "deadbeef\n",
                    ("status", "--porcelain=v1", "-z", "--untracked-files=all"): "?? new.txt\0?? graphify-out/graph.json\0",
                    ("ls-files", "-m", "-d", "-o", "--exclude-standard", "-z"): "new.txt\0graphify-out/graph.json\0",
                    ("diff", "--cached", "--name-only", "-z", "--diff-filter=ACDMRTUXB"): "",
                }
                return values[args]

            with mock.patch.object(task_run, "ROOT", root), mock.patch.object(task_run, "_git", side_effect=git_result):
                first = task_run.repo_fingerprint()
                derived.write_text("derived-two", encoding="utf-8")
                derived_only = task_run.repo_fingerprint()
                untracked.write_text("omega", encoding="utf-8")
                second = task_run.repo_fingerprint()

        self.assertEqual(first["head_sha256"], second["head_sha256"])
        self.assertEqual(first["worktree_sha256"], derived_only["worktree_sha256"])
        self.assertNotEqual(first["worktree_sha256"], second["worktree_sha256"])
        self.assertNotEqual(first["patch_sha256"], second["patch_sha256"])
        self.assertFalse(any("--binary" in args for args in calls), calls)

    def test_gate_argv_may_contain_literal_compare_without_cli_misdispatch(self) -> None:
        argv = ["gate", "--run", "abcd", "--gate-id", "unit", "--", "printf", "compare"]
        with mock.patch.object(task_run, "main", return_value=17) as main:
            with redirect_stderr(StringIO()):
                status_code = task_run.cli(argv)

        self.assertEqual(status_code, 17)
        main.assert_called_once_with(argv)

    def test_recorded_gate_requires_a_privacy_safe_evidence_identifier(self) -> None:
        parser = task_run._parser()
        with redirect_stderr(StringIO()), self.assertRaises(SystemExit):
            parser.parse_args(
                ["record-gate", "--run", "abcd", "--gate-id", "unit", "--status", "pass"]
            )

        args = parser.parse_args(
            [
                "record-gate",
                "--run",
                "abcd",
                "--gate-id",
                "unit",
                "--status",
                "pass",
                "--evidence-id",
                "review-artifact-v1",
            ]
        )
        self.assertEqual(args.evidence_id, "review-artifact-v1")

    def test_cli_cannot_lower_the_predeclared_savings_threshold(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            ledger = Path(temporary) / "runs.jsonl"
            stderr = StringIO()
            with redirect_stderr(stderr):
                status_code = task_run.main(
                    [
                        "--ledger",
                        str(ledger),
                        "compare",
                        "--task-id",
                        "case",
                        "--threshold",
                        "1",
                    ]
                )

        self.assertEqual(status_code, 2)
        self.assertIn("between 20 and 100", stderr.getvalue())


class RolloverMeasurementTest(unittest.TestCase):
    @staticmethod
    def _tool_event(
        when: dt.datetime, ordinal: int, command: str
    ) -> dict[str, object]:
        return {
            "timestamp": when.isoformat(),
            "ordinal": ordinal,
            "type": "response_item",
            "payload": {
                "type": "custom_tool_call",
                "call_id": f"call-{ordinal}",
                "input": {"cmd": command},
            },
        }

    @staticmethod
    def _rollover_start(
        run_id: str, arm: str, replicate: int, *, common: str = "rollover-common"
    ) -> dict[str, object]:
        value = start_row(run_id, "active", replicate)
        value.update(
            {
                "rollover_arm": arm,
                "rollover_policy": {
                    "arm": arm,
                    "arm_declared_before_session": True,
                    "native_model_policy_available": True,
                    "effective_token_budget_max_tokens": 13_600,
                },
                "rollover_common_policy_sha256": common,
                "rollover_policy_sha256": f"rollover-{arm}",
            }
        )
        return value

    @staticmethod
    def _rollover_finish(
        run_id: str,
        input_tokens: int,
        total_tokens: int,
        *,
        quality: str = "pass",
        checkpoint_tokens: int = 50,
        checkpointed_resume_completions: int = 1,
        new_context_calls: int = 1,
        correlated_prepared_resume_completions: int | None = None,
        fallback_lifecycle_lower_bound: int = 0,
    ) -> dict[str, object]:
        correlated = (
            min(checkpointed_resume_completions, new_context_calls)
            if correlated_prepared_resume_completions is None
            else correlated_prepared_resume_completions
        )
        fallback = fallback_lifecycle_lower_bound > 0
        mixed = fallback and bool(
            checkpointed_resume_completions or new_context_calls
        )
        intervention_fields = {
            "checkpointed_resume_completions": checkpointed_resume_completions,
            "prepared_resume_completions": checkpointed_resume_completions,
            "correlated_prepared_resume_completions": correlated,
            "uncorrelated_prepared_resume_completions": max(
                0, checkpointed_resume_completions - correlated
            ),
            "new_context_calls": new_context_calls,
            "correlated_new_context_calls": correlated,
            "uncorrelated_new_context_calls": max(0, new_context_calls - correlated),
            "recovery_precompact_allows": fallback_lifecycle_lower_bound,
            "recovery_advisory_resumes": fallback_lifecycle_lower_bound,
            "recovery_advisory_duplicates": 0,
            "fallback_lifecycle_lower_bound": fallback_lifecycle_lower_bound,
            "fallback_exposure_observed": fallback,
            "fallback_only_exposure": fallback and correlated == 0,
            "mixed_rollover_exposure": mixed,
            "intervention_correlation_status": (
                "mixed_fallback_exposure"
                if mixed
                else "correlated"
                if correlated
                else "none"
            ),
            "checkpoint_validation_failures": 0,
        }
        value = finish_row(
            run_id, input_tokens, total_tokens, quality=quality
        )
        value["metrics"]["rollover"] = {
            "combined": {
                "window_count": 2,
                "rollover_attempts": 1,
                "rollover_completions": 1,
                "rollout_compacted_transitions": 1,
                **intervention_fields,
                "rollover_failures": 0,
                "open_attempts": 0,
                "checkpoint_count": 1,
                "checkpoint_bytes": 240,
                "checkpoint_tokens_estimate": checkpoint_tokens,
                "checkpoint_estimate_source": "producer",
                "context_input_before_first_rollover": 800,
                "context_input_after_first_rollover": 300,
                "context_input_reduction_observed": 500,
                "code_read_tool_cells": 3,
                "repeated_code_read_tool_cells": 1,
                "repeated_code_read_tool_cells_after_rollover": 1,
                "document_read_tool_cells": 2,
                "repeated_document_read_tool_cells": 1,
                "repeated_document_read_tool_cells_after_rollover": 1,
                "before_first_rollover": {
                    "input": 600,
                    "cached_input": 0,
                    "uncached_input": 600,
                    "cache_write_input": 0,
                    "output": 100,
                    "reasoning_output": 0,
                    "total": 700,
                    "request_count": 1,
                    "exact": True,
                    "errors": [],
                },
                "after_rollovers": {
                    "input": input_tokens - 600,
                    "cached_input": 0,
                    "uncached_input": input_tokens - 600,
                    "cache_write_input": 0,
                    "output": total_tokens - input_tokens - 100,
                    "reasoning_output": 0,
                    "total": total_tokens - 700,
                    "request_count": 1,
                    "exact": True,
                    "errors": [],
                },
            }
        }
        value["metrics"]["rollover"]["root"] = dict(intervention_fields)
        return value

    def test_rollout_interval_segments_context_drop_and_repeated_reads(self) -> None:
        before = token_event(at(-1), vector(100, 20), vector(100, 20))
        before["ordinal"] = 5
        first = token_event(at(1), vector(160, 30), vector(60, 10))
        first["ordinal"] = 20
        compacted = {
            "timestamp": at(3).isoformat(),
            "ordinal": 30,
            "type": "compacted",
            "payload": {
                "window_id": "private-window-id",
                "window_number": 2,
                "replacement_history": [{"role": "user", "content": "capsule"}],
            },
        }
        second = token_event(at(4), vector(190, 38), vector(30, 8))
        second["ordinal"] = 40
        command = "sed -n '1,80p' lib/private_widget.dart"
        rows = [
            before,
            task_event(at(), "measured", ordinal=10),
            first,
            self._tool_event(at(2), 25, command),
            {
                "timestamp": at(2.5).isoformat(),
                "ordinal": 28,
                "type": "response_item",
                "payload": {
                    "type": "function_call",
                    "name": "functions.new_context",
                    "call_id": "private-context-call",
                },
            },
            compacted,
            self._tool_event(at(3.5), 35, command),
            second,
            terminal_event(at(5), "measured", ordinal=50),
        ]

        result = task_run._rollout_rollover_metrics(
            rows,
            at(),
            at(5),
            start_ordinal=10,
            end_ordinal=50,
        )

        self.assertEqual(result["window_count"], 2)
        self.assertEqual(result["rollover_attempts"], 1)
        self.assertEqual(result["rollover_completions"], 1)
        self.assertEqual(result["rollout_compacted_transitions"], 1)
        self.assertEqual(result["new_context_calls"], 1)
        self.assertEqual(
            result["_new_context_evidence"][0]["turn_sha256"],
            task_run._digest("measured"),
        )
        self.assertEqual(result["rollover_failures"], 0)
        self.assertEqual(result["before_first_rollover"]["input"], 60)
        self.assertEqual(result["after_rollovers"]["input"], 30)
        self.assertEqual(result["before_first_rollover"]["total"], 70)
        self.assertEqual(result["after_rollovers"]["total"], 38)
        self.assertEqual(result["context_input_before_first_rollover"], 60)
        self.assertEqual(result["context_input_after_first_rollover"], 30)
        self.assertEqual(result["context_input_reduction_observed"], 30)
        self.assertEqual(result["repeated_code_read_tool_cells_after_rollover"], 1)
        self.assertGreater(result["checkpoint_bytes"], 0)
        self.assertGreater(result["checkpoint_tokens_estimate"], 0)
        self.assertNotIn("private-window-id", json.dumps(result))

    def test_producer_lifecycle_joins_mutating_hashes_and_scopes_interval(self) -> None:
        session_hash = "a" * 16
        thread_hash = "b" * 16
        rows = [
            {
                "event": "precompact_allowed",
                "timestamp": at(-1).isoformat(),
                "codex_session_sha256": session_hash,
                "codex_thread_sha256": thread_hash,
                "checkpoint_sha256": "1" * 16,
                "generation": 99,
            },
            {
                "event": "checkpoint_saved",
                "timestamp": at(1).isoformat(),
                "codex_session_sha256": session_hash,
                "codex_thread_sha256": thread_hash,
                "checkpoint_sha256": "2" * 16,
                "generation": 1,
                "checkpoint_bytes": 200,
                "checkpoint_tokens_estimate": 40,
            },
            {
                "event": "precompact_allowed",
                "timestamp": at(2).isoformat(),
                "codex_session_sha256": session_hash,
                "codex_thread_sha256": thread_hash,
                "checkpoint_sha256": "3" * 16,
                "generation": 1,
                "checkpoint_bytes": 220,
                "checkpoint_tokens_estimate": 50,
            },
            {
                "event": "session_resumed",
                "timestamp": at(3).isoformat(),
                "codex_session_sha256": session_hash,
                "codex_thread_sha256": thread_hash,
                "checkpoint_sha256": "4" * 16,
                "generation": 1,
                "checkpoint_bytes": 210,
                "checkpoint_tokens_estimate": 45,
            },
            {
                "event": "checkpoint_stale",
                "timestamp": at(4).isoformat(),
                "codex_session_sha256": session_hash,
                "codex_thread_sha256": thread_hash,
                "checkpoint_sha256": "5" * 16,
                "generation": 2,
            },
            {
                "event": "precompact_blocked",
                "timestamp": at(4).isoformat(),
                "codex_session_sha256": session_hash,
                "codex_thread_sha256": thread_hash,
                "checkpoint_sha256": "6" * 16,
                "generation": 2,
            },
            {
                "event": "postcompact_observed",
                "timestamp": at(4.5).isoformat(),
                "codex_session_sha256": session_hash,
                "codex_thread_sha256": thread_hash,
                "checkpoint_sha256": "",
                "generation": 0,
                "checkpoint_bytes": 0,
                "checkpoint_tokens_estimate": 0,
            },
        ]
        filtered = [
            row
            for row in rows
            if task_run._row_in_interval(row, session_hash, at(), at(5))
        ]

        result = task_run._producer_rollover_metrics(filtered)

        self.assertEqual(result["rollover_attempts"], 2)
        self.assertEqual(result["rollover_completions"], 1)
        self.assertEqual(result["checkpointed_resume_completions"], 1)
        self.assertEqual(result["rollover_failures"], 1)
        self.assertEqual(result["checkpoint_count"], 1)
        self.assertEqual(result["checkpoint_bytes"], 220)
        self.assertEqual(result["checkpoint_tokens_estimate"], 50)
        self.assertEqual(result["producer_events"]["checkpoint_stale"], 1)
        self.assertNotIn("2" * 16, json.dumps(result))

        reversed_chain = task_run._producer_rollover_metrics(
            [
                {
                    "event": event,
                    "timestamp": at(offset).isoformat(),
                    "codex_thread_sha256": thread_hash,
                    "checkpoint_sha256": "7" * 16,
                    "generation": 7,
                }
                for event, offset in (
                    ("session_resumed", 1),
                    ("checkpoint_saved", 2),
                    ("precompact_allowed", 3),
                )
            ]
        )
        self.assertEqual(reversed_chain["checkpointed_resume_completions"], 0)

    def test_prepared_lifecycle_requires_ordered_postcompact_and_matching_turn(self) -> None:
        thread_hash = "b" * 16
        turn_hash = task_run._digest("measured-turn")

        def producer_rows(*, include_post: bool = True) -> list[dict[str, object]]:
            events: list[tuple[str, float]] = [
                ("checkpoint_saved", 1),
                ("precompact_allowed", 3),
            ]
            if include_post:
                events.append(("postcompact_observed", 4))
            events.append(("session_resumed", 5))
            return [
                {
                    "event": event,
                    "timestamp": at(offset).isoformat(),
                    "codex_thread_sha256": thread_hash,
                    "checkpoint_sha256": f"{index + 1}" * 16,
                    "generation": 1,
                    "continuation_mode": "prepared_rollover",
                    **(
                        {"precompact_turn_sha256": turn_hash}
                        if event != "checkpoint_saved"
                        else {}
                    ),
                }
                for index, (event, offset) in enumerate(events)
            ]

        producer = task_run._producer_rollover_metrics(producer_rows())
        rollout = task_run._sum_rollover_lanes([])
        rollout.update(
            {
                "new_context_calls": 1,
                "_new_context_evidence": [
                    {
                        "timestamp": at(2).isoformat(),
                        "ordinal": 20,
                        "turn_sha256": turn_hash,
                    }
                ],
            }
        )

        result = task_run._merge_rollover_lane(rollout, producer)

        self.assertEqual(result["checkpointed_resume_completions"], 1)
        self.assertEqual(result["prepared_resume_completions"], 1)
        self.assertEqual(result["correlated_prepared_resume_completions"], 1)
        self.assertEqual(result["intervention_correlation_status"], "correlated")
        self.assertNotIn("_prepared_lifecycles", json.dumps(result))
        self.assertNotIn("_new_context_evidence", json.dumps(result))

        missing_post = task_run._producer_rollover_metrics(
            producer_rows(include_post=False)
        )
        self.assertEqual(missing_post["checkpointed_resume_completions"], 1)
        self.assertEqual(missing_post["prepared_resume_completions"], 0)

        wrong_mode_rows = producer_rows()
        next(
            row
            for row in wrong_mode_rows
            if row["event"] == "postcompact_observed"
        )["continuation_mode"] = "recovery_advisory"
        wrong_mode = task_run._producer_rollover_metrics(wrong_mode_rows)
        self.assertEqual(wrong_mode["checkpointed_resume_completions"], 1)
        self.assertEqual(wrong_mode["prepared_resume_completions"], 0)

        wrong_turn_rollout = dict(rollout)
        wrong_turn_rollout["_new_context_evidence"] = [
            {
                "timestamp": at(2).isoformat(),
                "ordinal": 20,
                "turn_sha256": task_run._digest("different-turn"),
            }
        ]
        uncorrelated = task_run._merge_rollover_lane(
            wrong_turn_rollout, producer
        )
        self.assertEqual(
            uncorrelated["correlated_prepared_resume_completions"], 0
        )
        self.assertEqual(
            uncorrelated["uncorrelated_prepared_resume_completions"], 1
        )

    def test_fallback_advisory_is_diagnostic_and_preserves_exact_segments(self) -> None:
        thread_hash = "b" * 16
        producer = task_run._producer_rollover_metrics(
            [
                {
                    "event": event,
                    "timestamp": at(offset).isoformat(),
                    "codex_thread_sha256": thread_hash,
                    "checkpoint_sha256": "1" * 16,
                    "generation": 1,
                    "continuation_mode": "recovery_advisory",
                    "precompact_turn_sha256": task_run._digest("measured"),
                    "ready": False,
                }
                for event, offset in (
                    ("checkpoint_stale", 2),
                    ("precompact_recovery_allowed", 2.1),
                    ("postcompact_observed", 3),
                    ("session_recovery_advisory", 4),
                )
            ]
        )
        before = token_event(at(-1), vector(100, 20), vector(100, 20))
        before["ordinal"] = 5
        first = token_event(at(1), vector(160, 30), vector(60, 10))
        first["ordinal"] = 20
        second = token_event(at(4), vector(190, 38), vector(30, 8))
        second["ordinal"] = 40
        rollout = task_run._rollout_rollover_metrics(
            [
                before,
                task_event(at(), "measured", ordinal=10),
                first,
                {
                    "timestamp": at(3).isoformat(),
                    "ordinal": 30,
                    "type": "compacted",
                    "payload": {"window_id": "not-persisted"},
                },
                second,
                terminal_event(at(5), "measured", ordinal=50),
            ],
            at(),
            at(5),
            start_ordinal=10,
            end_ordinal=50,
        )

        result = task_run._merge_rollover_lane(rollout, producer)

        self.assertEqual(result["checkpointed_resume_completions"], 0)
        self.assertEqual(result["prepared_resume_completions"], 0)
        self.assertEqual(result["correlated_prepared_resume_completions"], 0)
        self.assertEqual(result["recovery_precompact_allows"], 1)
        self.assertEqual(result["recovery_advisory_resumes"], 1)
        self.assertEqual(result["checkpoint_validation_failures"], 1)
        self.assertEqual(result["rollover_failures"], 0)
        self.assertTrue(result["fallback_exposure_observed"])
        self.assertTrue(result["fallback_only_exposure"])
        self.assertTrue(result["before_first_rollover"]["exact"])
        self.assertTrue(result["after_rollovers"]["exact"])
        self.assertNotIn("not-persisted", json.dumps(result))

    def test_task_complete_after_not_ready_is_a_liveness_failure(self) -> None:
        thread_hash = "b" * 16
        producer = task_run._producer_rollover_metrics(
            [
                {
                    "event": "checkpoint_saved",
                    "timestamp": at(1).isoformat(),
                    "codex_thread_sha256": thread_hash,
                    "checkpoint_sha256": "1" * 16,
                    "generation": 1,
                    "ready": False,
                }
            ]
        )
        rollout = task_run._rollout_rollover_metrics(
            [
                task_event(at(), "measured", ordinal=10),
                terminal_event(at(2), "measured", ordinal=20),
            ],
            at(),
            at(2),
            start_ordinal=9,
            end_ordinal=20,
        )

        result = task_run._merge_rollover_lane(rollout, producer)

        self.assertEqual(result["not_ready_lifecycles"], 1)
        self.assertEqual(result["terminal_after_not_ready"], 1)
        self.assertEqual(result["terminal_after_not_ready_derived"], 1)
        self.assertEqual(result["rollover_failures"], 1)
        self.assertEqual(result["open_attempts"], 0)

        metrics = exact_metrics(100, 120)
        metrics["rollover"] = {"combined": result, "root": result}
        start = {
            "required_gates": ["unit"],
            "held_out_gates": [],
            "allow_na_gates": [],
        }
        quality = task_run._quality(
            start,
            [{"type": "gate", "gate_id": "unit", "status": "pass"}],
            metrics,
            "pass",
            {"critical": 0, "major": 0, "minor": 0},
            True,
        )
        self.assertEqual(quality["status"], "fail")
        self.assertFalse(quality["terminal_complete"])
        self.assertFalse(quality["rollover_liveness_intact"])

    def test_repair_and_hard_fallback_before_terminal_do_not_mask_a_terminal(self) -> None:
        thread_hash = "b" * 16
        rows = [
            {
                "event": event,
                "timestamp": at(offset).isoformat(),
                "codex_thread_sha256": thread_hash,
                "checkpoint_sha256": "1" * 16,
                "generation": generation,
                "ready": ready,
                "continuation_mode": mode,
                "not_ready_episode_sha256": "e" * 16,
            }
            for event, offset, generation, ready, mode in (
                ("checkpoint_saved", 1, 1, False, "unknown"),
                ("checkpoint_saved", 1.2, 2, True, "prepared_rollover"),
                (
                    "checkpoint_advisory_reset_requested",
                    1.4,
                    2,
                    False,
                    "recovery_advisory",
                ),
                (
                    "terminal_after_not_ready_blocked",
                    1.6,
                    2,
                    False,
                    "recovery_advisory",
                ),
            )
        ]
        producer = task_run._producer_rollover_metrics(rows)
        rollout = task_run._rollout_rollover_metrics(
            [
                task_event(at(), "measured", ordinal=10),
                terminal_event(at(2), "measured", ordinal=20),
            ],
            at(),
            at(2),
            start_ordinal=9,
            end_ordinal=20,
        )

        result = task_run._merge_rollover_lane(rollout, producer)

        self.assertEqual(result["not_ready_repairs_before_terminal"], 1)
        self.assertEqual(result["not_ready_advisories_before_terminal"], 1)
        self.assertEqual(result["terminal_after_not_ready_blocked"], 1)
        self.assertEqual(result["terminal_after_not_ready"], 1)
        self.assertEqual(result["rollover_failures"], 1)

    def test_advisory_arm_and_raw_new_context_do_not_mask_terminal(self) -> None:
        thread_hash = "b" * 16
        producer = task_run._producer_rollover_metrics(
            [
                {
                    "event": "checkpoint_saved",
                    "timestamp": at(1).isoformat(),
                    "codex_thread_sha256": thread_hash,
                    "checkpoint_sha256": "1" * 16,
                    "generation": 1,
                    "ready": False,
                    "not_ready_episode_sha256": "e" * 16,
                },
                {
                    "event": "checkpoint_advisory_reset_requested",
                    "timestamp": at(1.2).isoformat(),
                    "codex_thread_sha256": thread_hash,
                    "checkpoint_sha256": "1" * 16,
                    "generation": 1,
                    "ready": False,
                    "not_ready_episode_sha256": "e" * 16,
                },
            ]
        )
        rollout = task_run._rollout_rollover_metrics(
            [
                task_event(at(), "measured", ordinal=10),
                {
                    "timestamp": at(1.5).isoformat(),
                    "ordinal": 15,
                    "type": "response_item",
                    "payload": {
                        "type": "function_call",
                        "name": "functions.new_context",
                        "call_id": "private-unconsumed-call",
                    },
                },
                terminal_event(at(2), "measured", ordinal=20),
            ],
            at(),
            at(2),
            start_ordinal=9,
            end_ordinal=20,
        )

        result = task_run._merge_rollover_lane(rollout, producer)

        self.assertEqual(result["new_context_calls"], 1)
        self.assertEqual(result["not_ready_advisories_before_terminal"], 1)
        self.assertEqual(result["terminal_after_not_ready"], 1)
        self.assertEqual(result["rollover_failures"], 1)
        self.assertNotIn("private-unconsumed-call", json.dumps(result))

    def test_cross_generation_ready_retry_resolves_only_at_precompact(self) -> None:
        thread_hash = "b" * 16
        turn_hash = task_run._digest("measured")

        def producer_rows(include_precompact: bool) -> list[dict[str, object]]:
            rows: list[dict[str, object]] = [
                {
                    "event": "checkpoint_saved",
                    "timestamp": at(1).isoformat(),
                    "codex_thread_sha256": thread_hash,
                    "checkpoint_sha256": "1" * 16,
                    "generation": 1,
                    "ready": False,
                    "checkpoint_bytes": 100,
                    "not_ready_episode_sha256": "e" * 16,
                },
                {
                    "event": "checkpoint_saved",
                    "timestamp": at(1.2).isoformat(),
                    "codex_thread_sha256": thread_hash,
                    "checkpoint_sha256": "2" * 16,
                    "generation": 2,
                    "ready": True,
                    "checkpoint_bytes": 120,
                    "not_ready_episode_sha256": "e" * 16,
                },
            ]
            if include_precompact:
                rows.append(
                    {
                        "event": "precompact_allowed",
                        "timestamp": at(1.5).isoformat(),
                        "codex_thread_sha256": thread_hash,
                        "checkpoint_sha256": "2" * 16,
                        "generation": 2,
                        "ready": True,
                        "precompact_turn_sha256": turn_hash,
                        "not_ready_episode_sha256": "e" * 16,
                    }
                )
            return rows

        rollout = task_run._rollout_rollover_metrics(
            [
                task_event(at(), "measured", ordinal=10),
                terminal_event(at(2), "measured", ordinal=20),
            ],
            at(),
            at(2),
            start_ordinal=9,
            end_ordinal=20,
        )

        pending = task_run._merge_rollover_lane(
            rollout, task_run._producer_rollover_metrics(producer_rows(False))
        )
        transitioned = task_run._merge_rollover_lane(
            rollout, task_run._producer_rollover_metrics(producer_rows(True))
        )

        self.assertEqual(pending["checkpoint_count"], 2)
        self.assertEqual(pending["not_ready_repairs_before_terminal"], 1)
        self.assertEqual(pending["terminal_after_not_ready"], 1)
        self.assertEqual(pending["rollover_failures"], 1)
        self.assertEqual(transitioned["not_ready_repairs_before_terminal"], 1)
        self.assertEqual(transitioned["terminal_after_not_ready"], 0)
        self.assertEqual(transitioned["rollover_failures"], 0)
        self.assertEqual(transitioned["unresolved_not_ready"], 0)

    def test_later_user_turn_is_rescue_and_never_erases_terminal_failure(self) -> None:
        thread_hash = "b" * 16
        producer = task_run._producer_rollover_metrics(
            [
                {
                    "event": "checkpoint_saved",
                    "timestamp": at(1).isoformat(),
                    "codex_thread_sha256": thread_hash,
                    "checkpoint_sha256": "1" * 16,
                    "generation": 1,
                    "ready": False,
                }
            ]
        )
        rollout = task_run._rollout_rollover_metrics(
            [
                task_event(at(), "first", ordinal=10),
                terminal_event(at(2), "first", ordinal=20),
                task_event(at(3), "rescue", ordinal=30),
                user_message_event(at(3.1), "private rescue prompt", ordinal=31),
                {
                    "timestamp": at(4).isoformat(),
                    "ordinal": 40,
                    "type": "response_item",
                    "payload": {
                        "type": "function_call",
                        "name": "functions.new_context",
                        "call_id": "private-rescue-call",
                    },
                },
                {
                    "timestamp": at(5).isoformat(),
                    "ordinal": 50,
                    "type": "compacted",
                    "payload": {"window_id": "private-rescue-window"},
                },
            ],
            at(),
            at(5),
            start_ordinal=9,
            end_ordinal=50,
        )

        result = task_run._merge_rollover_lane(rollout, producer)

        self.assertEqual(result["terminal_after_not_ready"], 1)
        self.assertEqual(result["user_rescue_after_terminal"], 1)
        self.assertEqual(result["rollover_failures"], 1)
        serialized = json.dumps(result)
        self.assertNotIn("private-rescue", serialized)
        self.assertNotIn("private rescue prompt", serialized)

    def test_unknown_producer_threads_do_not_inflate_combined_lane(self) -> None:
        root_id = "root-thread"
        session_hash = "a" * 16
        root_hash = task_run._digest(root_id)

        def chain(thread_hash: str, generation: int) -> list[dict[str, object]]:
            return [
                {
                    "event": event,
                    "timestamp": at(offset).isoformat(),
                    "codex_session_sha256": session_hash,
                    "codex_thread_sha256": thread_hash,
                    "checkpoint_sha256": f"{generation}" * 16,
                    "generation": generation,
                    "checkpoint_bytes": 100,
                    "checkpoint_tokens_estimate": 20,
                }
                for event, offset in (
                    ("checkpoint_saved", 1),
                    ("precompact_allowed", 2),
                    ("session_resumed", 3),
                )
            ]

        producer = [*chain(root_hash, 1), *chain("b" * 16, 2)]
        rollout_rows = [
            task_event(at(), "turn", ordinal=10),
            token_event(at(1), vector(50, 10), vector(50, 10)),
            terminal_event(at(5), "turn", ordinal=50),
        ]
        rollout_rows[1]["ordinal"] = 20
        with (
            mock.patch.object(task_run, "_rollout_rows", return_value=rollout_rows),
            mock.patch.object(task_run, "_read_jsonl", return_value=producer),
        ):
            result = task_run.rollover_diagnostics(
                session_hash,
                [
                    {
                        "id": root_id,
                        "path": Path("/private/root.jsonl"),
                        "started_at": BASE.isoformat(),
                    }
                ],
                root_id,
                at(),
                at(5),
                root_start_ordinal=10,
                root_end_ordinal=50,
            )

        self.assertEqual(result["root"]["checkpointed_resume_completions"], 1)
        self.assertEqual(result["combined"]["checkpointed_resume_completions"], 1)
        self.assertEqual(result["unscoped_producer_events"], 3)

    def test_partial_producer_measurements_cannot_erase_rollout_measurements(self) -> None:
        rollout = task_run._sum_rollover_lanes([])
        rollout.update(
            {
                "thread_count": 1,
                "checkpoint_count": 2,
                "checkpoint_bytes": 1_000,
                "checkpoint_tokens_estimate": 250,
                "checkpoint_estimate_source": "rollout_bytes_div4",
            }
        )
        producer = {
            "producer_event_count": 1,
            "producer_events": {"checkpoint_saved": 1},
            "checkpoint_count": 1,
            "checkpoint_bytes": 100,
            "checkpoint_tokens_estimate": 20,
        }

        result = task_run._merge_rollover_lane(rollout, producer)

        self.assertEqual(result["checkpoint_count"], 2)
        self.assertEqual(result["checkpoint_bytes"], 1_000)
        self.assertEqual(result["checkpoint_tokens_estimate"], 250)
        self.assertEqual(
            result["checkpoint_measurements"]["rollout"]["count"], 2
        )
        self.assertEqual(
            result["checkpoint_measurements"]["producer"]["count"], 1
        )
        self.assertEqual(
            result["checkpoint_measurement_coverage"], "source_lanes_exposed"
        )

    def test_missing_segment_snapshots_are_never_reported_as_exact_zero(self) -> None:
        with_rollover = [
            task_event(at(), "turn", ordinal=10),
            {
                "timestamp": at(2).isoformat(),
                "ordinal": 20,
                "type": "compacted",
                "payload": {"window_id": "private-window"},
            },
            terminal_event(at(5), "turn", ordinal=30),
        ]
        result = task_run._rollout_rollover_metrics(
            with_rollover,
            at(),
            at(5),
            start_ordinal=10,
            end_ordinal=30,
        )
        self.assertFalse(result["before_first_rollover"]["exact"])
        self.assertFalse(result["after_rollovers"]["exact"])
        self.assertIn(
            "no_token_snapshot_in_interval",
            result["after_rollovers"]["errors"],
        )

        no_rollover = task_run._rollout_rollover_metrics(
            [
                task_event(at(), "turn", ordinal=10),
                terminal_event(at(5), "turn", ordinal=30),
            ],
            at(),
            at(5),
            start_ordinal=10,
            end_ordinal=30,
        )
        self.assertIsNone(no_rollover["after_rollovers"]["total"])
        self.assertFalse(no_rollover["after_rollovers"]["exact"])
        self.assertEqual(
            no_rollover["after_rollovers"]["errors"],
            ["not_applicable_no_rollover"],
        )

    def test_rollover_policy_exposes_diagnostics_and_has_common_arm_hash(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            control = task_run.rollover_policy(
                {"context_window_tokens": 272_000}, "control"
            )
            active = task_run.rollover_policy(
                {"context_window_tokens": 272_000}, "active"
            )

        self.assertEqual(control["native_token_budget_fallback_tokens"], 16_384)
        self.assertEqual(control["effective_token_budget_max_tokens"], 13_600)
        self.assertFalse(control["native_token_budget_expected_enabled"])
        self.assertTrue(active["native_token_budget_expected_enabled"])
        self.assertEqual(
            control["common_policy_sha256"], active["common_policy_sha256"]
        )
        self.assertNotEqual(control["policy_sha256"], active["policy_sha256"])
        environment = task_run.rollover_profile_environment("control")
        self.assertEqual(environment["CODEX_TASK_RUN_VARIANT"], "active")
        self.assertEqual(environment["CODEX_TASK_RUN_ROLLOVER_ARM"], "control")
        self.assertEqual(
            task_run.profile_environment("active")[
                "CODEX_TASK_RUN_ROLLOVER_ARM"
            ],
            "unspecified",
        )
        self.assertEqual(
            task_run._context_window_sha256({"window_id": "private-one"}),
            task_run._context_window_sha256({"window_id": "private-two"}),
        )

        with tempfile.TemporaryDirectory() as temporary:
            cache = {
                "models": [
                    {
                        "slug": "model-under-test",
                        "context_window": 272_000,
                        "max_context_window": 872_000,
                        "effective_context_window_percent": 95,
                        "model_messages": {
                            "token_budget": {
                                "auto_compact_fallback_buffer_tokens": 16_384
                            }
                        },
                    }
                ]
            }
            (Path(temporary) / "models_cache.json").write_text(
                json.dumps(cache), encoding="utf-8"
            )
            with mock.patch.dict(
                os.environ, {"CODEX_HOME": temporary}, clear=True
            ):
                capabilities = task_run._codex_model_capabilities(
                    "model-under-test"
                )
        self.assertTrue(capabilities["available"])
        self.assertEqual(capabilities["context_window_tokens"], 272_000)
        self.assertEqual(capabilities["token_budget_fallback_tokens"], 16_384)

    def test_start_requires_rollover_arm_to_be_set_before_session(self) -> None:
        args = argparse.Namespace(
            session="root",
            task_id="rollover-task",
            variant="active",
            rollover_arm="control",
            replicate=1,
            required_gate=["unit"],
            held_out_gate=["heldout"],
            allow_na_gate=[],
            device_matrix=None,
            review_rubric_id=None,
            allow_policy_mismatch=False,
            allow_reused_session=False,
            diagnostic_only=False,
        )
        root = {
            "id": "root",
            "session_id": "root",
            "path": Path("/private/rollout.jsonl"),
            "cli_version": "0.test",
            "started_at": BASE.isoformat(),
        }
        boundary = {
            "timestamp": BASE,
            "turn_id": "turn",
            "index": 1,
            "prior_task_count": 0,
            "prior_completed_turns": 0,
        }
        patches = (
            mock.patch.object(task_run, "_resolve_root_session", return_value=root),
            mock.patch.object(task_run, "_latest_task_started", return_value=boundary),
            mock.patch.object(task_run, "_task_request_identity", return_value=REQUEST_IDENTITY),
            mock.patch.object(task_run, "effective_policy", return_value={}),
            mock.patch.object(task_run, "profile_mismatches", return_value=[]),
            mock.patch.object(task_run, "repo_fingerprint", return_value={}),
            mock.patch.object(task_run, "tool_fingerprints", return_value={}),
            mock.patch.object(
                task_run,
                "_task_environment",
                return_value={"context_window_tokens": 272_000},
            ),
        )
        with (
            patches[0],
            patches[1],
            patches[2],
            patches[3],
            patches[4],
            patches[5],
            patches[6],
            patches[7],
            mock.patch.dict(os.environ, {}, clear=True),
            self.assertRaisesRegex(ValueError, "before starting"),
        ):
            task_run._start_event(args)

        patches = (
            mock.patch.object(task_run, "_resolve_root_session", return_value=root),
            mock.patch.object(task_run, "_latest_task_started", return_value=boundary),
            mock.patch.object(task_run, "_task_request_identity", return_value=REQUEST_IDENTITY),
            mock.patch.object(task_run, "effective_policy", return_value={}),
            mock.patch.object(task_run, "profile_mismatches", return_value=[]),
            mock.patch.object(task_run, "repo_fingerprint", return_value={}),
            mock.patch.object(task_run, "tool_fingerprints", return_value={}),
            mock.patch.object(
                task_run,
                "_task_environment",
                return_value={"context_window_tokens": 272_000},
            ),
        )
        with (
            patches[0],
            patches[1],
            patches[2],
            patches[3],
            patches[4],
            patches[5],
            patches[6],
            patches[7],
            mock.patch.dict(
                os.environ,
                {"CODEX_TASK_RUN_ROLLOVER_ARM": "active"},
                clear=True,
            ),
            self.assertRaisesRegex(ValueError, "does not match"),
        ):
            task_run._start_event(args)

    def test_three_rollover_pairs_prove_only_exact_causal_savings(self) -> None:
        rows: list[dict[str, object]] = []
        for replicate in range(1, 4):
            control_id = f"rollover-control-{replicate}"
            active_id = f"rollover-active-{replicate}"
            rows.extend(
                [
                    self._rollover_start(control_id, "control", replicate),
                    self._rollover_start(active_id, "active", replicate),
                    self._rollover_finish(
                        control_id,
                        1_000,
                        1_200,
                        checkpointed_resume_completions=0,
                        new_context_calls=0,
                    ),
                    self._rollover_finish(
                        active_id,
                        700 + 50 * (replicate - 1),
                        840 + 60 * (replicate - 1),
                        checkpoint_tokens=900_000,
                    ),
                ]
            )

        comparison = task_run.compare_events(
            rows, "taskhash", 20, experiment="rollover"
        )
        result = comparison["comparisons"]["control_to_active"]

        self.assertEqual(comparison["experiment"], "rollover")
        self.assertEqual(comparison["negative_control"]["arm"], "control")
        self.assertEqual(result["verdict"], "proven")
        self.assertEqual(result["comparable_quality_pass_pairs"], 3)
        self.assertEqual(result["median_input_tokens_saved"], 250.0)
        self.assertEqual(result["median_input_percent_saved"], 25.0)
        self.assertEqual(
            result["exact_token_pair_medians"]["uncached_input"]["reduction_percent"],
            25.0,
        )
        self.assertEqual(result["pairs"][0]["input_tokens_saved"], 300)
        self.assertEqual(
            result["pairs"][0]["right_intervention_evidence"][
                "root_correlated_prepared_resume_completions"
            ],
            1,
        )
        self.assertEqual(
            result["rollover_quality_pass_pair_medians"]["right"][
                "correlated_prepared_resume_completions"
            ],
            1.0,
        )
        self.assertTrue(result["within_run_segments_are_not_causal_savings"])
        self.assertFalse(comparison["checkpoint_estimates_used_in_savings"])

    def test_rollover_failures_and_policy_mismatch_block_proof(self) -> None:
        rows: list[dict[str, object]] = []
        for replicate in range(1, 5):
            control_id = f"control-failure-{replicate}"
            active_id = f"active-failure-{replicate}"
            rows.extend(
                [
                    self._rollover_start(control_id, "control", replicate),
                    self._rollover_start(
                        active_id,
                        "active",
                        replicate,
                        common="different" if replicate == 4 else "rollover-common",
                    ),
                    self._rollover_finish(
                        control_id,
                        1_000,
                        1_200,
                        checkpointed_resume_completions=0,
                        new_context_calls=0,
                    ),
                    self._rollover_finish(
                        active_id,
                        10 if replicate == 4 else 700,
                        12 if replicate == 4 else 840,
                        quality="fail" if replicate == 4 else "pass",
                    ),
                ]
            )

        result = task_run.compare_events(
            rows, "taskhash", 20, experiment="rollover"
        )["comparisons"]["control_to_active"]

        self.assertEqual(result["comparable_quality_pass_pairs"], 3)
        self.assertEqual(result["verdict"], "insufficient")
        self.assertEqual(result["mismatch_reasons"]["rollover_common_policy"], 1)
        self.assertEqual(len(result["rollover_observations"]), 4)
        self.assertFalse(
            result["rollover_observations"][-1][
                "included_in_exact_token_comparison"
            ]
        )

    def test_mistagged_or_unexposed_rollover_arms_cannot_emit_savings(self) -> None:
        rows = [
            self._rollover_start("control-mistag", "control", 1),
            self._rollover_start("active-mistag", "active", 1),
            self._rollover_finish(
                "control-mistag",
                1_000,
                1_200,
                checkpointed_resume_completions=0,
                new_context_calls=1,
            ),
            self._rollover_finish("active-mistag", 700, 840),
            self._rollover_start("control-no-call", "control", 2),
            self._rollover_start("active-no-call", "active", 2),
            self._rollover_finish(
                "control-no-call",
                1_000,
                1_200,
                checkpointed_resume_completions=0,
                new_context_calls=0,
            ),
            self._rollover_finish(
                "active-no-call",
                700,
                840,
                checkpointed_resume_completions=1,
                new_context_calls=0,
            ),
            self._rollover_start("control-no-chain", "control", 3),
            self._rollover_start("active-no-chain", "active", 3),
            self._rollover_finish(
                "control-no-chain",
                1_000,
                1_200,
                checkpointed_resume_completions=0,
                new_context_calls=0,
            ),
            self._rollover_finish(
                "active-no-chain",
                700,
                840,
                checkpointed_resume_completions=0,
                new_context_calls=1,
            ),
        ]

        result = task_run.compare_events(
            rows, "taskhash", 20, experiment="rollover"
        )["comparisons"]["control_to_active"]

        self.assertEqual(result["comparable_quality_pass_pairs"], 0)
        self.assertEqual(result["verdict"], "insufficient")
        self.assertEqual(result["mismatch_reasons"]["control_new_context_observed"], 1)
        self.assertEqual(result["mismatch_reasons"]["active_new_context_not_observed"], 1)
        self.assertEqual(
            result["mismatch_reasons"][
                "active_checkpoint_intervention_not_observed"
            ],
            2,
        )
        self.assertNotIn("input_tokens_saved", json.dumps(result))

    def test_fallback_mixed_and_uncorrelated_exposure_cannot_emit_savings(self) -> None:
        rows = [
            self._rollover_start("control-fallback", "control", 1),
            self._rollover_start("active-fallback", "active", 1),
            self._rollover_finish(
                "control-fallback",
                1_000,
                1_200,
                checkpointed_resume_completions=0,
                new_context_calls=0,
            ),
            self._rollover_finish(
                "active-fallback",
                700,
                840,
                checkpointed_resume_completions=0,
                new_context_calls=0,
                fallback_lifecycle_lower_bound=1,
            ),
            self._rollover_start("control-mixed", "control", 2),
            self._rollover_start("active-mixed", "active", 2),
            self._rollover_finish(
                "control-mixed",
                1_000,
                1_200,
                checkpointed_resume_completions=0,
                new_context_calls=0,
            ),
            self._rollover_finish(
                "active-mixed",
                700,
                840,
                fallback_lifecycle_lower_bound=1,
            ),
            self._rollover_start("control-unlinked", "control", 3),
            self._rollover_start("active-unlinked", "active", 3),
            self._rollover_finish(
                "control-unlinked",
                1_000,
                1_200,
                checkpointed_resume_completions=0,
                new_context_calls=0,
            ),
            self._rollover_finish(
                "active-unlinked",
                700,
                840,
                correlated_prepared_resume_completions=0,
            ),
        ]
        descendant_fallback = self._rollover_finish(
            "active-descendant-fallback",
            700,
            840,
            fallback_lifecycle_lower_bound=1,
        )
        descendant_fallback["metrics"]["rollover"]["root"].update(
            {
                "recovery_precompact_allows": 0,
                "recovery_advisory_resumes": 0,
                "fallback_lifecycle_lower_bound": 0,
                "fallback_exposure_observed": False,
                "fallback_only_exposure": False,
                "mixed_rollover_exposure": False,
            }
        )
        rows.extend(
            [
                self._rollover_start("control-descendant-fallback", "control", 4),
                self._rollover_start("active-descendant-fallback", "active", 4),
                self._rollover_finish(
                    "control-descendant-fallback",
                    1_000,
                    1_200,
                    checkpointed_resume_completions=0,
                    new_context_calls=0,
                ),
                descendant_fallback,
            ]
        )

        result = task_run.compare_events(
            rows, "taskhash", 20, experiment="rollover"
        )["comparisons"]["control_to_active"]

        self.assertEqual(result["comparable_quality_pass_pairs"], 0)
        self.assertEqual(result["mismatch_reasons"]["active_fallback_only"], 1)
        self.assertEqual(
            result["mismatch_reasons"]["active_mixed_rollover_exposure"], 2
        )
        self.assertEqual(
            result["mismatch_reasons"]["active_prepared_lifecycle_uncorrelated"],
            1,
        )
        self.assertEqual(
            result["mismatch_reasons"]["active_new_context_uncorrelated"], 1
        )
        self.assertNotIn("input_tokens_saved", json.dumps(result))

    def test_report_renders_rollover_without_calling_segments_savings(self) -> None:
        start = self._rollover_start("report-rollover", "active", 1)
        finish = self._rollover_finish("report-rollover", 700, 840)
        report = task_run._public_report([start, finish])
        rendered = task_run._render_report(report)

        self.assertEqual(report["rollover_arm"], "active")
        self.assertEqual(report["metrics"]["rollover"]["combined"]["window_count"], 2)
        self.assertIn("task token segments (not causal savings)", rendered)
        self.assertIn("attempts=1/completed=1/failed=0", rendered)
        self.assertIn("checkpointed/prepared/correlated=1/1/1", rendered)


if __name__ == "__main__":
    unittest.main()
