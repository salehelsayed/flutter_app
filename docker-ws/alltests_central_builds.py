"""Fresh central builds for the iOS chat-group recipient check (adapted from the run's prepare-central-builds-011.py
and select-central-artifacts.py). Run with cwd = the all-tests worktree and the run env sourced.
Usage: <output label>. Writes <run>/<label>/ reports + selected-artifacts.json and <run>/device-config-chatgroup.json
(a copy of device-config-next.json with only the chat-group adapter's prebuilt paths replaced)."""
import json, os, pathlib, subprocess, sys
sys.path.insert(0, 'scripts')
import mknoon_checks

root = pathlib.Path.cwd()
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
out = run / sys.argv[1]
out.mkdir(mode=0o700, exist_ok=False)
config = json.loads((run / 'device-config-next.json').read_text())
CID = 'full.group-reaction.ios_chat_group_message_and_reaction_recipient'

for profile in ('android.production_fcm', 'ios.device.production'):
    report = out / (profile + '.json')
    env = os.environ.copy()
    env.update(mknoon_checks.sims_environment(config, report, {'kind': 'sims', 'capability': 'build.' + profile}))
    env.update(ANDROID_APP_PACKAGE='com.mknoon.app', SIMS_APP_ID='com.mknoon.app',
               ORG_GRADLE_PROJECT_androidApplicationId='com.mknoon.app')
    command = ['dart', 'tool/sims/sims.dart', 'major', '--only', 'build.' + profile, '--prepare-builds', '--format', 'json']
    with (out / (profile + '.private.log')).open('w') as log:
        result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
    print(profile, 'preparation exit', result.returncode, flush=True)
    if result.returncode:
        sys.exit(result.returncode)
    with (out / (profile + '.verification.log')).open('w') as log:
        verified = subprocess.run(['dart', 'tool/sims/sims.dart', 'verify-report', str(report)],
                                  env=env, stdout=log, stderr=subprocess.STDOUT)
    print(profile, 'verification exit', verified.returncode, flush=True)
    if verified.returncode:
        sys.exit(verified.returncode)

selected = {}
for profile in ('android.production_fcm', 'ios.device.production'):
    report = out / (profile + '.json')
    digest = json.loads(report.read_text())['builds']['artifactDigests'][profile]
    matches = []
    for path in (root / 'build/sims/cache' / profile).glob('*/attestation.json'):
        item = json.loads(path.read_text())
        if item.get('artifactDigest') == digest:
            artifact = root / item['artifactPath']
            if artifact.exists():
                matches.append((path, item, artifact))
    assert len(matches) == 1, (profile, len(matches))
    path, item, artifact = matches[0]
    selected[profile] = {'artifact': str(artifact), 'report': str(report), 'attestation': str(path),
                         'inputDigest': item['inputDigest'], 'artifactDigest': digest}
(out / 'selected-artifacts.json').write_text(json.dumps(selected, indent=2) + '\n')

adapter = config['full_suite']['adapters'][CID]
adapter['prebuilt_android_apk'] = selected['android.production_fcm']['artifact']
adapter['prebuilt_android_build_report'] = selected['android.production_fcm']['report']
adapter['prebuilt_ios_bundle'] = selected['ios.device.production']['artifact']
adapter['prebuilt_ios_build_report'] = selected['ios.device.production']['report']
# Fresh setup app from current source, built exactly as the capture's own child build
# (_buildIosCandidate(e2eMode: true)) and hashed with its _sha256Directory rule.
import hashlib, shutil
env = os.environ.copy()
env.update(mknoon_checks.sims_environment(config, out / 'unused-setup-sims-report.json'))
relay = env.get('MKNOON_RELAY_ADDRESSES', '').strip()
assert relay, 'MKNOON_RELAY_ADDRESSES unresolved'
build = subprocess.run(['flutter', 'build', 'ios', '--profile', '--no-pub', '--dart-define=E2E_TEST_MODE=true',
                        '--dart-define=SIMS_BUILD_PROFILE_ID=ios.device.group_reaction_notification_397',
                        '--dart-define=MKNOON_RELAY_ADDRESSES=' + relay],
                       env=env, stdout=(out / 'setup-app.private.log').open('w'), stderr=subprocess.STDOUT)
print('setup app build exit', build.returncode, flush=True)
if build.returncode:
    sys.exit(build.returncode)
setup = out / 'setup' / 'Runner.app'
shutil.copytree(root / 'build/ios/iphoneos/Runner.app', setup, symlinks=True)
files = sorted((p for p in setup.rglob('*') if p.is_file() and not p.is_symlink()), key=lambda p: str(p))
h = hashlib.sha256()
for f in files:
    h.update(str(f.relative_to(setup)).encode() + b'\0'); h.update(f.read_bytes()); h.update(b'\0')
adapter['prebuilt_ios_setup_app'] = str(setup)
adapter['prebuilt_ios_setup_app_sha256'] = h.hexdigest()
print('setup app sha256', h.hexdigest(), flush=True)
target = run / 'device-config-chatgroup.json'
target.write_text(json.dumps(config, indent=2) + '\n')
os.chmod(target, 0o600)
print('selected artifacts and wrote', target.name, flush=True)
