#!/usr/bin/env python3
"""Compact, TDD-aware queries over the repo's architecture graph.

The base Graphify AST graph is strong at symbol discovery but intentionally
does not model Flutter test names or shell gate membership.  This script adds a
deterministic proof overlay and renders file-deduplicated context suited to
planning, counterexample review, and execution impact checks.
"""

from __future__ import annotations

import argparse
import datetime as dt
import difflib
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import time
from collections import Counter, defaultdict, deque
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
ARCH_DIR = ROOT / "graphify-arch"
GRAPH_PATH = ARCH_DIR / "graphify-out" / "graph.json"
LABELS_PATH = ARCH_DIR / "graphify-out" / ".graphify_labels.json"
OVERLAY_PATH = ARCH_DIR / "tdd-overlay.json"
GATE_SCRIPTS = (
    ROOT / "scripts" / "run_test_gates.sh",
    ROOT / "scripts" / "run_host_test_gates.sh",
)
STATS_PATH = ROOT / "graphify-out" / "context_query_stats.jsonl"
OVERLAY_VERSION = 3

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
    return Path(path).suffix.lower() in {
        ".dart", ".go", ".sh", ".py", ".swift", ".kt", ".java",
    }


class GraphIndex:
    def __init__(self, raw: dict[str, Any]):
        self.nodes = {str(n["id"]): n for n in raw.get("nodes", [])}
        self.edges = raw.get("links") or raw.get("edges") or []
        self.labels = Counter(
            str(n.get("norm_label") or n.get("label") or "").lower().rstrip("()")
            for n in self.nodes.values()
        )
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
            if term in {norm, nid.lower()} or term == Path(_source_file(node) or "").name.lower():
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


def _compact_lines(
    graph: GraphIndex,
    overlay: dict[str, Any],
    question: str,
    profile: str,
) -> tuple[list[str], dict[str, Any]]:
    seeds, confidence, terms = graph.seeds(question, profile)
    freshness = _freshness()
    lines = [
        f"Graph context: profile={profile} confidence={confidence} freshness={freshness} fingerprint={_graph_fingerprint()}"
    ]
    if not seeds:
        lines.append("No matching graph anchors. Use an exact class, function, or filename.")
        miss_terms, miss_structured = _tokens(question)
        suggestions = graph.suggest_anchors(miss_structured or miss_terms)
        if suggestions:
            lines.append("Did you mean:")
            lines.extend(suggestions)
        return lines, {"confidence": "none", "sources": 0, "tests": 0,
                       "seeds": [], "suggestions": len(suggestions)}

    community_labels = _load_community_labels()
    lines.append("Anchors:")
    for nid in seeds:
        node = graph.nodes[nid]
        source = _source_file(node) or "unknown"
        location = node.get("source_location") or ""
        cid = node.get("community")
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

    lines.append("Production/related files:")
    for path in (production + scripts)[:10]:
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
        )[:10]:
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
        "suggestions": len(suggestions),
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
    labels = _load_community_labels()
    freshness = _freshness()
    members: defaultdict[int, list[str]] = defaultdict(list)
    for nid, node in graph.nodes.items():
        cid = node.get("community")
        if isinstance(cid, int):
            members[cid].append(nid)

    seeds, confidence, terms = graph.seeds(question, profile)
    seed_cids = {
        cid for nid in seeds
        if isinstance(cid := graph.nodes[nid].get("community"), int)
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

    lines = [
        f"Component context: level=component confidence={confidence} freshness={freshness} fingerprint={_graph_fingerprint()}"
    ]
    ranked = [cid for cid, score in sorted(scores.items(), key=lambda item: (-item[1], item[0])) if score > 0]
    if not ranked:
        lines.append("No matching components. Use a feature word from a community label, or an exact symbol/filename.")
        miss_terms, miss_structured = _tokens(question)
        suggestions = graph.suggest_anchors(miss_structured or miss_terms)
        if suggestions:
            lines.append("Did you mean:")
            lines.extend(suggestions)
        return lines, {"confidence": "none", "level": "component",
                       "components": 0, "seeds": [],
                       "suggestions": len(suggestions)}

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
    }
    return lines, meta


def _bounded(lines: list[str], budget: int) -> str:
    limit = max(300, budget * 3)
    out: list[str] = []
    size = 0
    for line in lines:
        addition = len(line) + 1
        if size + addition > limit:
            out.append(f"... truncated at ~{budget} tokens; refine anchors or raise --budget")
            break
        out.append(line)
        size += addition
    return "\n".join(out)


