"""Read-only: print partial.json rows for selected ids. usage: <label>"""
import json, sys, pathlib
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
d = json.loads((run/sys.argv[1]/'partial.json').read_text())
sel = set(d.get('selected_ids') or [])
print('selected', sorted(sel), 'status', d.get('status'))
for r in d.get('results') or []:
    if r.get('id') in sel: print(json.dumps({k: v for k, v in r.items() if k not in ('command','selected_paths','investigate')})[:900])
