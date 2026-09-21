"""Real subprocess and source-inventory regressions for the existing full entry point."""
import contextlib
import io
import json
from pathlib import Path
import sys
import time
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mknoon_checks_test import RepositoryFixture, checks


class FullExecutionFixture(RepositoryFixture):
    def task(self, name, resources=None, dependencies=(), fail=False):
        path = name + '_test.py'
        self.write(path, '''import json, time, unittest
from pathlib import Path
class Fixture(unittest.TestCase):
 def test_interval(self):
  start=time.monotonic()
  time.sleep(.3)
  Path('.codex-test-logs/INTERVAL.json').write_text(json.dumps([start,time.monotonic()]))
  self.assertTrue(SUCCESS)
'''.replace('INTERVAL', name).replace('SUCCESS', str(not fail)))
        row = dict(id=name, kind='python', paths=[path],
                   command=[sys.executable, '-m', 'unittest', '-v', path],
                   boundary='isolated interval fixture', timeout_seconds=10,
                   dependencies=list(dependencies))
        if resources is not None:
            row['resources'] = resources
        return row

    def run_full(self, tasks, workers=1, only=None):
        self.rules['full_commands'] = tasks
        self.write('tool/testing/selection.json', json.dumps(self.rules))
        out = self.root / '.codex-test-logs' / str(time.monotonic_ns())
        with mock.patch.object(checks, 'ROOT', self.root), \
             mock.patch.object(checks, 'toolchain_identity', return_value={}), \
             contextlib.redirect_stdout(io.StringIO()):
            code = checks.main(['full', '--base', self.base, '--local', '--jobs', str(workers), '--output', str(out)] + (['--only', only] if only else []))
        return code, json.loads((out / 'results.json').read_text())

    def interval(self, name):
        return json.loads((self.root / '.codex-test-logs' / (name + '.json')).read_text())



class FullSchedulingTest(FullExecutionFixture):
    def test_full_cli_overlaps_independent_processes_and_reconciles_serial_obligations(self):
        tasks = [self.task(n, ['isolated:' + n]) for n in ['a', 'b']]
        serial_code, serial = self.run_full(tasks)
        self.assertLessEqual(self.interval('a')[1], self.interval('b')[0])
        code, parallel = self.run_full(tasks, workers=2)
        self.assertEqual((serial_code, code), (0, 0))
        self.assertLess(max(self.interval('a')[0], self.interval('b')[0]),
                        min(self.interval('a')[1], self.interval('b')[1]))
        self.assertEqual([(r['id'], r['status']) for r in serial['results']],
                         [(r['id'], r['status']) for r in parallel['results']])
        self.assertEqual(parallel['scheduling']['max_observed_concurrency'], 2)
        self.assertTrue(all(r['wait_seconds'] >= 0 for r in parallel['results']))

    def test_same_resource_and_unknown_metadata_serialize(self):
        for resources in [(['shared'], ['shared']), (None, ['isolated:b']),
                          (['device:one'], ['device-control:one'])]:
            self.run_full([self.task('a', resources[0]), self.task('b', resources[1])], 2)
            a, b = self.interval('a'), self.interval('b')
            self.assertTrue(a[1] <= b[0] or b[1] <= a[0])

    def test_failed_dependency_does_not_launch_but_independent_work_finishes(self):
        code, report = self.run_full([self.task('a', ['one'], fail=True),
                                     self.task('b', ['two'], dependencies=['a']),
                                     self.task('c', ['three'])], 3)
        rows = {r['id']: r for r in report['results']}
        self.assertNotEqual(code, 0)
        self.assertEqual(rows['a']['status'], 'FAIL')
        self.assertEqual(rows['b']['checkpoint'], 'dependency_failed')
        self.assertEqual(rows['b']['attempts'], [])
        self.assertEqual(rows['c']['status'], 'PASS')
        self.assertFalse((self.root / '.codex-test-logs/b.json').exists())

    def test_dependency_cycle_is_rejected_before_launch(self):
        self.rules['full_commands'] = [self.task('a', ['a'], ['b']), self.task('b', ['b'], ['a'])]
        with self.assertRaisesRegex(checks.InvalidPlan, 'cycle'):
            checks.validate(self.root, self.rules)


