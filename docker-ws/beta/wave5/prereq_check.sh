#!/bin/bash
# Evaluate only the prerequisites of selected full-run checks against the Wave 5 config (no tests run).
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$HOME/.maestro/bin:$HOME/development/flutter-3.47.2/bin:/usr/local/go/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"
python3 - <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, 'scripts')
import mknoon_checks as m
root = Path('.').resolve()
cfg = json.load(open('.codex-test-logs/production-bootstrap-migration-20260930/wave5-full-device-config.json'))
sel = json.load(open('tool/testing/selection.json'))
fc = {c['id']: c for c in sel['full_commands']}
matrix = m.device_matrix() if hasattr(m, 'device_matrix') else None
print('matrix fn:', [n for n in dir(m) if 'matrix' in n.lower()][:8])
PY
