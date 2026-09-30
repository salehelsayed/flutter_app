"""Read-only: show a plan.json selected check summary. usage: <label> <checkid> [width]"""
import json, sys, pathlib
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
p = json.loads((run/sys.argv[1]/'plan.json').read_text()); w = int(sys.argv[3]) if len(sys.argv) > 3 else 300
for c in p.get('selected', []):
    if c.get('id') != sys.argv[2]: continue
    for k, v in c.items():
        s = json.dumps(v); print(f'{k}: len={len(v) if isinstance(v,(list,dict)) else "-"} {s[:w]}')
