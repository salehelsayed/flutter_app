#!/usr/bin/env python3
"""Strict, read-only app diagnostic projection. Never exports private owner maps."""
import argparse
import collections
import datetime as dt
import html
import hashlib
import json
import pathlib
import re
import sys
import time

SCHEMA = json.loads(pathlib.Path(__file__).with_name('app_diagnostics_schema_v1.json').read_text())
UUID = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
HASH = re.compile(r'^[0-9a-f]{64}$')
BUILD = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._+\-]{0,79}$')
FINAL = {'finish', 'crash', 'hang'}
FAILURE = {'failed', 'rejected', 'timeout'}
EXPECTED = {'canceled', 'expired', 'blocked'}
STAGE_ORDER = {stage: i for i, stage in enumerate(SCHEMA['stage'])}


def strict_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate key')
        result[key] = value
    return result


def decode(raw):
    return json.loads(raw, object_pairs_hook=strict_object, parse_constant=lambda _: (_ for _ in ()).throw(ValueError('constant')))


def integer(value):
    return type(value) is int and 0 <= value <= SCHEMA['limits']['integerMaximum']


def validate(event):
    if not isinstance(event, dict) or set(event) - set(SCHEMA['required'] + SCHEMA['optional']) or set(SCHEMA['required']) - set(event):
        return False
    if type(event['schemaVersion']) is not int or event['schemaVersion'] != 1:
        return False
    for key in SCHEMA['uuidFields']:
        if key in event and (not isinstance(event[key], str) or not UUID.fullmatch(event[key])):
            return False
    for key in ('source', 'platform', 'feature', 'stage', 'outcome', 'reason'):
        if event[key] not in SCHEMA[key]:
            return False
    if event['source'] == 'relay':
        return False  # This collector accepts endpoint reports, not self-asserted server evidence.
    if any(not integer(event[key]) for key in ('sequence', 'occurredAtMs', 'elapsedMs')):
        return False
    if not isinstance(event['build'], str) or not BUILD.fullmatch(event['build']):
        return False
    values = event['values']
    if not isinstance(values, dict) or len(values) > SCHEMA['limits']['valuesCount']:
        return False
    for key, value in values.items():
        if key in SCHEMA['booleanValues']:
            if type(value) is not bool:
                return False
        elif key in SCHEMA['integerValues']:
            if not integer(value):
                return False
        elif key in SCHEMA['hashValues']:
            if not isinstance(value, str) or not HASH.fullmatch(value):
                return False
        elif key in SCHEMA['enumValues']:
            if value not in SCHEMA['enumValues'][key]:
                return False
        else:
            return False
    return len(json.dumps(event, separators=(',', ':'), ensure_ascii=False).encode()) <= SCHEMA['limits']['eventBytes']


def bounded_json(path, maximum):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > maximum:
        raise ValueError('file bounds')
    return decode(path.read_bytes())


def read_records(directory, now_ms, loss_samples=None):
    rows, health = [], collections.Counter()
    consent_path = directory / 'consent.json'
    if not consent_path.exists():
        return [], {'collectorState': 'no_consent_file', 'recordFiles': 0, 'invalidRecords': 0, 'droppedEvents': 0}
    consent = bounded_json(consent_path, 4 << 20)
    if not isinstance(consent, dict):
        raise ValueError('consent shape')
    retention = SCHEMA['limits']['serverRetentionDays'] * 86400000
    health['recordFiles'] = 0
    for path in sorted(directory.glob('*.json')):
        if not HASH.fullmatch(path.stem):
            continue
        health['recordFiles'] += 1
        try:
            record = bounded_json(path, SCHEMA['limits']['serverRecordBytes'])
            allowed = {'ownerDigest', 'consentEpoch', 'createdAtMs', 'events', 'finals', 'discardedEventIds', 'dropped', 'discardLedgerSaturated'}
            if not isinstance(record, dict) or set(record) - allowed or not HASH.fullmatch(record.get('ownerDigest', '')):
                raise ValueError('record shape')
            owner = record['ownerDigest']
            state = consent.get(owner, {})
            if state.get('enabled') is not True or state.get('erasePending', False) or state.get('consentEpoch') != record.get('consentEpoch'):
                health['unavailableConsentRecords'] += 1
                continue
            if not integer(record.get('createdAtMs')) or now_ms - record['createdAtMs'] > retention:
                health['expiredRecords'] += 1
                continue
            ordinary, finals = record.get('events', []), record.get('finals', {})
            if not isinstance(ordinary, list) or not isinstance(finals, dict) or len(ordinary) > SCHEMA['limits']['serverTraceEvents'] or len(finals) > 32:
                raise ValueError('event count')
            dropped = record.get('dropped', 0)
            if not integer(dropped):
                raise ValueError('drop count')
            if loss_samples is not None:
                identity = hashlib.sha256(('server:'+path.stem+':'+str(record['createdAtMs'])+':'+owner+':'+str(record.get('consentEpoch'))).encode()).hexdigest()
                loss_samples[identity] = {'count': dropped, 'lowerBound': record.get('discardLedgerSaturated') is True, 'layer': 'server'}
            health['droppedEvents'] += dropped
            health['lossCountLowerBound'] += int(record.get('discardLedgerSaturated') is True)
            for row in ordinary + list(finals.values()):
                if not isinstance(row, dict) or set(row) != {'receivedAtMs', 'event'} or not integer(row['receivedAtMs']) or not validate(row['event']):
                    health['invalidEvents'] += 1
                    continue
                rows.append({'_owner': owner, 'receivedAtMs': row['receivedAtMs'], 'event': row['event']})
        except (ValueError, TypeError, KeyError, OSError):
            health['invalidRecords'] += 1
    result = dict(health)
    result['collectorState'] = 'readable'
    result['consentingOwners'] = sum(isinstance(v, dict) and v.get('enabled') is True and not v.get('erasePending', False) and now_ms - v.get('updatedAtMs', 0) <= retention for v in consent.values())
    result['retainedOwnerCount'] = len({r['_owner'] for r in rows})
    return rows, result


