#!/usr/bin/env python3
"""Deterministic selection and evidence adapter for Mknoon's existing runners.

No network calls, LLM, database, or automatic retries. Raw process output is never
copied into shareable reports; structured completion facts are allowlisted.
"""
from __future__ import annotations

import argparse
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
        for cid in area.get('checks', []):
            if cid not in checks: errors.append('Unknown area check: ' + cid)
    sims = json.loads((root / SIMS).read_text()) if (root / SIMS).exists() else {'capabilities': []}
    capability_ids = {c['id'] for c in sims['capabilities']}
    for cid, c in checks.items():
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
        for path in c.get('references', []):
            if not (root / path).exists(): errors.append('Missing proof/reference: ' + path)
        if c.get('kind') == 'command' and not c.get('success_marker'):
            errors.append('Command needs explicit completion marker: ' + cid)
    for c in rules.get('full_commands', []):
        if not c.get('command') or c.get('timeout_seconds', 0) <= 0:
            errors.append('Invalid full command: ' + c.get('id', '?'))
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
        matching = [a for a in rules['areas'] if any(fnmatch.fnmatchcase(path, p) for p in a['patterns'])]
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
                unmapped.append(path)
    return {'selected': [{'id': cid, 'reasons': sorted(set(why)), **rules['checks'][cid]}
                         for cid, why in sorted(selected.items())],
            'affected_areas': sorted(areas), 'unmapped_changes': sorted(set(unmapped)),
            'documentation_exclusions': sorted(set(excluded)),
            'not_selected': sorted(set(rules['checks']) - set(selected))}


def command_for(check, root, files):
    kind = check['kind']
    if kind == 'flutter':
        paths = expand_paths(root, check['paths'], files)
        command = ['flutter', 'test', '--no-pub', '--machine', '--concurrency=1', '--timeout=2m', *paths]
        if check.get('names'): command += ['--name', '|'.join(re.escape(n) for n in check['names'])]
        return command, paths
    if kind == 'python':
        return [sys.executable, '-m', 'unittest', '-v', *check['paths']], check['paths']
    if kind == 'node': return ['node', '--test', '--test-reporter=tap', *check['paths']], check['paths']
    if kind == 'go':
        return ['go', 'test', '-json', '-count=1', '-timeout=10m', *check['packages']], check['packages']
    if kind == 'sims':
        return ['dart', 'tool/sims/sims.dart', 'major', '--only', check['capability'],
                '--prepare-builds', '--continue-on-failure', '--format', 'json'], [check['capability']]
    return check.get('command', []), check.get('paths', [])


