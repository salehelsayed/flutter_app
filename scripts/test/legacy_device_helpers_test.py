"""kx0031: promote the old bash-helper safety probes to workflow tests.

All device, signing and Flutter boundaries are stubbed in temporary Git repos.
The only real child processes belong to the process-owner test below. These
contracts do not certify a device install, a signature, or the Python launcher.
"""

import hashlib, json, os, pathlib, plistlib, shlex, shutil, subprocess, sys, tempfile, time, unittest, uuid

SOURCE = pathlib.Path(__file__).resolve().parents[2]

BASE = None

CASES = []

PLATFORM = r'''#!/usr/bin/env python3
import os,sys,json,hashlib,pathlib
args=sys.argv[1:]; tool=pathlib.Path(sys.argv[0]).name
log=pathlib.Path(os.environ['AUDIT_EVENTS'])
def event(x):
 with log.open('a') as f:f.write(json.dumps(x)+'\n')
if tool=='xcrun':
 if args[:4]==['simctl','list','devices','booted']:
  print(json.dumps({'devices':{'fixture':[{'udid':os.environ['AUDIT_SIM'],'name':'iPhone fixture','state':'Booted'}]}}));sys.exit(0)
 target=None
 if '--device' in args:target=args[args.index('--device')+1]
 elif args[:2] in [['simctl','install'],['simctl','launch'],['simctl','terminate'],['simctl','io']]:
  target=args[2] if args[2]!='--terminate-running-process' else args[3]
 event({'tool':tool,'op':' '.join(args[:4]),'target':hashlib.sha256(target.encode()).hexdigest() if target else None})
 if args[:2]==['codesign','--force']:
  stage='framework' if args[-1].endswith('Flutter.framework') else 'app'
  if os.environ.get('AUDIT_RESIGN_FAIL')==stage:sys.exit(19)
 if args[:4]==['devicectl','device','install','app'] and os.environ.get('AUDIT_FAIL_FIRST')=='1':
  marker=log.with_suffix('.first');
  if not marker.exists():marker.touch();sys.exit(1)
 if '--json-output' in args:
  pathlib.Path(args[args.index('--json-output')+1]).write_text(json.dumps({'result':{'apps':[{'bundleIdentifier':'com.mknoon.app','bundleVersion':'17'}]}}))
 sys.exit(0)
if tool=='ps':
 field=args[-1]
 if field=='uid=':print(os.getuid()+(1 if os.environ.get('AUDIT_FOREIGN')=='1' else 0))
 elif field=='comm=':print('/usr/bin/sleep' if os.environ.get('AUDIT_WRONG_PROGRAM')=='1' else sys.executable)
 else:
  root=os.environ['AUDIT_VARIANT_ROOT'];prefix='other/' if os.environ.get('AUDIT_WRONG_COMMAND')=='1' else '';print(f'{sys.executable} {root}/{prefix}serve.py {root}/server {root}/cert.pem {root}/key.pem')
 sys.exit(0)
if tool=='flutter':
 event({'tool':tool})
 if args[:2]==['build','apk']:
  p=pathlib.Path('build/app/outputs/flutter-apk/app-debug.apk');p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'fixture-apk')
 sys.exit(0)
if tool=='dart':
 event({'tool':tool})
 if '--key' in args and not pathlib.Path(args[args.index('--key')+1]).is_file():sys.exit(19)
 if '--out' in args:pathlib.Path(args[args.index('--out')+1]).write_text('fixture-output')
 sys.exit(0)
if tool=='kill':event({'tool':'kill','stop':not ('-0' in args)});sys.exit(0)
sys.exit(0)
'''

