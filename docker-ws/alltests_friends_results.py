"""Read-only: summarize intro_e2e result files on the three friends-smoke simulators (from the log's device order)."""
import json, subprocess, pathlib
sims = {'a': '674DFFF6-5F38-4235-93F6-AF7FBF86AE65', 'b': '6597ECAD-38EE-49AF-9A08-B1B0CA4BDD76', 'c': '8E31AD68-4DBF-4336-AEBF-18148DC9FA07'}
for role, udid in sims.items():
    try:
        docs = subprocess.run(['xcrun', 'simctl', 'get_app_container', udid, 'com.mknoon.app', 'data'],
                              capture_output=True, text=True, timeout=60).stdout.strip()
    except Exception as e:
        print(role, 'container error', e); continue
    d = pathlib.Path(docs) / 'Documents'
    for name in sorted(p.name for p in d.glob('intro_e2e*.json')):
        print(f'== {role} {name}')
        try:
            v = json.loads((d / name).read_text())
        except Exception as e:
            print('  unreadable', e); continue
        if name.endswith('result.json'):
            snap = v.get('snapshot', {})
            print('  stepId', v.get('stepId'), 'keys', sorted(v)[:12])
            for r in snap.get('introductions', []):
                print('  intro', r.get('id', '')[:8], 'rec', r.get('recipientStatus'), 'intr', r.get('introducedStatus'), 'overall', r.get('overallStatus'))
            print('  contacts', [c.get('peerId', '')[-6:] for c in snap.get('contacts', [])])
            for k in ('introAction', 'introDeliveryCustody', 'status', 'success'):
                if k in v: print(' ', k, json.dumps(v[k])[:300])
        else:
            print(' ', json.dumps(v)[:300])
