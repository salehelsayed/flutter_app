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
OTHER_SESSION = "2" * 16
ROOT_THREAD = "3" * 16
SUBAGENT_THREAD = "4" * 16
ROOT_CHECKPOINT = "a" * 16
SUBAGENT_CHECKPOINT = "b" * 16


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


def now(offset_seconds: int = 0) -> str:
    value = memory.dt.datetime.now(memory.dt.timezone.utc)
    value += memory.dt.timedelta(seconds=offset_seconds)
    return value.isoformat()


def append_rollover(
    runtime: memory.Runtime,
    event: str,
    *,
    session: str = SESSION,
    scope: str = "root",
    thread: str = ROOT_THREAD,
    checkpoint: str = ROOT_CHECKPOINT,
    timestamp: str | None = None,
    **values: object,
) -> None:
    row: dict[str, object] = {
        "schema_version": 1,
        "event": event,
        "timestamp": timestamp or now(),
        "codex_session_sha256": session,
        "codex_thread_sha256": thread,
        "agent_scope": scope,
        "trigger": "fixture",
        "checkpoint_sha256": checkpoint,
        "checkpoint_bytes": 400,
        "checkpoint_tokens_estimate": 100,
        "generation": 1,
        "ready": True,
        "phase_sha256": "c" * 16,
        "plan_sha256": "d" * 16,
    }
    row.update(values)
    memory._append_jsonl(
        runtime.state_dir / "context-rollover-events.jsonl", row
    )


