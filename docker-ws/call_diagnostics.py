#!/usr/bin/env python3
"""Read-only, bounded sanitized call diagnostics lookup. Never export auth maps."""
import argparse
import collections
import json
import hashlib
import pathlib
import re
import time
import uuid

MAX_RECORD_BYTES = 320 * 1024  # Joined endpoint/relay budget plus bounded evidence/ledger metadata.
SCHEMA = json.loads('{\n  "schemaVersion": 1,\n  "required": [\n    "schemaVersion",\n    "eventId",\n    "source",\n    "role",\n    "runId",\n    "sequence",\n    "occurredAtMs",\n    "elapsedMs",\n    "stage",\n    "action",\n    "outcome",\n    "reason",\n    "values"\n  ],\n  "optional": [\n    "traceId",\n    "requestId",\n    "operationId",\n    "parentOperationId",\n    "build"\n  ],\n  "uuidFields": [\n    "eventId",\n    "traceId",\n    "requestId",\n    "operationId",\n    "parentOperationId",\n    "runId"\n  ],\n  "source": [\n    "flutter",\n    "ios",\n    "android",\n    "relay"\n  ],\n  "role": [\n    "caller",\n    "callee",\n    "local",\n    "server"\n  ],\n  "stage": [\n    "attempt",\n    "preflight",\n    "authority",\n    "signaling",\n    "push",\n    "admission",\n    "presentation",\n    "answer",\n    "audio",\n    "media",\n    "turn",\n    "terminal",\n    "cleanup",\n    "upload",\n    "runtime"\n  ],\n  "action": [\n    "start",\n    "check",\n    "lookup",\n    "publish",\n    "revoke",\n    "invalidate",\n    "replace",\n    "send_direct",\n    "store",\n    "retrieve",\n    "ack",\n    "cancel",\n    "expire",\n    "dispatch",\n    "present",\n    "accept",\n    "activate",\n    "snapshot",\n    "finish",\n    "recover",\n    "drop",\n    "upload",\n    "flush",\n    "response",\n    "mint",\n    "retry",\n    "bind",\n    "configure",\n    "disable",\n    "enable",\n    "reset",\n    "receive",\n    "parse",\n    "commit",\n    "adopt",\n    "stop"\n  ],\n  "outcome": [\n    "started",\n    "ok",\n    "failed",\n    "rejected",\n    "not_found",\n    "not_found_or_expired",\n    "duplicate",\n    "skipped",\n    "suppressed",\n    "timeout",\n    "interrupted",\n    "completed",\n    "partial",\n    "pending",\n    "blocked",\n    "canceled",\n    "declined",\n    "busy",\n    "no_answer",\n    "connected",\n    "media_flow_verified",\n    "answered_without_verified_media",\n    "completed_after_media",\n    "dropped_after_media",\n    "preflight_failed",\n    "signaling_failed",\n    "native_answer_failed",\n    "media_failed",\n    "interrupted_unknown",\n    "partial_legacy",\n    "missing_endpoint_report",\n    "unknown"\n  ],\n  "reason": [\n    "none",\n    "unknown",\n    "user_action",\n    "local_user",\n    "remote_user",\n    "remote_terminal",\n    "permission_denied",\n    "microphone_denied",\n    "permission_revoked",\n    "full_screen_permission_denied",\n    "notifications_denied",\n    "platform_unsupported",\n    "graph_unavailable",\n    "graph_replaced",\n    "graph_shutdown",\n    "graph_not_owner",\n    "capability_unavailable",\n    "capability_publish_failed",\n    "endpoint_not_found",\n    "endpoint_expired",\n    "endpoint_invalid",\n    "authority_invalid",\n    "authority_rejected",\n    "authority_unreachable",\n    "wake_authority_missing",\n    "wake_failed",\n    "no_route",\n    "not_found_or_expired",\n    "receipt_missing",\n    "receipt_invalid",\n    "signature_invalid",\n    "blocked",\n    "busy",\n    "canceled",\n    "declined",\n    "no_answer",\n    "timeout",\n    "deadline",\n    "network_unavailable",\n    "transport_failed",\n    "bridge_unavailable",\n    "malformed_response",\n    "backend_unavailable",\n    "rate_limited",\n    "invalid_request",\n    "duplicate",\n    "replay",\n    "expired",\n    "stale_epoch",\n    "pushkit_token_invalidated",\n    "calls_disabled",\n    "native_token_updated",\n    "resume_refresh",\n    "bootstrap",\n    "logout",\n    "account_changed",\n    "native_snapshot_invalid",\n    "native_read_timeout",\n    "native_stream_failed",\n    "native_lifecycle_failed",\n    "token_rotation_cleanup",\n    "native_persistence_failed",\n    "native_answer_refused",\n    "provider_reset",\n    "action_timeout",\n    "audio_activation_failed",\n    "audio_session_failed",\n    "turn_unavailable",\n    "turn_credential_failed",\n    "ice_failed",\n    "dtls_failed",\n    "media_failed",\n    "media_stalled",\n    "negotiation_failed",\n    "cleanup_failed",\n    "sink_unavailable",\n    "quota_exceeded",\n    "retention_expired",\n    "interrupted_before_final_record",\n    "legacy_peer",\n    "diagnostics_disabled",\n    "server_error",\n    "auth_error",\n    "invalid_token",\n    "provider_error",\n    "rejected_payload",\n    "rejected_route",\n    "sent_cross_environment",\n    "write_failed",\n    "suppressed_attached",\n    "invalidated",\n    "token_changed",\n    "capability_disabled",\n    "token_invalidation",\n    "adoption_failed",\n    "unavailable",\n    "remote_reject"\n  ],\n  "booleanValues": [\n    "foreground",\n    "enabled",\n    "ownerMatched",\n    "accepted",\n    "connected",\n    "terminal",\n    "nativeCommitted",\n    "audioActive",\n    "structuralReady",\n    "mediaFlowVerified",\n    "inboundRtpObserved",\n    "outboundRtpObserved",\n    "inboundRtpProgress",\n    "outboundRtpProgress",\n    "muted",\n    "relayOnly",\n    "fullScreenAllowed",\n    "notificationAllowed",\n    "microphoneAllowed",\n    "hasMore",\n    "truncated",\n    "legacy",\n    "complete",\n    "found",\n    "storeCommitted",\n    "responseWritten",\n    "providerInvoked",\n    "databaseClosed",\n    "leaseReleased",\n    "requiredPersistenceComplete"\n  ],\n  "integerValues": [\n    "durationMs",\n    "retry",\n    "pending",\n    "acked",\n    "count",\n    "dropped",\n    "inboundPackets",\n    "outboundPackets",\n    "inboundBytes",\n    "outboundBytes",\n    "sampleCount",\n    "cleanupRemaining",\n    "graphGeneration",\n    "epoch",\n    "generation",\n    "limit",\n    "bytes",\n    "attemptCount",\n    "eventCount"\n  ],\n  "enumValues": {\n    "state": [\n      "idle",\n      "incoming_validating",\n      "incoming_ringing",\n      "outgoing_preparing",\n      "outgoing_inviting",\n      "outgoing_ringing",\n      "ringing",\n      "inviting",\n      "dialing",\n      "accepted",\n      "connecting",\n      "connected",\n      "reconnecting",\n      "ending",\n      "ended",\n      "failed",\n      "unknown"\n    ],\n    "transport": [\n      "direct",\n      "circuit_relay",\n      "turn_udp",\n      "turn_tcp",\n      "turn_tls",\n      "relay",\n      "none",\n      "unknown"\n    ],\n    "network": [\n      "wifi",\n      "cellular",\n      "ethernet",\n      "offline",\n      "unknown"\n    ],\n    "platform": [\n      "ios",\n      "android",\n      "other",\n      "unknown"\n    ],\n    "completeness": [\n      "complete",\n      "partial",\n      "legacy",\n      "interrupted",\n      "truncated",\n      "unknown"\n    ],\n    "route": [\n      "system_default",\n      "earpiece",\n      "speaker",\n      "bluetooth",\n      "wired_headset",\n      "unknown"\n    ],\n    "failureStage": [\n      "android_audio_focus",\n      "peer_create",\n      "user_media",\n      "track_invariant",\n      "add_track",\n      "snapshot_senders",\n      "snapshot_transceivers",\n      "snapshot_transceiver_direction",\n      "snapshot_receivers",\n      "snapshot_stats",\n      "snapshot_deadline",\n      "set_audio_session_active",\n      "create_connection",\n      "supported_output_routes",\n      "snapshot"\n    ],\n    "authorityKind": [\n      "endpoint",\n      "wake_grant",\n      "standard_call_token",\n      "ios_voip_token",\n      "unknown"\n    ],\n    "admissionDisposition": [\n      "admitted",\n      "terminal",\n      "permanent_reject",\n      "empty_or_already_acked",\n      "deferred",\n      "unknown"\n    ]\n  },\n  "limits": {\n    "localRetentionDays": 7,\n    "serverRetentionDays": 14,\n    "localBytes": 5242880,\n    "nativeBytes": 1048576,\n    "attempts": 100,\n    "eventsPerAttempt": 256,\n    "bytesPerAttempt": 65536,\n    "batchEvents": 64,\n    "eventBytes": 4096\n  }\n}\n')
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
BUILD = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.+_-]{0,79}$")


