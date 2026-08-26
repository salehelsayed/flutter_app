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
from collections import Counter
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


def _privacy_identity(value: Any) -> str | None:
    if value is None:
        return None
    candidate = str(value).strip().lower()
    if not candidate:
        return None
    if candidate == "root":
        return candidate
    if re.fullmatch(r"[0-9a-f]{16,64}", candidate):
        return candidate
    return hashlib.sha256(candidate.encode("utf-8", errors="replace")).hexdigest()[:16]


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
    session_sha256: str | None = None,
    thread_sha256: str | None = None,
    agent_sha256: str | None = None,
    trigger: str = "cli",
    opportunity_sha256: str | None = None,
    raw_read_intent_sha256: str | None = None,
    policy_version: int | None = None,
    mode: str | None = None,
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
        "codex_session_sha256": (
            _privacy_identity(session_sha256)
            if session_sha256 is not None
            else session_digest(os.environ.get("CODEX_SESSION_ID"))
        )
        or "unknown",
        "codex_thread_sha256": (
            _privacy_identity(thread_sha256)
            if thread_sha256 is not None
            else session_digest(os.environ.get("CODEX_THREAD_ID"))
        )
        or "unknown",
        "trigger": (
            str(trigger).strip().lower()
            if str(trigger).strip().lower()
            in {"cli", "pre_tool_use", "repeat_guard", "secondary_preflight"}
            else "unknown"
        ),
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
    if agent_sha256:
        record["agent_sha256"] = _privacy_identity(agent_sha256) or "unknown"
    if opportunity_sha256:
        candidate = str(opportunity_sha256).strip().lower()
        if not re.fullmatch(r"[0-9a-f]{16,64}", candidate):
            candidate = hashlib.sha256(
                candidate.encode("utf-8", errors="replace")
            ).hexdigest()[:16]
        record["opportunity_sha256"] = candidate
    if raw_read_intent_sha256:
        candidate = str(raw_read_intent_sha256).strip().lower()
        if not re.fullmatch(r"[0-9a-f]{16,64}", candidate):
            candidate = hashlib.sha256(
                candidate.encode("utf-8", errors="replace")
            ).hexdigest()[:16]
        record["raw_read_intent_sha256"] = candidate
    if policy_version is not None:
        try:
            record["policy_version"] = int(policy_version)
        except (TypeError, ValueError, OverflowError):
            record["policy_version"] = "unknown"
    if mode is not None:
        normalized_mode = str(mode).strip().lower()
        record["mode"] = (
            normalized_mode
            if normalized_mode in {"off", "shadow", "inject", "enforce"}
            else "unknown"
        )
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


_OPPORTUNITY_EVENTS = {
    "retrieval_opportunity",
    "retrieval-opportunity",
}
_FOLLOWUP_EVENTS = {
    "retrieval_followup",
    "retrieval_follow_up",
    "retrieval-opportunity-followup",
}
_OPPORTUNITY_KINDS = {
    "broad_sweep",
    "primary_read",
    "secondary_read",
    "repeat_read",
}
_RECALL_OUTCOMES = {
    "focused_hit",
    "broad_hit",
    "miss",
    "error",
    "provenance_mismatch",
    "disabled",
    "cached_hit",
    "not_attempted",
}
_OPPORTUNITY_ACTIONS = {"allow", "inject", "deny", "fail_open", "exempt"}
_OPPORTUNITY_MODES = {"off", "shadow", "inject", "enforce"}
_FOLLOWUP_OUTCOMES = {
    "targeted_window",
    "targeted_search",
    "whole_read",
    "primary_bypass",
    "changed",
    "timeout",
    "abandoned",
}
_COSTED_FOLLOWUP_OUTCOMES = {
    "targeted_window",
    "targeted_search",
    "whole_read",
    "primary_bypass",
}

_ROLLOVER_EVENTS = {
    "checkpoint_saved",
    "checkpoint_advisory_reset_requested",
    "precompact_allowed",
    "precompact_recovery_allowed",
    "precompact_blocked",
    "postcompact_observed",
    "session_resumed",
    "session_recovery_advisory",
    "terminal_after_not_ready_blocked",
    "terminal_after_not_ready",
    "user_rescue_after_terminal",
    "checkpoint_completed",
    "checkpoint_stale",
    "subagent_skipped",
}
_ROLLOVER_REASON_CODES = {
    "checkpoint_missing",
    "checkpoint_schema_mismatch",
    "checkpoint_age_exceeded",
    "checkpoint_already_consumed",
    "checkpoint_completed",
    "saved_at_missing",
    "plan_status_missing",
    "plan_missing",
    "plan_changed",
    "plan_outside_repo",
    "plan_too_large",
    "plan_extraction_failed",
    "plan_read_failed",
    "changed_path_outside_repo",
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
    "worktree_changed",
    "changed_path_limit_exceeded",
    "prepared_checkpoint_missing",
    "prepared_checkpoint_stale",
    "prepared_generation_mismatch",
    "subagent_rollover_unsupported",
    "rollover_intent_missing",
    "rollover_intent_stale",
    "rollover_intent_mismatch",
    "advisory_reset_requested",
}

_ROLLOVER_REPO_SCOPE_ALIASES = {
    "legacy_worktree_v1": "legacy_worktree_v1",
    "legacy_worktree": "legacy_worktree_v1",
    "whole_worktree_v1": "legacy_worktree_v1",
    "whole_worktree": "legacy_worktree_v1",
    "worktree_v1": "legacy_worktree_v1",
    "task_paths_v1": "task_paths_v1",
    "task_paths": "task_paths_v1",
    "task_scope_v1": "task_paths_v1",
    "task_scope": "task_paths_v1",
}


def _first_metric_value(row: dict[str, Any], *names: str) -> Any:
    for name in names:
        if name in row and row[name] is not None:
            return row[name]
    return None


def _metric_bool(value: Any) -> bool:
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)


def _metric_int(value: Any) -> int:
    try:
        numeric = float(value)
        if not math.isfinite(numeric):
            return 0
        return max(0, int(numeric))
    except (TypeError, ValueError, OverflowError):
        return 0


def _opportunity_digest(value: Any) -> str | None:
    if value is None:
        return None
    candidate = str(value).strip().lower()
    if not candidate:
        return None
    if re.fullmatch(r"[0-9a-f]{16,64}", candidate):
        return candidate
    return hashlib.sha256(candidate.encode("utf-8", errors="replace")).hexdigest()[:16]


def _raw_read_intent_digest(
    row: dict[str, Any], *, fallback: str | None
) -> str | None:
    """Return the v3 semantic identity, falling back for policy-v2 ledgers."""
    try:
        policy_version = int(row.get("policy_version", 0))
    except (TypeError, ValueError, OverflowError):
        policy_version = 0
    if policy_version >= 3:
        digest = _opportunity_digest(
            _first_metric_value(
                row,
                "raw_read_intent_sha256",
                "raw_intent_sha256",
                "read_intent_sha256",
            )
        )
        if digest:
            return digest
    return fallback


def _metric_category(value: Any, allowed: set[str] | None = None) -> str:
    candidate = str(value or "").strip().lower().replace("-", "_")
    if allowed is not None:
        return candidate if candidate in allowed else "unknown"
    # Hook-provided exclusion reasons are enums, but keep corrupt/untrusted values
    # from turning stats output into a prompt, command, or path disclosure.
    if re.fullmatch(r"[a-z][a-z0-9_]{0,63}", candidate):
        return candidate
    return "unknown"


def _rollover_scope(row: dict[str, Any]) -> str:
    candidate = str(row.get("agent_scope") or "").strip().lower()
    return candidate if candidate in {"root", "subagent"} else "unknown"


def _rollover_event(row: dict[str, Any]) -> str:
    return _metric_category(row.get("event"), _ROLLOVER_EVENTS)


def _rollover_repo_scope(row: dict[str, Any]) -> str:
    """Normalize fixed producer aliases without ever rendering raw values."""
    raw = _first_metric_value(
        row,
        "repo_scope",
        "repository_scope_mode",
        "repository_scope",
        "validation_scope",
    )
    if raw is None:
        # Events written before scoped validation used the whole-worktree
        # fingerprint. Treating them as legacy preserves historical adoption
        # counts without trusting a missing field as task-scoped validation.
        return "legacy_worktree_v1"
    candidate = str(raw).strip().lower().replace("-", "_")
    return _ROLLOVER_REPO_SCOPE_ALIASES.get(candidate, "unknown")


def _rollover_task_path_count(row: dict[str, Any]) -> int:
    return _metric_int(
        _first_metric_value(
            row,
            "task_path_count",
            "task_scope_path_count",
            "scoped_path_count",
            "changed_path_count",
        )
    )


def _rollover_task_scope_complete(row: dict[str, Any]) -> bool:
    value = _first_metric_value(
        row,
        "task_scope_complete",
        "repository_scope_complete",
        "scope_complete",
    )
    return value is True


