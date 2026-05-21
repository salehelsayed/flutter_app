import '../../../core/utils/flow_event_emitter.dart';

const ob011MissedMessageTelemetryEvent =
    'GROUP_RELEASE_MISSED_MESSAGE_TELEMETRY';

const ob011CauseTransport = 'transport';
const ob011CauseKey = 'key';
const ob011CauseMembership = 'membership';
const ob011CauseReplay = 'replay';
const ob011CauseDispatcher = 'dispatcher';
const ob011CauseUiFilter = 'ui_filter';
const ob011CauseUnknown = 'unknown';

const ob011RequiredCauseClasses = <String>{
  ob011CauseTransport,
  ob011CauseKey,
  ob011CauseMembership,
  ob011CauseReplay,
  ob011CauseDispatcher,
  ob011CauseUiFilter,
};

class GroupDeliveryExpectation {
  const GroupDeliveryExpectation({
    required this.groupId,
    required this.messageId,
    required this.senderPeerId,
    required this.recipientPeerId,
    this.keyEpoch,
    this.expectedVia,
  });

  final String groupId;
  final String messageId;
  final String senderPeerId;
  final String recipientPeerId;
  final int? keyEpoch;
  final String? expectedVia;
}

class GroupDeliveryObservation {
  const GroupDeliveryObservation({
    required this.groupId,
    required this.messageId,
    required this.recipientPeerId,
  });

  final String groupId;
  final String messageId;
  final String recipientPeerId;
}

Map<String, dynamic> buildGroupMissedMessageTelemetryReport({
  required Iterable<GroupDeliveryExpectation> expectedDeliveries,
  required Iterable<GroupDeliveryObservation> observedDeliveries,
  required Iterable<Map<String, dynamic>> diagnostics,
}) {
  final observedKeys = observedDeliveries
      .map(
        (observation) => _deliveryKey(
          groupId: observation.groupId,
          messageId: observation.messageId,
          recipientPeerId: observation.recipientPeerId,
        ),
      )
      .toSet();
  final diagnosticList = diagnostics.toList(growable: false);
  final missed = <Map<String, dynamic>>[];
  final causeCounts = <String, int>{
    for (final cause in ob011RequiredCauseClasses) cause: 0,
    ob011CauseUnknown: 0,
  };

  for (final expected in expectedDeliveries) {
    final key = _deliveryKey(
      groupId: expected.groupId,
      messageId: expected.messageId,
      recipientPeerId: expected.recipientPeerId,
    );
    if (observedKeys.contains(key)) continue;

    final match = _bestDiagnosticFor(expected, diagnosticList);
    final cause = _normalizeCause(match) ?? ob011CauseUnknown;
    causeCounts[cause] = (causeCounts[cause] ?? 0) + 1;

    missed.add({
      'groupIdPrefix': _safePrefix(expected.groupId),
      'messageId': expected.messageId,
      'senderPeerIdPrefix': _safePrefix(expected.senderPeerId),
      'recipientPeerIdPrefix': _safePrefix(expected.recipientPeerId),
      'keyEpoch': ?expected.keyEpoch,
      'expectedVia': ?expected.expectedVia,
      'cause': cause,
      'sourceEvent': _sourceEvent(match),
      'resolution': ?_stringValue(match?['resolution']),
      'diagnosticReason': ?_stringValue(match?['reason']),
    });
  }

  final coveredCauseClasses =
      causeCounts.entries
          .where(
            (entry) =>
                ob011RequiredCauseClasses.contains(entry.key) &&
                entry.value > 0,
          )
          .map((entry) => entry.key)
          .toList(growable: false)
        ..sort();

  return {
    'rowId': 'OB-011',
    'schemaVersion': 1,
    'missedMessages': missed,
    'summary': {
      'missedCount': missed.length,
      'causeCounts': causeCounts,
      'coveredCauseClasses': coveredCauseClasses,
      'unknownCount': causeCounts[ob011CauseUnknown] ?? 0,
    },
  };
}

Map<String, dynamic> emitGroupMissedMessageTelemetryReport({
  required Iterable<GroupDeliveryExpectation> expectedDeliveries,
  required Iterable<GroupDeliveryObservation> observedDeliveries,
  required Iterable<Map<String, dynamic>> diagnostics,
}) {
  final report = buildGroupMissedMessageTelemetryReport(
    expectedDeliveries: expectedDeliveries,
    observedDeliveries: observedDeliveries,
    diagnostics: diagnostics,
  );
  emitFlowEvent(
    layer: 'FL',
    event: ob011MissedMessageTelemetryEvent,
    details: report,
  );
  return report;
}

