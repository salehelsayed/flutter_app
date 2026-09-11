#!/usr/bin/env python3
"""Durable, privacy-safe checkpoints for Codex context-window rollover.

The checkpoint is deliberately separate from plans and specifications.  It is
private local execution state (0700 directory, atomic 0600 files) keyed by the
hashed root Codex session.  The model-visible capsule is bounded; lifecycle
telemetry contains only hashes, counters, categories, and size estimates.  It
never contains raw prompts, commands, plan paths, phase text, or Codex ids.

Codex 0.149 only supports reliable root-agent checkpoint restoration. Manual
subagent compaction is stopped so it can hand back to root; automatic child
compaction is allowed through native recovery without touching the root capsule.
The benchmark control arm is deliberately passive: it observes PostCompact but
never reads, validates, writes, or injects a checkpoint.
"""

from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import hashlib
import json
import math
import os
import re
import shlex
import stat
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Iterable, Iterator, Sequence

try:
    import fcntl
except ImportError:  # pragma: no cover - Windows is not a supported project host.
    fcntl = None  # type: ignore[assignment]


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import memory  # noqa: E402


SCHEMA_VERSION = 1
EVENT_SCHEMA_VERSION = 1
TASK_SCOPE_MANIFEST_SCHEMA_VERSION = 1
DEFAULT_MAX_AGE_SECONDS = 30 * 60
DEFAULT_PREPARED_MAX_AGE_SECONDS = 10 * 60
DEFAULT_CONTEXT_TOKENS = 700
MIN_CONTEXT_TOKENS = 160
MAX_CONTEXT_TOKENS = 1_000
MAX_PLAN_BYTES = 3_000_000
MAX_SECTION_CHARS = 96_000
MAX_LIST_ITEMS = 64
MAX_TASK_PATHS = 256
MAX_TASK_SCOPE_BYTES = 64 * 1024 * 1024
# The registered PreCompact hook has a 15-second timeout. Keep enough headroom
# for locking, validation, checkpoint persistence, telemetry, and JSON output.
MAX_TASK_CAPTURE_SECONDS = 10.0
MAX_LEGACY_DIRTY_BYTES = 16 * 1024 * 1024
MAX_LEGACY_DIRTY_PATHS = 4_096
MAX_LEGACY_CAPTURE_SECONDS = 8.0
MAX_TASK_SCOPE_ID_BYTES = 128
FALSE_VALUES = {"0", "false", "no", "off"}
HEX_ANCHOR = re.compile(r"^[0-9a-f]{12,64}$", re.I)
QUERY_ANCHOR = re.compile(
    r"\bquery_id\s*(?:=|:)?\s*`?([0-9a-f]{12,64})", re.I
)
EVIDENCE_ANCHOR = re.compile(
    r"\bevidence_digest\s*(?:=|:)?\s*`?([0-9a-f]{12,64})", re.I
)
TEST_ANCHOR = re.compile(r"\bTC[-_ ]?\d+(?:[-_]\d+)*\b", re.I)
GATE_COMMAND = re.compile(
    r"(?:^|[/\\])run_test_gates\.sh\s+([A-Za-z0-9_.-]+)", re.I
)
PATH_ANCHOR = re.compile(
    r"(?<![A-Za-z0-9_.-])(?:[A-Za-z0-9_.@+-]+/)+[A-Za-z0-9_.@+*-]+"
)
PLACEHOLDERS = {
    "",
    "-",
    "--",
    "---",
    "—",
    "n/a",
    "none recorded",
    "pending update",
    "<phase>",
    "<next>",
    "yyyy-mm-dd hh:mm",
}
STALE_REASONS = {
    "checkpoint_age_exceeded",
    "checkpoint_already_consumed",
    "changed_path_limit_exceeded",
    "plan_changed",
    "plan_missing",
    "plan_outside_repo",
    "plan_too_large",
    "plan_extraction_failed",
    "plan_read_failed",
    "prepared_checkpoint_missing",
    "prepared_checkpoint_stale",
    "prepared_generation_mismatch",
    "repo_head_changed",
    "task_scope_changed",
    "task_scope_id_invalid",
    "worktree_changed",
}
ROLLOVER_INTENT_REASONS = {
    "rollover_intent_missing",
    "rollover_intent_stale",
    "rollover_intent_mismatch",
}
CONTINUATION_MODES = {"prepared_rollover", "recovery_advisory"}
FIXED_REASON_CODES = {
    "advisory_reset_requested",
    "changed_path_outside_repo",
    "changed_path_limit_exceeded",
    "checkpoint_missing",
    "checkpoint_schema_mismatch",
    "checkpoint_completed",
    "saved_at_missing",
    "checkpoint_age_exceeded",
    "plan_status_missing",
    "plan_missing",
    "plan_outside_repo",
    "plan_too_large",
    "plan_extraction_failed",
    "plan_read_failed",
    "plan_changed",
    "phase_missing",
    "next_action_missing",
    "test_and_gate_anchors_missing",
    "graph_status_missing",
    "graph_query_missing",
    "graph_evidence_missing",
    "outstanding_work_missing",
    "outstanding_work_running",
    "repo_fingerprint_unavailable",
    "repo_head_changed",
    "task_scope_changed",
    "task_scope_id_invalid",
    "worktree_changed",
    "checkpoint_already_consumed",
    "prepared_checkpoint_missing",
    "prepared_checkpoint_stale",
    "prepared_generation_mismatch",
    "subagent_rollover_unsupported",
    *ROLLOVER_INTENT_REASONS,
}
FINGERPRINT_FAILURE_CODES = {
    "capture_limit_exceeded",
    "capture_timeout",
    "capture_unavailable",
    "git_command_failed",
    "git_output_invalid",
    "repository_changed",
    "scope_invalid",
    "scope_manifest_completed",
    "scope_manifest_invalid",
    "scope_manifest_missing",
    "scope_manifest_write_failed",
    "unsafe_index_state",
    "unstable_worktree",
    "unsupported_path",
    "legacy_dirty_content_byte_limit",
}
FINGERPRINT_FAILURE_STAGES = {
    "deadline",
    "dirty_path_content",
    "dirty_path_count",
    "git_scope_initial",
    "git_scope_verify",
    "head_final",
    "head_initial",
    "index_initial",
    "repository_verify",
    "scope_input",
    "scope_manifest",
    "status_initial",
    "worktree_initial",
    "worktree_verify",
}


def _utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _iso(value: dt.datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=dt.timezone.utc)
    return value.astimezone(dt.timezone.utc).isoformat()


def _parse_time(value: Any) -> dt.datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def _canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _digest(value: Any, *, length: int = 16) -> str:
    if not isinstance(value, str):
        value = _canonical(value)
    return hashlib.sha256(value.encode("utf-8", errors="replace")).hexdigest()[:length]


def _privacy_digest(value: Any) -> str:
    candidate = str(value or "").strip().lower()
    if re.fullmatch(r"[0-9a-f]{16,64}", candidate):
        return candidate[:16]
    return _digest(candidate or "unknown")


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(128 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _token_estimate(value: str) -> int:
    return int(math.ceil(len(value.encode("utf-8", errors="replace")) / 4.0))


def _clean_text(value: Any, limit: int) -> str:
    text = str(value or "")
    text = " ".join(text.replace("\x00", " ").split())
    return text[:limit].rstrip()


def _dedupe(values: Iterable[str], *, limit: int = MAX_LIST_ITEMS) -> list[str]:
    result: list[str] = []
    for value in values:
        cleaned = _clean_text(value, 240)
        if cleaned and cleaned not in result:
            result.append(cleaned)
        if len(result) >= limit:
            break
    return result


def _env_int(name: str, default: int, minimum: int, maximum: int) -> int:
    try:
        value = int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default
    return min(maximum, max(minimum, value))


def _control_rollover_arm() -> bool:
    return (
        os.environ.get("CODEX_TASK_RUN_ROLLOVER_ARM", "").strip().lower()
        == "control"
    )


def _max_age_seconds() -> int:
    return _env_int(
        "CODEX_ROLLOVER_MAX_AGE_SECONDS",
        DEFAULT_MAX_AGE_SECONDS,
        60,
        24 * 60 * 60,
    )


def _prepared_max_age_seconds() -> int:
    return _env_int(
        "CODEX_ROLLOVER_PREPARED_MAX_AGE_SECONDS",
        DEFAULT_PREPARED_MAX_AGE_SECONDS,
        30,
        60 * 60,
    )


def _context_token_limit(value: int | None = None) -> int:
    if value is not None:
        return min(MAX_CONTEXT_TOKENS, max(MIN_CONTEXT_TOKENS, int(value)))
    return _env_int(
        "CODEX_ROLLOVER_CONTEXT_TOKENS",
        DEFAULT_CONTEXT_TOKENS,
        MIN_CONTEXT_TOKENS,
        MAX_CONTEXT_TOKENS,
    )


def _state_directory(runtime: memory.Runtime) -> Path:
    path = runtime.state_dir / "context-rollover"
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path, 0o700)
    return path


def _checkpoint_path(runtime: memory.Runtime, session_sha256: str) -> Path:
    return _state_directory(runtime) / (session_sha256 + ".json")


def _scope_manifest_path(
    runtime: memory.Runtime, session_sha256: str, task_scope_sha256: str
) -> Path:
    directory = _state_directory(runtime) / "scopes" / session_sha256
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(directory, 0o700)
    return directory / (task_scope_sha256 + ".json")


def _lock_path(runtime: memory.Runtime, session_sha256: str) -> Path:
    return _state_directory(runtime) / (session_sha256 + ".lock")


def _telemetry_path(runtime: memory.Runtime) -> Path:
    return runtime.state_dir / "context-rollover-events.jsonl"


