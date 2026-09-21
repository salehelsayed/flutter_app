"""Real protected runner subprocess contracts; inventory/devices are fixtures.

These assert orchestration and leases, never product measurements. The original
blanket-block assertions are superseded by positive execution plus invalid-pin,
unknown-route, changed-owner, first-failure and exact-child refusal controls.
"""
import contextlib
import io
import json
import os
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
        for name in ['flutter','dart','adb','xcrun','bash']:(bin_dir/name).symlink_to(stub)
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
print('Host contract fixture subprocess executed; no product test or measurement')
'''



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
        run=subprocess.run([sys.executable,str(self.root/'scripts/mknoon_checks.py'),'full',
            '--base',self.base,'--local','--device-config',str(config),'--output',str(out)],
            cwd=self.root,env={**os.environ,'PATH':str(self.root/'bin')+':'+os.environ['PATH']},
            capture_output=True,text=True,timeout=30)
        self.assertTrue((out/'results.json').exists(),run.stdout+run.stderr)
        report=json.loads((out/'results.json').read_text())
        self.assertEqual(run.returncode,0,run.stdout+run.stderr+json.dumps(report['results']))
        row=report['results'][0]
        self.assertEqual(row['attempts'][0]['route_results'],[dict(id='dart version',status='PASS',checkpoint='protected_legacy_route_completed')])

if __name__=='__main__':unittest.main()
