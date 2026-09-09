#!/usr/bin/env python3
"""Save a protected aggregate report and emit only changed diagnostic alerts."""
import argparse
import fcntl
import importlib.util
import json
import os
import pathlib
import signal
import sys
import tempfile
import time

MAX_BYTES = 512 << 10
ALLOWED = {
    'diagnostic_evidence_incomplete', 'preflight_rejection_high',
    'technical_setup_failure_high', 'answered_without_verified_media_high',
    'drop_after_media_high', 'cleanup_failure_high', 'provider_failure_high',
    'credential_failure_high', 'telemetry_loss_high', 'telemetry_loss_observed',
    'withdrawal_unknown_origin_high',
}


def atomic_write(path, value):
    raw = json.dumps(value, separators=(',', ':')).encode() + b'\n'
    if len(raw) > MAX_BYTES:
        raise ValueError('report quota')
    fd, temporary = tempfile.mkstemp(prefix='.call-monitor-', dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'wb') as target:
            target.write(raw)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_cache(path):
    try:
        if path.is_symlink() or path.stat().st_size > MAX_BYTES:
            return {}
        value = json.loads(path.read_bytes())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def run_tick(operator, directory, destination, now_ms=None, writer=atomic_write):
    now_ms = int(time.time()*1000) if now_ms is None else now_ms
    directory, destination = pathlib.Path(directory), pathlib.Path(destination)
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if destination.parent.is_symlink():
        raise ValueError('output directory')
    os.chmod(destination.parent, 0o700)
    with os.fdopen(os.open(destination.parent/'monitor.lock', os.O_CREAT | os.O_RDWR, 0o600), 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state_path = destination.parent/'state.json'
        prior = read_cache(state_path)
        old_report = read_cache(destination)
        samples = {}
        rows, rejected = operator.read_records(directory, now_ms-3600000, None, 1000,
                                               now_ms=now_ms, _loss_samples=samples)
        report = operator.report(rows, rejected, since_ms=now_ms-3600000, now_ms=now_ms)
        interval, baseline = operator.counter_interval(samples, prior.get('lossBaseline', {}), now_ms)
        report['loss']['observedInterval'] = interval
        report['generatedAtMs'] = now_ms
        report['windowHours'] = 1
        report['recordLimit'] = 1000
        report['atRecordLimit'] = len(rows) >= 1000
        # Coverage remains historical. Activity alerts require positive increases
        # in comparable private counters, never a positive lifetime total alone.
        report['alerts'] = [a for a in report['alerts'] if a != 'telemetry_loss_high']
        if interval['observedIncreaseLowerBound'] > 0:
            report['alerts'].append('telemetry_loss_observed')
        current = set(report['alerts']) & ALLOWED
        old = set(old_report.get('alerts', [])) & ALLOWED
        report['alerts'] = sorted(current)
        writer(destination, report)
        # Baseline follows successful publication; a failed write cannot hide
        # the next observed increment. No private keys enter latest.json.
        writer(state_path, {'schemaVersion': 1, 'lossBaseline': baseline})
        return report, None if current == old else {
            'event': 'call_diagnostics_alert_changed', 'active': sorted(current), 'cleared': sorted(old-current)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--operator', default='/usr/local/bin/call_diagnostics.py')
    parser.add_argument('--dir', default='/var/lib/mknoon/call-diagnostics')
    parser.add_argument('--output', default='/var/lib/mknoon/call-diagnostics-report/latest.json')
    args = parser.parse_args()
    def deadline(*_):
        raise TimeoutError('monitor deadline')
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(45)
    try:
        # The installed strict operator is trusted code. Import is read-only:
        # never invoke monitors and never write __pycache__ beside the bundle.
        sys.dont_write_bytecode = True
        spec = importlib.util.spec_from_file_location('call_operator', args.operator)
        operator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(operator)
        _, change = run_tick(operator, args.dir, args.output)
        if change:
            print(json.dumps(change))
    except (OSError, ValueError, TypeError, AttributeError):
        print(json.dumps({'event': 'call_diagnostics_monitor_failed', 'reason': 'sink_unavailable'}))
        return 1
    finally:
        signal.alarm(0)
    return 0


if __name__ == '__main__':
    sys.exit(main())