def _rollover_reason_counts(rows: Iterable[dict[str, Any]]) -> dict[str, int]:
    counts: Counter[str] = Counter()
    seen: set[tuple[str, str, str, str]] = set()
    for index, row in enumerate(rows):
        raw = row.get("reason_codes")
        if raw is None:
            continue
        if not isinstance(raw, list):
            reasons = ["unknown"]
        else:
            reasons = [
                _metric_category(value, _ROLLOVER_REASON_CODES) for value in raw
            ]
        prefix = (
            _rollover_checkpoint_identity(row, index),
            str(row.get("timestamp") or row.get("ts") or "unknown"),
            _metric_category(row.get("trigger")),
        )
        for reason in reasons:
            identity = (*prefix, reason)
            if identity in seen:
                continue
            seen.add(identity)
            counts[reason] += 1
    return dict(sorted(counts.items()))


def _rollover_checkpoint_identity(row: dict[str, Any], index: int) -> str:
    session = str(row.get("codex_session_sha256") or "unknown")
    thread = str(row.get("codex_thread_sha256") or "unknown")
    generation = row.get("generation")
    if (
        re.fullmatch(r"[0-9a-f]{16,64}", session)
        and re.fullmatch(r"[0-9a-f]{16,64}", thread)
        and isinstance(generation, int)
        and not isinstance(generation, bool)
        and generation >= 0
    ):
        return "generation:{}:{}:{}".format(session, thread, generation)
    checkpoint = str(row.get("checkpoint_sha256") or "").strip().lower()
    if re.fullmatch(r"[0-9a-f]{16,64}", checkpoint):
        return "checkpoint:" + checkpoint
    # The identity remains internal to aggregation and is never rendered. A row
    # without a producer identity must not be merged with another malformed row.
    return "row:{}".format(index)


_ROLLOVER_LIVENESS_TRANSITIONS = {
    "precompact_allowed",
    "precompact_recovery_allowed",
    "postcompact_observed",
    "session_resumed",
    "session_recovery_advisory",
}


def _rollover_thread_identity(row: dict[str, Any], index: int) -> str:
    """Return a privacy-safe lane for retry correlation, never a raw ID."""
    session = str(row.get("codex_session_sha256") or "").strip().lower()
    thread = str(row.get("codex_thread_sha256") or "").strip().lower()
    if re.fullmatch(r"[0-9a-f]{16,64}", thread):
        if re.fullmatch(r"[0-9a-f]{16,64}", session):
            return "session:{}:thread:{}".format(session, thread)
        return "thread:{}".format(thread)
    # Malformed legacy rows may still correlate within one checkpoint, but must
    # never merge unrelated generations merely because their thread is absent.
    return "checkpoint:{}".format(_rollover_checkpoint_identity(row, index))


def _rollover_liveness_episode(row: dict[str, Any]) -> str | None:
    candidate = str(row.get("not_ready_episode_sha256") or "").strip().lower()
    return candidate if re.fullmatch(r"[0-9a-f]{16,64}", candidate) else None


def _rollover_liveness_metrics(
    recognized: list[tuple[int, dict[str, Any], str]],
) -> dict[str, int]:
    """Correlate NOT_READY retries across generations in one hashed thread.

    Checkpoint/artifact accounting remains generation-scoped. Liveness instead
    follows an ordered thread episode until PreCompact or recovery actually
    starts. A READY retry or advisory arm is evidence of remediation, not a
    transition, so either one remains pending and cannot conceal a terminal.
    """
    by_thread: dict[str, list[tuple[int, dict[str, Any], str]]] = {}
    for index, row, event in recognized:
        by_thread.setdefault(_rollover_thread_identity(row, index), []).append(
            (index, row, event)
        )

    not_ready_ids: set[str] = set()
    unresolved_ids: set[str] = set()
    repaired_ids: set[str] = set()
    advisory_ids: set[str] = set()
    terminal_episode_ids: set[str] = set()
    blocked_episode_ids: set[str] = set()
    rescued_episode_ids: set[str] = set()

    for thread_identity, rows in by_thread.items():
        active: dict[str, Any] | None = None
        last_failed_episode: tuple[str, str | None] | None = None
        episode_number = 0
        for index, row, event in sorted(rows, key=lambda value: value[0]):
            checkpoint_identity = _rollover_checkpoint_identity(row, index)
            producer_episode = _rollover_liveness_episode(row)
            if event == "checkpoint_saved" and row.get("ready") is False:
                not_ready_ids.add(checkpoint_identity)
                if (
                    active is not None
                    and producer_episode is not None
                    and active.get("producer_episode") is not None
                    and active["producer_episode"] != producer_episode
                ):
                    unresolved_ids.update(active["attempt_ids"])
                    active = None
                if active is None:
                    episode_number += 1
                    active = {
                        "id": "{}:episode:{}".format(
                            thread_identity, episode_number
                        ),
                        "attempt_ids": set(),
                        "producer_episode": producer_episode,
                    }
                elif active.get("producer_episode") is None:
                    active["producer_episode"] = producer_episode
                active["attempt_ids"].add(checkpoint_identity)
                continue

            if event == "user_rescue_after_terminal":
                if last_failed_episode is not None and (
                    producer_episode is None
                    or last_failed_episode[1] is None
                    or producer_episode == last_failed_episode[1]
                ):
                    rescued_episode_ids.add(last_failed_episode[0])
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

            attempt_ids = active["attempt_ids"]
            if event == "checkpoint_saved" and row.get("ready") is True:
                repaired_ids.update(attempt_ids)
            elif event == "checkpoint_advisory_reset_requested":
                advisory_ids.update(attempt_ids)
            elif event == "terminal_after_not_ready_blocked":
                blocked_episode_ids.add(active["id"])
            elif event == "terminal_after_not_ready":
                terminal_episode_ids.add(active["id"])
                last_failed_episode = (
                    active["id"],
                    active.get("producer_episode"),
                )
                active = None
            elif event in _ROLLOVER_LIVENESS_TRANSITIONS:
                active = None

        if active is not None:
            unresolved_ids.update(active["attempt_ids"])

    return {
        "not_ready_lifecycles": len(not_ready_ids),
        "unresolved_not_ready": len(unresolved_ids),
        "not_ready_repairs_before_terminal": len(repaired_ids),
        "not_ready_advisories_before_terminal": len(advisory_ids),
        "terminal_after_not_ready_blocked": len(blocked_episode_ids),
        "terminal_after_not_ready": len(terminal_episode_ids),
        "user_rescue_after_terminal": len(rescued_episode_ids),
    }