def _log_query(profile: str, question: str, budget: int, result: str, meta: dict[str, Any], duration_ms: float) -> None:
    if os.environ.get("GRAPHIFY_CONTEXT_LOG") == "0":
        return
    try:
        STATS_PATH.parent.mkdir(parents=True, exist_ok=True)
        record = {
            "ts": dt.datetime.now(dt.timezone.utc).isoformat(),
            "profile": profile,
            "question_sha256": hashlib.sha256(question.encode()).hexdigest()[:16],
            "budget": budget,
            "result_chars": len(result),
            "duration_ms": round(duration_ms, 2),
            **meta,
        }
        with STATS_PATH.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError:
        pass


def _stats_summary(records: list[dict[str, Any]]) -> list[str]:
    if not records:
        return ["Context query stats: no recorded queries"]
    estimated_tokens = [max(1, round(int(row.get("result_chars", 0)) / 4)) for row in records]
    utilization = [
        tokens / max(1, int(row.get("budget", 1)))
        for tokens, row in zip(estimated_tokens, records)
    ]
    ordered = sorted(estimated_tokens)
    p95 = ordered[min(len(ordered) - 1, math.ceil(len(ordered) * 0.95) - 1)]
    anchored = sum(row.get("confidence") == "anchored" for row in records)
    lines = [
        f"Context query stats: {len(records)} queries",
        f"- output: avg {round(sum(estimated_tokens) / len(records))} estimated tokens; p95 {p95}",
        f"- budget utilization: avg {sum(utilization) / len(records):.0%}",
        f"- anchored: {anchored}/{len(records)} ({anchored / len(records):.0%})",
    ]
    profiles = Counter(str(row.get("profile", "unknown")) for row in records)
    lines.append(
        "- profiles: "
        + ", ".join(f"{profile}={count}" for profile, count in sorted(profiles.items()))
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


def query(question: str, *, profile: str, budget: int, ensure_fresh: bool, level: str = "code") -> None:
    if ensure_fresh:
        _ensure_fresh()
    started = time.perf_counter()
    graph = _load_graph()
    if level == "component":
        lines, meta = _component_lines(graph, question, profile, budget)
    else:
        overlay = load_overlay()
        lines, meta = _compact_lines(graph, overlay, question, profile)
    result = _bounded(lines, budget)
    _log_query(profile, question, budget, result, meta, (time.perf_counter() - started) * 1000)
    print(result)


def affected(paths: list[str], *, budget: int) -> None:
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

    lines = [f"Affected context: {', '.join(sorted(changed))}"]
    if not impacted:
        lines.append("- no reverse dependencies resolved; verify typed callers directly")
    for path, relations in sorted(impacted.items(), key=lambda item: (_category(item[0]) in {"test", "integration_test"}, item[0])):
        lines.append(f"- {path} [{', '.join(sorted(relations))}]")
    print(_bounded(lines, budget))


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("build", help="rebuild the deterministic TDD proof overlay")
    q = sub.add_parser("query", help="render compact architecture context")
    q.add_argument("question")
    q.add_argument("--profile", choices=("general", "tdd", "review"), default="general")
    q.add_argument(
        "--level",
        choices=("code", "component"),
        default="code",
        help="component renders the labeled community map (C4 component view) instead of file-level context",
    )
    q.add_argument("--budget", type=int, default=600)
    q.add_argument("--ensure-fresh", action="store_true")
    a = sub.add_parser("affected", help="find reverse file/test impact for changed paths")
    a.add_argument("paths", nargs="+")
    a.add_argument("--budget", type=int, default=600)
    s = sub.add_parser("stats", help="summarize compact-query token usage")
    s.add_argument("--last", type=int, default=100)
    return parser


def main() -> None:
    args = _parser().parse_args()
    if args.command == "build":
        build_overlay()
    elif args.command == "query":
        if args.budget <= 0:
            raise SystemExit("--budget must be positive")
        query(
            args.question,
            profile=args.profile,
            budget=args.budget,
            ensure_fresh=args.ensure_fresh,
            level=args.level,
        )
    elif args.command == "affected":
        if args.budget <= 0:
            raise SystemExit("--budget must be positive")
        affected(args.paths, budget=args.budget)
    elif args.command == "stats":
        if args.last <= 0:
            raise SystemExit("--last must be positive")
        stats(last=args.last)


if __name__ == "__main__":
    main()
