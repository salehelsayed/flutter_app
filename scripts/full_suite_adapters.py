"""Runtime bindings and proof readers used by mknoon_checks' existing executor.

Recipes live in selection.json. This module neither schedules work nor discovers
new commands from operator configuration. Every subprocess stays under the
wrapper's build/device leases, cancellation, raw-log and cleanup barriers.
"""
import copy
from collections import Counter
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET


def _matches(role, row, matrix):
    platform = row.get('targetPlatform', '')
    if role.startswith('android'):
        return (platform.startswith('android') and row['id'] in matrix.get('adb', [])
                and bool(row.get('emulator')) == ('emulator' in role))
    if role.startswith('ios'):
        return (platform == 'ios' and bool(row.get('emulator')) == ('simulator' in role)
                and ('simulator' not in role or row['id'] in matrix.get('ios_simulators', [])))
    if role == 'macos': return platform in ('darwin','macos')
    return platform.startswith(role)


def availability(check, config, matrix):
    roles = check.get('device_roles', [])
    if not roles: return 'AVAILABLE'
    if matrix.get('errors') or 'flutter' not in matrix: return 'BLOCKED'
    for role in roles:
        available = _available_targets(check, role, matrix)
        pinned = config.get('devices', {}).get(role)
        if pinned and pinned not in available: return 'BLOCKED'
        if not available: return 'N/A'
    return 'AVAILABLE'


def _available_targets(check, role, matrix):
    # The native wrappers can boot their one leased simulator. Flutter's list
    # may omit an available shutdown simulator; simctl is authoritative here.
    if (role == 'ios_simulator' and 'MKNOON_NATIVE_IOS_SIMULATOR_ID' in check.get('environment', {})
            and 'native_ios_simulators' in matrix):
        return set(matrix['native_ios_simulators'])
    return {row['id'] for row in matrix.get('flutter', []) if _matches(role, row, matrix)}


def settings(check, config):
    values = dict(config.get('full_suite', {}))
    values.update(values.get('adapters', {}).get(check.get('id'), {}))
    return values


def prerequisites(check, config, matrix):
    errors = []
    if check.get('device_roles'):
        if config.get('isolated_test_environment') is not True:
            errors.append('isolated device/account/service configuration required')
        if not config.get('fixture_reference'): errors.append('fixture reference required')
        ids = config.get('devices', {})
        for role in check['device_roles']:
            target = ids.get(role)
            if not target: errors.append('pinned devices.' + role + ' required')
            elif target not in _available_targets(check, role, matrix):
                errors.append('pinned target not live or wrong platform: ' + role)
        targets=[ids[r] for r in check['device_roles'] if r in ids]
        if len(set(targets)) != len(targets): errors.append('device roles must be distinct')
    values=settings(check, config)
    for key in check.get('required_config', []):
        if not isinstance(values.get(key),str) or not values[key].strip():
            errors.append('full_suite.'+key+' required')
    for key in check.get('config_files', []):
        if values.get(key) and not Path(values[key]).is_file(): errors.append('full_suite.'+key+' must be a readable file')
    if check.get('xctest_fixture_selector') and values.get('ios_ui_fixtures'):
        try:
            data=json.loads(Path(values['ios_ui_fixtures']).read_text())
            selector=check['xctest_fixture_selector']
            fixture=data.get(selector)
            if not isinstance(fixture,dict): errors.append('ios_ui_fixtures missing exact selector: '+selector)
            elif fixture.get('target_id') not in [config.get('devices',{}).get(r) for r in check.get('device_roles',[])]:
                errors.append('ios_ui_fixtures target mismatch: '+selector)
        except (OSError, ValueError): errors.append('ios_ui_fixtures must contain valid fixture JSON')
    return errors


def bind(check, config, root, output):
    configured=settings(check,config)
    def value(text):
        def replace(match):
            key=match[1]
            if key=='root': return str(root)
            if key=='output': return str(output)
            category,name=key.split(':',1)
            return str(config['devices'][name] if category=='device' else configured[name])
        return re.sub(r'\{(root|output|(?:device|config):[A-Za-z0-9_.-]+)\}',replace,text)
    steps=copy.deepcopy(check['steps'])
    for step in steps:
        step['command']=[value(v) for v in step['command']]
        for key in ('cwd','report_glob','marker','xctest_fixture','xctestrun_directory','xctestrun_output','target_id'):
            if key in step: step[key]=value(step[key])
    return steps, {k:value(v) for k,v in check.get('environment',{}).items()}


