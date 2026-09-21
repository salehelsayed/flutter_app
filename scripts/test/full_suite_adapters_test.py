"""Executable fixture contracts for full-suite adapters (no live devices)."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
_LOCAL_DART = ROOT / '.codex-test-logs/runtime-tools/dart'
DART = _LOCAL_DART if _LOCAL_DART.exists() else Path(shutil.which('dart') or '/unavailable/dart')


class GroupFullAdapterTest(unittest.TestCase):
    def run_adapter(self, mode, partial=False):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            shim = base / 'dart'
            shim.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
Path(os.environ['ARGV_LOG']).write_text(json.dumps(sys.argv[1:]))
ids=json.loads(os.environ['SCENARIOS'])
if os.environ.get('PARTIAL')=='1':ids=ids[:-1]
path=os.environ.get('GMP_SWEEP_REPORT')
if path:Path(path).write_text(json.dumps({'scenarios':[{'scenario':s,'passed':True} for s in ids]}))
''')
            shim.chmod(0o755)
            app = base / 'Runner.app'; app.mkdir(); (app/'Info.plist').touch()
            source=(ROOT/'integration_test/scripts/group_multi_party_device_criteria.dart').read_text()
            ids=re.findall("^  '([^']+)':",source.split('const _scenarioRequirements =',1)[1].split('};',1)[0],re.M)
            ids.remove('all')
            if mode=='smoke':
                ids=re.findall("'([^']+)'",source.split('const smokeGroupMultiPartyDeviceScenarioIds = <String>[',1)[1].split('];',1)[0])
            env={**os.environ, 'PATH':str(base)+os.pathsep+os.environ['PATH'],
                 'MKNOON_RELAY_ADDRESSES':'127.0.0.1:4001','SIMS_ARTIFACT_IOS_SIMULATOR_E2E':str(app),
                 'SIMS_PROOF_DIRECTORY':str(base/'proof'), 'ARGV_LOG':str(base/'argv'),
                 'SCENARIOS':json.dumps(ids),'PARTIAL':str(int(partial))}
            targets=[f'{i}'*8+'-'+f'{i}'*4+'-'+f'{i}'*4+'-'+f'{i}'*4+'-'+f'{i}'*12 for i in range(1,5)]
            for key,value in zip('ABCD',targets):env[f'SIMS_IOS_SIMULATOR_{key}_DEVICE_ID']=value
            env['SIMS_IOS_DISPOSABLE_SIMULATOR_IDS']=','.join(targets)
            result=subprocess.run([str(DART),'integration_test/scripts/run_group_multi_party_sims.dart','--scenario',mode],cwd=ROOT,env=env,text=True,capture_output=True)
            self.assertIn('SIMS_RESULT_JSON=',result.stdout,result.stderr)
            payload=json.loads(result.stdout.split('SIMS_RESULT_JSON=')[-1])
            proof=json.loads(Path(payload['artifactEvidence']['path']).read_text()) if 'artifactEvidence' in payload else None
            return result.returncode,payload,json.loads((base/'argv').read_text()),proof

    @unittest.skipUnless(DART.exists(), 'real Dart SDK launcher required')
    def test_full_pass_requires_all_109_terminal_scenarios(self):
        code,payload,argv,proof=self.run_adapter('all')
        self.assertEqual(code,0,payload)
        self.assertEqual(argv[argv.index('--scenario')+1],'all')
        self.assertEqual(payload['assertionsAttempted'],109)
        self.assertIn('scenarioResults',json.dumps(proof))

    @unittest.skipUnless(DART.exists(), 'real Dart SDK launcher required')
    def test_successful_child_with_missing_scenario_is_blocked(self):
        code,payload,_,_=self.run_adapter('all',partial=True)
        self.assertNotEqual(code,0)
        self.assertEqual(payload['status'],'BLOCKED')
        self.assertEqual(payload['blocker'],'missingArtifact')

class RuntimeAdapterTest(unittest.TestCase):
    def module(self):
        import sys
        sys.path.insert(0,str(ROOT/'scripts'))
        import full_suite_adapters
        return full_suite_adapters

    def test_config_and_pinned_target_are_bound_without_shell_interpolation(self):
        m=self.module()
        check={'id':'reaction','device_roles':['android_physical','android_emulator'],
               'required_config':['service_account'], 'config_files':['service_account'],
               'steps':[{'command':['dart','run','runner.dart','--scenario','singleton','--recipient','{device:android_physical}',
                                    '--sender','{device:android_emulator}','--service-account','{config:service_account}','--artifact-dir','{output}'],
                         'format':'marker','marker':'validated singleton'}]}
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'credentials with spaces.json';path.write_text('{}')
            config={'isolated_test_environment':True,'fixture_reference':'fixture',
                    'devices':{'android_physical':'phone','android_emulator':'emulator-1'},
                    'full_suite':{'service_account':str(path)}}
            matrix={'flutter':[{'id':'phone','targetPlatform':'android-arm64','emulator':False},
                              {'id':'emulator-1','targetPlatform':'android-x64','emulator':True}], 'adb':['phone','emulator-1']}
            self.assertEqual(m.prerequisites(check,config,matrix),[])
            steps,env=m.bind(check,config,ROOT,Path(tmp)/'out')
            self.assertIn(str(path),steps[0]['command'])
            self.assertEqual(steps[0]['command'][steps[0]['command'].index('--scenario')+1],'singleton')
            self.assertEqual(steps[0]['command'][-1],str(Path(tmp)/'out'))
            config['full_suite']={}
            self.assertIn('full_suite.service_account required',m.prerequisites(check,config,matrix))

    def test_unavailable_optional_hardware_is_na_but_discovery_error_is_blocked(self):
        m=self.module();check={'device_roles':['ios_physical']}
        self.assertEqual(m.availability(check,{}, {'flutter':[],'errors':[]}), 'N/A')
        self.assertEqual(m.availability(check,{}, {'errors':['flutter discovery failed']}),'BLOCKED')

    def test_zero_exit_does_not_replace_test_completion(self):
        m=self.module()
        with tempfile.TemporaryDirectory() as tmp:
            step={'format':'xctest','selectors':['Example/testOne']}
            self.assertEqual(m.inspect(step,'** TEST SUCCEEDED **',0,False,Path(tmp))['status'],'BLOCKED')
            out="Test Case '-[RunnerTests.Example testOne]' passed (0.01 seconds).\nExecuted 1 test, with 0 failures"
            self.assertEqual(m.inspect(step,out,0,False,Path(tmp))['status'],'PASS')
            self.assertEqual(m.inspect(step,out.replace('passed','skipped'),0,False,Path(tmp))['status'],'BLOCKED')

    def test_junit_requires_exact_class_and_fresh_nonzero_results(self):
        m=self.module()
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p=root/'TEST-Plugin.xml'
            step={'format':'junit','report_glob':'TEST-*.xml','classes':['Plugin']}
            self.assertEqual(m.inspect(step,'BUILD SUCCESSFUL',0,False,root)['status'],'BLOCKED')
            p.write_text('<testsuite tests="1"><testcase classname="Plugin" name="assertion"/></testsuite>')
            self.assertEqual(m.inspect(step,'BUILD SUCCESSFUL',0,False,root)['status'],'PASS')
            p.write_text('<testsuite tests="1"><testcase classname="Other" name="assertion"/></testsuite>')
            self.assertEqual(m.inspect(step,'BUILD SUCCESSFUL',0,False,root)['status'],'BLOCKED')

import sys
sys.path.insert(0,str(ROOT/'scripts/test'))
from mknoon_full_checks_test import FullExecutionFixture


class AdapterCLITest(FullExecutionFixture):
    def test_existing_full_cli_executes_adapter_steps_and_retains_completion(self):
        self.write('contract.py',"from pathlib import Path\nPath('.codex-test-logs/proof').write_text('executed')\nprint('EXACT ASSERTIONS COMPLETE')\n")
        task={'id':'adapter','kind':'full_adapter','command':['python3','contract.py'],
              'steps':[{'command':[sys.executable,'contract.py'],'format':'marker','marker':'EXACT ASSERTIONS COMPLETE'}],
              'boundary':'real fixture subprocess','timeout_seconds':10,'resources':['isolated:adapter']}
        code,report=self.run_full([task])
        self.assertEqual(code,0,report)
        self.assertTrue((self.root/'.codex-test-logs/proof').exists())
        self.assertTrue(report['results'][0]['attempts'][0]['step_results'][0]['completion_observed'])

    def test_missing_step_completion_stops_dependent_adapter_step(self):
        self.write('empty.py','pass\n')
        self.write('later.py',"from pathlib import Path\nPath('.codex-test-logs/later').touch()\nprint('done')\n")
        task={'id':'adapter','kind':'full_adapter','command':[sys.executable,'empty.py'],
              'steps':[{'command':[sys.executable,'empty.py'],'format':'marker','marker':'done'},
                       {'command':[sys.executable,'later.py'],'format':'marker','marker':'done'}],
              'boundary':'fixture','timeout_seconds':10,'resources':['isolated:adapter']}
        code,report=self.run_full([task])
        self.assertNotEqual(code,0)
        self.assertFalse((self.root/'.codex-test-logs/later').exists())
        self.assertEqual(report['results'][0]['status'],'BLOCKED')

class MetadataCoverageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rules=json.loads((ROOT/'tool/testing/selection.json').read_text())

    def test_full_group_mode_and_exact_catalogue_are_selected(self):
        major=next(c for c in self.rules['full_commands'] if c['id']=='full-sims-major')
        self.assertEqual(major.get('environment',{}).get('SIMS_GROUP_MULTI_PARTY_SCENARIO'),'all')
        catalog=next(c for c in self.rules['full_inventory']['catalogs'] if 'group_multi_party_device_criteria' in c['path'])
        self.assertEqual(catalog['start'],'const _scenarioRequirements =')
        self.assertIn('all',catalog['exclude_selectors'])

    def test_exact_reaction_singletons_and_performance_variants(self):
        checks=self.rules['full_commands']
        commands=[step['command'] for c in checks for step in c.get('steps',[])]
        for selector in ['head_provenance','android_background_crypto_preflight','android_first_wake_profile_aot',
                         'android_durable_reaction_background_connected','android_message_unread_lifecycle',
                         'android_physical_recipient','ios_physical_recipient',
                         'ios_announcement_reaction_recipient','ios_chat_group_message_and_reaction_recipient']:
            matches=[c for c in commands if '--scenario' in c and c[c.index('--scenario')+1]==selector]
            self.assertEqual(len(matches),1,selector)
            self.assertIn('--recipient',matches[0]);self.assertIn('--artifact-dir',matches[0])
        first=next(c for c in commands if 'android_first_wake_profile_aot' in c)
        self.assertIn('--require-alert',first)
        for selector in ['FEED_INIT','SHELL_SWITCH','FEED_ORBIT_OFFSCREEN','CONVERSATION','CONVERSATION_SUB','ORBIT']:
            match=[c for c in commands if '--dart-define=PERF_TARGET='+selector in c]
            self.assertEqual(len(match),1,selector)
            self.assertIn('{device:macos}',match[0])
        self.assertFalse(any('--dart-define=PERF_TARGET=FEED' in c for c in commands))

    def test_native_proof_wrappers_and_contract_mains_have_executable_owners(self):
        text=json.dumps([c.get('steps') for c in self.rules['full_commands']])
        for path in ['run_app_visibility_native_371.sh','run_ios_nse_native_373.sh','run_android_headless_recovery_native_374.sh',
                     'run_app_visibility_android_e2e.sh','ios_receiver_bootstrap_contract_test.dart',
                     'ios_sender_projection_fixture_contract_test.dart',':background_push_crypto:testDebugUnitTest']:
            self.assertIn(path,text)

class BenchmarkAdapterTest(unittest.TestCase):
    def test_benchmark_suite_propagates_failed_or_empty_child_before_completion(self):
        for body in ['exit 7', 'exit 0']:
            with tempfile.TemporaryDirectory() as tmp:
                shim=Path(tmp)/'flutter';shim.write_text('#!/bin/sh\n'+body+'\n');shim.chmod(0o755)
                result=subprocess.run([str(DART),'integration_test/scripts/run_benchmark_suite.dart','-d','fixture-simulator','--scenarios','B','--fixture-dir',tmp],cwd=ROOT,env={**os.environ,'PATH':tmp+os.pathsep+os.environ['PATH']},text=True,capture_output=True)
                self.assertNotEqual(result.returncode,0,result.stdout)
                self.assertNotIn('FULL_BENCHMARK_COMPLETED',result.stdout)

class XCTestBindingTest(unittest.TestCase):
    def test_fresh_xctestrun_receives_exact_fixture_environment_and_selector(self):
        import plistlib
        import full_suite_adapters as m
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);products=root/'build/Build/Products';products.mkdir(parents=True)
            original=products/'Runner.xctestrun';original.write_bytes(plistlib.dumps({'RunnerUITests':{'EnvironmentVariables':{'BASE':'kept'}},'RunnerTests':{}}))
            fixture=root/'fixture.json';fixture.write_text(json.dumps({'NotificationTapUITests/testNotificationTap':{'environment':{'MKNOON_APNS_TAP_EXPECTED_TITLE':'fixture title'},'target_id':'phone'}}))
            step={'xctest_fixture':str(fixture),'selectors':['NotificationTapUITests/testNotificationTap'],
                  'xctestrun_directory':str(products),'xctestrun_output':str(root/'active.xctestrun'),'target_id':'phone'}
            m.prepare_step(step)
            result=plistlib.loads((root/'active.xctestrun').read_bytes())
            self.assertEqual(result['RunnerUITests']['EnvironmentVariables'],{'BASE':'kept','MKNOON_APNS_TAP_EXPECTED_TITLE':'fixture title'})
            self.assertEqual(plistlib.loads(original.read_bytes())['RunnerUITests']['EnvironmentVariables'],{'BASE':'kept'})
            step['target_id']='other'
            with self.assertRaisesRegex(ValueError,'target'):m.prepare_step(step)

class CanonicalHostTest(unittest.TestCase):
    def test_gate_host_alias_keeps_default_execution_and_full_skips_exact_host_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp);shim=base/'flutter';log=base/'calls';shim.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALL_LOG"\n');shim.chmod(0o755)
            env={**os.environ,'PATH':tmp+os.pathsep+os.environ['PATH'],'CALL_LOG':str(log)}
            normal=subprocess.run(['bash','scripts/run_test_gates.sh','baseline'],cwd=ROOT,env=env,text=True,capture_output=True)
            self.assertEqual(normal.returncode,0,normal.stderr);self.assertIn('test/core/',log.read_text())
            log.unlink()
            alias=subprocess.run(['bash','scripts/run_test_gates.sh','baseline'],cwd=ROOT,env={**env,'MKNOON_FULL_HOST_OWNER':'host.dart.all'},text=True,capture_output=True)
            self.assertEqual(alias.returncode,0,alias.stderr)
            calls=log.read_text()
            self.assertNotIn('test test/',calls,'full gate repeats canonical host tests')
            self.assertIn('integration_test/posts_phase1_fake_test.dart',calls)
            self.assertIn('integration_test/loading_states_smoke_test.dart',calls)
            self.assertIn('HOST_RESULT_ALIAS host.dart.all test/',alias.stdout)

class AdapterBoundaryTest(FullExecutionFixture):
    def test_missing_optional_target_is_na_and_never_launches(self):
        import contextlib,io,time
        from unittest import mock
        from mknoon_checks_test import checks
        task={'id':'ios','kind':'full_adapter','command':[sys.executable,'-c','raise SystemExit(9)'],
              'steps':[{'command':[sys.executable,'-c','raise SystemExit(9)'],'format':'marker','marker':'proof'}],
              'device_roles':['ios_physical'],'boundary':'optional native target','timeout_seconds':10,'resources':['unknown']}
        self.rules['full_commands']=[task]
        self.write('tool/testing/selection.json',json.dumps(self.rules))
        config=self.write('.codex-test-logs/devices.json',json.dumps({'isolated_test_environment':True,'fixture_reference':'fixture','devices':{}}))
        output=self.root/'.codex-test-logs/na'
        with mock.patch.object(checks,'ROOT',self.root),mock.patch.object(checks,'toolchain_identity',return_value={}),mock.patch.object(checks,'devices',return_value={'flutter':[],'adb':[],'ios_simulators':[],'errors':[]}),contextlib.redirect_stdout(io.StringIO()):
            code=checks.main(['full','--base',self.base,'--local','--device-config',str(config),'--output',str(output)])
        report=json.loads((output/'results.json').read_text())
        self.assertEqual(report['results'][0]['status'],'N/A')
        self.assertEqual(report['results'][0]['attempts'],[])
        self.assertEqual(report['results'][0]['checkpoint'],'target_unavailable_by_project_policy')

    def test_complete_sims_owner_alias_uses_exact_capability_result(self):
        from mknoon_checks_test import checks
        obligations=[{'id':'alias','path':'test/a.dart','selector':'gate:A','status':'SELECTED','owners':['major'],'owner_capability':'host.dart.all'}]
        results={'major':{'status':'BLOCKED','attempts':[{'capability_results':[{'id':'host.dart.all','status':'PASS'},{'id':'other','status':'BLOCKED'}]}]}}
        self.assertEqual(checks.obligation_results(obligations,results)[0]['status'],'PASS')
        results['major']['attempts'][0]['capability_results']=[]
        self.assertEqual(checks.obligation_results(obligations,results)[0]['status'],'NOT RUN')

class TargetPolicyTest(unittest.TestCase):
    def test_flutter_darwin_target_is_supported_for_macos_performance(self):
        import full_suite_adapters as m
        matrix={'flutter':[{'id':'macos','targetPlatform':'darwin','emulator':False}],'errors':[]}
        check={'device_roles':['macos']}
        self.assertEqual(m.availability(check,{},matrix),'AVAILABLE')
        config={'isolated_test_environment':True,'fixture_reference':'fixture','devices':{'macos':'macos'}}
        self.assertEqual(m.prerequisites(check,config,matrix),[])

class AdapterLogRetentionTest(FullExecutionFixture):
    def test_preparation_output_survives_later_fixture_failure(self):
        task={'id':'adapter','kind':'full_adapter','command':[sys.executable,'-c',"print('BUILD RECEIPT')"],
              'steps':[{'command':[sys.executable,'-c',"print('BUILD RECEIPT')"],'format':'marker','marker':'BUILD RECEIPT'},
                       {'command':[sys.executable,'-c',"print('not reached')"],'format':'xctest','selectors':['Fixture/testOne'],'xctest_fixture':'/missing-fixture.json'}],
              'boundary':'retained preparation evidence','timeout_seconds':10,'resources':['isolated:adapter']}
        code,report=self.run_full([task])
        self.assertNotEqual(code,0)
        logs=list((self.root/'.codex-test-logs').rglob('adapter-1.raw.log'))
        self.assertEqual(len(logs),1)
        self.assertIn('BUILD RECEIPT',logs[0].read_text())
        self.assertNotIn('not reached',logs[0].read_text())

class ClassificationSafetyTest(unittest.TestCase):
    def test_standalone_assertion_failure_is_fail_and_compilation_error_is_blocked(self):
        import full_suite_adapters as m
        with tempfile.TemporaryDirectory() as tmp:
            step={'format':'assert_main'}
            result=m.inspect(step,'Unhandled exception:\nBad state: assertion failed\n',255,False,Path(tmp))
            self.assertEqual(result['status'],'FAIL')
            self.assertEqual(m.inspect(step,'Error: import could not be resolved',255,False,Path(tmp))['status'],'BLOCKED')

    def test_changed_support_source_invalidates_its_exclusion(self):
        import testing_inventory
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'empty_test.dart').write_text('void main() {}')
            rules={'full_inventory':{'exclusions':[{'pattern':'empty_test.dart','reason':'empty template','source_sha256':'0'*64}]}}
            errors=testing_inventory.validate_policy(root,rules,['empty_test.dart'])
            self.assertTrue(any('source' in e.lower() for e in errors),errors)

class ChangedStandaloneContractTest(unittest.TestCase):
    def test_changed_assertion_mains_reuse_exact_adapters_and_unknown_tests_fail_closed(self):
        import copy
        from mknoon_checks_test import checks
        rules=json.loads((ROOT/'tool/testing/selection.json').read_text())
        paths=['scripts/test/ios_receiver_bootstrap_contract_test.dart','scripts/test/ios_sender_projection_fixture_contract_test.dart']
        result=checks.select(copy.deepcopy(rules),[{'path':p,'status':'M'} for p in paths],'change',paths,ROOT)
        self.assertEqual(result['unmapped_changes'],[])
        for path in paths:
            matches=[c for c in result['selected'] if c.get('kind')=='full_adapter' and c['command']==['dart','--enable-asserts',path]]
            self.assertEqual(len(matches),1,path)
        unknown='scripts/test/new_unowned_test.dart'
        result=checks.select(copy.deepcopy(rules),[{'path':unknown,'status':'A'}],'change',[unknown],ROOT)
        self.assertEqual(result['unmapped_changes'],[unknown])

    @unittest.skipUnless(DART.exists(), 'real Dart SDK launcher required')
    def test_both_current_standalone_contracts_execute_with_assertions(self):
        for path in ['scripts/test/ios_receiver_bootstrap_contract_test.dart','scripts/test/ios_sender_projection_fixture_contract_test.dart']:
            with self.subTest(path=path):
                result=subprocess.run([str(DART),'--enable-asserts',path],cwd=ROOT,text=True,capture_output=True)
                self.assertEqual(result.returncode,0,result.stderr)