def parse_execution(kind, output, returncode, timed_out=False, selected_paths=None, success_marker=None):
    """Only observed completion facts leave this function. No log text/test names."""
    counts = {'passed': 0, 'failed': 0, 'skipped': 0}
    completed = False
    first_failure = None
    failed_cases = []
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
                if result == 'failed':
                    location = t.get('url') or ''
                    if location.startswith('file:'):
                        location = unquote(urlparse(location).path).replace(str(ROOT) + '/', '')
                        if location.startswith('/'): location = 'external/' + Path(location).name
                    failed_cases.append({'test_id': e.get('testID'),
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
                if action == 'fail':
                    # Dynamic subtest labels and import paths may contain private
                    # data. Hash both, retaining the discoverable parent identity.
                    failed_cases.append({'name_sha256': digest(name),
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
            'failed_cases': failed_cases, 'timed_out': timed_out,
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
            p.wait(timeout=timeout)
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
        except BaseException:
            os.killpg(p.pid, signal.SIGKILL); p.wait(timeout=5)
            raise
        output.seek(0)
        data = output.read().decode('utf-8', 'replace')
    return data, p.returncode, timed_out, round(time.monotonic() - start, 3)


def aggregate(attempts):
    """A passing diagnostic rerun cannot erase a failed or blocked first attempt."""
    statuses = [a['status'] for a in attempts]
    for status in ('FAIL', 'BLOCKED', 'NOT RUN'):
        if status in statuses: return status
    return 'PASS' if statuses else 'NOT RUN'


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
    matrix = {'flutter': [], 'adb': [], 'ios_simulators': [], 'errors': []}
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
                matrix[name] = [d['udid'] for rows in json.loads(out)['devices'].values() for d in rows if d.get('isAvailable')]
        except (ValueError, OSError): matrix['errors'].append(name + ' discovery failed')
    return matrix


def prerequisites(check, root, device_config, matrix):
    reasons = []
    for executable in check.get('requirements', []):
        if not shutil.which(executable): reasons.append(executable + ' unavailable')
    if check['kind'] == 'flutter' and not (root / '.dart_tool/package_config.json').exists():
        reasons.append('Flutter packages unavailable: run flutter pub get')
    if check['kind'] == 'flutter' and flutter_sdk_mismatch(root):
        reasons.append('Flutter SDK on PATH differs from package_config; use the SDK that resolved this candidate')
    if check['kind'] in ('sims', 'legacy'):
        if not device_config or device_config.get('isolated_test_environment') is not True:
            reasons.append('isolated device/account/service configuration required')
        else:
            ids = device_config.get('devices', {})
            needed = check.get('device_roles', [] if check.get('sims_mode') else ['android_physical','android_emulator'])
            available = {d['id']: d for d in matrix.get('flutter', [])}
            for role in needed:
                target = ids.get(role)
                if not target or target not in available: reasons.append('target unavailable: ' + role); continue
                d = available[target]
                if role.startswith('android') and (target not in matrix['adb'] or not d['targetPlatform'].startswith('android')):
                    reasons.append('Android target is not live: ' + role)
                if role == 'android_emulator' and not d['emulator']: reasons.append('second Android target must be an emulator')
                if role == 'android_physical' and d['emulator']: reasons.append('primary Android target must be physical')
                if role.startswith('ios') and d['targetPlatform'] != 'ios': reasons.append('iOS target required')
                if role == 'ios_physical' and d['emulator']: reasons.append('physical iPhone required for this proof')
                if role == 'ios_simulator' and (not d['emulator'] or target not in matrix['ios_simulators']):
                    reasons.append('available iOS simulator required')
            if len(set(ids.values())) != len(ids): reasons.append('device roles must be distinct')
            if not device_config.get('fixture_reference'): reasons.append('fixture reference required')
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


def make_plan(args, root, rules):
    files = validate(root, rules)
    baseline = resolve_ref(root, args.base)
    if not args.local and git(root, 'status', '--porcelain', '--untracked-files=normal').strip():
        raise InvalidPlan('Working tree is dirty; use --local to include it, or an isolated clean candidate checkout')
    changes = changed_files(root, baseline, args.local)
    identity = source_identity(root, files, rules)
    selection = select(json.loads(json.dumps(rules)), changes, args.mode, files, root)
    for c in selection['selected']:
        c['command'], c['selected_paths'] = command_for(c, root, files)
    known = sum(c.get('estimated_seconds') or 0 for c in selection['selected'])
    return {'schema_version':1, 'mode':args.mode, 'baseline':baseline,
            'baseline_provenance':'operator-supplied published revision' if args.mode == 'release' else 'explicit comparison revision',
            'candidate_build': args.build_label, 'identity':identity, 'toolchains':toolchain_identity(root), 'changes':changes,
            'estimated_test_seconds_known':known,
            'runtime_unknown_checks':[c['id'] for c in selection['selected'] if c.get('estimated_seconds') is None],
            'build_setup_seconds':'unknown until execution', **selection}, files


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['discover','validate','plan','run','full','devices'])
    parser.add_argument('--mode', choices=['change','release'], default='change')
    parser.add_argument('--base', help='Explicit comparison ref; releases: actual previous published revision')
    parser.add_argument('--local', action='store_true', help='Include staged, unstaged and nonignored untracked changes')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--build-label', default='', help='Intended signed version, e.g. 1.0.1(117); not proof of artifact version')
    parser.add_argument('--only', help='Comma-separated diagnostic subset; required omitted checks stay NOT RUN')
    parser.add_argument('--rerun-failed', action='store_true', help='One diagnostic rerun; preserve first failure')
    parser.add_argument('--evidence', type=Path)
    parser.add_argument('--candidate-artifact', action='append', type=Path, default=[])
    parser.add_argument('--device-config', type=Path, help='Ignored JSON attesting disposable accounts/devices/services')
    parser.add_argument('--list-runners', action='store_true')
    parser.add_argument('--inventory', type=Path, help='Validate an existing inventory snapshot against current discovery')
    parser.add_argument('--plan', action='store_true', help='Full workflow discovery only')
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


def execute_plan(args, root, rules, plan, files, device_config, matrix, directory, started):
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
        ordered = sorted(plan['selected'], key=lambda c: (c['kind'] in ('sims','legacy','manual'), c['id'] != 'workflow', c['id']))
        prerequisite_failed = False
        runner_blocked = set()
        for c in ordered:
            row = {'id':c['id'], 'kind':c['kind'], 'command':c['command'], 'selected_paths':c['selected_paths'],
                   'investigate':c.get('investigate', []), 'attempts':[]}
            if only and c['id'] not in only:
                row.update(status='NOT RUN', checkpoint='diagnostic_subset')
            elif c['kind'] == 'manual':
                if evidence and evidence.get('baseline') != plan['baseline']:
                    row.update(status='BLOCKED', checkpoint='manual_evidence_baseline_mismatch')
                else:
                    row.update(manual_result(c, evidence, plan['identity'], root, artifact_hashes))
            elif c['blocked_prerequisites']:
                row.update(status='BLOCKED', checkpoint='prerequisite_unavailable', reasons=c['blocked_prerequisites'])
            elif c['kind'] in runner_blocked:
                row.update(status='NOT RUN', checkpoint='shared_runner_startup_failed')
            elif c['kind'] in ('sims','legacy') and prerequisite_failed:
                row.update(status='NOT RUN', checkpoint='host_prerequisite_failed')
            else:
                for attempt in range(2 if args.rerun_failed else 1):
                    if attempt and row['attempts'][0]['status'] == 'PASS': break
                    try:
                        env = os.environ.copy()
                        env['MKNOON_TEST_RUN_ID'] = directory.name + '-' + c['id']
                        env['GOTOOLCHAIN'] = 'go1.25.0'
                        if c['kind'] == 'sims':
                            report_path = directory / (c['id'] + '-' + str(attempt) + '-sims.json')
                            if report_path.exists(): raise InvalidPlan('Refusing to reuse a SIMS report')
                            env.update(sims_environment(device_config, report_path))
                        command = list(c['command'])
                        if c['kind'] == 'legacy':
                            legacy_dir = directory / (c['id'] + '-' + str(attempt))
                            command += ['--android-device', device_config['devices']['android_physical'],
                                        '--ios-simulator', device_config['devices']['ios_simulator'], '--output', str(legacy_dir)]
                        out, code, timeout, seconds = launch(command, root / c.get('cwd','.'), c['timeout_seconds'], env)
                        a = parse_execution(c['kind'], out, code, timeout, c['selected_paths'], c.get('success_marker'))
                        if c['kind'] == 'sims':
                            a = inspect_sims(report_path, c['capability'], code, timeout)
                            if a['status'] == 'PASS':
                                verify_command = ['dart', 'tool/sims/sims.dart', 'verify-report', str(report_path)]
                                _, verify_code, verify_timeout, verify_seconds = launch(verify_command, root, 120, env)
                                seconds += verify_seconds
                                if verify_code or verify_timeout:
                                    a.update(status='BLOCKED', checkpoint='sims_report_verification_failed')
                        if c['kind'] == 'legacy':
                            a = inspect_legacy(legacy_dir, code, timeout)
                        a.update(exit_status=code, duration_seconds=seconds, attempt=attempt + 1)
                        span = a.get('observed_test_span_seconds')
                        if span is not None:
                            a['outside_test_span_seconds'] = round(max(0, seconds - span), 3)
                    except OSError:
                        a = {'status':'BLOCKED','checkpoint':'test_runner_startup','exit_status':None,'duration_seconds':0, 'attempt':attempt + 1}
                    row['attempts'].append(a)
                row.update(status=aggregate(row['attempts']), checkpoint=row['attempts'][0]['checkpoint'])
                if row['status'] == 'BLOCKED' and row['checkpoint'] in ('compilation_error','test_runner_startup','test_runner_startup_or_process_failure'):
                    runner_blocked.add(c['kind'])
            if c['kind'] not in ('sims','legacy','manual') and row['status'] != 'PASS': prerequisite_failed = True
            results.append(row)
            print(row['status'], c['id'], flush=True)
            # Durable partial results survive interruption; they cannot claim completion.
            (directory / 'partial.json').write_text(json.dumps({'status':'NOT RUN','identity':plan['identity'],'results':results}, indent=2) + '\n')
    gaps = ['Unmapped behavior-affecting change: ' + p for p in plan['unmapped_changes']]
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
              'schema_version':1, 'automated_status':auto, 'status':overall,
              'artifact_sha256':artifact_hashes, 'devices':matrix,
              'toolchains':plan.get('toolchains', {}),
              'prior_full_failures':prior_full_failures(root),
              'wall_seconds':round(time.monotonic() - started, 3), 'results':results,'gaps':gaps,
              'command_seconds':round(sum(a.get('duration_seconds',0) for r in results for a in r['attempts']), 3),
              'timing_scope':'Flutter event span is observed separately; outside-span time includes SDK startup, compilation and shutdown. SIMS build timings come from its verified build report; unexecuted build timings remain unknown.',
              'raw_output_policy':'Share only plan/results/summary/partial JSON/text. Legacy/SIMS nested artifacts are local private evidence and require review/redaction before sharing.'}
    summarize(report, directory)
    return EXIT[overall]


def sims_environment(config, report):
    roles = {'android_physical':'SIMS_ANDROID_PHYSICAL_DEVICE_ID','android_emulator':'SIMS_ANDROID_EMULATOR_DEVICE_ID',
             'ios_simulator':'SIMS_IOS_SIMULATOR_ID','ios_physical':'SIMS_IOS_DEVICE_ID'}
    env = {roles[k]: v for k,v in config.get('devices', {}).items() if k in roles}
    env['SIMS_REPORT_PATH'] = str(report)
    env['SIMS_CHECKPOINT_PATH'] = str(report.with_suffix('.checkpoint.json'))
    return env


def inspect_sims(path, capability, code, timeout):
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
    not_applicable = [row for row in rows if capability == '*' and row.get('status') == 'N/A'
                      and row.get('reason') == 'target_unavailable_by_project_policy'
                      and row.get('blocker') == 'targetUnavailable'
                      and row.get('targetCapabilityAvailable') is False
                      and row.get('printOnly') is False and not row.get('assertionsAttempted')
                      and not row.get('artifactPresent') and not row.get('artifactEvidence')
                      and row.get('exitCode') in (None,0)]
    checked = [row for row in rows if row not in not_applicable]
    if code or not checked or any(row.get('status') != 'PASS' or not row.get('assertionsAttempted')
                   or not row.get('artifactPresent') or row.get('exitCode') != 0
                   or row.get('printOnly') is not False or row.get('blocker') is not None for row in checked):
        return {'status':'BLOCKED','checkpoint':'incomplete_sims_evidence'}
    return {'status':'PASS','checkpoint':'sims_assertions_and_artifact_observed','sims_report_sha256':file_hash(path),
            'builds':data.get('builds', {}), 'not_applicable':[r['capabilityId'] for r in not_applicable]}


def inspect_legacy(directory, code, timeout):
    summary = directory / 'summary.tsv'
    if not summary.is_file(): return {'status':'BLOCKED','checkpoint':'missing_full_regression_summary'}
    rows = [r.split('\t') for r in summary.read_text().splitlines() if r]
    statuses = [r[0] for r in rows]
    if 'FAIL' in statuses: return {'status':'FAIL','checkpoint':'legacy_route_failure',
                                 'failed_route_numbers':[i + 1 for i,r in enumerate(rows) if r[0] == 'FAIL']}
    if code or timeout or len(rows) != 95 or set(statuses) != {'PASS'}:
        return {'status':'BLOCKED','checkpoint':'incomplete_full_regression_routes'}
    logs = list((directory / 'logs').glob('*.log'))
    if len(logs) != 95: return {'status':'BLOCKED','checkpoint':'missing_full_regression_logs'}
    for log in logs:
        text = log.read_text(errors='replace')
        if re.search(r'No tests ran|No tests were found|0 tests? (?:passed|ran)|(?:Ran|Executed)\s+0\s+tests?|unbound variable|command not found', text, re.I):
            return {'status':'BLOCKED','checkpoint':'legacy_runner_incomplete', 'route_log':log.name}
        if re.search(r'~[1-9]\d*|--- SKIP:|\b[1-9]\d* (?:tests? )?skipped|\bskipped[=: ]+[1-9]\d*|"skipped"\s*:\s*true', text, re.I):
            return {'status':'BLOCKED','checkpoint':'legacy_skipped_tests', 'route_log':log.name}
    return {'status':'PASS','checkpoint':'legacy_95_routes_completed', 'route_count':95,
            'limitation':'Legacy per-route summaries are retained; case-level counts are not available for every nested runner.'}


def full_run(args, root, rules, directory, started):
    """Existing full entry points, serialized and identity-bound; no resume erasure."""
    validate(root, rules)
    commands = rules['full_commands']
    (directory / 'full-plan.json').write_text(json.dumps(commands, indent=2) + '\n')
    if args.plan:
        for c in commands: print(c['id'], ' '.join(c['command']))
        print('Full plan:', directory / 'full-plan.json'); return 0
    if not args.base: raise InvalidPlan('Full execution requires --base to record a common tested revision')
    config = json.loads(args.device_config.read_text()) if args.device_config else {}
    if not config.get('isolated_test_environment'): raise InvalidPlan('Full execution requires --device-config for isolated environments')
    # Full legacy campaigns may span days. No cancellation/resume or cross-revision merge.
    full_rules = json.loads(json.dumps(rules))
    full_rules['checks'] = {c['id']:c for c in commands}
    full_rules['fast'] = list(full_rules['checks']); full_rules['mandatory'] = []
    full_rules['areas'] = []; full_rules['conservative'] = []
    baseline = resolve_ref(root, args.base)
    if not args.local and git(root,'status','--porcelain','--untracked-files=normal').strip(): raise InvalidPlan('Full source is dirty; use --local or clean checkout')
    files = source_files(root)
    matrix = devices(root)
    plan = {'mode':'full', 'baseline':baseline, 'candidate_build':args.build_label,
            'toolchains':toolchain_identity(root),
            'identity':source_identity(root,files,rules), 'not_selected':[], 'unmapped_changes':[], 'selected':[]}
    for c in commands:
        check = dict(c)
        check['selected_paths'] = expand_paths(root, c.get('paths',[]), files) if c['kind'] == 'flutter' else c.get('paths',[])
        check['blocked_prerequisites'] = prerequisites(check,root,config,matrix)
        plan['selected'].append(check)
    # Preserve full workflow failures independently of release summaries.
    (directory / 'plan.json').write_text(json.dumps(plan,indent=2) + '\n')
    return execute_plan(args,root,rules,plan,files,config,matrix,directory,started)


if __name__ == '__main__':
    sys.exit(main())