def _rollover_lane_metrics(rows: list[dict[str, Any]]) -> dict[str, Any]:
    recognized: list[tuple[int, dict[str, Any], str]] = []
    unknown_events = 0
    for index, row in enumerate(rows):
        event = _rollover_event(row)
        if event == "unknown":
            unknown_events += 1
            continue
        recognized.append((index, row, event))

    event_counts = Counter(event for _index, _row, event in recognized)
    save_ids: set[str] = set()
    ready_ids: set[str] = set()
    not_ready_ids: set[str] = set()
    checkpoint_repo_scopes: dict[str, set[str]] = {}
    checkpoint_task_path_counts: dict[str, int] = {}
    checkpoint_task_scope_complete: dict[str, set[bool]] = {}
    checkpoint_measurements: dict[str, tuple[int, int]] = {}
    resumed_contexts: set[str] = set()
    recovery_contexts: set[str] = set()
    validation_failure_observations: set[tuple[str, str, str]] = set()
    interruption_observations: set[tuple[str, str, str]] = set()
    terminal_failure_observations: set[tuple[str, str, str]] = set()
    readiness_observations = 0
    for index, row, event in recognized:
        identity = _rollover_checkpoint_identity(row, index)
        if event == "checkpoint_saved":
            save_ids.add(identity)
            checkpoint_repo_scopes.setdefault(identity, set()).add(
                _rollover_repo_scope(row)
            )
            checkpoint_task_path_counts[identity] = max(
                checkpoint_task_path_counts.get(identity, 0),
                _rollover_task_path_count(row),
            )
            checkpoint_task_scope_complete.setdefault(identity, set()).add(
                _rollover_task_scope_complete(row)
            )
            if isinstance(row.get("ready"), bool):
                readiness_observations += 1
                (ready_ids if row["ready"] else not_ready_ids).add(identity)
        if event == "session_resumed":
            resumed_contexts.add(identity)
        if event == "session_recovery_advisory":
            recovery_contexts.add(identity)
        observation = (
            identity,
            str(row.get("timestamp") or row.get("ts") or "unknown"),
            _metric_category(row.get("trigger")),
        )
        if event == "checkpoint_stale":
            validation_failure_observations.add(observation)
        if event == "precompact_blocked":
            interruption_observations.add(observation)
        if event == "terminal_after_not_ready":
            terminal_failure_observations.add(observation)
        byte_count = row.get("checkpoint_bytes")
        token_count = row.get("checkpoint_tokens_estimate")
        safe_bytes = (
            int(byte_count)
            if isinstance(byte_count, int)
            and not isinstance(byte_count, bool)
            and byte_count >= 0
            else 0
        )
        safe_tokens = (
            int(token_count)
            if isinstance(token_count, int)
            and not isinstance(token_count, bool)
            and token_count >= 0
            else 0
        )
        prior_bytes, prior_tokens = checkpoint_measurements.get(identity, (0, 0))
        checkpoint_measurements[identity] = (
            max(prior_bytes, safe_bytes),
            max(prior_tokens, safe_tokens),
        )

    liveness = _rollover_liveness_metrics(recognized)

    saved_measurements = [
        checkpoint_measurements.get(identity, (0, 0)) for identity in save_ids
    ]
    normalized_repo_scopes = {
        identity: next(iter(scopes)) if len(scopes) == 1 else "unknown"
        for identity, scopes in checkpoint_repo_scopes.items()
    }
    repo_scope_counts = Counter(normalized_repo_scopes.values())
    complete_task_scope_ids = {
        identity
        for identity, values in checkpoint_task_scope_complete.items()
        if values == {True}
    }
    ready_task_scope_ids = {
        identity
        for identity in ready_ids
        if normalized_repo_scopes.get(identity) == "task_paths_v1"
        and identity in complete_task_scope_ids
    }
    ready_legacy_scope_ids = {
        identity
        for identity in ready_ids
        if normalized_repo_scopes.get(identity) == "legacy_worktree_v1"
    }
    ready_unknown_scope_ids = ready_ids - ready_task_scope_ids - ready_legacy_scope_ids
    attempted_task_scope_counts = [
        checkpoint_task_path_counts.get(identity, 0)
        for identity, scope in normalized_repo_scopes.items()
        if scope == "task_paths_v1"
    ]
    ready_task_scope_counts = [
        checkpoint_task_path_counts.get(identity, 0)
        for identity in ready_task_scope_ids
    ]
    task_scoped_resumes = sum(
        1
        for identity in resumed_contexts
        if identity in ready_task_scope_ids
    )
    return {
        "events": len(recognized),
        "unknown_events": unknown_events,
        "event_counts": dict(sorted(event_counts.items())),
        "checkpoint_save_events": event_counts["checkpoint_saved"],
        "checkpoints_saved": len(save_ids),
        "readiness_observations": readiness_observations,
        "checkpoints_ready": len(ready_ids),
        "checkpoints_not_ready": len(not_ready_ids),
        "checkpoint_bytes": sum(value[0] for value in saved_measurements),
        "checkpoint_tokens_estimate": sum(value[1] for value in saved_measurements),
        "checkpoint_repo_scopes": dict(sorted(repo_scope_counts.items())),
        "task_scoped_checkpoints": repo_scope_counts["task_paths_v1"],
        "legacy_worktree_checkpoints": repo_scope_counts["legacy_worktree_v1"],
        "unknown_repo_scope_checkpoints": repo_scope_counts["unknown"],
        "ready_task_scoped_checkpoints": len(ready_task_scope_ids),
        "ready_legacy_worktree_checkpoints": len(ready_legacy_scope_ids),
        "ready_unknown_repo_scope_checkpoints": len(ready_unknown_scope_ids),
        "task_scope_complete_attempts": len(
            {
                identity
                for identity, scope in normalized_repo_scopes.items()
                if scope == "task_paths_v1" and identity in complete_task_scope_ids
            }
        ),
        "attempted_task_path_count_total": sum(attempted_task_scope_counts),
        "attempted_task_path_count_max": max(
            attempted_task_scope_counts, default=0
        ),
        "task_path_count_total": sum(ready_task_scope_counts),
        "task_path_count_max": max(ready_task_scope_counts, default=0),
        "task_scoped_resumes": task_scoped_resumes,
        "precompact_allowed": event_counts["precompact_allowed"],
        "checkpoint_advisory_reset_requested": event_counts[
            "checkpoint_advisory_reset_requested"
        ],
        "precompact_recovery_allowed": event_counts[
            "precompact_recovery_allowed"
        ],
        "precompact_blocked": event_counts["precompact_blocked"],
        "postcompact_observed": event_counts["postcompact_observed"],
        "session_resumed": event_counts["session_resumed"],
        "session_recovery_advisory": event_counts[
            "session_recovery_advisory"
        ],
        **liveness,
        "checkpoint_completed": event_counts["checkpoint_completed"],
        "checkpoint_stale": event_counts["checkpoint_stale"],
        "subagent_skipped": event_counts["subagent_skipped"],
        "checkpoint_validation_failures": len(validation_failure_observations),
        # A validation miss that safely enters advisory recovery is not a failed
        # conversation. Only an actual blocked transition is an interruption.
        "interruptions": len(
            interruption_observations | terminal_failure_observations
        ),
        "failures": len(interruption_observations | terminal_failure_observations),
        # Each identity here is an observed resumed generation. The producer hook
        # cannot see the CLI's initial context-window identity, so this is not a
        # total context-window count.
        "resumed_contexts_observed": len(resumed_contexts),
        "recovery_contexts_observed": len(recovery_contexts),
        "reason_codes": _rollover_reason_counts(
            row for _index, row, _event in recognized
        ),
    }


def _rollover_metrics(rows: list[dict[str, Any]]) -> dict[str, Any]:
    by_scope = {
        scope: _rollover_lane_metrics(
            [row for row in rows if _rollover_scope(row) == scope]
        )
        for scope in ("root", "subagent", "unknown")
    }
    combined = _rollover_lane_metrics(rows)
    return {
        "rollover_event_count": combined["events"],
        "rollover_unknown_events": combined["unknown_events"],
        "rollover_event_counts": combined["event_counts"],
        "rollover_checkpoint_save_events": combined["checkpoint_save_events"],
        "rollover_checkpoints_saved": combined["checkpoints_saved"],
        "rollover_readiness_observations": combined["readiness_observations"],
        "rollover_checkpoints_ready": combined["checkpoints_ready"],
        "rollover_checkpoints_not_ready": combined["checkpoints_not_ready"],
        "rollover_checkpoint_bytes": combined["checkpoint_bytes"],
        "rollover_checkpoint_bytes_basis": "private_checkpoint_file",
        "rollover_checkpoint_tokens_estimate": combined[
            "checkpoint_tokens_estimate"
        ],
        "rollover_checkpoint_tokens_estimate_basis": "model_visible_capsule",
        "rollover_checkpoint_repo_scopes": combined["checkpoint_repo_scopes"],
        "rollover_task_scoped_checkpoints": combined["task_scoped_checkpoints"],
        "rollover_legacy_worktree_checkpoints": combined[
            "legacy_worktree_checkpoints"
        ],
        "rollover_unknown_repo_scope_checkpoints": combined[
            "unknown_repo_scope_checkpoints"
        ],
        "rollover_ready_task_scoped_checkpoints": combined[
            "ready_task_scoped_checkpoints"
        ],
        "rollover_ready_legacy_worktree_checkpoints": combined[
            "ready_legacy_worktree_checkpoints"
        ],
        "rollover_ready_unknown_repo_scope_checkpoints": combined[
            "ready_unknown_repo_scope_checkpoints"
        ],
        "rollover_task_scope_complete_attempts": combined[
            "task_scope_complete_attempts"
        ],
        "rollover_task_scope_attempt_rate": round(
            combined["task_scoped_checkpoints"]
            / float(max(1, combined["checkpoints_saved"])),
            3,
        ),
        "rollover_task_scope_adoption": round(
            combined["ready_task_scoped_checkpoints"]
            / float(max(1, combined["checkpoints_ready"])),
            3,
        ),
        "rollover_attempted_task_path_count_total": combined[
            "attempted_task_path_count_total"
        ],
        "rollover_attempted_task_path_count_max": combined[
            "attempted_task_path_count_max"
        ],
        "rollover_task_path_count_total": combined["task_path_count_total"],
        "rollover_task_path_count_max": combined["task_path_count_max"],
        "rollover_task_scoped_resumes": combined["task_scoped_resumes"],
        "rollover_checkpoint_advisory_reset_requested": combined[
            "checkpoint_advisory_reset_requested"
        ],
        "rollover_precompact_allowed": combined["precompact_allowed"],
        "rollover_precompact_recovery_allowed": combined[
            "precompact_recovery_allowed"
        ],
        "rollover_precompact_blocked": combined["precompact_blocked"],
        "rollover_postcompact_observed": combined["postcompact_observed"],
        "rollover_session_resumed": combined["session_resumed"],
        "rollover_session_recovery_advisory": combined[
            "session_recovery_advisory"
        ],
        "rollover_not_ready_lifecycles": combined["not_ready_lifecycles"],
        "rollover_unresolved_not_ready": combined["unresolved_not_ready"],
        "rollover_not_ready_repairs_before_terminal": combined[
            "not_ready_repairs_before_terminal"
        ],
        "rollover_not_ready_advisories_before_terminal": combined[
            "not_ready_advisories_before_terminal"
        ],
        "rollover_terminal_after_not_ready_blocked": combined[
            "terminal_after_not_ready_blocked"
        ],
        "rollover_terminal_after_not_ready": combined[
            "terminal_after_not_ready"
        ],
        "rollover_user_rescue_after_terminal": combined[
            "user_rescue_after_terminal"
        ],
        "rollover_checkpoint_completed": combined["checkpoint_completed"],
        "rollover_checkpoint_stale": combined["checkpoint_stale"],
        "rollover_subagent_skipped": combined["subagent_skipped"],
        "rollover_checkpoint_validation_failures": combined[
            "checkpoint_validation_failures"
        ],
        "rollover_interruptions": combined["interruptions"],
        "rollover_failures": combined["failures"],
        "rollover_resumed_contexts_observed": combined[
            "resumed_contexts_observed"
        ],
        "rollover_recovery_contexts_observed": combined[
            "recovery_contexts_observed"
        ],
        "rollover_context_window_count": "not_available_here",
        "rollover_context_window_count_source": "task_run",
        "rollover_reason_codes": combined["reason_codes"],
        "rollover_by_scope": by_scope,
        "rollover_task_tokens_before_first": "not_available_here",
        "rollover_task_tokens_after": "not_available_here",
        "rollover_task_token_source": "task_run",
        "rollover_observed_context_tokens_dropped": "not_available_here",
        "rollover_observed_context_drop_is_savings": False,
        "rollover_causal_savings": "task_run_matched_runs_only",
    }


