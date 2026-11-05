#!/usr/bin/env python3
"""Exact upstream camera XCTest host, with owned baseline/patched source copies.

This is native configuration-fault proof, not UI automation or playable-media proof.
No candidate source, pub cache, SDK, existing outputs or foreign processes are edited.
"""
from __future__ import annotations

import argparse
from collections import Counter
from contextlib import ExitStack
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.parse import unquote, urlparse
import uuid

import device_campaign_preflight as pre
import mknoon_checks as checks

ROOT = Path(__file__).resolve().parents[1]
VENDOR = Path('third_party/camera_avfoundation')
RUNTIME = Path('darwin/camera_avfoundation/Sources/camera_avfoundation/DefaultCamera.swift')
TEST_CLASS = 'CameraSampleBufferTests'
METHODS = (
    'testRecordingSwitchCreationFailurePreservesCapture',
    'testRecordingSwitchInputRejectionRestoresCapture',
    'testRecordingSwitchOutputRejectionRestoresCapture',
    'testRecordingSwitchConnectionRejectionRestoresCapture',
)
CASE = re.compile(r"Test Case '-\[(?:\w+\.)*CameraSampleBufferTests (\w+)\]' (passed|failed|skipped)")
FAULT = re.compile(r"error: -\[(?:\w+\.)*CameraSampleBufferTests (\w+)\] : [^\n]*CAMERA_SWITCH_RECOVERY")
NA = 'target_unavailable_by_project_policy'
CAPABILITY = 'native.camera.recording_switch'
ARTIFACT_VALIDATOR = 'validateCameraRecordingSwitchComparison'


class SetupError(RuntimeError):
    pass


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    os.chmod(path, 0o600)


def adjudicate(text, code, timed_out, variant):
    """Setup/compiler/process failures can never certify expected native RED."""
    events = CASE.findall(text)
    counts = {s: sum(state == s for _, state in events) for s in ('passed', 'failed', 'skipped')}
    complete = Counter(name for name, _ in events) == Counter(METHODS)
    fault_cases = set(FAULT.findall(text)) & set(METHODS)
    result = dict(status='BLOCKED', counts=counts, completion_observed=False,
                  exit_status=code, timed_out=timed_out, fault_cases=sorted(fault_cases))
    if timed_out or code == 93 or '** BUILD FAILED **' in text or not complete:
        return result
    if variant == 'baseline':
        expected = (code > 0 and counts['failed'] == 4 and not counts['skipped']
                    and fault_cases == set(METHODS) and '** TEST FAILED **' in text)
        result['status'] = 'EXPECTED_RED' if expected else 'FAIL'
    else:
        passed = code == 0 and counts['passed'] == 4 and '** TEST SUCCEEDED **' in text
        result['status'] = 'PASS' if passed else 'FAIL'
    result['completion_observed'] = True
    return result


def tracked_vendor():
    paths = subprocess.check_output(['git', 'ls-files', '--', str(VENDOR)], cwd=ROOT,
                                    text=True).splitlines()
    if not paths:
        raise SetupError('Freeze and commit the vendor before native execution')
    return [Path(p) for p in paths]


def prepare_variant(destination, variant, files):
    """Only this invocation's new scratch copy may receive the original runtime."""
    destination.mkdir(parents=True, exist_ok=False)
    for relative in files:
        source = ROOT / relative
        if source.is_symlink():
            raise SetupError('Vendor source symlinks are not accepted')
        target = destination / relative.relative_to(VENDOR)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    upstream = json.loads((destination / 'UPSTREAM.json').read_text())
    original = destination / upstream['original_runtime']
    if sha(original) != upstream['files'][str(RUNTIME)]:
        raise SetupError('Retained original runtime does not match upstream provenance')
    if variant == 'baseline':
        shutil.copyfile(original, destination / RUNTIME)
    return {str(p.relative_to(VENDOR)): sha(destination / p.relative_to(VENDOR)) for p in files}


