#!/usr/bin/env python3
"""Privacy-safe OFF/SHADOW/ACTIVE task measurement for Codex sessions.

The ledger deliberately stores aggregates and short hashes only.  Prompts,
commands, paths, model output, and raw Codex identifiers never enter it.
"""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import hashlib
import hmac
import importlib.util
import json
import math
import os
import re
import stat as statmod
import subprocess
import sys
import time
import tomllib
import uuid
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable, Iterator, Sequence


ROOT = Path(__file__).resolve().parents[1]
MEMORY_DIR = Path(__file__).resolve().parent
DEFAULT_LEDGER = MEMORY_DIR / "state" / "task-runs.jsonl"
DEFAULT_REQUEST_KEY = DEFAULT_LEDGER.with_name(DEFAULT_LEDGER.name + ".key")
DEFAULT_ROLLOVER_EVENTS = MEMORY_DIR / "state" / "context-rollover-events.jsonl"
DEFAULT_SESSIONS_ROOT = Path.home() / ".codex" / "sessions"
SCHEMA_VERSION = 1
NEGATIVE_CONTROL_TOLERANCE_PERCENT = 5.0
MINIMUM_SAVINGS_THRESHOLD_PERCENT = 20.0
ROLLOVER_ARMS = {"control", "active"}
# Codex' token-budget fallback is capped to five percent of the model context
# window.  Keep both values visible as policy diagnostics; neither is a token
# saving and neither is folded into exact usage.
TOKEN_BUDGET_FALLBACK_TOKENS = 16_384
TOKEN_KEYS = {
    "input": "input_tokens",
    "cached_input": "cached_input_tokens",
    "cache_write_input": "cache_write_input_tokens",
    "output": "output_tokens",
    "reasoning_output": "reasoning_output_tokens",
    "total": "total_tokens",
}
FALSE_VALUES = {"0", "false", "no", "off"}
GATE_ID = re.compile(r"^[a-z0-9][a-z0-9_.:-]{0,63}$")
HASH16 = re.compile(r"^[0-9a-f]{16}$")
HASH32 = re.compile(r"^[0-9a-f]{32}$")
SAFE_TIMEZONE = re.compile(r"^[A-Za-z0-9_+./-]{1,64}$")
POLICY_TUNING_DEFAULTS: dict[str, Any] = {
    "graphify_debug": False,
    "graphify_ceiling": 10,
    "graphify_batch_budget": 8,
    "memory_debug": False,
    "memory_ceiling": 4,
    "memory_primary_idle_seconds": 86_400,
    "memory_secondary_budget": 300,
    "memory_secondary_min_raw_tokens": 300,
    "memory_targeted_read_lines": 120,
    "memory_repeat_guard_budget": 300,
    "memory_primary_read": False,
    "memory_primary_output_bypass": False,
    "memory_secondary_bypass": False,
    "memory_repeat_guard_bypass": False,
}
POLICY_TUNING_KEYS = (
    *POLICY_TUNING_DEFAULTS,
    "graphify_state_dir_sha256",
    "memory_config_path_sha256",
    "memory_config_content_sha256",
    "memory_config_available",
)
ROLLOVER_ATTEMPT_EVENTS = {
    "precompact_allowed",
    "pre_compact",
    "rollover_attempt",
    "rollover_requested",
    "new_context_requested",
    "auto_limit_rollover",
}
ROLLOVER_COMPLETION_EVENTS = {
    "session_resumed",
    "session_start_compact",
    "post_compact",
    "rollover_completed",
}
ROLLOVER_FAILURE_EVENTS = {
    "precompact_blocked",
    "rollover_failed",
}
CHECKPOINT_VALIDATION_FAILURE_EVENTS = {
    "checkpoint_stale",
}
ROLLOVER_RECOVERY_EVENTS = {
    "precompact_recovery_allowed",
    "session_recovery_advisory",
}
ROLLOVER_LIVENESS_EVENTS = {
    "checkpoint_advisory_reset_requested",
    "terminal_after_not_ready_blocked",
    "terminal_after_not_ready",
    "user_rescue_after_terminal",
}
ROLLOVER_TRANSITION_EVENTS = {
    "precompact_allowed",
    "precompact_recovery_allowed",
    "postcompact_observed",
    "session_resumed",
    "session_recovery_advisory",
}


def _now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _timestamp(value: Any) -> dt.datetime | None:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        try:
            seconds = float(value)
            if abs(seconds) >= 100_000_000_000:
                seconds /= 1000.0
            return dt.datetime.fromtimestamp(seconds, dt.timezone.utc)
        except (ValueError, OverflowError, OSError):
            return None
    try:
        parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError, OverflowError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def _digest(value: Any) -> str:
    return hashlib.sha256(str(value).encode("utf-8", errors="replace")).hexdigest()[:16]


def _category(value: Any) -> str:
    """Keep only small enum-like labels in the private aggregate ledger."""
    normalized = str(value or "unknown").strip().lower().replace("-", "_")
    return normalized if re.fullmatch(r"[a-z][a-z0-9_]{0,63}", normalized) else "unknown"


def _safe_date(value: Any) -> str:
    text = str(value or "").strip()
    try:
        return dt.date.fromisoformat(text).isoformat()
    except ValueError:
        return "unknown"


def _safe_timezone(value: Any) -> str:
    text = str(value or "").strip()
    return text if SAFE_TIMEZONE.fullmatch(text) else "unknown"


def _context_window_sha256(value: Any) -> str:
    """Hash the whole context-window identity/configuration without persisting it."""
    if isinstance(value, dict):
        # ``session_meta.context_window.window_id`` is a fresh random runtime
        # identifier, not a model capability.  Comparing it would make every
        # fresh-session cohort incomparable, so retain only configuration keys
        # and a stable reference-shape marker.
        configured = {
            key: item
            for key, item in value.items()
            if not key.endswith("_id") and key != "id"
        }
        value = configured or {"window_reference": True}
    return _digest(_canonical(value))


def _context_window_tokens(value: Any) -> int | None:
    candidates: list[Any] = [value]
    if isinstance(value, dict):
        candidates = [
            value.get("tokens"),
            value.get("max_tokens"),
            value.get("context_window"),
        ]
    for candidate in candidates:
        if (
            isinstance(candidate, int)
            and not isinstance(candidate, bool)
            and candidate > 0
        ):
            return candidate
    return None


def _file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                digest.update(chunk)
    except OSError:
        return "unavailable"
    return digest.hexdigest()[:16]


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _request_key_path(ledger: Path) -> Path:
    return ledger.with_name(ledger.name + ".key")


def _request_key(path: Path = DEFAULT_REQUEST_KEY, *, create: bool = True) -> bytes:
    """Return a stable local HMAC key without ever placing it in the ledger."""
    path.parent.mkdir(parents=True, exist_ok=True)
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    lock_path = path.with_name(path.name + ".lock")
    lock_descriptor = os.open(
        lock_path,
        os.O_RDWR | os.O_CREAT | nofollow,
        0o600,
    )
    try:
        os.fchmod(lock_descriptor, 0o600)
        fcntl.flock(lock_descriptor, fcntl.LOCK_EX)
        try:
            descriptor = os.open(path, os.O_RDONLY | nofollow)
        except FileNotFoundError:
            if not create:
                raise ValueError("task request privacy key is unavailable")
            key = os.urandom(32)
            descriptor = os.open(
                path,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | nofollow,
                0o600,
            )
            try:
                os.fchmod(descriptor, 0o600)
                view = memoryview(key)
                while view:
                    written = os.write(descriptor, view)
                    view = view[written:]
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
            return key
        try:
            metadata = os.fstat(descriptor)
            if not statmod.S_ISREG(metadata.st_mode):
                raise ValueError("task request privacy key is not a regular file")
            os.fchmod(descriptor, 0o600)
            key = os.read(descriptor, 33)
        finally:
            os.close(descriptor)
        if len(key) != 32:
            raise ValueError("task request privacy key has an invalid length")
        return key
    finally:
        try:
            fcntl.flock(lock_descriptor, fcntl.LOCK_UN)
        finally:
            os.close(lock_descriptor)