def _retrieval_opportunity_metrics(
    usage: list[dict[str, Any]], events: list[dict[str, Any]]
) -> dict[str, Any]:
    """Summarize v2 retrieval opportunities without projecting them onto v1 rows.

    Policy-v3 separates action observations from semantic raw-read intents.
    Adoption is deduped by opportunity digest; costs, follow-ups, and avoided-read
    credit are deduped by raw intent. Policy-v2 rows fall back to one shared digest.
    """
    queries_by_intent: dict[str, list[dict[str, Any]]] = {}
    queries_by_action: dict[str, list[dict[str, Any]]] = {}
    for row in usage:
        action_digest = _opportunity_digest(
            _first_metric_value(row, "opportunity_sha256", "opportunity_hash")
        )
        intent_digest = _raw_read_intent_digest(row, fallback=action_digest)
        if intent_digest:
            queries_by_intent.setdefault(intent_digest, []).append(row)
        if action_digest:
            queries_by_action.setdefault(action_digest, []).append(row)

    opportunities: dict[str, dict[str, Any]] = {}
    followup_records: list[tuple[str | None, str | None, str, int]] = []
    event_count = 0
    cached_retry_events = 0
    missing_sequence = 0
    for row in events:
        event_name = str(row.get("event") or row.get("type") or "").strip().lower()
        if event_name in _OPPORTUNITY_EVENTS:
            event_count += 1
            digest = _opportunity_digest(
                _first_metric_value(row, "opportunity_sha256", "opportunity_hash")
            )
            if digest is None:
                # V2 requires the digest. Count malformed rows honestly, but never
                # invent a join identity that might merge unrelated private intents.
                missing_sequence += 1
                digest = "__missing_opportunity_{}".format(missing_sequence)
            raw_intent = _raw_read_intent_digest(row, fallback=digest) or digest
            state = opportunities.setdefault(
                digest,
                {
                    "raw_read_intent_sha256": raw_intent,
                    "kind": "unknown",
                    "eligibility": [],
                    "exclusions": set(),
                    "mode": "unknown",
                    "policy_version": "unknown",
                    "attempted": False,
                    "outcomes": set(),
                    "actions": set(),
                    "grounded": False,
                    "blocked": False,
                    "grounded_block": False,
                    "agent_scopes": set(),
                    "recall_tokens": 0,
                    "delivered_context_tokens": 0,
                    "estimated_raw_tokens": 0,
                    "avoided_tokens": 0,
                },
            )
            state["raw_read_intent_sha256"] = raw_intent
            kind_value = _first_metric_value(row, "kind", "opportunity_kind")
            if kind_value is not None:
                state["kind"] = _metric_category(kind_value, _OPPORTUNITY_KINDS)
            if "eligible" in row or "retrieval_eligible" in row:
                state["eligibility"].append(
                    _metric_bool(
                        _first_metric_value(row, "eligible", "retrieval_eligible")
                    )
                )
            exclusion = _first_metric_value(
                row, "exclusion", "exclusion_reason", "ineligible_reason"
            )
            if exclusion is not None:
                state["exclusions"].add(_metric_category(exclusion))
            mode_value = _first_metric_value(row, "mode", "retrieval_mode")
            if mode_value is not None:
                state["mode"] = _metric_category(mode_value, _OPPORTUNITY_MODES)
            policy_value = _first_metric_value(row, "policy_version", "policy")
            if policy_value is not None:
                try:
                    state["policy_version"] = str(int(policy_value))
                except (TypeError, ValueError):
                    state["policy_version"] = "unknown"
            state["attempted"] = bool(state["attempted"]) or _metric_bool(
                _first_metric_value(row, "recall_attempted", "attempted")
            )
            outcome_value = _first_metric_value(
                row, "recall_outcome", "retrieval_outcome"
            )
            if outcome_value is not None:
                outcome = _metric_category(outcome_value, _RECALL_OUTCOMES)
                state["outcomes"].add(outcome)
                if outcome == "cached_hit":
                    cached_retry_events += 1
                    # Serving a cached retrieval is adoption even though it does
                    # not execute a new query or add recall-token overhead.
                    state["attempted"] = True
            action_value = _first_metric_value(row, "action", "retrieval_action")
            action = "unknown"
            if action_value is not None:
                action = _metric_category(action_value, _OPPORTUNITY_ACTIONS)
                state["actions"].add(action)
            blocked = (
                _metric_bool(row.get("blocked"))
                or _metric_bool(row.get("grounded_block"))
                or action == "deny"
            )
            grounded = _metric_bool(
                _first_metric_value(row, "grounded", "auto_grounded")
            )
            state["blocked"] = bool(state["blocked"]) or blocked
            state["grounded"] = bool(state["grounded"]) or grounded
            state["grounded_block"] = bool(state["grounded_block"]) or (
                blocked and grounded
            ) or _metric_bool(row.get("grounded_block"))
            agent = str(row.get("agent_sha256") or "").strip()
            if agent == "root":
                state["agent_scopes"].add("root")
            elif agent:
                state["agent_scopes"].add("subagent")
            state["recall_tokens"] = max(
                int(state["recall_tokens"]),
                _metric_int(
                    _first_metric_value(row, "recall_tokens", "retrieval_tokens")
                ),
            )
            delivered_value = _first_metric_value(
                row,
                "delivered_context_tokens",
                "context_tokens_delivered",
                "delivered_tokens",
            )
            if delivered_value is not None:
                delivered_tokens = _metric_int(delivered_value)
            else:
                try:
                    policy_version = int(row.get("policy_version", 0))
                except (TypeError, ValueError, OverflowError):
                    policy_version = 0
                delivered_tokens = (
                    _metric_int(
                        _first_metric_value(
                            row, "recall_tokens", "retrieval_tokens"
                        )
                    )
                    if policy_version < 4 and action in {"inject", "deny"}
                    else 0
                )
            state["delivered_context_tokens"] = max(
                int(state["delivered_context_tokens"]), delivered_tokens
            )
            state["estimated_raw_tokens"] = max(
                int(state["estimated_raw_tokens"]),
                _metric_int(
                    _first_metric_value(
                        row, "estimated_raw_tokens", "estimated_tokens", "raw_tokens"
                    )
                ),
            )
            if blocked:
                state["avoided_tokens"] = max(
                    int(state["avoided_tokens"]),
                    _metric_int(
                        _first_metric_value(
                            row, "estimated_avoided_tokens", "avoided_tokens"
                        )
                    ),
                )
        elif event_name in _FOLLOWUP_EVENTS:
            action_digest = _opportunity_digest(
                _first_metric_value(row, "opportunity_sha256", "opportunity_hash")
            )
            raw_intent = _raw_read_intent_digest(row, fallback=None)
            if not action_digest and not raw_intent:
                continue
            outcome = _metric_category(
                _first_metric_value(row, "outcome", "followup_outcome"),
                _FOLLOWUP_OUTCOMES,
            )
            followup_tokens = _metric_int(
                _first_metric_value(
                    row, "estimated_raw_tokens", "estimated_tokens", "raw_tokens"
                )
            )
            if outcome not in _COSTED_FOLLOWUP_OUTCOMES:
                followup_tokens = 0
            followup_records.append(
                (action_digest, raw_intent, outcome, followup_tokens)
            )

    action_to_intent = {
        digest: str(state["raw_read_intent_sha256"])
        for digest, state in opportunities.items()
    }
    followups: dict[str, list[tuple[str, int]]] = {}
    for action_digest, raw_intent, outcome, tokens in followup_records:
        intent_digest = raw_intent or (
            action_to_intent.get(action_digest or "") if action_digest else None
        ) or action_digest
        if intent_digest:
            followups.setdefault(intent_digest, []).append((outcome, tokens))

    intents: dict[str, dict[str, Any]] = {}
    for action_digest, state in opportunities.items():
        intent_digest = str(state["raw_read_intent_sha256"])
        intent = intents.setdefault(
            intent_digest,
            {
                "actions": set(),
                "blocked": False,
                "event_recall_tokens": 0,
                "delivered_context_tokens": 0,
                "estimated_raw_tokens": 0,
                "avoided_tokens": 0,
            },
        )
        intent["actions"].add(action_digest)
        intent["blocked"] = bool(intent["blocked"]) or bool(state["blocked"])
        intent["event_recall_tokens"] = max(
            int(intent["event_recall_tokens"]), int(state["recall_tokens"])
        )
        intent["delivered_context_tokens"] += int(
            state["delivered_context_tokens"]
        )
        intent["estimated_raw_tokens"] = max(
            int(intent["estimated_raw_tokens"]),
            int(state["estimated_raw_tokens"]),
        )
        if state["blocked"]:
            intent["avoided_tokens"] = max(
                int(intent["avoided_tokens"]), int(state["avoided_tokens"])
            )

    kinds: Counter[str] = Counter()
    eligible_kinds: Counter[str] = Counter()
    exclusions: Counter[str] = Counter()
    constraints: Counter[str] = Counter()
    modes: Counter[str] = Counter()
    policies: Counter[str] = Counter()
    actions: Counter[str] = Counter()
    recall_outcomes: Counter[str] = Counter()
    followup_outcomes: Counter[str] = Counter()
    agent_splits: dict[str, dict[str, int]] = {
        scope: {
            "total": 0,
            "eligible": 0,
            "attempted": 0,
            "injected": 0,
            "blocked": 0,
        }
        for scope in ("root", "subagent", "mixed", "unknown")
    }
    eligible_count = 0
    excluded_count = 0
    attempted_count = 0
    eligible_attempted_count = 0
    injections = 0
    exemptions = 0
    primary_exemption_keys: set[str] = set()
    grounded_blocks = 0
    joined_queries = len(set(queries_by_intent) & set(intents))
    orphan_query_tokens = sum(
        _metric_int(query.get("tokens"))
        for digest, query_rows in queries_by_intent.items()
        if digest not in intents
        for query in query_rows
    )
    recall_overhead = orphan_query_tokens
    blocked_recall_overhead = 0
    production_query_rows = sum(len(rows) for rows in queries_by_intent.values())
    total_delivered_context = 0
    blocked_delivered_context = 0
    estimated_raw_tokens = 0
    total_followup_tokens = 0
    followup_cost_tokens = 0
    gross_avoided = 0
    direct_net_avoided = 0
    for digest, state in opportunities.items():
        query_rows = queries_by_action.get(digest, [])
        if query_rows:
            state["attempted"] = True
            if not state["agent_scopes"]:
                for query in query_rows:
                    agent = str(query.get("agent_sha256") or "").strip()
                    if agent == "root":
                        state["agent_scopes"].add("root")
                    elif agent:
                        state["agent_scopes"].add("subagent")
            if not state["outcomes"]:
                for query in query_rows:
                    if not bool(query.get("hit")):
                        state["outcomes"].add("miss")
                    elif query.get("confidence") == "broad":
                        state["outcomes"].add("broad_hit")
                    else:
                        state["outcomes"].add("focused_hit")

        kind = str(state["kind"])
        kinds[kind] += 1
        eligibility = state["eligibility"]
        eligible = any(eligibility)
        for reason in state["exclusions"]:
            constraints[str(reason)] += 1
        if eligible:
            eligible_count += 1
            eligible_kinds[kind] += 1
        else:
            excluded_count += 1
            reasons = state["exclusions"] or {"unknown"}
            for reason in reasons:
                exclusions[str(reason)] += 1
        modes[str(state["mode"])] += 1
        policies[str(state["policy_version"])] += 1
        for outcome in state["outcomes"] or {"not_attempted"}:
            recall_outcomes[str(outcome)] += 1
        attempted = bool(state["attempted"])
        if attempted:
            attempted_count += 1
            if eligible:
                eligible_attempted_count += 1
        action_labels = state["actions"] or {"unknown"}
        for action_label in action_labels:
            actions[str(action_label)] += 1
        injected = "inject" in action_labels
        if injected:
            injections += 1
        exempt = "exempt" in action_labels
        if exempt:
            exemptions += 1
        is_primary_exemption = (
            kind == "primary_read" and exempt
        ) or any(
            reason.startswith("primary_")
            or reason in {"primary", "direct_named_read", "named_document"}
            for reason in state["exclusions"]
        )
        if is_primary_exemption:
            primary_exemption_keys.add(str(state["raw_read_intent_sha256"]))
        blocked = bool(state["blocked"])
        if state["grounded_block"]:
            grounded_blocks += 1

        scopes = state["agent_scopes"]
        if scopes == {"root"}:
            scope = "root"
        elif scopes == {"subagent"}:
            scope = "subagent"
        elif scopes:
            scope = "mixed"
        else:
            scope = "unknown"
        split = agent_splits[scope]
        split["total"] += 1
        split["eligible"] += int(eligible)
        split["attempted"] += int(attempted)
        split["injected"] += int(injected)
        split["blocked"] += int(blocked)

    blocked_intents = 0
    followup_opportunities = 0
    for intent_digest, intent in intents.items():
        query_rows = queries_by_intent.get(intent_digest, [])
        # Every linked query row is executed recall work. Cached decisions have no
        # query row; event tokens are only the fallback for incomplete old ledgers.
        query_tokens = sum(_metric_int(query.get("tokens")) for query in query_rows)
        recall_tokens = max(int(intent["event_recall_tokens"]), query_tokens)
        recall_overhead += recall_tokens
        estimated_raw_tokens += int(intent["estimated_raw_tokens"])
        delivered_context = int(intent["delivered_context_tokens"])
        total_delivered_context += delivered_context

        intent_followup_rows = followups.get(intent_digest, [])
        intent_followups = {
            outcome for outcome, _tokens in intent_followup_rows
        }
        intent_followup_tokens = sum(
            tokens for _outcome, tokens in intent_followup_rows
        )
        if intent_followup_rows:
            followup_opportunities += 1
        total_followup_tokens += intent_followup_tokens
        for outcome in intent_followups:
            followup_outcomes[outcome] += 1
        if "primary_bypass" in intent_followups:
            primary_exemption_keys.add(intent_digest)

        if not intent["blocked"]:
            continue
        blocked_intents += 1
        avoided = int(intent["avoided_tokens"])
        gross_avoided += avoided
        blocked_recall_overhead += recall_tokens
        blocked_delivered_context += delivered_context
        blocked_followup_cost = intent_followup_tokens
        if intent_followups & {"whole_read", "primary_bypass"}:
            # A later full/bypass read consumes the originally avoided input.
            # When older follow-up rows lack a token estimate, erase the gross
            # credit rather than preserving savings that were not realized.
            blocked_followup_cost = max(blocked_followup_cost, avoided)
        followup_cost_tokens += blocked_followup_cost
        direct_net_avoided += (
            avoided - delivered_context - blocked_followup_cost
        )

    total = len(opportunities)
    return {
        "retrieval_opportunities": total,
        "retrieval_opportunity_events": event_count,
        "retrieval_duplicate_opportunity_events": max(0, event_count - total),
        "retrieval_unidentified_opportunities": missing_sequence,
        "retrieval_eligible_opportunities": eligible_count,
        "retrieval_excluded_opportunities": excluded_count,
        "retrieval_opportunities_by_kind": dict(sorted(kinds.items())),
        "retrieval_eligible_by_kind": dict(sorted(eligible_kinds.items())),
        "retrieval_exclusions_by_reason": dict(sorted(exclusions.items())),
        "retrieval_constraints_by_reason": dict(sorted(constraints.items())),
        "retrieval_modes": dict(sorted(modes.items())),
        "retrieval_policy_versions": dict(sorted(policies.items())),
        "retrieval_actions": dict(sorted(actions.items())),
        "retrieval_raw_read_intents": len(intents),
        "retrieval_attempted_opportunities": attempted_count,
        "retrieval_eligible_attempted_opportunities": eligible_attempted_count,
        "retrieval_attempt_coverage": round(
            eligible_attempted_count / float(max(1, eligible_count)), 3
        ),
        "retrieval_query_joins": joined_queries,
        "retrieval_orphaned_query_opportunities": len(
            set(queries_by_intent) - set(intents)
        ),
        "retrieval_orphaned_query_intents": len(
            set(queries_by_intent) - set(intents)
        ),
        "retrieval_recall_outcomes": dict(sorted(recall_outcomes.items())),
        "retrieval_focused_hits": recall_outcomes["focused_hit"],
        "retrieval_broad_hits": recall_outcomes["broad_hit"],
        "retrieval_misses": recall_outcomes["miss"],
        "retrieval_errors": recall_outcomes["error"],
        "retrieval_provenance_mismatches": recall_outcomes[
            "provenance_mismatch"
        ],
        "retrieval_cached_hits": recall_outcomes["cached_hit"],
        "retrieval_cached_retry_events": cached_retry_events,
        "retrieval_injections": injections,
        "retrieval_exemptions": exemptions,
        "retrieval_grounded_blocks": grounded_blocks,
        "retrieval_primary_exemptions": len(primary_exemption_keys),
        "retrieval_followup_opportunities": followup_opportunities,
        "retrieval_targeted_fallback_outcomes": dict(
            sorted(followup_outcomes.items())
        ),
        "retrieval_targeted_fallbacks": (
            followup_outcomes["targeted_window"]
            + followup_outcomes["targeted_search"]
        ),
        "retrieval_agent_splits": agent_splits,
        "retrieval_unique_blocked_intents": blocked_intents,
        "retrieval_estimated_raw_tokens": estimated_raw_tokens,
        "retrieval_orphaned_query_tokens": orphan_query_tokens,
        "retrieval_production_query_rows": production_query_rows,
        "retrieval_query_output_tokens": recall_overhead,
        "retrieval_recall_overhead_tokens": recall_overhead,
        "retrieval_blocked_query_output_tokens": blocked_recall_overhead,
        "retrieval_blocked_recall_overhead_tokens": blocked_recall_overhead,
        "retrieval_total_delivered_context_tokens": total_delivered_context,
        "retrieval_blocked_delivered_context_tokens": blocked_delivered_context,
        "retrieval_total_followup_tokens": total_followup_tokens,
        "retrieval_followup_cost_tokens": followup_cost_tokens,
        "retrieval_gross_avoided_tokens": gross_avoided,
        "retrieval_direct_net_avoided_tokens": direct_net_avoided,
    }


