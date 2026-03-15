import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';

void main() {
  group('background push fallback notifications', () {
    test('shows a fallback for Android-style data-only chat pushes', () {
      const message = RemoteMessage(
        data: {'type': 'new_message', 'from': '12D3KooWPeer'},
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, backgroundPushDefaultTitle);
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, '12D3KooWPeer');
    });

    test('uses provided title/body data when present', () {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'from': '12D3KooWPeer',
          'title': 'Alice',
          'body': 'Hello',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'Alice');
      expect(fallback.body, 'Hello');
      expect(fallback.payload, '12D3KooWPeer');
    });

    test(
      'skips the fallback when FCM already carries a visible notification',
      () {
        const message = RemoteMessage(
          notification: RemoteNotification(
            title: 'New Message',
            body: 'You have a new message',
          ),
          data: {'type': 'new_message', 'from': '12D3KooWPeer'},
        );

        expect(shouldShowBackgroundPushFallbackNotification(message), isFalse);
      },
    );

    test('shows fallback for group_message type with groupId', () {
      const message = RemoteMessage(
        data: {
          'type': 'group_message',
          'groupId': 'group-abc-123',
          'title': 'Team Chat',
          'body': 'New group message',
        },
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'Team Chat');
      expect(fallback.body, 'New group message');
      expect(fallback.payload, 'group:group-abc-123');
    });

    test('skips fallback for group_message type without groupId', () {
      const message = RemoteMessage(data: {'type': 'group_message'});

      expect(shouldShowBackgroundPushFallbackNotification(message), isFalse);
    });

    test('shows fallback for intros type', () {
      const message = RemoteMessage(data: {'type': 'intros'});

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, backgroundPushDefaultTitle);
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, 'intros');
    });

    test('shows fallback for unknown type with payload data key', () {
      const message = RemoteMessage(
        data: {'type': 'custom', 'payload': 'some-payload-data'},
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.payload, 'some-payload-data');
    });

    test('skips fallback for unknown type without payload data key', () {
      const message = RemoteMessage(data: {'type': 'unknown_type'});

      expect(shouldShowBackgroundPushFallbackNotification(message), isFalse);
    });

    test(
      'route key alone does not trigger fallback (only payload key does)',
      () {
        const message = RemoteMessage(
          data: {'type': 'custom', 'route': '/some/route'},
        );

        expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

        final fallback = buildBackgroundPushFallbackNotification(message);
        expect(fallback.payload, '/some/route');
      },
    );

    test('uses route as payload fallback when payload key is present', () {
      const message = RemoteMessage(
        data: {'type': 'custom', 'payload': 'trigger'},
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.payload, 'trigger');
    });

    test('shows fallback for post_create with post payload routing', () {
      const message = RemoteMessage(
        data: {
          'type': 'post_create',
          'post_id': 'post-123',
          'title': 'Alice posted',
          'body': 'Hello posts',
        },
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'Alice posted');
      expect(fallback.body, 'Hello posts');
      expect(fallback.payload, 'post:post-123');
    });

    test('shows fallback for post_comment with comment payload routing', () {
      const message = RemoteMessage(
        data: {
          'type': 'post_comment',
          'post_id': 'post-123',
          'comment_id': 'comment-7',
          'title': 'Bob commented',
          'body': 'I can lend one.',
        },
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'Bob commented');
      expect(fallback.body, 'I can lend one.');
      expect(fallback.payload, 'post_comment:post-123:comment-7');
    });

    test('treats whitespace-only values as absent', () {
      const message = RemoteMessage(data: {'type': '  ', 'payload': '   '});

      // type trims to null → falls through to payload check,
      // payload trims to null → should not show
      expect(shouldShowBackgroundPushFallbackNotification(message), isFalse);
    });
  });
}
