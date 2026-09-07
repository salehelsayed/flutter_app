import 'dart:async';
import 'dart:collection';

import '../domain/call_end_reason.dart';
import '../domain/call_event.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';
import 'call_cleanup_coordinator.dart';
import 'call_history_projector.dart';

abstract interface class CallEffectExecutor {
  /// Runs one reducer effect. A completed effect may return one fixed-shape
  /// follow-up event, which the coordinator reduces in the same serial lane.
  Future<CallEvent?> execute(CallEffect effect, CallSessionSnapshot snapshot);
}

final class NoopCallEffectExecutor implements CallEffectExecutor {
  const NoopCallEffectExecutor();

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async => null;
}

abstract interface class CallTimerHandle {
  bool get isActive;
  void cancel();
}

abstract interface class CallTimerScheduler {
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback);
}

final class DartCallTimerScheduler implements CallTimerScheduler {
  const DartCallTimerScheduler();

  @override
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback) =>
      _DartCallTimerHandle(delay, callback);
}

final class _DartCallTimerHandle implements CallTimerHandle {
  _DartCallTimerHandle(Duration delay, Future<void> Function() callback)
    : _timer = Timer(delay, () => unawaited(callback()));

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}

final class CallEventQueueFullException implements Exception {
  const CallEventQueueFullException();

  @override
  String toString() => 'CallEventQueueFullException';
}

/// Privacy-safe internal failures from process-owned coordinator work.
enum CallCoordinatorInternalFailure { timerDispatchFailed }

typedef CallAppliedStateTransitionObserver =
    void Function(
      CallEventType trigger,
      CallState resultingState,
      CallEndReason? endReason,
    );

/// One bounded terminal request can interrupt a reduction preparing media.
/// The request is still reduced on the coordinator lane, before later effects.
final class _CallPreparationInterruption {
  _CallPreparationInterruption(this.callId);

  final CallId callId;
  final requested = Completer<CallEvent>();
  final result = Completer<CallReduction>();
}

/// Owns one serial call lane. Reducer effects, timers, cleanup, and history are
/// executed outside the pure reducer and cannot mutate a terminal snapshot.
final class CallCoordinator {
  CallCoordinator({
    required this.reducer,
    required this.cleanupCoordinator,
    required this.historyProjector,
    this.effectExecutor = const NoopCallEffectExecutor(),
    required this.clock,
    required this.idSource,
    this.maxPendingEvents = 64,
    CallTimerScheduler? timerScheduler,
    this.terminalTombstoneCapacity = 128,
    this.effectTimeout = const Duration(seconds: 15),
    this.mediaPreparationTimeout = const Duration(seconds: 45),
    this.terminalEffectTimeout = const Duration(seconds: 5),
    this.terminalHistoryTimeout = const Duration(seconds: 5),
    this.onInternalFailure,
    this.onAppliedStateTransition,
  }) : _timerScheduler = timerScheduler ?? const DartCallTimerScheduler() {
    if (maxPendingEvents <= 0 ||
        terminalTombstoneCapacity <= 0 ||
        effectTimeout <= Duration.zero ||
        mediaPreparationTimeout <= Duration.zero ||
        terminalEffectTimeout <= Duration.zero ||
        terminalHistoryTimeout <= Duration.zero) {
      throw ArgumentError('coordinator bounds must be positive');
    }
  }

  final CallReducer reducer;
  final CallCleanupCoordinator cleanupCoordinator;
  final CallHistoryProjector historyProjector;
  final CallEffectExecutor effectExecutor;
  final DateTime Function() clock;
  final CallId Function() idSource;
  final int maxPendingEvents;
  final int terminalTombstoneCapacity;
  final Duration effectTimeout;
  final Duration mediaPreparationTimeout;
  final Duration terminalEffectTimeout;
  final Duration terminalHistoryTimeout;
  final void Function(CallCoordinatorInternalFailure failure)?
  onInternalFailure;
  final CallAppliedStateTransitionObserver? onAppliedStateTransition;
  final CallTimerScheduler _timerScheduler;