def group_attempts(rows):
    groups = collections.defaultdict(list)
    for row in rows:
        e = row['event']
        key = (row['_owner'], e['feature'], e.get('attemptId') or (e['runId'] + ':' + (e.get('traceId') or e['runId'])))
        groups[key].append(row)
    aliases = {owner: 'endpoint-' + str(i + 1) for i, owner in enumerate(sorted({r['_owner'] for r in rows}))}
    attempts = []
    for (owner, feature, _), events in groups.items():
        events.sort(key=lambda r: (r['receivedAtMs'], r['event']['occurredAtMs'], r['event']['sequence']))
        started = [r for r in events if r['event']['stage'] in {'start', 'launch'} and r['event']['outcome'] == 'started']
        finals = [r for r in events if r['event']['stage'] in FINAL]
        if not started and not finals and not any(r['event'].get('attemptId') for r in events):
            continue
        final = max(finals, key=lambda r: (r['event']['occurredAtMs'], r['receivedAtMs'])) if finals else None
        first = min(started, key=lambda r: r['event']['occurredAtMs'])['event'] if started else events[0]['event']
        runs = sorted({r['event']['runId'] for r in events})
        errors = [r for r in events if r['event']['outcome'] in FAILURE]
        failure = errors[0]['event'] if errors else None
        attempts.append({
            'endpointAlias': aliases[owner], 'runId': first['runId'], 'runIds': runs, 'crossRunRecovery': len(runs) > 1, 'durationMs': None if len(runs) > 1 or not started or final is None else max(0, final['event']['elapsedMs'] - first['elapsedMs']), 'feature': feature,
            'traceId': first.get('traceId'), 'attemptId': first.get('attemptId'),
            'platform': first['platform'], 'build': first['build'],
            'sources': sorted({r['event']['source'] for r in events}),
            'startObserved': bool(started), 'finalObserved': final is not None,
            'outcome': final['event']['outcome'] if final else 'incomplete',
            'reason': final['event']['reason'] if final else 'interrupted_before_final_record',
            'firstFailureStage': failure['stage'] if failure else None,
            'firstFailureReason': failure['reason'] if failure else None,
            'lastObservedStage': events[-1]['event']['stage'],
            'firstReceivedAtMs': min(r['receivedAtMs'] for r in events),
            'lastReceivedAtMs': max(r['receivedAtMs'] for r in events),
            'eventCount': len(events),
            'completeness': 'start_and_final' if started and final else 'missing_start' if final else 'missing_final',
        })
    return sorted(attempts, key=lambda a: (a['firstReceivedAtMs'], a['runId'], a['feature']))


