"""Real protected runner subprocess contracts; inventory/devices are fixtures.

These assert orchestration and leases, never product measurements. The original
blanket-block assertions are superseded by positive execution plus invalid-pin,
unknown-route, changed-owner, first-failure and exact-child refusal controls.
"""
import contextlib
import base64
import hashlib
import io
import json
import os
import re
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import signal
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import legacy_target_contracts as legacy
import mknoon_checks as checks
import migration_sqlcipher_portability as portability

ROOT = Path(__file__).resolve().parents[2]
DART = Path(os.environ.get('MKNOON_REVIEW_DART') or shutil.which('dart') or '/unavailable/dart').resolve()
_BUNDLED_DART = DART.parent / 'cache/dart-sdk/bin/dart'
if _BUNDLED_DART.is_file():
    DART = _BUNDLED_DART
PINS = {'android-physical':'closure-usb', 'android-emulator':'closure-emu',
        **{'ios-simulator-'+s:'closure-sim-'+s for s in 'abcd'}}
MATRIX = dict(errors=[], adb=['closure-usb','closure-emu'],
    ios_simulators=['closure-sim-'+s for s in 'abcd'],
    flutter=[dict(id=v,targetPlatform='android-arm64' if k.startswith('android') else 'ios',
                  emulator=k!='android-physical') for k,v in PINS.items()])
IDLE = ('ACTIVITY MANAGER RUNNING PROCESSES (dumpsys activity processes)\n'
        '  mProcessesReady=true mSystemReady=true mBooted=true mFactoryTest=0\n'
        '  mForceBackgroundCheck=false\n')


