"""Composition contracts: real readers/entrypoints, synthetic host evidence only."""
import contextlib
import copy
import io
import json
import os
import shutil
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mknoon_checks_test import RepositoryFixture, checks
from mknoon_full_checks_test import FullExecutionFixture
import full_suite_adapters as adapters
import testing_inventory as inventory

PROJECT = Path(__file__).resolve().parents[2]
DART = Path(os.environ.get('MKNOON_REVIEW_DART') or shutil.which('dart') or '/unavailable/dart').resolve()
_BUNDLED_DART = DART.parent / 'cache/dart-sdk/bin/dart'
if _BUNDLED_DART.is_file():
    DART = _BUNDLED_DART


def rules():
    return json.loads((PROJECT / checks.RULES).read_text())


class OwnershipCompositionTest(RepositoryFixture):
    def test_audited_batch_listing_keeps_canonical_host_owner(self):
        listing = copy.deepcopy(rules()['full_inventory']['listings'][0])
        self.write('scripts/run_host_test_gates.sh', '# fixture listing only\n')
        row = dict(id='full-sims-major', kind='sims', command=[])
        policy = dict(automatic=[dict(family='flutter_host', patterns=['test/*'])],
                      mappings=[], exclusions=[], catalogs=[], listings=[listing])
        selected = [row]
        with mock.patch.object(inventory, 'list_runner', return_value=dict(status='PASS',
                planned_commands=["Flutter batch path 'test/chat_test.dart'"])):
            ledger = inventory.reconcile(self.root, dict(full_commands=selected, full_inventory=policy),
                                         selected, checks.source_files(self.root))
        whole = next(r for r in ledger['obligations'] if r['path'] == 'test/chat_test.dart')
        self.assertEqual(whole['owners'], ['full-sims-major'])
        self.assertEqual(whole.get('receipt_bindings', []), [dict(owner='full-sims-major', capability='host.dart.all')])

    def test_new_mappings_and_explicit_catalogue_bind_exact_children(self):
        actual = rules()['full_inventory']
        paths = ['ios/RunnerUITests/GroupMediaBackgroundRecoveryUITests.swift',
                 'integration_test/scripts/run_group_multi_party_device_real.dart']
        mappings = [m for m in actual['mappings'] if any(p in m['patterns'] for p in paths)]
        catalog = next(c for c in actual['catalogs'] if 'group_multi_party_device_criteria' in c['path'])
        for path in set(paths) | {p for m in mappings for p in m['patterns']}:
            self.write(path, '// synthetic discovery fixture')
        for path in {catalog['path'], *(b['path'] for b in catalog['bindings'] if 'path' in b)}:
            self.write(path, (PROJECT / path).read_text())
        owner = dict(id='full-sims-major', kind='sims', command=[], capability='*')
        policy = dict(automatic=[], mappings=mappings, listings=[], exclusions=[], catalogs=[catalog])
        selected = [owner]
        ledger = inventory.reconcile(self.root, dict(full_commands=selected, full_inventory=policy),
                                     selected, checks.source_files(self.root))
        rows = [r for r in ledger['obligations'] if r['path'] in paths or r.get('family') == 'scenario']
        self.assertEqual(sum(r.get('family') == 'scenario' for r in rows), 109)
        for row in rows:
            with self.subTest(path=row['path'], selector=row['selector']):
                bindings = row.get('receipt_bindings', [])
                self.assertTrue(bindings)
                self.assertTrue(all(b.get('capability') for b in bindings))
                for status in ('N/A', 'FAIL', None):
                    receipts = [] if status is None else [dict(id=b['capability'], status=status) for b in bindings]
                    result = dict(status='PASS', attempts=[dict(capability_results=receipts)])
                    joined = checks.obligation_results([row], {'full-sims-major': result})
                    self.assertEqual(joined[0]['status'], status or 'NOT RUN')

    def test_new_alias_requires_unique_receipt_on_every_attempt(self):
        alias = dict(id='alias', path='test/a.dart', selector='gate:core', owners=['parent'],
                     family='result_alias', owner_capability='host.dart.all')
        for receipts in ([], [dict(id='host.dart.all', status='PASS')] * 2):
            result = dict(status='PASS', attempts=[dict(capability_results=receipts)])
            self.assertEqual(checks.obligation_results([alias], {'parent': result})[0]['status'], 'NOT RUN')

    def test_native_adapter_scope_survives_but_filtered_file_keeps_remaining_owner(self):
        path = 'scripts/test/native_fixture_test.py'
        self.write(path, 'import unittest\n')
        rows = [dict(id='native', kind='full_adapter', command=['bash', 'scripts/test/run_app_visibility_native_371.sh']),
                dict(id='filtered', kind='python', selected_paths=[path],
                     command=[sys.executable, '-m', 'unittest', path, '-kSelected'])]
        native_path = 'ios/RunnerTests/FixtureTests.swift'
        self.write(native_path, '// native')
        policy = dict(automatic=[dict(family='python_unittest', patterns=['scripts/test/*_test.py'])],
                      mappings=[dict(owner='native', patterns=[native_path], reason='Audited exact native recipe')],
                      exclusions=[], listings=[], catalogs=[])
        ledger = inventory.reconcile(self.root, dict(full_commands=rows, full_inventory=policy),
                                     rows, checks.source_files(self.root))
        self.assertEqual(next(r for r in ledger['obligations'] if r['path'] == native_path)['owners'], ['native'])
        whole = next(r for r in ledger['obligations'] if r['path'] == path and not r['selector'])
        self.assertNotIn('filtered', whole['owners'])
        self.assertTrue(whole['owners'])
        self.assertTrue(any(r['path'] == path and r['variant'] == 'command-filter' for r in ledger['obligations']))