def flutter_context():
    package = json.loads((ROOT / '.dart_tool/package_config.json').read_text())
    uri = next(p['rootUri'] for p in package['packages'] if p['name'] == 'flutter')
    flutter_root = (ROOT / '.dart_tool' / unquote(urlparse(uri).path)).resolve()
    sdk = flutter_root.parents[1]
    version = json.loads((sdk / 'bin/cache/flutter.version.json').read_text())['frameworkVersion']
    expected = json.loads((ROOT / '.fvmrc').read_text())['flutter']
    if version != expected:
        raise SetupError('Candidate package_config SDK differs from .fvmrc')
    env = dict(os.environ, PATH=str(sdk / 'bin') + os.pathsep + os.environ.get('PATH', ''),
               CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true')
    return str(sdk / 'bin/flutter'), version, env


def run_step(output, name, argv, cwd, env, timeout):
    raw = output / (name + '.raw.log')
    text, code, timed_out, elapsed = checks.launch_to_log(argv, cwd, timeout, env, raw)
    save(output / (name + '.json'), dict(command=argv, cwd=str(cwd), exit_status=code,
         timed_out=timed_out, seconds=elapsed, raw_sha256=sha(raw)))
    return text, code, timed_out


def require_step(output, name, argv, cwd, env, timeout):
    text, code, timed_out = run_step(output, name, argv, cwd, env, timeout)
    if code or timed_out:
        raise SetupError(name + ' did not complete; preserve its original raw/exit receipt')
    return text


def run_variant(output, variant, files, target, flutter, version, env):
    folder = output / variant
    folder.mkdir(mode=0o700)
    # Both the compilation source and DerivedData are new, internal-disk paths.
    scratch = Path(tempfile.mkdtemp(prefix='tmp-dd-camera-' + variant + '-', dir=Path.home()))
    plugin = scratch / 'source/camera_avfoundation'
    identities = prepare_variant(plugin, variant, files)
    example = plugin / 'example'
    save(folder / 'inputs.json', dict(variant=variant, head=subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), simulator_id=target,
        flutter_version=version, source_sha256=identities, scratch=str(scratch),
        derived_data=str(scratch / 'derived'), fixture_selectors=list(METHODS)))
    lock = example / 'pubspec.lock'
    if not lock.is_file():
        raise SetupError('Native example needs its committed offline-resolved lock')
    lock_hash = sha(lock)
    require_step(folder, 'pub', [flutter, 'pub', 'get', '--offline', '--enforce-lockfile'],
                 example, env, 300)
    if sha(lock) != lock_hash:
        raise SetupError('Native example dependency resolution changed its pinned lock')
    require_step(folder, 'configuration', [flutter, 'build', 'ios', '--simulator',
                 '--config-only', '--debug', '--no-pub', '--target', 'lib/main.dart'], example, env, 300)
    packages = json.loads((example / '.dart_tool/package_config.json').read_text())
    camera_uri = next(p['rootUri'] for p in packages['packages'] if p['name'] == 'camera_avfoundation')
    resolved_camera = (example / '.dart_tool' / unquote(urlparse(camera_uri).path)).resolve()
    if resolved_camera != plugin.resolve():
        raise SetupError('Example resolved a camera plugin outside its owned variant')
    actual_sources = {str(p.relative_to(VENDOR)): sha(plugin / p.relative_to(VENDOR)) for p in files}
    # Configuration may migrate the copied Xcode host. Seal its actual generated
    # build inputs too; runtime and assertion sources must remain exactly pinned.
    for path in identities:
        if path.startswith(('darwin/', 'lib/')) and actual_sources[path] != identities[path]:
            raise SetupError('Setup changed a native runtime/test or Dart plugin source')
    generated = {}
    for tree in [example / 'ios/Flutter', example / 'ios/Runner', example / '.dart_tool']:
        for path in tree.rglob('*'):
            if path.is_file() and path.suffix in ('.xcconfig', '.swift', '.h', '.m', '.json'):
                generated[str(path.relative_to(plugin))] = sha(path)
    save(folder / 'build-inputs.json', dict(source_sha256=actual_sources,
         generated_sha256=generated, resolved_camera_root=str(resolved_camera)))
    result_bundle = folder / 'native.xcresult'
    command = ['xcodebuild', 'test', '-project', str(example / 'ios/Runner.xcodeproj'),
               '-scheme', 'Runner', '-configuration', 'Debug', '-destination',
               'platform=iOS Simulator,id=' + target, '-derivedDataPath', str(scratch / 'derived'),
               '-resultBundlePath', str(result_bundle), '-clonedSourcePackagesDirPath',
               str(scratch / 'source-packages'), '-jobs', '1',
               '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO',
               'CODE_SIGNING_REQUIRED=NO', 'CLANG_MODULE_CACHE_PATH=' + str(scratch / 'module-cache'),
               'SWIFT_MODULE_CACHE_PATH=' + str(scratch / 'swift-module-cache')]
    command += ['-only-testing:RunnerTests/' + TEST_CLASS + '/' + method for method in METHODS]
    text, code, timed_out = run_step(folder, 'xctest', command, example, env, 1800)
    proof = adjudicate(text, code, timed_out, variant)
    if not result_bundle.is_dir():
        proof.update(status='BLOCKED', completion_observed=False, reason='missing_xcresult')
    proof['input_identity_sha256'] = sha(folder / 'inputs.json')
    proof['build_inputs_sha256'] = sha(folder / 'build-inputs.json')
    save(folder / 'result.json', proof)
    return proof, identities


