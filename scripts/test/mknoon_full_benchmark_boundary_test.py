"""Causal GP/H boundary contracts: real Dart owners, synthetic process leaves.

These are orchestration/host-file protocol assertions, never product results.
The leaf compiles the actual harness file helpers with the captured defines;
no device, native build, credential, provider or relay is used.
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
import threading
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import legacy_target_contracts as legacy
import device_campaign_preflight as preflight

ROOT = Path(__file__).resolve().parents[2]
DART = Path(os.environ.get('MKNOON_REVIEW_DART') or shutil.which('dart') or '/unavailable/dart').resolve()
_BUNDLED_DART = DART.parent / 'cache/dart-sdk/bin/dart'
if _BUNDLED_DART.is_file():
    DART = _BUNDLED_DART
RELAY = '/dns/isolated.invalid/tcp/4001/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
RELAYS = RELAY + ',' + RELAY.replace('/tcp/4001/', '/udp/4002/quic-v1/')
ANDROID = 'A,B,BR,C,D,E,F,G,I,J,K,L,M,N,R'
PINS = {'android-physical': 'boundary-usb', 'ios-simulator-a': 'boundary-sim'}
SCRIPTS = ['run_group_publish_benchmark.dart', 'run_timeout_accuracy_benchmark.dart']


PEER = r'''
import json,os,sys
for line in sys.stdin:
 request=json.loads(line)
 with open(os.environ['BOUNDARY_CAPTURE'],'a') as f:f.write(json.dumps({'tool':'peer','request':request})+'\n')
 result={'ok':True,'peerId':'synthetic-peer','publicKey':'synthetic-key','messages':[]}
 if request['cmd']=='start' and os.environ.get('BOUNDARY_MODE')=='reject-start':
  result={'ok':False,'errorMessage':'Synthetic leaf refuses network start'}
 print(json.dumps(result),flush=True)
'''
GO = r'''
import json,os,sys
with open(os.environ['BOUNDARY_CAPTURE'],'a') as f:f.write(json.dumps({'tool':'go','argv':sys.argv[1:]})+'\n')
'''
FLUTTER = r'''
import json,os,subprocess,sys
from pathlib import Path
args=sys.argv[1:]
with open(os.environ['BOUNDARY_CAPTURE'],'a') as f:f.write(json.dumps({'tool':'flutter','argv':args})+'\n')
defines=dict(a.removeprefix('--dart-define=').split('=',1) for a in args if a.startswith('--dart-define='))
key=defines['BENCHMARK'];gp=key=='GROUP_PUBLISH'
root=Path(os.environ['BOUNDARY_ROOT'])
harness=root/('integration_test/benchmark_group_publish_harness.dart' if gp else 'integration_test/benchmark_timeout_accuracy_harness.dart')
source=harness.read_text()
# Run the source-owned pure filesystem helpers, not a Python reimplementation
# of their paths. This cannot certify an installed simulator app's runtime.
helpers=source[source.index('const _configuredSharedDir'):source.index('Map<String, dynamic> _buildCliJoinFixture' if gp else 'class _HangingBridge')]
main="""
Future<void> main() async {
 if (loadCliPeerFixture()?['peerId'] != 'synthetic-peer') throw StateError('host CLI fixture unreadable');
 _writeSharedJson('join_fixture.json', {'groupId':'synthetic-group'});
 await _waitForSharedSignal('cli_joined');
}
""" if gp else """
Future<void> main() async {
 _writeSharedJson('receiver_fixture.json', {'peerId':'synthetic-receiver','addresses':<String>[]});
 await _waitForSharedSignal('send_go');
 _writeSharedSignal('capture_ready');
 await _waitForSharedSignal('cli_send_done');
}
"""
probe=Path(defines['BENCHMARK_SHARED_DIR'])/'actual_harness_helpers.dart'
probe.write_text("import 'dart:async';\nimport 'dart:convert';\nimport 'dart:io';\n"+
 ("import '"+(root/'integration_test/_support/cli_peer_fixture.dart').as_uri()+"';\n" if gp else '')+helpers+main)
name='benchmark WRONG' if os.environ.get('BOUNDARY_MODE')=='wrong-child' else 'benchmark '+key
print(json.dumps(dict(type='testStart',test=dict(id=1,name=name))),flush=True)
if os.environ.get('BOUNDARY_MODE')=='wrong-child':sys.exit(0)
run=subprocess.run([os.environ['BOUNDARY_DART'],*['-D'+k+'='+v for k,v in defines.items()],str(probe)],capture_output=True,text=True,timeout=10)
if run.returncode:print(run.stdout+run.stderr,file=sys.stderr);sys.exit(run.returncode)
with open(os.environ['BOUNDARY_CAPTURE'],'a') as f:f.write(json.dumps({'tool':'host-protocol','key':key,'completed':True})+'\n')
name='benchmark WRONG' if os.environ.get('BOUNDARY_MODE')=='wrong-child' else 'benchmark '+key
events=[dict(type='testDone',testID=1,result='success',skipped=False),dict(type='done',success=True)]
if os.environ.get('BOUNDARY_MODE')=='skip':events.insert(1,dict(type='print',testID=1,message='[SKIP] synthetic missing fixture'))
for event in events:print(json.dumps(event),flush=True)
'''


class BenchmarkBoundaryTest(unittest.TestCase):
    def nested(self, *, script='run_benchmark_suite.dart', relay=RELAYS,
               target='boundary-sim', pins=PINS, mode='', protected=True):
        with tempfile.TemporaryDirectory(prefix='benchmark-boundary-') as temporary:
            temp = Path(temporary)
            (temp/'bin').mkdir(); (temp/'go-mknoon/bin').mkdir(parents=True)
            (temp/'integration_test').symlink_to(ROOT/'integration_test', target_is_directory=True)
            for path, body in [(temp/'go-mknoon/bin/testpeer', PEER),
                               (temp/'bin/go', GO), (temp/'bin/flutter', FLUTTER)]:
                path.write_text('#!'+sys.executable+'\n'+body); path.chmod(0o755)
            (temp/'bin/dart').symlink_to(DART)
            capture = temp/'capture.jsonl'
            env = {**os.environ, 'PATH':str(temp/'bin'), 'BOUNDARY_CAPTURE':str(capture),
                   'BOUNDARY_ROOT':str(ROOT), 'BOUNDARY_DART':str(DART), 'BOUNDARY_MODE':mode}
            for name in ['MKNOON_RELAY_ADDR', 'MKNOON_RELAY_ADDRESSES', legacy.PIN, 'MKNOON_LEGACY_ISOLATED']:
                env.pop(name, None)
            if protected: env[legacy.PIN] = json.dumps(pins)
            if relay is not None: env['MKNOON_RELAY_ADDRESSES'] = relay
            argv = [str(DART), str(ROOT/'integration_test/scripts'/script), '-d', target]
            if script == 'run_benchmark_suite.dart': argv += ['--scenarios','GP,H','--fixture-dir',str(temp/'fixtures')]
            run = subprocess.run(argv,cwd=temp,env=env,capture_output=True,text=True,timeout=30)
            rows = [json.loads(s) for s in capture.read_text().splitlines()] if capture.exists() else []
            return run, rows

    def test_real_nested_go_and_flutter_receive_same_explicit_relays_and_host_protocol(self):
        run, rows = self.nested()
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        starts = [r['request'] for r in rows if r['tool']=='peer' and r['request']['cmd']=='start']
        self.assertEqual(len(starts), 2)
        for start in starts:self.assertEqual(start.get('params',{}).get('relayAddresses'), RELAYS.split(','))
        flutter = [r['argv'] for r in rows if r['tool']=='flutter']
        self.assertEqual(len(flutter), 2)
        for argv in flutter:
            self.assertEqual(argv[argv.index('-d')+1], PINS['ios-simulator-a'])
            self.assertIn('--dart-define=MKNOON_RELAY_ADDRESSES='+RELAYS, argv)
        self.assertEqual({r['key'] for r in rows if r['tool']=='host-protocol'}, {'GROUP_PUBLISH','TIMEOUT_ACCURACY'})

    def test_missing_or_malformed_protected_relays_fail_before_any_leaf_launch(self):
        for script in ['run_benchmark_suite.dart', *SCRIPTS]:
            for relay in [None, '', ' ', ',', 'not-a-relay', RELAY+',', RELAY.replace('4001','0'), RELAY.replace('4001','65536')]:
                with self.subTest(script=script,relay=relay):
                    run, rows = self.nested(script=script,relay=relay,mode='reject-start')
                    self.assertNotEqual(run.returncode, 0)
                    self.assertEqual(rows, [], run.stdout+run.stderr)

    def test_host_file_scripts_reject_android_physical_ios_and_unleased_targets_before_launch(self):
        for script in ['run_benchmark_suite.dart', *SCRIPTS]:
            for target, pins in [('boundary-usb',PINS), ('iphone',{'ios-physical':'iphone'}), ('foreign',PINS)]:
                with self.subTest(script=script,target=target):
                    run, rows = self.nested(script=script,target=target,pins=pins,mode='reject-start')
                    self.assertNotEqual(run.returncode, 0)
                    self.assertEqual(rows, [], run.stdout+run.stderr)

    def test_nested_failure_continues_other_scenario_without_completion(self):
        run, rows = self.nested(mode='reject-start')
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(len([r for r in rows if r['tool']=='peer' and r['request']['cmd']=='start']),2)
        self.assertNotIn('FULL_BENCHMARK_COMPLETED peer-suite', run.stdout)

    def test_only_unprotected_absent_relay_retains_legacy_defaults(self):
        run, rows = self.nested(relay=None,protected=False,mode='reject-start')
        starts=[r['request'] for r in rows if r['tool']=='peer' and r['request']['cmd']=='start']
        self.assertEqual(len(starts),2)
        self.assertTrue(all('relayAddresses' not in r.get('params',{}) for r in starts))
        self.assertNotEqual(run.returncode,0)  # Fixture stops before networking.

    def test_wrong_child_and_skip_cannot_emit_suite_completion(self):
        for mode in ['wrong-child','skip']:
            with self.subTest(mode=mode):
                run, rows = self.nested(mode=mode)
                self.assertNotEqual(run.returncode, 0, run.stdout+run.stderr)
                self.assertEqual(len([r for r in rows if r['tool']=='flutter']),2)
                self.assertNotIn('FULL_BENCHMARK_COMPLETED peer-suite', run.stdout)

    def test_catalogue_partitions_exact_original_dispatch_and_attests_nested_owners(self):
        contract = legacy.contracts()['full']['gate benchmark-sim']
        commands, _ = legacy.bind(contract,PINS,{'relay_addresses':RELAYS},Path('/synthetic/output'))
        self.assertEqual(contract['roles'], ['android-physical','ios-simulator-a'])
        self.assertEqual(len(commands),2)
        actual = [(c[c.index('-d')+1], c[c.index('--scenarios')+1]) for c in commands]
        self.assertEqual(actual, [(PINS['android-physical'],ANDROID),(PINS['ios-simulator-a'],'GP,H')])
        selections = [set(s.split(',')) for _,s in actual]
        self.assertFalse(selections[0] & selections[1])
        self.assertEqual(selections[0] | selections[1], set('A,B,BR,C,D,E,F,G,GP,H,I,J,K,L,M,N,R'.split(',')))
        for name in [*SCRIPTS, 'run_benchmark_suite.dart','benchmark_boundary.dart']:
            self.assertIn('integration_test/scripts/'+name,contract['sources'])

    def test_partition_leases_preflight_exact_receipts_and_independent_failure(self):
        matrix = dict(errors=[], adb=[PINS['android-physical']],
                      ios_simulators=[PINS['ios-simulator-a']],
                      flutter=[dict(id=v,targetPlatform='android-arm64' if k.startswith('android') else 'ios',
                                    emulator=k.startswith('ios')) for k,v in PINS.items()])
        env = {legacy.PIN:json.dumps(PINS), 'MKNOON_LEGACY_ISOLATED':'1',
               'MKNOON_LEGACY_CONFIG_JSON':json.dumps({'relay_addresses':RELAYS})}
        for mode in ['pass','missing','wrong-target','wrong-selection','duplicate','first-fails','cancel-after-pass','cancel-after-fail']:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temporary:
                calls = []
                cancel = threading.Event()
                def launch(argv, cwd, timeout, child):
                    # Every process, including fresh preflight, runs with both
                    # exact target leases held by the real route executor.
                    self.assertEqual(json.loads(child[legacy.PIN]), PINS)
                    for target in PINS.values():
                        with self.assertRaises(preflight.DeviceLeaseBusy):
                            with preflight.device_leases([target]):pass
                    calls.append(argv)
                    if argv[0]=='xcrun':
                        return json.dumps({'devices':{'fixture':[dict(udid=PINS['ios-simulator-a'],isAvailable=True)]}}),0,False,0
                    if argv[0]=='adb':
                        self.assertEqual(argv[1:3],['-s',PINS['android-physical']])
                        return ('ACTIVITY MANAGER RUNNING PROCESSES (dumpsys activity processes)\n'
                                '  mProcessesReady=true mSystemReady=true mBooted=true mFactoryTest=0\n'
                                '  mForceBackgroundCheck=false\n'),0,False,0
                    self.assertEqual({c[0] for c in calls[:2]}, {'adb','xcrun'})
                    target, selectors = argv[argv.index('-d')+1], argv[argv.index('--scenarios')+1]
                    marker = 'FULL_BENCHMARK_SELECTION '+target+' '+selectors
                    if mode=='wrong-target':marker=marker.replace(target,'foreign')
                    if mode=='wrong-selection':marker=marker.replace(selectors,'B')
                    if mode=='missing':marker='FULL_BENCHMARK_COMPLETED peer-suite'
                    if mode=='duplicate':marker+='\n'+marker
                    if mode.startswith('cancel-'):cancel.set()
                    return marker+'\n',int(mode in ('first-fails','cancel-after-fail') and target==PINS['android-physical']),False,0
                with contextlib.redirect_stdout(io.StringIO()), mock.patch.object(legacy.checks._LAUNCH_CONTEXT,'cancel_event',cancel,create=True):
                    result=legacy.execute('full',['gate benchmark-sim'],Path(temporary)/'out',env=env,matrix=matrix,launch=launch)
                expected='PASS' if mode=='pass' else 'FAIL' if mode in ('first-fails','cancel-after-fail') else 'BLOCKED'
                self.assertEqual(result['status'],expected)
                children=[c for c in calls if c[0]=='dart']
                self.assertEqual(len(children),1 if mode.startswith('cancel-') else 2)
                self.assertEqual([c[c.index('--scenarios')+1] for c in children], [ANDROID] if mode.startswith('cancel-') else [ANDROID,'GP,H'])
                receipts=result['route_results'][0]['command_results']
                self.assertEqual([r['index'] for r in receipts],[0,1])
                if mode=='first-fails':self.assertEqual([r['status'] for r in receipts],['FAIL','PASS'])
                if mode.startswith('cancel-'):self.assertEqual(receipts[-1]['status'],'NOT RUN')


if __name__ == '__main__':unittest.main()