def _task_request_identity(
    path: Path,
    start_ordinal: int,
    *,
    end_ordinal: int | None = None,
    key_path: Path = DEFAULT_REQUEST_KEY,
    create_key: bool = True,
) -> dict[str, Any]:
    """Keyed fingerprint of all ordered root-user inputs in the task interval."""
    requests: list[dict[str, Any]] = []
    volatile_content_keys = {
        "id",
        "metadata",
        "internal_chat_message_metadata_passthrough",
    }
    for index, row in enumerate(_rollout_rows(path)):
        ordinal = _row_ordinal(row, index)
        if ordinal <= start_ordinal:
            continue
        if end_ordinal is not None and ordinal >= end_ordinal:
            break
        payload = row.get("payload")
        if row.get("type") == "event_msg" and isinstance(payload, dict):
            if payload.get("type") == "task_started":
                break
        if (
            row.get("type") == "response_item"
            and isinstance(payload, dict)
            and payload.get("type") == "message"
            and payload.get("role") == "user"
        ):
            content = payload.get("content")
            if not isinstance(content, (list, str)):
                raise ValueError("the measured task has unrecognized user request content")
            if isinstance(content, list) and not all(isinstance(block, dict) for block in content):
                raise ValueError("the measured task has unrecognized user request blocks")
            stable_content = (
                [
                    {
                        key: value
                        for key, value in block.items()
                        if key not in volatile_content_keys
                    }
                    for block in content
                ]
                if isinstance(content, list)
                else content
            )
            requests.append({"role": "user", "content": stable_content})
    if not requests:
        raise ValueError("the measured task has no correlated user request")
    key = _request_key(key_path, create=create_key)
    return {
        "task_request_sha256": hmac.new(
            key,
            _canonical({"requests": requests}).encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()[:32],
        "task_request_count": len(requests),
        "task_request_key_sha256": hashlib.sha256(key).hexdigest()[:32],
    }


def _shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def _ledger_path() -> Path:
    override = os.environ.get("CODEX_TASK_RUN_LEDGER")
    return Path(override).expanduser() if override else DEFAULT_LEDGER


def _sessions_root() -> Path:
    override = os.environ.get("CODEX_TASK_RUN_SESSIONS_ROOT")
    return Path(override).expanduser() if override else DEFAULT_SESSIONS_ROOT


def _append_event(path: Path, row: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = (_canonical(row) + "\n").encode("utf-8")
    descriptor = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        view = memoryview(payload)
        while view:
            written = os.write(descriptor, view)
            view = view[written:]
        os.fsync(descriptor)
    finally:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        finally:
            os.close(descriptor)


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    try:
        handle = path.open(encoding="utf-8")
    except OSError:
        return rows
    with handle:
        for line in handle:
            try:
                value = json.loads(line)
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            if isinstance(value, dict):
                rows.append(value)
    return rows


def _rollout_rows(path: Path) -> list[dict[str, Any]]:
    return _read_jsonl(path)


def _row_ordinal(row: dict[str, Any], fallback: int) -> int:
    value = row.get("ordinal")
    return value if isinstance(value, int) and not isinstance(value, bool) else fallback


def _jsonl_complete(path: Path) -> bool:
    try:
        seen = False
        with path.open("rb") as handle:
            for raw in handle:
                if not raw.strip():
                    continue
                seen = True
                if not raw.endswith(b"\n") or not isinstance(json.loads(raw), dict):
                    return False
        return seen
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return False


def _task_boundaries(
    rows: Sequence[dict[str, Any]], start: dt.datetime, end: dt.datetime
) -> tuple[dict[str, int], set[str]]:
    starts: dict[str, int] = {}
    terminals: set[str] = set()
    for index, row in enumerate(rows):
        if row.get("type") != "event_msg" or not isinstance(row.get("payload"), dict):
            continue
        payload = row["payload"]
        kind = payload.get("type")
        if kind not in {"task_started", "task_complete", "turn_aborted"} or not payload.get("turn_id"):
            continue
        stamp = _timestamp(row.get("timestamp")) or _timestamp(
            payload.get("started_at")
            if kind == "task_started"
            else payload.get("completed_at")
        )
        if stamp is None or stamp < start or stamp > end:
            continue
        turn = _digest(payload["turn_id"])
        if kind == "task_started":
            starts.setdefault(turn, _row_ordinal(row, index))
        else:
            terminals.add(turn)
    return starts, terminals


def _has_matching_terminals(
    rows: Sequence[dict[str, Any]], start: dt.datetime, end: dt.datetime
) -> bool:
    starts, terminals = _task_boundaries(rows, start, end)
    return bool(starts) and set(starts) <= terminals


def _first_meta(path: Path) -> dict[str, Any] | None:
    try:
        handle = path.open(encoding="utf-8")
    except OSError:
        return None
    with handle:
        for index, line in enumerate(handle):
            # session_meta is a rollout header.  Never materialize a multi-hour
            # transcript merely to build the session catalog.
            if index >= 80:
                break
            try:
                row = json.loads(line)
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            if row.get("type") == "session_meta" and isinstance(row.get("payload"), dict):
                return row["payload"]
    return None


def _parent_thread(meta: dict[str, Any]) -> str | None:
    for key in ("parent_thread_id", "forked_from_id", "forked_from"):
        if meta.get(key):
            return str(meta[key])

    def nested(value: Any) -> str | None:
        if isinstance(value, dict):
            for key in ("parent_thread_id", "forked_from_id", "forked_from"):
                if value.get(key):
                    return str(value[key])
            for child in value.values():
                if found := nested(child):
                    return found
        elif isinstance(value, list):
            for child in value:
                if found := nested(child):
                    return found
        return None

    source = meta.get("source")
    return nested(source)


def _uuid7_date(value: str) -> dt.date | None:
    compact = value.replace("-", "").strip().lower()
    if not re.fullmatch(r"[0-9a-f]{32}", compact):
        return None
    try:
        return dt.datetime.fromtimestamp(int(compact[:12], 16) / 1000, dt.timezone.utc).date()
    except (ValueError, OverflowError, OSError):
        return None


def _day_path(root: Path, day: dt.date) -> Path:
    return root / f"{day.year:04d}" / f"{day.month:02d}" / f"{day.day:02d}"


def _session_paths(
    sessions_root: Path,
    *,
    start: dt.datetime | None = None,
    end: dt.datetime | None = None,
    extra_dates: Iterable[dt.date] = (),
    exact_id: str | None = None,
) -> list[Path]:
    paths: set[Path] = set()
    # Synthetic/test roots and older flat layouts remain cheap.
    try:
        paths.update(sessions_root.glob("*.jsonl"))
    except OSError:
        pass
    dates = set(extra_dates)
    if start is not None and end is not None:
        day = start.date() - dt.timedelta(days=1)
        final = end.date() + dt.timedelta(days=1)
        while day <= final:
            dates.add(day)
            day += dt.timedelta(days=1)
    elif exact_id and (uuid_day := _uuid7_date(exact_id)) is not None:
        dates.add(uuid_day)
    else:
        today = dt.datetime.now(dt.timezone.utc).date()
        dates.update(today - dt.timedelta(days=offset) for offset in range(15))
        dates.add(today + dt.timedelta(days=1))
    for day in dates:
        directory = _day_path(sessions_root, day)
        try:
            pattern = f"*{exact_id}*.jsonl" if exact_id else "*.jsonl"
            paths.update(directory.glob(pattern))
        except OSError:
            continue
    return sorted(paths)


def _session_catalog(
    sessions_root: Path,
    *,
    start: dt.datetime | None = None,
    end: dt.datetime | None = None,
    extra_dates: Iterable[dt.date] = (),
    paths: Iterable[Path] | None = None,
) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    selected = list(paths) if paths is not None else _session_paths(
        sessions_root, start=start, end=end, extra_dates=extra_dates
    )
    for path in selected:
        meta = _first_meta(path)
        if not meta or not meta.get("id"):
            continue
        result.append(
            {
                "path": path,
                "id": str(meta["id"]),
                "session_id": str(meta.get("session_id") or meta["id"]),
                "parent_id": _parent_thread(meta),
                "started_at": meta.get("timestamp"),
                "cli_version": str(meta.get("cli_version") or "unknown"),
                "meta": meta,
            }
        )
    return result


def _resolve_root_session(selector: str | None, sessions_root: Path) -> dict[str, Any]:
    wanted = (
        os.environ.get("CODEX_SESSION_ID")
        if selector in {None, "current"}
        else selector
    )
    if not wanted:
        raise ValueError("CODEX_SESSION_ID is unavailable; pass --session")
    direct_paths = _session_paths(sessions_root, exact_id=wanted)
    catalog = _session_catalog(sessions_root, paths=direct_paths)
    if not catalog:
        catalog = _session_catalog(sessions_root)
    matches = [
        item
        for item in catalog
        if item["id"] == wanted
        or item["session_id"] == wanted
        or _digest(item["id"]) == wanted
        or _digest(item["session_id"]) == wanted
    ]
    roots = [item for item in matches if item["id"] == item["session_id"]]
    if roots:
        return max(roots, key=lambda item: str(item.get("started_at") or ""))
    if matches:
        shared = matches[0]["session_id"]
        root_catalog = _session_catalog(
            sessions_root,
            paths=_session_paths(sessions_root, exact_id=shared),
        )
        for item in [*catalog, *root_catalog]:
            if item["id"] == shared:
                return item
    raise ValueError("no root Codex rollout matched the session selector")


def _root_session_date(item: dict[str, Any]) -> str:
    stamp = _timestamp(item.get("started_at"))
    day = stamp.date() if stamp is not None else _uuid7_date(str(item.get("id") or ""))
    return day.isoformat() if day is not None else "unknown"


def _catalog_for_run(start_event: dict[str, Any], end: dt.datetime) -> list[dict[str, Any]]:
    started = _timestamp(start_event.get("started_at"))
    if started is None:
        raise ValueError("invalid run start timestamp")
    extra: list[dt.date] = []
    try:
        root_day = dt.date.fromisoformat(str(start_event.get("root_session_date")))
        extra.append(root_day)
    except ValueError:
        root_day = started.date()
    # Reused descendants may have been born on any day since the long-lived
    # root session started, then receive a new follow-up task in this interval.
    scan_start = min(started, dt.datetime.combine(root_day, dt.time.min, dt.timezone.utc))
    return _session_catalog(
        _sessions_root(), start=scan_start, end=end, extra_dates=extra
    )


def _root_for_start(start_event: dict[str, Any]) -> dict[str, Any] | None:
    started = _timestamp(start_event.get("started_at"))
    if started is None:
        return None
    return next(
        (
            item
            for item in _catalog_for_run(start_event, started)
            if _digest(item["id"]) == start_event.get("root_thread_sha256")
        ),
        None,
    )


def _latest_task_started(path: Path, before: dt.datetime | None = None) -> dict[str, Any]:
    candidates: list[dict[str, Any]] = []
    terminal_turns: set[str] = set()
    completed_ordinals: list[int] = []
    start_ordinals: list[int] = []
    for index, row in enumerate(_rollout_rows(path)):
        payload = row.get("payload")
        if not isinstance(payload, dict) or row.get("type") != "event_msg":
            continue
        stamp = _timestamp(row.get("timestamp")) or _timestamp(
            payload.get("started_at") or payload.get("completed_at")
        )
        if stamp is None or (before is not None and stamp > before):
            continue
        if payload.get("type") in {"task_complete", "turn_aborted"} and payload.get("turn_id"):
            terminal_turns.add(str(payload["turn_id"]))
            completed_ordinals.append(_row_ordinal(row, index))
            continue
        if payload.get("type") == "task_started" and payload.get("turn_id"):
            start_ordinal = _row_ordinal(row, index)
            start_ordinals.append(start_ordinal)
            candidates.append(
                {
                    "timestamp": stamp,
                    "turn_id": str(payload["turn_id"]),
                    "index": start_ordinal,
                }
            )
    candidates = [item for item in candidates if item["turn_id"] not in terminal_turns]
    if not candidates:
        raise ValueError("no active task_started boundary was found in the root rollout")
    selected = candidates[-1]
    selected["prior_task_count"] = sum(
        ordinal < int(selected["index"]) for ordinal in start_ordinals
    )
    selected["prior_completed_turns"] = sum(
        ordinal < int(selected["index"]) for ordinal in completed_ordinals
    )
    return selected


def _terminal_boundary(path: Path, start: dict[str, Any]) -> dict[str, Any] | None:
    start_ordinal = int(start.get("start_ordinal", -1))
    turn_hash = str(start.get("task_turn_sha256") or "")
    for index, row in enumerate(_rollout_rows(path)):
        ordinal = _row_ordinal(row, index)
        if ordinal <= start_ordinal or row.get("type") != "event_msg":
            continue
        payload = row.get("payload")
        if not isinstance(payload, dict) or payload.get("type") not in {"task_complete", "turn_aborted"}:
            continue
        if _digest(payload.get("turn_id")) != turn_hash:
            continue
        stamp = _timestamp(row.get("timestamp")) or _timestamp(payload.get("completed_at"))
        if stamp is None:
            continue
        return {"ordinal": ordinal, "timestamp": stamp, "kind": str(payload["type"])}
    return None


def _bool_env(name: str, default: bool = True) -> bool:
    raw = os.environ.get(name)
    return default if raw is None else raw.strip().lower() not in FALSE_VALUES


def _int_env(name: str, default: int, minimum: int, maximum: int) -> int | str:
    del minimum, maximum  # Benchmarks require the exact canonical literal.
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        return int(raw)
    except (TypeError, ValueError):
        # Never persist the malformed value, but do keep a stable mismatch
        # sentinel instead of silently mapping it to a profile-matching default.
        return "invalid"


def _bounded_env_int(name: str, default: int, minimum: int, maximum: int) -> int:
    """Mirror the rollover hook's bounded integer environment semantics."""
    try:
        value = int(os.environ.get(name, default))
    except (TypeError, ValueError):
        value = default
    return min(maximum, max(minimum, value))


def rollover_policy(
    environment: dict[str, Any], arm: str = "unspecified"
) -> dict[str, Any]:
    """Return privacy-safe, model/session-specific rollover policy metadata."""
    context_tokens = environment.get("context_window_tokens")
    if not isinstance(context_tokens, int) or isinstance(context_tokens, bool):
        context_tokens = None
    fallback_tokens = environment.get(
        "token_budget_fallback_tokens", TOKEN_BUDGET_FALLBACK_TOKENS
    )
    if not isinstance(fallback_tokens, int) or isinstance(fallback_tokens, bool):
        fallback_tokens = TOKEN_BUDGET_FALLBACK_TOKENS
    effective_percent = environment.get("effective_context_window_percent", 95)
    if (
        not isinstance(effective_percent, int)
        or isinstance(effective_percent, bool)
        or not 0 < effective_percent <= 100
    ):
        effective_percent = 95
    reserve_fraction = (100 - effective_percent) / 100.0
    effective_max = (
        min(
            fallback_tokens,
            int(math.floor(context_tokens * reserve_fraction)),
        )
        if context_tokens
        else None
    )
    result = {
        "arm": arm if arm in ROLLOVER_ARMS else "unspecified",
        "arm_declared_before_session": arm in ROLLOVER_ARMS,
        "native_token_budget_expected_enabled": arm == "active",
        "native_token_budget_fallback_tokens": fallback_tokens,
        "native_effective_context_window_percent": effective_percent,
        "native_context_reserve_percent": 100 - effective_percent,
        "native_model_policy_available": bool(
            environment.get("model_capabilities_available", False)
        ),
        "native_model_policy_sha256": environment.get(
            "model_capabilities_sha256", "unavailable"
        ),
        "effective_token_budget_max_tokens": effective_max,
        "checkpoint_max_age_seconds": _bounded_env_int(
            "CODEX_ROLLOVER_MAX_AGE_SECONDS", 1_800, 60, 86_400
        ),
        "checkpoint_prepared_max_age_seconds": _bounded_env_int(
            "CODEX_ROLLOVER_PREPARED_MAX_AGE_SECONDS", 600, 30, 3_600
        ),
        "checkpoint_context_tokens": _bounded_env_int(
            "CODEX_ROLLOVER_CONTEXT_TOKENS", 700, 160, 1_000
        ),
        "checkpoint_telemetry": _bool_env("CODEX_ROLLOVER_TELEMETRY", True),
        "checkpoint_tool_sha256": _file_digest(
            MEMORY_DIR / "context_rollover.py"
        ),
        "policy_values_are_diagnostic_only": True,
    }
    common = {
        key: value
        for key, value in result.items()
        if key
        not in {
            "arm",
            "arm_declared_before_session",
            "native_token_budget_expected_enabled",
        }
    }
    result["common_policy_sha256"] = _digest(_canonical(common))
    result["policy_sha256"] = _digest(_canonical(result))
    return result


def rollover_profile_environment(arm: str) -> dict[str, str]:
    if arm not in ROLLOVER_ARMS:
        raise ValueError("rollover arm must be control or active")
    return {
        **profile_environment("active"),
        "CODEX_TASK_RUN_ROLLOVER_ARM": arm,
        "CODEX_ROLLOVER_MAX_AGE_SECONDS": "1800",
        "CODEX_ROLLOVER_PREPARED_MAX_AGE_SECONDS": "600",
        "CODEX_ROLLOVER_CONTEXT_TOKENS": "700",
        "CODEX_ROLLOVER_TELEMETRY": "1",
    }


def _memory_config_identity() -> dict[str, Any]:
    raw = os.environ.get("CODEX_MEMORY_CONFIG") or str(MEMORY_DIR / "config.json")
    path = Path(raw).expanduser()
    if not path.is_absolute():
        path = ROOT / path
    path = path.resolve()
    try:
        runtime = _load_memory_module().load_runtime(path, root=ROOT)
        content_sha256 = str(runtime.config_sha256)[:16]
        secondary = str(runtime.config.get("adoption", {}).get("secondary_mode", "inject")).lower()
        manifest_sha256 = _file_digest(runtime.manifest_path)
        state_path_sha256 = _digest(str(runtime.state_dir))
        available = True
    except (OSError, RuntimeError, ValueError, TypeError):
        content_sha256 = "unavailable"
        secondary = "invalid"
        manifest_sha256 = "unavailable"
        state_path_sha256 = "unavailable"
        available = False
    path_sha256 = _digest(str(path))
    return {
        "path_sha256": path_sha256,
        "content_sha256": content_sha256,
        "effective_sha256": _digest(
            _canonical({"path": path_sha256, "content": content_sha256})
        ),
        "available": available,
        "secondary_mode": secondary,
        "manifest_sha256": manifest_sha256,
        "state_path_sha256": state_path_sha256,
    }


def effective_policy() -> dict[str, Any]:
    memory_config = _memory_config_identity()
    secondary = os.environ.get("CODEX_MEMORY_SECONDARY_MODE", memory_config["secondary_mode"]).strip().lower()
    declared_variant = os.environ.get("CODEX_TASK_RUN_VARIANT", "unknown").strip().lower()
    return {
        "task_run_variant": (
            declared_variant
            if declared_variant in {"off", "shadow", "active"}
            else "unknown"
        ),
        "graphify_reminder": _bool_env("GRAPHIFY_CODEX_REMINDER"),
        "graphify_enforce": _bool_env("GRAPHIFY_CODEX_ENFORCE"),
        "graphify_affected_enforce": _bool_env("GRAPHIFY_CODEX_AFFECTED_ENFORCE"),
        "graphify_telemetry": _bool_env("GRAPHIFY_CONTEXT_LOG"),
        "graphify_observe_only": _bool_env("GRAPHIFY_CODEX_OBSERVE_ONLY", False),
        "graphify_debug": _bool_env("GRAPHIFY_CODEX_REMINDER_DEBUG", False),
        "graphify_ceiling": _int_env("GRAPHIFY_CODEX_REMINDER_CEILING", 10, 1, 10_000),
        "graphify_batch_budget": _int_env("GRAPHIFY_CODEX_REMINDER_BATCH_BUDGET", 8, 1, 1_000),
        "graphify_state_dir_sha256": _digest(os.environ.get("GRAPHIFY_CODEX_REMINDER_STATE_DIR", "default")),
        "memory_reminder": _bool_env("CODEX_MEMORY_REMINDER"),
        "memory_auto_recall": _bool_env("CODEX_MEMORY_AUTO_RECALL"),
        "memory_repeat_guard": _bool_env("CODEX_MEMORY_REPEAT_GUARD"),
        "memory_telemetry": _bool_env("CODEX_MEMORY_TELEMETRY"),
        "memory_observe_only": _bool_env("CODEX_MEMORY_OBSERVE_ONLY", False),
        "memory_debug": _bool_env("CODEX_MEMORY_REMINDER_DEBUG", False),
        "memory_ceiling": _int_env("CODEX_MEMORY_REMINDER_CEILING", 4, 1, 1_000),
        "memory_primary_idle_seconds": _int_env("CODEX_MEMORY_PRIMARY_IDLE_SECONDS", 86_400, 0, 31_536_000),
        "memory_secondary_budget": _int_env("CODEX_MEMORY_SECONDARY_BUDGET", 300, 80, 900),
        "memory_secondary_min_raw_tokens": _int_env("CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS", 300, 0, 1_000_000),
        "memory_targeted_read_lines": _int_env("CODEX_MEMORY_TARGETED_READ_LINES", 120, 1, 10_000),
        "memory_repeat_guard_budget": _int_env("CODEX_MEMORY_REPEAT_GUARD_BUDGET", 300, 80, 900),
        "memory_primary_read": _bool_env("CODEX_MEMORY_PRIMARY_READ", False),
        "memory_primary_output_bypass": _bool_env("CODEX_MEMORY_PRIMARY_OUTPUT_BYPASS", False),
        "memory_secondary_bypass": _bool_env("CODEX_MEMORY_SECONDARY_BYPASS", False),
        "memory_repeat_guard_bypass": _bool_env("CODEX_MEMORY_REPEAT_GUARD_BYPASS", False),
        "memory_config_path_sha256": memory_config["path_sha256"],
        "memory_config_content_sha256": memory_config["content_sha256"],
        "memory_config_available": memory_config["available"],
        "memory_secondary_mode": secondary if secondary in {"off", "shadow", "inject", "enforce"} else "invalid",
    }


def _policy_tuning_sha256(policy: dict[str, Any]) -> str:
    """Fingerprint policy knobs that must remain equal across all cohorts."""
    return _digest(_canonical({key: policy.get(key) for key in POLICY_TUNING_KEYS}))


def profile_mismatches(variant: str, policy: dict[str, Any]) -> list[str]:
    checks: dict[str, Any]
    if variant == "off":
        checks = {
            "task_run_variant": "off",
            "graphify_reminder": False,
            "graphify_enforce": False,
            "graphify_affected_enforce": False,
            "graphify_telemetry": True,
            "graphify_observe_only": False,
            "graphify_debug": False,
            "memory_reminder": False,
            "memory_auto_recall": False,
            "memory_repeat_guard": False,
            "memory_telemetry": True,
            "memory_observe_only": False,
            "memory_debug": False,
            "memory_secondary_mode": "off",
        }
    elif variant == "shadow":
        checks = {
            "task_run_variant": "shadow",
            "graphify_reminder": True,
            "graphify_enforce": False,
            "graphify_affected_enforce": False,
            "graphify_telemetry": True,
            "graphify_observe_only": True,
            "graphify_debug": False,
            "memory_reminder": True,
            "memory_auto_recall": True,
            "memory_repeat_guard": False,
            "memory_telemetry": True,
            "memory_observe_only": True,
            "memory_debug": False,
            "memory_secondary_mode": "shadow",
        }
    else:
        checks = {
            "task_run_variant": "active",
            "graphify_reminder": True,
            "graphify_enforce": True,
            "graphify_affected_enforce": True,
            "graphify_telemetry": True,
            "memory_reminder": True,
            "memory_auto_recall": True,
            "memory_repeat_guard": True,
            "memory_telemetry": True,
            "graphify_observe_only": False,
            "memory_observe_only": False,
            "graphify_debug": False,
            "memory_debug": False,
            "memory_secondary_mode": "inject",
        }
    result = [name for name, expected in checks.items() if policy.get(name) != expected]
    # ``effective_policy`` always supplies every tuning key.  Default missing
    # values only preserve the import-level helper's compatibility with older
    # synthetic fixtures; the CLI path still validates the full environment.
    result.extend(
        name
        for name, expected in POLICY_TUNING_DEFAULTS.items()
        if policy.get(name, expected) != expected
    )
    canonical_config = _digest(str((MEMORY_DIR / "config.json").resolve()))
    if policy.get("memory_config_path_sha256", canonical_config) != canonical_config:
        result.append("memory_config_path_sha256")
    if policy.get("memory_config_available", True) is not True:
        result.append("memory_config_available")
    return sorted(set(result))


def profile_environment(variant: str) -> dict[str, str]:
    common = {
        "CODEX_MEMORY_CONFIG": str((MEMORY_DIR / "config.json").resolve()),
        "CODEX_TASK_RUN_ROLLOVER_ARM": "unspecified",
        "GRAPHIFY_CODEX_REMINDER_CEILING": "10",
        "GRAPHIFY_CODEX_REMINDER_BATCH_BUDGET": "8",
        "GRAPHIFY_CODEX_REMINDER_DEBUG": "0",
        "GRAPHIFY_CONTEXT_LOG": "1",
        "CODEX_MEMORY_REMINDER_CEILING": "4",
        "CODEX_MEMORY_PRIMARY_IDLE_SECONDS": "86400",
        "CODEX_MEMORY_SECONDARY_BUDGET": "300",
        "CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS": "300",
        "CODEX_MEMORY_TARGETED_READ_LINES": "120",
        "CODEX_MEMORY_REPEAT_GUARD_BUDGET": "300",
        "CODEX_MEMORY_REMINDER_DEBUG": "0",
        "CODEX_MEMORY_TELEMETRY": "1",
        # Set one-shot flags explicitly so inherited shell values cannot
        # silently change a benchmark cohort.
        "CODEX_MEMORY_PRIMARY_READ": "0",
        "CODEX_MEMORY_PRIMARY_OUTPUT_BYPASS": "0",
        "CODEX_MEMORY_SECONDARY_BYPASS": "0",
        "CODEX_MEMORY_REPEAT_GUARD_BYPASS": "0",
    }
    if variant == "off":
        return {
            **common,
            "CODEX_TASK_RUN_VARIANT": "off",
            "GRAPHIFY_CODEX_REMINDER": "0",
            "GRAPHIFY_CODEX_ENFORCE": "0",
            "GRAPHIFY_CODEX_AFFECTED_ENFORCE": "0",
            "GRAPHIFY_CODEX_OBSERVE_ONLY": "0",
            "CODEX_MEMORY_REMINDER": "0",
            "CODEX_MEMORY_AUTO_RECALL": "0",
            "CODEX_MEMORY_REPEAT_GUARD": "0",
            "CODEX_MEMORY_SECONDARY_MODE": "off",
            "CODEX_MEMORY_OBSERVE_ONLY": "0",
        }
    if variant == "shadow":
        return {
            **common,
            "CODEX_TASK_RUN_VARIANT": "shadow",
            "GRAPHIFY_CODEX_REMINDER": "1",
            "GRAPHIFY_CODEX_ENFORCE": "0",
            "GRAPHIFY_CODEX_AFFECTED_ENFORCE": "0",
            "GRAPHIFY_CODEX_OBSERVE_ONLY": "1",
            "CODEX_MEMORY_REMINDER": "1",
            "CODEX_MEMORY_AUTO_RECALL": "1",
            "CODEX_MEMORY_REPEAT_GUARD": "0",
            "CODEX_MEMORY_SECONDARY_MODE": "shadow",
            "CODEX_MEMORY_OBSERVE_ONLY": "1",
        }
    return {
        **common,
        "CODEX_TASK_RUN_VARIANT": "active",
        "GRAPHIFY_CODEX_REMINDER": "1",
        "GRAPHIFY_CODEX_ENFORCE": "1",
        "GRAPHIFY_CODEX_AFFECTED_ENFORCE": "1",
        "CODEX_MEMORY_REMINDER": "1",
        "CODEX_MEMORY_AUTO_RECALL": "1",
        "CODEX_MEMORY_REPEAT_GUARD": "1",
        "CODEX_MEMORY_SECONDARY_MODE": "inject",
        "GRAPHIFY_CODEX_OBSERVE_ONLY": "0",
        "CODEX_MEMORY_OBSERVE_ONLY": "0",
    }


def _git(*args: str) -> str | None:
    try:
        result = subprocess.run(
            ["git", *args], cwd=ROOT, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, check=True, text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return result.stdout


def repo_fingerprint() -> dict[str, Any]:
    head = (_git("rev-parse", "HEAD") or "unavailable").strip()
    status = _git("status", "--porcelain=v1", "-z", "--untracked-files=all")
    changed = _git("ls-files", "-m", "-d", "-o", "--exclude-standard", "-z")
    staged = _git(
        "diff",
        "--cached",
        "--name-only",
        "-z",
        "--diff-filter=ACDMRTUXB",
    )

    def derived(relative: str) -> bool:
        normalized = relative.lstrip("./")
        return normalized == "graphify-out" or normalized.startswith("graphify-out/") or normalized == "graphify-arch/graphify-out" or normalized.startswith("graphify-arch/graphify-out/") or normalized == "codex-memory/state" or normalized.startswith("codex-memory/state/")

    status_entries: list[tuple[str, str]] = []
    status_parts = [value for value in (status or "").split("\0") if value]
    index = 0
    while index < len(status_parts):
        entry = status_parts[index]
        code = entry[:2].strip() or "unknown"
        relative = entry[3:] if len(entry) > 3 else ""
        if relative and not derived(relative):
            status_entries.append((code, relative))
        if any(marker in entry[:2] for marker in ("R", "C")) and index + 1 < len(status_parts):
            index += 1
            prior = status_parts[index]
            if prior and not derived(prior):
                status_entries.append(("prior", prior))
        index += 1

    paths = {
        value
        for value in [
            *((changed or "").split("\0")),
            *((staged or "").split("\0")),
            *(relative for _, relative in status_entries),
        ]
        if value and not derived(value)
    }
    worktree = hashlib.sha256()
    worktree.update(_canonical(sorted(status_entries)).encode())
    for relative in sorted(paths):
        worktree.update(b"\0path\0")
        worktree.update(relative.encode("utf-8", errors="surrogateescape"))
        candidate = ROOT / relative
        try:
            candidate.absolute().relative_to(ROOT.absolute())
            metadata = candidate.lstat()
            worktree.update(str(statmod.S_IMODE(metadata.st_mode)).encode())
            if statmod.S_ISLNK(metadata.st_mode):
                worktree.update(b"\0symlink\0")
                worktree.update(os.readlink(candidate).encode("utf-8", errors="surrogateescape"))
            elif statmod.S_ISREG(metadata.st_mode):
                worktree.update(b"\0file\0")
                with candidate.open("rb") as handle:
                    while chunk := handle.read(1024 * 1024):
                        worktree.update(chunk)
            elif statmod.S_ISDIR(metadata.st_mode):
                worktree.update(b"\0directory-or-submodule\0")
                try:
                    submodule = subprocess.run(
                        ["git", "-C", str(candidate), "rev-parse", "HEAD"],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL,
                        check=True,
                    ).stdout
                except (OSError, subprocess.CalledProcessError):
                    submodule = b"unavailable"
                worktree.update(submodule)
            else:
                worktree.update(b"\0special\0")
        except FileNotFoundError:
            worktree.update(b"\0deleted\0")
        except (OSError, ValueError):
            worktree.update(b"unavailable")
    codes = Counter(
        "untracked" if code == "??" else "ignored" if code == "!!" else code
        for code, _ in status_entries
    )
    digest = worktree.hexdigest()[:16]
    return {
        "head_sha256": _digest(head),
        "worktree_sha256": digest,
        "patch_sha256": digest,
        "dirty": bool(status_entries),
        "change_count": len(status_entries),
        "change_counts": dict(sorted(codes.items())),
    }


def tool_fingerprints() -> dict[str, str]:
    memory_config = _memory_config_identity()
    try:
        graphify_version = subprocess.run(
            ["graphify", "--version"], cwd=ROOT, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, check=False, text=True, timeout=5,
        ).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        graphify_version = "unavailable"
    values = {
        "memory_config": memory_config["effective_sha256"],
        "memory_config_path": memory_config["path_sha256"],
        "memory_config_content": memory_config["content_sha256"],
        "memory_graph": memory_config["manifest_sha256"],
        "memory_state_path": memory_config["state_path_sha256"],
        "memory_tool": _file_digest(MEMORY_DIR / "memory.py"),
        "memory_hook": _file_digest(MEMORY_DIR / "codex_memory_reminder.py"),
        "rollover_tool": _file_digest(MEMORY_DIR / "context_rollover.py"),
        "graphify_arch": _file_digest(ROOT / "graphify-arch" / "graphify-out" / "manifest.json"),
        "graphify_full": _file_digest(ROOT / "graphify-out" / "manifest.json"),
        "graphify_tool": _file_digest(ROOT / "graphify-arch" / "tdd_context.py"),
        "graphify_hook": _file_digest(ROOT / "graphify-arch" / "codex_graphify_reminder.py"),
        "coordinator": _file_digest(MEMORY_DIR / "task_run.py"),
        "hooks": _file_digest(ROOT / ".codex" / "hooks.json"),
        "graphify_runtime": _digest(graphify_version or "unavailable"),
        "python_runtime": _digest(sys.version),
    }
    values["policy_code_sha256"] = _digest(
        _canonical(
            {
                key: values[key]
                for key in (
                    "memory_config",
                    "memory_tool",
                    "memory_hook",
                    "rollover_tool",
                    "graphify_tool",
                    "graphify_hook",
                    "graphify_runtime",
                    "python_runtime",
                    "coordinator",
                    "hooks",
                )
            }
        )
    )
    return values


def _codex_model_capabilities(model: str) -> dict[str, Any]:
    path = (
        Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
        / "models_cache.json"
    )
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        value = {}
    selected = next(
        (
            item
            for item in value.get("models", [])
            if isinstance(item, dict)
            and str(item.get("slug") or item.get("id") or "") == model
        ),
        {},
    )

    def positive_int(raw: Any) -> int | None:
        return (
            int(raw)
            if isinstance(raw, int)
            and not isinstance(raw, bool)
            and raw > 0
            else None
        )

    messages = selected.get("model_messages")
    if not isinstance(messages, dict):
        messages = {}
    budget = selected.get("token_budget", messages.get("token_budget"))
    if not isinstance(budget, dict):
        budget = {}
    context = positive_int(selected.get("context_window"))
    maximum = positive_int(selected.get("max_context_window"))
    effective = positive_int(selected.get("effective_context_window_percent"))
    fallback = positive_int(budget.get("auto_compact_fallback_buffer_tokens"))
    result = {
        "context_window_tokens": context,
        "max_context_window_tokens": maximum,
        "effective_context_window_percent": effective,
        "token_budget_fallback_tokens": fallback,
        "available": bool(context and effective and fallback),
    }
    result["sha256"] = _digest(_canonical(result))
    return result


def _codex_config() -> dict[str, Any]:
    config = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))) / "config.toml"
    try:
        value = tomllib.loads(config.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        value = {}
    return {
        "model": str(value.get("model") or os.environ.get("CODEX_MODEL") or "unknown"),
        "reasoning_effort": str(value.get("model_reasoning_effort") or os.environ.get("CODEX_REASONING_EFFORT") or "unknown"),
        "service_tier": str(value.get("service_tier") or os.environ.get("CODEX_SERVICE_TIER") or "unknown"),
    }


def _task_environment(
    path: Path,
    turn_id: str,
    cli_version: str,
    start_ordinal: int,
    *,
    request_key_path: Path = DEFAULT_REQUEST_KEY,
) -> dict[str, Any]:
    result = _codex_config()
    result["cli_version"] = cli_version
    session_meta = _first_meta(path) or {}
    provider = session_meta.get("model_provider") or "unknown"
    context_window = session_meta.get("context_window", "unknown")
    result.update(
        {
            "model_provider": _category(provider),
            "model_provider_sha256": _digest(provider),
            "context_window_sha256": _context_window_sha256(
                context_window
            ),
            "context_window_tokens": _context_window_tokens(context_window),
        }
    )
    for index, row in enumerate(_rollout_rows(path)):
        ordinal = _row_ordinal(row, index)
        payload = row.get("payload")
        if (
            ordinal <= start_ordinal
            and row.get("type") == "event_msg"
            and isinstance(payload, dict)
            and payload.get("type") == "thread_settings_applied"
            and isinstance(payload.get("thread_settings"), dict)
        ):
            settings = payload["thread_settings"]
            if settings.get("model"):
                result["model"] = str(settings["model"])
            if settings.get("reasoning_effort"):
                result["reasoning_effort"] = str(settings["reasoning_effort"])
            if settings.get("service_tier"):
                result["service_tier"] = str(settings["service_tier"])
        if row.get("type") != "turn_context" or not isinstance(row.get("payload"), dict):
            continue
        payload = row["payload"]
        if str(payload.get("turn_id") or "") != turn_id:
            continue
        if payload.get("model"):
            result["model"] = str(payload["model"])
        if payload.get("effort"):
            result["reasoning_effort"] = str(payload["effort"])
        request_key = _request_key(request_key_path)
        result.update(
            {
                "collaboration_mode_sha256": _digest(_canonical(payload.get("collaboration_mode"))),
                "multi_agent_version_sha256": _digest(payload.get("multi_agent_version")),
                "approval_policy": _category(payload.get("approval_policy")),
                "permission_profile_sha256": _digest(_canonical(payload.get("permission_profile"))),
                "sandbox_policy_sha256": _digest(_canonical(payload.get("sandbox_policy"))),
                "personality_sha256": _digest(payload.get("personality")),
                "realtime_active": bool(payload.get("realtime_active")),
                "comp_sha256": (
                    str(payload.get("comp_hash"))[:16]
                    if re.fullmatch(r"[0-9a-fA-F]{16,64}", str(payload.get("comp_hash") or ""))
                    else _digest(payload.get("comp_hash"))
                ),
                "current_date": _safe_date(payload.get("current_date")),
                "timezone": _safe_timezone(payload.get("timezone")),
                "cwd_sha256": hmac.new(
                    request_key,
                    _canonical(payload.get("cwd")).encode("utf-8"),
                    hashlib.sha256,
                ).hexdigest()[:32],
                "cwd_available": isinstance(payload.get("cwd"), str),
                "workspace_roots_sha256": hmac.new(
                    request_key,
                    _canonical(payload.get("workspace_roots")).encode("utf-8"),
                    hashlib.sha256,
                ).hexdigest()[:32],
                "workspace_roots_available": isinstance(
                    payload.get("workspace_roots"), list
                ),
            }
        )
    capabilities = _codex_model_capabilities(str(result.get("model") or "unknown"))
    if result.get("context_window_tokens") is None:
        result["context_window_tokens"] = capabilities["context_window_tokens"]
    result.update(
        {
            "max_context_window_tokens": capabilities[
                "max_context_window_tokens"
            ],
            "effective_context_window_percent": capabilities[
                "effective_context_window_percent"
            ],
            "token_budget_fallback_tokens": capabilities[
                "token_budget_fallback_tokens"
            ],
            "model_capabilities_available": capabilities["available"],
            "model_capabilities_sha256": capabilities["sha256"],
        }
    )
    return result


def _normalize_gate(value: str) -> str:
    normalized = value.strip().lower()
    if not GATE_ID.fullmatch(normalized):
        raise ValueError(f"invalid gate ID {value!r}; use 1-64 lowercase allowlisted characters")
    return normalized


def _gate_args(values: Iterable[Any]) -> list[str]:
    flattened: list[str] = []
    for value in values:
        if isinstance(value, (list, tuple)):
            flattened.extend(str(item) for item in value)
        else:
            flattened.append(str(value))
    return flattened


def _token_values(raw: Any) -> dict[str, int | None]:
    value = raw if isinstance(raw, dict) else {}
    result: dict[str, int | None] = {}
    for output, source in TOKEN_KEYS.items():
        item = value.get(source)
        result[output] = item if isinstance(item, int) and not isinstance(item, bool) and item >= 0 else None
    return result


def _validate_token_vector(value: dict[str, int | None]) -> bool:
    if any(item is not None and item < 0 for item in value.values()):
        return False
    if value["cached_input"] is not None and value["input"] is not None and value["cached_input"] > value["input"]:
        return False
    if value["reasoning_output"] is not None and value["output"] is not None and value["reasoning_output"] > value["output"]:
        return False
    if value["total"] is not None and value["input"] is not None and value["output"] is not None:
        return value["total"] == value["input"] + value["output"]
    return True


def _vector_equal(left: dict[str, int | None], right: dict[str, int | None]) -> bool:
    return all(left[key] == right[key] for key in TOKEN_KEYS)


def token_interval(
    rows: Sequence[dict[str, Any]], start: dt.datetime, end: dt.datetime,
    *, require_baseline: bool = False, start_ordinal: int | None = None,
    end_ordinal: int | None = None,
) -> dict[str, Any]:
    """Return cumulative-prefix interval tokens, preserving subset fields.

    Duplicate cumulative snapshots add nothing.  A decrease begins a new
    cumulative epoch and contributes that epoch's current total.  Every
    non-zero contribution is checked against ``last_token_usage``.
    """
    events: list[tuple[int, dt.datetime, dict[str, int | None], dict[str, int | None]]] = []
    for index, row in enumerate(rows):
        ordinal = _row_ordinal(row, index)
        stamp = _timestamp(row.get("timestamp"))
        payload = row.get("payload")
        if stamp is None or not isinstance(payload, dict):
            continue
        if (
            row.get("type") != "event_msg"
            or payload.get("type") != "token_count"
            or (end_ordinal is not None and ordinal > end_ordinal)
        ):
            continue
        info = payload.get("info")
        if not isinstance(info, dict) or (end_ordinal is None and stamp > end):
            continue
        events.append((ordinal, stamp, _token_values(info.get("total_token_usage")), _token_values(info.get("last_token_usage"))))
    prefix = {key: 0 for key in TOKEN_KEYS}
    available = {key: True for key in TOKEN_KEYS}
    previous: dict[str, int | None] | None = None
    base = {key: 0 for key in TOKEN_KEYS}
    base_available = dict(available)
    base_captured = False
    duplicates_before = duplicates_interval = 0
    resets_before = resets_interval = 0
    requests = 0
    errors: list[str] = []
    in_scope_snapshots = 0
    for ordinal, stamp, total, last in events:
        in_interval = ordinal > start_ordinal if start_ordinal is not None else stamp >= start
        if in_interval:
            in_scope_snapshots += 1
        if in_interval and not base_captured:
            base = dict(prefix)
            base_available = dict(available)
            base_captured = True
        if not _validate_token_vector(total) and in_interval:
            errors.append("invalid_token_invariants")
        comparable = [key for key in TOKEN_KEYS if total[key] is not None and previous is not None and previous[key] is not None]
        duplicate = previous is not None and bool(comparable) and all(total[key] == previous[key] for key in comparable) and all((total[key] is None) == (previous[key] is None) for key in TOKEN_KEYS)
        reset = previous is not None and any(total[key] < previous[key] for key in comparable) if comparable else False
        delta: dict[str, int | None] = {}
        if previous is None and in_interval:
            # There may be no snapshot between task_started and the prior
            # request.  The first in-scope row still has an exact boundary:
            # total-last is its implicit baseline and last is this task's first
            # model request.  Counting total would leak whole-session usage.
            delta = dict(last)
            if any(last[key] is None for key in ("input", "output", "total")):
                errors.append("missing_first_last_usage")
            inferred_baseline = {
                key: (
                    total[key] - last[key]
                    if total[key] is not None and last[key] is not None
                    else None
                )
                for key in TOKEN_KEYS
            }
            if not _validate_token_vector(inferred_baseline):
                errors.append("invalid_inferred_baseline")
            for key in TOKEN_KEYS:
                if total[key] is not None and last[key] is not None and total[key] < last[key]:
                    errors.append("invalid_inferred_baseline")
        elif previous is None or reset:
            delta = dict(total)
        elif duplicate:
            delta = {key: 0 if total[key] is not None else None for key in TOKEN_KEYS}
        else:
            for key in TOKEN_KEYS:
                delta[key] = total[key] - previous[key] if total[key] is not None and previous[key] is not None else None
        nonzero = any((value or 0) > 0 for value in delta.values())
        if duplicate:
            if in_interval:
                duplicates_interval += 1
            else:
                duplicates_before += 1
        if reset:
            if in_interval:
                resets_interval += 1
            else:
                resets_before += 1
        for key in TOKEN_KEYS:
            if delta[key] is None:
                available[key] = False
        if nonzero:
            if in_interval:
                requests += 1
                if not _validate_token_vector(last):
                    errors.append("invalid_token_invariants")
            for key in TOKEN_KEYS:
                if delta[key] is not None:
                    prefix[key] += int(delta[key])
            if not _vector_equal(delta, last) and in_interval:
                errors.append("last_usage_mismatch")
        previous = total
    if not base_captured:
        base = dict(prefix)
        base_available = dict(available)
    if require_baseline and in_scope_snapshots == 0:
        errors.append("no_token_snapshot_in_interval")
    totals: dict[str, int | None] = {}
    for key in TOKEN_KEYS:
        valid = available[key] and base_available[key]
        totals[key] = prefix[key] - base[key] if valid else None
    essential = all(
        totals[key] is not None
        for key in ("input", "cached_input", "output", "reasoning_output", "total")
    )
    uncached = (
        totals["input"] - totals["cached_input"]
        if totals["input"] is not None and totals["cached_input"] is not None
        else None
    )
    return {
        **totals,
        "uncached_input": uncached,
        "request_count": requests,
        "duplicate_snapshots": duplicates_interval,
        "reset_epochs": resets_interval,
        "exact": essential and not errors,
        "errors": sorted(set(errors)),
    }


def _empty_token_metrics() -> dict[str, Any]:
    return {
        **{key: 0 for key in TOKEN_KEYS},
        "uncached_input": 0,
        "request_count": 0,
        "duplicate_snapshots": 0,
        "reset_epochs": 0,
        "exact": True,
        "errors": [],
    }


def _unavailable_token_metrics(reason: str) -> dict[str, Any]:
    return {
        **{key: None for key in TOKEN_KEYS},
        "uncached_input": None,
        "request_count": 0,
        "duplicate_snapshots": 0,
        "reset_epochs": 0,
        "exact": False,
        "errors": [reason],
    }


def _token_slice(value: dict[str, Any]) -> dict[str, Any]:
    return {
        key: value.get(key)
        for key in (
            *TOKEN_KEYS,
            "uncached_input",
            "request_count",
            "exact",
            "errors",
        )
    }


def _row_in_rollout_interval(
    row: dict[str, Any],
    index: int,
    start: dt.datetime,
    end: dt.datetime,
    *,
    start_ordinal: int | None,
    end_ordinal: int | None,
) -> bool:
    ordinal = _row_ordinal(row, index)
    stamp = _timestamp(row.get("timestamp"))
    if stamp is None:
        return False
    after_start = ordinal > start_ordinal if start_ordinal is not None else stamp >= start
    before_end = ordinal <= end_ordinal if end_ordinal is not None else stamp <= end
    return after_start and before_end


def _rollover_event_kind(row: dict[str, Any]) -> str | None:
    if row.get("type") == "compacted":
        return "completion"
    payload = row.get("payload") if isinstance(row.get("payload"), dict) else {}
    raw = payload.get("type") or payload.get("event") or row.get("event") or row.get("type")
    name = _category(raw)
    if name in ROLLOVER_FAILURE_EVENTS or re.search(r"(?:rollover|compact|new_context).*(?:fail|blocked|stale)$", name):
        return "failure"
    if name in ROLLOVER_COMPLETION_EVENTS or re.search(r"(?:rollover|compact|new_context).*(?:complete|completed|resumed)$", name):
        return "completion"
    if name in ROLLOVER_ATTEMPT_EVENTS or re.search(r"(?:rollover|compact|new_context).*(?:attempt|requested|started|allowed)$", name):
        return "attempt"
    return None


def _json_bytes(value: Any) -> int:
    encoder = json.JSONEncoder(
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    )
    return sum(len(chunk.encode("utf-8")) for chunk in encoder.iterencode(value))


def _checkpoint_measurement(payload: dict[str, Any]) -> tuple[int, int, str]:
    explicit_bytes = next(
        (
            payload.get(key)
            for key in ("checkpoint_bytes", "checkpoint_size_bytes")
            if isinstance(payload.get(key), int)
            and not isinstance(payload.get(key), bool)
            and payload.get(key) >= 0
        ),
        None,
    )
    explicit_tokens = next(
        (
            payload.get(key)
            for key in ("checkpoint_tokens_estimate", "checkpoint_token_estimate", "checkpoint_tokens")
            if isinstance(payload.get(key), int)
            and not isinstance(payload.get(key), bool)
            and payload.get(key) >= 0
        ),
        None,
    )
    if explicit_bytes is not None:
        byte_count = int(explicit_bytes)
        token_count = int(explicit_tokens) if explicit_tokens is not None else math.ceil(byte_count / 4)
        return byte_count, token_count, "explicit" if explicit_tokens is not None else "explicit_bytes_div4"
    if "replacement_history" in payload:
        byte_count = _json_bytes(payload.get("replacement_history"))
        return byte_count, math.ceil(byte_count / 4), "rollout_bytes_div4"
    return 0, int(explicit_tokens or 0), "explicit_tokens" if explicit_tokens is not None else "unavailable"


def _rollover_identity(row: dict[str, Any], index: int) -> str:
    payload = row.get("payload") if isinstance(row.get("payload"), dict) else {}
    for key in ("window_id", "rollover_id", "checkpoint_sha256", "call_id"):
        if payload.get(key):
            return f"{key}:{_digest(payload[key])}"
    return f"ordinal:{_row_ordinal(row, index)}"


def _is_new_context_call(row: dict[str, Any]) -> bool:
    payload = row.get("payload")
    if not isinstance(payload, dict) or payload.get("type") not in {
        "custom_tool_call",
        "function_call",
    }:
        return False
    name = str(payload.get("name") or payload.get("tool_name") or "")
    return name.rsplit(".", 1)[-1].strip().lower() == "new_context"


def _row_turn_sha256(row: dict[str, Any]) -> str | None:
    """Return only a privacy-safe turn identity from known rollout shapes."""
    payload = row.get("payload") if isinstance(row.get("payload"), dict) else {}
    metadata = payload.get("internal_chat_message_metadata_passthrough")
    item = payload.get("item") if isinstance(payload.get("item"), dict) else {}
    candidates = (
        payload.get("turn_id"),
        metadata.get("turn_id") if isinstance(metadata, dict) else None,
        item.get("turn_id"),
        row.get("turn_id"),
    )
    for candidate in candidates:
        if isinstance(candidate, str) and candidate.strip():
            return _digest(candidate)
    return None


def _rollout_rollover_metrics(
    rows: Sequence[dict[str, Any]],
    start: dt.datetime,
    end: dt.datetime,
    *,
    start_ordinal: int | None,
    end_ordinal: int | None,
) -> dict[str, Any]:
    records: list[tuple[int, str, dict[str, Any], str]] = []
    compacted_transition_ids: set[str] = set()
    new_context_calls = 0
    new_context_evidence: list[dict[str, Any]] = []
    compacted_evidence: list[dict[str, Any]] = []
    task_start_evidence: list[dict[str, Any]] = []
    user_message_evidence: list[dict[str, Any]] = []
    terminal_evidence: list[dict[str, Any]] = []
    active_turn_sha256: str | None = None
    for index, row in enumerate(rows):
        payload = row.get("payload") if isinstance(row.get("payload"), dict) else {}
        payload_type = _category(payload.get("type"))
        if payload_type == "task_started" or _category(row.get("type")) == "turn_context":
            active_turn_sha256 = _row_turn_sha256(row) or active_turn_sha256
        if not _row_in_rollout_interval(
            row,
            index,
            start,
            end,
            start_ordinal=start_ordinal,
            end_ordinal=end_ordinal,
        ):
            continue
        stamp = _timestamp(row.get("timestamp"))
        if payload_type == "task_started":
            task_start_evidence.append(
                {
                    "timestamp": stamp.isoformat() if stamp is not None else None,
                    "ordinal": _row_ordinal(row, index),
                    "turn_sha256": _row_turn_sha256(row) or active_turn_sha256,
                }
            )
        elif payload_type == "message" and _category(payload.get("role")) == "user":
            user_message_evidence.append(
                {
                    "timestamp": stamp.isoformat() if stamp is not None else None,
                    "ordinal": _row_ordinal(row, index),
                }
            )
        elif payload_type in {"task_complete", "turn_aborted"}:
            terminal_evidence.append(
                {
                    "timestamp": stamp.isoformat() if stamp is not None else None,
                    "ordinal": _row_ordinal(row, index),
                    "turn_sha256": _row_turn_sha256(row) or active_turn_sha256,
                    "kind": payload_type,
                }
            )
        if _is_new_context_call(row):
            new_context_calls += 1
            new_context_evidence.append(
                {
                    "timestamp": stamp.isoformat() if stamp is not None else None,
                    "ordinal": _row_ordinal(row, index),
                    "turn_sha256": _row_turn_sha256(row) or active_turn_sha256,
                }
            )
        kind = _rollover_event_kind(row)
        if kind:
            identity = _rollover_identity(row, index)
            if row.get("type") == "compacted":
                compacted_transition_ids.add(identity)
                compacted_evidence.append(
                    {
                        "timestamp": (
                            stamp.isoformat() if stamp is not None else None
                        ),
                        "ordinal": _row_ordinal(row, index),
                        "turn_sha256": _row_turn_sha256(row)
                        or active_turn_sha256,
                    }
                )
            records.append(
                (_row_ordinal(row, index), kind, payload, identity)
            )

    attempts = completions = failures = open_attempts = 0
    completion_rows: dict[str, tuple[int, dict[str, Any]]] = {}
    terminal_ids: set[str] = set()
    for ordinal, kind, payload, identity in sorted(records):
        if kind == "attempt":
            attempts += 1
            open_attempts += 1
        elif kind == "completion":
            if identity in terminal_ids:
                continue
            terminal_ids.add(identity)
            completions += 1
            if open_attempts:
                open_attempts -= 1
            else:
                attempts += 1
            completion_rows[identity] = (ordinal, payload)
        elif kind == "failure":
            if identity in terminal_ids:
                continue
            terminal_ids.add(identity)
            failures += 1
            if open_attempts:
                open_attempts -= 1
            else:
                attempts += 1

    checkpoint_bytes = checkpoint_tokens = 0
    sources: set[str] = set()
    for _ordinal, payload in completion_rows.values():
        byte_count, token_count, source = _checkpoint_measurement(payload)
        checkpoint_bytes += byte_count
        checkpoint_tokens += token_count
        sources.add(source)

    full = token_interval(
        rows,
        start,
        end,
        start_ordinal=start_ordinal,
        end_ordinal=end_ordinal,
        require_baseline=True,
    )
    if completion_rows:
        first_rollover = min(ordinal for ordinal, _payload in completion_rows.values())
        before = token_interval(
            rows,
            start,
            end,
            start_ordinal=start_ordinal,
            end_ordinal=first_rollover - 1,
            require_baseline=True,
        )
        after = token_interval(
            rows,
            start,
            end,
            start_ordinal=first_rollover,
            end_ordinal=end_ordinal,
            require_baseline=True,
        )
    else:
        first_rollover = None
        before = full
        after = _unavailable_token_metrics("not_applicable_no_rollover")
    context_before: int | None = None
    context_after: int | None = None
    if first_rollover is not None:
        request_inputs: list[tuple[int, int]] = []
        for index, row in enumerate(rows):
            if not _row_in_rollout_interval(
                row,
                index,
                start,
                end,
                start_ordinal=start_ordinal,
                end_ordinal=end_ordinal,
            ):
                continue
            payload = row.get("payload")
            if (
                row.get("type") != "event_msg"
                or not isinstance(payload, dict)
                or payload.get("type") != "token_count"
                or not isinstance(payload.get("info"), dict)
            ):
                continue
            last = _token_values(payload["info"].get("last_token_usage"))
            if not _validate_token_vector(last):
                continue
            input_tokens = last.get("input")
            if isinstance(input_tokens, int):
                request_inputs.append((_row_ordinal(row, index), input_tokens))
        before_values = [
            value for ordinal, value in request_inputs if ordinal < first_rollover
        ]
        after_values = [
            value for ordinal, value in request_inputs if ordinal > first_rollover
        ]
        context_before = before_values[-1] if before_values else None
        context_after = after_values[0] if after_values else None
    repeated_reads = _repeated_rollout_reads(
        rows,
        start,
        end,
        start_ordinal=start_ordinal,
        end_ordinal=end_ordinal,
        first_rollover_ordinal=first_rollover,
    )
    return {
        "thread_count": 1,
        "window_count": 1 + completions,
        "rollover_attempts": attempts,
        "rollover_completions": completions,
        "rollout_compacted_transitions": len(compacted_transition_ids),
        "new_context_calls": new_context_calls,
        "_new_context_evidence": new_context_evidence,
        "_compacted_evidence": compacted_evidence,
        "_task_start_evidence": task_start_evidence,
        "_user_message_evidence": user_message_evidence,
        "_terminal_evidence": terminal_evidence,
        "rollover_failures": failures,
        "open_attempts": open_attempts,
        "failure_observability": "observed_events_only",
        "checkpoint_count": len(completion_rows),
        "checkpoint_bytes": checkpoint_bytes,
        "checkpoint_tokens_estimate": checkpoint_tokens,
        "checkpoint_estimate_source": (
            next(iter(sources)) if len(sources) == 1 else "mixed" if sources else "unavailable"
        ),
        "before_first_rollover": _token_slice(before),
        "after_rollovers": _token_slice(after),
        "context_input_before_first_rollover": context_before,
        "context_input_after_first_rollover": context_after,
        "context_input_reduction_observed": (
            context_before - context_after
            if context_before is not None and context_after is not None
            else None
        ),
        "context_input_observation_count": int(
            context_before is not None and context_after is not None
        ),
        **repeated_reads,
        "estimates_are_diagnostic_only": True,
    }


def _sum_rollover_lanes(values: Iterable[dict[str, Any]]) -> dict[str, Any]:
    rows = list(values)
    if not rows:
        return {
            "thread_count": 0,
            "window_count": 0,
            "rollover_attempts": 0,
            "rollover_completions": 0,
            "rollout_compacted_transitions": 0,
            "new_context_calls": 0,
            "_new_context_evidence": [],
            "_compacted_evidence": [],
            "_task_start_evidence": [],
            "_user_message_evidence": [],
            "_terminal_evidence": [],
            "rollover_failures": 0,
            "open_attempts": 0,
            "failure_observability": "observed_events_only",
            "checkpoint_count": 0,
            "checkpoint_bytes": 0,
            "checkpoint_tokens_estimate": 0,
            "checkpoint_estimate_source": "unavailable",
            "before_first_rollover": _token_slice(_empty_token_metrics()),
            "after_rollovers": _token_slice(_empty_token_metrics()),
            "context_input_before_first_rollover": None,
            "context_input_after_first_rollover": None,
            "context_input_reduction_observed": None,
            "context_input_observation_count": 0,
            "code_read_tool_cells": 0,
            "repeated_code_read_tool_cells": 0,
            "repeated_code_read_tool_cells_after_rollover": 0,
            "document_read_tool_cells": 0,
            "repeated_document_read_tool_cells": 0,
            "repeated_document_read_tool_cells_after_rollover": 0,
            "repeat_read_source": "exact_outer_tool_command_hashes",
            "estimates_are_diagnostic_only": True,
        }
    sources = {
        str(row.get("checkpoint_estimate_source") or "unavailable")
        for row in rows
        if row.get("checkpoint_count")
    }
    observed_context = [
        row
        for row in rows
        if int(row.get("context_input_observation_count", 0)) > 0
    ]
    return {
        "thread_count": sum(int(row.get("thread_count", 0)) for row in rows),
        "window_count": sum(int(row.get("window_count", 0)) for row in rows),
        "rollover_attempts": sum(int(row.get("rollover_attempts", 0)) for row in rows),
        "rollover_completions": sum(int(row.get("rollover_completions", 0)) for row in rows),
        "rollout_compacted_transitions": sum(
            int(row.get("rollout_compacted_transitions", 0))
            for row in rows
        ),
        "new_context_calls": sum(
            int(row.get("new_context_calls", 0)) for row in rows
        ),
        "_new_context_evidence": [
            evidence
            for row in rows
            for evidence in row.get("_new_context_evidence", [])
            if isinstance(evidence, dict)
        ],
        "_compacted_evidence": [
            evidence
            for row in rows
            for evidence in row.get("_compacted_evidence", [])
            if isinstance(evidence, dict)
        ],
        "_task_start_evidence": [
            evidence
            for row in rows
            for evidence in row.get("_task_start_evidence", [])
            if isinstance(evidence, dict)
        ],
        "_user_message_evidence": [
            evidence
            for row in rows
            for evidence in row.get("_user_message_evidence", [])
            if isinstance(evidence, dict)
        ],
        "_terminal_evidence": [
            evidence
            for row in rows
            for evidence in row.get("_terminal_evidence", [])
            if isinstance(evidence, dict)
        ],
        "rollover_failures": sum(int(row.get("rollover_failures", 0)) for row in rows),
        "open_attempts": sum(int(row.get("open_attempts", 0)) for row in rows),
        "failure_observability": "observed_events_only",
        "checkpoint_count": sum(int(row.get("checkpoint_count", 0)) for row in rows),
        "checkpoint_bytes": sum(int(row.get("checkpoint_bytes", 0)) for row in rows),
        "checkpoint_tokens_estimate": sum(int(row.get("checkpoint_tokens_estimate", 0)) for row in rows),
        "checkpoint_estimate_source": (
            next(iter(sources)) if len(sources) == 1 else "mixed" if sources else "unavailable"
        ),
        "before_first_rollover": _sum_token_lanes(
            row["before_first_rollover"] for row in rows
        ),
        "after_rollovers": _sum_token_lanes(row["after_rollovers"] for row in rows),
        "context_input_before_first_rollover": (
            sum(int(row["context_input_before_first_rollover"]) for row in observed_context)
            if observed_context
            else None
        ),
        "context_input_after_first_rollover": (
            sum(int(row["context_input_after_first_rollover"]) for row in observed_context)
            if observed_context
            else None
        ),
        "context_input_reduction_observed": (
            sum(int(row["context_input_reduction_observed"]) for row in observed_context)
            if observed_context
            else None
        ),
        "context_input_observation_count": len(observed_context),
        "code_read_tool_cells": sum(int(row.get("code_read_tool_cells", 0)) for row in rows),
        "repeated_code_read_tool_cells": sum(int(row.get("repeated_code_read_tool_cells", 0)) for row in rows),
        "repeated_code_read_tool_cells_after_rollover": sum(
            int(row.get("repeated_code_read_tool_cells_after_rollover", 0)) for row in rows
        ),
        "document_read_tool_cells": sum(int(row.get("document_read_tool_cells", 0)) for row in rows),
        "repeated_document_read_tool_cells": sum(int(row.get("repeated_document_read_tool_cells", 0)) for row in rows),
        "repeated_document_read_tool_cells_after_rollover": sum(
            int(row.get("repeated_document_read_tool_cells_after_rollover", 0)) for row in rows
        ),
        "repeat_read_source": "exact_outer_tool_command_hashes",
        "estimates_are_diagnostic_only": True,
    }


def _included_rollouts(
    root_session: dict[str, Any], catalog: Sequence[dict[str, Any]],
    start: dt.datetime, end: dt.datetime,
) -> list[dict[str, Any]]:
    root_id = root_session["id"]
    group = {
        item["id"]: item
        for item in catalog
        if item.get("session_id") == root_session["session_id"]
    }

    def descends_from_root(item: dict[str, Any]) -> bool:
        parent = item.get("parent_id")
        seen: set[str] = set()
        while parent and parent not in seen:
            if parent == root_id:
                return True
            seen.add(str(parent))
            ancestor = group.get(str(parent))
            if ancestor is None:
                return False
            parent = ancestor.get("parent_id")
        return False

    result = [dict(root_session)]
    for item in sorted(group.values(), key=lambda value: str(value.get("started_at") or "")):
        if item["id"] == root_id or not descends_from_root(item):
            continue
        born = _timestamp(item.get("started_at"))
        if born is None or born > end:
            continue
        rows = _rollout_rows(item["path"])
        starts, _ = _task_boundaries(rows, start, end)
        newly_spawned = born >= start
        if not newly_spawned and not starts:
            # Exclude an older background task that merely overlaps the run;
            # include only an explicit in-interval follow-up boundary.
            continue
        selected = dict(item)
        selected["run_start_ordinal"] = -1 if newly_spawned else min(starts.values())
        selected["run_turn_sha256s"] = sorted(starts)
        result.append(selected)
    return result


def _sum_token_lanes(values: Iterable[dict[str, Any]]) -> dict[str, Any]:
    rows = list(values)
    result: dict[str, Any] = {}
    for key in TOKEN_KEYS:
        parts = [row.get(key) for row in rows]
        result[key] = sum(int(value) for value in parts) if all(value is not None for value in parts) else None
    parts = [row.get("uncached_input") for row in rows]
    result["uncached_input"] = (
        sum(int(value) for value in parts) if all(value is not None for value in parts) else None
    )
    result["request_count"] = sum(int(row.get("request_count", 0)) for row in rows)
    result["duplicate_snapshots"] = sum(int(row.get("duplicate_snapshots", 0)) for row in rows)
    result["reset_epochs"] = sum(int(row.get("reset_epochs", 0)) for row in rows)
    result["exact"] = all(bool(row.get("exact")) for row in rows)
    result["errors"] = sorted({error for row in rows for error in row.get("errors", [])})
    return result


def collect_tokens(
    root_session: dict[str, Any], catalog: Sequence[dict[str, Any]],
    start: dt.datetime, end: dt.datetime, *, root_start_ordinal: int | None = None,
    root_end_ordinal: int | None = None, require_complete_logs: bool = False,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    included = _included_rollouts(root_session, catalog, start, end)
    root_rows: list[dict[str, Any]] = []
    child_rows: list[dict[str, Any]] = []
    for item in included:
        born = _timestamp(item.get("started_at")) or start
        interval_start = start if item["id"] == root_session["id"] else max(start, born)
        rollout_rows = _rollout_rows(item["path"])
        metrics = token_interval(
            rollout_rows, interval_start, end,
            # An included descendant with no token_count rows is not a proven
            # zero-model-call lane.  Every lane must contribute at least one
            # in-scope cumulative snapshot before combined usage is exact.
            require_baseline=True,
            start_ordinal=(
                root_start_ordinal
                if item["id"] == root_session["id"]
                else int(item.get("run_start_ordinal", -1))
            ),
            end_ordinal=(root_end_ordinal if item["id"] == root_session["id"] else None),
        )
        if require_complete_logs and not _jsonl_complete(item["path"]):
            metrics["exact"] = False
            metrics["errors"] = sorted(set([*metrics["errors"], "partial_rollout_log"]))
        if require_complete_logs and int(metrics.get("request_count", 0)) < 1:
            metrics["exact"] = False
            metrics["errors"] = sorted(
                set([*metrics["errors"], "no_model_request_usage"])
            )
        if (
            require_complete_logs
            and item["id"] != root_session["id"]
            and not _has_matching_terminals(rollout_rows, start, end)
        ):
            metrics["exact"] = False
            metrics["errors"] = sorted(set([*metrics["errors"], "unterminated_descendant"]))
        (root_rows if item["id"] == root_session["id"] else child_rows).append(metrics)
    root_lane = _sum_token_lanes(root_rows)
    child_lane = _sum_token_lanes(child_rows) if child_rows else {
        **{key: 0 for key in TOKEN_KEYS}, "uncached_input": 0, "request_count": 0,
        "duplicate_snapshots": 0, "reset_epochs": 0, "exact": True, "errors": [],
    }
    combined = _sum_token_lanes([root_lane, child_lane])
    return {
        "root": root_lane,
        "subagent": child_lane,
        "combined": combined,
        "included_threads": {"root": 1, "subagent": len(child_rows), "combined": 1 + len(child_rows)},
    }, included


def _commands(payload: dict[str, Any]) -> list[str]:
    raw = payload.get("input", payload.get("arguments"))
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except json.JSONDecodeError:
            return [raw]
    if not isinstance(raw, dict):
        return []
    values: list[str] = []
    for key in ("cmd", "command"):
        if isinstance(raw.get(key), str):
            values.append(raw[key])
    return values


def _read_command_labels(joined: str) -> tuple[bool, bool]:
    graph_call = bool(
        re.search(
            r"(?:tdd_context\.py|\bgraphify\s+(?:path|explain|query|update))",
            joined,
        )
    )
    read_like = bool(
        re.search(
            r"(?:^|[;&|\s])(?:cat|sed|rg|head|tail|awk|nl)\b|read_text\s*\(",
            joined,
        )
    )
    document_read = read_like and bool(
        re.search(r"\.(?:md|mdx|rst|adoc)(?:[\s'\"),;]|$)", joined, re.I)
    )
    code_read = read_like and not graph_call and bool(
        re.search(
            r"\.(?:dart|go|swift|kt|java|py|sh|gradle|xml|ya?ml|toml)(?:[\s'\"),;]|$)|(?:^|[\s'\"])(?:lib|test|integration_test|ios|android|go-mknoon|go-relay-server|scripts)/",
            joined,
            re.I,
        )
    )
    return code_read, document_read


def _repeated_rollout_reads(
    rows: Sequence[dict[str, Any]],
    start: dt.datetime,
    end: dt.datetime,
    *,
    start_ordinal: int | None,
    end_ordinal: int | None,
    first_rollover_ordinal: int | None,
) -> dict[str, Any]:
    seen_code: set[str] = set()
    seen_documents: set[str] = set()
    counts: Counter[str] = Counter()
    for index, row in enumerate(rows):
        if not _row_in_rollout_interval(
            row,
            index,
            start,
            end,
            start_ordinal=start_ordinal,
            end_ordinal=end_ordinal,
        ):
            continue
        payload = row.get("payload")
        if not isinstance(payload, dict) or payload.get("type") not in {
            "custom_tool_call",
            "function_call",
        }:
            continue
        joined = "\n".join(_commands(payload))
        code_read, document_read = _read_command_labels(joined)
        ordinal = _row_ordinal(row, index)
        command_hash = _digest(joined)
        if code_read:
            counts["code_read_tool_cells"] += 1
            if command_hash in seen_code:
                counts["repeated_code_read_tool_cells"] += 1
                if first_rollover_ordinal is not None and ordinal > first_rollover_ordinal:
                    counts["repeated_code_read_tool_cells_after_rollover"] += 1
            seen_code.add(command_hash)
        if document_read:
            counts["document_read_tool_cells"] += 1
            if command_hash in seen_documents:
                counts["repeated_document_read_tool_cells"] += 1
                if first_rollover_ordinal is not None and ordinal > first_rollover_ordinal:
                    counts["repeated_document_read_tool_cells_after_rollover"] += 1
            seen_documents.add(command_hash)
    return {
        key: counts[key]
        for key in (
            "code_read_tool_cells",
            "repeated_code_read_tool_cells",
            "repeated_code_read_tool_cells_after_rollover",
            "document_read_tool_cells",
            "repeated_document_read_tool_cells",
            "repeated_document_read_tool_cells_after_rollover",
        )
    } | {"repeat_read_source": "exact_outer_tool_command_hashes"}


def _graphify_rollout_lane(items: Sequence[dict[str, Any]], start: dt.datetime, end: dt.datetime) -> dict[str, int]:
    counts: Counter[str] = Counter()
    for item in items:
        calls: dict[str, set[str]] = {}
        for row in _rollout_rows(item["path"]):
            stamp = _timestamp(row.get("timestamp"))
            payload = row.get("payload")
            if stamp is None or stamp < start or stamp > end or not isinstance(payload, dict):
                continue
            ptype = payload.get("type")
            if ptype in {"custom_tool_call", "function_call"}:
                commands = _commands(payload)
                joined = "\n".join(commands)
                graph_call = bool(re.search(r"(?:tdd_context\.py|\bgraphify\s+(?:path|explain|query|update))", joined))
                code_read, document_read = _read_command_labels(joined)
                labels: set[str] = set()
                if graph_call:
                    labels.add("graphify")
                    counts["tool_calls"] += 1
                    counts["compact_queries"] += len(re.findall(r"tdd_context\.py\s+query\b", joined))
                    counts["native_queries"] += len(re.findall(r"tdd_context\.py\s+native\b|\bgraphify\s+(?:path|explain)\b", joined))
                    counts["affected_queries"] += len(re.findall(r"tdd_context\.py\s+affected\b", joined))
                    counts["checkpoints"] += len(re.findall(r"tdd_context\.py\s+checkpoint\b", joined))
                if code_read:
                    labels.add("code")
                    counts["raw_code_tool_cells"] += 1
                if document_read:
                    labels.add("document")
                    counts["raw_document_tool_cells"] += 1
                call_id = str(payload.get("call_id") or "")
                if call_id:
                    calls[call_id] = labels
            elif ptype in {"custom_tool_call_output", "function_call_output"} and calls.get(str(payload.get("call_id") or "")):
                output = payload.get("output")
                output_text = output if isinstance(output, str) else _canonical(output)
                estimate = round(len(output_text) / 4)
                labels = calls[str(payload.get("call_id") or "")]
                if "graphify" in labels:
                    counts["output_tokens_estimate"] += estimate
                if "code" in labels:
                    counts["raw_code_output_tokens_estimate"] += estimate
                if "document" in labels:
                    counts["raw_document_output_tokens_estimate"] += estimate
    return {
        key: counts[key]
        for key in (
            "tool_calls",
            "compact_queries",
            "native_queries",
            "affected_queries",
            "checkpoints",
            "output_tokens_estimate",
            "raw_code_tool_cells",
            "raw_code_output_tokens_estimate",
            "raw_document_tool_cells",
            "raw_document_output_tokens_estimate",
        )
    }


def _row_in_interval(row: dict[str, Any], session_hash: str, start: dt.datetime, end: dt.datetime) -> bool:
    stamp = _timestamp(row.get("ts") or row.get("timestamp"))
    identity = row.get("codex_session_sha256", row.get("session_sha256"))
    return identity == session_hash and stamp is not None and start <= stamp <= end


def _producer_liveness_thread_identity(
    row: dict[str, Any], index: int
) -> str:
    """Return a privacy-safe correlation lane for checkpoint retries."""
    session = str(row.get("codex_session_sha256") or "").strip().lower()
    thread = str(row.get("codex_thread_sha256") or "").strip().lower()
    if HASH16.fullmatch(thread):
        return (
            f"session:{session}:thread:{thread}"
            if HASH16.fullmatch(session)
            else f"thread:{thread}"
        )
    checkpoint = str(row.get("checkpoint_sha256") or "").strip().lower()
    generation = row.get("generation")
    if HASH16.fullmatch(checkpoint):
        return f"checkpoint:{checkpoint}"
    if isinstance(generation, int) and not isinstance(generation, bool):
        return f"generation:{generation}:row:{index}"
    return f"row:{index}"


def _producer_liveness_attempt_identity(
    row: dict[str, Any], index: int, thread_identity: str
) -> str:
    generation = row.get("generation")
    if (
        isinstance(generation, int)
        and not isinstance(generation, bool)
        and generation > 0
    ):
        return f"{thread_identity}:generation:{generation}"
    checkpoint = str(row.get("checkpoint_sha256") or "").strip().lower()
    if HASH16.fullmatch(checkpoint):
        return f"{thread_identity}:checkpoint:{checkpoint}"
    return f"{thread_identity}:row:{index}"


def _producer_liveness_episode(row: dict[str, Any]) -> str | None:
    candidate = str(row.get("not_ready_episode_sha256") or "").strip().lower()
    return candidate if HASH16.fullmatch(candidate) else None


def _producer_liveness_metrics(
    recognized: Sequence[tuple[int, dict[str, Any], str]],
) -> dict[str, Any]:
    """Correlate retry generations without collapsing artifact accounting.

    A real prepare retry always advances generation. Liveness therefore follows
    ordered events in one hashed thread, while checkpoint counts remain grouped
    by generation in ``_producer_rollover_metrics``. READY and advisory events
    are remediation evidence only; PreCompact/post-compact/session recovery is
    the boundary that resolves an open NOT_READY episode.
    """
    by_thread: dict[str, list[tuple[int, dict[str, Any], str]]] = defaultdict(list)
    for index, row, event in recognized:
        by_thread[_producer_liveness_thread_identity(row, index)].append(
            (index, row, event)
        )

    episodes: list[dict[str, Any]] = []
    for thread_identity, thread_rows in by_thread.items():
        active: dict[str, Any] | None = None
        last_failed: dict[str, Any] | None = None
        for index, row, event in sorted(
            thread_rows,
            key=lambda value: (
                _timestamp(value[1].get("timestamp"))
                or dt.datetime.min.replace(tzinfo=dt.timezone.utc),
                value[0],
            ),
        ):
            stamp = _timestamp(row.get("timestamp"))
            stamp_text = stamp.isoformat() if stamp is not None else None
            producer_episode = _producer_liveness_episode(row)
            turn = next(
                (
                    str(row.get(key))
                    for key in (
                        "precompact_turn_sha256",
                        "task_turn_sha256",
                        "turn_sha256",
                    )
                    if HASH16.fullmatch(str(row.get(key) or ""))
                ),
                None,
            )
            if event == "checkpoint_saved" and row.get("ready") is False:
                if (
                    active is not None
                    and producer_episode is not None
                    and active.get("producer_episode") is not None
                    and active["producer_episode"] != producer_episode
                ):
                    active = None
                if active is None:
                    active = {
                        "attempt_ids": set(),
                        "producer_episode": producer_episode,
                        "not_ready_at": stamp_text,
                        "turns": set(),
                        "repair_at": [],
                        "advisory_at": [],
                        "transition_at": [],
                        "blocked_terminal_at": [],
                        "explicit_terminal_at": [],
                        "rescue_at": [],
                        "closed": None,
                    }
                    episodes.append(active)
                elif active.get("producer_episode") is None:
                    active["producer_episode"] = producer_episode
                active["attempt_ids"].add(
                    _producer_liveness_attempt_identity(
                        row, index, thread_identity
                    )
                )
                if active.get("not_ready_at") is None and stamp_text is not None:
                    active["not_ready_at"] = stamp_text
                if turn is not None:
                    active["turns"].add(turn)
                continue

            if event == "user_rescue_after_terminal":
                if (
                    last_failed is not None
                    and stamp_text is not None
                    and (
                        producer_episode is None
                        or last_failed.get("producer_episode") is None
                        or producer_episode
                        == last_failed.get("producer_episode")
                    )
                ):
                    last_failed["rescue_at"].append(stamp_text)
                continue
            if active is None:
                continue
            if (
                producer_episode is not None
                and active.get("producer_episode") is not None
                and active["producer_episode"] != producer_episode
            ):
                continue
            if active.get("producer_episode") is None:
                active["producer_episode"] = producer_episode
            if turn is not None:
                active["turns"].add(turn)
            if event == "checkpoint_saved" and row.get("ready") is True:
                active.setdefault("repaired_ids", set()).update(
                    active["attempt_ids"]
                )
                if stamp_text is not None:
                    active["repair_at"].append(stamp_text)
            elif event == "checkpoint_advisory_reset_requested":
                active.setdefault("advisory_ids", set()).update(
                    active["attempt_ids"]
                )
                if stamp_text is not None:
                    active["advisory_at"].append(stamp_text)
            elif event == "terminal_after_not_ready_blocked":
                if stamp_text is not None:
                    active["blocked_terminal_at"].append(stamp_text)
            elif event == "terminal_after_not_ready":
                if stamp_text is not None:
                    active["explicit_terminal_at"].append(stamp_text)
                active["closed"] = "terminal"
                last_failed = active
                active = None
            elif event in ROLLOVER_TRANSITION_EVENTS:
                if stamp_text is not None:
                    active["transition_at"].append(stamp_text)
                active["closed"] = "transition"
                active = None

    evidence: list[dict[str, Any]] = []
    for episode in episodes:
        turns = episode.get("turns", set())
        evidence.append(
            {
                "not_ready_at": episode.get("not_ready_at"),
                "turn_sha256": next(iter(turns)) if len(turns) == 1 else None,
                "repair_at": list(episode.get("repair_at", [])),
                "advisory_at": list(episode.get("advisory_at", [])),
                "transition_at": list(episode.get("transition_at", [])),
                "blocked_terminal_at": list(
                    episode.get("blocked_terminal_at", [])
                ),
                "explicit_terminal_at": list(
                    episode.get("explicit_terminal_at", [])
                ),
                "rescue_at": list(episode.get("rescue_at", [])),
            }
        )

    return {
        "not_ready_lifecycles": sum(
            len(episode["attempt_ids"]) for episode in episodes
        ),
        "unresolved_not_ready": sum(
            len(episode["attempt_ids"])
            for episode in episodes
            if episode.get("closed") is None
        ),
        "not_ready_repairs_before_terminal": sum(
            len(episode.get("repaired_ids", set())) for episode in episodes
        ),
        "not_ready_advisories_before_terminal": sum(
            len(episode.get("advisory_ids", set())) for episode in episodes
        ),
        "terminal_after_not_ready_blocked": sum(
            bool(episode.get("blocked_terminal_at")) for episode in episodes
        ),
        "terminal_after_not_ready": sum(
            episode.get("closed") == "terminal" for episode in episodes
        ),
        "user_rescue_after_terminal": sum(
            bool(episode.get("rescue_at")) for episode in episodes
        ),
        "_not_ready_lifecycles": evidence,
    }


def _producer_rollover_metrics(rows: Sequence[dict[str, Any]]) -> dict[str, Any]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    event_counts: Counter[str] = Counter()
    recognized_rows: list[tuple[int, dict[str, Any], str]] = []
    for index, row in enumerate(rows):
        event = _category(row.get("event"))
        if event not in (
            ROLLOVER_ATTEMPT_EVENTS
            | ROLLOVER_COMPLETION_EVENTS
            | ROLLOVER_FAILURE_EVENTS
            | CHECKPOINT_VALIDATION_FAILURE_EVENTS
            | ROLLOVER_RECOVERY_EVENTS
            | ROLLOVER_LIVENESS_EVENTS
            | {
                "checkpoint_saved",
                "checkpoint_completed",
                "postcompact_observed",
                "subagent_skipped",
            }
        ):
            continue
        recognized_rows.append((index, row, event))
        event_counts[event] += 1
        checkpoint = str(row.get("checkpoint_sha256") or "")
        generation = row.get("generation")
        thread_hash = str(row.get("codex_thread_sha256") or "")
        if (
            isinstance(generation, int)
            and not isinstance(generation, bool)
            and generation > 0
            and HASH16.fullmatch(thread_hash)
        ):
            # Checkpoint content hashes legitimately change as the same
            # generation is prepared, injected, and completed.
            identity = f"generation:{thread_hash}:{generation}"
        elif HASH16.fullmatch(checkpoint):
            identity = f"checkpoint:{checkpoint}"
        else:
            identity = _digest(
                _canonical(
                    {
                        "phase": row.get("phase_sha256"),
                        "generation": generation,
                        "index": index,
                    }
                )
            )
        groups[identity].append(row)

    liveness = _producer_liveness_metrics(recognized_rows)
    attempts = completions = failures = open_attempts = 0
    checkpointed_resume_completions = 0
    prepared_resume_completions = 0
    prepared_lifecycles: list[dict[str, Any]] = []
    recovery_precompact_allows = 0
    recovery_advisory_resumes = 0
    recovery_advisory_duplicates = 0
    checkpoint_advisory_reset_requests = 0
    nonterminal_failures = 0
    checkpoint_validation_failures = 0
    checkpoint_bytes = checkpoint_tokens = checkpoint_count = 0
    for raw_lifecycle in groups.values():
        lifecycle = sorted(
            raw_lifecycle,
            key=lambda row: _timestamp(row.get("timestamp"))
            or dt.datetime.min.replace(tzinfo=dt.timezone.utc),
        )
        names = {_category(row.get("event")) for row in lifecycle}
        has_not_ready = any(
            _category(row.get("event")) == "checkpoint_saved"
            and row.get("ready") is False
            for row in lifecycle
        )
        attempted = bool(names & ROLLOVER_ATTEMPT_EVENTS) or bool(
            has_not_ready
        )
        completed = any(
            _category(row.get("event")) in ROLLOVER_COMPLETION_EVENTS
            and not bool(row.get("duplicate"))
            for row in lifecycle
        )
        nonterminal_failed = bool(names & ROLLOVER_FAILURE_EVENTS)
        failed = nonterminal_failed
        nonterminal_failures += int(nonterminal_failed)
        checkpoint_validation_failures += int(
            bool(names & CHECKPOINT_VALIDATION_FAILURE_EVENTS)
        )
        recovery_precompact_allows += sum(
            _category(row.get("event")) == "precompact_recovery_allowed"
            for row in lifecycle
        )
        recovery_advisory_resumes += sum(
            _category(row.get("event")) == "session_recovery_advisory"
            and not bool(row.get("duplicate"))
            for row in lifecycle
        )
        recovery_advisory_duplicates += sum(
            _category(row.get("event")) == "session_recovery_advisory"
            and bool(row.get("duplicate"))
            for row in lifecycle
        )
        checkpoint_advisory_reset_requests += sum(
            _category(row.get("event"))
            == "checkpoint_advisory_reset_requested"
            for row in lifecycle
        )
        saved_positions = [
            index
            for index, row in enumerate(lifecycle)
            if _category(row.get("event")) == "checkpoint_saved"
        ]
        allowed_positions = [
            index
            for index, row in enumerate(lifecycle)
            if _category(row.get("event")) == "precompact_allowed"
        ]
        resumed_positions = [
            index
            for index, row in enumerate(lifecycle)
            if _category(row.get("event")) == "session_resumed"
            and not bool(row.get("duplicate"))
        ]
        checkpointed_resume = any(
            (
                (_timestamp(lifecycle[saved].get("timestamp")), saved)
                < (_timestamp(lifecycle[allowed].get("timestamp")), allowed)
                < (_timestamp(lifecycle[resumed].get("timestamp")), resumed)
            )
            for saved in saved_positions
            for allowed in allowed_positions
            for resumed in resumed_positions
            if _timestamp(lifecycle[saved].get("timestamp")) is not None
            and _timestamp(lifecycle[allowed].get("timestamp")) is not None
            and _timestamp(lifecycle[resumed].get("timestamp")) is not None
        )
        prepared_saved_positions = [
            index
            for index in saved_positions
            if _category(lifecycle[index].get("continuation_mode"))
            == "prepared_rollover"
        ]
        prepared_allowed_positions = [
            index
            for index in allowed_positions
            if _category(lifecycle[index].get("continuation_mode"))
            == "prepared_rollover"
            and HASH16.fullmatch(
                str(lifecycle[index].get("precompact_turn_sha256") or "")
            )
        ]
        prepared_resumed_positions = [
            index
            for index in resumed_positions
            if _category(lifecycle[index].get("continuation_mode"))
            == "prepared_rollover"
            and HASH16.fullmatch(
                str(lifecycle[index].get("precompact_turn_sha256") or "")
            )
        ]
        prepared_postcompact_positions = [
            index
            for index, row in enumerate(lifecycle)
            if _category(row.get("event")) == "postcompact_observed"
            and _category(row.get("continuation_mode")) == "prepared_rollover"
            and HASH16.fullmatch(
                str(row.get("precompact_turn_sha256") or "")
            )
        ]
        prepared_lifecycle: dict[str, Any] | None = None
        for saved in prepared_saved_positions:
            saved_at = _timestamp(lifecycle[saved].get("timestamp"))
            if saved_at is None:
                continue
            for allowed in prepared_allowed_positions:
                allowed_at = _timestamp(lifecycle[allowed].get("timestamp"))
                if allowed_at is None or (saved_at, saved) >= (allowed_at, allowed):
                    continue
                allowed_turn = str(
                    lifecycle[allowed].get("precompact_turn_sha256") or ""
                )
                for postcompact in prepared_postcompact_positions:
                    postcompact_at = _timestamp(
                        lifecycle[postcompact].get("timestamp")
                    )
                    postcompact_turn = str(
                        lifecycle[postcompact].get("precompact_turn_sha256") or ""
                    )
                    if (
                        postcompact_at is None
                        or allowed_turn != postcompact_turn
                        or (allowed_at, allowed)
                        >= (postcompact_at, postcompact)
                    ):
                        continue
                    for resumed in prepared_resumed_positions:
                        resumed_at = _timestamp(lifecycle[resumed].get("timestamp"))
                        resumed_turn = str(
                            lifecycle[resumed].get("precompact_turn_sha256") or ""
                        )
                        if (
                            resumed_at is None
                            or allowed_turn != resumed_turn
                            or (postcompact_at, postcompact)
                            >= (resumed_at, resumed)
                        ):
                            continue
                        prepared_lifecycle = {
                            "thread_sha256": str(
                                lifecycle[allowed].get("codex_thread_sha256") or ""
                            ),
                            "generation": lifecycle[allowed].get("generation"),
                            "turn_sha256": allowed_turn,
                            "saved_at": saved_at.isoformat(),
                            "allowed_at": allowed_at.isoformat(),
                            "postcompact_at": postcompact_at.isoformat(),
                            "resumed_at": resumed_at.isoformat(),
                        }
                        break
                    if prepared_lifecycle is not None:
                        break
                if prepared_lifecycle is not None:
                    break
            if prepared_lifecycle is not None:
                break
        if prepared_lifecycle is not None:
            prepared_resume_completions += 1
            prepared_lifecycles.append(prepared_lifecycle)
        if completed or failed:
            attempted = True
        attempts += int(attempted)
        completions += int(completed)
        checkpointed_resume_completions += int(checkpointed_resume)
        failures += int(failed)
        open_attempts += int(attempted and not completed and not failed)
        sizes = [
            int(row["checkpoint_bytes"])
            for row in lifecycle
            if "checkpoint_bytes" in row
            and isinstance(row.get("checkpoint_bytes"), int)
            and not isinstance(row.get("checkpoint_bytes"), bool)
            and row.get("checkpoint_bytes", 0) >= 0
        ]
        estimates = [
            int(row["checkpoint_tokens_estimate"])
            for row in lifecycle
            if "checkpoint_tokens_estimate" in row
            and isinstance(row.get("checkpoint_tokens_estimate"), int)
            and not isinstance(row.get("checkpoint_tokens_estimate"), bool)
            and row.get("checkpoint_tokens_estimate", 0) >= 0
        ]
        has_checkpoint_artifact = "checkpoint_saved" in names or any(
            isinstance(row.get("generation"), int)
            and not isinstance(row.get("generation"), bool)
            and row.get("generation", 0) > 0
            and HASH16.fullmatch(str(row.get("checkpoint_sha256") or ""))
            for row in lifecycle
        )
        if has_checkpoint_artifact and (sizes or estimates):
            checkpoint_count += 1
            checkpoint_bytes += max(sizes, default=0)
            checkpoint_tokens += max(estimates, default=0)
    effective_failures = nonterminal_failures + int(
        liveness["terminal_after_not_ready"]
    )
    effective_attempts = max(attempts, completions + effective_failures)
    return {
        "producer_event_count": sum(event_counts.values()),
        "producer_events": dict(sorted(event_counts.items())),
        "rollover_attempts": effective_attempts,
        "rollover_completions": completions,
        "checkpointed_resume_completions": checkpointed_resume_completions,
        "prepared_resume_completions": prepared_resume_completions,
        "_prepared_lifecycles": prepared_lifecycles,
        "recovery_precompact_allows": recovery_precompact_allows,
        "recovery_advisory_resumes": recovery_advisory_resumes,
        "recovery_advisory_duplicates": recovery_advisory_duplicates,
        "checkpoint_advisory_reset_requested": checkpoint_advisory_reset_requests,
        "fallback_lifecycle_lower_bound": max(
            recovery_precompact_allows,
            recovery_advisory_resumes,
            checkpoint_advisory_reset_requests,
        ),
        "fallback_exposure_observed": bool(
            recovery_precompact_allows
            or recovery_advisory_resumes
            or recovery_advisory_duplicates
            or checkpoint_advisory_reset_requests
        ),
        "not_ready_lifecycles": liveness["not_ready_lifecycles"],
        "unresolved_not_ready": liveness["unresolved_not_ready"],
        "not_ready_repairs_before_terminal": liveness[
            "not_ready_repairs_before_terminal"
        ],
        "not_ready_advisories_before_terminal": liveness[
            "not_ready_advisories_before_terminal"
        ],
        "terminal_after_not_ready_blocked": liveness[
            "terminal_after_not_ready_blocked"
        ],
        "terminal_after_not_ready": liveness["terminal_after_not_ready"],
        "user_rescue_after_terminal": liveness["user_rescue_after_terminal"],
        "rollover_nonterminal_failures": nonterminal_failures,
        "_not_ready_lifecycles": liveness["_not_ready_lifecycles"],
        "checkpoint_validation_failures": checkpoint_validation_failures,
        "rollover_failures": effective_failures,
        "open_attempts": max(
            0, effective_attempts - completions - effective_failures
        ),
        "checkpoint_count": checkpoint_count,
        "checkpoint_bytes": checkpoint_bytes,
        "checkpoint_tokens_estimate": checkpoint_tokens,
    }


def _correlate_prepared_rollovers(
    rollout: dict[str, Any], producer: dict[str, Any]
) -> dict[str, Any]:
    """Join prepared producer chains to actual new_context calls by turn/time."""
    calls = [
        value
        for value in rollout.get("_new_context_evidence", [])
        if isinstance(value, dict)
    ]
    lifecycles = [
        value
        for value in producer.get("_prepared_lifecycles", [])
        if isinstance(value, dict)
    ]
    used_calls: set[int] = set()
    correlated = 0
    for lifecycle in sorted(
        lifecycles, key=lambda value: str(value.get("allowed_at") or "")
    ):
        saved_at = _timestamp(lifecycle.get("saved_at"))
        allowed_at = _timestamp(lifecycle.get("allowed_at"))
        postcompact_at = _timestamp(lifecycle.get("postcompact_at"))
        resumed_at = _timestamp(lifecycle.get("resumed_at"))
        turn_sha256 = str(lifecycle.get("turn_sha256") or "")
        if (
            saved_at is None
            or allowed_at is None
            or postcompact_at is None
            or resumed_at is None
            or not HASH16.fullmatch(turn_sha256)
            or not saved_at < allowed_at < postcompact_at < resumed_at
        ):
            continue
        candidates: list[tuple[dt.datetime, int]] = []
        for index, call in enumerate(calls):
            if index in used_calls or call.get("turn_sha256") != turn_sha256:
                continue
            call_at = _timestamp(call.get("timestamp"))
            if call_at is not None and saved_at < call_at < allowed_at:
                candidates.append((call_at, index))
        if not candidates:
            continue
        _call_at, call_index = max(candidates)
        used_calls.add(call_index)
        correlated += 1

    prepared = int(producer.get("prepared_resume_completions", 0))
    call_count = int(rollout.get("new_context_calls", 0))
    fallback = bool(producer.get("fallback_exposure_observed"))
    mixed = fallback and bool(prepared or call_count)
    if mixed:
        status = "mixed_fallback_exposure"
    elif fallback and correlated == 0:
        status = "fallback_only"
    elif correlated and correlated == prepared == call_count:
        status = "correlated"
    elif prepared or call_count:
        status = "uncorrelated"
    else:
        status = "none"
    return {
        "correlated_prepared_resume_completions": correlated,
        "uncorrelated_prepared_resume_completions": max(0, prepared - correlated),
        "correlated_new_context_calls": correlated,
        "uncorrelated_new_context_calls": max(0, call_count - correlated),
        "fallback_exposure_observed": fallback,
        "mixed_rollover_exposure": mixed,
        "fallback_only_exposure": fallback and correlated == 0,
        "intervention_correlation_status": status,
    }


def _correlate_not_ready_liveness(
    rollout: dict[str, Any], producer: dict[str, Any]
) -> dict[str, int]:
    """Join privacy-safe NOT_READY timestamps to actual rollout terminals."""
    lifecycles = [
        value
        for value in producer.get("_not_ready_lifecycles", [])
        if isinstance(value, dict)
    ]
    terminals = [
        value
        for value in rollout.get("_terminal_evidence", [])
        if isinstance(value, dict) and _category(value.get("kind")) == "task_complete"
    ]
    starts = [
        value
        for value in rollout.get("_task_start_evidence", [])
        if isinstance(value, dict)
    ]
    user_messages = [
        value
        for value in rollout.get("_user_message_evidence", [])
        if isinstance(value, dict)
    ]
    compacted_transitions = [
        value
        for value in rollout.get("_compacted_evidence", [])
        if isinstance(value, dict)
    ]

    derived_terminals = 0
    derived_repairs = 0
    derived_advisories = 0
    derived_rescues = 0
    used_lifecycles: set[int] = set()
    failed_terminals: list[tuple[dt.datetime, str | None]] = []
    for terminal in sorted(
        terminals, key=lambda value: str(value.get("timestamp") or "")
    ):
        terminal_at = _timestamp(terminal.get("timestamp"))
        terminal_turn = str(terminal.get("turn_sha256") or "")
        if terminal_at is None:
            continue
        candidates: list[tuple[dt.datetime, int, dict[str, Any]]] = []
        for index, lifecycle in enumerate(lifecycles):
            if index in used_lifecycles:
                continue
            not_ready_at = _timestamp(lifecycle.get("not_ready_at"))
            lifecycle_turn = str(lifecycle.get("turn_sha256") or "")
            if not_ready_at is None or not_ready_at >= terminal_at:
                continue
            if (
                HASH16.fullmatch(lifecycle_turn)
                and HASH16.fullmatch(terminal_turn)
                and lifecycle_turn != terminal_turn
            ):
                continue
            candidates.append((not_ready_at, index, lifecycle))
        if not candidates:
            continue
        not_ready_at, lifecycle_index, lifecycle = max(candidates)

        transition_times = [
            stamp
            for value in lifecycle.get("transition_at", [])
            if (stamp := _timestamp(value)) is not None
        ]
        for transition in compacted_transitions:
            transition_at = _timestamp(transition.get("timestamp"))
            transition_turn = str(transition.get("turn_sha256") or "")
            if transition_at is None:
                continue
            if (
                HASH16.fullmatch(transition_turn)
                and HASH16.fullmatch(terminal_turn)
                and transition_turn != terminal_turn
            ):
                continue
            transition_times.append(transition_at)
        if any(not_ready_at < value < terminal_at for value in transition_times):
            used_lifecycles.add(lifecycle_index)
            continue

        derived_terminals += 1
        used_lifecycles.add(lifecycle_index)
        failed_terminals.append(
            (terminal_at, terminal_turn if HASH16.fullmatch(terminal_turn) else None)
        )
        derived_repairs += int(
            any(
                not_ready_at < value < terminal_at
                for raw in lifecycle.get("repair_at", [])
                if (value := _timestamp(raw)) is not None
            )
        )
        derived_advisories += int(
            any(
                not_ready_at < value < terminal_at
                for raw in lifecycle.get("advisory_at", [])
                if (value := _timestamp(raw)) is not None
            )
        )

    used_starts: set[int] = set()
    for terminal_at, terminal_turn in failed_terminals:
        candidates: list[tuple[dt.datetime, int]] = []
        for index, start in enumerate(starts):
            if index in used_starts:
                continue
            start_at = _timestamp(start.get("timestamp"))
            start_turn = str(start.get("turn_sha256") or "")
            if start_at is None or start_at <= terminal_at:
                continue
            if terminal_turn is not None and start_turn == terminal_turn:
                continue
            candidates.append((start_at, index))
        if candidates:
            _start_at, start_index = min(candidates)
            has_later_user_message = any(
                message_at > terminal_at
                for message in user_messages
                if (message_at := _timestamp(message.get("timestamp"))) is not None
            )
            if has_later_user_message:
                used_starts.add(start_index)
                derived_rescues += 1

    explicit_terminals = int(producer.get("terminal_after_not_ready", 0))
    terminal_count = max(explicit_terminals, derived_terminals)
    return {
        "terminal_after_not_ready": terminal_count,
        "terminal_after_not_ready_derived": derived_terminals,
        "terminal_after_not_ready_producer": explicit_terminals,
        "not_ready_repairs_before_terminal": max(
            int(producer.get("not_ready_repairs_before_terminal", 0)),
            derived_repairs,
        ),
        "not_ready_advisories_before_terminal": max(
            int(producer.get("not_ready_advisories_before_terminal", 0)),
            derived_advisories,
        ),
        "user_rescue_after_terminal": max(
            int(producer.get("user_rescue_after_terminal", 0)),
            derived_rescues,
        ),
        "user_rescue_after_terminal_derived": derived_rescues,
    }


def _merge_rollover_lane(
    rollout: dict[str, Any], producer: dict[str, Any]
) -> dict[str, Any]:
    result = dict(rollout)
    result.pop("_new_context_evidence", None)
    result.pop("_compacted_evidence", None)
    result.pop("_task_start_evidence", None)
    result.pop("_user_message_evidence", None)
    result.pop("_terminal_evidence", None)
    correlation = _correlate_prepared_rollovers(rollout, producer)
    liveness = _correlate_not_ready_liveness(rollout, producer)
    producer_events = int(producer.get("producer_event_count", 0))
    rollout_checkpoint = {
        "count": int(rollout.get("checkpoint_count", 0)),
        "bytes": int(rollout.get("checkpoint_bytes", 0)),
        "tokens_estimate": int(
            rollout.get("checkpoint_tokens_estimate", 0)
        ),
        "source": str(
            rollout.get("checkpoint_estimate_source") or "unavailable"
        ),
    }
    producer_checkpoint = {
        "count": int(producer.get("checkpoint_count", 0)),
        "bytes": int(producer.get("checkpoint_bytes", 0)),
        "tokens_estimate": int(
            producer.get("checkpoint_tokens_estimate", 0)
        ),
        "source": "producer" if producer.get("checkpoint_count") else "unavailable",
    }
    if rollout_checkpoint["count"] and producer_checkpoint["count"]:
        checkpoint_source = "nonjoinable_max_lower_bound"
        checkpoint_coverage = "source_lanes_exposed"
    elif producer_checkpoint["count"]:
        checkpoint_source = "producer"
        checkpoint_coverage = "producer_only"
    else:
        checkpoint_source = rollout_checkpoint["source"]
        checkpoint_coverage = "rollout_only"
    completions = max(
        int(rollout.get("rollover_completions", 0)),
        int(producer.get("rollover_completions", 0)),
    )
    nonterminal_failures = max(
        int(rollout.get("rollover_failures", 0)),
        int(producer.get("rollover_nonterminal_failures", 0)),
    )
    failures = nonterminal_failures + liveness["terminal_after_not_ready"]
    attempts = max(
        int(rollout.get("rollover_attempts", 0)),
        int(producer.get("rollover_attempts", 0)),
        completions + failures,
    )
    result.update(
        {
            "rollover_attempts": attempts,
            "rollover_completions": completions,
            "checkpointed_resume_completions": int(
                producer.get("checkpointed_resume_completions", 0)
            ),
            "prepared_resume_completions": int(
                producer.get("prepared_resume_completions", 0)
            ),
            "recovery_precompact_allows": int(
                producer.get("recovery_precompact_allows", 0)
            ),
            "recovery_advisory_resumes": int(
                producer.get("recovery_advisory_resumes", 0)
            ),
            "recovery_advisory_duplicates": int(
                producer.get("recovery_advisory_duplicates", 0)
            ),
            "checkpoint_advisory_reset_requested": int(
                producer.get("checkpoint_advisory_reset_requested", 0)
            ),
            "fallback_lifecycle_lower_bound": int(
                producer.get("fallback_lifecycle_lower_bound", 0)
            ),
            "checkpoint_validation_failures": int(
                producer.get("checkpoint_validation_failures", 0)
            ),
            **correlation,
            **liveness,
            "not_ready_lifecycles": int(
                producer.get("not_ready_lifecycles", 0)
            ),
            "unresolved_not_ready": max(
                0,
                int(producer.get("unresolved_not_ready", 0))
                - liveness["terminal_after_not_ready"],
            ),
            "terminal_after_not_ready_blocked": int(
                producer.get("terminal_after_not_ready_blocked", 0)
            ),
            "rollover_failures": failures,
            "open_attempts": max(0, attempts - completions - failures),
            "window_count": max(
                int(rollout.get("window_count", 0)),
                int(rollout.get("thread_count", 0)) + completions,
            ),
            "producer_event_count": producer_events,
            "producer_events": producer.get("producer_events", {}),
            "checkpoint_measurements": {
                "rollout": rollout_checkpoint,
                "producer": producer_checkpoint,
            },
            # The two streams have no stable shared lifecycle identifier.
            # Max is a conservative non-double-counting lower bound; source
            # lanes remain visible so partial producer coverage cannot erase
            # rollout observations.
            "checkpoint_count": max(
                rollout_checkpoint["count"], producer_checkpoint["count"]
            ),
            "checkpoint_bytes": max(
                rollout_checkpoint["bytes"], producer_checkpoint["bytes"]
            ),
            "checkpoint_tokens_estimate": max(
                rollout_checkpoint["tokens_estimate"],
                producer_checkpoint["tokens_estimate"],
            ),
            "checkpoint_estimate_source": checkpoint_source,
            "checkpoint_measurement_coverage": checkpoint_coverage,
            "failure_observability": (
                "producer_and_rollout_observed_events"
                if producer_events
                else "rollout_observed_events_only"
            ),
        }
    )
    return result


def rollover_diagnostics(
    session_hash: str,
    included: Sequence[dict[str, Any]],
    root_id: str,
    start: dt.datetime,
    end: dt.datetime,
    *,
    root_start_ordinal: int | None,
    root_end_ordinal: int | None,
    events_path: Path = DEFAULT_ROLLOVER_EVENTS,
) -> dict[str, Any]:
    root_metrics: list[dict[str, Any]] = []
    child_metrics: list[dict[str, Any]] = []
    for item in included:
        rows = _rollout_rows(item["path"])
        born = _timestamp(item.get("started_at")) or start
        interval_start = start if item["id"] == root_id else max(start, born)
        start_ordinal = (
            root_start_ordinal
            if item["id"] == root_id
            else int(item.get("run_start_ordinal", -1))
        )
        if item["id"] == root_id:
            end_ordinal = root_end_ordinal
        else:
            end_ordinal = max(
                (
                    _row_ordinal(row, index)
                    for index, row in enumerate(rows)
                    if (
                        (stamp := _timestamp(row.get("timestamp"))) is not None
                        and stamp <= end
                    )
                ),
                default=-1,
            )
        metrics = _rollout_rollover_metrics(
            rows,
            interval_start,
            end,
            start_ordinal=start_ordinal,
            end_ordinal=end_ordinal,
        )
        (root_metrics if item["id"] == root_id else child_metrics).append(metrics)

    rollout_root = _sum_rollover_lanes(root_metrics)
    rollout_child = _sum_rollover_lanes(child_metrics)
    rollout_combined = _sum_rollover_lanes([*root_metrics, *child_metrics])
    producer_rows = [
        row
        for row in _read_jsonl(events_path)
        if _row_in_interval(row, session_hash, start, end)
    ]
    thread_lanes = {
        _digest(item["id"]): ("root" if item["id"] == root_id else "subagent")
        for item in included
    }
    producer_by_lane: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in producer_rows:
        lane = thread_lanes.get(str(row.get("codex_thread_sha256") or ""), "unknown")
        producer_by_lane[lane].append(row)
    producer_root = _producer_rollover_metrics(producer_by_lane["root"])
    producer_child = _producer_rollover_metrics(producer_by_lane["subagent"])
    scoped_producer_rows = [
        *producer_by_lane["root"],
        *producer_by_lane["subagent"],
    ]
    producer_combined = _producer_rollover_metrics(scoped_producer_rows)
    return {
        "root": _merge_rollover_lane(rollout_root, producer_root),
        "subagent": _merge_rollover_lane(rollout_child, producer_child),
        "combined": _merge_rollover_lane(rollout_combined, producer_combined),
        "unscoped_producer_events": len(producer_by_lane["unknown"]),
        "telemetry_scope": "shared_session_and_task_interval",
        "rollout_compacted_is_authoritative_window_transition": True,
        "checkpoint_chain_required_for_causal_intervention": True,
        "prepared_chain_and_new_context_correlation_required": True,
        "fallback_recovery_is_diagnostic_only": True,
        "estimates_are_diagnostic_only": True,
    }


def _load_memory_module() -> Any:
    spec = importlib.util.spec_from_file_location("task_run_memory", MEMORY_DIR / "memory.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load Codex memory metrics")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _union_ranges(values: Iterable[Sequence[int]]) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int]] = []
    for raw in values:
        if not isinstance(raw, (list, tuple)) or len(raw) != 2:
            continue
        try:
            start, end = int(raw[0]), int(raw[1])
        except (TypeError, ValueError):
            continue
        if start > 0 and end >= start:
            ranges.append((start, end))
    merged: list[tuple[int, int]] = []
    for start, end in sorted(ranges):
        if merged and start <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def _range_lines(values: Iterable[tuple[int, int]]) -> int:
    return sum(end - start + 1 for start, end in values)


