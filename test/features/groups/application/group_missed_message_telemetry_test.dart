import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_missed_message_telemetry.dart';

void main() {
  group('OB-011 group missed message telemetry', () {
    test('OB-011 classifies every missed-message cause without unknowns', () {
      final expected = <GroupDeliveryExpectation>[
        _expected('msg-transport', 'peer-bob-ob011-transport'),
        _expected('msg-key', 'peer-bob-ob011-key', keyEpoch: 2),
        _expected('msg-membership', 'peer-charlie-ob011-membership'),
        _expected('msg-replay', 'peer-bob-ob011-replay'),
        _expected('msg-dispatcher', 'peer-bob-ob011-dispatcher'),
        _expected('msg-ui', 'peer-bob-ob011-ui'),
        _expected('msg-delivered', 'peer-bob-ob011-delivered'),
      ];
      final observed = <GroupDeliveryObservation>[
        const GroupDeliveryObservation(
          groupId: 'group-ob011-release-telemetry',
          messageId: 'msg-delivered',
          recipientPeerId: 'peer-bob-ob011-delivered',
        ),
      ];
      final diagnostics = <Map<String, dynamic>>[
        _diagnostic(
          messageId: 'msg-transport',
          recipientPeerId: 'peer-bob-ob011-transport',
          event: 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
          cause: ob011CauseTransport,
          reason: 'zero_peers',
          resolution: 'relay_inbox_pending',
        ),
        _diagnostic(
          messageId: 'msg-key',
          recipientPeerId: 'peer-bob-ob011-key',
          event: 'GROUP_DECRYPTION_FAILED',
          cause: ob011CauseKey,
          reason: 'missing_epoch_key',
          resolution: 'repair_requested',
        ),
        _diagnostic(
          messageId: 'msg-membership',
          recipientPeerId: 'peer-charlie-ob011-membership',
          event: 'GROUP_MESSAGE_LISTENER_UNKNOWN_SENDER_REJECTED',
          cause: ob011CauseMembership,
          reason: 'removed_member',
        ),
        _diagnostic(
          messageId: 'msg-replay',
          recipientPeerId: 'peer-bob-ob011-replay',
          event: 'GROUP_INBOX_REPLAY_CURSOR_GAP',
          cause: ob011CauseReplay,
          reason: 'cursor_gap',
          resolution: 'retry_replay',
        ),
        _diagnostic(
          messageId: 'msg-dispatcher',
          recipientPeerId: 'peer-bob-ob011-dispatcher',
          event: 'GROUP_DISPATCHER_OVERFLOW_RECOVERY_REQUESTED',
          cause: ob011CauseDispatcher,
          reason: 'dispatcher_overflow',
        ),
        _diagnostic(
          messageId: 'msg-ui',
          recipientPeerId: 'peer-bob-ob011-ui',
          event: 'GROUP_CONVERSATION_UI_FILTERED_MESSAGE',
          cause: ob011CauseUiFilter,
          reason: 'visibility_filter',
        ),
      ];

      final report = buildGroupMissedMessageTelemetryReport(
        expectedDeliveries: expected,
        observedDeliveries: observed,
        diagnostics: diagnostics,
      );

      final missed = report['missedMessages'] as List;
      expect(missed, hasLength(6));
      expect(
        missed.map((entry) => (entry as Map)['cause']).toSet(),
        equals(ob011RequiredCauseClasses),
      );
      expect(
        missed.map((entry) => (entry as Map)['messageId']),
        isNot(contains('msg-delivered')),
      );
      for (final entry in missed.cast<Map>()) {
        expect(entry['groupIdPrefix'], equals('group-ob'));
        expect(entry['senderPeerIdPrefix'], equals('peer-ali'));
        expect((entry['recipientPeerIdPrefix'] as String).length, 8);
        expect(entry['sourceEvent'], isNot('none'));
      }

      final summary = report['summary'] as Map;
      expect(summary['unknownCount'], 0);
      expect(
        summary['coveredCauseClasses'],
        equals(ob011RequiredCauseClasses.toList()..sort()),
      );
    });

    test('OB-011 emits a sanitized release telemetry flow event', () {
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final report = emitGroupMissedMessageTelemetryReport(
        expectedDeliveries: <GroupDeliveryExpectation>[
          _expected('msg-transport', 'peer-bob-ob011-transport'),
        ],
        observedDeliveries: const <GroupDeliveryObservation>[],
        diagnostics: <Map<String, dynamic>>[
          _diagnostic(
            messageId: 'msg-transport',
            recipientPeerId: 'peer-bob-ob011-transport',
            event: 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
            cause: ob011CauseTransport,
            reason: 'zero_peers',
          ),
        ],
      );

      expect(report['rowId'], 'OB-011');
      expect(events, hasLength(1));
      final event = events.single;
      expect(event['event'], ob011MissedMessageTelemetryEvent);
      final details = event['details'] as Map;
      expect(details['rowId'], 'OB-011');
      expect(details.toString(), isNot(contains('peer-bob-ob011-transport')));
      expect(details.toString(), contains('peer-bob'));
    });
  });
}

GroupDeliveryExpectation _expected(
  String messageId,
  String recipientPeerId, {
  int keyEpoch = 1,
}) {
  return GroupDeliveryExpectation(
    groupId: 'group-ob011-release-telemetry',
    messageId: messageId,
    senderPeerId: 'peer-alice-ob011-release',
    recipientPeerId: recipientPeerId,
    keyEpoch: keyEpoch,
    expectedVia: 'live_or_replay',
  );
}

Map<String, dynamic> _diagnostic({
  required String messageId,
  required String recipientPeerId,
  required String event,
  required String cause,
  required String reason,
  String? resolution,
}) {
  return {
    'event': event,
    'messageId': messageId,
    'groupId': 'group-ob011-release-telemetry',
    'recipientPeerId': recipientPeerId,
    'missedMessageCause': cause,
    'reason': reason,
    'resolution': ?resolution,
  };
}
