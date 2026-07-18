#!/usr/bin/env bash
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
cd "${CLAUDE_HOST_REPO_ROOT:-$(pwd)}"
export PYTHONHASHSEED=0

graphify_python="$(head -1 "$(command -v graphify)" | tr -d '#!')"

echo "=== write full-graph sig sidecar (exact upstream format) ==="
"$graphify_python" - <<'PYEOF'
import json
import collections
from graphify.cluster import community_member_sigs

g = json.load(open("graphify-out/graph.json"))
communities = collections.defaultdict(list)
for n in g["nodes"]:
    c = n.get("community")
    if c is not None:
        communities[c].append(n["id"])
sigs = community_member_sigs(dict(communities))
with open("graphify-out/.graphify_labels.json.sig", "w") as f:
    json.dump({str(k): v for k, v in sigs.items()}, f)
print("sig sidecar written:", len(sigs), "communities")
PYEOF

echo "=== regenerate arch report/html with curated labels ==="
graphify cluster-only graphify-arch --no-label
echo "arch cluster-only exit: $?"

echo "=== refresh arch aggregated community html ==="
(cd graphify-arch && graphify export html)
echo "arch export html exit: $?"

echo "=== regenerate full report with curated labels ==="
graphify cluster-only . --no-label
echo "full cluster-only exit: $?"
