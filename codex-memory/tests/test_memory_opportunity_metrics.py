#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


CODEX_MEMORY_DIR = Path(__file__).resolve().parents[1]
if str(CODEX_MEMORY_DIR) not in sys.path:
    sys.path.insert(0, str(CODEX_MEMORY_DIR))

import memory  # noqa: E402


SESSION = "1" * 16
ROOT_OPPORTUNITY = "a" * 16
SUBAGENT_OPPORTUNITY = "b" * 16
EXEMPT_OPPORTUNITY = "c" * 16
UNKNOWN_OPPORTUNITY = "d" * 16
ORPHAN_OPPORTUNITY = "e" * 16
ACTION_FOCUSED = "f" * 16
ACTION_CACHED = "6" * 16
ACTION_CACHED_TWO = "5" * 16
ACTION_BYPASS = "7" * 16
ACTION_FAIL_OPEN = "8" * 16
RAW_INTENT_ONE = "9" * 16
RAW_INTENT_TWO = "0" * 16


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


def now() -> str:
    return memory.dt.datetime.now(memory.dt.timezone.utc).isoformat()


def append_usage(runtime: memory.Runtime, **values: object) -> None:
    row: dict[str, object] = {
        "schema_version": 1,
        "ts": now(),
        "operation": "query",
        "codex_session_sha256": SESSION,
        "hit": True,
        "confidence": "focused",
        "tokens": 100,
        "coverage": 1.0,
        "duration_ms": 2,
        "auto_refreshed": False,
    }
    row.update(values)
    memory._append_jsonl(runtime.telemetry_path, row)


def append_event(runtime: memory.Runtime, **values: object) -> None:
    row: dict[str, object] = {
        "schema_version": 2,
        "policy_version": 2,
        "ts": now(),
        "codex_session_sha256": SESSION,
    }
    row.update(values)
    memory._append_jsonl(runtime.hook_events_path, row)


def opportunity(
    digest: str,
    *,
    kind: str = "secondary_read",
    eligible: bool = True,
    outcome: str = "focused_hit",
    action: str = "allow",
    agent: str = "root",
    attempted: bool = True,
    grounded: bool = True,
    raw_tokens: int = 1000,
    recall_tokens: int = 100,
    delivered_context_tokens: int | None = None,
    avoided_tokens: int = 0,
    blocked: bool = False,
    exclusion: str | None = None,
    mode: str = "enforce",
) -> dict[str, object]:
    row: dict[str, object] = {
        "event": "retrieval_opportunity",
        "opportunity_sha256": digest,
        "kind": kind,
        "eligible": eligible,
        "exclusion": exclusion,
        "mode": mode,
        "recall_attempted": attempted,
        "recall_outcome": outcome,
        "grounded": grounded,
        "action": action,
        "blocked": blocked,
        "agent_sha256": agent,
        "estimated_raw_tokens": raw_tokens,
        "recall_tokens": recall_tokens,
        "estimated_avoided_tokens": avoided_tokens,
    }
    if delivered_context_tokens is not None:
        row["delivered_context_tokens"] = delivered_context_tokens
    return row


def split_opportunity(
    action_digest: str,
    raw_intent_digest: str,
    *,
    policy_version: int = 4,
    **values: object,
) -> dict[str, object]:
    row = opportunity(action_digest, **values)  # type: ignore[arg-type]
    row["policy_version"] = policy_version
    row["raw_read_intent_sha256"] = raw_intent_digest
    return row