def native_xctest_receipts(output, expected):
    """Require the complete source-declared native selector multiset."""
    if (not isinstance(expected, dict) or not expected or
            any(not isinstance(k, str) or type(v) is not int or v <= 0
                for k, v in expected.items())):
        return None
    passed = Counter(c+'/'+m for c,m in re.findall(
        r"Test Case '-\[(?:\w+\.)?(\w+) (\w+)\]' passed", output))
    if (passed != Counter(expected) or
            re.search(r"Test Case .* (?:failed|skipped)|Executed 0 tests", output)):
        return None
    return [{'id':'xctest:'+selector, 'status':'PASS',
             'counts':{'passed':count,'failed':0,'skipped':0}}
            for selector,count in sorted(expected.items())]


def inspect(step, output, code, timeout, root):
    from mknoon_checks import parse_execution
    fmt=step['format']
    if fmt in ('flutter','python','node','go'):
        proof = parse_execution(fmt, output, code, timeout, step.get('paths',[]))
        # Adapter output and XCTest fixture data are private. Only source-owned
        # paths and typed/hash facts may survive into shared per-step evidence.
        paths = set(step.get('paths', [])) | {p for p in step.get('command', [])
                                               if p.endswith('.dart') and not p.startswith('-')}
        for collection in ('failed_cases', 'skipped_cases'):
            safe = []
            for case in proof.get(collection, []):
                item = {k:v for k,v in case.items() if
                        (k.endswith('_sha256') and isinstance(v,str) and re.fullmatch('[0-9a-f]{64}',v)) or
                        (k in ('test_id','line','column') and type(v) is int and v >= 0)}
                for key in ('suite_path','reported_location'):
                    value = case.get(key)
                    if value in paths: item[key] = value
                safe.append(item)
            proof[collection] = safe
        proof['compilation_diagnostics'] = [item for item in proof.get('compilation_diagnostics', [])
                                            if item.get('source_path') in paths]
        return proof
    result={'status':'BLOCKED','checkpoint':'incomplete_adapter_proof','completion_observed':False,
            'counts':{'passed':0,'failed':0,'skipped':0}}
    if timeout: return {**result,'checkpoint':'runner_timeout'}
    if 'ROUTING_PATHS/R-Sim-3: requires orchestrator' in output:
        return {**result,'checkpoint':'benchmark_routing_unregister_prerequisite'}
    if code:
        if fmt=='assert_main' and re.search(r'Unhandled exception:\s*(?:Bad state:|.*AssertionError)',output):
            result['counts']['failed']=1
            return {**result,'status':'FAIL','checkpoint':'contract_assertion_failed','exit_status':code}
        result.update(checkpoint='adapter_process_failed',exit_status=code)
        # Gradle exits nonzero for actual test failures too. Preserve the exact
        # JUnit assertion evidence before classifying a process failure.
        if fmt!='junit': return result
    if fmt=='build':
        if not step.get('expected_files') or not all((Path(root)/p).is_file() for p in step['expected_files']): return result
        return {**result,'status':'PASS','checkpoint':'build_preparation_completed','preparation_only':True}
    if fmt=='assert_main':
        # These exact source-owned mains throw on assertion failure and return
        # normally only after their complete synchronous/awaited checks finish.
        result['counts']['passed']=1
    elif fmt=='marker':
        if step['marker'] not in output: return result
        if re.search(r'\[(?:SKIP|BLOCKED)\]', output): return result
        if re.search(r'No tests ran|Executed 0 tests|\b[1-9]\d* (?:tests? )?skipped|"skipped"\s*:\s*true',output,re.I): return result
        result['counts']['passed']=1
        if 'native_xctest_counts' in step:
            expected = step['native_xctest_counts']
            receipts = native_xctest_receipts(output, expected)
            if receipts is None:
                return {**result, 'checkpoint':'incomplete_native_xctest_proof',
                        'counts':{'passed':0,'failed':0,'skipped':0}}
            result['route_results'] = receipts
    elif fmt=='xctest':
        passed=re.findall(r"Test Case '-\[(?:\w+\.)?(\w+) (\w+)\]' passed",output)
        expected=set(step['selectors'])
        observed={c+'/'+m for c,m in passed}
        if not expected or observed != expected or len(passed)!=len(expected): return result
        if re.search(r"Test Case .* (?:failed|skipped)|Executed 0 tests",output): return result
        result['counts']['passed']=len(passed)
    elif fmt=='junit':
        cases=[]
        for file in Path(root).glob(step['report_glob']):
            cases.extend(ET.parse(file).getroot().findall('.//testcase'))
        expected=set(step['classes'])
        if not cases or {c.get('classname') for c in cases} != expected: return result
        for case in cases:
            key='failed' if case.find('failure') is not None or case.find('error') is not None else 'skipped' if case.find('skipped') is not None else 'passed'
            result['counts'][key]+=1
        if result['counts']['failed']: return {**result,'status':'FAIL','checkpoint':'native_assertion_failed'}
        if result['counts']['skipped']: return result
        if code: return result
    else: raise ValueError('Unknown adapter proof format: '+fmt)
    return {**result,'status':'PASS','checkpoint':'adapter_assertions_completed','completion_observed':True}


