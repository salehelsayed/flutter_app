import 'dart:async';

import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/models/post_route_target.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class PostNotificationOpenCoordinator {
  static const String loadingFallbackMessage = 'Finishing catch-up...';

  final PendingPostTargetStore pendingTargetStore;
  final PostRepository postRepository;
  final AppShellController appShellController;
  final void Function() revealPostsSurface;
  final Duration waitBudget;
  final Duration expiryBudget;

  StreamSubscription<String>? _postChangesSubscription;
  Timer? _fallbackTimer;
  Timer? _expiryTimer;
  String? _revealedPostId;

  PostNotificationOpenCoordinator({
    required this.pendingTargetStore,
    required this.postRepository,
    required this.appShellController,
    required this.revealPostsSurface,
    this.waitBudget = const Duration(seconds: 5),
    this.expiryBudget = const Duration(seconds: 30),
  }) {
    _postChangesSubscription = postRepository.postChanges.listen((_) {
      unawaited(_openPostsSurfaceWhenObserved());
    });
    pendingTargetStore.addListener(_handlePendingTargetMutation);
  }

  Future<void> handleRouteTarget({
    required NotificationRouteTarget routeTarget,
    required Future<void> Function() drainOfflineInbox,
  }) async {
    if ((routeTarget.kind != NotificationRouteTargetKind.post &&
            routeTarget.kind != NotificationRouteTargetKind.postComment) ||
        routeTarget.postId == null) {
      return;
    }

    final postId = routeTarget.postId!;
    pendingTargetStore.setTarget(
      PostRouteTarget(postId: postId, commentId: routeTarget.commentId),
    );
    _revealedPostId = null;
    _armTimers(postId);

    unawaited(drainOfflineInbox());
    await _openPostsSurfaceWhenObserved();
  }

  void dispose() {
    pendingTargetStore.removeListener(_handlePendingTargetMutation);
    _postChangesSubscription?.cancel();
    _cancelTimers();
  }

  void _handlePendingTargetMutation() {
    final target = pendingTargetStore.target;
    if (target == null) {
      _cancelTimers();
      _revealedPostId = null;
      return;
    }
    if (_revealedPostId != null && _revealedPostId != target.postId) {
      _revealedPostId = null;
    }
  }

  void _armTimers(String postId) {
    _cancelTimers();
    _fallbackTimer = Timer(waitBudget, () {
      final target = pendingTargetStore.target;
      if (target == null || target.postId != postId) {
        return;
      }
      pendingTargetStore.showStatus(loadingFallbackMessage);
      _revealPosts(postId);
    });
    _expiryTimer = Timer(expiryBudget, () {
      final target = pendingTargetStore.target;
      if (target == null || target.postId != postId) {
        return;
      }
      pendingTargetStore.clear();
    });
  }

  void _cancelTimers() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }

  Future<void> _openPostsSurfaceWhenObserved() async {
    final target = pendingTargetStore.target;
    if (target == null) {
      return;
    }

    final post = await postRepository.getPost(target.postId);
    if (post == null) {
      return;
    }

    _cancelTimers();
    pendingTargetStore.showStatus(null);
    _revealPosts(target.postId);
  }

  void _revealPosts(String postId) {
    if (_revealedPostId == postId) {
      return;
    }
    _revealedPostId = postId;
    // Posts tab hidden for TestFlight — navigate to feed instead.
    appShellController.switchTo(AppShellTab.feed);
    revealPostsSurface();
  }
}