def valid_event(event):
    if not isinstance(event, dict) or set(event) - set(SCHEMA['required'] + SCHEMA['optional']):
        return False
    if set(SCHEMA['required']) - set(event) or type(event['schemaVersion']) is not int or event['schemaVersion'] != 1:
        return False
    for key in SCHEMA['uuidFields']:
        if key in event and (not isinstance(event[key], str) or not UUID.fullmatch(event[key])):
            return False
    for key in ('source', 'role', 'stage', 'action', 'outcome', 'reason'):
        if event[key] not in SCHEMA[key]:
            return False
    for key in ('sequence', 'occurredAtMs', 'elapsedMs'):
        if type(event[key]) is not int or not 0 <= event[key] <= 9007199254740991:
            return False
    if 'build' in event and (not isinstance(event['build'], str) or not BUILD.fullmatch(event['build'])):
        return False
    values = event['values']
    if not isinstance(values, dict) or len(values) > 32:
        return False
    for key, value in values.items():
        if key in SCHEMA['booleanValues']:
            if type(value) is not bool:
                return False
        elif key in SCHEMA['integerValues']:
            if type(value) is not int or not 0 <= value <= 9007199254740991:
                return False
        elif key in SCHEMA['enumValues']:
            if value not in SCHEMA['enumValues'][key]:
                return False
        else:
            return False
    return len(json.dumps(event, separators=(',', ':')).encode()) <= 4096


