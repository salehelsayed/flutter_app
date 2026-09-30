"""Read-only: print repair-progress attempts for checks. usage: <checkid> [lastN] [width]"""
import json, sys, pathlib
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
data = json.loads((run/'repair-progress.json').read_text())
n = int(sys.argv[2]) if len(sys.argv) > 2 else 2; w = int(sys.argv[3]) if len(sys.argv) > 3 else 1500
c = data['checks'].get(sys.argv[1])
if c is None: print('no check'); sys.exit()
print({k: (v if not isinstance(v, (list, dict)) else type(v).__name__) for k, v in c.items()})
for a in (c.get('attempts') or [])[-n:]: print('  ATT', json.dumps({k: v for k, v in a.items() if k != 'identity'})[:w], 'src', (a.get('identity') or {}).get('source_sha256','')[:12])
if sys.argv[1] == 'ACTIVE': pass
