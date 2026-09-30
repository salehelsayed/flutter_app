"""Build the Local Network XCTest adapter in Profile mode (both checkouts). A Debug Flutter app launched by
XCUITest on a physical iOS 14+ device never starts Dart, so the Local Network prompt can never appear."""
import json, pathlib
CID = 'full.xctest.notificationtapuitests.testautomatelocalnetworkpermission'
for root in ('/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree'):
    p = pathlib.Path(root, 'tool/testing/selection.json'); text = p.read_text()
    data = json.loads(text); hits = []
    def walk(o):
        if isinstance(o, dict):
            if o.get('id') == CID: hits.append(o)
            for v in o.values(): walk(v)
        elif isinstance(o, list):
            for v in o: walk(v)
    walk(data); assert len(hits) == 1, len(hits)
    entry = hits[0]; changed = 0
    for cmd in [entry.get('command', [])] + [s.get('command', []) for s in entry.get('steps', [])]:
        for i in range(len(cmd) - 1):
            if cmd[i] == '-configuration' and cmd[i + 1] == 'Debug': cmd[i + 1] = 'Profile'; changed += 1
    indent = 2 if '\n  "' in text[:200] else 4
    p.write_text(json.dumps(data, indent=indent, ensure_ascii=False) + ('\n' if text.endswith('\n') else ''))
    print(root, 'changed', changed)