def memory_diagnostics(session_hash: str, start: dt.datetime, end: dt.datetime) -> dict[str, Any]:
    module = _load_memory_module()
    runtime = module.load_runtime()
    usage = [row for row in _read_jsonl(runtime.telemetry_path) if _row_in_interval(row, session_hash, start, end)]
    events = [row for row in _read_jsonl(runtime.hook_events_path) if _row_in_interval(row, session_hash, start, end)]
    opportunity = module._retrieval_opportunity_metrics(usage, events)
    documents: dict[tuple[str, str], dict[str, Any]] = {}
    seen_agent_documents: set[tuple[str, str, str]] = set()
    coverage_exact = True
    for event in events:
        if event.get("event") != "document_read":
            continue
        for detail in event.get("coverage", []) if isinstance(event.get("coverage"), list) else []:
            if not isinstance(detail, dict) or not detail.get("confirmed", True):
                continue
            key = (str(detail.get("document_sha256") or ""), str(detail.get("version_sha256") or ""))
            if not all(key):
                coverage_exact = False
                continue
            ranges = _union_ranges(detail.get("ranges", []))
            covered = _range_lines(ranges)
            added = int(detail.get("added_lines", covered) or 0)
            agent = str(event.get("agent_sha256") or "unknown")
            agent_key = (*key, agent)
            if agent_key not in seen_agent_documents and added != covered:
                # The first in-window event carried pre-run state.  Do not use
                # hook-state supplementation or pretend its positions are local.
                coverage_exact = False
                continue
            seen_agent_documents.add(agent_key)
            entry = documents.setdefault(
                key,
                {
                    "ranges": [],
                    "agents": {},
                    "total_lines": int(detail.get("total_lines", 0) or 0),
                },
            )
            if entry["total_lines"] != int(detail.get("total_lines", 0) or 0):
                coverage_exact = False
                continue
            prior_agent = entry["agents"].get(agent, [])
            next_agent = _union_ranges([*prior_agent, *ranges])
            if _range_lines(next_agent) - _range_lines(prior_agent) != added:
                coverage_exact = False
                continue
            entry["ranges"] = _union_ranges([*entry["ranges"], *ranges])
            entry["agents"][agent] = next_agent
    covered_lines = sum(_range_lines(value["ranges"]) for value in documents.values()) if coverage_exact else None
    total_lines = sum(int(value["total_lines"]) for value in documents.values()) if coverage_exact else None
    overlap_lines = (
        sum(
            sum(_range_lines(ranges) for ranges in value["agents"].values())
            - _range_lines(value["ranges"])
            for value in documents.values()
        )
        if coverage_exact
        else None
    )
    targeted_revisits = sum(
        max(0, int(event.get("targeted_revisits", 0) or 0))
        for event in events
        if event.get("event") == "document_read"
    )
    redundant_attempts = sum(
        bool(event.get("redundant_broad_attempt"))
        for event in events
        if event.get("event") == "repeat_guard"
    )
    redundant_tokens_estimate = sum(
        max(0, int(event.get("estimated_tokens", 0) or 0))
        for event in events
        if event.get("event") == "repeat_guard"
        and event.get("redundant_broad_attempt")
    )
    return {
        "query_count": len(usage),
        "hook_event_count": len(events),
        "estimates_are_diagnostic_only": True,
        "opportunity": opportunity,
        "repeated_reads": {
            "targeted_document_revisits": targeted_revisits,
            "redundant_document_attempts": redundant_attempts,
            "redundant_document_tokens_estimate": redundant_tokens_estimate,
            "source": "interval_hook_events",
            "estimate_is_diagnostic_only": True,
        },
        "coverage": {
            "source": "interval_event_ranges_only",
            "hook_state_supplementation": False,
            "exact": coverage_exact,
            "documents": len(documents),
            "covered_lines": covered_lines,
            "total_lines": total_lines,
            "cross_agent_overlap_lines": overlap_lines,
            "multi_agent_documents": (
                sum(len(value["agents"]) > 1 for value in documents.values())
                if coverage_exact
                else None
            ),
        },
    }


