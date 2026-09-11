#!/usr/bin/env python3

from __future__ import annotations

import datetime as dt
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest import mock


CODEX_MEMORY_DIR = Path(__file__).resolve().parents[1]
if str(CODEX_MEMORY_DIR) not in sys.path:
    sys.path.insert(0, str(CODEX_MEMORY_DIR))

import context_rollover as rollover  # noqa: E402
import memory  # noqa: E402


UTC = dt.timezone.utc
BASE = dt.datetime(2026, 8, 23, 12, 0, tzinfo=UTC)
QUERY_ID = "a1b2c3d4e5f60718"
EVIDENCE_DIGEST = "1234567890abcdef"

PLAN = f"""# 401 - Context rollover fixture

Status: execution-ready

## Execution Progress

| Time | Phase / cursor | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-23 11:00 | Step 1 | `lib/example.dart` | setup complete | TC-01 observed | none | create RED |
| 2026-08-23 12:00 | Step 2 / TC-01 GREEN | `lib/example.dart`, `test/example_test.dart` | `./scripts/run_test_gates.sh feature-host-all` passed | TC-01 green; query_id={QUERY_ID}, evidence_digest={EVIDENCE_DIGEST} | none | Implement TC-02 preservation case |

## Test Contract

- TC-01 proves the causal change.
- TC-02 preserves the sibling behavior.

## Graph Grounding Snapshot

- query_id=ffffffffffffffff, evidence_digest=eeeeeeeeeeeeeeee

## Acceptance Gates

- `./scripts/run_test_gates.sh feature-host-all`
"""


