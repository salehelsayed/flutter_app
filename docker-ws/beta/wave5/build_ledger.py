#!/usr/bin/env python3
"""Wave 5 step 3: total the SIMS build blocks of every recorded campaign run.

Read-only. Usage: build_ledger.py <runs-dir> [--json out.json]
For each *-sims.json report: builds per profile, cache hits, invalidation reasons,
source digest and elapsed build time. Rebuilds are grouped by reason so a warm
rebuild of an unchanged input (reason other than a changed input) stands out.
"""
import glob, json, os, sys, collections

runs = sys.argv[1]
rows = []
for path in sorted(glob.glob(os.path.join(runs, '*', '*-sims.json'))):
    try:
        d = json.load(open(path))
    except Exception as e:
        print('unreadable', path, e); continue
    b = d.get('builds') or {}
    rows.append({
        'run': os.path.basename(os.path.dirname(path)),
        'report': os.path.basename(path),
        'source': d.get('sourceDigest'),
        'selected': d.get('selectedIds'),
        'requested': b.get('requestedProfiles', 0),
        'built': b.get('builtProfileIds', []),
        'hits': b.get('cacheHitProfileIds', []),
        'failed': b.get('failedProfileIds', []),
        'invalidations': b.get('invalidations', []),
        'declared': b.get('declaredExceptions', []),
        'elapsed': b.get('profileElapsedMs', {}),
        'digests': b.get('artifactDigests', {}),
    })
reasons = collections.Counter(i.split(':', 1)[1] for r in rows for i in r['invalidations'])
built = collections.Counter(p for r in rows for p in r['built'])
hits = collections.Counter(p for r in rows for p in r['hits'])
ms = collections.defaultdict(int)
for r in rows:
    for p in r['built']:
        ms[p] += r['elapsed'].get(p, 0)
print(f'reports {len(rows)}  requested {sum(r["requested"] for r in rows)}  '
      f'built {sum(built.values())}  hits {sum(hits.values())}  '
      f'failed {sum(len(r["failed"]) for r in rows)}  declared exceptions {sum(len(r["declared"]) for r in rows)}')
print('invalidation reasons:', dict(reasons))
print(f'{"profile":42} {"built":>5} {"hits":>5} {"build min":>9}')
for p in sorted(set(built) | set(hits)):
    print(f'{p:42} {built[p]:5} {hits[p]:5} {ms[p]/60000:9.1f}')
# Same artifact digest built twice = a rebuild that produced identical output.
seen = collections.defaultdict(list)
for r in rows:
    for p in r['built']:
        seen[(p, r['digests'].get(p))].append(r['run'])
dups = {k: v for k, v in seen.items() if len(v) > 1}
print('profiles rebuilt to an identical artifact digest:', len(dups))
for (p, dg), v in sorted(dups.items()):
    print(' ', p, (dg or '')[:12], v)
if '--json' in sys.argv:
    json.dump(rows, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1)