def graphify_diagnostics(
    session_hash: str, included: Sequence[dict[str, Any]], root_id: str,
    start: dt.datetime, end: dt.datetime,
) -> dict[str, Any]:
    root_items = [item for item in included if item["id"] == root_id]
    child_items = [item for item in included if item["id"] != root_id]
    root_lane = _graphify_rollout_lane(root_items, start, end)
    child_lane = _graphify_rollout_lane(child_items, start, end)
    combined = {key: root_lane[key] + child_lane[key] for key in root_lane}
    usage_path = ROOT / "graphify-out" / "context_query_stats.jsonl"
    reminder_path = ROOT / "graphify-arch" / "graphify-out" / "cache" / "codex-reminder" / "events.jsonl"
    usage = [row for row in _read_jsonl(usage_path) if _row_in_interval(row, session_hash, start, end)]
    reminders = [row for row in _read_jsonl(reminder_path) if _row_in_interval(row, session_hash, start, end)]
    thread_lane = {_digest(item["id"]): ("root" if item["id"] == root_id else "subagent") for item in included}
    shared_by_lane = Counter()
    for row in usage:
        shared_by_lane[thread_lane.get(str(row.get("codex_thread_sha256") or ""), "unknown")] += 1
    return {
        "rollout": {"root": root_lane, "subagent": child_lane, "combined": combined},
        "shared_usage": {
            "count": len(usage),
            "root": shared_by_lane["root"],
            "subagent": shared_by_lane["subagent"],
            "unknown": shared_by_lane["unknown"],
            "result_tokens_estimate": sum(max(0, int(row.get("result_tokens_estimate", 0) or 0)) for row in usage),
            "truncated": sum(bool(row.get("truncated")) for row in usage),
            "operations": dict(sorted(Counter(_category(row.get("operation")) for row in usage).items())),
        },
        "shared_reminders": {
            "count": len(reminders),
            "blocked": sum(bool(row.get("blocked")) for row in reminders),
            "events": dict(sorted(Counter(_category(row.get("event")) for row in reminders).items())),
        },
        "estimates_are_diagnostic_only": True,
    }


