import 'package:flutter_app/core/debug/keepalive_drop_e2e_contract.dart';

import '../../tool/sims/device_criteria.dart';
import 'sims_runtime_protocol.dart';

const String keepaliveArtifactValidatorId = 'validateKeepaliveDropArtifact';

String? validateKeepaliveCampaignInvocation(SimsRuntimeInvocation invocation) {
  if (invocation.schema != simsRuntimeConfigSchema ||
      invocation.profileId != keepaliveDropProfileId ||
      invocation.scenarioId != keepaliveDropScenarioId ||
      invocation.role != 'sender' ||
      invocation.runId.isEmpty ||
      invocation.nonce.isEmpty) {
    return 'keepalive runtime tuple is invalid';
  }
  final targetId = invocation.values['targetId'];
  final targetKind = invocation.values['targetKind'];
  final digest = invocation.values['buildArtifactSha256'];
  if (targetId is! String ||
      targetId.isEmpty ||
      targetKind != 'physical' ||
      digest is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    return 'keepalive runtime values are invalid';
  }
  return null;
}

String? validateKeepaliveDroppedSendResult(
  Map<String, Object?> result, {
  required SimsRuntimeInvocation invocation,
  required String targetPeerId,
}) {
  final tupleFailure = _resultTupleFailure(
    result,
    invocation: invocation,
    schema: keepaliveDroppedSendResultSchema,
    stepId: keepaliveDroppedSendStepId(invocation.runId),
    expectedStatus: 'complete',
  );
  if (tupleFailure != null) return tupleFailure;
  final messageId = result['messageId'];
  final prefix = result['messageIdPrefix'];
  if (messageId is! String ||
      prefix is! String ||
      keepaliveMessageIdPrefix(messageId) != prefix ||
      result['text'] != keepaliveRunMessageText(invocation.runId) ||
      result['dropLatchedBeforeSend'] != true ||
      result['dropLatchedAfterSend'] != true ||
      result['connectedBeforeSend'] != false ||
      result['localBeforeSend'] != false) {
    return 'keepalive dropped-send observations are invalid';
  }
  final transport = result['transport'];
  final status = result['messageStatus'];
  if (transport is! String ||
      !const <String>{'direct', 'relay', 'inbox'}.contains(transport) ||
      status is! String ||
      !const <String>{'inboxed', 'delivered'}.contains(status)) {
    return 'keepalive real send did not return an accepted transport/status';
  }
  final events = _strings(result['sendWindowEvents']);
  const required = <String>{
    'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
    'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP',
    'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
  };
  if (!events.toSet().containsAll(required)) {
    return 'keepalive dropped-send result is missing production events';
  }
  final begin = events.indexOf('CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN');
  final skip = events.indexOf('SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP');
  final custody = events.indexOf('CHAT_MSG_SEND_CUSTODY_CONFIRMED');
  if (begin < 0 || skip <= begin || custody <= begin) {
    return 'keepalive dropped-send events are out of order';
  }
  const forbidden = <String>{
    'P2P_SERVICE_DISCOVER_PEER',
    'P2P_SERVICE_DISCOVER_PEER_BEGIN',
    'P2P_SERVICE_DISCOVER_PEER_SUCCESS',
    'P2P_SERVICE_DISCOVER_PEER_NOT_FOUND',
    'P2P_SERVICE_DISCOVER_PEER_EXCEPTION',
    'P2P_SERVICE_DIAL_PEER',
    'P2P_SERVICE_DIAL_PEER_BEGIN',
    'P2P_SERVICE_DIAL_PEER_SUCCESS',
    'P2P_SERVICE_DIAL_PEER_ERROR',
    'P2P_SERVICE_DIAL_PEER_EXCEPTION',
  };
  if (events.any(forbidden.contains)) {
    return 'keepalive dropped-send window contains a direct attempt';
  }
  final latency = result['custodyLatencyMs'];
  if (latency is! num || latency < 0 || latency >= 1000) {
    return 'keepalive dropped-send custody is not sub-second';
  }
  final records = _records(result['messageEvents']);
  for (final event in const <String>[
    'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
    'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
  ]) {
    if (!_hasRecord(records, event, prefix, events)) {
      return 'keepalive dropped-send $event is not message-correlated';
    }
  }
  if (targetPeerId.isEmpty) {
    return 'keepalive target peer is empty';
  }
  return null;
}

