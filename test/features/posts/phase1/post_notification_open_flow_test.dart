import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/application/post_notification_open_coordinator.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  group('post notification open flow', () {
    late _CoordinatorHarness harness;

    setUp(() {
      harness = _CoordinatorHarness();
    });

    tearDown(() {
      harness.dispose();
    });

    test('local notification tap stores a pending target before opening Posts', () async {
      await routeNotificationPayload(
        payload: 'post:post-local',
        onRouteTarget: harness.handleRouteTarget,
      );

      expect(harness.pendingTargetStore.target?.postId, 'post-local');
      expect(harness.appShellController.activeTab, AppShellTab.feed);
      expect(harness.revealPostsSurfaceCalls, 0);
      expect(harness.drainOfflineInboxCalls, 1);
    });

    test('post-comment tap preserves the comment target before opening Posts', () async {
      await routeNotificationPayload(
        payload: 'post_comment:post-local:comment-1',
        onRouteTarget: harness.handleRouteTarget,
      );

      expect(harness.pendingTargetStore.target?.postId, 'post-local');
      expect(harness.pendingTargetStore.target?.commentId, 'comment-1');
      expect(harness.appShellController.activeTab, AppShellTab.feed);
      expect(harness.revealPostsSurfaceCalls, 0);
      expect(harness.drainOfflineInboxCalls, 1);
    });

    test('onMessageOpenedApp routes through the shared pending target flow', () async {
      await routeRemoteNotificationOpen(
        data: const <String, dynamic>{
          'type': 'post_create',
          'post_id': 'post-opened-app',
        },
        onRouteTarget: harness.handleRouteTarget,
        onMissingRouteTarget: harness.drainOfflineInbox,
      );

      expect(harness.pendingTargetStore.target?.postId, 'post-opened-app');
      expect(harness.appShellController.activeTab, AppShellTab.feed);
      expect(harness.drainOfflineInboxCalls, 1);
    });

    test('post_comment remote opens route through the shared pending target flow', () async {
      await routeRemoteNotificationOpen(
        data: const <String, dynamic>{
          'type': 'post_comment',
          'post_id': 'post-opened-app',
          'comment_id': 'comment-1',
        },
        onRouteTarget: harness.handleRouteTarget,
        onMissingRouteTarget: harness.drainOfflineInbox,
      );

      expect(harness.pendingTargetStore.target?.postId, 'post-opened-app');
      expect(harness.pendingTargetStore.target?.commentId, 'comment-1');
      expect(harness.appShellController.activeTab, AppShellTab.feed);
      expect(harness.drainOfflineInboxCalls, 1);
    });

    test('getInitialMessage routes through the shared pending target flow', () async {
      await routeInitialRemoteNotificationOpen(
        getInitialMessage: () async => const RemoteMessage(
          data: <String, dynamic>{
            'type': 'post_create',
            'post_id': 'post-initial-remote',
          },
        ),
        onRouteTarget: harness.handleRouteTarget,
        onMissingRouteTarget: harness.drainOfflineInbox,
      );

      expect(
        harness.pendingTargetStore.target?.postId,
        'post-initial-remote',
      );
      expect(harness.appShellController.activeTab, AppShellTab.feed);
      expect(harness.drainOfflineInboxCalls, 1);
    });

    test('terminated local fallback launch routes through the shared pending target flow', () async {
      await routeInitialLocalNotificationOpen(
        consumeInitialPayload: () async => 'post:post-initial-local',
        onRouteTarget: harness.handleRouteTarget,
      );

      expect(
        harness.pendingTargetStore.target?.postId,
        'post-initial-local',
      );
      expect(harness.appShellController.activeTab, AppShellTab.feed);
      expect(harness.drainOfflineInboxCalls, 1);
    });

    test('repo observation opens Posts and clears the fallback status', () async {
      await routeNotificationPayload(
        payload: 'post:post-observed',
        onRouteTarget: harness.handleRouteTarget,
      );

      await harness.postRepository.savePost(_post(id: 'post-observed'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(harness.appShellController.activeTab, AppShellTab.feed);
      expect(harness.revealPostsSurfaceCalls, 1);
      expect(harness.pendingTargetStore.statusMessage, isNull);
    });

    test('timeout opens Posts with the approved fallback message', () async {
      final timeoutHarness = _CoordinatorHarness(
        waitBudget: const Duration(milliseconds: 20),
        expiryBudget: const Duration(milliseconds: 120),
      );
      addTearDown(timeoutHarness.dispose);

      await routeNotificationPayload(
        payload: 'post:post-timeout',
        onRouteTarget: timeoutHarness.handleRouteTarget,
      );

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        timeoutHarness.pendingTargetStore.statusMessage,
        PostNotificationOpenCoordinator.loadingFallbackMessage,
      );
      expect(timeoutHarness.appShellController.activeTab, AppShellTab.feed);
      expect(timeoutHarness.revealPostsSurfaceCalls, 1);
    });

    test('pending target expires after the approved budget if the post never arrives', () async {
      final expiryHarness = _CoordinatorHarness(
        waitBudget: const Duration(milliseconds: 20),
        expiryBudget: const Duration(milliseconds: 60),
      );
      addTearDown(expiryHarness.dispose);

      await routeNotificationPayload(
        payload: 'post:post-expire',
        onRouteTarget: expiryHarness.handleRouteTarget,
      );

      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(expiryHarness.pendingTargetStore.target, isNull);
      expect(expiryHarness.pendingTargetStore.statusMessage, isNull);
    });

    test('missing remote route target falls back to inbox drain without setting a pending post target', () async {
      await routeRemoteNotificationOpen(
        data: const <String, dynamic>{
          'type': 'post_create',
        },
        onRouteTarget: harness.handleRouteTarget,
        onMissingRouteTarget: harness.drainOfflineInbox,
      );

      expect(harness.pendingTargetStore.target, isNull);
      expect(harness.drainOfflineInboxCalls, 1);
      expect(harness.revealPostsSurfaceCalls, 0);
    });
  });
}

class _CoordinatorHarness {
  final PendingPostTargetStore pendingTargetStore = PendingPostTargetStore();
  final AppShellController appShellController = AppShellController();
  final InMemoryPostRepository postRepository = InMemoryPostRepository();

  late final PostNotificationOpenCoordinator coordinator;
  int revealPostsSurfaceCalls = 0;
  int drainOfflineInboxCalls = 0;

  _CoordinatorHarness({
    Duration waitBudget = const Duration(seconds: 5),
    Duration expiryBudget = const Duration(seconds: 30),
  }) {
    coordinator = PostNotificationOpenCoordinator(
      pendingTargetStore: pendingTargetStore,
      postRepository: postRepository,
      appShellController: appShellController,
      revealPostsSurface: () {
        revealPostsSurfaceCalls += 1;
      },
      waitBudget: waitBudget,
      expiryBudget: expiryBudget,
    );
  }

  Future<void> handleRouteTarget(NotificationRouteTarget routeTarget) {
    return coordinator.handleRouteTarget(
      routeTarget: routeTarget,
      drainOfflineInbox: drainOfflineInbox,
    );
  }

  Future<void> drainOfflineInbox() async {
    drainOfflineInboxCalls += 1;
  }

  void dispose() {
    coordinator.dispose();
    postRepository.dispose();
  }
}

PostModel _post({required String id}) {
  return PostModel(
    id: id,
    eventId: 'evt-$id',
    senderPeerId: 'peer-bob',
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: 'Hello',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
  );
}