def _start_event(
    args: argparse.Namespace,
    *,
    request_key_path: Path = DEFAULT_REQUEST_KEY,
) -> dict[str, Any]:
    now = dt.datetime.now(dt.timezone.utc)
    variant = getattr(args, "variant", None) or os.environ.get("CODEX_TASK_RUN_VARIANT")
    if variant not in {"off", "shadow", "active"}:
        raise ValueError(
            "variant is unavailable; apply a task-run profile or pass --variant as a matching assertion"
        )
    root_session = _resolve_root_session(args.session, _sessions_root())
    boundary = _latest_task_started(root_session["path"], now)
    prior_tasks = int(boundary.get("prior_task_count", 0))
    reused_override = bool(getattr(args, "allow_reused_session", False))
    diagnostic_only = bool(
        getattr(args, "diagnostic_only", False)
        or reused_override
        or getattr(args, "allow_policy_mismatch", False)
    )
    if prior_tasks and not reused_override:
        raise ValueError(
            "measured cohorts require the first task in a fresh Codex rollout; start a fresh session or use --allow-reused-session for a permanently incomparable diagnostic run"
        )
    policy = effective_policy()
    mismatches = profile_mismatches(variant, policy)
    if mismatches and not args.allow_policy_mismatch:
        raise ValueError("policy profile mismatch: " + ", ".join(mismatches))
    required = sorted({_normalize_gate(value) for value in _gate_args(args.required_gate)})
    held_out = sorted({_normalize_gate(value) for value in _gate_args(args.held_out_gate)})
    allow_na = sorted({_normalize_gate(value) for value in _gate_args(args.allow_na_gate)})
    if not required:
        raise ValueError("at least one --required-gate must be predeclared")
    if not held_out and not diagnostic_only:
        raise ValueError(
            "at least one --held-out-gate is required for a comparable benchmark; use --diagnostic-only for a permanently savings-ineligible run"
        )
    if set(required) & set(held_out):
        raise ValueError("required and held-out gate IDs must be disjoint")
    if not set(allow_na) <= set(required) | set(held_out):
        raise ValueError("--allow-na-gate must name a predeclared gate")
    task_request = _task_request_identity(
        root_session["path"],
        int(boundary["index"]),
        key_path=request_key_path,
    )
    metadata = _task_environment(
        root_session["path"],
        boundary["turn_id"],
        root_session["cli_version"],
        int(boundary["index"]),
        request_key_path=request_key_path,
    )
    requested_rollover_arm = getattr(args, "rollover_arm", None)
    declared_rollover_arm = os.environ.get("CODEX_TASK_RUN_ROLLOVER_ARM")
    if declared_rollover_arm is not None:
        declared_rollover_arm = declared_rollover_arm.strip().lower()
        if declared_rollover_arm not in ROLLOVER_ARMS | {"unspecified"}:
            raise ValueError(
                "CODEX_TASK_RUN_ROLLOVER_ARM must be control, active, or unspecified"
            )
    if requested_rollover_arm and not declared_rollover_arm:
        raise ValueError(
            "--rollover-arm is an assertion only; set the rollover profile before starting the Codex session"
        )
    if (
        requested_rollover_arm
        and declared_rollover_arm
        and requested_rollover_arm != declared_rollover_arm
    ):
        raise ValueError("rollover arm assertion does not match the session environment")
    selected_rollover_arm = (
        requested_rollover_arm or declared_rollover_arm or "unspecified"
    )
    if selected_rollover_arm in ROLLOVER_ARMS and variant != "active":
        raise ValueError(
            "rollover experiments require the active Graphify/memory profile in both arms"
        )
    selected_rollover_policy = rollover_policy(metadata, selected_rollover_arm)
    return {
        "schema_version": SCHEMA_VERSION,
        "type": "start",
        "ts": _now(),
        "run_sha256": _digest(uuid.uuid4().hex + str(time.time_ns())),
        "task_sha256": _digest(args.task_id),
        **task_request,
        "variant": variant,
        "rollover_arm": selected_rollover_arm,
        "rollover_policy": selected_rollover_policy,
        "rollover_policy_sha256": selected_rollover_policy["policy_sha256"],
        "rollover_common_policy_sha256": selected_rollover_policy[
            "common_policy_sha256"
        ],
        "replicate": args.replicate,
        "started_at": boundary["timestamp"].isoformat(),
        "start_ordinal": int(boundary["index"]),
        "prior_task_count": prior_tasks,
        "prior_completed_turns": int(boundary.get("prior_completed_turns", 0)),
        "fresh_session_eligible": prior_tasks == 0,
        "reused_session_override": bool(prior_tasks and reused_override),
        "diagnostic_only": diagnostic_only,
        "session_group_sha256": _digest(root_session["session_id"]),
        "root_thread_sha256": _digest(root_session["id"]),
        "root_session_date": _root_session_date(root_session),
        "task_turn_sha256": _digest(boundary["turn_id"]),
        "repo_start": repo_fingerprint(),
        "tool_start": tool_fingerprints(),
        "environment": metadata,
        "policy": policy,
        "policy_tuning_sha256": _policy_tuning_sha256(policy),
        "profile_match": not mismatches,
        "profile_mismatches": mismatches,
        "policy_mismatch_override": bool(mismatches and args.allow_policy_mismatch),
        "required_gates": required,
        "held_out_gates": held_out,
        "allow_na_gates": allow_na,
        "gate_set_sha256": _digest(_canonical({"required": required, "held_out": held_out, "allow_na": allow_na})),
        "device_matrix_sha256": _digest(args.device_matrix) if args.device_matrix else "none",
        "review_rubric_sha256": (
            _digest(args.review_rubric_id)
            if getattr(args, "review_rubric_id", None)
            else "none"
        ),
    }


