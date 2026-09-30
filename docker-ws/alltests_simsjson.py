"""Read-only: summarize a sims json report. usage: alltests_simsjson.py <relpath> [ids,comma|ALLBAD] [maxlen]"""
import json, sys, pathlib
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
data = json.loads((run/sys.argv[1]).read_text())
want = sys.argv[2] if len(sys.argv) > 2 else 'KEYS'
mx = int(sys.argv[3]) if len(sys.argv) > 3 else 1500
def walk_keys(o, p='', d=0):
    if d > 3: return
    if isinstance(o, dict):
        for k, v in o.items():
            t = type(v).__name__ + (f'[{len(v)}]' if isinstance(v, (list, dict)) else '')
            print(f'{p}{k}: {t}'); walk_keys(v, p + '  ', d + 1)
    elif isinstance(o, list) and o:
        walk_keys(o[0], p + '  [0].', d + 1)
if want == 'KEYS': walk_keys(data); sys.exit()
def find_items(o):
    if isinstance(o, dict):
        if 'id' in o and ('status' in o or 'outcome' in o): yield o
        for v in o.values(): yield from find_items(v)
    elif isinstance(o, list):
        for v in o: yield from find_items(v)
ids = None if want == 'ALLBAD' else set(want.split(','))
for it in find_items(data):
    st = str(it.get('status') or it.get('outcome'))
    if ids is None and st.upper() in ('PASS', 'PASSED', 'SUCCESS'): continue
    if ids is not None and it.get('id') not in ids: continue
    print('#', it.get('id'), st); print('  ', json.dumps(it)[:mx])
