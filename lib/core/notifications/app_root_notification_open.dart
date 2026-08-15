import 'dart:async';

import 'package:flutter_app/core/notifications/app_visibility_route_binding.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';

typedef NotificationOpenSideEffect = Future<void> Function();

/// One parsed notification open and the immutable time at which its validated
/// route began. Keeping these values together prevents overlapping opens from
/// borrowing each other's timing context.
class NotificationOpenRouteContext {
  const NotificationOpenRouteContext._({
    required this.routeTarget,
    required this.tappedAt,
    required this.ordinal,
  });

  final NotificationRouteTarget routeTarget;
  final DateTime tappedAt;
  final int ordinal;
}

enum NotificationOpenRouteDisposition { routed, deferred, superseded }

enum NotificationOpenRouteCompletionStatus { routed, superseded, failed }

class NotificationOpenRouteCompletion {
  const NotificationOpenRouteCompletion._({
    required this.status,
    this.error,
    this.stackTrace,
  });

  const NotificationOpenRouteCompletion.routed()
    : this._(status: NotificationOpenRouteCompletionStatus.routed);

  const NotificationOpenRouteCompletion.superseded()
    : this._(status: NotificationOpenRouteCompletionStatus.superseded);

  NotificationOpenRouteCompletion.failed(Object error, StackTrace stackTrace)
    : this._(
        status: NotificationOpenRouteCompletionStatus.failed,
        error: error,
        stackTrace: stackTrace,
      );

  final NotificationOpenRouteCompletionStatus status;
  final Object? error;
  final StackTrace? stackTrace;

  bool get routed => status == NotificationOpenRouteCompletionStatus.routed;
}

class NotificationOpenRouteDispatch {
  const NotificationOpenRouteDispatch({
    required this.disposition,
    required this.completion,
  });

  final NotificationOpenRouteDisposition disposition;
  final Future<NotificationOpenRouteCompletion> completion;
}

enum NotificationOpenDeferredAttemptStatus {
  none,
  routed,
  retained,
  retry,
  failed,
  superseded,
}

class NotificationOpenDeferredAttemptResult {
  const NotificationOpenDeferredAttemptResult._({
    required this.status,
    this.context,
    this.attempt = 0,
    this.error,
    this.stackTrace,
  });

  const NotificationOpenDeferredAttemptResult.none()
    : this._(status: NotificationOpenDeferredAttemptStatus.none);

  final NotificationOpenDeferredAttemptStatus status;
  final NotificationOpenRouteContext? context;
  final int attempt;
  final Object? error;
  final StackTrace? stackTrace;
}

typedef NotificationOpenRetryTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// Owns the single bounded-retry timer for deferred notification routing.
///
/// The owner ordinal prevents an older attempt that completes late from
/// cancelling a newer open's retry. A newer owner may replace an older timer;
/// the same or an older owner cannot displace the timer already scheduled.
class NotificationOpenDeferredRetryScheduler {
  NotificationOpenDeferredRetryScheduler({
    NotificationOpenRetryTimerFactory? createTimer,
  }) : _createTimer = createTimer ?? _defaultCreateTimer;

  final NotificationOpenRetryTimerFactory _createTimer;
  Timer? _timer;
  int? _ownerOrdinal;

  int? get ownerOrdinal => _ownerOrdinal;
  bool get isScheduled => _timer != null;

  bool schedule({
    required int ownerOrdinal,
    required Duration delay,
    required void Function() onRetry,
  }) {
    final currentOwner = _ownerOrdinal;
    if (currentOwner != null && currentOwner >= ownerOrdinal) {
      return false;
    }

    _timer?.cancel();
    _timer = null;
    _ownerOrdinal = ownerOrdinal;
    late final Timer timer;
    timer = _createTimer(delay, () {
      if (!identical(_timer, timer) || _ownerOrdinal != ownerOrdinal) {
        return;
      }
      _timer = null;
      _ownerOrdinal = null;
      onRetry();
    });
    _timer = timer;
    return true;
  }

  bool cancelIfOwnedBy(int ownerOrdinal) {
    if (_ownerOrdinal != ownerOrdinal) {
      return false;
    }
    _timer?.cancel();
    _timer = null;
    _ownerOrdinal = null;
    return true;
  }

  void cancelAll() {
    _timer?.cancel();
    _timer = null;
    _ownerOrdinal = null;
  }