class RolloverMetricsTest(unittest.TestCase):
    def test_no_rollover_ledger_is_backward_compatible(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))

            value = memory.stats(runtime, selector=SESSION)
            rendered = memory._render_stats(value)

            self.assertEqual(value["rollover_event_count"], 0)
            self.assertEqual(value["rollover_checkpoints_saved"], 0)
            self.assertEqual(value["rollover_checkpoint_repo_scopes"], {})
            self.assertEqual(value["rollover_task_scoped_checkpoints"], 0)
            self.assertEqual(value["rollover_ready_task_scoped_checkpoints"], 0)
            self.assertEqual(value["rollover_legacy_worktree_checkpoints"], 0)
            self.assertEqual(value["rollover_task_scope_adoption"], 0.0)
            self.assertEqual(value["rollover_task_scope_attempt_rate"], 0.0)
            self.assertEqual(value["rollover_task_path_count_total"], 0)
            self.assertEqual(value["rollover_by_scope"]["root"]["events"], 0)
            self.assertEqual(
                value["rollover_task_tokens_before_first"],
                "not_available_here",
            )
            self.assertEqual(value["rollover_task_token_source"], "task_run")
            self.assertFalse(value["rollover_observed_context_drop_is_savings"])
            self.assertIn("observed context dropped not_available_here (not savings)", rendered)

    def test_lifecycle_is_deduplicated_split_and_safely_aggregated(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_rollover(runtime, "checkpoint_saved")
            append_rollover(runtime, "checkpoint_saved", duplicate=True)
            append_rollover(runtime, "precompact_allowed")
            append_rollover(runtime, "postcompact_observed")
            append_rollover(runtime, "session_resumed")
            append_rollover(runtime, "checkpoint_completed")
            append_rollover(
                runtime,
                "precompact_blocked",
                checkpoint="e" * 16,
                ready=False,
                checkpoint_bytes="999999",
                checkpoint_tokens_estimate="999999",
                reason_codes=[
                    "next_action_missing",
                    "changed_path_outside_repo",
                    "/private/customer/secret-plan.md",
                ],
            )
            append_rollover(
                runtime,
                "checkpoint_stale",
                checkpoint="f" * 16,
                ready=False,
                reason_codes=["prepared_checkpoint_stale"],
            )
            append_rollover(
                runtime,
                "checkpoint_saved",
                scope="subagent",
                thread=SUBAGENT_THREAD,
                checkpoint=SUBAGENT_CHECKPOINT,
                checkpoint_bytes=120,
                checkpoint_tokens_estimate=30,
                ready=False,
            )
            append_rollover(
                runtime,
                "subagent_skipped",
                scope="subagent",
                thread=SUBAGENT_THREAD,
                checkpoint=SUBAGENT_CHECKPOINT,
                checkpoint_bytes=120,
                checkpoint_tokens_estimate=30,
                ready=False,
                reason_codes=["subagent_rollover_unsupported"],
            )

            value = memory.stats(runtime, selector=SESSION)
            serialized = json.dumps(value, sort_keys=True)
            rendered = memory._render_stats(value)

            self.assertEqual(value["rollover_event_count"], 10)
            self.assertEqual(value["rollover_checkpoint_save_events"], 3)
            self.assertEqual(value["rollover_checkpoints_saved"], 2)
            self.assertEqual(value["rollover_checkpoint_bytes"], 520)
            self.assertEqual(value["rollover_checkpoint_tokens_estimate"], 130)
            self.assertEqual(
                value["rollover_checkpoint_tokens_estimate_basis"],
                "model_visible_capsule",
            )
            self.assertEqual(
                value["rollover_checkpoint_repo_scopes"],
                {"legacy_worktree_v1": 2},
            )
            self.assertEqual(value["rollover_task_scoped_checkpoints"], 0)
            self.assertEqual(value["rollover_legacy_worktree_checkpoints"], 2)
            self.assertEqual(value["rollover_task_scope_adoption"], 0.0)
            self.assertEqual(value["rollover_precompact_allowed"], 1)
            self.assertEqual(value["rollover_precompact_blocked"], 1)
            self.assertEqual(value["rollover_postcompact_observed"], 1)
            self.assertEqual(value["rollover_session_resumed"], 1)
            self.assertEqual(value["rollover_checkpoint_completed"], 1)
            self.assertEqual(value["rollover_checkpoint_validation_failures"], 1)
            self.assertEqual(value["rollover_interruptions"], 1)
            self.assertEqual(value["rollover_failures"], 1)
            self.assertEqual(value["rollover_resumed_contexts_observed"], 1)
            self.assertEqual(value["rollover_context_window_count"], "not_available_here")
            self.assertEqual(value["rollover_by_scope"]["root"]["events"], 8)
            self.assertEqual(value["rollover_by_scope"]["subagent"]["events"], 2)
            self.assertEqual(value["rollover_by_scope"]["root"]["failures"], 1)
            self.assertEqual(
                value["rollover_reason_codes"],
                {
                    "changed_path_outside_repo": 1,
                    "next_action_missing": 1,
                    "prepared_checkpoint_stale": 1,
                    "subagent_rollover_unsupported": 1,
                    "unknown": 1,
                },
            )
            self.assertNotIn("/private/customer/secret-plan.md", serialized)
            self.assertNotIn("/private/customer/secret-plan.md", rendered)
            self.assertIn(
                "Rollover scopes: root 8 events/1 resumed/1 interrupted", rendered
            )
            self.assertIn(
                "0 ready task-scoped/1 ready whole-worktree/0 ready unknown",
                rendered,
            )

    def test_task_scope_adoption_is_deduplicated_alias_tolerant_and_private(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_rollover(
                runtime,
                "checkpoint_saved",
                generation=1,
                repo_scope="task_paths_v1",
                task_path_count=4,
                task_scope_complete=True,
            )
            append_rollover(
                runtime,
                "checkpoint_saved",
                generation=1,
                repo_scope="task_paths_v1",
                task_path_count=4,
                task_scope_complete=True,
                duplicate=True,
            )
            append_rollover(
                runtime,
                "checkpoint_saved",
                generation=2,
                repository_scope_mode="task-scope",
                task_scope_path_count=3,
                repository_scope_complete=True,
            )
            append_rollover(
                runtime,
                "checkpoint_saved",
                generation=3,
                repo_scope="legacy_worktree_v1",
                task_path_count=99,
            )
            append_rollover(
                runtime,
                "checkpoint_saved",
                generation=4,
                repo_scope="private /customer/secret/path",
                task_path_count="private /customer/secret/count",
            )
            append_rollover(
                runtime,
                "checkpoint_stale",
                generation=1,
                ready=False,
                reason_codes=[
                    "task_scope_changed",
                    "changed_path_limit_exceeded",
                ],
            )

            value = memory.stats(runtime, selector=SESSION)
            serialized = json.dumps(value, sort_keys=True)
            rendered = memory._render_stats(value)

            self.assertEqual(value["rollover_checkpoints_saved"], 4)
            self.assertEqual(
                value["rollover_checkpoint_repo_scopes"],
                {
                    "legacy_worktree_v1": 1,
                    "task_paths_v1": 2,
                    "unknown": 1,
                },
            )
            self.assertEqual(value["rollover_task_scoped_checkpoints"], 2)
            self.assertEqual(value["rollover_legacy_worktree_checkpoints"], 1)
            self.assertEqual(value["rollover_unknown_repo_scope_checkpoints"], 1)
            self.assertEqual(value["rollover_ready_task_scoped_checkpoints"], 2)
            self.assertEqual(value["rollover_ready_legacy_worktree_checkpoints"], 1)
            self.assertEqual(value["rollover_ready_unknown_repo_scope_checkpoints"], 1)
            self.assertEqual(value["rollover_task_scope_adoption"], 0.5)
            self.assertEqual(value["rollover_task_scope_attempt_rate"], 0.5)
            self.assertEqual(value["rollover_task_scope_complete_attempts"], 2)
            self.assertEqual(value["rollover_task_path_count_total"], 7)
            self.assertEqual(value["rollover_task_path_count_max"], 4)
            self.assertEqual(
                value["rollover_reason_codes"],
                {"changed_path_limit_exceeded": 1, "task_scope_changed": 1},
            )
            self.assertIn(
                "2 ready task-scoped/1 ready whole-worktree/1 ready unknown",
                rendered,
            )
            self.assertIn("(0.5 operational adoption)", rendered)
            self.assertIn(
                "7 ready scoped-path slots/4 max per ready checkpoint",
                rendered,
            )
            self.assertNotIn("/customer/secret", serialized)
            self.assertNotIn("/customer/secret", rendered)

    def test_not_ready_task_scope_is_attempted_but_not_adopted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_rollover(
                runtime,
                "checkpoint_saved",
                repo_scope="task_paths_v1",
                task_path_count=5,
                task_scope_complete=True,
                ready=False,
                reason_codes=["repo_fingerprint_unavailable", "plan_read_failed"],
            )

            value = memory.stats(runtime, selector=SESSION)
            rendered = memory._render_stats(value)

            self.assertEqual(value["rollover_task_scoped_checkpoints"], 1)
            self.assertEqual(value["rollover_ready_task_scoped_checkpoints"], 0)
            self.assertEqual(value["rollover_task_scope_attempt_rate"], 1.0)
            self.assertEqual(value["rollover_task_scope_complete_attempts"], 1)
            self.assertEqual(value["rollover_task_scope_adoption"], 0.0)
            self.assertEqual(value["rollover_attempted_task_path_count_total"], 5)
            self.assertEqual(value["rollover_task_path_count_total"], 0)
            self.assertEqual(value["rollover_task_scoped_resumes"], 0)
            self.assertEqual(
                value["rollover_reason_codes"],
                {"plan_read_failed": 1, "repo_fingerprint_unavailable": 1},
            )
            self.assertIn("0 ready task-scoped", rendered)
            self.assertIn("attempted 1 task-scoped", rendered)

    def test_historical_unasserted_task_scope_is_not_operational_adoption(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_rollover(
                runtime,
                "checkpoint_saved",
                repo_scope="task_paths_v1",
                task_path_count=4,
                ready=True,
            )
            append_rollover(
                runtime,
                "session_resumed",
                repo_scope="task_paths_v1",
                task_path_count=4,
                ready=True,
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["rollover_task_scoped_checkpoints"], 1)
            self.assertEqual(value["rollover_task_scope_complete_attempts"], 0)
            self.assertEqual(value["rollover_ready_task_scoped_checkpoints"], 0)
            self.assertEqual(value["rollover_ready_unknown_repo_scope_checkpoints"], 1)
            self.assertEqual(value["rollover_task_scope_adoption"], 0.0)
            self.assertEqual(value["rollover_task_path_count_total"], 0)
            self.assertEqual(value["rollover_task_scoped_resumes"], 0)

    def test_latest_includes_a_rollover_only_session(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            memory._append_jsonl(
                runtime.telemetry_path,
                {
                    "schema_version": 1,
                    "ts": now(-10),
                    "operation": "query",
                    "codex_session_sha256": SESSION,
                    "hit": False,
                    "tokens": 10,
                },
            )
            append_rollover(
                runtime,
                "checkpoint_saved",
                session=OTHER_SESSION,
                timestamp=now(-1),
            )

            value = memory.stats(runtime, selector="latest")

            self.assertEqual(value["session"], OTHER_SESSION)
            self.assertEqual(value["queries"], 0)
            self.assertEqual(value["rollover_checkpoints_saved"], 1)

    def test_stale_and_blocked_markers_are_one_failed_precompact_attempt(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            timestamp = now()
            append_rollover(
                runtime,
                "checkpoint_stale",
                timestamp=timestamp,
                ready=False,
                reason_codes=["plan_changed"],
            )
            append_rollover(
                runtime,
                "precompact_blocked",
                timestamp=timestamp,
                ready=False,
                reason_codes=["plan_changed"],
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["rollover_checkpoint_stale"], 1)
            self.assertEqual(value["rollover_precompact_blocked"], 1)
            self.assertEqual(value["rollover_checkpoint_validation_failures"], 1)
            self.assertEqual(value["rollover_interruptions"], 1)
            self.assertEqual(value["rollover_failures"], 1)
            self.assertEqual(value["rollover_reason_codes"], {"plan_changed": 1})

    def test_advisory_recovery_is_visible_but_not_an_interruption(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            timestamp = now()
            append_rollover(
                runtime,
                "checkpoint_stale",
                timestamp=timestamp,
                ready=False,
                reason_codes=["worktree_changed"],
                continuation_mode="recovery_advisory",
            )
            append_rollover(
                runtime,
                "precompact_recovery_allowed",
                timestamp=timestamp,
                ready=False,
                reason_codes=["worktree_changed", "rollover_intent_missing"],
                continuation_mode="recovery_advisory",
            )
            append_rollover(
                runtime,
                "session_recovery_advisory",
                timestamp=now(1),
                ready=False,
                reason_codes=["worktree_changed"],
                continuation_mode="recovery_advisory",
            )

            value = memory.stats(runtime, selector=SESSION)
            rendered = memory._render_stats(value)

            self.assertEqual(value["rollover_precompact_recovery_allowed"], 1)
            self.assertEqual(value["rollover_session_recovery_advisory"], 1)
            self.assertEqual(value["rollover_recovery_contexts_observed"], 1)
            self.assertEqual(value["rollover_checkpoint_validation_failures"], 1)
            self.assertEqual(value["rollover_interruptions"], 0)
            self.assertEqual(value["rollover_failures"], 0)
            self.assertEqual(value["rollover_reason_codes"]["rollover_intent_missing"], 1)
            self.assertIn("1 recovery/0 blocked", rendered)
            self.assertIn("0 validated resumed/1 advisory recovery", rendered)

    def test_terminal_after_not_ready_is_a_permanent_failure_after_user_rescue(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_rollover(
                runtime,
                "checkpoint_saved",
                timestamp=now(-3),
                ready=False,
                reason_codes=["repo_fingerprint_unavailable"],
            )
            append_rollover(
                runtime,
                "terminal_after_not_ready",
                timestamp=now(-2),
                ready=False,
            )
            append_rollover(
                runtime,
                "user_rescue_after_terminal",
                timestamp=now(-1),
                ready=False,
            )

            value = memory.stats(runtime, selector=SESSION)
            rendered = memory._render_stats(value)

            self.assertEqual(value["rollover_not_ready_lifecycles"], 1)
            self.assertEqual(value["rollover_unresolved_not_ready"], 0)
            self.assertEqual(value["rollover_terminal_after_not_ready"], 1)
            self.assertEqual(value["rollover_user_rescue_after_terminal"], 1)
            self.assertEqual(value["rollover_interruptions"], 1)
            self.assertEqual(value["rollover_failures"], 1)
            self.assertIn("1 terminal failures/1 later user rescues", rendered)

    def test_not_ready_repair_hard_fallback_and_blocked_terminal_are_distinct(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_rollover(
                runtime,
                "checkpoint_saved",
                generation=1,
                timestamp=now(-10),
                ready=False,
                not_ready_episode_sha256="1" * 16,
            )
            append_rollover(
                runtime,
                "checkpoint_saved",
                generation=2,
                timestamp=now(-9),
                ready=True,
                not_ready_episode_sha256="1" * 16,
            )
            append_rollover(
                runtime,
                "precompact_allowed",
                generation=2,
                timestamp=now(-8),
                ready=True,
                not_ready_episode_sha256="1" * 16,
            )
            append_rollover(
                runtime,
                "checkpoint_saved",
                generation=3,
                timestamp=now(-7),
                ready=False,
                not_ready_episode_sha256="2" * 16,
            )
            append_rollover(
                runtime,
                "checkpoint_advisory_reset_requested",
                generation=3,
                timestamp=now(-6),
                ready=False,
                continuation_mode="recovery_advisory",
                not_ready_episode_sha256="2" * 16,
            )
            append_rollover(
                runtime,
                "terminal_after_not_ready_blocked",
                generation=3,
                timestamp=now(-5),
                ready=False,
                continuation_mode="recovery_advisory",
                not_ready_episode_sha256="2" * 16,
            )
            append_rollover(
                runtime,
                "precompact_recovery_allowed",
                generation=3,
                timestamp=now(-4),
                ready=False,
                continuation_mode="recovery_advisory",
                reason_codes=["advisory_reset_requested"],
                not_ready_episode_sha256="2" * 16,
            )
            append_rollover(
                runtime,
                "checkpoint_saved",
                generation=4,
                timestamp=now(-3),
                ready=False,
                not_ready_episode_sha256="3" * 16,
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["rollover_not_ready_lifecycles"], 3)
            self.assertEqual(value["rollover_not_ready_repairs_before_terminal"], 1)
            self.assertEqual(value["rollover_not_ready_advisories_before_terminal"], 1)
            self.assertEqual(value["rollover_checkpoint_advisory_reset_requested"], 1)
            self.assertEqual(value["rollover_terminal_after_not_ready_blocked"], 1)
            self.assertEqual(value["rollover_unresolved_not_ready"], 1)
            self.assertEqual(value["rollover_terminal_after_not_ready"], 0)
            self.assertEqual(value["rollover_failures"], 0)
            self.assertEqual(
                value["rollover_reason_codes"],
                {"advisory_reset_requested": 1},
            )

    def test_advisory_request_without_precompact_remains_unresolved(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_rollover(
                runtime,
                "checkpoint_saved",
                generation=1,
                timestamp=now(-2),
                ready=False,
            )
            append_rollover(
                runtime,
                "checkpoint_advisory_reset_requested",
                generation=1,
                timestamp=now(-1),
                ready=False,
                continuation_mode="recovery_advisory",
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["rollover_not_ready_lifecycles"], 1)
            self.assertEqual(
                value["rollover_not_ready_advisories_before_terminal"], 1
            )
            self.assertEqual(value["rollover_unresolved_not_ready"], 1)
            self.assertEqual(value["rollover_failures"], 0)

    def test_cross_generation_ready_retry_does_not_hide_later_terminal(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_rollover(
                runtime,
                "checkpoint_saved",
                generation=1,
                timestamp=now(-3),
                ready=False,
                not_ready_episode_sha256="e" * 16,
            )
            append_rollover(
                runtime,
                "checkpoint_saved",
                generation=2,
                timestamp=now(-2),
                ready=True,
                not_ready_episode_sha256="e" * 16,
            )
            append_rollover(
                runtime,
                "terminal_after_not_ready",
                generation=2,
                timestamp=now(-1),
                ready=True,
                not_ready_episode_sha256="e" * 16,
            )

            value = memory.stats(runtime, selector=SESSION)

            self.assertEqual(value["rollover_checkpoints_saved"], 2)
            self.assertEqual(value["rollover_not_ready_lifecycles"], 1)
            self.assertEqual(
                value["rollover_not_ready_repairs_before_terminal"], 1
            )
            self.assertEqual(value["rollover_terminal_after_not_ready"], 1)
            self.assertEqual(value["rollover_unresolved_not_ready"], 0)
            self.assertEqual(value["rollover_failures"], 1)

    def test_unknown_event_and_malformed_reasons_never_echo_payload(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime = runtime_for(Path(temporary))
            append_rollover(
                runtime,
                "private prompt /customer/secret",
                plan_sha256="private plan text",
                reason_codes="private failure /customer/secret",
            )
            append_rollover(
                runtime,
                "precompact_blocked",
                reason_codes="private failure /customer/secret",
            )

            value = memory.stats(runtime, selector=SESSION)
            serialized = json.dumps(value, sort_keys=True)

            self.assertEqual(value["rollover_event_count"], 1)
            self.assertEqual(value["rollover_unknown_events"], 1)
            self.assertEqual(value["rollover_reason_codes"], {"unknown": 1})
            for secret in (
                "private prompt",
                "/customer/secret",
                "private plan text",
                "private failure",
            ):
                self.assertNotIn(secret, serialized)


if __name__ == "__main__":
    unittest.main()
