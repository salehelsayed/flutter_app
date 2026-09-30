"""Read-only: full-legacy attempt summary (status, checkpoint, route counts, non-pass routes, block reasons)."""
import json, pathlib, collections
d = json.loads(pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/source097-major-legacy/results.json').read_text())
r = next(x for x in d['results'] if x['id'] == 'full-legacy')
for a in r.get('attempts', []):
    print({k: a.get(k) for k in ('status', 'checkpoint', 'exit_status', 'duration_seconds', 'reason', 'remediation')})
    rr = a.get('route_results') or []
    print('routes', len(rr), collections.Counter(x.get('status') for x in rr))
    for x in [x for x in rr if x.get('status') != 'PASS'][:25]:
        print('  ', x.get('id'), x.get('status'), x.get('checkpoint'))
print('gaps', [g for g in d.get('gaps', []) if 'legacy' in g.lower()][:5])