def _run_events(path: Path, run_id: str) -> list[dict[str, Any]]:
    rows = [row for row in _read_jsonl(path) if row.get("run_sha256") == run_id]
    if not rows:
        raise ValueError("unknown run ID")
    return rows


def _resolve_run(path: Path, selector: str) -> tuple[str, list[dict[str, Any]]]:
    rows = _read_jsonl(path)
    ids = sorted({str(row.get("run_sha256")) for row in rows if str(row.get("run_sha256", "")).startswith(selector)})
    if len(ids) != 1:
        raise ValueError("run selector must match exactly one run")
    return ids[0], [row for row in rows if row.get("run_sha256") == ids[0]]


def _latest_gates(events: Sequence[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for row in events:
        if row.get("type") == "gate":
            result[str(row.get("gate_id"))] = row
    return result


def _gate_evidence(start: dict[str, Any], events: Sequence[dict[str, Any]]) -> dict[str, Any]:
    latest = _latest_gates(events)
    gates: dict[str, dict[str, Any]] = {}
    complete = True
    for gate_id in [*start.get("required_gates", []), *start.get("held_out_gates", [])]:
        row = latest.get(gate_id, {})
        source = _category(row.get("source"))
        if source == "executed":
            definition = str(row.get("argv_sha256") or "")
            result = str(row.get("output_sha256") or "")
        elif source == "recorded":
            definition = str(row.get("evidence_sha256") or "")
            result = definition
        else:
            definition = ""
            result = ""
        valid = bool(HASH16.fullmatch(definition) and HASH16.fullmatch(result))
        complete = complete and valid
        gates[gate_id] = {
            "source": source,
            "definition_sha256": definition if valid else "missing",
            "result_sha256": result if HASH16.fullmatch(result) else "missing",
        }
    comparable = {
        gate_id: {
            "source": value["source"],
            "definition_sha256": value["definition_sha256"],
        }
        for gate_id, value in gates.items()
    }
    return {
        "complete": complete and bool(gates),
        "gates": gates,
        "definition_set_sha256": _digest(_canonical(comparable)),
    }


def _gate_assessment(start: dict[str, Any], events: Sequence[dict[str, Any]]) -> dict[str, Any]:
    latest = _latest_gates(events)
    histories: dict[str, list[str]] = defaultdict(list)
    for row in events:
        if row.get("type") == "gate":
            histories[str(row.get("gate_id"))].append(
                str(row.get("status") or "missing")
            )
    allowed_na = set(start.get("allow_na_gates", []))
    statuses: dict[str, str] = {}
    missing: list[str] = []
    invalid: list[str] = []
    historical_failures: list[str] = []
    attempt_counts: dict[str, int] = {}
    for gate in [*start.get("required_gates", []), *start.get("held_out_gates", [])]:
        status = str(latest.get(gate, {}).get("status") or "missing")
        statuses[gate] = status
        attempt_counts[gate] = len(histories.get(gate, []))
        if "fail" in histories.get(gate, []):
            historical_failures.append(gate)
        if status == "missing":
            missing.append(gate)
        elif status != "pass" and not (status == "na" and gate in allowed_na):
            invalid.append(gate)
        elif gate in historical_failures:
            invalid.append(gate)
    required = list(start.get("required_gates", []))
    return {
        "statuses": statuses,
        "missing": missing,
        "nonpassing": sorted(set(invalid)),
        "historical_failures": historical_failures,
        "attempt_counts": attempt_counts,
        "pass": bool(required) and not missing and not invalid,
        "required_gate_count": len(required),
    }


def _comparison_quality_evidence(
    start: dict[str, Any], quality: dict[str, Any], gate_evidence: dict[str, Any]
) -> bool:
    """Whether this run can participate in a later quality-safe comparison."""
    if start.get("diagnostic_only") or not gate_evidence.get("complete"):
        return False
    statuses = quality.get("gates", {}).get("statuses", {})
    passing = {
        gate_id
        for gate_id in start.get("held_out_gates", [])
        if statuses.get(gate_id) == "pass"
    }
    if not passing:
        return False
    rubric = str(start.get("review_rubric_sha256", "none"))
    if rubric == "none":
        return True
    evidence = gate_evidence.get("gates", {})
    return any(
        evidence.get(gate_id, {}).get("source") == "recorded"
        and evidence.get(gate_id, {}).get("definition_sha256") == rubric
        for gate_id in passing
    )


def _policy_intact(start: dict[str, Any], end_tools: dict[str, str]) -> tuple[bool, list[str]]:
    reasons: list[str] = []
    if start.get("diagnostic_only"):
        reasons.append("diagnostic_only")
    if not start.get("profile_match"):
        reasons.append("start_policy_profile_mismatch")
    if not start.get("fresh_session_eligible", True):
        reasons.append("reused_session_history")
    if effective_policy() != start.get("policy"):
        reasons.append("effective_policy_changed")
    if start.get("rollover_policy_sha256"):
        expected_arm = str(start.get("rollover_arm") or "unspecified")
        current_arm = os.environ.get("CODEX_TASK_RUN_ROLLOVER_ARM")
        if expected_arm in ROLLOVER_ARMS and (
            current_arm is None or current_arm.strip().lower() != expected_arm
        ):
            reasons.append("rollover_arm_environment_changed")
        current_rollover = rollover_policy(
            start.get("environment", {}),
            expected_arm,
        )
        if current_rollover.get("policy_sha256") != start.get(
            "rollover_policy_sha256"
        ):
            reasons.append("rollover_policy_changed")
    start_capabilities = start.get("environment", {}).get(
        "model_capabilities_sha256"
    )
    if start_capabilities:
        current_capabilities = _codex_model_capabilities(
            str(start.get("environment", {}).get("model") or "unknown")
        )
        if current_capabilities.get("sha256") != start_capabilities:
            reasons.append("model_capabilities_changed")
    for key in ("memory_config", "hooks", "rollover_tool", "policy_code_sha256"):
        if start.get("tool_start", {}).get(key) != end_tools.get(key):
            reasons.append(f"{key}_changed")
    return not reasons, reasons


def _calculate_run(
    start_event: dict[str, Any], end: dt.datetime,
    *, root_end_ordinal: int | None = None, terminal_kind: str | None = None,
) -> dict[str, Any]:
    catalog = _catalog_for_run(start_event, end)
    roots = [item for item in catalog if _digest(item["id"]) == start_event["root_thread_sha256"]]
    if not roots:
        raise ValueError("root rollout is no longer available")
    root = roots[0]
    started = _timestamp(start_event["started_at"])
    if started is None:
        raise ValueError("invalid run start timestamp")
    root_rows = _rollout_rows(root["path"])
    end_ordinal = (
        _row_ordinal(root_rows[-1], len(root_rows) - 1)
        if root_end_ordinal is None and root_rows
        else -1
        if root_end_ordinal is None
        else root_end_ordinal
    )
    tokens, included = collect_tokens(
        root,
        catalog,
        started,
        end,
        root_start_ordinal=int(start_event.get("start_ordinal", -1)),
        root_end_ordinal=end_ordinal,
        require_complete_logs=terminal_kind is not None,
    )
    group = start_event["session_group_sha256"]
    return {
        "tokens": tokens,
        "memory": memory_diagnostics(group, started, end),
        "graphify": graphify_diagnostics(group, included, root["id"], started, end),
        "rollover": rollover_diagnostics(
            group,
            included,
            root["id"],
            started,
            end,
            root_start_ordinal=int(start_event.get("start_ordinal", -1)),
            root_end_ordinal=end_ordinal,
        ),
        "rollout_boundary": {
            "root_start_ordinal": int(start_event.get("start_ordinal", -1)),
            "root_end_ordinal": end_ordinal,
            "terminal_kind": terminal_kind or "active",
        },
        "attribution_estimates_are_diagnostic_only": True,
    }


def _quality(
    start: dict[str, Any], events: Sequence[dict[str, Any]], metrics: dict[str, Any],
    acceptance: str, defects: dict[str, int], policy_intact: bool,
) -> dict[str, Any]:
    gates = _gate_assessment(start, events)
    exact = bool(metrics["tokens"]["combined"]["exact"])
    terminal_boundary_complete = (
        metrics.get("rollout_boundary", {}).get("terminal_kind")
        == "task_complete"
    )
    rollover = metrics.get("rollover", {})
    combined_rollover = (
        rollover.get("combined", {}) if isinstance(rollover, dict) else {}
    )
    terminal_after_not_ready = int(
        combined_rollover.get("terminal_after_not_ready", 0)
    )
    rollover_liveness_intact = terminal_after_not_ready == 0
    terminal_complete = terminal_boundary_complete and rollover_liveness_intact
    passed = exact and terminal_complete and policy_intact and acceptance == "pass" and defects["critical"] == 0 and gates["pass"]
    hard_fail = (
        acceptance == "fail"
        or defects["critical"] > 0
        or not rollover_liveness_intact
        or bool(gates.get("historical_failures"))
        or any(status == "fail" for status in gates["statuses"].values())
    )
    return {
        "status": "pass" if passed else "fail" if hard_fail else "incomplete",
        "acceptance": acceptance,
        "defects": defects,
        "gates": gates,
        "token_exact": exact,
        "policy_intact": policy_intact,
        "terminal_boundary_complete": terminal_boundary_complete,
        "terminal_complete": terminal_complete,
        "rollover_liveness_intact": rollover_liveness_intact,
        "terminal_after_not_ready": terminal_after_not_ready,
    }


def _finish_event(
    args: argparse.Namespace,
    run_id: str,
    events: Sequence[dict[str, Any]],
    *,
    request_key_path: Path = DEFAULT_REQUEST_KEY,
) -> dict[str, Any]:
    if any(row.get("type") == "finish" for row in events):
        raise ValueError("run is already finished")
    start = next(row for row in events if row.get("type") == "start")
    # Use the run's bounded date cohort; scanning every historical rollout is
    # both unnecessary and prohibitively expensive on long-lived machines.
    root = _root_for_start(start)
    if root is None:
        raise ValueError("root rollout is no longer available")
    terminal = _terminal_boundary(root["path"], start)
    if terminal is None:
        raise ValueError("the measured turn has no task_complete/turn_aborted boundary yet; use report for provisional exact-so-far metrics and retry finish after the turn ends")
    end = terminal["timestamp"]
    task_request = _task_request_identity(
        root["path"],
        int(start["start_ordinal"]),
        end_ordinal=int(terminal["ordinal"]),
        key_path=request_key_path,
        create_key=False,
    )
    if task_request["task_request_key_sha256"] != start.get(
        "task_request_key_sha256"
    ):
        raise ValueError("task request privacy key changed during the measured run")
    metrics = _calculate_run(
        start,
        end,
        root_end_ordinal=int(terminal["ordinal"]),
        terminal_kind=str(terminal["kind"]),
    )
    tools = tool_fingerprints()
    intact, reasons = _policy_intact(start, tools)
    defects = {
        "critical": args.critical_defects,
        "major": args.major_defects,
        "minor": args.minor_defects,
    }
    quality = _quality(start, events, metrics, args.acceptance, defects, intact)
    gate_evidence = _gate_evidence(start, events)
    quality["gate_evidence_complete"] = gate_evidence["complete"]
    quality["comparison_quality_evidence"] = _comparison_quality_evidence(
        start, quality, gate_evidence
    )
    if quality["status"] == "pass" and not gate_evidence["complete"]:
        quality["status"] = "incomplete"
    return {
        "schema_version": SCHEMA_VERSION,
        "type": "finish",
        "ts": _now(),
        "run_sha256": run_id,
        **task_request,
        "ended_at": end.isoformat(),
        "end_ordinal": int(terminal["ordinal"]),
        "end_turn_sha256": start["task_turn_sha256"],
        "repo_end": repo_fingerprint(),
        "tool_end": tools,
        "policy_end": effective_policy(),
        "comparability_environment_intact": intact,
        "comparability_environment_reasons": reasons,
        "repair_turns": args.repair_turns,
        "gate_evidence": gate_evidence,
        "quality": quality,
        "metrics": metrics,
        "complete": True,
    }


def _public_report(events: Sequence[dict[str, Any]], live: bool = False) -> dict[str, Any]:
    start = next(row for row in events if row.get("type") == "start")
    finish = next((row for row in reversed(events) if row.get("type") == "finish"), None)
    if finish is None:
        terminal: dict[str, Any] | None = None
        if not live:
            root = _root_for_start(start)
            if root is not None:
                terminal = _terminal_boundary(root["path"], start)
        if terminal is None:
            metrics = _calculate_run(start, dt.datetime.now(dt.timezone.utc))
        else:
            metrics = _calculate_run(
                start,
                terminal["timestamp"],
                root_end_ordinal=int(terminal["ordinal"]),
                terminal_kind=str(terminal["kind"]),
            )
        quality = {
            "status": "incomplete",
            "reason": "awaiting_finish" if terminal else "run_active",
            "token_exact_so_far": metrics["tokens"]["combined"]["exact"],
            "terminal_boundary_available": terminal is not None,
        }
        ended_at = None
        complete = False
    else:
        metrics = finish["metrics"]
        quality = finish["quality"]
        ended_at = finish["ended_at"]
        complete = True
    comparison_eligible = bool(
        complete
        and not start.get("diagnostic_only")
        and quality.get("status") == "pass"
        and quality.get(
            "comparison_quality_evidence",
            _comparison_quality_evidence(
                start,
                quality,
                finish.get("gate_evidence", {}) if finish else {},
            ),
        )
    )
    if finish is not None:
        comparability_intact = bool(
            finish.get(
                "comparability_environment_intact",
                quality.get("policy_intact", False),
            )
        )
        comparability_reasons = [
            _category(reason)
            for reason in finish.get("comparability_environment_reasons", [])
        ]
        if not comparability_intact and not comparability_reasons:
            comparability_reasons = ["policy_not_intact"]
    else:
        comparability_intact = bool(start.get("profile_match")) and not bool(
            start.get("diagnostic_only")
        )
        comparability_reasons = [
            _category(reason) for reason in start.get("profile_mismatches", [])
        ]
        if start.get("diagnostic_only"):
            comparability_reasons.append("diagnostic_only")
    return {
        "run_sha256": start["run_sha256"],
        "task_sha256": start["task_sha256"],
        "variant": start["variant"],
        "rollover_arm": start.get("rollover_arm", "unspecified"),
        "rollover_policy": start.get("rollover_policy", {}),
        "replicate": start["replicate"],
        "started_at": start["started_at"],
        "ended_at": ended_at,
        "complete": complete,
        "provisional": not complete,
        "comparison_eligible": comparison_eligible,
        "pair_candidate": comparison_eligible,
        "savings_eligible": False,
        "savings_requires_task_comparison": True,
        "profile_match": start["profile_match"],
        "diagnostic_only": bool(start.get("diagnostic_only")),
        "comparability_environment_intact": comparability_intact,
        "comparability_environment_reasons": sorted(set(comparability_reasons)),
        "quality": quality,
        "metrics": metrics,
        "gates": _gate_assessment(start, events),
    }


def _pair_mismatches(
    left: dict[str, Any],
    right: dict[str, Any],
    *,
    experiment: str = "graph",
) -> list[str]:
    fields = {
        "task": (left.get("task_sha256"), right.get("task_sha256")),
        "task_request_key": (
            left.get("task_request_key_sha256"),
            right.get("task_request_key_sha256"),
        ),
        "replicate": (left.get("replicate"), right.get("replicate")),
        "start_head": (left.get("repo_start", {}).get("head_sha256"), right.get("repo_start", {}).get("head_sha256")),
        "start_worktree": (left.get("repo_start", {}).get("worktree_sha256"), right.get("repo_start", {}).get("worktree_sha256")),
        "model": (left.get("environment", {}).get("model"), right.get("environment", {}).get("model")),
        "reasoning_effort": (left.get("environment", {}).get("reasoning_effort"), right.get("environment", {}).get("reasoning_effort")),
        "cli_version": (left.get("environment", {}).get("cli_version"), right.get("environment", {}).get("cli_version")),
        "service_tier": (left.get("environment", {}).get("service_tier"), right.get("environment", {}).get("service_tier")),
        "model_provider": (left.get("environment", {}).get("model_provider_sha256"), right.get("environment", {}).get("model_provider_sha256")),
        "context_window": (left.get("environment", {}).get("context_window_sha256"), right.get("environment", {}).get("context_window_sha256")),
        "context_window_tokens": (left.get("environment", {}).get("context_window_tokens"), right.get("environment", {}).get("context_window_tokens")),
        "max_context_window_tokens": (left.get("environment", {}).get("max_context_window_tokens"), right.get("environment", {}).get("max_context_window_tokens")),
        "effective_context_window_percent": (left.get("environment", {}).get("effective_context_window_percent"), right.get("environment", {}).get("effective_context_window_percent")),
        "token_budget_fallback_tokens": (left.get("environment", {}).get("token_budget_fallback_tokens"), right.get("environment", {}).get("token_budget_fallback_tokens")),
        "model_capabilities": (left.get("environment", {}).get("model_capabilities_sha256"), right.get("environment", {}).get("model_capabilities_sha256")),
        "collaboration_mode": (left.get("environment", {}).get("collaboration_mode_sha256"), right.get("environment", {}).get("collaboration_mode_sha256")),
        "multi_agent_version": (left.get("environment", {}).get("multi_agent_version_sha256"), right.get("environment", {}).get("multi_agent_version_sha256")),
        "approval_policy": (left.get("environment", {}).get("approval_policy"), right.get("environment", {}).get("approval_policy")),
        "permission_profile": (left.get("environment", {}).get("permission_profile_sha256"), right.get("environment", {}).get("permission_profile_sha256")),
        "sandbox_policy": (left.get("environment", {}).get("sandbox_policy_sha256"), right.get("environment", {}).get("sandbox_policy_sha256")),
        "personality": (left.get("environment", {}).get("personality_sha256"), right.get("environment", {}).get("personality_sha256")),
        "realtime_active": (left.get("environment", {}).get("realtime_active"), right.get("environment", {}).get("realtime_active")),
        "comp_hash": (left.get("environment", {}).get("comp_sha256"), right.get("environment", {}).get("comp_sha256")),
        "current_date": (left.get("environment", {}).get("current_date"), right.get("environment", {}).get("current_date")),
        "timezone": (left.get("environment", {}).get("timezone"), right.get("environment", {}).get("timezone")),
        "cwd": (
            left.get("environment", {}).get("cwd_sha256"),
            right.get("environment", {}).get("cwd_sha256"),
        ),
        "workspace_roots": (
            left.get("environment", {}).get("workspace_roots_sha256"),
            right.get("environment", {}).get("workspace_roots_sha256"),
        ),
        "cwd_available": (
            left.get("environment", {}).get("cwd_available"),
            right.get("environment", {}).get("cwd_available"),
        ),
        "workspace_roots_available": (
            left.get("environment", {}).get("workspace_roots_available"),
            right.get("environment", {}).get("workspace_roots_available"),
        ),
        "policy_tuning": (left.get("policy_tuning_sha256"), right.get("policy_tuning_sha256")),
        "rollover_common_policy": (
            left.get("rollover_common_policy_sha256", "legacy_unspecified"),
            right.get("rollover_common_policy_sha256", "legacy_unspecified"),
        ),
        "device_matrix": (left.get("device_matrix_sha256"), right.get("device_matrix_sha256")),
        "gate_set": (left.get("gate_set_sha256"), right.get("gate_set_sha256")),
        "review_rubric": (left.get("review_rubric_sha256", "none"), right.get("review_rubric_sha256", "none")),
        "memory_config": (left.get("tool_start", {}).get("memory_config"), right.get("tool_start", {}).get("memory_config")),
        "memory_state_path": (left.get("tool_start", {}).get("memory_state_path"), right.get("tool_start", {}).get("memory_state_path")),
        "hooks": (left.get("tool_start", {}).get("hooks"), right.get("tool_start", {}).get("hooks")),
        "graphify_runtime": (left.get("tool_start", {}).get("graphify_runtime"), right.get("tool_start", {}).get("graphify_runtime")),
        "python_runtime": (left.get("tool_start", {}).get("python_runtime"), right.get("tool_start", {}).get("python_runtime")),
        "rollover_tool": (left.get("tool_start", {}).get("rollover_tool"), right.get("tool_start", {}).get("rollover_tool")),
        "policy_code": (left.get("tool_start", {}).get("policy_code_sha256"), right.get("tool_start", {}).get("policy_code_sha256")),
        "memory_graph": (left.get("tool_start", {}).get("memory_graph"), right.get("tool_start", {}).get("memory_graph")),
        "graphify_arch": (left.get("tool_start", {}).get("graphify_arch"), right.get("tool_start", {}).get("graphify_arch")),
        "graphify_full": (left.get("tool_start", {}).get("graphify_full"), right.get("tool_start", {}).get("graphify_full")),
    }
    if experiment == "rollover":
        fields["graph_variant"] = (left.get("variant"), right.get("variant"))
    else:
        fields["rollover_arm"] = (
            left.get("rollover_arm", "unspecified"),
            right.get("rollover_arm", "unspecified"),
        )
    result = [name for name, values in fields.items() if values[0] != values[1]]
    if experiment == "rollover":
        if left.get("rollover_arm") != "control":
            result.append("baseline_rollover_arm")
        if right.get("rollover_arm") != "active":
            result.append("intervention_rollover_arm")
        if left.get("variant") != "active":
            result.append("baseline_graph_profile_not_active")
        if right.get("variant") != "active":
            result.append("intervention_graph_profile_not_active")
        for side, value in (("baseline", left), ("intervention", right)):
            policy = value.get("rollover_policy", {})
            if (
                not isinstance(policy, dict)
                or not policy.get("arm_declared_before_session")
                or not value.get("rollover_common_policy_sha256")
            ):
                result.append(f"{side}_rollover_policy_missing")
            elif (
                not policy.get("native_model_policy_available")
                or not isinstance(
                    policy.get("effective_token_budget_max_tokens"), int
                )
                or policy.get("effective_token_budget_max_tokens", 0) <= 0
            ):
                result.append(f"{side}_rollover_policy_unverified")
    left_key = str(left.get("task_request_key_sha256") or "")
    right_key = str(right.get("task_request_key_sha256") or "")
    if not HASH32.fullmatch(left_key) or not HASH32.fullmatch(right_key):
        result.append("task_request_key_missing")
    for key in ("cwd_sha256", "workspace_roots_sha256"):
        left_hash = str(left.get("environment", {}).get(key) or "")
        right_hash = str(right.get("environment", {}).get(key) or "")
        if not HASH32.fullmatch(left_hash) or not HASH32.fullmatch(right_hash):
            result.append(f"{key}_missing")
    if not left.get("environment", {}).get("cwd_available") or not right.get("environment", {}).get(
        "cwd_available"
    ):
        result.append("cwd_missing")
    if not left.get("environment", {}).get("workspace_roots_available") or not right.get(
        "environment", {}
    ).get("workspace_roots_available"):
        result.append("workspace_roots_missing")
    if left.get("diagnostic_only") or right.get("diagnostic_only"):
        result.append("diagnostic_only")
    return result


def _median(values: Sequence[float]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    middle = len(ordered) // 2
    return ordered[middle] if len(ordered) % 2 else (ordered[middle - 1] + ordered[middle]) / 2


def _rollover_snapshot(finish: dict[str, Any] | None) -> dict[str, Any] | None:
    if finish is None:
        return None
    value = finish.get("metrics", {}).get("rollover", {}).get("combined")
    if not isinstance(value, dict):
        return None
    return {
        key: value.get(key)
        for key in (
            "window_count",
            "rollover_attempts",
            "rollover_completions",
            "rollout_compacted_transitions",
            "checkpointed_resume_completions",
            "prepared_resume_completions",
            "correlated_prepared_resume_completions",
            "uncorrelated_prepared_resume_completions",
            "new_context_calls",
            "correlated_new_context_calls",
            "uncorrelated_new_context_calls",
            "recovery_precompact_allows",
            "recovery_advisory_resumes",
            "recovery_advisory_duplicates",
            "checkpoint_advisory_reset_requested",
            "fallback_lifecycle_lower_bound",
            "fallback_exposure_observed",
            "fallback_only_exposure",
            "mixed_rollover_exposure",
            "intervention_correlation_status",
            "checkpoint_validation_failures",
            "not_ready_lifecycles",
            "unresolved_not_ready",
            "not_ready_repairs_before_terminal",
            "not_ready_advisories_before_terminal",
            "terminal_after_not_ready_blocked",
            "terminal_after_not_ready",
            "terminal_after_not_ready_derived",
            "terminal_after_not_ready_producer",
            "user_rescue_after_terminal",
            "user_rescue_after_terminal_derived",
            "rollover_failures",
            "open_attempts",
            "checkpoint_count",
            "checkpoint_bytes",
            "checkpoint_tokens_estimate",
            "checkpoint_estimate_source",
            "context_input_before_first_rollover",
            "context_input_after_first_rollover",
            "context_input_reduction_observed",
            "code_read_tool_cells",
            "repeated_code_read_tool_cells",
            "repeated_code_read_tool_cells_after_rollover",
            "document_read_tool_cells",
            "repeated_document_read_tool_cells",
            "repeated_document_read_tool_cells_after_rollover",
            "before_first_rollover",
            "after_rollovers",
        )
    }


def _rollover_intervention_evidence(
    finish: dict[str, Any] | None,
) -> dict[str, Any] | None:
    if finish is None:
        return None
    root = finish.get("metrics", {}).get("rollover", {}).get("root")
    combined = finish.get("metrics", {}).get("rollover", {}).get("combined")
    if not isinstance(root, dict) or not isinstance(combined, dict):
        return None
    calls = root.get("new_context_calls")
    completions = root.get("checkpointed_resume_completions")
    prepared = root.get("prepared_resume_completions")
    correlated = root.get("correlated_prepared_resume_completions")
    unmatched_prepared = root.get("uncorrelated_prepared_resume_completions")
    unmatched_calls = root.get("uncorrelated_new_context_calls")
    fallback_count = root.get("fallback_lifecycle_lower_bound")
    fallback = root.get("fallback_exposure_observed")
    mixed = root.get("mixed_rollover_exposure")
    combined_fallback_count = combined.get("fallback_lifecycle_lower_bound")
    combined_fallback = combined.get("fallback_exposure_observed")
    combined_mixed = combined.get("mixed_rollover_exposure")
    if (
        not isinstance(calls, int)
        or isinstance(calls, bool)
        or not isinstance(completions, int)
        or isinstance(completions, bool)
        or not isinstance(prepared, int)
        or isinstance(prepared, bool)
        or not isinstance(correlated, int)
        or isinstance(correlated, bool)
        or not isinstance(unmatched_prepared, int)
        or isinstance(unmatched_prepared, bool)
        or not isinstance(unmatched_calls, int)
        or isinstance(unmatched_calls, bool)
        or not isinstance(fallback_count, int)
        or isinstance(fallback_count, bool)
        or not isinstance(fallback, bool)
        or not isinstance(mixed, bool)
        or not isinstance(combined_fallback_count, int)
        or isinstance(combined_fallback_count, bool)
        or not isinstance(combined_fallback, bool)
        or not isinstance(combined_mixed, bool)
    ):
        return None
    return {
        "root_new_context_calls": calls,
        "root_checkpointed_resume_completions": completions,
        "root_prepared_resume_completions": prepared,
        "root_correlated_prepared_resume_completions": correlated,
        "root_uncorrelated_prepared_resume_completions": unmatched_prepared,
        "root_uncorrelated_new_context_calls": unmatched_calls,
        "root_fallback_lifecycle_lower_bound": fallback_count,
        "root_fallback_exposure_observed": fallback,
        "root_mixed_rollover_exposure": mixed,
        "combined_fallback_lifecycle_lower_bound": combined_fallback_count,
        "combined_fallback_exposure_observed": combined_fallback,
        "combined_mixed_rollover_exposure": combined_mixed,
    }


def _cohort_observation(
    run_ids: Sequence[str], finishes: dict[str, dict[str, Any]]
) -> dict[str, Any]:
    statuses: Counter[str] = Counter()
    exact = 0
    snapshots: list[dict[str, Any]] = []
    for run_id in run_ids:
        finish = finishes.get(run_id)
        if finish is None:
            statuses["unfinished"] += 1
            continue
        statuses[_category(finish.get("quality", {}).get("status"))] += 1
        if finish.get("metrics", {}).get("tokens", {}).get("combined", {}).get(
            "exact"
        ):
            exact += 1
        snapshot = _rollover_snapshot(finish)
        if snapshot is not None:
            snapshots.append(snapshot)
    return {
        "attempt_count": len(run_ids),
        "status_counts": dict(sorted(statuses.items())),
        "exact_token_run_count": exact,
        "rollover": snapshots[0] if len(run_ids) == 1 and snapshots else None,
    }


def _median_rollover_pair_metrics(pairs: Sequence[dict[str, Any]]) -> dict[str, Any]:
    fields = (
        "window_count",
        "rollover_attempts",
        "rollover_completions",
        "rollout_compacted_transitions",
        "checkpointed_resume_completions",
        "prepared_resume_completions",
        "correlated_prepared_resume_completions",
        "uncorrelated_prepared_resume_completions",
        "new_context_calls",
        "correlated_new_context_calls",
        "uncorrelated_new_context_calls",
        "recovery_precompact_allows",
        "recovery_advisory_resumes",
        "checkpoint_advisory_reset_requested",
        "fallback_lifecycle_lower_bound",
        "checkpoint_validation_failures",
        "not_ready_lifecycles",
        "unresolved_not_ready",
        "not_ready_repairs_before_terminal",
        "not_ready_advisories_before_terminal",
        "terminal_after_not_ready_blocked",
        "terminal_after_not_ready",
        "user_rescue_after_terminal",
        "rollover_failures",
        "checkpoint_bytes",
        "checkpoint_tokens_estimate",
        "repeated_code_read_tool_cells_after_rollover",
        "repeated_document_read_tool_cells_after_rollover",
    )
    result: dict[str, Any] = {}
    for side in ("left", "right"):
        snapshots = [
            pair.get(f"{side}_rollover")
            for pair in pairs
            if isinstance(pair.get(f"{side}_rollover"), dict)
        ]
        result[side] = {
            field: _median(
                [
                    float(value[field])
                    for value in snapshots
                    if isinstance(value.get(field), (int, float))
                    and not isinstance(value.get(field), bool)
                ]
            )
            for field in fields
        }
    result["estimates_are_diagnostic_only"] = True
    return result


def _exact_pair_medians(pairs: Sequence[dict[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for field in ("input", "cached_input", "uncached_input", "output", "total"):
        reductions = [
            float(pair[f"{field}_reduction_percent"])
            for pair in pairs
            if isinstance(pair.get(f"{field}_reduction_percent"), (int, float))
            and not isinstance(pair.get(f"{field}_reduction_percent"), bool)
        ]
        result[field] = {
            "baseline": _median(
                [float(pair[f"baseline_{field}"]) for pair in pairs]
            ),
            "intervention": _median(
                [float(pair[f"intervention_{field}"]) for pair in pairs]
            ),
            "delta": _median([float(pair[f"{field}_delta"]) for pair in pairs]),
            "reduction_percent": _median(reductions),
        }
    return result


def compare_events(
    rows: Sequence[dict[str, Any]],
    task_hash: str,
    threshold: float,
    *,
    experiment: str = "graph",
) -> dict[str, Any]:
    if experiment not in {"graph", "rollover"}:
        raise ValueError("experiment must be graph or rollover")
    starts = {row["run_sha256"]: row for row in rows if row.get("type") == "start" and row.get("task_sha256") == task_hash}
    finishes = {row["run_sha256"]: row for row in rows if row.get("type") == "finish" and row.get("run_sha256") in starts}
    by_variant: dict[str, dict[int, list[str]]] = defaultdict(lambda: defaultdict(list))
    for run_id, start in starts.items():
        cohort = (
            str(start.get("rollover_arm") or "unspecified")
            if experiment == "rollover"
            else str(start["variant"])
        )
        by_variant[cohort][int(start["replicate"])].append(run_id)
    transitions = (
        (("control", "active"),)
        if experiment == "rollover"
        else (("off", "shadow"), ("shadow", "active"), ("off", "active"))
    )
    output: dict[str, Any] = {}
    for left_name, right_name in transitions:
        pairs: list[dict[str, Any]] = []
        mismatch_counts: Counter[str] = Counter()
        replicates = sorted(set(by_variant[left_name]) | set(by_variant[right_name]))
        for replicate in replicates:
            left_ids = by_variant[left_name][replicate]
            right_ids = by_variant[right_name][replicate]
            if not left_ids or not right_ids:
                if not left_ids:
                    mismatch_counts["missing_baseline_replicate"] += 1
                    if len(right_ids) == 1:
                        right_finish = finishes.get(right_ids[0])
                        if right_finish is None:
                            mismatch_counts["intervention_unfinished"] += 1
                        else:
                            right_status = right_finish.get("quality", {}).get("status")
                            if right_status == "fail":
                                mismatch_counts["intervention_quality_failure"] += 1
                            elif right_status != "pass":
                                mismatch_counts["intervention_quality_incomplete"] += 1
                            right_tokens = right_finish.get("metrics", {}).get("tokens", {}).get(
                                "combined", {}
                            )
                            if not right_tokens.get("exact"):
                                mismatch_counts["intervention_tokens_inexact"] += 1
                if not right_ids:
                    mismatch_counts["missing_intervention_replicate"] += 1
                continue
            if len(left_ids) != 1 or len(right_ids) != 1:
                mismatch_counts["ambiguous_replicate"] += 1
                continue
            left_id = left_ids[0]
            right_id = right_ids[0]
            left, right = starts[left_id], starts[right_id]
            mismatches = _pair_mismatches(
                left, right, experiment=experiment
            )
            if left_id not in finishes or right_id not in finishes:
                mismatches.append("unfinished")
                if right_id not in finishes:
                    mismatches.append("intervention_unfinished")
            if mismatches:
                for reason in mismatches:
                    mismatch_counts[reason] += 1
                continue
            left_finish, right_finish = finishes[left_id], finishes[right_id]
            finish_request_mismatches = [
                name
                for name, left_value, right_value in (
                    (
                        "task_request",
                        left_finish.get("task_request_sha256"),
                        right_finish.get("task_request_sha256"),
                    ),
                    (
                        "task_request_count",
                        left_finish.get("task_request_count"),
                        right_finish.get("task_request_count"),
                    ),
                    (
                        "task_request_key",
                        left_finish.get("task_request_key_sha256"),
                        right_finish.get("task_request_key_sha256"),
                    ),
                )
                if left_value != right_value
            ]
            left_request = str(left_finish.get("task_request_sha256") or "")
            right_request = str(right_finish.get("task_request_sha256") or "")
            if not HASH32.fullmatch(left_request) or not HASH32.fullmatch(right_request):
                finish_request_mismatches.append("task_request_missing")
            left_request_key = str(left_finish.get("task_request_key_sha256") or "")
            right_request_key = str(right_finish.get("task_request_key_sha256") or "")
            if not HASH32.fullmatch(left_request_key) or not HASH32.fullmatch(right_request_key):
                finish_request_mismatches.append("task_request_key_missing")
            left_request_count = left_finish.get("task_request_count")
            right_request_count = right_finish.get("task_request_count")
            if (
                not isinstance(left_request_count, int)
                or isinstance(left_request_count, bool)
                or left_request_count < 1
                or not isinstance(right_request_count, int)
                or isinstance(right_request_count, bool)
                or right_request_count < 1
            ):
                finish_request_mismatches.append("task_request_count_missing")
            if finish_request_mismatches:
                for reason in finish_request_mismatches:
                    mismatch_counts[reason] += 1
                continue
            left_quality = left_finish.get("quality", {})
            right_quality = right_finish.get("quality", {})
            left_liveness_failures = int(
                left_finish.get("metrics", {})
                .get("rollover", {})
                .get("combined", {})
                .get("terminal_after_not_ready", 0)
            )
            right_liveness_failures = int(
                right_finish.get("metrics", {})
                .get("rollover", {})
                .get("combined", {})
                .get("terminal_after_not_ready", 0)
            )
            if left_liveness_failures or right_liveness_failures:
                mismatch_counts["rollover_liveness_failure"] += 1
                if right_liveness_failures:
                    mismatch_counts["intervention_quality_failure"] += 1
                continue
            if (
                not left.get("profile_match")
                or not right.get("profile_match")
                or not left_quality.get("policy_intact", False)
                or not right_quality.get("policy_intact", False)
            ):
                mismatch_counts["policy_not_intact"] += 1
                continue
            worse_defects = [
                severity
                for severity in ("critical", "major", "minor")
                if int(right_quality.get("defects", {}).get(severity, 0))
                > int(left_quality.get("defects", {}).get(severity, 0))
            ]
            if worse_defects:
                mismatch_counts["quality_regression"] += 1
                for severity in worse_defects:
                    mismatch_counts[f"new_{severity}_defects"] += 1
                continue
            if int(right_finish.get("repair_turns", 0)) > int(left_finish.get("repair_turns", 0)):
                mismatch_counts["repair_turn_increase"] += 1
                continue
            if left_quality.get("status") != "pass" or right_quality.get("status") != "pass":
                mismatch_counts["quality_not_pass"] += 1
                if right_quality.get("status") == "fail":
                    mismatch_counts["intervention_quality_failure"] += 1
                elif right_quality.get("status") != "pass":
                    mismatch_counts["intervention_quality_incomplete"] += 1
                continue
            left_evidence = left_finish.get("gate_evidence", {})
            right_evidence = right_finish.get("gate_evidence", {})
            if not left_evidence.get("complete") or not right_evidence.get("complete"):
                mismatch_counts["gate_evidence_missing"] += 1
                continue
            if left_evidence.get("definition_set_sha256") != right_evidence.get("definition_set_sha256"):
                mismatch_counts["gate_evidence_mismatch"] += 1
                continue
            held_out = set(left.get("held_out_gates", []))
            left_statuses = left_quality.get("gates", {}).get("statuses", {})
            right_statuses = right_quality.get("gates", {}).get("statuses", {})
            # NA is useful operationally but is not executed held-out evidence.
            # A rubric identifier alone is likewise not proof; a matching,
            # passing held-out gate with frozen command/artifact evidence is.
            passing_held_out = {
                gate_id
                for gate_id in held_out
                if (
                left_statuses.get(gate_id) == "pass"
                and right_statuses.get(gate_id) == "pass"
                )
            }
            has_quality_evidence = bool(passing_held_out)
            rubric = str(left.get("review_rubric_sha256", "none"))
            blinded_review_evidence = False
            if rubric != "none":
                left_gate_evidence = left_evidence.get("gates", {})
                right_gate_evidence = right_evidence.get("gates", {})
                blinded_review_evidence = any(
                    left_gate_evidence.get(gate_id, {}).get("source") == "recorded"
                    and right_gate_evidence.get(gate_id, {}).get("source") == "recorded"
                    and left_gate_evidence.get(gate_id, {}).get("definition_sha256") == rubric
                    and right_gate_evidence.get(gate_id, {}).get("definition_sha256") == rubric
                    for gate_id in passing_held_out
                )
                has_quality_evidence = blinded_review_evidence
            if not has_quality_evidence:
                mismatch_counts["quality_evidence_missing"] += 1
                continue
            left_tokens = left_finish.get("metrics", {}).get("tokens", {}).get("combined", {})
            right_tokens = right_finish.get("metrics", {}).get("tokens", {}).get("combined", {})
            if not left_tokens.get("exact") or not right_tokens.get("exact"):
                mismatch_counts["tokens_inexact"] += 1
                if not right_tokens.get("exact"):
                    mismatch_counts["intervention_tokens_inexact"] += 1
                continue
            left_rollover = _rollover_snapshot(left_finish)
            right_rollover = _rollover_snapshot(right_finish)
            left_intervention = _rollover_intervention_evidence(left_finish)
            right_intervention = _rollover_intervention_evidence(right_finish)
            if experiment == "rollover":
                if (
                    left_rollover is None
                    or right_rollover is None
                    or left_intervention is None
                    or right_intervention is None
                ):
                    mismatch_counts["rollover_intervention_evidence_missing"] += 1
                    continue
                control_completions = left_intervention[
                    "root_checkpointed_resume_completions"
                ]
                active_completions = right_intervention[
                    "root_checkpointed_resume_completions"
                ]
                control_calls = left_intervention["root_new_context_calls"]
                active_calls = right_intervention["root_new_context_calls"]
                control_prepared = left_intervention[
                    "root_prepared_resume_completions"
                ]
                active_prepared = right_intervention[
                    "root_prepared_resume_completions"
                ]
                control_correlated = left_intervention[
                    "root_correlated_prepared_resume_completions"
                ]
                active_correlated = right_intervention[
                    "root_correlated_prepared_resume_completions"
                ]
                evidence_mismatches: list[str] = []
                if (
                    control_completions != 0
                    or control_prepared != 0
                    or control_correlated != 0
                ):
                    evidence_mismatches.append(
                        "control_checkpoint_intervention_observed"
                    )
                if control_calls != 0:
                    evidence_mismatches.append("control_new_context_observed")
                if left_intervention["combined_fallback_exposure_observed"]:
                    evidence_mismatches.append(
                        "control_recovery_intervention_observed"
                    )
                if active_correlated < 1:
                    evidence_mismatches.append(
                        "active_checkpoint_intervention_not_observed"
                    )
                if active_calls < 1:
                    evidence_mismatches.append(
                        "active_new_context_not_observed"
                    )
                if active_completions != active_correlated:
                    evidence_mismatches.append(
                        "active_checkpoint_lifecycle_uncorrelated"
                    )
                if (
                    active_prepared != active_correlated
                    or right_intervention[
                        "root_uncorrelated_prepared_resume_completions"
                    ]
                ):
                    evidence_mismatches.append(
                        "active_prepared_lifecycle_uncorrelated"
                    )
                if (
                    active_calls != active_correlated
                    or right_intervention["root_uncorrelated_new_context_calls"]
                ):
                    evidence_mismatches.append(
                        "active_new_context_uncorrelated"
                    )
                if right_intervention["combined_fallback_exposure_observed"]:
                    evidence_mismatches.append(
                        "active_mixed_rollover_exposure"
                        if active_correlated
                        else "active_fallback_only"
                    )
                if evidence_mismatches:
                    mismatch_counts.update(evidence_mismatches)
                    continue
            pair: dict[str, Any] = {
                "replicate": replicate,
                "blinded_review_evidence": blinded_review_evidence,
                "left_rollover": left_rollover,
                "right_rollover": right_rollover,
                "left_intervention_evidence": left_intervention,
                "right_intervention_evidence": right_intervention,
            }
            for severity in ("critical", "major", "minor"):
                pair[f"{severity}_defect_delta"] = (
                    int(left_quality.get("defects", {}).get(severity, 0))
                    - int(right_quality.get("defects", {}).get(severity, 0))
                )
            valid = True
            for field in (
                "input",
                "cached_input",
                "uncached_input",
                "output",
                "total",
            ):
                base = left_tokens.get(field)
                current = right_tokens.get(field)
                if (
                    not isinstance(base, int)
                    or isinstance(base, bool)
                    or base < 0
                    or not isinstance(current, int)
                    or isinstance(current, bool)
                    or current < 0
                    or (field in {"input", "total"} and base == 0)
                ):
                    mismatch_counts[f"invalid_{field}_tokens"] += 1
                    valid = False
                    break
                pair[f"baseline_{field}"] = base
                pair[f"intervention_{field}"] = current
                pair[f"{field}_delta"] = base - current
                pair[f"{field}_reduction_percent"] = (
                    round((base - current) * 100.0 / base, 3)
                    if base
                    else None
                )
            if valid and experiment == "rollover":
                pair["input_tokens_saved"] = pair["input_delta"]
                pair["input_percent_saved"] = pair[
                    "input_reduction_percent"
                ]
            if valid:
                pairs.append(pair)
        accepted_replicates = {int(pair["replicate"]) for pair in pairs}
        rollover_observations = [
            {
                "replicate": replicate,
                "baseline": _cohort_observation(
                    by_variant[left_name][replicate], finishes
                ),
                "intervention": _cohort_observation(
                    by_variant[right_name][replicate], finishes
                ),
                "included_in_exact_token_comparison": replicate
                in accepted_replicates,
            }
            for replicate in replicates
        ]
        input_median = _median([float(pair["input_reduction_percent"]) for pair in pairs])
        total_median = _median([float(pair["total_reduction_percent"]) for pair in pairs])
        quality_regressed = bool(
            mismatch_counts["quality_regression"]
            or mismatch_counts["repair_turn_increase"]
            or mismatch_counts["intervention_quality_failure"]
        )
        intervention_incomplete = bool(
            mismatch_counts["intervention_quality_incomplete"]
            or mismatch_counts["intervention_unfinished"]
            or mismatch_counts["intervention_tokens_inexact"]
        )
        comparison_incomplete = intervention_incomplete or bool(mismatch_counts)
        major_quality_deltas = [
            int(pair["critical_defect_delta"]) + int(pair["major_defect_delta"])
            for pair in pairs
        ]
        blinded_quality_deltas = [
            int(pair["critical_defect_delta"]) + int(pair["major_defect_delta"])
            for pair in pairs
            if pair.get("blinded_review_evidence")
        ]
        if quality_regressed:
            quality_verdict = "regressed"
        elif comparison_incomplete or len(pairs) < 3:
            quality_verdict = "insufficient"
        elif (
            len(blinded_quality_deltas) >= 3
            and (_median([float(value) for value in blinded_quality_deltas]) or 0) > 0
        ):
            quality_verdict = "improved"
        else:
            quality_verdict = "noninferior"
        if quality_regressed:
            verdict = "regressed"
        elif input_median is not None and total_median is not None and (input_median < 0 or total_median < 0):
            verdict = "regressed"
        elif comparison_incomplete or len(pairs) < 3:
            verdict = "insufficient"
        elif input_median is not None and total_median is not None and input_median >= threshold and total_median >= threshold:
            verdict = "proven"
        else:
            verdict = "not_proven"
        output[f"{left_name}_to_{right_name}"] = {
            "verdict": verdict,
            "quality_verdict": quality_verdict,
            "quality_improved_pairs": sum(value > 0 for value in major_quality_deltas),
            "quality_equal_pairs": sum(value == 0 for value in major_quality_deltas),
            "blinded_quality_pairs": len(blinded_quality_deltas),
            "comparable_quality_pass_pairs": len(pairs),
            "median_input_reduction_percent": input_median,
            "median_total_reduction_percent": total_median,
            "exact_token_pair_medians": _exact_pair_medians(pairs),
            "threshold_percent": threshold,
            "pairs": pairs,
            "rollover_observations": rollover_observations,
            "rollover_quality_pass_pair_medians": _median_rollover_pair_metrics(
                pairs
            ),
            "mismatch_reasons": dict(sorted(mismatch_counts.items())),
        }

    if experiment == "rollover":
        result = output["control_to_active"]
        result["role"] = "rollover_intervention"
        result["control_arm_role"] = "negative_control"
        result["checkpoint_intervention_evidence_pairs"] = len(
            result["pairs"]
        )
        result["paired_token_verdict"] = result["verdict"]
        result["causal_eligible"] = result["verdict"] in {
            "proven",
            "not_proven",
        }
        if result["pairs"]:
            result["median_input_tokens_saved"] = _median(
                [float(pair["input_tokens_saved"]) for pair in result["pairs"]]
            )
            result["median_input_percent_saved"] = result[
                "median_input_reduction_percent"
            ]
        result["within_run_segments_are_not_causal_savings"] = True
        return {
            "task_sha256": task_hash,
            "experiment": "rollover",
            "negative_control": {
                "arm": "control",
                "role": "token_budget_disabled_causal_baseline",
            },
            "comparisons": output,
            "estimates_used_in_exact_tokens": False,
            "checkpoint_estimates_used_in_savings": False,
        }

    negative = output["off_to_shadow"]
    negative["role"] = "negative_control"
    negative["paired_token_verdict"] = negative["verdict"]
    negative_reasons: list[str] = []
    negative_input = negative.get("median_input_reduction_percent")
    negative_total = negative.get("median_total_reduction_percent")
    if int(negative.get("comparable_quality_pass_pairs", 0)) < 3:
        negative_control_verdict = "insufficient"
        negative_reasons.append("fewer_than_three_comparable_pairs")
    elif negative.get("quality_verdict") == "insufficient":
        negative_control_verdict = "insufficient"
        negative_reasons.append("quality_evidence_incomplete")
    elif negative.get("quality_verdict") != "noninferior":
        negative_control_verdict = "failed"
        negative_reasons.append("unexpected_quality_shift")
    elif not isinstance(negative_input, (int, float)) or not isinstance(
        negative_total, (int, float)
    ):
        negative_control_verdict = "insufficient"
        negative_reasons.append("token_medians_unavailable")
    else:
        if abs(float(negative_input)) > NEGATIVE_CONTROL_TOLERANCE_PERCENT:
            negative_reasons.append("input_token_shift")
        if abs(float(negative_total)) > NEGATIVE_CONTROL_TOLERANCE_PERCENT:
            negative_reasons.append("total_token_shift")
        negative_control_verdict = "failed" if negative_reasons else "pass"
    negative["negative_control_verdict"] = negative_control_verdict
    negative["negative_control_reasons"] = negative_reasons
    negative["negative_control_tolerance_percent"] = NEGATIVE_CONTROL_TOLERANCE_PERCENT
    negative["causal_eligible"] = negative_control_verdict == "pass"
    negative["verdict"] = negative_control_verdict

    for name in ("shadow_to_active", "off_to_active"):
        result = output[name]
        result["role"] = "automatic_intervention"
        result["paired_token_verdict"] = result["verdict"]
        result["negative_control_verdict"] = negative_control_verdict
        result["negative_control_tolerance_percent"] = NEGATIVE_CONTROL_TOLERANCE_PERCENT
        result["causal_eligible"] = negative_control_verdict == "pass"
        if result["verdict"] == "regressed":
            continue
        if negative_control_verdict == "failed":
            result["verdict"] = "confounded"
            reasons = Counter(result.get("mismatch_reasons", {}))
            reasons["negative_control_failed"] += 1
            result["mismatch_reasons"] = dict(sorted(reasons.items()))
        elif negative_control_verdict != "pass":
            result["verdict"] = "insufficient"
            reasons = Counter(result.get("mismatch_reasons", {}))
            reasons["negative_control_insufficient"] += 1
            result["mismatch_reasons"] = dict(sorted(reasons.items()))

    return {
        "task_sha256": task_hash,
        "experiment": "graph",
        "negative_control": {
            "verdict": negative_control_verdict,
            "tolerance_percent": NEGATIVE_CONTROL_TOLERANCE_PERCENT,
            "reasons": negative_reasons,
        },
        "comparisons": output,
        "estimates_used_in_exact_tokens": False,
    }


def _render_report(value: dict[str, Any]) -> str:
    tokens = value["metrics"]["tokens"]
    quality = value["quality"]
    root_tokens = tokens.get("root", {"total": 0, "request_count": 0})
    child_tokens = tokens.get("subagent", {"total": 0, "request_count": 0})
    rollover = value.get("metrics", {}).get("rollover", {}).get("combined", {})
    before = rollover.get("before_first_rollover", {})
    after = rollover.get("after_rollovers", {})
    rollover_policy_value = value.get("rollover_policy", {})
    lines = [
        f"Task run {value['run_sha256']} · {value['variant']} replicate {value['replicate']} · rollover {value.get('rollover_arm', 'unspecified')} · quality {quality['status']}",
        f"exact tokens: {tokens['combined']['exact']} · input={tokens['combined']['input']} · output={tokens['combined']['output']} · total={tokens['combined']['total']} · requests={tokens['combined']['request_count']}",
        f"lanes: root total={root_tokens['total']}/{root_tokens['request_count']} requests · subagent total={child_tokens['total']}/{child_tokens['request_count']} requests",
        "rollover: windows={} · attempts={}/completed={}/failed={} · checkpointed/prepared/correlated={}/{}/{} · new-context calls={} · fallback allowed/advisory={}/{} · mixed={} · checkpoint={} bytes/~{} tokens".format(
            rollover.get("window_count", 0),
            rollover.get("rollover_attempts", 0),
            rollover.get("rollover_completions", 0),
            rollover.get("rollover_failures", 0),
            rollover.get("checkpointed_resume_completions", 0),
            rollover.get("prepared_resume_completions", 0),
            rollover.get("correlated_prepared_resume_completions", 0),
            rollover.get("new_context_calls", 0),
            rollover.get("recovery_precompact_allows", 0),
            rollover.get("recovery_advisory_resumes", 0),
            rollover.get("mixed_rollover_exposure", False),
            rollover.get("checkpoint_bytes", 0),
            rollover.get("checkpoint_tokens_estimate", 0),
        ),
        "rollover liveness: NOT_READY={}/unresolved={} · repaired/advisory before terminal={}/{} · advisory resets={} · blocked/actual terminals={}/{} · later user rescues={}".format(
            rollover.get("not_ready_lifecycles", 0),
            rollover.get("unresolved_not_ready", 0),
            rollover.get("not_ready_repairs_before_terminal", 0),
            rollover.get("not_ready_advisories_before_terminal", 0),
            rollover.get("checkpoint_advisory_reset_requested", 0),
            rollover.get("terminal_after_not_ready_blocked", 0),
            rollover.get("terminal_after_not_ready", 0),
            rollover.get("user_rescue_after_terminal", 0),
        ),
        "task token segments (not causal savings): before first rollover input/total={}/{} · after rollovers={}/{} · repeated code/document reads after={}/{}".format(
            before.get("input", 0),
            before.get("total", 0),
            after.get("input", 0),
            after.get("total", 0),
            rollover.get("repeated_code_read_tool_cells_after_rollover", 0),
            rollover.get("repeated_document_read_tool_cells_after_rollover", 0),
        ),
        "rollover policy diagnostics: fallback={} · effective max={} · checkpoint capsule={}".format(
            rollover_policy_value.get("native_token_budget_fallback_tokens"),
            rollover_policy_value.get("effective_token_budget_max_tokens"),
            rollover_policy_value.get("checkpoint_context_tokens"),
        ),
        f"complete: {value['complete']} · profile match: {value['profile_match']} · diagnostic only: {value['diagnostic_only']}",
        "comparability: "
        + ("intact" if value["comparability_environment_intact"] else "not intact")
        + (
            " · reasons=" + ",".join(value["comparability_environment_reasons"])
            if value["comparability_environment_reasons"]
            else ""
        ),
    ]
    return "\n".join(lines)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ledger", type=Path, help="private ledger override")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("profiles", help="print policy profiles")
    profile = sub.add_parser("profile", help="render one pre-session policy environment")
    profile.add_argument("--variant", choices=("off", "shadow", "active"), required=True)
    profile.add_argument("--format", choices=("shell", "json"), default="shell")
    rollover_profile = sub.add_parser(
        "rollover-profile",
        help="render an ACTIVE graph/memory rollover experiment environment",
    )
    rollover_profile.add_argument(
        "--arm", choices=("control", "active"), required=True
    )
    rollover_profile.add_argument(
        "--format", choices=("shell", "json"), default="shell"
    )
    start = sub.add_parser("start", help="start a measured task interval")
    start.add_argument("--task-id", required=True)
    start.add_argument(
        "--variant",
        choices=("off", "shadow", "active"),
        help="optional assertion; normally inferred from CODEX_TASK_RUN_VARIANT",
    )
    start.add_argument("--replicate", type=int, required=True)
    start.add_argument("--required-gate", action="append", nargs="+", default=[])
    start.add_argument("--held-out-gate", action="append", nargs="+", default=[])
    start.add_argument("--allow-na-gate", action="append", nargs="+", default=[])
    start.add_argument("--device-matrix")
    start.add_argument("--review-rubric-id")
    start.add_argument(
        "--rollover-arm",
        choices=("control", "active"),
        help="assert the rollover arm set before this Codex session started",
    )
    start.add_argument("--session")
    start.add_argument("--allow-policy-mismatch", action="store_true")
    start.add_argument("--allow-reused-session", action="store_true")
    start.add_argument(
        "--diagnostic-only",
        action="store_true",
        help="allow a non-comparable, permanently savings-ineligible run",
    )
    gate = sub.add_parser("gate", help="execute and record a declared gate")
    gate.add_argument("--run", required=True)
    gate.add_argument("--gate-id", required=True)
    gate.add_argument("argv", nargs=argparse.REMAINDER)
    record = sub.add_parser("record-gate", help="record an externally executed gate")
    record.add_argument("--run", required=True)
    record.add_argument("--gate-id", required=True)
    record.add_argument("--status", choices=("pass", "fail", "infra", "na"), required=True)
    record.add_argument("--evidence-id", required=True)
    finish = sub.add_parser("finish", help="finish and assess a measured run")
    finish.add_argument("--run", required=True)
    finish.add_argument("--acceptance", choices=("pass", "fail"), required=True)
    finish.add_argument("--critical-defects", type=int, required=True)
    finish.add_argument("--major-defects", type=int, required=True)
    finish.add_argument("--minor-defects", type=int, required=True)
    finish.add_argument("--repair-turns", type=int, required=True)
    report = sub.add_parser("report", help="show one run")
    report.add_argument("--run", required=True)
    report.add_argument("--json", action="store_true")
    compare = sub.add_parser("compare", help="compare paired variants")
    compare.add_argument("--task-id", required=True)
    compare.add_argument(
        "--experiment", choices=("graph", "rollover"), default="graph"
    )
    compare.add_argument(
        "--threshold",
        type=float,
        default=MINIMUM_SAVINGS_THRESHOLD_PERCENT,
        help="median input/total reduction required; may be stricter than 20, never lower",
    )
    compare.add_argument("--json", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    ledger = args.ledger or _ledger_path()
    try:
        if args.command == "profiles":
            print("Set one profile before starting the measured Codex session; start validates the effective policy.")
            for variant in ("off", "shadow", "active"):
                exports = " ".join(f"{key}={value}" for key, value in profile_environment(variant).items())
                print(f"{variant}: {exports}")
            return 0
        if args.command == "profile":
            values = profile_environment(args.variant)
            if args.format == "json":
                print(json.dumps(values, indent=2, sort_keys=True))
            else:
                print("# Apply before starting the measured Codex session.")
                for key, value in values.items():
                    print(f"export {key}={_shell_quote(value)}")
            return 0
        if args.command == "rollover-profile":
            values = rollover_profile_environment(args.arm)
            feature_action = "disable" if args.arm == "control" else "enable"
            if args.format == "json":
                print(
                    json.dumps(
                        {
                            "arm": args.arm,
                            "environment": values,
                            "codex_launch_argv_suffix": [
                                f"--{feature_action}",
                                "token_budget",
                            ],
                        },
                        indent=2,
                        sort_keys=True,
                    )
                )
            else:
                print("# Apply before starting the measured Codex session.")
                print(
                    "# Then launch: codex --{} token_budget".format(
                        feature_action
                    )
                )
                for key, value in values.items():
                    print(f"export {key}={_shell_quote(value)}")
            return 0
        if args.command == "start":
            if args.replicate < 1:
                raise ValueError("replicate must be positive")
            row = _start_event(args, request_key_path=_request_key_path(ledger))
            _append_event(ledger, row)
            print(row["run_sha256"])
            return 0
        if args.command == "compare":
            if (
                not math.isfinite(args.threshold)
                or args.threshold < MINIMUM_SAVINGS_THRESHOLD_PERCENT
                or args.threshold > 100.0
            ):
                raise ValueError(
                    "threshold must be finite and between 20 and 100 percent"
                )
            value = compare_events(
                _read_jsonl(ledger),
                _digest(args.task_id),
                args.threshold,
                experiment=args.experiment,
            )
            if args.json:
                print(json.dumps(value, indent=2, sort_keys=True))
            else:
                for name, result in value["comparisons"].items():
                    suffix = (
                        (
                            f" · median input saved={result['median_input_tokens_saved']} tokens/{result['median_input_percent_saved']}%"
                            if "median_input_tokens_saved" in result
                            else " · no evidence-qualified token-savings pairs"
                        )
                        if args.experiment == "rollover"
                        else f" · median input reduction={result['median_input_reduction_percent']}%"
                    )
                    print(
                        f"{name}: {result['verdict']} · pairs={result['comparable_quality_pass_pairs']}"
                        + suffix
                        + f" · total reduction={result['median_total_reduction_percent']}%"
                    )
            return 0
        run_id, events = _resolve_run(ledger, args.run)
        start = next(row for row in events if row.get("type") == "start")
        if args.command in {"gate", "record-gate"}:
            gate_id = _normalize_gate(args.gate_id)
            if gate_id not in set(start.get("required_gates", [])) | set(start.get("held_out_gates", [])):
                raise ValueError("gate was not predeclared at start")
            if args.command == "record-gate":
                row = {
                    "schema_version": SCHEMA_VERSION,
                    "type": "gate",
                    "ts": _now(),
                    "run_sha256": run_id,
                    "gate_id": gate_id,
                    "status": args.status,
                    "source": "recorded",
                    "evidence_sha256": _digest(args.evidence_id),
                }
                _append_event(ledger, row)
                return 0
            command = list(args.argv)
            if command and command[0] == "--":
                command = command[1:]
            if not command:
                raise ValueError("gate requires argv after --")
            argv_hash = _digest(_canonical(command))
            output_hash = hashlib.sha256()
            started = time.monotonic()
            try:
                process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            except OSError:
                row = {
                    "schema_version": SCHEMA_VERSION,
                    "type": "gate",
                    "ts": _now(),
                    "run_sha256": run_id,
                    "gate_id": gate_id,
                    "status": "infra",
                    "source": "executed",
                    "argv_sha256": argv_hash,
                    "output_sha256": output_hash.hexdigest()[:16],
                    "exit_code": None,
                    "duration_ms": round((time.monotonic() - started) * 1000, 2),
                }
                _append_event(ledger, row)
                print("task-run: gate process could not be started", file=sys.stderr)
                return 2
            assert process.stdout is not None
            while chunk := process.stdout.read(8192):
                output_hash.update(chunk)
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
            status_code = process.wait()
            row = {
                "schema_version": SCHEMA_VERSION, "type": "gate", "ts": _now(),
                "run_sha256": run_id, "gate_id": gate_id,
                "status": "pass" if status_code == 0 else "fail", "source": "executed",
                "argv_sha256": argv_hash, "output_sha256": output_hash.hexdigest()[:16],
                "exit_code": status_code, "duration_ms": round((time.monotonic() - started) * 1000, 2),
            }
            _append_event(ledger, row)
            return status_code
        if args.command == "finish":
            for value in (args.critical_defects, args.major_defects, args.minor_defects, args.repair_turns):
                if value < 0:
                    raise ValueError("defect and repair counts must be nonnegative")
            row = _finish_event(
                args,
                run_id,
                events,
                request_key_path=_request_key_path(ledger),
            )
            _append_event(ledger, row)
            print(_render_report(_public_report([*events, row])))
            return 0 if row["quality"]["status"] == "pass" else 2
        if args.command == "report":
            value = _public_report(events)
            print(json.dumps(value, indent=2, sort_keys=True) if args.json else _render_report(value))
            return 0
    except ValueError as exc:
        print(f"task-run: {exc}", file=sys.stderr)
        return 2
    return 0


def cli(argv: Sequence[str] | None = None) -> int:
    return main(list(sys.argv[1:] if argv is None else argv))


if __name__ == "__main__":
    raise SystemExit(cli())
