#!/usr/bin/env python3
"""Compare the broad and architecture-focused graphify graphs.

The metrics are intentionally simple and stable:
- efficiency: graph size and expected traversal/search breadth
- value: ratio of app-owned source nodes versus vendored/generated noise
- hub quality: whether top connected nodes are meaningful app symbols or noisy deps
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path


APP_PREFIXES = (
    "lib/",
    "test/",
    "integration_test/",
    "go-mknoon/",
    "go-relay-server/",
    "scripts/",
    "ios/NotificationService/",
)

NOISE_PREFIXES = (
    "ios/Pods/",
    "macos/Pods/",
    "ios/Flutter/ephemeral/",
    "macos/Flutter/ephemeral/",
    "go-mknoon/third_party/",
    "go-mknoon/.gocache/",
    "go-mknoon/bin/",
    "build/",
    ".dart_tool/",
)

GENERIC_HUB_LABELS = {
    "_",
    "New",
    "New()",
    "main",
    "main()",
    "Parse",
    "SQLITE_PRIVATE",
    "SQLITE_API",
    "sqlite3",
    "sqlite3_free",
    "sqlite3_free()",
}


def load_graph(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def links(graph: dict) -> list[dict]:
    return graph.get("links") or graph.get("edges") or []


def source_file(node: dict) -> str:
    return str(node.get("source_file") or node.get("src") or "")


def label(node: dict) -> str:
    return str(node.get("label") or node.get("id") or "")


def top_dir(path: str) -> str:
    if not path:
        return "(unknown)"
    parts = path.split("/")
    if len(parts) >= 2 and parts[0] in {"ios", "macos", "android", "windows"}:
        return "/".join(parts[:2])
    return parts[0]


def starts_with_any(path: str, prefixes: tuple[str, ...]) -> bool:
    return any(path.startswith(prefix) for prefix in prefixes)


def endpoint(edge: dict, key: str) -> str:
    value = edge.get(key)
    if isinstance(value, dict):
        return str(value.get("id") or value.get("label") or "")
    return str(value or "")


def summarize(path: Path) -> dict:
    graph = load_graph(path)
    nodes = graph.get("nodes", [])
    edge_list = links(graph)
    node_by_id = {str(n.get("id")): n for n in nodes}

    degree = defaultdict(int)
    for edge in edge_list:
        s = endpoint(edge, "source")
        t = endpoint(edge, "target")
        if s:
            degree[s] += 1
        if t:
            degree[t] += 1

    source_files = [source_file(n) for n in nodes if source_file(n)]
    source_set = set(source_files)
    top_sources = Counter(top_dir(p) for p in source_files).most_common(12)

    app_nodes = sum(1 for n in nodes if starts_with_any(source_file(n), APP_PREFIXES))
    noise_nodes = sum(1 for n in nodes if starts_with_any(source_file(n), NOISE_PREFIXES))
    unknown_nodes = sum(1 for n in nodes if not source_file(n))

    top_hubs = []
    for node_id, deg in sorted(degree.items(), key=lambda item: item[1], reverse=True)[:20]:
        n = node_by_id.get(node_id, {"id": node_id})
        hub_label = label(n)
        sf = source_file(n)
        noisy = starts_with_any(sf, NOISE_PREFIXES) or hub_label in GENERIC_HUB_LABELS
        top_hubs.append(
            {
                "id": node_id,
                "label": hub_label,
                "degree": deg,
                "source_file": sf,
                "noise": noisy,
            }
        )

    community_values = [n.get("community") for n in nodes if n.get("community") is not None]
    community_counts = Counter(community_values)

    node_count = len(nodes)
    edge_count = len(edge_list)
    community_count = len(community_counts)
    top_hub_noise = sum(1 for hub in top_hubs[:10] if hub["noise"])

    return {
        "graph": str(path),
        "nodes": node_count,
        "edges": edge_count,
        "communities": community_count,
        "source_files": len(source_set),
        "avg_edges_per_node": round(edge_count / node_count, 4) if node_count else 0,
        "avg_nodes_per_community": round(node_count / community_count, 2) if community_count else 0,
        "app_owned_nodes": app_nodes,
        "app_owned_ratio": round(app_nodes / node_count, 4) if node_count else 0,
        "noise_nodes": noise_nodes,
        "noise_ratio": round(noise_nodes / node_count, 4) if node_count else 0,
        "unknown_source_nodes": unknown_nodes,
        "unknown_source_ratio": round(unknown_nodes / node_count, 4) if node_count else 0,
        "top_hub_noise_count": top_hub_noise,
        "top_hub_noise_ratio": round(top_hub_noise / 10, 4),
        "top_source_dirs": top_sources,
        "top_hubs": top_hubs[:10],
    }


def pct_delta(new: float, old: float) -> float:
    if old == 0:
        return 0
    return round((new - old) / old, 4)


def write_markdown(out_path: Path, full: dict, arch: dict) -> None:
    lines = [
        "# Graphify Graph Selection",
        "",
        "## Definitions",
        "- Full graph: `graphify-out/graph.json`. Broad code-only index of every detected code file in the repo, including platform/vendor/generated code.",
        "- Architecture graph: `graphify-arch/graphify-out/graph.json`. Focused app-owned graph built from `.graphify-arch-src/` symlinks and `.graphifyignore` filters.",
        "",
        "## Selection Rule",
        "- Use the architecture graph for app architecture, feature flows, repository/service/UI relationships, and day-to-day code navigation.",
        "- Use the full graph when you need exhaustive symbol lookup across generated/native/vendor/platform code.",
        "",
        "## Metrics",
        "| Metric | Full | Architecture | Delta |",
        "| --- | ---: | ---: | ---: |",
    ]
    metric_rows = [
        ("nodes", "nodes"),
        ("edges", "edges"),
        ("communities", "communities"),
        ("source files", "source_files"),
        ("avg edges per node", "avg_edges_per_node"),
        ("avg nodes per community", "avg_nodes_per_community"),
        ("app-owned ratio", "app_owned_ratio"),
        ("noise ratio", "noise_ratio"),
        ("unknown-source ratio", "unknown_source_ratio"),
        ("top-10 hub noise ratio", "top_hub_noise_ratio"),
    ]
    for title, key in metric_rows:
        f = full[key]
        a = arch[key]
        lines.append(f"| {title} | {f} | {a} | {pct_delta(float(a), float(f)):+.2%} |")

    lines += [
        "",
        "## Top Hubs",
        "Full graph top hubs:",
    ]
    for hub in full["top_hubs"][:10]:
        noise = "noise" if hub["noise"] else "signal"
        lines.append(f"- `{hub['label']}` ({hub['degree']} edges, {noise}) `{hub['source_file']}`")

    lines += ["", "Architecture graph top hubs:"]
    for hub in arch["top_hubs"][:10]:
        noise = "noise" if hub["noise"] else "signal"
        lines.append(f"- `{hub['label']}` ({hub['degree']} edges, {noise}) `{hub['source_file']}`")

    lines += [
        "",
        "## Method",
        "- Efficiency means fewer nodes, fewer edges, fewer communities, and lower average traversal breadth for the same app-level question.",
        "- Value means more app-owned source nodes, less vendored/generated noise, and fewer generic/vendor symbols among the top hubs.",
        "- Graphify's built-in benchmark measures token compression against each graph's own corpus baseline. Use it as a cost proxy, not as the only value metric.",
        "- Rebuild the architecture graph and refresh this comparison:",
        "",
        "```bash",
        "graphify-arch/refresh_arch_graph.sh",
        "```",
        "",
        "- Re-run this comparison after rebuilding either graph:",
        "",
        "```bash",
        "python3 graphify-arch/compare_graphs.py \\",
        "  --full graphify-out/graph.json \\",
        "  --arch graphify-arch/graphify-out/graph.json \\",
        "  --out graphify-arch/GRAPH_SELECTION.md \\",
        "  --json-out graphify-arch/comparison.json",
        "```",
        "",
        "Optional token-compression benchmark:",
        "",
        "```bash",
        "graphify benchmark graphify-out/graph.json",
        "graphify benchmark graphify-arch/graphify-out/graph.json",
        "```",
        "",
    ]
    out_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--full", type=Path, required=True)
    parser.add_argument("--arch", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--json-out", type=Path, required=True)
    args = parser.parse_args()

    full = summarize(args.full)
    arch = summarize(args.arch)
    comparison = {
        "full": full,
        "architecture": arch,
        "deltas": {
            "nodes": pct_delta(arch["nodes"], full["nodes"]),
            "edges": pct_delta(arch["edges"], full["edges"]),
            "communities": pct_delta(arch["communities"], full["communities"]),
            "app_owned_ratio": pct_delta(arch["app_owned_ratio"], full["app_owned_ratio"]),
            "noise_ratio": pct_delta(arch["noise_ratio"], full["noise_ratio"]),
            "top_hub_noise_ratio": pct_delta(arch["top_hub_noise_ratio"], full["top_hub_noise_ratio"]),
        },
    }

    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(json.dumps(comparison, indent=2), encoding="utf-8")
    write_markdown(args.out, full, arch)
    print(f"Wrote {args.out}")
    print(f"Wrote {args.json_out}")


if __name__ == "__main__":
    main()