def fixture():
    root = pathlib.Path(tempfile.mkdtemp(dir=BASE))
    repo = root / 'repo'
    (repo / 'docker-ws').mkdir(parents=True)
    (repo / 'scripts').mkdir()
    for p in (SOURCE / 'docker-ws').glob('*.sh'):
        if p.name in {'fetch_codex_artifact.sh', 'mknoon_checks_host.sh', 'resign_and_install_iphones.sh', 'install_iphones_keep_identity.sh', 'se41_test_log.sh', 'se41_test_variant.sh', 'se55_iphone11_deploy.sh', '_flutter_sdk_env.sh', '_device_targets.sh', '_host_paths.sh'}:
            shutil.copy2(p, repo / 'docker-ws' / p.name)
    for name in ['se41_test_variant.sh']:
        p = repo / 'docker-ws' / name
        s = p.read_text()
        s = s.replace('ROOT=/Volumes/CrucialX9/se41_test', 'ROOT="$AUDIT_VARIANT_ROOT"')
        p.write_text(s)
    p = repo / 'docker-ws/se55_iphone11_deploy.sh'
    s = p.read_text().replace('cd /Volumes/CrucialX9/flutter_app || exit 1', 'cd "$AUDIT_REPO" || exit 1')
    p.write_text(s)
    shutil.copy2(SOURCE / '.gitignore', repo / '.gitignore')
    subprocess.run(['git', 'init', '-q', str(repo)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    (repo / 'sentinel.txt').write_text('preserve')
    subprocess.run(['git', '-C', str(repo), 'add', '-f', 'sentinel.txt'], check=True)
    bin = root / 'bin'
    bin.mkdir()
    for name in ['xcrun', 'ps', 'flutter', 'dart', 'kill']:
        p = bin / name
        p.write_text(PLATFORM)
        p.chmod(493)
    app = repo / 'build/ios/iphoneos/Runner.app'
    (app / 'Frameworks/Flutter.framework').mkdir(parents=True)
    (app / 'Runner').write_text('BridgeGenerateIdentity')
    with (app / 'Info.plist').open('wb') as f:
        plistlib.dump({'CFBundleVersion': '17', 'CFBundleShortVersionString': '1.0'}, f)
    variant = root / 'variant'
    (variant / 'server/mknoon').mkdir(parents=True)
    (variant / 'app').mkdir()
    (repo / 'scripts/mknoon_checks.py').write_text("import pathlib,sys\na=sys.argv[1:]\nif '--output' in a:\n p=pathlib.Path(a[a.index('--output')+1]);p.mkdir(parents=True,exist_ok=True);(p/'report.json').write_text('fixture')\nprint('fixture runner')\n")
    (repo / 'docker-ws/build_ios_flowlog.sh').write_text('#!/bin/bash\nexit 0\n')
    env = dict(os.environ)
    for k in ['IPHONE_UDIDS', 'IPHONE11_UDID', 'IPHONE13_UDID', 'BASH_ENV', 'ENV', 'MKNOON_FLUTTER_SDK']:
        env.pop(k, None)
    env.update(PATH=str(bin) + ':' + env['PATH'], MKNOON_FLUTTER_SDK=str(root / 'absent-sdk'), AUDIT_REPO=str(repo), AUDIT_VARIANT_ROOT=str(variant), AUDIT_EVENTS=str(root / 'events'), AUDIT_SIM=str(uuid.uuid4()), AUDIT_FOREIGN='0')
    bashenv = root / 'bashenv'
    bashenv.write_text('kill() { "' + sys.executable + '" "' + str(bin / 'kill') + '" "$@"; }\nexport -f kill\n')
    env['BASH_ENV'] = str(bashenv)
    return (root, repo, env)

def run(repo, env, name, *args):
    return subprocess.run(['bash', str(repo / 'docker-ws' / name), *map(str, args)], cwd=repo, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)

def events(env):
    p = pathlib.Path(env['AUDIT_EVENTS'])
    return [json.loads(l) for l in p.read_text().splitlines()] if p.exists() else []

def case(name, fn):
    CASES.append((name, fn))

def target_case(name, missing=False, invalid=False, precedence=False, fallback=False):
    root, repo, e = fixture()
    a = uuid.uuid4().hex + uuid.uuid4().hex[:8]
    b = uuid.uuid4().hex + uuid.uuid4().hex[:8]
    cfg = repo / 'docker-ws/local_devices.env'
    if precedence or fallback:
        cfg.write_text('IPHONE_UDIDS=' + b + '\n')
    if not missing:
        e['IPHONE_UDIDS'] = 'invalid-target' if invalid else a
    if fallback:
        e['AUDIT_FAIL_FIRST'] = '1'
    p = run(repo, e, name)
    ts = [x['target'] for x in events(e) if x.get('target')]
    if missing or invalid:
        return p.returncode != 0 and (not ts)
    return p.returncode == 0 and bool(ts) and all((t == hashlib.sha256(a.encode()).hexdigest() for t in ts))

case('installer_missing_target_refuses', lambda: target_case('install_iphones_keep_identity.sh', missing=True))

case('installer_invalid_target_refuses', lambda: target_case('install_iphones_keep_identity.sh', invalid=True))

case('resign_missing_target_refuses', lambda: target_case('resign_and_install_iphones.sh', missing=True))

case('resign_invalid_target_refuses', lambda: target_case('resign_and_install_iphones.sh', invalid=True))

case('explicit_target_beats_local_file', lambda: target_case('resign_and_install_iphones.sh', precedence=True))

case('fallback_keeps_exact_explicit_target', lambda: target_case('install_iphones_keep_identity.sh', fallback=True))

case('explicit_valid_target_works', lambda: target_case('install_iphones_keep_identity.sh'))

def sim(explicit=False):
    _, r, e = fixture()
    if explicit:
        e['IPHONE_UDIDS'] = e['AUDIT_SIM']
    p = run(r, e, 'se41_test_variant.sh', 'sim', 'install')
    ts = [x['target'] for x in events(e) if x.get('target')]
    return p.returncode == 0 and ts == [hashlib.sha256(e['AUDIT_SIM'].encode()).hexdigest()] if explicit else p.returncode != 0 and (not ts)

case('sim_missing_target_refuses', lambda: sim(False))

case('sim_explicit_target_works', lambda: sim(True))

def output(kind, safe=False):
    root, r, e = fixture()
    dst = root / 'outside.log' if safe else r / 'sentinel.txt'
    if kind == 'log':
        p = run(r, e, 'mknoon_checks_host.sh', dst, '--help')
    elif kind == 'runner-output':
        p = run(r, e, 'mknoon_checks_host.sh', r / 'build/check.log', 'run', '--output', r / 'source-output')
    else:
        p = run(r, e, 'se41_test_variant.sh', kind, *(['17', dst] if kind == 'build' else [root / 'payload', dst]))
    if kind == 'runner-output':
        return p.returncode != 0 and (not (r / 'source-output/report.json').exists())
    return p.returncode == 0 and dst.exists() if safe else p.returncode != 0 and (r / 'sentinel.txt').read_text() == 'preserve'

case('log_cannot_overwrite_tracked_file', lambda: output('log'))

case('log_outside_repo_allowed', lambda: output('log', True))

case('runner_output_cannot_write_source_dir', lambda: output('runner-output'))

case('build_output_cannot_overwrite_tracked_file', lambda: output('build'))

case('sign_output_cannot_overwrite_tracked_file', lambda: output('sign'))

def process(foreign):
    _, r, e = fixture()
    e['AUDIT_FOREIGN'] = '1' if foreign else '0'
    p = run(r, e, 'se41_test_variant.sh', 'serve-kill', str(1000000000))
    k = [x for x in events(e) if x.get('tool') == 'kill' and x.get('stop')]
    return p.returncode != 0 and (not k) if foreign else p.returncode == 0 and len(k) == 1

case('foreign_owner_process_preserved', lambda: process(True))

case('owned_exact_server_can_stop', lambda: process(False))

def deploy():
    root, r, e = fixture()
    e['IPHONE_UDIDS'] = uuid.uuid4().hex + uuid.uuid4().hex[:8]
    (r / 'docker-ws/local_devices.env').write_text('IPHONE11_UDID=' + e['IPHONE_UDIDS'] + '\n')
    (r / 'docker-ws/install_iphones_keep_identity.sh').write_text('#!/bin/bash\nexit 17\n')
    return run(r, e, 'se55_iphone11_deploy.sh', root / 'evidence').returncode == 17

case('deploy_propagates_installer_failure', deploy)

def publish():
    root, r, e = fixture()
    return run(r, e, 'se41_test_variant.sh', 'publish', root / 'missing-source').returncode != 0

case('publish_failure_is_not_success', publish)

def local_target(empty=False):
    _, r, e = fixture()
    t = uuid.uuid4().hex + uuid.uuid4().hex[:8]
    (r / 'docker-ws/local_devices.env').write_text('IPHONE_UDIDS=' + t + '\n')
    if empty:
        e['IPHONE_UDIDS'] = ''
    p = run(r, e, 'install_iphones_keep_identity.sh')
    ts = [x['target'] for x in events(e) if x.get('target')]
    return p.returncode != 0 and (not ts) if empty else p.returncode == 0 and bool(ts) and all((x == hashlib.sha256(t.encode()).hexdigest() for x in ts))

case('local_file_explicit_target_works', lambda: local_target())

case('explicit_empty_target_does_not_fall_back', lambda: local_target(True))

def sim_invalid(multiple=False):
    _, r, e = fixture()
    e['IPHONE_UDIDS'] = e['AUDIT_SIM'] + ' ' + str(uuid.uuid4()) if multiple else 'invalid-target'
    p = run(r, e, 'se41_test_variant.sh', 'sim', 'install')
    return p.returncode != 0 and (not events(e))

case('sim_invalid_target_refuses', lambda: sim_invalid())

case('sim_multiple_targets_refuses', lambda: sim_invalid(True))

def process_mismatch(flag):
    _, r, e = fixture()
    e[flag] = '1'
    p = run(r, e, 'se41_test_variant.sh', 'serve-kill', str(1000000000))
    return p.returncode != 0 and (not any((x.get('tool') == 'kill' for x in events(e))))

case('wrong_program_preserved', lambda: process_mismatch('AUDIT_WRONG_PROGRAM'))

case('wrong_server_command_preserved', lambda: process_mismatch('AUDIT_WRONG_COMMAND'))

def output_symlink():
    _, r, e = fixture()
    (r / 'build/link.log').symlink_to(r / 'sentinel.txt')
    p = run(r, e, 'mknoon_checks_host.sh', r / 'build/link.log', '--help')
    return p.returncode != 0 and (r / 'sentinel.txt').read_text() == 'preserve'

case('ignored_output_symlink_cannot_overwrite_source', output_symlink)

def result_symlink(name):
    _, r, e = fixture()
    e['IPHONE_UDIDS'] = uuid.uuid4().hex + uuid.uuid4().hex[:8]
    d = r / 'build/device-install'
    d.mkdir()
    (d / (name.removesuffix('.sh') + '_result.txt')).symlink_to(r / 'sentinel.txt')
    p = run(r, e, name)
    return p.returncode != 0 and (not events(e)) and ((r / 'sentinel.txt').read_text() == 'preserve')

case('installer_result_symlink_refuses', lambda: result_symlink('install_iphones_keep_identity.sh'))

case('resign_result_symlink_refuses', lambda: result_symlink('resign_and_install_iphones.sh'))

def traversal(name, args):
    _, r, e = fixture()
    e['IPHONE_UDIDS'] = e['AUDIT_SIM']
    p = run(r, e, name, *args)
    return p.returncode != 0 and (not events(e))

case('log_traversal_refuses', lambda: traversal('se41_test_log.sh', ['../sentinel.txt']))

case('screenshot_traversal_refuses', lambda: traversal('se41_test_variant.sh', ['sim', 'shot', '../sentinel']))

def copy_failure():
    _, r, e = fixture()
    p = pathlib.Path(e['PATH'].split(':')[0]) / 'rsync'
    p.write_text('#!/bin/bash\nexit 17\n')
    p.chmod(493)
    return run(r, e, 'se41_test_variant.sh', 'copy').returncode == 17

case('copy_propagates_rsync_failure', copy_failure)

def missing_signing_key():
    root, repo, env = fixture()
    payload = root / 'payload.json'
    payload.write_text('{}')
    out = root / 'signed.json'
    result = run(repo, env, 'se41_test_variant.sh', 'sign', payload, out)
    return result.returncode == 19 and (not out.exists()) and any((x.get('tool') == 'dart' for x in events(env)))

case('missing_signing_key_failure_propagates_without_output', missing_signing_key)

def resign_failure(stage):
    root, repo, env = fixture()
    env['IPHONE_UDIDS'] = uuid.uuid4().hex + uuid.uuid4().hex[:8]
    env['AUDIT_RESIGN_FAIL'] = stage
    temp = root / 'owned-temp'
    temp.mkdir()
    env['TMPDIR'] = str(temp)
    app = repo / 'build/ios/iphoneos/Runner.app'
    result = run(repo, env, 'resign_and_install_iphones.sh')
    log = events(env)
    return result.returncode != 0 and app.is_dir() and ((repo / 'sentinel.txt').read_text() == 'preserve') and (not list(temp.iterdir())) and (not any((x.get('op', '').startswith('devicectl') for x in log))) and ('OK bundleVersion=' not in result.stdout)

case('framework_resign_failure_aborts_before_install_and_leaves_no_temp', lambda: resign_failure('framework'))

case('app_resign_failure_aborts_before_install_and_leaves_no_temp', lambda: resign_failure('app'))

class LegacyDeviceHelpersTest(unittest.TestCase):

    def setUp(self):
        global BASE
        self.temp = tempfile.TemporaryDirectory(prefix='legacy-helper-contract-')
        self.addCleanup(self.temp.cleanup)
        BASE = pathlib.Path(self.temp.name).resolve()

    def test_stubbed_target_path_signing_and_process_boundaries(self):
        for name, probe in CASES:
            with self.subTest(boundary=name):
                self.assertTrue(probe(), name)

    def test_artifact_copy_rejects_resolved_source_and_destination_escapes(self):
        root, repo, env = fixture()
        script = repo / 'docker-ws/fetch_codex_artifact.sh'
        prefix = str(root / 'allowed_')
        script.write_text(script.read_text().replace('/Volumes/CrucialX9/flutter_app_codex_*', shlex.quote(prefix) + '*'))
        allowed = root / 'allowed_fixture'
        allowed.mkdir()
        outside = root / 'outside'
        outside.mkdir()
        good = allowed / 'good.txt'
        good.write_text('fixture-artifact')
        other = outside / 'outside.txt'
        other.write_text('preserve-outside')
        link = allowed / 'link.txt'
        link.symlink_to(other)
        for label, path, success in [('valid_source', good, True), ('dotdot_escape', allowed / '..' / 'outside' / 'outside.txt', False), ('symlink_escape', link, False)]:
            with self.subTest(boundary=label):
                target = repo / 'build/codex_artifacts' / label
                result = run(repo, env, 'fetch_codex_artifact.sh', path, label)
                if success:
                    self.assertEqual(result.returncode, 0)
                    self.assertEqual(target.read_text(), 'fixture-artifact')
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(target.exists())
        dest = repo / 'build/codex_artifacts/symlink-output'
        dest.symlink_to(repo / 'sentinel.txt')
        result = run(repo, env, 'fetch_codex_artifact.sh', good, dest.name)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((repo / 'sentinel.txt').read_text(), 'preserve')

    def test_owned_process_exact_command_guard(self):
        root = BASE / 'real-process'
        repo = root / 'repo'
        (repo / 'docker-ws').mkdir(parents=True)
        variant = root / 'variant'
        (variant / 'server').mkdir(parents=True)
        for name in ['_host_paths.sh', '_flutter_sdk_env.sh']:
            shutil.copy2(SOURCE / 'docker-ws' / name, repo / 'docker-ws' / name)
        text = (SOURCE / 'docker-ws/se41_test_variant.sh').read_text().replace('ROOT=/Volumes/CrucialX9/se41_test', 'ROOT="' + str(variant) + '"')
        script = repo / 'docker-ws/se41_test_variant.sh'
        script.write_text(text)
        (variant / 'serve.py').write_text('import time\ntime.sleep(60)\n')
        env = dict(os.environ)
        env.pop('BASH_ENV', None)
        env.pop('ENV', None)
        for wrong in [True, False]:
            with self.subTest(wrong_command=wrong):
                args = [sys.executable, str(variant / 'serve.py'), str(variant / ('other-server' if wrong else 'server')), str(variant / 'cert.pem'), str(variant / 'key.pem')]
                proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                try:
                    time.sleep(0.15)
                    result = subprocess.run(['bash', str(script), 'serve-kill', str(proc.pid)], cwd=repo, env=env, capture_output=True, timeout=10)
                    if wrong:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIsNone(proc.poll())
                    else:
                        self.assertEqual(result.returncode, 0)
                        self.assertIsNotNone(proc.wait(timeout=5))
                finally:
                    if proc.poll() is None:
                        proc.terminate()
                        proc.wait(timeout=5)

if __name__ == '__main__':
    unittest.main()
