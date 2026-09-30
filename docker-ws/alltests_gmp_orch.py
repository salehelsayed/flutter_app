"""Read-only: show orchestrator verdicts/timing for named scenario dirs and list sweep failure dirs."""
import pathlib, sys, json
t = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-tmp')
for pat in sys.argv[1:]:
    for d in t.glob(pat):
        for f in sorted(d.glob('*orchestrator_verdict.json')) + sorted(d.glob('*timing.json')) + sorted(d.glob('*_verdict.json'))[:1]:
            print('==', d.name, f.name); print(f.read_text(errors='replace')[:1300])
for d in sorted(t.glob('group_multi_party_sweep_*failures*')):
    print('SWEEP', d.name, [p.name for p in sorted(d.iterdir())][:40])
