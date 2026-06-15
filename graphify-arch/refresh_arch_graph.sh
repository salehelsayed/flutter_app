#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Re-apply the local Dart-extractor patch (line numbers + nested/multi-line
# functions) in case a graphifyy upgrade wiped it. Idempotent.
graphify_python="$(head -1 "$(command -v graphify)" | tr -d '#!')"
"$graphify_python" graphify-arch/patches/apply_dart_extractor_patch.py

rm -rf graphify-arch/graphify-out .graphify-arch-src/graphify-out

graphify extract .graphify-arch-src --out graphify-arch
graphify cluster-only graphify-arch --no-label
(cd graphify-arch && graphify export html)

python3 graphify-arch/compare_graphs.py \
  --full graphify-out/graph.json \
  --arch graphify-arch/graphify-out/graph.json \
  --out graphify-arch/GRAPH_SELECTION.md \
  --json-out graphify-arch/comparison.json

rm -rf .graphify-arch-src/graphify-out

echo "Architecture graph refreshed: graphify-arch/graphify-out/graph.json"
echo "Comparison refreshed: graphify-arch/GRAPH_SELECTION.md"