class LegacyBindingTest(unittest.TestCase):
    def test_full_wifi_smoke_binds_the_required_cli_peer_without_retries(self):
        contract = legacy.contracts()['full']['integration_test wifi_relay_fallback_smoke_test.dart']
        with tempfile.TemporaryDirectory() as tmp:
            commands, _ = legacy.bind(contract, PINS,
                {'relay_addresses':'/fixture/isolated-relay'}, Path(tmp))
        self.assertEqual(commands, [['dart', 'run',
            'integration_test/scripts/run_wifi_relay_fallback_smoke.dart',
            '-d', PINS['android-physical'], '--platform', 'android', '--retry', '0']])
        self.assertIn('integration_test/wifi_relay_fallback_smoke_test.dart', contract['sources'])

    def test_notification_matrix_binding_disables_automatic_retries(self):
        contract = legacy.contracts()['reliability']['scripts/run_ios_notification_tap_ui_smoke.sh']
        with tempfile.TemporaryDirectory() as tmp:
            commands, _ = legacy.bind(contract, PINS,
                {'relay_addresses':'/fixture/isolated-relay'}, Path(tmp))
        self.assertEqual(commands[0][-2:], ['--retries', '0'])

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='legacy-contract-')
        self.addCleanup(self.tmp.cleanup)
        self.tmp = Path(self.tmp.name)
        self.env = {**os.environ, legacy.PIN:json.dumps(PINS), 'MKNOON_LEGACY_ISOLATED':'1',
                    'MKNOON_LEGACY_CONFIG_JSON':json.dumps({'relay_addresses':'/fixture/isolated-relay','ios_disposable_simulator_ids':','.join(PINS['ios-simulator-'+x] for x in 'abcd')})}

    def test_exact_current_selections_have_audited_contracts(self):
        rules = json.loads((ROOT/checks.RULES).read_text())
        full = next(c for c in rules['full_commands'] if c['id']=='full-legacy')
        manifest = json.loads((ROOT/checks.SIMS).read_text())
        reliability = next(c for c in manifest['capabilities'] if c['id']=='reliability.full.cleaned_legacy')
        for kind, args, expected in [('full',full['command'][2:],80), ('reliability',reliability['command'][1:],67)]:
            with self.subTest(kind=kind):
                labels = legacy.selected_routes(kind,args)
                self.assertEqual(len(labels),expected)
                self.assertEqual(set(labels),set(legacy.contracts()[kind]))
                for label in labels:
                    commands, _ = legacy.bind(legacy.contracts()[kind][label],PINS,
                        {'relay_addresses':'/fixture/isolated-relay','ios_disposable_simulator_ids':','.join(PINS['ios-simulator-'+x] for x in 'abcd')},self.tmp)
                    self.assertTrue(commands)

    def test_invalid_pins_unknown_routes_and_changed_owners_launch_nothing(self):
        leaf = 'integration_test posts_phase1_fake_test.dart'
        contract = legacy.contracts()['full'][leaf]
        for pins in [{}, {'android-physical':'booted'}, {'android-physical':'-s foreign'},
                     {'android-physical':'owned','surprise':'foreign'}]:
            with self.subTest(pins=pins), self.assertRaises(ValueError):
                legacy.bind(contract,pins,{'relay_addresses':'fixture'},self.tmp)
        changed = {**contract,'sources':{'scripts/mknoon_checks.py':'0'*64}}
        with self.assertRaises(ValueError):legacy.bind(changed,PINS,{'relay_addresses':'fixture'},self.tmp)
        launcher = mock.Mock(side_effect=AssertionError('unknown route launched'))
        with contextlib.redirect_stdout(io.StringIO()):
            result=legacy.execute('full',['unknown route'],self.tmp/'unknown',env=self.env,matrix=MATRIX,launch=launcher)
        self.assertEqual(result['status'],'BLOCKED');launcher.assert_not_called()

    def test_ios_gesture_and_rendering_proofs_keep_ios_targets_and_exact_ownership(self):
        for kind, label in [
            ('reliability', 'integration_test/conversation_swipe_back_proof_test.dart'),
            ('full', 'integration_test conversation_swipe_back_proof_test.dart'),
            ('full', 'integration_test group_conversation_polish_proof_test.dart'),
        ]:
            with self.subTest(kind=kind, label=label):
                contract = legacy.contracts()[kind][label]
                self.assertEqual(contract['roles'], ['ios-simulator-a'])
                commands, _ = legacy.bind(contract, PINS,
                    {'relay_addresses': '/fixture/isolated-relay'}, self.tmp)
                self.assertEqual(commands[0][commands[0].index('-d') + 1], PINS['ios-simulator-a'])
                self.assertEqual(contract['owns'], [commands[0][-1]])

    def test_pb266_reliability_reuses_existing_non_debug_profile_proof(self):
        catalog=legacy.contracts()
        filename='group_exit_release_diagnostics_sqlcipher_proof_test.dart'
        full=catalog['full']['integration_test '+filename]
        reliability=catalog['reliability']['integration_test/'+filename]
        commands, _=legacy.bind(reliability,PINS,
            {'relay_addresses':'/fixture/isolated-relay'},self.tmp)
        self.assertEqual(reliability['commands'],full['commands'])
        self.assertTrue('--profile' in commands[0] or '--release' in commands[0])
        self.assertEqual(commands[0][commands[0].index('-d')+1],PINS['android-physical'])

    def test_group_lifecycle_routes_pass_values_accepted_by_the_real_dispatcher(self):
        path = 'integration_test/group_lifecycle_simulator_harness.dart'
        accepted = set(re.findall(r"case '([^']+)':", (ROOT/path).read_text()))
        labels = [label for label in legacy.selected_routes('reliability', ['all'])
                  if label.startswith(path + ':')]
        observed = set()
        for label in labels:
            with self.subTest(label=label):
                commands, _ = legacy.bind(legacy.contracts()['reliability'][label], PINS,
                    {'relay_addresses': '/fixture/isolated-relay'}, self.tmp)
                values = [arg.removeprefix('--dart-define=GROUP_SIM_SCENARIO=')
                          for arg in commands[0]
                          if arg.startswith('--dart-define=GROUP_SIM_SCENARIO=')]
                self.assertEqual(len(values), 1)
                self.assertIn(values[0], accepted)
                self.assertEqual(label, path + ':GROUP_SIM_SCENARIO=' + values[0])
                observed.add(values[0])
        self.assertEqual(observed, accepted)

    def test_host_route_executes_when_separate_device_leg_is_unavailable(self):
        def launch(argv,cwd,timeout,env):
            self.assertEqual(argv,['dart','--version'])
            return checks.launch([sys.executable,'-c','print("host subprocess executed")'],cwd,timeout,env)
        env={**self.env,legacy.PIN:'{}'}
        matrix=dict(errors=[],flutter=[],adb=[],ios_simulators=[])
        with contextlib.redirect_stdout(io.StringIO()):
            result=legacy.execute('full',['dart version','integration_test posts_phase1_fake_test.dart'],
                self.tmp/'host',env=env,matrix=matrix,launch=launch)
        self.assertEqual([r['status'] for r in result['route_results']],['PASS','N/A'])
        self.assertIn('host subprocess executed',(self.tmp/'host/logs/001.log').read_text())

    def test_missing_fixture_is_blocked_and_empty_hardware_never_counts_as_execution(self):
        label='integration_test posts_phase1_fake_test.dart'
        matrix=dict(errors=[],flutter=[],adb=[],ios_simulators=[])
        for suffix,config,status in [('fixture',{},'BLOCKED'),('hardware',{'relay_addresses':'fixture'},'N/A')]:
            env={**self.env,legacy.PIN:'{}','MKNOON_LEGACY_CONFIG_JSON':json.dumps(config)}
            launcher=mock.Mock(side_effect=AssertionError('unavailable route launched'))
            with contextlib.redirect_stdout(io.StringIO()):
                result=legacy.execute('full',[label],self.tmp/suffix,env=env,matrix=matrix,launch=launcher)
            self.assertEqual(result['status'],status);launcher.assert_not_called()
        malformed={**matrix,'flutter':[{'id':'unclassified-device'}]}
        self.assertEqual(legacy.availability(['android-physical'],{},malformed),'BLOCKED')

    def test_new_receipt_join_rejects_missing_duplicate_wrong_and_modified_logs(self):
        labels=['dart version'];out=self.tmp/'receipt'
        with contextlib.redirect_stdout(io.StringIO()):
            legacy.execute('full',labels,out,env=self.env,matrix=MATRIX,
                launch=lambda *args:('real host fixture completed',0,False,0))
        expected=[dict(label=label) for label in labels]
        self.assertEqual(checks.inspect_legacy(out,0,False,expected)['status'],'PASS')
        original=json.loads((out/'routes.json').read_text())
        for rows in [[],original*2,[dict(original[0],id='wrong')],
                     [dict(original[0],checkpoint='private arbitrary producer text')]]:
            (out/'routes.json').write_text(json.dumps(rows))
            self.assertEqual(checks.inspect_legacy(out,0,False,expected)['status'],'BLOCKED')
            self.assertEqual(checks.legacy_receipt_details(out,{},expected),[])
        (out/'routes.json').write_text(json.dumps(original))
        (out/'logs/001.log').write_text('changed after receipt')
        self.assertEqual(checks.inspect_legacy(out,0,False,expected)['status'],'BLOCKED')

    def test_zero_exit_skips_hold_later_devices_and_remain_blocked_in_receipts(self):
        labels = ['integration_test posts_phase1_fake_test.dart',
                  'integration_test conversation_swipe_back_proof_test.dart', 'dart version']
        for index, output in enumerate(['00:01 +2 ~1: All tests passed!\n',
                                        'Ran 4 tests\nOK (skipped=1)\n',
                                        'No tests ran.\n']):
            out = self.tmp / f'skipped-{index}'
            launched = []
            def launch(argv, cwd, timeout, env):
                if 'dumpsys' in argv: return IDLE, 0, False, 0
                launched.append(argv)
                return (output if argv[0] == 'flutter' else 'host completed'), 0, False, 0
            with contextlib.redirect_stdout(io.StringIO()):
                result = legacy.execute('full', labels, out, env=self.env, matrix=MATRIX, launch=launch)
            self.assertEqual([r['status'] for r in result['route_results']], ['BLOCKED','NOT RUN','PASS'])
            self.assertTrue(result['cleanup_review_required'])
            self.assertEqual(len(launched), 2)
            # Older receipts must not hide the skipped child when another route
            # already failed and the aggregate returns early for that failure.
            rows = json.loads((out/'routes.json').read_text())
            rows[0].update(status='PASS', checkpoint='protected_legacy_route_completed')
            rows[1].update(status='FAIL', checkpoint='legacy_child_failed')
            (out/'routes.json').write_text(json.dumps(rows))
            (out/'summary.tsv').write_text(''.join(f"{r['status']}\t{r['id']}\n" for r in rows))
            expected = [dict(label=x) for x in labels]
            self.assertEqual(checks.inspect_legacy(out,1,False,expected)['status'], 'FAIL')
            self.assertEqual(checks.legacy_receipt_details(out,{},expected)[0]['status'], 'BLOCKED')

    def test_cancellation_stops_owned_descendant_before_releasing_the_run(self):
        tools=self.tmp/'cancel-bin';tools.mkdir()
        child=tools/'dart'
        child.write_text('#!'+sys.executable+"\nimport os,signal,time\nfrom pathlib import Path\nsignal.signal(signal.SIGTERM,signal.SIG_IGN)\nPath(os.environ['CLOSURE_HEARTBEAT']+'.pid').write_text(str(os.getpid()))\nwhile True:\n Path(os.environ['CLOSURE_HEARTBEAT']).write_text(str(time.monotonic_ns()))\n time.sleep(.02)\n")
        child.chmod(0o755)
        heartbeat=self.tmp/'heartbeat'
        code="import sys; from pathlib import Path; sys.path.insert(0,sys.argv[1]); import legacy_target_contracts as l; l.install_cancellation(); l.execute('full',['dart version','flutter version'],Path(sys.argv[2]))"
        parent=subprocess.Popen([sys.executable,'-c',code,str(ROOT/'scripts'),str(self.tmp/'cancel-out')],
            cwd=ROOT,env={**self.env,'PATH':str(tools)+':'+os.environ['PATH'],'CLOSURE_HEARTBEAT':str(heartbeat)},
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        try:
            deadline=time.monotonic()+5
            while not heartbeat.exists() and time.monotonic()<deadline:time.sleep(.02)
            self.assertTrue(heartbeat.exists())
            parent.terminate();output,_=parent.communicate(timeout=5)
            before=heartbeat.read_text();time.sleep(.12)
            self.assertEqual(heartbeat.read_text(),before,output)
            rows=json.loads((self.tmp/'cancel-out/routes.json').read_text())
            self.assertEqual(rows[-1]['checkpoint'],'run_cancelled')
            self.assertNotEqual(rows[0]['status'],'PASS')
        finally:
            if parent.poll() is None:parent.kill();parent.wait()
            if heartbeat.with_suffix('.pid').exists():
                try:os.killpg(int(heartbeat.with_suffix('.pid').read_text()),signal.SIGKILL)
                except ProcessLookupError:pass

    def test_real_protected_full_and_reliability_cli_launch_every_configured_route(self):
        # Only executables at the SDK/native boundary are synthetic. The actual
        # shell selectors, dispatcher, lease implementation and receipts run.
        bin_dir=self.tmp/'bin';bin_dir.mkdir()
        stub=bin_dir/'stub'
        stub.write_text('#!'+sys.executable+'\n'+TOOL_FIXTURE.replace('@ROOT@',str(ROOT)).replace('@DART@',repr(str(DART))))
        stub.chmod(0o755)
        for name in ['flutter','dart','adb','xcrun','bash','python3']:(bin_dir/name).symlink_to(stub)
        env={**self.env,'PATH':str(bin_dir)+':'+os.environ['PATH'],
             'CLOSURE_FIXTURE_LOG':str(self.tmp/'commands.jsonl'),
             'MKNOON_LEGACY_INHERITED_LEASES_JSON':json.dumps(list(PINS.values()))}
        rules=json.loads((ROOT/checks.RULES).read_text())
        full=next(c for c in rules['full_commands'] if c['id']=='full-legacy')
        manifest=json.loads((ROOT/checks.SIMS).read_text())
        rel=next(c for c in manifest['capabilities'] if c['id']=='reliability.full.cleaned_legacy')
        for kind, argv, count in [('full',full['command'],80),('reliability',rel['command'],67)]:
            out=self.tmp/kind
            # Dispatcher selection requires the real shell, while leaf shell
            # commands are intentionally fixtures. Fixture bash recognizes only listings.
            command=(['/bin/bash',*argv[1:],'--output',str(out)] if kind=='full' else
                     ['/bin/bash',*argv])
            run=subprocess.run(command,cwd=ROOT,env={**env,'MKNOON_LEGACY_RECEIPT_DIRECTORY':str(out)},
                capture_output=True,text=True,timeout=90)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            receipts=json.loads((out/'routes.json').read_text())
            self.assertEqual(len(receipts),count)
            self.assertTrue(all(r['status']=='PASS' for r in receipts),receipts)
            self.assertEqual(len({r['id'] for r in receipts}),count)
        commands=[json.loads(s) for s in (self.tmp/'commands.jsonl').read_text().splitlines()]
        self.assertGreater(len(commands),147)
        self.assertTrue(any('--sender' in c['args'] for c in commands))
        self.assertTrue(any('--device-id' in c['args'] for c in commands))


TOOL_FIXTURE = r'''
import json,os,sys,subprocess
sys.path.insert(0,'@ROOT@/scripts')
import device_campaign_preflight as p
name=os.path.basename(sys.argv[0]);args=sys.argv[1:]
if name=='python3' and (not args or args[0]!='scripts/migration_sqlcipher_portability.py'):
    os.execv(sys.executable,[sys.executable,*args])
if name=='bash' and ('--dry-run' in args or '--selection-only' in args or any(a.startswith('--list') for a in args) or '--records-tsv' in args or any('check_reliability_simulation_discovery' in a for a in args)):
    os.execv('/bin/bash',['/bin/bash',*args])
if name=='dart' and ('--list-scenarios' in args or '--list' in args):
    os.execv(@DART@,['dart',*args])
pins=json.loads(os.environ.get('SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON','{}'))
if name=='flutter' and args==['devices','--machine']:
    print(json.dumps([dict(id=v,targetPlatform='android-arm64' if k.startswith('android') else 'ios',emulator=k!='android-physical') for k,v in pins.items()]));sys.exit()
if name=='adb' and args==['devices']:
    print('List of devices attached\n'+'\n'.join(v+'\tdevice' for k,v in pins.items() if k.startswith('android')));sys.exit()
if name=='xcrun' and args[:3]==['simctl','list','devices']:
    print(json.dumps({'devices':{'iOS-fixture':[dict(udid=v,name='iPhone fixture',isAvailable=True) for k,v in pins.items() if k.startswith('ios')]}}));sys.exit()
for target in pins.values():
    try:
        with p.device_leases([target]):pass
    except p.DeviceLeaseBusy:pass
    else:raise AssertionError('target was forwarded before acquiring its lease: '+target)
if name=='adb' and 'dumpsys' in args:
    print('ACTIVITY MANAGER RUNNING PROCESSES (dumpsys activity processes)\n  mProcessesReady=true mSystemReady=true mBooted=true mFactoryTest=0\n  mForceBackgroundCheck=false');sys.exit()
with open(os.environ['CLOSURE_FIXTURE_LOG'],'a') as f:f.write(json.dumps(dict(name=name,args=args,pins=pins))+'\n')
if name=='dart' and 'tool/sims/sims.dart' in args and '--only' in args:
    print('PASS\t'+args[args.index('--only')+1]+'\thost orchestration fixture')
if name=='dart' and 'integration_test/scripts/run_benchmark_suite.dart' in args:
    print('FULL_BENCHMARK_SELECTION '+args[args.index('-d')+1]+' '+args[args.index('--scenarios')+1])
if name=='python3' and 'scripts/migration_sqlcipher_portability.py' in args:
    print('SQLCIPHER_PORTABILITY_COMPLETED android_to_ios')
print('Host contract fixture subprocess executed; no product test or measurement')
'''



class PortabilityTransferTest(unittest.TestCase):
    def test_existing_native_tests_receive_exact_transferred_bytes_and_skip_or_corruption_blocks(self):
        for mode in ['pass', 'skip', 'corrupt', 'verify-failure']:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temporary:
                output = Path(temporary)/'proof'
                calls = []
                snapshot = b'exact encrypted fixture bytes'
                meta = dict(platform='android', checksum_sha256=hashlib.sha256(snapshot).hexdigest())
                def launch(argv, root, timeout, env):
                    calls.append(argv)
                    if argv[0] == 'adb':
                        self.assertEqual(argv[1:3], ['-s', PINS['android-physical']])
                        if 'base64' in argv:
                            data = json.dumps(meta).encode() if argv[-1].endswith('portability.json') else (b'corrupt' if mode == 'corrupt' else snapshot)
                            return base64.b64encode(data).decode(), 0, False, .1
                        return '', 0, False, .1
                    target = argv[argv.index('-d')+1]
                    define = next(a.split('=', 2)[2] for a in argv if a.startswith('--dart-define='))
                    if target == PINS['android-physical']:
                        self.assertIn('--no-uninstall', argv)
                        marker = 'PORTABILITY_EXPORT_WRITTEN dir='+define
                    else:
                        self.assertNotIn('--no-uninstall', argv)
                        self.assertEqual(target, PINS['ios-simulator-a'])
                        self.assertEqual((Path(define)/'snapshot.db').read_bytes(), snapshot)
                        self.assertEqual(json.loads((Path(define)/'portability.json').read_text()), meta)
                        marker = 'PORTABILITY_VERIFY_OK source=android target=ios'
                    failed = mode == 'verify-failure' and target == PINS['ios-simulator-a']
                    events = [dict(type='suite', suite=dict(id=0, path=portability.TEST))]
                    for index in range(3):
                        events += [dict(type='testStart', test=dict(id=index, suiteID=0, name='native case '+str(index))),
                                   dict(type='testDone', testID=index, result='error' if failed else 'success', skipped=mode=='skip' and index==1)]
                    events += [dict(type='print', message=marker), dict(type='done', success=not failed)]
                    return '\n'.join(json.dumps(x) for x in events), int(failed), False, .1
                env = {legacy.PIN: json.dumps(PINS)}
                with contextlib.redirect_stdout(io.StringIO()):
                    if mode == 'pass':
                        receipts = portability.run(PINS['android-physical'], PINS['ios-simulator-a'], output, env=env, launch=launch)
                        self.assertEqual(receipts[-1]['test_result']['counts'], dict(passed=3,failed=0,skipped=0))
                    else:
                        with self.assertRaises(RuntimeError):
                            portability.run(PINS['android-physical'], PINS['ios-simulator-a'], output, env=env, launch=launch)
                native = [c for c in calls if c[0]=='flutter']
                self.assertEqual(len(native), 1 if mode in ('skip','corrupt') else 2)
                self.assertTrue(any('rmdir' in c for c in calls))

    def test_missing_or_mismatched_pin_cannot_launch(self):
        launch = mock.Mock()
        with self.assertRaises(ValueError):
            portability.run('unknown', PINS['ios-simulator-a'], '/unused', env={legacy.PIN:json.dumps(PINS)}, launch=launch)
        launch.assert_not_called()


FOREGROUND_PREPARATION_FIXTURE = r'''
import json,os,sys,time
from pathlib import Path
args=sys.argv[1:]
defines=dict(a.removeprefix('--dart-define=').split('=',1) for a in args if a.startswith('--dart-define='))
role=defines['SMOKE_ROLE']; phase=args[0]
capture=Path(os.environ['PREPARATION_CAPTURE'])
with capture.open('a') as f:f.write(json.dumps(dict(phase=phase,role=role,args=args))+'\n')
if phase=='build':
 assert args[:2]==['build','ios'] and '--simulator' in args and '--debug' in args
 if os.environ['PREPARATION_MODE']=='fail-bob' and role=='bob':sys.exit(3)
 app=Path('build/ios/iphonesimulator/Runner.app');app.mkdir(parents=True,exist_ok=True)
 (app/'role.json').write_text(json.dumps(defines))
 sys.exit(0)
if phase=='drive':
 calls=[json.loads(x) for x in capture.read_text().splitlines()]
 assert [x['role'] for x in calls if x['phase']=='build']==['alice','bob']
 artifact=Path(next(x.split('=',1)[1] for x in args if x.startswith('--use-application-binary=')))
 assert json.loads((artifact/'role.json').read_text())==defines, 'wrong or overwritten role artifact'
else:
 assert phase=='test' and not any(x.startswith('--use-application-binary') for x in args)
directory=Path(defines['E2E_SHARED_DIR']);prefix='fgpush_'+defines['SMOKE_RUN_ID']+'_'
def signal(name):return directory/(prefix+name)
def wait(name):
 deadline=time.monotonic()+10
 while not signal(name).exists():
  if time.monotonic()>deadline:raise AssertionError('missing host fixture signal '+name)
  time.sleep(.01)
if role=='alice':signal('alice_ready').write_text('ok')
else:
 signal('bob_group_joined').write_text('ok')
 for case in ['s1','s2','s3']:
  wait(case+'_go');signal(case+'_bob_verdict').write_text(json.dumps(dict(programmaticPass=True)))
wait('all_done');signal(role+'_done').write_text('ok')
'''


class ForegroundGroupPreparationTest(unittest.TestCase):
    def run_fixture(self, mode):
        with tempfile.TemporaryDirectory(prefix='foreground-build-order-') as temporary:
            root=Path(temporary);(root/'bin').mkdir();(root/'tmp').mkdir()
            flutter=root/'bin/flutter';flutter.write_text('#!'+sys.executable+'\n'+FOREGROUND_PREPARATION_FIXTURE);flutter.chmod(0o755)
            capture=root/'commands.jsonl'
            devices=('fixture-usb,fixture-emulator' if mode=='android' else
                     '00000000-0000-0000-0000-000000000001,00000000-0000-0000-0000-000000000002')
            run=subprocess.run([str(DART),str(ROOT/'integration_test/scripts/run_foreground_group_push_simulator_smoke.dart'),'-d',devices],
                cwd=root,env={**os.environ,'PATH':str(root/'bin')+':'+os.environ['PATH'],
                              'TMPDIR':str(root/'tmp'),'PREPARATION_CAPTURE':str(capture),
                              'PREPARATION_MODE':mode,'MKNOON_RELAY_ADDRESSES':'fixture-relay'},
                capture_output=True,text=True,timeout=25)
            calls=[json.loads(x) for x in capture.read_text().splitlines()]
            return run,calls

    def test_ios_prepares_both_exact_role_binaries_before_any_peer_starts(self):
        run,calls=self.run_fixture('pass')
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertEqual([(x['phase'],x['role']) for x in calls],
                         [('build','alice'),('build','bob'),('drive','alice'),('drive','bob')])
        self.assertIn('Foreground group push simulator smoke PASSED',run.stderr)
        for row in calls:self.assertIn('--dart-define=MKNOON_RELAY_ADDRESSES=fixture-relay',row['args'])

    def test_failed_second_build_starts_neither_peer(self):
        run,calls=self.run_fixture('fail-bob')
        self.assertNotEqual(run.returncode,0)
        self.assertEqual([(x['phase'],x['role']) for x in calls],[('build','alice'),('build','bob')])

    def test_android_keeps_existing_direct_test_launches(self):
        run,calls=self.run_fixture('android')
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertEqual([(x['phase'],x['role']) for x in calls],[('test','alice'),('test','bob')])


class BenchmarkSuiteHandshakeTest(unittest.TestCase):
    def test_real_suite_stage_channel_and_independent_peer_failures(self):
        suite = Path(os.environ.get('MKNOON_CLOSURE_BENCHMARK_SUITE',
            ROOT/'integration_test/scripts/run_benchmark_suite.dart'))
        for mode in ['pass', 'android', 'unacknowledged', 'missing-stage', 'independent-failure']:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix='routing-suite-') as tmp:
                tmp=Path(tmp);(tmp/'bin').mkdir();(tmp/'go-mknoon/bin').mkdir(parents=True)
                for path,source in [(tmp/'bin/flutter',FLUTTER_BENCHMARK_FIXTURE),
                                    (tmp/'go-mknoon/bin/testpeer',PEER_FIXTURE), (tmp/'bin/adb',ADB_ROUTING_FIXTURE)]:
                    path.write_text('#!'+sys.executable+'\n'+source);path.chmod(0o755)
                env={**os.environ,'PATH':str(tmp/'bin')+':'+os.environ['PATH'],
                     'CLOSURE_MODE':mode,'CLOSURE_COMMANDS':str(tmp/'commands.jsonl')}
                run=subprocess.run([str(DART),str(suite),
                    '-d','fixture-sim','--scenarios','A,R','--fixture-dir',str(tmp/'fixtures')],
                    cwd=tmp,env=env,capture_output=True,text=True,timeout=20)
                calls=[json.loads(s) for s in (tmp/'commands.jsonl').read_text().splitlines()] if (tmp/'commands.jsonl').exists() else []
                self.assertEqual(run.returncode,0 if mode in ('pass','android') else 1,run.stdout+run.stderr)
                self.assertEqual('FULL_BENCHMARK_COMPLETED peer-suite' in run.stdout,mode in ('pass','android'))
                self.assertIn('app:R-Sim-3:request',calls)
                self.assertLess(calls.index('app:R-Sim-3:request'),calls.index('unregister'))
                if mode=='unacknowledged':self.assertNotIn('app:R-Sim-3:consumed',calls)
                else:
                    self.assertIn('app:R-Sim-7-restart:consumed',calls)
                    self.assertLess(calls.index('unregister'),calls.index('app:R-Sim-3:consumed'))
                if mode=='android':
                    self.assertTrue(any(isinstance(c,list) and c[:3]==['-s','fixture-sim','reverse'] and '--remove' in c for c in calls))
                self.assertIn('scenario:ONE_TO_ONE_SEND',calls)
                self.assertIn('scenario:ROUTING_PATHS',calls)