def aggregate(attempts, rows, baseline_rows, health):
    groups = collections.defaultdict(list)
    for attempt in attempts:
        groups[(attempt['feature'], attempt['build'], attempt['platform'])].append(attempt)
    summaries, alerts = [], []
    for (feature, build, platform), items in sorted(groups.items()):
        counts = collections.Counter(a['outcome'] for a in items)
        technical = sum(n for state, n in counts.items() if state in FAILURE)
        denominator = counts['success'] + counts['ok'] + technical
        incomplete = sum(not a['finalObserved'] for a in items)
        summary = {'feature': feature, 'build': build, 'platform': platform, 'attemptsObserved': len(items), 'outcomes': dict(counts), 'technicalFailures': technical, 'technicalRateDenominator': denominator, 'technicalFailureRate': technical / denominator if denominator else None, 'missingFinal': incomplete, 'missingStart': sum(not a['startObserved'] for a in items), 'expectedOutcomesExcludedFromTechnicalRate': sum(counts[x] for x in EXPECTED)}
        summaries.append(summary)
        if denominator >= 5 and technical / denominator >= .2:
            alerts.append({'kind': 'technical_failure_rate', 'feature': feature, 'build': build, 'platform': platform, 'count': technical, 'denominator': denominator, 'threshold': .2, 'minimumSamples': 5})
        if len(items) >= 5 and incomplete / len(items) >= .2:
            alerts.append({'kind': 'missing_final_rate', 'feature': feature, 'build': build, 'platform': platform, 'count': incomplete, 'denominator': len(items), 'threshold': .2, 'minimumSamples': 5})
    def signature(row):
        e = row['event']
        return (e['feature'], e['platform'], e['build'], e['stage'], e['reason'], e['values'].get('fingerprint'))
    prior = {signature(r) for r in baseline_rows if r['event']['outcome'] in FAILURE}
    errors = collections.Counter(signature(r) for r in rows if r['event']['outcome'] in FAILURE)
    error_summaries = []
    for key, count in sorted(errors.items(), key=lambda item: tuple(str(x) for x in item[0])):
        feature, platform, build, stage, reason, fingerprint = key
        entry = {'feature': feature, 'platform': platform, 'build': build, 'stage': stage, 'reason': reason, 'fingerprint': fingerprint, 'eventReports': count, 'newInRetainedBaseline': key not in prior, 'baselineEventCount': len(baseline_rows)}
        error_summaries.append(entry)
        if key not in prior and count >= 3:
            alerts.append({'kind': 'new_error_signature', **entry, 'minimumReports': 3})
    if health.get('droppedEvents', 0) or health.get('invalidEvents', 0) or health.get('invalidRecords', 0) or health.get('clientReportedDroppedEvents', 0):
        alerts.append({'kind': 'telemetry_coverage_gap', 'scope': 'retained_lifetime_and_validation', 'droppedEvents': health.get('droppedEvents', 0), 'lossCountIsLowerBound': bool(health.get('lossCountLowerBound')), 'invalidEvents': health.get('invalidEvents', 0), 'invalidRecords': health.get('invalidRecords', 0), 'clientReportedDroppedEvents': health.get('clientReportedDroppedEvents', 0)})
    return {'groups': summaries, 'errors': error_summaries, 'alerts': alerts}


# Baselines are private hashed counter identities, never part of an operator report.
MAX_LOSS_COUNTERS = 2048
LOSS_BASELINE_TTL_MS = 14 * 86400000


