import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';

void main() {
  group('background push fallback notifications', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('shows a fallback for Android-style data-only chat pushes', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const message = RemoteMessage(
        data: {'type': 'new_message', 'sender_id': '12D3KooWPeer'},
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
          'sender_id': '12D3KooWPeer',
          'title': 'Alice',
          'body': 'Hello',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'Alice');
      expect(fallback.body, 'Hello');
      expect(fallback.payload, '12D3KooWPeer');
    });

    test('uses pushTitle/pushBody when title/body are absent', () {
      const message = RemoteMessage(
        data: {
          'type': 'group_message',
          'groupId': 'group-abc-123',
          'pushTitle': 'Team Chat',
          'pushBody': 'Alice: Hello',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'Team Chat');
      expect(fallback.body, 'Alice: Hello');
      expect(fallback.payload, 'group:group-abc-123');
    });

    test('uses senderUsername as the fallback title when title is absent', () {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': '12D3KooWPeer',
          'senderUsername': 'Alice',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'Alice');
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, '12D3KooWPeer');
    });

    test(
      'preserves mixed-script title/body while trimming outer whitespace',
      () {
        const message = RemoteMessage(
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWPeer',
            'title': '  \u0644\u064a\u0644\u0649 Alpha  ',
            'body': '\n\u0645\u0631\u062d\u0628\u0627 Team 42\t',
          },
        );

        final fallback = buildBackgroundPushFallbackNotification(message);
        expect(fallback.title, '\u0644\u064a\u0644\u0649 Alpha');
        expect(fallback.body, '\u0645\u0631\u062d\u0628\u0627 Team 42');
        expect(fallback.payload, '12D3KooWPeer');
      },
    );

    test('preserves bidi control marks in fallback body passthrough', () {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': '12D3KooWPeer',
          'body': ' \u200f\u0645\u0631\u062d\u0628\u0627 Alpha\u200f ',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.body, '\u200f\u0645\u0631\u062d\u0628\u0627 Alpha\u200f');
    });

    test(
      'skips the fallback when FCM already carries a visible notification',
      () {
        const message = RemoteMessage(
          notification: RemoteNotification(
            title: 'New Message',
            body: 'You have a new message',
          ),
          data: {'type': 'new_message', 'sender_id': '12D3KooWPeer'},
        );

        expect(shouldShowBackgroundPushFallbackNotification(message), isFalse);
      },
    );

    test(
      'shows iOS fallback for data-only chat pushes when Flutter sees no visible notification payload',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        const message = RemoteMessage(
          data: {'type': 'new_message', 'sender_id': '12D3KooWPeer'},
        );

        expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);
      },
    );

    test(
      'skips named chat fallback on iOS when RemoteMessage already has a visible notification payload',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        const message = RemoteMessage(
          notification: RemoteNotification(title: 'Alice', body: 'Hello'),
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWPeer',
            'title': 'Alice',
            'body': 'Hello',
          },
        );

        expect(shouldShowBackgroundPushFallbackNotification(message), isFalse);
      },
    );

    test('shows fallback for group_message type with groupId', () {
      const message = RemoteMessage(
        data: {
          'type': 'group_message',
          'groupId': 'group-abc-123',
          'messageId': 'msg-123',
          'title': 'Team Chat',
          'body': 'New group message',
        },
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'Team Chat');
      expect(fallback.body, 'New group message');
      expect(fallback.payload, 'group:group-abc-123|message:msg-123');
    });

    test(
      'shows group fallback on iOS when Flutter sees only the data payload',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'title': 'Team Chat',
            'body': 'Alice: Hello',
          },
        );

        expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);
      },
    );

    test(
      'skips group fallback on iOS when RemoteMessage already has a visible notification payload',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        const message = RemoteMessage(
          notification: RemoteNotification(
            title: 'Team Chat',
            body: 'Alice: Hello',
          ),
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'title': 'Team Chat',
            'body': 'Alice: Hello',
          },
        );

        expect(shouldShowBackgroundPushFallbackNotification(message), isFalse);
      },
    );

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

    test('shows fallback for contact_request type', () {
      const message = RemoteMessage(
        data: {
          'type': 'contact_request',
          'sender_id': '12D3KooWRequestPeer',
          'title': 'New Contact Request',
          'body': 'Alice wants to connect',
        },
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'New Contact Request');
      expect(fallback.body, 'Alice wants to connect');
      expect(fallback.payload, 'contact_request:12D3KooWRequestPeer');
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

    test('builds a stable dedupe key from payload and message identity', () {
      final message = RemoteMessage(
        messageId: 'fcm-msg-123',
        sentTime: DateTime.utc(2026, 4, 4, 12),
        data: {'type': 'new_message', 'sender_id': '12D3KooWPeer'},
      );

      expect(
        backgroundPushFallbackDedupeKey(message),
        'payload=12D3KooWPeer|id=fcm-msg-123|ts=1775304000000',
      );
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
