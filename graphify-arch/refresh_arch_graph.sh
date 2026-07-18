#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mode="${1:---incremental}"
case "$mode" in
  --incremental|--full|--rebuild) ;;
  *)
    echo "Usage: $0 [--incremental|--full|--rebuild]" >&2
    exit 2
    ;;
esac

# NetworkX community assignment depends on hash iteration order. Keep full
# artifact refreshes stable across processes.
export PYTHONHASHSEED=0

# Re-apply the local Dart-extractor patch in case an upgrade wiped it.
graphify_python="$(head -1 "$(command -v graphify)" | tr -d '#!')"
"$graphify_python" graphify-arch/patches/apply_dart_extractor_patch.py

# Graphify 0.8.33's incremental --no-cluster branch overwrites graph.json with
# only the changed extraction. Use the repo-owned merger until upstream fixes
# that CLI path. Run it with Graphify's Python so package imports are available.
if [ "$mode" = "--rebuild" ]; then
  "$graphify_python" graphify-arch/refresh_graph.py --rebuild
else
  "$graphify_python" graphify-arch/refresh_graph.py
fi
python3 graphify-arch/tdd_context.py build
rm -f graphify-arch/.needs_incremental_refresh

if [ "$mode" = "--full" ] || [ "$mode" = "--rebuild" ]; then
  # Curated community labels live in graphify-out/.graphify_labels.json and are
  # sig-validated: cluster-only --no-label keeps every label whose community
  # membership is unchanged and hub-names only new/changed communities. Do NOT
  # add a `graphify label` call here — on this host no LLM backend works
  # (OPENAI_API_KEY invalid, claude-cli blocked by org policy, checked
  # 2026-07-18) and a failed label run overwrites the curated labels file with
  # bare hub names. To re-label accumulated hub-named communities, ask Claude
  # to regenerate them (see memory: graphify community labeling).
  graphify cluster-only graphify-arch --no-label
  (cd graphify-arch && graphify export html)

  python3 graphify-arch/compare_graphs.py \
    --full graphify-out/graph.json \
    --arch graphify-arch/graphify-out/graph.json \
    --out graphify-arch/GRAPH_SELECTION.md \
    --json-out graphify-arch/comparison.json
fi

echo "Architecture graph refreshed ($mode): graphify-arch/graphify-out/graph.json"
echo "TDD proof overlay refreshed: graphify-arch/tdd-overlay.json"
