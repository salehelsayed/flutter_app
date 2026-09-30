"""Focused diagnostic: run one smoke_test_friends.sh scenario on the pinned simulators with the route's env.
Usage: <output label> <scenario key>. Run with cwd = worktree and the run env sourced. Not a check result."""
import json, os, pathlib, subprocess, sys
sys.path.insert(0, 'scripts')
import mknoon_checks
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
out = run / sys.argv[1]
out.mkdir(mode=0o700, exist_ok=False)
config = json.loads((run / 'device-config-next.json').read_text())
env = os.environ.copy()
env.update(mknoon_checks.sims_environment(config, out / 'unused-sims-report.json'))
env.update(DEVICE_A='674DFFF6-5F38-4235-93F6-AF7FBF86AE65', DEVICE_B='6597ECAD-38EE-49AF-9A08-B1B0CA4BDD76',
           DEVICE_C='8E31AD68-4DBF-4336-AEBF-18148DC9FA07', DEVICE_D='DBE8C32E-9F19-4593-860A-B41113791D79',
           INTRO_E2E_SCENARIO=sys.argv[2])
with (out / 'friends.log').open('w') as log:
    result = subprocess.run(['bash', 'smoke_test_friends.sh'], env=env, stdout=log, stderr=subprocess.STDOUT)
(out / 'exit.txt').write_text(str(result.returncode) + '\n')
print('exit', result.returncode, flush=True)