def counter_interval(samples, previous, now_ms):
    def clean(values):
        if not isinstance(values, dict):
            return {}
        return {k: {'count': v['count'], 'lowerBound': v.get('lowerBound') is True,
                    'layer': v.get('layer') if v.get('layer') in {'client', 'server'} else 'unknown',
                    **({'reportedAtMs': v['reportedAtMs']} if type(v.get('reportedAtMs')) is int else {})}
                for k, v in list(values.items())[:MAX_LOSS_COUNTERS]
                if isinstance(k, str) and isinstance(v, dict) and
                type(v.get('count')) is int and 0 <= v['count'] <= 9007199254740991}
    current = clean(samples)
    previous = previous if isinstance(previous, dict) else {}
    stamp = previous.get('sampledAtMs')
    previous_values = previous.get('counters')
    usable = type(stamp) is int and 0 <= now_ms - stamp <= LOSS_BASELINE_TTL_MS and isinstance(previous_values, dict)
    prior = clean(previous_values) if usable else {}
    if usable and len(prior) != len(previous_values):
        usable, prior = False, {}
    shared = current.keys() & prior.keys()
    resets = sum(current[k]['count'] < prior[k]['count'] for k in shared)
    increase = sum(max(0, current[k]['count'] - prior[k]['count']) for k in shared)
    bounds = sum(current[k]['lowerBound'] or prior[k]['lowerBound'] for k in shared)
    stale = sum('reportedAtMs' in current[k] and current[k]['reportedAtMs'] <= prior[k].get('reportedAtMs', 0) for k in shared)
    unseen, missing = len(current.keys() - prior.keys()), len(prior.keys() - current.keys())
    truncated = len(samples) > MAX_LOSS_COUNTERS
    comparable = usable and not (resets or bounds or stale or unseen or missing or truncated or previous.get('truncated'))
    interval = {'fromMs': stamp if usable else None, 'toMs': now_ms,
                'baselineAvailable': usable, 'comparableCounters': len(shared),
                'firstSeenCounters': unseen, 'missingCounters': missing, 'resetCounters': resets,
                'saturatedCounters': bounds, 'staleSnapshotCounters': stale, 'baselineTruncated': bool(truncated or previous.get('truncated')),
                'observedIncreaseLowerBound': increase,
                'newDroppedEvents': increase if comparable else None,
                'scope': 'Observed cumulative counter increases between retained samples; resets, missing/new counters, stale baselines and ledger saturation leave total interval loss unknown. No event-loss rate is inferred.'}
    by_layer = {}
    for layer in ('client', 'server', 'unknown'):
        keys = {k for k in shared if current[k]['layer'] == prior[k]['layer'] == layer}
        delta = sum(max(0, current[k]['count'] - prior[k]['count']) for k in keys)
        by_layer[layer] = {'observedIncreaseLowerBound': delta,
                           'comparableCounters': len(keys),
                           'scope': 'Counter increases within this layer only; not added to another layer as unique lost events.'}
    interval['observedCounterIncrements'] = sum(v['observedIncreaseLowerBound'] for v in by_layer.values())
    interval['byLayer'] = by_layer
    interval['newDroppedEvents'] = None
    del interval['observedIncreaseLowerBound']
    interval['scope'] = 'Separate client and server cumulative counters. Aggregate counter increments can overlap across layers and never establish a unique lost-event total. First samples, resets, missing/stale snapshots and retention remain unknown.'
    return interval, {'sampledAtMs': now_ms, 'counters': current, 'truncated': truncated}


def report(directory, hours=24, limit=100, trace=None, run=None, now_ms=None, support_code=None, _loss_samples=None):
    now_ms = int(time.time() * 1000) if now_ms is None else now_ms
    samples = {} if _loss_samples is None else _loss_samples
    retained, health = read_records(pathlib.Path(directory), now_ms, samples)
    cutoff = now_ms - int(hours * 3600000)
    baseline = [r for r in retained if r['receivedAtMs'] < cutoff]
    rows = [r for r in retained if cutoff <= r['receivedAtMs'] <= now_ms]
    if trace or run or support_code:
        matched = [r for r in rows if
                   (not trace or r['event'].get('traceId') == trace) and
                   (not run or run in (r['event']['runId'], r['event'].get('reportingRunId'))) and
                   (not support_code or support_code in (r['event'].get('traceId'), r['event']['runId'], r['event'].get('reportingRunId')))]
        # A recovered terminal can be uploaded by a new process. Expand only
        # authenticated-owner/feature/attempt joins, never across claimed owners.
        attempts_matched = {(r['_owner'], r['event']['feature'], r['event']['attemptId']) for r in matched if r['event'].get('attemptId')}
        event_ids = {(r['_owner'], r['event']['eventId']) for r in matched}
        rows = [r for r in rows if (r['_owner'], r['event']['eventId']) in event_ids or
                (r['_owner'], r['event']['feature'], r['event'].get('attemptId')) in attempts_matched]
    latest_client_health, latest_run_health = {}, {}
    # These counters describe retained lifetimes, independent of the event window
    # or detail filter. A new process is an incomparable baseline, not new loss.
    for row in sorted(retained, key=lambda r: (r['receivedAtMs'], r['event']['occurredAtMs'], r['event']['sequence'])):
        e = row['event']
        if row['receivedAtMs'] <= now_ms and e['source'] == 'flutter' and e['feature'] == 'runtime' and e['stage'] == 'snapshot' and 'droppedEvents' in e['values']:
            latest_client_health[row['_owner']] = row
            latest_run_health[(row['_owner'], e['runId'])] = row
    for (owner, run_id), row in latest_run_health.items():
        key = hashlib.sha256(('client:'+owner+':'+run_id).encode()).hexdigest()
        samples[key] = {'count': row['event']['values']['droppedEvents'], 'lowerBound': False, 'reportedAtMs': row['receivedAtMs'], 'layer': 'client'}
    health['clientReportedDroppedEvents'] = sum(r['event']['values']['droppedEvents'] for r in latest_client_health.values())
    attempts = group_attempts(rows)
    summary = aggregate(attempts, rows, baseline, health)
    result = {'schemaVersion': 1, 'generatedAtMs': now_ms, 'windowHours': hours, 'retentionDays': SCHEMA['limits']['serverRetentionDays'], 'evidenceScope': 'Authenticated endpoint reports; receipt time is server-observed. UUID joins are diagnostic correlation, not proof of message custody, participants or content. Missing/disabled/offline/legacy endpoint records remain unknown.', 'health': health, 'eventReports': len(rows), 'attemptsObserved': len(attempts), **summary, 'attempts': attempts[-limit:], 'attemptsTruncated': max(0, len(attempts)-limit)}
    result['loss'] = {'retainedLifetime': {
        'droppedEvents': health.get('droppedEvents', 0),
        'clientReportedDroppedEvents': health['clientReportedDroppedEvents'],
        'lossCountIsLowerBound': bool(health.get('lossCountLowerBound')),
        'scope': 'Server counters over retained records; latest retained client cumulative snapshot per owner. Client and server counters are separate and must not be summed or divided by window event counts.'},
        'window': {'newDroppedEvents': None, 'scope': 'A standalone projection has no comparable monitor baseline; cumulative snapshot values do not establish current-window loss.'}}
    result['evidenceIncomplete'] = any(a['kind'] == 'telemetry_coverage_gap' for a in result['alerts'])
    if trace or run or support_code:
        aliases = {owner: 'endpoint-'+str(i+1) for i, owner in enumerate(sorted({r['_owner'] for r in rows}))}
        ordered = sorted(rows, key=lambda r: (r['receivedAtMs'], r['event']['sequence']))
        result['timeline'] = [{'endpointAlias': aliases[r['_owner']], 'receivedAtMs': r['receivedAtMs'], **r['event']} for r in ordered[-limit:]]
        result['timelineTruncated'] = max(0, len(ordered)-limit)
    return result


