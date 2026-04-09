/// Smoke test: simulates user tapping every notification type across all entry
/// points (remote push warm / terminated, local tap warm / initial launch) and
/// verifies the full prepare → drain → route pipeline fires correctly.
///
/// If any notification type silently breaks (wrong kind, lost peerId, skipped
/// drain, swallowed route) this test will catch it.
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';

import '../shared/fakes/fake_notification_service.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _NotificationSmokeHarness {
  final List<String> events = <String>[];
  final List<NotificationRouteTarget> routedTargets = <NotificationRouteTarget>[];
  int missingCalls = 0;

  void reset() {
    events.clear();
    routedTargets.clear();
    missingCalls = 0;
  }

  Future<void> prepare(NotificationRouteTarget target) async {
    events.add('prepare:${target.toPayload()}');

    final result = await prepareNotificationOpen(
      routeTarget: target,
      drainOfflineInbox: () async => events.add('drain:inbox'),
      drainGroupOfflineInboxForGroup: (groupId) async {
        events.add('drain:group:$groupId');
      },
    );

    expect(result.ok, isTrue, reason: result.error);
  }

  Future<void> route(NotificationRouteTarget target) async {
    events.add('route:${target.toPayload()}');
    routedTargets.add(target);
  }

  Future<void> missing() async {
    missingCalls += 1;
    events.add('missing');
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _NotificationSmokeHarness h;

  setUp(() {
    h = _NotificationSmokeHarness();
  });

  // =========================================================================
  // 1) Remote push tap (warm app) — every notification type
  // =========================================================================
  group('remote push tap (warm app)', () {
    test('new_message → conversation', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'new_message', 'sender_id': 'peer-alice'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, [
        'prepare:peer-alice',
        'drain:inbox',
        'route:peer-alice',
      ]);
      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.conversation);
      expect(h.routedTargets.single.peerId, 'peer-alice');
      expect(h.missingCalls, 0);
    });

    test('contact_request → contactRequest', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'contact_request', 'sender_id': 'peer-bob'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, [
        'prepare:contact_request:peer-bob',
        'drain:inbox',
        'route:contact_request:peer-bob',
      ]);
      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.contactRequest);
      expect(h.routedTargets.single.peerId, 'peer-bob');
    });

    test('intros → intros', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'intros'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, [
        'prepare:intros',
        'drain:inbox',
        'route:intros',
      ]);
      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.intros);
    });

    test('group_invite → intros', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'group_invite', 'groupId': 'grp-team'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, [
        'prepare:intros',
        'drain:inbox',
        'route:intros',
      ]);
      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.intros);
    });

    test('group_message → group', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'group_message', 'groupId': 'grp-team'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, [
        'prepare:group:grp-team',
        'drain:group:grp-team',
        'route:group:grp-team',
      ]);
      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.group);
      expect(h.routedTargets.single.groupId, 'grp-team');
    });

    test('post_create → post', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'post_create', 'post_id': 'p-42'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, [
        'prepare:post:p-42',
        // post kinds skip drainOfflineInbox
        'route:post:p-42',
      ]);
      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.post);
      expect(h.routedTargets.single.postId, 'p-42');
    });

    test('post_comment → postComment', () async {
      await routeRemoteNotificationOpen(
        data: const {
          'type': 'post_comment',
          'post_id': 'p-42',
          'comment_id': 'c-7',
        },
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, [
        'prepare:post_comment:p-42:c-7',
        'route:post_comment:p-42:c-7',
      ]);
      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.postComment);
      expect(h.routedTargets.single.postId, 'p-42');
      expect(h.routedTargets.single.commentId, 'c-7');
    });

    test('post_reaction → post', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'post_reaction', 'postId': 'p-99'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.post);
      expect(h.routedTargets.single.postId, 'p-99');
    });
  });

  // =========================================================================
  // 2) Remote push tap (terminated / cold start) — every notification type
  // =========================================================================
  group('remote push tap (terminated app)', () {
    test('new_message → conversation', () async {
      await routeInitialRemoteNotificationOpen(
        getInitialMessage: () async => const RemoteMessage(
          data: {'type': 'new_message', 'sender_id': 'peer-alice'},
        ),
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, [
        'prepare:peer-alice',
        'drain:inbox',
        'route:peer-alice',
      ]);
      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.conversation);
    });

    test('contact_request → contactRequest', () async {
      await routeInitialRemoteNotificationOpen(
        getInitialMessage: () async => const RemoteMessage(
          data: {'type': 'contact_request', 'sender_id': 'peer-bob'},
        ),
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.contactRequest);
      expect(h.routedTargets.single.peerId, 'peer-bob');
    });

    test('intros → intros', () async {
      await routeInitialRemoteNotificationOpen(
        getInitialMessage: () async => const RemoteMessage(
          data: {'type': 'intros'},
        ),
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.intros);
      expect(h.events, contains('drain:inbox'));
    });

    test('group_invite → intros', () async {
      await routeInitialRemoteNotificationOpen(
        getInitialMessage: () async => const RemoteMessage(
          data: {'type': 'group_invite', 'groupId': 'grp-team'},
        ),
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.intros);
      expect(h.events, contains('drain:inbox'));
    });

    test('group_message → group', () async {
      await routeInitialRemoteNotificationOpen(
        getInitialMessage: () async => const RemoteMessage(
          data: {'type': 'group_message', 'groupId': 'grp-team'},
        ),
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.group);
      expect(h.events, contains('drain:group:grp-team'));
    });

    test('post_create → post', () async {
      await routeInitialRemoteNotificationOpen(
        getInitialMessage: () async => const RemoteMessage(
          data: {'type': 'post_create', 'post_id': 'p-42'},
        ),
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.post);
      expect(h.routedTargets.single.postId, 'p-42');
    });

    test('post_comment → postComment', () async {
      await routeInitialRemoteNotificationOpen(
        getInitialMessage: () async => const RemoteMessage(
          data: {
            'type': 'post_comment',
            'post_id': 'p-42',
            'comment_id': 'c-7',
          },
        ),
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.postComment);
      expect(h.routedTargets.single.postId, 'p-42');
      expect(h.routedTargets.single.commentId, 'c-7');
    });

    test('no initial message → nothing fires', () async {
      await routeInitialRemoteNotificationOpen(
        getInitialMessage: () async => null,
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, isEmpty);
      expect(h.routedTargets, isEmpty);
      expect(h.missingCalls, 0);
    });
  });

  // =========================================================================
  // 3) Local notification tap (warm app) — every notification type
  // =========================================================================
  group('local notification tap (warm app)', () {
    test('conversation payload', () async {
      await routeAppRootLocalNotificationTap(
        payload: 'peer-alice',
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.events, [
        'prepare:peer-alice',
        'drain:inbox',
        'route:peer-alice',
      ]);
      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.conversation);
    });

    test('contact_request payload', () async {
      await routeAppRootLocalNotificationTap(
        payload: 'contact_request:peer-bob',
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.contactRequest);
      expect(h.routedTargets.single.peerId, 'peer-bob');
      expect(h.events, contains('drain:inbox'));
    });

    test('intros payload', () async {
      await routeAppRootLocalNotificationTap(
        payload: 'intros',
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.intros);
      expect(h.events, contains('drain:inbox'));
    });

    test('group payload', () async {
      await routeAppRootLocalNotificationTap(
        payload: 'group:grp-team',
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.group);
      expect(h.routedTargets.single.groupId, 'grp-team');
      expect(h.events, contains('drain:group:grp-team'));
    });

    test('post payload', () async {
      await routeAppRootLocalNotificationTap(
        payload: 'post:p-42',
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.post);
      expect(h.routedTargets.single.postId, 'p-42');
      // Post skips drain
      expect(h.events, isNot(contains('drain:inbox')));
    });

    test('post_comment payload', () async {
      await routeAppRootLocalNotificationTap(
        payload: 'post_comment:p-42:c-7',
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.postComment);
      expect(h.routedTargets.single.postId, 'p-42');
      expect(h.routedTargets.single.commentId, 'c-7');
    });

    test('post_comment with colon in commentId preserves full id', () async {
      await routeAppRootLocalNotificationTap(
        payload: 'post_comment:p-42:c:special:7',
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.postComment);
      expect(h.routedTargets.single.postId, 'p-42');
      expect(h.routedTargets.single.commentId, 'c:special:7');
    });
  });

  // =========================================================================
  // 4) Local notification initial launch (terminated app) — every type
  // =========================================================================
  group('local notification initial launch (terminated app)', () {
    late FakeNotificationService notificationService;

    setUp(() {
      notificationService = FakeNotificationService();
    });

    Future<void> simulateLaunchFromLocal({
      required String title,
      required String body,
      required NotificationRouteTarget target,
    }) async {
      await notificationService.showNotification(
        title: title,
        body: body,
        payload: target.toPayload(),
      );
      notificationService.initialPayload =
          notificationService.shownGeneric.last.payload;
    }

    test('conversation initial launch', () async {
      await simulateLaunchFromLocal(
        title: 'Alice',
        body: 'Hey!',
        target: const NotificationRouteTarget.conversation('peer-alice'),
      );

      await routeAppRootInitialLocalNotificationOpen(
        consumeInitialPayload: notificationService.consumeInitialPayload,
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.conversation);
      expect(h.routedTargets.single.peerId, 'peer-alice');
      expect(h.events, contains('drain:inbox'));
    });

    test('contact_request initial launch', () async {
      await simulateLaunchFromLocal(
        title: 'New Contact Request',
        body: 'Bob wants to connect',
        target: const NotificationRouteTarget.contactRequest('peer-bob'),
      );

      await routeAppRootInitialLocalNotificationOpen(
        consumeInitialPayload: notificationService.consumeInitialPayload,
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.contactRequest);
      expect(h.routedTargets.single.peerId, 'peer-bob');
    });

    test('intros initial launch', () async {
      await simulateLaunchFromLocal(
        title: 'Introductions',
        body: 'You have new introductions',
        target: const NotificationRouteTarget.intros(),
      );

      await routeAppRootInitialLocalNotificationOpen(
        consumeInitialPayload: notificationService.consumeInitialPayload,
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.intros);
    });

    test('group initial launch', () async {
      await simulateLaunchFromLocal(
        title: 'Team Chat',
        body: 'New message in group',
        target: const NotificationRouteTarget.group('grp-team'),
      );

      await routeAppRootInitialLocalNotificationOpen(
        consumeInitialPayload: notificationService.consumeInitialPayload,
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.group);
      expect(h.routedTargets.single.groupId, 'grp-team');
      expect(h.events, contains('drain:group:grp-team'));
    });

    test('post initial launch', () async {
      await simulateLaunchFromLocal(
        title: 'Alice posted',
        body: 'Check it out',
        target: const NotificationRouteTarget.post('p-42'),
      );

      await routeAppRootInitialLocalNotificationOpen(
        consumeInitialPayload: notificationService.consumeInitialPayload,
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.post);
      expect(h.routedTargets.single.postId, 'p-42');
    });

    test('post_comment initial launch', () async {
      await simulateLaunchFromLocal(
        title: 'Bob commented',
        body: 'Nice!',
        target: const NotificationRouteTarget.postComment(
          postId: 'p-42',
          commentId: 'c-7',
        ),
      );

      await routeAppRootInitialLocalNotificationOpen(
        consumeInitialPayload: notificationService.consumeInitialPayload,
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.postComment);
      expect(h.routedTargets.single.postId, 'p-42');
      expect(h.routedTargets.single.commentId, 'c-7');
    });

    test('no initial payload → nothing fires', () async {
      await routeAppRootInitialLocalNotificationOpen(
        consumeInitialPayload: notificationService.consumeInitialPayload,
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.events, isEmpty);
      expect(h.routedTargets, isEmpty);
    });

    test('initial payload consumed only once', () async {
      await simulateLaunchFromLocal(
        title: 'Alice',
        body: 'Hey!',
        target: const NotificationRouteTarget.conversation('peer-alice'),
      );

      // First consumption
      await routeAppRootInitialLocalNotificationOpen(
        consumeInitialPayload: notificationService.consumeInitialPayload,
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );
      expect(h.routedTargets, hasLength(1));

      // Second consumption — should be a no-op
      h.reset();
      await routeAppRootInitialLocalNotificationOpen(
        consumeInitialPayload: notificationService.consumeInitialPayload,
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );
      expect(h.routedTargets, isEmpty);
    });
  });

  // =========================================================================
  // 5) Payload round-trip integrity (toPayload → fromPayload)
  // =========================================================================
  group('payload round-trip integrity', () {
    final cases = <(String, NotificationRouteTarget, NotificationRouteTargetKind)>[
      ('conversation', const NotificationRouteTarget.conversation('peer-abc'), NotificationRouteTargetKind.conversation),
      ('contactRequest', const NotificationRouteTarget.contactRequest('peer-def'), NotificationRouteTargetKind.contactRequest),
      ('group', const NotificationRouteTarget.group('grp-xyz'), NotificationRouteTargetKind.group),
      ('intros', const NotificationRouteTarget.intros(), NotificationRouteTargetKind.intros),
      ('post', const NotificationRouteTarget.post('p-99'), NotificationRouteTargetKind.post),
      ('postComment', const NotificationRouteTarget.postComment(postId: 'p-99', commentId: 'c-3'), NotificationRouteTargetKind.postComment),
    ];

    for (final (label, target, expectedKind) in cases) {
      test('$label round-trips', () {
        final payload = target.toPayload();
        final parsed = NotificationRouteTarget.fromPayload(payload);
        expect(parsed, isNotNull, reason: '$label payload "$payload" should parse');
        expect(parsed!.kind, expectedKind);
        expect(parsed.peerId, target.peerId);
        expect(parsed.groupId, target.groupId);
        expect(parsed.postId, target.postId);
        expect(parsed.commentId, target.commentId);
      });
    }
  });

  // =========================================================================
  // 6) Background push fallback → local show → tap → route (full round-trip)
  // =========================================================================
  group('background push fallback → show → tap → route', () {
    late FakeNotificationService notificationService;

    setUp(() {
      notificationService = FakeNotificationService();
    });

    Future<void> simulateBackgroundPushThenTap({
      required Map<String, dynamic> pushData,
      required NotificationRouteTargetKind expectedKind,
    }) async {
      // 1. Background push arrives (data-only)
      final message = RemoteMessage(data: pushData);
      expect(
        shouldShowBackgroundPushFallbackNotification(message),
        isTrue,
        reason: 'should show fallback for $pushData',
      );

      // 2. Build fallback and show it locally
      final fallback = buildBackgroundPushFallbackNotification(message);
      await notificationService.showNotification(
        title: fallback.title,
        body: fallback.body,
        payload: fallback.payload,
      );

      // 3. User taps it (warm app)
      final tappedPayload = notificationService.shownGeneric.last.payload!;
      await routeAppRootLocalNotificationTap(
        payload: tappedPayload,
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      // 4. Verify the right target arrived
      expect(h.routedTargets, hasLength(1));
      expect(h.routedTargets.single.kind, expectedKind);
    }

    test('new_message push → fallback → tap → conversation route', () async {
      await simulateBackgroundPushThenTap(
        pushData: const {'type': 'new_message', 'sender_id': 'peer-alice'},
        expectedKind: NotificationRouteTargetKind.conversation,
      );
      expect(h.routedTargets.single.peerId, 'peer-alice');
      expect(h.events, contains('drain:inbox'));
    });

    test('contact_request push → fallback → tap → contactRequest route', () async {
      await simulateBackgroundPushThenTap(
        pushData: const {'type': 'contact_request', 'sender_id': 'peer-bob'},
        expectedKind: NotificationRouteTargetKind.contactRequest,
      );
      expect(h.routedTargets.single.peerId, 'peer-bob');
      expect(h.events, contains('drain:inbox'));
    });

    test('intros push → fallback → tap → intros route', () async {
      await simulateBackgroundPushThenTap(
        pushData: const {'type': 'intros'},
        expectedKind: NotificationRouteTargetKind.intros,
      );
      expect(h.events, contains('drain:inbox'));
    });

    test('group_invite push → fallback → tap → intros route', () async {
      await simulateBackgroundPushThenTap(
        pushData: const {'type': 'group_invite', 'groupId': 'grp-team'},
        expectedKind: NotificationRouteTargetKind.intros,
      );
      expect(h.events, contains('drain:inbox'));
    });

    test('group_message push → fallback → tap → group route', () async {
      await simulateBackgroundPushThenTap(
        pushData: const {'type': 'group_message', 'groupId': 'grp-team'},
        expectedKind: NotificationRouteTargetKind.group,
      );
      expect(h.routedTargets.single.groupId, 'grp-team');
      expect(h.events, contains('drain:group:grp-team'));
    });

    test('post_create push → fallback → tap → post route', () async {
      await simulateBackgroundPushThenTap(
        pushData: const {'type': 'post_create', 'post_id': 'p-42'},
        expectedKind: NotificationRouteTargetKind.post,
      );
      expect(h.routedTargets.single.postId, 'p-42');
    });

    test('post_comment push → fallback → tap → postComment route', () async {
      await simulateBackgroundPushThenTap(
        pushData: const {
          'type': 'post_comment',
          'post_id': 'p-42',
          'comment_id': 'c-7',
        },
        expectedKind: NotificationRouteTargetKind.postComment,
      );
      expect(h.routedTargets.single.postId, 'p-42');
      expect(h.routedTargets.single.commentId, 'c-7');
    });
  });

  // =========================================================================
  // 7) Edge cases: malformed / missing data
  // =========================================================================
  group('edge cases — malformed or missing data', () {
    test('unknown push type → missing handler fires', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'unknown_future_type'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, ['missing']);
      expect(h.routedTargets, isEmpty);
      expect(h.missingCalls, 1);
    });

    test('new_message without sender_id → missing', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'new_message'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.missingCalls, 1);
      expect(h.routedTargets, isEmpty);
    });

    test('contact_request without any peer field → missing', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'contact_request'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.missingCalls, 1);
    });

    test('group_message without groupId → missing', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'group_message'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.missingCalls, 1);
    });

    test('post_comment without comment_id → missing', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'post_comment', 'post_id': 'p-42'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.missingCalls, 1);
    });

    test('whitespace-only sender_id → missing', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'new_message', 'sender_id': '   '},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.missingCalls, 1);
    });

    test('empty local payload → nothing fires', () async {
      await routeAppRootLocalNotificationTap(
        payload: '',
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.events, isEmpty);
    });

    test('whitespace-only local payload → nothing fires', () async {
      await routeAppRootLocalNotificationTap(
        payload: '   ',
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.events, isEmpty);
    });

    test('contact_request: with empty peerId → nothing fires', () async {
      await routeAppRootLocalNotificationTap(
        payload: 'contact_request:',
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.events, isEmpty);
    });

    test('group: with empty groupId → nothing fires', () async {
      await routeAppRootLocalNotificationTap(
        payload: 'group:',
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
      );

      expect(h.events, isEmpty);
    });
  });

  // =========================================================================
  // 8) Legacy field fallbacks
  // =========================================================================
  group('legacy field fallbacks', () {
    test('new_message with "from" instead of "sender_id"', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'new_message', 'from': 'peer-legacy'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.conversation);
      expect(h.routedTargets.single.peerId, 'peer-legacy');
    });

    test('sender_id takes precedence over from', () async {
      await routeRemoteNotificationOpen(
        data: const {
          'type': 'new_message',
          'sender_id': 'peer-new',
          'from': 'peer-old',
        },
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.peerId, 'peer-new');
    });

    test('contact_request with peer_id fallback', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'contact_request', 'peer_id': 'peer-alt'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.contactRequest);
      expect(h.routedTargets.single.peerId, 'peer-alt');
    });

    test('contact_request with peerId fallback', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'contact_request', 'peerId': 'peer-camel'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.peerId, 'peer-camel');
    });

    test('contact_request with ns fallback', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'contact_request', 'ns': 'peer-ns'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.peerId, 'peer-ns');
    });

    test('post_create with postId (camelCase) fallback', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'post_create', 'postId': 'p-camel'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.post);
      expect(h.routedTargets.single.postId, 'p-camel');
    });

    test('generic payload key as fallback for unknown type', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'future_type', 'payload': 'peer-generic'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      // Falls through to fromPayload('peer-generic') → conversation
      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.conversation);
      expect(h.routedTargets.single.peerId, 'peer-generic');
    });

    test('generic route key as fallback for unknown type', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'future_type', 'route': 'group:grp-fallback'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.routedTargets.single.kind, NotificationRouteTargetKind.group);
      expect(h.routedTargets.single.groupId, 'grp-fallback');
    });
  });

  // =========================================================================
  // 9) Drain correctness per notification kind
  // =========================================================================
  group('drain correctness per notification kind', () {
    test('conversation drains 1:1 inbox, not group', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'new_message', 'sender_id': 'peer-x'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, contains('drain:inbox'));
      expect(h.events, isNot(anyElement(startsWith('drain:group:'))));
    });

    test('contactRequest drains 1:1 inbox, not group', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'contact_request', 'sender_id': 'peer-x'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, contains('drain:inbox'));
      expect(h.events, isNot(anyElement(startsWith('drain:group:'))));
    });

    test('intros drains 1:1 inbox, not group', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'intros'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, contains('drain:inbox'));
      expect(h.events, isNot(anyElement(startsWith('drain:group:'))));
    });

    test('group_invite drains 1:1 inbox, not group', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'group_invite', 'groupId': 'grp-x'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, contains('drain:inbox'));
      expect(h.events, isNot(anyElement(startsWith('drain:group:'))));
    });

    test('group drains targeted group inbox, not 1:1', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'group_message', 'groupId': 'grp-x'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, contains('drain:group:grp-x'));
      expect(h.events, isNot(contains('drain:inbox')));
    });

    test('post skips all drains', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'post_create', 'post_id': 'p-1'},
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, isNot(contains('drain:inbox')));
      expect(h.events, isNot(anyElement(startsWith('drain:group:'))));
    });

    test('postComment skips all drains', () async {
      await routeRemoteNotificationOpen(
        data: const {
          'type': 'post_comment',
          'post_id': 'p-1',
          'comment_id': 'c-1',
        },
        onBeforeRouteTarget: h.prepare,
        onRouteTarget: h.route,
        onMissingRouteTarget: h.missing,
      );

      expect(h.events, isNot(contains('drain:inbox')));
      expect(h.events, isNot(anyElement(startsWith('drain:group:'))));
    });
  });

  // =========================================================================
  // 10) Sequencing: prepare always fires before route
  // =========================================================================
  group('sequencing guarantees', () {
    test('prepare fires before route on every notification kind', () async {
      final kinds = <Map<String, dynamic>>[
        {'type': 'new_message', 'sender_id': 'p-1'},
        {'type': 'contact_request', 'sender_id': 'p-2'},
        {'type': 'intros'},
        {'type': 'group_invite', 'groupId': 'g-1'},
        {'type': 'group_message', 'groupId': 'g-1'},
        {'type': 'post_create', 'post_id': 'post-1'},
        {'type': 'post_comment', 'post_id': 'post-1', 'comment_id': 'c-1'},
      ];

      for (final data in kinds) {
        h.reset();
        await routeRemoteNotificationOpen(
          data: data,
          onBeforeRouteTarget: h.prepare,
          onRouteTarget: h.route,
          onMissingRouteTarget: h.missing,
        );

        final prepareIdx = h.events.indexWhere((e) => e.startsWith('prepare:'));
        final routeIdx = h.events.indexWhere((e) => e.startsWith('route:'));
        expect(
          prepareIdx,
          lessThan(routeIdx),
          reason: 'prepare must fire before route for ${data['type']}',
        );
      }
    });
  });
}