class NativeBoundaryTest(RepositoryFixture):
    def test_native_available_shutdown_target_is_not_absent_hardware(self):
        check = next(c for c in rules()['full_commands'] if c['id'] == 'full.native.371')
        matrix = dict(flutter=[], errors=[], ios_simulators=['owned'], native_ios_simulators=['owned'])
        config = dict(isolated_test_environment=True, fixture_reference='fixture', devices=dict(ios_simulator='owned'))
        self.assertEqual(adapters.availability(check, config, matrix), 'AVAILABLE')
        self.assertEqual(adapters.prerequisites(check, config, matrix), [])
        config['devices']['ios_simulator'] = 'unavailable'
        self.assertEqual(adapters.availability(check, config, matrix), 'BLOCKED')

    def test_actual_native_recipes_pin_selection_and_block_unconfigured_execution(self):
        actual = {c['id']: c for c in rules()['full_commands']}
        for number, variable in [('371', 'IOS_DEVICES_JSON'), ('373', 'IOS_SIMULATORS_JSON')]:
            check = actual['full.native.' + number]
            with self.subTest(number=number):
                self.assertIn('ios_simulator', check.get('device_roles', []))
                self.assertTrue(checks.is_campaign(check))
                self.assertTrue(adapters.prerequisites(check, {}, {}))
                self.assertEqual(adapters.availability(check, {}, {'flutter': [], 'errors': []}), 'N/A')
                steps, env = adapters.bind(check, {'devices': {'ios_simulator': 'OWNED-SIM'}}, PROJECT, self.root)
                self.assertIn('OWNED-SIM', env.values())
                source = (PROJECT / steps[0]['command'][1]).read_text()
                assignment = re.search(r'simulator_id="\$\(.*?\n\)"', source, re.S).group()
                matrix = self.write('matrix.json', json.dumps({'devices': {'iOS-runtime': [
                    dict(name='iPhone foreign', udid='UNLEASED-SIMULATOR', isAvailable=True),
                    dict(name='iPhone owned', udid='OWNED-SIM', isAvailable=True)]}}))
                run = subprocess.run(['bash', '-c', assignment + '\nprintf "%s" "$simulator_id"'],
                                     env={**os.environ, **env, variable: str(matrix)}, capture_output=True, text=True)
                self.assertEqual(run.returncode, 0, run.stderr)
                self.assertEqual(run.stdout, 'OWNED-SIM')

    def test_extra_roles_and_macos_config_have_exact_protected_assignments(self):
        ids = dict(android_physical='usb', android_emulator='emu', android_emulator_second='emu2',
                   ios_simulator='sim', ios_simulator_b='simB', ios_simulator_c='simC', ios_simulator_d='simD', macos='macos')
        env = checks.sims_environment(dict(devices=ids), self.root / 'report')
        self.assertEqual(set(json.loads(env.get('SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON', '{}')).values()), set(ids.values()))
        self.assertEqual(env.get('SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID'), 'emu2')

    def test_disposable_group_authorization_cannot_forward_an_unleased_target(self):
        config = dict(devices=dict(ios_simulator_a='simA'),
                      full_suite=dict(ios_disposable_simulator_ids='simA,foreign'))
        with self.assertRaisesRegex(checks.InvalidPlan, 'protected'):
            checks.sims_environment(config, self.root / 'report')

    def test_native_and_xctest_preflight_holds_exact_lease_before_entrypoint(self):
        for cid in ('full.native.371', 'full.xctest.notificationtapuitests.testnotificationtap'):
            row = copy.deepcopy(next(c for c in rules()['full_commands'] if c['id'] == cid))
            role = row.get('device_roles', ['ios_simulator'])[0]
            row.update(selected_paths=[], command=['fixture'], steps=[dict(command=[sys.executable, 'proof.py'], format='marker', marker='FIXTURE COMPLETE')], environment={})
            config = dict(devices={role: 'OWNED-SIM'})
            self.write('proof.py', '''import fcntl,hashlib
from pathlib import Path
p=Path('.codex-test-logs/leases')/(hashlib.sha256(b'OWNED-SIM').hexdigest()+'.lock')
with p.open('r+') as lock:
 try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 except BlockingIOError: pass
 else: raise AssertionError('entrypoint reached unleased target')
print('FIXTURE COMPLETE')
''')
            files = checks.source_files(self.root)
            plan = dict(mode='full', baseline=self.base, candidate_build='fixture', selected=[row],
                        identity=checks.source_identity(self.root, files, self.rules), not_selected=[], unmapped_changes=[])
            out = self.root / '.codex-test-logs' / str(time.monotonic_ns()); out.mkdir(parents=True)
            real_launch, lease = checks.launch, checks.device_preflight.device_leases
            observed = []
            def launch(command, cwd, timeout, env):
                if command[:2] == ['xcrun', 'simctl']:
                    observed.append(command)
                    return json.dumps({'devices': {'iOS-runtime': [dict(udid='OWNED-SIM', isAvailable=True)]}}), 0, False, 0
                if role == 'ios_simulator': self.assertTrue(observed, 'simulator preflight omitted')
                return real_launch(command, cwd, timeout, env)
            with mock.patch.object(checks, 'launch', side_effect=launch), mock.patch.object(checks.device_preflight, 'device_leases', side_effect=lambda ids: lease(ids, self.root / '.codex-test-logs/leases')), contextlib.redirect_stdout(io.StringIO()):
                checks.execute_plan(self.args(mode='full'), self.root, self.rules, plan, files, config, {}, out, time.monotonic())
            result = json.loads((out / 'results.json').read_text())['results'][0]
            self.assertEqual(result['status'], 'PASS', result)


