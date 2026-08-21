#!/usr/bin/env python3
"""Fail-open Codex hook for recall-before-broad-document-search adoption.

The hook never blocks a tool call and never records commands, prompts, paths,
or raw session ids. A direct full read of one named plan/spec is deliberately
outside its scope; only broad searches over configured document roots count.
"""

from __future__ import annotations

import ast
import datetime as dt
import hashlib
import json
import math
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Iterable

try:
    import fcntl
except ImportError:  # pragma: no cover
    fcntl = None  # type: ignore[assignment]

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import memory  # noqa: E402


STATE_SCHEMA_VERSION = 1
EVENT_SCHEMA_VERSION = 1
DEFAULT_CEILING = 4
FALSE_VALUES = {"0", "false", "no", "off"}
SHELL_TOOLS = {"bash", "exec", "exec_command", "functions.exec", "shell", "shell_command"}
SEARCH_TOOLS = {"glob", "grep", "search", "search_files"}
JS_COMMAND = re.compile(
    r"\b(?:cmd|command)\s*:\s*(?P<literal>\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')",
    re.S,
)
MEMORY_QUERY = re.compile(
    r"(?:^|[\s;&|])(?:python3?(?:\.\d+)?[ \t]+)?"
    r"(?:[^\s;&|]*/)?codex-memory/memory\.py[ \t]+query\b",
    re.I,
)
SEARCH_COMMAND = re.compile(r"(?:^|[\s;&|])(rg|grep|find|fd)[ \t]", re.I)
DOCUMENT_ROOT = re.compile(
    r"(?:Test-Flight-Improv|Network-Arch|docs(?:/|\b)|UI-[A-Za-z0-9_-]*|UI-\*)",
    re.I,
)
MARKDOWN_SWEEP = re.compile(
    r"(?:-g|--glob|-name)[ \t]+['\"]?[^\s'\"]*\*[^\s'\"]*\.md|"
    r"(?:\*\*/)?\*[^\s'\"]*\.md",
    re.I,
)
CAT_DOCUMENT = re.compile(
    r"(?:^|[;&|]\s*)cat(?:[ \t]+--)?[ \t]+(?P<path>[^\s;&|]+\.md)\b",
    re.I,
)
SED_DOCUMENT = re.compile(
    r"(?:^|[;&|]\s*)sed[ \t]+-n[ \t]+['\"]?"
    r"(?P<start>\d+),(?P<end>\d+)p['\"]?[ \t]+(?P<path>[^\s;&|]+\.md)\b",
    re.I,
)
HEAD_DOCUMENT = re.compile(
    r"(?:^|[;&|]\s*)head[ \t]+(?:-n[ \t]+)?(?P<end>\d+)[ \t]+"
    r"(?P<path>[^\s;&|]+\.md)\b",
    re.I,
)


def _enabled() -> bool:
    return os.environ.get("CODEX_MEMORY_REMINDER", "1").strip().lower() not in FALSE_VALUES


def _ceiling() -> int:
    try:
        value = int(os.environ.get("CODEX_MEMORY_REMINDER_CEILING", DEFAULT_CEILING))
    except ValueError:
        return DEFAULT_CEILING
    return value if 1 <= value <= 1000 else DEFAULT_CEILING


def _utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8", errors="replace")).hexdigest()[:16]


def _tool_name(payload: dict[str, Any]) -> str:
    return str(payload.get("tool_name") or "").strip().lower()


def _dedupe(values: Iterable[str]) -> list[str]:
    result: list[str] = []
    for value in values:
        if value and value not in result:
            result.append(value)
    return result


