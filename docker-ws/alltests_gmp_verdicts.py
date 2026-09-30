"""Read-only: summarize group multi-party orchestrator verdicts written since the run started."""
import json, pathlib, collections
t = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-tmp')
ref = (pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/source097-major-legacy/plan.json')).stat().st_mtime
files = [p for p in t.glob('group_multi_party_*/*orchestrator_verdict.json') if p.stat().st_mtime > ref]
print('verdicts', len(files))
first = json.loads(files[0].read_text()) if files else {}
print('keys', sorted(first)[:15])
c = collections.Counter(); bad = []
for p in files:
    v = json.loads(p.read_text())
    s = str(v.get('ok'))
    c[s] += 1
    if s != 'True':
        bad.append((p.parent.name[18:70], (v.get('reason') or v.get('failure') or v.get('detail') or '')[:120] if isinstance(v.get('reason') or v.get('failure') or v.get('detail') or '', str) else ''))
print(dict(c))
for b in bad[:12]: print(' ', b)
