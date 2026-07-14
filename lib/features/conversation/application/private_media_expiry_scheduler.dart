import 'dart:async';

import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

/// Only a newly visible receiver-local disappearing parent can move the next
/// expiry earlier. Ordinary delivery/status churn, outgoing messages, and
/// already-terminal private rows must not wake the scheduler.
Stream<void> directPrivateMediaExpiryRescheduleSignals(
  Stream<ConversationMessage> messageChanges,
) => messageChanges
    .where(
      (message) =>
          message.isIncoming &&
          message.privateMediaPolicy.mode == PrivateMediaMode.disappearing &&
          message.privateMediaState == PrivateMediaLifecycleState.available,
    )
    .map<void>((_) {});

/// Generation-checked foreground ownership for recovery + scheduler arming.
///
/// Cold-start and resume recovery are awaited local operations. If the app is
/// paused while either is pending, [onBackgrounded] invalidates its token so
/// the completion cannot undo the stop. A later real resume mints a fresh
/// token and is the only path that may re-arm.
class PrivateMediaLifecycleForegroundRuntime {
  PrivateMediaLifecycleForegroundRuntime({
    required this.isForeground,
    required this.recoverLocalLifecycle,
    required this.startScheduler,
    required this.stopScheduler,
    required this.disposeScheduler,
  });

  final bool Function() isForeground;
  final Future<void> Function() recoverLocalLifecycle;
  final void Function() startScheduler;
  final void Function() stopScheduler;
  final void Function() disposeScheduler;

  bool _foreground = false;
  bool _disposed = false;
  int _generation = 0;
  Future<void> _recoveryTail = Future<void>.value();

  Future<void> recoverColdStartAndArm() {
    if (_disposed) return Future<void>.value();
    // Flutter may launch into a hidden/paused state. Local reconciliation is
    // still required, but only an actually resumed launch owns the timer.
    _foreground = isForeground();
    final generation = ++_generation;
    return _enqueueRecoveryAndArm(generation);
  }

  Future<void> recoverResumeAndArm() {
    if (_disposed) return Future<void>.value();
    _foreground = true;
    final generation = ++_generation;
    return _enqueueRecoveryAndArm(generation);
  }

  Future<void> _enqueueRecoveryAndArm(int generation) {
    // Serialize bounded passes. A resume that arrives while an earlier pass is
    // pending must run once after it (state may have changed while paused), and
    // its newer generation is the only one allowed to arm the scheduler.
    final recovery = _recoveryTail.then((_) => recoverLocalLifecycle());
    _recoveryTail = recovery.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return recovery.whenComplete(() {
      if (!_disposed && _foreground && generation == _generation) {
        startScheduler();
      }
    });
  }

  void onBackgrounded() {
    if (_disposed) return;
    _foreground = false;
    _generation++;
    stopScheduler();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _foreground = false;
    _generation++;
    disposeScheduler();
  }
}

/// One foreground-only timer for receiver-local disappearing media.
///
/// The durable lifecycle engine remains the expiry authority. This class only
/// asks for the next deadline, wakes the engine, and reschedules. Repository
/// change signals move the timer earlier when a newly received parent lands.
class PrivateMediaExpiryScheduler {
  PrivateMediaExpiryScheduler({
    required this.loadNextExpiryAtMs,
    required this.sweepDueExpiries,
    required this.rescheduleSignals,
    required this.nowMs,
    this.retryDelay = const Duration(seconds: 1),
  });

  final Future<int?> Function() loadNextExpiryAtMs;
  final Future<void> Function(int evaluationFloorMs) sweepDueExpiries;
  final Stream<void> rescheduleSignals;
  final int Function() nowMs;
  final Duration retryDelay;

  Timer? _timer;
  StreamSubscription<void>? _subscription;
  bool _running = false;
  bool _disposed = false;
  int _generation = 0;
  int? _clockFloorMs;

  bool get isRunning => _running;

  void start() {
    if (_disposed) return;
    _running = true;
    _subscription ??= rescheduleSignals.listen((_) {
      if (_running) unawaited(_reschedule());
    });
    unawaited(_reschedule());
  }

  void stop() {
    _running = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  Future<void> _reschedule() async {
    if (!_running || _disposed) return;
    final generation = ++_generation;
    _timer?.cancel();
    _timer = null;

    final observedNowMs = nowMs();
    final previousFloorMs = _clockFloorMs;
    final clockFloorMs =
        previousFloorMs == null || observedNowMs > previousFloorMs
        ? observedNowMs
        : previousFloorMs;
    _clockFloorMs = clockFloorMs;

    final int? next;
    try {
      next = await loadNextExpiryAtMs();
    } catch (_) {
      // A repository failure must not escape an unawaited future or leave an
      // already-due item stranded until another lifecycle event.
      _armRetry(generation);
      return;
    }
    if (!_running || _disposed || generation != _generation) return;
    if (next == null) return;

    final delayMs = next - clockFloorMs;
    final evaluationFloorMs = next > clockFloorMs ? next : clockFloorMs;
    _timer = Timer(
      Duration(milliseconds: delayMs > 0 ? delayMs : 0),
      () => unawaited(_onTimer(generation, evaluationFloorMs)),
    );
  }

  Future<void> _onTimer(int generation, int evaluationFloorMs) async {
    if (!_running || _disposed || generation != _generation) return;
    _timer = null;
    final previousFloorMs = _clockFloorMs;
    if (previousFloorMs == null || evaluationFloorMs > previousFloorMs) {
      _clockFloorMs = evaluationFloorMs;
    }
    try {
      await sweepDueExpiries(evaluationFloorMs);
    } catch (_) {
      // Keep the scheduler alive with a bounded non-zero retry, avoiding both
      // silent death and a zero-delay hot loop.
      _armRetry(generation);
      return;
    }
    if (_running && !_disposed && generation == _generation) {
      await _reschedule();
    }
  }

  void _armRetry(int generation) {
    if (!_running || _disposed || generation != _generation) return;
    _timer?.cancel();
    final delay = retryDelay > Duration.zero
        ? retryDelay
        : const Duration(milliseconds: 1);
    _timer = Timer(delay, () {
      if (_running && !_disposed && generation == _generation) {
        unawaited(_reschedule());
      }
    });
  }
}
