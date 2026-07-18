#!/usr/bin/env bash
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
cd "${CLAUDE_HOST_REPO_ROOT:-$(pwd)}"

graphify_python="$(head -1 "$(command -v graphify)" | tr -d '#!')"

echo "=== idempotency: rerun patch ==="
"$graphify_python" graphify-arch/patches/apply_dart_extractor_patch.py

echo "=== extraction smoke test ==="
mkdir -p .claude-host-tmp/patch-smoke
cat > .claude-host-tmp/patch-smoke/sample.dart <<'EOF'
/* multi
   line
   comment */
class MediaRepository {
  Future<(String, int?)>
  handleIncomingChatMessage({int? id}) async {
    String verifyCommittedLocalPath(String p) {
      return p;
    }
    final T = 1;
    return ('x', id);
  }
}
EOF
"$graphify_python" - <<'PYEOF'
import json
from pathlib import Path
from graphify.extractors.dart import extract_dart
out = extract_dart(Path(".claude-host-tmp/patch-smoke/sample.dart"))
for n in out["nodes"]:
    print(n["label"], "|", n.get("source_location"))
print("edges with local_function ctx:", [e for e in out["edges"] if e.get("context") == "local_function"] and "YES" or "NO")
PYEOF