def _line_ranges(value: Any, total_lines: int) -> list[tuple[int, int]]:
    """Return a bounded, merged line-range list from privacy-safe telemetry."""
    if not isinstance(value, list) or total_lines <= 0:
        return []
    bounded: list[tuple[int, int]] = []
    for item in value:
        if not isinstance(item, (list, tuple)) or len(item) != 2:
            continue
        start = _metric_int(item[0])
        end = _metric_int(item[1])
        if start <= 0 or end < start or start > total_lines:
            continue
        bounded.append((start, min(end, total_lines)))
    merged: list[tuple[int, int]] = []
    for start, end in sorted(bounded):
        if merged and start <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def _range_line_count(ranges: Iterable[tuple[int, int]]) -> int:
    return sum(end - start + 1 for start, end in ranges)


def _session_hook_coverage(
    runtime: Runtime,
    session_sha256: str,
    keys: set[tuple[str, str]],
) -> tuple[
    dict[tuple[str, str], list[tuple[int, int]]],
    set[tuple[str, str, str]],
    set[tuple[str, str]],
    dict[tuple[str, str, str], list[tuple[int, int]]],
]:
    """Load current exact ranges for legacy events that predate range telemetry.

    State is used only for document/version identities already anchored by a
    confirmed event in the selected ledger. This prevents unrelated or stale
    hook state from inventing coverage in a stats window.
    """
    ranges_by_key: dict[tuple[str, str], list[tuple[int, int]]] = {}
    exact_agents: set[tuple[str, str, str]] = set()
    authoritative: set[tuple[str, str]] = set()
    agent_ranges: dict[tuple[str, str, str], list[tuple[int, int]]] = {}
    if session_sha256 == "all" or not keys:
        return ranges_by_key, exact_agents, authoritative, agent_ranges
    state_dir = runtime.state_dir / "hook-state"
    try:
        paths = tuple(
            path
            for path in state_dir.glob("*.json")
            if path.name.startswith(session_sha256 + "-")
        )
    except OSError:
        return ranges_by_key, exact_agents, authoritative, agent_ranges
    states: list[dict[str, Any]] = []
    for path in paths:
        try:
            state = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(state, dict) or state.get("session_sha256") != session_sha256:
            continue
        states.append(state)
    shared_state = next(
        (
            state
            for state in states
            if not state.get("agent_sha256")
            and isinstance(state.get("primary"), dict)
        ),
        None,
    )
    shared_epoch = (
        str(shared_state.get("task_epoch_sha256") or "")
        if shared_state is not None
        else ""
    )
    for state in states:
        agent = str(state.get("agent_sha256") or "")
        documents = state.get("documents")
        same_epoch = (
            not shared_epoch
            or str(state.get("task_epoch_sha256") or "") == shared_epoch
        )
        if isinstance(documents, dict) and agent and same_epoch:
            for document_sha256, entry in documents.items():
                if not isinstance(entry, dict):
                    continue
                version_sha256 = str(entry.get("version_sha256") or "")
                key = (str(document_sha256), version_sha256)
                if key not in keys:
                    continue
                total_lines = max(1, _metric_int(entry.get("total_lines")))
                ranges = _line_ranges(entry.get("ranges"), total_lines)
                ranges_by_key[key] = _line_ranges(
                    [*ranges_by_key.get(key, []), *ranges], total_lines
                )
                agent_key = (key[0], key[1], agent)
                agent_ranges[agent_key] = ranges
                exact_agents.add(agent_key)
        primary = state.get("primary") if state is shared_state else None
        if isinstance(primary, dict):
            key = (
                str(primary.get("document_sha256") or ""),
                str(primary.get("version_sha256") or ""),
            )
            if key in keys:
                total_lines = max(1, _metric_int(primary.get("total_lines")))
                ranges = _line_ranges(primary.get("ranges"), total_lines)
                ranges_by_key[key] = _line_ranges(
                    [*ranges_by_key.get(key, []), *ranges], total_lines
                )
                # The shared primary is maintained as the cross-agent union.
                authoritative.add(key)
    return ranges_by_key, exact_agents, authoritative, agent_ranges


