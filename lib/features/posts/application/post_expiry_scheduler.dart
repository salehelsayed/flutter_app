import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

/// Plan 407: a thought's card retires once the thought is gone or opened.
Future<void> retireSettledThoughtNotification({
  required String postId,
  required PostRepository postRepo,
  required Future<void> Function(String conversationKey) cancel,
}) async {
  final post = await postRepo.getPost(postId);
  if (post == null || (post.isIncoming && post.isFocused)) {
    await cancel(NotificationRouteTarget.post(postId).toPayload());
  }
}

/// One serialized foreground expiry owner. Reads independently enforce expiry;
/// this timer removes files/rows at the earliest remaining deadline.
class PostExpiryScheduler {
  PostExpiryScheduler({
    required this.postChanges,
    this.onPostChanged,
    required this.loadNextExpiry,
    required this.sweep,
    DateTime Function()? nowProvider,
  }) : now = nowProvider ?? DateTime.now;

  final Stream<String> postChanges;
  final Future<void> Function(String postId)? onPostChanged;
  final Set<String> _changedPostIds = <String>{};
  final Future<DateTime?> Function() loadNextExpiry;
  final Future<void> Function() sweep;
  final DateTime Function() now;
  StreamSubscription<String>? _subscription;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _foreground = true;
  bool _disposed = false;
  bool _refreshRequested = false;
  bool _sweepRequested = false;

  Future<void> start() {
    if (_disposed) return Future<void>.value();
    _subscription ??= postChanges.listen((postId) {
      _changedPostIds.add(postId);
      _requestRefresh();
    });
    return refresh(sweepNow: true);
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    _timer?.cancel();
    if (foreground) _requestRefresh(sweepNow: true);
  }

  void _requestRefresh({bool sweepNow = false}) {
    unawaited(
      refresh(sweepNow: sweepNow).catchError((Object error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'POST_EXPIRY_SWEEP_ERROR',
          details: {'errorType': error.runtimeType.toString()},
        );
        if (_foreground && !_disposed) {
          _timer?.cancel();
          _timer = Timer(
            const Duration(minutes: 1),
            () => _requestRefresh(sweepNow: true),
          );
        }
      }),
    );
  }

  Future<void> refresh({bool sweepNow = false}) {
    if (_disposed || !_foreground) return Future<void>.value();
    _refreshRequested = true;
    _sweepRequested = _sweepRequested || sweepNow;
    return _inFlight ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_refreshRequested && _foreground && !_disposed) {
        _refreshRequested = false;
        _timer?.cancel();
        for (final postId in _changedPostIds.toList()) {
          _changedPostIds.remove(postId);
          try {
            await onPostChanged?.call(postId);
          } catch (_) {
            _changedPostIds.add(postId);
            rethrow;
          }
          if (_disposed || !_foreground) break;
        }
        if (_disposed || !_foreground) continue;
        if (_sweepRequested) {
          _sweepRequested = false;
          await sweep();
        }
        if (_disposed || !_foreground) continue;
        final expiry = await loadNextExpiry();
        if (!_foreground || _disposed || expiry == null) continue;
        final delay = expiry.difference(now().toUtc());
        _timer = Timer(
          delay.isNegative ? Duration.zero : delay,
          () => _requestRefresh(sweepNow: true),
        );
      }
    } finally {
      _inFlight = null;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_subscription?.cancel());
  }
}

/// Bound at the existing production composition root, avoiding another app-root
/// owner. A suspended process catches up on its next resume/startup.
class PostExpiryLifecycleBinding with WidgetsBindingObserver {
  PostExpiryLifecycleBinding(this.scheduler);
  final PostExpiryScheduler scheduler;
  bool _disposed = false;

  void attach() {
    if (_disposed) return;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    scheduler.setForeground(
      state == null || state == AppLifecycleState.resumed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    scheduler.setForeground(state == AppLifecycleState.resumed);
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    scheduler.dispose();
  }
}