def validate(check, root):
    errors=[]
    if not check.get('steps'): errors.append('Adapter needs executable proof steps')
    elif check['steps'][-1].get('format') == 'build': errors.append('Preparation alone is not an executable proof')
    for step in check.get('steps', []):
        if not step.get('command') or step.get('format') not in ('flutter','python','node','go','marker','xctest','junit','assert_main','build'):
            errors.append('Invalid adapter step')
        if step.get('format')=='marker' and not step.get('marker'): errors.append('Missing adapter completion marker')
        if step.get('format')=='xctest' and not step.get('selectors'): errors.append('Missing exact XCTest selectors')
        if 'native_xctest_counts' in step:
            counts = step['native_xctest_counts']
            if (step.get('format') != 'marker' or not isinstance(counts,dict) or not counts or
                    any(not isinstance(k,str) or not re.fullmatch(r'\w+/test\w+',k) or
                        type(v) is not int or v < 1 for k,v in counts.items())):
                errors.append('Native campaign receipts require exact XCTest selectors and positive counts')
        if step.get('format')=='junit' and (not step.get('classes') or not step.get('report_glob')): errors.append('Missing JUnit class/report selection')
        if step.get('format')=='assert_main' and step.get('command',[])[:2] != ['dart','--enable-asserts']:
            errors.append('Assertion mains must enable Dart assertions')
        for value in step.get('command',[]):
            for key in re.findall(r'\{config:([^}]+)\}',value):
                if key not in check.get('required_config',[]): errors.append('Undeclared required config: '+key)
            for role in re.findall(r'\{device:([^}]+)\}',value):
                if role not in check.get('device_roles',[]): errors.append('Undeclared device role: '+role)
    return errors


def prepare_step(step):
    """Populate a fresh, this-invocation XCTest product with explicit fixture data.

    No installed/prebuilt app is accepted as a cache hit. xcodebuild's preceding
    build-for-testing step owns the products in a fresh private DerivedData path.
    UI fixture values are private and never copied into the shared result ledger.
    """
    if not step.get('xctest_fixture'): return
    import plistlib
    fixtures=json.loads(Path(step['xctest_fixture']).read_text())
    selector=step['selectors'][0]
    fixture=fixtures.get(selector)
    if not isinstance(fixture,dict): raise ValueError('XCTest fixture missing exact selector: '+selector)
    if fixture.get('target_id') != step['target_id']: raise ValueError('XCTest fixture target mismatch')
    values=fixture.get('environment')
    if not isinstance(values,dict) or any(not isinstance(k,str) or not k.startswith('MKNOON_') or not isinstance(v,str) for k,v in values.items()):
        raise ValueError('XCTest fixture requires string MKNOON_ environment entries')
    products=list(Path(step['xctestrun_directory']).glob('*.xctestrun'))
    if len(products)!=1: raise ValueError('Expected exactly one freshly built xctestrun')
    data=plistlib.loads(products[0].read_bytes())
    targets=[data['RunnerUITests']] if 'RunnerUITests' in data else [
        target for configuration in data.get('TestConfigurations',[])
        for target in configuration.get('TestTargets',[]) if target.get('BlueprintName')=='RunnerUITests']
    if len(targets)!=1: raise ValueError('Fresh xctestrun omitted exact RunnerUITests target')
    target=targets[0]
    target.setdefault('EnvironmentVariables',{}).update(values)
    target['OnlyTestIdentifiers']=[selector]
    # __TESTROOT__ is relative to the xctestrun, so keep the patched copy beside
    # the build products rather than moving it into a different directory.
    destination=Path(step['xctestrun_output'])
    def anchor(value):
        if isinstance(value,str):return value.replace('__TESTROOT__',str(products[0].parent))
        if isinstance(value,list):return [anchor(v) for v in value]
        if isinstance(value,dict):return {k:anchor(v) for k,v in value.items()}
        return value
    destination.write_bytes(plistlib.dumps(anchor(data)))
    destination.chmod(0o600)
