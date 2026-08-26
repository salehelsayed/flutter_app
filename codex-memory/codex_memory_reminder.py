#!/usr/bin/env python3
"""Recall, output sizing, and same-provenance guards for document reads.

The first confirmed pass over one named plan/spec remains outside the guard.
Later broad rereads of that unchanged document may be denied only after exact
Codex-memory recall returns same-document provenance. Broad corpus searches are
automatically grounded. Telemetry never records commands, prompts, paths, raw
questions, or raw session ids.
"""

from __future__ import annotations

import ast
import datetime as dt
import hashlib
import json
import math
import os
import re
import shlex
import sqlite3
import sys
import time
from dataclasses import dataclass, replace
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


STATE_SCHEMA_VERSION = 3
SHARED_STATE_SCHEMA_VERSION = 3
EVENT_SCHEMA_VERSION = 1
ADOPTION_POLICY_VERSION = 4
DEFAULT_CEILING = 4
DEFAULT_TARGETED_WINDOW_LINES = 120
DEFAULT_REPEAT_GUARD_BUDGET = 300
DEFAULT_SECONDARY_BUDGET = 300
DEFAULT_SECONDARY_MIN_RAW_TOKENS = 300
DEFAULT_PRIMARY_IDLE_SECONDS = 86_400
DEFAULT_OUTER_OUTPUT_CAP = 10_000
OUTPUT_CAP_SAFETY_RATIO = 0.9
PRIMARY_OUTPUT_DENIAL_PREFIX = "Codex-memory primary output-safety gate:"
FALSE_VALUES = {"0", "false", "no", "off"}
TRUE_VALUES = {"1", "true", "yes", "on"}
SHELL_TOOLS = {"bash", "exec", "exec_command", "functions.exec", "shell", "shell_command"}
SEARCH_TOOLS = {"glob", "grep", "search", "search_files"}
JS_COMMAND = re.compile(
    r"(?<![A-Za-z0-9_])[\"']?(?:cmd|command)[\"']?\s*:\s*"
    r"(?P<literal>\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')",
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
    r"(?P<script>\d+,\d+p(?:;\d+,\d+p)*)['\"]?[ \t]+"
    r"(?P<path>[^\s;&|]+\.md)\b",
    re.I,
)
NL_SED_DOCUMENT = re.compile(
    r"(?:^|[;&|]\s*)nl[ \t]+(?:-[A-Za-z]+[ \t]+)*(?:--[ \t]+)?"
    r"(?P<path>[^\s;&|]+\.md)[ \t]*\|[ \t]*sed[ \t]+-n[ \t]+"
    r"(?P<quote>['\"])(?P<script>\d+,\d+p(?:;\d+,\d+p)*)(?P=quote)",
    re.I,
)
SED_RANGE = re.compile(r"(?P<start>\d+),(?P<end>\d+)p", re.I)
HEAD_DOCUMENT = re.compile(
    r"(?:^|[;&|]\s*)head[ \t]+(?:-n[ \t]+)?(?P<end>\d+)[ \t]+"
    r"(?P<path>[^\s;&|]+\.md)\b",
    re.I,
)
REPEAT_GUARD_BYPASS = re.compile(
    r"^\s*CODEX_MEMORY_REPEAT_GUARD_BYPASS\s*=\s*"
    r"(?:1|true|yes|on)\s+",
    re.I,
)
SECONDARY_BYPASS = re.compile(
    r"^\s*CODEX_MEMORY_SECONDARY_BYPASS\s*=\s*"
    r"(?:1|true|yes|on)\s+",
    re.I,
)
PRIMARY_READ_MARKER = re.compile(
    r"^\s*CODEX_MEMORY_PRIMARY_READ\s*=\s*"
    r"(?:1|true|yes|on)\s+",
    re.I,
)
PRIMARY_OUTPUT_BYPASS = re.compile(
    r"^\s*CODEX_MEMORY_PRIMARY_OUTPUT_BYPASS\s*=\s*"
    r"(?:1|true|yes|on)\s+",
    re.I,
)
EXEC_PRAGMA = re.compile(r"^\s*//\s*@exec:\s*(\{[^\r\n]*\})", re.I)


@dataclass(frozen=True)
class DocumentRead:
    path: Path
    relative: str
    document_sha256: str
    version_sha256: str
    start_line: int
    end_line: int
    ranges: tuple[tuple[int, int], ...]
    total_lines: int
    requested_lines: int
    whole: bool
    estimated_tokens: int
    confirmed: bool
    output_cap_tokens: int
    line_numbered: bool = False


@dataclass(frozen=True)
class DocumentReadBatch:
    reads: tuple[DocumentRead, ...]
    mixed: bool = False
    bypass: bool = False
    secondary_bypass: bool = False
    primary_marker: bool = False
    primary_output_bypass: bool = False


def _enabled() -> bool:
    return os.environ.get("CODEX_MEMORY_REMINDER", "1").strip().lower() not in FALSE_VALUES


def _observe_only() -> bool:
    raw = os.environ.get("CODEX_MEMORY_OBSERVE_ONLY")
    return raw is not None and raw.strip().lower() not in FALSE_VALUES


def _auto_recall_enabled() -> bool:
    return os.environ.get("CODEX_MEMORY_AUTO_RECALL", "1").strip().lower() not in FALSE_VALUES


def _repeat_guard_enabled() -> bool:
    return os.environ.get("CODEX_MEMORY_REPEAT_GUARD", "1").strip().lower() not in FALSE_VALUES


def _adoption(runtime: memory.Runtime) -> dict[str, Any]:
    value = runtime.config.get("adoption", {})
    return value if isinstance(value, dict) else {}


def _secondary_mode(runtime: memory.Runtime) -> str:
    configured = str(_adoption(runtime).get("secondary_mode", "inject"))
    value = os.environ.get("CODEX_MEMORY_SECONDARY_MODE", configured).strip().lower()
    return value if value in {"off", "shadow", "inject", "enforce"} else "inject"


def _primary_idle_seconds(runtime: memory.Runtime) -> int:
    configured = _adoption(runtime).get(
        "primary_idle_seconds", DEFAULT_PRIMARY_IDLE_SECONDS
    )
    try:
        value = int(os.environ.get("CODEX_MEMORY_PRIMARY_IDLE_SECONDS", configured))
    except (TypeError, ValueError):
        return DEFAULT_PRIMARY_IDLE_SECONDS
    return value if 0 <= value <= 31_536_000 else DEFAULT_PRIMARY_IDLE_SECONDS


def _secondary_budget(runtime: memory.Runtime) -> int:
    configured = _adoption(runtime).get(
        "secondary_budget",
        min(
            DEFAULT_SECONDARY_BUDGET,
            int(runtime.config["retrieval"]["default_budget"]),
        ),
    )
    try:
        value = int(os.environ.get("CODEX_MEMORY_SECONDARY_BUDGET", configured))
    except (TypeError, ValueError):
        value = DEFAULT_SECONDARY_BUDGET
    hard_cap = int(runtime.config["retrieval"].get("hard_cap", value))
    return min(max(80, value), hard_cap)


def _secondary_min_raw_tokens(runtime: memory.Runtime) -> int:
    configured = _adoption(runtime).get(
        "secondary_min_raw_tokens", DEFAULT_SECONDARY_MIN_RAW_TOKENS
    )
    try:
        value = int(
            os.environ.get("CODEX_MEMORY_SECONDARY_MIN_RAW_TOKENS", configured)
        )
    except (TypeError, ValueError):
        return DEFAULT_SECONDARY_MIN_RAW_TOKENS
    return value if 0 <= value <= 1_000_000 else DEFAULT_SECONDARY_MIN_RAW_TOKENS


def _focused_recall(result: memory.RecallResult) -> bool:
    return bool(
        not result.truncated and result.confidence in {"exact", "focused"}
    )


def _targeted_window_lines() -> int:
    try:
        value = int(
            os.environ.get(
                "CODEX_MEMORY_TARGETED_READ_LINES", DEFAULT_TARGETED_WINDOW_LINES
            )
        )
    except ValueError:
        return DEFAULT_TARGETED_WINDOW_LINES
    return value if 1 <= value <= 10_000 else DEFAULT_TARGETED_WINDOW_LINES


def _repeat_guard_budget(runtime: memory.Runtime) -> int:
    default = min(
        DEFAULT_REPEAT_GUARD_BUDGET,
        int(runtime.config["retrieval"]["default_budget"]),
    )
    try:
        value = int(os.environ.get("CODEX_MEMORY_REPEAT_GUARD_BUDGET", default))
    except ValueError:
        return default
    hard_cap = int(runtime.config["retrieval"].get("hard_cap", value))
    return min(max(80, value), hard_cap)


def _outer_output_cap(payload: dict[str, Any]) -> int:
    """Return the visible outer tool cap, not a nested exec_command cap."""
    tool_input = payload.get("tool_input")
    if isinstance(tool_input, dict):
        value = tool_input.get("max_output_tokens")
        if isinstance(value, int) and value > 0:
            return value
    if _tool_name(payload) == "functions.exec" and isinstance(tool_input, str):
        first_line = tool_input.splitlines()[0] if tool_input.splitlines() else ""
        match = EXEC_PRAGMA.match(first_line)
        if match:
            try:
                value = json.loads(match.group(1)).get("max_output_tokens")
            except (AttributeError, json.JSONDecodeError):
                value = None
            if isinstance(value, int) and value > 0:
                return value
    return DEFAULT_OUTER_OUTPUT_CAP


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


def _text_tokens(value: str | None) -> int:
    if not value:
        return 0
    return int(math.ceil(len(value.encode("utf-8", errors="replace")) / 4.0))


def _tool_name(payload: dict[str, Any]) -> str:
    return str(payload.get("tool_name") or "").strip().lower()


def _tool_family(payload: dict[str, Any]) -> str:
    name = _tool_name(payload)
    leaf = name.rsplit(".", 1)[-1]
    if name in SHELL_TOOLS or leaf in {
        "bash",
        "exec",
        "exec_command",
        "shell",
        "shell_command",
    }:
        return "shell"
    return leaf


def _tool_identity_fields(
    payload: dict[str, Any], commands: Iterable[str]
) -> dict[str, Any]:
    """Return privacy-safe identities that can be joined to rollout cells."""
    name = _tool_family(payload)
    command_values = [command.strip() for command in commands if command.strip()]
    tool_input = payload.get("tool_input")
    if name == "shell" and command_values:
        # Codex emits exec_command/cmd in Pre and may emit Bash/command in Post.
        # Treat those aliases as the same semantic shell input for fallback
        # correlation when the official tool_use_id is unavailable.
        serialized = memory._canonical_json({"commands": command_values})
    elif isinstance(tool_input, str):
        try:
            decoded = json.loads(tool_input)
        except json.JSONDecodeError:
            serialized = tool_input.strip()
        else:
            serialized = memory._canonical_json(decoded)
    else:
        try:
            serialized = memory._canonical_json(tool_input)
        except (TypeError, ValueError):
            serialized = str(tool_input)
    fields: dict[str, Any] = {
        "tool_input_sha256": _digest(name + "\0" + serialized),
    }
    command_hashes = _dedupe(_digest(command) for command in command_values)
    if command_hashes:
        fields["command_sha256s"] = command_hashes
    return fields


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


def _clean_query_hint(value: str) -> str | None:
    cleaned = re.sub(r"[^A-Za-z0-9_.:@+ -]+", " ", value).strip()
    if not cleaned or len(cleaned) < 2:
        return None
    return " ".join(cleaned.split())[:120]


def _query_hint(payload: dict[str, Any], commands: Iterable[str]) -> str | None:
    hints: list[str] = []

    def add(value: str) -> None:
        hint = _clean_query_hint(value)
        if hint and hint.lower() not in {item.lower() for item in hints}:
            hints.append(hint)

    tool_input = payload.get("tool_input")
    if isinstance(tool_input, dict):
        for key in ("query", "pattern", "search_term", "searchTerm"):
            value = tool_input.get(key)
            if isinstance(value, str):
                add(value)
        direct_path = _direct_path(payload)
        if direct_path:
            add(direct_path)
        if hints:
            return " ".join(hints)[:120]
    for command in commands:
        try:
            tokens = shlex.split(command)
        except ValueError:
            continue
        search_index = next(
            (
                index
                for index, token in enumerate(tokens)
                if Path(token).name.lower() in {"rg", "grep", "find", "fd"}
            ),
            None,
        )
        if search_index is None:
            continue
        for token in tokens[search_index + 1 :]:
            if (
                token.startswith("-")
                or "*" in token
                or token in {";", "&&", "||", "|"}
            ):
                continue
            add(token)
            if len(hints) >= 4:
                break
        if hints:
            break
    return " ".join(hints)[:120] if hints else None


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


def _single_document_search(command: str, runtime: memory.Runtime) -> bool:
    if not SEARCH_COMMAND.search(command) or MARKDOWN_SWEEP.search(command):
        return False
    try:
        tokens = shlex.split(command)
    except ValueError:
        return False
    configured: set[Path] | None = None
    matches = 0
    for token in tokens:
        if token.startswith("-") or "*" in token or not token.lower().endswith(".md"):
            continue
        if configured is None:
            configured = _configured_document_paths(runtime)
        if _resolve_document(token, runtime, configured) is not None:
            matches += 1
    return matches == 1


def _configured_search_documents(
    commands: Iterable[str], runtime: memory.Runtime
) -> set[Path]:
    configured: set[Path] | None = None
    result: set[Path] = set()
    for command in commands:
        if not SEARCH_COMMAND.search(command) or MARKDOWN_SWEEP.search(command):
            continue
        try:
            tokens = shlex.split(command)
        except ValueError:
            continue
        for token in tokens:
            if token.startswith("-") or "*" in token or not token.lower().endswith(".md"):
                continue
            if configured is None:
                configured = _configured_document_paths(runtime)
            path = _resolve_document(token, runtime, configured)
            if path is not None:
                result.add(path)
    return result