  static Timer _defaultCreateTimer(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}

/// Owns validated-open ordering and the startup-deferred route slot.
///
/// Ordinals are assigned before preparation starts. Dispatch and defer both
/// reject lower ordinals, so reverse async-preparation completion cannot make
/// an older tap replace a newer one. A deferred entry remains owned while it is
/// attempted and is cleared with an identity/CAS check only after success (or
/// a bounded terminal failure). Completion failures are values, not unhandled
/// error futures.
class NotificationOpenRouteCoordinator {
  int _nextOrdinal = 0;
  int _latestDispatchOrdinal = 0;
  NotificationOpenRouteContext? _active;
  _DeferredNotificationOpenRoute? _deferred;

  NotificationOpenRouteContext? get active => _active;
  NotificationOpenRouteContext? get deferred => _deferred?.context;
  DateTime? get activeTappedAt => _active?.tappedAt;
  int get latestDispatchOrdinal => _latestDispatchOrdinal;

  NotificationOpenRouteContext createContext({
    required NotificationRouteTarget routeTarget,
    required DateTime tappedAt,
  }) {
    return NotificationOpenRouteContext._(
      routeTarget: routeTarget,
      tappedAt: tappedAt,
      ordinal: ++_nextOrdinal,
    );
  }

  bool isLatest(NotificationOpenRouteContext context) {
    return context.ordinal >= _latestDispatchOrdinal;
  }

  bool defer(NotificationOpenRouteContext context) {
    if (context.ordinal < _latestDispatchOrdinal) {
      return false;
    }

    final current = _deferred;
    if (current != null) {
      if (current.context.ordinal > context.ordinal) {
        return false;
      }
      if (identical(current.context, context)) {
        return true;
      }
      _deferred = null;
      current.complete(const NotificationOpenRouteCompletion.superseded());
    }

    _deferred = _DeferredNotificationOpenRoute(context);
    return true;
  }

  void cancelDeferred() {
    final pending = _deferred;
    if (pending == null) return;
    _deferred = null;
    pending.complete(const NotificationOpenRouteCompletion.superseded());
  }

  Future<NotificationOpenRouteDispatch> dispatch({
    required NotificationOpenRouteContext context,
    required Future<NotificationOpenRouteDisposition> Function(
      NotificationOpenRouteContext context,
    )
    onRouteContext,
  }) async {
    if (context.ordinal < _latestDispatchOrdinal) {
      return NotificationOpenRouteDispatch(
        disposition: NotificationOpenRouteDisposition.superseded,
        completion: Future<NotificationOpenRouteCompletion>.value(
          const NotificationOpenRouteCompletion.superseded(),
        ),
      );
    }
    if (context.ordinal > _latestDispatchOrdinal) {
      _latestDispatchOrdinal = context.ordinal;
      _supersedeDeferredOlderThan(context.ordinal);
    }

    _active = context;
    try {
      final disposition = await onRouteContext(context);
      if (disposition == NotificationOpenRouteDisposition.deferred) {
        final pending = _deferred;
        if (pending != null && identical(pending.context, context)) {
          return NotificationOpenRouteDispatch(
            disposition: disposition,
            completion: pending.completer.future,
          );
        }
        return NotificationOpenRouteDispatch(
          disposition: NotificationOpenRouteDisposition.superseded,
          completion: Future<NotificationOpenRouteCompletion>.value(
            const NotificationOpenRouteCompletion.superseded(),
          ),
        );
      }
      final completion = disposition == NotificationOpenRouteDisposition.routed
          ? const NotificationOpenRouteCompletion.routed()
          : const NotificationOpenRouteCompletion.superseded();
      return NotificationOpenRouteDispatch(
        disposition: disposition,
        completion: Future<NotificationOpenRouteCompletion>.value(completion),
      );
    } finally {
      if (identical(_active, context)) {
        _active = null;
      }
    }
  }