def execute(args, output):
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip():
        raise SetupError('Native execution requires a clean, committed camera candidate')
    flutter, version, env = flutter_context()
    matrix = require_step(output, 'simulators', ['xcrun', 'simctl', 'list', 'devices',
                          'available', '--json'], ROOT, env, 30)
    devices = [d for runtime, rows in json.loads(matrix)['devices'].items() if 'iOS' in runtime
               for d in rows if d.get('isAvailable')]
    protected = json.loads(env.get('SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON', '{}'))
    pinned = (args.simulator_id or env.get('MKNOON_NATIVE_IOS_SIMULATOR_ID')
              or env.get('SIMS_IOS_SIMULATOR_ID') or protected.get('ios_simulator'))
    if not devices or (pinned and pinned not in {d['udid'] for d in devices}):
        return dict(status='N/A', assertionsAttempted=0, blocker='targetUnavailable',
                    targetCapabilityAvailable=False, reason=NA), 0
    if not pinned:
        raise SetupError('Pin an explicitly discovered --simulator-id; automatic fallback is disabled')
    if protected and pinned not in protected.values():
        raise SetupError('Exact simulator differs from the parent lease assignment')
    files = tracked_vendor()
    vendor = ROOT / VENDOR
    if not (vendor / 'example/pubspec.lock').is_file():
        raise SetupError('Native example lock is absent')
    if 'enable-swift-package-manager: true' not in (vendor / 'example/pubspec.yaml').read_text():
        raise SetupError('Native example must pin SPM locally; do not change global Flutter config')
    source = (vendor / 'darwin/Tests/SampleBufferTests.swift').read_text()
    if any(source.count('func ' + method + '(') != 1 for method in METHODS):
        raise SetupError('Exact native fault selectors are absent or duplicated')
    require_step(output, 'xcode-version', ['xcodebuild', '-version'], ROOT, env, 30)
    save(output / 'setup.json', dict(simulator_id=pinned, flutter_version=version,
         candidate_head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT,
                                                text=True).strip(), variant=args.variant))
    if args.setup_check:
        # Setup facts never certify a scenario and deliberately carry no PASS sentinel.
        return dict(status='SETUP_READY', assertionsAttempted=0), 0
    variants = ['baseline', 'patched'] if args.variant == 'both' else [args.variant]
    results, source_ids = {}, {}
    with ExitStack() as owners:
        # Match the existing native wrapper's admission window. Only admission
        # waits repeat; a launched setup/test variant is never automatically retried.
        deadline = time.monotonic() + 3 * 3600
        while True:
            if pre.default_host_guard():
                try:
                    if not protected:
                        owners.enter_context(pre.device_leases([pre.NATIVE_LEASE, pinned]))
                except pre.DeviceLeaseBusy:
                    pass
                else:
                    break
            if time.monotonic() >= deadline:
                raise SetupError('Native capacity/device lease admission did not complete')
            time.sleep(15)
        live = require_step(output, 'leased-simulator', ['xcrun', 'simctl', 'list', 'devices',
                            'available', '--json'], ROOT, env, 30)
        if not any(d['udid'] == pinned and d.get('isAvailable')
                   for runtime, rows in json.loads(live)['devices'].items() if 'iOS' in runtime
                   for d in rows):
            return dict(status='N/A', assertionsAttempted=0, blocker='targetUnavailable',
                        targetCapabilityAvailable=False, reason=NA), 0
        for variant in variants:
            results[variant], source_ids[variant] = run_variant(
                output, variant, files, pinned, flutter, version, env)
            expected = 'EXPECTED_RED' if variant == 'baseline' else 'PASS'
            if results[variant]['status'] != expected:
                status = results[variant]['status']
                return dict(status=status, assertionsAttempted=sum(results[variant]['counts'].values()),
                            blocker='harness' if status == 'BLOCKED' else 'test', variants=results), 2
    if len(source_ids) == 2:
        differences = [p for p in source_ids['baseline']
                       if source_ids['baseline'][p] != source_ids['patched'][p]]
        if differences != [str(RUNTIME)]:
            raise SetupError('Baseline/patched variants differ beyond the original runtime')
    save(output / 'comparison.json', dict(variants=results, same_fixture=True,
         runtime_only_delta=str(RUNTIME), source_identities=source_ids))
    if args.variant == 'baseline':
        return dict(status='EXPECTED_RED', assertionsAttempted=4, variants=results), 0
    return dict(status='PASS', assertionsAttempted=4, variants=results), 0


