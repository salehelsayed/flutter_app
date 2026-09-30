"""Focused diagnostic (not a check result): run selected group multi-party scenarios one at a time on the four
pinned simulators with the route env. Usage: <output label> <scenario>[,<scenario>...]. cwd = worktree, run env
sourced. Writes <run>/<label>/<scenario>.log and summary.json."""
import json, os, pathlib, subprocess, sys, time
sys.path.insert(0, 'scripts')
import mknoon_checks
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
out = run / sys.argv[1]
out.mkdir(mode=0o700, exist_ok=False)
config = json.loads((run / 'device-config-next.json').read_text())
sims = ['674DFFF6-5F38-4235-93F6-AF7FBF86AE65', '6597ECAD-38EE-49AF-9A08-B1B0CA4BDD76',
        '8E31AD68-4DBF-4336-AEBF-18148DC9FA07', 'DBE8C32E-9F19-4593-860A-B41113791D79']
env = os.environ.copy()
env.update(mknoon_checks.sims_environment(config, out / 'unused-sims-report.json'))
env['SIMS_IOS_DISPOSABLE_SIMULATOR_IDS'] = ','.join(sims)
summary = []
for scenario in sys.argv[2].split(','):
    started = time.time()
    with (out / f'{scenario}.log').open('w') as log:
        rc = subprocess.run(['dart', 'run', 'integration_test/scripts/run_group_multi_party_device_real.dart',
                             '--scenario', scenario, '-d', ','.join(sims)],
                            env=env, stdout=log, stderr=subprocess.STDOUT).returncode
    summary.append({'scenario': scenario, 'exit': rc, 'seconds': round(time.time() - started, 1)})
    (out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(scenario, 'exit', rc, flush=True)
print('done', flush=True)
