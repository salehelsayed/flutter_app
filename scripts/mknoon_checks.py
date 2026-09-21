#!/usr/bin/env python3
"""Deterministic selection and evidence adapter for Mknoon's existing runners.

No network calls, LLM, database, or automatic retries. Raw process output is never
copied into shareable reports; structured completion facts are allowlisted.
"""
from __future__ import annotations

import argparse
from contextlib import ExitStack
from concurrent.futures import ThreadPoolExecutor, wait, FIRST_COMPLETED
import threading
import device_campaign_preflight as device_preflight
import datetime as dt
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
RULES = Path('tool/testing/selection.json')
SIMS = Path('tool/sims/critical_features.json')
EXIT = {'PASS': 0, 'FAIL': 1, 'BLOCKED': 2, 'NOT RUN': 3}
_LAUNCH_CONTEXT = threading.local()


class InvalidPlan(ValueError):
    pass


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def file_hash(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def git(root, *args):
    p = subprocess.run(['git', *args], cwd=root, capture_output=True, timeout=60)
    if p.returncode:
        raise InvalidPlan('Git baseline/candidate operation failed: ' + args[0])
    return p.stdout


def source_files(root):
    from testing_inventory import source_files as inventory_files
    return inventory_files(root)


def resolve_ref(root, ref):
    if not ref:
        raise InvalidPlan('BLOCKED: supply --base with an explicit verified comparison revision; release mode requires the actually published revision')
    return git(root, 'rev-parse', '--verify', ref + '^{commit}').decode().strip()


def changed_files(root, base, local):
    """Union committed diff, index, worktree and untracked. Retain both rename ends."""
    commands = [('diff', '--name-status', '-z', '--find-renames', base, 'HEAD')]
    if local:
        commands += [('diff', '--name-status', '-z', '--find-renames', 'HEAD'),
                     ('diff', '--cached', '--name-status', '-z', '--find-renames')]
    rows = set()
    for cmd in commands:
        items = git(root, *cmd).split(b'\0')
        i = 0
        while i < len(items) and items[i]:
            status = items[i].decode(); i += 1
            count = 2 if status[0] in 'RC' else 1
            for _ in range(count):
                rows.add((items[i].decode('utf-8', 'surrogateescape'), status)); i += 1
    if local:
        rows.update((p.decode('utf-8', 'surrogateescape'), '?') for p in
                    git(root, 'ls-files', '-z', '--others', '--exclude-standard').split(b'\0') if p)
    return [{'path': p, 'status': s} for p, s in sorted(rows)]


def source_identity(root, files, rules):
    """Hash all tracked build inputs, including local additions, without storing content."""
    inputs = [p for p in files if not any(fnmatch.fnmatchcase(p, pattern)
              for pattern in rules.get('evidence_exclusions', []))]
    hashes = {p: file_hash(root / p) for p in inputs}
    bundle = {p: hashes[p] for p in inputs if p.endswith(('.js', '.mjs', '.cjs', '.aar', '.xcframework'))
              or p in ('pubspec.yaml', 'pubspec.lock', 'tool/build/voice_call_release_defines.json')}
    return {'head': resolve_ref(root, 'HEAD'), 'source_sha256': digest(hashes),
            'input_count': len(inputs), 'bundle_and_config_sha256': bundle,
            'rules_sha256': digest(rules)}


def toolchain_identity(root):
    result = {'python': sys.version.split()[0]}
    for name, args in [('flutter',['--version','--machine']), ('go',['version']), ('node',['--version'])]:
        if not shutil.which(name):
            result[name] = {'available': False}; continue
        try:
            output, code, timed_out, _ = launch([name,*args], root, 30)
            if code or timed_out: raise ValueError()
            if name == 'flutter':
                data = json.loads(output)
                result[name] = {k:data.get(k) for k in ('frameworkVersion','frameworkRevision','engineRevision','dartSdkVersion')}
            else:
                result[name] = {'version': output.strip()}
        except (ValueError,OSError): result[name] = {'available': False}
    config = root / '.dart_tool/package_config.json'
    if config.exists(): result['package_config_sha256'] = file_hash(config)
    return result


def flutter_sdk_mismatch(root):
    config = root / '.dart_tool/package_config.json'
    executable = shutil.which('flutter')
    if not config.is_file() or not executable: return False
    executable = Path(executable).resolve()
    if executable.parent.name != 'bin': return False  # external shim: no invented SDK root
    for package in json.loads(config.read_text()).get('packages', []):
        if package.get('name') != 'flutter': continue
        uri = urlparse(package.get('rootUri',''))
        if uri.scheme == 'file':
            package_root = Path(unquote(uri.path)).resolve()
            return package_root != executable.parent.parent / 'packages/flutter'
    return False


def expand_paths(root, paths, files):
    expanded = set()
    for path in paths:
        if (root / path).is_file():
            expanded.add(path)
        else:
            expanded.update(p for p in files if p.endswith('_test.dart') and
                (p.startswith(path.rstrip('/') + '/') or fnmatch.fnmatchcase(p, path)))
    return sorted(expanded)


def validate(root, rules, files=None):
    files = files if files is not None else source_files(root)
    errors = []
    checks = rules.get('checks', {})
    if rules.get('schema_version') != 1 or not checks:
        errors.append('Invalid schema_version or empty checks')
    for group in ('fast', 'mandatory', 'conservative'):
        if not rules.get(group): errors.append('Empty required selection group: ' + group)
        for cid in rules.get(group, []):
            if cid not in checks: errors.append('Unknown check: ' + cid)
    for area in rules.get('areas', []):
        if not area.get('patterns') or not area.get('why'): errors.append('Incomplete area: ' + area.get('id', '?'))
        for path in area.get('exclude_paths', []):
            if any(c in path for c in '*?[') or not any(
                    other is not area and any(fnmatch.fnmatchcase(path, p) for p in other['patterns'])
                    and path not in other.get('exclude_paths', []) for other in rules['areas']):
                errors.append('Area exclusions need an exact path with another mapping: ' + path)
        for cid in area.get('checks', []):
            if cid not in checks: errors.append('Unknown area check: ' + cid)
    sims = json.loads((root / SIMS).read_text()) if (root / SIMS).exists() else {'capabilities': []}
    capability_ids = {c['id'] for c in sims['capabilities']}
    for cid, c in checks.items():
        errors.extend(message + ': ' + cid for message in device_preflight.validate_metadata(c))
        if not re.fullmatch(r'[a-z0-9_.-]+', cid): errors.append('Invalid check id: ' + cid)
        if c.get('kind') not in ('flutter', 'python', 'node', 'go', 'sims', 'manual', 'command'):
            errors.append('Unknown runner kind: ' + cid)
        if not c.get('boundary') or c.get('timeout_seconds', 0) <= 0:
            errors.append('Missing boundary/timeout: ' + cid)
        for path in c.get('paths', []):
            matches = expand_paths(root, [path], files)
            if not matches: errors.append('Stale/missing test selector: ' + cid + ': ' + path)
        if c.get('kind') == 'flutter':
            paths = expand_paths(root, c.get('paths', []), files)
            if not paths: errors.append('Empty Flutter selection: ' + cid)
            for name in c.get('names', []):
                if not any(name in (root / p).read_text() for p in paths):
                    errors.append('Stale test name: ' + cid + ': ' + name)
        if c.get('kind') == 'sims' and c.get('capability') not in capability_ids:
            errors.append('Stale SIMS capability: ' + cid)
        if c.get('kind') == 'sims':
            adapter = c.get('adapter')
            if adapter is not None and (not isinstance(adapter, str)
                    or not re.fullmatch(r'integration_test/scripts/[a-z0-9_]+\.dart', adapter)
                    or not (root / adapter).is_file()):
                errors.append('Invalid/missing SIMS fixture adapter: ' + cid)
            package = c.get('disposable_android_package')
            if package is not None and not is_disposable_android_package(package):
                errors.append('Invalid fixed disposable Android package: ' + cid)
            if 'requires_disposable_android_package' in c and (
                    c['requires_disposable_android_package'] is not True or package is not None):
                errors.append('Invalid disposable Android package policy: ' + cid)
            if any(role.startswith('android') for role in c.get('device_roles', [])) and (
                    package is None and c.get('requires_disposable_android_package') is not True):
                errors.append('Android SIMS execution requires a disposable package policy: ' + cid)
            if 'requires_firebase_android_client' in c and (
                    c['requires_firebase_android_client'] is not True or
                    (package is None and c.get('requires_disposable_android_package') is not True)):
                errors.append('Invalid Firebase Android client policy: ' + cid)
        for path in c.get('references', []):
            if not (root / path).exists(): errors.append('Missing proof/reference: ' + path)
        if c.get('kind') == 'command' and not c.get('success_marker'):
            errors.append('Command needs explicit completion marker: ' + cid)
    validate_schedule(rules.get('full_commands', []))
    for c in rules.get('full_commands', []):
        errors.extend(message + ': ' + c.get('id', '?') for message in device_preflight.validate_metadata(c))
        if not re.fullmatch(r'[a-z0-9_.-]+', c.get('id','')) or c.get('kind') not in ('flutter','python','node','go','sims','legacy','command','full_adapter'):
            errors.append('Invalid full check identity/kind: ' + c.get('id','?'))
        if not c.get('command') or c.get('timeout_seconds', 0) <= 0:
            errors.append('Invalid full command: ' + c.get('id', '?'))
        if c.get('kind') == 'full_adapter':
            from full_suite_adapters import validate as validate_adapter
            errors.extend(message + ': ' + c['id'] for message in validate_adapter(c, root))
        for arg in c.get('command', []):
            if arg.startswith(('scripts/', 'tool/')) and not (root / arg).exists():
                errors.append('Stale full command reference: ' + arg)
    if (root / '.agents/skills').exists():
        for name in ('mknoon-change-check','mknoon-release-check','mknoon-test-maintenance'):
            path = root / '.agents/skills' / name / 'SKILL.md'
            if not path.is_file():
                errors.append('Missing workflow skill: ' + name); continue
            text = path.read_text()
            if not text.startswith('---\n') or not re.search(r'^name: ' + re.escape(name) + r'$', text, re.M) or not re.search(r'^description: .+', text, re.M):
                errors.append('Invalid skill metadata: ' + name)
            if 'scripts/mknoon_checks.py' not in text or 'docs/testing/TESTING.md' not in text:
                errors.append('Stale shared workflow reference: ' + name)
    from testing_inventory import validate_policy
    errors.extend(validate_policy(root, rules, files))
    if errors: raise InvalidPlan('\n'.join(errors))
    return files


def select(rules, changes, mode, files, root):
    selected = {}
    areas = set()
    unmapped = []
    excluded = []
    def add(cid, why):
        if mode != 'release' and rules['checks'][cid]['kind'] == 'manual':
            return
        selected.setdefault(cid, []).append(why)
    for cid in rules['fast']: add(cid, 'fast prerequisite')
    if mode == 'release':
        for cid in rules['mandatory']: add(cid, 'mandatory release check')
    for change in changes:
        path = change['path']
        matching = [a for a in rules['areas'] if any(fnmatch.fnmatchcase(path, p) for p in a['patterns'])
                    and path not in a.get('exclude_paths', [])]
        if matching:
            for area in matching:
                areas.add(area['id'])
                for cid in area['checks']: add(cid, path + ': ' + area['why'])
        elif any(fnmatch.fnmatchcase(path, p) for p in rules.get('documentation_only', [])):
            excluded.append(path)
        else:
            unmapped.append(path)
            for cid in rules['conservative']: add(cid, 'unmapped impact: ' + path)
        if path.endswith('_test.dart') and path in files:
            # A changed test is always run, even if it is new or outside a curated list.
            cid = 'changed.' + hashlib.sha256(path.encode()).hexdigest()[:12]
            if path.startswith('test/'):
                rules['checks'][cid] = {'kind': 'flutter', 'paths': [path], 'boundary': 'changed host test',
                    'timeout_seconds': 900, 'estimated_seconds': None, 'investigate': [path]}
                add(cid, 'added/modified/renamed test: ' + path)
            else:
                # Standalone assertion mains are not Flutter package:test files.
                # Reuse only an exact, already validated source-owned recipe;
                # new external test files still require an ownership decision.
                owners = [c for c in rules.get('full_commands', [])
                          if c.get('kind') == 'full_adapter'
                          and c.get('command') == ['dart', '--enable-asserts', path]
                          and len(c.get('steps', [])) == 1
                          and c['steps'][0].get('format') == 'assert_main']
                if len(owners) == 1:
                    owner = owners[0]
                    rules['checks'][owner['id']] = {**owner, 'paths': [path]}
                    add(owner['id'], 'changed standalone assertion main: ' + path)
                else:
                    unmapped.append(path)
    return {'selected': [{'id': cid, 'reasons': sorted(set(why)), **rules['checks'][cid]}
                         for cid, why in sorted(selected.items())],
            'affected_areas': sorted(areas), 'unmapped_changes': sorted(set(unmapped)),
            'documentation_exclusions': sorted(set(excluded)),
            'not_selected': sorted(set(rules['checks']) - set(selected))}


def positive_int(value):
    value = int(value)
    if value < 1 or value > 64: raise argparse.ArgumentTypeError('must be between 1 and 64')
    return value


def command_for(check, root, files):
    kind = check['kind']
    if kind == 'flutter':
        paths = expand_paths(root, check['paths'], files)
        command = ['flutter', 'test', '--no-pub', '--machine', '--concurrency=' + str(check.get('workers', 1)), '--timeout=2m', *paths]
        if check.get('names'): command += ['--name', '|'.join(re.escape(n) for n in check['names'])]
        return command, paths
    if kind == 'python':
        return [sys.executable, '-m', 'unittest', '-v', *check['paths']], check['paths']
    if kind == 'node': return ['node', '--test', '--test-reporter=tap', *check['paths']], check['paths']
    if kind == 'go':
        return ['go', 'test', '-json', '-count=1', '-timeout=10m', *check['packages']], check['packages']
    if kind == 'sims':
        if check.get('adapter'):
            return ['dart', 'run', check['adapter'], '--mode', 'major', '--scenario', check['capability']], [check['capability']]
        return ['dart', 'tool/sims/sims.dart', 'major', '--only', check['capability'],
                '--continue-on-failure', '--format', 'json'], [check['capability']]
    return check.get('command', []), check.get('paths', [])


def parse_execution(kind, output, returncode, timed_out=False, selected_paths=None, success_marker=None):
    """Only observed completion facts leave this function. No log text/test names."""
    counts = {'passed': 0, 'failed': 0, 'skipped': 0}
    completed = False
    first_failure = None
    failed_cases = []
    skipped_cases = []
    first_case_ms = None
    runner_done_ms = None
    compilation_diagnostics = []
    for match in re.finditer(r'([^\s"\\]+\.dart):(\d+):(\d+): Error:', output):
        path = match[1].replace(str(ROOT) + '/', '')
        if path.startswith('/'):
            path = 'external/' + (path.split('/packages/',1)[1] if '/packages/' in path else Path(path).name)
        item = {'source_path':path, 'line':int(match[2]), 'column':int(match[3]), 'error_kind':'compilation_error'}
        if item not in compilation_diagnostics: compilation_diagnostics.append(item)
    observed_paths = set()
    if kind == 'flutter':
        tests, suites = {}, {}
        for line in output.splitlines():
            try: e = json.loads(line)
            except ValueError: continue
            if not isinstance(e, dict): continue
            if e.get('type') == 'suite': suites[e['suite']['id']] = e['suite'].get('path', '')
            if e.get('type') == 'testStart':
                tests[e['test']['id']] = e['test']
                if first_case_ms is None and not e['test'].get('name','').startswith('loading '):
                    first_case_ms = e.get('time')
            if e.get('type') == 'testDone':
                t = tests.get(e.get('testID'), {})
                # Exclude loader and (setUpAll)/(tearDownAll) synthetic successes.
                if t.get('name', '').startswith('loading ') or re.search(r'\((setUpAll|tearDownAll)\)$', t.get('name', '')):
                    if e.get('result') == 'error': first_failure = 'test_runner_startup'
                    continue
                result = 'skipped' if e.get('skipped') else ('passed' if e.get('result') == 'success' else 'failed')
                counts[result] += 1
                if result == 'failed' and first_failure is None: first_failure = 'test_assertion'
                if result in ('failed', 'skipped'):
                    location = t.get('url') or ''
                    if location.startswith('file:'):
                        location = unquote(urlparse(location).path).replace(str(ROOT) + '/', '')
                        if location.startswith('/'): location = 'external/' + Path(location).name
                    cases = failed_cases if result == 'failed' else skipped_cases
                    cases.append({'test_id': e.get('testID'),
                        'suite_path': suites.get(t.get('suiteID'), '').replace(str(ROOT) + '/', ''),
                        'name_sha256': digest(t.get('name', '')),
                        'reported_location': location,
                        'line': t.get('line'), 'column': t.get('column')})
                observed_paths.add(suites.get(t.get('suiteID'), ''))
            if e.get('type') == 'error' and first_failure is None: first_failure = 'test_error'
            if e.get('type') == 'done':
                completed = e.get('success') is True
                runner_done_ms = e.get('time')
        missing = [p for p in selected_paths or [] if not any(q.endswith('/' + p) or q == p for q in observed_paths)]
    elif kind == 'go':
        package_done = set()
        for line in output.splitlines():
            try: e = json.loads(line)
            except ValueError: continue
            if not isinstance(e, dict): continue
            name, package, action = e.get('Test'), e.get('Package'), e.get('Action')
            if isinstance(name, str) and name and action in ('pass', 'fail', 'skip'):
                counts[{'pass':'passed','fail':'failed','skip':'skipped'}[action]] += 1
                if action in ('fail', 'skip'):
                    # Dynamic subtest labels and import paths may contain private
                    # data. Hash both, retaining the discoverable parent identity.
                    cases = failed_cases if action == 'fail' else skipped_cases
                    cases.append({'name_sha256': digest(name),
                        'top_level_name_sha256': digest(name.split('/', 1)[0]),
                        'package_sha256': digest(package)
                            if isinstance(package, str) and package else None})
            if name in (None, '') and action == 'pass' and isinstance(package, str) and package:
                package_done.add(package)
        completed = bool(package_done)
        missing = []
    elif kind == 'python':
        m = re.search(r'Ran (\d+) tests? in ', output)
        n = int(m[1]) if m else 0
        counts['failed'] = sum(int(x) for x in re.findall(r'(?:failures|errors)=(\d+)', output))
        counts['skipped'] = sum(int(x) for x in re.findall(r'skipped=(\d+)', output))
        counts['passed'] = max(0, n - counts['failed'] - counts['skipped'])
        completed = bool(re.search(r'^OK(?: \(.*\))?$', output, re.M))
        missing = []
    elif kind == 'node':
        for key, label in [('passed','pass'),('failed','fail'),('skipped','skipped')]:
            m = re.search(r'^# ' + label + r' (\d+)', output, re.M)
            if m: counts[key] = int(m[1])
        completed = bool(re.search(r'^1\.\.[1-9]\d*$', output, re.M))
        subtests = re.findall(r'^# Subtest: (.+)$', output, re.M)
        if subtests and all(name.endswith(('.js','.cjs','.mjs')) for name in subtests):
            # Node considers an empty test file a passing file-level subtest.
            counts['passed'] = 0
            completed = False
        missing = []
    else:
        completed = bool(success_marker and success_marker in output)
        counts['passed'] = int(completed)
        missing = []
    total = counts['passed'] + counts['failed']
    process_error = bool(re.search(r'(?m)^.*: line \d+: .*?(?:unbound variable|command not found)', output))
    if compilation_diagnostics and not total:
        status, checkpoint = 'BLOCKED', 'compilation_error'
    elif counts['failed'] or (first_failure and first_failure != 'test_runner_startup'):
        status, checkpoint = 'FAIL', first_failure or 'test_assertion'
    elif timed_out:
        status, checkpoint = 'BLOCKED', 'runner_timeout'
    elif process_error:
        status, checkpoint = 'BLOCKED', 'process_error_despite_exit_status'
    elif returncode != 0:
        status, checkpoint = 'BLOCKED', 'compilation_error' if compilation_diagnostics else 'test_runner_startup_or_process_failure'
    elif not completed or not total or missing or counts['skipped']:
        status, checkpoint = 'BLOCKED', 'incomplete_or_zero_test_execution'
    else:
        status, checkpoint = 'PASS', 'runner_completed'
    return {'status': status, 'checkpoint': checkpoint, 'counts': counts,
            'completion_observed': completed, 'missing_test_files': missing,
            'failed_cases': failed_cases, 'skipped_cases': skipped_cases,
            'timed_out': timed_out,
            'compilation_diagnostics': compilation_diagnostics,
            'observed_test_span_seconds': max(0, runner_done_ms - first_case_ms) / 1000
                if isinstance(first_case_ms, (int,float)) and isinstance(runner_done_ms, (int,float)) else None,
            'raw_output_sha256': hashlib.sha256(output.encode()).hexdigest()}


def launch(command, cwd, timeout, env=None):
    """One bounded process group; always kill descendants on timeout/interruption."""
    start = time.monotonic()
    with tempfile.TemporaryFile(mode='w+b') as output:
        p = subprocess.Popen(command, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT,
                             start_new_session=True)
        timed_out = False
        try:
            deadline = start + timeout
            while p.poll() is None:
                cancel = getattr(_LAUNCH_CONTEXT, 'cancel_event', None)
                if cancel is not None and cancel.is_set():
                    raise InterruptedError('run cancelled')
                remaining = deadline - time.monotonic()
                if remaining <= 0: raise subprocess.TimeoutExpired(command, timeout)
                try: p.wait(timeout=min(.1, remaining))
                except subprocess.TimeoutExpired: pass
        except subprocess.TimeoutExpired:
            timed_out = True
            try: os.killpg(p.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            try: p.wait(timeout=3)
            except subprocess.TimeoutExpired:
                pass
            # The leader may have exited while descendants ignored TERM.
            try: os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            p.wait(timeout=5)
        except BaseException as error:
            try: os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            p.wait(timeout=5)
            if not isinstance(error, InterruptedError): raise
            timed_out = True
        output.seek(0)
        data = output.read().decode('utf-8', 'replace')
    return data, p.returncode, timed_out, round(time.monotonic() - start, 3)


def aggregate(attempts):
    """A passing diagnostic rerun cannot erase a failed or blocked first attempt."""
    statuses = [a['status'] for a in attempts]
    for status in ('FAIL', 'BLOCKED', 'NOT RUN'):
        if status in statuses: return status
    return 'N/A' if statuses and set(statuses) == {'N/A'} else 'PASS' if statuses else 'NOT RUN'


def manual_result(check, evidence, identity, root, artifact_hashes):
    row = evidence.get('checks', {}).get(check['id'])
    missing = {'status':'BLOCKED', 'checkpoint':'required_evidence_missing', 'attempts': []}
    if not row: return missing
    if evidence.get('source_sha256') != identity['source_sha256'] or evidence.get('rules_sha256') != identity['rules_sha256']:
        return {**missing, 'checkpoint':'evidence_identity_mismatch'}
    if evidence.get('artifact_sha256') != artifact_hashes or not artifact_hashes:
        return {**missing, 'checkpoint':'signed_artifact_evidence_mismatch'}
    if row.get('status') not in ('PASS', 'FAIL', 'BLOCKED') or not row.get('reviewer') or not row.get('observed_at'):
        return {**missing, 'checkpoint':'evidence_record_incomplete'}
    receipts = row.get('receipts', [])
    required = set(check.get('assertions', []))
    if not receipts: return missing
    if row['status'] == 'PASS' and not required.issubset(set(row.get('assertions_observed', []))): return missing
    if row['status'] == 'FAIL' and row.get('failed_assertion') not in required: return missing
    for receipt in receipts:
        p = root / receipt.get('path', '')
        if not p.is_file() or file_hash(p) != receipt.get('sha256'):
            return {**missing, 'checkpoint':'evidence_receipt_missing_or_changed'}
    # Retain receipt hashes only: operator prose, names and content are private.
    return {'status': row['status'], 'checkpoint':row.get('failed_assertion', 'attested_manual_assertions'), 'attempts': [],
            'receipt_sha256': [r['sha256'] for r in receipts],
            'assertions_observed': sorted(required.intersection(row.get('assertions_observed', [])))}


def devices(root):
    matrix = {'flutter': [], 'adb': [], 'ios_simulators': [], 'native_ios_simulators': [], 'errors': []}
    commands = [('flutter', ['flutter','devices','--machine']), ('adb',['adb','devices']),
                ('ios_simulators',['xcrun','simctl','list','devices','available','--json'])]
    for name, command in commands:
        if not shutil.which(command[0]):
            matrix['errors'].append(name + ' tool unavailable'); continue
        try:
            out, code, timeout, _ = launch(command, root, 45)
            if code or timeout: raise ValueError()
            if name == 'flutter':
                matrix[name] = [{k: d.get(k) for k in ('id','targetPlatform','emulator','sdk')} for d in json.loads(out)]
            elif name == 'adb': matrix[name] = [l.split()[0] for l in out.splitlines() if l.endswith('\tdevice')]
            else:
                simulator_rows = json.loads(out)['devices']
                matrix[name] = [d['udid'] for rows in simulator_rows.values() for d in rows if d.get('isAvailable')]
                matrix['native_ios_simulators'] = [d['udid'] for runtime, rows in simulator_rows.items() for d in rows
                    if 'iOS' in runtime and d.get('isAvailable') and d.get('name', '').startswith('iPhone')]
        except (ValueError, OSError): matrix['errors'].append(name + ' discovery failed')
    return matrix


def per_route_legacy(check):
    if check.get('protected_target_boundary') != 'audited_per_route': return False
    if check['kind'] == 'legacy':
        return check['command'][:2] == ['bash', 'scripts/run_flutter_full_regression.sh']
    return (check['kind'] == 'sims' and check.get('capability') == 'reliability.full.cleaned_legacy'
            and check['command'][:5] == ['dart', 'tool/sims/sims.dart', 'full', '--only', 'reliability.full.cleaned_legacy'])


def prerequisites(check, root, device_config, matrix):
    reasons = []
    for executable in check.get('requirements', []):
        if not shutil.which(executable): reasons.append(executable + ' unavailable')
    uses_flutter_sdk = check['kind'] == 'flutter' or (check['kind'] == 'sims' and 'flutter' in check.get('requirements', []))
    if uses_flutter_sdk and not (root / '.dart_tool/package_config.json').exists():
        reasons.append('Flutter packages unavailable: run flutter pub get')
    if uses_flutter_sdk and flutter_sdk_mismatch(root):
        reasons.append('Flutter SDK on PATH differs from package_config; use the SDK that resolved this candidate')
    if check['kind'] == 'full_adapter':
        from full_suite_adapters import prerequisites as adapter_prerequisites
        reasons.extend(adapter_prerequisites(check, device_config, matrix))
    if check['kind'] in ('sims', 'legacy') and not per_route_legacy(check):
        if not device_config or device_config.get('isolated_test_environment') is not True:
            reasons.append('isolated device/account/service configuration required')
        else:
            ids = device_config.get('devices', {})
            needed = device_preflight.device_roles(check, device_config)
            available = {d['id']: d for d in matrix.get('flutter', [])}
            for role in needed:
                target = ids.get(role)
                if not target or target not in available: reasons.append('target unavailable: ' + role); continue
                d = available[target]
                if role.startswith('android') and (target not in matrix['adb'] or not d['targetPlatform'].startswith('android')):
                    reasons.append('Android target is not live: ' + role)
                if role.startswith('android_emulator') and not d['emulator']: reasons.append('second Android target must be an emulator')
                if role == 'android_physical' and d['emulator']: reasons.append('primary Android target must be physical')
                if role.startswith('ios') and d['targetPlatform'] != 'ios': reasons.append('iOS target required')
                if role == 'ios_physical' and d['emulator']: reasons.append('physical iPhone required for this proof')
                if role.startswith('ios_simulator') and (not d['emulator'] or target not in matrix['ios_simulators']):
                    reasons.append('available iOS simulator required')
            if len(set(ids.values())) != len(ids): reasons.append('device roles must be distinct')
            if not device_config.get('fixture_reference'): reasons.append('fixture reference required')
            try:
                package = sims_android_package(check, device_config)
                if check.get('requires_firebase_android_client') and not firebase_android_client_matches(root, package):
                    reasons.append('Matching Firebase Android client configuration required for disposable package')
            except InvalidPlan as error:
                reasons.append(str(error))
    return reasons


def summarize(report, directory):
    (directory / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = [f"Automated: {report['automated_status']}; overall: {report['status']}",
             f"Mode: {report['mode']}; revision: {report['identity']['head']}",
             f"Source: {report['identity']['source_sha256']}",
             f"Baseline: {report['baseline']}; rules: {report['identity']['rules_sha256']}",
             f"Wall time: {report['wall_seconds']:.3f}s (includes selection, discovery and setup)"]
    for r in report['results']:
        lines.append(f"{r['status']:7} {r['id']}: {r.get('checkpoint','')}" )
    lines += [f"Gap: {g}" for g in report.get('gaps', [])]
    (directory / 'summary.txt').write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines[:5]))
    print('Report:', directory / 'summary.txt')


def prior_full_failures(root):
    """Keep historical failures visible, without merging unrelated green runs."""
    receipts = []
    for path in sorted((root / '.codex-test-logs').glob('*/results.json')):
        try: data = json.loads(path.read_text())
        except (ValueError, OSError): continue
        if data.get('mode') == 'full' and data.get('status') != 'PASS':
            receipts.append({'run':path.parent.name, 'status':data.get('status', 'BLOCKED'),
                             'head':data.get('identity', {}).get('head'), 'sha256':file_hash(path)})
    for path in sorted((root / '.full_regression_logs').glob('*/summary.tsv')):
        rows = path.read_text(errors='replace').splitlines()
        failed = [i+1 for i,r in enumerate(rows) if r.split('\t')[0] != 'PASS']
        if failed or len(rows) != 95:
            receipts.append({'run':path.parent.name,'status':'FAIL' if failed else 'BLOCKED',
                             'head':None,'failed_route_numbers':failed,'sha256':file_hash(path)})
    return receipts


def plan_fingerprint(plan):
    """Portable execution contract; host prerequisites/tool versions are separate evidence."""
    selected = []
    for check in plan['selected']:
        row = {k: v for k, v in check.items() if k != 'blocked_prerequisites'}
        # sys.executable is host-specific, but the interpreter invocation is not.
        if row['kind'] == 'python':
            row['command'] = ['python3', *row['command'][1:]]
        selected.append(row)
    return digest({**{k: plan.get(k) for k in (
        'mode', 'baseline', 'candidate_build', 'identity', 'changes',
        'not_selected', 'unmapped_changes', 'ci', 'obligations', 'coverage_gaps', 'runner_expansions', 'execution_settings')}, 'selected': selected})


def make_plan(args, root, rules, *, capture_toolchains=True):
    files = validate(root, rules)
    baseline = resolve_ref(root, args.base)
    if not args.local and git(root, 'status', '--porcelain', '--untracked-files=normal').strip():
        raise InvalidPlan('Working tree is dirty; use --local to include it, or an isolated clean candidate checkout')
    changes = changed_files(root, baseline, args.local)
    identity = source_identity(root, files, rules)
    selection = select(json.loads(json.dumps(rules)), changes, args.mode, files, root)
    for c in selection['selected']:
        if c['kind'] == 'flutter': c['workers'] = getattr(args, 'flutter_workers', 1)
        c['command'], c['selected_paths'] = command_for(c, root, files)
    known = sum(c.get('estimated_seconds') or 0 for c in selection['selected'])
    return {'schema_version':1, 'mode':args.mode, 'baseline':baseline,
            'baseline_provenance':'operator-supplied published revision' if args.mode == 'release' else 'explicit comparison revision',
            'candidate_build': args.build_label, 'identity':identity,
            'toolchains':toolchain_identity(root) if capture_toolchains else {}, 'changes':changes,
            'estimated_test_seconds_known':known,
            'runtime_unknown_checks':[c['id'] for c in selection['selected'] if c.get('estimated_seconds') is None],
            'build_setup_seconds':'unknown until execution', **selection}, files


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['discover','validate','plan','run','full','devices',
                                         'ci-plan','ci-run','ci-verify'])
    parser.add_argument('--jobs', type=positive_int, default=1, help='Maximum independent checks (default: 1); unknown resources serialize')
    parser.add_argument('--flutter-workers', type=positive_int, default=1, help='Bounded workers in each compatible Flutter invocation (default: 1)')
    parser.add_argument('--sims-jobs', type=positive_int, default=1, help='SIMS resource scheduler capacity (default: 1)')
    parser.add_argument('--mode', choices=['change','release'], default='change')
    parser.add_argument('--base', help='Explicit comparison ref; releases: actual previous published revision')
    parser.add_argument('--local', action='store_true', help='Include staged, unstaged and nonignored untracked changes')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--build-label', default='', help='Intended signed version, e.g. 1.0.1(117); not proof of artifact version')
    parser.add_argument('--only', help='Comma-separated diagnostic subset; required omitted checks stay NOT RUN')
    parser.add_argument('--rerun-failed', action='store_true', help='One host diagnostic rerun; devices require cleanup review and a fresh run; preserve first failure')
    parser.add_argument('--evidence', type=Path)
    parser.add_argument('--candidate-artifact', action='append', type=Path, default=[])
    parser.add_argument('--device-config', type=Path, help='Ignored JSON attesting disposable accounts/devices/services')
    parser.add_argument('--list-runners', action='store_true')
    parser.add_argument('--inventory', type=Path, help='Validate an existing inventory snapshot against current discovery')
    parser.add_argument('--plan', action='store_true', help='Full workflow discovery only')
    parser.add_argument('--expected-plan', type=Path, help='CI metadata plan from this workflow attempt')
    parser.add_argument('--report-directory', type=Path, help='CI execution plan/results to verify')
    args = parser.parse_args(argv)
    started = time.monotonic()
    root = ROOT
    directory = args.output or root / '.codex-test-logs' / ('checks-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S') + '-' + uuid.uuid4().hex[:8])
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    # Never overwrite or resume a ledger: preserve attempts and source identity.
    if any(directory.iterdir()):
        print('BLOCKED: output is not empty; use a fresh run directory', file=sys.stderr); return 2
    os.chmod(directory, 0o700)
    try:
        rules = json.loads((root / RULES).read_text())
        if args.action.startswith('ci-'):
            return ci_action(args, root, rules, directory, started)
        if args.action == 'discover':
            from testing_inventory import main as inventory_main
            command = ['--output', str(directory / 'inventory.json')]
            if args.list_runners: command.append('--list-runners')
            status = inventory_main(command)
            print('Inventory:', directory / 'inventory.json')
            return status
        if args.action == 'devices':
            result = devices(root)
            (directory / 'devices.json').write_text(json.dumps(result, indent=2) + '\n')
            print('Device inventory:', directory / 'devices.json'); return 0 if not result['errors'] else 2
        if args.action == 'validate':
            validate(root, rules)
            if args.inventory:
                from testing_inventory import discover
                old = json.loads(args.inventory.read_text())
                current = discover(root)
                if old.get('source_paths_sha256') != current['source_paths_sha256']:
                    raise InvalidPlan('Stale inventory: refresh discovery before using its references')
                if any(not (root / e['path']).is_file() for e in old.get('entries', [])):
                    raise InvalidPlan('Stale inventory points to deleted files')
            print('PASS: selection metadata and references validated'); return 0
        if args.action == 'full':
            return full_run(args, root, rules, directory, started)
        plan, files = make_plan(args, root, rules)
        (directory / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
        device_config = json.loads(args.device_config.read_text()) if args.device_config else {}
        matrix = devices(root) if device_config else {}
        for c in plan['selected']:
            c['blocked_prerequisites'] = prerequisites(c, root, device_config, matrix)
            if c['kind'] == 'manual': c['blocked_prerequisites'] = ['requires candidate-bound manual evidence']
        plan['plan_sha256'] = plan_fingerprint(plan)
        (directory / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
        if args.action == 'plan':
            print(f"Selected {len(plan['selected'])} checks; {len(plan['changes'])} change rows; areas: {', '.join(plan['affected_areas'])}")
            for c in plan['selected']:
                print(c['id'] + ': ' + '; '.join(c['reasons'])[:320] + (' [BLOCKED: ' + '; '.join(c['blocked_prerequisites']) + ']' if c['blocked_prerequisites'] else ''))
            print('Plan:', directory / 'plan.json')
            return 2 if plan['unmapped_changes'] else 0
        return execute_plan(args, root, rules, plan, files, device_config, matrix, directory, started)
    except (InvalidPlan, ValueError, KeyError, OSError, subprocess.TimeoutExpired) as e:
        error = {'schema_version':1, 'status':'BLOCKED', 'checkpoint':'invalid_plan_or_prerequisite',
                 'error':str(e), 'wall_seconds':round(time.monotonic() - started, 3)}
        (directory / 'error.json').write_text(json.dumps(error, indent=2) + '\n')
        print('BLOCKED:', str(e), file=sys.stderr)
        print('Evidence:', directory / 'error.json', file=sys.stderr)
        return 2


def validate_schedule(rows):
    ids = [r['id'] for r in rows]
    if len(ids) != len(set(ids)): raise InvalidPlan('Duplicate schedule id')
    remaining = {}
    for row in rows:
        resources = row.get('resources')
        if resources is not None and (not isinstance(resources, list) or
                any(not isinstance(r, str) or not r for r in resources)):
            raise InvalidPlan('Invalid resources: ' + row['id'])
        deps = row.get('dependencies', [])
        if not isinstance(deps, list) or any(d not in ids for d in deps):
            raise InvalidPlan('Unknown dependency: ' + row['id'])
        remaining[row['id']] = set(deps)
    while remaining:
        ready = {k for k,v in remaining.items() if not v}
        if not ready: raise InvalidPlan('Schedule dependency cycle')
        remaining = {k:v-ready for k,v in remaining.items() if k not in ready}


def is_campaign(check):
    return check['kind'] in ('sims', 'legacy') or (check['kind'] == 'full_adapter' and bool(check.get('device_roles')))


def check_resources(check):
    resources = set(check.get('resources') or ['unknown'])
    if any(r not in ('performance.global', 'shared-native-build') and not r.startswith(
            ('isolated:', 'device:', 'device-control:', 'build:', 'artifact:', 'relay-mutation:')) for r in resources):
        resources.add('unknown')
    resources = {r.replace('device-control:', 'device:', 1) for r in resources}
    if 'unknown' in resources: resources.add('shared-native-build')
    if check['kind'] in ('flutter', 'sims', 'legacy') or any(
            word in ' '.join(check.get('command', [])) for word in ('gradlew', 'xcodebuild', 'flutter')):
        resources.add('shared-native-build')
    if is_campaign(check):
        resources.add('device-campaign-barrier')
    return resources


def resources_compatible(left, right):
    a, b = check_resources(left), check_resources(right)
    return not ({'unknown', 'performance.global'} & (a | b) or a & b)


def obligation_results(obligations, results):
    ledger = []
    for obligation in obligations:
        row = dict(obligation)
        owners = row.get('owners', [])
        if owners:
            row['status'] = aggregate([results[i] for i in owners])
        bindings = row.get('receipt_bindings', [])
        if not bindings and (row.get('family') == 'sims' or row.get('owner_capability')):
            bindings = [dict(owner=owner, capability=row.get('owner_capability', row['selector'])) for owner in owners]
        if bindings:
            outcomes = []
            for binding in bindings:
                parent = results[binding['owner']]
                key = next((k for k in ('capability', 'route') if k in binding), None)
                if key is None:
                    outcomes.append(parent); continue
                attempts = parent.get('attempts', [])
                if not attempts:
                    outcomes.append(dict(status=parent['status'] if parent['status'] in ('FAIL','BLOCKED') else 'NOT RUN'))
                for attempt in attempts:
                    receipts = [r for r in attempt.get(key+'_results', []) if r['id'] == binding[key]]
                    outcomes.extend(receipts if len(receipts) == 1 else [dict(status='NOT RUN', reason='No unique child execution receipt')])
            row['status'] = 'N/A' if outcomes and all(r['status']=='N/A' for r in outcomes) else aggregate(outcomes)
            reason = next((r.get('reason') for r in outcomes if r['status'] == row['status'] and r.get('reason')), None)
            if reason: row['reason'] = reason
        ledger.append(row)
    return ledger


def safe_sims_facts(data, capability_ids=(), profile_ids=()):
    """Share only typed facts and identities already selected from project source.

    Producer diagnostics (including nested verdicts/resources and arbitrary map
    keys) stay in the private SIMS report. A string that looks like an ID is not
    an allowlist: stdout can contain arbitrary identifier-shaped private text.
    """
    def counts(source, keys):
        return {k: source[k] for k in keys if type(source.get(k)) is int and source[k] >= 0}

    def ids(values, allowed):
        return [v for v in values if isinstance(v, str) and v in allowed] if isinstance(values, list) else []

    builds = data.get('builds') if isinstance(data.get('builds'), dict) else {}
    safe_builds = counts(builds, ('requestedProfiles', 'actualBuilds', 'hits', 'misses',
                                  'invalidations', 'totalElapsedMs'))
    for key in ('builtProfileIds', 'cacheHitProfileIds', 'failedProfileIds'):
        safe_builds[key] = ids(builds.get(key), profile_ids)
    timings = builds.get('profileElapsedMs', {})
    safe_builds['profileElapsedMs'] = counts(timings, profile_ids) if isinstance(timings, dict) else {}
    schedule = data.get('schedule') if isinstance(data.get('schedule'), dict) else {}
    safe_schedule = counts(schedule, ('maxObservedConcurrency',))
    for key in ('selectedIds', 'attemptedIds', 'terminalIds'):
        safe_schedule[key] = ids(schedule.get(key), capability_ids)
    if schedule.get('causalFailureId') in capability_ids:
        safe_schedule['causalFailureId'] = schedule['causalFailureId']
    traces = []
    for trace in schedule.get('traces', []):
        if not isinstance(trace, dict) or trace.get('capabilityId') not in capability_ids: continue
        safe = dict(capabilityId=trace['capabilityId'], **counts(trace, ('dependencyWaitMs',)))
        for key in ('startedAt', 'endedAt'):
            value = trace.get(key)
            if isinstance(value, str) and re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z', value):
                try: safe[key] = dt.datetime.fromisoformat(value).isoformat()
                except ValueError: pass
        traces.append(safe)
    safe_schedule['traces'] = traces
    return dict(builds=safe_builds, schedule=safe_schedule)


def sims_receipt_details(path, attempt, capability_ids=(), profile_ids=()):
    if not path.is_file(): return {}
    data = json.loads(path.read_text())
    receipts = []
    for verdict in data.get('verdicts', []):
        cid = verdict.get('capabilityId')
        observed = verdict.get('status')
        status = observed if observed in ('FAIL', 'BLOCKED', 'NOT RUN') else 'BLOCKED'
        if observed == 'PASS' and attempt.get('report_verification_observed'):
            status = 'PASS'
        if (observed == 'N/A' and attempt.get('report_verification_observed') and
                verdict.get('reason') == 'target_unavailable_by_project_policy'):
            status = 'N/A'
        receipts.append(dict(id=cid if cid in capability_ids else None, status=status,
                             observed_status=observed if observed in ('PASS', 'FAIL', 'BLOCKED', 'NOT RUN', 'N/A') else None,
                             reason='target_unavailable_by_project_policy' if status == 'N/A' else None,
                             assertions_attempted=verdict.get('assertionsAttempted')
                             if type(verdict.get('assertionsAttempted')) is int and verdict['assertionsAttempted'] >= 0 else None))
    return dict(capability_results=receipts, **safe_sims_facts(data, capability_ids, profile_ids), install_seconds=None)


def execute_plan(args, root, rules, plan, files, device_config, matrix, directory, started):
    os.chmod(directory, 0o700)
    plan['plan_sha256'] = plan_fingerprint(plan)
    (directory / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
    evidence = json.loads(args.evidence.read_text()) if args.evidence else {}
    artifact_hashes = {p.name:file_hash(p) for p in args.candidate_artifact}
    if len(artifact_hashes) != len(args.candidate_artifact): raise InvalidPlan('Candidate artifact basenames must be unique')
    only = set(args.only.split(',')) if args.only else None
    if only and only - {c['id'] for c in plan['selected']}:
        raise InvalidPlan('Unknown/unselected --only check: ' + ', '.join(sorted(only - {c['id'] for c in plan['selected']})))
    results = []
    # Serialize tools/native/builds; concurrent use of the existing shared AAR cache is unsafe.
    import fcntl
    lock = (root / '.codex-test-logs/checks.lock')
    lock.parent.mkdir(exist_ok=True)
    with lock.open('a') as handle:
        try: fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: raise InvalidPlan('Another Mknoon check run owns shared build resources')
        ordered = sorted(plan['selected'], key=lambda c: (is_campaign(c) or c['kind'] == 'manual', c['id'] != 'workflow', c['id']))
        prerequisite_failed = False
        runner_blocked = set()
        device_cleanup_pending = False
        validate_schedule(ordered)
        campaign_descendants = {c['id'] for c in ordered if is_campaign(c)}
        while True:
            downstream = {c['id'] for c in ordered if set(c.get('dependencies', [])) & campaign_descendants}
            if downstream <= campaign_descendants: break
            campaign_descendants |= downstream
        host_prerequisite_ids = {c['id'] for c in ordered if c['kind'] != 'manual' and c['id'] not in campaign_descendants}
        schedule_started = time.monotonic()
        cancel_event = threading.Event()
        results_by_id = {}
        pending = list(ordered)
        active = {}
        max_running = 0
        jobs = getattr(args, 'jobs', 1)

        def execute_check(c):
            _LAUNCH_CONTEXT.cancel_event = cancel_event
            check_started = time.monotonic()
            row = {'id':c['id'], 'kind':c['kind'], 'command':c['command'], 'selected_paths':c['selected_paths'],
                   'investigate':c.get('investigate', []), 'attempts':[]}
            if only and c['id'] not in only:
                row.update(status='NOT RUN', checkpoint='diagnostic_subset')
            elif c['kind'] == 'manual':
                if evidence and evidence.get('baseline') != plan['baseline']:
                    row.update(status='BLOCKED', checkpoint='manual_evidence_baseline_mismatch')
                else:
                    row.update(manual_result(c, evidence, plan['identity'], root, artifact_hashes))
            elif c.get('target_availability') == 'N/A':
                row.update(status='N/A', checkpoint='target_unavailable_by_project_policy')
            elif c['kind'] == 'legacy' and c['command'][:2] != ['bash', 'scripts/run_flutter_full_regression.sh']:
                row.update(status='BLOCKED', checkpoint='unknown_legacy_command')
            elif c.get('blocked_prerequisites'):
                row.update(status='BLOCKED', checkpoint='prerequisite_unavailable', reasons=c['blocked_prerequisites'])
            elif c['kind'] in runner_blocked:
                row.update(status='NOT RUN', checkpoint='shared_runner_startup_failed')
            elif is_campaign(c) and device_cleanup_pending and not per_route_legacy(c):
                row.update(status='NOT RUN', checkpoint='device_cleanup_review_required')
            elif is_campaign(c) and prerequisite_failed:
                row.update(status='NOT RUN', checkpoint='host_prerequisite_failed')
            elif not per_route_legacy(c) and any(results_by_id[d]['status'] != 'PASS' for d in c.get('dependencies', [])):
                row.update(status='NOT RUN', checkpoint='dependency_failed')
            else:
                for attempt in range(2 if args.rerun_failed else 1):
                    # Device failures need diagnosis and cleanup review before a fresh run.
                    if attempt and (row['attempts'][0]['status'] == 'PASS' or is_campaign(c)): break
                    campaign_started = False
                    try:
                        with ExitStack() as owners:
                            if 'shared-native-build' in check_resources(c):
                                owners.enter_context(device_preflight.device_leases(['mknoon.shared-native-build']))
                            env = os.environ.copy()
                            env['MKNOON_TEST_RUN_ID'] = directory.name + '-' + c['id']
                            env['MKNOON_HOST_FLUTTER_WORKERS'] = str(getattr(args, 'flutter_workers', 1))
                            env['SIMS_MAX_PARALLEL'] = str(getattr(args, 'sims_jobs', 1))
                            env['SIMS_HOST_CONCURRENCY'] = str(getattr(args, 'flutter_workers', 1))
                            env['GOTOOLCHAIN'] = 'go1.25.0'
                            if per_route_legacy(c):
                                env['MKNOON_LEGACY_CLEANUP_PENDING'] = '1' if device_cleanup_pending else '0'
                            if c['kind'] != 'full_adapter': env.update(c.get('environment', {}))
                            if c['kind'] in ('sims', 'legacy'):
                                env.pop('RELIABILITY_MULTI_DEVICE_IDS', None)
                            if c['kind'] == 'full_adapter' and c.get('device_roles'):
                                protected_config = dict(device_config, full_suite={}, devices={role: device_config.get('devices', {}).get(role)
                                    for role in c['device_roles'] if device_config.get('devices', {}).get(role)})
                                env.update(sims_environment(protected_config, directory / (c['id'] + '-binding.json'), c))
                            if c['kind'] == 'sims':
                                report_path = directory / (c['id'] + '-' + str(attempt) + '-sims.json')
                                if report_path.exists(): raise InvalidPlan('Refusing to reuse a SIMS report')
                                env.update(sims_environment(device_config, report_path, c))
                                if c.get('capability') == 'reliability.full.cleaned_legacy':
                                    env['MKNOON_LEGACY_RECEIPT_DIRECTORY'] = str(directory / (c['id'] + '-' + str(attempt) + '-routes'))
                            command = list(c['command'])
                            if c['kind'] == 'legacy':
                                env.update(sims_environment(device_config, directory / (c['id'] + '-nested-sims.json'), c))
                                legacy_dir = directory / (c['id'] + '-' + str(attempt))
                                command += ['--output', str(legacy_dir)]
                                env['MKNOON_LEGACY_CLEANUP_PENDING'] = '1' if device_cleanup_pending else '0'
                                # Consume the canonical host alias only with its
                                # exact child receipt, even if another SIMS child failed.
                                host = results_by_id.get('full-sims-major', {})
                                receipts = [r for a in host.get('attempts', []) for r in a.get('capability_results', []) if r.get('id') == 'host.dart.all']
                                if len(receipts) != 1 or receipts[0]['status'] != 'PASS':
                                    env.pop('MKNOON_FULL_HOST_OWNER', None)
                            if is_campaign(c) and not per_route_legacy(c) and (c.get('device_roles') or c.get('sims_mode')):
                                targets = [device_config.get('devices', {}).get(role) for role in device_preflight.device_roles(c, device_config)]
                                owners.enter_context(device_preflight.device_leases([target for target in targets if target]))
                                preflight = device_preflight.run(c, root, device_config, launch, env)
                                row.setdefault('preflight', []).append(preflight)
                                if preflight['status'] != 'PASS':
                                    raise device_preflight.PreflightBlocked(preflight)
                            campaign_started = is_campaign(c)
                            if c['kind'] == 'full_adapter':
                                from full_suite_adapters import bind, inspect, prepare_step
                                adapter_dir = directory / (c['id'] + '-' + str(attempt + 1) + '-proof')
                                adapter_dir.mkdir()
                                steps, adapter_env = bind(c, device_config, root, adapter_dir)
                                env.update(adapter_env)
                                step_results, outputs, seconds = [], [], 0
                                for step in steps:
                                    prepare_step(step)
                                    # Never accept stale native XML from an earlier Gradle invocation.
                                    before = {str(p):p.stat().st_mtime_ns for p in root.glob(step.get('report_glob','__no_reports__'))}
                                    step_out, code, timeout, duration = launch(step['command'], root / step.get('cwd','.'), c['timeout_seconds'], env)
                                    seconds += duration
                                    outputs.append(step_out)
                                    partial_raw = directory / (c['id'] + '-' + str(attempt + 1) + '.raw.log')
                                    partial_raw.write_text('\n'.join(outputs))
                                    os.chmod(partial_raw, 0o600)
                                    proof = inspect(step, step_out, code, timeout, root)
                                    if step.get('format') == 'junit' and before and all(Path(p).exists() and Path(p).stat().st_mtime_ns == h for p,h in before.items()):
                                        proof.update(status='BLOCKED', checkpoint='stale_native_results')
                                    step_results.append(proof)
                                    if proof['status'] != 'PASS': break
                                out = '\n'.join(outputs)
                                a = dict(step_results[-1], step_results=step_results)
                            else:
                                out, code, timeout, seconds = launch(command, root / c.get('cwd','.'), c['timeout_seconds'], env)
                            raw_path = directory / (c['id'] + '-' + str(attempt + 1) + '.raw.log')
                            raw_path.write_text(out)
                            os.chmod(raw_path, 0o600)
                            if c['kind'] != 'full_adapter':
                                a = parse_execution(c['kind'], out, code, timeout, c['selected_paths'], c.get('success_marker'))
                            if c['kind'] == 'sims':
                                if report_path.is_file(): os.chmod(report_path, 0o600)
                                a = inspect_sims(report_path, c['capability'], code, timeout,
                                    c['selected_paths'] if c.get('expanded_capabilities') else None)
                                if a['status'] in ('PASS', 'N/A'):
                                    verify_command = ['dart', 'tool/sims/sims.dart', 'verify-report', str(report_path)]
                                    _, verify_code, verify_timeout, verify_seconds = launch(verify_command, root, 120, env)
                                    seconds += verify_seconds
                                    if verify_code or verify_timeout:
                                        a.update(status='BLOCKED', checkpoint='sims_report_verification_failed')
                                    else:
                                        a['report_verification_observed'] = True
                                a.update(sims_receipt_details(report_path, a, c['selected_paths'],
                                    [r['buildProfile'] for r in c.get('expanded_capabilities', []) if r.get('buildProfile')]))
                            if c.get('capability') == 'reliability.full.cleaned_legacy':
                                nested_dir = Path(env['MKNOON_LEGACY_RECEIPT_DIRECTORY'])
                                a['route_results'] = legacy_receipt_details(nested_dir, a, c.get('expanded_legacy_routes', []))
                            if c['kind'] == 'legacy':
                                a = inspect_legacy(legacy_dir, code, timeout, c.get('expanded_routes'))
                                a['route_results'] = legacy_receipt_details(legacy_dir, a, c.get('expanded_routes', []))
                            if cancel_event.is_set() and a['status'] != 'FAIL':
                                a.update(status='BLOCKED', checkpoint='run_cancelled', cancelled=True)
                            a.update(exit_status=code, duration_seconds=seconds, attempt=attempt + 1)
                            span = a.get('observed_test_span_seconds')
                            if span is not None:
                                a['outside_test_span_seconds'] = round(max(0, seconds - span), 3)
                    except device_preflight.PreflightBlocked as error:
                        a = {**error.receipt, 'exit_status': None, 'duration_seconds': 0, 'attempt': attempt + 1}
                    except device_preflight.DeviceLeaseBusy:
                        a = {'status': 'BLOCKED', 'checkpoint': 'device_lease_unavailable', 'exit_status': None,
                             'duration_seconds': 0, 'attempt': attempt + 1,
                             'remediation': 'Another campaign or an unsafe lease path prevents exclusive ownership. Inspect the owner, let cleanup finish, then retry; never kill a foreign owner.'}
                    except ValueError as error:
                        diagnostic = directory / (c['id'] + '-' + str(attempt + 1) + '.diagnostic.raw.log')
                        diagnostic.write_text(str(error))
                        os.chmod(diagnostic, 0o600)
                        a = {'status':'BLOCKED','checkpoint':'adapter_fixture_invalid',
                             'exit_status':None,'duration_seconds':0,'attempt':attempt + 1}
                    except OSError:
                        a = {'status':'BLOCKED','checkpoint':'test_runner_startup','exit_status':None,'duration_seconds':0, 'attempt':attempt + 1}
                    if campaign_started and a['status'] != 'PASS':
                        a['cleanup_review_required'] = True
                    row['attempts'].append(a)
                row.update(status=aggregate(row['attempts']), checkpoint=row['attempts'][0]['checkpoint'])
            row['wait_seconds'] = round(check_started - schedule_started, 3)
            row['execution_seconds'] = round(time.monotonic() - check_started, 3)
            return row
        def commit(row):
            nonlocal prerequisite_failed, device_cleanup_pending
            results_by_id[row['id']] = row
            if row['id'] in host_prerequisite_ids and row['status'] in ('FAIL', 'BLOCKED'):
                prerequisite_failed = True
            if any(a.get('cleanup_review_required') for a in row['attempts']):
                device_cleanup_pending = True
            if row['kind'] != 'full_adapter' and row['status'] == 'BLOCKED' and row['checkpoint'] in ('compilation_error', 'test_runner_startup', 'test_runner_startup_or_process_failure'):
                runner_blocked.add(row['kind'])
            print(row['status'], row['id'], flush=True)
            (directory / 'partial.json').write_text(json.dumps({
                'status': 'NOT RUN', 'identity': plan['identity'],
                'selected_ids': [c['id'] for c in ordered],
                'results': [results_by_id[c['id']] for c in ordered if c['id'] in results_by_id]}, indent=2) + '\n')

        old_term = None
        if threading.current_thread() is threading.main_thread():
            old_term = signal.signal(signal.SIGTERM, lambda *_: cancel_event.set())
        try:
            with ThreadPoolExecutor(max_workers=jobs) as pool:
                try:
                    while pending or active:
                        for c in list(pending):
                            if cancel_event.is_set(): break
                            if (only and c['id'] not in only) or c.get('blocked_prerequisites') or c['kind'] == 'manual':
                                pending.remove(c)
                                commit(execute_check(c))
                                continue
                            if len(active) >= jobs: continue
                            if any(d not in results_by_id for d in c.get('dependencies', [])): continue
                            # Device failure/cleanup barriers remain invocation-wide. All
                            # host prerequisites finish before a campaign acquires leases.
                            if is_campaign(c) and any(
                                    x['id'] in host_prerequisite_ids
                                    for x in pending + list(active.values()) if x is not c): continue
                            if any(not resources_compatible(c, x) for x in active.values()): continue
                            pending.remove(c)
                            active[pool.submit(execute_check, c)] = c
                            max_running = max(max_running, len(active))
                        if active:
                            done, _ = wait(active, timeout=.1, return_when=FIRST_COMPLETED)
                            for future in done:
                                c = active.pop(future)
                                commit(future.result())
                        elif pending and not cancel_event.is_set():
                            raise InvalidPlan('Schedule dependency cycle or unavailable dependency')
                        if cancel_event.is_set(): break
                except KeyboardInterrupt:
                    cancel_event.set()
                except BaseException:
                    cancel_event.set()
                    raise
                finally:
                    # Signal every owned process group before draining the pool.
                    if cancel_event.is_set():
                        for future, c in list(active.items()):
                            commit(future.result())
                        for c in pending:
                            commit(dict(id=c['id'], kind=c['kind'], command=c['command'],
                                selected_paths=c['selected_paths'], attempts=[], status='NOT RUN',
                                checkpoint='run_cancelled', wait_seconds=round(time.monotonic()-schedule_started, 3)))
        finally:
            if old_term is not None: signal.signal(signal.SIGTERM, old_term)
        results = [results_by_id[c['id']] for c in ordered]
    gaps = ['Unmapped behavior-affecting change: ' + p for p in plan['unmapped_changes']]
    gaps += ['Uncovered full obligation: ' + oid for oid in plan.get('coverage_gaps', [])]
    if cancel_event.is_set(): gaps.append('Run cancelled; unfinished obligations retained')
    current = source_identity(root, source_files(root), rules)
    if current != plan['identity']: gaps.append('Source/configuration changed during execution; candidate evidence invalidated')
    if plan.get('toolchains') and toolchain_identity(root) != plan['toolchains']:
        gaps.append('Toolchain or resolved package configuration changed during execution')
    if any(file_hash(p) != artifact_hashes[p.name] for p in args.candidate_artifact): gaps.append('Candidate artifact changed during execution')
    if args.mode == 'release' and not artifact_hashes: gaps.append('Signed candidate artifacts not supplied')
    auto = aggregate([r for r in results if r['kind'] != 'manual'])
    overall = aggregate(results)
    if gaps and overall != 'FAIL': overall = 'BLOCKED'
    report = {**{k:plan[k] for k in ('mode','baseline','candidate_build','identity','not_selected')},
              'obligations': obligation_results(plan.get('obligations', []), results_by_id),
              'scheduling': {'jobs': jobs, 'max_observed_concurrency': max_running},
              'schema_version':1, 'automated_status':auto, 'status':overall,
              'plan_sha256':plan['plan_sha256'], 'ci':plan.get('ci'),
              'artifact_sha256':artifact_hashes, 'devices':matrix,
              'toolchains':plan.get('toolchains', {}),
              'prior_full_failures':prior_full_failures(root),
              'wall_seconds':round(time.monotonic() - started, 3), 'results':results,'gaps':gaps,
              'command_seconds':round(sum(a.get('duration_seconds',0) for r in results for a in r['attempts']), 3),
              'timing_scope':'Flutter event span is observed separately; outside-span time includes SDK startup, compilation and shutdown. SIMS build timings come from its verified build report; unexecuted build timings remain unknown.',
              'raw_output_policy':'Share only plan/results/summary/partial JSON/text. Legacy/SIMS nested artifacts are local private evidence and require review/redaction before sharing.'}
    summarize(report, directory)
    return EXIT[overall]


def is_disposable_android_package(package):
    # These runners reset private files to create fresh accounts. A generic
    # isolation attestation must not authorize resetting the production app.
    return isinstance(package, str) and re.fullmatch(r'com\.mknoon\.sims\.[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*', package) is not None


def firebase_android_client_matches(root, package):
    # Inspect only binding fields; do not copy provider configuration into any
    # report. Firebase's real registration/delivery proof remains the runner's.
    try:
        data = json.loads((root / 'android/app/google-services.json').read_text())
        if not isinstance(data.get('project_info', {}).get('project_id'), str):
            return False
        matches = [client['client_info'] for client in data['client']
                   if client['client_info']['android_client_info']['package_name'] == package]
        return len(matches) == 1 and bool(matches[0].get('mobilesdk_app_id'))
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return False


def sims_android_package(check, config):
    fixed = check.get('disposable_android_package')
    if fixed is None and not check.get('requires_disposable_android_package'):
        return None
    packages = config.get('sims_android_packages', {})
    if not isinstance(packages, dict):
        raise InvalidPlan('Explicit disposable Android package mapping required')
    supplied = packages.get(check['capability'])
    if fixed is not None and supplied is not None and supplied != fixed:
        raise InvalidPlan('Configured disposable Android package differs from the campaign build')
    package = fixed if fixed is not None else supplied
    if not is_disposable_android_package(package):
        raise InvalidPlan('Explicit disposable Android package in com.mknoon.sims required')
    return package


def sims_environment(config, report, check=None):
    roles = {'android_physical':'SIMS_ANDROID_PHYSICAL_DEVICE_ID','android_emulator':'SIMS_ANDROID_EMULATOR_DEVICE_ID',
             'android_emulator_second':'SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID',
             'ios_simulator':'SIMS_IOS_SIMULATOR_ID','ios_physical':'SIMS_IOS_DEVICE_ID',
             'macos':'SIMS_MACOS_DEVICE_ID',
             **{'ios_simulator_'+p:'SIMS_IOS_SIMULATOR_'+p.upper()+'_DEVICE_ID' for p in 'abcd'}}
    if any(k not in roles or not isinstance(v, str) or not v.strip() for k,v in config.get('devices', {}).items()):
        raise InvalidPlan('Invalid protected device role or ID')
    # Clear omitted pins as well: raw legacy adapters must not inherit an
    # unleased peer from the launching shell.
    env = {name: '' for name in roles.values()}
    env.update({roles[k]: v for k,v in config.get('devices', {}).items()})
    ids = config.get('devices', {})
    pins = {('ios-simulator-a' if k == 'ios_simulator' else k.replace('_', '-')): v for k,v in ids.items()}
    if ids.get('ios_simulator') and ids.get('ios_simulator_a') != ids['ios_simulator'] and ids.get('ios_simulator_a'):
        raise InvalidPlan('Conflicting iOS simulator role aliases')
    env['SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON'] = json.dumps(pins, sort_keys=True)
    env['SIMS_IOS_PHYSICAL_DEVICE_ID'] = ids.get('ios_physical', '')
    env['SIMS_IOS_SIMULATOR_A_DEVICE_ID'] = pins.get('ios-simulator-a', '')
    if ids.get('android_physical') and ids.get('android_emulator'):
        env['RELIABILITY_MULTI_DEVICE_IDS'] = ids['android_physical'] + ',' + ids['android_emulator']
    package = sims_android_package(check or {}, config)
    if package is not None:
        # Build identity, installed APK and every nested app-state operation use
        # the same package. Ambient local.properties/environment cannot select
        # the production app while the config claims a disposable fixture.
        env.update(ANDROID_APP_PACKAGE=package, SIMS_APP_ID=package,
                   ORG_GRADLE_PROJECT_androidApplicationId=package)
    supplied = config.get('full_suite', {})
    bindings = {
        'relay_addresses':['MKNOON_RELAY_ADDRESSES'],
        'service_account':['SIMS_PROVIDER_FCM_CREDENTIAL_PATH','FIREBASE_SERVICE_ACCOUNT'],
        'relay_target':['MKNOON_257_RELAY_TARGET','MKNOON_256_RELAY_TARGET'],
        'relay_key':['MKNOON_257_RELAY_KEY','MKNOON_256_RELAY_KEY'],
        'group_staging_manifest':['MKNOON_257_STAGING_MANIFEST'],
        'direct_staging_manifest':['MKNOON_256_STAGING_MANIFEST'],
        'group_media_ios_fixture_driver':['SIMS_GROUP_MEDIA_IOS_FIXTURE_DRIVER'],
        'ios_disposable_simulator_ids':['SIMS_IOS_DISPOSABLE_SIMULATOR_IDS'],
    }
    for key, names in bindings.items():
        if key in supplied:
            if not isinstance(supplied[key], str): raise InvalidPlan('full_suite.' + key + ' must be a string')
            if key == 'ios_disposable_simulator_ids' and any(
                    value.strip() not in pins.values() for value in supplied[key].split(',') if value.strip()):
                raise InvalidPlan('Disposable simulator authorization must stay inside protected device assignments')
            env.update({name:supplied[key] for name in names})
    for letter in 'abcd':
        target=config.get('devices', {}).get('ios_simulator_'+letter)
        if target: env['SIMS_IOS_SIMULATOR_'+letter.upper()+'_DEVICE_ID']=target
    env['MKNOON_LEGACY_CONFIG_JSON'] = json.dumps(supplied)
    env['MKNOON_LEGACY_ISOLATED'] = '1' if config.get('isolated_test_environment') is True and config.get('fixture_reference') else '0'
    env['SIMS_REPORT_PATH'] = str(report)
    env['SIMS_CHECKPOINT_PATH'] = str(report.with_suffix('.checkpoint.json'))
    return env


def inspect_sims(path, capability, code, timeout, selected_capabilities=None):
    if not path.is_file(): return {'status':'BLOCKED','checkpoint':'runner_timeout' if timeout else 'missing_sims_report'}
    data = json.loads(path.read_text())
    verdicts = data.get('verdicts', [])
    rows = verdicts if capability == '*' else [v for v in verdicts if v.get('capabilityId') == capability]
    if not rows: return {'status':'BLOCKED','checkpoint':'zero_capability_execution'}
    if any(row.get('status') == 'FAIL' for row in rows):
        return {'status':'FAIL','checkpoint':'sims_assertion_failure', 'timed_out':timeout}
    if timeout: return {'status':'BLOCKED','checkpoint':'runner_timeout'}
    if len({v.get('capabilityId') for v in rows}) != len(rows) or data.get('validationErrors'):
        return {'status':'BLOCKED','checkpoint':'invalid_sims_evidence'}
    if selected_capabilities is not None:
        observed = {v.get('capabilityId') for v in verdicts}
        expected = set(selected_capabilities)
        if observed != expected:
            return {'status':'BLOCKED', 'checkpoint':'incomplete_sims_selection',
                    'missing_capabilities':sorted(expected-observed), 'unexpected_capability_count':len(observed-expected)}
    not_applicable = [row for row in rows if (capability == '*' or capability == 'reliability.full.cleaned_legacy') and row.get('status') == 'N/A'
                      and row.get('reason') == 'target_unavailable_by_project_policy'
                      and row.get('blocker') == 'targetUnavailable'
                      and row.get('targetCapabilityAvailable') is False
                      and row.get('printOnly') is False and not row.get('assertionsAttempted')
                      and not row.get('artifactPresent') and not row.get('artifactEvidence')
                      and row.get('exitCode') in (None,0)]
    checked = [row for row in rows if row not in not_applicable]
    if capability == 'reliability.full.cleaned_legacy' and not code and not checked and not_applicable:
        return dict(status='N/A', checkpoint='target_unavailable_by_project_policy', sims_report_sha256=file_hash(path))
    if code or not checked or any(row.get('status') != 'PASS' or not row.get('assertionsAttempted')
                   or not row.get('artifactPresent') or row.get('exitCode') != 0
                   or row.get('printOnly') is not False or row.get('blocker') is not None for row in checked):
        return {'status':'BLOCKED','checkpoint':'incomplete_sims_evidence'}
    return {'status':'PASS','checkpoint':'sims_assertions_and_artifact_observed','sims_report_sha256':file_hash(path),
            'timed_out':False, **safe_sims_facts(data, selected_capabilities or ([capability] if capability != '*' else [])),
            'not_applicable':[r['capabilityId'] for r in not_applicable if r['capabilityId'] in (selected_capabilities or [])]}


def legacy_receipt_details(directory, attempt, expected_routes):
    summary = directory / 'summary.tsv'
    if not summary.is_file(): return []
    protected = directory / 'routes.json'
    if protected.is_file():
        data = json.loads(protected.read_text())
        expected_ids = [r['label'] for r in expected_routes]
        if not isinstance(data, list) or not all(isinstance(r, dict) for r in data): return []
        if len(set(expected_ids)) != len(expected_ids) or [r.get('id') for r in data] != expected_ids: return []
        summaries = [line.split('\t')[:2] for line in summary.read_text().splitlines()]
        if summaries != [[r.get('status'), r.get('id')] for r in data]: return []
        checkpoints = {'protected_legacy_route_completed','target_unavailable_by_project_policy',
                       'target_binding_unavailable','device_cleanup_review_required','legacy_child_failed',
                       'legacy_contract_invalid','legacy_child_incomplete','missing_legacy_child_receipt','run_cancelled',
                       'device_automation_busy','device_automation_unobserved','device_target_unavailable'}
        receipts = []
        for i, r in enumerate(data, 1):
            log = directory / 'logs' / f'{i:03d}.log'
            if (r.get('status') not in ('PASS','FAIL','BLOCKED','NOT RUN','N/A') or
                    r.get('checkpoint') not in checkpoints or not log.is_file() or
                    file_hash(log) != r.get('log_sha256') or
                    (r['status'] == 'N/A' and r['checkpoint'] != 'target_unavailable_by_project_policy')):
                return []
            receipts.append(dict(id=r['id'], status=r['status'], checkpoint=r['checkpoint']))
        return receipts
    expected = {r['label'] for r in expected_routes}
    rows = [r.split('\t') for r in summary.read_text().splitlines()]
    receipts = []
    for row in rows:
        if len(row) < 2 or row[1] not in expected: continue
        status = 'FAIL' if row[0] == 'FAIL' else 'BLOCKED'
        if row[0] == 'PASS' and attempt['status'] == 'PASS': status = 'PASS'
        receipts.append(dict(id=row[1], status=status))
    return receipts


def inspect_legacy(directory, code, timeout, expected_routes=None):
    summary = directory / 'summary.tsv'
    if not summary.is_file(): return {'status':'BLOCKED','checkpoint':'missing_full_regression_summary'}
    rows = [r.split('\t') for r in summary.read_text().splitlines() if r]
    statuses = [r[0] for r in rows]
    expected_count = len(expected_routes) if expected_routes is not None else 95
    missing_routes = sorted({r['label'] for r in expected_routes or []} - {r[1] for r in rows if len(r)>1})
    if 'FAIL' in statuses: return {'status':'FAIL','checkpoint':'legacy_route_failure',
                                 'failed_route_numbers':[i + 1 for i,r in enumerate(rows) if r[0] == 'FAIL'],
                                 'missing_routes':missing_routes}
    if expected_routes is not None and (len({r[1] for r in rows if len(r)>1}) != len(rows) or
            {r[1] for r in rows if len(r)>1} != {r['label'] for r in expected_routes}):
        return {'status':'BLOCKED','checkpoint':'legacy_route_selection_mismatch','missing_routes':missing_routes}
    protected_receipts = legacy_receipt_details(directory, {}, expected_routes or []) if (directory / 'routes.json').is_file() else []
    if (directory / 'routes.json').is_file() and len(protected_receipts) != expected_count:
        return dict(status='BLOCKED', checkpoint='invalid_legacy_child_receipts')
    allowed = {'PASS', 'N/A'} if len(protected_receipts) == expected_count else {'PASS'}
    if code or timeout or len(rows) != expected_count or not set(statuses) <= allowed:
        return {'status':'BLOCKED','checkpoint':'incomplete_full_regression_routes'}
    logs = list((directory / 'logs').glob('*.log'))
    if len(logs) != expected_count: return {'status':'BLOCKED','checkpoint':'missing_full_regression_logs'}
    for log in logs:
        text = log.read_text(errors='replace')
        if re.search(r'No tests ran|No tests were found|0 tests? (?:passed|ran)|(?:Ran|Executed)\s+0\s+tests?|unbound variable|command not found', text, re.I):
            return {'status':'BLOCKED','checkpoint':'legacy_runner_incomplete', 'route_log':log.name}
        if re.search(r'~[1-9]\d*|--- SKIP:|\b[1-9]\d* (?:tests? )?skipped|\bskipped[=: ]+[1-9]\d*|"skipped"\s*:\s*true', text, re.I):
            return {'status':'BLOCKED','checkpoint':'legacy_skipped_tests', 'route_log':log.name}
    return {'status':'PASS','checkpoint':'legacy_95_routes_completed' if expected_routes is None else 'legacy_selected_routes_completed', 'route_count':expected_count,
            'timed_out':False, 'summary_sha256':file_hash(summary),
            'limitation':'Legacy per-route summaries are retained; case-level counts are not available for every nested runner.'}


def make_full_plan(args, root, rules, *, capture_toolchains=True):
    baseline = resolve_ref(root, args.base)
    if not args.local and git(root,'status','--porcelain','--untracked-files=normal').strip():
        raise InvalidPlan('Full source is dirty; use --local or clean checkout')
    files = source_files(root)
    plan = {'execution_settings': {'jobs':getattr(args,'jobs',1), 'flutter_workers':getattr(args,'flutter_workers',1), 'sims_jobs':getattr(args,'sims_jobs',1)},
            'mode':'full', 'baseline':baseline, 'candidate_build':args.build_label,
            'toolchains':toolchain_identity(root) if capture_toolchains else {},
            'identity':source_identity(root,files,rules), 'not_selected':[], 'unmapped_changes':[], 'selected':[]}
    for c in rules['full_commands']:
        check = dict(c)
        check['command'] = list(c['command'])
        if c['kind'] == 'sims' and getattr(args, 'sims_jobs', 1) > 1:
            check['command'].append('--simultaneous')
        check['selected_paths'] = expand_paths(root, c.get('paths',[]), files) if c['kind'] == 'flutter' else c.get('paths',[])
        plan['selected'].append(check)
    if rules.get('full_inventory'):
        from testing_inventory import reconcile
        plan.update(reconcile(root, rules, plan['selected'], files, getattr(args, 'flutter_workers', 1)))
    validate_schedule(plan['selected'])
    return plan, files


def full_run(args, root, rules, directory, started):
    """Existing full entry points, serialized and identity-bound; no resume erasure."""
    validate(root, rules)
    if args.plan:
        if not args.base: args.base = 'HEAD'
        args.local = True  # preview records the current bytes; never authorizes execution
        plan, _ = make_full_plan(args, root, rules, capture_toolchains=False)
        plan['plan_sha256'] = plan_fingerprint(plan)
        (directory / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
        (directory / 'full-plan.json').write_text(json.dumps(plan, indent=2) + '\n')
        print(f"Planned {len(plan['selected'])} checks; {len(plan.get('obligations', []))} obligations; {len(plan.get('coverage_gaps', []))} coverage gaps")
        print('Full plan:', directory / 'plan.json')
        return 2 if plan.get('coverage_gaps') else 0
    if not args.base: raise InvalidPlan('Full execution requires --base to record a common tested revision')
    config = json.loads(args.device_config.read_text()) if args.device_config else {}
    # Full legacy campaigns may span days. No cancellation/resume or cross-revision merge.
    plan, files = make_full_plan(args, root, rules)
    matrix = devices(root) if config else {}
    for check in plan['selected']:
        check['blocked_prerequisites'] = prerequisites(check,root,config,matrix)
        if check['kind'] == 'full_adapter':
            from full_suite_adapters import availability
            check['target_availability'] = availability(check,config,matrix)
    # Preserve full workflow failures independently of release summaries.
    (directory / 'plan.json').write_text(json.dumps(plan,indent=2) + '\n')
    return execute_plan(args,root,rules,plan,files,config,matrix,directory,started)


def ci_context(root, env=None):
    """Resolve immutable event SHAs, never HEAD^ or the merge commit's merge-base."""
    env = os.environ if env is None else env
    required = ('GITHUB_SHA', 'GITHUB_REPOSITORY', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT',
                'GITHUB_EVENT_NAME', 'GITHUB_EVENT_PATH', 'GITHUB_WORKFLOW_REF', 'GITHUB_REF')
    if any(not env.get(k) for k in required):
        raise InvalidPlan('CI event provenance missing')
    candidate = env['GITHUB_SHA']
    if not re.fullmatch(r'[0-9a-f]{40}', candidate) or resolve_ref(root, 'HEAD') != candidate:
        raise InvalidPlan('CI checkout does not match the expected candidate SHA')
    if any(not re.fullmatch(r'[1-9][0-9]*', env[k]) for k in ('GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT')):
        raise InvalidPlan('CI run identity invalid')
    event = json.loads(Path(env['GITHUB_EVENT_PATH']).read_text())
    context = {k.removeprefix('GITHUB_').lower(): env[k] for k in required if k != 'GITHUB_EVENT_PATH'}
    if event['repository']['full_name'] != context['repository']:
        raise InvalidPlan('CI repository provenance mismatch')
    if context['event_name'] == 'pull_request':
        pr = event['pull_request']
        head, base = pr['head']['sha'], pr['base']['sha']
        if any(not re.fullmatch(r'[0-9a-f]{40}', sha) for sha in (head, base)):
            raise InvalidPlan('PR head/base must be immutable SHAs')
        parents = git(root, 'rev-list', '--parents', '-n', '1', candidate).decode().split()[1:]
        if parents != [base, head] or context['ref'] != f"refs/pull/{event['number']}/merge":
            raise InvalidPlan('PR merge candidate has stale or mismatched head/base parents')
        context.update(mode='change', pr_number=event['number'], pr_head=head, pr_base=base,
                       pr_base_ref=pr['base']['ref'], head_repository=pr['head']['repo']['full_name'])
        context['baseline'] = git(root, 'merge-base', head, base).decode().strip()
    elif context['event_name'] == 'schedule':
        context.update(mode='full', baseline=candidate)
    elif context['event_name'] == 'workflow_dispatch':
        inputs = event.get('inputs', {})
        mode = inputs.get('mode', 'change')
        if mode not in ('change', 'release', 'full'):
            raise InvalidPlan('Unsupported CI mode')
        # A mutable branch name is not a published-build attestation.
        baseline = inputs.get('baseline', '')
        if not re.fullmatch(r'[0-9a-f]{40}', baseline):
            raise InvalidPlan('CI dispatch requires an explicit verified baseline SHA')
        context.update(mode=mode, baseline=resolve_ref(root, baseline),
                       build_label=inputs.get('build_label', ''))
    else:
        raise InvalidPlan('Unsupported CI event; privileged PR execution is prohibited')
    return context


def require_ci(condition, message):
    if not condition:
        raise InvalidPlan(message)


def verify_ci_results(expected, execution_plan, report, context, fingerprint,
                      metadata_result, execution_result):
    """Fail closed on job conclusions, complete membership and original execution facts."""
    require_ci(metadata_result == 'success', 'CI metadata did not succeed: ' + metadata_result)
    require_ci(execution_result == 'success', 'CI selected execution did not succeed: ' + execution_result)
    require_ci(bool(fingerprint) and expected.get('plan_sha256') == fingerprint
               and plan_fingerprint(expected) == fingerprint, 'CI expected plan fingerprint mismatch')
    require_ci(expected.get('ci') == context, 'CI expected event/candidate provenance mismatch')
    require_ci(execution_plan.get('plan_sha256') == fingerprint
               and plan_fingerprint(execution_plan) == fingerprint, 'CI execution plan mismatch')
    require_ci(not expected.get('coverage_gaps'), 'Full inventory obligations remain uncovered or manual')
    require_ci(not expected['unmapped_changes'], 'Unmapped changes remain unresolved')
    require_ci(report.get('schema_version') == 1 and report.get('ci') == context
               and report.get('plan_sha256') == fingerprint, 'CI result provenance missing or stale')
    for key in ('mode', 'baseline', 'candidate_build', 'identity', 'not_selected', 'toolchains'):
        require_ci(report.get(key) == execution_plan.get(key), 'CI result identity mismatch: ' + key)
    require_ci(report.get('status') == 'PASS' and report.get('automated_status') == 'PASS'
               and report.get('gaps') == [], 'CI report is failed, blocked or incomplete')
    expected_obligations = execution_plan.get('obligations', [])
    actual_obligations = report.get('obligations', [])
    require_ci(len(actual_obligations) == len(expected_obligations) and
               {o['id'] for o in actual_obligations} == {o['id'] for o in expected_obligations},
               'CI full obligation ledger mismatch')
    require_ci(actual_obligations == obligation_results(expected_obligations, {r['id']:r for r in report.get('results', [])}),
               'CI full obligation outcomes differ from their execution receipts')
    for obligation in actual_obligations:
        require_ci(obligation['status'] in ('PASS', 'EXCLUDED', 'INACTIVE', 'N/A'), 'Incomplete full obligation')
    selected = {c['id']: c for c in execution_plan['selected']}
    rows = report.get('results', [])
    require_ci(bool(selected) and len(selected) == len(execution_plan['selected'])
               and len(rows) == len(selected) and {r['id'] for r in rows} == set(selected),
               'CI selected results are missing, duplicated or unexpected')
    is_hash = lambda value: isinstance(value, str) and bool(re.fullmatch(r'[0-9a-f]{64}', value))
    if context['mode'] == 'release':
        artifacts = report.get('artifact_sha256', {})
        require_ci(bool(artifacts) and all(is_hash(h) for h in artifacts.values()),
                   'Signed candidate artifact evidence missing')
    for row in rows:
        check = selected[row['id']]
        label = 'CI result for ' + row['id']
        require_ci(row.get('status') == 'PASS', label + ' did not pass')
        for key in ('kind', 'command', 'selected_paths'):
            require_ci(row.get(key) == check[key], label + ' has mismatched ' + key)
        attempts = row.get('attempts', [])
        if check['kind'] == 'manual':
            require_ci(context['mode'] == 'release' and attempts == []
                       and row.get('checkpoint') == 'attested_manual_assertions'
                       and set(row.get('assertions_observed', [])) == set(check['assertions'])
                       and bool(row.get('receipt_sha256'))
                       and all(is_hash(h) for h in row['receipt_sha256']), label + ' lacks required signed evidence')
            continue
        require_ci(1 <= len(attempts) <= 2, label + ' has no complete first attempt')
        for number, attempt in enumerate(attempts, 1):
            require_ci(attempt.get('status') == 'PASS' and attempt.get('attempt') == number
                       and type(attempt.get('exit_status')) is int and attempt['exit_status'] == 0
                       and attempt.get('timed_out') is False, label + ' has a failed or unfinished attempt')
            kind = check['kind']
            if kind == 'sims':
                require_ci(attempt.get('checkpoint') == 'sims_assertions_and_artifact_observed'
                           and is_hash(attempt.get('sims_report_sha256'))
                           and attempt.get('report_verification_observed') is True,
                           label + ' lacks verified device evidence')
            elif kind == 'legacy':
                require_ci(attempt.get('checkpoint') == ('legacy_selected_routes_completed' if check.get('expanded_routes') else 'legacy_95_routes_completed')
                           and attempt.get('route_count') == len(check.get('expanded_routes', [None]*95)) and is_hash(attempt.get('summary_sha256')),
                           label + ' lacks complete full-regression evidence')
            else:
                counts = attempt.get('counts', {})
                require_ci(kind in ('flutter', 'python', 'node', 'go', 'command')
                           and attempt.get('checkpoint') == 'runner_completed'
                           and attempt.get('completion_observed') is True
                           and type(counts.get('passed')) is int and counts['passed'] > 0
                           and counts.get('failed') == 0 and counts.get('skipped') == 0
                           and attempt.get('missing_test_files') == []
                           and attempt.get('failed_cases') == []
                           and attempt.get('compilation_diagnostics') == []
                           and is_hash(attempt.get('raw_output_sha256')),
                           label + ' lacks complete substantive execution')
    return {'status':'PASS', 'plan_sha256':fingerprint, 'ci':context, 'completed_checks':len(rows)}


def ci_action(args, root, rules, directory, started):
    """Use the existing selector/runner with an independently reconstructed CI plan."""
    context = ci_context(root)
    require_ci(not args.local and not args.only, 'CI cannot use a dirty candidate or diagnostic subset')
    args.base, args.mode = context['baseline'], context['mode']
    args.build_label = context.get('build_label', '')
    validate(root, rules)
    builder = make_full_plan if args.mode == 'full' else make_plan
    plan, files = builder(args, root, rules, capture_toolchains=args.action == 'ci-run')
    plan['ci'] = context
    plan['plan_sha256'] = plan_fingerprint(plan)
    if args.action == 'ci-plan':
        (directory / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
        with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
            output.write('plan_sha256=' + plan['plan_sha256'] + '\n')
        print(f"Planned {len(plan['selected'])} {args.mode} checks at {context['sha']}; baseline {args.base}")
        return 0
    if args.action == 'ci-verify':
        # Check job conclusions before touching possibly absent artifacts.
        require_ci(os.environ.get('MKNOON_METADATA_RESULT') == 'success', 'CI metadata job did not succeed')
        require_ci(os.environ.get('MKNOON_EXECUTION_RESULT') == 'success',
                   'CI selected job disabled, skipped, cancelled, failed or not completed')
    require_ci(args.expected_plan is not None, 'CI expected plan missing')
    expected = json.loads(args.expected_plan.read_text())
    fingerprint = os.environ.get('MKNOON_PLAN_SHA256', '')
    require_ci(bool(fingerprint) and expected.get('plan_sha256') == fingerprint
               and plan_fingerprint(expected) == fingerprint
               and plan['plan_sha256'] == fingerprint, 'CI plan or candidate differs from metadata expectation')
    if args.action == 'ci-run':
        require_ci(context['event_name'] != 'pull_request' or context['head_repository'] == context['repository'],
                   'Fork code is prohibited on the shared runner')
        require_ci(args.mode == 'release' or not (args.evidence or args.candidate_artifact),
                   'Signed artifact evidence belongs only to release acceptance')
        config = json.loads(args.device_config.read_text()) if args.device_config else {}
        matrix = devices(root) if config else {}
        for c in plan['selected']:
            c['blocked_prerequisites'] = prerequisites(c, root, config, matrix)
        return execute_plan(args, root, rules, plan, files, config, matrix, directory, started)
    require_ci(args.report_directory is not None, 'CI results directory missing')
    execution_plan = json.loads((args.report_directory / 'plan.json').read_text())
    report = json.loads((args.report_directory / 'results.json').read_text())
    verdict = verify_ci_results(expected, execution_plan, report, context, fingerprint,
                                os.environ['MKNOON_METADATA_RESULT'], os.environ['MKNOON_EXECUTION_RESULT'])
    (directory / 'verdict.json').write_text(json.dumps(verdict, indent=2) + '\n')
    print(f"PASS: all {verdict['completed_checks']} selected checks have complete candidate-bound results")
    return 0


if __name__ == '__main__':
    sys.exit(main())