def write(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def git(root: Path, *args: str) -> None:
    subprocess.run(
        ["git", *args],
        cwd=root,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def fixture(root: Path) -> tuple[memory.Runtime, Path]:
    plan = root / "plans" / "401-context-rollover-tdd-plan.md"
    write(plan, PLAN)
    write(root / "lib" / "example.dart", "aaaa\n")
    write(root / "test" / "example_test.dart", "test fixture\n")
    write(root / ".gitignore", "state/\n")
    git(root, "init", "-q")
    git(root, "add", ".")
    subprocess.run(
        [
            "git",
            "-c",
            "user.name=Codex Test",
            "-c",
            "user.email=codex@example.invalid",
            "commit",
            "-qm",
            "fixture",
        ],
        cwd=root,
        check=True,
    )
    state = root / "state"
    runtime = memory.Runtime(
        root=root,
        config_path=root / "config.json",
        config={},
        config_sha256="f" * 64,
        state_dir=state,
        db_path=state / "graph.db",
        manifest_path=state / "manifest.json",
        telemetry_path=state / "usage.jsonl",
        hook_events_path=state / "hook-events.jsonl",
    )
    return runtime, plan


def save_ready(
    runtime: memory.Runtime,
    plan: Path,
    *,
    now: dt.datetime = BASE,
    session: str = "root-session-raw",
) -> dict[str, object]:
    snapshot = rollover.plan_snapshot(plan, runtime)
    snapshot["task_scope_complete"] = True
    checkpoint, reasons = rollover.save_checkpoint(
        runtime,
        session_id=session,
        thread_id=session,
        snapshot=snapshot,
        outstanding_work="none",
        trigger="cli_prepare",
        now=now,
    )
    if reasons:
        raise AssertionError(reasons)
    return checkpoint


def events(runtime: memory.Runtime) -> list[dict[str, object]]:
    path = runtime.state_dir / "context-rollover-events.jsonl"
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def planless_prepare_args(
    task_scope_id: str | None,
    *paths: str,
    complete: bool = True,
    json_mode: bool = False,
) -> list[str]:
    args = [
        "prepare",
        "--plan-status",
        "not-applicable",
        "--phase-id",
        "PH-planless",
        "--next-action",
        "Continue the plan-less task",
        "--graph-status",
        "not-applicable",
        "--outstanding-work",
        "none",
    ]
    if task_scope_id is not None:
        args.extend(["--task-scope-id", task_scope_id])
    for path in paths:
        args.extend(["--changed-path", path])
    if complete:
        args.append("--task-scope-complete")
    if json_mode:
        args.append("--json")
    return args


def run_prepare_cli(
    runtime: memory.Runtime,
    args: list[str],
    *,
    session: str = "root-session",
) -> tuple[int, str]:
    output = StringIO()
    with (
        mock.patch.object(rollover, "_load_runtime", return_value=runtime),
        mock.patch.dict(
            os.environ,
            {"CODEX_SESSION_ID": session, "CODEX_THREAD_ID": session},
            clear=False,
        ),
        redirect_stdout(output),
    ):
        code = rollover.main(args)
    return code, output.getvalue()


class ContextRolloverTest(unittest.TestCase):
    def test_plan_snapshot_accepts_phase_cursor_and_single_component_tc(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            snapshot = rollover.plan_snapshot(plan, runtime)
            self.assertEqual(snapshot["plan"]["status"], "tracked")
            self.assertEqual(snapshot["phase"]["id"], "Step 2 / TC-01 GREEN")
            self.assertEqual(
                [item["id"] for item in snapshot["tests"]], ["TC-01", "TC-02"]
            )
            self.assertEqual(snapshot["gates"][0]["id"], "feature-host-all")
            self.assertEqual(snapshot["graphify"]["query_id"], QUERY_ID)
            self.assertEqual(snapshot["graphify"]["evidence_digest"], EVIDENCE_DIGEST)
            self.assertIn("lib/example.dart", snapshot["changed_paths"])
            self.assertEqual(snapshot["next_action"], "Implement TC-02 preservation case")

    def test_atomic_checkpoint_and_telemetry_are_private_and_telemetry_has_no_raw_text(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            checkpoint = save_ready(runtime, plan)
            session_hash = rollover._privacy_digest("root-session-raw")
            path = runtime.state_dir / "context-rollover" / (session_hash + ".json")
            telemetry = runtime.state_dir / "context-rollover-events.jsonl"
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(telemetry.stat().st_mode), 0o600)
            self.assertTrue(checkpoint["ready"])
            raw = telemetry.read_text(encoding="utf-8")
            for secret in (
                "root-session-raw",
                "plans/401-context-rollover-tdd-plan.md",
                "Step 2 / TC-01 GREEN",
                "Implement TC-02 preservation case",
                "run_test_gates.sh",
            ):
                self.assertNotIn(secret, raw)
            row = json.loads(raw.strip())
            self.assertEqual(row["event"], "checkpoint_saved")
            self.assertEqual(row["agent_scope"], "root")
            self.assertEqual(row["repo_scope"], "task_paths_v1")
            self.assertEqual(row["task_path_count"], 2)
            self.assertTrue(row["task_scope_complete"])
            self.assertGreater(row["checkpoint_bytes"], 0)
            self.assertGreater(row["checkpoint_tokens_estimate"], 0)
            self.assertNotIn("lib/example.dart", raw)

    def test_non_plan_checkpoint_needs_no_graph_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            snapshot = rollover._empty_snapshot()
            snapshot.update(
                {
                    "plan": {"status": "not-applicable", "relative_path": "", "sha256": ""},
                    "phase": {"id": "diagnostic-1"},
                    "graphify": {
                        "status": "not-yet-grounded",
                        "query_id": "",
                        "evidence_digest": "",
                    },
                    "next_action": "Locate the relevant code with a targeted source search",
                }
            )
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="diagnostic",
                thread_id="diagnostic",
                snapshot=snapshot,
                outstanding_work="completed",
                now=BASE,
            )
            self.assertEqual(reasons, [])
            self.assertTrue(checkpoint["ready"])

            snapshot.pop("graphify")
            _checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="missing-graph-status",
                thread_id="missing-graph-status",
                snapshot=snapshot,
                outstanding_work="none",
                now=BASE,
            )
            self.assertEqual(reasons, [])
            self.assertTrue(_checkpoint["ready"])
            self.assertNotIn("Graphify", rollover._render_context(_checkpoint))

    def test_outstanding_work_is_required_and_running_blocks_ready(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            snapshot = rollover.plan_snapshot(plan, runtime)
            _checkpoint, missing = rollover.save_checkpoint(
                runtime,
                session_id="missing",
                thread_id="missing",
                snapshot=snapshot,
                outstanding_work=None,
                now=BASE,
            )
            _checkpoint, running = rollover.save_checkpoint(
                runtime,
                session_id="running",
                thread_id="running",
                snapshot=snapshot,
                outstanding_work="running",
                now=BASE,
            )
            self.assertIn("outstanding_work_missing", missing)
            self.assertIn("outstanding_work_running", running)

    def test_precompact_and_session_start_form_a_bounded_resume_cycle(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            save_ready(runtime, plan)
            pre = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "turn_id": "raw-turn-secret",
                    "trigger": "auto",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=10),
            )
            self.assertEqual(pre, {"continue": True, "suppressOutput": True})
            post = rollover.process_hook(
                {
                    "hook_event_name": "PostCompact",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "trigger": "auto",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=11),
            )
            self.assertEqual(post, {"continue": True, "suppressOutput": True})
            resumed = rollover.process_hook(
                {
                    "hook_event_name": "SessionStart",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "source": "compact",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=12),
                context_token_limit=200,
            )
            context = resumed["hookSpecificOutput"]["additionalContext"]
            self.assertLessEqual(rollover._token_estimate(context), 200)
            self.assertIn("Step 2 / TC-01 GREEN", context)
            self.assertIn("query_id=" + QUERY_ID, context)
            self.assertIn("TC-01=observed", context)
            self.assertIn("feature-host-all=observed", context)
            self.assertIn("Implement TC-02 preservation case", context)
            names = [row["event"] for row in events(runtime)]
            self.assertIn("precompact_allowed", names)
            self.assertIn("postcompact_observed", names)
            self.assertIn("session_resumed", names)
            private = json.loads(
                (
                    runtime.state_dir
                    / "context-rollover"
                    / (rollover._privacy_digest("root-session-raw") + ".json")
                ).read_text(encoding="utf-8")
            )
            self.assertNotIn("raw-turn-secret", json.dumps(private))
            self.assertEqual(private["precompact"]["turn_sha256"], rollover._digest("raw-turn-secret"))
            self.assertEqual(private["precompact"]["mode"], "prepared_rollover")
            lifecycle = {
                row["event"]: row
                for row in events(runtime)
                if row["event"]
                in {
                    "checkpoint_saved",
                    "precompact_allowed",
                    "postcompact_observed",
                    "session_resumed",
                }
            }
            self.assertEqual(
                lifecycle["checkpoint_saved"]["continuation_mode"],
                "prepared_rollover",
            )
            for event_name in (
                "precompact_allowed",
                "postcompact_observed",
                "session_resumed",
            ):
                self.assertEqual(
                    lifecycle[event_name]["continuation_mode"],
                    "prepared_rollover",
                )
                self.assertEqual(
                    lifecycle[event_name]["precompact_turn_sha256"],
                    rollover._digest("raw-turn-secret"),
                )

    def test_bounded_capsule_labels_every_truncated_checkpoint_list(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            checkpoint = save_ready(runtime, plan)
            checkpoint["changed_paths"] = [
                f"lib/scope_{index}.dart" for index in range(20)
            ]
            checkpoint["tests"] = [
                {"id": f"TC-{index:02d}", "status": "observed"}
                for index in range(20)
            ]
            checkpoint["gates"] = [
                {"id": f"gate-{index:02d}", "status": "observed"}
                for index in range(15)
            ]
            context = rollover._render_context(checkpoint, token_limit=1_000)
            self.assertIn(
                "Changed paths (first 16 of 20; +4 remain bound in the private "
                "checkpoint and carry automatically)",
                context,
            )
            self.assertIn(
                "Test anchors (first 16 of 20; +4 remain bound in the private checkpoint)",
                context,
            )
            self.assertIn(
                "Gate anchors (first 12 of 15; +3 remain bound in the private checkpoint)",
                context,
            )
            self.assertIn("changed paths 16/20 shown (+4 private/carried)", context)
            self.assertNotIn("lib/scope_16.dart", context)
            self.assertNotIn("TC-16=observed", context)
            self.assertNotIn("gate-12=observed", context)
            self.assertLessEqual(rollover._token_estimate(context), 1_000)

    def test_control_arm_is_passive_for_root_and_subagent_hooks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            checkpoint = save_ready(runtime, plan)
            path = (
                runtime.state_dir
                / "context-rollover"
                / (checkpoint["codex_session_sha256"] + ".json")
            )
            before = path.read_bytes()
            prior_events = len(events(runtime))
            root = {
                "session_id": "root-session-raw",
                "cwd": str(runtime.root),
                "turn_id": "raw-control-turn",
                "trigger": "manual",
            }
            child = {
                **root,
                "agent_id": "raw-child-agent",
                "agent_type": "worker",
            }
            with (
                mock.patch.dict(
                    os.environ,
                    {"CODEX_TASK_RUN_ROLLOVER_ARM": "control"},
                    clear=False,
                ),
                mock.patch.object(
                    rollover,
                    "_read_checkpoint",
                    side_effect=AssertionError("control read a checkpoint"),
                ),
                mock.patch.object(
                    rollover,
                    "_validation_reasons",
                    side_effect=AssertionError("control validated a checkpoint"),
                ),
                mock.patch.object(
                    rollover,
                    "_atomic_write",
                    side_effect=AssertionError("control wrote a checkpoint"),
                ),
                mock.patch.object(
                    rollover,
                    "_session_lock",
                    side_effect=AssertionError("control locked checkpoint state"),
                ),
            ):
                for payload in (root, child):
                    pre = rollover.process_hook(
                        {**payload, "hook_event_name": "PreCompact"},
                        runtime=runtime,
                        now=BASE + dt.timedelta(seconds=10),
                    )
                    self.assertEqual(
                        pre, {"continue": True, "suppressOutput": True}
                    )
                    post = rollover.process_hook(
                        {**payload, "hook_event_name": "PostCompact"},
                        runtime=runtime,
                        now=BASE + dt.timedelta(seconds=11),
                    )
                    self.assertEqual(
                        post, {"continue": True, "suppressOutput": True}
                    )
                    resumed = rollover.process_hook(
                        {
                            **payload,
                            "hook_event_name": "SessionStart",
                            "source": "compact",
                        },
                        runtime=runtime,
                        now=BASE + dt.timedelta(seconds=12),
                    )
                    self.assertIsNone(resumed)

            self.assertEqual(path.read_bytes(), before)
            observed = events(runtime)[prior_events:]
            self.assertEqual(
                [row["event"] for row in observed],
                ["postcompact_observed", "postcompact_observed"],
            )
            self.assertEqual(
                [row["agent_scope"] for row in observed], ["root", "subagent"]
            )
            self.assertTrue(
                all(row["trigger"] == "control_postcompact_manual" for row in observed)
            )
            telemetry = json.dumps(observed)
            self.assertNotIn("root-session-raw", telemetry)
            self.assertNotIn("raw-child-agent", telemetry)
            self.assertNotIn("raw-control-turn", telemetry)

    def test_unarmed_auto_compaction_uses_locator_only_advisory_recovery(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            snapshot = rollover.plan_snapshot(plan, runtime)
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=snapshot,
                outstanding_work="none",
                trigger="cli_save",
                now=BASE,
            )
            self.assertEqual(reasons, [])
            self.assertIsNone(checkpoint["continuation_intent"])

            pre = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "turn_id": "unarmed-raw-turn",
                    "trigger": "auto",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=5),
            )
            self.assertEqual(pre, {"continue": True, "suppressOutput": True})
            self.assertEqual(events(runtime)[-1]["event"], "precompact_recovery_allowed")
            self.assertIn("rollover_intent_missing", events(runtime)[-1]["reason_codes"])

            resumed = rollover.process_hook(
                {
                    "hook_event_name": "SessionStart",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "source": "compact",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=6),
                context_token_limit=200,
            )
            context = resumed["hookSpecificOutput"]["additionalContext"]
            self.assertIn("ADVISORY", context)
            self.assertIn(
                "Plan locator only (reread required): "
                "plans/401-context-rollover-tdd-plan.md",
                context,
            )
            for stale_claim in (
                "Step 2 / TC-01 GREEN",
                "Implement TC-02 preservation case",
                "TC-01=observed",
                "feature-host-all=observed",
            ):
                self.assertNotIn(stale_claim, context)
            self.assertLessEqual(rollover._token_estimate(context), 200)
            names = [row["event"] for row in events(runtime)]
            self.assertIn("session_recovery_advisory", names)
            self.assertNotIn("session_resumed", names)
            telemetry = json.dumps(events(runtime))
            self.assertNotIn("unarmed-raw-turn", telemetry)
            self.assertNotIn(str(plan), telemetry)

    def test_advisory_filters_corrupt_reason_text_from_context_and_telemetry(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            snapshot = rollover.plan_snapshot(plan, runtime)
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=snapshot,
                outstanding_work="none",
                trigger="cli_save",
                now=BASE,
            )
            self.assertEqual(reasons, [])
            rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "turn_id": "turn",
                    "trigger": "auto",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=5),
            )
            checkpoint = rollover._read_checkpoint(
                runtime, checkpoint["codex_session_sha256"]
            )
            checkpoint["precompact"]["reason_codes"].append(
                "private prompt /customer/secret"
            )
            rollover._atomic_write(
                rollover._checkpoint_path(
                    runtime, checkpoint["codex_session_sha256"]
                ),
                checkpoint,
            )

            resumed = rollover.process_hook(
                {
                    "hook_event_name": "SessionStart",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "source": "compact",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=6),
            )
            serialized = json.dumps(events(runtime), sort_keys=True)
            context = resumed["hookSpecificOutput"]["additionalContext"]
            self.assertNotIn("private prompt", serialized)
            self.assertNotIn("/customer/secret", serialized)
            self.assertNotIn("private prompt", context)
            self.assertNotIn("/customer/secret", context)

    def test_missing_auto_precompact_is_recovery_not_interruption(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            result = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "missing-auto",
                    "cwd": str(runtime.root),
                    "turn_id": "turn",
                    "trigger": "auto",
                },
                runtime=runtime,
                now=BASE,
            )
            self.assertEqual(result, {"continue": True, "suppressOutput": True})
            row = events(runtime)[-1]
            self.assertEqual(row["event"], "precompact_recovery_allowed")
            self.assertEqual(row["continuation_mode"], "recovery_advisory")
            self.assertIn("checkpoint_missing", row["reason_codes"])

    def test_expired_or_mismatched_prepare_arm_never_gets_trusted_resume(self) -> None:
        mutations = {
            "expired": lambda intent: intent.update(
                {"armed_at": rollover._iso(BASE - dt.timedelta(minutes=11))}
            ),
            "session": lambda intent: intent.update(
                {"codex_session_sha256": "f" * 16}
            ),
            "thread": lambda intent: intent.update(
                {"codex_thread_sha256": "e" * 16}
            ),
            "generation": lambda intent: intent.update(
                {"generation": int(intent["generation"]) + 1}
            ),
            "worktree": lambda intent: intent.update(
                {"worktree_sha256": "d" * 16}
            ),
            "binding": lambda intent: intent.update(
                {"checkpoint_binding_sha256": "c" * 16}
            ),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                runtime, plan = fixture(Path(temporary))
                checkpoint = save_ready(runtime, plan)
                mutate(checkpoint["continuation_intent"])
                rollover._atomic_write(
                    rollover._checkpoint_path(
                        runtime, checkpoint["codex_session_sha256"]
                    ),
                    checkpoint,
                )
                result = rollover.process_hook(
                    {
                        "hook_event_name": "PreCompact",
                        "session_id": "root-session-raw",
                        "cwd": str(runtime.root),
                        "turn_id": "turn",
                        "trigger": "auto",
                    },
                    runtime=runtime,
                    now=BASE + dt.timedelta(seconds=5),
                )
                self.assertEqual(
                    result, {"continue": True, "suppressOutput": True}
                )
                row = events(runtime)[-1]
                self.assertEqual(row["event"], "precompact_recovery_allowed")
                self.assertTrue(
                    {"rollover_intent_stale", "rollover_intent_mismatch"}
                    & set(row["reason_codes"])
                )

    def test_prepare_uses_one_repository_snapshot_and_prints_ready(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            baseline = rollover._repo_fingerprint(runtime.root)
            calls = 0

            def fingerprint_once(
                _root: Path,
                _changed_paths: object = None,
                **_kwargs: object,
            ) -> dict[str, object]:
                nonlocal calls
                calls += 1
                if calls > 1:
                    raise AssertionError("prepare recomputed a moving worktree")
                return dict(baseline)

            output = StringIO()
            with (
                mock.patch.object(rollover, "_load_runtime", return_value=runtime),
                mock.patch.object(
                    rollover, "_repo_fingerprint", side_effect=fingerprint_once
                ),
                mock.patch.dict(
                    os.environ,
                    {
                        "CODEX_SESSION_ID": "root-session-raw",
                        "CODEX_THREAD_ID": "root-session-raw",
                    },
                    clear=False,
                ),
                redirect_stdout(output),
            ):
                code = rollover.main(
                    [
                        "prepare",
                        "--from-plan",
                        str(plan),
                        "--outstanding-work",
                        "none",
                    ]
                )
            self.assertEqual(code, 0)
            self.assertEqual(calls, 1)
            self.assertIn("READY checkpoint=", output.getvalue())

    def test_control_precompact_hook_failure_remains_fail_open(self) -> None:
        payload = json.dumps(
            {
                "hook_event_name": "PreCompact",
                "session_id": "control-session",
                "cwd": "/tmp",
                "turn_id": "turn",
            }
        )
        output = StringIO()
        with (
            mock.patch.dict(
                os.environ,
                {"CODEX_TASK_RUN_ROLLOVER_ARM": "control"},
                clear=False,
            ),
            mock.patch("sys.stdin", StringIO(payload)),
            mock.patch.object(
                rollover, "_load_runtime", side_effect=RuntimeError("boom")
            ),
            redirect_stdout(output),
        ):
            code = rollover.main(["hook-pre"])
        self.assertEqual(code, 0)
        self.assertEqual(
            json.loads(output.getvalue()),
            {"continue": True, "suppressOutput": True},
        )

    def test_missing_checkpoint_fails_precompact_closed_but_hook_returns_json(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            result = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "missing",
                    "cwd": str(runtime.root),
                    "turn_id": "turn",
                    "trigger": "manual",
                },
                runtime=runtime,
                now=BASE,
            )
            self.assertFalse(result["continue"])
            self.assertIn("checkpoint_missing", result["stopReason"])
            self.assertEqual(events(runtime)[-1]["event"], "precompact_blocked")

    def test_subagent_auto_precompact_continues_without_touching_root_checkpoint(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            checkpoint = save_ready(runtime, plan)
            path = (
                runtime.state_dir
                / "context-rollover"
                / (checkpoint["codex_session_sha256"] + ".json")
            )
            before = path.read_bytes()
            result = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "agent_id": "child-agent-raw",
                    "agent_type": "worker",
                    "turn_id": "child-turn",
                    "trigger": "auto",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=5),
            )
            self.assertTrue(result["continue"])
            self.assertEqual(path.read_bytes(), before)
            row = events(runtime)[-1]
            self.assertEqual(row["event"], "subagent_skipped")
            self.assertEqual(row["agent_scope"], "subagent")
            self.assertNotIn("child-agent-raw", json.dumps(row))

    def test_subagent_manual_precompact_remains_blocked(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            result = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "agent_id": "child-agent-raw",
                    "agent_type": "worker",
                    "turn_id": "child-turn",
                    "trigger": "manual",
                },
                runtime=runtime,
                now=BASE,
            )
            self.assertFalse(result["continue"])
            self.assertIn("Subagent context rollover is unsupported", result["stopReason"])

    def test_cli_prepare_rejects_mismatched_thread_and_session_before_writing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            output = StringIO()
            with (
                mock.patch.object(rollover, "_load_runtime", return_value=runtime),
                mock.patch.dict(
                    os.environ,
                    {"CODEX_SESSION_ID": "root-session", "CODEX_THREAD_ID": "child-thread"},
                    clear=False,
                ),
                redirect_stdout(output),
            ):
                code = rollover.main(
                    [
                        "prepare",
                        "--from-plan",
                        str(plan),
                        "--outstanding-work",
                        "none",
                    ]
                )
            self.assertEqual(code, 2)
            self.assertIn("subagent_rollover_unsupported", output.getvalue())
            checkpoint_dir = runtime.state_dir / "context-rollover"
            self.assertEqual(list(checkpoint_dir.glob("*.json")), [])

    def test_cli_subagent_cannot_spoof_root_with_explicit_thread_selector(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            output = StringIO()
            with (
                mock.patch.object(rollover, "_load_runtime", return_value=runtime),
                mock.patch.dict(
                    os.environ,
                    {"CODEX_SESSION_ID": "root-session", "CODEX_THREAD_ID": "child-thread"},
                    clear=False,
                ),
                redirect_stdout(output),
            ):
                code = rollover.main(
                    [
                        "prepare",
                        "--session",
                        "root-session",
                        "--thread",
                        "root-session",
                        "--from-plan",
                        str(plan),
                        "--outstanding-work",
                        "none",
                    ]
                )
            self.assertEqual(code, 2)
            self.assertIn("subagent_rollover_unsupported", output.getvalue())
            self.assertEqual(
                list((runtime.state_dir / "context-rollover").glob("*.json")), []
            )

    def test_cli_prepare_ready_prints_exact_new_context_guidance(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            output = StringIO()
            with (
                mock.patch.object(rollover, "_load_runtime", return_value=runtime),
                mock.patch.dict(
                    os.environ,
                    {"CODEX_SESSION_ID": "root-session", "CODEX_THREAD_ID": "root-session"},
                    clear=False,
                ),
                redirect_stdout(output),
            ):
                code = rollover.main(
                    [
                        "prepare",
                        "--from-plan",
                        str(plan),
                        "--outstanding-work",
                        "none",
                    ]
                )
            self.assertEqual(code, 0)
            self.assertIn("READY checkpoint=", output.getvalue())
            self.assertIn("call `functions.new_context` now", output.getvalue())

    def test_cli_prepare_fingerprint_unavailable_is_not_ready(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            (runtime.root / "large-unrelated.bin").write_bytes(b"x" * 2048)
            with mock.patch.object(rollover, "MAX_LEGACY_DIRTY_BYTES", 1024):
                code, output = run_prepare_cli(
                    runtime,
                    [
                        "prepare",
                        "--from-plan",
                        str(plan),
                        "--outstanding-work",
                        "none",
                    ],
                )

            self.assertEqual(code, 2)
            self.assertIn(
                "NOT_READY reason_codes=repo_fingerprint_unavailable", output
            )
            self.assertIn(
                "repo_fingerprint_failure=legacy_dirty_content_byte_limit",
                output,
            )
            self.assertIn("DO NOT call `functions.new_context`", output)
            self.assertNotIn("READY checkpoint=", output)
            checkpoint = rollover._read_checkpoint(
                runtime, rollover._privacy_digest("root-session")
            )
            self.assertFalse(checkpoint["ready"])
            self.assertIn(
                "repo_fingerprint_unavailable",
                checkpoint["validation_reason_codes"],
            )
            public = rollover._safe_public_status(
                checkpoint,
                runtime,
                now=rollover._utc_now(),
                compare_repo=False,
            )
            self.assertEqual(
                public["repo_fingerprint_failure"],
                "legacy_dirty_content_byte_limit",
            )

    def test_cli_prepare_fingerprint_unavailable_json_is_untrusted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            (runtime.root / "large-unrelated.bin").write_bytes(b"x" * 2048)
            with mock.patch.object(rollover, "MAX_LEGACY_DIRTY_BYTES", 1024):
                code, output = run_prepare_cli(
                    runtime,
                    [
                        "prepare",
                        "--from-plan",
                        str(plan),
                        "--outstanding-work",
                        "none",
                        "--json",
                    ],
                )

            self.assertEqual(code, 2)
            result = json.loads(output)
            self.assertIs(result["ready"], False)
            self.assertIn(
                "repo_fingerprint_unavailable", result["reason_codes"]
            )
            self.assertEqual(
                result["repo_fingerprint_failure"],
                "legacy_dirty_content_byte_limit",
            )
            self.assertEqual(
                result["repo_fingerprint_failure_stage"], "dirty_path_content"
            )
            self.assertEqual(result["repo_fingerprint_failure_limit"], 1024)
            self.assertEqual(result["repo_fingerprint_failure_observed"], 2048)
            self.assertNotEqual(result.get("status"), "ADVISORY_RESET")
            self.assertNotIn("advisory_reset_permitted", result)

    def test_advisory_fingerprint_failure_remains_untrusted_through_resume(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            (runtime.root / "large-unrelated.bin").write_bytes(b"x" * 2048)
            session = "root-session"
            lifecycle_now = rollover._utc_now()
            with mock.patch.object(rollover, "MAX_LEGACY_DIRTY_BYTES", 1024):
                code, output = run_prepare_cli(
                    runtime,
                    [
                        "prepare",
                        "--from-plan",
                        str(plan),
                        "--outstanding-work",
                        "none",
                        "--advisory-reset-on-not-ready",
                        "--json",
                    ],
                    session=session,
                )
                result = json.loads(output)
                self.assertEqual(code, 0)
                self.assertEqual(result["status"], "ADVISORY_RESET")
                self.assertIs(result["ready"], False)
                self.assertEqual(
                    result["repo_fingerprint_failure"],
                    "legacy_dirty_content_byte_limit",
                )
                self.assertIn(
                    "repo_fingerprint_unavailable", result["reason_codes"]
                )

                checkpoint = rollover._read_checkpoint(
                    runtime, rollover._privacy_digest(session)
                )
                self.assertFalse(checkpoint["ready"])
                self.assertEqual(checkpoint["advisory_reset"]["status"], "pending")

                precompact = rollover.process_hook(
                    {
                        "hook_event_name": "PreCompact",
                        "session_id": session,
                        "cwd": str(runtime.root),
                        "turn_id": "fingerprint-failure-turn",
                        "trigger": "auto",
                    },
                    runtime=runtime,
                    now=lifecycle_now,
                )
                self.assertEqual(
                    precompact, {"continue": True, "suppressOutput": True}
                )
                resumed = rollover.process_hook(
                    {
                        "hook_event_name": "SessionStart",
                        "session_id": session,
                        "cwd": str(runtime.root),
                        "source": "compact",
                    },
                    runtime=runtime,
                    now=lifecycle_now + dt.timedelta(seconds=1),
                )

            context = resumed["hookSpecificOutput"]["additionalContext"]
            self.assertIn("ADVISORY", context)
            self.assertIn("repo_fingerprint_unavailable", context)
            self.assertIn("legacy_dirty_content_byte_limit", context)
            self.assertNotIn(
                "Validated prepared context-rollover checkpoint", context
            )
            checkpoint = rollover._read_checkpoint(
                runtime, rollover._privacy_digest(session)
            )
            self.assertFalse(checkpoint["ready"])
            self.assertEqual(checkpoint["advisory_reset"]["status"], "consumed")
            names = [row["event"] for row in events(runtime)]
            self.assertIn("session_recovery_advisory", names)
            self.assertNotIn("session_resumed", names)

    def test_cli_advisory_reset_runs_untrusted_recovery_lifecycle(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            outside = runtime.root.parent / "private-outside-secret.dart"
            output = StringIO()
            environment = {
                "CODEX_SESSION_ID": "root-session",
                "CODEX_THREAD_ID": "root-session",
            }
            with (
                mock.patch.object(rollover, "_load_runtime", return_value=runtime),
                mock.patch.dict(os.environ, environment, clear=False),
                redirect_stdout(output),
            ):
                code = rollover.main(
                    [
                        "prepare",
                        "--from-plan",
                        str(plan),
                        "--outstanding-work",
                        "none",
                        "--changed-path",
                        str(outside),
                        "--task-scope-complete",
                        "--advisory-reset-on-not-ready",
                    ]
                )

            self.assertEqual(code, 0)
            self.assertIn("ADVISORY_RESET checkpoint=", output.getvalue())
            self.assertIn("changed_path_outside_repo", output.getvalue())
            self.assertIn("call `functions.new_context` now", output.getvalue())
            session_hash = rollover._privacy_digest("root-session")
            checkpoint = rollover._read_checkpoint(runtime, session_hash)
            self.assertFalse(checkpoint["ready"])
            self.assertIn(
                "changed_path_outside_repo",
                checkpoint["validation_reason_codes"],
            )
            self.assertEqual(
                events(runtime)[-1]["event"],
                "checkpoint_advisory_reset_requested",
            )

            lifecycle_now = rollover._utc_now()
            stop_output = StringIO()
            with (
                mock.patch.object(rollover, "_load_runtime", return_value=runtime),
                mock.patch(
                    "sys.stdin",
                    StringIO(
                        json.dumps(
                            {
                                "session_id": "root-session",
                                "cwd": str(runtime.root),
                            }
                        )
                    ),
                ),
                redirect_stdout(stop_output),
            ):
                stop_code = rollover.main(["hook-stop"])
            self.assertEqual(stop_code, 0)
            stop_result = json.loads(stop_output.getvalue())
            self.assertFalse(stop_result["continue"])
            self.assertIn("functions.new_context", stop_result["systemMessage"])
            self.assertEqual(
                events(runtime)[-1]["event"], "terminal_after_not_ready_blocked"
            )

            precompact = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "root-session",
                    "cwd": str(runtime.root),
                    "turn_id": "hard-exhaustion-turn",
                    "trigger": "auto",
                },
                runtime=runtime,
                now=lifecycle_now,
            )
            self.assertEqual(
                precompact, {"continue": True, "suppressOutput": True}
            )
            checkpoint = rollover._read_checkpoint(runtime, session_hash)
            self.assertFalse(checkpoint["ready"])
            self.assertEqual(checkpoint["precompact"]["mode"], "recovery_advisory")
            self.assertEqual(checkpoint["advisory_reset"]["status"], "consumed")
            self.assertEqual(
                checkpoint["not_ready_liveness"]["status"], "transitioned"
            )
            stop_after_precompact = rollover.process_hook(
                {
                    "hook_event_name": "Stop",
                    "session_id": "root-session",
                    "cwd": str(runtime.root),
                },
                runtime=runtime,
                now=lifecycle_now + dt.timedelta(milliseconds=500),
            )
            self.assertEqual(
                stop_after_precompact,
                {"continue": True, "suppressOutput": True},
            )

            postcompact = rollover.process_hook(
                {
                    "hook_event_name": "PostCompact",
                    "session_id": "root-session",
                    "cwd": str(runtime.root),
                    "turn_id": "hard-exhaustion-turn",
                    "trigger": "auto",
                },
                runtime=runtime,
                now=lifecycle_now + dt.timedelta(seconds=1),
            )
            self.assertEqual(
                postcompact, {"continue": True, "suppressOutput": True}
            )
            resumed = rollover.process_hook(
                {
                    "hook_event_name": "SessionStart",
                    "session_id": "root-session",
                    "cwd": str(runtime.root),
                    "source": "compact",
                },
                runtime=runtime,
                now=lifecycle_now + dt.timedelta(seconds=2),
            )
            context = resumed["hookSpecificOutput"]["additionalContext"]
            self.assertIn("ADVISORY", context)
            self.assertNotIn("Validated prepared context-rollover checkpoint", context)
            final_checkpoint = rollover._read_checkpoint(runtime, session_hash)
            self.assertFalse(final_checkpoint["ready"])
            names = [row["event"] for row in events(runtime)]
            self.assertIn("precompact_recovery_allowed", names)
            self.assertIn("postcompact_observed", names)
            self.assertIn("session_recovery_advisory", names)
            self.assertNotIn("session_resumed", names)
            self.assertNotIn("terminal_after_not_ready", names)

    def test_telemetry_failure_cannot_block_advisory_prepare_or_stop_deny(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            outside = runtime.root.parent / "private-outside-secret.dart"
            environment = {
                "CODEX_SESSION_ID": "root-session",
                "CODEX_THREAD_ID": "root-session",
            }
            prepare_output = StringIO()
            with (
                mock.patch.object(rollover, "_load_runtime", return_value=runtime),
                mock.patch.object(
                    rollover,
                    "_append_event_unchecked",
                    side_effect=OSError("telemetry unavailable"),
                ),
                mock.patch.dict(os.environ, environment, clear=False),
                redirect_stdout(prepare_output),
            ):
                prepare_code = rollover.main(
                    [
                        "prepare",
                        "--from-plan",
                        str(plan),
                        "--outstanding-work",
                        "none",
                        "--changed-path",
                        str(outside),
                        "--task-scope-complete",
                        "--advisory-reset-on-not-ready",
                    ]
                )

            self.assertEqual(prepare_code, 0)
            self.assertIn("ADVISORY_RESET checkpoint=", prepare_output.getvalue())
            session_hash = rollover._privacy_digest("root-session")
            checkpoint = rollover._read_checkpoint(runtime, session_hash)
            self.assertFalse(checkpoint["ready"])
            self.assertEqual(checkpoint["advisory_reset"]["status"], "pending")
            self.assertEqual(events(runtime), [])

            stop_output = StringIO()
            with (
                mock.patch.object(rollover, "_load_runtime", return_value=runtime),
                mock.patch.object(
                    rollover,
                    "_append_event_unchecked",
                    side_effect=OSError("telemetry unavailable"),
                ),
                mock.patch(
                    "sys.stdin",
                    StringIO(
                        json.dumps(
                            {
                                "session_id": "root-session",
                                "cwd": str(runtime.root),
                            }
                        )
                    ),
                ),
                redirect_stdout(stop_output),
            ):
                stop_code = rollover.main(["hook-stop"])

            self.assertEqual(stop_code, 0)
            stop_result = json.loads(stop_output.getvalue())
            self.assertFalse(stop_result["continue"])
            self.assertIn("functions.new_context", stop_result["systemMessage"])
            self.assertEqual(events(runtime), [])

    def test_ready_retry_keeps_not_ready_episode_open_until_precompact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            first_snapshot = rollover.plan_snapshot(plan, runtime)
            first_snapshot["next_action"] = ""
            first_snapshot["task_scope_complete"] = True
            first, first_reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=first_snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE,
            )
            self.assertIn("next_action_missing", first_reasons)
            episode = first["not_ready_liveness"]["episode_sha256"]
            self.assertEqual(first["not_ready_liveness"]["status"], "pending")

            second_snapshot = rollover.plan_snapshot(plan, runtime)
            second_snapshot["task_scope_complete"] = True
            second, second_reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=second_snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE + dt.timedelta(seconds=1),
            )
            self.assertEqual(second_reasons, [])
            self.assertTrue(second["ready"])
            self.assertEqual(second["not_ready_liveness"]["status"], "pending")
            self.assertEqual(second["not_ready_liveness"]["episode_sha256"], episode)

            stopped = rollover.process_hook(
                {
                    "hook_event_name": "Stop",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=2),
            )
            self.assertEqual(stopped, {"continue": True, "suppressOutput": True})
            row = events(runtime)[-1]
            self.assertEqual(row["event"], "terminal_after_not_ready")
            self.assertEqual(row["not_ready_episode_sha256"], episode)
            checkpoint = rollover._read_checkpoint(
                runtime, rollover._privacy_digest("root-session-raw")
            )
            self.assertEqual(checkpoint["not_ready_liveness"]["status"], "terminal")

    def test_precompact_or_completion_preserves_not_ready_terminal_boundary(self) -> None:
        for resolution in ("precompact", "completed"):
            with self.subTest(resolution=resolution), tempfile.TemporaryDirectory() as temporary:
                runtime, plan = fixture(Path(temporary))
                first_snapshot = rollover.plan_snapshot(plan, runtime)
                first_snapshot["next_action"] = ""
                first_snapshot["task_scope_complete"] = True
                first, first_reasons = rollover.save_checkpoint(
                    runtime,
                    session_id="root-session-raw",
                    thread_id="root-session-raw",
                    snapshot=first_snapshot,
                    outstanding_work="none",
                    trigger="cli_prepare",
                    now=BASE,
                )
                self.assertIn("next_action_missing", first_reasons)
                episode = first["not_ready_liveness"]["episode_sha256"]

                if resolution == "precompact":
                    second_snapshot = rollover.plan_snapshot(plan, runtime)
                    second_snapshot["task_scope_complete"] = True
                    second, second_reasons = rollover.save_checkpoint(
                        runtime,
                        session_id="root-session-raw",
                        thread_id="root-session-raw",
                        snapshot=second_snapshot,
                        outstanding_work="none",
                        trigger="cli_prepare",
                        now=BASE + dt.timedelta(seconds=1),
                    )
                    self.assertEqual(second_reasons, [])
                    self.assertEqual(
                        second["not_ready_liveness"]["episode_sha256"], episode
                    )
                    result = rollover.process_hook(
                        {
                            "hook_event_name": "PreCompact",
                            "session_id": "root-session-raw",
                            "cwd": str(runtime.root),
                            "turn_id": "ready-retry-turn",
                            "trigger": "auto",
                        },
                        runtime=runtime,
                        now=BASE + dt.timedelta(seconds=2),
                    )
                    self.assertEqual(
                        result, {"continue": True, "suppressOutput": True}
                    )
                    expected_status = "transitioned"
                else:
                    self.assertTrue(
                        rollover.complete_checkpoint(
                            runtime,
                            session_id="root-session-raw",
                            thread_id="root-session-raw",
                            now=BASE + dt.timedelta(seconds=1),
                        )
                    )
                    expected_status = "pending"

                checkpoint = rollover._read_checkpoint(
                    runtime, rollover._privacy_digest("root-session-raw")
                )
                self.assertEqual(
                    checkpoint["not_ready_liveness"]["status"], expected_status
                )
                event_count = len(events(runtime))
                stopped = rollover.process_hook(
                    {
                        "hook_event_name": "Stop",
                        "session_id": "root-session-raw",
                        "cwd": str(runtime.root),
                    },
                    runtime=runtime,
                    now=BASE + dt.timedelta(seconds=3),
                )
                self.assertEqual(
                    stopped, {"continue": True, "suppressOutput": True}
                )
                if resolution == "precompact":
                    self.assertEqual(len(events(runtime)), event_count)
                    self.assertNotIn(
                        "terminal_after_not_ready",
                        [row["event"] for row in events(runtime)],
                    )
                else:
                    self.assertEqual(len(events(runtime)), event_count + 1)
                    self.assertEqual(
                        events(runtime)[-1]["event"], "terminal_after_not_ready"
                    )
                    checkpoint = rollover._read_checkpoint(
                        runtime, rollover._privacy_digest("root-session-raw")
                    )
                    self.assertEqual(
                        checkpoint["not_ready_liveness"]["status"], "terminal"
                    )

    def test_cli_changed_paths_are_repo_relative_or_rejected_without_storage(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            outside = runtime.root.parent / "private-outside-secret.dart"
            environment = {
                "CODEX_SESSION_ID": "root-session",
                "CODEX_THREAD_ID": "root-session",
            }
            output = StringIO()
            with (
                mock.patch.object(rollover, "_load_runtime", return_value=runtime),
                mock.patch.dict(os.environ, environment, clear=False),
                redirect_stdout(output),
            ):
                code = rollover.main(
                    [
                        "prepare",
                        "--from-plan",
                        str(plan),
                        "--outstanding-work",
                        "none",
                        "--changed-path",
                        str(outside),
                    ]
                )
            self.assertEqual(code, 2)
            self.assertIn("changed_path_outside_repo", output.getvalue())
            session_hash = rollover._privacy_digest("root-session")
            checkpoint = rollover._read_checkpoint(runtime, session_hash)
            self.assertNotIn(str(outside), json.dumps(checkpoint))
            self.assertIsNone(checkpoint["advisory_reset"])
            ordinary_stop = rollover.process_hook(
                {
                    "hook_event_name": "Stop",
                    "session_id": "root-session",
                    "cwd": str(runtime.root),
                },
                runtime=runtime,
                now=rollover._utc_now(),
            )
            self.assertEqual(
                ordinary_stop, {"continue": True, "suppressOutput": True}
            )
            self.assertEqual(events(runtime)[-1]["event"], "terminal_after_not_ready")

            inside = runtime.root / "lib" / "new_file.dart"
            output = StringIO()
            with (
                mock.patch.object(rollover, "_load_runtime", return_value=runtime),
                mock.patch.dict(os.environ, environment, clear=False),
                redirect_stdout(output),
            ):
                code = rollover.main(
                    [
                        "prepare",
                        "--from-plan",
                        str(plan),
                        "--outstanding-work",
                        "none",
                        "--changed-path",
                        str(inside),
                    ]
                )
            self.assertEqual(code, 0)
            checkpoint = rollover._read_checkpoint(runtime, session_hash)
            self.assertIn("lib/new_file.dart", checkpoint["changed_paths"])
            self.assertNotIn(str(runtime.root), json.dumps(checkpoint["changed_paths"]))

    def test_named_plan_extraction_failure_is_persistently_not_ready(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            output = StringIO()
            environment = {
                "CODEX_SESSION_ID": "root-session",
                "CODEX_THREAD_ID": "root-session",
            }
            with (
                mock.patch.object(rollover, "_load_runtime", return_value=runtime),
                mock.patch.dict(os.environ, environment, clear=False),
                redirect_stdout(output),
            ):
                code = rollover.main(
                    [
                        "prepare",
                        "--from-plan",
                        str(runtime.root / "plans" / "missing-plan.md"),
                        "--plan-status",
                        "not-applicable",
                        "--phase-id",
                        "override-phase",
                        "--next-action",
                        "continue",
                        "--graph-status",
                        "not-applicable",
                        "--outstanding-work",
                        "none",
                        "--changed-path",
                        "lib/example.dart",
                        "--task-scope-complete",
                    ]
                )
            self.assertEqual(code, 2)
            self.assertIn("plan_missing", output.getvalue())
            session_hash = rollover._privacy_digest("root-session")
            checkpoint = rollover._read_checkpoint(runtime, session_hash)
            self.assertFalse(checkpoint["ready"])
            self.assertIn("plan_missing", checkpoint["validation_reason_codes"])
            self.assertIn(
                "plan_missing",
                rollover._validation_reasons(
                    checkpoint,
                    runtime,
                    now=rollover._utc_now(),
                    require_fresh_generation=True,
                    compare_repo=False,
                ),
            )
            row = events(runtime)[-1]
            self.assertEqual(row["event"], "checkpoint_saved")
            self.assertFalse(row["ready"])
            self.assertIn("plan_missing", row["reason_codes"])

    def test_content_aware_worktree_change_uses_automatic_recovery(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            source = runtime.root / "lib" / "example.dart"
            write(source, "bbbb\n")
            saved_mtime = source.stat().st_mtime_ns
            save_ready(runtime, plan)
            write(source, "cccc\n")
            os.utime(source, ns=(saved_mtime, saved_mtime))
            result = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "turn_id": "turn",
                    "trigger": "auto",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=5),
            )
            self.assertEqual(result, {"continue": True, "suppressOutput": True})
            row = events(runtime)[-1]
            self.assertEqual(row["event"], "precompact_recovery_allowed")
            self.assertIn("task_scope_changed", row["reason_codes"])
            self.assertEqual(row["continuation_mode"], "recovery_advisory")

    def test_plan_scope_unions_all_progress_rows_and_accepts_root_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            write(runtime.root / "pubspec.yaml", "name: fixture\n")
            write(
                plan,
                PLAN.replace(
                    "| 2026-08-23 11:00 | Step 1 | `lib/example.dart` |",
                    "| 2026-08-23 11:00 | Step 1 | `pubspec.yaml` |",
                ),
            )
            snapshot = rollover.plan_snapshot(plan, runtime)
            snapshot["task_scope_complete"] = True
            self.assertEqual(
                snapshot["changed_paths"],
                ["pubspec.yaml", "lib/example.dart", "test/example_test.dart"],
            )
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE,
            )
            self.assertEqual(reasons, [])
            self.assertEqual(checkpoint["repo"]["validation_scope"], "task_paths_v1")
            self.assertEqual(checkpoint["repo"]["task_path_count"], 3)

    def test_unrelated_shared_worktree_edits_do_not_stale_task_scope(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            checkpoint = save_ready(runtime, plan)
            write(runtime.root / "shared" / "unrelated.dart", "other agent\n")
            write(runtime.root / ".gitignore", "state/\nother-state/\n")
            reasons = rollover._validation_reasons(
                checkpoint,
                runtime,
                now=BASE + dt.timedelta(seconds=5),
                require_fresh_generation=True,
            )
            self.assertNotIn("task_scope_changed", reasons)
            self.assertNotIn("worktree_changed", reasons)
            result = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "turn_id": "turn",
                    "trigger": "auto",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=5),
            )
            self.assertEqual(result, {"continue": True, "suppressOutput": True})
            self.assertEqual(events(runtime)[-1]["event"], "precompact_allowed")

    def test_plan_paths_without_completeness_assertion_use_global_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            omitted = runtime.root / "lib" / "omitted_task_file.dart"
            write(omitted, "baseline\n")
            git(runtime.root, "add", "lib/omitted_task_file.dart")
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=Codex Test",
                    "-c",
                    "user.email=codex@example.invalid",
                    "commit",
                    "-qm",
                    "add omitted fixture",
                ],
                cwd=runtime.root,
                check=True,
            )
            snapshot = rollover.plan_snapshot(plan, runtime)
            self.assertFalse(snapshot["task_scope_complete"])
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE,
            )
            self.assertEqual(reasons, [])
            self.assertEqual(checkpoint["repo"]["validation_scope"], "legacy_worktree_v1")
            write(omitted, "changed but absent from plan Files\n")
            self.assertIn(
                "worktree_changed",
                rollover._validation_reasons(
                    checkpoint,
                    runtime,
                    now=BASE + dt.timedelta(seconds=5),
                    require_fresh_generation=True,
                ),
            )

    def test_scoped_staged_deleted_and_executable_changes_are_detected(self) -> None:
        for change in ("staged", "deleted", "executable"):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary:
                runtime, plan = fixture(Path(temporary))
                checkpoint = save_ready(runtime, plan)
                source = runtime.root / "lib" / "example.dart"
                if change == "staged":
                    write(source, "staged change\n")
                    git(runtime.root, "add", "lib/example.dart")
                elif change == "deleted":
                    source.unlink()
                else:
                    source.chmod(source.stat().st_mode | stat.S_IXUSR)
                reasons = rollover._validation_reasons(
                    checkpoint,
                    runtime,
                    now=BASE + dt.timedelta(seconds=5),
                    require_fresh_generation=True,
                )
                self.assertIn("task_scope_changed", reasons)

    def test_skip_worktree_index_flag_change_is_detected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            checkpoint = save_ready(runtime, plan)
            git(runtime.root, "update-index", "--skip-worktree", "lib/example.dart")
            reasons = rollover._validation_reasons(
                checkpoint,
                runtime,
                now=BASE + dt.timedelta(seconds=5),
                require_fresh_generation=True,
            )
            self.assertIn("task_scope_changed", reasons)

    def test_intent_to_add_transition_to_staged_empty_is_detected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            new_file = runtime.root / "lib" / "empty.dart"
            new_file.write_bytes(b"")
            git(runtime.root, "add", "-N", "lib/empty.dart")
            snapshot = rollover.plan_snapshot(plan, runtime)
            snapshot["changed_paths"].append("lib/empty.dart")
            snapshot["explicit_changed_paths"].append("lib/empty.dart")
            snapshot["task_scope_complete"] = True
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE,
            )
            self.assertEqual(reasons, [])
            git(runtime.root, "add", "lib/empty.dart")
            self.assertIn(
                "task_scope_changed",
                rollover._validation_reasons(
                    checkpoint,
                    runtime,
                    now=BASE + dt.timedelta(seconds=5),
                    require_fresh_generation=True,
                ),
            )

    def test_explicit_missing_path_creation_is_detected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            snapshot = rollover.plan_snapshot(plan, runtime)
            snapshot["changed_paths"].append("lib/new_file.dart")
            snapshot["explicit_changed_paths"].append("lib/new_file.dart")
            snapshot["task_scope_complete"] = True
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE,
            )
            self.assertEqual(reasons, [])
            write(runtime.root / "lib" / "new_file.dart", "created\n")
            self.assertIn(
                "task_scope_changed",
                rollover._validation_reasons(
                    checkpoint,
                    runtime,
                    now=BASE + dt.timedelta(seconds=5),
                    require_fresh_generation=True,
                ),
            )

    def test_scoped_regular_file_hashes_all_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            source = runtime.root / "lib" / "example.dart"
            source.write_bytes(b"a" * (3 * 1024 * 1024))
            saved_mtime = source.stat().st_mtime_ns
            checkpoint = save_ready(runtime, plan)
            changed = bytearray(b"a" * (3 * 1024 * 1024))
            changed[len(changed) // 2] = ord("b")
            source.write_bytes(changed)
            os.utime(source, ns=(saved_mtime, saved_mtime))
            self.assertIn(
                "task_scope_changed",
                rollover._validation_reasons(
                    checkpoint,
                    runtime,
                    now=BASE + dt.timedelta(seconds=5),
                    require_fresh_generation=True,
                ),
            )

    def test_leaf_symlink_target_is_hashed_without_reading_external_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            runtime, plan = fixture(base / "repo")
            outside_a = base / "outside-a"
            outside_b = base / "outside-b"
            write(outside_a, "secret-a\n")
            write(outside_b, "secret-b\n")
            link = runtime.root / "lib" / "external.dart"
            link.symlink_to(outside_a)
            snapshot = rollover.plan_snapshot(plan, runtime)
            snapshot["changed_paths"].append("lib/external.dart")
            snapshot["explicit_changed_paths"].append("lib/external.dart")
            snapshot["task_scope_complete"] = True
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE,
            )
            self.assertEqual(reasons, [])
            write(outside_a, "external content may change without being read\n")
            unchanged = rollover._validation_reasons(
                checkpoint,
                runtime,
                now=BASE + dt.timedelta(seconds=5),
                require_fresh_generation=True,
            )
            self.assertNotIn("task_scope_changed", unchanged)
            link.unlink()
            link.symlink_to(outside_b)
            self.assertIn(
                "task_scope_changed",
                rollover._validation_reasons(
                    checkpoint,
                    runtime,
                    now=BASE + dt.timedelta(seconds=6),
                    require_fresh_generation=True,
                ),
            )

    def test_intermediate_symlink_alias_is_rejected_before_it_can_be_retargeted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            runtime, plan = fixture(base / "repo")
            target_a = runtime.root / "target-a"
            target_b = runtime.root / "target-b"
            write(target_a / "scoped.dart", "a\n")
            write(target_b / "scoped.dart", "b\n")
            alias = runtime.root / "alias"
            alias.symlink_to(target_a, target_is_directory=True)
            snapshot = rollover.plan_snapshot(plan, runtime)
            snapshot["changed_paths"].append("alias/scoped.dart")
            snapshot["explicit_changed_paths"].append("alias/scoped.dart")
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE,
            )
            self.assertFalse(checkpoint["ready"])
            self.assertIn("changed_path_outside_repo", reasons)
            self.assertNotIn("alias/scoped.dart", checkpoint["changed_paths"])
            alias.unlink()
            alias.symlink_to(target_b, target_is_directory=True)
            self.assertIn(
                "changed_path_outside_repo",
                rollover._validation_reasons(
                    checkpoint,
                    runtime,
                    now=BASE + dt.timedelta(seconds=5),
                    require_fresh_generation=True,
                ),
            )

            outside = base / "outside"
            write(outside / "scoped.dart", "outside\n")
            outside_alias = runtime.root / "outside-alias"
            outside_alias.symlink_to(outside, target_is_directory=True)
            normalized, invalid, truncated = rollover._normalize_changed_paths(
                ["outside-alias/scoped.dart"], runtime.root
            )
            self.assertEqual(normalized, [])
            self.assertTrue(invalid)
            self.assertFalse(truncated)

    def test_head_change_stales_even_when_scoped_leaves_are_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            checkpoint = save_ready(runtime, plan)
            write(runtime.root / "shared.txt", "unrelated commit\n")
            git(runtime.root, "add", "shared.txt")
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=Codex Test",
                    "-c",
                    "user.email=codex@example.invalid",
                    "commit",
                    "-qm",
                    "unrelated head move",
                ],
                cwd=runtime.root,
                check=True,
            )
            reasons = rollover._validation_reasons(
                checkpoint,
                runtime,
                now=BASE + dt.timedelta(seconds=5),
                require_fresh_generation=True,
            )
            self.assertIn("repo_head_changed", reasons)

    def test_legacy_checkpoint_retains_whole_worktree_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            checkpoint = save_ready(runtime, plan)
            checkpoint["repo"] = rollover._legacy_repo_fingerprint(runtime.root)
            self.assertNotIn(
                "worktree_changed",
                rollover._validation_reasons(
                    checkpoint,
                    runtime,
                    now=BASE + dt.timedelta(seconds=5),
                    require_fresh_generation=True,
                ),
            )
            write(runtime.root / "shared" / "old-checkpoint-sees-this.txt", "dirty\n")
            reasons = rollover._validation_reasons(
                checkpoint,
                runtime,
                now=BASE + dt.timedelta(seconds=6),
                require_fresh_generation=True,
            )
            self.assertIn("worktree_changed", reasons)
            self.assertNotIn("task_scope_changed", reasons)

    def test_legacy_fallback_hashes_middle_bytes_exactly(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            source = runtime.root / "lib" / "example.dart"
            source.write_bytes(b"a" * (3 * 1024 * 1024))
            saved_mtime = source.stat().st_mtime_ns
            baseline = rollover._legacy_repo_fingerprint(runtime.root)
            self.assertTrue(baseline["available"])
            changed = bytearray(b"a" * (3 * 1024 * 1024))
            changed[len(changed) // 2] = ord("b")
            source.write_bytes(changed)
            os.utime(source, ns=(saved_mtime, saved_mtime))
            current = rollover._legacy_repo_fingerprint(runtime.root)
            self.assertTrue(current["available"])
            self.assertNotEqual(
                baseline["worktree_sha256"], current["worktree_sha256"]
            )

    def test_legacy_fallback_over_byte_cap_is_unavailable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            source = runtime.root / "lib" / "example.dart"
            source.write_bytes(b"x" * 2048)
            with mock.patch.object(rollover, "MAX_LEGACY_DIRTY_BYTES", 1024):
                fingerprint = rollover._legacy_repo_fingerprint(runtime.root)
            self.assertFalse(fingerprint["available"])

    def test_unstable_scoped_read_is_not_ready(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            snapshot = rollover.plan_snapshot(plan, runtime)
            snapshot["task_scope_complete"] = True
            with mock.patch.object(
                rollover, "_scoped_worktree_state", return_value=None
            ):
                checkpoint, reasons = rollover.save_checkpoint(
                    runtime,
                    session_id="root-session-raw",
                    thread_id="root-session-raw",
                    snapshot=snapshot,
                    outstanding_work="none",
                    trigger="cli_prepare",
                    now=BASE,
                )
            self.assertFalse(checkpoint["ready"])
            self.assertIn("repo_fingerprint_unavailable", reasons)

    def test_task_scope_fingerprint_is_byte_and_time_bounded(self) -> None:
        # .codex/hooks.json registers PreCompact with a 15-second timeout.
        self.assertLessEqual(rollover.MAX_TASK_CAPTURE_SECONDS, 10.0)
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            source = runtime.root / "lib" / "example.dart"
            source.write_bytes(b"x" * 2048)
            with mock.patch.object(rollover, "MAX_TASK_SCOPE_BYTES", 1024):
                over_bytes = rollover._task_scope_fingerprint(
                    runtime.root, ["lib/example.dart"]
                )
            self.assertFalse(over_bytes["available"])

            with mock.patch.object(rollover, "MAX_TASK_CAPTURE_SECONDS", 0.0):
                out_of_time = rollover._task_scope_fingerprint(
                    runtime.root, ["lib/example.dart"]
                )
            self.assertFalse(out_of_time["available"])

    def test_changed_path_overflow_is_never_a_trusted_partial_scope(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            snapshot = rollover.plan_snapshot(plan, runtime)
            paths = [
                f"lib/generated_{index}.dart"
                for index in range(rollover.MAX_TASK_PATHS + 1)
            ]
            snapshot["changed_paths"] = paths
            snapshot["explicit_changed_paths"] = paths
            snapshot["task_scope_complete"] = True
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE,
            )
            self.assertFalse(checkpoint["ready"])
            self.assertIn("changed_path_limit_exceeded", reasons)
            self.assertEqual(checkpoint["repo"]["validation_scope"], "legacy_worktree_v1")

    def test_more_than_32_unique_task_paths_use_scoped_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            snapshot = rollover.plan_snapshot(plan, runtime)
            paths = [f"lib/generated_{index}.dart" for index in range(40)]
            snapshot["changed_paths"] = paths
            snapshot["explicit_changed_paths"] = paths
            snapshot["task_scope_complete"] = True
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE,
            )
            self.assertEqual(reasons, [])
            self.assertTrue(checkpoint["ready"])
            self.assertEqual(checkpoint["changed_paths"], paths)
            self.assertEqual(checkpoint["repo"]["validation_scope"], "task_paths_v1")
            self.assertEqual(checkpoint["repo"]["task_path_count"], 40)

    def test_redeclared_cumulative_scope_is_deduplicated_before_limit_check(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            prior_paths = [f"lib/task_{index}.dart" for index in range(14)]
            first_snapshot = rollover.plan_snapshot(plan, runtime)
            first_snapshot["changed_paths"] = prior_paths
            first_snapshot["explicit_changed_paths"] = prior_paths
            first_snapshot["task_scope_complete"] = True
            first, first_reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=first_snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE,
            )
            self.assertEqual(first_reasons, [])
            self.assertTrue(first["ready"])

            cumulative_paths = [f"lib/task_{index}.dart" for index in range(22)]
            second_snapshot = rollover.plan_snapshot(plan, runtime)
            second_snapshot["changed_paths"] = cumulative_paths
            second_snapshot["explicit_changed_paths"] = cumulative_paths
            second_snapshot["task_scope_complete"] = True
            second, second_reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=second_snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE + dt.timedelta(seconds=5),
            )
            self.assertEqual(second_reasons, [])
            self.assertTrue(second["ready"])
            self.assertEqual(second["changed_paths"], cumulative_paths)
            self.assertNotIn(
                "changed_path_limit_exceeded",
                second["validation_reason_codes"],
            )

    def test_planless_post_rollover_omission_inherits_private_task_scope(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            raw_scope = "private-planless-task-a"
            session = "root-session"
            first_code, first_output = run_prepare_cli(
                runtime,
                planless_prepare_args(raw_scope, "lib/example.dart"),
                session=session,
            )
            self.assertEqual(first_code, 0, first_output)
            self.assertIn("READY checkpoint=", first_output)
            self.assertNotIn(raw_scope, first_output)
            first = rollover._read_checkpoint(
                runtime, rollover._privacy_digest("root-session")
            )
            self.assertEqual(first["changed_paths"], ["lib/example.dart"])
            self.assertRegex(
                first["task_scope_id_sha256"], r"^[0-9a-f]{16,64}$"
            )
            self.assertNotIn(raw_scope, json.dumps(first, sort_keys=True))
            manifest_path = rollover._scope_manifest_path(
                runtime,
                rollover._privacy_digest(session),
                first["task_scope_id_sha256"],
            )
            self.assertEqual(stat.S_IMODE(manifest_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(manifest_path.parent.stat().st_mode), 0o700)

            lifecycle_now = rollover._utc_now()
            precompact = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": session,
                    "cwd": str(runtime.root),
                    "turn_id": "planless-first-rollover",
                    "trigger": "auto",
                },
                runtime=runtime,
                now=lifecycle_now,
            )
            self.assertEqual(
                precompact, {"continue": True, "suppressOutput": True}
            )
            resumed = rollover.process_hook(
                {
                    "hook_event_name": "SessionStart",
                    "session_id": session,
                    "cwd": str(runtime.root),
                    "source": "compact",
                },
                runtime=runtime,
                now=lifecycle_now + dt.timedelta(seconds=1),
            )
            resumed_context = resumed["hookSpecificOutput"]["additionalContext"]
            self.assertNotIn(raw_scope, resumed_context)
            self.assertIn("Validated prepared context-rollover checkpoint", resumed_context)

            second_code, second_output = run_prepare_cli(
                runtime,
                planless_prepare_args(None, "test/example_test.dart"),
                session=session,
            )
            self.assertEqual(second_code, 0, second_output)
            self.assertNotIn(raw_scope, second_output)
            second = rollover._read_checkpoint(
                runtime, rollover._privacy_digest("root-session")
            )
            self.assertEqual(
                second["changed_paths"],
                ["lib/example.dart", "test/example_test.dart"],
            )
            self.assertEqual(
                second["task_scope_id_sha256"], first["task_scope_id_sha256"]
            )
            self.assertEqual(second["repo"]["validation_scope"], "task_paths_v1")
            self.assertEqual(second["repo"]["task_path_count"], 2)
            self.assertNotIn(raw_scope, json.dumps(second, sort_keys=True))
            self.assertNotIn(raw_scope, json.dumps(events(runtime), sort_keys=True))

    def test_planless_different_task_scope_id_never_carries_prior_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            first_code, first_output = run_prepare_cli(
                runtime,
                planless_prepare_args("private-task-a", "lib/example.dart"),
            )
            self.assertEqual(first_code, 0, first_output)
            first = rollover._read_checkpoint(
                runtime, rollover._privacy_digest("root-session")
            )

            second_code, second_output = run_prepare_cli(
                runtime,
                planless_prepare_args("private-task-b", "test/example_test.dart"),
            )
            self.assertEqual(second_code, 0, second_output)
            second = rollover._read_checkpoint(
                runtime, rollover._privacy_digest("root-session")
            )
            self.assertEqual(second["changed_paths"], ["test/example_test.dart"])
            self.assertNotIn("lib/example.dart", second["changed_paths"])
            self.assertNotEqual(
                first["task_scope_id_sha256"], second["task_scope_id_sha256"]
            )
            serialized = json.dumps(
                {"checkpoint": second, "events": events(runtime)}, sort_keys=True
            )
            self.assertNotIn("private-task-a", serialized)
            self.assertNotIn("private-task-b", serialized)

    def test_tracked_plan_post_rollover_omission_inherits_private_task_scope(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            session = "root-session"
            raw_scope = "private-tracked-task"
            first_code, first_output = run_prepare_cli(
                runtime,
                [
                    "prepare",
                    "--from-plan",
                    str(plan),
                    "--outstanding-work",
                    "none",
                    "--task-scope-id",
                    raw_scope,
                    "--task-scope-complete",
                ],
                session=session,
            )
            self.assertEqual(first_code, 0, first_output)
            first = rollover._read_checkpoint(
                runtime, rollover._privacy_digest(session)
            )

            lifecycle_now = rollover._utc_now()
            rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": session,
                    "cwd": str(runtime.root),
                    "turn_id": "tracked-first-rollover",
                    "trigger": "auto",
                },
                runtime=runtime,
                now=lifecycle_now,
            )
            rollover.process_hook(
                {
                    "hook_event_name": "SessionStart",
                    "session_id": session,
                    "cwd": str(runtime.root),
                    "source": "compact",
                },
                runtime=runtime,
                now=lifecycle_now + dt.timedelta(seconds=1),
            )

            second_code, second_output = run_prepare_cli(
                runtime,
                [
                    "prepare",
                    "--from-plan",
                    str(plan),
                    "--outstanding-work",
                    "none",
                    "--changed-path",
                    "lib/new.dart",
                    "--task-scope-complete",
                ],
                session=session,
            )
            self.assertEqual(second_code, 0, second_output)
            second = rollover._read_checkpoint(
                runtime, rollover._privacy_digest(session)
            )
            self.assertEqual(
                second["task_scope_id_sha256"], first["task_scope_id_sha256"]
            )
            self.assertIn("lib/example.dart", second["changed_paths"])
            self.assertIn("test/example_test.dart", second["changed_paths"])
            self.assertIn("lib/new.dart", second["changed_paths"])
            self.assertNotIn(raw_scope, json.dumps(second, sort_keys=True))

    def test_inherited_task_scope_fails_closed_when_manifest_is_missing(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            session = "root-session"
            first_code, first_output = run_prepare_cli(
                runtime,
                planless_prepare_args("private-missing-manifest", "lib/example.dart"),
                session=session,
            )
            self.assertEqual(first_code, 0, first_output)
            first = rollover._read_checkpoint(
                runtime, rollover._privacy_digest(session)
            )
            manifest_path = rollover._scope_manifest_path(
                runtime,
                rollover._privacy_digest(session),
                first["task_scope_id_sha256"],
            )
            manifest_path.unlink()

            second_code, second_output = run_prepare_cli(
                runtime,
                planless_prepare_args(None, "test/example_test.dart"),
                session=session,
            )
            self.assertEqual(second_code, 2)
            self.assertIn("repo_fingerprint_unavailable", second_output)
            self.assertIn(
                "repo_fingerprint_failure=scope_manifest_missing", second_output
            )
            second = rollover._read_checkpoint(
                runtime, rollover._privacy_digest(session)
            )
            self.assertFalse(second["ready"])
            self.assertEqual(
                second["repo"]["repo_fingerprint_failure"],
                "scope_manifest_missing",
            )

    def test_saved_task_scope_becomes_untrusted_if_manifest_disappears(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            session = "root-session"
            code, output = run_prepare_cli(
                runtime,
                planless_prepare_args("private-bound-scope", "lib/example.dart"),
                session=session,
            )
            self.assertEqual(code, 0, output)
            checkpoint = rollover._read_checkpoint(
                runtime, rollover._privacy_digest(session)
            )
            rollover._scope_manifest_path(
                runtime,
                rollover._privacy_digest(session),
                checkpoint["task_scope_id_sha256"],
            ).unlink()

            reasons = rollover._validation_reasons(
                checkpoint,
                runtime,
                now=rollover._utc_now(),
                require_fresh_generation=True,
            )
            self.assertIn("repo_fingerprint_unavailable", reasons)

    def test_completed_task_scope_id_cannot_resurrect_its_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            session = "root-session"
            raw_scope = "private-completed-scope"
            code, output = run_prepare_cli(
                runtime,
                planless_prepare_args(raw_scope, "lib/example.dart"),
                session=session,
            )
            self.assertEqual(code, 0, output)
            self.assertTrue(
                rollover.complete_checkpoint(
                    runtime,
                    session_id=session,
                    thread_id=session,
                )
            )

            retry_code, retry_output = run_prepare_cli(
                runtime,
                planless_prepare_args(raw_scope, "test/example_test.dart"),
                session=session,
            )
            self.assertEqual(retry_code, 2)
            self.assertIn("repo_fingerprint_unavailable", retry_output)
            self.assertIn(
                "repo_fingerprint_failure=scope_manifest_completed", retry_output
            )

    def test_invalid_task_scope_id_fails_closed_without_raw_value_leak(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            raw_scope = "SENSITIVE-" + (
                "x" * (rollover.MAX_TASK_SCOPE_ID_BYTES + 1)
            )
            code, output = run_prepare_cli(
                runtime,
                planless_prepare_args(raw_scope, "lib/example.dart"),
            )
            self.assertEqual(code, 2)
            self.assertIn("task_scope_id_invalid", output)
            self.assertNotIn(raw_scope, output)
            checkpoint = rollover._read_checkpoint(
                runtime, rollover._privacy_digest("root-session")
            )
            self.assertFalse(checkpoint["ready"])
            self.assertIn(
                "task_scope_id_invalid", checkpoint["validation_reason_codes"]
            )
            self.assertFalse(checkpoint.get("task_scope_id_sha256"))
            serialized = json.dumps(
                {"checkpoint": checkpoint, "events": events(runtime)},
                sort_keys=True,
            )
            self.assertNotIn(raw_scope, serialized)

    def test_explicit_complete_empty_scope_is_scoped_and_ignores_unrelated_dirt(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            with mock.patch.object(
                rollover,
                "_legacy_repo_fingerprint",
                side_effect=AssertionError("explicit empty scope used legacy capture"),
            ):
                code, output = run_prepare_cli(
                    runtime,
                    planless_prepare_args("empty-private-task"),
                )
                self.assertEqual(code, 0, output)
                checkpoint = rollover._read_checkpoint(
                    runtime, rollover._privacy_digest("root-session")
                )
                self.assertTrue(checkpoint["ready"])
                self.assertTrue(checkpoint["task_scope_complete"])
                self.assertEqual(checkpoint["changed_paths"], [])
                self.assertEqual(
                    checkpoint["repo"]["validation_scope"], "task_paths_v1"
                )
                self.assertEqual(checkpoint["repo"]["task_path_count"], 0)
                self.assertRegex(
                    checkpoint["task_scope_id_sha256"], r"^[0-9a-f]{16,64}$"
                )
                self.assertNotIn(
                    "empty-private-task", json.dumps(checkpoint, sort_keys=True)
                )
                self.assertNotIn(
                    "empty-private-task",
                    json.dumps(events(runtime), sort_keys=True),
                )

                write(
                    runtime.root / "shared" / "unrelated-large.txt",
                    "unrelated\n" * 4096,
                )
                reasons = rollover._validation_reasons(
                    checkpoint,
                    runtime,
                    now=rollover._utc_now(),
                    require_fresh_generation=True,
                )
                self.assertNotIn("repo_fingerprint_unavailable", reasons)
                self.assertNotIn("task_scope_changed", reasons)
                self.assertNotIn("worktree_changed", reasons)
                precompact = rollover.process_hook(
                    {
                        "hook_event_name": "PreCompact",
                        "session_id": "root-session",
                        "cwd": str(runtime.root),
                        "turn_id": "empty-scope-turn",
                        "trigger": "auto",
                    },
                    runtime=runtime,
                    now=rollover._utc_now(),
                )
                self.assertEqual(
                    precompact, {"continue": True, "suppressOutput": True}
                )
                self.assertEqual(events(runtime)[-1]["event"], "precompact_allowed")

    def test_empty_scope_without_completeness_uses_legacy_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            with mock.patch.object(
                rollover,
                "_legacy_repo_fingerprint",
                wraps=rollover._legacy_repo_fingerprint,
            ) as legacy:
                code, output = run_prepare_cli(
                    runtime,
                    planless_prepare_args(
                        "empty-incomplete-task", complete=False
                    ),
                )
            self.assertEqual(code, 0, output)
            self.assertGreaterEqual(legacy.call_count, 1)
            checkpoint = rollover._read_checkpoint(
                runtime, rollover._privacy_digest("root-session")
            )
            self.assertFalse(checkpoint["task_scope_complete"])
            self.assertEqual(checkpoint["changed_paths"], [])
            self.assertEqual(
                checkpoint["repo"]["validation_scope"], "legacy_worktree_v1"
            )

    def test_incomplete_bound_scope_can_be_completed_after_id_inheritance(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            first_code, first_output = run_prepare_cli(
                runtime,
                planless_prepare_args(
                    "private-later-complete",
                    "lib/example.dart",
                    complete=False,
                ),
            )
            self.assertEqual(first_code, 0, first_output)
            first = rollover._read_checkpoint(
                runtime, rollover._privacy_digest("root-session")
            )
            self.assertNotIn("task_scope_manifest_sha256", first)

            second_code, second_output = run_prepare_cli(
                runtime,
                planless_prepare_args(
                    None,
                    "lib/example.dart",
                    "test/example_test.dart",
                ),
            )
            self.assertEqual(second_code, 0, second_output)
            second = rollover._read_checkpoint(
                runtime, rollover._privacy_digest("root-session")
            )
            self.assertEqual(second["repo"]["validation_scope"], "task_paths_v1")
            self.assertEqual(second["repo"]["task_path_count"], 2)
            self.assertRegex(
                second["task_scope_manifest_sha256"], r"^[0-9a-f]{64}$"
            )

    def test_complete_empty_scope_without_task_scope_id_is_never_trusted_scoped(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            code, output = run_prepare_cli(
                runtime,
                planless_prepare_args(None),
            )
            checkpoint = rollover._read_checkpoint(
                runtime, rollover._privacy_digest("root-session")
            )
            self.assertTrue(
                code == 2
                or checkpoint["repo"]["validation_scope"] == "legacy_worktree_v1",
                output,
            )
            self.assertFalse(
                checkpoint["ready"]
                and checkpoint["repo"]["validation_scope"] == "task_paths_v1"
                and checkpoint["repo"]["task_path_count"] == 0
            )

    def test_legacy_planless_checkpoint_without_task_scope_id_never_carries(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            first_code, first_output = run_prepare_cli(
                runtime,
                planless_prepare_args(None, "lib/example.dart"),
            )
            self.assertEqual(first_code, 0, first_output)
            first = rollover._read_checkpoint(
                runtime, rollover._privacy_digest("root-session")
            )
            self.assertNotIn("task_scope_id_sha256", first)

            second_code, second_output = run_prepare_cli(
                runtime,
                planless_prepare_args(None, "test/example_test.dart"),
            )
            self.assertEqual(second_code, 0, second_output)
            second = rollover._read_checkpoint(
                runtime, rollover._privacy_digest("root-session")
            )
            self.assertEqual(second["changed_paths"], ["test/example_test.dart"])
            self.assertNotIn("lib/example.dart", second["changed_paths"])
            self.assertNotIn("task_scope_id_sha256", second)

    def test_incomplete_prior_scope_is_never_partially_carried_forward(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            first_snapshot = rollover.plan_snapshot(plan, runtime)
            generated = [
                f"lib/generated_{index}.dart"
                for index in range(rollover.MAX_TASK_PATHS + 1)
            ]
            first_snapshot["changed_paths"] = generated
            first_snapshot["explicit_changed_paths"] = generated
            first_snapshot["task_scope_complete"] = True
            first, first_reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=first_snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE,
            )
            self.assertFalse(first["ready"])
            self.assertIn("changed_path_limit_exceeded", first_reasons)

            corrected_snapshot = rollover.plan_snapshot(plan, runtime)
            corrected_snapshot["task_scope_complete"] = True
            second, second_reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=corrected_snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE + dt.timedelta(seconds=5),
            )
            self.assertEqual(second_reasons, [])
            self.assertTrue(second["ready"])
            self.assertFalse(set(generated) & set(second["changed_paths"]))

    def test_unverified_plan_path_prose_falls_back_to_legacy_scope(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            text = PLAN.replace(
                "| 2026-08-23 11:00 | Step 1 | `lib/example.dart` |",
                "| 2026-08-23 11:00 | Step 1 | `existing helper and contract` |",
            ).replace(
                "| 2026-08-23 12:00 | Step 2 / TC-01 GREEN | `lib/example.dart`, `test/example_test.dart` |",
                "| 2026-08-23 12:00 | Step 2 / TC-01 GREEN | criteria/probe/runner |",
            )
            write(plan, text)
            snapshot = rollover.plan_snapshot(plan, runtime)
            self.assertEqual(snapshot["changed_paths"], [])
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE,
            )
            self.assertEqual(reasons, [])
            self.assertEqual(checkpoint["repo"]["validation_scope"], "legacy_worktree_v1")

    def test_missing_plan_tokens_are_filtered_from_a_mixed_real_scope(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            write(
                plan,
                PLAN.replace(
                    "`lib/example.dart`, `test/example_test.dart`",
                    "`lib/example.dart`, `criteria/probe/runner`, `permission/identity`, `.xctestrun`",
                ),
            )
            snapshot = rollover.plan_snapshot(plan, runtime)
            snapshot["task_scope_complete"] = True
            self.assertEqual(
                snapshot["changed_paths"],
                ["lib/example.dart"],
            )
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE,
            )
            self.assertEqual(reasons, [])
            self.assertEqual(checkpoint["repo"]["validation_scope"], "task_paths_v1")
            self.assertEqual(checkpoint["repo"]["task_path_count"], 1)

    def test_same_plan_carries_prior_scope_but_different_plan_does_not(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            first = save_ready(runtime, plan)
            self.assertIn("test/example_test.dart", first["changed_paths"])
            self.assertNotIn("task_scope_id_sha256", first)
            write(
                plan,
                PLAN.replace(
                    "`lib/example.dart`, `test/example_test.dart`",
                    "`lib/example.dart`",
                ),
            )
            second_snapshot = rollover.plan_snapshot(plan, runtime)
            second_snapshot["task_scope_complete"] = True
            second, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=second_snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE + dt.timedelta(seconds=10),
            )
            self.assertEqual(reasons, [])
            self.assertIn("test/example_test.dart", second["changed_paths"])
            self.assertNotIn("task_scope_id_sha256", second)

            other_plan = runtime.root / "plans" / "402-other-plan.md"
            write(
                other_plan,
                PLAN.replace("401 - Context", "402 - Other").replace(
                    "`lib/example.dart`, `test/example_test.dart`",
                    "`lib/example.dart`",
                ),
            )
            third_snapshot = rollover.plan_snapshot(other_plan, runtime)
            third_snapshot["task_scope_complete"] = True
            third, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=third_snapshot,
                outstanding_work="none",
                trigger="cli_prepare",
                now=BASE + dt.timedelta(seconds=20),
            )
            self.assertEqual(reasons, [])
            self.assertNotIn("test/example_test.dart", third["changed_paths"])

    def test_edit_after_precompact_downgrades_session_start_to_advisory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            save_ready(runtime, plan)
            precompact = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "turn_id": "turn",
                    "trigger": "auto",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=5),
            )
            self.assertEqual(precompact, {"continue": True, "suppressOutput": True})
            self.assertEqual(events(runtime)[-1]["event"], "precompact_allowed")
            write(runtime.root / "lib" / "example.dart", "changed after compact\n")
            resumed = rollover.process_hook(
                {
                    "hook_event_name": "SessionStart",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "source": "compact",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=6),
            )
            context = resumed["hookSpecificOutput"]["additionalContext"]
            self.assertIn("ADVISORY", context)
            self.assertEqual(events(runtime)[-1]["event"], "session_recovery_advisory")
            self.assertIn("task_scope_changed", events(runtime)[-1]["reason_codes"])

    def test_unarmed_manual_precompact_is_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            snapshot = rollover.plan_snapshot(plan, runtime)
            checkpoint, reasons = rollover.save_checkpoint(
                runtime,
                session_id="root-session-raw",
                thread_id="root-session-raw",
                snapshot=snapshot,
                outstanding_work="none",
                trigger="cli_save",
                now=BASE,
            )
            self.assertTrue(checkpoint["ready"])
            self.assertEqual(reasons, [])
            result = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "turn_id": "turn",
                    "trigger": "manual",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(seconds=5),
            )
            self.assertFalse(result["continue"])
            self.assertIn("rollover_intent_missing", result["stopReason"])
            self.assertEqual(events(runtime)[-1]["event"], "precompact_blocked")
            self.assertIn("rollover_intent_missing", events(runtime)[-1]["reason_codes"])

    def test_stale_checkpoint_and_changed_plan_auto_compaction_recover(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            save_ready(runtime, plan)
            stale = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "turn_id": "turn",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(minutes=31),
            )
            self.assertEqual(stale, {"continue": True, "suppressOutput": True})
            self.assertEqual(events(runtime)[-1]["event"], "precompact_recovery_allowed")
            self.assertIn("checkpoint_age_exceeded", events(runtime)[-1]["reason_codes"])

            save_ready(runtime, plan, now=BASE + dt.timedelta(minutes=32))
            write(plan, PLAN + "\nchanged\n")
            changed = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "turn_id": "turn-2",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(minutes=32, seconds=5),
            )
            self.assertEqual(changed, {"continue": True, "suppressOutput": True})
            self.assertEqual(events(runtime)[-1]["event"], "precompact_recovery_allowed")
            self.assertIn("plan_changed", events(runtime)[-1]["reason_codes"])

    def test_invalid_manual_precompact_remains_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            save_ready(runtime, plan)
            result = rollover.process_hook(
                {
                    "hook_event_name": "PreCompact",
                    "session_id": "root-session-raw",
                    "cwd": str(runtime.root),
                    "turn_id": "turn",
                    "trigger": "manual",
                },
                runtime=runtime,
                now=BASE + dt.timedelta(minutes=31),
            )
            self.assertFalse(result["continue"])
            self.assertIn("checkpoint_age_exceeded", result["stopReason"])
            self.assertEqual(events(runtime)[-1]["event"], "precompact_blocked")

    def test_missing_session_start_injects_bounded_generic_advisory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            result = rollover.process_hook(
                {
                    "hook_event_name": "SessionStart",
                    "session_id": "missing",
                    "cwd": str(runtime.root),
                    "source": "compact",
                },
                runtime=runtime,
                now=BASE,
                context_token_limit=160,
            )
            context = result["hookSpecificOutput"]["additionalContext"]
            self.assertIn("ADVISORY", context)
            self.assertIn("checkpoint_missing", context)
            self.assertIn("No independently verified active-plan locator", context)
            self.assertLessEqual(rollover._token_estimate(context), 160)
            self.assertEqual(events(runtime)[-1]["event"], "session_recovery_advisory")

    def test_postcompact_is_always_non_blocking_even_when_checkpoint_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, _plan = fixture(Path(temporary))
            result = rollover.process_hook(
                {
                    "hook_event_name": "PostCompact",
                    "session_id": "missing",
                    "cwd": str(runtime.root),
                    "trigger": "auto",
                },
                runtime=runtime,
                now=BASE,
            )
            self.assertEqual(result, {"continue": True, "suppressOutput": True})
            self.assertEqual(events(runtime)[-1]["event"], "postcompact_observed")
            self.assertFalse(events(runtime)[-1]["ready"])

    def test_recognizable_precompact_internal_error_is_auto_open_manual_closed(self) -> None:
        payload = json.dumps(
            {
                "hook_event_name": "PreCompact",
                "session_id": "session",
                "cwd": "/tmp",
                "turn_id": "turn",
            }
        )
        output = StringIO()
        with (
            mock.patch("sys.stdin", StringIO(payload)),
            mock.patch.object(rollover, "_load_runtime", side_effect=RuntimeError("boom")),
            redirect_stdout(output),
        ):
            code = rollover.main(["hook-pre"])
        self.assertEqual(code, 0)
        result = json.loads(output.getvalue())
        self.assertTrue(result["continue"])
        self.assertNotIn("boom", output.getvalue())

        manual_payload = json.dumps(
            {
                "hook_event_name": "PreCompact",
                "session_id": "session",
                "cwd": "/tmp",
                "turn_id": "turn",
                "trigger": "manual",
            }
        )
        output = StringIO()
        with (
            mock.patch("sys.stdin", StringIO(manual_payload)),
            mock.patch.object(rollover, "_load_runtime", side_effect=RuntimeError("boom")),
            redirect_stdout(output),
        ):
            code = rollover.main(["hook-pre"])
        self.assertEqual(code, 0)
        result = json.loads(output.getvalue())
        self.assertFalse(result["continue"])
        self.assertIn("Manual context compaction stopped", result["stopReason"])
        self.assertNotIn("boom", output.getvalue())

        output = StringIO()
        with mock.patch("sys.stdin", StringIO("{bad json")), redirect_stdout(output):
            code = rollover.main(["hook-pre"])
        self.assertEqual(code, 0)
        self.assertEqual(output.getvalue(), "")

    def test_complete_marks_checkpoint_and_emits_terminal_event(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            runtime, plan = fixture(Path(temporary))
            save_ready(runtime, plan)
            self.assertTrue(
                rollover.complete_checkpoint(
                    runtime,
                    session_id="root-session-raw",
                    thread_id="root-session-raw",
                    now=BASE + dt.timedelta(seconds=30),
                )
            )
            session_hash = rollover._privacy_digest("root-session-raw")
            checkpoint = rollover._read_checkpoint(runtime, session_hash)
            self.assertEqual(checkpoint["status"], "completed")
            self.assertEqual(events(runtime)[-1]["event"], "checkpoint_completed")


if __name__ == "__main__":
    unittest.main()
