#!/usr/bin/env python3
"""Protected execution of the two audited legacy inventories.

The shell listings remain the selection authority. Each selected leaf must have
an exact contract, including the bytes of every nested target owner. A new or
changed owner blocks that leaf, never grants it a default device. Device leases
and fresh preflight precede every command (including builds/preparation).
"""
from contextlib import ExitStack
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import signal
import threading
import sys
import tempfile
import uuid

import device_campaign_preflight as preflight
import mknoon_checks as checks

ROOT = Path(__file__).resolve().parents[1]
CATALOG = 'tool/testing/legacy_target_contracts.json'
PIN = 'SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON'


def contracts(root=ROOT):
    return json.loads((root / CATALOG).read_text())


def selected_routes(kind, args, root=ROOT):
    script = ('scripts/run_flutter_full_regression.sh' if kind == 'full'
              else 'scripts/run_reliability_simulations.sh')
    args = list(args)
    for option in ('--output', '--resume'):
        if option in args:
            index = args.index(option)
            del args[index:index + 2]
    with tempfile.TemporaryDirectory(prefix='legacy-list-') as temporary:
        listing_args = ['--output', str(Path(temporary) / 'listing')] if kind == 'full' else []
        output, code, timeout, _ = checks.launch(
            ['bash', script, *args, *listing_args, '--dry-run'], root, 120, os.environ.copy())
    if code or timeout:
        raise ValueError('Legacy selection listing failed: ' + output)
    if kind == 'full':
        return re.findall(r'^RUN \d+/095 (.+)$', output, re.M)
    result = []
    for line in output.splitlines():
        if not re.match(r'^\s*\d+\. ', line):
            continue
        argv = shlex.split(re.sub(r'^\s*\d+\. ', '', line))
        path = next((s.removeprefix('./') for s in argv if s.endswith(('.dart', '.sh'))), None)
        if not path:
            raise ValueError('Unknown legacy listing')
        scenario = argv[argv.index('--scenario') + 1] if '--scenario' in argv else ''
        scenario = next((s.split('=', 1)[1] for s in argv
                         if s.startswith('--dart-define=GROUP_SIM_SCENARIO=')), scenario)
        result.append(path + (':' + scenario if scenario else ''))
    if not result or len(set(result)) != len(result):
        raise ValueError('Empty or duplicate legacy selection')
    return result


def bind(contract, pins, config, output, root=ROOT):
    """Pure validation/binding; raises before any child or preparation starts."""
    allowed_roles = {'android-physical','android-emulator','android-emulator-second','ios-physical','macos', *('ios-simulator-' + x for x in 'abcd')}
    if not isinstance(pins, dict) or set(pins) - allowed_roles or any(
            not isinstance(k, str) or not isinstance(v, str) or
            not re.fullmatch(r'[A-Za-z0-9_.:-]+', v) or v in ('booted', 'all')
            for k, v in pins.items()):
        raise ValueError('Invalid protected assignments')
    for path, digest in contract['sources'].items():
        if not (root / path).is_file() or checks.file_hash(root / path) != digest:
            raise ValueError('Target owner changed: ' + path)
    roles = contract['roles']
    if any(role not in pins for role in roles):
        raise ValueError('Missing explicit target role')
    if len({pins[r] for r in roles}) != len(roles):
        raise ValueError('Target roles must be distinct')
    values = {'output': str(output), **{'device:' + r: pins[r] for r in roles}}
    for key in contract.get('config', []):
        value = config.get(key)
        if not isinstance(value, str) or not value.strip():
            raise ValueError('Missing fixture configuration: ' + key)
        values['config:' + key] = value
    def expand(s):
        return re.sub(r'\{([^}]+)\}', lambda m: values[m[1]], s)
    if contract.get('disposable_simulators') and (set(config['ios_disposable_simulator_ids'].split(',')) != {pins[r] for r in roles}):
        raise ValueError('Explicit disposal authorization must name exactly this simulator topology')
    commands = [[expand(s) for s in cmd] for cmd in contract['commands']]
    env = {k: expand(v) for k, v in contract.get('environment', {}).items()}
    if 'command_completion_markers' in contract:
        if len(contract['command_completion_markers']) != len(commands):
            raise ValueError('Each independent command requires its exact receipt')
        for marker in contract['command_completion_markers']:
            expand(marker)  # Reject unknown receipt bindings before launch.
    return commands, env


def role_config(pins):
    return {('ios_simulator' if k == 'ios-simulator-a' else k.replace('-', '_')): v
            for k, v in pins.items()}