@contextlib.contextmanager
def _session_lock(runtime: memory.Runtime, session_sha256: str) -> Iterator[None]:
    path = _lock_path(runtime, session_sha256)
    descriptor = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        if fcntl is not None:
            fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        if fcntl is not None:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def _atomic_write(path: Path, value: dict[str, Any]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    data = (_canonical(value) + "\n").encode("utf-8")
    temporary = path.with_name(
        ".{}.{}.{}.tmp".format(path.name, os.getpid(), time.time_ns())
    )
    descriptor = os.open(
        temporary,
        os.O_CREAT | os.O_EXCL | os.O_WRONLY,
        0o600,
    )
    try:
        os.fchmod(descriptor, 0o600)
        view = memoryview(data)
        while view:
            written = os.write(descriptor, view)
            view = view[written:]
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    try:
        os.replace(temporary, path)
        os.chmod(path, 0o600)
        try:
            directory_fd = os.open(path.parent, os.O_RDONLY)
        except OSError:
            directory_fd = None
        if directory_fd is not None:
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
    return len(data)


def _task_scope_id_digest(
    value: Any, *, session_sha256: str, thread_sha256: str
) -> str:
    raw = str(value or "").strip()
    try:
        encoded = raw.encode("ascii", errors="strict") if raw else b""
    except UnicodeEncodeError:
        return ""
    if (
        not encoded
        or len(encoded) > MAX_TASK_SCOPE_ID_BYTES
        or re.fullmatch(r"[A-Za-z0-9._:-]+", raw) is None
    ):
        return ""
    return _digest(
        {
            "version": 1,
            "codex_session_sha256": session_sha256,
            "codex_thread_sha256": thread_sha256,
            "task_scope_id": raw,
        },
        length=64,
    )


def _task_scope_paths_sha256(paths: Sequence[str]) -> str:
    return _digest(sorted(set(paths)), length=64)


def _scope_manifest_digest(manifest: dict[str, Any]) -> str:
    return _digest(manifest, length=64)


def _scope_manifest_value(
    *,
    session_sha256: str,
    thread_sha256: str,
    task_scope_sha256: str,
    changed_paths: Sequence[str],
    generation: int,
    now: dt.datetime,
    status: str = "active",
) -> dict[str, Any]:
    paths = list(changed_paths)
    return {
        "schema_version": TASK_SCOPE_MANIFEST_SCHEMA_VERSION,
        "codex_session_sha256": session_sha256,
        "codex_thread_sha256": thread_sha256,
        "task_scope_id_sha256": task_scope_sha256,
        "status": status,
        "task_scope_complete": True,
        "changed_paths": paths,
        "changed_paths_sha256": _task_scope_paths_sha256(paths),
        "generation": generation,
        "updated_at": _iso(now),
    }


def _read_scope_manifest(
    runtime: memory.Runtime,
    *,
    session_sha256: str,
    thread_sha256: str,
    task_scope_sha256: str,
) -> tuple[dict[str, Any] | None, str]:
    if not re.fullmatch(r"[0-9a-f]{64}", task_scope_sha256):
        return None, "scope_manifest_invalid"
    path = _scope_manifest_path(runtime, session_sha256, task_scope_sha256)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None, "scope_manifest_missing"
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        return None, "scope_manifest_invalid"
    if not isinstance(value, dict):
        return None, "scope_manifest_invalid"
    paths = value.get("changed_paths")
    generation = value.get("generation")
    if (
        value.get("schema_version") != TASK_SCOPE_MANIFEST_SCHEMA_VERSION
        or value.get("codex_session_sha256") != session_sha256
        or value.get("codex_thread_sha256") != thread_sha256
        or value.get("task_scope_id_sha256") != task_scope_sha256
        or value.get("status") not in {"active", "completed"}
        or value.get("task_scope_complete") is not True
        or not isinstance(paths, list)
        or len(paths) > MAX_TASK_PATHS
        or not all(isinstance(item, str) and item for item in paths)
        or not isinstance(generation, int)
        or isinstance(generation, bool)
        or generation <= 0
        or value.get("changed_paths_sha256") != _task_scope_paths_sha256(paths)
    ):
        return None, "scope_manifest_invalid"
    normalized, invalid, truncated = _normalize_changed_paths(paths, runtime.root)
    if invalid or truncated or normalized != paths:
        return None, "scope_manifest_invalid"
    return value, ""


def _fingerprint_failure(
    code: str,
    stage: str,
    *,
    limit: int | None = None,
    observed: int | None = None,
    path: str | None = None,
) -> dict[str, Any]:
    safe_code = code if code in FINGERPRINT_FAILURE_CODES else "capture_unavailable"
    safe_stage = stage if stage in FINGERPRINT_FAILURE_STAGES else "repository_verify"
    result: dict[str, Any] = {"code": safe_code, "stage": safe_stage}
    if isinstance(limit, int) and not isinstance(limit, bool) and limit >= 0:
        result["limit"] = limit
    if isinstance(observed, int) and not isinstance(observed, bool) and observed >= 0:
        result["observed"] = observed
    if path:
        result["path_sha256"] = _digest(path, length=64)
    return result


def _unavailable_fingerprint(
    validation_scope: str,
    *,
    task_path_count: int = 0,
    failure: dict[str, Any] | None = None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "available": False,
        "head": "",
        "worktree_sha256": "",
        "validation_scope": validation_scope,
        "task_path_count": task_path_count,
    }
    detail = failure or _fingerprint_failure(
        "capture_unavailable", "repository_verify"
    )
    result["repo_fingerprint_failure"] = detail["code"]
    result["repo_fingerprint_failure_stage"] = detail["stage"]
    for key in ("limit", "observed", "path_sha256"):
        if key in detail:
            result["repo_fingerprint_failure_{}".format(key)] = detail[key]
    return result


def _public_fingerprint_failure(repo: Any) -> dict[str, Any] | None:
    if not isinstance(repo, dict):
        return None
    code = str(repo.get("repo_fingerprint_failure") or "")
    stage = str(repo.get("repo_fingerprint_failure_stage") or "")
    if code not in FINGERPRINT_FAILURE_CODES or stage not in FINGERPRINT_FAILURE_STAGES:
        return None
    result: dict[str, Any] = {"code": code, "stage": stage}
    for key in ("limit", "observed"):
        value = repo.get("repo_fingerprint_failure_{}".format(key))
        if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
            result[key] = value
    return result


def _read_checkpoint(
    runtime: memory.Runtime, session_sha256: str
) -> dict[str, Any] | None:
    path = _checkpoint_path(runtime, session_sha256)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        return None
    if not isinstance(value, dict) or value.get("schema_version") != SCHEMA_VERSION:
        return None
    if value.get("codex_session_sha256") != session_sha256:
        return None
    return value


def _append_event_unchecked(runtime: memory.Runtime, row: dict[str, Any]) -> None:
    if os.environ.get("CODEX_ROLLOVER_TELEMETRY", "1").strip().lower() in FALSE_VALUES:
        return
    path = _telemetry_path(runtime)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = (_canonical(row) + "\n").encode("utf-8")
    descriptor = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        if fcntl is not None:
            fcntl.flock(descriptor, fcntl.LOCK_EX)
        view = memoryview(data)
        while view:
            written = os.write(descriptor, view)
            view = view[written:]
    finally:
        if fcntl is not None:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def _append_event(runtime: memory.Runtime, row: dict[str, Any]) -> None:
    """Persist observability without making rollover control depend on it."""
    try:
        _append_event_unchecked(runtime, row)
    except Exception as exc:
        if os.environ.get("CODEX_ROLLOVER_DEBUG") == "1":
            print(
                "context rollover telemetry ignored error: {}".format(exc),
                file=sys.stderr,
            )


def _legacy_repo_fingerprint(root: Path) -> dict[str, Any]:
    resolved_root = root.resolve()
    unavailable = _unavailable_fingerprint("legacy_worktree_v1")
    deadline = time.monotonic() + MAX_LEGACY_CAPTURE_SECONDS

    def repository_state() -> tuple[bytes, bytes, bytes] | None:
        def run_git(arguments: Sequence[str], maximum: float) -> bytes:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(arguments, 0)
            return subprocess.run(
                ["git", *arguments],
                cwd=resolved_root,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=min(maximum, remaining),
            ).stdout

        try:
            head = run_git(["rev-parse", "HEAD"], 5).strip()
            status = run_git(
                ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
                8,
            )
            index = run_git(["ls-files", "--stage", "-v", "-z"], 8)
        except (OSError, subprocess.SubprocessError):
            return None
        if (
            not re.fullmatch(rb"[0-9a-f]{40,64}", head)
            or len(status) > MAX_LEGACY_DIRTY_BYTES
            or len(index) > MAX_LEGACY_DIRTY_BYTES
        ):
            return None
        # Skip-worktree, assume-unchanged, conflicts, and other non-H index
        # states can hide worktree changes from status; never trust fallback in
        # their presence.
        if any(raw and not raw.startswith(b"H ") for raw in index.split(b"\0")):
            return None
        return head, status, index

    baseline = repository_state()
    if baseline is None:
        return unavailable
    head, status, index = baseline
    entries = [item for item in status.split(b"\0") if item]
    if len(entries) > MAX_LEGACY_DIRTY_PATHS * 2:
        return unavailable
    paths: list[bytes] = []
    expect_rename_source = False
    for entry in entries:
        if expect_rename_source:
            paths.append(entry)
            expect_rename_source = False
            continue
        if len(entry) >= 4 and entry[2:3] == b" ":
            paths.append(entry[3:])
            expect_rename_source = entry[:1] in {b"R", b"C"} or entry[1:2] in {b"R", b"C"}
        else:
            paths.append(entry)
    unique_paths = sorted(set(paths))
    if len(unique_paths) > MAX_LEGACY_DIRTY_PATHS:
        return unavailable

    def worktree_snapshot() -> dict[bytes, dict[str, Any]] | None:
        captured: dict[bytes, dict[str, Any]] = {}
        remaining = MAX_LEGACY_DIRTY_BYTES
        for raw_path in unique_paths:
            if time.monotonic() > deadline:
                return None
            state = _scoped_worktree_state(
                resolved_root / os.fsdecode(raw_path),
                resolved_root,
                maximum_bytes=remaining,
                failure=legacy_capture_failure,
                byte_limit_failure="legacy_dirty_content_byte_limit",
            )
            if state is None:
                return None
            if state.get("kind") == "regular":
                remaining -= int(state.get("size", 0) or 0)
            captured[raw_path] = state
        return captured

    legacy_capture_failure: dict[str, Any] = {}
    first_worktree = worktree_snapshot()
    second_worktree = worktree_snapshot()
    ending = repository_state()
    if (
        first_worktree is None
        or first_worktree != second_worktree
        or ending != baseline
        or time.monotonic() > deadline
    ):
        if legacy_capture_failure:
            return _unavailable_fingerprint(
                "legacy_worktree_v1", failure=legacy_capture_failure
            )
        return unavailable
    content = hashlib.sha256()
    content.update(b"status\0" + status + b"\0index\0" + index)
    for raw_path in unique_paths:
        content.update(
            b"\0path\0"
            + raw_path
            + b"\0state\0"
            + _canonical(second_worktree[raw_path]).encode("utf-8")
        )
    return {
        "available": True,
        "head": head.decode("ascii", errors="replace"),
        "worktree_sha256": content.hexdigest(),
    }


def _stat_identity(value: os.stat_result) -> tuple[int, int, int, int, int]:
    return (
        value.st_dev,
        value.st_ino,
        value.st_mode,
        value.st_size,
        value.st_mtime_ns,
    )


def _scoped_worktree_state(
    path: Path,
    root: Path,
    *,
    maximum_bytes: int | None = None,
    deadline: float | None = None,
    failure: dict[str, Any] | None = None,
    byte_limit_failure: str = "capture_limit_exceeded",
) -> dict[str, Any] | None:
    """Capture an exact leaf state, returning None when a stable read is unsafe."""
    try:
        relative = path.relative_to(root)
    except ValueError:
        return None
    if not relative.parts:
        return None
    directory_flags = (
        os.O_RDONLY
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    with contextlib.ExitStack() as stack:
        try:
            if deadline is not None and time.monotonic() >= deadline:
                return None
            directory = os.open(root, directory_flags)
            stack.callback(os.close, directory)
            for component in relative.parts[:-1]:
                if deadline is not None and time.monotonic() >= deadline:
                    return None
                directory = os.open(component, directory_flags, dir_fd=directory)
                stack.callback(os.close, directory)
            leaf = relative.parts[-1]
            try:
                before = os.stat(leaf, dir_fd=directory, follow_symlinks=False)
            except FileNotFoundError:
                try:
                    os.stat(leaf, dir_fd=directory, follow_symlinks=False)
                except FileNotFoundError:
                    return {"kind": "missing"}
                except OSError:
                    return None
                return None
        except FileNotFoundError:
            return {"kind": "missing"}
        except OSError:
            return None
        if stat.S_ISLNK(before.st_mode):
            try:
                target = os.readlink(leaf, dir_fd=directory)
                after = os.stat(leaf, dir_fd=directory, follow_symlinks=False)
            except OSError:
                return None
            if _stat_identity(before) != _stat_identity(after):
                return None
            return {
                "kind": "symlink",
                "target_sha256": hashlib.sha256(os.fsencode(target)).hexdigest(),
            }
        if not stat.S_ISREG(before.st_mode):
            return None
        if maximum_bytes is not None and before.st_size > maximum_bytes:
            if failure is not None and not failure:
                failure.update(
                    _fingerprint_failure(
                        byte_limit_failure,
                        "dirty_path_content",
                        limit=max(0, maximum_bytes),
                        observed=before.st_size,
                        path=relative.as_posix(),
                    )
                )
            return None
        flags = (
            os.O_RDONLY
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_NOFOLLOW", 0)
        )
        try:
            descriptor = os.open(leaf, flags, dir_fd=directory)
        except OSError:
            return None
        digest = hashlib.sha256()
        try:
            opened_before = os.fstat(descriptor)
            if not stat.S_ISREG(opened_before.st_mode):
                return None
            while True:
                if deadline is not None and time.monotonic() >= deadline:
                    return None
                chunk = os.read(descriptor, 128 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
            opened_after = os.fstat(descriptor)
        except OSError:
            return None
        finally:
            os.close(descriptor)
        try:
            final = os.stat(leaf, dir_fd=directory, follow_symlinks=False)
        except OSError:
            return None
        if (
            _stat_identity(before) != _stat_identity(opened_before)
            or _stat_identity(opened_before) != _stat_identity(opened_after)
            or _stat_identity(opened_after) != _stat_identity(final)
        ):
            return None
        return {
            "kind": "regular",
            "sha256": digest.hexdigest(),
            "size": final.st_size,
            "executable": bool(final.st_mode & 0o111),
        }


def _git_scope_entries(
    root: Path, head: str, paths: Sequence[str], *, deadline: float
) -> tuple[
    dict[str, dict[str, str]],
    dict[str, list[dict[str, str]]],
    str,
] | None:
    def run(command: list[str]) -> bytes | None:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return None
        try:
            return subprocess.run(
                command,
                cwd=root,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=min(8.0, remaining),
            ).stdout
        except (OSError, subprocess.SubprocessError):
            return None

    tree_output = run(
        ["git", "--literal-pathspecs", "ls-tree", "-z", head, "--", *paths]
    )
    index_output = run(
        [
            "git",
            "--literal-pathspecs",
            "ls-files",
            "--stage",
            "-v",
            "-z",
            "--",
            *paths,
        ]
    )
    status_output = run(
        [
            "git",
            "--literal-pathspecs",
            "status",
            "--porcelain=v2",
            "-z",
            "--untracked-files=all",
            "--",
            *paths,
        ]
    )
    if tree_output is None or index_output is None or status_output is None:
        return None
    wanted = set(paths)
    tree: dict[str, dict[str, str]] = {}
    for raw in tree_output.split(b"\0"):
        if not raw:
            continue
        metadata, separator, raw_path = raw.partition(b"\t")
        fields = metadata.split()
        path = os.fsdecode(raw_path)
        if not separator or len(fields) != 3 or path not in wanted:
            return None
        tree[path] = {
            "mode": fields[0].decode("ascii", errors="strict"),
            "type": fields[1].decode("ascii", errors="strict"),
            "object": fields[2].decode("ascii", errors="strict"),
        }
    index: dict[str, list[dict[str, str]]] = {path: [] for path in paths}
    try:
        for raw in index_output.split(b"\0"):
            if not raw:
                continue
            metadata, separator, raw_path = raw.partition(b"\t")
            fields = metadata.split()
            path = os.fsdecode(raw_path)
            if not separator or len(fields) != 4 or path not in wanted:
                return None
            index[path].append(
                {
                    "tag": fields[0].decode("ascii", errors="strict"),
                    "mode": fields[1].decode("ascii", errors="strict"),
                    "object": fields[2].decode("ascii", errors="strict"),
                    "stage": fields[3].decode("ascii", errors="strict"),
                }
            )
    except UnicodeDecodeError:
        return None
    for entries in index.values():
        entries.sort(
            key=lambda item: (
                item["stage"],
                item["tag"],
                item["mode"],
                item["object"],
            )
        )
    return tree, index, hashlib.sha256(status_output).hexdigest()


def _task_scope_fingerprint(
    root: Path,
    paths: Sequence[str],
    *,
    task_scope_sha256: str = "",
) -> dict[str, Any]:
    resolved_root = root.resolve()
    deadline = time.monotonic() + MAX_TASK_CAPTURE_SECONDS
    unavailable = _unavailable_fingerprint(
        "task_paths_v1", task_path_count=len(paths)
    )
    if len(paths) > MAX_TASK_PATHS:
        return unavailable
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        return unavailable
    try:
        head = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=resolved_root,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=min(5.0, remaining),
        ).stdout.decode("ascii", errors="strict").strip()
    except (OSError, subprocess.SubprocessError, UnicodeDecodeError):
        head = ""
    unavailable["head"] = head
    if not re.fullmatch(r"[0-9a-f]{40,64}", head):
        return unavailable
    if not paths:
        try:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return unavailable
            ending_head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=resolved_root,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=min(5.0, remaining),
            ).stdout.decode("ascii", errors="strict").strip()
        except (OSError, subprocess.SubprocessError, UnicodeDecodeError):
            return unavailable
        if ending_head != head:
            return unavailable
        empty_status_sha256 = hashlib.sha256(b"").hexdigest()
        scope_state: dict[str, Any] = {
            "task_paths": [],
            "git_status_sha256": empty_status_sha256,
        }
        if task_scope_sha256:
            scope_state["task_scope_id_sha256"] = task_scope_sha256
        result = {
            "available": True,
            "head": head,
            "worktree_sha256": hashlib.sha256(
                _canonical(scope_state).encode("utf-8")
            ).hexdigest(),
            "validation_scope": "task_paths_v1",
            "task_path_count": 0,
            "task_paths": [],
            "git_status_sha256": empty_status_sha256,
        }
        if task_scope_sha256:
            result["task_scope_id_sha256"] = task_scope_sha256
        return result
    entries = _git_scope_entries(resolved_root, head, paths, deadline=deadline)
    if entries is None:
        return unavailable
    tree, index_before, status_before = entries

    def worktree_snapshot() -> dict[str, dict[str, Any]] | None:
        captured: dict[str, dict[str, Any]] = {}
        remaining_bytes = MAX_TASK_SCOPE_BYTES
        for relative in paths:
            if time.monotonic() >= deadline:
                return None
            state = _scoped_worktree_state(
                resolved_root / relative,
                resolved_root,
                maximum_bytes=remaining_bytes,
                deadline=deadline,
            )
            if state is None:
                return None
            if state.get("kind") == "regular":
                remaining_bytes -= int(state.get("size", 0) or 0)
            captured[relative] = state
        return captured

    first_worktree = worktree_snapshot()
    second_worktree = worktree_snapshot()
    if first_worktree is None or first_worktree != second_worktree:
        return unavailable
    ending_entries = _git_scope_entries(
        resolved_root, head, paths, deadline=deadline
    )
    if (
        ending_entries is None
        or ending_entries[1] != index_before
        or ending_entries[2] != status_before
    ):
        return unavailable
    try:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return unavailable
        ending_head = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=resolved_root,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=min(5.0, remaining),
        ).stdout.decode("ascii", errors="strict").strip()
    except (OSError, subprocess.SubprocessError, UnicodeDecodeError):
        return unavailable
    if ending_head != head:
        return unavailable
    task_paths = []
    for relative in sorted(paths):
        task_paths.append(
            {
                "path_sha256": hashlib.sha256(
                    relative.encode("utf-8", errors="surrogateescape")
                ).hexdigest(),
                "head": tree.get(relative, {"kind": "missing"}),
                "index": index_before.get(relative, []),
                "worktree": second_worktree[relative],
            }
        )
    scope_state = {
        "task_paths": task_paths,
        "git_status_sha256": status_before,
    }
    if task_scope_sha256:
        scope_state["task_scope_id_sha256"] = task_scope_sha256
    result = {
        "available": True,
        "head": head,
        "worktree_sha256": hashlib.sha256(
            _canonical(scope_state).encode("utf-8")
        ).hexdigest(),
        "validation_scope": "task_paths_v1",
        "task_path_count": len(task_paths),
        "task_paths": task_paths,
        "git_status_sha256": status_before,
    }
    if task_scope_sha256:
        result["task_scope_id_sha256"] = task_scope_sha256
    return result


