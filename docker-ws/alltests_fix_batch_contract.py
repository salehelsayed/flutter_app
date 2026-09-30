"""Make the batch gate contract hermetic against the outer wrapper's worker budget (both checkouts)."""
import pathlib
rel = 'scripts/test/host_test_gate_batch_contract_test.sh'
old = 'ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"\ncd "$ROOT_DIR"\n'
new = old + '\n# The contract pins direct-caller --concurrency behavior. An outer check\n# wrapper exports its own worker budget, which the gate would apply instead.\nunset MKNOON_HOST_FLUTTER_WORKERS\n'
for root in ('/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree'):
    p = pathlib.Path(root, rel); s = p.read_text()
    if new in s: print('already', root)
    elif s.count(old) == 1: p.write_text(s.replace(old, new, 1)); print('fixed', root)
    else: print('NO MATCH', root)
