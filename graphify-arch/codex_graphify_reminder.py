#!/usr/bin/env python3
"""Advisory Codex hook for Graphify-first code browsing cadence.

The hook is deliberately fail-open: it never denies or rewrites a tool call.
It emits additional model context once when code browsing begins without a
compact/native Graphify query, then at each configured raw-browse ceiling.
Plan/spec document reads are classified separately and never increment the
counter.

Only anonymous counters are persisted. Commands, prompts, filenames, raw
session ids, and tool inputs are not written to the state or event ledger.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Iterable

try:
    import fcntl
except ImportError:  # pragma: no cover - this repository runs the hook on macOS/Linux.
    fcntl = None  # type: ignore[assignment]

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import tdd_context as context  # noqa: E402


STATE_SCHEMA_VERSION = 1
EVENT_SCHEMA_VERSION = 1
DEFAULT_CEILING = 20
DEFAULT_STATE_DIR = (
    context.ARCH_DIR / "graphify-out" / "cache" / "codex-reminder"
)

_SHELL_TOOL_NAMES = {
    "bash",
    "exec",
    "exec_command",
    "functions.exec",
    "shell",
    "shell_command",
    "unified_exec",
}
_READ_TOOL_NAMES = {"read", "read_file"}
_SEARCH_TOOL_NAMES = {"glob", "grep", "search", "search_files"}
_FALSE_VALUES = {"0", "false", "no", "off"}


def _utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8", errors="replace")).hexdigest()[:16]


def _enabled() -> bool:
    return os.environ.get("GRAPHIFY_CODEX_REMINDER", "1").strip().lower() not in _FALSE_VALUES


def _ceiling() -> int:
    raw = os.environ.get("GRAPHIFY_CODEX_REMINDER_CEILING", str(DEFAULT_CEILING))
    try:
        value = int(raw)
    except ValueError:
        return DEFAULT_CEILING
    return value if 1 <= value <= 10_000 else DEFAULT_CEILING


def _state_dir() -> Path:
    override = os.environ.get("GRAPHIFY_CODEX_REMINDER_STATE_DIR")
    return Path(override).expanduser() if override else DEFAULT_STATE_DIR


def _inside_repository(raw_cwd: Any) -> bool:
    try:
        cwd = Path(str(raw_cwd or context.ROOT)).resolve()
        cwd.relative_to(context.ROOT.resolve())
    except (OSError, ValueError):
        return False
    return True


def _tool_name(payload: dict[str, Any]) -> str:
    return str(payload.get("tool_name") or "").strip().lower()


def _dedupe(values: Iterable[str]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        result.append(value)
    return result


def _commands(payload: dict[str, Any]) -> list[str]:
    """Extract shell commands from native and functions.exec hook payloads."""
    tool_input = payload.get("tool_input")
    candidates: list[str] = []
    parse_inputs: list[str] = []
    if isinstance(tool_input, dict):
        for key in ("command", "cmd"):
            value = tool_input.get(key)
            if isinstance(value, str):
                candidates.append(value)
        for key in ("input", "code"):
            value = tool_input.get(key)
            if isinstance(value, str):
                parse_inputs.append(value)
        try:
            parse_inputs.append(json.dumps(tool_input))
        except (TypeError, ValueError):
            pass
    elif isinstance(tool_input, str):
        parse_inputs.append(tool_input)

    for raw in parse_inputs:
        candidates.extend(context._exec_commands_from_tool_input(raw))

    name = _tool_name(payload)
    if not candidates and name in _SHELL_TOOL_NAMES and isinstance(tool_input, str):
        # Older native shell payloads can carry the command as a bare string.
        candidates.append(tool_input)
    return _dedupe(candidates)


def _has_code_context(commands: Iterable[str]) -> bool:
    for command in commands:
        for operation, invocation in context._helper_invocations(command):
            if operation not in {"query", "native"}:
                continue
            if not context._document_terms(invocation, root=context.ROOT):
                return True
        for invocation in context._direct_native_invocations(command):
            if not context._document_terms(invocation, root=context.ROOT):
                return True
    return False


def _command_code_browse(commands: Iterable[str]) -> bool:
    return any(
        context._command_browse_kinds(command, root=context.ROOT)[1]
        for command in commands
    )


def _direct_path(payload: dict[str, Any]) -> str | None:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return None
    for key in ("file_path", "path", "directory"):
        value = tool_input.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def _normalized_repo_path(raw_path: str) -> str | None:
    path = Path(raw_path).expanduser()
    try:
        resolved = path.resolve() if path.is_absolute() else (context.ROOT / path).resolve()
        return resolved.relative_to(context.ROOT.resolve()).as_posix()
    except (OSError, ValueError):
        return None


def _direct_code_browse(payload: dict[str, Any]) -> bool:
    name = _tool_name(payload)
    short_name = name.rsplit(".", 1)[-1]
    direct_namespace = "." not in name or name.startswith("functions.")
    raw_path = _direct_path(payload)
    if direct_namespace and short_name in _READ_TOOL_NAMES:
        if raw_path is None:
            return False
        normalized = _normalized_repo_path(raw_path)
        return bool(normalized and context._is_code_context_path(normalized))
    if not direct_namespace or short_name not in _SEARCH_TOOL_NAMES:
        return False
    if raw_path is None:
        # A project-scoped grep/glob without a path is still a raw codebase browse.
        return True
    normalized = _normalized_repo_path(raw_path)
    if normalized is None:
        return False
    if context._is_plan_spec_document(normalized):
        return False
    first = normalized.split("/", 1)[0]
    return first in context._CODE_BROWSE_ROOTS or normalized in {"", "."}


def _event_kind(payload: dict[str, Any]) -> tuple[bool, bool]:
    commands = _commands(payload)
    return (
        _has_code_context(commands),
        _command_code_browse(commands) or _direct_code_browse(payload),
    )


def _state_key(payload: dict[str, Any]) -> tuple[str, str] | None:
    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        transcript = payload.get("transcript_path")
        if not isinstance(transcript, str) or not transcript:
            return None
        session_id = f"transcript:{transcript}"
    session_sha256 = context._session_digest(session_id)
    agent_id = payload.get("agent_id")
    agent_sha256 = _digest(str(agent_id)) if agent_id else "root"
    return session_sha256, agent_sha256


def _default_state(session_sha256: str, agent_sha256: str) -> dict[str, Any]:
    return {
        "schema_version": STATE_SCHEMA_VERSION,
        "session_sha256": session_sha256,
        "agent_sha256": agent_sha256,
        "raw_since_context": 0,
        "context_calls": 0,
        "initial_reminded": False,
        "last_ceiling_reminder_raw": 0,
        "reminders": 0,
        "event_sequence": 0,
        "recent_tool_use_hashes": [],
    }


def _read_state(path: Path, session_sha256: str, agent_sha256: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return _default_state(session_sha256, agent_sha256)
    if not isinstance(value, dict) or value.get("schema_version") != STATE_SCHEMA_VERSION:
        return _default_state(session_sha256, agent_sha256)
    if value.get("session_sha256") != session_sha256 or value.get("agent_sha256") != agent_sha256:
        return _default_state(session_sha256, agent_sha256)
    return value


def _write_state(path: Path, state: dict[str, Any]) -> None:
    temporary = path.with_name(f".{path.name}.{os.getpid()}.{time.time_ns()}.tmp")
    try:
        temporary.write_text(
            json.dumps(state, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def _append_event(path: Path, event: dict[str, Any]) -> None:
    data = (json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n").encode()
    descriptor = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
    try:
        os.write(descriptor, data)
    finally:
        os.close(descriptor)


def _output(message: str) -> dict[str, Any]:
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": message,
        }
    }


def _initial_message() -> str:
    return (
        "Graphify advisory (non-blocking): raw app-code browsing started without "
        "a compact/native Graphify query. The current call was allowed. Before "
        "further code exploration, run `python3 graphify-arch/tdd_context.py "
        "query \"<exact symbol or filename>\" --profile general --budget 600`. "
        "Plan/spec and instruction-document reads are excluded from this counter."
    )


def _ceiling_message(raw_count: int, ceiling: int) -> str:
    return (
        f"Graphify advisory checkpoint (non-blocking): {raw_count} raw app-code "
        "browse calls occurred since the last compact/native Graphify query "
        f"(cadence target: {ceiling}). The current call was allowed. Before more "
        "exploratory code reads, run a focused compact query with exact symbols "
        "or filenames. If this branch is ending and only final targeted "
        "verification remains, finish it without querying merely to raise the "
        "Graphify count. Plan/spec reads are excluded."
    )


def process_hook(
    payload: dict[str, Any],
    *,
    state_dir: Path | None = None,
    ceiling: int | None = None,
    timestamp: str | None = None,
) -> dict[str, Any] | None:
    """Process one hook payload and return optional Codex additional context."""
    if payload.get("hook_event_name") not in {None, "PreToolUse"}:
        return None
    if not _inside_repository(payload.get("cwd")):
        return None
    context_seen, code_browse = _event_kind(payload)
    if not context_seen and not code_browse:
        return None
    identity = _state_key(payload)
    if identity is None:
        return None
    session_sha256, agent_sha256 = identity
    state_dir = state_dir or _state_dir()
    ceiling = ceiling or _ceiling()
    timestamp = timestamp or _utc_now()
    state_dir.mkdir(parents=True, exist_ok=True)
    stem = f"{session_sha256}-{agent_sha256}"
    state_path = state_dir / f"{stem}.json"
    lock_path = state_dir / f"{stem}.lock"
    ledger_path = state_dir / "events.jsonl"

    with lock_path.open("a+", encoding="utf-8") as lock_handle:
        if fcntl is not None:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        state = _read_state(state_path, session_sha256, agent_sha256)
        tool_use_id = str(payload.get("tool_use_id") or "")
        tool_use_hash = _digest(tool_use_id) if tool_use_id else ""
        recent = [str(value) for value in state.get("recent_tool_use_hashes", [])]
        if tool_use_hash and tool_use_hash in recent:
            return None
        if tool_use_hash:
            state["recent_tool_use_hashes"] = [*recent[-63:], tool_use_hash]

        events: list[dict[str, Any]] = []
        if context_seen:
            state["raw_since_context"] = 0
            state["context_calls"] = int(state.get("context_calls", 0)) + 1
            state["last_ceiling_reminder_raw"] = 0
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append(
                {
                    "event": "context",
                    "sequence": state["event_sequence"],
                    "raw_since_context": 0,
                }
            )

        reminder_kind: str | None = None
        reminder_message: str | None = None
        if code_browse:
            raw_count = int(state.get("raw_since_context", 0)) + 1
            state["raw_since_context"] = raw_count
            if not int(state.get("context_calls", 0)) and not bool(
                state.get("initial_reminded")
            ):
                reminder_kind = "initial"
                reminder_message = _initial_message()
                state["initial_reminded"] = True
            elif raw_count >= ceiling and (
                raw_count - int(state.get("last_ceiling_reminder_raw", 0)) >= ceiling
            ):
                reminder_kind = "ceiling"
                reminder_message = _ceiling_message(raw_count, ceiling)
                state["last_ceiling_reminder_raw"] = raw_count
            if reminder_kind:
                state["reminders"] = int(state.get("reminders", 0)) + 1
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append(
                {
                    "event": "code_browse",
                    "sequence": state["event_sequence"],
                    "raw_since_context": raw_count,
                    "reminder": reminder_kind,
                }
            )

        state["updated_at"] = timestamp
        _write_state(state_path, state)
        for event in events:
            _append_event(
                ledger_path,
                {
                    "schema_version": EVENT_SCHEMA_VERSION,
                    "ts": timestamp,
                    "session_sha256": session_sha256,
                    "agent_sha256": agent_sha256,
                    **event,
                },
            )
        if fcntl is not None:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)

    return _output(reminder_message) if reminder_message else None


def main() -> int:
    if not _enabled():
        return 0
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            return 0
        result = process_hook(payload)
        if result is not None:
            print(json.dumps(result, separators=(",", ":")))
    except Exception as exc:  # The advisory must never interrupt the requested tool.
        if os.environ.get("GRAPHIFY_CODEX_REMINDER_DEBUG") == "1":
            print(f"graphify reminder ignored error: {exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