ADB_ROUTING_FIXTURE = r'''
import json,os,sys
args=sys.argv[1:]
assert args[:3]==['-s','fixture-sim','reverse']
with open(os.environ['CLOSURE_COMMANDS'],'a') as f:f.write(json.dumps(args)+'\n')
if '--remove' not in args:print(args[-1].split(':')[1])
'''

PEER_FIXTURE = r'''
import json,os,sys
for line in sys.stdin:
    cmd=json.loads(line)['cmd']
    with open(os.environ['CLOSURE_COMMANDS'],'a') as f:f.write(json.dumps(cmd)+'\n')
    response={'ok':True,'namespace':'fixture','peerId':'fixture-peer-identity-00000000000000','publicKey':'fixture-key'}
    if cmd=='unregister' and os.environ['CLOSURE_MODE']=='unacknowledged':response={'ok':False}
    print(json.dumps(response),flush=True)
'''

FLUTTER_BENCHMARK_FIXTURE = r'''
import base64,json,os,sys,urllib.request
args=sys.argv[1:]
if args==['devices','--machine']:
    print(json.dumps([dict(id='fixture-sim',targetPlatform='android-arm64' if os.environ['CLOSURE_MODE']=='android' else 'ios',emulator=True)]));sys.exit()
def log(s):
    with open(os.environ['CLOSURE_COMMANDS'],'a') as f:f.write(json.dumps(s)+'\n')
def event(**data):print(json.dumps(data),flush=True)
defines=dict(a.removeprefix('--dart-define=').split('=',1) for a in args if a.startswith('--dart-define='))
key=defines['BENCHMARK'];log('scenario:'+key)
event(type='testStart',test=dict(id=1,name='benchmark '+key))
if key=='ROUTING_PATHS':
    for stage in ['R-Sim-3','R-Sim-3-restore','R-Sim-7-stop','R-Sim-7-restart']:
        binding=dict(run=defines['ROUTING_STAGE_RUN'],target=defines['ROUTING_STAGE_TARGET'],stage=stage,nonce=base64.urlsafe_b64encode(os.urandom(32)).decode())
        log('app:'+stage+':request')
        for action in ['request','consumed']:
            req=urllib.request.Request(defines['ROUTING_STAGE_URL']+'/'+action,data=json.dumps(binding).encode(),headers={'Authorization':'Bearer '+defines['ROUTING_STAGE_SECRET']})
            try:
                with urllib.request.urlopen(req,timeout=5) as response:ack=json.load(response)
                assert ack==dict(binding,ok=True)
            except Exception:sys.exit(1)
        log('app:'+stage+':consumed')
        event(type='print',testID=1,message='ROUTING_STAGE_CONSUMED '+binding['run']+' '+binding['target']+' '+stage+' '+binding['nonce'])
    for i in range(1,8 if os.environ['CLOSURE_MODE']=='missing-stage' else 9):
        event(type='print',testID=1,message='BENCHMARK_STAGE_COMPLETED R-Sim-'+str(i))
failed=os.environ['CLOSURE_MODE']=='independent-failure' and key=='ONE_TO_ONE_SEND'
event(type='testDone',testID=1,result='failure' if failed else 'success',skipped=False)
event(type='done',success=not failed)
sys.exit(1 if failed else 0)
'''