class FullInventoryTest(RepositoryFixture):
    def policy(self):
        self.rules['full_commands'] = []
        self.rules['full_inventory'] = {
            'automatic': [{'family': 'flutter_host', 'patterns': ['test/*', 'packages/*/test/*']},
                          {'family': 'python_unittest', 'patterns': ['*_test.py']}],
            'exclusions': [], 'catalogs': [], 'listings': [], 'mappings': []}

    def test_new_sources_are_selected_and_unmapped_native_is_a_completeness_gap(self):
        self.policy()
        self.write('test/new_test.dart', "void main() {}")
        self.write('packages/plugin/pubspec.yaml', 'name: plugin\n')
        self.write('packages/plugin/test/new_test.dart', 'void main() {}')
        self.write('ios/RunnerTests/NewTests.swift', '// native assertions')
        self.write('test/fixtures/example_test.dart', '// fixture')
        plan, _ = checks.make_full_plan(self.args(), self.root, self.rules, capture_toolchains=False)
        bypath = {r['path']: r for r in plan['obligations']}
        self.assertEqual(bypath['test/new_test.dart']['status'], 'SELECTED')
        self.assertEqual(bypath['ios/RunnerTests/NewTests.swift']['status'], 'UNMAPPED')
        self.assertEqual(bypath['test/fixtures/example_test.dart']['status'], 'EXCLUDED')
        nested = next(c for c in plan['selected'] if c.get('cwd') == 'packages/plugin')
        self.assertIn('test/new_test.dart', nested['command'])
        self.assertTrue(plan['coverage_gaps'])
        self.assertEqual(len({r['id'] for r in plan['obligations']}), len(plan['obligations']))

    def test_catalog_selectors_preserve_variants_and_deduplicate_only_identical_obligations(self):
        self.policy()
        self.write('cases.dart', "scenario: 'one', scenario: 'two', scenario: 'one'")
        self.rules['full_inventory']['catalogs'] = [
            {'path': 'cases.dart', 'pattern': "scenario: '([^']+)'", 'variant': 'android', 'reason': 'Needs peer adapter'},
            {'path': 'cases.dart', 'pattern': "scenario: '([^']+)'", 'variant': 'ios', 'reason': 'Needs iOS adapter'}]
        plan, _ = checks.make_full_plan(self.args(), self.root, self.rules, capture_toolchains=False)
        rows = [r for r in plan['obligations'] if r['path'] == 'cases.dart']
        self.assertEqual(len(rows), 4)
        self.assertTrue(all(r['status'] == 'UNMAPPED' for r in rows))
        self.assertEqual({r['selector'] for r in rows}, {'one', 'two'})

    def test_same_file_with_filtered_command_does_not_claim_all_file_tests(self):
        self.policy()
        self.rules['full_commands'] = [dict(id='subset', kind='flutter', paths=['test/chat_test.dart'],
            names=['one case'], command=['flutter', 'test', 'test/chat_test.dart', '--name', 'one case'],
            timeout_seconds=20, boundary='subset only')]
        plan, _ = checks.make_full_plan(self.args(), self.root, self.rules, capture_toolchains=False)
        owners = next(r for r in plan['obligations'] if r['path']=='test/chat_test.dart')['owners']
        self.assertNotEqual(owners, ['subset'])
        self.assertTrue(any(c['id'] in owners and '--name' not in c['command'] for c in plan['selected']))

    def test_full_plan_inventory_is_fingerprint_bound(self):
        self.policy()
        plan, _ = checks.make_full_plan(self.args(), self.root, self.rules, capture_toolchains=False)
        before = checks.plan_fingerprint(plan)
        plan['obligations'].append({'id': 'forgotten', 'status':'UNMAPPED'})
        self.assertNotEqual(before, checks.plan_fingerprint(plan))


class FullBuildContractTest(RepositoryFixture):
    def test_full_manifest_executes_proofs_and_expands_all_selected_capabilities(self):
        root = Path(__file__).resolve().parents[2]
        rules = json.loads((root / checks.RULES).read_text())
        for row in rules['full_commands']:
            if row['kind'] == 'sims':
                self.assertNotIn('--prepare-builds', row['command'])

    def test_sims_subset_report_cannot_satisfy_larger_selected_inventory(self):
        from mknoon_checks_test import ExternalReportRegressionTest
        path = self.root / 'report.json'
        path.write_text(json.dumps({'verdicts': [ExternalReportRegressionTest.verdict('one')], 'validationErrors': []}))
        result = checks.inspect_sims(path, '*', 0, False, selected_capabilities=['one','two'])
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertEqual(result['missing_capabilities'], ['two'])

    def test_native_build_resources_cannot_overlap_even_with_distinct_profile_names(self):
        a = dict(kind='command', command=['flutter', 'build', 'apk'], resources=['build:one'])
        b = dict(kind='command', command=['./android/gradlew', 'test'], resources=['build:two'])
        self.assertFalse(checks.resources_compatible(a, b))


