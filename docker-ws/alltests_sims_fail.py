"""Read-only: failing capability/route rows inside one check's attempts (sims/legacy)."""
import json, sys, pathlib
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
d = json.loads((run / sys.argv[1] / 'results.json').read_text())
for r in d['results']:
    if r['id'] != sys.argv[2]: continue
    for a in r.get('attempts', []):
        print('attempt', a.get('status'), a.get('checkpoint'), 'exit', a.get('exit_status'), 'dur', a.get('duration_seconds'))
        for key in ('capability_results', 'route_results'):
            rows = a.get(key) or []
            bad = [x for x in rows if x.get('status') not in ('PASS', 'N/A')]
            print(' ', key, 'total', len(rows), 'non-pass', len(bad), 'pass', sum(1 for x in rows if x.get('status') == 'PASS'))
            for x in bad[:40]:
                print('   ', x.get('id'), x.get('status'), (x.get('reason') or x.get('checkpoint') or '')[:200] if isinstance(x.get('reason') or x.get('checkpoint') or '', str) else '')