String? validateKeepaliveRecoveryResult(
  Map<String, Object?> result, {
  required SimsRuntimeInvocation invocation,
  required String messageId,
}) {
  final tupleFailure = _resultTupleFailure(
    result,
    invocation: invocation,
    schema: keepaliveRecoveryResultSchema,
    stepId: keepaliveRecoveryStepId(invocation.runId),
    expectedStatus: 'complete',
  );
  if (tupleFailure != null) return tupleFailure;
  final prefix = keepaliveMessageIdPrefix(messageId);
  if (result['messageIdPrefix'] != prefix ||
      result['dropLatchedAfterRecovery'] != false ||
      result['messageStatus'] != 'delivered' ||
      result['postDropPeerPingObserved'] != true) {
    return 'keepalive recovery did not prove delivery and re-arm';
  }
  final events = _strings(result['events']);
  if (!events.contains('DELIVERY_RECEIPT_APPLIED') ||
      !events.contains('P2P_SERVICE_PEER_PING_SUCCESS')) {
    return 'keepalive recovery is missing receipt or peer ping';
  }
  final receipt = _record(result['receiptEvent']);
  if (receipt == null ||
      !_hasRecord(
        <_EventRecord>[receipt],
        'DELIVERY_RECEIPT_APPLIED',
        prefix,
        events,
      )) {
    return 'keepalive delivery receipt belongs to another message';
  }
  return null;
}

Map<String, Object?> assembleKeepaliveDropArtifact({
  required Map<String, Object?> sendResult,
  required Map<String, Object?> recoveryResult,
  required Iterable<String> deviceIds,
}) {
  final sendEvents = _strings(sendResult['sendWindowEvents']);
  final recoveryEvents = _strings(recoveryResult['events']);
  final events = <String>[
    'KEEPALIVE_PEER_DROP',
    ...sendEvents,
    ...recoveryEvents,
  ];
  final prefix = sendResult['messageIdPrefix']! as String;
  final messageEvents = <Map<String, Object?>>[];
  for (final record in _records(sendResult['messageEvents'])) {
    messageEvents.add(record.shifted(1).toJson());
  }
  final receipt = _record(recoveryResult['receiptEvent']);
  if (receipt != null) {
    messageEvents.add(receipt.shifted(1 + sendEvents.length).toJson());
  }
  final artifact = <String, Object?>{
    'scenario': keepaliveDropScenarioId,
    'status': 'passed',
    'deviceIds': List<String>.unmodifiable(deviceIds),
    'events': events,
    'sendWindowEvents': sendEvents,
    'messageIdPrefix': prefix,
    'messageEvents': messageEvents,
    'custodyLatencyMs': sendResult['custodyLatencyMs'],
  };
  final validation = validateKeepaliveDropArtifact(artifact);
  if (!validation.ok) {
    throw StateError(validation.detail);
  }
  return Map<String, Object?>.unmodifiable(artifact);
}

String? _resultTupleFailure(
  Map<String, Object?> result, {
  required SimsRuntimeInvocation invocation,
  required String schema,
  required String stepId,
  required String expectedStatus,
}) {
  if (result['schema'] != schema ||
      result['profileId'] != invocation.profileId ||
      result['scenario'] != invocation.scenarioId ||
      result['role'] != invocation.role ||
      result['runId'] != invocation.runId ||
      result['nonce'] != invocation.nonce ||
      result['stepId'] != stepId ||
      result['status'] != expectedStatus ||
      result['success'] != true) {
    return 'keepalive app result does not match the runtime tuple';
  }
  return null;
}

List<String> _strings(Object? value) => value is Iterable
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];

List<_EventRecord> _records(Object? value) => value is Iterable
    ? value.map(_record).whereType<_EventRecord>().toList(growable: false)
    : const <_EventRecord>[];

_EventRecord? _record(Object? value) {
  if (value is! Map) return null;
  final event = value['event'];
  final eventIndex = value['eventIndex'];
  final prefix = value['messageIdPrefix'];
  if (event is! String || eventIndex is! int || prefix is! String) return null;
  return _EventRecord(event, eventIndex, prefix);
}

bool _hasRecord(
  List<_EventRecord> records,
  String event,
  String prefix,
  List<String> events,
) => records.any(
  (record) =>
      record.event == event &&
      record.prefix == prefix &&
      record.index >= 0 &&
      record.index < events.length &&
      events[record.index] == event,
);

final class _EventRecord {
  const _EventRecord(this.event, this.index, this.prefix);

  final String event;
  final int index;
  final String prefix;

  _EventRecord shifted(int offset) =>
      _EventRecord(event, index + offset, prefix);

  Map<String, Object?> toJson() => <String, Object?>{
    'event': event,
    'eventIndex': index,
    'messageIdPrefix': prefix,
  };
}
