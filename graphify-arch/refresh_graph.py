#!/usr/bin/env python3
"""Refresh the architecture graph without Graphify's no-cluster overwrite bug.

Graphify 0.8.33 writes only the changed extraction when ``extract`` is used in
incremental mode together with ``--no-cluster``.  This repo wants the opposite
combination for routine work: merge changed AST output into the persistent
graph, but defer expensive community detection and report generation.

This wrapper deliberately uses Graphify's public detect/extract/build/export
functions.  It keeps the installed package untouched and can be removed once
the upstream CLI gives ``--no-cluster`` the same incremental merge semantics as
its clustered path.
"""

from __future__ import annotations

import argparse
import json
import os
from collections import defaultdict
from pathlib import Path

from graphify.build import build
from graphify.detect import detect, detect_incremental, save_manifest
from graphify.export import to_json
from graphify.extract import extract


ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / ".graphify-arch-src"
OUT = ROOT / "graphify-arch" / "graphify-out"
GRAPH = OUT / "graph.json"
MANIFEST = OUT / "manifest.json"


def _relative_source(path: str | Path | None) -> str:
    if not path:
        return ""
    candidate = Path(path)
    if candidate.is_absolute():
        try:
            # Keep this lexical: resolving a file below lib/ follows the
            # architecture corpus symlink back into the repository and loses
            # the TARGET prefix that must be stripped.
            return candidate.relative_to(TARGET).as_posix()
        except ValueError:
            return candidate.as_posix()
    return candidate.as_posix().removeprefix("./")


def _without_sources(data: dict, sources: set[str]) -> dict:
    """Return an extraction minus every replaced/deleted source."""
    links = data.get("links", data.get("edges", []))
    nodes = data.get("nodes", [])
    removed_ids = {
        str(node.get("id"))
        for node in nodes
        if _relative_source(node.get("source_file", "")) in sources
    }
    kept_nodes = [node for node in nodes if str(node.get("id")) not in removed_ids]
    kept_edges = [
        edge
        for edge in links
        if str(edge.get("source")) not in removed_ids
        and str(edge.get("target")) not in removed_ids
        and _relative_source(edge.get("source_file", "")) not in sources
    ]
    return {
        "nodes": kept_nodes,
        "edges": kept_edges,
        "hyperedges": data.get("hyperedges", []),
    }


def _load_existing_without(sources: set[str]) -> dict:
    if not GRAPH.exists():
        return {"nodes": [], "edges": [], "hyperedges": []}
    data = json.loads(GRAPH.read_text(encoding="utf-8"))
    return _without_sources(data, sources)


def _communities(graph) -> dict[int, list[str]]:
    """Preserve prior communities; changed nodes remain unclustered until --full."""
    result: dict[int, list[str]] = defaultdict(list)
    for node_id, attrs in graph.nodes(data=True):
        community = attrs.get("community")
        if isinstance(community, int):
            result[community].append(node_id)
        elif isinstance(community, str) and community.isdigit():
            result[int(community)].append(node_id)
    return dict(result)


def _write_graph(graph) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    temporary = GRAPH.with_suffix(".json.tmp")
    to_json(graph, _communities(graph), str(temporary), force=True)
    os.replace(temporary, GRAPH)


def refresh(*, rebuild: bool) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    incremental = not rebuild and GRAPH.exists() and MANIFEST.exists()
    if incremental:
        detection = detect_incremental(
            TARGET,
            manifest_path=str(MANIFEST),
            kind="semantic",
        )
        selected = detection.get("new_files", {})
        deleted = detection.get("deleted_files", [])
        unchanged = sum(
            len(paths) for paths in detection.get("unchanged_files", {}).values()
        )
    else:
        detection = detect(TARGET)
        selected = detection.get("files", {})
        deleted = []
        unchanged = 0

    code_files = [Path(path) for path in selected.get("code", [])]
    replaced_sources = {_relative_source(path) for path in code_files}
    replaced_sources.update(_relative_source(path) for path in deleted)

    action = "incremental" if incremental else "rebuild"
    print(
        f"[arch-refresh] {action}: {len(code_files)} changed code, "
        f"{unchanged} unchanged, {len(deleted)} deleted",
        flush=True,
    )

    if not incremental or replaced_sources:
        ast_result = (
            extract(code_files, cache_root=TARGET)
            if code_files
            else {"nodes": [], "edges": [], "hyperedges": []}
        )
        base = _load_existing_without(replaced_sources) if incremental else None
        chunks = ([base] if base is not None else []) + [ast_result]
        # The complete rebuild performs Graphify's global fuzzy deduplication.
        # On an incremental pass, the unchanged base is already deduplicated
        # and changed-source nodes were removed above. Re-running fuzzy dedup
        # over ~45k nodes costs tens of seconds and can churn unrelated IDs;
        # normal NetworkX ID merging is sufficient for the replacement set.
        graph = build(chunks, dedup=not incremental, root=TARGET)
        if graph.number_of_nodes() == 0 and code_files:
            raise RuntimeError("architecture extraction produced an empty graph")
        _write_graph(graph)
        print(
            f"[arch-refresh] wrote {GRAPH.relative_to(ROOT)}: "
            f"{graph.number_of_nodes()} nodes, {graph.number_of_edges()} edges",
            flush=True,
        )
    else:
        print("[arch-refresh] graph is current", flush=True)

    # Save the complete detection, not only the changed subset. Graphify's
    # manifest writer also preserves unchanged entries and drops real deletes.
    save_manifest(
        detection.get("files", {}),
        manifest_path=str(MANIFEST),
        kind="both",
        root=TARGET,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--rebuild",
        action="store_true",
        help="extract the complete architecture corpus instead of merging changes",
    )
    args = parser.parse_args()
    refresh(rebuild=args.rebuild)


if __name__ == "__main__":
    main()