def write_comparison_evidence(output, result):
    """Bind only this invocation's complete native comparison to durable proof."""
    manifest = json.loads((ROOT / 'tool/sims/critical_features.json').read_text())
    row = next(row for row in manifest['capabilities'] if row['id'] == CAPABILITY)
    if (row.get('artifactRequired') is not True
            or row.get('artifactValidator') != ARTIFACT_VALIDATOR
            or row.get('artifactValidators', [ARTIFACT_VALIDATOR]) != [ARTIFACT_VALIDATOR]):
        raise SetupError('Camera comparison artifact declaration differs from its producer')
    comparison_path = output / 'comparison.json'
    comparison = json.loads(comparison_path.read_text())
    variants = result.get('variants', {})
    if (set(variants) != {'baseline', 'patched'} or comparison.get('variants') != variants
            or comparison.get('same_fixture') is not True
            or comparison.get('runtime_only_delta') != str(RUNTIME)):
        raise SetupError('Durable camera comparison is missing or incomplete')
    sources = comparison['source_identities']
    if (set(sources) != {'baseline', 'patched'}
            or sources['baseline'].keys() != sources['patched'].keys()
            or [p for p in sources['baseline']
                if sources['baseline'][p] != sources['patched'][p]] != [str(RUNTIME)]):
        raise SetupError('Camera proof must retain the same fixture and only runtime delta')

    def reference(path):
        return dict(path=str(path.resolve(strict=True)), sha256=sha(path))

    receipts = {}
    for variant, proof in variants.items():
        folder = output / variant
        inputs = json.loads((folder / 'inputs.json').read_text())
        step = json.loads((folder / 'xctest.json').read_text())
        observed = adjudicate((folder / 'xctest.raw.log').read_text(),
                              step['exit_status'], step['timed_out'], variant)
        expected = 'EXPECTED_RED' if variant == 'baseline' else 'PASS'
        bundle = folder / 'native.xcresult'
        if (proof.get('status') != expected or observed['status'] != expected
                or any(proof.get(key) != value for key, value in observed.items())
                or json.loads((folder / 'result.json').read_text()) != proof
                or proof.get('input_identity_sha256') != sha(folder / 'inputs.json')
                or proof.get('build_inputs_sha256') != sha(folder / 'build-inputs.json')
                or step.get('raw_sha256') != sha(folder / 'xctest.raw.log')
                or inputs.get('variant') != variant
                or inputs.get('fixture_selectors') != list(METHODS)
                or inputs.get('source_sha256') != sources[variant]
                or not bundle.is_dir() or not any(bundle.iterdir())):
            raise SetupError('Camera ' + variant + ' proof lacks complete native receipts')
        receipts[variant] = {name: reference(folder / name) for name in (
            'result.json', 'inputs.json', 'build-inputs.json', 'xctest.json', 'xctest.raw.log')}
        receipts[variant]['xcresult'] = dict(path=str(bundle.resolve(strict=True)))
    payload = dict(schema='mknoon.sims.proof.v1', capabilityId=CAPABILITY,
                   validatorIds=[ARTIFACT_VALIDATOR], comparison=reference(comparison_path),
                   variants=receipts)
    temporary, artifact = output / 'comparison-proof.json.tmp', output / 'comparison-proof.json'
    save(temporary, payload)
    temporary.replace(artifact)
    return dict(**reference(artifact), validatorIds=[ARTIFACT_VALIDATOR])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--variant', choices=['baseline', 'patched', 'both'], default='both')
    parser.add_argument('--simulator-id')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--setup-check', action='store_true')
    args = parser.parse_args(argv)
    os.umask(0o077)
    capture = Path(os.environ.get('MKNOON_CAPTURE_ROOT', ROOT / '.codex-test-logs'))
    output = args.output or capture / ('camera-native-' + time.strftime('%Y%m%dT%H%M%S') + '-' + uuid.uuid4().hex[:8])
    output.mkdir(parents=True, mode=0o700, exist_ok=False)
    checks._LAUNCH_CONTEXT.capture_budget = checks.CaptureBudget()
    result = {}
    try:
        result, code = execute(args, output)
        if result['status'] == 'PASS' and code == 0 and args.variant == 'both':
            result['artifactEvidence'] = write_comparison_evidence(output, result)
    except (SetupError, pre.DeviceLeaseBusy, OSError, ValueError, KeyError, StopIteration) as error:
        result, code = dict(status='BLOCKED', assertionsAttempted=0, blocker='harness',
                            detail=str(error), variants=result.get('variants', {})), 2
    save(output / 'result.json', result)
    if result['status'] not in ('SETUP_READY', 'EXPECTED_RED'):
        wire = {k: result[k] for k in ('status', 'assertionsAttempted', 'blocker',
                'targetCapabilityAvailable', 'reason', 'detail') if k in result}
        evidence = result.get('artifactEvidence')
        wire.update(artifactPresent=evidence is not None, printOnly=False, exitCode=code)
        if evidence is not None:
            wire['artifactEvidence'] = evidence
        print('SIMS_RESULT_JSON=' + json.dumps(wire, sort_keys=True))
    print('Camera native receipt: ' + str(output / 'result.json'))
    return code


if __name__ == '__main__':
    sys.exit(main())