def _broad_command_search(commands: Iterable[str], runtime: memory.Runtime) -> bool:
    markers = _configured_markers(runtime)
    for command in commands:
        if (
            MEMORY_QUERY.search(command)
            or not SEARCH_COMMAND.search(command)
            or _single_document_search(command, runtime)
        ):
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
    configured = _configured_document_paths(runtime)
    if _resolve_document(path, runtime, configured) is not None:
        return False
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


def _read_measurement(
    path: Path,
    requested_ranges: Iterable[tuple[int, int | None]],
    *,
    runtime: memory.Runtime,
    output_cap_tokens: int,
    line_numbered: bool = False,
) -> DocumentRead | None:
    try:
        data = path.read_bytes()
    except OSError:
        return None
    lines = data.splitlines(keepends=True) or [b""]
    total_lines = len(lines)
    bounded: list[tuple[int, int]] = []
    for start, end in requested_ranges:
        requested_start = max(1, start)
        if requested_start > total_lines or (
            end is not None and end < requested_start
        ):
            continue
        bounded.append(
            (
                requested_start,
                total_lines if end is None else min(total_lines, end),
            )
        )
    merged = _merge_ranges(bounded)
    if not merged:
        return None
    requested_lines = _covered_lines(merged)
    estimated_bytes = sum(
        sum(len(line) for line in lines[start - 1 : end])
        for start, end in merged
    )
    if line_numbered:
        estimated_bytes += sum(
            max(6, len(str(line_number))) + 1
            for start, end in merged
            for line_number in range(start, end + 1)
        )
    relative = path.resolve().relative_to(runtime.root.resolve()).as_posix()
    estimated_tokens = int(math.ceil(estimated_bytes / 4.0))
    return DocumentRead(
        path=path,
        relative=relative,
        document_sha256=_digest(relative),
        version_sha256=hashlib.sha256(data).hexdigest()[:16],
        start_line=merged[0][0],
        end_line=merged[-1][1],
        ranges=tuple(merged),
        total_lines=total_lines,
        requested_lines=requested_lines,
        whole=requested_lines >= total_lines,
        estimated_tokens=estimated_tokens,
        confirmed=estimated_tokens
        <= int(output_cap_tokens * OUTPUT_CAP_SAFETY_RATIO),
        output_cap_tokens=output_cap_tokens,
        line_numbered=line_numbered,
    )


def _is_javascript_wrapper(command: str) -> bool:
    return bool(JS_COMMAND.search(command)) and bool(
        re.search(r"\b(?:await\s+)?tools\.|\b(?:const|let|var)\s+", command)
    )


def _standalone_document_read(command: str) -> bool:
    stripped = command.strip()
    changed = True
    while changed:
        changed = False
        for pattern in (
            REPEAT_GUARD_BYPASS,
            SECONDARY_BYPASS,
            PRIMARY_READ_MARKER,
            PRIMARY_OUTPUT_BYPASS,
        ):
            updated = pattern.sub("", stripped, count=1)
            if updated != stripped:
                stripped = updated.strip()
                changed = True
    patterns = (
        re.compile(r"cat(?:[ \t]+--)?[ \t]+[^\s;&|]+\.md", re.I),
        re.compile(
            r"sed[ \t]+-n[ \t]+['\"]?\d+,\d+p(?:;\d+,\d+p)*['\"]?[ \t]+"
            r"[^\s;&|]+\.md",
            re.I,
        ),
        re.compile(
            r"head[ \t]+(?:-n[ \t]+)?\d+[ \t]+[^\s;&|]+\.md",
            re.I,
        ),
        re.compile(
            r"nl[ \t]+(?:-[A-Za-z]+[ \t]+)*(?:--[ \t]+)?[^\s;&|]+\.md"
            r"[ \t]*\|[ \t]*sed[ \t]+-n[ \t]+"
            r"['\"]\d+,\d+p(?:;\d+,\d+p)*['\"]",
            re.I,
        ),
    )
    return any(pattern.fullmatch(stripped) for pattern in patterns)


def _payload_repeat_guard_bypass(payload: dict[str, Any]) -> bool:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return False
    for key in (
        "codex_memory_repeat_guard_bypass",
        "memory_repeat_guard_bypass",
    ):
        value = tool_input.get(key)
        if value is True or (isinstance(value, str) and value.lower() in TRUE_VALUES):
            return True
    return False


def _payload_flag(payload: dict[str, Any], *keys: str) -> bool:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return False
    for key in keys:
        value = tool_input.get(key)
        if value is True or (isinstance(value, str) and value.lower() in TRUE_VALUES):
            return True
    return False


def _sed_ranges(script: str) -> list[tuple[int, int | None]]:
    return [
        (int(match.group("start")), int(match.group("end")))
        for match in SED_RANGE.finditer(script)
    ]


def _document_reads(
    payload: dict[str, Any],
    commands: Iterable[str],
    runtime: memory.Runtime,
) -> DocumentReadBatch:
    candidates: dict[Path, list[tuple[int, int | None]]] = {}
    line_numbered_paths: set[Path] = set()
    configured: set[Path] | None = None
    effective_commands = [
        command for command in commands if not _is_javascript_wrapper(command)
    ]
    read_commands = 0
    bypass = _payload_repeat_guard_bypass(payload)
    secondary_bypass = _payload_flag(
        payload,
        "codex_memory_secondary_bypass",
        "memory_secondary_bypass",
    )
    primary_marker = _payload_flag(
        payload,
        "codex_memory_primary_read",
        "memory_primary_read",
    )
    primary_output_bypass = _payload_flag(
        payload,
        "codex_memory_primary_output_bypass",
        "memory_primary_output_bypass",
    )

    def add(
        raw_path: str,
        start: int,
        end: int | None,
        *,
        line_numbered: bool = False,
    ) -> None:
        nonlocal configured
        if configured is None:
            configured = _configured_document_paths(runtime)
        path = _resolve_document(raw_path, runtime, configured)
        if path is not None:
            candidates.setdefault(path, []).append((start, end))
            if line_numbered:
                line_numbered_paths.add(path)

    for command in effective_commands:
        normalized = command
        changed = True
        while changed:
            changed = False
            for pattern, field in (
                (REPEAT_GUARD_BYPASS, "repeat"),
                (SECONDARY_BYPASS, "secondary"),
                (PRIMARY_READ_MARKER, "primary"),
                (PRIMARY_OUTPUT_BYPASS, "primary_output"),
            ):
                updated = pattern.sub("", normalized, count=1)
                if updated == normalized:
                    continue
                normalized = updated
                changed = True
                if field == "repeat":
                    bypass = True
                elif field == "secondary":
                    secondary_bypass = True
                elif field == "primary":
                    primary_marker = True
                else:
                    primary_output_bypass = True
        found = False
        for match in NL_SED_DOCUMENT.finditer(normalized):
            for start, end in _sed_ranges(match.group("script")):
                add(
                    match.group("path"),
                    start,
                    end,
                    line_numbered=True,
                )
            found = True
        for match in CAT_DOCUMENT.finditer(normalized):
            add(match.group("path"), 1, None)
            found = True
        for match in SED_DOCUMENT.finditer(normalized):
            for start, end in _sed_ranges(match.group("script")):
                add(match.group("path"), start, end)
            found = True
        for match in HEAD_DOCUMENT.finditer(normalized):
            add(match.group("path"), 1, int(match.group("end")))
            found = True
        if found:
            read_commands += 1
    name = _tool_name(payload).rsplit(".", 1)[-1]
    if name in {"read", "read_file"}:
        raw_path = _direct_path(payload)
        if raw_path:
            tool_input = payload.get("tool_input")
            start = 1
            end: int | None = None
            if isinstance(tool_input, dict):
                raw_start = tool_input.get("start_line", tool_input.get("line_start"))
                raw_limit = tool_input.get("limit")
                raw_end = tool_input.get("end_line", tool_input.get("line_end"))
                if isinstance(raw_start, int) and raw_start > 0:
                    start = raw_start
                if isinstance(raw_end, int) and raw_end >= start:
                    end = raw_end
                elif isinstance(raw_limit, int) and raw_limit > 0:
                    end = start + raw_limit - 1
            add(raw_path, start, end)
            read_commands += 1
    output_cap_tokens = _outer_output_cap(payload)
    reads = tuple(
        result
        for path, line_ranges in sorted(candidates.items())
        if (
            result := _read_measurement(
                path,
                line_ranges,
                runtime=runtime,
                output_cap_tokens=output_cap_tokens,
                line_numbered=path in line_numbered_paths,
            )
        )
        is not None
    )
    if sum(document.estimated_tokens for document in reads) > int(
        output_cap_tokens * OUTPUT_CAP_SAFETY_RATIO
    ):
        reads = tuple(replace(document, confirmed=False) for document in reads)
    unrelated_commands = max(0, len(effective_commands) - read_commands)
    mixed = bool(reads) and (
        len(reads) != 1
        or read_commands != 1
        or unrelated_commands > 0
        or (
            bool(effective_commands)
            and not _standalone_document_read(effective_commands[0])
            and name not in {"read", "read_file"}
        )
    )
    if mixed:
        reads = tuple(replace(document, confirmed=False) for document in reads)
    return DocumentReadBatch(
        reads=reads,
        mixed=mixed,
        bypass=bypass,
        secondary_bypass=secondary_bypass,
        primary_marker=primary_marker,
        primary_output_bypass=primary_output_bypass,
    )


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


def _batch_sha256(payload: dict[str, Any], tool_use_sha256: str) -> str | None:
    containers = [payload]
    tool_input = payload.get("tool_input")
    if isinstance(tool_input, dict):
        containers.append(tool_input)
    for container in containers:
        for key in (
            "batch_id",
            "batchId",
            "parent_tool_use_id",
            "parent_call_id",
            "exec_cell_id",
            "orchestrator_call_id",
        ):
            value = container.get(key)
            if value:
                return _digest(str(value))
    if _tool_name(payload) == "functions.exec" and tool_use_sha256:
        return tool_use_sha256
    return None


def _default_state(session: str, agent: str) -> dict[str, Any]:
    return {
        "schema_version": STATE_SCHEMA_VERSION,
        "session_sha256": session,
        "agent_sha256": agent,
        "task_epoch_sha256": None,
        "context_calls": 0,
        "broad_since_context": 0,
        "initial_reminded": False,
        "last_ceiling_reminder": 0,
        "reminders": 0,
        "event_sequence": 0,
        "recent_tool_use_hashes": [],
        "documents": {},
        "denied_repeat_inputs": {},
        "pending_deliveries": {},
        "document_preflight_services": {},
    }


def _default_shared_state(session: str) -> dict[str, Any]:
    return {
        "schema_version": SHARED_STATE_SCHEMA_VERSION,
        "session_sha256": session,
        "task_epoch_sha256": None,
        "primary": None,
        "secondary_cache": {},
        "secondary_versions": {},
        "pending_followups": {},
        "recent_action_sha256s": [],
        "updated_at": None,
    }


