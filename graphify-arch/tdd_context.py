#!/usr/bin/env python3
"""Compact, TDD-aware queries over the repo's architecture graph.

The base Graphify AST graph is strong at symbol discovery but intentionally
does not model Flutter test names or shell gate membership.  This script adds a
deterministic proof overlay and renders file-deduplicated context suited to
planning, counterexample review, and execution impact checks.
"""

from __future__ import annotations

import argparse
import ast
import datetime as dt
import difflib
import functools
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import time
import uuid
from collections import Counter, defaultdict, deque
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
ARCH_DIR = ROOT / "graphify-arch"
GRAPH_PATH = ARCH_DIR / "graphify-out" / "graph.json"
ARCH_MANIFEST_PATH = ARCH_DIR / "graphify-out" / "manifest.json"
FULL_GRAPH_PATH = ROOT / "graphify-out" / "graph.json"
FULL_MANIFEST_PATH = ROOT / "graphify-out" / "manifest.json"
LABELS_PATH = ARCH_DIR / "graphify-out" / ".graphify_labels.json"
OVERLAY_PATH = ARCH_DIR / "tdd-overlay.json"
BENCHMARK_PATH = ARCH_DIR / "query-benchmark.json"
GATE_SCRIPTS = (
    ROOT / "scripts" / "run_test_gates.sh",
    ROOT / "scripts" / "run_host_test_gates.sh",
)
STATS_PATH = ROOT / "graphify-out" / "context_query_stats.jsonl"
REMINDER_STATS_PATH = (
    ARCH_DIR / "graphify-out" / "cache" / "codex-reminder" / "events.jsonl"
)
OVERLAY_VERSION = 3
USAGE_SCHEMA_VERSION = 3
TRUNCATION_PREFIX = "... truncated at ~"

SUPPORTED_SOURCE_SUFFIXES = {
    ".dart", ".go", ".sh", ".py", ".swift", ".kt", ".java",
}
DOCUMENT_SUFFIXES = {".md", ".mdx", ".rst", ".adoc"}
CODE_CONTEXT_SUFFIXES = SUPPORTED_SOURCE_SUFFIXES | {
    ".gradle", ".json", ".properties", ".toml", ".xml", ".yaml", ".yml",
}

SOURCE_ROOTS = (
    "lib",
    "go-mknoon",
    "go-relay-server",
    "integration_test",
    "test",
    "scripts",
    "ios",
)

STOPWORDS = {
    "about", "after", "against", "all", "also", "and", "architecture",
    "are", "audit", "before", "between", "code", "counterexample",
    "current", "detection", "does", "evidence", "files", "find", "for",
    "from", "gate", "gates", "graph", "graphify", "how", "identify",
    "implementation", "into", "minimal", "plan", "planning", "precision",
    "query", "registration", "relationships", "review", "source", "stale",
    "support", "test", "tests", "the", "their", "through", "trace", "tdd",
    "that", "this", "what", "where", "which", "with", "would",
}

GENERIC_LABELS = STOPWORDS | {
    "action", "actions", "boundary", "cleanup", "data", "delete", "direct",
    "handler", "harness", "lifecycle", "main", "media", "message", "parent",
    "path", "paths", "received", "restart", "result", "status", "tombstone",
}

GATE_COMMANDS = {
    "ONE_TO_ONE_HOST_TESTS": "./scripts/run_host_test_gates.sh 1to1",
    "BASELINE_TESTS": "./scripts/run_test_gates.sh baseline",
    "ONE_TO_ONE_TESTS": "./scripts/run_test_gates.sh 1to1",
    "FEED_TESTS": "./scripts/run_test_gates.sh feed",
    "INTRO_TESTS": "./scripts/run_test_gates.sh intro",
    "GROUP_TESTS": "./scripts/run_test_gates.sh groups",
    "POSTS_TESTS": "./scripts/run_test_gates.sh posts",
    "TRANSPORT_TESTS": "./scripts/run_test_gates.sh transport",
    "RUNTIME_TELEMETRY_TESTS": "./scripts/run_test_gates.sh runtime-telemetry",
    "NIGHTLY_ONLY_TESTS": "./scripts/run_test_gates.sh nightly",
}

RELATION_WEIGHT = {
    "calls": 8.0,
    "implements": 7.0,
    "inherits": 7.0,
    "extends": 7.0,
    "references": 6.0,
    "imports": 5.0,
    "configures": 5.0,
    "navigates": 5.0,
    "method": 3.0,
    "contains": 2.0,
    "defines": 1.0,
}


def _rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except (ValueError, OSError):
        return path.as_posix()