def _document_coverage_metrics(
    runtime: Runtime,
    doc_reads: list[dict[str, Any]],
    *,
    session_sha256: str,
) -> dict[str, Any]:
    """Compute one version-aware, cross-agent first-pass union per document."""
    buckets: dict[tuple[str, str], dict[str, Any]] = {}
    latest_seen: dict[str, tuple[int, tuple[str, str], int]] = {}
    latest_epoch = (
        ""
        if session_sha256 == "all"
        else next(
            (
                str(row.get("task_epoch_sha256"))
                for row in reversed(doc_reads)
                if str(row.get("task_epoch_sha256") or "")
            ),
            "",
        )
    )
    for ordinal, row in enumerate(doc_reads):
        row_epoch = str(row.get("task_epoch_sha256") or "")
        if latest_epoch and row_epoch != latest_epoch:
            continue
        details = row.get("coverage")
        if not isinstance(details, list):
            continue
        agent = str(row.get("agent_sha256") or "root")
        for detail in details:
            if not isinstance(detail, dict):
                continue
            document_sha256 = str(detail.get("document_sha256") or "")
            if not document_sha256:
                continue
            version_sha256 = str(detail.get("version_sha256") or "unknown")
            key = (document_sha256, version_sha256)
            total_lines = max(1, _metric_int(detail.get("total_lines")))
            latest_seen[document_sha256] = (ordinal, key, total_lines)
            if not _metric_bool(detail.get("confirmed", True)):
                continue
            bucket = buckets.setdefault(
                key,
                {
                    "total_lines": total_lines,
                    "ranges": [],
                    "max_covered_lines": 0,
                    "max_covered_by_agent": {},
                    "expected_agents": set(),
                    "exact_agents": set(),
                    "agent_ranges": {},
                },
            )
            bucket["total_lines"] = max(int(bucket["total_lines"]), total_lines)
            bucket["max_covered_lines"] = max(
                int(bucket["max_covered_lines"]),
                min(total_lines, _metric_int(detail.get("covered_lines"))),
            )
            bucket["max_covered_by_agent"][agent] = max(
                int(bucket["max_covered_by_agent"].get(agent, 0)),
                min(total_lines, _metric_int(detail.get("covered_lines"))),
            )
            bucket["expected_agents"].add(agent)
            if isinstance(detail.get("ranges"), list):
                exact_ranges = _line_ranges(
                    detail["ranges"], int(bucket["total_lines"])
                )
                bucket["ranges"] = _line_ranges(
                    [*bucket["ranges"], *detail["ranges"]],
                    int(bucket["total_lines"]),
                )
                bucket["agent_ranges"][agent] = _line_ranges(
                    [
                        *bucket["agent_ranges"].get(agent, []),
                        *exact_ranges,
                    ],
                    int(bucket["total_lines"]),
                )
                # The scalar is a useful corruption check because producer rows
                # contain the agent's full cumulative range snapshot.
                if _range_line_count(exact_ranges) == min(
                    int(bucket["total_lines"]),
                    _metric_int(detail.get("covered_lines")),
                ):
                    bucket["exact_agents"].add(agent)

    confirmed_keys = set(buckets)
    (
        state_ranges,
        state_agents,
        authoritative,
        state_agent_ranges,
    ) = _session_hook_coverage(runtime, session_sha256, confirmed_keys)
    used_state = False
    for key, ranges in state_ranges.items():
        bucket = buckets[key]
        prior = [] if key in authoritative else bucket["ranges"]
        bucket["ranges"] = _line_ranges(
            [*prior, *ranges], int(bucket["total_lines"])
        )
        used_state = True
    for document_sha256, version_sha256, agent in state_agents:
        bucket = buckets.get((document_sha256, version_sha256))
        if bucket is not None:
            state_ranges_for_agent = state_agent_ranges.get(
                (document_sha256, version_sha256, agent), []
            )
            if _range_line_count(state_ranges_for_agent) >= int(
                bucket["max_covered_by_agent"].get(agent, 0)
            ):
                bucket["exact_agents"].add(agent)
    for (document_sha256, version_sha256, agent), ranges in state_agent_ranges.items():
        bucket = buckets.get((document_sha256, version_sha256))
        if bucket is not None:
            bucket["agent_ranges"][agent] = ranges

    covered_lines = 0
    total_lines = 0
    completed = 0
    exact = True
    used_legacy_fallback = False
    overlap_lines = 0
    overlapping_documents = 0
    multi_agent_documents = 0
    overlap_exact = True
    documents = set(latest_seen)
    for document_sha256 in documents:
        _ordinal, key, latest_total = latest_seen[document_sha256]
        bucket = buckets.get(key)
        if bucket is None:
            # Preserve the historical meaning of unique_documents: an attempted
            # but unconfirmed version is visible with zero credited coverage.
            # A real version change intentionally stops carrying the old
            # version's union forward.
            total_lines += latest_total
            continue
        document_total = int(bucket["total_lines"])
        range_lines = min(document_total, _range_line_count(bucket["ranges"]))
        bucket_exact = key in authoritative or bucket["expected_agents"].issubset(
            bucket["exact_agents"]
        )
        if bucket_exact:
            document_covered = range_lines
        else:
            # `covered_lines` is cumulative per agent. Its maximum is a safe
            # lower bound; summing it across agents would overstate overlap.
            document_covered = max(range_lines, int(bucket["max_covered_lines"]))
            exact = False
            used_legacy_fallback = True
        covered_lines += min(document_total, document_covered)
        total_lines += document_total
        completed += int(document_covered >= document_total)
        exact_agent_coverage = bucket["expected_agents"].issubset(
            bucket["exact_agents"]
        )
        per_agent_union = _line_ranges(
            [
                value
                for ranges in bucket["agent_ranges"].values()
                for value in ranges
            ],
            document_total,
        )
        complete_agent_attribution = (
            _range_line_count(per_agent_union) == range_lines
        )
        if exact_agent_coverage and complete_agent_attribution:
            per_agent_lines = [
                _range_line_count(ranges)
                for ranges in bucket["agent_ranges"].values()
                if ranges
            ]
            multi_agent_documents += int(len(per_agent_lines) > 1)
            document_overlap = max(0, sum(per_agent_lines) - range_lines)
            overlap_lines += document_overlap
            overlapping_documents += int(document_overlap > 0)
        else:
            overlap_exact = False

    if used_legacy_fallback:
        source = "legacy_conservative"
    elif used_state:
        source = "hook_state"
    elif documents:
        source = "event_ranges"
    else:
        source = "none"
    return {
        "unique_documents": len(documents),
        "first_pass_covered_lines": covered_lines,
        "first_pass_total_lines": total_lines,
        "first_pass_coverage": round(
            covered_lines / float(max(1, total_lines)), 3
        ),
        "completed_first_pass_documents": completed,
        "first_pass_coverage_exact": exact,
        "first_pass_coverage_source": source,
        "cross_agent_document_overlap_lines": overlap_lines,
        "cross_agent_overlapping_documents": overlapping_documents,
        "cross_agent_multi_agent_documents": multi_agent_documents,
        "cross_agent_overlap_exact": overlap_exact,
    }