String _deliveryKey({
  required String groupId,
  required String messageId,
  required String recipientPeerId,
}) => '$groupId\n$messageId\n$recipientPeerId';

Map<String, dynamic>? _bestDiagnosticFor(
  GroupDeliveryExpectation expected,
  List<Map<String, dynamic>> diagnostics,
) {
  Map<String, dynamic>? fallback;
  for (final diagnostic in diagnostics) {
    final messageMatches = _matchesOptional(
      diagnostic,
      'messageId',
      expected.messageId,
    );
    final groupMatches = _matchesOptional(
      diagnostic,
      'groupId',
      expected.groupId,
    );
    final recipientMatches =
        _matchesOptional(
          diagnostic,
          'recipientPeerId',
          expected.recipientPeerId,
        ) ||
        _matchesOptional(
          diagnostic,
          'targetPeerId',
          expected.recipientPeerId,
        ) ||
        _matchesOptional(diagnostic, 'recipientId', expected.recipientPeerId);

    if (messageMatches && groupMatches && recipientMatches) {
      return diagnostic;
    }
    if (fallback == null && messageMatches && groupMatches) {
      fallback = diagnostic;
    }
  }
  return fallback;
}

bool _matchesOptional(
  Map<String, dynamic> diagnostic,
  String key,
  String expected,
) {
  final value = _lookupDiagnosticValue(diagnostic, key);
  if (value == null) return true;
  return value == expected;
}

String? _normalizeCause(Map<String, dynamic>? diagnostic) {
  if (diagnostic == null) return null;
  for (final key in const <String>[
    'missedMessageCause',
    'cause',
    'reasonCategory',
    'category',
  ]) {
    final explicit = _normalizeCauseValue(
      _lookupDiagnosticValue(diagnostic, key),
    );
    if (explicit != null) return explicit;
  }

  final event = _sourceEvent(diagnostic).toLowerCase();
  final reason = (_lookupDiagnosticValue(diagnostic, 'reason') ?? '')
      .toLowerCase();
  final text = '$event $reason';
  if (text.contains('dispatcher') || text.contains('overflow')) {
    return ob011CauseDispatcher;
  }
  if (text.contains('ui_filter') ||
      text.contains('visibility') ||
      text.contains('entitlement') ||
      text.contains('conversation_filter')) {
    return ob011CauseUiFilter;
  }
  if (text.contains('replay') ||
      text.contains('inbox') ||
      text.contains('drain') ||
      text.contains('cursor')) {
    return ob011CauseReplay;
  }
  if (text.contains('decrypt') ||
      text.contains('key') ||
      text.contains('epoch')) {
    return ob011CauseKey;
  }
  if (text.contains('member') ||
      text.contains('unauthorized') ||
      text.contains('removed') ||
      text.contains('unknown_sender')) {
    return ob011CauseMembership;
  }
  if (text.contains('transport') ||
      text.contains('zero_peers') ||
      text.contains('partial_peers') ||
      text.contains('publish') ||
      text.contains('background')) {
    return ob011CauseTransport;
  }
  return null;
}

String? _normalizeCauseValue(Object? value) {
  final normalized = value?.toString().trim().toLowerCase().replaceAll(
    '-',
    '_',
  );
  if (normalized == null || normalized.isEmpty) return null;
  if (ob011RequiredCauseClasses.contains(normalized)) return normalized;
  if (normalized == 'ui' || normalized == 'filter') {
    return ob011CauseUiFilter;
  }
  if (normalized == 'live_transport' || normalized == 'network') {
    return ob011CauseTransport;
  }
  if (normalized == 'key_epoch' || normalized == 'decryption') {
    return ob011CauseKey;
  }
  if (normalized == 'member' || normalized == 'authorization') {
    return ob011CauseMembership;
  }
  if (normalized == 'offline_replay' || normalized == 'inbox_replay') {
    return ob011CauseReplay;
  }
  return null;
}

String _sourceEvent(Map<String, dynamic>? diagnostic) {
  return _stringValue(diagnostic?['event']) ??
      _stringValue(diagnostic?['sourceEvent']) ??
      'none';
}

String? _lookupDiagnosticValue(Map<String, dynamic> diagnostic, String key) {
  final direct = diagnostic[key];
  if (direct != null) return direct.toString();
  final details = diagnostic['details'];
  if (details is Map && details[key] != null) return details[key].toString();
  return null;
}

String? _stringValue(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

String _safePrefix(String value) {
  if (value.length <= 8) return value;
  return value.substring(0, 8);
}
