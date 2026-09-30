"""Read-only: find strings in repair-progress.json (and failure-report.md) mentioning a pattern. usage: <regex> [maxhits] [width]"""
import json, sys, pathlib, re
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
rx = re.compile(sys.argv[1]); mh = int(sys.argv[2]) if len(sys.argv) > 2 else 20; w = int(sys.argv[3]) if len(sys.argv) > 3 else 600
data = json.loads((run/'repair-progress.json').read_text())
hits = []
def walk(o, path):
    if isinstance(o, dict):
        for k, v in o.items(): walk(v, path + '.' + str(k))
    elif isinstance(o, list):
        for i, v in enumerate(o): walk(v, path + f'[{i}]')
    elif isinstance(o, str) and rx.search(o): hits.append((path, o))
walk(data, '$')
print('hits', len(hits))
for p, v in hits[-mh:]: print('*', p[:160], '=>', v[:w])