# Baselines are private hashed counter identities, never part of an operator report.
MAX_LOSS_COUNTERS = 2048
LOSS_BASELINE_TTL_MS = 14 * 86400000


def counter_interval(samples, previous, now_ms):
    def clean(values):
        if not isinstance(values, dict):
            return {}
        return {k: {'count': v['count'], 'lowerBound': v.get('lowerBound') is True,
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
    return interval, {'sampledAtMs': now_ms, 'counters': current, 'truncated': truncated}


def read_records(directory, since_ms, trace=None, limit=1000, now_ms=None, _loss_samples=None):
    now_ms = int(time.time()*1000) if now_ms is None else now_ms
    rows, rejected = [], 0
    paths = [directory / (trace + '.json')] if trace else sorted(directory.glob('*.json'))
    for path in paths[:10001]:
        if not UUID.fullmatch(path.stem) and not (path.stem.startswith('runtime-') and (re.fullmatch(r'[0-9a-f]{8}-[0-9a-f]{4}-[45][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}', path.stem[8:]) or re.fullmatch(r'[0-9a-f]{64}', path.stem[8:]))):
            continue
        try:
            if path.is_symlink() or path.stat().st_size > MAX_RECORD_BYTES:
                rejected += 1
                continue
            record = json.loads(path.read_bytes())
            if type(record.get('createdAtMs')) is not int or record['createdAtMs'] < now_ms - 14*86400000:
                continue
            events = []
            seen = set()
            event_rows = record.get('events', [])
            if event_rows is None:  # Go encodes an empty nil slice as JSON null.
                event_rows = []
            for row in event_rows + list(record.get('summaries', {}).values()):
                event, received = row.get('event'), row.get('receivedAtMs')
                if not valid_event(event) or type(received) is not int:
                    rejected += 1
                    continue
                if not since_ms <= received <= now_ms or event['eventId'] in seen:
                    continue
                if trace and event.get('traceId') != trace:
                    continue
                seen.add(event['eventId'])
                events.append({'receivedAtMs': received, 'event': event})
            events.sort(key=lambda x: (x['receivedAtMs'], x['event']['runId'], x['event']['sequence']))
            dropped = record.get('dropped', 0)
            legacy = record.get('legacyDropAttempts', 0)
            if any(type(v) is not int or not 0 <= v <= 9007199254740991 for v in (dropped, legacy)):
                raise ValueError('counter bounds')
            if record.get('dropAccountingVersion', 0) == 0:
                legacy += dropped
                dropped = 0
            saturated = record.get('discardLedgerSaturated') is True
            if _loss_samples is not None:
                identity = hashlib.sha256((path.stem+':'+str(record['createdAtMs'])).encode()).hexdigest()
                _loss_samples[identity] = {'count': dropped, 'lowerBound': saturated or bool(legacy)}
            # Loss-only retained records remain coverage evidence even when
            # their last event falls outside the requested receipt window.
            if events or dropped or legacy or saturated:
                item = {'events': events, 'droppedEvents': dropped,
                        'legacyQuotaRejectionAttempts': legacy,
                        'discardLedgerSaturated': saturated}
                for key in ('droppedFirstAtMs', 'droppedUpdatedAtMs'):
                    value = record.get(key)
                    if type(value) is int and 0 < value <= now_ms:
                        item[key] = value
                item['_windowSinceMs'], item['_windowEndMs'] = since_ms, now_ms
                rows.append(item)
            if len(rows) >= limit:
                break
        except FileNotFoundError:
            if not trace:
                rejected += 1
        except (OSError, ValueError, TypeError, AttributeError):
            rejected += 1
    return rows, rejected


def report(rows, rejected, trace=None, since_ms=None, now_ms=None):
    counters = collections.Counter()
    terminal = collections.Counter()
    traces = set()
    admitted = set()
    media = set()
    complete = set()
    terminal_roles = collections.defaultdict(set)
    media_roles = collections.defaultdict(set)
    reported_roles = collections.defaultdict(set)
    legacy = set()
    all_events = []
    for row in rows:
        counters['droppedEvents'] += row['droppedEvents']
        counters['legacyQuotaRejectionAttempts'] += row.get('legacyQuotaRejectionAttempts', 0)
        counters['recordsWithUnknownHistoricalLoss'] += bool(row.get('legacyQuotaRejectionAttempts', 0))
        counters['discardLedgerSaturatedRecords'] += row.get('discardLedgerSaturated', False)
        for wrapper in row['events']:
            event = wrapper['event']
            all_events.append(wrapper)
            tid = event.get('traceId')
            if tid:
                traces.add(tid)
                if event['source'] != 'relay' and event['role'] in ('caller', 'callee'):
                    reported_roles[tid].add(event['role'])
                if event['outcome'] == 'partial_legacy' or event['values'].get('legacy') or event['values'].get('completeness') == 'legacy':
                    legacy.add(tid)
            counters['retainedEvents'] += 1
            if event['source'] == 'relay' and event['values'].get('storeCommitted'):
                admitted.add(tid)
            if event['stage'] == 'terminal' and event['action'] == 'finish':
                terminal[event['outcome']] += 1
                complete.add(tid)
                if event['source'] != 'relay' and event['role'] in ('caller', 'callee'):
                    terminal_roles[tid].add(event['role'])
            if event['outcome'] == 'media_flow_verified' or event['values'].get('mediaFlowVerified'):
                if event['source'] != 'relay':
                    media.add(tid)
                    if event['role'] in ('caller', 'callee'):
                        media_roles[tid].add(event['role'])
            if event['stage'] == 'push' and event['action'] == 'dispatch' and event['outcome'] == 'started' and event['values'].get('providerInvoked'):
                counters['providerInvocations'] += 1
            if event['stage'] == 'push' and event['action'] == 'dispatch' and event['outcome'] == 'failed' and event['values'].get('providerInvoked'):
                counters['providerFailures'] += 1
            if event['stage'] == 'turn' and event['action'] == 'mint' and event['outcome'] == 'ok':
                counters['turnCredentialsMinted'] += 1
    for values in (traces, admitted, media, complete):
        values.discard(None)
    result = {'schemaVersion': 1, 'observedTraceCount': len(traces), 'mailboxAdmittedTraceCount': len(admitted), 'anyEndpointReportedMediaTraceCount': len(media), 'bothEndpointsReportedMediaTraceCount': sum(roles == {'caller', 'callee'} for roles in media_roles.values()), 'callerTerminalTraceCount': sum('caller' in roles for roles in terminal_roles.values()), 'calleeTerminalTraceCount': sum('callee' in roles for roles in terminal_roles.values()), 'bothEndpointsTerminalTraceCount': sum(roles == {'caller', 'callee'} for roles in terminal_roles.values()), 'missingEndpointTerminalTraceCount': sum(terminal_roles[tid] != {'caller', 'callee'} for tid in traces), 'legacyTraceCount': len(legacy), 'unknownEndpointRoleTraceCount': sum(not reported_roles[tid] for tid in traces), 'tracesWithoutTerminalRecord': len(traces-complete), 'counts': dict(counters), 'terminalRecordOutcomes': dict(terminal), 'invalidOrUnreadableRecordCount': rejected,
              'scope': 'Opted-in retained records only. Client media is reported evidence; relay admission, push submission, and TURN minting do not prove audio. Coturn allocations remain aggregate.'}
    alerts = []
    result['telemetryLossCountExact'] = not (counters['legacyQuotaRejectionAttempts'] or counters['discardLedgerSaturatedRecords'])
    result['lossCountScope'] = 'droppedEvents counts durable distinct permanent trace-cap refusals within a bounded ledger. Saturated ledgers are a lower bound. Legacy quota-rejection attempts include retries and do not establish a unique lost-event count.'
    result['evidenceIncomplete'] = bool(counters['droppedEvents'] or rejected or not result['telemetryLossCountExact'])
    window_count, unknown = 0, int(rejected > 0)
    for row in rows:
        count = row['droppedEvents']
        start = since_ms if since_ms is not None else row.get('_windowSinceMs')
        end = now_ms if now_ms is not None else row.get('_windowEndMs')
        first, updated = row.get('droppedFirstAtMs'), row.get('droppedUpdatedAtMs')
        if row.get('legacyQuotaRejectionAttempts') or row.get('discardLedgerSaturated'):
            unknown += 1
        elif not count:
            continue
        elif type(start) is int and type(end) is int and type(first) is int and type(updated) is int and 0 < first <= updated <= end:
            if updated < start:
                continue
            if first >= start:
                window_count += count
            else:
                unknown += 1
        else:
            unknown += 1
    result['loss'] = {'retainedLifetime': {
        'droppedEvents': counters['droppedEvents'],
        'legacyQuotaRejectionAttempts': counters['legacyQuotaRejectionAttempts'],
        'lossCountIsLowerBound': not result['telemetryLossCountExact'],
        'scope': 'Cumulative counters on retained records, independent of the receipt window.'},
        'window': {'droppedEvents': None if unknown else window_count,
                   'knownDroppedEventsLowerBound': window_count, 'recordsWithUnknownWindowLoss': unknown,
                   'scope': 'Only server counter first/update timestamps can place the whole loss count inside or before the receipt window. Crossing counters, legacy counts and saturated ledgers remain unknown.'}}
    if result['evidenceIncomplete']:
        alerts.append('diagnostic_evidence_incomplete')
    result['alerts'] = alerts
    if trace:
        result['traceId'] = trace
        result['hasRetainedEvents'] = bool(all_events)
        result['endpointCompleteness'] = {'callerTerminal': 'caller' in terminal_roles[trace], 'calleeTerminal': 'callee' in terminal_roles[trace], 'callerReportedMedia': 'caller' in media_roles[trace], 'calleeReportedMedia': 'callee' in media_roles[trace], 'legacy': trace in legacy}
        result['events'] = sorted(all_events, key=lambda x: (x['receivedAtMs'], x['event']['runId'], x['event']['sequence']))
    add_operational_projection(result, all_events, trace)
    return result


def add_operational_projection(result, all_events, trace=None):
    terminal = collections.defaultdict(set)
    attempted, answered, media, cleanup = set(), set(), set(), set()
    preflight, cleanup_failed = set(), set()
    phase_failures = collections.Counter()
    withdrawals = {}
    credentials = collections.Counter()
    failure_rows = []
    for row in all_events:
        e = row['event']
        tid = e.get('traceId')
        failed = e['outcome'] in ('failed', 'rejected', 'timeout', 'blocked', 'preflight_failed', 'signaling_failed', 'native_answer_failed', 'media_failed', 'answered_without_verified_media', 'dropped_after_media')
        if tid and e['source'] != 'relay' and (e['stage'] == 'attempt' or e['role'] == 'caller'):
            attempted.add(tid)
        if tid and e['stage'] == 'terminal' and e['action'] == 'finish' and e['source'] != 'relay':
            terminal[tid].add(e['outcome'])
            if e['outcome'] == 'preflight_failed':
                preflight.add(tid)
        if tid and e['source'] != 'relay' and ((e['stage'] == 'answer' and e['outcome'] == 'ok') or e['values'].get('accepted')):
            answered.add(tid)
        if tid and e['source'] != 'relay' and (e['values'].get('mediaFlowVerified') or e['outcome'] in ('media_flow_verified', 'completed_after_media', 'dropped_after_media')):
            media.add(tid)
            answered.add(tid)
        if failed:
            phase_failures[e['stage']] += 1
            failure_rows.append(row)
            if tid and e['stage'] == 'preflight':
                preflight.add(tid)
        if tid and e['stage'] == 'cleanup':
            cleanup.add(tid)
            if failed or (e['action'] in ('finish', 'stop') and e['values'].get('cleanupRemaining', 0) > 0):
                cleanup_failed.add(tid)
        if e['stage'] == 'authority' and e['action'] in ('revoke', 'invalidate', 'disable'):
            key = e.get('operationId', e['eventId'])
            previous = withdrawals.get(key)
            if previous is None or (previous['reason'] in ('none', 'unknown') and e['reason'] not in ('none', 'unknown')):
                withdrawals[key] = e
        if e['source'] == 'relay' and e['stage'] == 'turn' and e['action'] == 'mint' and e['outcome'] in ('ok', 'failed', 'rejected', 'timeout'):
            credentials['completedRequests'] += 1
            if e['outcome'] != 'ok':
                credentials['failedRequests'] += 1
    neutral = {'declined', 'canceled', 'busy', 'no_answer'}
    technical_setup = {'signaling_failed', 'native_answer_failed', 'media_failed'}
    post_preflight = technical_setup | {'completed_after_media', 'dropped_after_media', 'answered_without_verified_media', 'media_flow_verified'}
    terminal_known = post_preflight | neutral | {'preflight_failed'}
    classified = {tid for tid, outcomes in terminal.items() if outcomes & terminal_known}
    normal = {tid for tid, outcomes in terminal.items() if outcomes & neutral and not outcomes & (technical_setup | {'preflight_failed'})}
    preflight_only = {tid for tid, outcomes in terminal.items() if 'preflight_failed' in outcomes and not outcomes & post_preflight}
    technical_denominator = classified - normal - preflight_only
    setup_failed = {tid for tid, outcomes in terminal.items() if outcomes & technical_setup}
    without_media = {tid for tid, outcomes in terminal.items() if 'answered_without_verified_media' in outcomes}
    after_media = {tid for tid, outcomes in terminal.items() if 'dropped_after_media' in outcomes}
    by_origin = collections.Counter(e['reason'] for e in withdrawals.values())
    ratios = {}
    def ratio(name, numerator, denominator, threshold):
        eligible = denominator >= 5
        value = numerator / denominator if denominator else None
        ratios[name] = {'numerator': numerator, 'denominator': denominator, 'rate': value, 'minimumSamples': 5, 'alertThreshold': threshold, 'alertEligible': eligible}
        if eligible and numerator and value >= threshold:
            result['alerts'].append(name + '_high')
    ratio('preflight_rejection', len(preflight), len(attempted | preflight), 0.2)
    ratio('technical_setup_failure', len(setup_failed), len(technical_denominator), 0.2)
    ratio('answered_without_verified_media', len(without_media), len(answered | without_media), 0.1)
    ratio('drop_after_media', len(after_media), len(media | after_media), 0.1)
    ratio('provider_failure', result['counts'].get('providerFailures', 0), result['counts'].get('providerInvocations', 0), 0.2)
    ratio('credential_failure', credentials['failedRequests'], credentials['completedRequests'], 0.2)
    loss = result['loss']['window']['droppedEvents']
    if loss is None:
        ratios['telemetry_loss'] = {'numerator': None, 'denominator': None, 'rate': None,
            'minimumSamples': 5, 'alertThreshold': 0.000001, 'alertEligible': False}
    else:
        ratio('telemetry_loss', loss, result['counts'].get('retainedEvents', 0) + loss, 0.000001)
    ratios['telemetry_loss']['rateIsLowerBound'] = not result['telemetryLossCountExact']
    ratios['telemetry_loss']['scope'] = 'Timestamp-attributable server loss and retained events in the same receipt window; invalid record counts are coverage gaps, not lost-event counts.'
    ratio('cleanup_failure', len(cleanup_failed), len(cleanup), 0.2)
    ratio('withdrawal_unknown_origin', by_origin['none'] + by_origin['unknown'], len(withdrawals), 0.2)
    result['rates'] = ratios
    result['phaseFailureEventCounts'] = dict(phase_failures)
    result['registrationWithdrawalOperationsByOrigin'] = dict(by_origin)
    result['neutralTerminalTraceCount'] = len(normal)
    result['unclassifiedTerminalTraceCount'] = len(terminal.keys() - classified)
    result['preflightRateScope'] = 'Distinct traces with a failed preflight phase or client terminal preflight_failed, divided by observed client attempt/caller traces plus any preflight-failure traces. Duplicate phase/terminal reports count once. Missing attempts remain outside this retained-evidence denominator.'
    result['technicalRateScope'] = 'Post-preflight signaling/native-answer/media setup failures among distinct opted-in client-reported classified terminal traces. Preflight-only failures and declines/cancels/busy/no-answer are excluded from this denominator. Phase failures can recover and are counted separately. Minimum5 observations before rate alerts.'
    result['alerts'] = sorted(set(result['alerts']))
    if trace:
        relevant = [row for row in all_events if row['event'].get('traceId') == trace]
        present = {row['event']['stage'] for row in relevant}
        failed = sorted((row for row in failure_rows if row['event'].get('traceId') == trace), key=lambda row: row['receivedAtMs'])
        result['firstReceivedFailure'] = None
        if failed:
            row = failed[0]
            result['firstReceivedFailure'] = {'receivedAtMs': row['receivedAtMs'], **{key: value for key, value in row['event'].items() if key in ('source', 'stage', 'action', 'outcome', 'reason', 'requestId', 'operationId', 'parentOperationId')}}
        required = ['attempt', 'preflight', 'signaling', 'presentation', 'answer', 'media', 'cleanup', 'terminal']
        admission_expected = 'admission' in present or any(row['event']['source'] == 'android' and row['event']['role'] == 'callee' and row['event']['stage'] == 'push' for row in relevant)
        if admission_expected:
            required.insert(required.index('presentation'), 'admission')
        result['missingStageReports'] = [stage for stage in required if stage not in present]
        result['firstMissingStageReport'] = next(iter(result['missingStageReports']), None)
        result['presentationReported'] = 'presentation' in present
        result['admissionReported'] = 'admission' in present
        result['answerReported'] = 'answer' in present
        result['cleanupReported'] = 'cleanup' in present
        result['failureOrderingScope'] = 'First relay-received failed phase; different device clocks and delayed uploads do not establish global causal order. Missing stages may be normal for declined/canceled/preflight-only or legacy calls.'
        result['operationChain'] = [{**{key: value for key, value in row['event'].items() if key in ('operationId', 'parentOperationId', 'source', 'stage', 'action', 'outcome', 'reason', 'occurredAtMs')}, 'receivedAtMs': row['receivedAtMs']} for row in relevant if row['event'].get('operationId') or row['event'].get('parentOperationId')]


def attach_authority_chain(result, directory, since_ms, limit):
    references = {row[key] for row in result.get('operationChain', []) for key in ('operationId', 'parentOperationId') if key in row}
    if not references:
        result['unresolvedOperationReferenceCount'] = 0
        return
    rows, rejected = read_records(directory, since_ms, None, limit)
    candidates = [row for record in rows for row in record['events'] if row['event']['stage'] in ('authority', 'runtime')]
    found, added, seen = set(), [], set()
    for _ in range(8):
        changed = False
        for row in candidates:
            e = row['event']
            operation = e.get('operationId')
            if operation not in references or e['eventId'] in seen:
                continue
            found.add(operation)
            seen.add(e['eventId'])
            added.append({**{key: value for key, value in e.items() if key in ('operationId', 'parentOperationId', 'source', 'role', 'stage', 'action', 'outcome', 'reason', 'occurredAtMs', 'values')}, 'receivedAtMs': row['receivedAtMs']})
            parent = e.get('parentOperationId')
            if parent and parent not in references:
                references.add(parent)
                changed = True
            if len(added) >= 128:
                break
        if not changed or len(added) >= 128:
            break
    result['relatedAuthorityOperations'] = added[:128]
    result['unresolvedOperationReferenceCount'] = len(references - found)
    result['authorityJoinAtRecordLimit'] = len(rows) >= limit or len(added) >= 128
    result['authorityJoinInvalidRecordCount'] = rejected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dir', required=True, type=pathlib.Path)
    parser.add_argument('--trace')
    parser.add_argument('--hours', type=int, default=24)
    parser.add_argument('--limit', type=int, default=1000)
    args = parser.parse_args()
    if args.trace and not UUID.fullmatch(args.trace):
        parser.error('--trace requires a canonical UUID')
    if not 1 <= args.hours <= 336 or not 1 <= args.limit <= 1000:
        parser.error('hours must be1..336 and limit1..1000')
    rows, rejected = read_records(args.dir, int(time.time()*1000)-args.hours*3600000, args.trace, args.limit)
    output = report(rows, rejected, args.trace)
    if args.trace:
        attach_authority_chain(output, args.dir, int(time.time()*1000)-args.hours*3600000, args.limit)
    output['recordLimit'] = args.limit
    output['atRecordLimit'] = len(rows) >= args.limit
    print(json.dumps(output, indent=2, sort_keys=True))

if __name__ == '__main__':
    main()
