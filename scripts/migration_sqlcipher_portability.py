#!/usr/bin/env python3
"""Transfer the existing native SQLCipher fixture between two leased targets.

The Dart test owns encryption, checksum, schema and row assertions. This adapter
only supplies its existing defines and transfers its exact artifact. Appium UI
cannot establish SQLCipher portability. The protected legacy parent owns device
discovery, leases, preflight and the shared native build resource.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import sys
import uuid

import mknoon_checks as checks

TEST = 'integration_test/migration_database_sqlcipher_capability_test.dart'
MARKER = 'SQLCIPHER_PORTABILITY_COMPLETED android_to_ios'


def run(android, ios, output, *, root=checks.ROOT, env=None, launch=checks.launch):
    env = dict(os.environ if env is None else env)
    pins = json.loads(env.get('SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON', '{}'))
    if pins.get('android-physical') != android or pins.get('ios-simulator-a') != ios:
        raise ValueError('Portability requires both exact protected target assignments')
    output = Path(output).resolve()
    output.mkdir(parents=True, mode=0o700)
    fixture = output / 'fixture'
    fixture.mkdir(mode=0o700)
    relative = 'cache/mknoon-portability-' + uuid.uuid4().hex
    remote = '/data/user/0/com.mknoon.app/' + relative
    receipts = []

    def command(name, argv, timeout=900):
        raw, code, timed_out, seconds = launch(argv, root, timeout, env)
        log = output / (name + '.private.log')
        log.touch(mode=0o600)
        log.write_text(raw)
        receipts.append(dict(step=name, exit_status=code, timed_out=timed_out,
                             elapsed_seconds=seconds, log_sha256=checks.digest(raw)))
        (output/'steps.json').write_text(json.dumps(receipts, indent=2)+'\n')
        if code or timed_out:
            raise RuntimeError(name + ' failed; retained private log')
        return raw

    def native(name, target, define, marker):
        raw = command(name, ['flutter','test','--no-pub',TEST,'-d',target,
                             '--reporter=json','--dart-define='+define,
                             *(['--no-uninstall'] if name == 'android-export' else [])])
        facts = checks.parse_execution('flutter', raw, 0, selected_paths=[TEST])
        receipts[-1]['test_result'] = facts
        (output/'steps.json').write_text(json.dumps(receipts, indent=2)+'\n')
        if facts['status'] != 'PASS' or facts['counts'] != dict(passed=3, failed=0, skipped=0) or marker not in raw:
            raise RuntimeError(name + ' missing exact native assertions or portability marker')

    original_failure = None
    try:
        native('android-export', android, 'MIGRATION_PORTABILITY_EXPORT_DIR='+remote,
               'PORTABILITY_EXPORT_WRITTEN dir='+remote)
        for filename in ['portability.json', 'snapshot.db']:
            encoded = command('transfer-'+filename, ['adb','-s',android,'exec-out',
                              'run-as','com.mknoon.app','base64',relative+'/'+filename], 30)
            data = base64.b64decode(''.join(encoded.split()), validate=True)
            path = fixture / filename
            path.touch(mode=0o600)
            path.write_bytes(data)
        meta = json.loads((fixture/'portability.json').read_text())
        if meta.get('platform') != 'android' or hashlib.sha256((fixture/'snapshot.db').read_bytes()).hexdigest() != meta.get('checksum_sha256'):
            raise RuntimeError('Transferred source identity or snapshot checksum mismatch')
    except BaseException as error:
        original_failure = error
        raise
    finally:
        # Remove only this run's unique fixture files; never app data or peers.
        try:
            command('android-fixture-cleanup', ['adb','-s',android,'shell','run-as',
                    'com.mknoon.app','rm','-f',relative+'/snapshot.db',relative+'/portability.json'], 30)
            command('android-fixture-directory-cleanup', ['adb','-s',android,'shell','run-as',
                    'com.mknoon.app','rmdir',relative], 30)
            # Flutter normally uninstalls integration apps. Defer that step
            # until run-as has copied the fixture, then restore its behavior.
            command('android-test-app-cleanup', ['adb','-s',android,'uninstall','com.mknoon.app'], 60)
        except (OSError, RuntimeError):
            # Cleanup diagnostics remain in steps.json without hiding the first
            # native/export/transfer failure (including a never-created folder).
            if original_failure is None:
                raise
    native('ios-verify', ios, 'MIGRATION_PORTABILITY_FIXTURE_DIR='+str(fixture),
           'PORTABILITY_VERIFY_OK source=android target=ios')
    print(MARKER, flush=True)
    return receipts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--android', required=True)
    parser.add_argument('--ios', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    try:
        run(args.android, args.ios, args.output)
    except (ValueError, OSError, RuntimeError) as error:
        print('FAIL:', error, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