  final StreamController<CallSessionSnapshot> _snapshots =
      StreamController<CallSessionSnapshot>.broadcast(sync: true);
  final Map<CallEffectType, CallTimerHandle> _timers =
      <CallEffectType, CallTimerHandle>{};
  final ListQueue<CallId> _terminalOrder = ListQueue<CallId>();
  final Set<CallId> _terminalIds = <CallId>{};
  final Map<CallId, CallSessionSnapshot> _terminalSnapshots =
      <CallId, CallSessionSnapshot>{};
  final Map<CallId, CallCleanupReport> _terminalCleanupReports =
      <CallId, CallCleanupReport>{};

  Future<void> _tail = Future<void>.value();
  CallSessionSnapshot? _active;
  CallSessionSnapshot? _last;
  int _pendingEvents = 0;
  bool _disposed = false;
  bool _disposing = false;
  Future<void>? _disposeInFlight;
  int _internalFailureCount = 0;
  _CallPreparationInterruption? _preparationInterruption;

  Stream<CallSessionSnapshot> get snapshots => _snapshots.stream;
  CallSessionSnapshot? get activeSession => _active;
  CallSessionSnapshot? get lastSnapshot => _last;
  int get internalFailureCount => _internalFailureCount;

  bool terminalCleanupAckReady(CallId callId) =>
      _terminalCleanupReports[callId]?.terminalAckReady == true;

  Future<bool> retryTerminalCleanup(CallId callId) {
    if (_disposed || _disposing) return Future<bool>.value(false);
    final completer = Completer<bool>();
    _tail = _tail.then<void>((_) async {
      final snapshot = _terminalSnapshots[callId];
      if (snapshot == null || !snapshot.isTerminal) {
        completer.complete(false);
        return;
      }
      try {
        final report = await cleanupCoordinator.cleanup(snapshot);
        _terminalCleanupReports[callId] = report;
        completer.complete(report.terminalAckReady);
      } catch (_) {
        completer.complete(false);
      }
    });
    return completer.future;
  }

  Future<CallReduction> placeCall({
    required String contactPeerId,
    required String localAccountPeerId,
    required String localDeviceId,
  }) {
    final callId = idSource();
    return dispatch(
      CallEvent(
        type: CallEventType.place,
        eventId: 'local-place-${callId.value}',
        occurredAt: clock(),
        callId: callId,
        contactPeerId: contactPeerId,
        localAccountPeerId: localAccountPeerId,
        localDeviceId: localDeviceId,
        remoteAccountPeerId: contactPeerId,
      ),
    );
  }

  /// [onApplied] observes admission before effects finish. Native Answer uses
  /// this to acknowledge the action without waiting for microphone permission.
  /// The returned future still waits for the complete reduction and its effects.
  Future<CallReduction> dispatch(
    CallEvent event, {
    void Function(CallReduction reduction)? onApplied,
  }) {
    if (_disposed || _disposing) {
      return Future<CallReduction>.error(
        StateError('call coordinator is disposed'),
      );
    }
    final interrupted = _interruptPreparation(event);
    if (interrupted != null) return interrupted;
    if (_pendingEvents >= maxPendingEvents) {
      return Future<CallReduction>.error(const CallEventQueueFullException());
    }
    _pendingEvents++;
    final completer = Completer<CallReduction>();
    _tail = _tail.then<void>((_) async {
      try {
        completer.complete(await _dispatchNow(event, onApplied: onApplied));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _pendingEvents--;
      }
    });
    return completer.future;
  }

  Future<CallReduction>? _interruptPreparation(CallEvent event) {
    final interruption = _preparationInterruption;
    final current = _active;
    if (interruption == null ||
        interruption.requested.isCompleted ||
        current == null ||
        current.isTerminal ||
        current.callId != interruption.callId) {
      return null;
    }
    final reduction = reducer.reduce(current, event);
    if (reduction.decision != CallEventDecision.applied ||
        !reduction.snapshot.isTerminal) {
      return null;
    }
    interruption.requested.complete(event);
    return interruption.result.future;
  }