class AdapterPrivacyTest(FullExecutionFixture):
    def test_full_legacy_unknown_command_blocks_before_any_nested_launcher(self):
        task = copy.deepcopy(next(c for c in rules()['full_commands'] if c['id'] == 'full-legacy'))
        task.update(dependencies=[], requirements=[], device_roles=[], command=[sys.executable, 'forbidden.py'])
        self.write('forbidden.py', "raise AssertionError('opaque legacy launcher must not execute')\n")
        task['selected_paths'] = []
        files = checks.source_files(self.root)
        plan = dict(mode='full', baseline=self.base, candidate_build='fixture', selected=[task],
                    identity=checks.source_identity(self.root, files, self.rules), not_selected=[], unmapped_changes=[])
        out = self.root / '.codex-test-logs' / str(time.monotonic_ns()); out.mkdir(parents=True)
        with contextlib.redirect_stdout(io.StringIO()):
            checks.execute_plan(self.args(mode='full'), self.root, self.rules, plan, files,
                dict(devices=dict(android_physical='usb', ios_simulator='sim')), {}, out, time.monotonic())
        row = json.loads((out / 'results.json').read_text())['results'][0]
        self.assertEqual(row['status'], 'BLOCKED')
        self.assertEqual(row['checkpoint'], 'unknown_legacy_command')
        self.assertEqual(row['attempts'], [])

    def test_per_step_flutter_locations_use_source_paths_only(self):
        poison = 'private_fixture_payload_9821'
        output = '\n'.join(json.dumps(e) for e in [
            dict(type='suite', suite=dict(id=1, path=poison)),
            dict(type='testStart', test=dict(id=1, suiteID=1, name=poison, url=poison)),
            dict(type='testDone', testID=1, result='error', skipped=False),
            dict(type='done', success=False)])
        proof = adapters.inspect(dict(format='flutter', command=['flutter', 'test', 'test/source_test.dart'],
                                      paths=['test/source_test.dart']), output, 1, False, self.root)
        self.assertEqual(proof['status'], 'FAIL')
        self.assertNotIn(poison, json.dumps(proof))

    def test_per_step_diagnostics_and_invalid_fixture_payload_stay_private(self):
        poison = 'private_fixture_payload_7359'
        self.write('contract.py', "print('done')\n")
        task = dict(id='adapter', kind='full_adapter', command=[sys.executable, 'contract.py'],
                    steps=[dict(command=[sys.executable, 'contract.py'], format='marker', marker='done')],
                    timeout_seconds=10, boundary='fixture', resources=['isolated:fixture'])
        with mock.patch.object(adapters, 'prepare_step', side_effect=ValueError(poison)):
            _, result = self.run_full([task])
        self.assertNotIn(poison, json.dumps(result))
        self.assertEqual(result['results'][0]['status'], 'BLOCKED')