# A full CLI invocation in a disposable repository. The source wrapper, shell
# selector and dispatcher are real; the one selected SDK boundary is a process
# fixture. This formerly stopped at unprotected_legacy_nested_targets.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from mknoon_checks_test import RepositoryFixture

class FullLegacyCLITest(RepositoryFixture):
    def test_full_cli_executes_configured_protected_legacy_host_route(self):
        import shutil
        source = Path(os.environ.get('MKNOON_CLOSURE_CHECKS_SOURCE', ROOT/'scripts/mknoon_checks.py'))
        rules_source = Path(os.environ.get('MKNOON_CLOSURE_RULES_SOURCE', ROOT/checks.RULES))
        task = next(c for c in json.loads(rules_source.read_text())['full_commands'] if c['id']=='full-legacy')
        labels = legacy.selected_routes('full', [])
        task.update(command=['bash','scripts/run_flutter_full_regression.sh',
                    *[a for label in labels if label!='dart version' for a in ['--exclude-label',label]]],
                    requirements=[],device_roles=[],dependencies=[],
                    expanded_routes=[dict(label='dart version')])
        self.rules['full_commands']=[task]
        self.rules['full_inventory']={}
        for path in ['scripts/device_campaign_preflight.py','scripts/legacy_target_contracts.py',
                     'scripts/run_flutter_full_regression.sh','scripts/testing_inventory.py',
                     'tool/testing/legacy_target_contracts.json']:
            target=self.root/path;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/path,target)
        shutil.copy2(source,self.root/'scripts/mknoon_checks.py')
        self.write(str(checks.RULES),json.dumps(self.rules))
        config=self.write('fixture.json',json.dumps(dict(isolated_test_environment=True,fixture_reference='owned-host-fixture',devices={})))
        dart=self.write('bin/dart','#!'+sys.executable+'\nprint("Dart SDK host fixture executed")\n');dart.chmod(0o755)
        for name, response in [('flutter','[]'),('adb','List of devices attached'),('xcrun','{"devices":{}}')]:
            stub=self.write('bin/'+name,'#!'+sys.executable+'\nimport sys\nprint(\"{}\" if \"--version\" in sys.argv else '+repr(response)+')\n');stub.chmod(0o755)
        out=self.root/'.codex-test-logs/full-cli'
        # The fixture executes the actual CLI, but owns no native build or
        # device. Use the real lease implementation in a fixture-private
        # directory so host contracts can coexist with live campaigns.
        lease_directory=self.root/'.codex-test-logs/fixture-leases'
        bootstrap=self.write('invoke_checks_fixture.py',
            'import functools,runpy,sys\n'
            f'sys.path.insert(0,{str(self.root/"scripts")!r})\n'
            'import device_campaign_preflight as preflight\n'
            f'preflight.device_leases=functools.partial(preflight.device_leases,directory={str(lease_directory)!r})\n'
            f'runpy.run_path({str(self.root/"scripts/mknoon_checks.py")!r},run_name="__main__")\n')
        run=subprocess.run([sys.executable,str(bootstrap),'full',
            '--base',self.base,'--local','--device-config',str(config),'--output',str(out)],
            cwd=self.root,env={**os.environ,'PATH':str(self.root/'bin')+':'+os.environ['PATH']},
            capture_output=True,text=True,timeout=30)
        self.assertTrue((out/'results.json').exists(),run.stdout+run.stderr)
        report=json.loads((out/'results.json').read_text())
        self.assertEqual(run.returncode,0,run.stdout+run.stderr+json.dumps(report['results']))
        lease_name=hashlib.sha256(b'mknoon.shared-native-build').hexdigest()+'.lock'
        self.assertTrue((lease_directory/lease_name).is_file(), 'synthetic CLI must use its own real lease directory')
        row=report['results'][0]
        self.assertEqual(row['attempts'][0]['route_results'],[dict(id='dart version',status='PASS',checkpoint='protected_legacy_route_completed')])