  Future<NotificationOpenDeferredAttemptResult> runDeferredAttempt({
    required int maxAttempts,
    required Future<NotificationOpenRouteDisposition> Function(
      NotificationOpenRouteContext context,
    )
    onRouteContext,
  }) {
    assert(maxAttempts > 0);
    final pending = _deferred;
    if (pending == null) {
      return Future<NotificationOpenDeferredAttemptResult>.value(
        const NotificationOpenDeferredAttemptResult.none(),
      );
    }

    // More than one lifecycle/home-ready signal can request a flush in the
    // same frame. Join the attempt already owned by this exact deferred entry
    // instead of invoking a second navigation side effect or consuming another
    // retry. Installing the shared future before starting the handler also
    // makes a synchronous/re-entrant flush join safely.
    final inFlightAttempt = pending.inFlightAttempt;
    if (inFlightAttempt != null) {
      return inFlightAttempt;
    }
    final completer = Completer<NotificationOpenDeferredAttemptResult>();
    final sharedAttempt = completer.future;
    pending.inFlightAttempt = sharedAttempt;
    unawaited(() async {
      try {
        completer.complete(
          await _executeDeferredAttempt(
            pending: pending,
            maxAttempts: maxAttempts,
            onRouteContext: onRouteContext,
          ),
        );
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (identical(pending.inFlightAttempt, sharedAttempt)) {
          pending.inFlightAttempt = null;
        }
      }
    }());
    return sharedAttempt;
  }

