import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';

void main() {
  setUp(() {
    flowEventLoggingEnabled = false;
  });

  group('firebaseMessagingBackgroundHandler', () {
    test('completes without error for valid RemoteMessage', () async {
      const message = RemoteMessage(
        messageId: 'msg-123',
        data: {'type': 'inbox', 'peerId': '12D3KooW...'},
      );

      // Should not throw
      await firebaseMessagingBackgroundHandler(message);
    });

    test('handles RemoteMessage with null messageId', () async {
      const message = RemoteMessage(data: {'type': 'inbox'});

      await firebaseMessagingBackgroundHandler(message);
    });

    test('handles RemoteMessage with empty data map', () async {
      const message = RemoteMessage(messageId: 'msg-456');

      await firebaseMessagingBackgroundHandler(message);
    });
  });

  group('shouldShowBackgroundPushFallbackNotification', () {
    test(
      'returns true for data-only message with type=new_message',
      () {
        const message = RemoteMessage(
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWTestPeer',
          },
        );

        expect(
          shouldShowBackgroundPushFallbackNotification(message),
          isTrue,
        );
      },
    );

    test(
      'returns true for data-only message with type=group_message',
      () {
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
          },
        );

        expect(
          shouldShowBackgroundPushFallbackNotification(message),
          isTrue,
        );
      },
    );

    test(
      'returns false when message already has a notification field',
      () {
        const message = RemoteMessage(
          notification: RemoteNotification(
            title: 'Already visible',
            body: 'System notification present',
          ),
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWTestPeer',
          },
        );

        expect(
          shouldShowBackgroundPushFallbackNotification(message),
          isFalse,
        );
      },
    );

    test(
      'returns false when data has no routable keys',
      () {
        const message = RemoteMessage(
          data: {
            'unrelated_key': 'some_value',
          },
        );

        expect(
          shouldShowBackgroundPushFallbackNotification(message),
          isFalse,
        );
      },
    );

    test('returns false for empty data map', () {
      const message = RemoteMessage();

      expect(
        shouldShowBackgroundPushFallbackNotification(message),
        isFalse,
      );
    });

    test(
      'returns true for data-only message with type=intros',
      () {
        const message = RemoteMessage(
          data: {'type': 'intros'},
        );

        expect(
          shouldShowBackgroundPushFallbackNotification(message),
          isTrue,
        );
      },
    );

    test(
      'returns true for data-only message with type=post_create',
      () {
        const message = RemoteMessage(
          data: {
            'type': 'post_create',
            'postId': 'post-xyz-789',
          },
        );

        expect(
          shouldShowBackgroundPushFallbackNotification(message),
          isTrue,
        );
      },
    );

    test(
      'returns false for new_message without sender_id or from field',
      () {
        const message = RemoteMessage(
          data: {'type': 'new_message'},
        );

        expect(
          shouldShowBackgroundPushFallbackNotification(message),
          isFalse,
        );
      },
    );

    test(
      'returns false for group_message without groupId field',
      () {
        const message = RemoteMessage(
          data: {'type': 'group_message'},
        );

        expect(
          shouldShowBackgroundPushFallbackNotification(message),
          isFalse,
        );
      },
    );
  });

  group('buildBackgroundPushFallbackNotification', () {
    test('uses default title and body when data has none', () {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': '12D3KooWTestPeer',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);

      expect(fallback.title, equals(backgroundPushDefaultTitle));
      expect(fallback.body, equals(backgroundPushDefaultBody));
    });

    test('uses custom title and body from data when present', () {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': '12D3KooWTestPeer',
          'title': 'Custom Title',
          'body': 'Custom Body',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);

      expect(fallback.title, equals('Custom Title'));
      expect(fallback.body, equals('Custom Body'));
    });

    test('produces payload from new_message peerId', () {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': '12D3KooWTestPeer',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);

      expect(fallback.payload, equals('12D3KooWTestPeer'));
    });

    test('produces group: prefixed payload for group_message', () {
      const message = RemoteMessage(
        data: {
          'type': 'group_message',
          'groupId': 'group-abc-123',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);

      expect(fallback.payload, equals('group:group-abc-123'));
    });

    test('ignores whitespace-only title and body', () {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': '12D3KooWTestPeer',
          'title': '   ',
          'body': '  ',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);

      expect(fallback.title, equals(backgroundPushDefaultTitle));
      expect(fallback.body, equals(backgroundPushDefaultBody));
    });
  });
}
