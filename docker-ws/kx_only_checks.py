#!/usr/bin/env python3
"""Run mknoon_checks with the device-audio adapter limited to chosen KX rows.

The adapter already supports --exclude kxNNNN and --continue-on-failure. This wrapper
appends an --exclude for every other KX row of the call-profile cohort, so only the base
proof plus the rows in KX_KEEP (comma-separated) run. Harness-only, run from a tree root:
  KX_KEEP=kx0006 python3 <this> run --mode change --base <rev> --local --only device-audio ...
"""
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path.cwd() / 'scripts'))
import mknoon_checks  # noqa: E402

KEEP = {k.strip() for k in os.environ.get('KX_KEEP', '').split(',') if k.strip()}
BASE = 'android.production_1to1_audio_call'


def cohort(root):
    rows = {r['id']: r for r in json.loads((root / 'tool/sims/critical_features.json').read_text())['capabilities']}
    profile = rows[BASE].get('buildProfile')
    return sorted(i for i, r in rows.items() if i.startswith('kx') and r.get('buildProfile') == profile
                  and r.get('active', True) and 'major' in r.get('modes', []))


original = mknoon_checks.command_for


def command_for(check, root, files):
    command, paths = original(check, root, files)
    if check.get('id') == 'device-audio' and KEEP:
        rows = cohort(Path(root))
        unknown = KEEP - set(rows)
        if unknown:
            raise SystemExit('KX_KEEP rows not in the call-profile cohort: ' + ','.join(sorted(unknown)))
        for row in rows:
            if row not in KEEP:
                command += ['--exclude', row]
        command.append('--continue-on-failure')
        paths = [p for p in paths if p == BASE or p in KEEP or not p.startswith('kx')]
    return command, paths


mknoon_checks.command_for = command_for
sys.exit(mknoon_checks.main(sys.argv[1:]))