class FullSafetyTest(FullExecutionFixture):
    def test_unknown_mapping_owner_and_empty_catalog_fail_validation(self):
        self.rules['full_commands'] = [self.task('a', ['isolated:a'])]
        self.rules['full_inventory'] = dict(automatic=[], exclusions=[], catalogs=[], listings=[],
            mappings=[dict(owner='typo', patterns=['test/*'], reason='fixture')])
        with self.assertRaises(checks.InvalidPlan): checks.validate(self.root, self.rules)

    def test_run_records_every_obligation_when_coverage_is_incomplete(self):
        self.rules['full_inventory'] = dict(automatic=[], exclusions=[], catalogs=[], listings=[], mappings=[])
        code, report = self.run_full([self.task('a', ['isolated:a'])], 2)
        self.assertNotEqual(code, 0)
        self.assertTrue(report['gaps'])
        self.assertTrue(any(r['status']=='UNMAPPED' for r in report['obligations']))
        self.assertEqual(report['results'][0]['status'], 'PASS')

    def test_owned_group_cancel_keeps_pending_and_raw_evidence(self):
        import os
        import signal
        import subprocess
        import threading
        tasks = [self.task('a', ['one']), self.task('b', ['one'])]
        self.write('a_test.py', '''import os,signal,subprocess,sys,time,unittest
from pathlib import Path
class Test(unittest.TestCase):
 def test_child(self):
  child=subprocess.Popen([sys.executable,'-c', "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(.6); open('.codex-test-logs/escaped','w').write('escaped')"])
  Path('.codex-test-logs/started').write_text(str(child.pid))
  print('owned raw evidence', flush=True)
  time.sleep(30)
''')
        def cancel():
            deadline=time.monotonic()+10
            while not (self.root/'.codex-test-logs/started').exists() and time.monotonic()<deadline:
                time.sleep(.02)
            os.kill(os.getpid(), signal.SIGTERM)
        thread=threading.Thread(target=cancel)
        thread.start()
        code, report = self.run_full(tasks, 2)
        thread.join()
        time.sleep(.7)
        self.assertNotEqual(code, 0)
        self.assertFalse((self.root/'.codex-test-logs/escaped').exists())
        self.assertEqual(report['results'][1]['checkpoint'], 'run_cancelled')
        logs=list((self.root/'.codex-test-logs').glob('*/a-1.raw.log'))
        self.assertEqual(len(logs),1)
        self.assertIn('owned raw evidence', logs[0].read_text())