def availability(roles, pins, matrix):
    """Missing pins are never auto-selected; N/A needs successful discovery."""
    relevant = ['flutter'] + (['adb'] if any(r.startswith('android') for r in roles) else []) + (['ios_simulators'] if any(r.startswith('ios-simulator') for r in roles) else [])
    if any(any(e.startswith(source) for source in relevant) for e in matrix.get('errors', [])):
        return 'BLOCKED'
    live = matrix.get('flutter', [])
    if any(not isinstance(d.get('id'), str) or not isinstance(d.get('targetPlatform'), str) or type(d.get('emulator')) is not bool for d in live):
        return 'BLOCKED'
    def matches(role, d):
        platform = d.get('targetPlatform', '')
        if role.startswith('ios-simulator'):
            return platform == 'ios' and d.get('emulator') is True and d['id'] in matrix['ios_simulators']
        if role == 'ios-physical':
            return platform == 'ios' and d.get('emulator') is False
        if role.startswith('android'):
            return (platform.startswith('android') and d['id'] in matrix['adb'] and
                    d.get('emulator') == (role != 'android-physical'))
        return role == 'macos' and platform == 'darwin'
    for role in roles:
        if role in pins and not any(d['id'] == pins[role] and matches(role, d) for d in live):
            return 'BLOCKED'
    missing = [r for r in roles if r not in pins]
    if missing:
        # Count the available targets in each required class. A four-simulator
        # leg is unavailable when only two are present, without blocking pairs.
        for role in missing:
            need = sum(r.startswith('ios-simulator') for r in roles) if role.startswith('ios-simulator') else 1
            if sum(matches(role, d) for d in live) < need:
                return 'N/A'
        return 'BLOCKED'
    return 'AVAILABLE'


def execute(kind, labels, output, *, root=ROOT, env=None, matrix=None, launch=None):
    env = dict(os.environ if env is None else env)
    launch = launch or checks.launch
    catalog = contracts(root)[kind]
    output.mkdir(parents=True, exist_ok=False)
    os.chmod(output, 0o700)
    (output / 'logs').mkdir()
    pins = json.loads(env.get(PIN, '{}'))
    config = json.loads(env.get('MKNOON_LEGACY_CONFIG_JSON', '{}'))
    receipts = []
    cleanup_pending = env.get('MKNOON_LEGACY_CLEANUP_PENDING') == '1'
    cancel = getattr(checks._LAUNCH_CONTEXT, 'cancel_event', None)
    for index, label in enumerate(labels, 1):
        row = dict(id=label, status='BLOCKED', checkpoint='unknown_legacy_route')
        text = ''
        log = output / 'logs' / f'{index:03d}.log'
        contract = catalog.get(label)
        launched = False
        try:
            if cancel is not None and cancel.is_set():
                row.update(status='NOT RUN', checkpoint='run_cancelled')
                continue
            if contract is None:
                raise ValueError('Unknown route')
            roles = contract['roles']
            # Audit source bytes even if the hardware is absent. Implementation
            # drift must not become a policy N/A.
            for path, digest in contract['sources'].items():
                if checks.file_hash(root / path) != digest:
                    raise ValueError('Target owner changed: ' + path)
            for key in contract.get('config', []):
                if not isinstance(config.get(key), str) or not config[key].strip():
                    raise ValueError('Missing fixture configuration: ' + key)
            if roles:
                if env.get('MKNOON_LEGACY_ISOLATED') != '1':
                    raise ValueError('Isolated fixture configuration required')
                if matrix is None:
                    matrix = checks.devices(root)
                state = availability(roles, pins, matrix)
                if state != 'AVAILABLE':
                    row.update(status=state, checkpoint='target_unavailable_by_project_policy' if state == 'N/A' else 'target_binding_unavailable')
                    continue
                if cleanup_pending:
                    row.update(status='NOT RUN', checkpoint='device_cleanup_review_required')
                    continue
            commands, bindings = bind(contract, pins, config, output / f'route-{index}', root)
            child = dict(env)
            # All target-bearing legacy defaults are cleared, then only the
            # route's documented injection points are restored.
            for name in list(child):
                if name.startswith(('SIMS_ANDROID_', 'SIMS_IOS_', 'RELIABILITY_', 'DEVICE_')) or name in (
                    'FLUTTER_DEVICE_ID', 'FLUTTER_MULTI_DEVICE_IDS', 'IOS_NOTIFICATION_TAP_DEVICES',
                    'SIMULATOR_DEVICE', 'IOS_SECONDARY_SIMULATOR_DEVICE', 'ANDROID_SERIAL'):
                    child.pop(name)
            scoped = {r: pins[r] for r in roles}
            child.update(checks.sims_environment({'devices':role_config(scoped)}, output / f'sims-{index}.json'))
            child.update(bindings)
            if contract.get('config'):
                child['MKNOON_RELAY_ADDRESSES'] = config.get('relay_addresses', '')
            with ExitStack() as owned:
                owned.enter_context(preflight.device_leases(scoped.values()))
                if roles:
                    check = dict(kind='full_adapter', device_roles=list(role_config(scoped)))
                    receipt = preflight.run(check, root, {'devices':role_config(scoped)}, launch, child)
                    if receipt['status'] != 'PASS':
                        row.update(status='BLOCKED', checkpoint=receipt['checkpoint'])
                        continue
                row.update(status='PASS', checkpoint='protected_legacy_route_completed')
                for command_index, command in enumerate(commands):
                    if cancel is not None and cancel.is_set():
                        if row['status'] == 'PASS':
                            row.update(status='NOT RUN', checkpoint='run_cancelled')
                        if contract.get('command_completion_markers'):
                            row.setdefault('command_results', []).append(dict(
                                index=command_index, status='NOT RUN', checkpoint='run_cancelled'))
                        break
                    launched = bool(roles)
                    part, code, timed_out, _ = launch(command, root, contract.get('timeout_seconds', 14400), child)
                    text += part
                    command_status = 'PASS'
                    checkpoint = 'protected_legacy_route_completed'
                    if code or timed_out:
                        command_status = 'BLOCKED' if timed_out or code == 78 or ('BLOCKED' in part and not re.search(r'^FAIL[\t ]', part, re.M)) else 'FAIL'
                        checkpoint = 'legacy_child_failed'
                    elif re.search(r'\[SKIP\]|\[BLOCKED\]|No tests ran|No tests were found|--- SKIP:|"skipped"\s*:\s*true', part):
                        command_status, checkpoint = 'BLOCKED', 'legacy_child_incomplete'
                    markers = contract.get('command_completion_markers')
                    if markers:
                        marker = markers[command_index]
                        for role in roles:
                            marker = marker.replace('{device:' + role + '}', pins[role])
                        if command_status == 'PASS' and part.splitlines().count(marker) != 1:
                            command_status, checkpoint = 'BLOCKED', 'missing_legacy_child_receipt'
                        row.setdefault('command_results', []).append(dict(
                            index=command_index, status=command_status,
                            checkpoint=checkpoint, receipt_sha256=checks.digest(marker)))
                    # Independent benchmark partitions retain the first failure
                    # while attempting the other selection. Build/dependent
                    # command chains keep their existing stop-on-failure policy.
                    if command_status != 'PASS':
                        if row['status'] != 'FAIL':
                            row.update(status=command_status, checkpoint=checkpoint)
                        if not contract.get('independent_commands') or timed_out or code == 78:
                            break
                if row['status'] == 'PASS' and contract.get('completion_marker') and contract['completion_marker'] not in text:
                    row.update(status='BLOCKED', checkpoint='missing_legacy_child_receipt')
                row['contract_sha256'] = checks.digest(contract)
        except (ValueError, KeyError, OSError, preflight.DeviceLeaseBusy) as error:
            text += str(error) + '\n'
            row.update(status='BLOCKED', checkpoint='legacy_contract_invalid')
        finally:
            if launched and row['status'] != 'PASS':
                cleanup_pending = True
            log.write_text(text)
            os.chmod(log, 0o600)
            row['log_sha256'] = checks.file_hash(log)
            receipts.append(row)
            (output / 'routes.json').write_text(json.dumps(receipts, indent=2) + '\n')
            (output / 'summary.tsv').write_text(''.join(
                f"{r['status']}\t{r['id']}\tlogs/{i:03d}.log\t0s\n" for i, r in enumerate(receipts, 1)))
            print(row['status'], label, flush=True)
    statuses = {r['status'] for r in receipts}
    status = 'FAIL' if 'FAIL' in statuses else 'BLOCKED' if statuses - {'PASS', 'N/A'} or not statuses else 'N/A' if statuses == {'N/A'} else 'PASS'
    return dict(status=status, route_results=receipts, cleanup_review_required=cleanup_pending)


