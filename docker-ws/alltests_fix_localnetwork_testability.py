"""Profile build-for-testing needs ENABLE_TESTABILITY=YES so RunnerTests' `@testable import Runner` resolves (both checkouts)."""
import json, pathlib
CID = 'full.xctest.notificationtapuitests.testautomatelocalnetworkpermission'
for root in ('/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree'):
    p = pathlib.Path(root, 'tool/testing/selection.json'); text = p.read_text(); data = json.loads(text); hits = []
    def walk(o):
        if isinstance(o, dict):
            if o.get('id') == CID: hits.append(o)
            for v in o.values(): walk(v)
        elif isinstance(o, list):
            for v in o: walk(v)
    walk(data); assert len(hits) == 1
    changed = 0
    for cmd in [hits[0]['command']] + [s['command'] for s in hits[0].get('steps', [])]:
        if len(cmd) > 1 and cmd[1] == 'build-for-testing' and 'ENABLE_TESTABILITY=YES' not in cmd:
            i = cmd.index('-configuration'); cmd.insert(i + 2, 'ENABLE_TESTABILITY=YES'); changed += 1
    p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + ('\n' if text.endswith('\n') else ''))
    print(root, 'changed', changed)