def _commands(payload: dict[str, Any]) -> list[str]:
    tool_input = payload.get("tool_input")
    values: list[str] = []
    raw_values: list[str] = []
    if isinstance(tool_input, dict):
        for key in ("cmd", "command"):
            value = tool_input.get(key)
            if isinstance(value, str):
                values.append(value)
        for key in ("code", "input"):
            value = tool_input.get(key)
            if isinstance(value, str):
                raw_values.append(value)
    elif isinstance(tool_input, str):
        raw_values.append(tool_input)
    for raw in raw_values:
        values.append(raw)
        for match in JS_COMMAND.finditer(raw):
            try:
                decoded = ast.literal_eval(match.group("literal"))
            except (SyntaxError, ValueError):
                continue
            if isinstance(decoded, str):
                values.append(decoded)
    return _dedupe(values)


def _has_context(commands: Iterable[str]) -> bool:
    return any(MEMORY_QUERY.search(command) for command in commands)


def _configured_markers(runtime: memory.Runtime) -> list[str]:
    markers: list[str] = []
    for source in runtime.config.get("sources", []):
        if source.get("enabled", True) is False:
            continue
        root = str(source.get("root", ".")).strip("./")
        if root:
            markers.append(root.lower())
        for pattern in source.get("include", []):
            prefix = re.split(r"[*?[{]", str(pattern), maxsplit=1)[0].strip("./")
            if prefix:
                markers.append(prefix.lower())
    return _dedupe(markers)


def _broad_command_search(commands: Iterable[str], runtime: memory.Runtime) -> bool:
    markers = _configured_markers(runtime)
    for command in commands:
        if MEMORY_QUERY.search(command) or not SEARCH_COMMAND.search(command):
            continue
        lowered = command.lower()
        if (
            DOCUMENT_ROOT.search(command)
            or MARKDOWN_SWEEP.search(command)
            or any(marker in lowered for marker in markers)
        ):
            return True
    return False


def _direct_path(payload: dict[str, Any]) -> str | None:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return None
    for key in ("path", "directory", "file_path"):
        value = tool_input.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def _direct_broad_search(payload: dict[str, Any], runtime: memory.Runtime) -> bool:
    name = _tool_name(payload).rsplit(".", 1)[-1]
    if name not in SEARCH_TOOLS:
        return False
    path = _direct_path(payload)
    if path is None:
        tool_input = payload.get("tool_input")
        raw = json.dumps(tool_input, sort_keys=True) if isinstance(tool_input, dict) else str(tool_input)
        lowered = raw.lower()
        return bool(
            DOCUMENT_ROOT.search(raw)
            or MARKDOWN_SWEEP.search(raw)
            or any(marker in lowered for marker in _configured_markers(runtime))
        )
    lowered = path.lower()
    return bool(
        DOCUMENT_ROOT.search(path)
        or MARKDOWN_SWEEP.search(path)
        or any(marker in lowered for marker in _configured_markers(runtime))
    )


def _configured_document_paths(runtime: memory.Runtime) -> set[Path]:
    try:
        files, _counts = memory.collect_sources(runtime)
    except (OSError, ValueError):
        return set()
    return {item.path.resolve() for item in files}


def _resolve_document(raw: str, runtime: memory.Runtime, configured: set[Path]) -> Path | None:
    value = raw.strip("`'\"(),")
    path = Path(value).expanduser()
    try:
        resolved = path.resolve() if path.is_absolute() else (runtime.root / path).resolve()
        resolved.relative_to(runtime.root.resolve())
    except (OSError, ValueError):
        return None
    return resolved if resolved in configured else None


def _read_measurement(path: Path, start: int, end: int | None) -> tuple[bool, int]:
    try:
        data = path.read_bytes()
    except OSError:
        return False, 0
    total_lines = max(1, data.count(b"\n") + (0 if data.endswith(b"\n") else 1))
    bounded_end = total_lines if end is None else min(total_lines, max(start, end))
    requested_lines = max(0, bounded_end - max(1, start) + 1)
    estimated_bytes = int(math.ceil(len(data) * requested_lines / float(total_lines)))
    return start <= 1 and (end is None or end >= total_lines), int(math.ceil(estimated_bytes / 4.0))