GROUP_MULTI_PREPARATION_FIXTURE = r'''
import json,os,sys,time
from pathlib import Path
args=sys.argv[1:]
defines=dict(a.removeprefix('--dart-define=').split('=',1) for a in args if a.startswith('--dart-define='))
role=defines['MD004_ROLE'];phase=args[0]
capture=Path(os.environ['PREPARATION_CAPTURE'])
with capture.open('a') as f:f.write(json.dumps(dict(phase=phase,role=role,args=args))+'\n')
if phase=='build':
 assert args[:2]==['build','ios'] and '--simulator' in args and '--debug' in args
 if os.environ['PREPARATION_MODE']=='fail-'+role:sys.exit(3)
 peer_capture=Path(os.environ['CLOSURE_COMMANDS'])
 assert not peer_capture.exists() or not peer_capture.read_text(), 'timed peer started during preparation'
 app=Path('build/ios/iphonesimulator/Runner.app');app.mkdir(parents=True,exist_ok=True)
 (app/'role.json').write_text(json.dumps(defines));sys.exit(0)
if phase=='drive':
 calls=[json.loads(x) for x in capture.read_text().splitlines()]
 assert [x['role'] for x in calls if x['phase']=='build']==['primary','sibling']
 artifact=Path(next(x.split('=',1)[1] for x in args if x.startswith('--use-application-binary=')))
 assert json.loads((artifact/'role.json').read_text())==defines,'wrong or overwritten role artifact'
else:
 assert phase=='test' and not any(x.startswith('--use-application-binary') for x in args)
assert Path(defines['CLI_PEER_FIXTURE']).is_file()
directory=Path(defines['E2E_SHARED_DIR']);prefix='md004_'+defines['MD004_RUN_ID']+'_'
def signal(name):return directory/(prefix+name)
if role=='primary':
 signal('cli_group_join_fixture.json').write_text(json.dumps({'groupId':'fixture-group','keyEpoch':1,'groupKey':'fixture-key','groupConfig':{'members':[{'peerId':'fixture-peer-identity-00000000000000'},{'peerId':'fixture-primary'},{'peerId':'fixture-sibling'}]}}))
 signal('cli_publish_ready').write_text('ok')
 deadline=time.monotonic()+10
 while not signal('cli_message_published').exists():
  if time.monotonic()>deadline:raise AssertionError('missing CLI publication')
  time.sleep(.01)
else:signal('sibling_complete').write_text('ok')
'''


