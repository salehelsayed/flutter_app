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
}