def _document_reads(
    payload: dict[str, Any],
    commands: Iterable[str],
    runtime: memory.Runtime,
) -> list[tuple[bool, int]]:
    candidates: dict[Path, tuple[int, int | None]] = {}
    configured: set[Path] | None = None

    def add(raw_path: str, start: int, end: int | None) -> None:
        nonlocal configured
        if configured is None:
            configured = _configured_document_paths(runtime)
        path = _resolve_document(raw_path, runtime, configured)
        if path is not None:
            candidates[path] = (start, end)

    for command in commands:
        for match in CAT_DOCUMENT.finditer(command):
            add(match.group("path"), 1, None)
        for match in SED_DOCUMENT.finditer(command):
            add(match.group("path"), int(match.group("start")), int(match.group("end")))
        for match in HEAD_DOCUMENT.finditer(command):
            add(match.group("path"), 1, int(match.group("end")))
    name = _tool_name(payload).rsplit(".", 1)[-1]
    if name in {"read", "read_file"}:
        raw_path = _direct_path(payload)
        if raw_path:
            add(raw_path, 1, None)
    return [_read_measurement(path, *line_range) for path, line_range in sorted(candidates.items())]


def _inside_repo(payload: dict[str, Any], root: Path) -> bool:
    try:
        cwd = Path(str(payload.get("cwd") or root)).resolve()
        cwd.relative_to(root.resolve())
        return True
    except (OSError, ValueError):
        return False


def _identity(payload: dict[str, Any]) -> tuple[str, str] | None:
    session = payload.get("session_id")
    if not isinstance(session, str) or not session:
        transcript = payload.get("transcript_path")
        if not isinstance(transcript, str) or not transcript:
            return None
        session = "transcript:" + transcript
    agent = payload.get("agent_id")
    return memory.session_digest(session), _digest(str(agent)) if agent else "root"


def _default_state(session: str, agent: str) -> dict[str, Any]:
    return {
        "schema_version": STATE_SCHEMA_VERSION,
        "session_sha256": session,
        "agent_sha256": agent,
        "context_calls": 0,
        "broad_since_context": 0,
        "initial_reminded": False,
        "last_ceiling_reminder": 0,
        "reminders": 0,
        "event_sequence": 0,
        "recent_tool_use_hashes": [],
    }


def _read_state(path: Path, session: str, agent: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return _default_state(session, agent)
    if (
        not isinstance(value, dict)
        or value.get("schema_version") != STATE_SCHEMA_VERSION
        or value.get("session_sha256") != session
        or value.get("agent_sha256") != agent
    ):
        return _default_state(session, agent)
    return value


def _write_state(path: Path, state: dict[str, Any]) -> None:
    temporary = path.with_name(".{}.{}.{}.tmp".format(path.name, os.getpid(), time.time_ns()))
    try:
        temporary.write_text(memory._canonical_json(state) + "\n", encoding="utf-8")
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def _output(message: str) -> dict[str, Any]:
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": message,
        }
    }


def _initial_message() -> str:
    return (
        "Codex-memory advisory (non-blocking): a broad plan/spec/document search "
        "started without compact document recall. The current call was allowed. "
        "Before another corpus sweep, run `python3 codex-memory/memory.py query "
        "\"<focused status, decision, rationale, or spec question>\"`. A direct "
        "complete read of one named plan/spec remains allowed; code relationships "
        "belong in Graphify."
    )


def _ceiling_message(count: int, ceiling: int) -> str:
    return (
        "Codex-memory advisory checkpoint (non-blocking): {} broad document "
        "searches occurred since the last recall query (cadence target: {}). "
        "The current call was allowed. Query the Codex document graph with one "
        "focused question before continuing a new corpus-wide branch; direct "
        "reads of already-selected documents remain appropriate."
    ).format(count, ceiling)