def _read_shared_state(path: Path, session: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return _default_shared_state(session)
    if (
        not isinstance(value, dict)
        or value.get("schema_version") != SHARED_STATE_SCHEMA_VERSION
        or value.get("session_sha256") != session
    ):
        return _default_shared_state(session)
    return value


def _sync_agent_task_epoch(
    state: dict[str, Any], task_epoch_sha256: str | None
) -> bool:
    epoch = str(task_epoch_sha256 or "")
    if not epoch or state.get("task_epoch_sha256") == epoch:
        return False
    state.update(
        {
            "task_epoch_sha256": epoch,
            "context_calls": 0,
            "broad_since_context": 0,
            "initial_reminded": False,
            "last_ceiling_reminder": 0,
            "documents": {},
            "denied_repeat_inputs": {},
            "pending_deliveries": {},
            "document_preflight_services": {},
            "recent_tool_use_hashes": [],
        }
    )
    return True


def _elapsed_seconds(older: Any, newer: str) -> float | None:
    if not isinstance(older, str) or not older:
        return None
    try:
        before = dt.datetime.fromisoformat(older.replace("Z", "+00:00"))
        after = dt.datetime.fromisoformat(newer.replace("Z", "+00:00"))
        if before.tzinfo is None:
            before = before.replace(tzinfo=dt.timezone.utc)
        if after.tzinfo is None:
            after = after.replace(tzinfo=dt.timezone.utc)
    except ValueError:
        return None
    return max(0.0, (after - before).total_seconds())


def _broad_document_read(document: DocumentRead) -> bool:
    return bool(
        document.whole or document.requested_lines > _targeted_window_lines()
    )


def _opportunity_sha256(
    session_sha256: str,
    task_epoch_sha256: str,
    document: DocumentRead,
    *,
    kind: str = "secondary_read",
) -> str:
    return _digest(
        "\0".join(
            (
                "raw-read-intent-v4",
                kind,
                session_sha256,
                task_epoch_sha256,
                document.document_sha256,
                document.version_sha256,
                ";".join(
                    "{}-{}".format(start, end)
                    for start, end in document.ranges
                ),
            )
        )
    )


def _action_opportunity_sha256(
    raw_read_intent_sha256: str,
    *,
    agent_sha256: str,
    action_seed_sha256: str,
    mode: str,
    action: str,
    exclusion: str | None,
    recall_outcome: str,
) -> str:
    return _digest(
        "\0".join(
            (
                "retrieval-action-v4",
                raw_read_intent_sha256,
                agent_sha256,
                action_seed_sha256,
                mode,
                action,
                exclusion or "none",
                recall_outcome,
            )
        )
    )


def _record_action(shared: dict[str, Any], action_sha256: str) -> bool:
    recent = [str(value) for value in shared.get("recent_action_sha256s", [])]
    if action_sha256 in recent:
        return False
    shared["recent_action_sha256s"] = [*recent[-127:], action_sha256]
    return True


def _next_task_epoch(
    shared: dict[str, Any],
    *,
    session_sha256: str,
    document_sha256: str,
    timestamp: str,
) -> str:
    return _digest(
        "\0".join(
            (
                "document-task-v4",
                session_sha256,
                document_sha256,
                timestamp,
                str(shared.get("task_epoch_sha256") or "initial"),
            )
        )
    )


def _cache_key(document: DocumentRead) -> str:
    return _digest(document.document_sha256 + "\0" + document.version_sha256)


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
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def _ranges(value: Any, total_lines: int) -> list[tuple[int, int]]:
    result: list[tuple[int, int]] = []
    if not isinstance(value, list):
        return result
    for item in value:
        if not isinstance(item, list) or len(item) != 2:
            continue
        try:
            start, end = int(item[0]), int(item[1])
        except (TypeError, ValueError):
            continue
        start = min(total_lines, max(1, start))
        end = min(total_lines, max(start, end))
        result.append((start, end))
    return _merge_ranges(result)


def _merge_ranges(values: Iterable[tuple[int, int]]) -> list[tuple[int, int]]:
    merged: list[tuple[int, int]] = []
    for start, end in sorted(values):
        if not merged or start > merged[-1][1] + 1:
            merged.append((start, end))
            continue
        merged[-1] = (merged[-1][0], max(merged[-1][1], end))
    return merged


def _covered_lines(values: Iterable[tuple[int, int]]) -> int:
    return sum(end - start + 1 for start, end in values)


def _uncovered_ranges(
    requested: Iterable[tuple[int, int]],
    covered: Iterable[tuple[int, int]],
) -> list[tuple[int, int]]:
    """Subtract confirmed coverage from requested line ranges."""
    remaining: list[tuple[int, int]] = []
    confirmed = _merge_ranges(covered)
    for requested_start, requested_end in _merge_ranges(requested):
        cursor = requested_start
        for covered_start, covered_end in confirmed:
            if covered_end < cursor:
                continue
            if covered_start > requested_end:
                break
            if covered_start > cursor:
                remaining.append((cursor, min(requested_end, covered_start - 1)))
            cursor = max(cursor, covered_end + 1)
            if cursor > requested_end:
                break
        if cursor <= requested_end:
            remaining.append((cursor, requested_end))
    return remaining


def _minimum_output_cap_tokens(estimated_tokens: int) -> int:
    cap = max(1, int(math.ceil(estimated_tokens / OUTPUT_CAP_SAFETY_RATIO)))
    while estimated_tokens > int(cap * OUTPUT_CAP_SAFETY_RATIO):
        cap += 1
    return cap


def _next_safe_primary_range(
    document: DocumentRead,
    candidates: Iterable[tuple[int, int]],
) -> tuple[int, int, int] | None:
    """Return the first candidate prefix that conservatively fits the output cap."""
    safe_tokens = int(document.output_cap_tokens * OUTPUT_CAP_SAFETY_RATIO)
    if safe_tokens <= 0:
        return None
    try:
        lines = document.path.read_bytes().splitlines(keepends=True) or [b""]
    except OSError:
        return None
    byte_budget = safe_tokens * 4
    for start, end in candidates:
        consumed = 0
        safe_end = start - 1
        for line_number in range(start, min(end, len(lines)) + 1):
            size = len(lines[line_number - 1])
            if document.line_numbered:
                size += max(6, len(str(line_number))) + 1
            if consumed + size > byte_budget:
                break
            consumed += size
            safe_end = line_number
        if safe_end >= start:
            return start, safe_end, int(math.ceil(consumed / 4.0))
    return None


def _primary_output_guidance(
    document: DocumentRead,
    primary: dict[str, Any],
    *,
    selection_pending: bool,
    agent_sha256: str,
    bypass: bool,
) -> tuple[str, dict[str, Any]] | None:
    safe_limit = int(document.output_cap_tokens * OUTPUT_CAP_SAFETY_RATIO)
    if document.estimated_tokens <= safe_limit:
        return None
    confirmed = (
        _ranges(primary.get("ranges"), document.total_lines)
        if primary.get("document_sha256") == document.document_sha256
        and primary.get("version_sha256") == document.version_sha256
        else []
    )
    shared_covered_lines = _covered_lines(confirmed)
    if shared_covered_lines >= document.total_lines and not selection_pending:
        return None
    globally_missing = _uncovered_ranges([(1, document.total_lines)], confirmed)
    requested_missing = _uncovered_ranges(document.ranges, confirmed)
    safe_range = _next_safe_primary_range(
        document, requested_missing or globally_missing
    )
    minimum_cap = _minimum_output_cap_tokens(document.estimated_tokens)
    selection_marker = "CODEX_MEMORY_PRIMARY_READ=1" if selection_pending else ""
    bounded_retry: str | None = None
    suggested_fields: dict[str, Any] = {"suggested_range_count": 0}
    if safe_range is not None:
        start, end, estimated_tokens = safe_range
        bounded = replace(
            document,
            start_line=start,
            end_line=end,
            ranges=((start, end),),
            requested_lines=end - start + 1,
            whole=(start == 1 and end == document.total_lines),
            estimated_tokens=estimated_tokens,
            confirmed=True,
        )
        bounded_retry = _document_retry_command(bounded, selection_marker)
        suggested_fields = {
            "suggested_range_count": 1,
            "suggested_start_line": start,
            "suggested_end_line": end,
            "suggested_range_lines": end - start + 1,
        }
    full_retry = _document_retry_command(document, selection_marker)
    bypass_marker = " ".join(
        value
        for value in (selection_marker, "CODEX_MEMORY_PRIMARY_OUTPUT_BYPASS=1")
        if value
    )
    bypass_retry = _document_retry_command(document, bypass_marker)
    missing_lines = max(0, document.total_lines - shared_covered_lines)
    if bypass:
        message = (
            "Codex-memory primary output-cap bypass (read allowed): this clean "
            "primary read is estimated at {} tokens, above the {}-token safe "
            "share of the visible {}-token cap. The one-shot bypass preserves "
            "access but a clipped response will not receive coverage credit or "
            "commit a pending primary selection."
        ).format(
            document.estimated_tokens,
            safe_limit,
            document.output_cap_tokens,
        )
        guidance_action = "bypass"
        output_safety_blocked = False
    else:
        message = (
            PRIMARY_OUTPUT_DENIAL_PREFIX
            + " this clean primary read "
            "is estimated at {} tokens, above the {}-token safe share of the "
            "visible {}-token output cap, so this attempt was not started. "
            "Shared Post-confirmed first-pass coverage is {}/{} lines. "
        ).format(
            document.estimated_tokens,
            safe_limit,
            document.output_cap_tokens,
            shared_covered_lines,
            document.total_lines,
        )
        if bounded_retry:
            message += "Read the next non-overlapping missing chunk with `{}`. ".format(
                bounded_retry
            )
        else:
            message += (
                "No whole missing line fits this cap; raise the visible output "
                "cap before retrying a bounded range. "
            )
        if agent_sha256 != "root":
            message += (
                "If this subagent needs a specific section that shared coverage "
                "already includes, use the parent's context packet or a targeted "
                "window of at most {} lines that fits the cap; targeted rereads "
                "remain allowed. "
            ).format(_targeted_window_lines())
        else:
            message += (
                "A targeted window of at most {} lines that fits the cap also "
                "remains allowed when only one section is needed. "
            ).format(_targeted_window_lines())
        message += (
            "Alternatively retry `{}` with visible `max_output_tokens` of at "
            "least {}, or explicitly allow this one risky read with `{}`. "
        ).format(full_retry, minimum_cap, bypass_retry)
        if selection_pending:
            message += (
                "Keep `CODEX_MEMORY_PRIMARY_READ=1` on the first safe retry; "
                "only its successful matching PostToolUse commits the primary. "
                "Omit the marker from later chunks so they extend rather than "
                "reset shared coverage."
            )
        else:
            message += (
                "The shared primary is already selected, so leave "
                "`CODEX_MEMORY_PRIMARY_READ` unset while completing it."
            )
        guidance_action = "deny"
        output_safety_blocked = True
    fields = {
        "guided": True,
        "guidance_reason": "output_cap",
        "guidance_action": guidance_action,
        "output_safety_blocked": output_safety_blocked,
        "guidance_context_tokens": _text_tokens(message),
        "shared_covered_lines": shared_covered_lines,
        "missing_lines": missing_lines,
        "minimum_output_cap_tokens": minimum_cap,
        **suggested_fields,
    }
    return message, fields


def _document_entry(
    state: dict[str, Any], document: DocumentRead
) -> tuple[dict[str, Any] | None, bool]:
    documents = state.get("documents")
    if not isinstance(documents, dict):
        documents = {}
        state["documents"] = documents
    raw = documents.get(document.document_sha256)
    if not isinstance(raw, dict):
        return None, False
    same_version = raw.get("version_sha256") == document.version_sha256
    return raw, same_version


def _entry_complete(entry: dict[str, Any] | None, total_lines: int) -> bool:
    if not entry:
        return False
    return _covered_lines(_ranges(entry.get("ranges"), total_lines)) >= total_lines


def _stored_entry_complete(entry: dict[str, Any] | None) -> bool:
    if not entry:
        return False
    try:
        total_lines = max(1, int(entry.get("total_lines", 0)))
    except (TypeError, ValueError):
        return False
    return _entry_complete(entry, total_lines)


def _broad_repeat_candidate(
    entry: dict[str, Any] | None,
    document: DocumentRead,
    *,
    same_version: bool,
) -> bool:
    return bool(
        same_version
        and _entry_complete(entry, document.total_lines)
        and (
            document.whole
            or document.requested_lines > _targeted_window_lines()
        )
    )


def _record_allowed_document_read(
    state: dict[str, Any], document: DocumentRead, *, timestamp: str
) -> dict[str, Any]:
    documents = state.setdefault("documents", {})
    existing = documents.get(document.document_sha256)
    if not isinstance(existing, dict) or existing.get("version_sha256") != document.version_sha256:
        existing = {
            "version_sha256": document.version_sha256,
            "total_lines": document.total_lines,
            "ranges": [],
            "chunks": 0,
        }
    before = _ranges(existing.get("ranges"), document.total_lines)
    before_lines = _covered_lines(before)
    before_complete = before_lines >= document.total_lines
    after = (
        _merge_ranges([*before, *document.ranges])
        if document.confirmed
        else before
    )
    after_lines = _covered_lines(after)
    targeted_revisit = bool(
        before_complete
        and document.confirmed
        and not document.whole
        and document.requested_lines <= _targeted_window_lines()
        and after_lines == before_lines
    )
    existing.update(
        {
            "version_sha256": document.version_sha256,
            "total_lines": document.total_lines,
            "ranges": [[start, end] for start, end in after],
            "updated_at": timestamp,
            "chunks": int(existing.get("chunks", 0)) + bool(document.confirmed),
        }
    )
    documents[document.document_sha256] = existing
    if len(documents) > 128:
        oldest = min(
            documents,
            key=lambda key: str(documents[key].get("updated_at", "")),
        )
        documents.pop(oldest, None)
    return {
        "document_sha256": document.document_sha256,
        "version_sha256": document.version_sha256,
        "ranges": [[start, end] for start, end in after],
        "covered_lines": after_lines,
        "total_lines": document.total_lines,
        "added_lines": max(0, after_lines - before_lines),
        "complete": after_lines >= document.total_lines,
        "targeted_revisit": targeted_revisit,
        "confirmed": document.confirmed,
        "output_cap_tokens": document.output_cap_tokens,
        "line_numbered": document.line_numbered,
        "estimated_tokens": document.estimated_tokens,
        "total_chunks": int(existing.get("chunks", 0)),
    }


def _unconfirmed_document_detail(
    state: dict[str, Any],
    *,
    document_sha256: str,
    version_sha256: str,
    total_lines: int,
    estimated_tokens: int,
    output_cap_tokens: int,
    whole: bool,
) -> dict[str, Any]:
    documents = state.get("documents")
    entry = documents.get(document_sha256) if isinstance(documents, dict) else None
    same_version = bool(
        isinstance(entry, dict) and entry.get("version_sha256") == version_sha256
    )
    prior_ranges = (
        _ranges(entry.get("ranges"), total_lines) if same_version else []
    )
    covered = _covered_lines(prior_ranges)
    return {
        "document_sha256": document_sha256,
        "version_sha256": version_sha256,
        "ranges": [[start, end] for start, end in prior_ranges],
        "covered_lines": covered,
        "total_lines": total_lines,
        "added_lines": 0,
        "complete": covered >= total_lines,
        "targeted_revisit": False,
        "confirmed": False,
        "output_cap_tokens": output_cap_tokens,
        "estimated_tokens": estimated_tokens,
        "total_chunks": int(entry.get("chunks", 0)) if same_version else 0,
        "whole": whole,
    }


def _document_attempt_event(
    state: dict[str, Any],
    details: list[dict[str, Any]],
    *,
    task_epoch_sha256: str = "",
) -> dict[str, Any] | None:
    if not details:
        return None
    return _next_event(
        state,
        "document_read",
        documents=len(details),
        whole_documents=sum(bool(item.get("whole")) for item in details),
        estimated_tokens=sum(int(item.get("estimated_tokens", 0)) for item in details),
        targeted_revisits=0,
        coverage=details,
        **(
            {"task_epoch_sha256": task_epoch_sha256}
            if task_epoch_sha256
            else {}
        ),
    )


def _output(message: str, *, deny: bool = False) -> dict[str, Any]:
    payload: dict[str, Any] = {"hookEventName": "PreToolUse"}
    if deny:
        payload["permissionDecision"] = "deny"
        payload["permissionDecisionReason"] = message
    else:
        payload["additionalContext"] = message
    return {"hookSpecificOutput": payload}


def _query_command(hint: str | None) -> str:
    question = hint or "<focused status, decision, rationale, or spec question>"
    return f'python3 codex-memory/memory.py query "{question}"'


def _initial_message(hint: str | None) -> str:
    return (
        "Codex-memory advisory (non-blocking): a broad plan/spec/document search "
        "started without compact document recall. The current call was allowed. "
        f"Before another corpus sweep, run `{_query_command(hint)}`. A direct "
        "complete read of one named plan/spec remains allowed; code relationships "
        "belong in Graphify."
    )


def _ungrounded_message(count: int, hint: str | None) -> str:
    return (
        f"Codex-memory advisory repeated (non-blocking): broad document sweep "
        f"#{count} still has no compact recall context. The current call was "
        f"allowed. Before another sweep, run `{_query_command(hint)}`; then read "
        "only the provenance-selected documents."
    )


def _ceiling_message(count: int, ceiling: int, hint: str | None) -> str:
    return (
        "Codex-memory advisory checkpoint (non-blocking): {} broad document "
        "searches occurred since the last recall query (cadence target: {}). "
        "The current call was allowed. Run `{}` before continuing a new "
        "corpus-wide branch; direct "
        "reads of already-selected documents remain appropriate."
    ).format(count, ceiling, _query_command(hint))


def _automatic_question(hint: str | None) -> str:
    return hint or "current plan specification status decision rationale"


def _automatic_recall(
    runtime: memory.Runtime,
    hint: str | None,
    *,
    session_sha256: str,
    agent_sha256: str,
    opportunity_sha256: str | None = None,
    mode: str = "inject",
) -> tuple[str | None, str, int]:
    """Run bounded deterministic recall and record it against the hook session."""
    question = _automatic_question(hint)
    refreshed = False
    refresh_ms = 0.0
    if bool(runtime.config.get("freshness", {}).get("auto_refresh", True)):
        refreshed, _report, refresh_ms = memory.ensure_fresh(runtime)
    elif not runtime.db_path.exists():
        return None, "miss", 0
    budget = int(runtime.config["retrieval"]["default_budget"])
    started = time.perf_counter()
    result = memory.recall(runtime, question, budget=budget)
    duration_ms = (time.perf_counter() - started) * 1000
    memory.log_query(
        runtime,
        question,
        budget,
        result,
        duration_ms=duration_ms,
        refreshed=refreshed,
        refresh_ms=refresh_ms,
        session_sha256=session_sha256,
        agent_sha256=agent_sha256,
        trigger="pre_tool_use",
        raw_read_intent_sha256=opportunity_sha256,
        policy_version=(ADOPTION_POLICY_VERSION if opportunity_sha256 else None),
        mode=(mode if opportunity_sha256 else None),
    )
    if not result.hit:
        return None, "miss", result.tokens
    outcome = "focused_hit" if _focused_recall(result) else "broad_hit"
    return result.output, outcome, result.tokens


def _same_document_provenance(output: str, relative: str) -> bool:
    normalized = output.replace("\\", "/")
    target = relative.replace("\\", "/")
    return bool(
        re.search(
            r"(?:—|provenance\s*[:=])\s+{}:\d+(?:-\d+)?\s+@".format(
                re.escape(target)
            ),
            normalized,
            re.I,
        )
    )


def _repeat_guard_recall(
    runtime: memory.Runtime,
    document: DocumentRead,
    *,
    session_sha256: str,
    agent_sha256: str,
    opportunity_sha256: str | None = None,
) -> tuple[str | None, str, int]:
    """Recall one exact document and require provenance for that same document."""
    title = Path(document.relative).stem.replace("-", " ").replace("_", " ")
    question = "document {} {} specification decisions".format(
        document.relative, title
    )
    refreshed = False
    refresh_ms = 0.0
    if bool(runtime.config.get("freshness", {}).get("auto_refresh", True)):
        refreshed, _report, refresh_ms = memory.ensure_fresh(runtime)
    elif not runtime.db_path.exists():
        return None, "miss", 0
    budget = _repeat_guard_budget(runtime)
    started = time.perf_counter()
    result = memory.recall(runtime, question, budget=budget)
    duration_ms = (time.perf_counter() - started) * 1000
    memory.log_query(
        runtime,
        question,
        budget,
        result,
        duration_ms=duration_ms,
        refreshed=refreshed,
        refresh_ms=refresh_ms,
        session_sha256=session_sha256,
        agent_sha256=agent_sha256,
        trigger="repeat_guard",
        raw_read_intent_sha256=opportunity_sha256,
        policy_version=(ADOPTION_POLICY_VERSION if opportunity_sha256 else None),
        mode=("enforce" if opportunity_sha256 else None),
    )
    if not result.hit:
        return None, "miss", result.tokens
    outcome = "focused_hit" if _focused_recall(result) else "broad_hit"
    if not _same_document_provenance(result.output, document.relative):
        return None, "provenance_mismatch", result.tokens
    return result.output, outcome, result.tokens


def _current_document_version(document: DocumentRead) -> str | None:
    try:
        return hashlib.sha256(document.path.read_bytes()).hexdigest()[:16]
    except OSError:
        return None


def _indexed_document_matches(
    runtime: memory.Runtime, document: DocumentRead
) -> bool:
    if not runtime.db_path.exists():
        return False
    try:
        connection = sqlite3.connect(runtime.db_path)
        try:
            values = {
                str(row[0])
                for row in connection.execute(
                    "SELECT DISTINCT source_sha256 FROM entities WHERE source_doc = ?",
                    (document.relative,),
                )
                if row[0]
            }
        finally:
            connection.close()
    except (OSError, sqlite3.Error):
        return False
    return bool(values) and all(
        value.startswith(document.version_sha256) for value in values
    )


def _secondary_recall(
    runtime: memory.Runtime,
    document: DocumentRead,
    *,
    session_sha256: str,
    agent_sha256: str,
    opportunity_sha256: str,
    mode: str,
) -> tuple[str | None, str, int, bool, bool]:
    """Return context, outcome, tokens, enforceability, and version safety."""
    title = Path(document.relative).stem.replace("-", " ").replace("_", " ")
    question = "document {} {} specification decisions".format(
        document.relative, title
    )
    refreshed = False
    refresh_ms = 0.0
    if bool(runtime.config.get("freshness", {}).get("auto_refresh", True)):
        refreshed, _report, refresh_ms = memory.ensure_fresh(runtime)
    elif not runtime.db_path.exists():
        return None, "miss", 0, False, False
    budget = _secondary_budget(runtime)
    started = time.perf_counter()
    result = memory.recall(runtime, question, budget=budget)
    duration_ms = (time.perf_counter() - started) * 1000
    memory.log_query(
        runtime,
        question,
        budget,
        result,
        duration_ms=duration_ms,
        refreshed=refreshed,
        refresh_ms=refresh_ms,
        session_sha256=session_sha256,
        agent_sha256=agent_sha256,
        trigger="secondary_preflight",
        raw_read_intent_sha256=opportunity_sha256,
        policy_version=ADOPTION_POLICY_VERSION,
        mode=mode,
    )
    if not result.hit:
        return None, "miss", result.tokens, False, True
    focused = _focused_recall(result)
    outcome = "focused_hit" if focused else "broad_hit"
    if not _same_document_provenance(result.output, document.relative):
        return None, "provenance_mismatch", result.tokens, False, True
    version_safe = bool(
        _current_document_version(document) == document.version_sha256
        and _indexed_document_matches(runtime, document)
    )
    return result.output, outcome, result.tokens, focused, version_safe


def _document_retry_command(document: DocumentRead, marker: str) -> str:
    path = shlex.quote(document.relative)
    if document.line_numbered:
        script = ";".join(
            "{},{}p".format(start, end) for start, end in document.ranges
        )
        return " ".join(
            value
            for value in (
                marker,
                "nl",
                "-ba",
                path,
                "|",
                "sed",
                "-n",
                shlex.quote(script),
            )
            if value
        )
    if document.whole:
        return " ".join(value for value in (marker, "cat", path) if value)
    script = ";".join("{},{}p".format(start, end) for start, end in document.ranges)
    return " ".join(
        value
        for value in (marker, "sed", "-n", shlex.quote(script), path)
        if value
    )


def _secondary_context_message(recalled: str, *, broad: bool = False) -> str:
    qualifier = "broad/truncated advisory" if broad else "focused grounding"
    return (
        "Codex-memory secondary-document preflight ({}; read allowed):\n{}"
    ).format(qualifier, recalled)


def _secondary_denial_message(document: DocumentRead, recalled: str) -> str:
    primary_retry = _document_retry_command(document, "CODEX_MEMORY_PRIMARY_READ=1")
    bypass_retry = _document_retry_command(
        document, "CODEX_MEMORY_SECONDARY_BYPASS=1"
    )
    return (
        "Codex-memory secondary-document gate: a focused, current, exact-path "
        "recall grounded this non-primary broad read, so it was blocked. "
        "If this is the new task's primary document, the root agent must retry "
        "with `{}`. Otherwise allow this read once with `{}` or use a targeted "
        "window of at most {} lines.\nGrounding:\n{}"
    ).format(primary_retry, bypass_retry, _targeted_window_lines(), recalled)


def _next_event(state: dict[str, Any], event: str, **fields: Any) -> dict[str, Any]:
    state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
    return {"event": event, "sequence": state["event_sequence"], **fields}


def _shared_primary_complete(primary: dict[str, Any], document: DocumentRead) -> bool:
    return bool(
        primary.get("document_sha256") == document.document_sha256
        and primary.get("version_sha256") == document.version_sha256
        and _covered_lines(_ranges(primary.get("ranges"), document.total_lines))
        >= document.total_lines
    )


def _record_shared_primary_read(
    primary: dict[str, Any],
    document: DocumentRead,
    *,
    agent_sha256: str,
    timestamp: str,
) -> None:
    if primary.get("version_sha256") != document.version_sha256:
        primary["version_sha256"] = document.version_sha256
        primary["total_lines"] = document.total_lines
        primary["ranges"] = []
    before = _ranges(primary.get("ranges"), document.total_lines)
    after = _merge_ranges([*before, *document.ranges]) if document.confirmed else before
    primary.update(
        {
            "document_sha256": document.document_sha256,
            "version_sha256": document.version_sha256,
            "total_lines": document.total_lines,
            "ranges": [[start, end] for start, end in after],
            "last_seen_at": timestamp,
            "last_agent_sha256": agent_sha256,
        }
    )


def _pending_for_document(
    pending: dict[str, Any],
    document_sha256: str,
    version_sha256: str | None = None,
) -> list[tuple[str, dict[str, Any]]]:
    matches: list[tuple[str, dict[str, Any]]] = []
    for raw_intent, value in pending.items():
        if not isinstance(value, dict):
            continue
        if value.get("document_sha256") != document_sha256:
            continue
        if version_sha256 is not None and value.get("version_sha256") != version_sha256:
            continue
        matches.append((str(raw_intent), value))
    return sorted(matches, key=lambda item: str(item[1].get("updated_at", "")))


def _terminal_followup_event(
    state: dict[str, Any],
    prior: dict[str, Any],
    *,
    outcome: str,
    document_sha256: str,
    version_sha256: str | None,
) -> dict[str, Any]:
    return _next_event(
        state,
        "retrieval_followup",
        policy_version=ADOPTION_POLICY_VERSION,
        opportunity_sha256=prior.get("opportunity_sha256"),
        raw_read_intent_sha256=prior.get("raw_read_intent_sha256"),
        outcome=outcome,
        document_sha256=document_sha256,
        version_sha256=version_sha256,
        estimated_raw_tokens=0,
    )


def _followup_plan(
    raw_intent: str,
    prior: dict[str, Any],
    *,
    outcome: str,
) -> dict[str, Any]:
    return {
        "pending_raw_intent_sha256": raw_intent,
        "opportunity_sha256": prior.get("opportunity_sha256"),
        "raw_read_intent_sha256": prior.get("raw_read_intent_sha256"),
        "outcome": outcome,
        "document_sha256": prior.get("document_sha256"),
        "version_sha256": prior.get("version_sha256"),
    }


def _document_service_key(task_epoch_sha256: str, document: DocumentRead) -> str:
    return _digest(
        "\0".join(
            (
                "secondary-window-service-v4",
                task_epoch_sha256,
                document.document_sha256,
                document.version_sha256,
            )
        )
    )


def _projected_document_coverage(
    state: dict[str, Any], document: DocumentRead
) -> int:
    entry, same_version = _document_entry(state, document)
    before = _ranges(entry.get("ranges"), document.total_lines) if entry and same_version else []
    return _covered_lines(_merge_ranges([*before, *document.ranges]))


def _secondary_preflight(
    runtime: memory.Runtime,
    *,
    state: dict[str, Any],
    shared: dict[str, Any],
    document_reads: list[DocumentRead],
    search_documents: set[Path],
    read_batch: DocumentReadBatch,
    session_sha256: str,
    agent_sha256: str,
    action_seed_sha256: str,
    timestamp: str,
) -> tuple[
    str | None,
    str | None,
    bool,
    list[dict[str, Any]],
    list[dict[str, Any]],
    dict[str, Any] | None,
]:
    """Preflight secondary reads without crediting delivery before PostToolUse."""
    mode = _secondary_mode(runtime)
    events: list[dict[str, Any]] = []
    followup_plans: list[dict[str, Any]] = []
    primary_transition: dict[str, Any] | None = None
    denial: str | None = None
    context: str | None = None
    force_primary_allow = False
    primary_established = False
    broad_reads = [document for document in document_reads if _broad_document_read(document)]
    clean_single = len(document_reads) == 1 and not read_batch.mixed
    primary = shared.get("primary")
    if not isinstance(primary, dict):
        primary = None

    idle_seconds = _primary_idle_seconds(runtime)
    elapsed = _elapsed_seconds(shared.get("updated_at"), timestamp)
    idle_reset = bool(
        primary
        and agent_sha256 == "root"
        and idle_seconds > 0
        and elapsed is not None
        and elapsed >= idle_seconds
        and clean_single
        and bool(broad_reads)
    )
    marker_document = document_reads[0] if clean_single and document_reads else None
    root_marker = bool(
        read_batch.primary_marker
        and agent_sha256 == "root"
        and marker_document is not None
    )

    pending = shared.setdefault("pending_followups", {})
    if not isinstance(pending, dict):
        pending = {}
        shared["pending_followups"] = pending

    if root_marker or idle_reset:
        assert marker_document is not None
        primary = {
            "document_sha256": marker_document.document_sha256,
            "version_sha256": marker_document.version_sha256,
            "total_lines": marker_document.total_lines,
            "ranges": [],
            "owner_agent_sha256": agent_sha256,
            "set_at": timestamp,
        }
        candidate_epoch = _next_task_epoch(
            shared,
            session_sha256=session_sha256,
            document_sha256=marker_document.document_sha256,
            timestamp=timestamp,
        )
        primary_transition = {
            "kind": "root_marker" if root_marker else "idle_reset",
            "expected_task_epoch_sha256": str(
                shared.get("task_epoch_sha256") or ""
            ),
            "candidate_task_epoch_sha256": candidate_epoch,
            "document_sha256": marker_document.document_sha256,
            "version_sha256": marker_document.version_sha256,
            "total_lines": marker_document.total_lines,
            "owner_agent_sha256": agent_sha256,
            "set_at": timestamp,
        }
        force_primary_allow = bool(root_marker or idle_reset)
        primary_established = True
    elif primary is None and agent_sha256 == "root" and clean_single and broad_reads:
        document = broad_reads[0]
        primary = {
            "document_sha256": document.document_sha256,
            "version_sha256": document.version_sha256,
            "total_lines": document.total_lines,
            "ranges": [],
            "owner_agent_sha256": agent_sha256,
            "set_at": timestamp,
        }
        candidate_epoch = _next_task_epoch(
            shared,
            session_sha256=session_sha256,
            document_sha256=document.document_sha256,
            timestamp=timestamp,
        )
        primary_transition = {
            "kind": "initial",
            "expected_task_epoch_sha256": str(
                shared.get("task_epoch_sha256") or ""
            ),
            "candidate_task_epoch_sha256": candidate_epoch,
            "document_sha256": document.document_sha256,
            "version_sha256": document.version_sha256,
            "total_lines": document.total_lines,
            "owner_agent_sha256": agent_sha256,
            "set_at": timestamp,
            "requires_no_primary": True,
        }
        force_primary_allow = True
        primary_established = True

    matching_primary_document = (
        document_reads[0]
        if clean_single
        and primary is not None
        and primary.get("document_sha256") == document_reads[0].document_sha256
        else None
    )
    primary_guidance_message: str | None = None
    primary_guidance_fields: dict[str, Any] = {}
    if matching_primary_document is not None:
        guidance = _primary_output_guidance(
            matching_primary_document,
            primary,
            selection_pending=primary_transition is not None,
            agent_sha256=agent_sha256,
            bypass=read_batch.primary_output_bypass,
        )
        if guidance is not None:
            primary_guidance_message, primary_guidance_fields = guidance
            if read_batch.primary_output_bypass:
                context = primary_guidance_message
            else:
                denial = primary_guidance_message

    primary_event_document = marker_document if root_marker or idle_reset else (
        document_reads[0] if primary_established and document_reads else None
    )
    if primary_event_document is None and primary_guidance_message is not None:
        primary_event_document = matching_primary_document
    if primary_event_document is not None and (
        root_marker
        or _broad_document_read(primary_event_document)
        or bool(primary_guidance_message)
    ):
        if primary_transition is not None:
            task_epoch = _digest(
                "\0".join(
                    (
                        "provisional-primary-intent-v4",
                        str(shared.get("task_epoch_sha256") or "initial"),
                        primary_event_document.document_sha256,
                        primary_event_document.version_sha256,
                        str(primary_transition.get("kind") or "candidate"),
                    )
                )
            )
        else:
            task_epoch = str(shared.get("task_epoch_sha256") or "")
        primary_intent = _opportunity_sha256(
            session_sha256,
            task_epoch,
            primary_event_document,
            kind="primary_read",
        )
        primary_exclusion = (
            "primary_marker"
            if root_marker
            else "idle_reset"
            if idle_reset
            else "primary_first_pass"
            if primary_established
            else "primary_continuation"
        )
        primary_action = _action_opportunity_sha256(
            primary_intent,
            agent_sha256=agent_sha256,
            action_seed_sha256=action_seed_sha256,
            mode=_secondary_mode(runtime),
            action="exempt",
            exclusion=primary_exclusion,
            recall_outcome="not_attempted",
        )
        if _record_action(shared, primary_action):
            events.append(_next_event(
                state,
                "retrieval_opportunity",
                policy_version=ADOPTION_POLICY_VERSION,
                opportunity_sha256=primary_action,
                raw_read_intent_sha256=primary_intent,
                kind="primary_read",
                eligible=False,
                exclusion=primary_exclusion,
                mode=_secondary_mode(runtime),
                recall_attempted=False,
                recall_outcome="not_attempted",
                grounded=False,
                action="exempt",
                blocked=False,
                document_sha256=primary_event_document.document_sha256,
                version_sha256=primary_event_document.version_sha256,
                estimated_raw_tokens=primary_event_document.estimated_tokens,
                recall_tokens=0,
                delivered_context_tokens=0,
                estimated_avoided_tokens=0,
                **primary_guidance_fields,
            ))
    if denial is not None and primary_guidance_message is not None:
        return denial, None, force_primary_allow, events, [], None

    # Plan fallback resolution now; successful PostToolUse commits it.
    targeted_documents = [
        document
        for document in document_reads
        if not _broad_document_read(document)
    ]
    for document in targeted_documents:
        matches = _pending_for_document(
            pending, document.document_sha256, document.version_sha256
        )
        if matches:
            raw_intent, prior = matches[-1]
            followup_plans.append(
                _followup_plan(raw_intent, prior, outcome="targeted_window")
            )
        for raw_intent, prior in _pending_for_document(
            pending, document.document_sha256
        ):
            if prior.get("version_sha256") == document.version_sha256:
                continue
            events.append(
                _terminal_followup_event(
                    state,
                    prior,
                    outcome="changed",
                    document_sha256=document.document_sha256,
                    version_sha256=document.version_sha256,
                )
            )
            pending.pop(raw_intent, None)
    for path in search_documents:
        measured = _read_measurement(
            path,
            [(1, 1)],
            runtime=runtime,
            output_cap_tokens=DEFAULT_OUTER_OUTPUT_CAP,
        )
        if measured is None:
            continue
        matches = _pending_for_document(
            pending, measured.document_sha256, measured.version_sha256
        )
        if matches:
            raw_intent, prior = matches[-1]
            followup_plans.append(
                _followup_plan(raw_intent, prior, outcome="targeted_search")
            )

    primary_sha = primary.get("document_sha256") if primary else None
    broad_secondary_reads = [
        document
        for document in broad_reads
        if document.document_sha256 != primary_sha
    ]
    task_epoch = str(shared.get("task_epoch_sha256") or "")
    if not task_epoch:
        task_epoch = _digest(session_sha256 + "\0provisional-document-task-v4")
    versions = shared.setdefault("secondary_versions", {})
    if not isinstance(versions, dict):
        versions = {}
        shared["secondary_versions"] = versions
    observed_changes: set[str] = set()
    for candidate in document_reads:
        if candidate.document_sha256 == primary_sha:
            continue
        prior_version = versions.get(candidate.document_sha256)
        if prior_version and prior_version != candidate.version_sha256:
            observed_changes.add(candidate.document_sha256)
        versions[candidate.document_sha256] = candidate.version_sha256
    services = state.setdefault("document_preflight_services", {})
    if not isinstance(services, dict):
        services = {}
        state["document_preflight_services"] = services
    cumulative_secondary_reads: list[DocumentRead] = []
    if clean_single:
        for candidate in targeted_documents:
            if candidate.document_sha256 == primary_sha:
                continue
            service_key = _document_service_key(task_epoch, candidate)
            if service_key in services:
                continue
            if _projected_document_coverage(state, candidate) > _targeted_window_lines():
                cumulative_secondary_reads.append(candidate)
    secondary_reads = broad_secondary_reads or cumulative_secondary_reads
    if not secondary_reads:
        return (
            denial,
            context,
            force_primary_allow,
            events,
            followup_plans,
            primary_transition,
        )

    document = secondary_reads[0]
    opportunity = _opportunity_sha256(session_sha256, task_epoch, document)
    eligible = True
    exclusion: str | None = None
    recall_attempted = False
    recall_outcome = "not_attempted"
    grounded = False
    blocked = False
    action = "allow"
    recall_tokens = 0
    context_tokens_for_cost = 0
    enforceable = False
    provisional = primary is None
    unconfirmed = not document.confirmed

    changed = document.document_sha256 in observed_changes
    if changed:
        for raw_intent, prior in _pending_for_document(
            pending, document.document_sha256
        ):
            events.append(
                _terminal_followup_event(
                    state,
                    prior,
                    outcome="changed",
                    document_sha256=document.document_sha256,
                    version_sha256=document.version_sha256,
                )
            )
            pending.pop(raw_intent, None)

    if len(secondary_reads) != 1 or read_batch.mixed:
        eligible = False
        exclusion = "mixed"
        action = "fail_open"
    elif changed:
        eligible = False
        exclusion = "changed"
        action = "fail_open"
    elif read_batch.secondary_bypass:
        eligible = False
        exclusion = "bypass"
        action = "exempt"
    elif mode == "off":
        eligible = False
        exclusion = "disabled"
        recall_outcome = "disabled"
        action = "exempt"
    else:
        if unconfirmed:
            exclusion = "unconfirmed"
        cache = shared.setdefault("secondary_cache", {})
        if not isinstance(cache, dict):
            cache = {}
            shared["secondary_cache"] = cache
        cached = cache.get(_cache_key(document))
        version_safe = False
        if isinstance(cached, dict) and isinstance(cached.get("context"), str):
            recall_attempted = True
            recalled = str(cached["context"])
            recall_outcome = "cached_hit"
            recall_tokens = 0
            context_tokens_for_cost = int(cached.get("context_tokens", 0))
            enforceable = bool(cached.get("enforceable"))
            grounded = True
            version_safe = bool(
                _current_document_version(document) == document.version_sha256
                and _indexed_document_matches(runtime, document)
            )
        else:
            recall_attempted = True
            try:
                (
                    recalled,
                    recall_outcome,
                    recall_tokens,
                    enforceable,
                    version_safe,
                ) = _secondary_recall(
                    runtime,
                    document,
                    session_sha256=session_sha256,
                    agent_sha256=agent_sha256,
                    opportunity_sha256=opportunity,
                    mode=mode,
                )
            except Exception:
                recalled = None
                recall_outcome = "error"
                recall_tokens = 0
                enforceable = False
                version_safe = False
            grounded = recalled is not None
            context_tokens_for_cost = recall_tokens
            if grounded and version_safe and enforceable:
                cache[_cache_key(document)] = {
                    "document_sha256": document.document_sha256,
                    "version_sha256": document.version_sha256,
                    "context": recalled,
                    "context_tokens": recall_tokens,
                    "enforceable": enforceable,
                    "updated_at": timestamp,
                }
                if len(cache) > 64:
                    oldest = min(
                        cache,
                        key=lambda key: str(cache[key].get("updated_at", "")),
                    )
                    cache.pop(oldest, None)
        if grounded and not version_safe:
            eligible = False
            exclusion = "changed"
            action = "fail_open"
            grounded = False
        elif grounded:
            cheap = bool(
                document.estimated_tokens < _secondary_min_raw_tokens(runtime)
                or document.estimated_tokens <= context_tokens_for_cost
            )
            if (
                mode == "enforce"
                and enforceable
                and not provisional
                and not unconfirmed
                and not cheap
                and _broad_document_read(document)
            ):
                denial = _secondary_denial_message(document, recalled)
                action = "deny"
                blocked = True
            elif mode in {"inject", "enforce"}:
                context = _secondary_context_message(
                    recalled, broad=not enforceable
                )
                action = "inject"
                if mode == "enforce" and provisional:
                    exclusion = "provisional_primary"
                elif mode == "enforce" and not _broad_document_read(document):
                    exclusion = "targeted_window"
                elif mode == "enforce" and cheap:
                    exclusion = "below_enforcement_threshold"
            elif mode == "shadow":
                action = "allow"
            else:
                action = "allow"
        else:
            action = "fail_open"

    if recall_attempted:
        service_key = _document_service_key(task_epoch, document)
        services[service_key] = {
            "document_sha256": document.document_sha256,
            "version_sha256": document.version_sha256,
            "recall_outcome": recall_outcome,
            "action": action,
            "updated_at": timestamp,
        }
        if len(services) > 128:
            oldest = min(
                services,
                key=lambda key: str(services[key].get("updated_at", "")),
            )
            services.pop(oldest, None)

    action_opportunity = _action_opportunity_sha256(
        opportunity,
        agent_sha256=agent_sha256,
        action_seed_sha256=action_seed_sha256,
        mode=mode,
        action=action,
        exclusion=exclusion,
        recall_outcome=recall_outcome,
    )
    if blocked:
        pending[opportunity] = {
            "opportunity_sha256": action_opportunity,
            "raw_read_intent_sha256": opportunity,
            "document_sha256": document.document_sha256,
            "version_sha256": document.version_sha256,
            "estimated_raw_tokens": document.estimated_tokens,
            "updated_at": timestamp,
        }
    elif _broad_document_read(document):
        for raw_intent, prior in _pending_for_document(
            pending, document.document_sha256, document.version_sha256
        ):
            followup_plans.append(
                _followup_plan(raw_intent, prior, outcome="whole_read")
            )
    delivered_context_tokens = _text_tokens(
        denial if action == "deny" else context if action == "inject" else None
    )
    event_grounded = bool(action in {"inject", "deny"} and delivered_context_tokens)
    if _record_action(shared, action_opportunity):
        events.append(_next_event(
            state,
            "retrieval_opportunity",
            policy_version=ADOPTION_POLICY_VERSION,
            opportunity_sha256=action_opportunity,
            raw_read_intent_sha256=opportunity,
            kind="secondary_read",
            eligible=eligible,
            exclusion=exclusion,
            mode=mode,
            recall_attempted=recall_attempted,
            recall_outcome=recall_outcome,
            grounded=event_grounded,
            action=action,
            blocked=blocked,
            document_sha256=document.document_sha256,
            version_sha256=document.version_sha256,
            estimated_raw_tokens=document.estimated_tokens,
            recall_tokens=recall_tokens,
            delivered_context_tokens=delivered_context_tokens,
            estimated_avoided_tokens=(document.estimated_tokens if blocked else 0),
        ))
    return (
        denial,
        context,
        force_primary_allow,
        events,
        followup_plans,
        primary_transition,
    )


def _repeat_guard_message(document: DocumentRead, recalled: str) -> str:
    path = shlex.quote(document.relative)
    return (
        "Codex-memory repeat-read guard: this unchanged configured document "
        "already has complete first-pass coverage in the current session, so "
        "the redundant broad read was blocked. Exact bounded recall returned "
        "same-document provenance:\n"
        + recalled
        + "\nUse a targeted lookup such as `rg -n '<term>' {}` or a small line "
        "window such as `sed -n '<start>,<end>p' {}`. To force this one broad "
        "read, prefix the shell command with "
        "`CODEX_MEMORY_REPEAT_GUARD_BYPASS=1`; to opt out for the environment, "
        "set `CODEX_MEMORY_REPEAT_GUARD=0`."
    ).format(path, path)


def _delivery_key(tool_use_sha256: str, tool_input_sha256: str) -> str:
    return "t:" + tool_use_sha256 if tool_use_sha256 else "i:" + tool_input_sha256


def _serialized_delivery_read(document: DocumentRead) -> dict[str, Any]:
    return {
        "document_sha256": document.document_sha256,
        "version_sha256": document.version_sha256,
        "ranges": [[start, end] for start, end in document.ranges],
        "total_lines": document.total_lines,
        "requested_lines": document.requested_lines,
        "whole": document.whole,
        "estimated_tokens": document.estimated_tokens,
        "confirmed": document.confirmed,
        "output_cap_tokens": document.output_cap_tokens,
        "line_numbered": document.line_numbered,
    }


def _reserve_pending_delivery(
    state: dict[str, Any],
    *,
    task_epoch_sha256: str,
    tool_use_sha256: str,
    tool_input_sha256: str,
    document_reads: list[DocumentRead],
    followups: list[dict[str, Any]],
    primary_transition: dict[str, Any] | None,
    timestamp: str,
) -> None:
    if not document_reads and not followups and primary_transition is None:
        return
    deliveries = state.setdefault("pending_deliveries", {})
    if not isinstance(deliveries, dict):
        deliveries = {}
        state["pending_deliveries"] = deliveries
    key = _delivery_key(tool_use_sha256, tool_input_sha256)
    deliveries[key] = {
        "task_epoch_sha256": task_epoch_sha256,
        "tool_use_sha256": tool_use_sha256 or None,
        "tool_input_sha256": tool_input_sha256,
        "document_reads": [
            _serialized_delivery_read(document) for document in document_reads
        ],
        "attempt_logged": any(not document.confirmed for document in document_reads),
        "followups": followups,
        "primary_transition": primary_transition,
        "created_at": timestamp,
    }
    if len(deliveries) > 128:
        oldest = min(
            deliveries,
            key=lambda item: str(deliveries[item].get("created_at", "")),
        )
        deliveries.pop(oldest, None)


def _response_has_truthy_flag(value: Any, names: set[str]) -> bool:
    if isinstance(value, list):
        return any(_response_has_truthy_flag(item, names) for item in value)
    if not isinstance(value, dict):
        return False
    for key, item in value.items():
        normalized = str(key).replace("-", "_").lower()
        if normalized in names and (
            item is True
            or (isinstance(item, str) and item.strip().lower() in TRUE_VALUES)
        ):
            return True
        if isinstance(item, dict) and _response_has_truthy_flag(item, names):
            return True
    return False


def _response_text(value: Any) -> tuple[str, bool]:
    if isinstance(value, str):
        return value, True
    if isinstance(value, list):
        block_texts = [
            str(item.get("text"))
            for item in value
            if isinstance(item, dict) and isinstance(item.get("text"), str)
        ]
        if block_texts:
            header = block_texts[0].lstrip().lower()
            if header.startswith("script completed"):
                return "\n".join(block_texts[1:]), True
            if header.startswith("script failed") or header.startswith("script running"):
                return "\n".join(block_texts), True
        parts: list[str] = []
        found = False
        for item in value:
            text, present = _response_text(item)
            if present:
                found = True
                parts.append(text)
        return "\n".join(parts), found
    if not isinstance(value, dict):
        return "", False
    for key in ("output", "stdout", "text", "content"):
        if key not in value:
            continue
        text, present = _response_text(value[key])
        if present:
            return text, True
    for key in ("structuredContent", "structured_content", "result", "response"):
        if key not in value:
            continue
        text, present = _response_text(value[key])
        if present:
            return text, True
    return "", False


def _response_field_values(value: Any, names: set[str]) -> list[Any]:
    if isinstance(value, list):
        result: list[Any] = []
        for item in value:
            result.extend(_response_field_values(item, names))
        return result
    if not isinstance(value, dict):
        return []
    result = []
    for key, item in value.items():
        normalized = str(key).replace("-", "_").lower()
        if normalized in names:
            result.append(item)
        if isinstance(item, (dict, list)):
            result.extend(_response_field_values(item, names))
    return result


def _transport_script_status(value: Any) -> str | None:
    if isinstance(value, dict) and "content" in value:
        return _transport_script_status(value.get("content"))
    if not isinstance(value, list):
        return None
    first = next(
        (
            str(item.get("text"))
            for item in value
            if isinstance(item, dict) and isinstance(item.get("text"), str)
        ),
        "",
    ).lstrip().lower()
    if first.startswith("script completed"):
        return "completed"
    if first.startswith("script failed"):
        return "failed"
    if first.startswith("script running"):
        return "running"
    return None


def _successful_tool_response(payload: dict[str, Any]) -> tuple[bool, str]:
    if "tool_response" not in payload:
        return False, ""
    response = payload.get("tool_response")
    if _transport_script_status(response) in {"failed", "running"}:
        return False, ""
    if isinstance(response, dict):
        if _response_has_truthy_flag(
            response, {"iserror", "is_error", "truncated", "is_truncated", "output_truncated"}
        ):
            return False, ""
        exit_codes = _response_field_values(response, {"exit_code", "exitcode"})
        for exit_code in exit_codes:
            try:
                if int(exit_code) != 0:
                    return False, ""
            except (TypeError, ValueError):
                return False, ""
        statuses = {
            str(value).strip().lower()
            for value in _response_field_values(response, {"status"})
            if value is not None
        }
        if statuses.intersection(
            {"error", "failed", "cancelled", "canceled", "timed_out", "timeout"}
        ):
            return False, ""
        if any(
            value is not None and value is not False and value != ""
            for value in _response_field_values(response, {"error"})
        ):
            return False, ""
        has_session = bool(
            _response_field_values(response, {"session_id", "sessionid"})
        )
        if has_session and not exit_codes and not statuses.intersection(
            {"complete", "completed", "success", "succeeded"}
        ) and _transport_script_status(response) != "completed":
            return False, ""
    text, present = _response_text(response)
    if not present:
        return False, ""
    lowered = text.lstrip().lower()
    if lowered.startswith(
        (
            "warning: truncated output",
            "[output truncated",
            "output truncated by",
        )
    ):
        return False, ""
    return True, text


def _delivery_reads_match(
    expected: Any, actual: list[DocumentRead]
) -> bool:
    if not isinstance(expected, list) or len(expected) != len(actual):
        return False
    expected_values = sorted(
        (
            str(item.get("document_sha256") or ""),
            str(item.get("version_sha256") or ""),
            tuple(tuple(value) for value in item.get("ranges", [])),
            bool(item.get("line_numbered")),
        )
        for item in expected
        if isinstance(item, dict)
    )
    actual_values = sorted(
        (
            document.document_sha256,
            document.version_sha256,
            tuple(document.ranges),
            document.line_numbered,
        )
        for document in actual
    )
    return len(expected_values) == len(actual_values) and expected_values == actual_values


def _append_events(
    runtime: memory.Runtime,
    events: Iterable[dict[str, Any]],
    *,
    timestamp: str,
    session_sha256: str,
    agent_sha256: str,
    tool_use_sha256: str,
    identity_fields: dict[str, Any],
    batch_sha256: str | None,
) -> None:
    for event in events:
        if _observe_only():
            event = {**event, "observe_only": True}
        memory._append_jsonl(
            runtime.hook_events_path,
            {
                "schema_version": EVENT_SCHEMA_VERSION,
                "ts": timestamp,
                "codex_session_sha256": session_sha256,
                "agent_sha256": agent_sha256,
                **({"tool_use_sha256": tool_use_sha256} if tool_use_sha256 else {}),
                **identity_fields,
                **({"batch_sha256": batch_sha256} if batch_sha256 else {}),
                **event,
            },
        )


def _process_post_hook(
    payload: dict[str, Any],
    *,
    runtime: memory.Runtime,
    state_dir: Path | None,
    timestamp: str | None,
) -> None:
    """Credit delivery only after a correlated, complete PostToolUse response."""
    if not _inside_repo(payload, runtime.root):
        return None
    identity = _identity(payload)
    if identity is None:
        return None
    session, agent = identity
    commands = _commands(payload)
    identity_fields = _tool_identity_fields(payload, commands)
    input_sha256 = str(identity_fields.get("tool_input_sha256") or "")
    tool_id = str(payload.get("tool_use_id") or "")
    tool_hash = _digest(tool_id) if tool_id else ""
    if "tool_response" not in payload:
        return None
    state_dir = state_dir or runtime.state_dir / "hook-state"
    state_dir.mkdir(parents=True, exist_ok=True)
    stem = "{}-{}".format(session, agent)
    state_path = state_dir / (stem + ".json")
    lock_path = state_dir / (stem + ".lock")
    shared_state_path = state_dir / (session + "-shared.json")
    shared_lock_path = state_dir / (session + "-shared.lock")
    timestamp = timestamp or _utc_now()
    batch_sha256 = _batch_sha256(payload, tool_hash)
    with shared_lock_path.open("a+", encoding="utf-8") as shared_lock_handle, lock_path.open(
        "a+", encoding="utf-8"
    ) as lock_handle:
        if fcntl is not None:
            fcntl.flock(shared_lock_handle.fileno(), fcntl.LOCK_EX)
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        state = _read_state(state_path, session, agent)
        shared = _read_shared_state(shared_state_path, session)
        _sync_agent_task_epoch(state, shared.get("task_epoch_sha256"))
        deliveries = state.get("pending_deliveries")
        if not isinstance(deliveries, dict):
            return None
        keys = [_delivery_key(tool_hash, input_sha256)]
        if tool_hash:
            keys.append(_delivery_key("", input_sha256))
        delivery_key = next((key for key in keys if key in deliveries), None)
        if delivery_key is None:
            return None
        pending_delivery = deliveries.get(delivery_key)
        if not isinstance(pending_delivery, dict):
            return None
        expected_reads = pending_delivery.get("document_reads")
        events: list[dict[str, Any]] = []

        def retire_delivery(*, record_attempt: bool = False) -> None:
            if (
                record_attempt
                and not bool(pending_delivery.get("attempt_logged"))
                and isinstance(expected_reads, list)
            ):
                details = [
                    _unconfirmed_document_detail(
                        state,
                        document_sha256=str(item.get("document_sha256") or ""),
                        version_sha256=str(item.get("version_sha256") or ""),
                        total_lines=max(1, int(item.get("total_lines", 1))),
                        estimated_tokens=max(0, int(item.get("estimated_tokens", 0))),
                        output_cap_tokens=max(0, int(item.get("output_cap_tokens", 0))),
                        whole=bool(item.get("whole")),
                    )
                    for item in expected_reads
                    if isinstance(item, dict)
                ]
                attempt_event = _document_attempt_event(
                    state,
                    details,
                    task_epoch_sha256=str(shared.get("task_epoch_sha256") or ""),
                )
                if attempt_event is not None:
                    events.append(attempt_event)
            deliveries.pop(delivery_key, None)
            state["updated_at"] = timestamp
            _write_state(state_path, state)
            _append_events(
                runtime,
                events,
                timestamp=timestamp,
                session_sha256=session,
                agent_sha256=agent,
                tool_use_sha256=tool_hash,
                identity_fields=identity_fields,
                batch_sha256=batch_sha256,
            )

        success, delivered = _successful_tool_response(payload)
        if not success:
            retire_delivery(record_attempt=True)
            return None
        task_epoch = str(shared.get("task_epoch_sha256") or "")
        if pending_delivery.get("task_epoch_sha256") != task_epoch:
            retire_delivery(record_attempt=True)
            return None
        read_batch = _document_reads(payload, commands, runtime)
        actual_reads = list(read_batch.reads)
        if not _delivery_reads_match(expected_reads, actual_reads):
            retire_delivery(record_attempt=True)
            return None
        expected_confirmed = bool(
            isinstance(expected_reads, list)
            and all(
                isinstance(item, dict) and item.get("confirmed") is True
                for item in expected_reads
            )
        )
        if actual_reads and (
            not expected_confirmed or not all(document.confirmed for document in actual_reads)
        ):
            retire_delivery(record_attempt=True)
            return None
        required_lines = sum(document.requested_lines for document in actual_reads)
        if required_lines and len(delivered.splitlines()) < required_lines:
            retire_delivery(record_attempt=True)
            return None

        confirmed_reads = [replace(document, confirmed=True) for document in actual_reads]
        transition = pending_delivery.get("primary_transition")
        if isinstance(transition, dict):
            expected_epoch = str(
                transition.get("expected_task_epoch_sha256") or ""
            )
            candidate_epoch = str(
                transition.get("candidate_task_epoch_sha256") or ""
            )
            transition_key = (
                str(transition.get("document_sha256") or ""),
                str(transition.get("version_sha256") or ""),
            )
            transition_document = next(
                (
                    document
                    for document in confirmed_reads
                    if (
                        document.document_sha256,
                        document.version_sha256,
                    )
                    == transition_key
                ),
                None,
            )
            if (
                expected_epoch != task_epoch
                or not candidate_epoch
                or transition_document is None
                or (
                    transition.get("requires_no_primary") is True
                    and isinstance(shared.get("primary"), dict)
                )
            ):
                retire_delivery()
                return None
            pending_followups = shared.get("pending_followups")
            if not isinstance(pending_followups, dict):
                pending_followups = {}
                shared["pending_followups"] = pending_followups
            transition_kind = str(transition.get("kind") or "")
            for raw_intent, prior in list(pending_followups.items()):
                if not isinstance(prior, dict):
                    pending_followups.pop(raw_intent, None)
                    continue
                matching = bool(
                    prior.get("document_sha256") == transition_key[0]
                    and prior.get("version_sha256") == transition_key[1]
                )
                if transition_kind == "idle_reset":
                    outcome = "timeout"
                    estimated_tokens = 0
                elif matching:
                    outcome = (
                        "primary_bypass"
                        if transition_kind == "root_marker"
                        else "whole_read"
                    )
                    estimated_tokens = transition_document.estimated_tokens
                else:
                    outcome = "abandoned"
                    estimated_tokens = 0
                events.append(
                    _next_event(
                        state,
                        "retrieval_followup",
                        policy_version=ADOPTION_POLICY_VERSION,
                        opportunity_sha256=prior.get("opportunity_sha256"),
                        raw_read_intent_sha256=prior.get(
                            "raw_read_intent_sha256"
                        ),
                        outcome=outcome,
                        document_sha256=prior.get("document_sha256"),
                        version_sha256=prior.get("version_sha256"),
                        estimated_raw_tokens=estimated_tokens,
                    )
                )
                pending_followups.pop(raw_intent, None)
            shared["primary"] = {
                "document_sha256": transition_key[0],
                "version_sha256": transition_key[1],
                "total_lines": int(transition.get("total_lines", 1)),
                "ranges": [],
                "owner_agent_sha256": transition.get("owner_agent_sha256"),
                "set_at": transition.get("set_at") or timestamp,
            }
            shared["task_epoch_sha256"] = candidate_epoch
            shared["secondary_versions"] = {}
            _sync_agent_task_epoch(state, candidate_epoch)

        if confirmed_reads:
            details = [
                _record_allowed_document_read(state, document, timestamp=timestamp)
                for document in confirmed_reads
            ]
            primary = shared.get("primary")
            if isinstance(primary, dict):
                for document in confirmed_reads:
                    if (
                        primary.get("document_sha256") == document.document_sha256
                    ):
                        _record_shared_primary_read(
                            primary,
                            document,
                            agent_sha256=agent,
                            timestamp=timestamp,
                        )
            events.append(
                _next_event(
                    state,
                    "document_read",
                    documents=len(confirmed_reads),
                    whole_documents=sum(document.whole for document in confirmed_reads),
                    estimated_tokens=sum(
                        document.estimated_tokens for document in confirmed_reads
                    ),
                    targeted_revisits=sum(
                        bool(detail["targeted_revisit"]) for detail in details
                    ),
                    task_epoch_sha256=str(
                        shared.get("task_epoch_sha256") or ""
                    ),
                    coverage=details,
                )
            )

        pending_followups = shared.get("pending_followups")
        if not isinstance(pending_followups, dict):
            pending_followups = {}
            shared["pending_followups"] = pending_followups
        actual_by_document = {
            (document.document_sha256, document.version_sha256): document
            for document in confirmed_reads
        }
        for plan in pending_delivery.get("followups", []):
            if not isinstance(plan, dict):
                continue
            raw_intent = str(plan.get("pending_raw_intent_sha256") or "")
            prior = pending_followups.get(raw_intent)
            if not isinstance(prior, dict):
                continue
            if (
                prior.get("opportunity_sha256") != plan.get("opportunity_sha256")
                or prior.get("raw_read_intent_sha256")
                != plan.get("raw_read_intent_sha256")
            ):
                continue
            outcome = str(plan.get("outcome") or "")
            if outcome == "targeted_search" and not delivered.strip():
                continue
            document_key = (
                str(plan.get("document_sha256") or ""),
                str(plan.get("version_sha256") or ""),
            )
            measured = actual_by_document.get(document_key)
            if outcome != "targeted_search" and measured is None:
                continue
            estimated_tokens = (
                _text_tokens(delivered)
                if outcome == "targeted_search"
                else int(measured.estimated_tokens)
            )
            events.append(
                _next_event(
                    state,
                    "retrieval_followup",
                    policy_version=ADOPTION_POLICY_VERSION,
                    opportunity_sha256=prior.get("opportunity_sha256"),
                    raw_read_intent_sha256=prior.get("raw_read_intent_sha256"),
                    outcome=outcome,
                    document_sha256=plan.get("document_sha256"),
                    version_sha256=plan.get("version_sha256"),
                    estimated_raw_tokens=estimated_tokens,
                )
            )
            pending_followups.pop(raw_intent, None)

        deliveries.pop(delivery_key, None)
        state["updated_at"] = timestamp
        shared["updated_at"] = timestamp
        _write_state(state_path, state)
        _write_state(shared_state_path, shared)
        _append_events(
            runtime,
            events,
            timestamp=timestamp,
            session_sha256=session,
            agent_sha256=agent,
            tool_use_sha256=tool_hash,
            identity_fields=identity_fields,
            batch_sha256=batch_sha256,
        )
        if fcntl is not None:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
            fcntl.flock(shared_lock_handle.fileno(), fcntl.LOCK_UN)
    return None


def process_hook(
    payload: dict[str, Any],
    *,
    runtime: memory.Runtime | None = None,
    state_dir: Path | None = None,
    ceiling: int | None = None,
    timestamp: str | None = None,
    auto_recall: bool | None = None,
) -> dict[str, Any] | None:
    hook_event = payload.get("hook_event_name") or payload.get("hookEventName")
    runtime = runtime or memory.load_runtime()
    if hook_event == "PostToolUse":
        return _process_post_hook(
            payload,
            runtime=runtime,
            state_dir=state_dir,
            timestamp=timestamp,
        )
    if hook_event not in {None, "PreToolUse"}:
        return None
    if not _inside_repo(payload, runtime.root):
        return None
    commands = _commands(payload)
    context_seen = _has_context(commands)
    document_browse = _broad_command_search(commands, runtime) or _direct_broad_search(
        payload, runtime
    )
    broad_command_count = sum(
        _broad_command_search([command], runtime) for command in commands
    )
    if document_browse and broad_command_count == 0:
        broad_command_count = 1
    read_batch = _document_reads(payload, commands, runtime)
    document_reads = list(read_batch.reads)
    search_documents = _configured_search_documents(commands, runtime)
    direct_search_path = _direct_path(payload)
    if (
        direct_search_path
        and _tool_name(payload).rsplit(".", 1)[-1] in SEARCH_TOOLS
    ):
        configured = _configured_document_paths(runtime)
        resolved = _resolve_document(direct_search_path, runtime, configured)
        if resolved is not None:
            search_documents.add(resolved)
    if (
        not context_seen
        and not document_browse
        and not document_reads
        and not search_documents
    ):
        return None
    identity = _identity(payload)
    if identity is None:
        return None
    session, agent = identity
    state_dir = state_dir or runtime.state_dir / "hook-state"
    ceiling = ceiling or _ceiling()
    timestamp = timestamp or _utc_now()
    auto_recall = _auto_recall_enabled() if auto_recall is None else auto_recall
    state_dir.mkdir(parents=True, exist_ok=True)
    stem = "{}-{}".format(session, agent)
    state_path = state_dir / (stem + ".json")
    lock_path = state_dir / (stem + ".lock")
    shared_state_path = state_dir / (session + "-shared.json")
    shared_lock_path = state_dir / (session + "-shared.lock")
    denial: str | None = None
    automatic_context: str | None = None
    reminder: str | None = None
    with shared_lock_path.open("a+", encoding="utf-8") as shared_lock_handle, lock_path.open(
        "a+", encoding="utf-8"
    ) as lock_handle:
        if fcntl is not None:
            fcntl.flock(shared_lock_handle.fileno(), fcntl.LOCK_EX)
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        state = _read_state(state_path, session, agent)
        shared = _read_shared_state(shared_state_path, session)
        _sync_agent_task_epoch(state, shared.get("task_epoch_sha256"))
        tool_id = str(payload.get("tool_use_id") or "")
        tool_hash = _digest(tool_id) if tool_id else ""
        batch_sha256 = _batch_sha256(payload, tool_hash)
        identity_fields = _tool_identity_fields(payload, commands)
        input_sha256 = str(identity_fields.get("tool_input_sha256") or "")
        recent = [str(value) for value in state.get("recent_tool_use_hashes", [])]
        denied_inputs = state.get("denied_repeat_inputs")
        cached_denial = (
            denied_inputs.get(input_sha256)
            if isinstance(denied_inputs, dict)
            else None
        )
        cached_denial_matches = bool(
            len(document_reads) == 1
            and not read_batch.mixed
            and not read_batch.bypass
            and _repeat_guard_enabled()
            and isinstance(cached_denial, dict)
            and cached_denial.get("document_sha256")
            == document_reads[0].document_sha256
            and cached_denial.get("version_sha256")
            == document_reads[0].version_sha256
            and isinstance(cached_denial.get("context"), str)
        )
        # Allowed hook deliveries dedupe by tool id. A denied input is checked
        # first so an exact retry cannot become allowed merely because a host
        # also retained its tool id in the recent-delivery window.
        if tool_hash and tool_hash in recent and not cached_denial_matches:
            return None
        events: list[dict[str, Any]] = []
        if context_seen:
            state["context_calls"] = int(state.get("context_calls", 0)) + 1
            state["broad_since_context"] = 0
            state["last_ceiling_reminder"] = 0
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append({"event": "context", "sequence": state["event_sequence"]})

        (
            secondary_denial,
            secondary_context,
            force_primary_allow,
            secondary_events,
            delivery_followups,
            primary_transition,
        ) = _secondary_preflight(
            runtime,
            state=state,
            shared=shared,
            document_reads=document_reads,
            search_documents=search_documents,
            read_batch=read_batch,
            session_sha256=session,
            agent_sha256=agent,
            action_seed_sha256=(tool_hash or input_sha256),
            timestamp=timestamp,
        )
        if secondary_denial:
            denial = secondary_denial
        if secondary_context:
            automatic_context = secondary_context
        events.extend(secondary_events)
        output_safety_denial = bool(
            secondary_denial
            and secondary_denial.startswith(PRIMARY_OUTPUT_DENIAL_PREFIX)
        )
        if output_safety_denial:
            state["updated_at"] = timestamp
            shared["updated_at"] = timestamp
            _write_state(state_path, state)
            _write_state(shared_state_path, shared)
            _append_events(
                runtime,
                events,
                timestamp=timestamp,
                session_sha256=session,
                agent_sha256=agent,
                tool_use_sha256=tool_hash,
                identity_fields=identity_fields,
                batch_sha256=batch_sha256,
            )
            if fcntl is not None:
                fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
                fcntl.flock(shared_lock_handle.fileno(), fcntl.LOCK_UN)
            return _output(secondary_denial, deny=True)
        _sync_agent_task_epoch(state, shared.get("task_epoch_sha256"))
        recent = [str(value) for value in state.get("recent_tool_use_hashes", [])]
        repeat_candidates: list[DocumentRead] = []
        changed_candidates: list[DocumentRead] = []
        for document in document_reads:
            entry, same_version = _document_entry(state, document)
            primary = shared.get("primary")
            shared_same_version = bool(
                isinstance(primary, dict)
                and primary.get("document_sha256") == document.document_sha256
                and primary.get("version_sha256") == document.version_sha256
            )
            shared_changed_complete = bool(
                isinstance(primary, dict)
                and primary.get("document_sha256") == document.document_sha256
                and primary.get("version_sha256") != document.version_sha256
                and _covered_lines(
                    _ranges(primary.get("ranges"), int(primary.get("total_lines", 1)))
                )
                >= int(primary.get("total_lines", 1))
            )
            if (
                (
                    entry
                    and not same_version
                    and _stored_entry_complete(entry)
                    or shared_changed_complete
                )
                and (
                    document.whole
                    or document.requested_lines > _targeted_window_lines()
                )
            ):
                changed_candidates.append(document)
            if not force_primary_allow and (
                _broad_repeat_candidate(entry, document, same_version=same_version)
                or (
                    shared_same_version
                    and isinstance(primary, dict)
                    and _shared_primary_complete(primary, document)
                    and _broad_document_read(document)
                )
            ):
                repeat_candidates.append(document)

        guard_document = (
            repeat_candidates[0]
            if denial is None
            and len(document_reads) == 1
            and len(repeat_candidates) == 1
            and not read_batch.mixed
            else None
        )
        repeat_outcome: str | None = None
        repeat_document: DocumentRead | None = None
        repeat_cached = False
        repeat_recall_attempted = False
        repeat_recall_outcome = "not_attempted"
        repeat_recall_tokens = 0
        repeat_opportunity: str | None = None
        repeat_candidate = (
            repeat_candidates[0]
            if repeat_candidates
            else changed_candidates[0]
            if changed_candidates
            else None
        )
        if repeat_candidate is not None:
            task_epoch = str(shared.get("task_epoch_sha256") or "")
            if not task_epoch:
                task_epoch = _digest(session + "\0provisional-document-task-v4")
            repeat_opportunity = _opportunity_sha256(
                session,
                task_epoch,
                repeat_candidate,
                kind="repeat_read",
            )
        if repeat_candidates and read_batch.mixed:
            repeat_outcome = "fail_open_mixed"
            repeat_document = repeat_candidates[0]
        elif changed_candidates:
            repeat_outcome = "fail_open_changed"
            repeat_document = changed_candidates[0]
            denied_inputs = state.get("denied_repeat_inputs")
            if isinstance(denied_inputs, dict):
                for key, value in list(denied_inputs.items()):
                    if (
                        isinstance(value, dict)
                        and value.get("document_sha256")
                        == repeat_document.document_sha256
                    ):
                        denied_inputs.pop(key, None)
        elif guard_document is not None:
            repeat_document = guard_document
            if read_batch.bypass:
                repeat_outcome = "bypass"
            elif not _repeat_guard_enabled():
                repeat_outcome = "opt_out"
            else:
                denied_inputs = state.get("denied_repeat_inputs")
                if not isinstance(denied_inputs, dict):
                    denied_inputs = {}
                    state["denied_repeat_inputs"] = denied_inputs
                cached = denied_inputs.get(input_sha256)
                if (
                    isinstance(cached, dict)
                    and cached.get("document_sha256")
                    == guard_document.document_sha256
                    and cached.get("version_sha256")
                    == guard_document.version_sha256
                    and isinstance(cached.get("context"), str)
                ):
                    denial = str(cached["context"])
                    repeat_outcome = "blocked_cached"
                    repeat_cached = True
                    repeat_recall_attempted = True
                    repeat_recall_outcome = "cached_hit"
                else:
                    repeat_recall_attempted = True
                    try:
                        recall_response = _repeat_guard_recall(
                            runtime,
                            guard_document,
                            session_sha256=session,
                            agent_sha256=agent,
                            opportunity_sha256=repeat_opportunity,
                        )
                        if len(recall_response) == 3:
                            (
                                recalled,
                                recall_outcome,
                                repeat_recall_tokens,
                            ) = recall_response
                        else:  # Backward-compatible test/plugin double.
                            recalled, recall_outcome = recall_response
                    except Exception:
                        recalled, recall_outcome = None, "error"
                    repeat_recall_outcome = (
                        "focused_hit" if recall_outcome == "grounded" else recall_outcome
                    )
                    if recalled:
                        denial = _repeat_guard_message(guard_document, recalled)
                        repeat_outcome = "blocked"
                        denied_inputs[input_sha256] = {
                            "document_sha256": guard_document.document_sha256,
                            "version_sha256": guard_document.version_sha256,
                            "context": denial,
                            "updated_at": timestamp,
                        }
                        if len(denied_inputs) > 64:
                            oldest = min(
                                denied_inputs,
                                key=lambda key: str(
                                    denied_inputs[key].get("updated_at", "")
                                ),
                            )
                            denied_inputs.pop(oldest, None)
                    else:
                        repeat_outcome = "fail_open_" + recall_outcome

        if repeat_outcome and repeat_document:
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append(
                {
                    "event": "repeat_guard",
                    "sequence": state["event_sequence"],
                    "document_sha256": repeat_document.document_sha256,
                    "version_sha256": repeat_document.version_sha256,
                    "outcome": repeat_outcome,
                    "redundant_broad_attempt": repeat_outcome
                    != "fail_open_changed",
                    "grounded_block": repeat_outcome
                    in {"blocked", "blocked_cached"},
                    "cached_context": repeat_cached,
                    "estimated_tokens": repeat_document.estimated_tokens,
                    "estimated_avoided_tokens": (
                        repeat_document.estimated_tokens if denial else 0
                    ),
                }
            )
            if repeat_opportunity:
                blocked_repeat = repeat_outcome in {"blocked", "blocked_cached"}
                exclusion = (
                    "mixed"
                    if repeat_outcome == "fail_open_mixed"
                    else "changed"
                    if repeat_outcome == "fail_open_changed"
                    else "bypass"
                    if repeat_outcome == "bypass"
                    else "disabled"
                    if repeat_outcome == "opt_out"
                    else None
                )
                repeat_action = (
                    "deny"
                    if blocked_repeat
                    else "exempt"
                    if repeat_outcome in {"bypass", "opt_out"}
                    else "fail_open"
                )
                repeat_action_opportunity = _action_opportunity_sha256(
                    repeat_opportunity,
                    agent_sha256=agent,
                    action_seed_sha256=(tool_hash or input_sha256),
                    mode=("enforce" if _repeat_guard_enabled() else "off"),
                    action=repeat_action,
                    exclusion=exclusion,
                    recall_outcome=repeat_recall_outcome,
                )
                if _record_action(shared, repeat_action_opportunity):
                    events.append(_next_event(
                        state,
                        "retrieval_opportunity",
                        policy_version=ADOPTION_POLICY_VERSION,
                        opportunity_sha256=repeat_action_opportunity,
                        raw_read_intent_sha256=repeat_opportunity,
                        kind="repeat_read",
                        eligible=exclusion is None,
                        exclusion=exclusion,
                        mode=("enforce" if _repeat_guard_enabled() else "off"),
                        recall_attempted=repeat_recall_attempted,
                        recall_outcome=repeat_recall_outcome,
                        grounded=blocked_repeat,
                        action=repeat_action,
                        blocked=blocked_repeat,
                        document_sha256=repeat_document.document_sha256,
                        version_sha256=repeat_document.version_sha256,
                        estimated_raw_tokens=repeat_document.estimated_tokens,
                        recall_tokens=repeat_recall_tokens,
                        delivered_context_tokens=_text_tokens(
                            denial if blocked_repeat else None
                        ),
                        estimated_avoided_tokens=(
                            repeat_document.estimated_tokens if blocked_repeat else 0
                        ),
                    ))

        reminder_kind: str | None = None
        if document_browse and denial is None:
            count = int(state.get("broad_since_context", 0)) + 1
            grounded = int(state.get("context_calls", 0)) > 0
            hint = _query_hint(payload, commands)
            cadence_due = grounded and count >= ceiling and (
                count - int(state.get("last_ceiling_reminder", 0)) >= ceiling
            )
            auto_grounded = False
            task_epoch = str(shared.get("task_epoch_sha256") or "")
            if not task_epoch:
                task_epoch = _digest(session + "\0provisional-document-task-v4")
            broad_intent = _digest(
                "\0".join(
                    (
                        "raw-read-intent-v4",
                        "broad_sweep",
                        session,
                        task_epoch,
                        input_sha256,
                    )
                )
            )
            broad_eligible = bool(not grounded or cadence_due)
            broad_mode = "inject" if auto_recall else "off"
            broad_recall_attempted = False
            broad_recall_outcome = (
                "disabled"
                if broad_eligible and not auto_recall
                else "not_attempted"
            )
            broad_recall_tokens = 0
            if auto_recall and (not grounded or cadence_due):
                broad_recall_attempted = True
                try:
                    (
                        recalled,
                        broad_recall_outcome,
                        broad_recall_tokens,
                    ) = _automatic_recall(
                        runtime,
                        hint,
                        session_sha256=session,
                        agent_sha256=agent,
                        opportunity_sha256=broad_intent,
                        mode=broad_mode,
                    )
                except Exception:  # Automatic recall is an optimization; stay fail-open.
                    recalled = None
                    broad_recall_outcome = "error"
                if recalled:
                    grounded = True
                    auto_grounded = True
                    count = 1
                    state["context_calls"] = int(state.get("context_calls", 0)) + 1
                    state["broad_since_context"] = count
                    state["initial_reminded"] = False
                    state["last_ceiling_reminder"] = 0
                    state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
                    events.append(
                        {
                            "event": "context",
                            "sequence": state["event_sequence"],
                            "automatic": True,
                        }
                    )
                    automatic_context = (
                        "Codex-memory automatic grounding (plans/specs only):\n"
                        + recalled
                    )
            broad_exclusion = (
                "disabled"
                if broad_eligible and not auto_recall
                else "already_grounded"
                if not broad_eligible
                else None
            )
            broad_action = (
                "inject"
                if auto_grounded
                else "fail_open"
                if broad_recall_attempted
                else "exempt"
                if broad_mode == "off"
                else "allow"
            )
            broad_action_opportunity = _action_opportunity_sha256(
                broad_intent,
                agent_sha256=agent,
                action_seed_sha256=(tool_hash or input_sha256),
                mode=broad_mode,
                action=broad_action,
                exclusion=broad_exclusion,
                recall_outcome=broad_recall_outcome,
            )
            if _record_action(shared, broad_action_opportunity):
                events.append(_next_event(
                    state,
                    "retrieval_opportunity",
                    policy_version=ADOPTION_POLICY_VERSION,
                    opportunity_sha256=broad_action_opportunity,
                    raw_read_intent_sha256=broad_intent,
                    kind="broad_sweep",
                    eligible=broad_eligible and auto_recall,
                    exclusion=broad_exclusion,
                    mode=broad_mode,
                    recall_attempted=broad_recall_attempted,
                    recall_outcome=broad_recall_outcome,
                    grounded=grounded,
                    action=broad_action,
                    blocked=False,
                    estimated_raw_tokens=0,
                    recall_tokens=broad_recall_tokens,
                    delivered_context_tokens=_text_tokens(
                        automatic_context if auto_grounded else None
                    ),
                    estimated_avoided_tokens=0,
                ))
            if not auto_grounded:
                state["broad_since_context"] = count
            if not grounded:
                if not bool(state.get("initial_reminded")):
                    reminder = _initial_message(hint)
                    reminder_kind = "initial"
                    state["initial_reminded"] = True
                else:
                    reminder = _ungrounded_message(count, hint)
                    reminder_kind = "ungrounded"
            elif not auto_grounded and cadence_due:
                reminder = _ceiling_message(count, ceiling, hint)
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
                    "auto_grounded": auto_grounded,
                    "broad_since_context": count,
                    "reminder": reminder_kind,
                    "batch_size_hint": broad_command_count,
                }
            )
        if tool_hash and denial is None:
            state["recent_tool_use_hashes"] = [*recent[-63:], tool_hash]
        if denial is None:
            unconfirmed_details = [
                _unconfirmed_document_detail(
                    state,
                    document_sha256=document.document_sha256,
                    version_sha256=document.version_sha256,
                    total_lines=document.total_lines,
                    estimated_tokens=document.estimated_tokens,
                    output_cap_tokens=document.output_cap_tokens,
                    whole=document.whole,
                )
                for document in document_reads
                if not document.confirmed
            ]
            attempt_event = _document_attempt_event(
                state,
                unconfirmed_details,
                task_epoch_sha256=str(shared.get("task_epoch_sha256") or ""),
            )
            if attempt_event is not None:
                events.append(attempt_event)
            _reserve_pending_delivery(
                state,
                task_epoch_sha256=str(shared.get("task_epoch_sha256") or ""),
                tool_use_sha256=tool_hash,
                tool_input_sha256=input_sha256,
                document_reads=document_reads,
                followups=delivery_followups,
                primary_transition=primary_transition,
                timestamp=timestamp,
            )
        state["updated_at"] = timestamp
        shared["updated_at"] = timestamp
        _write_state(state_path, state)
        _write_state(shared_state_path, shared)
        _append_events(
            runtime,
            events,
            timestamp=timestamp,
            session_sha256=session,
            agent_sha256=agent,
            tool_use_sha256=tool_hash,
            identity_fields=identity_fields,
            batch_sha256=batch_sha256,
        )
        if fcntl is not None:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
            fcntl.flock(shared_lock_handle.fileno(), fcntl.LOCK_UN)
    if denial:
        return _output(denial, deny=True)
    context_output = automatic_context or reminder
    return _output(context_output) if context_output else None


def main() -> int:
    if not _enabled():
        return 0
    try:
        payload = json.load(sys.stdin)
        if isinstance(payload, dict):
            result = process_hook(payload)
            if result is not None and not _observe_only():
                print(json.dumps(result, separators=(",", ":")))
    except Exception as exc:  # The reminder must never interrupt a user tool call.
        if os.environ.get("CODEX_MEMORY_REMINDER_DEBUG") == "1":
            print("codex-memory reminder ignored error: {}".format(exc), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