def _repo_fingerprint(
    root: Path,
    changed_paths: Sequence[str] | None = None,
    *,
    allow_all_missing: bool = False,
    task_scope_sha256: str = "",
) -> dict[str, Any]:
    if changed_paths is not None:
        normalized, invalid, truncated = _normalize_changed_paths(changed_paths, root)
        if (
            invalid
            or truncated
            or not all(isinstance(path, str) for path in changed_paths)
            or len(normalized) != len(changed_paths)
        ):
            return _unavailable_fingerprint(
                "task_paths_v1",
                task_path_count=len(normalized),
                failure=_fingerprint_failure("scope_invalid", "scope_input"),
            )
        scoped = _task_scope_fingerprint(
            root, normalized, task_scope_sha256=task_scope_sha256
        )
        if scoped.get("available") and not allow_all_missing:
            task_paths = scoped.get("task_paths")
            all_missing = bool(task_paths) and all(
                isinstance(item, dict)
                and item.get("head") == {"kind": "missing"}
                and item.get("index") == []
                and item.get("worktree") == {"kind": "missing"}
                for item in task_paths
            )
            if all_missing:
                legacy = _legacy_repo_fingerprint(root)
                return {
                    **legacy,
                    "validation_scope": "legacy_worktree_v1",
                    "task_path_count": 0,
                }
        return scoped
    legacy = _legacy_repo_fingerprint(root)
    return {
        **legacy,
        "validation_scope": "legacy_worktree_v1",
        "task_path_count": 0,
    }


def _section(text: str, title: str) -> str:
    lines = text.splitlines()
    wanted = title.strip().lower()
    start: int | None = None
    for index, line in enumerate(lines):
        match = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if not match:
            continue
        heading = re.sub(r"\s+#+$", "", match.group(2)).strip().lower()
        if start is None:
            if heading == wanted:
                start = index + 1
            continue
        if len(match.group(1)) <= 2:
            return "\n".join(lines[start:index])[:MAX_SECTION_CHARS]
    return "\n".join(lines[start:])[:MAX_SECTION_CHARS] if start is not None else ""


def _split_table_row(line: str) -> list[str]:
    value = line.strip()
    if not value.startswith("|"):
        return []
    value = value[1:]
    if value.endswith("|"):
        value = value[:-1]
    cells: list[str] = []
    current: list[str] = []
    escaped = False
    for char in value:
        if escaped:
            current.append(char)
            escaped = False
        elif char == "\\":
            escaped = True
            current.append(char)
        elif char == "|":
            cells.append("".join(current).strip())
            current = []
        else:
            current.append(char)
    cells.append("".join(current).strip())
    return cells