  Future<void> _finishPreparationInterruption(
    _CallPreparationInterruption interruption,
  ) async {
    final event = await interruption.requested.future;
    try {
      interruption.result.complete(await _dispatchNow(event));
    } catch (error, stackTrace) {
      interruption.result.completeError(error, stackTrace);
    }
  }

  Future<CallReduction> _dispatchNow(
    CallEvent event, {
    void Function(CallReduction reduction)? onApplied,
  }) async {
    final eventCallId = event.callId;
    if (eventCallId != null && _terminalIds.contains(eventCallId)) {
      return CallReduction.coordinatorDecision(
        snapshot: _last ?? CallSessionSnapshot.idle(now: clock()),
        decision: CallEventDecision.ignored,
        reason: CallReductionReason.terminalDominates,
      );
    }

    final current = _active;
    if (current != null &&
        eventCallId != null &&
        eventCallId != current.callId &&
        (event.type == CallEventType.remoteInvite ||
            event.type == CallEventType.place)) {
      final sameContact = event.contactPeerId == current.contactPeerId;
      final isGlare =
          sameContact &&
          current.direction == CallDirection.outgoing &&
          event.type == CallEventType.remoteInvite;
      if (!isGlare) {
        return _rejectBusy(current);
      }
      final incomingTuple = _incomingGlareTuple(event);
      final currentTuple = current.glareTuple;
      if (incomingTuple == null || currentTuple == null) {
        return _rejectBusy(current);
      }
      if (currentTuple.compareTo(incomingTuple) <= 0) {
        return _rejectBusy(
          current,
          reason: CallReductionReason.glareCanonicalCallWon,
        );
      }
      await _applyReduction(
        reducer.reduce(
          current,
          CallEvent(
            type: CallEventType.glareLost,
            eventId: 'glare-lost-${current.callId!.value}',
            occurredAt: event.occurredAt,
            callId: current.callId,
            contactPeerId: current.contactPeerId,
            localAccountPeerId: current.direction == CallDirection.outgoing
                ? current.callerAccountPeerId
                : null,
            localDeviceId: current.direction == CallDirection.outgoing
                ? current.callerDeviceId
                : null,
            remoteAccountPeerId: current.direction == CallDirection.incoming
                ? current.callerAccountPeerId
                : current.contactPeerId,
            remoteDeviceId: current.direction == CallDirection.incoming
                ? current.callerDeviceId
                : 'unknown-device',
          ),
        ),
        trigger: CallEventType.glareLost,
      );
    }

    final base = _active ?? CallSessionSnapshot.idle(now: clock());
    return _applyReduction(
      reducer.reduce(base, event),
      trigger: event.type,
      onApplied: onApplied,
    );
  }

  Future<CallReduction> _rejectBusy(
    CallSessionSnapshot current, {
    CallReductionReason reason = CallReductionReason.busy,
  }) async {
    const effect = CallEffect(CallEffectType.sendBusy);
    try {
      await effectExecutor.execute(effect, current).timeout(effectTimeout);
    } catch (_) {
      // Busy delivery belongs to the rejected invite and cannot disturb the
      // unrelated active call.
    }
    return CallReduction.coordinatorDecision(
      snapshot: current,
      decision: reason == CallReductionReason.busy
          ? CallEventDecision.rejected
          : CallEventDecision.ignored,
      reason: reason,
      effects: const <CallEffect>[effect],
    );
  }

