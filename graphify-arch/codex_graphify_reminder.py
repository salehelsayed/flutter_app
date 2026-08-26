#!/usr/bin/env python3
"""Targeted Codex gate for Graphify-first code browsing cadence.

The hook denies only an ungrounded code browse, plan/spec-to-code transition,
over-budget browse batch, cadence breach, or code-exploration spawn without a
compact context packet. An anchored compact query, exact raw-search route, or
measured native fallback unlocks the branch; broad questions do not.
Classification and persistence errors remain fail-open. Plan/spec
document reads are classified separately and never increment the code counter.

Only anonymous counters and truncated SHA-256 join identities are written to
telemetry. Commands, prompts, filenames, raw session ids, and tool inputs never
enter the event ledger. A private per-session state file retains only normalized
repo-relative pending paths so the hook can construct one exact affected command.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import re
import shlex
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
DEFAULT_CEILING = 10
DEFAULT_BATCH_BUDGET = 8
CONTEXT_PACKET_TTL_SECONDS = 30 * 60
DEFAULT_AFFECTED_BUDGET = 600
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
_APP_OWNED_CODE_ROOTS = frozenset(context._CODE_BROWSE_ROOTS) - {"graphify-arch"}
_AFFECTED_BLOCK_PREFIX = "Graphify affected closure gate:"
_MOVE_PATCH_PATH = re.compile(r"\*\*\*\s+Move\s+to:\s*(?P<path>[^\\\r\n]+)")
_CODE_TASK = re.compile(
    r"\b(?:code|codebase|source|symbol|caller|implementation|implement|test|"
    r"debug|trace|inspect|review|refactor|fix|module|class|function)\b|"
    r"(?:^|[\s`'\"])(?:lib|test|integration_test|ios|android|scripts|tool|go-[^/\s]+)\/",
    re.I,
)
_CODE_PATH = re.compile(
    r"(?:^|[\s`'\"])(?:[^\s`'\"]+/)+[^\s`'\"]+\."
    r"(?:dart|py|js|ts|tsx|jsx|go|rs|java|kt|swift|m|mm|c|cc|cpp|h|hpp|sh|toml|yaml|yml|json)\b",
    re.I,
)


def _utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8", errors="replace")).hexdigest()[:16]


def _enabled() -> bool:
    return os.environ.get("GRAPHIFY_CODEX_REMINDER", "1").strip().lower() not in _FALSE_VALUES


def _observe_only() -> bool:
    raw = os.environ.get("GRAPHIFY_CODEX_OBSERVE_ONLY")
    return raw is not None and raw.strip().lower() not in _FALSE_VALUES


def _enforce_enabled() -> bool:
    return os.environ.get("GRAPHIFY_CODEX_ENFORCE", "1").strip().lower() not in _FALSE_VALUES


def _affected_enforce_enabled() -> bool:
    return (
        os.environ.get("GRAPHIFY_CODEX_AFFECTED_ENFORCE", "1").strip().lower()
        not in _FALSE_VALUES
    )


def _ceiling() -> int:
    raw = os.environ.get("GRAPHIFY_CODEX_REMINDER_CEILING", str(DEFAULT_CEILING))
    try:
        value = int(raw)
    except ValueError:
        return DEFAULT_CEILING
    return value if 1 <= value <= 10_000 else DEFAULT_CEILING


def _batch_budget() -> int:
    raw = os.environ.get(
        "GRAPHIFY_CODEX_REMINDER_BATCH_BUDGET", str(DEFAULT_BATCH_BUDGET)
    )
    try:
        value = int(raw)
    except ValueError:
        return DEFAULT_BATCH_BUDGET
    return value if 1 <= value <= 1_000 else DEFAULT_BATCH_BUDGET


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


def _tool_identity_fields(
    payload: dict[str, Any], commands: Iterable[str]
) -> dict[str, Any]:
    """Return privacy-safe identities that can be joined to rollout cells."""
    name = _tool_name(payload).rsplit(".", 1)[-1]
    tool_input = payload.get("tool_input")
    if isinstance(tool_input, str):
        try:
            decoded = json.loads(tool_input)
        except json.JSONDecodeError:
            serialized = tool_input.strip()
        else:
            serialized = json.dumps(decoded, sort_keys=True, separators=(",", ":"))
    else:
        try:
            serialized = json.dumps(
                tool_input, sort_keys=True, separators=(",", ":")
            )
        except (TypeError, ValueError):
            serialized = str(tool_input)
    fields: dict[str, Any] = {
        "tool_input_sha256": _digest(name + "\0" + serialized),
    }
    command_hashes = _dedupe(
        _digest(command.strip()) for command in commands if command.strip()
    )
    if command_hashes:
        fields["command_sha256s"] = command_hashes
    return fields


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


def _query_question(invocation: str, *, direct_native: bool = False) -> str | None:
    """Extract the positional question from a recognized Graphify invocation."""
    try:
        tokens = shlex.split(invocation)
    except ValueError:
        return None
    for index, token in enumerate(tokens):
        name = Path(token).name
        helper = name == "tdd_context.py"
        native = direct_native and name == "graphify"
        if not (helper or native):
            continue
        if index + 2 >= len(tokens) or tokens[index + 1] != "query":
            return None
        return tokens[index + 2]
    return None


def _has_exact_anchor_shape(question: str | None) -> bool:
    """Require the same symbol/file-shaped term used by compact anchoring."""
    if not question:
        return False
    _, structured = context._tokens(question)
    return bool(structured)


def _query_is_grounded(question: str | None) -> bool:
    """Mirror compact-query anchoring/routing before crediting hook context."""
    if not _has_exact_anchor_shape(question):
        return False
    assert question is not None
    try:
        graph = context._load_graph()
        seeds, confidence, _ = graph.seeds(question, "general")
        route = context._scope_route(question, confidence)
    except (OSError, ValueError, json.JSONDecodeError, SystemExit):
        # Hook classification remains fail-open if graph state cannot be read.
        return True
    if route.get("route") == "raw_search_fallback":
        return True
    return (
        bool(seeds)
        and confidence == "anchored"
        and route.get("route") == "architecture"
    )


def _has_code_context(commands: Iterable[str]) -> bool:
    for command in commands:
        for operation, invocation in context._helper_invocations(command):
            if operation not in {"query", "native", "affected"}:
                continue
            if context._document_terms(invocation, root=context.ROOT):
                continue
            if operation in {"native", "affected"} or _query_is_grounded(
                _query_question(invocation)
            ):
                return True
        for invocation in context._direct_native_invocations(command):
            if (
                not context._document_terms(invocation, root=context.ROOT)
                and _has_exact_anchor_shape(
                    _query_question(invocation, direct_native=True)
                )
            ):
                return True
    return False


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


def _event_details(payload: dict[str, Any]) -> tuple[bool, bool, bool, int, list[str]]:
    commands = _commands(payload)
    command_document_read = any(
        context._command_browse_kinds(command, root=context.ROOT)[0]
        for command in commands
    )
    command_browse_count = sum(
        context._command_browse_kinds(command, root=context.ROOT)[1]
        for command in commands
    )
    direct_code_browse = _direct_code_browse(payload)
    direct_document_read = False
    raw_path = _direct_path(payload)
    if raw_path and _tool_name(payload).rsplit(".", 1)[-1] in _READ_TOOL_NAMES:
        normalized = _normalized_repo_path(raw_path)
        direct_document_read = bool(
            normalized and context._is_plan_spec_document(normalized)
        )
    code_browse = bool(command_browse_count or direct_code_browse)
    return (
        _has_code_context(commands),
        command_document_read or direct_document_read,
        code_browse,
        max(command_browse_count, int(direct_code_browse)) if code_browse else 0,
        commands,
    )


def _query_anchors(payload: dict[str, Any], commands: Iterable[str]) -> str | None:
    anchors: list[str] = []

    def add(value: str) -> None:
        normalized = value.replace("\\", "/").removeprefix("./")
        cleaned = re.sub(r"[^A-Za-z0-9_./@+-]+", "", normalized)
        if cleaned:
            anchors.append(cleaned[:160])

    raw_path = _direct_path(payload)
    if raw_path:
        normalized = _normalized_repo_path(raw_path)
        if normalized and context._is_code_context_path(normalized):
            add(normalized)
    for command in commands:
        for target in context._repo_command_paths(command, root=context.ROOT):
            if context._is_code_context_path(target):
                add(target)
    selected = _dedupe(anchors)[:3]
    return " ".join(selected) if selected else None


def _code_spawn(payload: dict[str, Any]) -> bool:
    """Return whether this is an explorer/worker task that will browse code."""
    if _tool_name(payload).rsplit(".", 1)[-1] != "spawn_agent":
        return False
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return False
    agent_type = str(tool_input.get("agent_type") or "").strip().lower()
    if agent_type not in {"explorer", "worker"}:
        return False
    message = str(tool_input.get("message") or "")
    if re.search(r"\b(?:document-only|docs-only|non-code)\b", message, re.I):
        return False
    if agent_type == "worker" and not (_CODE_TASK.search(message) or _CODE_PATH.search(message)):
        return False
    return True


def _spawn_context_gap(payload: dict[str, Any]) -> list[str]:
    """Return missing compact-context fields for a code explorer/worker spawn."""
    if not _code_spawn(payload):
        return []
    tool_input = payload.get("tool_input")
    assert isinstance(tool_input, dict)  # Guaranteed by _code_spawn.
    message = str(tool_input.get("message") or "")
    checks = {
        "query_id": re.search(
            r"\bquery_id\s*[:=]\s*[A-Za-z0-9_.:-]{8,64}\b", message
        ),
        "evidence_digest": re.search(
            r"\bevidence_digest\s*[:=]\s*[A-Za-z0-9_.:-]{8,64}\b", message
        ),
        "shortlisted code/test paths": _CODE_PATH.search(message),
        "open proof question": re.search(
            r"\b(?:open\s+)?proof\s+question\s*[:=]", message, re.I
        ),
    }
    return [label for label, matched in checks.items() if not matched]


def _spawn_gate_message(missing: Iterable[str]) -> str:
    fields = ", ".join(missing)
    return (
        "Graphify spawn gate: code exploration was not started because the task "
        f"is missing {fields}. Run/reuse one compact Graphify query, then retry "
        "the spawn with `query_id=<id>`, `evidence_digest=<digest>`, at least one "
        "shortlisted production/test path, and `open proof question: ...`. A "
        "worker may start its own query only for a genuinely different branch."
    )


def _spawn_advisory_message(missing: Iterable[str]) -> str:
    fields = ", ".join(missing)
    return (
        "Graphify spawn advisory (non-blocking): this code agent task is missing "
        f"{fields}. The spawn was allowed. Future tasks should carry "
        "`query_id=<id>`, `evidence_digest=<digest>`, shortlisted production/test "
        "paths, and `open proof question: ...`."
    )


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


def _tool_input_text(payload: dict[str, Any]) -> str:
    tool_input = payload.get("tool_input")
    if isinstance(tool_input, str):
        return tool_input
    if not isinstance(tool_input, dict):
        return ""
    parts = [
        value
        for key in ("patch", "input", "code")
        if isinstance((value := tool_input.get(key)), str)
    ]
    try:
        parts.append(json.dumps(tool_input))
    except (TypeError, ValueError):
        pass
    return "\n".join(parts)


def _is_app_owned_code_path(path: str) -> bool:
    """Limit impact debt to repo app/test/native/script code, not Codex tooling."""
    normalized = path.replace("\\", "/").lstrip("./")
    if not context._is_code_context_path(normalized):
        return False
    first = normalized.split("/", 1)[0]
    return first in _APP_OWNED_CODE_ROOTS


def _apply_patch_paths(payload: dict[str, Any]) -> set[str]:
    """Return normalized app-owned paths from a direct/nested apply_patch call."""
    text = _tool_input_text(payload)
    short_name = _tool_name(payload).rsplit(".", 1)[-1]
    if short_name != "apply_patch" and not re.search(
        r"\btools\.apply_patch\s*\(", text
    ):
        return set()
    raw_paths = context._patch_paths_from_tool_input(text, root=context.ROOT)
    raw_paths.update(match.group("path") for match in _MOVE_PATCH_PATH.finditer(text))
    paths: set[str] = set()
    for raw_path in raw_paths:
        normalized = _normalized_repo_path(raw_path.strip(" '\"`(),;"))
        if normalized and _is_app_owned_code_path(normalized):
            paths.add(normalized)
    return paths


def _affected_attempts(commands: Iterable[str]) -> list[dict[str, Any]]:
    """Return literal affected attempts with canonical privacy-safe input hashes."""
    attempts: list[dict[str, Any]] = []
    for command in commands:
        for operation, invocation in context._helper_invocations(command):
            if operation != "affected":
                continue
            try:
                tokens = shlex.split(invocation)
            except ValueError:
                continue
            try:
                index = tokens.index("affected") + 1
            except ValueError:
                continue
            canonical_inputs: set[str] = set()
            app_paths: set[str] = set()
            while index < len(tokens):
                token = tokens[index]
                if token == "--budget":
                    index += 2
                    continue
                if token.startswith("--budget=") or token.startswith("-"):
                    index += 1
                    continue
                index += 1
                if re.search(r"[$*?\[\]{}]", token):
                    continue
                canonical_inputs.add(Path(token).as_posix().removeprefix("./"))
                normalized = _normalized_repo_path(token)
                if normalized and _is_app_owned_code_path(normalized):
                    app_paths.add(normalized)
            if canonical_inputs:
                attempts.append(
                    {
                        "paths": sorted(app_paths),
                        "question_sha256": _digest(
                            "\n".join(sorted(canonical_inputs))
                        ),
                    }
                )
    return attempts


def _unwrapped_tokens(segment: str) -> list[str]:
    try:
        tokens = shlex.split(segment)
    except ValueError:
        return []
    while tokens and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", tokens[0]):
        tokens.pop(0)
    if tokens and Path(tokens[0]).name == "env":
        tokens.pop(0)
        while tokens and (
            tokens[0].startswith("-")
            or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", tokens[0])
        ):
            tokens.pop(0)
    if tokens and Path(tokens[0]).name == "command":
        tokens.pop(0)
        while tokens and tokens[0].startswith("-"):
            tokens.pop(0)
    return tokens


def _git_subcommand(tokens: list[str]) -> str | None:
    if not tokens or Path(tokens[0]).name != "git":
        return None
    index = 1
    options_with_value = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
    while index < len(tokens):
        token = tokens[index]
        if token in options_with_value:
            index += 2
            continue
        if any(token.startswith(option + "=") for option in options_with_value):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        return token
    return None


def _has_test_selector(arguments: Iterable[str], suffix: str) -> bool:
    args = list(arguments)
    if any(arg in {"-k", "-n", "--name", "--plain-name"} for arg in args):
        return True
    return any(
        arg.split("::", 1)[0].lower().endswith(suffix) or "::" in arg
        for arg in args
        if not arg.startswith("-")
    )


def _segment_closure_kind(segment: str) -> str | None:
    tokens = _unwrapped_tokens(segment)
    if not tokens:
        return None
    if _git_subcommand(tokens) == "commit":
        return "git_commit"

    program = Path(tokens[0]).name
    args = tokens[1:]
    if program in {"bash", "sh", "zsh"}:
        while args and args[0].startswith("-"):
            args.pop(0)
        if not args:
            return None
        program = Path(args[0]).name
        args = args[1:]
    if program in {"run_test_gates.sh", "run_host_test_gates.sh"}:
        return "curated_test_gate"
    if program in {"flutter", "dart"} and args[:1] == ["test"]:
        return None if _has_test_selector(args[1:], ".dart") else "broad_test_gate"
    if program in {"pytest", "py.test"}:
        return None if _has_test_selector(args, ".py") else "broad_test_gate"
    if program.startswith("python") and args[:2] == ["-m", "pytest"]:
        pytest_args = args[2:]
        return None if _has_test_selector(pytest_args, ".py") else "broad_test_gate"
    if program.startswith("python") and args[:2] == ["-m", "unittest"]:
        unittest_args = args[2:]
        if "discover" in unittest_args or not any(
            not arg.startswith("-") for arg in unittest_args
        ):
            return "broad_test_gate"
        return None
    if program == "go" and args[:1] == ["test"]:
        test_args = args[1:]
        if any(arg == "./..." or arg.endswith("/...") for arg in test_args):
            return "broad_test_gate"
        return None
    if program == "cargo" and args[:1] == ["test"]:
        test_args = args[1:]
        if not test_args:
            return "broad_test_gate"
        if any(arg in {"--test", "--package", "-p"} for arg in test_args):
            return None
        return None if any(not arg.startswith("-") for arg in test_args) else "broad_test_gate"
    if (program in {"npm", "pnpm", "yarn"} and args[:1] == ["test"]) or (
        program in {"make", "gmake"} and args[:1] == ["test"]
    ):
        return "broad_test_gate"
    return None


def _closure_kind(commands: Iterable[str]) -> str | None:
    for command in commands:
        for segment in context._shell_command_segments(command):
            if kind := _segment_closure_kind(segment):
                return kind
    return None


def _affected_command(paths: Iterable[str]) -> str:
    rendered = " ".join(shlex.quote(path) for path in sorted(set(paths)))
    return (
        f"python3 graphify-arch/tdd_context.py affected {rendered} "
        f"--budget {DEFAULT_AFFECTED_BUDGET}"
    )


def _affected_gate_message(paths: Iterable[str]) -> str:
    pending = sorted(set(paths))
    return (
        f"{_AFFECTED_BLOCK_PREFIX} {len(pending)} app-owned changed file(s) still "
        "need consolidated reverse-impact context. This closure did not run. "
        f"Run `{_affected_command(pending)}`, then retry the closure. Focused "
        "red/green tests remain allowed. Explicit bypass: set "
        "`GRAPHIFY_CODEX_AFFECTED_ENFORCE=0`."
    )


def _is_affected_block(message: str) -> bool:
    return message.startswith(_AFFECTED_BLOCK_PREFIX)


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
        "handoff_pending": False,
        "handoff_reminded": False,
        "last_ceiling_reminder_raw": 0,
        "reminders": 0,
        "blocks": 0,
        "event_sequence": 0,
        "recent_tool_use_hashes": [],
        "recent_blocked_tools": {},
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


def _read_affected_state(path: Path, session_sha256: str) -> dict[str, Any]:
    default = {
        "schema_version": STATE_SCHEMA_VERSION,
        "session_sha256": session_sha256,
        "pending_paths": [],
        "closure_blocks": 0,
        "recoveries": 0,
        "blocked_pending": False,
        "awaiting_confirmations": [],
    }
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default
    if (
        not isinstance(value, dict)
        or value.get("schema_version") != STATE_SCHEMA_VERSION
        or value.get("session_sha256") != session_sha256
    ):
        return default
    pending: set[str] = set()
    for raw_path in value.get("pending_paths", []):
        if not isinstance(raw_path, str):
            continue
        normalized = _normalized_repo_path(raw_path)
        if normalized and normalized == raw_path and _is_app_owned_code_path(normalized):
            pending.add(normalized)
    value["pending_paths"] = sorted(pending)
    awaiting: list[dict[str, Any]] = []
    for raw_attempt in value.get("awaiting_confirmations", []):
        if not isinstance(raw_attempt, dict):
            continue
        question_sha256 = str(raw_attempt.get("question_sha256") or "")
        attempted_at = str(raw_attempt.get("attempted_at") or "")
        attempt_sha256 = str(raw_attempt.get("attempt_sha256") or "")
        if not re.fullmatch(r"[0-9a-f]{16}", question_sha256):
            continue
        if not re.fullmatch(r"[0-9a-f]{16}", attempt_sha256):
            continue
        try:
            dt.datetime.fromisoformat(attempted_at.replace("Z", "+00:00"))
        except ValueError:
            continue
        attempt_paths: set[str] = set()
        for raw_path in raw_attempt.get("paths", []):
            if not isinstance(raw_path, str):
                continue
            normalized = _normalized_repo_path(raw_path)
            if (
                normalized
                and normalized == raw_path
                and _is_app_owned_code_path(normalized)
            ):
                attempt_paths.add(normalized)
        if not attempt_paths:
            continue
        awaiting.append(
            {
                "attempt_sha256": attempt_sha256,
                "question_sha256": question_sha256,
                "attempted_at": attempted_at,
                "paths": sorted(attempt_paths),
                "miss_reported": bool(raw_attempt.get("miss_reported")),
            }
        )
    value["awaiting_confirmations"] = awaiting[-64:]
    return value


def _usage_timestamp(raw_value: Any) -> dt.datetime | None:
    try:
        value = dt.datetime.fromisoformat(str(raw_value or "").replace("Z", "+00:00"))
    except ValueError:
        return None
    return value if value.tzinfo else value.replace(tzinfo=dt.timezone.utc)


def _confirmed_affected_attempts(
    awaiting: list[dict[str, Any]],
    *,
    session_sha256: str,
    usage_path: Path,
) -> set[str]:
    """Match successful canonical affected records by session, input, and time."""
    if not awaiting:
        return set()
    candidates: dict[str, list[tuple[str, dt.datetime]]] = {}
    for attempt in awaiting:
        attempted_at = _usage_timestamp(attempt.get("attempted_at"))
        if attempted_at is None:
            continue
        candidates.setdefault(str(attempt["question_sha256"]), []).append(
            (str(attempt["attempt_sha256"]), attempted_at)
        )
    confirmed: set[str] = set()
    try:
        handle = usage_path.open(encoding="utf-8")
    except OSError:
        return confirmed
    with handle:
        for line in handle:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(row, dict) or row.get("operation") != "affected":
                continue
            if session_sha256 not in {
                row.get("codex_thread_sha256"),
                row.get("codex_session_sha256"),
            }:
                continue
            question_sha256 = str(row.get("question_sha256") or "")
            if question_sha256 not in candidates:
                continue
            succeeded_at = _usage_timestamp(row.get("ts"))
            if succeeded_at is None:
                continue
            confirmed.update(
                attempt_sha256
                for attempt_sha256, attempted_at in candidates[question_sha256]
                if succeeded_at >= attempted_at
            )
    return confirmed


def _affected_state_awaiting(state_dir: Path, session_sha256: str) -> bool:
    path = state_dir / f"{session_sha256}-affected.json"
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return bool(
        isinstance(value, dict) and value.get("awaiting_confirmations")
    )


def _affected_transition(
    state_dir: Path,
    session_sha256: str,
    *,
    changed_paths: set[str],
    affected_attempts: list[dict[str, Any]],
    tool_use_sha256: str,
    closure_kind: str | None,
    enforce: bool,
    count_block: bool,
    timestamp: str,
    usage_path: Path,
) -> dict[str, Any]:
    """Atomically update session-wide impact debt for runtime guidance."""
    state_path = state_dir / f"{session_sha256}-affected.json"
    lock_path = state_dir / f"{session_sha256}-affected.lock"
    with lock_path.open("a+", encoding="utf-8") as lock_handle:
        try:
            os.fchmod(lock_handle.fileno(), 0o600)
        except OSError:
            pass
        if fcntl is not None:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        state = _read_affected_state(state_path, session_sha256)
        pending = set(state.get("pending_paths", []))
        pending_before = len(pending)
        awaiting = list(state.get("awaiting_confirmations", []))
        confirmed_ids = _confirmed_affected_attempts(
            awaiting,
            session_sha256=session_sha256,
            usage_path=usage_path,
        )
        confirmed_attempts = [
            attempt
            for attempt in awaiting
            if attempt["attempt_sha256"] in confirmed_ids
        ]
        confirmed_paths = {
            path
            for attempt in confirmed_attempts
            for path in attempt.get("paths", [])
        }
        covered_count = len(pending & confirmed_paths)
        pending.difference_update(confirmed_paths)
        awaiting = [
            attempt
            for attempt in awaiting
            if attempt["attempt_sha256"] not in confirmed_ids
        ]
        # A subsequent PreToolUse means the prior tool call has returned. If its
        # canonical success record is still absent, retain the debt but retire
        # the attempt so a failed command does not cause unbounded log rescans.
        confirmation_misses = len(awaiting)
        awaiting = []

        candidate_pending = pending | changed_paths
        blocked = bool(closure_kind and candidate_pending and enforce)
        applied_changed_paths = set() if blocked else changed_paths
        if not blocked:
            pending.update(applied_changed_paths)

        recorded_attempts = 0
        attempted_named_paths: set[str] = set()
        if not blocked:
            existing_ids = {str(attempt["attempt_sha256"]) for attempt in awaiting}
            for index, attempt in enumerate(affected_attempts):
                named_paths = set(attempt.get("paths", [])) & pending
                attempted_named_paths.update(attempt.get("paths", []))
                if not named_paths:
                    continue
                attempt_sha256 = _digest(
                    "\0".join(
                        (
                            tool_use_sha256,
                            str(attempt["question_sha256"]),
                            timestamp,
                            str(index),
                        )
                    )
                )
                if attempt_sha256 in existing_ids:
                    continue
                awaiting.append(
                    {
                        "attempt_sha256": attempt_sha256,
                        "question_sha256": str(attempt["question_sha256"]),
                        "attempted_at": timestamp,
                        "paths": sorted(named_paths),
                        "miss_reported": False,
                    }
                )
                existing_ids.add(attempt_sha256)
                recorded_attempts += 1

        recovered = bool(confirmed_attempts and state.get("blocked_pending") and not pending)
        if recovered:
            state["recoveries"] = int(state.get("recoveries", 0)) + 1
            state["blocked_pending"] = False

        if blocked and count_block:
            state["closure_blocks"] = int(state.get("closure_blocks", 0)) + 1
            state["blocked_pending"] = True

        state["pending_paths"] = sorted(pending)
        state["awaiting_confirmations"] = awaiting[-64:]
        state["updated_at"] = timestamp
        _write_state(state_path, state)
        try:
            state_path.chmod(0o600)
        except OSError:
            pass
        if fcntl is not None:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
    return {
        "pending_paths": sorted(candidate_pending if blocked else pending),
        "pending_before": pending_before,
        "pending_count": len(candidate_pending if blocked else pending),
        "persisted_pending_count": len(pending),
        "changed_count": len(applied_changed_paths),
        "affected_attempt_count": len(affected_attempts) if not blocked else 0,
        "affected_recorded_count": recorded_attempts,
        "affected_named_count": len(attempted_named_paths),
        "covered_count": covered_count,
        "confirmed_attempt_count": len(confirmed_attempts),
        "confirmation_miss_count": confirmation_misses,
        "awaiting_confirmation_count": len(awaiting),
        "closure_kind": closure_kind,
        "blocked": blocked,
        "recovered": recovered,
        "closure_blocks": int(state.get("closure_blocks", 0)),
        "recoveries": int(state.get("recoveries", 0)),
    }


def _append_event(path: Path, event: dict[str, Any]) -> None:
    if _observe_only():
        event = {**event, "observe_only": True}
    data = (json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n").encode()
    descriptor = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
    try:
        os.write(descriptor, data)
    finally:
        os.close(descriptor)


def _context_packet_update(
    state_dir: Path,
    session_sha256: str,
    *,
    add: bool,
    timestamp: str,
) -> bool:
    """Register or atomically claim one anonymous spawned-agent context packet."""
    state_path = state_dir / f"{session_sha256}-context-packets.json"
    lock_path = state_dir / f"{session_sha256}-context-packets.lock"
    with lock_path.open("a+", encoding="utf-8") as lock_handle:
        if fcntl is not None:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        try:
            value = json.loads(state_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            value = {}
        try:
            available = max(0, int(value.get("available", 0)))
        except (TypeError, ValueError):
            available = 0
        try:
            updated_at = dt.datetime.fromisoformat(
                str(value.get("updated_at") or "").replace("Z", "+00:00")
            )
            now = dt.datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
            if updated_at.tzinfo is None:
                updated_at = updated_at.replace(tzinfo=dt.timezone.utc)
            if now.tzinfo is None:
                now = now.replace(tzinfo=dt.timezone.utc)
            if now - updated_at > dt.timedelta(seconds=CONTEXT_PACKET_TTL_SECONDS):
                available = 0
        except ValueError:
            available = 0
        if add:
            available = min(64, available + 1)
            claimed = True
        elif available:
            available -= 1
            claimed = True
        else:
            claimed = False
        _write_state(
            state_path,
            {
                "schema_version": STATE_SCHEMA_VERSION,
                "available": available,
                "updated_at": timestamp,
            },
        )
        if fcntl is not None:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
    return claimed


def _output(message: str, *, deny: bool = False) -> dict[str, Any]:
    payload: dict[str, Any] = {"hookEventName": "PreToolUse"}
    if deny:
        payload["permissionDecision"] = "deny"
        payload["permissionDecisionReason"] = message
    else:
        payload["additionalContext"] = message
    return {"hookSpecificOutput": payload}


def _query_command(anchors: str | None) -> str:
    question = anchors or "<exact symbol or filename>"
    return (
        "python3 graphify-arch/tdd_context.py query "
        f'"{question}" --profile general --budget 600'
    )


def _initial_message(anchors: str | None) -> str:
    return (
        "Graphify advisory (non-blocking): raw app-code browsing started without "
        "an anchored compact/native Graphify query. The current call was allowed. Before "
        f"further code exploration, run `{_query_command(anchors)}`. "
        "Plan/spec and instruction-document reads are excluded from this counter."
    )


def _handoff_message(anchors: str | None) -> str:
    return (
        "Graphify plan→code handoff advisory (non-blocking): a plan/spec was read "
        "after the last code context and source browsing has now started. The "
        f"current call was allowed. Before another source browse, run "
        f"`{_query_command(anchors)}` using only code symbols or filenames; do not "
        "put the plan path or prose into Graphify."
    )


def _batch_message(count: int, budget: int, anchors: str | None) -> str:
    return (
        f"Graphify batch advisory (non-blocking): this orchestration cell declares "
        f"{count} raw code-browse commands (cell target: ≤{budget}). The current "
        "call was allowed. End the cell after this batch, inspect its output, and "
        f"run `{_query_command(anchors)}` or a checkpoint before another "
        "exploratory batch."
    )


def _ceiling_message(raw_count: int, ceiling: int, anchors: str | None) -> str:
    return (
        f"Graphify advisory checkpoint (non-blocking): {raw_count} raw app-code "
        "browse calls occurred since the last compact/native Graphify query "
        f"(cadence target: {ceiling}). The current call was allowed. Before more "
        f"exploratory code reads, run `{_query_command(anchors)}`. If this branch "
        "is ending and only final targeted "
        "verification remains, finish it without querying merely to raise the "
        "Graphify count. Plan/spec reads are excluded."
    )


def _gate_message(
    kind: str,
    anchors: str | None,
    *,
    raw_count: int,
    ceiling: int,
    batch_size: int,
    batch_budget: int,
) -> str:
    reasons = {
        "handoff": "a plan/spec was read and this is the first source browse",
        "initial": "this code branch has no compact/native Graphify context",
        "batch": (
            f"this orchestration cell declares {batch_size} raw browse commands "
            f"(limit {batch_budget})"
        ),
        "ceiling": (
            f"{raw_count} raw code-browse calls have already run since the last "
            f"context (limit {ceiling})"
        ),
    }
    return (
        f"Graphify {kind} gate: {reasons[kind]}. This browse did not run. "
        f"Run `{_query_command(anchors)}` using only code symbols/filenames, then "
        "retry the browse. A broad query does not unlock the branch; "
        "use an exact symbol, filename, gate, or node ID. "
        "Direct reads of the named plan/spec remain allowed."
    )


def process_hook(
    payload: dict[str, Any],
    *,
    state_dir: Path | None = None,
    ceiling: int | None = None,
    batch_budget: int | None = None,
    timestamp: str | None = None,
    enforce: bool | None = None,
    affected_enforce: bool | None = None,
    usage_path: Path | None = None,
) -> dict[str, Any] | None:
    """Process one hook payload and optionally deny an ungrounded code browse."""
    if payload.get("hook_event_name") not in {None, "PreToolUse"}:
        return None
    if not _inside_repository(payload.get("cwd")):
        return None
    context_seen, document_read, code_browse, batch_size_hint, commands = (
        _event_details(payload)
    )
    code_spawn = _code_spawn(payload)
    spawn_missing = _spawn_context_gap(payload) if code_spawn else []
    changed_paths = _apply_patch_paths(payload)
    affected_attempts = _affected_attempts(commands)
    affected_seen = bool(affected_attempts)
    closure_kind = _closure_kind(commands)
    identity = _state_key(payload)
    if identity is None:
        return None
    session_sha256, agent_sha256 = identity
    state_dir = state_dir or _state_dir()
    if (
        not context_seen
        and not document_read
        and not code_browse
        and not code_spawn
        and not changed_paths
        and not affected_seen
        and not closure_kind
        and not _affected_state_awaiting(state_dir, session_sha256)
    ):
        return None
    ceiling = ceiling or _ceiling()
    batch_budget = batch_budget or _batch_budget()
    timestamp = timestamp or _utc_now()
    enforce = _enforce_enabled() if enforce is None else enforce
    affected_enforce = (
        _affected_enforce_enabled()
        if affected_enforce is None
        else affected_enforce
    )
    impact_enforce = bool(enforce and affected_enforce)
    usage_path = usage_path or context.STATS_PATH
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
        batch_sha256 = _batch_sha256(payload, tool_use_hash)
        identity_fields = _tool_identity_fields(payload, commands)
        recent = [str(value) for value in state.get("recent_tool_use_hashes", [])]
        blocked_tools = {
            str(key): str(value)
            for key, value in (state.get("recent_blocked_tools") or {}).items()
            if key and value
        }
        duplicate_tool = bool(tool_use_hash and tool_use_hash in recent)
        was_duplicate_tool = duplicate_tool
        impact = _affected_transition(
            state_dir,
            session_sha256,
            changed_paths=changed_paths,
            affected_attempts=[] if duplicate_tool else affected_attempts,
            tool_use_sha256=tool_use_hash,
            closure_kind=closure_kind,
            enforce=impact_enforce,
            count_block=not duplicate_tool,
            timestamp=timestamp,
            usage_path=usage_path,
        )
        if tool_use_hash and tool_use_hash in recent:
            if tool_use_hash in blocked_tools:
                blocked_message = blocked_tools[tool_use_hash]
                current_affected_message = (
                    _affected_gate_message(impact["pending_paths"])
                    if impact["blocked"]
                    else ""
                )
                affected_block = _is_affected_block(blocked_message)
                affected_sentinel = blocked_message == _AFFECTED_BLOCK_PREFIX
                impact_changed = bool(
                    impact["confirmed_attempt_count"]
                    or impact["confirmation_miss_count"]
                    or (
                        affected_block
                        and not affected_sentinel
                        and blocked_message != current_affected_message
                    )
                )
                if affected_block and (
                    not impact["blocked"] or impact_changed
                ):
                    blocked_tools.pop(tool_use_hash, None)
                    state["recent_blocked_tools"] = blocked_tools
                    state["recent_tool_use_hashes"] = [
                        value
                        for value in state.get("recent_tool_use_hashes", [])
                        if value != tool_use_hash
                    ]
                    recent = list(state["recent_tool_use_hashes"])
                    duplicate_tool = False
                elif affected_block:
                    return _output(current_affected_message, deny=True)
                else:
                    return _output(blocked_tools[tool_use_hash], deny=True)
            else:
                return None
        if tool_use_hash:
            state["recent_tool_use_hashes"] = [*recent[-63:], tool_use_hash]
        if (
            code_spawn
            and not int(state.get("context_calls", 0))
            and "parent compact context" not in spawn_missing
        ):
            spawn_missing.append("parent compact context")

        events: list[dict[str, Any]] = []
        result_message: str | None = None
        deny = False
        closure_blocked = bool(impact["blocked"])

        if impact["changed_count"]:
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append(
                {
                    "event": "code_change",
                    "sequence": state["event_sequence"],
                    "changed_file_count": impact["changed_count"],
                    "pending_affected_count": impact["pending_count"],
                }
            )
        if impact["confirmed_attempt_count"]:
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append(
                {
                    "event": "affected_coverage",
                    "sequence": state["event_sequence"],
                    "confirmed_attempt_count": impact["confirmed_attempt_count"],
                    "covered_file_count": impact["covered_count"],
                    "pending_affected_count": impact["pending_count"],
                    "confirmed": True,
                    "recovered": impact["recovered"],
                    "recoveries": impact["recoveries"],
                }
            )
        if impact["confirmation_miss_count"]:
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append(
                {
                    "event": "affected_confirmation",
                    "sequence": state["event_sequence"],
                    "confirmed": False,
                    "confirmation_miss_count": impact["confirmation_miss_count"],
                    "awaiting_confirmation_count": impact[
                        "awaiting_confirmation_count"
                    ],
                    "pending_affected_count": impact["pending_count"],
                }
            )
        if impact["affected_attempt_count"]:
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append(
                {
                    "event": "affected_attempt",
                    "sequence": state["event_sequence"],
                    "affected_attempt_count": impact["affected_attempt_count"],
                    "affected_recorded_count": impact["affected_recorded_count"],
                    "affected_named_count": impact["affected_named_count"],
                    "awaiting_confirmation_count": impact[
                        "awaiting_confirmation_count"
                    ],
                    "pending_affected_count": impact["pending_count"],
                    "confirmed": False,
                }
            )
        if closure_kind:
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append(
                {
                    "event": "closure",
                    "sequence": state["event_sequence"],
                    "closure_kind": closure_kind,
                    "pending_affected_count": impact["pending_count"],
                    "blocked": closure_blocked,
                    "gate": "affected_closure" if closure_blocked else None,
                    "closure_blocks": impact["closure_blocks"],
                    "recoveries": impact["recoveries"],
                }
            )
            if closure_blocked:
                result_message = _affected_gate_message(impact["pending_paths"])
                deny = True
                if not was_duplicate_tool:
                    state["blocks"] = int(state.get("blocks", 0)) + 1

        if (
            code_browse
            and not closure_blocked
            and not context_seen
            and not document_read
            and not bool(state.get("handoff_pending"))
            and agent_sha256 != "root"
            and not int(state.get("context_calls", 0))
            and batch_size_hint <= batch_budget
            and _context_packet_update(
                state_dir,
                session_sha256,
                add=False,
                timestamp=timestamp,
            )
        ):
            state["context_calls"] = 1
            state["raw_since_context"] = 0
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append(
                {
                    "event": "context",
                    "sequence": state["event_sequence"],
                    "raw_since_context": 0,
                    "inherited": True,
                }
            )

        if code_spawn and not closure_blocked:
            spawn_blocked = bool(spawn_missing and enforce)
            if spawn_missing:
                result_message = (
                    _spawn_gate_message(spawn_missing)
                    if spawn_blocked
                    else _spawn_advisory_message(spawn_missing)
                )
                state["reminders"] = int(state.get("reminders", 0)) + int(
                    not spawn_blocked
                )
                state["blocks"] = int(state.get("blocks", 0)) + int(spawn_blocked)
                deny = spawn_blocked
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append(
                {
                    "event": "spawn",
                    "sequence": state["event_sequence"],
                    "context_packet": not spawn_missing,
                    "missing_fields": len(spawn_missing),
                    "blocked": spawn_blocked,
                    "gate": "spawn_context" if spawn_blocked else None,
                    "reminder": (
                        "spawn_context" if spawn_missing and not spawn_blocked else None
                    ),
                }
            )
            if not spawn_missing:
                _context_packet_update(
                    state_dir,
                    session_sha256,
                    add=True,
                    timestamp=timestamp,
                )

        gate_kind: str | None = None
        if code_browse and enforce and not context_seen and not closure_blocked:
            current_raw = int(state.get("raw_since_context", 0))
            attempted_raw = current_raw + max(1, batch_size_hint)
            if bool(state.get("handoff_pending")) or document_read:
                gate_kind = "handoff"
            elif not int(state.get("context_calls", 0)):
                gate_kind = "initial"
            elif batch_size_hint > batch_budget:
                gate_kind = "batch"
            elif current_raw >= ceiling or attempted_raw > ceiling:
                gate_kind = "ceiling"

        if gate_kind:
            anchors = _query_anchors(payload, commands)
            current_raw = int(state.get("raw_since_context", 0))
            result_message = _gate_message(
                gate_kind,
                anchors,
                raw_count=current_raw,
                ceiling=ceiling,
                batch_size=batch_size_hint,
                batch_budget=batch_budget,
            )
            deny = True
            state["blocks"] = int(state.get("blocks", 0)) + 1
            state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
            events.append(
                {
                    "event": "code_browse",
                    "sequence": state["event_sequence"],
                    "raw_since_context": current_raw,
                    "attempted_raw_since_context": current_raw
                    + max(1, batch_size_hint),
                    "blocked": True,
                    "gate": gate_kind,
                    "reminder": None,
                    "batch_size_hint": batch_size_hint,
                    "batch_budget": batch_budget,
                }
            )
        elif not code_spawn and not closure_blocked:
            if document_read:
                state["handoff_pending"] = True
                state["handoff_reminded"] = False
                state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
                events.append(
                    {
                        "event": "document_read",
                        "sequence": state["event_sequence"],
                        "raw_since_context": int(state.get("raw_since_context", 0)),
                    }
                )
            if context_seen:
                state["raw_since_context"] = 0
                state["context_calls"] = int(state.get("context_calls", 0)) + 1
                state["handoff_pending"] = False
                state["handoff_reminded"] = False
                state["last_ceiling_reminder_raw"] = 0
                if blocked_tools:
                    blocked_hashes = {
                        key
                        for key, message in blocked_tools.items()
                        if not _is_affected_block(message)
                        or not impact["pending_count"]
                    }
                    state["recent_tool_use_hashes"] = [
                        value
                        for value in state.get("recent_tool_use_hashes", [])
                        if value not in blocked_hashes
                    ]
                    blocked_tools = {
                        key: message
                        for key, message in blocked_tools.items()
                        if key not in blocked_hashes
                    }
                    state["recent_blocked_tools"] = blocked_tools
                state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
                events.append(
                    {
                        "event": "context",
                        "sequence": state["event_sequence"],
                        "raw_since_context": 0,
                    }
                )

            if code_browse:
                raw_count = int(state.get("raw_since_context", 0)) + 1
                state["raw_since_context"] = raw_count
                reminder_kind: str | None = None
                if not enforce:
                    anchors = _query_anchors(payload, commands)
                    if bool(state.get("handoff_pending")) and not bool(
                        state.get("handoff_reminded")
                    ):
                        reminder_kind = "handoff"
                        result_message = _handoff_message(anchors)
                        state["handoff_reminded"] = True
                    elif not int(state.get("context_calls", 0)) and not bool(
                        state.get("initial_reminded")
                    ):
                        reminder_kind = "initial"
                        result_message = _initial_message(anchors)
                        state["initial_reminded"] = True
                    elif batch_size_hint > batch_budget:
                        reminder_kind = "batch"
                        result_message = _batch_message(
                            batch_size_hint, batch_budget, anchors
                        )
                    elif raw_count >= ceiling and (
                        raw_count
                        - int(state.get("last_ceiling_reminder_raw", 0))
                        >= ceiling
                    ):
                        reminder_kind = "ceiling"
                        result_message = _ceiling_message(
                            raw_count, ceiling, anchors
                        )
                        state["last_ceiling_reminder_raw"] = raw_count
                    if reminder_kind:
                        state["reminders"] = int(state.get("reminders", 0)) + 1
                state["event_sequence"] = int(state.get("event_sequence", 0)) + 1
                events.append(
                    {
                        "event": "code_browse",
                        "sequence": state["event_sequence"],
                        "raw_since_context": raw_count,
                        "blocked": False,
                        "gate": None,
                        "reminder": reminder_kind,
                        "batch_size_hint": batch_size_hint,
                        "batch_budget": batch_budget,
                    }
                )

        if deny and tool_use_hash and result_message:
            blocked_tools[tool_use_hash] = (
                _AFFECTED_BLOCK_PREFIX if closure_blocked else result_message
            )
            state["recent_blocked_tools"] = dict(
                list(blocked_tools.items())[-64:]
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
                    **(
                        {"tool_use_sha256": tool_use_hash}
                        if tool_use_hash
                        else {}
                    ),
                    **(
                        {"batch_sha256": batch_sha256}
                        if batch_sha256
                        else {}
                    ),
                    **identity_fields,
                    **event,
                },
            )
        if fcntl is not None:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)

    return _output(result_message, deny=deny) if result_message else None


def main() -> int:
    if not _enabled():
        return 0
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            return 0
        result = process_hook(payload)
        if result is not None and not _observe_only():
            print(json.dumps(result, separators=(",", ":")))
    except Exception as exc:  # Classification/persistence failures remain fail-open.
        if os.environ.get("GRAPHIFY_CODEX_REMINDER_DEBUG") == "1":
            print(f"graphify reminder ignored error: {exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