def _line(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _local_import(owner: Path, value: str) -> str | None:
    if value.startswith("package:flutter_app/"):
        candidate = ROOT / "lib" / value.removeprefix("package:flutter_app/")
    elif value.startswith("."):
        candidate = owner.parent / value
    else:
        return None
    try:
        resolved = candidate.resolve()
        resolved.relative_to(ROOT.resolve())
    except (OSError, ValueError):
        return None
    return _rel(resolved)


def _dart_tests(path: Path, text: str) -> list[dict[str, Any]]:
    pattern = re.compile(
        r"\b(?P<kind>testWidgets|test)\s*\(\s*(?:r)?"
        r"(?P<quote>['\"])(?P<name>.*?)(?P=quote)\s*,",
        re.DOTALL,
    )
    found = []
    for match in pattern.finditer(text):
        name = re.sub(r"\s+", " ", match.group("name")).strip()
        if name:
            found.append(
                {
                    "name": name,
                    "kind": match.group("kind"),
                    "line": _line(text, match.start()),
                }
            )
    return found


def _go_tests(text: str) -> list[dict[str, Any]]:
    pattern = re.compile(r"^func\s+(?P<name>Test[A-Za-z0-9_]+)\s*\(", re.MULTILINE)
    return [
        {"name": m.group("name"), "kind": "go_test", "line": _line(text, m.start())}
        for m in pattern.finditer(text)
    ]


def _gate_arrays(text: str) -> dict[str, set[str]]:
    result: dict[str, set[str]] = defaultdict(set)
    array_re = re.compile(
        r"(?:readonly\s+)?(?P<name>[A-Z][A-Z0-9_]+)=\(\s*\n(?P<body>.*?)\n\)",
        re.DOTALL,
    )
    for match in array_re.finditer(text):
        for value in re.findall(r"['\"]([^'\"]+(?:_test\.dart|\.sh))['\"]", match.group("body")):
            result[value].add(match.group("name"))
    return result


def _auto_gates(path: str) -> list[dict[str, str]]:
    if path.startswith("test/features/"):
        return [{"name": "AUTO_FEATURE_HOST", "command": "./scripts/run_host_test_gates.sh feature-host-all"}]
    if path.startswith("test/core/"):
        return [{"name": "AUTO_CORE_HOST", "command": "./scripts/run_host_test_gates.sh core-host-all"}]
    if path.startswith("test/performance/"):
        return [{"name": "AUTO_PERFORMANCE_HOST", "command": "./scripts/run_host_test_gates.sh performance-host"}]
    if path.startswith("go-mknoon/"):
        return [{"name": "GO_MKNOON", "command": "go test ./...", "cwd": "go-mknoon"}]
    if path.startswith("go-relay-server/"):
        return [{"name": "GO_RELAY", "command": "go test ./...", "cwd": "go-relay-server"}]
    if path.startswith("integration_test/"):
        return [{
            "name": "INTEGRATION_DISCOVERY_REQUIRED",
            "command": "./scripts/run_test_gates.sh reliability-sim --dry-run",
        }]
    return []


def _proof_traits(path: str, text: str) -> tuple[list[str], list[str]]:
    low = text.lower()
    fixtures: set[str] = set()
    boundaries: set[str] = set()
    if "fakebridge" in low or "fake_bridge" in low:
        fixtures.add("fake_bridge")
    if "sqflite_sqlcipher" in low or "realdbfixture" in low or "sqlcipher" in low:
        fixtures.add("real_sqlcipher")
        boundaries.add("sqlcipher")
    if path.startswith("integration_test/"):
        boundaries.add("integration_test")
    if any(value in low for value in ("methodchannel", "platform.isios", "platform.isandroid")):
        boundaries.add("native_platform")
    if any(value in low for value in ("relay", "relayserver", "relay_server")):
        boundaries.add("relay")
    if any(value in low for value in ("mlkem", "ed25519", "encrypt", "decrypt")):
        boundaries.add("crypto")
    if any(value in low for value in ("notification", "firebase_messaging", "apns", "fcm")):
        boundaries.add("notification")
    return sorted(fixtures), sorted(boundaries)


def _input_files() -> list[Path]:
    files: list[Path] = []
    for base in (ROOT / "test", ROOT / "integration_test"):
        if base.exists():
            files.extend(sorted(base.rglob("*_test.dart")))
    for base in (ROOT / "go-mknoon", ROOT / "go-relay-server"):
        if base.exists():
            files.extend(
                p
                for p in sorted(base.rglob("*_test.go"))
                if not any(part in {"third_party", ".gocache", "testdata"} for part in p.parts)
            )
    return files


def _graph_fingerprint() -> str:
    if not GRAPH_PATH.exists():
        return "missing"
    stat = GRAPH_PATH.stat()
    payload = f"{stat.st_size}:{stat.st_mtime_ns}".encode()
    return hashlib.sha256(payload).hexdigest()[:16]


def build_overlay(*, quiet: bool = False) -> dict[str, Any]:
    gate_membership: dict[str, set[str]] = defaultdict(set)
    for script in GATE_SCRIPTS:
        if not script.exists():
            continue
        for path, gates in _gate_arrays(script.read_text(encoding="utf-8")).items():
            gate_membership[path].update(gates)
    records: dict[str, dict[str, Any]] = {}
    production_to_tests: dict[str, list[str]] = defaultdict(list)

    for path in _input_files():
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        rel = _rel(path)
        if path.suffix == ".dart":
            tests = _dart_tests(path, text)
            imports = [
                local
                for value in re.findall(r"\bimport\s+['\"]([^'\"]+)['\"]", text)
                if (local := _local_import(path, value)) is not None
            ]
            tags = sorted(set(re.findall(r"@Tags\s*\(\s*\[([^]]+)\]", text)))
        else:
            tests = _go_tests(text)
            imports = []
            tags = []

        gates = _auto_gates(rel)
        for gate in sorted(gate_membership.get(rel, set())):
            gates.append({"name": gate, "command": GATE_COMMANDS.get(gate, "N/A — inspect run_test_gates.sh")})

        fixtures, boundaries = _proof_traits(rel, text)
        record = {
            "path": rel,
            "tests": tests,
            "imports": sorted(set(imports)),
            "gates": gates,
            "tags": tags,
            "fixtures": fixtures,
            "boundaries": boundaries,
        }
        records[rel] = record
        for imported in record["imports"]:
            production_to_tests[imported].append(rel)

    overlay = {
        "version": OVERLAY_VERSION,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "graph_fingerprint": _graph_fingerprint(),
        "test_files": records,
        "production_to_tests": {k: sorted(set(v)) for k, v in sorted(production_to_tests.items())},
        "summary": {
            "test_files": len(records),
            "test_cases": sum(len(r["tests"]) for r in records.values()),
            "production_import_targets": len(production_to_tests),
            "registered_files": sum(bool(r["gates"]) for r in records.values()),
        },
    }
    OVERLAY_PATH.write_text(json.dumps(overlay, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if not quiet:
        summary = overlay["summary"]
        print(
            "TDD overlay: "
            f"{summary['test_files']} files, {summary['test_cases']} named tests, "
            f"{summary['production_import_targets']} production targets"
        )
    return overlay


def _overlay_stale() -> bool:
    if not OVERLAY_PATH.exists():
        return True
    try:
        current = json.loads(OVERLAY_PATH.read_text(encoding="utf-8"))
        if current.get("version") != OVERLAY_VERSION:
            return True
    except (OSError, json.JSONDecodeError):
        return True
    stamp = OVERLAY_PATH.stat().st_mtime_ns
    candidates = _input_files()
    candidates.extend(script for script in GATE_SCRIPTS if script.exists())
    return any(path.stat().st_mtime_ns > stamp for path in candidates)


def load_overlay() -> dict[str, Any]:
    if _overlay_stale():
        return build_overlay(quiet=True)
    try:
        return json.loads(OVERLAY_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return build_overlay(quiet=True)


def _source_file(node: dict[str, Any]) -> str | None:
    source = node.get("source_file")
    if isinstance(source, str) and source:
        return source.replace("\\", "/")
    label = str(node.get("label") or "")
    if label.startswith("package:flutter_app/"):
        return "lib/" + label.removeprefix("package:flutter_app/")
    return None


def _tokens(question: str) -> tuple[list[str], list[str]]:
    raw = re.findall(r"[A-Za-z_][A-Za-z0-9_./:-]*", question)
    terms = []
    structured = []
    for token in raw:
        low = token.lower().strip(".:/-")
        if len(low) < 3 or low in STOPWORDS:
            continue
        if low not in terms:
            terms.append(low)
        if (
            "_" in token
            or "/" in token
            or "." in token
            or any(ch.isdigit() for ch in token)
            or bool(re.search(r"[a-z][A-Z]", token))
            or (token.isupper() and len(token) > 3)
        ):
            structured.append(low)
    return terms[:20], structured[:12]


def _category(path: str | None) -> str:
    if not path:
        return "unknown"
    return path.split("/", 1)[0]


def _supported_source(path: str | None) -> bool:
    if not path:
        return False
    return Path(path).suffix.lower() in SUPPORTED_SOURCE_SUFFIXES


class GraphIndex:
    def __init__(self, raw: dict[str, Any]):
        self.nodes = {str(n["id"]): n for n in raw.get("nodes", [])}
        self.edges = raw.get("links") or raw.get("edges") or []
        self.labels = Counter(
            str(n.get("norm_label") or n.get("label") or "").lower().rstrip("()")
            for n in self.nodes.values()
        )
        self.source_communities: defaultdict[str, Counter[int]] = defaultdict(Counter)
        for node in self.nodes.values():
            source = _source_file(node)
            community = node.get("community")
            if source and isinstance(community, int):
                self.source_communities[source][community] += 1
        self.adj: dict[str, list[tuple[str, dict[str, Any], bool]]] = defaultdict(list)
        self.file_edges: list[tuple[str, str, str]] = []
        for edge in self.edges:
            src = str(edge.get("source"))
            tgt = str(edge.get("target"))
            if src not in self.nodes or tgt not in self.nodes:
                continue
            self.adj[src].append((tgt, edge, True))
            self.adj[tgt].append((src, edge, False))
            src_file = _source_file(self.nodes[src])
            tgt_file = _source_file(self.nodes[tgt])
            if src_file and tgt_file and src_file != tgt_file:
                self.file_edges.append((src_file, tgt_file, str(edge.get("relation") or "")))

    def community_for(self, nid: str) -> int | None:
        community = self.nodes[nid].get("community")
        if isinstance(community, int):
            return community
        source = _source_file(self.nodes[nid])
        if not source or not self.source_communities.get(source):
            return None
        return self.source_communities[source].most_common(1)[0][0]

    def seeds(self, question: str, profile: str) -> tuple[list[str], str, list[str]]:
        terms, structured = _tokens(question)
        if not terms:
            return [], "none", []

        exact_structured = {t for t in structured if self._exact_term(t)}
        scoring_terms = [t for t in terms if t in exact_structured] or terms
        confidence = "anchored" if exact_structured else "broad"

        doc_freq: Counter[str] = Counter()
        for node in self.nodes.values():
            norm = str(node.get("norm_label") or node.get("label") or "").lower()
            for term in scoring_terms:
                if term in norm:
                    doc_freq[term] += 1

        scored: list[tuple[float, str]] = []
        count = max(1, len(self.nodes))
        for nid, node in self.nodes.items():
            norm = str(node.get("norm_label") or node.get("label") or "").lower().rstrip("()")
            source = (_source_file(node) or "").lower()
            score = 0.0
            for term in scoring_terms:
                weight = math.log(1 + count / (1 + doc_freq[term]))
                if term in {norm, nid.lower()} or term == Path(source).name:
                    score += 100.0 * weight
                elif norm.startswith(term):
                    score += 15.0 * weight
                elif term in norm:
                    score += 3.0 * weight
                if term in source:
                    score += 5.0 * weight
            if score <= 0:
                continue
            if not source:
                score *= 0.25
            elif not _supported_source(source):
                score *= 0.1
            if norm in GENERIC_LABELS:
                score *= 0.2
            duplicate_count = self.labels.get(norm, 1)
            if duplicate_count > 10:
                score *= max(0.2, 10 / duplicate_count)
            cat = _category(source)
            if profile == "general" and cat in {"test", "integration_test"}:
                score *= 0.35
            if profile in {"tdd", "review"} and cat == "scripts":
                score *= 1.2
            scored.append((score, nid))

        scored.sort(reverse=True)
        chosen: list[str] = []
        labels_seen: set[str] = set()
        files_seen: set[str] = set()
        top_score = scored[0][0] if scored else 0.0
        for score, nid in scored:
            if chosen and top_score and score < top_score * 0.20:
                break
            node = self.nodes[nid]
            norm = str(node.get("norm_label") or node.get("label") or "").lower().rstrip("()")
            source = _source_file(node) or ""
            if norm in labels_seen:
                continue
            if source and source in files_seen and len(chosen) >= 1:
                continue
            chosen.append(nid)
            labels_seen.add(norm)
            if source:
                files_seen.add(source)
            if len(chosen) == 3:
                break
        return chosen, confidence, scoring_terms

    def _exact_term(self, term: str) -> bool:
        for nid, node in self.nodes.items():
            norm = str(node.get("norm_label") or node.get("label") or "").lower().rstrip("()")
            source = (_source_file(node) or "").lower().removeprefix("./")
            if term in {norm, nid.lower(), source, Path(source).name.lower()}:
                return True
        return False

    def missed_structured_terms(self, question: str) -> list[str]:
        """Symbol-shaped question terms with no exact anchor — typo suspects."""
        _, structured = _tokens(question)
        return [t for t in structured if not self._exact_term(t)]

    def suggest_anchors(self, candidates: list[str], limit: int = 5) -> list[str]:
        """Did-you-mean pass over terms known to have no exact/substring hit.

        Callers pass either every question term (total miss) or just the
        missed structured terms (broad result where a symbol-shaped term
        failed exact match — the typo case). Edit-distance similarity is
        the only signal left at that point. Matches against the label
        vocabulary and source-file basenames; returns render-ready lines.
        """
        candidates = candidates[:6]
        if not candidates:
            return []

        label_nodes: dict[str, dict[str, Any]] = {}
        basenames: dict[str, str] = {}
        for node in self.nodes.values():
            norm = str(node.get("norm_label") or node.get("label") or "").rstrip("()")
            low = norm.lower()
            if len(low) >= 4 and low not in GENERIC_LABELS:
                prev = label_nodes.get(low)
                if prev is None or (
                    _source_file(node) and not _source_file(prev)
                ):
                    label_nodes[low] = node
            source = _source_file(node)
            if source:
                basenames.setdefault(Path(source).name.lower(), source)

        vocab = list(label_nodes)
        names = list(basenames)
        out: list[str] = []
        seen: set[str] = set()
        for term in candidates:
            for low in difflib.get_close_matches(term, vocab, n=2, cutoff=0.72):
                if low in seen:
                    continue
                seen.add(low)
                node = label_nodes[low]
                source = _source_file(node) or "unknown"
                location = node.get("source_location") or ""
                out.append(
                    f"- {node.get('label', low)} — {source}"
                    f"{':' + str(location).lstrip('L') if location else ''}"
                    f" (close to '{term}')"
                )
            for name in difflib.get_close_matches(term, names, n=1, cutoff=0.72):
                if name in seen:
                    continue
                seen.add(name)
                out.append(f"- {basenames[name]} (close to '{term}')")
            if len(out) >= limit:
                break
        return out[:limit]

    def context_files(self, seeds: list[str], terms: list[str], *, depth: int = 2) -> tuple[list[str], list[tuple[str, str, str]]]:
        scores: defaultdict[str, float] = defaultdict(float)
        seen = set(seeds)
        queue = deque((nid, 0) for nid in seeds)
        file_edges: set[tuple[str, str, str]] = set()
        for nid in seeds:
            source = _source_file(self.nodes[nid])
            if source:
                scores[source] += 100.0

        while queue:
            nid, distance = queue.popleft()
            if distance >= depth:
                continue
            neighbors = sorted(
                self.adj.get(nid, []),
                key=lambda item: RELATION_WEIGHT.get(str(item[1].get("relation") or ""), 0.5),
                reverse=True,
            )[:100]
            current_file = _source_file(self.nodes[nid])
            for neighbor, edge, forward in neighbors:
                relation = str(edge.get("relation") or "")
                weight = RELATION_WEIGHT.get(relation, 0.5) / (distance + 1)
                neighbor_file = _source_file(self.nodes[neighbor])
                if neighbor_file:
                    scores[neighbor_file] += weight
                    for term in terms:
                        if term in neighbor_file.lower():
                            scores[neighbor_file] += 4.0
                if current_file and neighbor_file and current_file != neighbor_file:
                    source, target = (current_file, neighbor_file) if forward else (neighbor_file, current_file)
                    file_edges.add((source, target, relation))
                if neighbor not in seen:
                    seen.add(neighbor)
                    queue.append((neighbor, distance + 1))

        ordered = sorted(scores, key=lambda path: (scores[path], path), reverse=True)
        return ordered[:20], sorted(file_edges)[:40]


def _freshness() -> str:
    if not GRAPH_PATH.exists():
        return "missing"
    graph_time = GRAPH_PATH.stat().st_mtime_ns
    for root_name in SOURCE_ROOTS:
        base = ROOT / root_name
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.is_file() and path.suffix in {".dart", ".go", ".py", ".sh", ".swift"}:
                if any(part in {"third_party", ".gocache", "testdata"} for part in path.parts):
                    continue
                if path.name.startswith("app_localizations") and path.suffix == ".dart":
                    continue
                if path.stat().st_mtime_ns > graph_time:
                    return f"stale:{_rel(path)}"
    return "current"


def _ensure_fresh() -> None:
    freshness = _freshness()
    if freshness == "current":
        return
    subprocess.run([str(ARCH_DIR / "refresh_arch_graph.sh"), "--incremental"], cwd=ROOT, check=True)


def _load_graph() -> GraphIndex:
    if not GRAPH_PATH.exists():
        raise SystemExit("No architecture graph. Run ./graphify-arch/refresh_arch_graph.sh --full")
    return GraphIndex(json.loads(GRAPH_PATH.read_text(encoding="utf-8")))


def _tests_for_files(
    overlay: dict[str, Any],
    primary: Iterable[str],
    related: Iterable[str],
    selected: Iterable[str],
    terms: Iterable[str],
) -> list[dict[str, Any]]:
    test_files = overlay.get("test_files", {})
    paths: set[str] = {p for p in selected if p in test_files}
    reverse = overlay.get("production_to_tests", {})
    primary_list = list(dict.fromkeys(primary))
    primary_set = set(primary_list)
    primary_weight = {
        path: len(primary_list) - index for index, path in enumerate(primary_list)
    }
    related_set = set(related)
    for path in primary_set | related_set:
        paths.update(reverse.get(path, []))
    ranked: list[tuple[float, str, dict[str, Any]]] = []
    for path in paths:
        if path not in test_files:
            continue
        record = test_files[path]
        imports = set(record.get("imports", []))
        score = 120.0 * sum(
            primary_weight[production_path]
            for production_path in imports & primary_set
        )
        score += 15.0 * len(imports & related_set)
        low_path = path.lower()
        compact_path = re.sub(r"[^a-z0-9]", "", low_path)
        for production_path in primary_set:
            stem = Path(production_path).stem.lower()
            if stem in low_path or re.sub(r"[^a-z0-9]", "", stem) in compact_path:
                score += 160.0 * primary_weight[production_path]
        for term in terms:
            if term in low_path:
                score += 8.0
            if term in compact_path:
                score += 12.0
            score += min(
                6.0,
                sum(1 for test in record.get("tests", []) if term in test.get("name", "").lower()),
            )
        if path in selected:
            score += 10.0
        ranked.append((score, path, record))
    ranked.sort(key=lambda row: (row[0], row[1]), reverse=True)
    return [record for _, _, record in ranked]


@functools.lru_cache(maxsize=4)
def _manifest_sources(path: Path) -> frozenset[str]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return frozenset()
    if not isinstance(raw, dict):
        return frozenset()
    return frozenset({
        str(source).replace("\\", "/").removeprefix("./")
        for source in raw
    })


def _file_terms(
    question: str,
    *,
    root: Path = ROOT,
    limit: int = 12,
) -> list[str]:
    """Return normalized filename/path-shaped terms without retaining prose."""
    terms: list[str] = []
    seen: set[str] = set()
    raw_tokens = re.findall(r"[A-Za-z0-9_./\\:-]+", question)
    try:
        root_text = root.resolve().as_posix().lower().rstrip("/") + "/"
    except OSError:
        root_text = ""
    for token in raw_tokens:
        normalized = token.replace("\\", "/").strip(".,:;()[]{}'\"")
        low = normalized.lower()
        if root_text and low.startswith(root_text):
            normalized = normalized[len(root_text):]
        normalized = normalized.removeprefix("./").lstrip("/")
        low = normalized.lower()
        if not normalized or ("/" not in normalized and not Path(normalized).suffix):
            continue
        if low not in seen:
            seen.add(low)
            terms.append(normalized)
    return terms[:limit]


def _document_terms(question: str, *, root: Path = ROOT) -> list[str]:
    """Return document targets that must stay outside code-graph queries."""
    return [
        term
        for term in _file_terms(question, root=root, limit=64)
        if Path(term).suffix.lower() in DOCUMENT_SUFFIXES
    ]


def _manifest_matches(term: str, sources: Iterable[str]) -> list[str]:
    by_path = {source.lower(): source for source in sources}
    low_term = term.lower()
    if "/" in term:
        match = by_path.get(low_term)
        return [match] if match else []
    matches = sorted(
        source for source in sources if Path(source).name.lower() == low_term
    )
    return matches


def _scope_route(
    question: str,
    confidence: str,
    *,
    arch_sources: set[str] | None = None,
    full_sources: set[str] | None = None,
    root: Path = ROOT,
) -> dict[str, Any]:
    """Classify exact file targets that need a graph or raw-source fallback."""
    document_targets = _document_terms(question, root=root)
    if document_targets:
        return {
            "route": "document_handoff",
            "route_reason": "document_must_be_read_before_code_graph_query",
            "fallback_targets": [],
            "document_targets": sorted(document_targets),
        }
    arch_sources = (
        _manifest_sources(ARCH_MANIFEST_PATH)
        if arch_sources is None
        else arch_sources
    )
    full_sources = (
        (
            _manifest_sources(FULL_MANIFEST_PATH)
            if FULL_GRAPH_PATH.exists()
            else frozenset()
        )
        if full_sources is None
        else full_sources
    )
    arch_lower = {source.lower() for source in arch_sources}
    full_only: set[str] = set()
    extraction_misses: set[str] = set()
    raw_only: set[str] = set()

    for term in _file_terms(question, root=root):
        arch_matches = _manifest_matches(term, arch_sources)
        full_matches = _manifest_matches(term, full_sources)
        full_only.update(
            source for source in full_matches if source.lower() not in arch_lower
        )
        if arch_matches and confidence != "anchored":
            extraction_misses.update(arch_matches)

        if "/" not in term:
            continue
        candidate = root / term
        try:
            exists = (
                candidate.is_file()
                and candidate.resolve().is_relative_to(root.resolve())
            )
        except OSError:
            exists = False
        indexed = bool(arch_matches or full_matches)
        if exists and not indexed:
            raw_only.add(term)

    if full_only:
        return {
            "route": "full_graph_fallback",
            "route_reason": "exact_target_outside_architecture_graph",
            "fallback_targets": sorted(full_only),
            "document_targets": [],
        }
    if extraction_misses:
        return {
            "route": "raw_search_fallback",
            "route_reason": "architecture_extraction_miss",
            "fallback_targets": sorted(extraction_misses),
            "document_targets": [],
        }
    if raw_only:
        return {
            "route": "raw_search_fallback",
            "route_reason": "exact_target_not_indexed",
            "fallback_targets": sorted(raw_only),
            "document_targets": [],
        }
    return {
        "route": "architecture",
        "route_reason": "architecture_match_or_concept_query",
        "fallback_targets": [],
        "document_targets": [],
    }


def _scope_route_lines(route: dict[str, Any]) -> list[str]:
    targets = [str(path) for path in route.get("fallback_targets", [])]
    if route.get("route") == "document_handoff":
        document_targets = [
            str(path) for path in route.get("document_targets", [])
        ]
        lines = [
            "Scope route: document_handoff — plans/specifications are intentionally outside code graphs.",
        ]
        lines.extend(f"- {path}" for path in document_targets[:5])
        lines.append(
            "Next: read the document directly, extract exact code paths/symbols, "
            "then run a new code-only Graphify query without document paths."
        )
        return lines
    if route.get("route") == "full_graph_fallback":
        lines = [
            "Scope route: full_graph_fallback — exact target is outside the architecture graph.",
        ]
        lines.extend(f"- {path}" for path in targets[:5])
        lines.append(
            "Next: run the measured native Graphify wrapper with the exact target "
            "above and the query_id from the header."
        )
        return lines
    if route.get("route") == "raw_search_fallback":
        lines = [
            "Scope route: raw_search_fallback — exact target is not queryable in the selected graph.",
        ]
        lines.extend(f"- {path}" for path in targets[:5])
        lines.append("Next: verify the exact target with a targeted source search.")
        return lines
    return []


def _document_handoff_context(
    question: str,
    *,
    profile: str,
    level: str,
) -> tuple[list[str], dict[str, Any]] | None:
    """Reject document-bearing graph queries before loading or searching a graph."""
    route = _scope_route(question, "not_applicable")
    if route["route"] != "document_handoff":
        return None
    label = "Component" if level == "component" else "Graph"
    lines = [
        f"{label} context: profile={profile} confidence=not_applicable "
        "freshness=not_checked fingerprint=not_queried"
    ]
    lines.extend(_scope_route_lines(route))
    lines.append(
        "Architecture context not queried; complete the document-to-code handoff first."
    )
    meta: dict[str, Any] = {
        "confidence": "not_applicable",
        "seeds": [],
        "seed_count": 0,
        "suggestions": 0,
        "exact_anchor_count": 0,
        "selected_files": [],
        "proof_files": [],
        **route,
    }
    if level == "component":
        meta.update({"level": "component", "components": 0})
    else:
        meta.update({"sources": 0, "tests": 0})
    return lines, meta


def _compact_lines(
    graph: GraphIndex,
    overlay: dict[str, Any],
    question: str,
    profile: str,
) -> tuple[list[str], dict[str, Any]]:
    handoff = _document_handoff_context(
        question,
        profile=profile,
        level="code",
    )
    if handoff is not None:
        return handoff
    seeds, confidence, terms = graph.seeds(question, profile)
    _, structured_terms = _tokens(question)
    exact_anchor_count = sum(graph._exact_term(term) for term in structured_terms)
    scope_route = _scope_route(question, confidence)
    freshness = _freshness()
    lines = [
        f"Graph context: profile={profile} confidence={confidence} freshness={freshness} fingerprint={_graph_fingerprint()}"
    ]
    route_lines = _scope_route_lines(scope_route)
    if route_lines:
        lines.extend(route_lines)
    if scope_route["route"] != "architecture" and confidence != "anchored":
        lines.append("Architecture context skipped to avoid an unrelated broad shortlist.")
        return lines, {
            "confidence": confidence,
            "sources": 0,
            "tests": 0,
            "seeds": [],
            "seed_count": 0,
            "suggestions": 0,
            "exact_anchor_count": exact_anchor_count,
            "selected_files": [],
            "proof_files": [],
            **scope_route,
        }
    if confidence == "anchored":
        lines.append(
            "Query use: navigation only — verify current source and exact test assertions; "
            "missing graph evidence does not prove implementation absence."
        )
    else:
        lines.append(
            "Query use: anchor discovery only — no exact symbol, filename, gate, or node ID matched."
        )
        lines.append(
            "Do not answer implementation, absence, completeness, reliability, or authority "
            "questions from this output."
        )
    if not seeds:
        lines.append("No matching graph anchors. Use an exact class, function, or filename.")
        miss_terms, miss_structured = _tokens(question)
        suggestions = graph.suggest_anchors(miss_structured or miss_terms)
        if suggestions:
            lines.append("Did you mean:")
            lines.extend(suggestions)
        lines.append(
            "Required next step: obtain one exact symbol or filename, then query that anchor "
            "with one specific caller, implementation, test, or gate relationship."
        )
        return lines, {
            "confidence": "none",
            "sources": 0,
            "tests": 0,
            "seeds": [],
            "seed_count": 0,
            "suggestions": len(suggestions),
            "exact_anchor_count": exact_anchor_count,
            "selected_files": [],
            "proof_files": [],
            **scope_route,
        }

    community_labels = _load_community_labels()
    lines.append("Anchors:")
    for nid in seeds:
        node = graph.nodes[nid]
        source = _source_file(node) or "unknown"
        location = node.get("source_location") or ""
        cid = graph.community_for(nid)
        community = community_labels.get(cid) if isinstance(cid, int) else None
        membership = (
            f" ∈ {community}"
            if community and not community.startswith("Community ")
            else ""
        )
        lines.append(
            f"- {node.get('label', nid)} — {source}"
            f"{':' + str(location).lstrip('L') if location else ''} [{nid}]{membership}"
        )

    # Broad result with a symbol-shaped term that exact-matched nothing:
    # almost always a typo'd or renamed anchor. Surface the near misses
    # right after the anchors (not at the tail, where _bounded truncates
    # first) so the refinement round has a concrete symbol to use.
    suggestions: list[str] = []
    if confidence != "anchored":
        missed = graph.missed_structured_terms(question)
        if missed:
            suggestions = graph.suggest_anchors(missed)
            if suggestions:
                lines.append("Did you mean:")
                lines.extend(suggestions)

        # Ordinary vocabulary can land on plausible but unrelated nodes.  A
        # broad result is useful only for choosing an exact refinement anchor;
        # withholding related files and proof candidates prevents callers from
        # silently treating ranked graph proximity as an answer.
        lines.append(
            "Required next step: choose a semantically relevant exact anchor above and refine "
            "it with one specific caller, implementation, test, or gate relationship."
        )
        lines.append(
            "If no candidate matches, run one --level component discovery query for the "
            "subsystem, then anchor on a returned key symbol; do not retry broad code synonyms."
        )
        return lines, {
            "confidence": confidence,
            "sources": 0,
            "tests": 0,
            "seeds": [str(graph.nodes[n].get("label", n)) for n in seeds],
            "seed_count": len(seeds),
            "suggestions": len(suggestions),
            "exact_anchor_count": exact_anchor_count,
            "selected_files": [],
            "proof_files": [],
            **scope_route,
        }

    files, edges = graph.context_files(seeds, terms)
    primary_production = [
        source
        for nid in seeds
        if (source := _source_file(graph.nodes[nid]))
        and _category(source) not in {"test", "integration_test", "scripts", "unknown"}
    ]
    production = [p for p in files if _category(p) not in {"test", "integration_test", "scripts", "unknown"}]
    scripts = [p for p in files if _category(p) == "scripts"]
    test_records = _tests_for_files(
        overlay,
        primary_production,
        production[:10],
        files,
        terms,
    )

    display_file_limit = 6 if profile == "review" else 10
    displayed_files = (production + scripts)[:display_file_limit]
    lines.append("Production/related files:")
    for path in displayed_files:
        lines.append(f"- {path}")

    if profile == "review":
        selected_prod = set(production[:10])
        bypasses = set()
        for source, target, relation in graph.file_edges:
            if (
                target in selected_prod
                and source not in selected_prod
                and _category(source) != "test"
            ):
                if relation in {"imports", "calls", "references", "implements", "inherits", "extends"}:
                    bypasses.add((source, relation, target))
        lines.append("Caller/bypass candidates:")
        for source, relation, target in sorted(
            bypasses,
            key=lambda row: (
                any(fragment in row[0] for fragment in ("lifecycle", "background", "notification", "ios/", "integration_test")),
                row,
            ),
            reverse=True,
        )[:4]:
            lines.append(f"- {source} --{relation}--> {target}")
        if not bypasses:
            lines.append("- none resolved; raw caller verification remains required")

    if profile in {"tdd", "review"}:
        lines.append("Direct proof candidates:")
        if not test_records:
            lines.append("- none in deterministic overlay; verify with targeted source search")
        record_limit = 4 if profile == "review" else 8
        for record in test_records[:record_limit]:
            gate_names = "; ".join(
                f"{g['name']} => {g['command']}" for g in record.get("gates", [])
            ) or "unregistered"
            traits = sorted(set(record.get("fixtures", []) + record.get("boundaries", [])))
            trait_suffix = f"; proof traits: {', '.join(traits)}" if traits else ""
            tests = record.get("tests", [])
            if tests:
                for test in tests[:2]:
                    lines.append(
                        f"- {record['path']}:{test['line']} :: {test['name']} "
                        f"[gates: {gate_names}{trait_suffix}]"
                    )
            else:
                lines.append(
                    f"- {record['path']} [named test not parsed; gates: {gate_names}{trait_suffix}]"
                )

    lines.append("Key file relationships:")
    for source, target, relation in edges[:10]:
        lines.append(f"- {source} --{relation}--> {target}")
    if confidence != "anchored":
        lines.append("Warning: broad seed selection; refine with an exact symbol or filename before treating this as a shortlist.")

    meta = {
        "confidence": confidence,
        "sources": len(set(production + scripts)),
        "tests": sum(len(r.get("tests", [])) for r in test_records),
        "seeds": [str(graph.nodes[n].get("label", n)) for n in seeds],
        "seed_count": len(seeds),
        "suggestions": len(suggestions),
        "exact_anchor_count": exact_anchor_count,
        "selected_files": displayed_files,
        "proof_files": [record["path"] for record in test_records[:record_limit]]
        if profile in {"tdd", "review"}
        else [],
        **scope_route,
    }
    return lines, meta


def _load_community_labels() -> dict[int, str]:
    try:
        raw = json.loads(LABELS_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    labels: dict[int, str] = {}
    for key, value in raw.items():
        try:
            labels[int(key)] = str(value)
        except (TypeError, ValueError):
            continue
    return labels


def _component_lines(
    graph: GraphIndex,
    question: str,
    profile: str,
    budget: int = 600,
) -> tuple[list[str], dict[str, Any]]:
    """Render the labeled community (C4 component) map relevant to a question.

    Communities are the component layer: curated labels over the deterministic
    clustering. This mode answers "which components are involved and how do
    they connect" in a few hundred tokens; drill into code with --level code.
    """
    handoff = _document_handoff_context(
        question,
        profile=profile,
        level="component",
    )
    if handoff is not None:
        return handoff
    labels = _load_community_labels()
    freshness = _freshness()
    members: defaultdict[int, list[str]] = defaultdict(list)
    for nid, node in graph.nodes.items():
        cid = node.get("community")
        if isinstance(cid, int):
            members[cid].append(nid)

    seeds, confidence, terms = graph.seeds(question, profile)
    _, structured_terms = _tokens(question)
    exact_anchor_count = sum(graph._exact_term(term) for term in structured_terms)
    scope_route = _scope_route(question, confidence)
    lines = [
        f"Component context: level=component confidence={confidence} freshness={freshness} fingerprint={_graph_fingerprint()}"
    ]
    route_lines = _scope_route_lines(scope_route)
    if route_lines:
        lines.extend(route_lines)
    if scope_route["route"] != "architecture" and confidence != "anchored":
        lines.append("Architecture component context skipped to avoid an unrelated broad map.")
        return lines, {
            "confidence": confidence,
            "level": "component",
            "components": 0,
            "seeds": [],
            "seed_count": 0,
            "suggestions": 0,
            "exact_anchor_count": exact_anchor_count,
            "selected_files": [],
            "proof_files": [],
            **scope_route,
        }
    seed_cids = {
        cid for nid in seeds
        if isinstance(cid := graph.community_for(nid), int)
    }

    scores: defaultdict[int, float] = defaultdict(float)
    for cid in seed_cids:
        scores[cid] += 120.0
    label_matched = False
    for cid, label in labels.items():
        if cid not in members:
            continue
        low = label.lower()
        for term in terms:
            if term in low:
                scores[cid] += 40.0
                label_matched = True
    if label_matched:
        confidence = "anchored"

    # Pull in the strongest neighbors of matched components so the map shows
    # what they talk to, then keep relationship aggregation to the chosen set.
    node_cid = {
        nid: cid for nid, node in graph.nodes.items()
        if isinstance(cid := node.get("community"), int)
    }
    pair_relations: defaultdict[tuple[int, int], Counter[str]] = defaultdict(Counter)
    neighbor_pull: defaultdict[int, float] = defaultdict(float)
    matched = {cid for cid, score in scores.items() if score > 0}
    for edge in graph.edges:
        src = node_cid.get(str(edge.get("source")))
        tgt = node_cid.get(str(edge.get("target")))
        if src is None or tgt is None or src == tgt:
            continue
        relation = str(edge.get("relation") or "")
        pair_relations[(src, tgt)][relation] += 1
        if src in matched and tgt not in matched:
            neighbor_pull[tgt] += RELATION_WEIGHT.get(relation, 0.5)
        elif tgt in matched and src not in matched:
            neighbor_pull[src] += RELATION_WEIGHT.get(relation, 0.5)
    for cid, pull in neighbor_pull.items():
        scores[cid] += min(30.0, pull * 0.1)

    # Mirror the code-level profile bias: planning questions (general) want
    # production components first; tdd/review keep test communities ranked.
    if profile == "general":
        for cid in list(scores):
            categories = Counter(
                _category(_source_file(graph.nodes[nid]))
                for nid in members.get(cid, [])
                if _source_file(graph.nodes[nid])
            )
            if categories and categories.most_common(1)[0][0] in {"test", "integration_test"}:
                scores[cid] *= 0.5

    ranked = [cid for cid, score in sorted(scores.items(), key=lambda item: (-item[1], item[0])) if score > 0]
    if not ranked:
        lines.append("No matching components. Use a feature word from a community label, or an exact symbol/filename.")
        miss_terms, miss_structured = _tokens(question)
        suggestions = graph.suggest_anchors(miss_structured or miss_terms)
        if suggestions:
            lines.append("Did you mean:")
            lines.extend(suggestions)
        return lines, {
            "confidence": "none",
            "level": "component",
            "components": 0,
            "seeds": [],
            "seed_count": 0,
            "suggestions": len(suggestions),
            "exact_anchor_count": exact_anchor_count,
            "selected_files": [],
            "proof_files": [],
            **scope_route,
        }

    # _bounded caps output at ~budget*3 chars; leave room for the
    # relationships section, which is this mode's main payload.
    component_cap = max(4, min(8, budget // 100))
    chosen = ranked[:component_cap]
    chosen_set = set(chosen)
    lines.append("Components:")
    for cid in chosen:
        ids = members[cid]
        dirs = Counter()
        for nid in ids:
            source = _source_file(graph.nodes[nid])
            if source:
                parent = source.rsplit("/", 1)[0] if "/" in source else source
                dirs["/".join(parent.split("/")[:3])] += 1
        key_members: list[str] = []
        for nid in sorted(ids, key=lambda n: -len(graph.adj.get(n, []))):
            node = graph.nodes[nid]
            label = str(node.get("label") or "").strip()
            if "/" in label:
                label = label.rsplit("/", 1)[-1]
            label = label[:36]
            norm = label.lower().rstrip("()")
            if not label or norm in GENERIC_LABELS or label in key_members:
                continue
            if not _supported_source(_source_file(node)):
                continue
            key_members.append(label)
            if len(key_members) == 2:
                break
        dir_text = ", ".join(d for d, _ in dirs.most_common(2)) or "no source dirs"
        key_text = ", ".join(key_members) or "-"
        lines.append(
            f"- [{cid}] {labels.get(cid, f'Community {cid}')} ({len(ids)}n) {dir_text}; key: {key_text}"
        )

    pair_totals = {
        pair: sum(relations.values())
        for pair, relations in pair_relations.items()
        if pair[0] in chosen_set and pair[1] in chosen_set
    }
    lines.append("Component relationships:")
    if not pair_totals:
        lines.append("- none among selected components; broaden the question or drill into code level")
    for (src, tgt), total in sorted(pair_totals.items(), key=lambda item: -item[1])[:8]:
        relation_text = ", ".join(
            f"{relation}×{count}"
            for relation, count in pair_relations[(src, tgt)].most_common(2)
        )
        lines.append(
            f"- {labels.get(src, src)} --{relation_text}--> {labels.get(tgt, tgt)}"
        )
    lines.append(
        "Drill down: rerun with --level code (default) anchored on a key symbol above."
    )

    meta = {
        "confidence": confidence,
        "level": "component",
        "components": len(chosen),
        "seeds": [str(graph.nodes[n].get("label", n)) for n in seeds],
        "seed_count": len(seeds),
        "suggestions": 0,
        "exact_anchor_count": exact_anchor_count,
        "selected_files": [],
        "proof_files": [],
        **scope_route,
    }
    return lines, meta


def _bounded(lines: list[str], budget: int) -> str:
    limit = max(300, budget * 3)
    out: list[str] = []
    size = 0
    for line in lines:
        addition = len(line) + 1
        if size + addition > limit:
            out.append(f"{TRUNCATION_PREFIX}{budget} tokens; refine anchors or raise --budget")
            break
        out.append(line)
        size += addition
    return "\n".join(out)


def _environment_digest(name: str) -> str | None:
    value = os.environ.get(name)
    if not value:
        return None
    return hashlib.sha256(value.encode()).hexdigest()[:16]


def _context_evidence_digest(meta: dict[str, Any]) -> str:
    """Return a stable digest for the compact evidence set, without logging paths."""
    evidence = {
        "route": meta.get("route"),
        "selected_files": sorted(str(path) for path in meta.get("selected_files", [])),
        "proof_files": sorted(str(path) for path in meta.get("proof_files", [])),
        "fallback_targets": sorted(
            str(path) for path in meta.get("fallback_targets", [])
        ),
    }
    encoded = json.dumps(evidence, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode()).hexdigest()[:16]


def _usage_record(
    *,
    operation: str,
    profile: str,
    input_text: str,
    budget: int,
    result: str,
    meta: dict[str, Any],
    duration_ms: float,
    query_id: str,
    query_stage: str,
    refinement_of: str | None = None,
) -> dict[str, Any]:
    logged_meta = dict(meta)
    selected_files = logged_meta.pop("selected_files", [])
    proof_files = logged_meta.pop("proof_files", [])
    fallback_targets = logged_meta.pop("fallback_targets", [])
    document_targets = logged_meta.pop("document_targets", [])
    record: dict[str, Any] = {
        "schema_version": USAGE_SCHEMA_VERSION,
        "ts": dt.datetime.now(dt.timezone.utc).isoformat(),
        "operation": operation,
        "profile": profile,
        "query_id": query_id,
        "query_stage": query_stage,
        "evidence_digest": _context_evidence_digest(meta),
        "question_sha256": hashlib.sha256(input_text.encode()).hexdigest()[:16],
        "budget": budget,
        "result_chars": len(result),
        "result_tokens_estimate": max(1, round(len(result) / 4)),
        "duration_ms": round(duration_ms, 2),
        "truncated": TRUNCATION_PREFIX in result,
        "graph_scope": "architecture",
        "selected_file_count": len(selected_files),
        "proof_file_count": len(proof_files),
        "fallback_target_count": len(fallback_targets),
        "document_target_count": len(document_targets),
        **logged_meta,
    }
    if refinement_of:
        record["refinement_of"] = refinement_of
    session_digest = _environment_digest("CODEX_SESSION_ID")
    thread_digest = _environment_digest("CODEX_THREAD_ID")
    if session_digest:
        record["codex_session_sha256"] = session_digest
    if thread_digest:
        record["codex_thread_sha256"] = thread_digest
    return record


def _append_usage(record: dict[str, Any]) -> None:
    if os.environ.get("GRAPHIFY_CONTEXT_LOG") == "0":
        return
    try:
        STATS_PATH.parent.mkdir(parents=True, exist_ok=True)
        with STATS_PATH.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError:
        pass


def _log_query(
    profile: str,
    question: str,
    budget: int,
    result: str,
    meta: dict[str, Any],
    duration_ms: float,
    *,
    query_id: str,
    query_stage: str,
    refinement_of: str | None,
) -> None:
    _append_usage(
        _usage_record(
            operation="query",
            profile=profile,
            input_text=question,
            budget=budget,
            result=result,
            meta=meta,
            duration_ms=duration_ms,
            query_id=query_id,
            query_stage=query_stage,
            refinement_of=refinement_of,
        )
    )


def _stats_summary(records: list[dict[str, Any]]) -> list[str]:
    if not records:
        return ["Graphify context stats: no recorded uses"]
    estimated_tokens = [
        max(
            1,
            int(
                row.get("result_tokens_estimate")
                or round(int(row.get("result_chars", 0)) / 4)
            ),
        )
        for row in records
    ]
    utilization = [
        tokens / max(1, int(row.get("budget", 1)))
        for tokens, row in zip(estimated_tokens, records)
    ]
    ordered = sorted(estimated_tokens)
    p95 = ordered[min(len(ordered) - 1, math.ceil(len(ordered) * 0.95) - 1)]
    operations = Counter(str(row.get("operation", "query")) for row in records)
    query_records = [row for row in records if row.get("operation", "query") == "query"]
    confidence_records = [
        row for row in query_records
        if row.get("confidence") in {"anchored", "broad", "none"}
    ]
    anchored = sum(row.get("confidence") == "anchored" for row in confidence_records)
    lines = [
        f"Graphify context stats: {len(records)} recorded uses",
        "- operations: "
        + ", ".join(f"{name}={count}" for name, count in sorted(operations.items())),
        f"- output: avg {round(sum(estimated_tokens) / len(records))} estimated tokens; p95 {p95}",
        f"- budget utilization: avg {sum(utilization) / len(records):.0%}",
    ]
    if confidence_records:
        lines.append(
            f"- query anchoring: {anchored}/{len(confidence_records)} "
            f"({anchored / len(confidence_records):.0%})"
        )
    profiles = Counter(str(row.get("profile", "unknown")) for row in query_records)
    if profiles:
        lines.append(
            "- profiles: "
            + ", ".join(f"{profile}={count}" for profile, count in sorted(profiles.items()))
        )
    route_records = [row for row in query_records if row.get("route")]
    if route_records:
        routes = Counter(str(row["route"]) for row in route_records)
        lines.append(
            f"- routes ({len(route_records)} measured): "
            + ", ".join(f"{route}={count}" for route, count in sorted(routes.items()))
        )
    stage_records = [row for row in query_records if row.get("query_stage")]
    if stage_records:
        initial = [row for row in stage_records if row["query_stage"] == "initial"]
        refinements = [row for row in stage_records if row["query_stage"] == "refinement"]
        if initial:
            initial_anchored = sum(row.get("confidence") == "anchored" for row in initial)
            lines.append(
                f"- first-query anchoring: {initial_anchored}/{len(initial)} "
                f"({initial_anchored / len(initial):.0%})"
            )
        if refinements:
            refined_anchored = sum(row.get("confidence") == "anchored" for row in refinements)
            declared_links = sum(bool(row.get("refinement_of")) for row in refinements)
            lines.append(
                f"- refinement anchoring: {refined_anchored}/{len(refinements)} "
                f"({refined_anchored / len(refinements):.0%}); "
                f"declared_links={declared_links}"
            )
    truncation_records = [row for row in records if "truncated" in row]
    if truncation_records:
        truncated = sum(bool(row["truncated"]) for row in truncation_records)
        lines.append(
            f"- truncation: {truncated}/{len(truncation_records)} "
            f"({truncated / len(truncation_records):.0%})"
        )
    linked_threads = {
        str(row["codex_thread_sha256"])
        for row in records
        if row.get("codex_thread_sha256")
    }
    if linked_threads:
        linked_records = sum(bool(row.get("codex_thread_sha256")) for row in records)
        lines.append(
            f"- Codex linkage: {linked_records}/{len(records)} uses across "
            f"{len(linked_threads)} hashed threads"
        )
    return lines


def stats(*, last: int) -> None:
    records: list[dict[str, Any]] = []
    if STATS_PATH.exists():
        for line in STATS_PATH.read_text(encoding="utf-8").splitlines():
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    print("\n".join(_stats_summary(records[-last:])))


_EXEC_COMMAND_LITERAL = re.compile(
    r"(?:(?P<key_quote>[\"'])cmd(?P=key_quote)|\bcmd\b)\s*:\s*"
    r"(?P<literal>\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')",
    re.DOTALL,
)
_RAW_BROWSE_COMMAND = re.compile(
    r"(?:^|[;&|()\s])(?:bat|cat|find|grep|head|jq|nl|rg|sed|tail)(?:\s|$)"
)
_HELPER_COMMAND = re.compile(
    r"^\s*(?:(?:then|do)\s+)?"
    r"(?:env\s+)?"
    r"(?:[A-Za-z_][A-Za-z0-9_]*=[^\s;&|]+\s+)*"
    r"(?:(?:/usr/bin/time|time)(?:\s+-[A-Za-z]+)*\s+)?"
    r"(?:(?:python(?:3(?:\.\d+)?)?)\s+)?"
    r"(?:\S*/)?graphify-arch/tdd_context\.py\s+"
    r"(?P<operation>query|affected|native|checkpoint)\b"
)
_NATIVE_GRAPH_COMMAND = re.compile(
    r"^\s*(?:(?:then|do)\s+)?"
    r"(?:env\s+)?"
    r"(?:[A-Za-z_][A-Za-z0-9_]*=[^\s;&|]+\s+)*"
    r"(?:command\s+)?graphify\s+query\b"
)
_APPLY_PATCH_PATH = re.compile(
    r"\*\*\*\s+(?:Add|Delete|Update)\s+File:\s*(?P<path>[^\\\r\n]+)"
)
_SED_RANGE = re.compile(
    r"\bsed\s+-n\s+['\"]?(?P<start>\d+),(?P<end>\d+|\$)p['\"]?\s+"
    r"(?:--\s+)?(?P<path>[^\s;&|]+)"
)
_HEAD_OR_TAIL = re.compile(
    r"\b(?P<kind>head|tail)\s+-n\s+(?P<end>\d+)\s+"
    r"(?:--\s+)?(?P<path>[^\s;&|]+)"
)
_WHOLE_STREAM = re.compile(
    r"(?:^|&&|\|\||;)\s*(?:command\s+)?(?:bat|cat)\s+(?P<args>[^;&|]+)"
)
_TOOL_OUTPUT_TRUNCATION = re.compile(
    r"Warning:\s+truncated output\s+\(original token count:\s*(?P<tokens>\d+)\)",
    re.I,
)
_INSTRUCTION_DOCUMENTS = {
    "agents.md", "changelog.md", "contributing.md", "license.md", "readme.md",
    "skill.md",
}
_CODE_BROWSE_ROOTS = set(SOURCE_ROOTS) | {
    "android", "graphify-arch", "linux", "macos", "tool", "web", "windows",
}


def _decode_js_literal(literal: str) -> str | None:
    try:
        value = json.loads(literal) if literal.startswith('"') else ast.literal_eval(literal)
    except (SyntaxError, ValueError, json.JSONDecodeError):
        return None
    return value if isinstance(value, str) else None


def _exec_call_objects(tool_input: str) -> list[str]:
    """Return object literals passed to exec_command, ignoring strings/comments."""
    token = "tools.exec_command"
    objects: list[str] = []
    index = 0
    quote: str | None = None
    escaped = False
    while index < len(tool_input):
        char = tool_input[index]
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            index += 1
            continue
        if char in {'"', "'", "`"}:
            quote = char
            index += 1
            continue
        if tool_input.startswith("//", index):
            newline = tool_input.find("\n", index + 2)
            index = len(tool_input) if newline < 0 else newline + 1
            continue
        if tool_input.startswith("/*", index):
            ending = tool_input.find("*/", index + 2)
            index = len(tool_input) if ending < 0 else ending + 2
            continue
        if not tool_input.startswith(token, index):
            index += 1
            continue
        cursor = index + len(token)
        while cursor < len(tool_input) and tool_input[cursor].isspace():
            cursor += 1
        if cursor >= len(tool_input) or tool_input[cursor] != "(":
            index = cursor
            continue
        cursor += 1
        while cursor < len(tool_input) and tool_input[cursor].isspace():
            cursor += 1
        if cursor >= len(tool_input) or tool_input[cursor] != "{":
            index = cursor
            continue
        start = cursor
        depth = 0
        object_quote: str | None = None
        object_escaped = False
        while cursor < len(tool_input):
            current = tool_input[cursor]
            if object_quote is not None:
                if object_escaped:
                    object_escaped = False
                elif current == "\\":
                    object_escaped = True
                elif current == object_quote:
                    object_quote = None
            elif current in {'"', "'", "`"}:
                object_quote = current
            elif current == "{":
                depth += 1
            elif current == "}":
                depth -= 1
                if depth == 0:
                    objects.append(tool_input[start : cursor + 1])
                    cursor += 1
                    break
            cursor += 1
        index = max(cursor, index + len(token))
    return objects


def _exec_commands_from_tool_input(tool_input: str) -> list[str]:
    """Extract literal exec_command commands from one Codex exec tool call."""
    try:
        direct = json.loads(tool_input)
    except (TypeError, json.JSONDecodeError):
        direct = None
    if isinstance(direct, dict) and isinstance(direct.get("cmd"), str):
        return [direct["cmd"]]
    if "tools.exec_command" not in tool_input:
        return []
    commands: list[str] = []
    for object_literal in _exec_call_objects(tool_input):
        match = _EXEC_COMMAND_LITERAL.search(object_literal)
        if match is None:
            continue
        decoded = _decode_js_literal(match.group("literal"))
        if decoded is not None:
            commands.append(decoded)
    return commands


def _shell_command_segments(command: str) -> list[str]:
    """Split a shell command at unquoted control operators."""
    segments: list[str] = []
    start = 0
    index = 0
    quote: str | None = None
    escaped = False
    while index < len(command):
        char = command[index]
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\" and quote != "'":
                escaped = True
            elif char == quote:
                quote = None
            index += 1
            continue
        if char in {'"', "'", "`"}:
            quote = char
            index += 1
            continue
        if char == "\\" and index + 1 < len(command) and command[index + 1] == "\n":
            # A shell continuation is part of the same invocation. Keeping it
            # intact is essential for multi-line `affected <path>...` coverage.
            index += 2
            continue
        if char in ";|&\n":
            segment = command[start:index].strip(" ()\t")
            if segment:
                segments.append(segment)
            while index + 1 < len(command) and command[index + 1] == char:
                index += 1
            start = index + 1
        index += 1
    segment = command[start:].strip(" ()\t")
    if segment:
        segments.append(segment)
    return segments


def _helper_invocations(command: str) -> list[tuple[str, str]]:
    invocations: list[tuple[str, str]] = []
    for segment in _shell_command_segments(command):
        match = _HELPER_COMMAND.match(segment)
        if match:
            invocations.append((match.group("operation"), segment))
    return invocations


def _direct_native_invocations(command: str) -> list[str]:
    return [
        segment
        for segment in _shell_command_segments(command)
        if _NATIVE_GRAPH_COMMAND.match(segment)
    ]


def _patch_paths_from_tool_input(tool_input: str, *, root: Path = ROOT) -> set[str]:
    """Extract repository paths from apply_patch calls without requiring existence."""
    paths: set[str] = set()
    root_prefix = root.resolve().as_posix().rstrip("/") + "/"
    for match in _APPLY_PATCH_PATH.finditer(tool_input):
        target = match.group("path").strip(" '\"`(),;")
        if target.startswith(root_prefix):
            target = target[len(root_prefix):]
        target = target.removeprefix("./").replace("\\", "/")
        if target:
            paths.add(target)
    return paths


def _tool_output_text(value: Any) -> str:
    """Flatten text shown by a Codex tool result for output-token estimation."""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(filter(None, (_tool_output_text(item) for item in value)))
    if isinstance(value, dict):
        if isinstance(value.get("text"), str):
            return value["text"]
        if "output" in value:
            return _tool_output_text(value["output"])
    return ""


def _tool_output_details(value: Any) -> dict[str, Any]:
    """Return model-visible output size and any Codex truncation metadata."""
    text = _tool_output_text(value)
    original_tokens = [
        int(match.group("tokens"))
        for match in _TOOL_OUTPUT_TRUNCATION.finditer(text)
    ]
    exit_codes: list[int] = []

    def collect_exit_codes(item: Any) -> None:
        if isinstance(item, dict):
            for key in ("exit_code", "exitCode"):
                value = item.get(key)
                if isinstance(value, int):
                    exit_codes.append(value)
            for nested in item.values():
                collect_exit_codes(nested)
        elif isinstance(item, list):
            for nested in item:
                collect_exit_codes(nested)

    collect_exit_codes(value)
    if not exit_codes:
        structured = re.search(r'["\']exit_code["\']\s*:\s*(-?\d+)', text)
        standard = re.search(
            r"(?im)^(?:exit code\s*:|process exited with code\s+)\s*(-?\d+)\b",
            text,
        )
        match = structured or standard
        if match:
            exit_codes.append(int(match.group(1)))
    return {
        "chars": len(text),
        "truncated": bool(original_tokens),
        "original_tokens": max(original_tokens, default=0),
        "exit_code": exit_codes[0] if exit_codes else None,
    }


def _load_usage_records(path: Path = STATS_PATH) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    try:
        handle = path.open(encoding="utf-8")
    except OSError:
        return records
    with handle:
        for line in handle:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(row, dict):
                records.append(row)
    return records


def _usage_records_for_session(
    session_sha256: str,
    *,
    path: Path = STATS_PATH,
) -> list[dict[str, Any]]:
    if session_sha256 == "unknown":
        return []
    records = _load_usage_records(path)
    thread_matches = [
        row
        for row in records
        if row.get("codex_thread_sha256") == session_sha256
    ]
    if thread_matches:
        return thread_matches
    return [
        row
        for row in records
        if row.get("codex_session_sha256") == session_sha256
    ]


def _reminder_records_for_session(
    session_sha256: str,
    *,
    path: Path = REMINDER_STATS_PATH,
) -> list[dict[str, Any]]:
    if session_sha256 == "unknown":
        return []
    records: list[dict[str, Any]] = []
    try:
        handle = path.open(encoding="utf-8")
    except OSError:
        return records
    with handle:
        for line in handle:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if (
                isinstance(row, dict)
                and row.get("schema_version") == 1
                and row.get("session_sha256") == session_sha256
            ):
                records.append(row)
    return records


def _reminder_metrics(
    records: list[dict[str, Any]],
    *,
    model_visible_tool_hashes: set[str] | None = None,
    model_visible_input_hashes: set[str] | None = None,
    model_visible_command_hashes: set[str] | None = None,
) -> dict[str, Any]:
    """Summarize executed hook events, enforced blocks, and rollout identity joins."""
    grouped: defaultdict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in records:
        grouped[str(row.get("agent_sha256") or "root")].append(row)

    reminder_kinds = {"initial", "handoff", "batch", "ceiling", "spawn_context"}
    visible_tool_hashes = model_visible_tool_hashes or set()
    visible_input_hashes = model_visible_input_hashes or set()
    visible_command_hashes = model_visible_command_hashes or set()
    visibility_available = bool(
        visible_tool_hashes or visible_input_hashes or visible_command_hashes
    )

    def command_hashes(row: dict[str, Any]) -> set[str]:
        value = row.get("command_sha256s")
        if isinstance(value, list):
            return {str(item) for item in value if item}
        return {str(value)} if value else set()

    def model_visible(row: dict[str, Any]) -> bool:
        return bool(
            (
                row.get("tool_use_sha256")
                and str(row["tool_use_sha256"]) in visible_tool_hashes
            )
            or (
                row.get("tool_input_sha256")
                and str(row["tool_input_sha256"]) in visible_input_hashes
            )
            or command_hashes(row).intersection(visible_command_hashes)
        )

    def identity_stored(row: dict[str, Any]) -> bool:
        return bool(
            row.get("tool_use_sha256")
            or row.get("tool_input_sha256")
            or command_hashes(row)
        )

    def same_delivery_batch(
        reminder_row: dict[str, Any], later_row: dict[str, Any]
    ) -> bool:
        first_batch = reminder_row.get("batch_sha256")
        later_batch = later_row.get("batch_sha256")
        if first_batch and first_batch == later_batch:
            return True
        first_time = _audit_timestamp(reminder_row.get("ts"))
        later_time = _audit_timestamp(later_row.get("ts"))
        return bool(
            first_time
            and later_time
            and dt.timedelta(0)
            <= later_time - first_time
            <= dt.timedelta(milliseconds=250)
        )

    reminders = 0
    initial = 0
    handoff = 0
    batch = 0
    ceiling = 0
    spawn = 0
    responded = 0
    ignored = 0
    batched = 0
    pending = 0
    agent_summaries: list[dict[str, Any]] = []
    for agent, agent_records in grouped.items():
        raw_records = [
            row
            for row in agent_records
            if row.get("event") == "code_browse" and not row.get("blocked")
        ]
        attempted_raw_records = [
            row for row in agent_records if row.get("event") == "code_browse"
        ]
        enforced_raw_records = [
            row
            for row in raw_records
            if "blocked" in row
        ]
        agent_summaries.append(
            {
                "agent_sha256": agent,
                "code_browse_events": len(raw_records),
                "code_browse_attempts": len(attempted_raw_records),
                "context_events": sum(
                    row.get("event") == "context" for row in agent_records
                ),
                "reminders": sum(
                    row.get("reminder") in reminder_kinds for row in agent_records
                ),
                "max_gap": max(
                    (int(row.get("raw_since_context", 0)) for row in raw_records),
                    default=0,
                ),
                "enforced_max_gap": max(
                    (
                        int(row.get("raw_since_context", 0))
                        for row in enforced_raw_records
                    ),
                    default=0,
                ),
                "batch_violations": sum(
                    int(row.get("batch_size_hint", 0))
                    > int(row.get("batch_budget", 8))
                    for row in raw_records
                ),
                "blocks": sum(bool(row.get("blocked")) for row in agent_records),
                "spawns": sum(row.get("event") == "spawn" for row in agent_records),
            }
        )
        for index, row in enumerate(agent_records):
            reminder = row.get("reminder")
            if reminder not in reminder_kinds:
                continue
            reminders += 1
            initial += int(reminder == "initial")
            handoff += int(reminder == "handoff")
            batch += int(reminder == "batch")
            ceiling += int(reminder == "ceiling")
            spawn += int(reminder == "spawn_context")
            outcome = "pending"
            visible_boundary_seen = False
            for later in agent_records[index + 1 :]:
                if later.get("event") == "context":
                    outcome = "responded"
                    break
                if later.get("reminder") in reminder_kinds:
                    nested_before_visibility = bool(
                        visibility_available
                        and not visible_boundary_seen
                        and not model_visible(later)
                    )
                    outcome = (
                        "batched"
                        if same_delivery_batch(row, later)
                        or nested_before_visibility
                        else "ignored"
                    )
                    break
                if model_visible(later):
                    visible_boundary_seen = True
            responded += int(outcome == "responded")
            ignored += int(outcome == "ignored")
            batched += int(outcome == "batched")
            pending += int(outcome == "pending")
    agent_summaries.sort(
        key=lambda row: (
            -int(row["max_gap"]),
            -int(row["code_browse_events"]),
            str(row["agent_sha256"]),
        )
    )
    code_attempts = [row for row in records if row.get("event") == "code_browse"]
    code_browse_events = sum(not row.get("blocked") for row in code_attempts)
    blocked_code_browses = sum(bool(row.get("blocked")) for row in code_attempts)
    blocked_events = [row for row in records if row.get("blocked")]
    gate_counts = Counter(str(row.get("gate")) for row in blocked_events)
    closure_events = [row for row in records if row.get("event") == "closure"]
    affected_coverage_events = [
        row for row in records if row.get("event") == "affected_coverage"
    ]
    closure_block_events = sum(bool(row.get("blocked")) for row in closure_events)
    closure_blocks = max(
        closure_block_events,
        max((int(row.get("closure_blocks", 0)) for row in closure_events), default=0),
    )
    recovery_events = sum(bool(row.get("recovered")) for row in affected_coverage_events)
    recoveries = max(
        recovery_events,
        max(
            (
                int(row.get("recoveries", 0))
                for row in [*closure_events, *affected_coverage_events]
            ),
            default=0,
        ),
    )
    latest_pending_affected = next(
        (
            int(row["pending_affected_count"])
            for row in reversed(records)
            if row.get("pending_affected_count") is not None
        ),
        0,
    )
    spawn_events = [row for row in records if row.get("event") == "spawn"]
    enforcement_events = [row for row in records if "blocked" in row]
    enforced_code_browses = [
        row
        for row in code_attempts
        if "blocked" in row and not row.get("blocked")
    ]
    batch_hints = sum(
        row.get("event") == "code_browse"
        and not row.get("blocked")
        and int(row.get("batch_size_hint", 0)) > 1
        for row in records
    )
    batch_violations = sum(
        row.get("event") == "code_browse"
        and not row.get("blocked")
        and int(row.get("batch_size_hint", 0))
        > int(row.get("batch_budget", 8))
        for row in records
    )
    tool_identity_events = sum(identity_stored(row) for row in records)
    tool_identity_linked = sum(
        identity_stored(row) and model_visible(row) for row in records
    )
    modern_identity_events = sum(
        bool(row.get("tool_input_sha256") or command_hashes(row)) for row in records
    )
    modern_identity_linked = sum(
        bool(row.get("tool_input_sha256") or command_hashes(row))
        and model_visible(row)
        for row in records
    )
    return {
        "hook_tracking": bool(records),
        "hook_event_count": len(records),
        "hook_code_browse_attempts": len(code_attempts),
        "hook_code_browse_events": code_browse_events,
        "hook_blocked_code_browses": blocked_code_browses,
        "hook_context_events": sum(row.get("event") == "context" for row in records),
        "hook_reminders": reminders,
        "hook_initial_reminders": initial,
        "hook_handoff_reminders": handoff,
        "hook_batch_reminders": batch,
        "hook_ceiling_reminders": ceiling,
        "hook_spawn_reminders": spawn,
        "hook_reminders_responded": responded,
        "hook_reminders_ignored": ignored,
        "hook_reminders_batched": batched,
        "hook_reminders_pending": pending,
        "hook_batch_hints": batch_hints,
        "hook_batch_violations": batch_violations,
        "hook_blocks": len(blocked_events),
        "hook_initial_blocks": gate_counts["initial"],
        "hook_handoff_blocks": gate_counts["handoff"],
        "hook_batch_blocks": gate_counts["batch"],
        "hook_ceiling_blocks": gate_counts["ceiling"],
        "hook_spawn_blocks": gate_counts["spawn_context"],
        "hook_affected_closure_attempts": len(closure_events),
        "hook_affected_closure_blocks": gate_counts["affected_closure"],
        "hook_affected_closure_block_counter": closure_blocks,
        "hook_affected_closure_passes": sum(
            not bool(row.get("blocked")) for row in closure_events
        ),
        "hook_affected_closure_recoveries": recoveries,
        "hook_affected_closure_recovery_events": recovery_events,
        "hook_affected_coverage_events": len(affected_coverage_events),
        "hook_latest_pending_affected_count": latest_pending_affected,
        "hook_spawn_events": len(spawn_events),
        "hook_spawn_context_packets": sum(
            bool(row.get("context_packet")) for row in spawn_events
        ),
        "hook_enforcement_active": bool(enforcement_events),
        "hook_enforcement_events": len(enforcement_events),
        "hook_enforced_code_browse_events": len(enforced_code_browses),
        "hook_enforced_max_gap": max(
            (
                int(row.get("raw_since_context", 0))
                for row in enforced_code_browses
            ),
            default=0,
        ),
        "hook_max_gap": max(
            (int(row["max_gap"]) for row in agent_summaries), default=0
        ),
        "hook_tool_identity_events": tool_identity_events,
        "hook_tool_identity_linked": tool_identity_linked,
        "hook_modern_identity_events": modern_identity_events,
        "hook_modern_identity_linked": modern_identity_linked,
        "hook_nested_tool_events": tool_identity_events - tool_identity_linked,
        "hook_agent_summaries": agent_summaries,
    }


def _nearest_rank_p95(values: list[int]) -> int:
    if not values:
        return 0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, math.ceil(len(ordered) * 0.95) - 1)]


def _audit_timestamp(value: Any) -> dt.datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def _browse_gap_metrics(
    browse_indices: Iterable[int],
    context_indices: Iterable[int],
) -> dict[str, Any]:
    browse = set(browse_indices)
    contexts = set(context_indices)
    if not browse:
        return {
            "raw_browse_gaps": [],
            "raw_browse_current_gap": 0,
            "raw_browse_max_gap": 0,
            "raw_browse_p95_gap": 0,
            "raw_browse_before_first_context": 0,
        }
    gaps: list[int] = []
    current = 0
    for index in sorted(browse | contexts):
        if index in contexts:
            if current:
                gaps.append(current)
            current = 0
        if index in browse:
            current += 1
    if current:
        gaps.append(current)
    first_context = min(contexts) if contexts else None
    before_first = sum(
        index < first_context if first_context is not None else True
        for index in browse
    )
    current_gap = sum(
        index > max(contexts) if contexts else True
        for index in browse
    )
    return {
        "raw_browse_gaps": gaps,
        "raw_browse_current_gap": current_gap,
        "raw_browse_max_gap": max(gaps, default=0),
        "raw_browse_p95_gap": _nearest_rank_p95(gaps),
        "raw_browse_before_first_context": before_first,
    }


def _repo_command_paths(command: str, *, root: Path = ROOT) -> list[str]:
    """Return repository file-shaped command terms for session auditing."""
    paths: list[str] = []
    seen: set[str] = set()
    for term in _file_terms(command, root=root, limit=256):
        normalized = term.removeprefix("HEAD:")
        suffix = Path(normalized).suffix.lower()
        candidate = root / normalized
        if suffix not in CODE_CONTEXT_SUFFIXES | DOCUMENT_SUFFIXES:
            try:
                if not candidate.is_file():
                    continue
            except OSError:
                continue
        low = normalized.lower()
        if low in seen:
            continue
        seen.add(low)
        paths.append(normalized)
    return paths


def _is_plan_spec_document(path: str) -> bool:
    normalized = path.replace("\\", "/").lower()
    name = Path(normalized).name
    if Path(name).suffix not in DOCUMENT_SUFFIXES:
        return False
    if name in _INSTRUCTION_DOCUMENTS or "/.agents/skills/" in f"/{normalized}":
        return False
    return True


def _is_code_context_path(path: str) -> bool:
    normalized = path.replace("\\", "/").lstrip("./")
    if Path(normalized).suffix.lower() not in CODE_CONTEXT_SUFFIXES:
        return False
    first = normalized.split("/", 1)[0]
    return first != "build" and (
        first in _CODE_BROWSE_ROOTS or "/" not in normalized
    )


def _is_app_owned_code_path(path: str) -> bool:
    """Return whether a changed path belongs to the application/test surface."""
    normalized = path.replace("\\", "/").lstrip("./")
    first = normalized.split("/", 1)[0]
    if first == "test_fixtures":
        return Path(normalized).suffix.lower() in CODE_CONTEXT_SUFFIXES
    return first != "graphify-arch" and _is_code_context_path(normalized)


def _command_browse_kinds(command: str, *, root: Path = ROOT) -> tuple[bool, bool]:
    """Return (plan/spec document read, raw code browse) for a shell command."""
    lower = command.lower()
    if not _RAW_BROWSE_COMMAND.search(lower) and not re.search(
        r"\bgit\s+(?:diff|show)\b", lower
    ):
        return False, False
    paths = _repo_command_paths(command, root=root)
    document_read = any(_is_plan_spec_document(path) for path in paths)
    code_browse = any(_is_code_context_path(path) for path in paths)
    if re.search(r"\b(?:find|grep|rg)\b", lower):
        roots = "|".join(re.escape(item) for item in sorted(_CODE_BROWSE_ROOTS))
        code_browse = code_browse or bool(
            re.search(rf"(?:^|[\s'\"])(?:{roots})(?:[\s/'\"]|$)", lower)
        )
    if re.search(r"\bgit\s+(?:diff|show)\b", lower):
        code_browse = True
    return document_read, code_browse


@functools.lru_cache(maxsize=512)
def _audit_line_count(root_text: str, relative_path: str) -> int | None:
    """Return the current line count for heuristic whole-file classification.

    Session stats intentionally avoid a per-file `git show` on dirty paths. In
    large active worktrees those subprocesses dominated a two-session audit,
    while HEAD is not necessarily the file version that existed at read time.
    Using the current file is deterministic, conservative for appended lines,
    and keeps this explicitly heuristic metric usable.
    """
    root = Path(root_text)
    try:
        data = (root / relative_path).read_bytes()
        return data.count(b"\n") + int(bool(data) and not data.endswith(b"\n"))
    except OSError:
        return None


def _normalize_audit_target(raw_path: str, *, root: Path) -> str | None:
    token = raw_path.strip("'\"`(),").removeprefix("HEAD:")
    terms = _file_terms(token, root=root, limit=2)
    if not terms:
        return None
    relative = terms[0].removeprefix("HEAD:")
    if not (root / relative).is_file():
        return None
    return relative


def _file_read_intervals(
    command: str,
    *,
    root: Path = ROOT,
) -> dict[str, list[tuple[int, int]]]:
    """Return line intervals emitted by direct whole/ranged file readers."""
    intervals: defaultdict[str, list[tuple[int, int]]] = defaultdict(list)
    root_text = str(root.resolve())

    def add(raw_path: str, start: int, end: str | int | None) -> None:
        relative = _normalize_audit_target(raw_path, root=root)
        if relative is None:
            return
        line_count = _audit_line_count(root_text, relative)
        if line_count is None:
            return
        if end is None:
            end_value = line_count
        elif end == "$":
            end_value = line_count
        else:
            end_value = min(line_count, int(end))
        if start <= end_value:
            intervals[relative].append((max(1, start), end_value))

    for match in _SED_RANGE.finditer(command):
        add(match.group("path"), int(match.group("start")), match.group("end"))
    for match in _HEAD_OR_TAIL.finditer(command):
        relative = _normalize_audit_target(match.group("path"), root=root)
        if relative is None:
            continue
        line_count = _audit_line_count(root_text, relative)
        if line_count is None:
            continue
        count = int(match.group("end"))
        start = 1 if match.group("kind") == "head" else max(1, line_count - count + 1)
        end = min(line_count, count) if match.group("kind") == "head" else line_count
        intervals[relative].append((start, end))
    for match in _WHOLE_STREAM.finditer(command):
        for path in _repo_command_paths(match.group("args"), root=root):
            add(path, 1, None)
    return dict(intervals)


def _merge_line_intervals(
    intervals: Iterable[tuple[int, int]],
) -> list[tuple[int, int]]:
    """Return inclusive line intervals as a sorted non-overlapping union."""
    merged: list[list[int]] = []
    for start, end in sorted(intervals):
        if end < start:
            continue
        if not merged or start > merged[-1][1] + 1:
            merged.append([start, end])
        else:
            merged[-1][1] = max(merged[-1][1], end)
    return [(start, end) for start, end in merged]


def _interval_line_total(intervals: Iterable[tuple[int, int]]) -> int:
    return sum(end - start + 1 for start, end in _merge_line_intervals(intervals))


def _interval_overlap_lines(
    left: Iterable[tuple[int, int]],
    right: Iterable[tuple[int, int]],
) -> int:
    """Count inclusive lines shared by two interval collections."""
    first = _merge_line_intervals(left)
    second = _merge_line_intervals(right)
    first_index = second_index = 0
    overlap = 0
    while first_index < len(first) and second_index < len(second):
        first_start, first_end = first[first_index]
        second_start, second_end = second[second_index]
        overlap += max(0, min(first_end, second_end) - max(first_start, second_start) + 1)
        if first_end <= second_end:
            first_index += 1
        else:
            second_index += 1
    return overlap


def _affected_paths_from_invocation(
    invocation: str,
    *,
    root: Path = ROOT,
) -> list[str]:
    """Extract only paths named after the helper's ``affected`` subcommand."""
    match = re.search(r"\baffected\b(?P<arguments>.*)$", invocation, re.DOTALL)
    if match is None:
        return []
    seen: set[str] = set()
    paths: list[str] = []
    for target in _file_terms(match.group("arguments"), root=root, limit=256):
        normalized = target.removeprefix("HEAD:")
        if normalized in seen or not _is_app_owned_code_path(normalized):
            continue
        seen.add(normalized)
        paths.append(normalized)
    return paths


def _document_read_metrics(
    events: Iterable[dict[str, Any]],
    call_outputs: dict[str, dict[str, Any]],
    *,
    root: Path = ROOT,
) -> dict[str, Any]:
    """Classify document coverage, revisits, overlap, and truncated output."""
    covered_by_path: defaultdict[str, list[tuple[int, int]]] = defaultdict(list)
    contributing_by_path: defaultdict[str, set[int]] = defaultdict(set)
    first_pass_calls: set[int] = set()
    targeted_revisit_calls: set[int] = set()
    redundant_calls: set[int] = set()
    truncated_calls: set[tuple[int, str]] = set()
    whole_calls: set[int] = set()
    whole_call_ids: set[str] = set()
    whole_files: set[str] = set()
    first_pass_targets = 0
    targeted_revisit_targets = 0
    redundant_targets = 0
    truncated_targets = 0
    first_pass_lines = 0
    overlap_lines = 0

    ordered_events = sorted(
        events,
        key=lambda event: (int(event["index"]), str(event["target"])),
    )
    for event in ordered_events:
        index = int(event["index"])
        call_id = str(event.get("call_id") or "")
        target = str(event["target"])
        requested = _merge_line_intervals(event.get("intervals") or [])
        if not requested:
            continue
        output = call_outputs.get(call_id, {}) if call_id else {}
        if output.get("truncated"):
            truncated_calls.add((index, call_id))
            truncated_targets += 1
            # Requested ranges are not claimed as model-visible coverage when
            # Codex says the result was cut off. A later bounded retry supplies
            # the confirmable first pass instead of becoming a fake reread.
            continue

        line_count = _audit_line_count(str(root.resolve()), target)
        prior = covered_by_path[target]
        requested_lines = _interval_line_total(requested)
        shared_lines = _interval_overlap_lines(requested, prior)
        new_lines = requested_lines - shared_lines
        overlap_lines += shared_lines
        prior_full = _intervals_cover_file(target, prior, root=root)

        if new_lines:
            first_pass_targets += 1
            first_pass_calls.add(index)
            first_pass_lines += new_lines
            contributing_by_path[target].add(index)
        elif prior_full and line_count is not None and requested_lines < line_count:
            targeted_revisit_targets += 1
            targeted_revisit_calls.add(index)
        else:
            redundant_targets += 1
            redundant_calls.add(index)

        covered_by_path[target] = _merge_line_intervals([*prior, *requested])
        if _intervals_cover_file(target, requested, root=root):
            whole_calls.add(index)
            whole_files.add(target)
            if call_id:
                whole_call_ids.add(call_id)

    covered_files = {
        target
        for target, intervals in covered_by_path.items()
        if _intervals_cover_file(target, intervals, root=root)
    }
    covered_calls: set[int] = set()
    for target in covered_files:
        covered_calls.update(contributing_by_path[target])

    truncated_call_ids = {call_id for _, call_id in truncated_calls if call_id}
    truncation_waste = round(
        sum(int(call_outputs[call_id].get("chars", 0)) for call_id in truncated_call_ids)
        / 4
    )
    truncation_dropped = sum(
        max(
            0,
            int(call_outputs[call_id].get("original_tokens", 0))
            - round(int(call_outputs[call_id].get("chars", 0)) / 4),
        )
        for call_id in truncated_call_ids
    )
    return {
        "document_read_target_count": len(ordered_events),
        "document_first_pass_read_calls": len(first_pass_calls),
        "document_first_pass_read_targets": first_pass_targets,
        "document_first_pass_lines": first_pass_lines,
        "document_targeted_revisit_calls": len(targeted_revisit_calls),
        "document_targeted_revisit_targets": targeted_revisit_targets,
        "document_overlap_lines": overlap_lines,
        "document_redundant_read_calls": len(redundant_calls),
        "document_redundant_read_targets": redundant_targets,
        "document_truncated_read_calls": len(truncated_calls),
        "document_truncated_read_targets": truncated_targets,
        "document_truncation_waste_tokens_estimate": truncation_waste,
        "document_truncation_dropped_tokens_estimate": truncation_dropped,
        "whole_document_read_calls": len(whole_calls),
        "whole_document_file_count": len(whole_files),
        "whole_document_call_ids": whole_call_ids,
        "covered_document_read_calls": len(covered_calls),
        "covered_document_file_count": len(covered_files),
    }


def _affected_coverage_metrics(
    events: Iterable[dict[str, Any]],
    canonical_records: Iterable[dict[str, Any]],
    call_outputs: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    """Replay edit/impact occurrences, crediting only successful affected calls."""
    canonical_candidates = []
    for row in canonical_records:
        canonical_candidates.append(
            {
                "digest": str(row.get("question_sha256") or ""),
                "timestamp": _audit_timestamp(row.get("ts")),
                "claimed": False,
            }
        )

    def claim_canonical(
        event: dict[str, Any],
        *,
        allow_untimed: bool,
    ) -> bool:
        digest = hashlib.sha256(
            "\n".join(sorted(str(path) for path in event["paths"])).encode()
        ).hexdigest()[:16]
        event_time = event.get("timestamp")
        matches: list[tuple[float, dict[str, Any]]] = []
        for candidate in canonical_candidates:
            if candidate["claimed"] or candidate["digest"] != digest:
                continue
            candidate_time = candidate["timestamp"]
            if event_time is not None and candidate_time is not None:
                distance = abs((event_time - candidate_time).total_seconds())
                if distance > 120:
                    continue
            else:
                if not allow_untimed:
                    continue
                distance = 0.0
            matches.append((distance, candidate))
        if not matches:
            return False
        selected = min(matches, key=lambda item: item[0])[1]
        selected["claimed"] = True
        return True

    pending: dict[str, int] = {}
    covered_files: set[str] = set()
    covered_pending_paths = 0
    full_calls = partial_calls = unrelated_calls = no_pending_calls = 0
    successful_calls = failed_calls = unverified_calls = 0

    for event in sorted(events, key=lambda row: int(row["index"])):
        if event["kind"] == "patch":
            for target in event["paths"]:
                pending.pop(target, None)
                pending[target] = int(event["index"])
            continue

        output = call_outputs.get(str(event.get("call_id") or ""), {})
        exit_code = output.get("exit_code")
        # An explicit failure cannot borrow a canonical record from a later
        # same-path retry. Otherwise canonical usage proves that affected()
        # reached its measured append, while an explicit zero exit is a valid
        # fallback for logging-disabled runs.
        canonical_success = claim_canonical(
            event,
            allow_untimed=not (isinstance(exit_code, int) and exit_code != 0),
        )
        successful = canonical_success or exit_code == 0
        if not successful:
            if isinstance(exit_code, int) and exit_code != 0:
                failed_calls += 1
            else:
                unverified_calls += 1
            continue

        successful_calls += 1
        pending_before = set(pending)
        covered_pending = pending_before.intersection(event["paths"])
        if not pending_before:
            no_pending_calls += 1
        elif covered_pending == pending_before:
            full_calls += 1
        elif covered_pending:
            partial_calls += 1
        else:
            unrelated_calls += 1
        covered_pending_paths += len(covered_pending)
        covered_files.update(covered_pending)
        for target in covered_pending:
            pending.pop(target, None)

    pending_paths = list(pending)
    patch_events = [event for event in events if event["kind"] == "patch"]
    if not patch_events:
        coverage_status = "not_applicable"
    elif not pending_paths:
        coverage_status = "full"
    elif covered_pending_paths:
        coverage_status = "partial"
    else:
        coverage_status = "none"
    return {
        "affected_coverage_status": coverage_status,
        "affected_pending_path_count": len(pending_paths),
        "affected_pending_paths": pending_paths,
        "affected_covered_pending_paths": covered_pending_paths,
        "affected_covered_file_count": len(covered_files),
        "affected_full_coverage_calls": full_calls,
        "affected_partial_coverage_calls": partial_calls,
        "affected_unrelated_calls": unrelated_calls,
        "affected_no_pending_calls": no_pending_calls,
        "affected_successful_calls": successful_calls,
        "affected_failed_calls": failed_calls,
        "affected_unverified_calls": unverified_calls,
        "affected_after_latest_change": coverage_status in {
            "not_applicable",
            "full",
        },
    }


def _intervals_cover_file(
    relative_path: str,
    intervals: Iterable[tuple[int, int]],
    *,
    root: Path = ROOT,
) -> bool:
    line_count = _audit_line_count(str(root.resolve()), relative_path)
    if line_count is None:
        return False
    covered_through = 0
    for start, end in sorted(intervals):
        if start > covered_through + 1:
            return False
        covered_through = max(covered_through, end)
        if covered_through >= line_count:
            return True
    return covered_through >= line_count


def _whole_file_targets(command: str, *, root: Path = ROOT) -> set[str]:
    """Heuristically identify files fully emitted by one shell command."""
    return {
        path
        for path, intervals in _file_read_intervals(command, root=root).items()
        if _intervals_cover_file(path, intervals, root=root)
    }


@functools.lru_cache(maxsize=1024)
def _session_metadata(path: Path) -> dict[str, Any]:
    """Read the small rollout header used for cohorting and anonymous joins."""
    try:
        with path.open(encoding="utf-8") as handle:
            for _ in range(40):
                line = handle.readline()
                if not line:
                    break
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if row.get("type") == "session_meta":
                    payload = row.get("payload")
                    if not isinstance(payload, dict):
                        break
                    session_id = payload.get("id")
                    thread_source = payload.get("thread_source")
                    source_text = json.dumps(thread_source, sort_keys=True).lower()
                    return {
                        "session_id": str(session_id) if session_id else None,
                        "started_at": payload.get("timestamp") or row.get("timestamp"),
                        "session_kind": (
                            "subagent" if "subagent" in source_text else "root"
                        ),
                        "cli_version": str(payload.get("cli_version") or "unknown"),
                        "thread_source": thread_source,
                    }
    except OSError:
        pass
    return {
        "session_id": None,
        "started_at": None,
        "session_kind": "unknown",
        "cli_version": "unknown",
        "thread_source": None,
    }


def _session_id(path: Path) -> str | None:
    return _session_metadata(path).get("session_id")


def _session_digest(session_id: str | None) -> str:
    if not session_id:
        return "unknown"
    return hashlib.sha256(session_id.encode()).hexdigest()[:16]


def _canonical_tool_input(value: Any) -> str:
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError:
            return value.strip()
    try:
        return json.dumps(value, sort_keys=True, separators=(",", ":"))
    except (TypeError, ValueError):
        return str(value)


def _tool_input_digest(tool_name: Any, tool_input: Any) -> str:
    short_name = str(tool_name or "").strip().lower().rsplit(".", 1)[-1]
    return _session_digest(short_name + "\0" + _canonical_tool_input(tool_input))


def _command_digest(command: str) -> str:
    return _session_digest(command.strip())


def _session_files(sessions_root: Path) -> list[Path]:
    try:
        files = list(sessions_root.rglob("*.jsonl"))
    except OSError:
        return []
    return sorted(
        files,
        key=lambda path: path.stat().st_mtime if path.exists() else 0,
        reverse=True,
    )


def _resolve_session_log(selector: str, *, sessions_root: Path) -> Path:
    files = _session_files(sessions_root)
    if not files:
        raise SystemExit(f"No Codex rollout logs found under {sessions_root}")
    current = os.environ.get("CODEX_SESSION_ID")
    current_digest = _session_digest(current) if current else None
    if selector == "latest":
        return files[0]
    if selector == "latest-other":
        for path in files:
            if _session_digest(_session_id(path)) != current_digest:
                return path
        raise SystemExit("No Codex rollout log other than the current session was found")
    wanted = current if selector == "current" else selector
    if not wanted:
        raise SystemExit("CODEX_SESSION_ID is unavailable; pass --session latest or a hash")
    for path in files:
        raw_id = _session_id(path)
        digest = _session_digest(raw_id)
        if raw_id == wanted or digest == wanted or digest.startswith(wanted):
            return path
    raise SystemExit(f"No Codex rollout log matched session selector {selector!r}")


def _session_audit(
    path: Path,
    *,
    root: Path = ROOT,
    usage_path: Path = STATS_PATH,
    reminder_path: Path = REMINDER_STATS_PATH,
) -> dict[str, Any]:
    session_metadata = _session_metadata(path)
    session_sha256 = _session_digest(session_metadata.get("session_id"))
    reminder_records = _reminder_records_for_session(
        session_sha256, path=reminder_path
    )
    blocked_candidates: list[dict[str, Any]] = []
    for row in reminder_records:
        if not row.get("blocked"):
            continue
        raw_commands = row.get("command_sha256s")
        blocked_candidates.append(
            {
                "tool": str(row.get("tool_use_sha256") or ""),
                "input": str(row.get("tool_input_sha256") or ""),
                "commands": {
                    str(value)
                    for value in (
                        raw_commands if isinstance(raw_commands, list) else [raw_commands]
                    )
                    if value
                },
                "timestamp": _audit_timestamp(row.get("ts")),
                "claimed": False,
            }
        )

    def claim_blocked_rollout(
        *,
        tool_hash: str,
        input_hash: str,
        command_hashes: set[str],
        timestamp: dt.datetime | None,
    ) -> bool:
        matches: list[tuple[float, dict[str, Any]]] = []
        for candidate in blocked_candidates:
            if candidate["claimed"]:
                continue
            tool_match = bool(tool_hash and tool_hash == candidate["tool"])
            input_match = bool(input_hash and input_hash == candidate["input"])
            commands_match = bool(
                command_hashes and command_hashes.issubset(candidate["commands"])
            )
            if not (tool_match or input_match or commands_match):
                continue
            candidate_time = candidate["timestamp"]
            if timestamp is None or candidate_time is None:
                if not tool_match:
                    continue
                distance = 0.0
            else:
                distance = abs((timestamp - candidate_time).total_seconds())
                if distance > 10.0 and not tool_match:
                    continue
            matches.append((distance, candidate))
        if not matches:
            return False
        selected = min(matches, key=lambda item: item[0])[1]
        selected["claimed"] = True
        return True
    tool_calls = 0
    blocked_rollout_calls = 0
    exec_commands = 0
    document_read_indices: list[int] = []
    code_browse_indices: list[int] = []
    compact_code_indices: list[int] = []
    compact_code_events: list[tuple[int, dt.datetime | None, bool]] = []
    compact_code_unlogged_indices: list[int] = []
    affected_indices: list[int] = []
    impact_events: list[dict[str, Any]] = []
    measured_native_indices: list[int] = []
    direct_native_code_indices: list[int] = []
    native_document_queries = 0
    branch_marker_indices: list[int] = []
    code_change_indices: list[int] = []
    changed_code_files: set[str] = set()
    code_change_path_occurrences = 0
    whole_code_calls: set[int] = set()
    document_files: set[str] = set()
    code_files: set[str] = set()
    whole_code_files: set[str] = set()
    covered_code_calls: set[int] = set()
    covered_code_files: set[str] = set()
    read_coverage: defaultdict[str, list[tuple[int, int, int]]] = defaultdict(list)
    document_read_events: list[dict[str, Any]] = []
    compact_document_queries = 0
    compact_document_events: list[tuple[int, dt.datetime | None, bool]] = []
    compact_document_unlogged_queries = 0
    call_output_chars: dict[str, int] = {}
    call_outputs: dict[str, dict[str, Any]] = {}
    document_call_ids: set[str] = set()
    code_call_ids: set[str] = set()
    whole_code_call_ids: set[str] = set()
    rollout_tool_hashes: set[str] = set()
    rollout_tool_input_hashes: set[str] = set()
    rollout_command_hashes: set[str] = set()

    try:
        handle = path.open(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"Unable to read Codex rollout log {path}: {exc}") from exc
    with handle:
        for line in handle:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            payload = row.get("payload") if isinstance(row, dict) else None
            if not isinstance(payload, dict):
                continue
            payload_type = payload.get("type")
            if payload_type in {"custom_tool_call_output", "function_call_output"}:
                call_id = payload.get("call_id")
                if call_id:
                    details = _tool_output_details(payload.get("output"))
                    call_outputs[str(call_id)] = details
                    call_output_chars[str(call_id)] = int(details["chars"])
                continue
            if payload_type not in {"custom_tool_call", "function_call"}:
                continue

            tool_calls += 1
            row_timestamp = _audit_timestamp(row.get("timestamp"))
            call_id = str(payload.get("call_id") or "")
            call_tool_hash = _session_digest(call_id) if call_id else ""
            if call_id:
                rollout_tool_hashes.add(call_tool_hash)
            raw_tool_input = payload.get("input")
            if raw_tool_input is None:
                raw_tool_input = payload.get("arguments")
            if raw_tool_input is None:
                raw_tool_input = ""
            call_input_hash = _tool_input_digest(
                payload.get("name"), raw_tool_input
            )
            rollout_tool_input_hashes.add(call_input_hash)
            tool_input = raw_tool_input
            if not isinstance(tool_input, str):
                try:
                    tool_input = json.dumps(tool_input, sort_keys=True)
                except (TypeError, ValueError):
                    tool_input = ""
            commands = _exec_commands_from_tool_input(tool_input)
            call_command_hashes = {
                _command_digest(command) for command in commands if command.strip()
            }
            rollout_command_hashes.update(call_command_hashes)
            exec_commands += len(commands)
            if claim_blocked_rollout(
                tool_hash=call_tool_hash,
                input_hash=call_input_hash,
                command_hashes=call_command_hashes,
                timestamp=row_timestamp,
            ):
                blocked_rollout_calls += 1
                continue
            call_document_read = False
            call_code_browse = False
            call_whole_documents: set[str] = set()
            call_whole_code: set[str] = set()
            call_document_intervals: defaultdict[
                str, list[tuple[int, int]]
            ] = defaultdict(list)

            patch_paths = _patch_paths_from_tool_input(tool_input, root=root)
            code_patch_paths = {
                target for target in patch_paths if _is_app_owned_code_path(target)
            }
            if code_patch_paths:
                code_change_indices.append(tool_calls)
                changed_code_files.update(code_patch_paths)
                code_change_path_occurrences += len(code_patch_paths)
                impact_events.append(
                    {
                        "kind": "patch",
                        "index": tool_calls,
                        "paths": sorted(code_patch_paths),
                    }
                )

            for command in commands:
                command_paths = _repo_command_paths(command, root=root)
                document_read, code_browse = _command_browse_kinds(
                    command, root=root
                )
                call_document_read = call_document_read or document_read
                call_code_browse = call_code_browse or code_browse
                if document_read:
                    document_files.update(
                        target
                        for target in command_paths
                        if _is_plan_spec_document(target)
                    )
                if code_browse:
                    code_files.update(
                        target
                        for target in command_paths
                        if _is_code_context_path(target)
                    )
                for operation, invocation in _helper_invocations(command):
                    document_query = bool(_document_terms(invocation, root=root))
                    logging_disabled = bool(
                        re.search(
                            r"(?:^|\s)GRAPHIFY_CONTEXT_LOG=(?:0|'0'|\"0\")(?:\s|$)",
                            invocation,
                        )
                    )
                    if operation == "query":
                        if document_query:
                            compact_document_queries += 1
                            compact_document_events.append(
                                (tool_calls, row_timestamp, logging_disabled)
                            )
                            compact_document_unlogged_queries += int(
                                logging_disabled
                            )
                        else:
                            compact_code_indices.append(tool_calls)
                            compact_code_events.append(
                                (tool_calls, row_timestamp, logging_disabled)
                            )
                            if logging_disabled:
                                compact_code_unlogged_indices.append(tool_calls)
                    elif operation == "affected":
                        affected_indices.append(tool_calls)
                        impact_events.append(
                            {
                                "kind": "affected",
                                "index": tool_calls,
                                "call_id": call_id,
                                "timestamp": row_timestamp,
                                "paths": set(
                                    _affected_paths_from_invocation(
                                        invocation,
                                        root=root,
                                    )
                                ),
                            }
                        )
                    elif operation == "native":
                        if document_query:
                            native_document_queries += 1
                        else:
                            measured_native_indices.append(tool_calls)
                    elif operation == "checkpoint" and re.search(
                        r"(?:^|\s)--new-branch(?:\s|$)", invocation
                    ):
                        branch_marker_indices.append(tool_calls)
                for invocation in _direct_native_invocations(command):
                    if _document_terms(invocation, root=root):
                        native_document_queries += 1
                    else:
                        direct_native_code_indices.append(tool_calls)
                command_intervals = _file_read_intervals(command, root=root)
                for target, intervals in command_intervals.items():
                    read_coverage[target].extend(
                        (tool_calls, start, end) for start, end in intervals
                    )
                    if _is_plan_spec_document(target):
                        call_document_intervals[target].extend(intervals)
                for target in (
                    candidate
                    for candidate, intervals in command_intervals.items()
                    if _intervals_cover_file(candidate, intervals, root=root)
                ):
                    if _is_plan_spec_document(target):
                        call_whole_documents.add(target)
                    elif _is_code_context_path(target):
                        call_whole_code.add(target)
            if call_document_read:
                document_read_indices.append(tool_calls)
                if call_id:
                    document_call_ids.add(call_id)
            if call_code_browse:
                code_browse_indices.append(tool_calls)
                if call_id:
                    code_call_ids.add(call_id)
            if call_whole_documents:
                # Final whole-document accounting is output-aware below; a
                # requested full stream that Codex truncated is not called a
                # completed one-call read.
                pass
            if call_whole_code:
                whole_code_calls.add(tool_calls)
                whole_code_files.update(call_whole_code)
                if call_id:
                    whole_code_call_ids.add(call_id)
            for target, intervals in call_document_intervals.items():
                document_read_events.append(
                    {
                        "index": tool_calls,
                        "call_id": call_id,
                        "target": target,
                        "intervals": intervals,
                    }
                )

    for target, spans in read_coverage.items():
        intervals = [(start, end) for _, start, end in spans]
        if not _intervals_cover_file(target, intervals, root=root):
            continue
        contributing_calls = {index for index, _, _ in spans}
        if _is_code_context_path(target):
            covered_code_files.add(target)
            covered_code_calls.update(contributing_calls)

    document_metrics = _document_read_metrics(
        document_read_events,
        call_outputs,
        root=root,
    )

    handoff_status = "not_applicable"
    handoff_detail = "no plan/spec read followed by raw code browsing"
    if document_read_indices:
        first_document = min(document_read_indices)
        later_code = [index for index in code_browse_indices if index >= first_document]
        if later_code:
            first_code = min(later_code)
            last_document = max(
                index for index in document_read_indices if index <= first_code
            )
            qualifying = [
                index
                for index in compact_code_indices
                if last_document < index < first_code
            ]
            if qualifying:
                handoff_status = "pass"
                handoff_detail = (
                    f"code-only Graphify call #{qualifying[-1]} preceded raw code "
                    f"browse #{first_code}"
                )
            else:
                handoff_status = "fail"
                handoff_detail = (
                    f"raw code browse #{first_code} followed document read "
                    f"#{last_document} without an intervening code-only Graphify query"
                )

    usage_records = _usage_records_for_session(session_sha256, path=usage_path)
    reminder_metrics = _reminder_metrics(
        reminder_records,
        model_visible_tool_hashes=rollout_tool_hashes,
        model_visible_input_hashes=rollout_tool_input_hashes,
        model_visible_command_hashes=rollout_command_hashes,
    )
    canonical_queries = [
        row
        for row in usage_records
        if row.get("operation", "query") == "query"
        and row.get("route") != "document_handoff"
    ]
    canonical_document_queries = [
        row
        for row in usage_records
        if row.get("operation", "query") == "query"
        and row.get("route") == "document_handoff"
    ]
    canonical_native = [
        row for row in usage_records if row.get("operation") == "native_query"
    ]
    canonical_affected = [
        row for row in usage_records if row.get("operation") == "affected"
    ]
    impact_metrics = _affected_coverage_metrics(
        impact_events,
        canonical_affected,
        call_outputs,
    )
    refinement_counts = Counter(
        str(row["refinement_of"])
        for row in canonical_queries
        if row.get("query_stage") == "refinement" and row.get("refinement_of")
    )
    broad_initials = [
        row
        for row in canonical_queries
        if row.get("query_stage") == "initial"
        and row.get("confidence") == "broad"
        and row.get("route") == "architecture"
    ]
    invalid_broad_followups = [
        row
        for row in broad_initials
        if refinement_counts[str(row.get("query_id"))] != 1
    ]
    fallback_queries = [
        row for row in canonical_queries if row.get("route") == "full_graph_fallback"
    ]
    fallback_followup_counts = Counter(
        str(row["followup_of"])
        for row in canonical_native
        if row.get("followup_of")
    )
    linked_fallbacks = [
        row
        for row in fallback_queries
        if fallback_followup_counts[str(row.get("query_id"))] == 1
    ]
    missing_fallbacks = [
        row
        for row in fallback_queries
        if fallback_followup_counts[str(row.get("query_id"))] == 0
    ]
    duplicate_fallbacks = [
        row
        for row in fallback_queries
        if fallback_followup_counts[str(row.get("query_id"))] > 1
    ]
    legacy_fallback_credit = min(
        len(missing_fallbacks), len(direct_native_code_indices)
    )
    fallback_followups = len(linked_fallbacks) + legacy_fallback_credit

    native_code_indices = measured_native_indices + direct_native_code_indices
    cadence = _browse_gap_metrics(
        code_browse_indices,
        compact_code_indices + native_code_indices,
    )
    branch_compliant = 0
    for marker in sorted(set(branch_marker_indices)):
        next_query = min(
            (index for index in compact_code_indices if index >= marker),
            default=None,
        )
        next_browse = min(
            (index for index in code_browse_indices if index >= marker),
            default=None,
        )
        if next_query is not None and (
            next_browse is None or next_query < next_browse
        ):
            branch_compliant += 1

    def output_tokens(call_ids: set[str]) -> int:
        return round(sum(call_output_chars.get(call_id, 0) for call_id in call_ids) / 4)

    whole_document_call_ids = set(document_metrics.pop("whole_document_call_ids"))

    latest_context = next(
        (
            row
            for row in reversed(usage_records)
            if row.get("operation") in {"query", "native_query"}
            and row.get("route") != "document_handoff"
        ),
        None,
    )
    usage_times = [
        parsed
        for row in usage_records
        if (parsed := _audit_timestamp(row.get("ts"))) is not None
    ]
    telemetry_cutoff = (
        min(usage_times) - dt.timedelta(minutes=5) if usage_times else None
    )

    def pretelemetry_count(
        events: Iterable[tuple[int, dt.datetime | None, bool]],
    ) -> int:
        if telemetry_cutoff is None:
            return 0
        return sum(
            not logging_disabled
            and timestamp is not None
            and timestamp < telemetry_cutoff
            for _, timestamp, logging_disabled in events
        )

    compact_code_pretelemetry = pretelemetry_count(compact_code_events)
    compact_document_pretelemetry = pretelemetry_count(compact_document_events)
    compact_code_logged_parsed = (
        len(compact_code_indices)
        - len(compact_code_unlogged_indices)
        - compact_code_pretelemetry
    )
    compact_document_logged_parsed = (
        compact_document_queries
        - compact_document_unlogged_queries
        - compact_document_pretelemetry
    )
    compact_count = (
        len(canonical_queries) if usage_records else len(compact_code_indices)
    )
    document_query_count = (
        len(canonical_document_queries)
        if usage_records
        else compact_document_queries
    )

    return {
        "session_sha256": session_sha256,
        "session_kind": session_metadata.get("session_kind", "unknown"),
        "started_at": session_metadata.get("started_at"),
        "cli_version": session_metadata.get("cli_version", "unknown"),
        "tool_calls": tool_calls,
        "blocked_rollout_calls": blocked_rollout_calls,
        "exec_commands": exec_commands,
        "document_read_calls": len(set(document_read_indices)),
        "document_file_count": len(document_files),
        "document_unique_file_count": len(document_files),
        "document_output_tokens_estimate": output_tokens(document_call_ids),
        "whole_document_output_tokens_estimate": output_tokens(
            whole_document_call_ids
        ),
        **document_metrics,
        "code_browse_calls": len(set(code_browse_indices)),
        "code_file_count": len(code_files),
        "code_output_tokens_estimate": output_tokens(code_call_ids),
        "whole_code_read_calls": len(whole_code_calls),
        "whole_code_file_count": len(whole_code_files),
        "whole_code_output_tokens_estimate": output_tokens(whole_code_call_ids),
        "covered_code_read_calls": len(covered_code_calls),
        "covered_code_file_count": len(covered_code_files),
        "compact_code_queries": compact_count,
        "compact_code_queries_executed": len(compact_code_indices),
        "compact_code_queries_parsed": compact_code_logged_parsed,
        "compact_code_queries_unlogged": len(compact_code_unlogged_indices),
        "compact_code_queries_pretelemetry": compact_code_pretelemetry,
        "compact_document_queries": document_query_count,
        "compact_document_queries_executed": compact_document_queries,
        "compact_document_queries_parsed": compact_document_logged_parsed,
        "compact_document_queries_unlogged": compact_document_unlogged_queries,
        "compact_document_queries_pretelemetry": compact_document_pretelemetry,
        "native_code_queries": len(canonical_native)
        if usage_records
        else len(native_code_indices),
        "native_code_queries_parsed": len(native_code_indices),
        "native_document_queries": native_document_queries,
        "affected_queries": len(canonical_affected)
        if usage_records
        else len(affected_indices),
        "affected_queries_parsed": len(affected_indices),
        "canonical_usage_linked": bool(usage_records),
        "canonical_usage_records": len(usage_records),
        "graphify_output_tokens_estimate": sum(
            int(row.get("result_tokens_estimate", 0)) for row in usage_records
        ),
        "broad_initial_queries": len(broad_initials),
        "broad_refined_queries": len(broad_initials) - len(invalid_broad_followups),
        "unrefined_broad_query_ids": [
            str(row.get("query_id")) for row in invalid_broad_followups
        ],
        "duplicate_broad_refinement_query_ids": [
            str(row.get("query_id"))
            for row in broad_initials
            if refinement_counts[str(row.get("query_id"))] > 1
        ],
        "fallback_queries": len(fallback_queries),
        "fallback_followups": fallback_followups,
        "unfollowed_fallback_query_ids": [
            *(str(row.get("query_id")) for row in duplicate_fallbacks),
            *(
                str(row.get("query_id"))
                for row in missing_fallbacks[legacy_fallback_credit:]
            ),
        ],
        "duplicate_fallback_followup_query_ids": [
            str(row.get("query_id")) for row in duplicate_fallbacks
        ],
        "branch_markers": len(set(branch_marker_indices)),
        "branch_graphify_first": branch_compliant,
        "code_change_calls": len(set(code_change_indices)),
        "code_change_path_occurrences": code_change_path_occurrences,
        "changed_code_file_count": len(changed_code_files),
        **impact_metrics,
        "latest_query_id": str(latest_context.get("query_id"))
        if latest_context
        else None,
        "latest_evidence_digest": str(latest_context.get("evidence_digest"))
        if latest_context and latest_context.get("evidence_digest")
        else None,
        "handoff_status": handoff_status,
        "handoff_detail": handoff_detail,
        **reminder_metrics,
        **cadence,
    }


def _session_audit_lines(audit: dict[str, Any]) -> list[str]:
    lines = [
        f"Codex/Graphify session audit: {audit['session_sha256']} "
        f"({audit['tool_calls']} tool calls; {audit['session_kind']}; "
        f"CLI {audit['cli_version']})",
        "- plan/spec documents: "
        f"unique={audit['document_unique_file_count']}; "
        f"read-calls={audit['document_read_calls']}; "
        f"read-targets={audit['document_read_target_count']}; "
        f"whole-in-one-call={audit['whole_document_read_calls']} calls/"
        f"{audit['whole_document_file_count']} files; output≈"
        f"{audit['document_output_tokens_estimate']} tokens",
        "- document coverage: first-pass="
        f"{audit['document_first_pass_read_calls']} calls/"
        f"{audit['document_first_pass_read_targets']} targets/"
        f"{audit['covered_document_file_count']} complete files/"
        f"{audit['document_first_pass_lines']} unique lines; targeted-revisits="
        f"{audit['document_targeted_revisit_calls']} calls/"
        f"{audit['document_targeted_revisit_targets']} targets; overlap="
        f"{audit['document_overlap_lines']} lines; redundant="
        f"{audit['document_redundant_read_calls']} calls/"
        f"{audit['document_redundant_read_targets']} targets",
        "- document truncation: "
        f"{audit['document_truncated_read_calls']} calls/"
        f"{audit['document_truncated_read_targets']} targets; visible-retry-waste≈"
        f"{audit['document_truncation_waste_tokens_estimate']} tokens; "
        f"dropped-before-model≈"
        f"{audit['document_truncation_dropped_tokens_estimate']} tokens",
        "- executed raw code browsing: "
        f"reads={audit['code_browse_calls']} calls/{audit['code_file_count']} files; "
        f"denied rollout cells excluded={audit['blocked_rollout_calls']}; "
        f"whole-in-one-call={audit['whole_code_read_calls']} calls/"
        f"{audit['whole_code_file_count']} files; cumulative-full="
        f"{audit['covered_code_read_calls']} calls/"
        f"{audit['covered_code_file_count']} files; output≈"
        f"{audit['code_output_tokens_estimate']} tokens; whole-output≈"
        f"{audit['whole_code_output_tokens_estimate']} tokens",
        "- executed raw browse cadence: "
        f"current-gap={audit['raw_browse_current_gap']}; "
        f"max-gap={audit['raw_browse_max_gap']}; "
        f"p95-gap={audit['raw_browse_p95_gap']}; "
        f"before-first-context={audit['raw_browse_before_first_context']}",
        "- Graphify navigation: "
        f"compact-code={audit['compact_code_queries']} canonical/"
        f"{audit['compact_code_queries_parsed']} logged-rollout-parsed"
        f" (+{audit['compact_code_queries_unlogged']} logging-disabled; "
        f"+{audit['compact_code_queries_pretelemetry']} pre-telemetry; "
        f"{audit['compact_code_queries_executed']} executed); "
        f"compact-document={audit['compact_document_queries']}; "
        f"native-code={audit['native_code_queries']}; "
        f"affected={audit['affected_queries']}; output≈"
        f"{audit['graphify_output_tokens_estimate']} tokens",
        "- required follow-ups: "
        f"broad-refinement={audit['broad_refined_queries']}/"
        f"{audit['broad_initial_queries']}; fallback-follow-up="
        f"{audit['fallback_followups']}/{audit['fallback_queries']}; "
        f"affected-coverage={str(audit['affected_coverage_status']).upper()}; "
        f"pending={audit['affected_pending_path_count']}",
        "- affected path debt: "
        f"successful={audit['affected_successful_calls']}; "
        f"failed={audit['affected_failed_calls']}; "
        f"unverified={audit['affected_unverified_calls']}; "
        f"covered-pending={audit['affected_covered_pending_paths']}; "
        f"full-calls={audit['affected_full_coverage_calls']}; "
        f"partial-calls={audit['affected_partial_coverage_calls']}; "
        f"unrelated-calls={audit['affected_unrelated_calls']}; "
        f"no-debt-calls={audit['affected_no_pending_calls']}; pending-paths="
        f"{','.join(audit['affected_pending_paths']) or 'none'}",
        "- branch markers: "
        f"Graphify-first={audit['branch_graphify_first']}/"
        f"{audit['branch_markers']}",
        f"- plan→code handoff: {str(audit['handoff_status']).upper()} — "
        f"{audit['handoff_detail']}",
        "- output-token and whole-file counts are heuristic; truncated ranges are not credited as confirmed coverage",
    ]
    if audit["hook_tracking"]:
        lines.insert(
            -1,
            "- enforcement hook: "
            f"enforced-era-raw={audit['hook_enforced_code_browse_events']} "
            f"max-gap={audit['hook_enforced_max_gap']}; "
            f"all-ledger-raw={audit['hook_code_browse_events']} vs "
            f"rollout-browse-cells={audit['code_browse_calls']}; "
            f"attempts={audit['hook_code_browse_attempts']}; "
            f"blocks={audit['hook_blocks']} "
            f"(initial={audit['hook_initial_blocks']}, "
            f"handoff={audit['hook_handoff_blocks']}, "
            f"batch={audit['hook_batch_blocks']}, "
            f"ceiling={audit['hook_ceiling_blocks']}, "
            f"spawn={audit['hook_spawn_blocks']}, "
            f"affected-closure={audit['hook_affected_closure_blocks']}); "
            f"contexts={audit['hook_context_events']}; "
            f"legacy-advisories={audit['hook_reminders']} "
            f"(initial={audit['hook_initial_reminders']}, "
            f"handoff={audit['hook_handoff_reminders']}, "
            f"batch={audit['hook_batch_reminders']}, "
            f"ceiling={audit['hook_ceiling_reminders']}, "
            f"spawn={audit['hook_spawn_reminders']}); outcomes="
            f"responded={audit['hook_reminders_responded']}, "
            f"ignored={audit['hook_reminders_ignored']}, "
            f"same-batch={audit['hook_reminders_batched']}, "
            f"pending={audit['hook_reminders_pending']}",
        )
        lines.insert(
            -1,
            "- affected closure hook: "
            f"attempts={audit['hook_affected_closure_attempts']}; "
            f"blocks={audit['hook_affected_closure_blocks']} "
            f"(counter={audit['hook_affected_closure_block_counter']}); "
            f"passes={audit['hook_affected_closure_passes']}; "
            f"coverage-events={audit['hook_affected_coverage_events']}; "
            f"recoveries={audit['hook_affected_closure_recoveries']}; "
            f"latest-pending={audit['hook_latest_pending_affected_count']}",
        )
        summaries = audit.get("hook_agent_summaries") or []
        if summaries:
            worst = summaries[0]
            lines.insert(
                -1,
                "- enforcement agents/batches: "
                f"agents={len(summaries)}; worst={worst['agent_sha256']} "
                f"raw={worst['code_browse_events']}/"
                f"{worst['code_browse_attempts']} max-gap={worst['max_gap']} "
                f"enforced-max={worst['enforced_max_gap']} "
                f"blocks={worst['blocks']}; "
                f"multi-command-cells={audit['hook_batch_hints']}; "
                f"over-budget={audit['hook_batch_violations']}; "
                f"spawn-packets={audit['hook_spawn_context_packets']}/"
                f"{audit['hook_spawn_events']}; identity stored="
                f"{audit['hook_tool_identity_events']}/"
                f"{audit['hook_event_count']} linked-to-rollout="
                f"{audit['hook_tool_identity_linked']}/"
                f"{audit['hook_tool_identity_events']} unlinked="
                f"{audit['hook_nested_tool_events']}; modern-linked="
                f"{audit['hook_modern_identity_linked']}/"
                f"{audit['hook_modern_identity_events']}",
            )
    if audit.get("latest_query_id"):
        lines.append(
            "- carry forward: "
            f"query_id={audit['latest_query_id']} evidence_digest="
            f"{audit.get('latest_evidence_digest') or 'unavailable'}"
        )
    if audit["compact_code_queries"] != audit["compact_code_queries_parsed"]:
        lines.append(
            "- measurement warning: canonical compact count differs from rollout parsing"
        )
    return lines


def _aggregate_session_audit_lines(audits: list[dict[str, Any]]) -> list[str]:
    eligible = [
        audit for audit in audits if audit["handoff_status"] in {"pass", "fail"}
    ]
    passed = sum(audit["handoff_status"] == "pass" for audit in eligible)
    kinds = Counter(str(audit.get("session_kind") or "unknown") for audit in audits)
    lines = [
        f"Codex/Graphify session audit: {len(audits)} recent sessions "
        f"(roots={kinds['root']}, subagents={kinds['subagent']}, "
        f"unknown={kinds['unknown']})",
        f"- plan→code handoff: {passed}/{len(eligible)} compliant"
        if eligible
        else "- plan→code handoff: no eligible sessions",
        "- plan/spec documents: "
        f"unique/session-sum={sum(a['document_unique_file_count'] for a in audits)}; "
        f"read-calls={sum(a['document_read_calls'] for a in audits)}; "
        f"read-targets={sum(a['document_read_target_count'] for a in audits)}; "
        f"whole-in-one-call={sum(a['whole_document_read_calls'] for a in audits)} calls/"
        f"{sum(a['whole_document_file_count'] for a in audits)} files; "
        f"first-pass-complete={sum(a['covered_document_file_count'] for a in audits)} files; "
        f"targeted-revisits={sum(a['document_targeted_revisit_calls'] for a in audits)} calls; "
        f"overlap={sum(a['document_overlap_lines'] for a in audits)} lines; "
        f"redundant={sum(a['document_redundant_read_calls'] for a in audits)} calls; "
        f"truncated={sum(a['document_truncated_read_calls'] for a in audits)} calls/≈"
        f"{sum(a['document_truncation_waste_tokens_estimate'] for a in audits)} visible tokens",
        "- executed raw code browsing: "
        f"reads={sum(a['code_browse_calls'] for a in audits)} calls; "
        f"denied rollout cells excluded="
        f"{sum(a['blocked_rollout_calls'] for a in audits)}; "
        f"whole-in-one-call={sum(a['whole_code_read_calls'] for a in audits)} calls/"
        f"{sum(a['whole_code_file_count'] for a in audits)} files; "
        f"cumulative-full={sum(a['covered_code_read_calls'] for a in audits)} calls/"
        f"{sum(a['covered_code_file_count'] for a in audits)} files; output≈"
        f"{sum(a['code_output_tokens_estimate'] for a in audits)} tokens",
        "- executed raw browse cadence: "
        f"worst-current-gap={max(a['raw_browse_current_gap'] for a in audits)}; "
        f"worst-max-gap={max(a['raw_browse_max_gap'] for a in audits)}; "
        f"worst-p95-gap={max(a['raw_browse_p95_gap'] for a in audits)}",
        "- Graphify navigation: "
        f"compact-code={sum(a['compact_code_queries'] for a in audits)}; "
        f"logged-rollout-parsed="
        f"{sum(a['compact_code_queries_parsed'] for a in audits)}; "
        f"logging-disabled={sum(a['compact_code_queries_unlogged'] for a in audits)}; "
        f"pre-telemetry={sum(a['compact_code_queries_pretelemetry'] for a in audits)}; "
        f"compact-document={sum(a['compact_document_queries'] for a in audits)}; "
        f"native-code={sum(a['native_code_queries'] for a in audits)}; "
        f"affected={sum(a['affected_queries'] for a in audits)}",
        "- required follow-ups: "
        f"broad-refinement={sum(a['broad_refined_queries'] for a in audits)}/"
        f"{sum(a['broad_initial_queries'] for a in audits)}; "
        f"fallback-follow-up={sum(a['fallback_followups'] for a in audits)}/"
        f"{sum(a['fallback_queries'] for a in audits)}; "
        f"branch-first={sum(a['branch_graphify_first'] for a in audits)}/"
        f"{sum(a['branch_markers'] for a in audits)}; affected-pending="
        f"{sum(a['affected_pending_path_count'] for a in audits)} paths/"
        f"{sum(bool(a['affected_pending_path_count']) for a in audits)} sessions",
        "- output-token and whole-file counts are heuristic; truncated ranges are not credited as confirmed coverage",
    ]
    tracked = [audit for audit in audits if audit["hook_tracking"]]
    if tracked:
        lines.insert(
            -1,
            f"- enforcement hook: tracked={len(tracked)}/{len(audits)} sessions; "
            f"enforced-era-raw="
            f"{sum(a['hook_enforced_code_browse_events'] for a in tracked)}; "
            f"worst-enforced-gap={max(a['hook_enforced_max_gap'] for a in tracked)}; "
            f"all-ledger-raw={sum(a['hook_code_browse_events'] for a in tracked)}; "
            f"blocked={sum(a['hook_blocks'] for a in tracked)}; "
            f"spawn-blocked={sum(a['hook_spawn_blocks'] for a in tracked)}; "
            f"affected-closure=attempts="
            f"{sum(a['hook_affected_closure_attempts'] for a in tracked)} "
            f"blocks={sum(a['hook_affected_closure_blocks'] for a in tracked)} "
            f"recoveries="
            f"{sum(a['hook_affected_closure_recoveries'] for a in tracked)} "
            f"pending={sum(a['hook_latest_pending_affected_count'] for a in tracked)}; "
            f"legacy-advisories={sum(a['hook_reminders'] for a in tracked)}; outcomes="
            f"responded={sum(a['hook_reminders_responded'] for a in tracked)}, "
            f"ignored={sum(a['hook_reminders_ignored'] for a in tracked)}, "
            f"same-batch={sum(a['hook_reminders_batched'] for a in tracked)}, "
            f"pending={sum(a['hook_reminders_pending'] for a in tracked)}; "
            f"identity-linked={sum(a['hook_tool_identity_linked'] for a in tracked)}/"
            f"{sum(a['hook_tool_identity_events'] for a in tracked)}; modern="
            f"{sum(a['hook_modern_identity_linked'] for a in tracked)}/"
            f"{sum(a['hook_modern_identity_events'] for a in tracked)}",
        )
    return lines


def _workflow_gates(
    audit: dict[str, Any],
    *,
    max_raw_gap: int,
    enforce_closure: bool = False,
) -> list[tuple[str, bool | None, str]]:
    handoff = audit["handoff_status"]
    pending_affected = int(
        audit.get(
            "affected_pending_path_count",
            int(bool(audit.get("code_change_calls")))
            if not audit.get("affected_after_latest_change", True)
            else 0,
        )
    )
    affected_coverage = str(
        audit.get(
            "affected_coverage_status",
            "full" if not pending_affected else "none",
        )
    )
    hook_cadence = bool(audit.get("hook_enforcement_active"))
    executed_gap = (
        int(audit["hook_enforced_max_gap"])
        if hook_cadence
        else int(audit["raw_browse_p95_gap"])
    )
    return [
        (
            "telemetry parity",
            audit["compact_code_queries"] == audit["compact_code_queries_parsed"]
            if audit["canonical_usage_linked"]
            else None,
            f"canonical={audit['compact_code_queries']} parsed="
            f"{audit['compact_code_queries_parsed']}",
        ),
        (
            "plan→code Graphify-first",
            handoff == "pass" if handoff != "not_applicable" else None,
            audit["handoff_detail"],
        ),
        (
            "raw browse gap",
            executed_gap <= max_raw_gap
            and audit["hook_batch_violations"] == 0,
            f"executed={executed_gap} rollout-p95={audit['raw_browse_p95_gap']} "
            f"rollout-max={audit['raw_browse_max_gap']} "
            f"target≤{max_raw_gap}; over-budget-cells="
            f"{audit['hook_batch_violations']}",
        ),
        (
            "broad→refinement",
            audit["broad_refined_queries"] == audit["broad_initial_queries"]
            if audit["canonical_usage_linked"]
            else None,
            f"{audit['broad_refined_queries']}/{audit['broad_initial_queries']}",
        ),
        (
            "fallback→native follow-up",
            audit["fallback_followups"] == audit["fallback_queries"]
            if audit["canonical_usage_linked"]
            else None,
            f"{audit['fallback_followups']}/{audit['fallback_queries']}",
        ),
        (
            "branch Graphify-first",
            audit["branch_graphify_first"] == audit["branch_markers"]
            if audit["branch_markers"]
            else None,
            f"{audit['branch_graphify_first']}/{audit['branch_markers']}",
        ),
        (
            "post-edit affected",
            (
                pending_affected == 0
                if enforce_closure
                else (True if pending_affected == 0 else None)
            )
            if audit["code_change_calls"]
            else None,
            (
                "status=PENDING "
                if audit["code_change_calls"]
                and pending_affected
                and not enforce_closure
                else ""
            )
            + f"coverage={affected_coverage.upper()} "
            f"edit-calls={audit['code_change_calls']} affected="
            f"{audit['affected_queries']} pending="
            f"{pending_affected}",
        ),
        (
            "legacy advisory response",
            audit["hook_reminders_ignored"] == 0
            if (
                audit["hook_reminders_responded"]
                + audit["hook_reminders_ignored"]
            )
            else None,
            f"responded={audit['hook_reminders_responded']} "
            f"ignored={audit['hook_reminders_ignored']} "
            f"same-batch={audit['hook_reminders_batched']} "
            f"pending={audit['hook_reminders_pending']}",
        ),
    ]


def _workflow_benchmark_lines(
    audit: dict[str, Any],
    *,
    max_raw_gap: int,
    enforce_closure: bool = False,
) -> tuple[list[str], bool]:
    gates = _workflow_gates(
        audit,
        max_raw_gap=max_raw_gap,
        enforce_closure=enforce_closure,
    )
    applicable = [gate for gate in gates if gate[1] is not None]
    passed = sum(bool(gate[1]) for gate in applicable)
    lines = [
        f"Graphify workflow benchmark: {passed}/{len(applicable)} gates passed "
        f"for {audit['session_sha256']}"
    ]
    for name, status, detail in gates:
        label = (
            "PENDING"
            if status is None and detail.startswith("status=PENDING")
            else "N/A"
            if status is None
            else "PASS"
            if status
            else "FAIL"
        )
        lines.append(f"- {label} {name}: {detail}")
    lines.extend(
        [
            "- volume: "
            f"raw={audit['code_browse_calls']} calls/"
            f"≈{audit['code_output_tokens_estimate']} tokens; whole-code="
            f"{audit['whole_code_read_calls']} calls/"
            f"≈{audit['whole_code_output_tokens_estimate']} tokens",
            "- count is diagnostic; optimize workflow gates and raw output, not total queries",
        ]
    )
    return lines, passed == len(applicable)


def _checkpoint_lines(
    audit: dict[str, Any],
    *,
    max_raw_gap: int,
    new_branch: bool,
) -> list[str]:
    pending_affected = int(
        audit.get(
            "affected_pending_path_count",
            int(bool(audit.get("code_change_calls")))
            if not audit.get("affected_after_latest_change", True)
            else 0,
        )
    )
    requery_reasons: list[str] = []
    if new_branch:
        requery_reasons.append("new investigation branch was declared")
    if audit["code_browse_calls"] and not audit["compact_code_queries"]:
        requery_reasons.append("source browsing has no compact code query")
    if audit["raw_browse_current_gap"] >= max_raw_gap:
        requery_reasons.append(
            f"current raw-browse gap {audit['raw_browse_current_gap']} reached "
            f"the {max_raw_gap}-call ceiling"
        )
    followup_reasons: list[str] = []
    if audit["broad_refined_queries"] < audit["broad_initial_queries"]:
        query_ids = ",".join(audit["unrefined_broad_query_ids"][:3])
        followup_reasons.append(
            "broad query needs exactly one linked refinement"
            + (f" ({query_ids})" if query_ids else "")
        )
    if audit["fallback_followups"] < audit["fallback_queries"]:
        query_ids = ",".join(audit["unfollowed_fallback_query_ids"][:3])
        followup_reasons.append(
            "full-graph fallback needs exactly one measured native follow-up"
            + (f" ({query_ids})" if query_ids else "")
        )
    if audit["code_change_calls"] and pending_affected:
        followup_reasons.append(
            f"latest code-change batch has {pending_affected} pending affected path(s)"
        )
    if requery_reasons:
        status = "REQUERY_REQUIRED"
    elif followup_reasons:
        status = "FOLLOW_UP_REQUIRED"
    elif (
        audit["canonical_usage_linked"]
        and audit["compact_code_queries"] != audit["compact_code_queries_parsed"]
    ):
        status = "MEASUREMENT_WARNING"
    else:
        status = "OK"
    lines = [
        f"Graphify workflow checkpoint: {status} ({audit['session_sha256']})",
        "- cadence: "
        f"current-gap={audit['raw_browse_current_gap']}; "
        f"p95-gap={audit['raw_browse_p95_gap']}; ceiling={max_raw_gap}",
        "- follow-ups: "
        f"broad={audit['broad_refined_queries']}/{audit['broad_initial_queries']}; "
        f"fallback={audit['fallback_followups']}/{audit['fallback_queries']}; "
        f"affected-coverage="
        f"{str(audit.get('affected_coverage_status', 'full' if not pending_affected else 'pending')).upper()}; "
        f"pending={pending_affected}",
    ]
    lines.extend(f"- action: {reason}" for reason in requery_reasons + followup_reasons)
    if audit.get("latest_query_id"):
        lines.append(
            "- reuse if still on the same branch: "
            f"query_id={audit['latest_query_id']} evidence_digest="
            f"{audit.get('latest_evidence_digest') or 'unavailable'}"
        )
    lines.append("- checkpoint is advisory and does not block source access")
    return lines


def session_stats(
    *,
    selector: str | None,
    recent: int | None,
    exclude_current: bool,
    roots_only: bool = False,
    subagents_only: bool = False,
    started_after: str | None = None,
    sessions_root: Path | None = None,
) -> None:
    if sessions_root is None:
        configured_home = os.environ.get("CODEX_HOME")
        codex_root = Path(configured_home) if configured_home else Path.home() / ".codex"
        sessions_root = codex_root / "sessions"
    if recent is not None:
        files = _session_files(sessions_root)
        current_digest = _environment_digest("CODEX_SESSION_ID")
        if exclude_current and current_digest:
            files = [
                path
                for path in files
                if _session_digest(_session_id(path)) != current_digest
            ]
        if roots_only:
            files = [
                path
                for path in files
                if _session_metadata(path).get("session_kind") == "root"
            ]
        if subagents_only:
            files = [
                path
                for path in files
                if _session_metadata(path).get("session_kind") == "subagent"
            ]
        if started_after:
            cutoff = _audit_timestamp(started_after)
            if cutoff is None:
                raise SystemExit(
                    "--started-after must be an ISO-8601 timestamp with a date"
                )
            files = [
                path
                for path in files
                if (
                    (started := _audit_timestamp(
                        _session_metadata(path).get("started_at")
                    ))
                    is not None
                    and started >= cutoff
                )
            ]
        audits = [_session_audit(path) for path in files[:recent]]
        if not audits:
            raise SystemExit("No Codex rollout logs matched the requested recent-session audit")
        print("\n".join(_aggregate_session_audit_lines(audits)))
        return
    path = _resolve_session_log(selector or "current", sessions_root=sessions_root)
    print("\n".join(_session_audit_lines(_session_audit(path))))


def checkpoint(
    *,
    selector: str,
    max_raw_gap: int,
    new_branch: bool,
    sessions_root: Path | None = None,
) -> None:
    if sessions_root is None:
        configured_home = os.environ.get("CODEX_HOME")
        codex_root = Path(configured_home) if configured_home else Path.home() / ".codex"
        sessions_root = codex_root / "sessions"
    path = _resolve_session_log(selector, sessions_root=sessions_root)
    audit = _session_audit(path)
    print(
        "\n".join(
            _checkpoint_lines(
                audit,
                max_raw_gap=max_raw_gap,
                new_branch=new_branch,
            )
        )
    )


def workflow_benchmark(
    *,
    selector: str,
    max_raw_gap: int,
    enforce_closure: bool = False,
    sessions_root: Path | None = None,
) -> bool:
    if sessions_root is None:
        configured_home = os.environ.get("CODEX_HOME")
        codex_root = Path(configured_home) if configured_home else Path.home() / ".codex"
        sessions_root = codex_root / "sessions"
    path = _resolve_session_log(selector, sessions_root=sessions_root)
    lines, passed = _workflow_benchmark_lines(
        _session_audit(path),
        max_raw_gap=max_raw_gap,
        enforce_closure=enforce_closure,
    )
    print("\n".join(lines))
    return passed


def benchmark(*, cases_path: Path = BENCHMARK_PATH) -> bool:
    try:
        raw = json.loads(cases_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"Unable to load Graphify benchmark {cases_path}: {exc}") from exc
    cases = raw.get("cases") if isinstance(raw, dict) else None
    if not isinstance(cases, list) or not cases:
        raise SystemExit(f"Graphify benchmark has no cases: {cases_path}")

    graph = _load_graph()
    overlay = load_overlay()
    failures: list[str] = []
    output_tokens: list[int] = []
    truncated_cases = 0
    source_checks = source_hits = 0
    proof_checks = proof_hits = 0
    anchored = 0

    for index, case in enumerate(cases, start=1):
        if not isinstance(case, dict):
            failures.append(f"case-{index}: case must be an object")
            continue
        name = str(case.get("name") or f"case-{index}")
        question = str(case.get("question") or "")
        profile = str(case.get("profile") or "general")
        level = str(case.get("level") or "code")
        budget = int(case.get("budget") or 600)
        expected = case.get("expected") if isinstance(case.get("expected"), dict) else {}
        if profile not in {"general", "tdd", "review"} or level not in {"code", "component"}:
            failures.append(f"{name}: invalid profile or level")
            continue
        if level == "component":
            lines, meta = _component_lines(graph, question, profile, budget)
        else:
            lines, meta = _compact_lines(graph, overlay, question, profile)
        result = _bounded(lines, budget)
        if TRUNCATION_PREFIX in result:
            truncated_cases += 1
        estimated = max(1, round(len(result) / 4))
        output_tokens.append(estimated)
        case_errors: list[str] = []

        expected_confidence = expected.get("confidence")
        if expected_confidence and meta.get("confidence") != expected_confidence:
            case_errors.append(
                f"confidence={meta.get('confidence')} expected={expected_confidence}"
            )
        expected_route = expected.get("route")
        if expected_route and meta.get("route") != expected_route:
            case_errors.append(f"route={meta.get('route')} expected={expected_route}")

        expected_sources = {
            str(path) for path in expected.get("source_any", []) if str(path)
        }
        if expected_sources:
            source_checks += 1
            delivered_sources = {path for path in expected_sources if path in result}
            if delivered_sources:
                source_hits += 1
            else:
                case_errors.append(
                    "source not delivered; expected one of "
                    + ", ".join(sorted(expected_sources))
                )

        expected_proofs = {
            str(path) for path in expected.get("proof_any", []) if str(path)
        }
        if expected_proofs:
            proof_checks += 1
            delivered_proofs = {path for path in expected_proofs if path in result}
            if delivered_proofs:
                proof_hits += 1
            else:
                case_errors.append(
                    "proof not delivered; expected one of "
                    + ", ".join(sorted(expected_proofs))
                )

        for required in expected.get("contains", []):
            if str(required) not in result:
                case_errors.append(f"missing output marker: {required}")
        max_tokens = int(expected.get("max_estimated_tokens") or budget)
        if estimated > max_tokens:
            case_errors.append(f"estimated_tokens={estimated} exceeds {max_tokens}")
        if meta.get("confidence") == "anchored":
            anchored += 1
        failures.extend(f"{name}: {error}" for error in case_errors)

    if not output_tokens:
        print("Graphify precision benchmark: 0 valid cases")
        if failures:
            print("Failures:\n" + "\n".join(f"- {failure}" for failure in failures))
        return False
    ordered_tokens = sorted(output_tokens)
    p95 = ordered_tokens[
        min(len(ordered_tokens) - 1, math.ceil(len(ordered_tokens) * 0.95) - 1)
    ]
    passed = len(cases) - len({failure.split(":", 1)[0] for failure in failures})
    lines = [
        f"Graphify precision benchmark: {passed}/{len(cases)} cases passed",
        f"- anchored: {anchored}/{len(cases)} ({anchored / len(cases):.0%})",
        f"- output: avg {round(sum(output_tokens) / len(output_tokens))} estimated tokens; p95 {p95}",
        f"- truncation: {truncated_cases}/{len(cases)} ({truncated_cases / len(cases):.0%})",
    ]
    if source_checks:
        lines.append(
            f"- expected-source hit: {source_hits}/{source_checks} "
            f"({source_hits / source_checks:.0%})"
        )
    if proof_checks:
        lines.append(
            f"- expected-proof hit: {proof_hits}/{proof_checks} "
            f"({proof_hits / proof_checks:.0%})"
        )
    if failures:
        lines.append("Failures:")
        lines.extend(f"- {failure}" for failure in failures)
    print("\n".join(lines))
    return not failures


def query(
    question: str,
    *,
    profile: str,
    budget: int,
    ensure_fresh: bool,
    level: str = "code",
    query_stage: str = "initial",
    refinement_of: str | None = None,
) -> None:
    started = time.perf_counter()
    query_id = uuid.uuid4().hex[:16]
    handoff = _document_handoff_context(
        question,
        profile=profile,
        level=level,
    )
    if handoff is not None:
        lines, meta = handoff
    else:
        if ensure_fresh:
            _ensure_fresh()
        graph = _load_graph()
        if level == "component":
            lines, meta = _component_lines(graph, question, profile, budget)
        else:
            overlay = load_overlay()
            lines, meta = _compact_lines(graph, overlay, question, profile)
    if lines:
        if meta.get("route") == "document_handoff":
            answer_scope = "not_queried"
        elif meta.get("confidence") in {"broad", "none"}:
            answer_scope = "anchor_discovery_only"
        else:
            answer_scope = "navigation_only"
        meta["answer_scope"] = answer_scope
        lines[0] += f" answer_scope={answer_scope} query_id={query_id}"
        if meta.get("route") != "document_handoff":
            lines[0] += f" evidence_digest={_context_evidence_digest(meta)}"
    if (
        level == "code"
        and meta.get("route") == "architecture"
        and meta.get("confidence") in {"broad", "none"}
    ):
        if query_stage == "initial":
            guidance = (
                "Refine command: python3 graphify-arch/tdd_context.py query "
                '"<EXACT_SYMBOL_OR_FILENAME> <one specific caller/test/gate relationship>" '
                f"--profile {profile} --budget {budget} --stage refinement "
                f"--refines {query_id}"
            )
        else:
            guidance = (
                "Refinement still has no exact anchor. Stop rephrasing with broad synonyms; "
                "use a Did-you-mean candidate or targeted symbol/filename search."
            )
        insert_at = next(
            (
                index + 1
                for index, line in enumerate(lines)
                if line.startswith("Required next step:")
            ),
            min(3, len(lines)),
        )
        lines.insert(insert_at, guidance)
    if meta.get("route") == "full_graph_fallback":
        targets = [str(path) for path in meta.get("fallback_targets", [])]
        if targets:
            followup_line = (
                "Next: python3 graphify-arch/tdd_context.py native "
                f"{json.dumps(' '.join(targets))} --budget 800 --follows {query_id}"
            )
            for index, line in enumerate(lines):
                if line.startswith("Next: run the measured native Graphify wrapper"):
                    lines[index] = followup_line
                    break
            else:
                lines.append(followup_line)
    result = _bounded(lines, budget)
    _log_query(
        profile,
        question,
        budget,
        result,
        meta,
        (time.perf_counter() - started) * 1000,
        query_id=query_id,
        query_stage=query_stage,
        refinement_of=refinement_of,
    )
    print(result)


def native(question: str, *, budget: int, follows: str) -> None:
    """Run and measure the full-graph follow-up for a routed architecture miss."""
    started = time.perf_counter()
    query_id = uuid.uuid4().hex[:16]
    try:
        proc = subprocess.run(
            ["graphify", "query", question, "--budget", str(budget)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise SystemExit(f"Unable to run native Graphify query: {exc}") from exc
    body = proc.stdout.strip()
    if proc.returncode != 0:
        detail = proc.stderr.strip() or body or f"exit {proc.returncode}"
        raise SystemExit(f"Native Graphify query failed: {detail}")
    meta = {
        "confidence": "not_applicable",
        "route": "full_graph_followup",
        "route_reason": "measured_native_fallback",
        "graph_scope": "full",
        "followup_of": follows,
        "selected_files": [],
        "proof_files": [],
        "fallback_targets": [question],
        "document_targets": [],
    }
    header = (
        f"Native Graph context: query_id={query_id} follows={follows} "
        f"evidence_digest={_context_evidence_digest(meta)}"
    )
    result = header if not body else f"{header}\n{body}"
    _append_usage(
        _usage_record(
            operation="native_query",
            profile="native",
            input_text=question,
            budget=budget,
            result=result,
            meta=meta,
            duration_ms=(time.perf_counter() - started) * 1000,
            query_id=query_id,
            query_stage="fallback",
        )
    )
    print(result)


def affected(paths: list[str], *, budget: int) -> None:
    started = time.perf_counter()
    query_id = uuid.uuid4().hex[:16]
    graph = _load_graph()
    overlay = load_overlay()
    changed = {Path(path).as_posix().removeprefix("./") for path in paths}
    impacted: defaultdict[str, set[str]] = defaultdict(set)
    for source, target, relation in graph.file_edges:
        if target in changed and source not in changed:
            impacted[source].add(relation)
    for target in changed:
        for test_path in overlay.get("production_to_tests", {}).get(target, []):
            impacted[test_path].add("tests")

    lines = [f"Affected context: {', '.join(sorted(changed))} query_id={query_id}"]
    if not impacted:
        lines.append("- no reverse dependencies resolved; verify typed callers directly")
    for path, relations in sorted(impacted.items(), key=lambda item: (_category(item[0]) in {"test", "integration_test"}, item[0])):
        lines.append(f"- {path} [{', '.join(sorted(relations))}]")
    result = _bounded(lines, budget)
    _append_usage(
        _usage_record(
            operation="affected",
            profile="affected",
            input_text="\n".join(sorted(changed)),
            budget=budget,
            result=result,
            meta={
                "confidence": "not_applicable",
                "route": "architecture",
                "route_reason": "reverse_impact",
                "changed_file_count": len(changed),
                "impacted_file_count": len(impacted),
                "selected_files": sorted(impacted),
                "proof_files": [],
                "fallback_targets": [],
            },
            duration_ms=(time.perf_counter() - started) * 1000,
            query_id=query_id,
            query_stage="impact",
        )
    )
    print(result)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("build", help="rebuild the deterministic TDD proof overlay")
    q = sub.add_parser("query", help="render compact architecture context")
    q.add_argument(
        "question",
        help=(
            "code-index question shaped as '<exact symbol or filename> "
            "<one specific caller/test/gate relationship>'; not a product-truth question"
        ),
    )
    q.add_argument("--profile", choices=("general", "tdd", "review"), default="general")
    q.add_argument(
        "--level",
        choices=("code", "component"),
        default="code",
        help="component renders the labeled community map (C4 component view) instead of file-level context",
    )
    q.add_argument("--budget", type=int, default=600)
    q.add_argument("--ensure-fresh", action="store_true")
    q.add_argument(
        "--stage",
        choices=("initial", "refinement"),
        default="initial",
        help="mark whether this is the first query or a refinement",
    )
    q.add_argument(
        "--refines",
        help="query_id from the broad/none query being refined",
    )
    n = sub.add_parser(
        "native",
        help="run and measure a full-graph fallback query",
    )
    n.add_argument("question")
    n.add_argument("--budget", type=int, default=800)
    n.add_argument(
        "--follows",
        required=True,
        help="query_id of the full_graph_fallback compact query",
    )
    a = sub.add_parser("affected", help="find reverse file/test impact for changed paths")
    a.add_argument("paths", nargs="+")
    a.add_argument("--budget", type=int, default=600)
    s = sub.add_parser("stats", help="summarize compact-query token usage")
    s.add_argument("--last", type=int, default=100)
    ss = sub.add_parser(
        "session-stats",
        help="audit plan/spec-to-Graphify-to-code browsing in Codex rollout logs",
    )
    selection = ss.add_mutually_exclusive_group()
    selection.add_argument(
        "--session",
        help="current, latest, latest-other, a raw session id, or a 16-char hash",
    )
    selection.add_argument(
        "--recent",
        type=int,
        help="aggregate this many most recently modified Codex sessions",
    )
    ss.add_argument(
        "--exclude-current",
        action="store_true",
        help="with --recent, omit the current Codex session",
    )
    cohort = ss.add_mutually_exclusive_group()
    cohort.add_argument(
        "--roots-only",
        action="store_true",
        help="with --recent, include only user/root sessions",
    )
    cohort.add_argument(
        "--subagents-only",
        action="store_true",
        help="with --recent, include only subagent sessions",
    )
    ss.add_argument(
        "--started-after",
        help="with --recent, include sessions started at/after this ISO-8601 time",
    )
    cp = sub.add_parser(
        "checkpoint",
        help="report non-blocking branch and raw-browse workflow actions",
    )
    cp.add_argument("--session", default="current")
    cp.add_argument("--max-raw-gap", type=int, default=10)
    cp.add_argument(
        "--new-branch",
        action="store_true",
        help="mark a semantic investigation-branch transition",
    )
    wb = sub.add_parser(
        "workflow-benchmark",
        help="score Graphify adoption for one Codex session",
    )
    wb.add_argument("--session", default="current")
    wb.add_argument("--max-raw-gap", type=int, default=10)
    wb.add_argument(
        "--closure",
        action="store_true",
        help="treat unresolved final affected-path debt as a failing closure gate",
    )
    b = sub.add_parser("benchmark", help="run deterministic Graphify precision cases")
    b.add_argument("--cases", type=Path, default=BENCHMARK_PATH)
    return parser


def main() -> None:
    args = _parser().parse_args()
    if args.command == "build":
        build_overlay()
    elif args.command == "query":
        if args.budget <= 0:
            raise SystemExit("--budget must be positive")
        if args.stage == "refinement" and not args.refines:
            raise SystemExit("--stage refinement requires --refines <query_id>")
        if args.stage == "initial" and args.refines:
            raise SystemExit("--refines requires --stage refinement")
        if args.refines and not re.fullmatch(r"[A-Za-z0-9_.:-]{1,64}", args.refines):
            raise SystemExit("--refines must be a 1-64 character identifier")
        query(
            args.question,
            profile=args.profile,
            budget=args.budget,
            ensure_fresh=args.ensure_fresh,
            level=args.level,
            query_stage=args.stage,
            refinement_of=args.refines,
        )
    elif args.command == "native":
        if args.budget <= 0:
            raise SystemExit("--budget must be positive")
        if not re.fullmatch(r"[A-Za-z0-9_.:-]{1,64}", args.follows):
            raise SystemExit("--follows must be a 1-64 character identifier")
        native(args.question, budget=args.budget, follows=args.follows)
    elif args.command == "affected":
        if args.budget <= 0:
            raise SystemExit("--budget must be positive")
        affected(args.paths, budget=args.budget)
    elif args.command == "stats":
        if args.last <= 0:
            raise SystemExit("--last must be positive")
        stats(last=args.last)
    elif args.command == "session-stats":
        if args.recent is not None and args.recent <= 0:
            raise SystemExit("--recent must be positive")
        if args.exclude_current and args.recent is None:
            raise SystemExit("--exclude-current requires --recent")
        if (args.roots_only or args.subagents_only or args.started_after) and args.recent is None:
            raise SystemExit("cohort filters require --recent")
        session_stats(
            selector=args.session,
            recent=args.recent,
            exclude_current=args.exclude_current,
            roots_only=args.roots_only,
            subagents_only=args.subagents_only,
            started_after=args.started_after,
        )
    elif args.command == "checkpoint":
        if args.max_raw_gap <= 0:
            raise SystemExit("--max-raw-gap must be positive")
        checkpoint(
            selector=args.session,
            max_raw_gap=args.max_raw_gap,
            new_branch=args.new_branch,
        )
    elif args.command == "workflow-benchmark":
        if args.max_raw_gap <= 0:
            raise SystemExit("--max-raw-gap must be positive")
        if not workflow_benchmark(
            selector=args.session,
            max_raw_gap=args.max_raw_gap,
            enforce_closure=args.closure,
        ):
            raise SystemExit(1)
    elif args.command == "benchmark":
        if not benchmark(cases_path=args.cases):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
