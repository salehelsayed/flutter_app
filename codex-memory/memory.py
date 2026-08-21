#!/usr/bin/env python3
"""Codex-owned, deterministic recall for plans, specs, and project documents.

This graph is intentionally separate from Graphify's code graph. It owns its
corpus configuration, SQLite database, freshness manifest, retrieval budget,
and privacy-safe Codex session telemetry. No network, embeddings, or model call
is used while building or querying it.

Typical use:
  python3 codex-memory/memory.py query "which plan superseded 148?"
  python3 codex-memory/memory.py status
  python3 codex-memory/memory.py refresh
  python3 codex-memory/memory.py stats --session current
  python3 codex-memory/memory.py benchmark
"""

from __future__ import annotations

import argparse
import contextlib
import dataclasses
import datetime as dt
import fnmatch
import hashlib
import importlib.util
import json
import math
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Iterable, Iterator

try:
    import fcntl
except ImportError:  # pragma: no cover - this repository runs on macOS/Linux.
    fcntl = None  # type: ignore[assignment]


TOOL_VERSION = 1
ROOT = Path(__file__).resolve().parent.parent
MEMORY_DIR = Path(__file__).resolve().parent
DEFAULT_CONFIG_PATH = MEMORY_DIR / "config.json"
LOCAL_CONFIG_NAME = "config.local.json"
SCHEMA_PATH = MEMORY_DIR / "schema.sql"