def stats(runtime: Runtime, *, selector: str = "current", days: int = 30) -> dict[str, Any]:
    usage = _read_jsonl(runtime.telemetry_path)
    events = _read_jsonl(runtime.hook_events_path)
    rollover_events = _read_jsonl(
        runtime.state_dir / "context-rollover-events.jsonl"
    )
    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=max(1, days))

    def timestamp(row: dict[str, Any]) -> dt.datetime | None:
        try:
            value = dt.datetime.fromisoformat(
                str(row.get("ts") or row.get("timestamp") or "").replace(
                    "Z", "+00:00"
                )
            )
            if value.tzinfo is None:
                value = value.replace(tzinfo=dt.timezone.utc)
            return value.astimezone(dt.timezone.utc)
        except (TypeError, ValueError, OverflowError):
            return None

    def recent(row: dict[str, Any]) -> bool:
        value = timestamp(row)
        return bool(value is not None and value >= cutoff)

    usage = [row for row in usage if recent(row)]
    events = [row for row in events if recent(row)]
    rollover_events = [row for row in rollover_events if recent(row)]
    if selector == "current":
        selected_digest = session_digest(os.environ.get("CODEX_SESSION_ID"))
    elif selector == "latest":
        candidates = [
            row
            for row in (*usage, *events, *rollover_events)
            if re.fullmatch(
                r"[0-9a-f]{16,64}",
                str(row.get("codex_session_sha256") or "").strip().lower(),
            )
        ]
        latest = max(candidates, key=lambda row: timestamp(row) or cutoff, default=None)
        selected_digest = (
            str(latest.get("codex_session_sha256")).strip().lower()
            if latest
            else "unknown"
        )
    elif selector == "all":
        selected_digest = "all"
    else:
        selected_digest = selector
    if selected_digest != "all":
        usage = [row for row in usage if row.get("codex_session_sha256") == selected_digest]
        events = [row for row in events if row.get("codex_session_sha256") == selected_digest]
        rollover_events = [
            row
            for row in rollover_events
            if row.get("codex_session_sha256") == selected_digest
        ]
    hits = sum(bool(row.get("hit")) for row in usage)
    broad = sum(row.get("confidence") == "broad" for row in usage)
    doc_browses = [row for row in events if row.get("event") == "document_browse"]
    doc_reads = [row for row in events if row.get("event") == "document_read"]
    repeat_guard = [row for row in events if row.get("event") == "repeat_guard"]
    legacy_hook_events = [
        row
        for row in events
        if str(row.get("event") or row.get("type") or "").strip().lower()
        not in (_OPPORTUNITY_EVENTS | _FOLLOWUP_EVENTS)
    ]
    grounded_browses = sum(bool(row.get("grounded")) for row in doc_browses)
    auto_grounded_browses = sum(
        bool(row.get("auto_grounded")) for row in doc_browses
    )
    reminder_kinds = Counter(
        str(row.get("reminder"))
        for row in doc_browses
        if row.get("reminder")
    )
    document_coverage = _document_coverage_metrics(
        runtime, doc_reads, session_sha256=selected_digest
    )
    guided_primary_reads = [
        row
        for row in events
        if str(row.get("event") or "").strip().lower().replace("-", "_")
        == "retrieval_opportunity"
        and str(row.get("kind") or "").strip().lower().replace("-", "_")
        == "primary_read"
        and _metric_bool(row.get("guided"))
    ]
    guidance_reasons = Counter(
        _metric_category(row.get("guidance_reason"))
        for row in guided_primary_reads
    )
    guidance_actions = Counter(
        _metric_category(row.get("guidance_action"))
        for row in guided_primary_reads
    )
    latest_guidance = guided_primary_reads[-1] if guided_primary_reads else {}
    repeat_outcomes = Counter(str(row.get("outcome") or "unknown") for row in repeat_guard)
    opportunity_metrics = _retrieval_opportunity_metrics(usage, events)
    rollover_metrics = _rollover_metrics(rollover_events)
    return {
        "session": selected_digest,
        "window_days": days,
        "queries": len(usage),
        "automatic_queries": sum(
            row.get("trigger")
            in {"pre_tool_use", "repeat_guard", "secondary_preflight"}
            for row in usage
        ),
        "secondary_preflight_queries": sum(
            row.get("trigger") == "secondary_preflight" for row in usage
        ),
        "repeat_guard_automatic_queries": sum(
            row.get("trigger") == "repeat_guard" for row in usage
        ),
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
        "auto_grounded_document_browses": auto_grounded_browses,
        "ungrounded_document_browses": len(doc_browses) - grounded_browses,
        "reminders": sum(bool(row.get("reminder")) for row in doc_browses),
        "initial_reminders": reminder_kinds["initial"],
        "repeated_ungrounded_reminders": reminder_kinds["ungrounded"],
        "ceiling_reminders": reminder_kinds["ceiling"],
        "hook_agents": len(
            {
                str(row.get("agent_sha256") or "root")
                for row in events
            }
        ),
        "multi_command_document_cells": sum(
            int(row.get("batch_size_hint", 0)) > 1 for row in doc_browses
        ),
        "hook_tool_identity_events": sum(
            bool(
                row.get("tool_use_sha256")
                or row.get("tool_input_sha256")
                or row.get("command_sha256s")
            )
            for row in legacy_hook_events
        ),
        "hook_event_count": len(legacy_hook_events),
        "document_read_calls": len(doc_reads),
        "documents_read": sum(int(row.get("documents", 0)) for row in doc_reads),
        "whole_documents_read": sum(int(row.get("whole_documents", 0)) for row in doc_reads),
        "estimated_document_read_tokens": sum(
            int(row.get("estimated_tokens", 0)) for row in doc_reads
        ),
        "estimated_confirmed_document_tokens": sum(
            int(detail.get("estimated_tokens", 0))
            for row in doc_reads
            for detail in (
                row.get("coverage") if isinstance(row.get("coverage"), list) else []
            )
            if isinstance(detail, dict)
            and _metric_bool(detail.get("confirmed", True))
        ),
        "estimated_unconfirmed_document_tokens": sum(
            int(detail.get("estimated_tokens", 0))
            for row in doc_reads
            for detail in (
                row.get("coverage") if isinstance(row.get("coverage"), list) else []
            )
            if isinstance(detail, dict)
            and not _metric_bool(detail.get("confirmed", True))
        ),
        **document_coverage,
        "primary_guidance_events": len(guided_primary_reads),
        "primary_guidance_reasons": dict(sorted(guidance_reasons.items())),
        "primary_guidance_actions": dict(sorted(guidance_actions.items())),
        "primary_guidance_output_safety_blocks": sum(
            _metric_bool(row.get("output_safety_blocked"))
            for row in guided_primary_reads
        ),
        "primary_guidance_context_tokens": sum(
            _metric_int(row.get("guidance_context_tokens"))
            for row in guided_primary_reads
        ),
        "primary_guidance_shared_covered_lines": _metric_int(
            latest_guidance.get("shared_covered_lines")
        ),
        "primary_guidance_missing_lines": _metric_int(
            latest_guidance.get("missing_lines")
        ),
        "primary_guidance_suggested_ranges": sum(
            _metric_int(row.get("suggested_range_count"))
            for row in guided_primary_reads
        ),
        "unconfirmed_document_ranges": sum(
            not _metric_bool(detail.get("confirmed", True))
            for row in doc_reads
            for detail in (
                row.get("coverage") if isinstance(row.get("coverage"), list) else []
            )
            if isinstance(detail, dict)
        ),
        "targeted_document_revisits": sum(
            int(row.get("targeted_revisits", 0)) for row in doc_reads
        ),
        "redundant_broad_attempts": sum(
            bool(row.get("redundant_broad_attempt")) for row in repeat_guard
        ),
        "repeat_guard_grounded_blocks": sum(
            bool(row.get("grounded_block")) for row in repeat_guard
        ),
        "repeat_guard_fail_opens": sum(
            str(row.get("outcome", "")).startswith("fail_open_")
            for row in repeat_guard
        ),
        "repeat_guard_bypasses": repeat_outcomes["bypass"],
        "repeat_guard_opt_outs": repeat_outcomes["opt_out"],
        "repeat_guard_cached_blocks": repeat_outcomes["blocked_cached"],
        "estimated_avoided_document_tokens": sum(
            int(row.get("estimated_avoided_tokens", 0)) for row in repeat_guard
        ),
        **opportunity_metrics,
        **rollover_metrics,
    }


