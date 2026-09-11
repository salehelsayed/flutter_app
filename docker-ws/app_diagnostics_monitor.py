#!/usr/bin/env python3
"""One private monitor tick; systemd runs it every five minutes."""
import argparse
import fcntl
import hashlib
import json
import os
import pathlib
import sys
import tempfile
import time

import app_diagnostics as operator

MAX_ENTRIES = 200
MAX_FILE_BYTES = 512 << 10
ALERT_KEYS = ('kind', 'feature', 'platform', 'build', 'stage', 'reason', 'fingerprint', 'errorClass', 'osReasonCode', 'operation')
KINDS = {'technical_failure_rate','missing_final_rate','missing_start_rate','interrupted_unknown_rate','new_error_signature','telemetry_loss','telemetry_coverage_gap','collector_unavailable','coverage_projection_truncated'}
COUNT_KEYS = ('count', 'denominator', 'eventReports', 'droppedEvents', 'invalidEvents', 'invalidRecords', 'clientReportedDroppedEvents', 'observedCounterIncrements')


def atomic_write(path, raw):
    if len(raw) > MAX_FILE_BYTES:
        raise ValueError('snapshot quota')
    fd, name = tempfile.mkstemp(prefix='.app-monitor-', dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'wb') as target:
            target.write(raw)
            target.flush()
            os.fsync(target.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def alert_key(alert):
    return hashlib.sha256(json.dumps({k: alert[k] for k in ALERT_KEYS if k in alert}, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def safe_alert(alert):
    # Input originates only from the strict operator projection. Never include
    # trace/run/event/owner identifiers, filenames or arbitrary error text.
    if not isinstance(alert, dict) or alert.get('kind') not in KINDS:
        return None
    result = {'kind': alert['kind']}
    for key in (*ALERT_KEYS[1:], 'fingerprintSpecificity'):
        if key not in alert or alert[key] is None:
            continue
        value = alert[key]
        if key in {'feature', 'platform', 'stage', 'reason'}:
            if value not in operator.SCHEMA[key]:
                return None
        elif key == 'build':
            if not isinstance(value, str) or not operator.BUILD.fullmatch(value):
                return None
        elif key == 'fingerprint':
            if not isinstance(value, str) or not operator.HASH.fullmatch(value):
                return None
        elif key in {'errorClass', 'operation'}:
            if value not in operator.SCHEMA['enumValues'][key]:
                return None
        elif key == 'osReasonCode':
            if not operator.integer(value):
                return None
        elif key == 'fingerprintSpecificity':
            if value not in {'reported', 'class_only', 'none'}:
                return None
        result[key] = value
    for key in COUNT_KEYS:
        if key in alert:
            if not operator.integer(alert[key]):
                return None
            result[key] = alert[key]
    return result


def mature_coverage_alerts(attempts, now_ms):
    groups = {}
    for attempt in attempts:
        if now_ms - attempt['firstReceivedAtMs'] < 300000:
            continue
        key = (attempt['feature'], attempt['build'], attempt['platform'])
        groups.setdefault(key, []).append(attempt)
    alerts = []
    for (feature, build, platform), values in sorted(groups.items()):
        if len(values) < 5:
            continue
        for kind, count in (
            ('missing_final_rate', sum(not a['finalObserved'] for a in values)),
            ('missing_start_rate', sum(not a['startObserved'] for a in values)),
            ('interrupted_unknown_rate', sum(a['outcome'] == 'interrupted_unknown' for a in values)),
        ):
            if count / len(values) >= .2:
                alerts.append({'kind': kind, 'feature': feature, 'build': build, 'platform': platform, 'count': count, 'denominator': len(values), 'minimumSamples': 5, 'graceSeconds': 300, 'threshold': .2})
    return alerts


def run_tick(directory, output, now_ms=None, report_fn=operator.report, writer=atomic_write):
    now_ms = int(time.time()*1000) if now_ms is None else now_ms
    output = pathlib.Path(output)
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    if output.is_symlink():
        raise ValueError('output directory')
    os.chmod(output, 0o700)
    lock_fd = os.open(output/'monitor.lock', os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(lock_fd, 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        prior = {}
        loss_baseline = {}
        state_path = output/'state.json'
        if state_path.exists():
            try:
                state = operator.bounded_json(state_path, MAX_FILE_BYTES)
                if isinstance(state, dict) and state.get('schemaVersion') == 1 and isinstance(state.get('active'), dict):
                    loss_baseline = state.get('lossBaseline', {})
                    prior = {k: safe_alert(v) for k, v in list(state['active'].items())[:MAX_ENTRIES] if operator.HASH.fullmatch(k) and safe_alert(v) is not None}
            except (OSError, ValueError, TypeError):
                pass  # A corrupt monitor cache cannot block collection or echo bytes.
        samples = {}
        try:
            result = report_fn(directory, hours=24, limit=2000, now_ms=now_ms, _loss_samples=samples)
        except (OSError, ValueError, TypeError):
            result = {'schemaVersion':1,'generatedAtMs':now_ms,'windowHours':24,'retentionDays':14,
                      'evidenceScope':'Collector read failed; zero projections are placeholders. Event and attempt counts are unavailable.',
                      'health':{'collectorState':'unavailable'},'eventReports':0,'attemptsObserved':0,
                      'groups':[],'errors':[],'alerts':[],'attempts':[],'attemptsTruncated':0}
        interval, next_baseline = operator.counter_interval(samples, loss_baseline, now_ms)
        if result['health'].get('collectorState') != 'readable':
            interval['newDroppedEvents'] = None
            interval['collectionAvailable'] = False
            # A missing collection cannot establish a new zero baseline.
            next_baseline = {}
        else:
            interval['collectionAvailable'] = True
        result.setdefault('loss', {})['observedInterval'] = interval
        alerts = [a for a in result['alerts'] if a['kind'] not in {'missing_final_rate', 'telemetry_loss'}]
        if interval['observedCounterIncrements'] > 0:
            alerts.append({'kind': 'telemetry_loss', 'observedCounterIncrements': interval['observedCounterIncrements'], 'scope': 'observed_between_monitor_samples'})
        alerts.extend(mature_coverage_alerts(result['attempts'], now_ms))
        if result['health'].get('collectorState') != 'readable':
            alerts.append({'kind': 'collector_unavailable', 'count': 1})
        if result['attemptsTruncated']:
            alerts.append({'kind': 'coverage_projection_truncated', 'count': result['attemptsTruncated']})
        alerts = sorted(alerts, key=alert_key)
        all_keys = {alert_key(a) for a in alerts}
        current = {alert_key(a): safe_alert(a) for a in alerts[:MAX_ENTRIES] if safe_alert(a) is not None}
        # Aggregate snapshots contain no per-attempt identifiers. A clear causes
        # the next tick to overwrite old aggregates, not retain an event archive.
        snapshot = {k: v for k, v in result.items() if k not in {'attempts', 'timeline'}}
        snapshot['monitor'] = {'intervalSeconds': 300, 'coverageGraceSeconds': 300, 'localJournalOnly': True, 'entriesPerSection': MAX_ENTRIES, 'alertsTruncated': max(0, len(alerts)-MAX_ENTRIES)}
        for key in ('groups', 'errors'):
            snapshot[key+'Truncated'] = max(0, len(snapshot[key])-MAX_ENTRIES)
            snapshot[key] = snapshot[key][:MAX_ENTRIES]
        snapshot['alerts'] = alerts[:MAX_ENTRIES]
        changes = [{'event': 'alert_opened', **current[k]} for k in sorted(set(current)-set(prior))]
        changes += [{'event': 'alert_cleared', **safe_alert(prior[k])} for k in sorted(set(prior)-all_keys)]
        changes = changes[:MAX_ENTRIES]
        writer(output/'snapshot.json', json.dumps(snapshot, indent=2, sort_keys=True).encode())
        writer(output/'dashboard.html', operator.dashboard(snapshot).encode())
        writer(output/'alerts.json', json.dumps({'schemaVersion': 1, 'generatedAtMs': now_ms, 'active': list(current.values()), 'transitions': changes}, indent=2, sort_keys=True).encode())
        # State is committed last. A failed snapshot write never suppresses the
        # next attempt to publish that alert. A crash may repeat a journal notice.
        writer(state_path, json.dumps({'schemaVersion': 1, 'generatedAtMs': now_ms, 'active': current, 'lossBaseline': next_baseline}, sort_keys=True).encode())
        return changes, snapshot


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dir', default='/var/lib/mknoon/app-diagnostics')
    parser.add_argument('--output-dir', default='/var/lib/mknoon/app-diagnostics-monitor')
    args = parser.parse_args()
    try:
        changes, snapshot = run_tick(args.dir, args.output_dir)
    except Exception:
        print('app_diagnostics_monitor event=failed reason=sink_unavailable')
        return 1
    for change in changes:
        # Only fixed event/kind plus integer counts enter the local journal.
        counts = ' '.join(k+'='+str(change[k]) for k in COUNT_KEYS if k in change and type(change[k]) is int)
        print('app_diagnostics_monitor event='+change['event']+' kind='+change['kind']+(' '+counts if counts else ''))
    print('app_diagnostics_monitor event=snapshot state='+snapshot['health']['collectorState']+' alerts='+str(len(snapshot['alerts'])))
    return 0


if __name__ == '__main__':
    sys.exit(main())