CHARS_PER_TOKEN = 4
WORD = re.compile(r"[A-Za-z0-9][A-Za-z0-9_./-]*")
HEADING = re.compile(r"^(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$")
STATUS_LINE = re.compile(
    r"^[ \t]*(?:[-*][ \t]+)?(?:\*\*)?status:?\*{0,2}[ \t]*:?[ \t]*(.+)$",
    re.I,
)
PLAN_REFERENCE = re.compile(r"\bplan[ \t#:_-]*(\d{2,4})\b", re.I)
MARKDOWN_LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+\.md)(?:#[^)]*)?\)", re.I)
WIKI_LINK = re.compile(r"\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]")
FENCE = re.compile(r"^[ \t]*(```|~~~)")
MARKDOWN_DECORATION = re.compile(r"[`*_~]+")
SPACE = re.compile(r"\s+")

STOPWORDS = frozenset(
    """
    a an the is are was were be been being of for to in on at by with as and or
    what which who whom whose why how did does do done it its that this these
    those from still no any all there here about into over under should would
    could can may might tell show give use using used says say according
    """.split()
)

STATUS_RULES = (
    ("superseded", ("superseded",)),
    ("refuted", ("refuted", "dropped")),
    ("closed", ("closed", "device-green", "device-proven")),
    ("executed", ("implemented", "executed", "complete", "accepted", "host-green")),
    ("execution-ready", ("execution-ready", "execution ready")),
    ("deferred", ("deferred", "blocked")),
    ("proposed", ("proposed", "planned", "reviewed", "awaiting-review")),
)


@dataclasses.dataclass(frozen=True)
class Runtime:
    root: Path
    config_path: Path
    config: dict[str, Any]
    config_sha256: str
    state_dir: Path
    db_path: Path
    manifest_path: Path
    telemetry_path: Path
    hook_events_path: Path


@dataclasses.dataclass(frozen=True)
class SourceFile:
    path: Path
    relative: str
    source_name: str
    adapter: str
    priority: int


@dataclasses.dataclass(frozen=True)
class Entity:
    id: str
    name: str
    etype: str
    status: str
    status_raw: str
    body: str
    source_doc: str
    source_line: int
    source_end_line: int
    source_commit: str
    source_sha256: str
    source_name: str
    priority: int
    updated_date: str | None
    built_at: str

    def row(self) -> tuple[Any, ...]:
        return dataclasses.astuple(self)


@dataclasses.dataclass(frozen=True)
class Relation:
    src_id: str
    dst_id: str
    rtype: str
    source_doc: str
    source_line: int
    source_commit: str

    def row(self) -> tuple[Any, ...]:
        return dataclasses.astuple(self)


@dataclasses.dataclass
class BuildReport:
    source_counts: dict[str, int]
    skipped: list[tuple[str, str]]
    entities: int = 0
    relations: int = 0
    aliases: int = 0
    duration_ms: float = 0.0
    fingerprint: str = ""

    def render(self) -> str:
        counts = ", ".join(
            "{}={}".format(name, count)
            for name, count in sorted(self.source_counts.items())
        )
        lines = [
            "Codex memory refreshed: {}".format(counts or "no sources"),
            "graph: {} entities · {} relations · {} aliases".format(
                self.entities, self.relations, self.aliases
            ),
            "fingerprint: {} · {:.1f} ms".format(
                self.fingerprint[:16], self.duration_ms
            ),
        ]
        if self.skipped:
            lines.append("skipped: {}".format(len(self.skipped)))
            lines.extend("  {} — {}".format(path, why) for path, why in self.skipped[:20])
            if len(self.skipped) > 20:
                lines.append("  ... {} more".format(len(self.skipped) - 20))
        return "\n".join(lines)


@dataclasses.dataclass(frozen=True)
class RecallResult:
    output: str
    hit: bool
    confidence: str
    matched_terms: int
    query_terms: int
    selected_entities: int
    source_documents: int
    truncated: bool
    tokens: int


class GraphRows:
    def __init__(self) -> None:
        self.entities: dict[str, Entity] = {}
        self.relations: set[Relation] = set()
        self.aliases: dict[tuple[str, str], int] = {}
        self.pending_doc_links: list[tuple[str, str, int, str]] = []
        self.pending_plan_links: list[tuple[str, str, int, str]] = []

    def add_entity(self, entity: Entity) -> None:
        existing = self.entities.get(entity.id)
        if existing is not None and existing != entity:
            raise ValueError("conflicting entity id: {}".format(entity.id))
        self.entities[entity.id] = entity

    def add_relation(self, relation: Relation) -> None:
        self.relations.add(relation)

    def add_alias(self, alias: str, entity_id: str, weight: int) -> None:
        normalized = normalize_alias(alias)
        if not normalized or len(normalized) > 240:
            return
        key = (normalized, entity_id)
        self.aliases[key] = max(weight, self.aliases.get(key, 0))


def _canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _merge_config(base: Any, override: Any, *, key: str = "") -> Any:
    """Merge local overrides; source rows are patched by their stable name."""
    if isinstance(base, dict) and isinstance(override, dict):
        result = dict(base)
        for child_key, value in override.items():
            result[child_key] = _merge_config(result.get(child_key), value, key=child_key)
        return result
    if key == "sources" and isinstance(base, list) and isinstance(override, list):
        result = [dict(item) if isinstance(item, dict) else item for item in base]
        positions = {
            item.get("name"): index
            for index, item in enumerate(result)
            if isinstance(item, dict) and item.get("name")
        }
        for item in override:
            if isinstance(item, dict) and item.get("name") in positions:
                index = positions[item["name"]]
                result[index] = _merge_config(result[index], item)
            else:
                result.append(item)
        return result
    return override


def _absolute(root: Path, value: str | Path) -> Path:
    path = Path(value).expanduser()
    return path if path.is_absolute() else root / path


def load_runtime(
    config_path: Path | str | None = None,
    *,
    root: Path | str = ROOT,
) -> Runtime:
    root = Path(root).resolve()
    raw_path = config_path or os.environ.get("CODEX_MEMORY_CONFIG") or DEFAULT_CONFIG_PATH
    path = _absolute(root, raw_path).resolve()
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValueError("Codex-memory config is missing: {}".format(path)) from exc
    except json.JSONDecodeError as exc:
        raise ValueError("invalid JSON in {}: {}".format(path, exc)) from exc
    local_path = path.with_name(LOCAL_CONFIG_NAME)
    if local_path.exists():
        try:
            override = json.loads(local_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError("invalid JSON in {}: {}".format(local_path, exc)) from exc
        config = _merge_config(config, override)
    _validate_config(config)
    digest = hashlib.sha256(_canonical_json(config).encode("utf-8")).hexdigest()
    state = config["state"]
    state_dir = _absolute(root, state["directory"]).resolve()
    return Runtime(
        root=root,
        config_path=path,
        config=config,
        config_sha256=digest,
        state_dir=state_dir,
        db_path=state_dir / state["database"],
        manifest_path=state_dir / state["manifest"],
        telemetry_path=state_dir / state["telemetry"],
        hook_events_path=state_dir / state["hook_events"],
    )


def _validate_config(config: Any) -> None:
    if not isinstance(config, dict) or config.get("schema_version") != 1:
        raise ValueError("config.schema_version must be 1")
    for name in ("state", "freshness", "retrieval", "documents"):
        if not isinstance(config.get(name), dict):
            raise ValueError("config.{} must be an object".format(name))
    if not isinstance(config.get("sources"), list) or not config["sources"]:
        raise ValueError("config.sources must be a non-empty list")
    names: set[str] = set()
    for source in config["sources"]:
        if not isinstance(source, dict) or not source.get("name"):
            raise ValueError("every source needs a name")
        if source["name"] in names:
            raise ValueError("duplicate source name: {}".format(source["name"]))
        names.add(source["name"])
        if source.get("adapter") not in {"project_memory_plans", "markdown_sections"}:
            raise ValueError("unsupported adapter for {}".format(source["name"]))
        if not isinstance(source.get("include"), list) or not source["include"]:
            raise ValueError("source {} needs include globs".format(source["name"]))
    retrieval = config["retrieval"]
    hard_cap = int(retrieval.get("hard_cap", 0))
    default_budget = int(retrieval.get("default_budget", 0))
    if hard_cap < 100 or not 50 <= default_budget <= hard_cap:
        raise ValueError("retrieval budget must satisfy 50 <= default <= hard_cap")
    if not 0 <= int(retrieval.get("max_hops", 1)) <= 2:
        raise ValueError("retrieval.max_hops must be 0, 1, or 2")
    if config["freshness"].get("check") not in {"stat", "content"}:
        raise ValueError("freshness.check must be 'stat' or 'content'")


def normalize_alias(value: str) -> str:
    value = MARKDOWN_DECORATION.sub("", value).strip().lower()
    return SPACE.sub(" ", value).strip(" ./-_:#")


def _source_relative(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def _matches_any(value: str, patterns: Iterable[str]) -> bool:
    path = Path(value)
    return any(fnmatch.fnmatch(value, pattern) or path.match(pattern) for pattern in patterns)


def collect_sources(runtime: Runtime) -> tuple[list[SourceFile], dict[str, int]]:
    selected: dict[str, SourceFile] = {}
    counts: dict[str, int] = {}
    for source in runtime.config["sources"]:
        name = str(source["name"])
        if source.get("enabled", True) is False:
            counts[name] = 0
            continue
        source_root = _absolute(runtime.root, source.get("root", ".")).resolve()
        excludes = [str(value) for value in source.get("exclude", [])]
        path_pattern = source.get("path_regex")
        selector = re.compile(str(path_pattern)) if path_pattern else None
        paths: set[Path] = set()
        if source_root.exists():
            for pattern in source["include"]:
                paths.update(path for path in source_root.glob(str(pattern)) if path.is_file())
        accepted: list[Path] = []
        for path in sorted(paths, key=lambda item: item.as_posix().lower()):
            if path.suffix.lower() != ".md":
                continue
            local = _source_relative(path, source_root)
            repo_relative = _source_relative(path, runtime.root)
            if _matches_any(local, excludes) or _matches_any(repo_relative, excludes):
                continue
            if selector and not selector.search(local):
                continue
            accepted.append(path)
            candidate = SourceFile(
                path=path,
                relative=repo_relative,
                source_name=name,
                adapter=str(source["adapter"]),
                priority=int(source.get("priority", 50)),
            )
            existing = selected.get(repo_relative)
            if existing is None or candidate.priority > existing.priority:
                selected[repo_relative] = candidate
        counts[name] = len(accepted)
        floor = int(source.get("minimum_files", 0))
        if len(accepted) < floor:
            raise ValueError(
                "source {} matched {} files, below minimum_files {}".format(
                    name, len(accepted), floor
                )
            )
    return sorted(selected.values(), key=lambda item: item.relative), counts


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _implementation_sha256() -> str:
    digest = hashlib.sha256()
    for path in (
        Path(__file__).resolve(),
        SCHEMA_PATH,
        ROOT / "project-memory" / "src" / "build_graph.py",
    ):
        digest.update(path.name.encode("utf-8"))
        digest.update(_sha256_file(path).encode("ascii"))
    return digest.hexdigest()


def _inventory(files: Iterable[SourceFile], *, hashes: bool) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for item in files:
        stat = item.path.stat()
        row: dict[str, Any] = {
            "source": item.source_name,
            "adapter": item.adapter,
            "priority": item.priority,
            "size": stat.st_size,
            "mtime_ns": stat.st_mtime_ns,
        }
        if hashes:
            row["sha256"] = _sha256_file(item.path)
        result[item.relative] = row
    return result


def _read_manifest(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def freshness(
    runtime: Runtime,
    *,
    verify_content: bool = False,
    files: list[SourceFile] | None = None,
) -> tuple[bool, list[str], list[SourceFile], dict[str, int]]:
    try:
        files, counts = collect_sources(runtime) if files is None else (files, {})
    except (OSError, ValueError) as exc:
        return False, ["source-error:{}".format(exc)], files or [], {}
    manifest = _read_manifest(runtime.manifest_path)
    reasons: list[str] = []
    if not runtime.db_path.exists():
        reasons.append("database-missing")
    if manifest is None:
        reasons.append("manifest-missing")
        return False, reasons, files, counts
    if manifest.get("tool_version") != TOOL_VERSION:
        reasons.append("tool-version")
    if manifest.get("implementation_sha256") != _implementation_sha256():
        reasons.append("implementation")
    if manifest.get("config_sha256") != runtime.config_sha256:
        reasons.append("config")
    check_content = verify_content or runtime.config["freshness"].get("check") == "content"
    current = _inventory(files, hashes=check_content)
    previous = manifest.get("files") if isinstance(manifest.get("files"), dict) else {}
    if set(current) != set(previous):
        reasons.append("source-set")
    else:
        for path, row in current.items():
            old = previous[path]
            keys = ["source", "adapter", "priority", "size", "mtime_ns"]
            if check_content:
                keys.append("sha256")
            if any(row.get(key) != old.get(key) for key in keys):
                reasons.append("changed:{}".format(path))
                break
    return not reasons, reasons, files, counts


def _git(root: Path, *args: str) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return result.stdout.decode("utf-8", "replace").strip()


def _provenance(root: Path) -> tuple[str, set[str]]:
    head = _git(root, "rev-parse", "--short", "HEAD") or "no-git"
    dirty: set[str] = set()
    porcelain = _git(root, "status", "--porcelain", "--untracked-files=all", "--", ".")
    if porcelain:
        for line in porcelain.splitlines():
            raw = line[3:].strip().strip('"') if len(line) > 3 else ""
            if " -> " in raw:
                raw = raw.split(" -> ", 1)[1]
            if raw:
                dirty.add(raw)
    return head, dirty


_PROJECT_MEMORY_MODULE: Any = None


def _project_memory_module() -> Any:
    global _PROJECT_MEMORY_MODULE
    if _PROJECT_MEMORY_MODULE is not None:
        return _PROJECT_MEMORY_MODULE
    path = ROOT / "project-memory" / "src" / "build_graph.py"
    spec = importlib.util.spec_from_file_location("codex_memory_plan_adapter", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load project-memory plan adapter: {}".format(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    _PROJECT_MEMORY_MODULE = module
    return module


def _clean_heading(value: str) -> str:
    value = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", value)
    value = MARKDOWN_DECORATION.sub("", value)
    return SPACE.sub(" ", value).strip(" #")


def _document_status(lines: list[str]) -> tuple[str, str, int]:
    for index, line in enumerate(lines[:80]):
        match = STATUS_LINE.match(line)
        if not match:
            continue
        raw = SPACE.sub(" ", match.group(1)).strip()
        lowered = raw.lower()
        for status, needles in STATUS_RULES:
            if any(needle in lowered for needle in needles):
                return status, raw, index + 1
        return "documented", raw, index + 1
    return "documented", "(no explicit status)", 1


def _heading_points(lines: list[str]) -> list[tuple[int, int, str]]:
    result: list[tuple[int, int, str]] = []
    fence: str | None = None
    for index, line in enumerate(lines):
        marker = FENCE.match(line)
        if marker:
            token = marker.group(1)
            if fence is None:
                fence = token
            elif token.startswith(fence[:3]):
                fence = None
            continue
        if fence is not None:
            continue
        match = HEADING.match(line)
        if match:
            title = _clean_heading(match.group(2))
            if title:
                result.append((index, len(match.group(1)), title))
    return result


def _line_chunks(
    lines: list[str],
    *,
    first_line: int,
    max_chars: int,
) -> Iterator[tuple[str, int, int]]:
    if not lines:
        yield "", first_line, first_line
        return
    start = 0
    chars = 0
    for index, line in enumerate(lines):
        next_size = len(line) + 1
        if index > start and chars + next_size > max_chars:
            body = "\n".join(lines[start:index]).strip()
            yield body, first_line + start, first_line + index - 1
            start = index
            chars = 0
        chars += next_size
    body = "\n".join(lines[start:]).strip()
    yield body, first_line + start, first_line + len(lines) - 1


def _id(prefix: str, *parts: str) -> str:
    digest = hashlib.sha256("\0".join(parts).encode("utf-8")).hexdigest()[:20]
    return "{}:{}".format(prefix, digest)


def _name_aliases(name: str, path: str) -> list[tuple[str, int]]:
    values: dict[str, int] = {}

    def add(value: str, weight: int) -> None:
        normalized = normalize_alias(value)
        if normalized:
            values[normalized] = max(weight, values.get(normalized, 0))

    add(name, 18)
    add(path, 30)
    stem = Path(path).stem
    add(stem, 22)
    add(stem.replace("-", " ").replace("_", " "), 20)
    words = [
        value.lower()
        for value in WORD.findall("{} {}".format(name, stem))
        if len(value.strip("./-_")) >= 3 and value.lower() not in STOPWORDS
    ]
    for word in words:
        add(word, 4 if len(word) < 8 else 6)
        for part in re.split(r"[-_/]+", word):
            if len(part) >= 4:
                add(part, 3)
    for left, right in zip(words, words[1:]):
        add("{} {}".format(left, right), 8)
        add("{}-{}".format(left, right), 7)
    return sorted(values.items())


def _heading_aliases(heading: str) -> list[tuple[str, int]]:
    """Compact section aliases; FTS owns body/title recall.

    Repeating a document path and title alias on every section inflated the
    live database by ~250k rows and made an exact filename seed every section.
    A section needs only its own heading phrases; the DOCUMENT row owns paths.
    """
    values: dict[str, int] = {}

    def add(value: str, weight: int) -> None:
        normalized = normalize_alias(value)
        if normalized:
            values[normalized] = max(weight, values.get(normalized, 0))

    add(heading, 18)
    words = [
        value.lower()
        for value in WORD.findall(heading)
        if len(value.strip("./-_")) >= 3 and value.lower() not in STOPWORDS
    ]
    for word in words:
        add(word, 5 if len(word) < 8 else 7)
    for left, right in zip(words, words[1:]):
        add("{} {}".format(left, right), 9)
        add("{}-{}".format(left, right), 8)
    return sorted(values.items())


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def _ingest_plan_source(
    runtime: Runtime,
    source: dict[str, Any],
    files: list[SourceFile],
    rows: GraphRows,
    *,
    built_at: str,
) -> None:
    module = _project_memory_module()
    source_root = _absolute(runtime.root, source.get("root", ".")).resolve()
    direct = {item.path.resolve() for item in files if item.path.parent.resolve() == source_root}
    matched = {path.resolve() for path in source_root.glob("*-tdd-plan.md") if path.is_file()}
    if direct != matched:
        raise ValueError(
            "project_memory_plans adapter requires the exact direct-child "
            "*-tdd-plan.md corpus; config matched {} but adapter sees {}".format(
                len(direct), len(matched)
            )
        )
    with tempfile.TemporaryDirectory(prefix="codex-memory-plan-") as temporary:
        plan_db = Path(temporary) / "plans.db"
        report = module.build(
            source_root,
            plan_db,
            floor=int(source.get("minimum_files", 0)),
            memory_dir=None,
        )
        if not report.floor_satisfied:
            raise ValueError("plan adapter floor failed for {}".format(source["name"]))
        connection = sqlite3.connect(str(plan_db))
        try:
            entities = list(
                connection.execute(
                    "SELECT id,name,etype,status,status_raw,source_doc,source_line,"
                    "source_commit,updated_date FROM entities"
                )
            )
            relations = list(
                connection.execute(
                    "SELECT src_id,dst_id,rtype,source_doc,source_line FROM relations"
                )
            )
            aliases = list(connection.execute("SELECT alias,entity_id FROM aliases"))
        finally:
            connection.close()
    file_map = {item.relative: item for item in files}
    hashes = {item.relative: _sha256_file(item.path) for item in files}
    commits: dict[str, str] = {}
    for row in entities:
        entity_id, name, etype, status, status_raw, doc, line, commit, updated = row
        doc = str(doc)
        source_file = file_map.get(doc)
        if source_file is None:
            raise ValueError("plan adapter emitted an unconfigured document: {}".format(doc))
        commits[entity_id] = str(commit)
        body = str(status_raw) if etype == "PLAN" else ""
        rows.add_entity(
            Entity(
                id=str(entity_id),
                name=str(name),
                etype=str(etype),
                status=str(status),
                status_raw=str(status_raw),
                body=body,
                source_doc=doc,
                source_line=max(1, int(line)),
                source_end_line=max(1, int(line)),
                source_commit=str(commit),
                source_sha256=hashes[doc],
                source_name=str(source["name"]),
                priority=int(source.get("priority", 100)),
                updated_date=str(updated) if updated else None,
                built_at=built_at,
            )
        )
        for alias, weight in _name_aliases(str(name), doc):
            rows.add_alias(alias, str(entity_id), weight)
    for alias, entity_id in aliases:
        alias_text = str(alias)
        weight = 28 if alias_text.isdigit() else (12 if " " in alias_text or "-" in alias_text else 6)
        rows.add_alias(alias_text, str(entity_id), weight)
    for src_id, dst_id, rtype, doc, line in relations:
        rows.add_relation(
            Relation(
                str(src_id),
                str(dst_id),
                str(rtype),
                str(doc),
                int(line),
                commits.get(str(src_id), commits.get(str(dst_id), "unknown")),
            )
        )


def _ingest_markdown_file(
    item: SourceFile,
    rows: GraphRows,
    *,
    head: str,
    dirty: set[str],
    built_at: str,
    max_bytes: int,
    chunk_chars: int,
    skipped: list[tuple[str, str]],
) -> None:
    try:
        size = item.path.stat().st_size
    except OSError as exc:
        skipped.append((item.relative, "stat failed: {}".format(exc)))
        return
    if size > max_bytes:
        skipped.append((item.relative, "{} bytes exceeds max_file_bytes".format(size)))
        return
    try:
        text = _read_text(item.path)
    except OSError as exc:
        skipped.append((item.relative, "read failed: {}".format(exc)))
        return
    if not text.strip():
        skipped.append((item.relative, "empty"))
        return
    source_sha = hashlib.sha256(text.encode("utf-8")).hexdigest()
    commit = head + "+worktree" if item.relative in dirty else head
    lines = text.splitlines()
    points = _heading_points(lines)
    title_point = next((point for point in points if point[1] == 1), None)
    title = title_point[2] if title_point else _clean_heading(item.path.stem.replace("_", " "))
    status, status_raw, status_line = _document_status(lines)
    document_id = _id("document", item.relative)
    first_section = next(
        (point[0] for point in points if title_point is None or point[0] != title_point[0]),
        len(lines),
    )
    intro_start = (title_point[0] + 1) if title_point else 0
    intro = "\n".join(lines[intro_start:first_section]).strip()
    rows.add_entity(
        Entity(
            document_id,
            title,
            "DOCUMENT",
            status,
            status_raw,
            intro,
            item.relative,
            status_line,
            max(status_line, first_section),
            commit,
            source_sha,
            item.source_name,
            item.priority,
            None,
            built_at,
        )
    )
    for alias, weight in _name_aliases(title, item.relative):
        rows.add_alias(alias, document_id, weight)
    _collect_links(rows, document_id, item.relative, intro_start + 1, intro)

    hierarchy: list[tuple[int, str]] = []
    section_points = [point for point in points if title_point is None or point[0] != title_point[0]]
    for ordinal, point in enumerate(section_points):
        index, level, heading = point
        hierarchy = [(old_level, value) for old_level, value in hierarchy if old_level < level]
        hierarchy.append((level, heading))
        next_index = section_points[ordinal + 1][0] if ordinal + 1 < len(section_points) else len(lines)
        body_lines = lines[index + 1 : next_index]
        chunks = list(
            _line_chunks(body_lines, first_line=index + 2, max_chars=max(1000, chunk_chars))
        )
        for part, (body, first_line, end_line) in enumerate(chunks, start=1):
            trail = " › ".join(value for _depth, value in hierarchy[-3:])
            name = "{} › {}".format(title, trail)
            if len(chunks) > 1:
                name += " (part {})".format(part)
            section_id = _id("section", item.relative, str(index + 1), str(part))
            rows.add_entity(
                Entity(
                    section_id,
                    name,
                    "SECTION",
                    status,
                    status_raw,
                    body,
                    item.relative,
                    index + 1,
                    max(index + 1, end_line),
                    commit,
                    source_sha,
                    item.source_name,
                    item.priority,
                    None,
                    built_at,
                )
            )
            rows.add_relation(
                Relation(document_id, section_id, "contains", item.relative, index + 1, commit)
            )
            for alias, weight in _heading_aliases(heading):
                rows.add_alias(alias, section_id, weight)
            _collect_links(rows, section_id, item.relative, first_line, body)


def _collect_links(
    rows: GraphRows,
    entity_id: str,
    source_doc: str,
    first_line: int,
    body: str,
) -> None:
    for match in MARKDOWN_LINK.finditer(body):
        line = first_line + body[: match.start()].count("\n")
        rows.pending_doc_links.append((entity_id, source_doc, line, match.group(1)))
    for match in WIKI_LINK.finditer(body):
        line = first_line + body[: match.start()].count("\n")
        rows.pending_doc_links.append((entity_id, source_doc, line, match.group(1)))
    for match in PLAN_REFERENCE.finditer(body):
        line = first_line + body[: match.start()].count("\n")
        rows.pending_plan_links.append((entity_id, source_doc, line, match.group(1)))


def _resolve_links(rows: GraphRows) -> None:
    doc_targets: dict[str, str] = {}
    plan_targets: dict[str, str] = {}
    commits = {entity.id: entity.source_commit for entity in rows.entities.values()}
    for entity in rows.entities.values():
        if entity.etype in {"DOCUMENT", "PLAN"}:
            doc_targets[entity.source_doc.lower()] = entity.id
            doc_targets[Path(entity.source_doc).name.lower()] = entity.id
        if entity.etype == "PLAN":
            match = re.match(r"plan:(\d+)-", entity.id)
            if match:
                plan_targets[match.group(1)] = entity.id
    for src_id, source_doc, line, raw_target in rows.pending_doc_links:
        if re.match(r"^[a-z]+://", raw_target, re.I):
            continue
        cleaned = raw_target.split("#", 1)[0].replace("%20", " ")
        candidate = (Path(source_doc).parent / cleaned).as_posix()
        target = doc_targets.get(candidate.lower()) or doc_targets.get(Path(cleaned).name.lower())
        if target and target != src_id:
            rows.add_relation(
                Relation(src_id, target, "references", source_doc, line, commits[src_id])
            )
    for src_id, source_doc, line, number in rows.pending_plan_links:
        target = plan_targets.get(number)
        if target and target != src_id:
            rows.add_relation(
                Relation(src_id, target, "references", source_doc, line, commits[src_id])
            )


def _write_database(
    runtime: Runtime,
    rows: GraphRows,
    *,
    built_at: str,
    fingerprint: str,
) -> None:
    runtime.state_dir.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".graph.", suffix=".db", dir=str(runtime.state_dir)
    )
    os.close(descriptor)
    os.unlink(temporary_name)
    connection = sqlite3.connect(temporary_name)
    try:
        connection.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
        connection.executemany(
            "INSERT INTO entities VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            [entity.row() for entity in sorted(rows.entities.values(), key=lambda row: row.id)],
        )
        connection.executemany(
            "INSERT INTO relations VALUES (?,?,?,?,?,?)",
            [relation.row() for relation in sorted(rows.relations, key=lambda row: row.row())],
        )
        connection.executemany(
            "INSERT INTO aliases VALUES (?,?,?)",
            [
                (alias, entity_id, weight)
                for (alias, entity_id), weight in sorted(rows.aliases.items())
            ],
        )
        connection.executemany(
            "INSERT INTO entity_fts(entity_id,name,body,source_doc) VALUES (?,?,?,?)",
            [
                (entity.id, entity.name, entity.body, entity.source_doc)
                for entity in sorted(rows.entities.values(), key=lambda row: row.id)
            ],
        )
        connection.executemany(
            "INSERT INTO metadata(key,value) VALUES (?,?)",
            [
                ("tool_version", str(TOOL_VERSION)),
                ("implementation_sha256", _implementation_sha256()),
                ("config_sha256", runtime.config_sha256),
                ("fingerprint", fingerprint),
                ("built_at", built_at),
            ],
        )
        connection.commit()
    finally:
        connection.close()
    os.replace(temporary_name, runtime.db_path)


def _atomic_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(".{}.{}.tmp".format(path.name, os.getpid()))
    try:
        temporary.write_text(_canonical_json(value) + "\n", encoding="utf-8")
        os.replace(temporary, path)
    finally:
        with contextlib.suppress(FileNotFoundError):
            temporary.unlink()


def build_graph(
    runtime: Runtime,
    *,
    files: list[SourceFile] | None = None,
    source_counts: dict[str, int] | None = None,
) -> BuildReport:
    started = time.perf_counter()
    if files is None or source_counts is None:
        files, source_counts = collect_sources(runtime)
    inventory = _inventory(files, hashes=True)
    fingerprint_payload = {
        "tool_version": TOOL_VERSION,
        "implementation_sha256": _implementation_sha256(),
        "config_sha256": runtime.config_sha256,
        "files": {
            path: {
                "source": row["source"],
                "adapter": row["adapter"],
                "sha256": row["sha256"],
            }
            for path, row in inventory.items()
        },
    }
    fingerprint = hashlib.sha256(
        _canonical_json(fingerprint_payload).encode("utf-8")
    ).hexdigest()
    built_at = dt.datetime.now(dt.timezone.utc).isoformat()
    rows = GraphRows()
    skipped: list[tuple[str, str]] = []
    head, dirty = _provenance(runtime.root)
    sources_by_name = {
        str(source["name"]): source
        for source in runtime.config["sources"]
        if source.get("enabled", True) is not False
    }
    files_by_source: dict[str, list[SourceFile]] = {}
    for item in files:
        files_by_source.setdefault(item.source_name, []).append(item)
    for name, source in sources_by_name.items():
        source_files = files_by_source.get(name, [])
        if source["adapter"] == "project_memory_plans":
            _ingest_plan_source(runtime, source, source_files, rows, built_at=built_at)
    max_bytes = int(runtime.config["documents"].get("max_file_bytes", 2_500_000))
    chunk_chars = int(runtime.config["documents"].get("section_chunk_chars", 12_000))
    for item in files:
        if item.adapter != "markdown_sections":
            continue
        _ingest_markdown_file(
            item,
            rows,
            head=head,
            dirty=dirty,
            built_at=built_at,
            max_bytes=max_bytes,
            chunk_chars=chunk_chars,
            skipped=skipped,
        )
    _resolve_links(rows)
    _write_database(runtime, rows, built_at=built_at, fingerprint=fingerprint)
    manifest = {
        "schema_version": 1,
        "tool_version": TOOL_VERSION,
        "implementation_sha256": _implementation_sha256(),
        "config_sha256": runtime.config_sha256,
        "config_path": _source_relative(runtime.config_path, runtime.root),
        "built_at": built_at,
        "fingerprint": fingerprint,
        "files": inventory,
        "source_counts": source_counts,
        "graph": {
            "entities": len(rows.entities),
            "relations": len(rows.relations),
            "aliases": len(rows.aliases),
        },
        "skipped": [{"path": path, "reason": reason} for path, reason in skipped],
    }
    _atomic_json(runtime.manifest_path, manifest)
    return BuildReport(
        source_counts=source_counts,
        skipped=skipped,
        entities=len(rows.entities),
        relations=len(rows.relations),
        aliases=len(rows.aliases),
        duration_ms=(time.perf_counter() - started) * 1000,
        fingerprint=fingerprint,
    )


def ensure_fresh(
    runtime: Runtime,
    *,
    force: bool = False,
    verify_content: bool = False,
) -> tuple[bool, BuildReport | None, float]:
    started = time.perf_counter()
    runtime.state_dir.mkdir(parents=True, exist_ok=True)
    lock_path = runtime.state_dir / "refresh.lock"
    with lock_path.open("a+", encoding="utf-8") as lock_handle:
        if fcntl is not None:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        fresh, _reasons, files, counts = freshness(
            runtime, verify_content=verify_content
        )
        report = None if fresh and not force else build_graph(
            runtime, files=files, source_counts=counts
        )
        if fcntl is not None:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
    return report is not None, report, (time.perf_counter() - started) * 1000


def _connect_readonly(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect("file:{}?mode=ro".format(path), uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def token_count(text: str) -> int:
    return int(math.ceil(len(text) / float(CHARS_PER_TOKEN)))


def tokenize(question: str) -> list[str]:
    result: list[str] = []
    for word in WORD.findall(question):
        token = word.strip("./-_").lower()
        if not token or token in STOPWORDS or token in result:
            continue
        result.append(token)
    return result


def _probes(question: str, terms: list[str]) -> list[str]:
    result: set[str] = set(terms)
    for term in terms:
        for part in re.split(r"[-_/]+", term):
            if len(part) >= 4:
                result.add(part)
    for left, right in zip(terms, terms[1:]):
        result.add("{} {}".format(left, right))
        result.add("{}-{}".format(left, right))
    normalized = normalize_alias(question)
    if len(normalized) <= 160:
        result.add(normalized)
    return sorted(value for value in result if value)


def _fts_query(terms: list[str]) -> str:
    values: list[str] = []
    for term in terms[:16]:
        pieces = [piece for piece in re.split(r"[^a-z0-9_]+", term) if len(piece) >= 2]
        for piece in pieces:
            escaped = piece.replace('"', '""')
            value = '"{}"'.format(escaped)
            if value not in values:
                values.append(value)
    return " OR ".join(values)


def _entity_rows(connection: sqlite3.Connection, ids: Iterable[str]) -> dict[str, sqlite3.Row]:
    values = sorted(set(ids))
    if not values:
        return {}
    placeholders = ",".join("?" for _ in values)
    query = "SELECT * FROM entities WHERE id IN ({})".format(placeholders)
    return {str(row["id"]): row for row in connection.execute(query, values)}


def _candidate_ids(
    connection: sqlite3.Connection,
    question: str,
    terms: list[str],
    retrieval: dict[str, Any],
) -> tuple[dict[str, dict[str, Any]], set[str]]:
    candidates: dict[str, dict[str, Any]] = {}
    exact: set[str] = set()
    probes = _probes(question, terms)
    if probes:
        placeholders = ",".join("?" for _ in probes)
        sql = (
            "SELECT entity_id, SUM(weight) AS score, COUNT(DISTINCT alias) AS matches "
            "FROM aliases WHERE alias IN ({}) GROUP BY entity_id"
        ).format(placeholders)
        for row in connection.execute(sql, probes):
            candidates[str(row[0])] = {
                "alias_score": float(row[1]),
                "alias_matches": int(row[2]),
                "fts_order": 10_000,
            }
    fts = _fts_query(terms)
    if fts:
        try:
            rows = connection.execute(
                "SELECT entity_id, bm25(entity_fts,0.0,8.0,1.0,4.0) AS rank "
                "FROM entity_fts WHERE entity_fts MATCH ? ORDER BY rank, entity_id LIMIT ?",
                (fts, int(retrieval.get("fts_candidates", 80))),
            )
            for order, row in enumerate(rows):
                item = candidates.setdefault(
                    str(row[0]),
                    {"alias_score": 0.0, "alias_matches": 0, "fts_order": 10_000},
                )
                item["fts_order"] = min(int(item["fts_order"]), order)
        except sqlite3.OperationalError:
            pass
    plan_numbers = PLAN_REFERENCE.findall(question)
    for number in plan_numbers:
        for row in connection.execute(
            "SELECT id FROM entities WHERE etype='PLAN' AND id LIKE ? ORDER BY id",
            ("plan:{}-%".format(number),),
        ):
            entity_id = str(row[0])
            candidates.setdefault(
                entity_id,
                {"alias_score": 0.0, "alias_matches": 0, "fts_order": 10_000},
            )["exact"] = "plan"
            exact.add(entity_id)
    for path_token in re.findall(r"[^\s\"']+\.md", question, re.I):
        basename = Path(path_token.strip("`(),")).name.lower()
        for row in connection.execute(
            "SELECT id FROM entities WHERE lower(source_doc) LIKE ? ORDER BY id LIMIT 20",
            ("%{}".format(basename),),
        ):
            entity_id = str(row[0])
            candidates.setdefault(
                entity_id,
                {"alias_score": 0.0, "alias_matches": 0, "fts_order": 10_000},
            )["exact"] = "path"
            exact.add(entity_id)
    return candidates, exact


def _term_matches(row: sqlite3.Row, terms: list[str]) -> tuple[set[str], set[str]]:
    name_text = "{} {} {} {}".format(
        row["name"], row["source_doc"], row["status"], row["status_raw"]
    ).lower()
    body_text = str(row["body"]).lower()
    name_hits = {term for term in terms if term in name_text}
    body_hits = {term for term in terms if term in body_text}
    return name_hits, body_hits


def _candidate_score(
    row: sqlite3.Row,
    meta: dict[str, Any],
    terms: list[str],
) -> tuple[float, set[str]]:
    name_hits, body_hits = _term_matches(row, terms)
    hits = name_hits | body_hits
    score = float(meta.get("alias_score", 0.0)) * 2.5
    score += float(meta.get("alias_matches", 0)) * 12
    score += len(name_hits) * 28 + len(body_hits) * 8
    # Prefer one passage that covers the question over several entities that
    # merely repeat a generic title token (for example, many "project-memory"
    # plans versus the one guide section explaining why graphs stay separate).
    score += (len(hits) / float(max(1, len(terms)))) * 120
    score += sum(8 for term in hits if len(term) >= 10)
    order = int(meta.get("fts_order", 10_000))
    if order < 10_000:
        score += max(0, 32 - min(order, 32))
    score += int(row["priority"]) / 10.0
    if meta.get("exact"):
        score += 1000
    if row["etype"] in {"PLAN", "FINDING", "GAP"}:
        score += 12
    return score, hits


def _clean_body(value: str) -> str:
    value = re.sub(r"```.*?```", " ", value, flags=re.S)
    value = re.sub(r"<!--.*?-->", " ", value, flags=re.S)
    value = MARKDOWN_DECORATION.sub("", value)
    value = value.replace("|", " ").replace("#", " ")
    return SPACE.sub(" ", value).strip()


def _snippet(body: str, terms: list[str], limit: int) -> str:
    text = _clean_body(body)
    if not text:
        return ""
    lowered = text.lower()
    positions = [lowered.find(term) for term in terms if lowered.find(term) >= 0]
    center = min(positions) if positions else 0
    start = max(0, center - limit // 3)
    end = min(len(text), start + limit)
    if start:
        boundary = text.find(" ", start)
        start = boundary + 1 if 0 <= boundary < end else start
    if end < len(text):
        boundary = text.rfind(" ", start, end)
        end = boundary if boundary > start else end
    value = text[start:end].strip()
    return ("…" if start else "") + value + ("…" if end < len(text) else "")


def _provenance_text(row: sqlite3.Row) -> str:
    start = int(row["source_line"])
    end = int(row["source_end_line"])
    lines = str(start) if end <= start else "{}-{}".format(start, end)
    return "{}:{} @{}".format(row["source_doc"], lines, row["source_commit"])


def _entity_fact(row: sqlite3.Row, terms: list[str], snippet_chars: int) -> str:
    etype = str(row["etype"])
    if etype == "PLAN":
        return "PLAN {} [{}] — {}".format(row["name"], row["status"], _provenance_text(row))
    if etype in {"FINDING", "GAP", "MEMORY", "NOTE"}:
        return "{} [{}] {} — {}".format(
            etype, row["status"], row["name"], _provenance_text(row)
        )
    snippet = _snippet(str(row["body"]), terms, snippet_chars)
    prefix = "{} [{}] {}".format(etype, row["status"], row["name"])
    if snippet:
        prefix += " — {}".format(snippet)
    return "{} — {}".format(prefix, _provenance_text(row))


def _relation_facts(
    connection: sqlite3.Connection,
    selected: list[sqlite3.Row],
    terms: list[str],
    edges_per_seed: int,
    max_hops: int,
) -> dict[str, list[str]]:
    ids = [str(row["id"]) for row in selected]
    if not ids or edges_per_seed <= 0 or max_hops <= 0:
        return {}
    if max_hops == 1:
        placeholders = ",".join("?" for _ in ids)
        sql = (
            "SELECT src_id,dst_id,rtype,source_doc,source_line,source_commit "
            "FROM relations WHERE src_id IN ({0}) OR dst_id IN ({0})"
        ).format(placeholders)
        edges = list(connection.execute(sql, [*ids, *ids]))
        origins = {
            entity_id: [
                edge for edge in edges if entity_id in {str(edge[0]), str(edge[1])}
            ]
            for entity_id in ids
        }
    else:
        edges = list(
            connection.execute(
                "SELECT src_id,dst_id,rtype,source_doc,source_line,source_commit FROM relations"
            )
        )
        adjacency: dict[str, list[sqlite3.Row]] = {}
        for edge in edges:
            adjacency.setdefault(str(edge[0]), []).append(edge)
            adjacency.setdefault(str(edge[1]), []).append(edge)
        origins: dict[str, list[sqlite3.Row]] = {}
        for origin in ids:
            visited = {origin}
            frontier = {origin}
            reached_edges: list[sqlite3.Row] = []
            for _hop in range(min(max_hops, 2)):
                next_frontier: set[str] = set()
                for node in sorted(frontier):
                    for edge in adjacency.get(node, []):
                        reached_edges.append(edge)
                        neighbor = str(edge[1]) if str(edge[0]) == node else str(edge[0])
                        if neighbor not in visited:
                            next_frontier.add(neighbor)
                visited.update(next_frontier)
                frontier = next_frontier
            origins[origin] = reached_edges
    endpoint_ids = {str(row[0]) for row in edges} | {str(row[1]) for row in edges}
    entities = _entity_rows(connection, endpoint_ids)
    grouped: dict[str, list[tuple[int, str]]] = {}
    for origin, origin_edges in origins.items():
        for edge in origin_edges:
            src_id, dst_id, rtype, doc, line, commit = edge
            if rtype == "contains":
                continue
            src = entities.get(str(src_id))
            dst = entities.get(str(dst_id))
            if src is None or dst is None:
                continue
            text = "{} {} {}".format(src["name"], dst["name"], rtype).lower()
            relevance = sum(1 for term in terms if term in text)
            fact = "{} [{}] --{}--> {} [{}] — {}:{} @{}".format(
                src["name"], src["status"], rtype, dst["name"], dst["status"], doc, line, commit
            )
            grouped.setdefault(origin, []).append((relevance, fact))
    result: dict[str, list[str]] = {}
    for entity_id, values in grouped.items():
        ordered = sorted(values, key=lambda item: (-item[0], item[1]))
        result[entity_id] = [value for _score, value in ordered[:edges_per_seed]]
    return result


def recall(runtime: Runtime, question: str, *, budget: int | None = None) -> RecallResult:
    retrieval = runtime.config["retrieval"]
    requested = int(budget if budget is not None else retrieval["default_budget"])
    limit = min(max(50, requested), int(retrieval["hard_cap"]))
    terms = tokenize(question)
    if not terms:
        output = "No Codex-memory facts found: no searchable terms"
        return RecallResult(output, False, "miss", 0, 0, 0, 0, False, token_count(output))
    with _connect_readonly(runtime.db_path) as connection:
        candidate_meta, exact_ids = _candidate_ids(connection, question, terms, retrieval)
        entity_map = _entity_rows(connection, candidate_meta)
        required_ids = {
            entity_id
            for entity_id, meta in candidate_meta.items()
            if meta.get("exact") == "plan"
        }
        ranked: list[tuple[float, str, set[str], sqlite3.Row]] = []
        for entity_id, row in entity_map.items():
            # Explicit plan anchors are a complete routing instruction. Their
            # own structured edges provide findings/gaps/supersession; unrelated
            # FTS matches only spend budget and can hide one of several plans.
            if required_ids and entity_id not in required_ids:
                continue
            score, hits = _candidate_score(row, candidate_meta[entity_id], terms)
            if hits or entity_id in exact_ids:
                ranked.append((score, entity_id, hits, row))
        ranked.sort(key=lambda item: (-item[0], item[1]))
        selected: list[sqlite3.Row] = []
        selected_hits: dict[str, set[str]] = {}
        per_doc: dict[str, int] = {}
        max_seeds = int(retrieval.get("max_seeds", 12))
        max_per_doc = int(retrieval.get("max_facts_per_document", 2))
        for _score, entity_id, hits, row in ranked:
            if len(selected) >= max_seeds and entity_id not in required_ids:
                continue
            doc = str(row["source_doc"])
            structured = row["etype"] in {"PLAN", "FINDING", "GAP", "MEMORY", "NOTE"}
            if not structured and per_doc.get(doc, 0) >= max_per_doc and entity_id not in required_ids:
                continue
            selected.append(row)
            selected_hits[entity_id] = hits
            per_doc[doc] = per_doc.get(doc, 0) + 1
            if len(selected) >= max_seeds and required_ids.issubset(
                {str(value["id"]) for value in selected}
            ):
                break
        if not selected:
            output = "No Codex-memory facts found for: {}".format(" ".join(terms))
            return RecallResult(
                output, False, "miss", 0, len(terms), 0, 0, False, token_count(output)
            )
        answer_selected: list[sqlite3.Row] = []
        answer_hits: set[str] = set()
        for row in selected:
            answer_selected.append(row)
            answer_hits.update(selected_hits.get(str(row["id"]), set()))
            if required_ids:
                if required_ids.issubset({str(value["id"]) for value in answer_selected}):
                    break
                continue
            coverage_so_far = len(answer_hits) / float(len(terms))
            if coverage_so_far >= 0.80 or (
                coverage_so_far >= 0.70 and len(answer_selected) >= 2
            ) or len(answer_selected) >= 4:
                break
        relation_intent = {
            "refuted", "refutes", "finding", "superseded", "supersedes",
            "deferred", "owner", "references", "relationship", "rationale",
        }
        status_intent = {
            "status", "state", "executed", "planning-only", "closed", "open",
            "complete", "completed", "landed",
        }
        edge_limit = int(retrieval.get("edges_per_seed", 2))
        if (
            required_ids
            and status_intent.intersection(terms)
            and not relation_intent.intersection(terms)
            and not re.search(r"\b(?:why|how)\b", question, re.I)
        ):
            edge_limit = 0
        relation_facts = _relation_facts(
            connection,
            answer_selected,
            terms,
            edge_limit,
            int(retrieval.get("max_hops", 1)),
        )
        facts: list[str] = []
        seen: set[str] = set()
        # Entity breadth comes first. In a multi-anchor question (for example,
        # five explicit plan numbers), every requested entity must be visible
        # before one plan's relationship tail consumes the budget.
        for row in answer_selected:
            fact = _entity_fact(row, terms, int(retrieval.get("snippet_chars", 320)))
            if fact not in seen:
                facts.append(fact)
                seen.add(fact)
        for row in answer_selected:
            for edge in relation_facts.get(str(row["id"]), []):
                if edge not in seen:
                    facts.append(edge)
                    seen.add(edge)
    matched = set().union(
        *(selected_hits[str(row["id"])] for row in answer_selected)
    ) if answer_selected else set()
    coverage = len(matched) / float(len(terms))
    anchored = any(
        candidate_meta.get(str(row["id"]), {}).get("exact")
        for row in answer_selected
    )
    if anchored and coverage >= 0.50:
        confidence = "exact"
    elif coverage >= 0.55 and len(matched) >= 2:
        confidence = "focused"
    else:
        confidence = "broad"
    source_docs = len({str(row["source_doc"]) for row in answer_selected})
    header = "Codex memory: confidence={} · coverage={}/{} · docs={}".format(
        confidence, len(matched), len(terms), source_docs
    )
    kept = [header]
    used = token_count(header) + 1
    truncated = False
    for index, fact in enumerate(facts):
        cost = token_count(fact) + 1
        if used + cost > limit:
            truncated = True
            notice = "... truncated at {} tokens; {} facts omitted".format(
                limit, len(facts) - index
            )
            if used + token_count(notice) + 1 <= limit:
                kept.append(notice)
            break
        kept.append("- " + fact)
        used += cost
    output = "\n".join(kept)
    return RecallResult(
        output=output,
        hit=True,
        confidence=confidence,
        matched_terms=len(matched),
        query_terms=len(terms),
        selected_entities=len(answer_selected),
        source_documents=source_docs,
        truncated=truncated,
        tokens=token_count(output),
    )


def session_digest(value: str | None) -> str:
    if not value:
        return "unknown"
    return hashlib.sha256(value.encode("utf-8", errors="replace")).hexdigest()[:16]


def _append_jsonl(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = (_canonical_json(value) + "\n").encode("utf-8")
    descriptor = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
    try:
        os.write(descriptor, data)
    finally:
        os.close(descriptor)


def log_query(
    runtime: Runtime,
    question: str,
    budget: int,
    result: RecallResult,
    *,
    duration_ms: float,
    refreshed: bool,
    refresh_ms: float,
) -> None:
    if os.environ.get("CODEX_MEMORY_TELEMETRY", "1").strip().lower() in {
        "0", "false", "no", "off"
    }:
        return
    manifest = _read_manifest(runtime.manifest_path) or {}
    record: dict[str, Any] = {
        "schema_version": 1,
        "ts": dt.datetime.now(dt.timezone.utc).isoformat(),
        "operation": "query",
        "question_sha256": hashlib.sha256(question.encode("utf-8")).hexdigest()[:16],
        "codex_session_sha256": session_digest(os.environ.get("CODEX_SESSION_ID")),
        "codex_thread_sha256": session_digest(os.environ.get("CODEX_THREAD_ID")),
        "budget": budget,
        "tokens": result.tokens,
        "hit": result.hit,
        "confidence": result.confidence,
        "matched_terms": result.matched_terms,
        "query_terms": result.query_terms,
        "coverage": round(
            result.matched_terms / float(max(1, result.query_terms)), 3
        ),
        "selected_entities": result.selected_entities,
        "source_documents": result.source_documents,
        "truncated": result.truncated,
        "duration_ms": round(duration_ms, 2),
        "auto_refreshed": refreshed,
        "refresh_ms": round(refresh_ms, 2),
        "graph_fingerprint": str(manifest.get("fingerprint", ""))[:16],
    }
    _append_jsonl(runtime.telemetry_path, record)


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    try:
        with path.open(encoding="utf-8") as handle:
            for line in handle:
                try:
                    value = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(value, dict):
                    rows.append(value)
    except OSError:
        pass
    return rows


def _p95(values: list[float]) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, int(math.ceil(len(ordered) * 0.95)) - 1)
    return float(ordered[index])


def stats(runtime: Runtime, *, selector: str = "current", days: int = 30) -> dict[str, Any]:
    usage = _read_jsonl(runtime.telemetry_path)
    events = _read_jsonl(runtime.hook_events_path)
    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=max(1, days))

    def recent(row: dict[str, Any]) -> bool:
        try:
            timestamp = dt.datetime.fromisoformat(str(row.get("ts", "")))
            if timestamp.tzinfo is None:
                timestamp = timestamp.replace(tzinfo=dt.timezone.utc)
            return timestamp >= cutoff
        except ValueError:
            return False

    usage = [row for row in usage if recent(row)]
    events = [row for row in events if recent(row)]
    if selector == "current":
        selected_digest = session_digest(os.environ.get("CODEX_SESSION_ID"))
    elif selector == "latest":
        selected_digest = str(usage[-1].get("codex_session_sha256")) if usage else "unknown"
    elif selector == "all":
        selected_digest = "all"
    else:
        selected_digest = selector
    if selected_digest != "all":
        usage = [row for row in usage if row.get("codex_session_sha256") == selected_digest]
        events = [row for row in events if row.get("codex_session_sha256") == selected_digest]
    hits = sum(bool(row.get("hit")) for row in usage)
    broad = sum(row.get("confidence") == "broad" for row in usage)
    doc_browses = [row for row in events if row.get("event") == "document_browse"]
    doc_reads = [row for row in events if row.get("event") == "document_read"]
    grounded_browses = sum(bool(row.get("grounded")) for row in doc_browses)
    return {
        "session": selected_digest,
        "window_days": days,
        "queries": len(usage),
        "hits": hits,
        "misses": len(usage) - hits,
        "broad_results": broad,
        "average_tokens": round(
            sum(float(row.get("tokens", 0)) for row in usage) / max(1, len(usage)), 1
        ),
        "average_coverage": round(
            sum(float(row.get("coverage", 0)) for row in usage) / max(1, len(usage)), 3
        ),
        "p95_duration_ms": round(
            _p95([float(row.get("duration_ms", 0)) for row in usage]), 2
        ),
        "auto_refreshes": sum(bool(row.get("auto_refreshed")) for row in usage),
        "broad_document_browses": len(doc_browses),
        "grounded_document_browses": grounded_browses,
        "ungrounded_document_browses": len(doc_browses) - grounded_browses,
        "reminders": sum(bool(row.get("reminder")) for row in doc_browses),
        "document_read_calls": len(doc_reads),
        "documents_read": sum(int(row.get("documents", 0)) for row in doc_reads),
        "whole_documents_read": sum(int(row.get("whole_documents", 0)) for row in doc_reads),
        "estimated_document_read_tokens": sum(
            int(row.get("estimated_tokens", 0)) for row in doc_reads
        ),
    }


def _render_stats(value: dict[str, Any]) -> str:
    return (
        "Codex memory usage ({session}, {window_days}d): {queries} queries · "
        "{hits} hit · {broad_results} broad · {average_tokens} avg tokens · "
        "{average_coverage} avg coverage · {p95_duration_ms} ms p95\n"
        "Document sweeps: {broad_document_browses} broad · "
        "{grounded_document_browses} grounded · {ungrounded_document_browses} "
        "ungrounded · {reminders} reminders · {auto_refreshes} auto-refreshes\n"
        "Document reads: {document_read_calls} calls · {documents_read} documents · "
        "{whole_documents_read} whole · ~{estimated_document_read_tokens} input tokens"
    ).format(**value)


def benchmark(runtime: Runtime, *, budget: int | None = None) -> tuple[bool, str]:
    ensure_fresh(runtime)
    evaluation = runtime.config.get("evaluation", {})
    cases: list[dict[str, Any]] = []
    plan_path = _absolute(runtime.root, evaluation.get("plan_questions", ""))
    if plan_path.exists():
        value = json.loads(plan_path.read_text(encoding="utf-8"))
        plan_rows = value.get("questions", []) if isinstance(value, dict) else []
        cases.extend(row for row in plan_rows if row.get("v1_scope"))
    document_path = _absolute(runtime.root, evaluation.get("document_questions", ""))
    if document_path.exists():
        value = json.loads(document_path.read_text(encoding="utf-8"))
        doc_rows = value.get("questions", []) if isinstance(value, dict) else []
        cases.extend(doc_rows)
    results: list[tuple[str, bool, int, float, list[str]]] = []
    for case in cases:
        started = time.perf_counter()
        result = recall(runtime, str(case["query"]), budget=budget)
        elapsed = (time.perf_counter() - started) * 1000
        lowered = result.output.lower()
        required = [str(value) for value in case.get("required", [])]
        if case.get("source"):
            required.append(str(case["source"]))
        missing = [value for value in required if value.lower() not in lowered]
        results.append((str(case.get("id", "?")), not missing, result.tokens, elapsed, missing))
    lines = ["case  pass  tokens  ms  missing"]
    for case_id, passed, tokens, elapsed, missing in results:
        lines.append(
            "{:<5} {:<5} {:>6} {:>6.1f}  {}".format(
                case_id, "yes" if passed else "NO", tokens, elapsed, ", ".join(missing)
            )
        )
    passed_count = sum(row[1] for row in results)
    lines.append(
        "gate: {}/{} · avg tokens {:.1f} · p95 {:.1f} ms".format(
            passed_count,
            len(results),
            sum(row[2] for row in results) / max(1, len(results)),
            _p95([row[3] for row in results]),
        )
    )
    return passed_count == len(results), "\n".join(lines)


def _status(runtime: Runtime, *, verify_content: bool) -> dict[str, Any]:
    fresh, reasons, files, counts = freshness(runtime, verify_content=verify_content)
    manifest = _read_manifest(runtime.manifest_path) or {}
    return {
        "fresh": fresh,
        "reasons": reasons,
        "config": _source_relative(runtime.config_path, runtime.root),
        "config_sha256": runtime.config_sha256[:16],
        "database": _source_relative(runtime.db_path, runtime.root),
        "fingerprint": str(manifest.get("fingerprint", ""))[:16],
        "built_at": manifest.get("built_at"),
        "selected_files": len(files),
        "source_counts": counts or manifest.get("source_counts", {}),
        "graph": manifest.get("graph", {}),
        "freshness_check": "content" if verify_content else runtime.config["freshness"]["check"],
    }


def _render_status(value: dict[str, Any]) -> str:
    state = "fresh" if value["fresh"] else "STALE ({})".format(", ".join(value["reasons"]))
    counts = ", ".join(
        "{}={}".format(name, count)
        for name, count in sorted(value["source_counts"].items())
    )
    graph = value.get("graph", {})
    return (
        "Codex memory: {state}\n"
        "config: {config} @{config_sha256}\n"
        "database: {database} · fingerprint={fingerprint} · built={built_at}\n"
        "sources: {selected_files} files ({counts})\n"
        "graph: {entities} entities · {relations} relations · {aliases} aliases · check={check}"
    ).format(
        state=state,
        config=value["config"],
        config_sha256=value["config_sha256"],
        database=value["database"],
        fingerprint=value["fingerprint"] or "none",
        built_at=value["built_at"] or "never",
        selected_files=value["selected_files"],
        counts=counts or "none",
        entities=graph.get("entities", 0),
        relations=graph.get("relations", 0),
        aliases=graph.get("aliases", 0),
        check=value["freshness_check"],
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", default=None, help="base config; default codex-memory/config.json")
    subparsers = parser.add_subparsers(dest="command", required=True)

    query_parser = subparsers.add_parser("query", help="compact deterministic recall")
    query_parser.add_argument("question")
    query_parser.add_argument("--budget", type=int, default=None)
    query_parser.add_argument("--no-refresh", action="store_true")
    query_parser.add_argument("--ensure-fresh", action="store_true")
    query_parser.add_argument("--verify-content", action="store_true")
    query_parser.add_argument("--json", action="store_true")

    refresh_parser = subparsers.add_parser("refresh", help="refresh when stale")
    refresh_parser.add_argument("--force", action="store_true")
    refresh_parser.add_argument("--verify-content", action="store_true")

    status_parser = subparsers.add_parser("status", help="show corpus and freshness")
    status_parser.add_argument("--verify-content", action="store_true")
    status_parser.add_argument("--json", action="store_true")

    stats_parser = subparsers.add_parser("stats", help="usage and adoption metrics")
    stats_parser.add_argument("--session", default="current", help="current, latest, all, or hash")
    stats_parser.add_argument("--days", type=int, default=30)
    stats_parser.add_argument("--json", action="store_true")

    benchmark_parser = subparsers.add_parser("benchmark", help="run plan + document recall gates")
    benchmark_parser.add_argument("--budget", type=int, default=None)

    statusline_parser = subparsers.add_parser("statusline", help="one-line UTC-day usage fragment")
    statusline_parser.add_argument("--today", default=None)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        runtime = load_runtime(args.config)
        if args.command == "refresh":
            refreshed, report, _elapsed = ensure_fresh(
                runtime, force=args.force, verify_content=args.verify_content
            )
            print(report.render() if refreshed and report else "Codex memory already fresh")
            return 0
        if args.command == "status":
            value = _status(runtime, verify_content=args.verify_content)
            print(json.dumps(value, indent=2, sort_keys=True) if args.json else _render_status(value))
            return 0 if value["fresh"] else 1
        if args.command == "stats":
            value = stats(runtime, selector=args.session, days=args.days)
            print(json.dumps(value, indent=2, sort_keys=True) if args.json else _render_stats(value))
            return 0
        if args.command == "statusline":
            today = args.today or dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")
            rows = [
                row for row in _read_jsonl(runtime.telemetry_path)
                if str(row.get("ts", ""))[:10] == today
            ]
            if runtime.telemetry_path.exists():
                hits = sum(bool(row.get("hit")) for row in rows)
                broad = sum(row.get("confidence") == "broad" for row in rows)
                print("cmem {} ({} hit · {} broad)".format(len(rows), hits, broad))
            return 0
        if args.command == "benchmark":
            passed, output = benchmark(runtime, budget=args.budget)
            print(output)
            return 0 if passed else 1
        if args.command == "query":
            refresh_ms = 0.0
            refreshed = False
            auto = bool(runtime.config["freshness"].get("auto_refresh", True))
            if not args.no_refresh and (auto or args.ensure_fresh):
                refreshed, _report, refresh_ms = ensure_fresh(
                    runtime, verify_content=args.verify_content
                )
            elif not runtime.db_path.exists():
                print("FAIL: database missing; run `python3 codex-memory/memory.py refresh`", file=sys.stderr)
                return 2
            started = time.perf_counter()
            result = recall(runtime, args.question, budget=args.budget)
            elapsed = (time.perf_counter() - started) * 1000
            requested_budget = int(
                args.budget if args.budget is not None else runtime.config["retrieval"]["default_budget"]
            )
            log_query(
                runtime,
                args.question,
                requested_budget,
                result,
                duration_ms=elapsed,
                refreshed=refreshed,
                refresh_ms=refresh_ms,
            )
            if args.json:
                value = dataclasses.asdict(result)
                value["auto_refreshed"] = refreshed
                value["refresh_ms"] = round(refresh_ms, 2)
                print(json.dumps(value, indent=2, sort_keys=True))
            else:
                print(result.output)
            return 0
    except (OSError, sqlite3.Error, ValueError, RuntimeError) as exc:
        print("FAIL: {}".format(exc), file=sys.stderr)
        return 2
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
