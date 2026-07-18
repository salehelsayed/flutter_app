#!/usr/bin/env bash
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
cd "${CLAUDE_HOST_REPO_ROOT:-$(pwd)}"
export PYTHONHASHSEED=0

graphify_python="$(head -1 "$(command -v graphify)" | tr -d '#!')"
"$graphify_python" - <<'PYEOF'
"""Iterate build_from_json's fuzzy dedup to a node-count fixpoint, then persist
one final clustering. Ends the shrink-refuse loop: every later cluster-only
load reproduces this graph exactly, so curated labels stay attached."""
import json
from graphify.build import build_from_json
from graphify.cluster import cluster, remap_communities_to_previous, community_member_sigs
from graphify.export import to_json

raw = json.loads(open("graphify-out/graph.json", encoding="utf-8").read())
directed = bool(raw.get("directed", False))
built_at = raw.get("built_at_commit")
previous = {n["id"]: n["community"] for n in raw.get("nodes", [])
            if n.get("community") is not None and n.get("id") is not None}

count = len(raw["nodes"])
for i in range(60):
    G = build_from_json(raw, directed=directed)
    n = G.number_of_nodes()
    print(f"iter {i}: {count} -> {n} nodes")
    if n == count:
        break
    count = n
    # round-trip through the JSON shape so the next build_from_json pass
    # re-runs dedup on the merged result
    from networkx.readwrite import json_graph
    data = json_graph.node_link_data(G, edges="links")
    data["directed"] = directed
    raw = data
else:
    raise SystemExit("dedup did not reach a fixpoint in 60 iterations")

communities = cluster(G, resolution=1.0, exclude_hubs_percentile=None)
if previous:
    communities = remap_communities_to_previous(communities, previous)
print(f"final: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges, {len(communities)} communities")

labels = {int(k): v for k, v in json.load(
    open("graphify-out/.graphify_labels.json", encoding="utf-8")).items()}
wrote = to_json(G, communities, "graphify-out/graph.json", force=True,
                built_at_commit=built_at, community_labels=labels)
print("graph.json force-written:", wrote)

sigs = community_member_sigs(communities)
with open("graphify-out/.graphify_labels.json.sig", "w") as f:
    json.dump({str(k): v for k, v in sigs.items()}, f)
print("sig sidecar rewritten:", len(sigs))
PYEOF
echo "fixpoint exit: $?"
