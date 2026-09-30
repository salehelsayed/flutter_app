"""Run one pinned Maestro flow and require its exact successful JUnit receipt.

The enclosing check wrapper owns device leases and setup checks. This adapter
does not install applications, drive UI itself, build, or retry failed flows.
"""
import argparse
import hashlib
import json
import os
import signal
from pathlib import Path
import subprocess
import time
import xml.etree.ElementTree as ET


def validate_flow_receipts(report, expected_names):
    root = ET.parse(report).getroot()
    cases = list(root.iter('testcase'))
    names = [case.get('name') for case in cases]
    if len(names) != len(set(names)) or sorted(names) != sorted(expected_names):
        raise ValueError('missing, duplicate, or unexpected Maestro flow receipt')
    for case in cases:
        if any(case.find(tag) is not None for tag in ('failure', 'error', 'skipped')):
            raise ValueError('Maestro flow did not pass')
        if case.get('status', '').lower() in ('skipped', 'failed', 'disabled', 'error', 'cancelled', 'canceled'):
            raise ValueError('Maestro flow did not execute successfully')
    for suite in root.iter('testsuite'):
        for key in ('failures', 'errors', 'skipped', 'disabled'):
            if int(suite.get(key, '0')) != 0:
                raise ValueError('Maestro suite has incomplete or failed flows')
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--flow', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expected-name', required=True)
    parser.add_argument('--env', action='append', default=[])
    parser.add_argument('--maestro', default='maestro')
    args = parser.parse_args()
    if not args.flow.is_file() or not args.device.strip():
        parser.error('existing flow and explicit target required')
    args.output.mkdir(parents=True, exist_ok=False)
    command = [args.maestro, 'test', '--device', args.device,
               '--format', 'JUNIT', '--output', str(args.output / 'junit.xml'),
               '--debug-output', str(args.output / 'debug')]
    for value in args.env:
        command.extend(['--env', value])
    command.append(str(args.flow))
    start = time.monotonic()
    timed_out = False
    with (args.output / 'process.log').open('wb') as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=110)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            code = 124
    names = []
    error = None
    try:
        if timed_out:
            raise ValueError('Maestro flow timed out; owned process group terminated')
        if code:
            raise ValueError('Maestro exited unsuccessfully')
        names = validate_flow_receipts(args.output / 'junit.xml', [args.expected_name])
    except (ValueError, OSError, ET.ParseError) as failure:
        error = str(failure)
    receipt = {'status': 'PASS' if error is None else 'FAIL', 'flows': names,
               'flow_sha256': hashlib.sha256(args.flow.read_bytes()).hexdigest(),
               'duration_seconds': time.monotonic() - start, 'error': error,
               'exit_status': code}
    (args.output / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return 0 if error is None else 1


if __name__ == '__main__':
    raise SystemExit(main())