class HostWorkerContractTest(RepositoryFixture):
    def test_top_level_worker_budget_reaches_existing_host_batch(self):
        import os
        import subprocess
        root = Path(__file__).resolve().parents[2]
        env = dict(os.environ, MKNOON_HOST_FLUTTER_WORKERS='3')
        result = subprocess.run(['bash','scripts/run_host_test_gates.sh','host-all','--dart-only',
                                 '--batch-flutter','--concurrency','4','--list'], cwd=root, env=env,
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('concurrency=3;',result.stdout)


class LegacySelectionTest(RepositoryFixture):
    def test_legacy_excludes_only_explicit_duplicate_routes_and_keeps_default_95(self):
        import subprocess
        root = Path(__file__).resolve().parents[2]
        for exclusions, count in [([],95),(['all core tests','all feature tests'],93)]:
            args=['bash','scripts/run_flutter_full_regression.sh','--dry-run','--output',str(self.root/'logs')]
            for label in exclusions: args += ['--exclude-label',label]
            result=subprocess.run(args,cwd=root,capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(sum(l.startswith('RUN ') for l in result.stdout.splitlines()),count)
            for label in exclusions:self.assertNotIn(' '+label+'\n',result.stdout)


class LedgerOutcomeTest(RepositoryFixture):
    def test_unavailable_and_unrun_sims_rows_do_not_inherit_parent_pass(self):
        obligations = [dict(id=n,path='manifest',selector=n,family='sims',owners=['sims'],status='SELECTED') for n in ['pass','absent','missing']]
        results = {'sims': dict(status='BLOCKED',attempts=[dict(status='BLOCKED',capability_results=[
            dict(id='pass',status='PASS',observed_status='PASS'),
            dict(id='absent',status='N/A',reason='target_unavailable_by_project_policy')])])}
        rows=checks.obligation_results(obligations,results)
        self.assertEqual([r['status'] for r in rows],['PASS','N/A','NOT RUN'])
        self.assertEqual(rows[1]['reason'],'target_unavailable_by_project_policy')


class ClassificationListingTest(RepositoryFixture):
    def test_classification_listing_does_not_need_dart_or_launch_scenarios(self):
        import os
        import subprocess
        root=Path(__file__).resolve().parents[2]
        executable=self.write('bin/dart', '#!/bin/sh\necho "unexpected scenario execution" >&2\nexit 97\n')
        executable.chmod(0o755)
        result=subprocess.run(['bash','scripts/check_reliability_simulation_discovery.sh','--classifications-tsv'],
            cwd=root,env=dict(os.environ,PATH=str(executable.parent)+':'+os.environ['PATH']),capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('integration_test/scripts/run_group_multi_party_device_real.dart',result.stdout)
        self.assertNotIn('unexpected scenario execution',result.stderr)


class FailurePreservationTest(RepositoryFixture):
    def test_partial_legacy_failure_keeps_the_failure_and_missing_routes(self):
        directory=self.root/'legacy';directory.mkdir()
        (directory/'summary.tsv').write_text('FAIL\tfirst\tfirst.log\t1s\n')
        result=checks.inspect_legacy(directory,1,False,[dict(label='first'),dict(label='second')])
        self.assertEqual(result['status'],'FAIL')
        self.assertIn('second',result['missing_routes'])


class PortableInventoryTest(RepositoryFixture):
    def test_temporary_listing_paths_do_not_change_candidate_plan_identity(self):
        import testing_inventory as inventory
        runner=dict(id='fixture',command=[sys.executable,'-c',"print('RUN 001/001 fixture\\n  route: flutter test sample_test.dart')"],
                    required_paths=[],format='full_routes',temporary_output=True)
        a=inventory.list_runner(self.root,runner)
        b=inventory.list_runner(self.root,runner)
        self.assertEqual(a['command'],b['command'])
        self.assertEqual(a['command'],runner['command'])

    def test_new_full_only_capability_is_a_gap_and_selected_profile_is_part_of_identity(self):
        self.rules['full_commands']=[]
        self.rules['full_inventory']=dict(automatic=[],exclusions=[],catalogs=[],listings=[],mappings=[])
        self.write('tool/sims/critical_features.json',json.dumps({'capabilities':[
            dict(id='future',modes=['full'],active=True,buildProfile='android.main',command=['dart','future.dart'])]}))
        plan,_=checks.make_full_plan(self.args(),self.root,self.rules,capture_toolchains=False)
        future=next(r for r in plan['obligations'] if r['selector']=='future')
        self.assertEqual(future['status'],'UNMAPPED')
        self.rules['full_commands']=[dict(id='selected',kind='sims',capability='future',sims_mode='full',command=['dart','tool/sims/sims.dart','full','--only','future'])]
        plan,_=checks.make_full_plan(self.args(),self.root,self.rules,capture_toolchains=False)
        future=next(r for r in plan['obligations'] if r['selector']=='future')
        self.assertEqual(future['variant'],'android.main')
        self.assertEqual(future['status'],'SELECTED')


class SchedulerBoundaryTest(FullExecutionFixture):
    def test_omitted_rows_do_not_inflate_execution_concurrency(self):
        _, report = self.run_full([self.task(n, ['isolated:'+n]) for n in ['a','b','c']], 3, only='a,b')
        self.assertEqual(report['scheduling']['max_observed_concurrency'],2)
        self.assertEqual(next(r for r in report['results'] if r['id']=='c')['status'],'NOT RUN')

    def test_host_postprocessing_dependency_can_follow_a_device_fixture(self):
        self.rules['full_commands'] = [self.task('setup', ['isolated:setup']),
            dict(id='device', kind='sims', command=[sys.executable,'device_fixture.py'],
                 capability='fixture', timeout_seconds=10, dependencies=['setup'], device_roles=[], resources=['device:fixture']),
            self.task('post', ['isolated:post'], dependencies=['device'])]
        self.write('device_fixture.py', "import json,os; from pathlib import Path; assert 2+2==4; Path(os.environ['SIMS_REPORT_PATH']).write_text(json.dumps({'verdicts':[{'capabilityId':'fixture','status':'PASS','assertionsAttempted':1,'artifactPresent':True,'exitCode':0,'printOnly':False,'blocker':None}]}))")
        args=self.args(jobs=3)
        plan,files=checks.make_full_plan(args,self.root,self.rules,capture_toolchains=False)
        for row in plan['selected']:row['blocked_prerequisites']=[]
        out=self.root/'.codex-test-logs/device-post';out.mkdir(parents=True)
        real_launch=checks.launch
        def launch(command,cwd,timeout,env=None):
            if command[0]=='dart':
                self.assertIn('verify-report',command)
                command=[sys.executable,'-c',"import json,sys; assert json.load(open(sys.argv[1]))['verdicts'][0]['assertionsAttempted']==1",command[-1]]
            return real_launch(command,cwd,timeout,env)
        with mock.patch.object(checks,'launch',side_effect=launch), contextlib.redirect_stdout(io.StringIO()):
            code=checks.execute_plan(args,self.root,self.rules,plan,files,{}, {},out,time.monotonic())
        self.assertEqual(code,0)
        report=json.loads((out/'results.json').read_text())
        self.assertTrue(all(r['status']=='PASS' for r in report['results']))