def _column_name(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def _latest_progress_row(section: str) -> dict[str, str]:
    rows = _progress_rows(section)
    for row in reversed(rows):
        phase = next(
            (
                value.strip().lower()
                for key, value in row.items()
                if key == "phase" or key.startswith("phase ")
            ),
            "",
        )
        if phase not in PLACEHOLDERS and not phase.startswith("<"):
            return row
    return {}


def _progress_rows(section: str) -> list[dict[str, str]]:
    """Return every bounded Execution Progress row in document order."""
    lines = section.splitlines()
    result: list[dict[str, str]] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        header = _split_table_row(line)
        normalized = [_column_name(cell) for cell in header]
        if not any(name.startswith("phase") for name in normalized) or not any(
            name.startswith("next") for name in normalized
        ):
            index += 1
            continue
        if index + 1 >= len(lines) or not re.match(r"^\s*\|?\s*:?-{3,}", lines[index + 1]):
            index += 1
            continue
        rows: list[list[str]] = []
        cursor = index + 2
        while cursor < len(lines):
            candidate = lines[cursor]
            cells = _split_table_row(candidate)
            if not cells:
                break
            if len(cells) < len(header):
                cells.extend([""] * (len(header) - len(cells)))
            rows.append(cells[: len(header)])
            cursor += 1
        result.extend(
            {
                normalized[position]: cells[position]
                for position in range(len(header))
            }
            for cells in rows
        )
        index = max(cursor, index + 1)
    return result


def _field(row: dict[str, str], *names: str) -> str:
    for wanted in names:
        for key, value in row.items():
            if key == wanted or key.startswith(wanted + " "):
                return value
    return ""


def _graph_pair(text: str) -> tuple[str, str]:
    events: list[tuple[int, str, str]] = []
    events.extend((match.start(), "query", match.group(1).lower()) for match in QUERY_ANCHOR.finditer(text))
    events.extend(
        (match.start(), "evidence", match.group(1).lower())
        for match in EVIDENCE_ANCHOR.finditer(text)
    )
    query = ""
    pairs: list[tuple[str, str]] = []
    for _position, kind, value in sorted(events):
        if kind == "query":
            query = value
        elif query:
            pairs.append((query, value))
    return pairs[-1] if pairs else ("", "")


def _test_ids(text: str) -> list[str]:
    return _dedupe(
        match.group(0).upper().replace("_", "-").replace(" ", "-")
        for match in TEST_ANCHOR.finditer(text)
    )


def _gate_ids(text: str) -> list[str]:
    values = [match.group(1) for match in GATE_COMMAND.finditer(text)]
    for match in re.finditer(r"`([A-Za-z0-9_.-]*(?:host-all|feature-host-all|core-host-all))`", text, re.I):
        values.append(match.group(1))
    return _dedupe(values)


def _changed_paths(value: str, root: Path) -> tuple[list[str], bool, bool]:
    candidates: list[tuple[str, bool]] = []
    masked = list(value)
    for match in re.finditer(r"`([^`]+)`", value):
        candidate = match.group(1).strip()
        # Plan tables are not a shell parser. Multiword backticks are commonly
        # commands or prose; unusual filenames must be declared explicitly via
        # repeated --changed-path instead of becoming a guessed task scope.
        if candidate and not any(char.isspace() for char in candidate):
            candidates.append((candidate, True))
        for index in range(match.start(), match.end()):
            masked[index] = " "
    candidates.extend(
        (match.group(0), False)
        for match in PATH_ANCHOR.finditer("".join(masked))
    )
    raw_paths: list[str] = []
    invalid = False
    for candidate, explicitly_delimited in candidates:
        for part in re.split(r"\s*,\s*|\s+and\s+", candidate):
            cleaned = part.strip().strip("`'\"()[]{}:;,")
            if not explicitly_delimited and "/" not in cleaned:
                continue
            raw_paths.append(cleaned)
    normalized, rejected, truncated = _normalize_changed_paths(raw_paths, root)
    invalid = invalid or rejected
    return normalized, invalid, truncated


def _normalize_changed_paths(
    values: Iterable[str], root: Path
) -> tuple[list[str], bool, bool]:
    """Return literal repo-relative leaves, rejected-input, and overflow flags."""
    result: list[str] = []
    invalid = False
    truncated = False
    lexical_root = Path(os.path.abspath(os.fspath(root)))
    resolved_root = root.resolve()
    for raw in values:
        candidate = str(raw or "").strip()
        if (
            not candidate
            or len(candidate) > 512
            or any(char in candidate for char in "*?[\n\r\x00")
            or candidate in {".", ".."}
        ):
            invalid = True
            continue
        path = Path(candidate).expanduser()
        try:
            if ".." in path.parts:
                raise ValueError("parent traversal is not a stable task path")
            if path.is_absolute():
                absolute = Path(os.path.abspath(os.fspath(path)))
                try:
                    relative = absolute.relative_to(lexical_root)
                except ValueError:
                    relative = absolute.relative_to(resolved_root)
                literal = resolved_root / relative
            else:
                literal = resolved_root / path
                relative = literal.relative_to(resolved_root)
            parent = resolved_root
            for component in relative.parts[:-1]:
                parent = parent / component
                if parent.is_symlink():
                    raise ValueError("symlink parent is not a stable task path")
        except (OSError, ValueError):
            invalid = True
            continue
        normalized = relative.as_posix()
        if normalized and normalized not in result:
            if len(result) >= MAX_TASK_PATHS:
                truncated = True
                continue
            result.append(normalized)
    return result, invalid, truncated


def _known_plan_paths(root: Path, paths: Sequence[str]) -> list[str] | None:
    """Filter heuristic plan paths to leaves evidenced by Git or the worktree."""
    if not paths:
        return []
    known: set[str] = set()
    missing: list[str] = []
    for relative in paths:
        try:
            (root / relative).lstat()
        except FileNotFoundError:
            missing.append(relative)
        except OSError:
            return None
        else:
            known.add(relative)
    if missing:
        try:
            index_output = subprocess.run(
                [
                    "git",
                    "--literal-pathspecs",
                    "ls-files",
                    "-z",
                    "--cached",
                    "--",
                    *missing,
                ],
                cwd=root,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=8,
            ).stdout
            tree_output = subprocess.run(
                [
                    "git",
                    "--literal-pathspecs",
                    "ls-tree",
                    "--name-only",
                    "-z",
                    "HEAD",
                    "--",
                    *missing,
                ],
                cwd=root,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=8,
            ).stdout
        except (OSError, subprocess.SubprocessError):
            return None
        known.update(
            os.fsdecode(raw)
            for output in (index_output, tree_output)
            for raw in output.split(b"\0")
            if raw
        )
    return [path for path in paths if path in known]


def _placeholder(value: str) -> bool:
    normalized = _clean_text(value, 240).lower()
    return normalized in PLACEHOLDERS or normalized.startswith("<")


def plan_snapshot(plan_path: Path | str, runtime: memory.Runtime) -> dict[str, Any]:
    """Extract only bounded execution-continuity anchors from one named plan."""
    path = Path(plan_path).expanduser()
    if not path.is_absolute():
        path = runtime.root / path
    path = path.resolve()
    try:
        relative = str(path.relative_to(runtime.root.resolve()))
    except (OSError, ValueError) as exc:
        raise ValueError("plan_outside_repo") from exc
    try:
        size = path.stat().st_size
    except OSError as exc:
        raise ValueError("plan_missing") from exc
    if size > MAX_PLAN_BYTES:
        raise ValueError("plan_too_large")
    text = path.read_text(encoding="utf-8")
    progress = _section(text, "Execution Progress")
    row = _latest_progress_row(progress)
    phase = _clean_text(_field(row, "phase"), 160)
    next_action = _clean_text(_field(row, "next", "next action"), 800)
    evidence = _clean_text(_field(row, "current evidence", "evidence"), 700)
    blocker = _clean_text(_field(row, "decision blocker", "decision", "blocker"), 500)
    changed_paths: list[str] = []
    changed_path_invalid = False
    changed_path_truncated = len(progress) >= MAX_SECTION_CHARS
    for progress_row in _progress_rows(progress):
        files = _field(progress_row, "files", "changed files", "paths")
        extracted, invalid, truncated = _changed_paths(files, runtime.root)
        changed_path_invalid = changed_path_invalid or invalid
        changed_path_truncated = changed_path_truncated or truncated
        for changed_path in extracted:
            if changed_path in changed_paths:
                continue
            if len(changed_paths) >= MAX_TASK_PATHS:
                changed_path_truncated = True
                continue
            changed_paths.append(changed_path)
    known_changed_paths = _known_plan_paths(runtime.root, changed_paths)
    changed_path_lookup_unavailable = known_changed_paths is None
    if known_changed_paths is not None:
        changed_paths = known_changed_paths
    graph_text = progress or ""
    query_id, evidence_digest = _graph_pair(graph_text)
    if not query_id:
        graph_snapshot = _section(text, "Graph Grounding Snapshot")
        if not graph_snapshot:
            graph_snapshot = _section(text, "Graph Grounding Snapshots")
        query_id, evidence_digest = _graph_pair(graph_snapshot)
    planned_tests = _test_ids(text)
    observed_tests = set(_test_ids(progress))
    tests = [
        {"id": value, "status": "observed" if value in observed_tests else "planned"}
        for value in planned_tests
    ]
    gate_ids = _gate_ids(text)
    observed_gates = set(_gate_ids(progress))
    gates = [
        {"id": value, "status": "observed" if value in observed_gates else "planned"}
        for value in gate_ids
    ]
    return {
        "plan": {
            "status": "tracked",
            "relative_path": relative,
            "sha256": _file_sha256(path),
        },
        "phase": {"id": phase},
        "tests": tests,
        "gates": gates,
        "graphify": {
            "status": "grounded" if query_id and evidence_digest else "",
            "query_id": query_id,
            "evidence_digest": evidence_digest,
        },
        "changed_paths": changed_paths,
        "plan_changed_paths": list(changed_paths),
        "explicit_changed_paths": [],
        "task_scope_complete": False,
        "current_evidence": evidence,
        "blocker": blocker,
        "next_action": next_action,
        "input_reason_codes": [
            *(["changed_path_outside_repo"] if changed_path_invalid else []),
            *(["changed_path_limit_exceeded"] if changed_path_truncated else []),
            *(
                ["repo_fingerprint_unavailable"]
                if changed_path_lookup_unavailable
                else []
            ),
        ],
    }


def _parse_anchor_values(values: Sequence[str] | None, *, default_status: str) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    positions: dict[str, int] = {}
    for raw in values or []:
        identifier, separator, status = raw.partition("=")
        identifier = _clean_text(identifier, 180)
        status = _clean_text(status if separator else default_status, 40).lower()
        if not identifier:
            continue
        item = {"id": identifier, "status": status or default_status}
        if identifier in positions:
            result[positions[identifier]] = item
        else:
            positions[identifier] = len(result)
            result.append(item)
        if len(result) >= MAX_LIST_ITEMS:
            break
    return result


def _merge_anchors(
    original: list[dict[str, str]], overrides: Sequence[str] | None, *, default_status: str
) -> list[dict[str, str]]:
    values = [dict(item) for item in original if isinstance(item, dict)]
    positions = {str(item.get("id")): index for index, item in enumerate(values)}
    for item in _parse_anchor_values(overrides, default_status=default_status):
        if item["id"] in positions:
            values[positions[item["id"]]] = item
        else:
            positions[item["id"]] = len(values)
            values.append(item)
    return values[:MAX_LIST_ITEMS]


def _empty_snapshot() -> dict[str, Any]:
    return {
        "plan": {"status": "", "relative_path": "", "sha256": ""},
        "phase": {"id": ""},
        "tests": [],
        "gates": [],
        "graphify": {"status": "", "query_id": "", "evidence_digest": ""},
        "changed_paths": [],
        "plan_changed_paths": [],
        "explicit_changed_paths": [],
        "task_scope_complete": False,
        "_task_scope_id": "",
        "current_evidence": "",
        "blocker": "",
        "next_action": "",
        "input_reason_codes": [],
    }


def _apply_overrides(
    snapshot: dict[str, Any], args: argparse.Namespace, root: Path
) -> dict[str, Any]:
    plan = dict(snapshot.get("plan", {}))
    if getattr(args, "plan_status", None):
        plan["status"] = args.plan_status
        if args.plan_status == "not-applicable":
            plan["relative_path"] = ""
            plan["sha256"] = ""
    snapshot["plan"] = plan
    if getattr(args, "phase_id", None):
        snapshot["phase"] = {"id": _clean_text(args.phase_id, 160)}
    if getattr(args, "next_action", None):
        snapshot["next_action"] = _clean_text(args.next_action, 800)
    snapshot["tests"] = _merge_anchors(
        list(snapshot.get("tests", [])), getattr(args, "test", None), default_status="observed"
    )
    snapshot["gates"] = _merge_anchors(
        list(snapshot.get("gates", [])), getattr(args, "gate", None), default_status="observed"
    )
    graphify = dict(snapshot.get("graphify", {}))
    if getattr(args, "graph_status", None):
        graphify["status"] = args.graph_status
    if getattr(args, "graph_query_id", None):
        graphify["query_id"] = str(args.graph_query_id).lower()
    if getattr(args, "graph_evidence_digest", None):
        graphify["evidence_digest"] = str(args.graph_evidence_digest).lower()
    if graphify.get("query_id") and graphify.get("evidence_digest") and not graphify.get("status"):
        graphify["status"] = "grounded"
    snapshot["graphify"] = graphify
    changed = list(snapshot.get("changed_paths", []))
    overrides, invalid, truncated = _normalize_changed_paths(
        getattr(args, "changed_path", None) or [], root
    )
    for path in overrides:
        if path in changed:
            continue
        if len(changed) >= MAX_TASK_PATHS:
            truncated = True
            continue
        changed.append(path)
    snapshot["changed_paths"] = changed
    explicit_paths = list(snapshot.get("explicit_changed_paths", []))
    for path in overrides:
        if path not in explicit_paths:
            explicit_paths.append(path)
    snapshot["explicit_changed_paths"] = explicit_paths
    snapshot["task_scope_complete"] = bool(
        getattr(args, "task_scope_complete", False)
    )
    raw_task_scope_id = str(getattr(args, "task_scope_id", None) or "").strip()
    snapshot["_task_scope_id"] = raw_task_scope_id
    reasons = list(snapshot.get("input_reason_codes", []))
    if invalid:
        reasons.append("changed_path_outside_repo")
    if truncated:
        reasons.append("changed_path_limit_exceeded")
    snapshot["input_reason_codes"] = _dedupe(reasons, limit=8)
    return snapshot


def _checkpoint_bytes(runtime: memory.Runtime, checkpoint: dict[str, Any] | None) -> int:
    if checkpoint is None:
        return 0
    path = _checkpoint_path(runtime, str(checkpoint.get("codex_session_sha256") or "unknown"))
    try:
        return path.stat().st_size
    except OSError:
        return len((_canonical(checkpoint) + "\n").encode("utf-8"))


def _intent_binding(checkpoint: dict[str, Any]) -> str:
    """Hash immutable continuation fields without recursively hashing the intent."""
    fields = {
                "schema_version": checkpoint.get("schema_version"),
                "codex_session_sha256": checkpoint.get("codex_session_sha256"),
                "codex_thread_sha256": checkpoint.get("codex_thread_sha256"),
                "generation": checkpoint.get("generation"),
                "plan": checkpoint.get("plan"),
                "phase": checkpoint.get("phase"),
                "tests": checkpoint.get("tests"),
                "gates": checkpoint.get("gates"),
                "graphify": checkpoint.get("graphify"),
                "changed_paths": checkpoint.get("changed_paths"),
                "task_scope_complete": checkpoint.get("task_scope_complete"),
                "input_reason_codes": checkpoint.get("input_reason_codes"),
                "current_evidence": checkpoint.get("current_evidence"),
                "blocker": checkpoint.get("blocker"),
                "next_action": checkpoint.get("next_action"),
                "outstanding_work": checkpoint.get("outstanding_work"),
                "repo": checkpoint.get("repo"),
    }
    # Keep legacy intent digests byte-for-byte compatible when the optional
    # plan-less task binding is absent.
    for key in ("task_scope_id_sha256", "task_scope_manifest_sha256"):
        if key in checkpoint:
            fields[key] = checkpoint.get(key)
    return _digest(_canonical(fields))


def _rollover_intent_reasons(
    checkpoint: dict[str, Any] | None,
    *,
    session_sha256: str,
    thread_sha256: str,
    now: dt.datetime,
) -> list[str]:
    if checkpoint is None:
        return ["rollover_intent_missing"]
    intent = checkpoint.get("continuation_intent")
    if not isinstance(intent, dict) or intent.get("mode") != "prepared_rollover":
        return ["rollover_intent_missing"]
    reasons: list[str] = []
    armed_at = _parse_time(intent.get("armed_at"))
    if (
        armed_at is None
        or (now - armed_at).total_seconds() > _prepared_max_age_seconds()
    ):
        reasons.append("rollover_intent_stale")
    repo = checkpoint.get("repo")
    repo_worktree = str(repo.get("worktree_sha256") or "") if isinstance(repo, dict) else ""
    intent_generation = intent.get("generation")
    checkpoint_generation = checkpoint.get("generation")
    if (
        intent.get("codex_session_sha256") != session_sha256
        or intent.get("codex_thread_sha256") != thread_sha256
        or not isinstance(intent_generation, int)
        or isinstance(intent_generation, bool)
        or not isinstance(checkpoint_generation, int)
        or isinstance(checkpoint_generation, bool)
        or intent_generation != checkpoint_generation
        or intent.get("worktree_sha256") != repo_worktree
        or intent.get("checkpoint_binding_sha256") != _intent_binding(checkpoint)
    ):
        reasons.append("rollover_intent_mismatch")
    return sorted(set(reasons))


def _advisory_reset_pending(
    checkpoint: dict[str, Any] | None,
    *,
    session_sha256: str,
    thread_sha256: str,
    now: dt.datetime,
) -> bool:
    if checkpoint is None:
        return False
    marker = checkpoint.get("advisory_reset")
    if not isinstance(marker, dict):
        return False
    requested_at = _parse_time(marker.get("requested_at"))
    generation = checkpoint.get("generation")
    marker_generation = marker.get("generation")
    age_seconds = (
        (now - requested_at).total_seconds() if requested_at is not None else -1
    )
    return bool(
        marker.get("mode") == "recovery_advisory"
        and marker.get("status") == "pending"
        and -5 <= age_seconds <= _prepared_max_age_seconds()
        and isinstance(generation, int)
        and not isinstance(generation, bool)
        and isinstance(marker_generation, int)
        and not isinstance(marker_generation, bool)
        and marker_generation == generation
        and marker.get("codex_session_sha256") == session_sha256
        and marker.get("codex_thread_sha256") == thread_sha256
        and marker.get("checkpoint_binding_sha256") == _intent_binding(checkpoint)
    )


def _not_ready_liveness_marker(
    checkpoint: dict[str, Any] | None,
    *,
    session_sha256: str,
    thread_sha256: str,
) -> dict[str, Any] | None:
    """Return a privacy-safe cross-generation NOT_READY episode marker."""
    if checkpoint is None:
        return None
    marker = checkpoint.get("not_ready_liveness")
    if not isinstance(marker, dict):
        return None
    generation = checkpoint.get("generation")
    opened_generation = marker.get("opened_generation")
    if not (
        marker.get("mode") == "not_ready_liveness"
        and marker.get("status")
        in {"pending", "transitioned", "terminal", "completed"}
        and re.fullmatch(
            r"[0-9a-f]{16,64}", str(marker.get("episode_sha256") or "")
        )
        and isinstance(generation, int)
        and not isinstance(generation, bool)
        and isinstance(opened_generation, int)
        and not isinstance(opened_generation, bool)
        and 0 < opened_generation <= generation
        and marker.get("codex_session_sha256") == session_sha256
        and marker.get("codex_thread_sha256") == thread_sha256
    ):
        return None
    return marker


def _not_ready_liveness_pending(
    checkpoint: dict[str, Any] | None,
    *,
    session_sha256: str,
    thread_sha256: str,
) -> bool:
    marker = _not_ready_liveness_marker(
        checkpoint,
        session_sha256=session_sha256,
        thread_sha256=thread_sha256,
    )
    return bool(marker is not None and marker.get("status") == "pending")


def _validation_reasons(
    checkpoint: dict[str, Any] | None,
    runtime: memory.Runtime,
    *,
    now: dt.datetime,
    require_precompact: bool = False,
    require_fresh_generation: bool = False,
    compare_repo: bool = True,
) -> list[str]:
    if checkpoint is None:
        return ["checkpoint_missing"]
    reasons: list[str] = []
    input_reasons = checkpoint.get("input_reason_codes")
    if isinstance(input_reasons, list):
        reasons.extend(
            reason
            for reason in input_reasons
            if isinstance(reason, str)
            and reason
            in {
                "changed_path_outside_repo",
                "changed_path_limit_exceeded",
                "repo_fingerprint_unavailable",
                "task_scope_id_invalid",
                "plan_missing",
                "plan_outside_repo",
                "plan_too_large",
                "plan_extraction_failed",
                "plan_read_failed",
            }
        )
    if checkpoint.get("schema_version") != SCHEMA_VERSION:
        reasons.append("checkpoint_schema_mismatch")
    if checkpoint.get("status") == "completed":
        reasons.append("checkpoint_completed")
    saved_at = _parse_time(checkpoint.get("saved_at"))
    if saved_at is None:
        reasons.append("saved_at_missing")
    elif (now - saved_at).total_seconds() > _max_age_seconds():
        reasons.append("checkpoint_age_exceeded")
    plan = checkpoint.get("plan")
    plan_status = str(plan.get("status") or "") if isinstance(plan, dict) else ""
    if plan_status not in {"tracked", "not-applicable"}:
        reasons.append("plan_status_missing")
    elif plan_status == "tracked" and isinstance(plan, dict):
        relative = str(plan.get("relative_path") or "")
        sha256 = str(plan.get("sha256") or "")
        if not relative or not re.fullmatch(r"[0-9a-f]{64}", sha256):
            reasons.append("plan_missing")
        else:
            try:
                path = (runtime.root / relative).resolve()
                path.relative_to(runtime.root.resolve())
            except (OSError, ValueError):
                reasons.append("plan_outside_repo")
            else:
                if not path.is_file():
                    reasons.append("plan_missing")
                else:
                    try:
                        current_sha = _file_sha256(path)
                    except OSError:
                        current_sha = ""
                    if current_sha != sha256:
                        reasons.append("plan_changed")
    phase = checkpoint.get("phase")
    phase_id = str(phase.get("id") or "") if isinstance(phase, dict) else ""
    if _placeholder(phase_id):
        reasons.append("phase_missing")
    if _placeholder(str(checkpoint.get("next_action") or "")):
        reasons.append("next_action_missing")
    tests = checkpoint.get("tests")
    gates = checkpoint.get("gates")
    if (
        plan_status == "tracked"
        and (not isinstance(tests, list) or not isinstance(gates, list) or not (tests or gates))
    ):
        reasons.append("test_and_gate_anchors_missing")
    # Older checkpoints can retain graph metadata for historical inspection.
    # Code navigation no longer depends on a graph query or evidence digest.
    outstanding = str(checkpoint.get("outstanding_work") or "")
    if outstanding not in {"none", "completed", "running"}:
        reasons.append("outstanding_work_missing")
    elif outstanding == "running":
        reasons.append("outstanding_work_running")
    repo = checkpoint.get("repo")
    if not isinstance(repo, dict) or not repo.get("available"):
        reasons.append("repo_fingerprint_unavailable")
    elif compare_repo:
        validation_scope = str(repo.get("validation_scope") or "")
        saved_paths = checkpoint.get("changed_paths")
        if validation_scope == "task_paths_v1":
            task_paths = repo.get("task_paths")
            task_scope_id_sha256 = str(
                checkpoint.get("task_scope_id_sha256") or ""
            ).lower()
            bound_scope = bool(
                re.fullmatch(r"[0-9a-f]{64}", task_scope_id_sha256)
            )
            manifest_valid = True
            if bound_scope:
                manifest, _manifest_failure = _read_scope_manifest(
                    runtime,
                    session_sha256=str(
                        checkpoint.get("codex_session_sha256") or ""
                    ),
                    thread_sha256=str(
                        checkpoint.get("codex_thread_sha256") or ""
                    ),
                    task_scope_sha256=task_scope_id_sha256,
                )
                manifest_valid = bool(
                    manifest is not None
                    and manifest.get("status") == "active"
                    and manifest.get("changed_paths") == saved_paths
                    and checkpoint.get("task_scope_manifest_sha256")
                    == _scope_manifest_digest(manifest)
                    and repo.get("task_scope_id_sha256")
                    == task_scope_id_sha256
                )
            valid_scope = (
                isinstance(saved_paths, list)
                and 0 <= len(saved_paths) <= MAX_TASK_PATHS
                and (bool(saved_paths) or bound_scope)
                and checkpoint.get("task_scope_complete") is True
                and manifest_valid
                and all(isinstance(path, str) and path for path in saved_paths)
                and repo.get("task_path_count") == len(saved_paths)
                and re.fullmatch(
                    r"[0-9a-f]{64}",
                    str(repo.get("git_status_sha256") or ""),
                )
                and isinstance(task_paths, list)
                and len(task_paths) == len(saved_paths)
                and all(
                    isinstance(item, dict)
                    and re.fullmatch(
                        r"[0-9a-f]{64}", str(item.get("path_sha256") or "")
                    )
                    for item in task_paths
                )
            )
            current = (
                _repo_fingerprint(
                    runtime.root,
                    saved_paths,
                    allow_all_missing=True,
                    task_scope_sha256=(
                        task_scope_id_sha256 if bound_scope else ""
                    ),
                )
                if valid_scope
                else {
                    "available": False,
                    "head": "",
                    "worktree_sha256": "",
                }
            )
        elif validation_scope in {"", "legacy_worktree_v1"}:
            # Schema-v1 checkpoints created before task_paths_v1 carried only
            # the whole-worktree digest. Preserve that conservative behavior.
            current = _repo_fingerprint(runtime.root)
        else:
            current = {
                "available": False,
                "head": "",
                "worktree_sha256": "",
            }
        if not current.get("available"):
            reasons.append("repo_fingerprint_unavailable")
        else:
            if current.get("head") != repo.get("head"):
                reasons.append("repo_head_changed")
            if current.get("worktree_sha256") != repo.get("worktree_sha256"):
                reasons.append(
                    "task_scope_changed"
                    if validation_scope == "task_paths_v1"
                    else "worktree_changed"
                )
    generation = int(checkpoint.get("generation", 0) or 0)
    injected = int(checkpoint.get("last_injected_generation", 0) or 0)
    if require_fresh_generation and generation <= injected:
        reasons.append("checkpoint_already_consumed")
    if require_precompact:
        prepared = checkpoint.get("precompact")
        if not isinstance(prepared, dict):
            reasons.append("prepared_checkpoint_missing")
        else:
            prepared_at = _parse_time(prepared.get("at"))
            if prepared_at is None or (now - prepared_at).total_seconds() > _prepared_max_age_seconds():
                reasons.append("prepared_checkpoint_stale")
            if int(prepared.get("generation", -1)) != generation:
                reasons.append("prepared_generation_mismatch")
            if isinstance(repo, dict) and prepared.get("worktree_sha256") != repo.get("worktree_sha256"):
                reasons.append("prepared_generation_mismatch")
    return sorted(set(reasons))


def _safe_public_status(
    checkpoint: dict[str, Any] | None,
    runtime: memory.Runtime,
    *,
    now: dt.datetime,
    compare_repo: bool = True,
) -> dict[str, Any]:
    reasons = _validation_reasons(
        checkpoint,
        runtime,
        now=now,
        require_fresh_generation=True,
        compare_repo=compare_repo,
    )
    if checkpoint is None:
        return {
            "ready": False,
            "reason_codes": reasons,
            "checkpoint_bytes": 0,
            "checkpoint_tokens_estimate": 0,
        }
    rendered = _render_context(checkpoint)
    result = {
        "ready": not reasons,
        "reason_codes": reasons,
        "codex_session_sha256": str(checkpoint.get("codex_session_sha256") or ""),
        "codex_thread_sha256": str(checkpoint.get("codex_thread_sha256") or ""),
        "checkpoint_sha256": _digest(_canonical(checkpoint)),
        "plan_sha256": str(checkpoint.get("plan", {}).get("sha256") or ""),
        "phase_sha256": _digest(str(checkpoint.get("phase", {}).get("id") or "")),
        "generation": int(checkpoint.get("generation", 0) or 0),
        "checkpoint_bytes": _checkpoint_bytes(runtime, checkpoint),
        "checkpoint_tokens_estimate": _token_estimate(rendered),
        "test_anchor_count": len(checkpoint.get("tests", [])),
        "gate_anchor_count": len(checkpoint.get("gates", [])),
        "changed_path_count": len(checkpoint.get("changed_paths", [])),
        "repo_scope": str(checkpoint.get("repo", {}).get("validation_scope") or ""),
        "task_scope_complete": checkpoint.get("task_scope_complete") is True,
    }
    scope_id = str(checkpoint.get("task_scope_id_sha256") or "").lower()
    if re.fullmatch(r"[0-9a-f]{64}", scope_id):
        result["task_scope_id_sha256"] = scope_id
    fingerprint_failure = _public_fingerprint_failure(checkpoint.get("repo"))
    if fingerprint_failure is not None:
        result["repo_fingerprint_failure"] = fingerprint_failure["code"]
        result["repo_fingerprint_failure_stage"] = fingerprint_failure["stage"]
        for key in ("limit", "observed"):
            if key in fingerprint_failure:
                result["repo_fingerprint_failure_{}".format(key)] = (
                    fingerprint_failure[key]
                )
    return result


def _event(
    event: str,
    checkpoint: dict[str, Any] | None,
    runtime: memory.Runtime,
    *,
    timestamp: dt.datetime,
    session_sha256: str,
    thread_sha256: str,
    trigger: str,
    reason_codes: Sequence[str] | None = None,
    duplicate: bool | None = None,
    agent_scope: str = "root",
    ready: bool | None = None,
    continuation_mode: str | None = None,
) -> dict[str, Any]:
    rendered = _render_context(checkpoint) if checkpoint else ""
    row: dict[str, Any] = {
        "schema_version": EVENT_SCHEMA_VERSION,
        "event": event,
        "timestamp": _iso(timestamp),
        "codex_session_sha256": session_sha256,
        "codex_thread_sha256": thread_sha256,
        "agent_scope": agent_scope,
        "trigger": trigger,
        "checkpoint_bytes": _checkpoint_bytes(runtime, checkpoint),
        "checkpoint_tokens_estimate": _token_estimate(rendered),
        "checkpoint_sha256": _digest(_canonical(checkpoint)) if checkpoint else "",
        "phase_sha256": _digest(str((checkpoint or {}).get("phase", {}).get("id") or "")),
        "plan_sha256": str((checkpoint or {}).get("plan", {}).get("sha256") or ""),
        "generation": int((checkpoint or {}).get("generation", 0) or 0),
        "ready": bool((checkpoint or {}).get("ready")) if ready is None else bool(ready),
    }
    if reason_codes:
        # Telemetry accepts only fixed categories. Never let a corrupt private
        # checkpoint turn arbitrary local text into a ledger field.
        safe_reason_codes = sorted(
            {
                reason
                for reason in reason_codes
                if isinstance(reason, str) and reason in FIXED_REASON_CODES
            }
        )
        if safe_reason_codes:
            row["reason_codes"] = safe_reason_codes
    if duplicate is not None:
        row["duplicate"] = bool(duplicate)
    marker = (checkpoint or {}).get("precompact")
    intent = (checkpoint or {}).get("continuation_intent")
    mode = ""
    if isinstance(marker, dict):
        mode = str(marker.get("mode") or "")
        turn_sha256 = str(marker.get("turn_sha256") or "").lower()
        if re.fullmatch(r"[0-9a-f]{16,64}", turn_sha256):
            row["precompact_turn_sha256"] = turn_sha256[:16]
    if not mode and isinstance(intent, dict):
        mode = str(intent.get("mode") or "")
    if continuation_mode in CONTINUATION_MODES:
        mode = continuation_mode
    if mode in CONTINUATION_MODES:
        row["continuation_mode"] = mode
    liveness = (checkpoint or {}).get("not_ready_liveness")
    if isinstance(liveness, dict):
        episode_sha256 = str(liveness.get("episode_sha256") or "").lower()
        if re.fullmatch(r"[0-9a-f]{16,64}", episode_sha256):
            row["not_ready_episode_sha256"] = episode_sha256[:16]
    repo = (checkpoint or {}).get("repo")
    if isinstance(repo, dict):
        repo_scope = str(repo.get("validation_scope") or "")
        if repo_scope in {"legacy_worktree_v1", "task_paths_v1"}:
            row["repo_scope"] = repo_scope
        task_path_count = repo.get("task_path_count")
        if (
            isinstance(task_path_count, int)
            and not isinstance(task_path_count, bool)
            and 0 <= task_path_count <= MAX_TASK_PATHS
        ):
            row["task_path_count"] = task_path_count
    if checkpoint is not None:
        row["task_scope_complete"] = (
            checkpoint.get("task_scope_complete") is True
        )
        scope_id = str(checkpoint.get("task_scope_id_sha256") or "").lower()
        if re.fullmatch(r"[0-9a-f]{64}", scope_id):
            row["task_scope_id_sha256"] = scope_id[:16]
        fingerprint_failure = _public_fingerprint_failure(repo)
        if fingerprint_failure is not None:
            row["repo_fingerprint_failure"] = fingerprint_failure["code"]
            row["repo_fingerprint_failure_stage"] = fingerprint_failure["stage"]
    return row


def save_checkpoint(
    runtime: memory.Runtime,
    *,
    session_id: str,
    thread_id: str | None,
    snapshot: dict[str, Any],
    outstanding_work: str | None = None,
    trigger: str = "cli_save",
    advisory_reset_on_not_ready: bool = False,
    now: dt.datetime | None = None,
) -> tuple[dict[str, Any], list[str]]:
    now = now or _utc_now()
    session_sha256 = _privacy_digest(session_id)
    thread_sha256 = _privacy_digest(thread_id or session_id)
    with _session_lock(runtime, session_sha256):
        previous = _read_checkpoint(runtime, session_sha256)
        generation = int((previous or {}).get("generation", 0) or 0) + 1
        previous_liveness = _not_ready_liveness_marker(
            previous,
            session_sha256=session_sha256,
            thread_sha256=thread_sha256,
        )
        carried_liveness = (
            dict(previous_liveness)
            if previous_liveness is not None
            and previous_liveness.get("status") == "pending"
            else None
        )
        raw_changed_paths = snapshot.get("changed_paths", [])
        if not isinstance(raw_changed_paths, list):
            raw_changed_paths = []
        raw_task_scope_id = snapshot.get("_task_scope_id")
        task_scope_id_inherited = False
        task_scope_sha256 = _task_scope_id_digest(
            raw_task_scope_id,
            session_sha256=session_sha256,
            thread_sha256=thread_sha256,
        )
        if (
            not str(raw_task_scope_id or "").strip()
            and (previous or {}).get("status") != "completed"
        ):
            inherited_scope = str(
                (previous or {}).get("task_scope_id_sha256") or ""
            ).lower()
            if re.fullmatch(r"[0-9a-f]{64}", inherited_scope):
                task_scope_sha256 = inherited_scope
                task_scope_id_inherited = True
        task_scope_id_invalid = bool(str(raw_task_scope_id or "").strip()) and not bool(
            task_scope_sha256
        )
        scope_manifest_failure = ""
        if task_scope_sha256 and snapshot.get("task_scope_complete") is True:
            prior_manifest, manifest_read_failure = _read_scope_manifest(
                runtime,
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
                task_scope_sha256=task_scope_sha256,
            )
            if prior_manifest is not None:
                if prior_manifest.get("status") == "completed":
                    scope_manifest_failure = "scope_manifest_completed"
                else:
                    prior_paths = prior_manifest.get("changed_paths")
                    if isinstance(prior_paths, list):
                        raw_changed_paths = [*prior_paths, *raw_changed_paths]
            elif manifest_read_failure != "scope_manifest_missing":
                scope_manifest_failure = manifest_read_failure
            elif (
                task_scope_id_inherited
                and re.fullmatch(
                    r"[0-9a-f]{64}",
                    str((previous or {}).get("task_scope_manifest_sha256") or ""),
                )
            ):
                # A continuation may omit the raw ID because only its hash is
                # persisted. Its existing manifest is therefore mandatory;
                # silently rebuilding from newly supplied paths could trust a
                # partial scope after private state loss.
                scope_manifest_failure = "scope_manifest_missing"
        current_plan = snapshot.get("plan")
        previous_plan = (previous or {}).get("plan")
        previous_repo = (previous or {}).get("repo")
        previous_input_reasons = (previous or {}).get("input_reason_codes")
        carry_previous_scope = (
            not task_scope_sha256
            and isinstance(current_plan, dict)
            and isinstance(previous_plan, dict)
            and current_plan.get("status") == "tracked"
            and previous_plan.get("status") == "tracked"
            and bool(current_plan.get("relative_path"))
            and current_plan.get("relative_path") == previous_plan.get("relative_path")
            and (previous or {}).get("ready") is True
            and isinstance(previous_repo, dict)
            and previous_repo.get("validation_scope") == "task_paths_v1"
            and (
                not isinstance(previous_input_reasons, list)
                or not any(
                    reason
                    in {
                        "changed_path_outside_repo",
                        "changed_path_limit_exceeded",
                        "repo_fingerprint_unavailable",
                    }
                    for reason in previous_input_reasons
                )
            )
        )
        if carry_previous_scope:
            previous_paths = (previous or {}).get("changed_paths")
            if isinstance(previous_paths, list):
                raw_changed_paths = [*previous_paths, *raw_changed_paths]
        changed_paths, invalid_paths, truncated_paths = _normalize_changed_paths(
            raw_changed_paths, runtime.root
        )
        raw_input_reasons = snapshot.get("input_reason_codes", [])
        input_reason_codes = (
            list(raw_input_reasons) if isinstance(raw_input_reasons, list) else []
        )
        if invalid_paths:
            input_reason_codes.append("changed_path_outside_repo")
        if truncated_paths:
            input_reason_codes.append("changed_path_limit_exceeded")
        if task_scope_id_invalid:
            input_reason_codes.append("task_scope_id_invalid")
        input_reason_codes = _dedupe(input_reason_codes, limit=8)
        scope_incomplete = any(
            reason
            in {
                "changed_path_outside_repo",
                "changed_path_limit_exceeded",
                "repo_fingerprint_unavailable",
                "task_scope_id_invalid",
            }
            for reason in input_reason_codes
        )
        explicit_paths = snapshot.get("explicit_changed_paths")
        explicit_scope = (
            carry_previous_scope
            or bool(task_scope_sha256)
            or not isinstance(explicit_paths, list)
            or bool(explicit_paths)
        )
        scoped_capture = bool(
            snapshot.get("task_scope_complete") is True
            and not scope_incomplete
            and not scope_manifest_failure
            and (changed_paths or task_scope_sha256)
        )
        if scope_manifest_failure:
            repo = _unavailable_fingerprint(
                "task_paths_v1",
                task_path_count=len(changed_paths),
                failure=_fingerprint_failure(
                    scope_manifest_failure, "scope_manifest"
                ),
            )
        else:
            repo = _repo_fingerprint(
                runtime.root,
                changed_paths if scoped_capture else None,
                allow_all_missing=explicit_scope,
                task_scope_sha256=(task_scope_sha256 if scoped_capture else ""),
            )
        task_scope_manifest_sha256 = ""
        if scoped_capture and task_scope_sha256 and not scope_manifest_failure:
            manifest = _scope_manifest_value(
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
                task_scope_sha256=task_scope_sha256,
                changed_paths=changed_paths,
                generation=generation,
                now=now,
            )
            try:
                _atomic_write(
                    _scope_manifest_path(
                        runtime, session_sha256, task_scope_sha256
                    ),
                    manifest,
                )
            except OSError:
                repo = _unavailable_fingerprint(
                    "task_paths_v1",
                    task_path_count=len(changed_paths),
                    failure=_fingerprint_failure(
                        "scope_manifest_write_failed", "scope_manifest"
                    ),
                )
            else:
                task_scope_manifest_sha256 = _scope_manifest_digest(manifest)
        checkpoint = {
            "schema_version": SCHEMA_VERSION,
            "codex_session_sha256": session_sha256,
            "codex_thread_sha256": thread_sha256,
            "generation": generation,
            "status": "ready",
            "saved_at": _iso(now),
            "updated_at": _iso(now),
            "source": trigger,
            "plan": dict(snapshot.get("plan", {})),
            "phase": dict(snapshot.get("phase", {})),
            "tests": list(snapshot.get("tests", []))[:MAX_LIST_ITEMS],
            "gates": list(snapshot.get("gates", []))[:MAX_LIST_ITEMS],
            "graphify": dict(snapshot.get("graphify", {})),
            "changed_paths": changed_paths,
            "task_scope_complete": snapshot.get("task_scope_complete") is True,
            "input_reason_codes": input_reason_codes,
            "current_evidence": _clean_text(snapshot.get("current_evidence"), 700),
            "blocker": _clean_text(snapshot.get("blocker"), 500),
            "next_action": _clean_text(snapshot.get("next_action"), 800),
            "outstanding_work": outstanding_work or "",
            "repo": repo,
            "continuation_intent": None,
            "precompact": None,
            "advisory_reset": None,
            "not_ready_liveness": carried_liveness,
            "last_injected_generation": int(
                (previous or {}).get("last_injected_generation", 0) or 0
            ),
            "last_injected_at": (previous or {}).get("last_injected_at"),
        }
        if task_scope_sha256:
            checkpoint["task_scope_id_sha256"] = task_scope_sha256
        if task_scope_manifest_sha256:
            checkpoint["task_scope_manifest_sha256"] = (
                task_scope_manifest_sha256
            )
        if trigger == "cli_prepare":
            checkpoint["continuation_intent"] = {
                "mode": "prepared_rollover",
                "armed_at": _iso(now),
                "codex_session_sha256": session_sha256,
                "codex_thread_sha256": thread_sha256,
                "generation": generation,
                "worktree_sha256": str(repo.get("worktree_sha256") or ""),
                "checkpoint_binding_sha256": _intent_binding(checkpoint),
            }
        # The captured repository fingerprint is the save's atomic baseline.
        # Recomputing it inside this same operation makes shared-worktree writes
        # race every prepare into NOT_READY; PreCompact performs the later drift
        # check at the actual transition boundary.
        reasons = _validation_reasons(
            checkpoint, runtime, now=now, compare_repo=False
        )
        checkpoint["ready"] = not reasons
        checkpoint["validation_reason_codes"] = reasons
        if reasons:
            liveness = checkpoint.get("not_ready_liveness")
            if not isinstance(liveness, dict):
                opened_at = _iso(now)
                checkpoint["not_ready_liveness"] = {
                    "mode": "not_ready_liveness",
                    "status": "pending",
                    "opened_at": opened_at,
                    "opened_generation": generation,
                    "last_not_ready_generation": generation,
                    "episode_sha256": _digest(
                        _canonical(
                            {
                                "codex_session_sha256": session_sha256,
                                "codex_thread_sha256": thread_sha256,
                                "opened_generation": generation,
                                "opened_at": opened_at,
                            }
                        )
                    ),
                    "codex_session_sha256": session_sha256,
                    "codex_thread_sha256": thread_sha256,
                }
            else:
                liveness["last_not_ready_generation"] = generation
        if advisory_reset_on_not_ready and reasons:
            checkpoint["advisory_reset"] = {
                "mode": "recovery_advisory",
                "status": "pending",
                "requested_at": _iso(now),
                "generation": generation,
                "codex_session_sha256": session_sha256,
                "codex_thread_sha256": thread_sha256,
                "checkpoint_binding_sha256": _intent_binding(checkpoint),
            }
        _atomic_write(_checkpoint_path(runtime, session_sha256), checkpoint)
    _append_event(
        runtime,
        _event(
            "checkpoint_saved",
            checkpoint,
            runtime,
            timestamp=now,
            session_sha256=session_sha256,
            thread_sha256=thread_sha256,
            trigger=trigger,
            reason_codes=reasons,
        ),
    )
    if isinstance(checkpoint.get("advisory_reset"), dict):
        _append_event(
            runtime,
            _event(
                "checkpoint_advisory_reset_requested",
                checkpoint,
                runtime,
                timestamp=now,
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
                trigger="cli_prepare_advisory_reset",
                reason_codes=reasons,
                ready=False,
                continuation_mode="recovery_advisory",
            ),
        )
    return checkpoint, reasons


def _fit_utf8(value: str, maximum_bytes: int) -> str:
    encoded = value.encode("utf-8", errors="replace")
    if len(encoded) <= maximum_bytes:
        return value
    if maximum_bytes <= 3:
        return ""
    clipped = encoded[: maximum_bytes - 3]
    while clipped:
        try:
            return clipped.decode("utf-8") + "..."
        except UnicodeDecodeError:
            clipped = clipped[:-1]
    return ""


def _render_context(
    checkpoint: dict[str, Any] | None,
    *,
    token_limit: int | None = None,
) -> str:
    if not checkpoint:
        return ""
    maximum_bytes = _context_token_limit(token_limit) * 4
    plan_value = checkpoint.get("plan")
    phase_value = checkpoint.get("phase")
    plan = plan_value if isinstance(plan_value, dict) else {}
    phase = phase_value if isinstance(phase_value, dict) else {}
    tests = checkpoint.get("tests") if isinstance(checkpoint.get("tests"), list) else []
    gates = checkpoint.get("gates") if isinstance(checkpoint.get("gates"), list) else []
    changed = (
        checkpoint.get("changed_paths")
        if isinstance(checkpoint.get("changed_paths"), list)
        else []
    )
    lines = [
        "Validated prepared context-rollover checkpoint.",
        "Checkpoint: {} generation {}.".format(
            _digest(_canonical(checkpoint)), checkpoint.get("generation", 0)
        ),
        (
            "Plan: {} (sha256 {}).".format(
                _clean_text(plan.get("relative_path"), 260),
                str(plan.get("sha256") or "")[:16],
            )
            if plan.get("status") == "tracked"
            else "Plan status: not-applicable."
        ),
        "Phase: {}.".format(_clean_text(phase.get("id"), 180)),
        "Next exact action: {}".format(_clean_text(checkpoint.get("next_action"), 700)),
        "Outstanding work: {}.".format(
            _clean_text(checkpoint.get("outstanding_work"), 40)
        ),
    ]
    truncation_notices: list[str] = []
    if len(changed) > 16:
        truncation_notices.append(
            "changed paths 16/{} shown (+{} private/carried)".format(
                len(changed), len(changed) - 16
            )
        )
    if len(tests) > 16:
        truncation_notices.append(
            "test anchors 16/{} shown (+{} private)".format(
                len(tests), len(tests) - 16
            )
        )
    if len(gates) > 12:
        truncation_notices.append(
            "gate anchors 12/{} shown (+{} private)".format(
                len(gates), len(gates) - 12
            )
        )
    if truncation_notices:
        lines.append("Bounded-list notice: {}.".format("; ".join(truncation_notices)))
    if changed:
        values = [_clean_text(value, 140) for value in changed[:16]]
        label = "Changed paths"
        if len(changed) > 16:
            label += (
                " (first 16 of {}; +{} remain bound in the private checkpoint "
                "and carry automatically)"
            ).format(len(changed), len(changed) - 16)
        lines.append(
            _fit_utf8("{}: {}.".format(label, ", ".join(values)), 1_000)
        )
    if tests:
        values = [
            "{}={}".format(
                _clean_text(item.get("id"), 80),
                _clean_text(item.get("status"), 30),
            )
            for item in tests[:16]
            if isinstance(item, dict)
        ]
        label = "Test anchors"
        if len(tests) > 16:
            label += " (first 16 of {}; +{} remain bound in the private checkpoint)".format(
                len(tests), len(tests) - 16
            )
        lines.append(_fit_utf8("{}: {}.".format(label, ", ".join(values)), 800))
    if gates:
        values = [
            "{}={}".format(
                _clean_text(item.get("id"), 80),
                _clean_text(item.get("status"), 30),
            )
            for item in gates[:12]
            if isinstance(item, dict)
        ]
        label = "Gate anchors"
        if len(gates) > 12:
            label += " (first 12 of {}; +{} remain bound in the private checkpoint)".format(
                len(gates), len(gates) - 12
            )
        lines.append(_fit_utf8("{}: {}.".format(label, ", ".join(values)), 700))
    if checkpoint.get("current_evidence"):
        lines.append("Current evidence: {}".format(_clean_text(checkpoint["current_evidence"], 500)))
    if checkpoint.get("blocker") and str(checkpoint.get("blocker")).lower() not in {"none", "n/a", "—"}:
        lines.append("Decision/blocker: {}".format(_clean_text(checkpoint["blocker"], 360)))
    lines.append(
        "Resume from these anchors, verify current repository state, and do not rely on missing conversation history."
    )
    return _fit_utf8("\n".join(lines), maximum_bytes)


def _safe_plan_locator(
    checkpoint: dict[str, Any] | None, runtime: memory.Runtime
) -> str | None:
    plan = (checkpoint or {}).get("plan")
    if not isinstance(plan, dict) or plan.get("status") != "tracked":
        return None
    relative = str(plan.get("relative_path") or "")
    if not relative:
        return None
    try:
        path = (runtime.root / relative).resolve()
        normalized = path.relative_to(runtime.root.resolve()).as_posix()
    except (OSError, ValueError):
        return None
    return normalized if path.is_file() else None


def _recovery_context(
    reasons: Sequence[str],
    checkpoint: dict[str, Any] | None,
    runtime: memory.Runtime,
    *,
    token_limit: int | None = None,
) -> str:
    fixed_reasons = sorted(
        {
            reason
            for reason in reasons
            if isinstance(reason, str) and reason in FIXED_REASON_CODES
        }
    )
    lines = [
        "Context rollover recovery is ADVISORY, not a validated prepared rollover.",
        "Reason codes: {}.".format(",".join(fixed_reasons) or "checkpoint_missing"),
        (
            "Use this advisory only as orientation; reload current repository and "
            "plan state before acting."
        ),
    ]
    fingerprint_failure = _public_fingerprint_failure(
        (checkpoint or {}).get("repo")
    )
    if fingerprint_failure is not None:
        detail = [
            fingerprint_failure["code"],
            "stage={}".format(fingerprint_failure["stage"]),
        ]
        for key in ("observed", "limit"):
            if key in fingerprint_failure:
                detail.append("{}={}".format(key, fingerprint_failure[key]))
        lines.append("Repository fingerprint failure: {}.".format(" ".join(detail)))
    locator = _safe_plan_locator(checkpoint, runtime)
    if locator:
        lines.append(
            "Plan locator only (reread required): {}.".format(
                _clean_text(locator, 320)
            )
        )
    else:
        lines.append("No independently verified active-plan locator is available.")
    lines.append(
        "Do not trust stale phase, next-action, evidence, test, or gate fields; "
        "re-establish the relevant code context with targeted source searches."
    )
    return _fit_utf8(
        "\n".join(lines), _context_token_limit(token_limit) * 4
    )


def _inside_repo(payload: dict[str, Any], root: Path) -> bool:
    try:
        cwd = Path(str(payload.get("cwd") or root)).resolve()
        cwd.relative_to(root.resolve())
        return True
    except (OSError, ValueError):
        return False


def _root_payload(payload: dict[str, Any]) -> bool:
    agent = payload.get("agent_id") or payload.get("agentId")
    if agent is not None and str(agent).strip().lower() not in {"", "root"}:
        return False
    agent_type = str(payload.get("agent_type") or payload.get("agentType") or "").lower()
    return agent_type not in {"subagent", "explorer", "worker", "reviewer"}


def _hook_identity(payload: dict[str, Any]) -> tuple[str, str] | None:
    raw_session = payload.get("session_id") or payload.get("sessionId")
    if not raw_session:
        raw_session = payload.get("transcript_path") or payload.get("transcriptPath")
    if not raw_session:
        return None
    raw_thread = (
        payload.get("thread_id")
        or payload.get("threadId")
        or payload.get("agent_id")
        or payload.get("agentId")
        or raw_session
    )
    return _privacy_digest(raw_session), _privacy_digest(raw_thread)


def _not_ready_message(reasons: Sequence[str], checkpoint: dict[str, Any] | None) -> str:
    codes = ",".join(sorted(set(reasons)))
    plan_value = (checkpoint or {}).get("plan")
    plan = str(
        plan_value.get("relative_path") or "<active-plan-path>"
        if isinstance(plan_value, dict)
        else "<active-plan-path>"
    )
    command = (
        "python3 codex-memory/context_rollover.py prepare --from-plan {} "
        "--outstanding-work none"
    ).format(
        shlex.quote(plan),
    )
    message = (
        "Manual context rollover stopped: durable checkpoint NOT_READY "
        "({}). Finish any foreground process, update the bounded Execution "
        "Progress row, run `{}`, require READY, then retry rollover. Do not call "
        "functions.new_context while this checkpoint is NOT_READY."
    ).format(codes, command)
    fingerprint_failure = _public_fingerprint_failure(
        (checkpoint or {}).get("repo")
    )
    if fingerprint_failure is not None:
        message += " Repository fingerprint failure: {} (stage={}).".format(
            fingerprint_failure["code"], fingerprint_failure["stage"]
        )
    return message


def process_hook(
    payload: dict[str, Any],
    *,
    runtime: memory.Runtime | None = None,
    now: dt.datetime | None = None,
    context_token_limit: int | None = None,
) -> dict[str, Any] | None:
    """Handle Stop, PreCompact, PostCompact, and compact SessionStart payloads.

    Expected Codex 0.149 inputs:
    - Stop: common hook fields; a pending hard-exhaustion advisory reset blocks
      terminal completion until automatic PreCompact consumes it.
    - PreCompact: common hook fields plus ``turn_id`` and ``trigger``.
    - SessionStart: common hook fields plus ``source``; only ``compact`` injects.

    A prepared, fresh root checkpoint receives the trusted continuation path.
    Ordinary automatic compaction is never stopped by missing/stale local state;
    it receives a bounded advisory recovery path after compaction. Manual invalid
    compaction remains fail-closed, and malformed input fails open.
    """
    runtime = runtime or memory.load_runtime()
    if not _inside_repo(payload, runtime.root):
        return None
    identity = _hook_identity(payload)
    if identity is None:
        return None
    session_sha256, thread_sha256 = identity
    now = now or _utc_now()
    event_name = str(
        payload.get("hook_event_name") or payload.get("hookEventName") or ""
    )
    if _control_rollover_arm():
        # The control arm measures Codex's native/legacy compaction behavior.
        # It must not consult or mutate the intervention's private capsule, and
        # it must not inject intervention context after that native transition.
        if event_name == "PreCompact":
            return {"continue": True, "suppressOutput": True}
        if event_name == "PostCompact":
            raw_trigger = str(payload.get("trigger") or "auto").lower()
            trigger = (
                "control_postcompact_manual"
                if raw_trigger == "manual"
                else "control_postcompact_auto"
            )
            _append_event(
                runtime,
                _event(
                    "postcompact_observed",
                    None,
                    runtime,
                    timestamp=now,
                    session_sha256=session_sha256,
                    thread_sha256=thread_sha256,
                    trigger=trigger,
                    agent_scope="root" if _root_payload(payload) else "subagent",
                    ready=False,
                ),
            )
            return {"continue": True, "suppressOutput": True}
        if event_name == "SessionStart":
            return None
        if event_name == "Stop":
            return {"continue": True, "suppressOutput": True}
    if not _root_payload(payload):
        raw_trigger = str(payload.get("trigger") or "auto").lower()
        trigger = {
            "PreCompact": "precompact_subagent",
            "PostCompact": "postcompact_subagent",
        }.get(event_name, "subagent_hook")
        _append_event(
            runtime,
            _event(
                "subagent_skipped",
                None,
                runtime,
                timestamp=now,
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
                trigger=trigger,
                reason_codes=["subagent_rollover_unsupported"],
                agent_scope="subagent",
                ready=False,
            ),
        )
        if event_name == "PreCompact":
            if raw_trigger != "manual":
                # A stopped automatic PreCompact maps to TurnAborted in Codex
                # 0.149, so the child cannot produce the handoff the old message
                # requested. Let native compaction preserve the worker instead;
                # it still cannot read or mutate the root continuation capsule.
                return {"continue": True, "suppressOutput": True}
            message = (
                "Subagent context rollover is unsupported in Codex 0.149 and cannot "
                "be restored by SessionStart. Stop this compaction and return a concise "
                "handoff to the root agent instead."
            )
            return {
                "continue": False,
                "stopReason": message,
                "systemMessage": message,
                "suppressOutput": False,
            }
        return {"continue": True, "suppressOutput": True}
    if event_name == "Stop":
        with _session_lock(runtime, session_sha256):
            checkpoint = _read_checkpoint(runtime, session_sha256)
            pending_advisory_reset = _advisory_reset_pending(
                checkpoint,
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
                now=now,
            )
            liveness = _not_ready_liveness_marker(
                checkpoint,
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
            )
            pending_not_ready = bool(
                liveness is not None and liveness.get("status") == "pending"
            )
            precompact = (checkpoint or {}).get("precompact")
            precompact_mode = (
                str(precompact.get("mode") or "")
                if isinstance(precompact, dict)
                else ""
            )
            generation = int((checkpoint or {}).get("generation", 0) or 0)
            already_injected = bool(
                generation > 0
                and int((checkpoint or {}).get("last_injected_generation", 0) or 0)
                == generation
            )
            legacy_untransitioned_not_ready = bool(
                checkpoint is not None
                and liveness is None
                and checkpoint.get("ready") is False
                and checkpoint.get("status") != "completed"
                and precompact_mode not in CONTINUATION_MODES
                and not already_injected
            )
            terminal_after_not_ready = bool(
                not pending_advisory_reset
                and (pending_not_ready or legacy_untransitioned_not_ready)
            )
            if terminal_after_not_ready and liveness is not None:
                liveness["status"] = "terminal"
                liveness["terminal_at"] = _iso(now)
                liveness["terminal_generation"] = generation
                try:
                    _atomic_write(_checkpoint_path(runtime, session_sha256), checkpoint)
                except Exception as exc:
                    if os.environ.get("CODEX_ROLLOVER_DEBUG") == "1":
                        print(
                            "context rollover terminal marker ignored error: {}".format(
                                exc
                            ),
                            file=sys.stderr,
                        )
        if terminal_after_not_ready:
            raw_reasons = (checkpoint or {}).get("validation_reason_codes")
            reason_codes = raw_reasons if isinstance(raw_reasons, list) else []
            _append_event(
                runtime,
                _event(
                    "terminal_after_not_ready",
                    checkpoint,
                    runtime,
                    timestamp=now,
                    session_sha256=session_sha256,
                    thread_sha256=thread_sha256,
                    trigger="stop_after_not_ready",
                    reason_codes=reason_codes,
                    ready=False,
                ),
            )
            return {"continue": True, "suppressOutput": True}
        if not pending_advisory_reset:
            return {"continue": True, "suppressOutput": True}
        raw_reasons = (checkpoint or {}).get("validation_reason_codes")
        reason_codes = raw_reasons if isinstance(raw_reasons, list) else []
        _append_event(
            runtime,
            _event(
                "terminal_after_not_ready_blocked",
                checkpoint,
                runtime,
                timestamp=now,
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
                trigger="stop_advisory_reset_pending",
                reason_codes=reason_codes,
                ready=False,
                continuation_mode="recovery_advisory",
            ),
        )
        message = (
            "Context rollover advisory reset is pending after a NOT_READY "
            "checkpoint. Do not end this turn. Call `functions.new_context` "
            "immediately; automatic recovery will resume with advisory context."
        )
        return {
            "continue": False,
            "stopReason": message,
            "systemMessage": message,
            "suppressOutput": False,
        }
    if event_name == "PreCompact":
        raw_trigger = str(payload.get("trigger") or "auto").lower()
        trigger = "precompact_manual" if raw_trigger == "manual" else "precompact_auto"
        with _session_lock(runtime, session_sha256):
            checkpoint = _read_checkpoint(runtime, session_sha256)
            pending_advisory_reset = _advisory_reset_pending(
                checkpoint,
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
                now=now,
            )
            pending_not_ready_liveness = _not_ready_liveness_pending(
                checkpoint,
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
            )
            reasons = _validation_reasons(
                checkpoint,
                runtime,
                now=now,
                require_fresh_generation=True,
            )
            if pending_advisory_reset:
                reasons = sorted(set([*reasons, "advisory_reset_requested"]))
            intent_reasons = _rollover_intent_reasons(
                checkpoint,
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
                now=now,
            )
            prepared_rollover = not reasons and not intent_reasons
            recovery_allowed = raw_trigger != "manual" or prepared_rollover
            recovery_reasons = sorted(set([*reasons, *intent_reasons]))
            if recovery_allowed and checkpoint is not None:
                checkpoint["precompact"] = {
                    "at": _iso(now),
                    "generation": int(checkpoint.get("generation", 0) or 0),
                    "turn_sha256": _digest(str(payload.get("turn_id") or "unknown")),
                    "trigger": raw_trigger if raw_trigger in {"manual", "auto"} else "auto",
                    "worktree_sha256": str(checkpoint.get("repo", {}).get("worktree_sha256") or ""),
                    "mode": (
                        "prepared_rollover"
                        if prepared_rollover
                        else "recovery_advisory"
                    ),
                    "reason_codes": [] if prepared_rollover else recovery_reasons,
                }
                checkpoint["updated_at"] = _iso(now)
                checkpoint["ready"] = not reasons
                checkpoint["validation_reason_codes"] = reasons
                if pending_advisory_reset and raw_trigger != "manual":
                    advisory_reset = checkpoint.get("advisory_reset")
                    if isinstance(advisory_reset, dict):
                        advisory_reset["status"] = "consumed"
                        advisory_reset["consumed_at"] = _iso(now)
                if pending_not_ready_liveness:
                    not_ready_liveness = checkpoint.get("not_ready_liveness")
                    if isinstance(not_ready_liveness, dict):
                        not_ready_liveness["status"] = "transitioned"
                        not_ready_liveness["transitioned_at"] = _iso(now)
                        not_ready_liveness["transitioned_generation"] = int(
                            checkpoint.get("generation", 0) or 0
                        )
                _atomic_write(_checkpoint_path(runtime, session_sha256), checkpoint)
        if reasons:
            if any(reason in STALE_REASONS for reason in reasons):
                _append_event(
                    runtime,
                    _event(
                        "checkpoint_stale",
                        checkpoint,
                        runtime,
                        timestamp=now,
                        session_sha256=session_sha256,
                        thread_sha256=thread_sha256,
                        trigger=trigger,
                        reason_codes=reasons,
                        ready=False,
                    ),
                )
        if recovery_allowed and not prepared_rollover:
            _append_event(
                runtime,
                _event(
                    "precompact_recovery_allowed",
                    checkpoint,
                    runtime,
                    timestamp=now,
                    session_sha256=session_sha256,
                    thread_sha256=thread_sha256,
                    trigger=trigger,
                    reason_codes=recovery_reasons,
                    ready=False,
                    continuation_mode="recovery_advisory",
                ),
            )
            return {"continue": True, "suppressOutput": True}
        if recovery_reasons:
            _append_event(
                runtime,
                _event(
                    "precompact_blocked",
                    checkpoint,
                    runtime,
                    timestamp=now,
                    session_sha256=session_sha256,
                    thread_sha256=thread_sha256,
                    trigger=trigger,
                    reason_codes=recovery_reasons,
                    ready=False,
                ),
            )
            message = _not_ready_message(recovery_reasons, checkpoint)
            return {
                "continue": False,
                "stopReason": message,
                "systemMessage": message,
                "suppressOutput": False,
            }
        _append_event(
            runtime,
            _event(
                "precompact_allowed",
                checkpoint,
                runtime,
                timestamp=now,
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
                trigger=trigger,
                continuation_mode="prepared_rollover",
            ),
        )
        return {"continue": True, "suppressOutput": True}

    if event_name == "PostCompact":
        raw_trigger = str(payload.get("trigger") or "auto").lower()
        trigger = "postcompact_manual" if raw_trigger == "manual" else "postcompact_auto"
        with _session_lock(runtime, session_sha256):
            checkpoint = _read_checkpoint(runtime, session_sha256)
            reasons = _validation_reasons(
                checkpoint,
                runtime,
                now=now,
                require_precompact=True,
            )
            marker = (checkpoint or {}).get("precompact")
            if not isinstance(marker, dict) or marker.get("mode") != "prepared_rollover":
                marker_reasons = marker.get("reason_codes") if isinstance(marker, dict) else []
                safe_marker_reasons = (
                    [
                        reason
                        for reason in marker_reasons
                        if isinstance(reason, str) and reason in FIXED_REASON_CODES
                    ]
                    if isinstance(marker_reasons, list)
                    else []
                )
                reasons = sorted(set([*reasons, *safe_marker_reasons]))
                if not safe_marker_reasons:
                    reasons.append("rollover_intent_missing")
        if reasons:
            _append_event(
                runtime,
                _event(
                    "checkpoint_stale",
                    checkpoint,
                    runtime,
                    timestamp=now,
                    session_sha256=session_sha256,
                    thread_sha256=thread_sha256,
                    trigger=trigger,
                    reason_codes=reasons,
                    ready=False,
                ),
            )
        _append_event(
            runtime,
            _event(
                "postcompact_observed",
                checkpoint,
                runtime,
                timestamp=now,
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
                trigger=trigger,
                reason_codes=reasons,
                ready=not reasons,
            ),
        )
        # PostCompact is observational. It must never stop or inject.
        return {"continue": True, "suppressOutput": True}

    if event_name == "SessionStart":
        source = str(payload.get("source") or "").lower()
        if source != "compact":
            return None
        trigger = "session_compact"
        with _session_lock(runtime, session_sha256):
            checkpoint = _read_checkpoint(runtime, session_sha256)
            reasons = _validation_reasons(
                checkpoint,
                runtime,
                now=now,
                require_precompact=True,
                require_fresh_generation=False,
            )
            marker = (checkpoint or {}).get("precompact")
            marker_mode = (
                str(marker.get("mode") or "") if isinstance(marker, dict) else ""
            )
            marker_reasons = marker.get("reason_codes") if isinstance(marker, dict) else []
            safe_marker_reasons = (
                [
                    reason
                    for reason in marker_reasons
                    if isinstance(reason, str) and reason in FIXED_REASON_CODES
                ]
                if isinstance(marker_reasons, list)
                else []
            )
            generation = int((checkpoint or {}).get("generation", 0) or 0)
            duplicate = bool(
                checkpoint is not None
                and generation > 0
                and int(checkpoint.get("last_injected_generation", 0) or 0)
                == generation
            )
            prepared_rollover = (
                checkpoint is not None
                and marker_mode == "prepared_rollover"
                and not reasons
                and not duplicate
            )
            if prepared_rollover and checkpoint is not None:
                context = _render_context(checkpoint, token_limit=context_token_limit)
            else:
                advisory_reasons = sorted(set([*reasons, *safe_marker_reasons]))
                if marker_mode != "prepared_rollover" and not advisory_reasons:
                    advisory_reasons.append("rollover_intent_missing")
                if duplicate:
                    advisory_reasons = sorted(
                        set([*advisory_reasons, "checkpoint_already_consumed"])
                    )
                context = _recovery_context(
                    advisory_reasons,
                    checkpoint,
                    runtime,
                    token_limit=context_token_limit,
                )
            if checkpoint is not None and generation > 0:
                checkpoint["last_injected_generation"] = generation
                checkpoint["last_injected_at"] = _iso(now)
                checkpoint["updated_at"] = _iso(now)
                _atomic_write(_checkpoint_path(runtime, session_sha256), checkpoint)
        if not prepared_rollover:
            _append_event(
                runtime,
                _event(
                    "checkpoint_stale",
                    checkpoint,
                    runtime,
                    timestamp=now,
                    session_sha256=session_sha256,
                    thread_sha256=thread_sha256,
                    trigger=trigger,
                    reason_codes=advisory_reasons,
                    ready=False,
                    continuation_mode="recovery_advisory",
                ),
            )
            _append_event(
                runtime,
                _event(
                    "session_recovery_advisory",
                    checkpoint,
                    runtime,
                    timestamp=now,
                    session_sha256=session_sha256,
                    thread_sha256=thread_sha256,
                    trigger=trigger,
                    reason_codes=advisory_reasons,
                    ready=False,
                    continuation_mode="recovery_advisory",
                ),
            )
        else:
            _append_event(
                runtime,
                _event(
                    "session_resumed",
                    checkpoint,
                    runtime,
                    timestamp=now,
                    session_sha256=session_sha256,
                    thread_sha256=thread_sha256,
                    trigger=trigger,
                    duplicate=False,
                    continuation_mode="prepared_rollover",
                ),
            )
        return {
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": context,
            }
        }
    return None