  Future<CallReduction> _applyReduction(
    CallReduction reduction, {
    required CallEventType trigger,
    void Function(CallReduction reduction)? onApplied,
  }) async {
    if (reduction.decision != CallEventDecision.applied) return reduction;
    final snapshot = reduction.snapshot;
    _active = snapshot;
    _last = snapshot;
    final previousInterruption = _preparationInterruption;
    final interruption =
        reduction.effects.any(
          (effect) => _isMediaPreparationEffect(effect.type),
        )
        ? _CallPreparationInterruption(snapshot.callId!)
        : null;
    if (interruption != null) _preparationInterruption = interruption;
    try {
      onAppliedStateTransition?.call(
        trigger,
        snapshot.state,
        snapshot.endReason,
      );
    } catch (_) {
      // Identifier-free diagnostics cannot change reducer application.
    }
    _snapshots.add(snapshot);
    try {
      onApplied?.call(reduction);
    } catch (_) {
      // An admission observer cannot change canonical call handling.
    }

    Object? firstEffectError;
    StackTrace? firstEffectStack;
    final terminalDeliveries = <Future<void>>[];
    try {
      for (final effect in reduction.effects) {
        try {
          if (interruption?.requested.isCompleted == true) {
            await _finishPreparationInterruption(interruption!);
            break;
          }
          if (snapshot.isTerminal && _isTerminalDelivery(effect.type)) {
            terminalDeliveries.add(
              _executeTerminalDelivery(effect, snapshot).catchError((
                Object error,
                StackTrace stackTrace,
              ) {
                firstEffectError ??= error;
                firstEffectStack ??= stackTrace;
              }),
            );
            continue;
          }
          await _executeEffect(effect, snapshot, interruption: interruption);
          if (interruption?.requested.isCompleted == true) {
            await _finishPreparationInterruption(interruption!);
            break;
          }
          if (_active?.callId != snapshot.callId ||
              _active?.state != snapshot.state) {
            break;
          }
        } catch (error, stackTrace) {
          if (interruption?.requested.isCompleted == true) {
            await _finishPreparationInterruption(interruption!);
            break;
          }
          firstEffectError ??= error;
          firstEffectStack ??= stackTrace;
          if (!snapshot.isTerminal) {
            try {
              await _dispatchNow(_effectFailureEvent(effect, snapshot));
            } catch (_) {
              // The nested terminal path still owns its cleanup attempt.
            }
            break;
          }
        }
      }
    } finally {
      if (interruption != null) {
        _preparationInterruption = previousInterruption;
      }
      if (snapshot.isTerminal) {
        _cancelTimers();
        try {
          final report = await cleanupCoordinator.cleanup(snapshot);
          _terminalSnapshots[snapshot.callId!] = snapshot;
          _terminalCleanupReports[snapshot.callId!] = report;
        } finally {
          try {
            await historyProjector
                .projectTerminal(snapshot)
                .timeout(terminalHistoryTimeout);
          } finally {
            _rememberTerminal(snapshot.callId!);
            if (_active?.callId == snapshot.callId) _active = null;
          }
        }
      }
    }
    if (terminalDeliveries.isNotEmpty) {
      await Future.wait<void>(terminalDeliveries);
    }
    if (firstEffectError != null) {
      Error.throwWithStackTrace(firstEffectError!, firstEffectStack!);
    }
    return reduction;
  }

