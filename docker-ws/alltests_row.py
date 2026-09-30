"""Read-only: print one check row (attempt details) from a run-root report, with long strings cut."""
import json, sys, pathlib
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
label, cid = sys.argv[1], sys.argv[2]
for name in ('results.json', 'partial.json'):
    f = run / label / name
    if f.exists():
        d = json.loads(f.read_text())
        for r in d.get('results', []):
            if r.get('id') == cid:
                s = json.dumps(r, indent=1)
                print(s[:int(sys.argv[3]) if len(sys.argv) > 3 else 5000])
        break
