#!/bin/bash
# Plan 414: run tests with the JSON reporter and list each test result.
cd "$(cd "$(dirname "$0")/.." && pwd)"
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
OUT="Test-Flight-Improv/evidence/414/$1"; shift
"$SDK/bin/flutter" test --no-pub --reporter json "$@" > "$OUT.json" 2>/dev/null
echo "EXIT=$?"
python3 - "$OUT.json" > "$OUT" <<'PY'
import json, sys
names = {}
for line in open(sys.argv[1]):
    try:
        e = json.loads(line)
    except Exception:
        continue
    if e.get('type') == 'testStart':
        names[e['test']['id']] = e['test']['name']
    if e.get('type') == 'testDone' and not e.get('hidden'):
        print(e['result'], names.get(e['testID'], '?'))
PY
rm -f "$OUT.json"
python3 - "$OUT" <<'PY'
import sys
rows = open(sys.argv[1]).read().splitlines()
print('success:', sum(r.startswith('success') for r in rows), 'of', len(rows))
for r in rows:
    if not r.startswith('success') or '414' in r:
        print(r)
PY
