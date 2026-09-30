"""Read-only: print detail of named orchestrator verdicts in the current sweep failures dir, and the ge016 proof block of a role verdict."""
import pathlib, sys, json
t = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-tmp')
sw = next(t.glob('group_multi_party_sweep_1790391161175_failures_*'))
for s in sys.argv[1:]:
    for f in sw.glob(f'*_{s}_orchestrator_verdict.json'):
        print('==', s, json.loads(f.read_text()).get('detail', '')[:600])
v = json.loads(next(t.glob('group_multi_party_ge016_*/gmp_*_bob_verdict.json')).read_text())
print('ge016 bob proof', json.dumps(v.get('ge016ConcurrentAdminMutationProof'))[:900])