def install_cancellation():
    # The parent launcher kills this process group. Our own children have
    # bounded groups too; forward cancellation before releasing any lease.
    cancel = threading.Event()
    checks._LAUNCH_CONTEXT.cancel_event = cancel
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: cancel.set())


def main():
    install_cancellation()
    kind, *args = sys.argv[1:]
    if kind not in ('full', 'reliability') or PIN not in os.environ:
        raise ValueError('Explicit protected legacy boundary required')
    labels = selected_routes(kind, args)
    if kind == 'reliability' and os.environ.get('MKNOON_LEGACY_RECEIPT_DIRECTORY'):
        output = Path(os.environ['MKNOON_LEGACY_RECEIPT_DIRECTORY'])
    elif '--output' in args:
        output = Path(args[args.index('--output') + 1])
    else:
        output = Path(os.environ.get('SIMS_PROOF_DIRECTORY', 'build/legacy-proofs')) / uuid.uuid4().hex
    result = execute(kind, labels, output)
    if kind == 'reliability':
        status = result['status']
        code = 78 if status == 'BLOCKED' else 0 if status == 'N/A' else checks.EXIT[status]
        sentinel = dict(status=status, assertionsAttempted=0 if status in ('BLOCKED','N/A') else len([r for r in result['route_results'] if r['status'] in ('PASS','FAIL')]),
                        artifactPresent=status == 'PASS', printOnly=False, exitCode=code)
        if status == 'N/A':
            sentinel.update(blocker='targetUnavailable', targetCapabilityAvailable=False, reason='target_unavailable_by_project_policy')
        elif status != 'PASS': sentinel['blocker'] = 'environment' if status == 'BLOCKED' else 'harness'
        print('SIMS_RESULT_JSON=' + json.dumps(sentinel))
    if result['status'] == 'N/A': return 0
    return (78 if result['status'] == 'BLOCKED' else checks.EXIT[result['status']]) if kind == 'reliability' else checks.EXIT[result['status']]


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, OSError) as error:
        print('BLOCKED:', error, file=sys.stderr)
        sys.exit(2)