class MemoryOpportunityMetricsTest(unittest.TestCase):
    def test_latest_selects_hook_only_session_and_ignores_malformed_newer_row(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            query_session = "2" * 16
            hook_session = "3" * 16
            malformed_session = "4" * 16
            current = memory.dt.datetime.now(memory.dt.timezone.utc)
            append_usage(
                runtime,
                ts=(current - memory.dt.timedelta(minutes=2)).isoformat(),
                codex_session_sha256=query_session,
            )
            hook_row = split_opportunity(
                ACTION_FOCUSED,
                RAW_INTENT_ONE,
                action="inject",
                recall_tokens=30,
                delivered_context_tokens=30,
            )
            hook_row.update(
                {
                    "ts": (current - memory.dt.timedelta(minutes=1)).isoformat(),
                    "codex_session_sha256": hook_session,
                    "event": "retrieval_opportunity",
                }
            )
            memory._append_jsonl(runtime.hook_events_path, hook_row)
            malformed = split_opportunity(
                ACTION_CACHED,
                RAW_INTENT_TWO,
                action="deny",
                blocked=True,
                delivered_context_tokens=20,
                avoided_tokens=200,
            )
            malformed.update(
                {
                    "ts": "9999-99-99T99:99:99Z",
                    "codex_session_sha256": malformed_session,
                    "event": "retrieval_opportunity",
                }
            )
            memory._append_jsonl(runtime.hook_events_path, malformed)

            value = memory.stats(runtime, selector="latest")

            self.assertEqual(value["session"], hook_session)
            self.assertEqual(value["queries"], 0)
            self.assertEqual(value["retrieval_opportunities"], 1)
            self.assertEqual(value["retrieval_policy_versions"], {"4": 1})
            self.assertIn(
                "policy versions {'4': 1}", memory._render_stats(value)
            )

    def test_old_ledgers_remain_compatible_and_do_not_invent_v2_opportunities(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_usage(runtime)
            append_event(
                runtime,
                schema_version=1,
                policy_version=None,
                event="document_browse",
                grounded=False,
                reminder="initial",
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["queries"], 1)
            self.assertEqual(value["ungrounded_document_browses"], 1)
            self.assertEqual(value["retrieval_opportunities"], 0)
            self.assertEqual(value["retrieval_gross_avoided_tokens"], 0)
            self.assertIn("Retrieval opportunities: 0", memory._render_stats(value))

    def test_log_query_adds_optional_join_fields_without_leaking_question(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            result = memory.RecallResult(
                output="bounded answer",
                hit=True,
                confidence="focused",
                matched_terms=2,
                query_terms=2,
                selected_entities=1,
                source_documents=1,
                truncated=False,
                tokens=75,
            )
            memory.log_query(
                runtime,
                "private legacy question",
                120,
                result,
                duration_ms=1,
                refreshed=False,
                refresh_ms=0,
                session_sha256=SESSION,
            )
            memory.log_query(
                runtime,
                "private opportunity question",
                120,
                result,
                duration_ms=1,
                refreshed=False,
                refresh_ms=0,
                session_sha256=SESSION,
                agent_sha256="root",
                trigger="secondary_preflight",
                opportunity_sha256=ROOT_OPPORTUNITY,
                policy_version=2,
                mode="inject",
            )
            append_event(
                runtime,
                **opportunity(
                    ROOT_OPPORTUNITY,
                    action="inject",
                    recall_tokens=0,
                    avoided_tokens=900,
                ),
            )

            rows = memory._read_jsonl(runtime.telemetry_path)
            raw = runtime.telemetry_path.read_text(encoding="utf-8")
            self.assertNotIn("private legacy question", raw)
            self.assertNotIn("private opportunity question", raw)
            self.assertNotIn("opportunity_sha256", rows[0])
            self.assertEqual(rows[1]["opportunity_sha256"], ROOT_OPPORTUNITY)
            self.assertEqual(rows[1]["policy_version"], 2)
            self.assertEqual(rows[1]["mode"], "inject")
            self.assertEqual(rows[1]["agent_sha256"], "root")

            value = memory.stats(runtime, selector=SESSION)
            self.assertEqual(value["retrieval_query_joins"], 1)
            self.assertEqual(value["retrieval_recall_overhead_tokens"], 75)
            self.assertEqual(value["automatic_queries"], 1)
            self.assertEqual(value["secondary_preflight_queries"], 1)
            self.assertEqual(value["repeat_guard_automatic_queries"], 0)

    def test_log_query_malformed_policy_is_fail_safe_and_privacy_safe(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            result = memory.RecallResult(
                output="bounded answer",
                hit=True,
                confidence="focused",
                matched_terms=1,
                query_terms=1,
                selected_entities=1,
                source_documents=1,
                truncated=False,
                tokens=20,
            )
            malformed = "private malformed policy value"
            raw_session = "private raw session identity"
            raw_thread = "private raw thread identity"
            raw_agent = "private raw agent identity"
            raw_trigger = "private_raw_trigger"
            raw_intent = "private raw read intent identity"

            memory.log_query(
                runtime,
                "private malformed-policy question",
                120,
                result,
                duration_ms=1,
                refreshed=False,
                refresh_ms=0,
                session_sha256=raw_session,
                thread_sha256=raw_thread,
                agent_sha256=raw_agent,
                trigger=raw_trigger,
                opportunity_sha256=ROOT_OPPORTUNITY,
                raw_read_intent_sha256=raw_intent,
                policy_version=malformed,  # type: ignore[arg-type]
                mode="private-mode",
            )

            raw = runtime.telemetry_path.read_text(encoding="utf-8")
            row = json.loads(raw)
            self.assertEqual(row["policy_version"], "unknown")
            self.assertEqual(row["mode"], "unknown")
            self.assertEqual(row["codex_session_sha256"], memory.session_digest(raw_session))
            self.assertEqual(row["codex_thread_sha256"], memory.session_digest(raw_thread))
            self.assertEqual(row["agent_sha256"], memory.session_digest(raw_agent))
            self.assertEqual(row["trigger"], "unknown")
            self.assertEqual(
                row["raw_read_intent_sha256"], memory.session_digest(raw_intent)
            )
            self.assertNotIn(malformed, raw)
            self.assertNotIn("private malformed-policy question", raw)
            self.assertNotIn(raw_session, raw)
            self.assertNotIn(raw_thread, raw)
            self.assertNotIn(raw_agent, raw)
            self.assertNotIn(raw_trigger, raw)
            self.assertNotIn(raw_intent, raw)

    def test_log_query_can_join_v4_raw_intent_without_action_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            result = memory.RecallResult(
                output="bounded answer",
                hit=True,
                confidence="focused",
                matched_terms=1,
                query_terms=1,
                selected_entities=1,
                source_documents=1,
                truncated=False,
                tokens=45,
            )
            memory.log_query(
                runtime,
                "private split-identity question",
                120,
                result,
                duration_ms=1,
                refreshed=False,
                refresh_ms=0,
                session_sha256=SESSION,
                trigger="secondary_preflight",
                raw_read_intent_sha256=RAW_INTENT_ONE,
                policy_version=4,
                mode="enforce",
            )
            append_event(
                runtime,
                **split_opportunity(
                    ACTION_FOCUSED,
                    RAW_INTENT_ONE,
                    action="deny",
                    blocked=True,
                    recall_tokens=0,
                    delivered_context_tokens=45,
                    avoided_tokens=500,
                ),
            )

            row = memory._read_jsonl(runtime.telemetry_path)[0]
            self.assertNotIn("opportunity_sha256", row)
            self.assertEqual(row["raw_read_intent_sha256"], RAW_INTENT_ONE)
            self.assertEqual(row["policy_version"], 4)
            value = memory.stats(runtime, selector=SESSION)
            self.assertEqual(value["retrieval_query_joins"], 1)
            self.assertEqual(value["retrieval_recall_overhead_tokens"], 45)
            self.assertEqual(value["retrieval_direct_net_avoided_tokens"], 455)

    def test_injection_never_receives_direct_read_savings(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_event(
                runtime,
                **split_opportunity(
                    ACTION_FOCUSED,
                    RAW_INTENT_ONE,
                    action="inject",
                    raw_tokens=5000,
                    recall_tokens=80,
                    delivered_context_tokens=80,
                    avoided_tokens=5000,
                ),
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["retrieval_injections"], 1)
            self.assertEqual(value["retrieval_recall_overhead_tokens"], 80)
            self.assertEqual(value["retrieval_total_delivered_context_tokens"], 80)
            self.assertEqual(value["retrieval_blocked_delivered_context_tokens"], 0)
            self.assertEqual(value["retrieval_gross_avoided_tokens"], 0)
            self.assertEqual(value["retrieval_direct_net_avoided_tokens"], 0)

    def test_shadow_exact_hit_has_production_but_no_delivered_context(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_usage(
                runtime,
                policy_version=4,
                raw_read_intent_sha256=RAW_INTENT_ONE,
                opportunity_sha256=None,
                trigger="secondary_preflight",
                tokens=80,
            )
            append_event(
                runtime,
                **split_opportunity(
                    ACTION_FOCUSED,
                    RAW_INTENT_ONE,
                    mode="shadow",
                    action="allow",
                    recall_tokens=80,
                    delivered_context_tokens=0,
                    avoided_tokens=0,
                ),
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["retrieval_production_query_rows"], 1)
            self.assertEqual(value["retrieval_query_output_tokens"], 80)
            self.assertEqual(value["retrieval_total_delivered_context_tokens"], 0)
            self.assertEqual(value["retrieval_gross_avoided_tokens"], 0)
            self.assertEqual(value["retrieval_direct_net_avoided_tokens"], 0)

    def test_blocked_net_is_avoided_read_minus_joined_recall_once(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_usage(
                runtime,
                opportunity_sha256=ROOT_OPPORTUNITY,
                trigger="secondary_preflight",
                tokens=120,
            )
            append_event(
                runtime,
                **opportunity(
                    ROOT_OPPORTUNITY,
                    action="deny",
                    blocked=True,
                    recall_tokens=120,
                    avoided_tokens=1000,
                ),
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["retrieval_query_joins"], 1)
            self.assertEqual(value["retrieval_unique_blocked_intents"], 1)
            self.assertEqual(value["retrieval_grounded_blocks"], 1)
            self.assertEqual(value["retrieval_gross_avoided_tokens"], 1000)
            self.assertEqual(value["retrieval_recall_overhead_tokens"], 120)
            self.assertEqual(value["retrieval_total_delivered_context_tokens"], 120)
            self.assertEqual(value["retrieval_blocked_delivered_context_tokens"], 120)
            self.assertEqual(value["retrieval_direct_net_avoided_tokens"], 880)

    def test_repeated_executed_recalls_sum_overhead_but_not_savings(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_usage(
                runtime,
                opportunity_sha256=ROOT_OPPORTUNITY,
                trigger="secondary_preflight",
                tokens=40,
            )
            append_usage(
                runtime,
                opportunity_sha256=ROOT_OPPORTUNITY,
                trigger="secondary_preflight",
                tokens=60,
            )
            append_event(
                runtime,
                **opportunity(
                    ROOT_OPPORTUNITY,
                    action="deny",
                    blocked=True,
                    recall_tokens=60,
                    avoided_tokens=500,
                ),
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["retrieval_query_joins"], 1)
            self.assertEqual(value["retrieval_unique_blocked_intents"], 1)
            self.assertEqual(value["retrieval_gross_avoided_tokens"], 500)
            self.assertEqual(value["retrieval_recall_overhead_tokens"], 100)
            self.assertEqual(value["retrieval_total_delivered_context_tokens"], 60)
            self.assertEqual(value["retrieval_direct_net_avoided_tokens"], 440)

    def test_bypass_and_fail_open_actions_do_not_suppress_later_denies(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_event(
                runtime,
                **split_opportunity(
                    ACTION_BYPASS,
                    RAW_INTENT_ONE,
                    eligible=False,
                    attempted=False,
                    outcome="not_attempted",
                    action="exempt",
                    exclusion="bypass",
                    grounded=False,
                    recall_tokens=0,
                    delivered_context_tokens=0,
                ),
            )
            append_event(
                runtime,
                **split_opportunity(
                    ACTION_FOCUSED,
                    RAW_INTENT_ONE,
                    action="deny",
                    blocked=True,
                    recall_tokens=70,
                    delivered_context_tokens=70,
                    avoided_tokens=1000,
                ),
            )
            append_event(
                runtime,
                **split_opportunity(
                    ACTION_FAIL_OPEN,
                    RAW_INTENT_TWO,
                    outcome="miss",
                    action="fail_open",
                    grounded=False,
                    recall_tokens=30,
                    delivered_context_tokens=0,
                ),
            )
            append_event(
                runtime,
                **split_opportunity(
                    ACTION_CACHED,
                    RAW_INTENT_TWO,
                    action="deny",
                    blocked=True,
                    recall_tokens=70,
                    delivered_context_tokens=70,
                    avoided_tokens=1000,
                ),
            )
            for raw_intent, tokens in (
                (RAW_INTENT_ONE, 70),
                (RAW_INTENT_TWO, 30),
                (RAW_INTENT_TWO, 70),
            ):
                append_usage(
                    runtime,
                    policy_version=4,
                    raw_read_intent_sha256=raw_intent,
                    opportunity_sha256=None,
                    trigger="secondary_preflight",
                    tokens=tokens,
                )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["retrieval_opportunities"], 4)
            self.assertEqual(value["retrieval_raw_read_intents"], 2)
            self.assertEqual(value["retrieval_actions"]["deny"], 2)
            self.assertEqual(value["retrieval_actions"]["exempt"], 1)
            self.assertEqual(value["retrieval_actions"]["fail_open"], 1)
            self.assertEqual(value["retrieval_query_joins"], 2)
            self.assertEqual(value["retrieval_unique_blocked_intents"], 2)
            self.assertEqual(value["retrieval_gross_avoided_tokens"], 2000)
            self.assertEqual(value["retrieval_blocked_recall_overhead_tokens"], 170)
            self.assertEqual(value["retrieval_blocked_delivered_context_tokens"], 140)
            self.assertEqual(value["retrieval_direct_net_avoided_tokens"], 1860)

    def test_initial_deny_two_cached_actions_and_whole_bypass_share_one_intent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_usage(
                runtime,
                policy_version=4,
                raw_read_intent_sha256=RAW_INTENT_ONE,
                opportunity_sha256=None,
                trigger="secondary_preflight",
                tokens=100,
            )
            append_event(
                runtime,
                **split_opportunity(
                    ACTION_FOCUSED,
                    RAW_INTENT_ONE,
                    action="deny",
                    blocked=True,
                    recall_tokens=100,
                    delivered_context_tokens=100,
                    avoided_tokens=1000,
                ),
            )
            append_event(
                runtime,
                **split_opportunity(
                    ACTION_CACHED,
                    RAW_INTENT_ONE,
                    attempted=False,
                    outcome="cached_hit",
                    action="deny",
                    blocked=True,
                    recall_tokens=0,
                    delivered_context_tokens=100,
                    avoided_tokens=1000,
                ),
            )
            append_event(
                runtime,
                **split_opportunity(
                    ACTION_CACHED_TWO,
                    RAW_INTENT_ONE,
                    attempted=True,
                    outcome="cached_hit",
                    action="deny",
                    blocked=True,
                    recall_tokens=0,
                    delivered_context_tokens=100,
                    avoided_tokens=1000,
                ),
            )
            append_event(
                runtime,
                policy_version=4,
                event="retrieval_followup",
                opportunity_sha256=ACTION_FOCUSED,
                raw_read_intent_sha256=RAW_INTENT_ONE,
                outcome="whole_read",
                estimated_raw_tokens=1000,
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["retrieval_opportunities"], 3)
            self.assertEqual(value["retrieval_raw_read_intents"], 1)
            self.assertEqual(value["retrieval_attempted_opportunities"], 3)
            self.assertEqual(value["retrieval_cached_hits"], 2)
            self.assertEqual(value["retrieval_actions"]["deny"], 3)
            self.assertEqual(value["retrieval_unique_blocked_intents"], 1)
            self.assertEqual(value["retrieval_gross_avoided_tokens"], 1000)
            self.assertEqual(value["retrieval_recall_overhead_tokens"], 100)
            self.assertEqual(value["retrieval_total_delivered_context_tokens"], 300)
            self.assertEqual(value["retrieval_blocked_delivered_context_tokens"], 300)
            self.assertEqual(value["retrieval_followup_cost_tokens"], 1000)
            self.assertEqual(value["retrieval_direct_net_avoided_tokens"], -300)

    def test_v4_followup_joins_raw_intent_and_erases_gross(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_usage(
                runtime,
                policy_version=4,
                raw_read_intent_sha256=RAW_INTENT_ONE,
                opportunity_sha256=None,
                trigger="secondary_preflight",
                tokens=100,
            )
            append_event(
                runtime,
                **split_opportunity(
                    ACTION_FOCUSED,
                    RAW_INTENT_ONE,
                    action="deny",
                    blocked=True,
                    recall_tokens=0,
                    delivered_context_tokens=100,
                    avoided_tokens=1000,
                ),
            )
            append_event(
                runtime,
                policy_version=4,
                event="retrieval_followup",
                opportunity_sha256=ACTION_FOCUSED,
                raw_read_intent_sha256=RAW_INTENT_ONE,
                outcome="whole_read",
                estimated_raw_tokens=1000,
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["retrieval_followup_opportunities"], 1)
            self.assertEqual(value["retrieval_followup_cost_tokens"], 1000)
            self.assertEqual(value["retrieval_gross_avoided_tokens"], 1000)
            self.assertEqual(value["retrieval_blocked_recall_overhead_tokens"], 100)
            self.assertEqual(value["retrieval_direct_net_avoided_tokens"], -100)

    def test_terminal_followups_never_charge_stale_blocked_estimates(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_event(
                runtime,
                **split_opportunity(
                    ACTION_FOCUSED,
                    RAW_INTENT_ONE,
                    action="deny",
                    blocked=True,
                    recall_tokens=80,
                    delivered_context_tokens=80,
                    avoided_tokens=500,
                ),
            )
            for outcome in ("timeout", "abandoned"):
                append_event(
                    runtime,
                    policy_version=4,
                    event="retrieval_followup",
                    opportunity_sha256=ACTION_FOCUSED,
                    raw_read_intent_sha256=RAW_INTENT_ONE,
                    outcome=outcome,
                    estimated_raw_tokens=500,
                )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["retrieval_gross_avoided_tokens"], 500)
            self.assertEqual(value["retrieval_blocked_delivered_context_tokens"], 80)
            self.assertEqual(value["retrieval_total_followup_tokens"], 0)
            self.assertEqual(value["retrieval_followup_cost_tokens"], 0)
            self.assertEqual(
                value["retrieval_targeted_fallback_outcomes"]["timeout"], 1
            )
            self.assertEqual(
                value["retrieval_targeted_fallback_outcomes"]["abandoned"], 1
            )
            self.assertEqual(value["retrieval_direct_net_avoided_tokens"], 420)

    def test_targeted_followup_reduces_net_and_orphan_queries_count_as_overhead(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_usage(
                runtime,
                opportunity_sha256=ORPHAN_OPPORTUNITY,
                trigger="secondary_preflight",
                tokens=30,
            )
            append_event(
                runtime,
                **opportunity(
                    ROOT_OPPORTUNITY,
                    action="deny",
                    blocked=True,
                    recall_tokens=100,
                    avoided_tokens=1000,
                ),
            )
            append_event(
                runtime,
                event="retrieval_followup",
                opportunity_sha256=ROOT_OPPORTUNITY,
                outcome="targeted_window",
                estimated_raw_tokens=80,
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["retrieval_orphaned_query_opportunities"], 1)
            self.assertEqual(value["retrieval_orphaned_query_tokens"], 30)
            self.assertEqual(value["retrieval_recall_overhead_tokens"], 130)
            self.assertEqual(value["retrieval_blocked_recall_overhead_tokens"], 100)
            self.assertEqual(value["retrieval_total_followup_tokens"], 80)
            self.assertEqual(value["retrieval_followup_cost_tokens"], 80)
            self.assertEqual(value["retrieval_gross_avoided_tokens"], 1000)
            self.assertEqual(value["retrieval_direct_net_avoided_tokens"], 820)
            self.assertIn(
                "~1000 gross - ~100 delivered context - ~80 follow-up cost = ~820 net",
                memory._render_stats(value),
            )

    def test_whole_or_primary_bypass_followup_erases_gross_savings(self) -> None:
        for followup_outcome, followup_tokens in (
            ("whole_read", 1000),
            ("primary_bypass", 0),
        ):
            with self.subTest(outcome=followup_outcome):
                with tempfile.TemporaryDirectory() as temporary:
                    runtime = runtime_for(Path(temporary))
                    append_event(
                        runtime,
                        **opportunity(
                            ROOT_OPPORTUNITY,
                            action="deny",
                            blocked=True,
                            recall_tokens=100,
                            avoided_tokens=1000,
                        ),
                    )
                    append_event(
                        runtime,
                        event="retrieval_followup",
                        opportunity_sha256=ROOT_OPPORTUNITY,
                        outcome=followup_outcome,
                        estimated_raw_tokens=followup_tokens,
                    )

                    value = memory.stats(runtime, selector=SESSION)

                    self.assertEqual(value["retrieval_gross_avoided_tokens"], 1000)
                    self.assertEqual(
                        value["retrieval_blocked_recall_overhead_tokens"], 100
                    )
                    self.assertEqual(value["retrieval_followup_cost_tokens"], 1000)
                    self.assertEqual(value["retrieval_direct_net_avoided_tokens"], -100)

    def test_primary_read_kind_is_reported_as_primary_exemption(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_event(
                runtime,
                **opportunity(
                    ROOT_OPPORTUNITY,
                    kind="primary_read",
                    eligible=False,
                    attempted=False,
                    outcome="not_attempted",
                    action="exempt",
                    exclusion=None,
                    grounded=False,
                    recall_tokens=0,
                ),
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["retrieval_opportunities_by_kind"], {"primary_read": 1})
            self.assertEqual(value["retrieval_primary_exemptions"], 1)

    def test_metric_tokens_reject_nonfinite_values(self) -> None:
        for value in (float("inf"), float("-inf"), float("nan"), "inf", "nan"):
            with self.subTest(value=value):
                self.assertEqual(memory._metric_int(value), 0)

    def test_cached_retry_dedupes_blocked_intent_and_savings(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_usage(runtime, opportunity_sha256=ROOT_OPPORTUNITY, tokens=100)
            append_event(
                runtime,
                **opportunity(
                    ROOT_OPPORTUNITY,
                    action="deny",
                    blocked=True,
                    avoided_tokens=1000,
                ),
            )
            append_event(
                runtime,
                **opportunity(
                    ROOT_OPPORTUNITY,
                    action="deny",
                    blocked=True,
                    attempted=False,
                    outcome="cached_hit",
                    recall_tokens=0,
                    avoided_tokens=1000,
                ),
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["retrieval_opportunities"], 1)
            self.assertEqual(value["retrieval_opportunity_events"], 2)
            self.assertEqual(value["retrieval_duplicate_opportunity_events"], 1)
            self.assertEqual(value["retrieval_cached_retry_events"], 1)
            self.assertEqual(value["retrieval_unique_blocked_intents"], 1)
            self.assertEqual(value["retrieval_gross_avoided_tokens"], 1000)
            self.assertEqual(value["retrieval_recall_overhead_tokens"], 100)
            self.assertEqual(value["retrieval_direct_net_avoided_tokens"], 900)

    def test_v2_aliases_join_without_exposing_accounting_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_usage(
                runtime,
                opportunity_hash=ROOT_OPPORTUNITY,
                tokens=60,
            )
            append_event(
                runtime,
                type="retrieval-opportunity",
                opportunity_hash=ROOT_OPPORTUNITY,
                opportunity_kind="repeat_read",
                retrieval_eligible=True,
                retrieval_mode="enforce",
                attempted=True,
                retrieval_outcome="focused_hit",
                retrieval_action="deny",
                grounded_block=True,
                agent_sha256="root",
                estimated_tokens=700,
                retrieval_tokens=60,
                avoided_tokens=700,
            )
            append_event(
                runtime,
                type="retrieval-opportunity-followup",
                opportunity_hash=ROOT_OPPORTUNITY,
                followup_outcome="targeted_window",
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["retrieval_query_joins"], 1)
            self.assertEqual(value["retrieval_opportunities_by_kind"], {"repeat_read": 1})
            self.assertEqual(value["retrieval_unique_blocked_intents"], 1)
            self.assertEqual(value["retrieval_grounded_blocks"], 1)
            self.assertEqual(value["retrieval_direct_net_avoided_tokens"], 640)
            self.assertEqual(value["retrieval_targeted_fallbacks"], 1)

    def test_policy2_and_policy3_delivery_fallbacks_remain_private(self) -> None:
        for policy_version, recall_tokens, expected_net in (
            (2, 80, 920),
            (3, 90, 910),
        ):
            with self.subTest(policy_version=policy_version):
                with tempfile.TemporaryDirectory() as temporary:
                    runtime = runtime_for(Path(temporary))
                    if policy_version == 2:
                        row = opportunity(
                            ROOT_OPPORTUNITY,
                            action="deny",
                            blocked=True,
                            recall_tokens=recall_tokens,
                            avoided_tokens=1000,
                        )
                    else:
                        row = split_opportunity(
                            ACTION_FOCUSED,
                            RAW_INTENT_ONE,
                            policy_version=3,
                            action="deny",
                            blocked=True,
                            recall_tokens=recall_tokens,
                            avoided_tokens=1000,
                        )
                    append_event(runtime, **row)

                    value = memory.stats(runtime, selector=SESSION)
                    rendered = json.dumps(value, sort_keys=True)

                    self.assertEqual(
                        value["retrieval_total_delivered_context_tokens"],
                        recall_tokens,
                    )
                    self.assertEqual(
                        value["retrieval_blocked_delivered_context_tokens"],
                        recall_tokens,
                    )
                    self.assertEqual(
                        value["retrieval_direct_net_avoided_tokens"], expected_net
                    )
                    self.assertNotIn(ROOT_OPPORTUNITY, rendered)
                    self.assertNotIn(RAW_INTENT_ONE, rendered)

    def test_fallback_transitions_exemptions_and_agent_splits_are_accounted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_event(
                runtime,
                **opportunity(
                    ROOT_OPPORTUNITY,
                    kind="broad_sweep",
                    outcome="broad_hit",
                    action="inject",
                    agent="root",
                ),
            )
            append_event(
                runtime,
                **opportunity(
                    SUBAGENT_OPPORTUNITY,
                    outcome="error",
                    action="fail_open",
                    agent="subagent-hash",
                ),
            )
            append_event(
                runtime,
                **opportunity(
                    EXEMPT_OPPORTUNITY,
                    kind="repeat_read",
                    eligible=False,
                    attempted=False,
                    outcome="disabled",
                    action="exempt",
                    exclusion="primary_document",
                    agent="root",
                    grounded=False,
                    recall_tokens=0,
                ),
            )
            private_reason = "private/customer/roadmap.md"
            unknown = opportunity(
                UNKNOWN_OPPORTUNITY,
                kind="broad_sweep",
                eligible=False,
                attempted=False,
                outcome="not_attempted",
                action="exempt",
                agent="",
                grounded=False,
                recall_tokens=0,
            )
            unknown["exclusion"] = private_reason
            append_event(runtime, **unknown)
            for outcome in ("targeted_search", "whole_read", "targeted_search"):
                append_event(
                    runtime,
                    event="retrieval_followup",
                    opportunity_sha256=ROOT_OPPORTUNITY,
                    outcome=outcome,
                )
            append_event(
                runtime,
                event="retrieval_followup",
                opportunity_sha256=EXEMPT_OPPORTUNITY,
                outcome="primary_bypass",
            )

            value = memory.stats(runtime, selector=SESSION)
            rendered = json.dumps(value, sort_keys=True)

            self.assertEqual(value["retrieval_opportunities"], 4)
            self.assertEqual(value["retrieval_eligible_opportunities"], 2)
            self.assertEqual(value["retrieval_excluded_opportunities"], 2)
            self.assertEqual(value["retrieval_attempted_opportunities"], 2)
            self.assertEqual(value["retrieval_attempt_coverage"], 1.0)
            self.assertEqual(value["retrieval_broad_hits"], 1)
            self.assertEqual(value["retrieval_errors"], 1)
            self.assertEqual(value["retrieval_primary_exemptions"], 1)
            self.assertEqual(value["retrieval_targeted_fallbacks"], 1)
            self.assertEqual(
                value["retrieval_targeted_fallback_outcomes"]["targeted_search"],
                1,
            )
            self.assertEqual(
                value["retrieval_targeted_fallback_outcomes"]["whole_read"], 1
            )
            self.assertEqual(value["retrieval_agent_splits"]["root"]["total"], 2)
            self.assertEqual(
                value["retrieval_agent_splits"]["subagent"]["total"], 1
            )
            self.assertEqual(value["retrieval_agent_splits"]["unknown"]["total"], 1)
            self.assertNotIn(private_reason, rendered)
            self.assertNotIn(ROOT_OPPORTUNITY, rendered)
            self.assertNotIn("subagent-hash", rendered)

    def test_constraints_include_eligible_non_enforcement_reasons(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            rows = (
                (ACTION_FOCUSED, "unconfirmed", True, "inject"),
                (ACTION_CACHED, "provisional_primary", True, "inject"),
                (
                    ACTION_CACHED_TWO,
                    "below_enforcement_threshold",
                    True,
                    "inject",
                ),
                (ACTION_BYPASS, "mixed", False, "fail_open"),
            )
            for action_digest, reason, eligible, action in rows:
                append_event(
                    runtime,
                    **split_opportunity(
                        action_digest,
                        RAW_INTENT_ONE,
                        eligible=eligible,
                        exclusion=reason,
                        action=action,
                        recall_tokens=10,
                        delivered_context_tokens=(10 if action == "inject" else 0),
                    ),
                )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["retrieval_eligible_opportunities"], 3)
            self.assertEqual(value["retrieval_excluded_opportunities"], 1)
            self.assertEqual(value["retrieval_exclusions_by_reason"], {"mixed": 1})
            self.assertEqual(
                value["retrieval_constraints_by_reason"],
                {
                    "below_enforcement_threshold": 1,
                    "mixed": 1,
                    "provisional_primary": 1,
                    "unconfirmed": 1,
                },
            )


if __name__ == "__main__":
    unittest.main()