def complete_checkpoint(
    runtime: memory.Runtime,
    *,
    session_id: str,
    thread_id: str | None = None,
    now: dt.datetime | None = None,
) -> bool:
    now = now or _utc_now()
    session_sha256 = _privacy_digest(session_id)
    thread_sha256 = _privacy_digest(thread_id or session_id)
    with _session_lock(runtime, session_sha256):
        checkpoint = _read_checkpoint(runtime, session_sha256)
        if checkpoint is None:
            return False
        checkpoint["status"] = "completed"
        checkpoint["ready"] = False
        checkpoint["updated_at"] = _iso(now)
        checkpoint["validation_reason_codes"] = ["checkpoint_completed"]
        task_scope_id_sha256 = str(
            checkpoint.get("task_scope_id_sha256") or ""
        ).lower()
        if re.fullmatch(r"[0-9a-f]{64}", task_scope_id_sha256):
            manifest, _manifest_failure = _read_scope_manifest(
                runtime,
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
                task_scope_sha256=task_scope_id_sha256,
            )
            if manifest is not None and manifest.get("status") == "active":
                completed_manifest = _scope_manifest_value(
                    session_sha256=session_sha256,
                    thread_sha256=thread_sha256,
                    task_scope_sha256=task_scope_id_sha256,
                    changed_paths=list(manifest.get("changed_paths", [])),
                    generation=int(checkpoint.get("generation", 0) or 0),
                    now=now,
                    status="completed",
                )
                _atomic_write(
                    _scope_manifest_path(
                        runtime, session_sha256, task_scope_id_sha256
                    ),
                    completed_manifest,
                )
                checkpoint["task_scope_manifest_sha256"] = (
                    _scope_manifest_digest(completed_manifest)
                )
        _atomic_write(_checkpoint_path(runtime, session_sha256), checkpoint)
    _append_event(
        runtime,
        _event(
            "checkpoint_completed",
            checkpoint,
            runtime,
            timestamp=now,
            session_sha256=session_sha256,
            thread_sha256=thread_sha256,
            trigger="cli_complete",
            reason_codes=["checkpoint_completed"],
        ),
    )
    return True


