"""Refresh the legacy_target_contracts sha256 pin for one file after a format pass (both checkouts).
Usage: <relpath>. Replaces the hash recorded under '"<relpath>": "<hash>"' with the file's current hash."""
import hashlib, pathlib, re, sys
rel = sys.argv[1]
for root in ('/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree'):
    new = hashlib.sha256(pathlib.Path(root, rel).read_bytes()).hexdigest()
    c = pathlib.Path(root, 'tool/testing/legacy_target_contracts.json'); ct = c.read_text()
    olds = set(re.findall(r'"' + re.escape(rel) + r'": "([0-9a-f]{64})"', ct))
    for old in olds:
        ct = ct.replace(old, new)
    c.write_text(ct)
    print(root, 'old', sorted(olds), 'new', new)
