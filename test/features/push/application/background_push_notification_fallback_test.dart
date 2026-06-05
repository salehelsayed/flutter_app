import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';
import 'package:flutter_app/features/push/application/resolve_group_notification_route_target_use_case.dart';

import '../../../shared/fakes/fake_notification_service.dart';

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

    test('ignores title/body data on protected chat pushes', () {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': '12D3KooWPeer',
          'title': 'Alice',
          'body': 'Hello',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, backgroundPushDefaultTitle);
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, '12D3KooWPeer');
    });

    test('ignores retired pushTitle/pushBody preview fields', () {
      const message = RemoteMessage(
        data: {
          'type': 'group_message',
          'groupId': 'group-abc-123',
          'pushTitle': 'Team Chat',
          'pushBody': 'Alice: Hello',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, backgroundPushDefaultTitle);
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, 'group:group-abc-123');
    });

    test('ignores retired senderUsername preview fallback', () {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': '12D3KooWPeer',
          'senderUsername': 'Alice',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, backgroundPushDefaultTitle);
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, '12D3KooWPeer');
    });

    test('preserves mixed-script title/body for non-message fallback copy', () {
      const message = RemoteMessage(
        data: {
          'type': 'contact_request',
          'sender_id': '12D3KooWPeer',
          'title': '  \u0644\u064a\u0644\u0649 Alpha  ',
          'body': '\n\u0645\u0631\u062d\u0628\u0627 Team 42\t',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, '\u0644\u064a\u0644\u0649 Alpha');
      expect(fallback.body, '\u0645\u0631\u062d\u0628\u0627 Team 42');
      expect(fallback.payload, 'contact_request:12D3KooWPeer');
    });

    test('preserves bidi control marks in non-message fallback body', () {
      const message = RemoteMessage(
        data: {
          'type': 'contact_request',
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
      expect(fallback.title, backgroundPushDefaultTitle);
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, 'group:group-abc-123|message:msg-123');
    });

    test('shows fallback for group-message aliases', () {
      const message = RemoteMessage(
        data: {
          'payloadType': 'group_message',
          'group_id': 'group-snake-123',
          'message_id': 'msg-123',
          'title': 'Team Chat',
          'body': 'New group message',
        },
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, backgroundPushDefaultTitle);
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, 'group:group-snake-123|message:msg-123');
    });

    test(
      'foreground fallback helper shows local notification when requested',
      () async {
        final notificationService = FakeNotificationService();
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'message_id': 'msg-123',
            'title': 'Team Chat',
            'body': 'New group message',
          },
        );

        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: message,
          groupMessageDisplayEligibilityResolver: (_) async =>
              const GroupMessageNotificationDisplayEligibility.allowCurrentMember(),
        );

        expect(shown, isTrue);
        expect(notificationService.shownGeneric, hasLength(1));
        expect(notificationService.shownGeneric.single.title, 'New Message');
        expect(
          notificationService.shownGeneric.single.body,
          'You have a new message',
        );
        expect(
          notificationService.shownGeneric.single.payload,
          'group:group-abc-123|message:msg-123',
        );
      },
    );

    test(
      'foreground fallback shows current-member group_message with visible FCM payload',
      () async {
        final notificationService = FakeNotificationService();
        const message = RemoteMessage(
          notification: RemoteNotification(
            title: 'Team Chat',
            body: 'Alice: Hello',
          ),
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'message_id': 'msg-123',
            'title': 'Team Chat',
            'body': 'Alice: Hello',
          },
        );

        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: message,
          groupMessageDisplayEligibilityResolver: (groupId) async {
            expect(groupId, 'group-abc-123');
            return const GroupMessageNotificationDisplayEligibility.allowCurrentMember();
          },
        );

        expect(shown, isTrue);
        expect(notificationService.shownGeneric, hasLength(1));
        expect(notificationService.shownGeneric.single.title, 'New Message');
        expect(
          notificationService.shownGeneric.single.body,
          'You have a new message',
        );
        expect(
          notificationService.shownGeneric.single.payload,
          'group:group-abc-123|message:msg-123',
        );
      },
    );

    test(
      'foreground fallback suppresses non-current group_message with visible FCM payload',
      () async {
        final notificationService = FakeNotificationService();
        const message = RemoteMessage(
          notification: RemoteNotification(
            title: 'Team Chat',
            body: 'Alice: Hello',
          ),
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'message_id': 'msg-123',
            'title': 'Team Chat',
            'body': 'Alice: Hello',
          },
        );

        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: message,
          groupMessageDisplayEligibilityResolver: (groupId) async {
            expect(groupId, 'group-abc-123');
            return const GroupMessageNotificationDisplayEligibility.suppressed(
              'local_member_missing',
            );
          },
        );

        expect(shown, isFalse);
        expect(notificationService.shownGeneric, isEmpty);
      },
    );

    test('foreground fallback helper is a no-op when not requested', () async {
      final notificationService = FakeNotificationService();
      const message = RemoteMessage(
        data: {'type': 'group_message', 'groupId': 'group-abc-123'},
      );

      final shown = await showForegroundPushFallbackNotificationIfNeeded(
        result: ForegroundRemoteMessageResult.drained,
        notificationService: notificationService,
        message: message,
      );

      expect(shown, isFalse);
      expect(notificationService.shownGeneric, isEmpty);
    });

    test(
      'display eligibility suppresses ordinary group_message fallback without current membership',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'message_id': 'msg-123',
          },
        );

        final result = await resolveBackgroundPushFallbackDisplayEligibility(
          message,
          groupMessageDisplayEligibilityResolver: (groupId) async {
            expect(groupId, 'group-abc-123');
            return const GroupMessageNotificationDisplayEligibility.suppressed(
              'group_missing',
            );
          },
        );

        expect(result.shouldDisplay, isFalse);
        expect(result.reason, 'group_missing');
      },
    );

    test(
      'display eligibility preserves ordinary group_message fallback for current members',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'message_id': 'msg-123',
          },
        );

        final result = await resolveBackgroundPushFallbackDisplayEligibility(
          message,
          groupMessageDisplayEligibilityResolver: (groupId) async {
            expect(groupId, 'group-abc-123');
            return const GroupMessageNotificationDisplayEligibility.allowCurrentMember();
          },
        );

        expect(result.shouldDisplay, isTrue);
        expect(result.reason, 'display_allowed');
      },
    );

    test(
      'display eligibility suppresses payload-only group route without current membership',
      () async {
        const message = RemoteMessage(
          data: {'payload': 'group:group-abc-123|message:msg-legacy'},
        );

        final result = await resolveBackgroundPushFallbackDisplayEligibility(
          message,
          groupMessageDisplayEligibilityResolver: (groupId) async {
            expect(groupId, 'group-abc-123');
            return const GroupMessageNotificationDisplayEligibility.suppressed(
              'local_member_missing',
            );
          },
        );

        expect(result.shouldDisplay, isFalse);
        expect(result.reason, 'local_member_missing');
      },
    );

    test(
      'foreground fallback preserves payload-only group route for current members',
      () async {
        final notificationService = FakeNotificationService();
        const message = RemoteMessage(
          data: {'payload': 'group:group-abc-123|message:msg-legacy'},
        );

        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: message,
          groupMessageDisplayEligibilityResolver: (groupId) async {
            expect(groupId, 'group-abc-123');
            return const GroupMessageNotificationDisplayEligibility.allowCurrentMember();
          },
        );

        expect(shown, isTrue);
        expect(notificationService.shownGeneric, hasLength(1));
        expect(
          notificationService.shownGeneric.single.payload,
          'group:group-abc-123|message:msg-legacy',
        );
      },
    );

    test(
      'display eligibility leaves group_invite fallback on the intros route',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_invite',
            'groupId': 'group-abc-123',
            'title': 'Book Club',
          },
        );

        final result = await resolveBackgroundPushFallbackDisplayEligibility(
          message,
        );

        expect(result.shouldDisplay, isTrue);
        expect(
          buildBackgroundPushFallbackNotification(message).payload,
          'intros',
        );
      },
    );

    test(
      'foreground fallback helper suppresses group_message when display eligibility denies it',
      () async {
        final notificationService = FakeNotificationService();
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'message_id': 'msg-123',
          },
        );

        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: message,
          groupMessageDisplayEligibilityResolver: (_) async =>
              const GroupMessageNotificationDisplayEligibility.suppressed(
                'local_member_missing',
              ),
        );

        expect(shown, isFalse);
        expect(notificationService.shownGeneric, isEmpty);
      },
    );

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
        final fallback = buildBackgroundPushFallbackNotification(message);
        expect(fallback.title, backgroundPushDefaultTitle);
        expect(fallback.body, backgroundPushDefaultBody);
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

    test('preserves provided copy for a new-introduction intros fallback', () {
      const message = RemoteMessage(
        data: {
          'type': 'intros',
          'title': 'New Introduction',
          'body': 'Noor introduced Sarah to you',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'New Introduction');
      expect(fallback.body, 'Noor introduced Sarah to you');
      expect(fallback.payload, 'intros');
    });

    test(
      'preserves provided role-correct copy for an introducer mutual-accept intros fallback',
      () {
        const message = RemoteMessage(
          data: {
            'type': 'intros',
            'title': 'New Connection',
            'body':
                'Sarah accepted your intro to Lina. Lina and Sarah are now connected',
          },
        );

        final fallback = buildBackgroundPushFallbackNotification(message);
        expect(fallback.title, 'New Connection');
        expect(
          fallback.body,
          'Sarah accepted your intro to Lina. Lina and Sarah are now connected',
        );
        expect(fallback.payload, 'intros');
      },
    );

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

    test('shows fallback for group_invite type and routes to intros', () {
      const message = RemoteMessage(
        data: {
          'type': 'group_invite',
          'groupId': 'group-abc-123',
          'title': 'Book Club',
          'body': 'Alice invited you to Book Club',
        },
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'Book Club');
      expect(fallback.body, 'Alice invited you to Book Club');
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

    test(
      'GIRD-006 uses canonical group payload and message identity for fallback dedupe',
      () {
        const message = RemoteMessage(
          messageId: 'fcm-gird006-group-transport',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-group-image',
            'title': 'Team Chat',
            'body': 'Alice: Photo',
          },
        );

        final fallback = buildBackgroundPushFallbackNotification(message);

        expect(
          fallback.payload,
          'group:group-gird006|message:msg-gird006-group-image',
        );
        expect(fallback.title, backgroundPushDefaultTitle);
        expect(fallback.body, backgroundPushDefaultBody);
        expect(
          backgroundPushFallbackDedupeKey(message),
          'payload=group:group-gird006|message:msg-gird006-group-image|id=msg-gird006-group-image',
        );
      },
    );

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