def _resolve_selector(value: str | None, environment_name: str) -> str:
    candidate = str(value or "current")
    if candidate == "current":
        candidate = str(os.environ.get(environment_name) or "")
    if not candidate:
        raise ValueError("{} is unavailable; pass an explicit selector".format(environment_name))
    return candidate


def _load_runtime(args: argparse.Namespace) -> memory.Runtime:
    root = Path(args.root).expanduser().resolve() if getattr(args, "root", None) else memory.ROOT
    return memory.load_runtime(getattr(args, "config", None), root=root)


def _save_command(args: argparse.Namespace, *, trigger: str) -> int:
    runtime = _load_runtime(args)
    environment_session = os.environ.get("CODEX_SESSION_ID")
    environment_thread = os.environ.get("CODEX_THREAD_ID")
    session_id = _resolve_selector(args.session, "CODEX_SESSION_ID")
    thread_id = (
        _resolve_selector(args.thread, "CODEX_THREAD_ID")
        if args.thread not in {None, "current"} or os.environ.get("CODEX_THREAD_ID")
        else session_id
    )
    if (
        environment_session
        and environment_thread
        and environment_session != environment_thread
    ) or thread_id != session_id:
        # Codex 0.149 has no SessionStart restoration leg for subagents.  Never
        # let a child overwrite the root session's continuation capsule.
        session_sha256 = _privacy_digest(session_id)
        thread_sha256 = _privacy_digest(
            environment_thread
            if environment_session and environment_thread != environment_session
            else thread_id
        )
        _append_event(
            runtime,
            _event(
                "subagent_skipped",
                None,
                runtime,
                timestamp=_utc_now(),
                session_sha256=session_sha256,
                thread_sha256=thread_sha256,
                trigger=trigger,
                reason_codes=["subagent_rollover_unsupported"],
                agent_scope="subagent",
                ready=False,
            ),
        )
        result = {
            "ready": False,
            "reason_codes": ["subagent_rollover_unsupported"],
            "codex_session_sha256": session_sha256,
            "codex_thread_sha256": thread_sha256,
            "checkpoint_bytes": 0,
            "checkpoint_tokens_estimate": 0,
        }
        if args.json:
            print(_canonical(result))
        else:
            print("NOT_READY reason_codes=subagent_rollover_unsupported.")
            print("DO NOT call `functions.new_context`; return a handoff to the root agent.")
        return 2
    snapshot = _empty_snapshot()
    extraction_error: str | None = None
    if args.from_plan:
        try:
            snapshot = plan_snapshot(args.from_plan, runtime)
        except ValueError as exc:
            candidate = str(exc)
            extraction_error = candidate if candidate in {
                "plan_missing",
                "plan_outside_repo",
                "plan_too_large",
            } else "plan_extraction_failed"
        except (OSError, UnicodeDecodeError):
            extraction_error = "plan_read_failed"
    snapshot = _apply_overrides(snapshot, args, runtime.root)
    if extraction_error:
        snapshot["input_reason_codes"] = _dedupe(
            [*snapshot.get("input_reason_codes", []), extraction_error],
            limit=8,
        )
    checkpoint, reasons = save_checkpoint(
        runtime,
        session_id=session_id,
        thread_id=thread_id,
        snapshot=snapshot,
        outstanding_work=args.outstanding_work,
        trigger=trigger,
        advisory_reset_on_not_ready=bool(
            trigger == "cli_prepare"
            and getattr(args, "advisory_reset_on_not_ready", False)
        ),
    )
    public = _safe_public_status(
        checkpoint, runtime, now=_utc_now(), compare_repo=False
    )
    public["ready"] = not reasons and bool(public.get("ready"))
    public["reason_codes"] = sorted(set([*public.get("reason_codes", []), *reasons]))
    advisory_reset = bool(
        trigger == "cli_prepare"
        and getattr(args, "advisory_reset_on_not_ready", False)
        and not public["ready"]
    )
    if advisory_reset:
        public["status"] = "ADVISORY_RESET"
        public["advisory_reset_permitted"] = True
        public["continuation_mode"] = "recovery_advisory"
    if args.json:
        print(_canonical(public))
    elif public["ready"]:
        print(
            "READY checkpoint={} generation={} capsule_tokens~{}.".format(
                public["checkpoint_sha256"],
                public["generation"],
                public["checkpoint_tokens_estimate"],
            )
        )
        print("NEXT: call `functions.new_context` now.")
    elif advisory_reset:
        print(
            "ADVISORY_RESET checkpoint={} generation={} reason_codes={}.".format(
                public["checkpoint_sha256"],
                public["generation"],
                ",".join(public["reason_codes"]),
            )
        )
        if public.get("repo_fingerprint_failure"):
            print(
                "repo_fingerprint_failure={}.".format(
                    public["repo_fingerprint_failure"]
                )
            )
        print(
            "NEXT: call `functions.new_context` now; SessionStart will inject "
            "advisory recovery only."
        )
    else:
        print("NOT_READY reason_codes={}.".format(",".join(public["reason_codes"])))
        if public.get("repo_fingerprint_failure"):
            print(
                "repo_fingerprint_failure={}.".format(
                    public["repo_fingerprint_failure"]
                )
            )
        print("DO NOT call `functions.new_context`.")
        print(
            "NEXT: update the active plan's bounded Execution Progress row and rerun "
            "`python3 codex-memory/context_rollover.py prepare --from-plan "
            "<active-plan-path> --outstanding-work none`."
        )
    return 0 if public["ready"] or advisory_reset else 2


