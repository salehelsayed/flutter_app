import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('group notification content classification', () {
    final cases =
        <
          ({
            String label,
            Map<String, dynamic> data,
            ConversationNotificationContentKind? expected,
          })
        >[
          (
            label: 'reaction wins conflicting type and payloadType',
            data: const <String, dynamic>{
              'type': 'group_message',
              'payloadType': 'group_reaction',
            },
            expected: ConversationNotificationContentKind.reaction,
          ),
          (
            label: 'reaction wins conflicting kind',
            data: const <String, dynamic>{
              'type': 'group_message',
              'kind': 'group_reaction',
            },
            expected: ConversationNotificationContentKind.reaction,
          ),
          (
            label: 'offline replay is a message',
            data: const <String, dynamic>{'kind': 'group_offline_replay'},
            expected: ConversationNotificationContentKind.message,
          ),
          (
            label: 'legacy payload-only group route is a message',
            data: const <String, dynamic>{'payload': 'group:legacy-group'},
            expected: ConversationNotificationContentKind.message,
          ),
          (
            label: 'legacy anchored group route is a message',
            data: const <String, dynamic>{
              'route': 'group:legacy-group|message:legacy-message',
            },
            expected: ConversationNotificationContentKind.message,
          ),
          (
            label: 'values are whitespace normalized',
            data: const <String, dynamic>{'type': '  group_reaction  '},
            expected: ConversationNotificationContentKind.reaction,
          ),
          (
            label: 'unknown route is unclassified',
            data: const <String, dynamic>{'type': 'unknown'},
            expected: null,
          ),
          (
            label: 'empty input is unclassified',
            data: const <String, dynamic>{},
            expected: null,
          ),
        ];

    for (final testCase in cases) {
      test(testCase.label, () {
        expect(
          groupNotificationContentKindFromRemoteData(testCase.data),
          testCase.expected,
        );
      });
    }
  });

  test(
    'typed payload envelope round-trips routing and exact card identity',
    () {
      const metadata = ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: 'message-42',
        generation: 'generation-42',
      );

      final encoded = encodeConversationNotificationPayload(
        routePayload: 'group:group-42|message:message-42',
        conversationKey: 'group:group-42',
        metadata: metadata,
      );
      final decoded = decodeConversationNotificationPayload(encoded);

      expect(decoded?.routePayload, 'group:group-42|message:message-42');
      expect(decoded?.conversationKey, 'group:group-42');
      expect(decoded?.metadata, metadata);
      expect(decodeConversationNotificationPayload('group:legacy'), isNull);
      expect(
        decodeConversationNotificationPayload(
          '${conversationNotificationPayloadEnvelopePrefix}not-base64',
        ),
        isNull,
      );
    },
  );

  test(
    'TC-396 shared direct local envelope vector matches Swift source classifier',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/shared/fixtures/ios_direct_notification_source_v1.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(fixture['version'], 1);
      final expectedPeerId = fixture['expectedPeerId'] as String;
      final expectedMessageId = fixture['expectedMessageId'] as String;
      final vectors = fixture['vectors'] as List<dynamic>;

      bool matchesExpectedLocalEnvelope(Map<String, dynamic> vector) {
        if (vector['origin'] != 'local') return false;
        final userInfo = vector['userInfo'] as Map<String, dynamic>;
        final notificationId = userInfo['NotificationId'];
        if (notificationId is! int ||
            notificationId < 0 ||
            notificationId > 0x7fffffff ||
            userInfo.containsKey('type') ||
            userInfo.containsKey('sender_id') ||
            userInfo.containsKey('message_id')) {
          return false;
        }
        final payload = userInfo['payload'];
        if (payload == expectedPeerId) return true;
        final envelope = decodeConversationNotificationPayload(
          payload is String ? payload : null,
        );
        return envelope?.routePayload == expectedPeerId &&
            envelope?.conversationKey == expectedPeerId &&
            envelope?.metadata.kind ==
                ConversationNotificationContentKind.message &&
            envelope?.metadata.eventIdentity == expectedMessageId;
      }

      for (final rawVector in vectors) {
        final vector = rawVector as Map<String, dynamic>;
        final expectsLocal = vector['expectedSource'] == 'flutter_local';
        expect(
          matchesExpectedLocalEnvelope(vector),
          expectsLocal,
          reason: vector['name'] as String,
        );
      }
    },
  );
}