def process_hook(
    payload: dict[str, Any],
    *,
    runtime: memory.Runtime | None = None,
    state_dir: Path | None = None,
    ceiling: int | None = None,
    timestamp: str | None = None,
) -> dict[str, Any] | None:
    if payload.get("hook_event_name") not in {None, "PreToolUse"}:
        return None
    runtime = runtime or memory.load_runtime()
    if not _inside_repo(payload, runtime.root):
        return None
    commands = _commands(payload)
    context_seen = _has_context(commands)
    document_browse = _broad_command_search(commands, runtime) or _direct_broad_search(
        payload, runtime
    )
    document_reads = _document_reads(payload, commands, runtime)
    if not context_seen and not document_browse and not document_reads:
        return None
    identity = _identity(payload)
    if identity is None:
        return None
    session, agent = identity
    state_dir = state_dir or runtime.state_dir / "hook-state"
    ceiling = ceiling or _ceiling()
    timestamp = timestamp or _utc_now()
    state_dir.mkdir(parents=True, exist_ok=True)
    stem = "{}-{}".format(session, agent)
    state_path = state_dir / (stem + ".json")
    lock_path = state_dir / (stem + ".lock")
    with lock_path.open("a+", encoding="utf-8") as lock_handle:
        if fcntl is not None:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        state = _read_state(state_path, session, agent)
        tool_id = str(payload.get("tool_use_id") or "")
        tool_hash = _digest(tool_id) if tool_id else ""
        recent = [str(value) for value in state.get("recent_tool_use_hashes", [])]
        if tool_hash and tool_hash in recent:
            return None
        if tool_hash:
            state["recent_tool_use_hashes"] = [*recent[-63:], tool_hash]
        events: list[dict[str, Any]] = []
        if context_seen:
            state["context_calls"] = int(state.get("context_calls", 0)) + 1
            state["broad_since_context"] = 0
            state["last_ceiling_reminder"] = 0
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append({"event": "context", "sequence": state["event_sequence"]})
        if document_reads:
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append(
                {
                    "event": "document_read",
                    "sequence": state["event_sequence"],
                    "documents": len(document_reads),
                    "whole_documents": sum(whole for whole, _tokens in document_reads),
                    "estimated_tokens": sum(tokens for _whole, tokens in document_reads),
                }
            )
        reminder: str | None = None
        reminder_kind: str | None = None
        if document_browse:
            count = int(state.get("broad_since_context", 0)) + 1
            state["broad_since_context"] = count
            grounded = int(state.get("context_calls", 0)) > 0
            if not grounded and not bool(state.get("initial_reminded")):
                reminder = _initial_message()
                reminder_kind = "initial"
                state["initial_reminded"] = True
            elif grounded and count >= ceiling and (
                count - int(state.get("last_ceiling_reminder", 0)) >= ceiling
            ):
                reminder = _ceiling_message(count, ceiling)
                reminder_kind = "ceiling"
                state["last_ceiling_reminder"] = count
            if reminder:
                state["reminders"] = int(state.get("reminders", 0)) + 1
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append(
                {
                    "event": "document_browse",
                    "sequence": state["event_sequence"],
                    "grounded": grounded,
                    "broad_since_context": count,
                    "reminder": reminder_kind,
                }
            )
        state["updated_at"] = timestamp
        _write_state(state_path, state)
        for event in events:
            memory._append_jsonl(
                runtime.hook_events_path,
                {
                    "schema_version": EVENT_SCHEMA_VERSION,
                    "ts": timestamp,
                    "codex_session_sha256": session,
                    "agent_sha256": agent,
                    **event,
                },
            )
        if fcntl is not None:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
    return _output(reminder) if reminder else None


def main() -> int:
    if not _enabled():
        return 0
    try:
        payload = json.load(sys.stdin)
        if isinstance(payload, dict):
            result = process_hook(payload)
            if result is not None:
                print(json.dumps(result, separators=(",", ":")))
    except Exception as exc:  # The reminder must never interrupt a user tool call.
        if os.environ.get("CODEX_MEMORY_REMINDER_DEBUG") == "1":
            print("codex-memory reminder ignored error: {}".format(exc), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