def _status_command(args: argparse.Namespace) -> int:
    runtime = _load_runtime(args)
    session_id = _resolve_selector(args.session, "CODEX_SESSION_ID")
    session_sha256 = _privacy_digest(session_id)
    with _session_lock(runtime, session_sha256):
        checkpoint = _read_checkpoint(runtime, session_sha256)
    public = _safe_public_status(checkpoint, runtime, now=_utc_now())
    if args.json:
        print(_canonical(public))
    else:
        state = "READY" if public["ready"] else "NOT_READY"
        print(
            "{} checkpoint={} generation={} capsule_tokens~{} reasons={}.".format(
                state,
                public.get("checkpoint_sha256", "none"),
                public.get("generation", 0),
                public.get("checkpoint_tokens_estimate", 0),
                ",".join(public.get("reason_codes", [])) or "none",
            )
        )
        if public.get("repo_fingerprint_failure"):
            print(
                "repo_fingerprint_failure={}.".format(
                    public["repo_fingerprint_failure"]
                )
            )
    return 0 if public["ready"] else 2


def _complete_command(args: argparse.Namespace) -> int:
    runtime = _load_runtime(args)
    environment_session = os.environ.get("CODEX_SESSION_ID")
    environment_thread = os.environ.get("CODEX_THREAD_ID")
    session_id = _resolve_selector(args.session, "CODEX_SESSION_ID")
    thread_id = os.environ.get("CODEX_THREAD_ID") or session_id
    if (
        environment_session
        and environment_thread
        and environment_session != environment_thread
    ) or thread_id != session_id:
        print("NOT_READY reason_codes=subagent_rollover_unsupported.")
        return 2
    if not complete_checkpoint(runtime, session_id=session_id, thread_id=thread_id):
        print("NOT_READY reason_codes=checkpoint_missing.")
        return 2
    print("COMPLETED context-rollover checkpoint; lifecycle metrics retained privately.")
    return 0


