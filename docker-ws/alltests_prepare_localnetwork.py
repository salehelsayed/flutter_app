"""Profile-mode copy of source047-prepare-localnetwork-config.py. A Debug Flutter app launched by XCUITest (not Flutter tooling) never starts Dart on iOS 14+, so the Local Network prompt can never appear. Usage: <output label>."""
import os,sys,json,fcntl,subprocess,base64,hashlib
from pathlib import Path
root=Path.cwd();sys.path.insert(0,str(root/'scripts'))
import mknoon_checks as checks,device_campaign_preflight as preflight
run=Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run');out=run/sys.argv[1];out.mkdir(mode=0o700)
config=json.loads((run/'device-config-localnetwork.staged.json').read_text())
fixture=json.loads(Path(config['full_suite']['ios_ui_fixtures']).read_text())['NotificationTapUITests/testAutomateLocalNetworkPermission']
assert fixture['target_id']==config['devices']['ios_physical']=='00008030-001A6D2801BB802E'
username=fixture['environment']['MKNOON_397_AUTO_SETUP_USERNAME']
env=dict(os.environ);env.update(checks.sims_environment(config,out/'unused-sims-report.json'))
relay=env.get('MKNOON_RELAY_ADDRESSES','').strip();assert relay
command=['flutter','build','ios','--config-only','--profile','--no-codesign','--target=lib/main.dart','--dart-define=E2E_TEST_MODE=true','--dart-define=AUTO_SETUP_USERNAME='+username,'--dart-define=MKNOON_RELAY_ADDRESSES='+relay]
with (root/'.codex-test-logs/checks.lock').open('a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 with preflight.device_leases(['mknoon.shared-native-build']):
  generated=root/'ios/Flutter/Generated.xcconfig'
  if generated.exists():(out/'Generated.before.private.xcconfig').write_bytes(generated.read_bytes())
  with (out/'command.private.log').open('w') as log:result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT)
  if result.returncode:sys.exit(result.returncode)
  raw=generated.read_text();line=next(x for x in raw.splitlines() if x.startswith('DART_DEFINES='));defines={}
  for part in line.split('=',1)[1].split(','):
   decoded=base64.b64decode(part).decode();key,value=decoded.split('=',1);defines[key]=value
  assert defines.get('E2E_TEST_MODE')=='true' and defines.get('AUTO_SETUP_USERNAME')==username
  assert not defines.get('SIMS_BUILD_PROFILE_ID')
  assert defines.get('MKNOON_RELAY_ADDRESSES')==relay
  (out/'Generated.prepared.private.xcconfig').write_bytes(generated.read_bytes())
  summary={'exit_code':0,'profile':'ordinary-profile-e2e','e2e_test_mode':True,'auto_setup_username':username,'sims_profile_absent':True,'relay_define_sha256':hashlib.sha256(relay.encode()).hexdigest(),'generated_sha256':hashlib.sha256(generated.read_bytes()).hexdigest(),'native_scenario_executed':False}
  (out/'result.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary),flush=True)