  Future<void> _executeTerminalDelivery(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async => effectExecutor
      .execute(effect, snapshot)
      .timeout(terminalEffectTimeout)
      .then<void>((_) {});

  Future<void> _executeEffect(
    CallEffect effect,
    CallSessionSnapshot snapshot, {
    _CallPreparationInterruption? interruption,
  }) async {
    switch (effect.type) {
      case CallEffectType.scheduleNoAnswerTimeout:
        _scheduleTimer(effect, snapshot, CallTimeoutKind.noAnswer);
        return;
      case CallEffectType.scheduleInviteExpiry:
        _scheduleTimer(effect, snapshot, CallTimeoutKind.inviteExpiry);
        return;
      case CallEffectType.scheduleNegotiationTimeout:
        _scheduleTimer(effect, snapshot, CallTimeoutKind.negotiation);
        return;
      case CallEffectType.scheduleReconnectTimeout:
        _scheduleTimer(effect, snapshot, CallTimeoutKind.reconnect);
        return;
      case CallEffectType.cancelTimers:
        _cancelTimers();
        return;
      case CallEffectType.cleanup:
      case CallEffectType.projectHistory:
        return;
      default:
        final execution = effectExecutor
            .execute(effect, snapshot)
            .timeout(
              _isMediaPreparationEffect(effect.type)
                  ? mediaPreparationTimeout
                  : effectTimeout,
            );
        final followUp = await (interruption == null
            ? execution
            : Future.any<CallEvent?>(<Future<CallEvent?>>[
                execution,
                interruption.requested.future.then<CallEvent?>((_) => null),
              ]));
        // Cleanup retires the media bundle and fences late engine completion.
        // A late preparation must never send Accept or advance another call.
        if (interruption?.requested.isCompleted == true) return;
        if (followUp != null) await _dispatchNow(followUp);
    }
  }

  CallEvent _effectFailureEvent(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) => CallEvent(
    type: CallEventType.negotiationFailed,
    eventId:
        'effect-failed-${effect.type.name}-${snapshot.recentEventIds.length}',
    occurredAt: clock(),
    callId: snapshot.callId,
    contactPeerId: snapshot.contactPeerId,
    endReason: _isNegotiationEffect(effect.type)
        ? CallEndReason.mediaFailed
        : CallEndReason.signalingFailed,
  );

  static bool _isTerminalDelivery(CallEffectType type) =>
      type == CallEffectType.sendTerminate || type == CallEffectType.sendReject;

  static bool _isNegotiationEffect(CallEffectType type) => switch (type) {
    CallEffectType.prepareAcceptedMedia ||
    CallEffectType.startNegotiation ||
    CallEffectType.deliverOffer ||
    CallEffectType.deliverAnswer ||
    CallEffectType.queueIceCandidate ||
    CallEffectType.restartIce ||
    CallEffectType.requestIceRestart => true,
    _ => false,
  };

  /// Effects that may show the microphone permission prompt. The user can
  /// take longer than the ordinary effect budget to answer it.
  static bool _isMediaPreparationEffect(CallEffectType type) => switch (type) {
    CallEffectType.prepareAcceptedMedia ||
    CallEffectType.startNegotiation ||
    CallEffectType.deliverOffer => true,
    _ => false,
  };

  void _scheduleTimer(
    CallEffect effect,
    CallSessionSnapshot snapshot,
    CallTimeoutKind timeoutKind,
  ) {
    final delay = effect.delay;
    final callId = snapshot.callId;
    if (delay == null || callId == null || delay.isNegative) return;
    var remaining = delay;
    if (timeoutKind == CallTimeoutKind.inviteExpiry &&
        snapshot.startedAt != null) {
      final authenticatedDeadline = snapshot.startedAt!.add(delay);
      final untilDeadline = authenticatedDeadline.difference(clock());
      remaining = untilDeadline.isNegative ? Duration.zero : untilDeadline;
    }
    _timers.remove(effect.type)?.cancel();
    var fired = false;
    _timers[effect.type] = _timerScheduler.schedule(remaining, () async {
      if (fired) return;
      fired = true;
      _timers.remove(effect.type);
      if (_disposed ||
          _terminalIds.contains(callId) ||
          _active?.callId != callId) {
        return;
      }
      await _enqueueTimerEvent(
        CallEvent(
          type: CallEventType.timeout,
          eventId: 'timer-${timeoutKind.name}-${callId.value}',
          occurredAt: clock(),
          callId: callId,
          contactPeerId: snapshot.contactPeerId,
          localAccountPeerId: snapshot.direction == CallDirection.outgoing
              ? snapshot.callerAccountPeerId
              : null,
          localDeviceId: snapshot.direction == CallDirection.outgoing
              ? snapshot.callerDeviceId
              : null,
          remoteAccountPeerId: snapshot.direction == CallDirection.incoming
              ? snapshot.callerAccountPeerId
              : snapshot.contactPeerId,
          remoteDeviceId: snapshot.direction == CallDirection.incoming
              ? snapshot.callerDeviceId
              : null,
          timeoutKind: timeoutKind,
        ),
      );
    });
  }

  /// Timer events have one reserved bounded path behind the public queue.
  /// There are at most the fixed effect-keyed timers in [_timers], so this
  /// cannot grow with caller traffic and cannot be rejected by queue pressure.
  Future<void> _enqueueTimerEvent(CallEvent event) {
    final interrupted = _interruptPreparation(event);
    if (interrupted != null) {
      return interrupted.then<void>((_) {}).catchError((Object _) {
        _reportInternalFailure(
          CallCoordinatorInternalFailure.timerDispatchFailed,
        );
      });
    }
    final scheduled = _tail.then<void>((_) async {
      if (_disposed) return;
      try {
        await _dispatchNow(event);
      } catch (_) {
        _reportInternalFailure(
          CallCoordinatorInternalFailure.timerDispatchFailed,
        );
      }
    });
    _tail = scheduled;
    return scheduled;
  }

  void _reportInternalFailure(CallCoordinatorInternalFailure failure) {
    _internalFailureCount++;
    try {
      onInternalFailure?.call(failure);
    } catch (_) {
      // An observer cannot break the serialized coordinator lane.
    }
  }

  void _cancelTimers() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _rememberTerminal(CallId callId) {
    if (!_terminalIds.add(callId)) return;
    _terminalOrder.addLast(callId);
    while (_terminalOrder.length > terminalTombstoneCapacity) {
      final evicted = _terminalOrder.removeFirst();
      _terminalIds.remove(evicted);
      _terminalSnapshots.remove(evicted);
      _terminalCleanupReports.remove(evicted);
    }
  }

  static String? _incomingGlareTuple(CallEvent event) {
    final account = event.remoteAccountPeerId;
    final callId = event.callId;
    if (account == null || callId == null) return null;
    return '${callId.value}\u0000$account';
  }

  Future<void> dispose() {
    if (_disposed) return Future<void>.value();
    final inFlight = _disposeInFlight;
    if (inFlight != null) return inFlight;
    _disposing = true;
    final attempt = _disposeAfterQueuedEvents();
    _disposeInFlight = attempt;
    return attempt;
  }

  Future<void> _disposeAfterQueuedEvents() async {
    Object? shutdownError;
    StackTrace? shutdownStack;
    try {
      final preparing = _active;
      if (preparing != null) {
        final interrupted = _interruptPreparation(
          CallEvent(
            type: CallEventType.appShutdown,
            eventId: 'dispose-preparation-${preparing.callId!.value}',
            occurredAt: clock(),
            callId: preparing.callId,
            contactPeerId: preparing.contactPeerId,
          ),
        );
        if (interrupted != null) {
          try {
            await interrupted;
          } catch (error, stackTrace) {
            shutdownError = error;
            shutdownStack = stackTrace;
          }
        }
      }
      final serialized = _tail.then<void>((_) async {
        final current = _active;
        if (current == null || current.isTerminal) return;
        try {
          await _dispatchNow(
            CallEvent(
              type: CallEventType.appShutdown,
              eventId: 'dispose-shutdown-${current.callId!.value}',
              occurredAt: clock(),
              callId: current.callId,
              contactPeerId: current.contactPeerId,
              localAccountPeerId: current.direction == CallDirection.outgoing
                  ? current.callerAccountPeerId
                  : null,
              localDeviceId: current.direction == CallDirection.outgoing
                  ? current.callerDeviceId
                  : null,
              remoteAccountPeerId: current.direction == CallDirection.incoming
                  ? current.callerAccountPeerId
                  : current.contactPeerId,
              remoteDeviceId: current.direction == CallDirection.incoming
                  ? current.callerDeviceId
                  : null,
            ),
          );
        } catch (error, stackTrace) {
          shutdownError = error;
          shutdownStack = stackTrace;
        }
      });
      _tail = serialized;
      await serialized;
    } catch (error, stackTrace) {
      shutdownError ??= error;
      shutdownStack ??= stackTrace;
    } finally {
      _cancelTimers();
      _disposed = true;
      _disposing = false;
      await _snapshots.close();
    }
    if (shutdownError != null) {
      Error.throwWithStackTrace(shutdownError!, shutdownStack!);
    }
  }
}