def _hook_command(args: argparse.Namespace) -> int:
    payload: dict[str, Any] | None = None
    try:
        value = json.load(sys.stdin)
        payload = value if isinstance(value, dict) else None
        if isinstance(payload, dict):
            forced_event = getattr(args, "forced_event", None)
            if forced_event:
                payload["hook_event_name"] = forced_event
            result = process_hook(payload, runtime=_load_runtime(args))
            if result is not None:
                print(_canonical(result))
    except Exception as exc:
        event_name = str(
            (payload or {}).get("hook_event_name")
            or (payload or {}).get("hookEventName")
            or getattr(args, "forced_event", "")
        )
        raw_trigger = str((payload or {}).get("trigger") or "auto").lower()
        if payload is not None and event_name == "PreCompact" and (
            _control_rollover_arm() or raw_trigger != "manual"
        ):
            print(_canonical({"continue": True, "suppressOutput": True}))
        elif payload is not None and event_name == "PreCompact":
            # Once a valid PreCompact payload is recognizable, an internal
            # checkpoint failure must stop destructive history replacement.
            message = (
                "Manual context compaction stopped because checkpoint validation "
                "failed internally. Preserve this context, run context_rollover.py "
                "status/prepare, and retry only after READY."
            )
            print(
                _canonical(
                    {
                        "continue": False,
                        "stopReason": message,
                        "systemMessage": message,
                        "suppressOutput": False,
                    }
                )
            )
        if os.environ.get("CODEX_ROLLOVER_DEBUG") == "1":
            print("context rollover hook ignored error: {}".format(exc), file=sys.stderr)
    return 0


def _add_runtime_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--config", help=argparse.SUPPRESS)
    parser.add_argument("--root", help=argparse.SUPPRESS)


def _add_save_options(parser: argparse.ArgumentParser) -> None:
    _add_runtime_options(parser)
    parser.add_argument("--session", default="current")
    parser.add_argument("--thread", default="current")
    parser.add_argument("--from-plan", metavar="PATH")
    parser.add_argument(
        "--plan-status", choices=("tracked", "not-applicable")
    )
    parser.add_argument("--phase-id")
    parser.add_argument("--next-action")
    parser.add_argument("--test", action="append", default=[])
    parser.add_argument("--gate", action="append", default=[])
    parser.add_argument("--changed-path", action="append", default=[])
    parser.add_argument(
        "--task-scope-id",
        help="private stable identifier used to carry one root task scope",
    )
    parser.add_argument(
        "--task-scope-complete",
        action="store_true",
        help="assert that cumulative plan, prior, and --changed-path scope is complete",
    )
    parser.add_argument("--graph-query-id")
    parser.add_argument("--graph-evidence-digest")
    parser.add_argument(
        "--graph-status",
        choices=("grounded", "not-applicable", "not-yet-grounded"),
    )
    parser.add_argument(
        "--outstanding-work",
        choices=("none", "completed", "running"),
    )
    parser.add_argument("--json", action="store_true")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command")
    save = sub.add_parser("save", help="save and validate a rollover checkpoint")
    _add_save_options(save)
    prepare = sub.add_parser(
        "prepare", help="model-friendly save alias for token-budget reminders"
    )
    _add_save_options(prepare)
    prepare.add_argument(
        "--advisory-reset-on-not-ready",
        action="store_true",
        help=(
            "at hard exhaustion, permit immediate new_context with advisory-only "
            "recovery when the checkpoint remains NOT_READY"
        ),
    )
    status = sub.add_parser("status", help="show privacy-safe checkpoint readiness")
    _add_runtime_options(status)
    status.add_argument("--session", default="current")
    status.add_argument("--json", action="store_true")
    complete = sub.add_parser("complete", help="close the active checkpoint")
    _add_runtime_options(complete)
    complete.add_argument("--session", default="current")
    hook = sub.add_parser("hook", help="read a Codex hook payload from stdin")
    _add_runtime_options(hook)
    for name, event in (
        ("hook-pre", "PreCompact"),
        ("hook-post", "PostCompact"),
        ("hook-session-start", "SessionStart"),
        ("hook-stop", "Stop"),
    ):
        explicit = sub.add_parser(name, help="handle one explicit Codex lifecycle hook")
        _add_runtime_options(explicit)
        explicit.set_defaults(forced_event=event)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    values = list(sys.argv[1:] if argv is None else argv)
    if not values and not sys.stdin.isatty():
        values = ["hook"]
    parser = _parser()
    args = parser.parse_args(values)
    if args.command == "save":
        return _save_command(args, trigger="cli_save")
    if args.command == "prepare":
        return _save_command(args, trigger="cli_prepare")
    if args.command == "status":
        return _status_command(args)
    if args.command == "complete":
        return _complete_command(args)
    if args.command in {
        "hook",
        "hook-pre",
        "hook-post",
        "hook-session-start",
        "hook-stop",
    }:
        return _hook_command(args)
    parser.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
