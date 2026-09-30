"""Focused diagnostic (not a check result): run selected SIMS major capabilities with the run's device config env,
while streaming the physical Pixel's logcat to a file. Usage: <output label> <cap>[,<cap>...]. cwd = worktree,
run env sourced. Writes <run>/<label>/{sims.log,report.json,pixel-logcat.txt}."""
import json, os, pathlib, subprocess, sys
sys.path.insert(0, 'scripts')
import mknoon_checks
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
out = run / sys.argv[1]
out.mkdir(mode=0o700, exist_ok=False)
config = json.loads((run / 'device-config-next.json').read_text())
report = out / 'report.json'
env = os.environ.copy()
env.update(mknoon_checks.sims_environment(config, report, {'kind': 'sims', 'capability': sys.argv[2].split(',')[0]}))
pixel = config['devices'].get('android_physical', '21071FDF600CSC')
subprocess.run(['adb', '-s', pixel, 'logcat', '-c'], check=False)
logcat = subprocess.Popen(['adb', '-s', pixel, 'logcat', '-v', 'time'],
                          stdout=(out / 'pixel-logcat.txt').open('w'), stderr=subprocess.STDOUT)
try:
    cmd = ['dart', 'tool/sims/sims.dart', 'major', '--format', 'json']
    for cap in sys.argv[2].split(','):
        cmd += ['--only', cap]
    with (out / 'sims.log').open('w') as log:
        rc = subprocess.run(cmd, env=env, stdout=log, stderr=subprocess.STDOUT).returncode
finally:
    logcat.terminate()
(out / 'exit.txt').write_text(f'{rc}\n')
print('exit', rc, flush=True)