class GroupMultiDevicePreparationTest(unittest.TestCase):
    def run_fixture(self, mode):
        with tempfile.TemporaryDirectory(prefix='group-multi-build-order-') as temporary:
            root=Path(temporary)
            for rel in ['bin','tmp','go-mknoon/bin']:(root/rel).mkdir(parents=True)
            for rel,source in [('bin/flutter',GROUP_MULTI_PREPARATION_FIXTURE),('go-mknoon/bin/testpeer',PEER_FIXTURE)]:
                script=root/rel;script.write_text('#!'+sys.executable+'\n'+source);script.chmod(0o755)
            make=root/'bin/make';make.write_text('#!/bin/sh\nexit 0\n');make.chmod(0o755)
            capture=root/'commands.jsonl';peer_capture=root/'peer-commands.jsonl'
            devices=('fixture-usb,fixture-emulator' if mode=='android' else
                     '00000000-0000-0000-0000-000000000001,00000000-0000-0000-0000-000000000002')
            run=subprocess.run([str(DART),str(ROOT/'integration_test/scripts/run_group_multi_device_real.dart'),'-d',devices],
                cwd=root,env={**os.environ,'PATH':str(root/'bin')+':'+os.environ['PATH'],
                              'TMPDIR':str(root/'tmp'),'PREPARATION_CAPTURE':str(capture),
                              'PREPARATION_MODE':mode,'MKNOON_RELAY_ADDRESSES':'fixture-relay',
                              'CLOSURE_COMMANDS':str(peer_capture),'CLOSURE_MODE':'pass'},
                capture_output=True,text=True,timeout=25)
            calls=[json.loads(x) for x in capture.read_text().splitlines()] if capture.exists() else []
            peer_calls=[json.loads(x) for x in peer_capture.read_text().splitlines()] if peer_capture.exists() else []
            return run,calls,peer_calls

    def test_ios_prepares_exact_roles_before_launch_and_cli_fixture_deadline(self):
        run,calls,peer_calls=self.run_fixture('pass')
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertEqual([(x['phase'],x['role']) for x in calls],
                         [('build','primary'),('build','sibling'),('drive','primary'),('drive','sibling')])
        self.assertIn('MD-004 proof completed successfully',run.stderr)
        self.assertIn('group_inbox_store',peer_calls)
        for row in calls:self.assertIn('--dart-define=MKNOON_RELAY_ADDRESSES=fixture-relay',row['args'])

    def test_either_build_failure_starts_no_app_or_protocol_peer(self):
        for role in ['primary','sibling']:
            with self.subTest(role=role):
                run,calls,peer_calls=self.run_fixture('fail-'+role)
                self.assertNotEqual(run.returncode,0)
                self.assertTrue(calls)
                self.assertTrue(all(x['phase']=='build' for x in calls))
                self.assertEqual(peer_calls,[])

    def test_android_keeps_existing_direct_test_launches(self):
        run,calls,peer_calls=self.run_fixture('android')
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertEqual([(x['phase'],x['role']) for x in calls],[('test','primary'),('test','sibling')])
        self.assertIn('group_inbox_store',peer_calls)


if __name__=='__main__':unittest.main()