def _render_stats(value: dict[str, Any]) -> str:
    return (
        "Codex memory usage ({session}, {window_days}d): {queries} queries "
        "({automatic_queries} automatic) · "
        "{hits} hit · {broad_results} broad · {average_tokens} avg tokens · "
        "{average_coverage} avg coverage · {p95_duration_ms} ms p95\n"
        "Document sweeps: {broad_document_browses} broad · "
        "{grounded_document_browses} grounded "
        "({auto_grounded_document_browses} automatic) · "
        "{ungrounded_document_browses} "
        "ungrounded · {reminders} reminders "
        "({initial_reminders} initial/{repeated_ungrounded_reminders} repeated/"
        "{ceiling_reminders} ceiling) · {auto_refreshes} auto-refreshes\n"
        "Hook scope: {hook_agents} agents · {multi_command_document_cells} "
        "multi-command cells · identity coverage "
        "{hook_tool_identity_events}/{hook_event_count}\n"
        "Document reads: {document_read_calls} calls · {unique_documents} unique/"
        "{documents_read} observed · {whole_documents_read} whole · "
        "~{estimated_document_read_tokens} requested tokens "
        "({estimated_confirmed_document_tokens} confirmed/"
        "{estimated_unconfirmed_document_tokens} unconfirmed)\n"
        "First pass: {first_pass_covered_lines}/{first_pass_total_lines} lines "
        "({first_pass_coverage}, {first_pass_coverage_source}, "
        "exact={first_pass_coverage_exact}) · "
        "{completed_first_pass_documents} complete · "
        "{unconfirmed_document_ranges} unconfirmed ranges · "
        "{targeted_document_revisits} targeted revisits\n"
        "Cross-agent document coverage: {cross_agent_document_overlap_lines} "
        "overlap lines · {cross_agent_overlapping_documents} overlapping/"
        "{cross_agent_multi_agent_documents} multi-agent documents · "
        "exact={cross_agent_overlap_exact}\n"
        "Primary range guidance: {primary_guidance_events} events/"
        "{primary_guidance_output_safety_blocks} output-safety blocks · "
        "actions {primary_guidance_actions} · reasons {primary_guidance_reasons} · "
        "latest shared {primary_guidance_shared_covered_lines} lines/"
        "{primary_guidance_missing_lines} missing · "
        "{primary_guidance_suggested_ranges} suggested ranges · "
        "~{primary_guidance_context_tokens} context tokens\n"
        "Repeat guard: {redundant_broad_attempts} broad attempts · "
        "{repeat_guard_grounded_blocks} grounded blocks "
        "({repeat_guard_cached_blocks} cached) · {repeat_guard_fail_opens} fail-open · "
        "{repeat_guard_bypasses} bypass/{repeat_guard_opt_outs} opt-out · "
        "~{estimated_avoided_document_tokens} avoided tokens · "
        "{repeat_guard_automatic_queries} automatic exact queries\n"
        "Retrieval opportunities: {retrieval_opportunities} action IDs/"
        "{retrieval_raw_read_intents} raw intents/"
        "{retrieval_opportunity_events} events · "
        "{retrieval_eligible_opportunities} eligible/"
        "{retrieval_excluded_opportunities} excluded · "
        "{retrieval_attempted_opportunities} attempted "
        "({retrieval_attempt_coverage} eligible coverage) · "
        "{secondary_preflight_queries} secondary preflights · policy versions "
        "{retrieval_policy_versions}\n"
        "Retrieval outcomes: {retrieval_focused_hits} focused/"
        "{retrieval_broad_hits} broad/{retrieval_misses} miss/"
        "{retrieval_errors} error · {retrieval_injections} injects · "
        "{retrieval_grounded_blocks} grounded blocks · "
        "{retrieval_targeted_fallbacks} targeted fallbacks\n"
        "Retrieval production: {retrieval_production_query_rows} query rows · "
        "~{retrieval_query_output_tokens} output tokens "
        "(~{retrieval_blocked_query_output_tokens} blocked-intent/"
        "~{retrieval_orphaned_query_tokens} orphaned)\n"
        "Model context cost: ~{retrieval_total_delivered_context_tokens} "
        "delivered tokens (~{retrieval_blocked_delivered_context_tokens} "
        "blocked-intent) · ~{retrieval_total_followup_tokens} observed "
        "follow-up tokens\n"
        "Direct retrieval savings: {retrieval_unique_blocked_intents} unique "
        "blocked intents · ~{retrieval_gross_avoided_tokens} gross - "
        "~{retrieval_blocked_delivered_context_tokens} delivered context - "
        "~{retrieval_followup_cost_tokens} follow-up cost = ~"
        "{retrieval_direct_net_avoided_tokens} net avoided tokens\n"
        "Context rollover: {rollover_event_count} events · "
        "{rollover_checkpoints_saved} checkpoints/"
        "{rollover_checkpoints_ready} ready/"
        "{rollover_checkpoints_not_ready} not ready · PreCompact "
        "{rollover_precompact_allowed} allowed/"
        "{rollover_precompact_recovery_allowed} recovery/"
        "{rollover_precompact_blocked} blocked · PostCompact "
        "{rollover_postcompact_observed} observed\n"
        "Rollover continuation: {rollover_session_resumed} validated resumed/"
        "{rollover_session_recovery_advisory} advisory recovery · "
        "{rollover_checkpoint_completed} completed · "
        "{rollover_checkpoint_validation_failures} validation misses/"
        "{rollover_interruptions} interruptions · reasons {rollover_reason_codes} · "
        "{rollover_resumed_contexts_observed} validated/"
        "{rollover_recovery_contexts_observed} advisory contexts observed\n"
        "Rollover liveness: {rollover_not_ready_lifecycles} NOT_READY lifecycles/"
        "{rollover_unresolved_not_ready} unresolved · "
        "{rollover_not_ready_repairs_before_terminal} repaired before terminal/"
        "{rollover_not_ready_advisories_before_terminal} advisory before terminal · "
        "{rollover_checkpoint_advisory_reset_requested} advisory resets/"
        "{rollover_terminal_after_not_ready_blocked} blocked terminals · "
        "{rollover_terminal_after_not_ready} terminal failures/"
        "{rollover_user_rescue_after_terminal} later user rescues\n"
        "Rollover scopes: root {rollover_by_scope[root][events]} events/"
        "{rollover_by_scope[root][session_resumed]} resumed/"
        "{rollover_by_scope[root][failures]} interrupted · subagent "
        "{rollover_by_scope[subagent][events]} events/"
        "{rollover_by_scope[subagent][session_resumed]} resumed/"
        "{rollover_by_scope[subagent][failures]} interrupted · "
        "{rollover_subagent_skipped} skipped\n"
        "Rollover repository validation: "
        "{rollover_ready_task_scoped_checkpoints} ready task-scoped/"
        "{rollover_ready_legacy_worktree_checkpoints} ready whole-worktree/"
        "{rollover_ready_unknown_repo_scope_checkpoints} ready unknown "
        "({rollover_task_scope_adoption} operational adoption) · attempted "
        "{rollover_task_scoped_checkpoints} task-scoped/"
        "{rollover_legacy_worktree_checkpoints} whole-worktree/"
        "{rollover_unknown_repo_scope_checkpoints} unknown "
        "({rollover_task_scope_attempt_rate} attempt rate; "
        "{rollover_task_scope_complete_attempts} completeness assertions) · "
        "{rollover_task_path_count_total} ready scoped-path slots/"
        "{rollover_task_path_count_max} max per ready checkpoint · "
        "{rollover_task_scoped_resumes} validated scoped resumes · modes "
        "{rollover_checkpoint_repo_scopes}\n"
        "Rollover checkpoint footprint: {rollover_checkpoint_bytes} private bytes · ~"
        "{rollover_checkpoint_tokens_estimate} model-visible capsule tokens\n"
        "Rollover token accounting: before {rollover_task_tokens_before_first}/"
        "after {rollover_task_tokens_after} here (source: "
        "{rollover_task_token_source}) · observed context dropped "
        "{rollover_observed_context_tokens_dropped} (not savings) · causal "
        "savings {rollover_causal_savings}"
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