  Future<NotificationOpenDeferredAttemptResult> _executeDeferredAttempt({
    required _DeferredNotificationOpenRoute pending,
    required int maxAttempts,
    required Future<NotificationOpenRouteDisposition> Function(
      NotificationOpenRouteContext context,
    )
    onRouteContext,
  }) async {
    final context = pending.context;
    if (context.ordinal < _latestDispatchOrdinal) {
      _completeDeferredIfCurrent(
        pending,
        const NotificationOpenRouteCompletion.superseded(),
      );
      return NotificationOpenDeferredAttemptResult._(
        status: NotificationOpenDeferredAttemptStatus.superseded,
        context: context,
        attempt: pending.attempts,
      );
    }

    pending.attempts += 1;
    final attempt = pending.attempts;
    _active = context;
    try {
      final disposition = await onRouteContext(context);
      switch (disposition) {
        case NotificationOpenRouteDisposition.routed:
          final completed = _completeDeferredIfCurrent(
            pending,
            const NotificationOpenRouteCompletion.routed(),
          );
          return NotificationOpenDeferredAttemptResult._(
            status: completed
                ? NotificationOpenDeferredAttemptStatus.routed
                : NotificationOpenDeferredAttemptStatus.superseded,
            context: context,
            attempt: attempt,
          );
        case NotificationOpenRouteDisposition.deferred:
          return NotificationOpenDeferredAttemptResult._(
            status: identical(_deferred, pending)
                ? NotificationOpenDeferredAttemptStatus.retained
                : NotificationOpenDeferredAttemptStatus.superseded,
            context: context,
            attempt: attempt,
          );
        case NotificationOpenRouteDisposition.superseded:
          _completeDeferredIfCurrent(
            pending,
            const NotificationOpenRouteCompletion.superseded(),
          );
          return NotificationOpenDeferredAttemptResult._(
            status: NotificationOpenDeferredAttemptStatus.superseded,
            context: context,
            attempt: attempt,
          );
      }
    } catch (error, stackTrace) {
      final stillCurrent = identical(_deferred, pending) && isLatest(context);
      if (!stillCurrent) {
        return NotificationOpenDeferredAttemptResult._(
          status: NotificationOpenDeferredAttemptStatus.superseded,
          context: context,
          attempt: attempt,
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (attempt < maxAttempts) {
        return NotificationOpenDeferredAttemptResult._(
          status: NotificationOpenDeferredAttemptStatus.retry,
          context: context,
          attempt: attempt,
          error: error,
          stackTrace: stackTrace,
        );
      }
      _completeDeferredIfCurrent(
        pending,
        NotificationOpenRouteCompletion.failed(error, stackTrace),
      );
      return NotificationOpenDeferredAttemptResult._(
        status: NotificationOpenDeferredAttemptStatus.failed,
        context: context,
        attempt: attempt,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (identical(_active, context)) {
        _active = null;
      }
    }
  }

  void _supersedeDeferredOlderThan(int ordinal) {
    final pending = _deferred;
    if (pending == null || pending.context.ordinal >= ordinal) {
      return;
    }
    _deferred = null;
    pending.complete(const NotificationOpenRouteCompletion.superseded());
  }

  bool _completeDeferredIfCurrent(
    _DeferredNotificationOpenRoute pending,
    NotificationOpenRouteCompletion completion,
  ) {
    if (!identical(_deferred, pending)) {
      return false;
    }
    _deferred = null;
    pending.complete(completion);
    return true;
  }
}

class _DeferredNotificationOpenRoute {
  _DeferredNotificationOpenRoute(this.context);

  final NotificationOpenRouteContext context;
  final Completer<NotificationOpenRouteCompletion> completer =
      Completer<NotificationOpenRouteCompletion>();
  Future<NotificationOpenDeferredAttemptResult>? inFlightAttempt;
  int attempts = 0;

  void complete(NotificationOpenRouteCompletion completion) {
    if (!completer.isCompleted) {
      completer.complete(completion);
    }
  }
}

bool didNotificationOpenRouteSucceed({
  required bool routeTargetResolved,
  required NotificationOpenRouteCompletion? completion,
}) {
  return routeTargetResolved && completion?.routed == true;
}

Future<void> routeAppRootInitialLocalNotificationOpen({
  required Future<String?> Function() consumeInitialPayload,
  required PrepareNotificationRouteTargetHandler onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
  NotificationOpenSideEffect? onBeforeOpen,
}) async {
  await onBeforeOpen?.call();
  await routeInitialLocalNotificationOpen(
    consumeInitialPayload: consumeInitialPayload,
    onBeforeRouteTarget: onBeforeRouteTarget,
    onRouteTarget: onRouteTarget,
  );
}

Future<void> routeAppRootLocalNotificationTap({
  required String payload,
  required PrepareNotificationRouteTargetHandler onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
  NotificationOpenSideEffect? onBeforeOpen,
}) async {
  await onBeforeOpen?.call();
  await routeNotificationPayload(
    payload: payload,
    onBeforeRouteTarget: onBeforeRouteTarget,
    onRouteTarget: onRouteTarget,
  );
}

Future<void> routeAppRootRemoteNotificationOpen({
  required Map<String, dynamic> data,
  required PrepareNotificationRouteTargetHandler onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
  MissingGroupNotificationRouteIdHandler? onMissingGroupRouteId,
  required MissingNotificationRouteTargetHandler onMissingRouteTarget,
  NotificationOpenSideEffect? onBeforeOpen,
  NotificationRouteTarget? prevalidatedRouteTarget,
}) async {
  await routeAppRootRemoteNotificationOpenWithResult(
    data: data,
    onBeforeRouteTarget: onBeforeRouteTarget,
    onRouteTarget: onRouteTarget,
    onMissingGroupRouteId: onMissingGroupRouteId,
    onMissingRouteTarget: onMissingRouteTarget,
    onBeforeOpen: onBeforeOpen,
    prevalidatedRouteTarget: prevalidatedRouteTarget,
  );
}

Future<bool> routeAppRootRemoteNotificationOpenWithResult({
  required Map<String, dynamic> data,
  required PrepareNotificationRouteTargetHandler onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
  MissingGroupNotificationRouteIdHandler? onMissingGroupRouteId,
  required MissingNotificationRouteTargetHandler onMissingRouteTarget,
  NotificationOpenSideEffect? onBeforeOpen,
  NotificationRouteTarget? prevalidatedRouteTarget,
}) async {
  await onBeforeOpen?.call();
  if (prevalidatedRouteTarget != null) {
    await onBeforeRouteTarget(prevalidatedRouteTarget);
    await onRouteTarget(prevalidatedRouteTarget);
    return true;
  }
  return routeRemoteNotificationOpenWithResult(
    data: data,
    onBeforeRouteTarget: onBeforeRouteTarget,
    onRouteTarget: onRouteTarget,
    onMissingGroupRouteId: onMissingGroupRouteId,
    onMissingRouteTarget: onMissingRouteTarget,
  );
}

bool isNotificationRouteTargetAlreadyActive({
  required NotificationRouteTarget routeTarget,
  required AppVisibilityTopRouteReader appVisibilityRouteRegistry,
}) {
  switch (routeTarget.kind) {
    case NotificationRouteTargetKind.group:
      return appVisibilityRouteRegistry.isCurrentTopConversationValue(
        lane: AppVisibilityConversationLane.group,
        value: routeTarget.toPayload(),
      );
    case NotificationRouteTargetKind.conversation:
      return appVisibilityRouteRegistry.isCurrentTopConversationValue(
        lane: AppVisibilityConversationLane.direct,
        value: routeTarget.toPayload(),
      );
    case NotificationRouteTargetKind.contactRequest:
    case NotificationRouteTargetKind.intros:
    case NotificationRouteTargetKind.post:
    case NotificationRouteTargetKind.postComment:
      return false;
  }
}