def dashboard(result):
    rows = ''.join('<tr>'+''.join('<td>'+html.escape(str(row[key]))+'</td>' for key in ('feature','build','platform','attemptsObserved','technicalFailures','technicalRateDenominator','missingFinal'))+'</tr>' for row in result['groups'])
    alerts = html.escape(json.dumps(result['alerts'], indent=2))
    return '<!doctype html><meta charset="utf-8"><title>Mknoon app diagnostics</title><style>body{font:16px system-ui;max-width:1200px;margin:40px auto;padding:0 20px}table{border-collapse:collapse;width:100%}td,th{padding:12px;text-align:left;border-bottom:1px solid #ccc}pre{white-space:pre-wrap;background:#f2f4f8;padding:20px}</style><h1>App diagnostics</h1><p>'+html.escape(result['evidenceScope'])+'</p><p>Generated '+dt.datetime.fromtimestamp(result['generatedAtMs']/1000,dt.timezone.utc).isoformat()+' · '+str(result['eventReports'])+' event reports · '+str(result['attemptsObserved'])+' observed attempts</p><table><tr><th>Feature</th><th>Build</th><th>Platform</th><th>Attempts</th><th>Technical failures</th><th>Rate denominator</th><th>Missing final</th></tr>'+rows+'</table><h2>Local alerts</h2><pre>'+alerts+'</pre><h2>Collector health</h2><pre>'+html.escape(json.dumps(result['health'],indent=2))+'</pre>'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dir', default='/var/lib/mknoon/app-diagnostics')
    parser.add_argument('--hours', type=float, default=24)
    parser.add_argument('--limit', type=int, default=100)
    parser.add_argument('--trace')
    parser.add_argument('--support-code')
    parser.add_argument('--run')
    parser.add_argument('--format', choices=['json', 'html'], default='json')
    args = parser.parse_args()
    if not 0 < args.hours <= 14*24 or not 1 <= args.limit <= 2000 or any(v is not None and not UUID.fullmatch(v) for v in (args.trace, args.run, args.support_code)):
        parser.error('bounded hours/limit and canonical UUIDv4 required')
    try:
        result = report(args.dir, args.hours, args.limit, args.trace, args.run, support_code=args.support_code)
    except (ValueError, TypeError, OSError):
        print(json.dumps({'schemaVersion':1,'health':{'collectorState':'unavailable'},'reason':'sink_unavailable'}))
        return 1
    print(dashboard(result) if args.format == 'html' else json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == '__main__':
    sys.exit(main())
