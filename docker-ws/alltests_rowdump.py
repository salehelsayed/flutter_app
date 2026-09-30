"""Read-only: dump selected (non-diagnostic_subset) rows of <label>/results.json (or partial.json) compactly.
usage: alltests_rowdump.py <label> [file] [maxlen]"""
import json, sys, pathlib
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
label = sys.argv[1]; fn = sys.argv[2] if len(sys.argv) > 2 else 'results.json'
mx = int(sys.argv[3]) if len(sys.argv) > 3 else 400
data = json.loads((run/label/fn).read_text())
print('top keys', list(data)[:20])
rows = data.get('results') or data.get('rows') or data.get('checks') or []
def short(v, m=mx):
    s = v if isinstance(v, str) else json.dumps(v)
    return s[:m]
for r in rows:
    if not isinstance(r, dict) or r.get('checkpoint') == 'diagnostic_subset': continue
    print('== ROW', r.get('id'), r.get('status'), r.get('checkpoint'))
    for k, v in r.items():
        if k in ('attempts',): continue
        print(f'  {k}: {short(v)}')
    for i, a in enumerate(r.get('attempts') or []):
        print(f'  -- attempt {i} keys {sorted(a)}')
        for k, v in a.items():
            if k in ('capability_results', 'step_results'): continue
            print(f'    {k}: {short(v)}')
        for key in ('step_results', 'capability_results'):
            items = a.get(key) or []
            if isinstance(items, dict): items = [dict(id=k, **(v if isinstance(v, dict) else {'v': v})) for k, v in items.items()]
            print(f'    {key}: n={len(items)}')
            for it in items:
                st = it.get('status') if isinstance(it, dict) else None
                if st in ('PASS', 'pass', 'passed') and key == 'capability_results': continue
                print('     *', short(it, int(sys.argv[4]) if len(sys.argv) > 4 else 600))
