"""Read-only: print non-PASS verdicts + assessment reasons + invalidations from a sims json. usage: <relpath> [maxlen]"""
import json, sys, pathlib
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
d = json.loads((run/sys.argv[1]).read_text()); mx = int(sys.argv[2]) if len(sys.argv) > 2 else 700
tr = {t['capabilityId']: t for t in (d.get('schedule') or {}).get('traces', [])}
print('causal', (d.get('schedule') or {}).get('causalFailureId'), 'clean', d.get('cleanFullRun'), 'diagCont', d.get('diagnosticContinuation'))
for v in d.get('verdicts', []):
    if v.get('status') == 'PASS': continue
    t = tr.get(v['capabilityId'], {})
    print(f"# {v['capabilityId']} {v['status']} exit={v.get('exitCode')} asserts={v.get('assertionsAttempted')} artifact={v.get('artifactPresent')} {t.get('startedAt','')[:19]}..{t.get('endedAt','')[11:19]}")
    print('   blocker:', v.get('blocker')); print('   detail:', (v.get('detail') or '')[:mx])
print('PASS ids:', [v['capabilityId'] for v in d.get('verdicts', []) if v.get('status') == 'PASS'])
print('assessment reasons:'); [print('  -', str(r)[:300]) for r in (d.get('assessment') or {}).get('reasons', [])]
print('invalidations:'); [print('  -', json.dumps(r)[:300]) for r in (d.get('builds') or {}).get('invalidations', [])]
print('validationErrors', d.get('validationErrors'))