class BenchmarkCompositionTest(unittest.TestCase):
    def test_dart_runtime_is_available_without_ignored_worker_artifacts(self):
        self.assertTrue(DART.is_file(), 'Use the installed Dart SDK, not a worker artifact')
        self.assertNotIn('.codex-test-logs', DART.parts)

    def test_actual_suite_uses_selected_benchmark_argv_and_rejects_wrong_child(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            shim = folder / 'flutter'
            shim.write_text('''#!@PYTHON@
import json,os,sys
from pathlib import Path
Path(os.environ['ARGV_LOG']).write_text(json.dumps(sys.argv[1:]))
for e in [dict(type='testStart',test=dict(id=1,name=os.environ['TEST_NAME'])),
          dict(type='testDone',testID=1,result='success',skipped=False),dict(type='done',success=True)]:
 print(json.dumps(e))
'''.replace('@PYTHON@', sys.executable))
            shim.chmod(0o755)
            for name, passed in [('benchmark NODE_STARTUP', True), ('benchmark OTHER', False)]:
                run = subprocess.run([str(DART), 'integration_test/scripts/run_benchmark_suite.dart',
                    '-d', 'OWNED-SIM', '--scenarios', 'B', '--fixture-dir', tmp], cwd=PROJECT,
                    env={**os.environ, 'PATH':tmp, 'ARGV_LOG':str(folder/'argv'), 'TEST_NAME':name}, capture_output=True, text=True)
                argv = json.loads((folder/'argv').read_text())
                self.assertEqual(argv[argv.index('-d') + 1], 'OWNED-SIM')
                self.assertIn('--dart-define=BENCHMARK=NODE_STARTUP', argv)
                self.assertEqual(run.returncode == 0, passed, run.stdout + run.stderr)
                self.assertEqual('FULL_BENCHMARK_COMPLETED' in run.stdout, passed)

    def test_actual_dart_reader_rejects_print_return_and_missing_routing_stages(self):
        probe = '''import 'dart:convert';
import '@READER@';
void main() {
 for (final omission in [true, false]) {
  final c = BenchmarkCompletion();
  final events = [
   {'type':'testStart','test':{'id':1,'name':'benchmark ROUTING_PATHS'}},
   if (omission) {'type':'print','testID':1,'message':'[SKIP] CLI peer not unregistered — needs orchestrator to signal unregister'},
   {'type':'testDone','testID':1,'result':'success','skipped':false},
   {'type':'done','success':true}];
  for (final e in events) { c.observe(jsonEncode(e)); }
  var rejected=false;
  try { c.requireCompleted(); } on StateError { rejected=true; }
  if (!rejected) throw StateError('omitted selected routing stages accepted');
 }
 for (final duplicate in [false, true]) {
  final c = BenchmarkCompletion();
  c.observe(jsonEncode({'type':'testStart','test':{'id':1,'name':'benchmark ROUTING_PATHS'}}));
  for (var i=1; i<=8; i++) {
   c.observe(jsonEncode({'type':'print','testID':1,'message':'BENCHMARK_STAGE_COMPLETED R-Sim-$i'}));
  }
  if (duplicate) c.observe(jsonEncode({'type':'print','testID':1,'message':'BENCHMARK_STAGE_COMPLETED R-Sim-1'}));
  c.observe(jsonEncode({'type':'testDone','testID':1,'result':'success','skipped':false}));
  c.observe(jsonEncode({'type':'done','success':true}));
  var rejected=false;
  try { c.requireCompleted(); } on StateError { rejected=true; }
  if (rejected != duplicate) throw StateError('exact stage receipt set not enforced');
 }
}'''.replace('@READER@', (PROJECT / 'integration_test/scripts/benchmark_completion.dart').as_uri())
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'probe.dart'; path.write_text(probe)
            run = subprocess.run([str(DART), '--enable-asserts', str(path)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_outer_marker_rejects_omission_and_missing_runtime_stays_incomplete(self):
        step = next(c for c in rules()['full_commands'] if c['id'] == 'full.benchmark.peer-suite')['steps'][-1]
        proof = adapters.inspect(step, '[SKIP] CLI peer not unregistered\nFULL_BENCHMARK_COMPLETED peer-suite\n', 0, False, PROJECT)
        self.assertEqual(proof['status'], 'BLOCKED')
        with tempfile.TemporaryDirectory() as tmp:
            run = subprocess.run([str(DART), 'integration_test/scripts/run_benchmark_suite.dart', '-d', 'synthetic', '--scenarios', 'R', '--fixture-dir', tmp],
                                 cwd=PROJECT, env={**os.environ, 'PATH': tmp}, capture_output=True, text=True)
            self.assertNotEqual(run.returncode, 0)
            self.assertIn('flutter', run.stdout + run.stderr)
            self.assertNotIn('FULL_BENCHMARK_COMPLETED', run.stdout)


if __name__ == '__main__':
    unittest.main()
