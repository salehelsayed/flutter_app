#!/usr/bin/env bash
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
cd "${CLAUDE_HOST_REPO_ROOT:-$(pwd)}"

graphify_python="$(head -1 "$(command -v graphify)" | tr -d '#!')"
"$graphify_python" - <<'PYEOF'
from collections import Counter
from pathlib import Path
from graphify.detect import detect_incremental

d = detect_incremental(Path("."), manifest_path="graphify-out/manifest.json", kind="semantic")
new = d.get("new_files", {})
deleted = d.get("deleted_files", [])
unchanged = d.get("unchanged_files", {})
print("unchanged:", {k: len(v) for k, v in unchanged.items()})
print("new/changed:", {k: len(v) for k, v in new.items()})
print("deleted:", len(deleted))
exts = Counter(Path(p).suffix for p in new.get("code", []))
print("new/changed code by ext:", exts.most_common(15))
dexts = Counter(Path(p).suffix for p in deleted)
print("deleted by ext:", dexts.most_common(10))
print("sample new:", [str(p) for p in list(new.get("code", []))[:8]])
PYEOF
