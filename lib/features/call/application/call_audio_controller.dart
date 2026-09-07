import 'dart:async';

import '../../../core/permissions/mic_permission_gateway.dart';
import '../domain/call_engine.dart';

/// App-owned microphone permission seam. Plugin types stay behind adapters.
abstract interface class CallMicrophonePermission {
  Future<MicPermissionStatus> request();
}

/// An exclusive lease over media that conflicts with foreground call audio.
///
/// Releasing the lease may restore playback only through its existing
/// interruption owner. It must never restart microphone recording.
abstract interface class CallMediaConflictLease {
  Future<void> release();
}

/// Stops or refuses conflicting recording before returning an exclusive lease.
abstract interface class CallMediaConflictPort {
  Future<CallMediaConflictLease> acquireForCall();
}

/// A fixed-shape refusal that does not expose recorder or playback details.
final class CallMediaConflictRefused implements Exception {
  const CallMediaConflictRefused();

  @override
  String toString() => 'CallMediaConflictRefused';
}

/// Coarse audio-session interruption signal owned by the application layer.
final class CallAudioSessionInterruption {
  const CallAudioSessionInterruption.begin() : isBeginning = true;

  const CallAudioSessionInterruption.end() : isBeginning = false;

  final bool isBeginning;
}

/// Foreground audio focus/session ownership without platform plugin types.
abstract interface class CallForegroundAudioSession {
  Stream<CallAudioSessionInterruption> get interruptions;

  /// True only while this call still owns foreground audio recovery authority.
  bool get ownsSession;

  Future<void> activate();

  Future<void> deactivate();
}

enum CallAudioStartStatus {
  started,
  notLocallyAccepted,
  invalidConfiguration,
  permissionDenied,
  permissionFailed,
  mediaConflict,
  audioSessionFailed,
  engineFailed,
  closed,
}

/// The fixed, identifier-free engine substage that failed during audio start.
///
/// Exceptions, connection configuration, call authority and media details are
/// deliberately excluded from this diagnostic boundary.
enum CallAudioEngineStartStage {
  setAudioSessionActive,
  createConnection,
  supportedOutputRoutes,
  snapshot,
}

typedef CallAudioEngineStartFailureObserver =
    void Function(CallAudioEngineStartStage stage);

enum CallAudioFailure {
  none,
  notLocallyAccepted,
  invalidConfiguration,
  permissionDenied,
  permissionFailed,
  mediaConflict,
  audioSessionFailed,
  engineFailed,
  notActive,
  unsupportedRoute,
  controlFailed,
  interruptionFailed,
  cleanupFailed,
  closed,
}

extension on CallAudioFailure {
  String? get messageKey => switch (this) {
    CallAudioFailure.none => null,
    CallAudioFailure.notLocallyAccepted => 'call.audio.notAccepted',
    CallAudioFailure.invalidConfiguration => 'call.audio.invalidConfiguration',
    CallAudioFailure.permissionDenied => 'call.audio.permissionDenied',
    CallAudioFailure.permissionFailed => 'call.audio.permissionUnavailable',
    CallAudioFailure.mediaConflict => 'call.audio.mediaConflict',
    CallAudioFailure.audioSessionFailed => 'call.audio.sessionUnavailable',
    CallAudioFailure.engineFailed => 'call.audio.mediaFailed',
    CallAudioFailure.notActive => 'call.audio.notActive',
    CallAudioFailure.unsupportedRoute => 'call.audio.routeUnsupported',
    CallAudioFailure.controlFailed => 'call.audio.controlFailed',
    CallAudioFailure.interruptionFailed => 'call.audio.interruptionFailed',
    CallAudioFailure.cleanupFailed => 'call.audio.cleanupFailed',
    CallAudioFailure.closed => 'call.audio.closed',
  };
}

enum CallAudioInterruptionIntent { pausedReconnect, recover }

/// Fixed-cardinality cleanup step that made [CallAudioController.close]
/// report [CallAudioFailure.cleanupFailed]. The system-route reset is
/// deliberately absent: it is best-effort and never fails cleanup by itself.
enum CallAudioCleanupStage {
  engineClose,
  interruptionSubscriptionCancel,
  routeSubscriptionCancel,
  commandTail,
  sessionDeactivate,
  leaseRelease,
  interruptionIntentsClose,
  stateChangesClose,
}

/// Actual, coarse control state projected from [CallEngine.snapshot].
final class CallAudioControlState {
  CallAudioControlState({
    required this.muted,
    required this.selectedRoute,
    required List<CallAudioOutputRoute> supportedRoutes,
    required this.active,
    required this.failure,
  }) : supportedRoutes = List<CallAudioOutputRoute>.unmodifiable(
         supportedRoutes,
       );

  static final idle = CallAudioControlState(
    muted: false,
    selectedRoute: CallAudioOutputRoute.systemDefault,
    supportedRoutes: const <CallAudioOutputRoute>[],
    active: false,
    failure: CallAudioFailure.none,
  );

  final bool muted;
  final CallAudioOutputRoute selectedRoute;
  final List<CallAudioOutputRoute> supportedRoutes;
  final bool active;
  final CallAudioFailure failure;

  String? get messageKey => failure.messageKey;

  CallAudioControlState withFailure(CallAudioFailure nextFailure) =>
      CallAudioControlState(
        muted: muted,
        selectedRoute: selectedRoute,
        supportedRoutes: supportedRoutes,
        active: active,
        failure: nextFailure,
      );

  CallAudioControlState inactive({CallAudioFailure? nextFailure}) =>
      CallAudioControlState(
        muted: muted,
        selectedRoute: selectedRoute,
        supportedRoutes: supportedRoutes,
        active: false,
        failure: nextFailure ?? failure,
      );
}

final class CallAudioStartResult {
  const CallAudioStartResult({
    required this.status,
    required this.state,
    this.permissionStatus,
  });

  final CallAudioStartStatus status;
  final CallAudioControlState state;
  final MicPermissionStatus? permissionStatus;
}

/// Owns one foreground call's permission, media conflict, session and controls.
final class CallAudioController {
  CallAudioController({
    required CallEngine engine,
    required CallMicrophonePermission microphonePermission,
    required CallMediaConflictPort mediaConflicts,
    required CallForegroundAudioSession audioSession,
    CallAudioEngineStartFailureObserver? onEngineStartFailure,
  }) : _engine = engine,
       _microphonePermission = microphonePermission,
       _mediaConflicts = mediaConflicts,
       _audioSession = audioSession,
       _onEngineStartFailure = onEngineStartFailure {
    _interruptionSubscription = _audioSession.interruptions.listen(
      _onInterruption,
      onError: (_) => _recordFailure(CallAudioFailure.interruptionFailed),
    );
    final CallAudioOutputRouteChangeSource? routeChangeSource =
        engine is CallAudioOutputRouteChangeSource
        ? engine as CallAudioOutputRouteChangeSource
        : null;
    _outputRouteSubscription = routeChangeSource?.outputRouteChanges.listen(
      _onOutputRouteChanged,
      onError: (_) {},
    );
  }

  final CallEngine _engine;
  final CallMicrophonePermission _microphonePermission;
  final CallMediaConflictPort _mediaConflicts;
  final CallForegroundAudioSession _audioSession;
  final CallAudioEngineStartFailureObserver? _onEngineStartFailure;
  final StreamController<CallAudioInterruptionIntent> _interruptionIntents =
      StreamController<CallAudioInterruptionIntent>.broadcast(sync: true);
  final StreamController<CallAudioControlState> _stateChanges =
      StreamController<CallAudioControlState>.broadcast(sync: true);

  late final StreamSubscription<CallAudioSessionInterruption>
  _interruptionSubscription;
  StreamSubscription<CallAudioOutputRoute>? _outputRouteSubscription;
  Future<void> _commandTail = Future<void>.value();
  bool _cleanupInsideStart = false;
  Future<CallAudioStartResult>? _startFuture;
  Future<void>? _closeFuture;
  Future<void>? _engineCloseFuture;
  Future<void>? _routeResetFuture;
  Future<bool>? _cleanupFuture;
  CallMediaConflictLease? _conflictLease;
  CallAudioFailure? _failureBeforeCleanup;
  CallAudioCleanupStage? _cleanupFailureStage;
  bool _routeResetFailedAtCleanup = false;
  CallAudioControlState _state = CallAudioControlState.idle;
  bool _started = false;
  bool _closeRequested = false;
  bool _audioSessionActivationAttempted = false;
  bool _interruptionSubscriptionCancelled = false;
  bool _interrupted = false;
  bool _pendingOutputRouteRefresh = false;

  CallAudioControlState get state => _state;

  /// First fatal cleanup step that failed during the latest cleanup attempt,
  /// or null when cleanup succeeded (or has not run).
  CallAudioCleanupStage? get cleanupFailureStage => _cleanupFailureStage;

  /// True when the best-effort system-route reset failed during cleanup.
  /// The platform releases the route with the call; cleanup still succeeds.
  bool get routeResetFailedAtCleanup => _routeResetFailedAtCleanup;

  /// Broadcasts engine-projected results and fixed-shape failure states.
  /// Consumers read [state] initially and must not invent optimistic controls.
  Stream<CallAudioControlState> get stateChanges => _stateChanges.stream;

  Stream<CallAudioInterruptionIntent> get interruptionIntents =>
      _interruptionIntents.stream;

  Future<CallAudioStartResult> start({
    required bool locallyAccepted,
    required CallConnectionConfiguration configuration,
  }) {
    if (!locallyAccepted) {
      return Future<CallAudioStartResult>.value(
        _result(
          CallAudioStartStatus.notLocallyAccepted,
          CallAudioFailure.notLocallyAccepted,
        ),
      );
    }
    if (!_isAudioOnlyCapture(configuration)) {
      return Future<CallAudioStartResult>.value(
        _result(
          CallAudioStartStatus.invalidConfiguration,
          CallAudioFailure.invalidConfiguration,
        ),
      );
    }
    if (_closeRequested) {
      return Future<CallAudioStartResult>.value(_closedResult());
    }
    return _startFuture ??= _startOnce(configuration);
  }

  Future<CallAudioStartResult> _startOnce(
    CallConnectionConfiguration configuration,
  ) async {
    MicPermissionStatus permissionStatus;
    try {
      permissionStatus = await _microphonePermission.request();
    } catch (_) {
      return _terminalStartFailure(
        CallAudioStartStatus.permissionFailed,
        CallAudioFailure.permissionFailed,
      );
    }
    if (_closeRequested) return _closedResult(permissionStatus);
    if (permissionStatus != MicPermissionStatus.granted) {
      return _terminalStartFailure(
        CallAudioStartStatus.permissionDenied,
        CallAudioFailure.permissionDenied,
        permissionStatus: permissionStatus,
      );
    }

    try {
      _conflictLease = await _mediaConflicts.acquireForCall();
    } catch (_) {
      return _terminalStartFailure(
        CallAudioStartStatus.mediaConflict,
        CallAudioFailure.mediaConflict,
        permissionStatus: permissionStatus,
      );
    }
    if (_closeRequested) return _closedResult(permissionStatus);

    _audioSessionActivationAttempted = true;
    try {
      await _audioSession.activate();
    } catch (_) {
      return _terminalStartFailure(
        CallAudioStartStatus.audioSessionFailed,
        CallAudioFailure.audioSessionFailed,
        permissionStatus: permissionStatus,
      );
    }
    if (_closeRequested) return _closedResult(permissionStatus);

    var engineStartStage = CallAudioEngineStartStage.setAudioSessionActive;
    try {
      await _engine.setAudioSessionActive(true);
      if (_closeRequested) return _closedResult(permissionStatus);
      engineStartStage = CallAudioEngineStartStage.createConnection;
      await _engine.createConnection(configuration);
      if (_closeRequested) return _closedResult(permissionStatus);
      List<CallAudioOutputRoute> supportedRoutes;
      try {
        supportedRoutes = await _engine.supportedOutputRoutes();
      } catch (_) {
        supportedRoutes = const <CallAudioOutputRoute>[
          CallAudioOutputRoute.systemDefault,
        ];
      }
      if (_closeRequested) return _closedResult(permissionStatus);
      _updateState(
        CallAudioControlState(
          muted: !configuration.captureAudio,
          selectedRoute: CallAudioOutputRoute.systemDefault,
          supportedRoutes: _deduplicate(supportedRoutes),
          active: true,
          failure: CallAudioFailure.none,
        ),
      );
      if (_closeRequested) return _closedResult(permissionStatus);
    } catch (_) {
      _reportEngineStartFailure(engineStartStage);
      return _terminalStartFailure(
        CallAudioStartStatus.engineFailed,
        CallAudioFailure.engineFailed,
        permissionStatus: permissionStatus,
      );
    }

    _started = true;
    if (_pendingOutputRouteRefresh) {
      _pendingOutputRouteRefresh = false;
      _onOutputRouteChanged(CallAudioOutputRoute.systemDefault);
    }
    return CallAudioStartResult(
      status: CallAudioStartStatus.started,
      state: _state,
      permissionStatus: permissionStatus,
    );
  }

  Future<CallAudioStartResult> _terminalStartFailure(
    CallAudioStartStatus status,
    CallAudioFailure failure, {
    MicPermissionStatus? permissionStatus,
  }) async {
    _updateState(_state.withFailure(failure));
    _closeRequested = true;
    // Cleanup runs inside the start future. A command queued during start
    // (a native mute) is itself awaiting that future, so waiting for the
    // command tail here would deadlock and leak the capture lease.
    _cleanupInsideStart = true;
    final cleanupFailed = await _ensureCleanup();
    _cleanupInsideStart = false;
    if (cleanupFailed) {
      _updateState(_state.withFailure(CallAudioFailure.cleanupFailed));
    }
    return CallAudioStartResult(
      status: status,
      state: _state,
      permissionStatus: permissionStatus,
    );
  }

  Future<CallAudioControlState> setMuted(bool muted) =>
      _enqueueCommand(() async {
        final inFlightStart = _startFuture;
        if (!_started && !_closeRequested && inFlightStart != null) {
          await inFlightStart;
        }
        if (!_canControl) return _unavailableControlState();
        try {
          await _engine.setLocalAudioEnabled(!muted);
          return _refreshState();
        } catch (_) {
          return _recoverControlState(CallAudioFailure.controlFailed);
        }
      });

  Future<CallAudioControlState> selectOutputRoute(CallAudioOutputRoute route) =>
      _enqueueCommand(() async {
        if (!_canControl) return _unavailableControlState();
        List<CallAudioOutputRoute> supported;
        try {
          supported = await _engine.supportedOutputRoutes();
        } catch (_) {
          return _recoverControlState(CallAudioFailure.controlFailed);
        }
        if (!supported.contains(route)) {
          return _recoverControlState(
            CallAudioFailure.unsupportedRoute,
            supportedRoutes: supported,
          );
        }
        try {
          await _engine.selectOutputRoute(route);
          return _refreshState(supportedRoutes: supported);
        } catch (_) {
          return _recoverControlState(
            CallAudioFailure.controlFailed,
            supportedRoutes: supported,
          );
        }
      });

  /// Waits until commands already accepted by the controller have settled.
  Future<void> settle() => _commandTail;

  Future<void> close() {
    _closeRequested = true;
    final existing = _closeFuture;
    if (existing != null) return existing;
    final routeReset = _beginRouteReset();
    if (routeReset != null) {
      unawaited(routeReset.catchError((Object _) {}));
    }
    final engineClosing = _beginEngineClose();
    unawaited(engineClosing.catchError((Object _) {}));
    late final Future<void> next;
    next = _closeAfterStart().then<void>(
      (cleanupFailed) {
        if (cleanupFailed && identical(_closeFuture, next)) {
          _closeFuture = null;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_closeFuture, next)) _closeFuture = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _closeFuture = next;
    return next;
  }

  Future<bool> _closeAfterStart() async {
    final startFuture = _startFuture;
    if (startFuture != null) {
      try {
        await startFuture;
      } catch (_) {}
    }
    final cleanupFailed = await _ensureCleanup();
    if (cleanupFailed) {
      _updateState(
        _state.inactive(nextFailure: CallAudioFailure.cleanupFailed),
      );
    } else {
      _updateState(_state.inactive());
    }
    return cleanupFailed;
  }

  Future<bool> _ensureCleanup() {
    final existing = _cleanupFuture;
    if (existing != null) return existing;
    _failureBeforeCleanup ??= _state.failure;
    late final Future<bool> next;
    next = _cleanupOnce().then<bool>(
      (failed) {
        if (failed && identical(_cleanupFuture, next)) {
          _cleanupFuture = null;
        }
        return failed;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_cleanupFuture, next)) _cleanupFuture = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _cleanupFuture = next;
    return next;
  }

  Future<bool> _cleanupOnce() async {
    var failed = false;
    _cleanupFailureStage = null;
    _routeResetFailedAtCleanup = false;

    Future<bool> run(
      CallAudioCleanupStage stage,
      Future<void> Function() operation,
    ) async {
      try {
        await operation();
        return true;
      } catch (_) {
        failed = true;
        _cleanupFailureStage ??= stage;
        return false;
      }
    }

    final routeReset = _beginRouteReset();
    if (routeReset != null) {
      unawaited(routeReset.catchError((Object _) {}));
    }
    var engineCloseSucceeded = true;
    try {
      await _beginEngineClose();
    } catch (_) {
      failed = true;
      _cleanupFailureStage ??= CallAudioCleanupStage.engineClose;
      engineCloseSucceeded = false;
    }
    if (!_interruptionSubscriptionCancelled &&
        await run(
          CallAudioCleanupStage.interruptionSubscriptionCancel,
          _interruptionSubscription.cancel,
        )) {
      _interruptionSubscriptionCancelled = true;
    }
    final outputRouteSubscription = _outputRouteSubscription;
    if (outputRouteSubscription != null &&
        await run(
          CallAudioCleanupStage.routeSubscriptionCancel,
          outputRouteSubscription.cancel,
        )) {
      _outputRouteSubscription = null;
    }
    if (routeReset != null) {
      // Best-effort: the platform releases the output route together with
      // the call (Telecom/CallKit end it before media cleanup runs), so a
      // refused reset must not fail cleanup or poison its retry.
      try {
        await routeReset;
      } catch (_) {
        _routeResetFailedAtCleanup = true;
      }
    }
    if (!_cleanupInsideStart) {
      await run(CallAudioCleanupStage.commandTail, () => _commandTail);
    }
    if (_audioSessionActivationAttempted &&
        await run(
          CallAudioCleanupStage.sessionDeactivate,
          _audioSession.deactivate,
        )) {
      _audioSessionActivationAttempted = false;
    }
    final lease = _conflictLease;
    if (lease != null &&
        engineCloseSucceeded &&
        await run(CallAudioCleanupStage.leaseRelease, lease.release)) {
      _conflictLease = null;
    }
    if (!_interruptionIntents.isClosed) {
      await run(
        CallAudioCleanupStage.interruptionIntentsClose,
        _interruptionIntents.close,
      );
    }
    if (!failed) _started = false;
    _updateState(
      _state.inactive(
        nextFailure: failed
            ? CallAudioFailure.cleanupFailed
            : _failureBeforeCleanup ?? CallAudioFailure.none,
      ),
    );
    if (!_stateChanges.isClosed) {
      await run(CallAudioCleanupStage.stateChangesClose, _stateChanges.close);
    }
    return failed;
  }

  Future<void> _beginEngineClose() {
    final existing = _engineCloseFuture;
    if (existing != null) return existing;
    late final Future<void> next;
    next = Future<void>.sync(_engine.close).onError((
      Object error,
      StackTrace stackTrace,
    ) {
      if (identical(_engineCloseFuture, next)) _engineCloseFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
    _engineCloseFuture = next;
    return next;
  }

  Future<void>? _beginRouteReset() {
    if (!_started) return null;
    final existing = _routeResetFuture;
    if (existing != null) return existing;
    late final Future<void> next;
    next =
        Future<void>.sync(
          () => _engine.selectOutputRoute(CallAudioOutputRoute.systemDefault),
        ).onError((Object error, StackTrace stackTrace) {
          if (identical(_routeResetFuture, next)) _routeResetFuture = null;
          Error.throwWithStackTrace(error, stackTrace);
        });
    _routeResetFuture = next;
    return next;
  }

  void _onInterruption(CallAudioSessionInterruption interruption) {
    if (!_started || _closeRequested) return;
    if (interruption.isBeginning) {
      if (_interrupted) return;
      _interrupted = true;
      if (!_interruptionIntents.isClosed) {
        _interruptionIntents.add(CallAudioInterruptionIntent.pausedReconnect);
      }
      unawaited(
        _enqueueCommand<CallAudioControlState>(() async {
          if (!_canControl) return _unavailableControlState();
          try {
            await _engine.setAudioSessionActive(false);
            return _refreshState();
          } catch (_) {
            return _recoverControlState(CallAudioFailure.interruptionFailed);
          }
        }),
      );
      return;
    }

    if (!_interrupted) return;
    _interrupted = false;
    if (!_audioSession.ownsSession) return;
    unawaited(
      _enqueueCommand<CallAudioControlState>(() async {
        if (!_canControl || !_audioSession.ownsSession) {
          return _unavailableControlState();
        }
        try {
          await _engine.setAudioSessionActive(true);
          final refreshed = await _refreshState();
          if (_canControl && _audioSession.ownsSession) {
            _interruptionIntents.add(CallAudioInterruptionIntent.recover);
          }
          return refreshed;
        } catch (_) {
          return _recoverControlState(CallAudioFailure.interruptionFailed);
        }
      }),
    );
  }

  void _onOutputRouteChanged(CallAudioOutputRoute _) {
    if (_closeRequested) return;
    if (!_started) {
      // Native activation and the initial inventory read can reveal the
      // actual route before start has published its initial control state.
      _pendingOutputRouteRefresh = true;
      return;
    }
    unawaited(
      _enqueueCommand<CallAudioControlState>(() async {
        if (!_canControl) return _state;
        try {
          return await _refreshState();
        } catch (_) {
          _recordFailure(CallAudioFailure.controlFailed);
          return _state;
        }
      }),
    );
  }

  bool get _canControl => _started && !_closeRequested;

  CallAudioControlState _unavailableControlState() {
    final failure = _closeRequested
        ? CallAudioFailure.closed
        : CallAudioFailure.notActive;
    _updateState(_state.withFailure(failure));
    return _state;
  }

  Future<CallAudioControlState> _refreshState({
    List<CallAudioOutputRoute>? supportedRoutes,
    CallAudioFailure failure = CallAudioFailure.none,
  }) async {
    final routes = supportedRoutes ?? await _engine.supportedOutputRoutes();
    final snapshot = await _engine.snapshot();
    if (_closeRequested) return _state;
    _updateState(
      CallAudioControlState(
        muted: !snapshot.localAudioEnabled,
        selectedRoute: snapshot.outputRoute,
        supportedRoutes: _deduplicate(routes),
        active: snapshot.audioSessionActive,
        failure: failure,
      ),
    );
    return _state;
  }

  Future<CallAudioControlState> _recoverControlState(
    CallAudioFailure failure, {
    List<CallAudioOutputRoute>? supportedRoutes,
  }) async {
    try {
      return await _refreshState(
        supportedRoutes: supportedRoutes,
        failure: failure,
      );
    } catch (_) {
      _recordFailure(failure);
      return _state;
    }
  }

  void _recordFailure(CallAudioFailure failure) {
    _updateState(_state.withFailure(failure));
  }

  void _reportEngineStartFailure(CallAudioEngineStartStage stage) {
    try {
      _onEngineStartFailure?.call(stage);
    } catch (_) {
      // Identifier-free diagnostics cannot change media lifecycle authority.
    }
  }

  Future<T> _enqueueCommand<T>(Future<T> Function() command) {
    final result = Completer<T>();
    _commandTail = _commandTail.then((_) async {
      try {
        result.complete(await command());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  CallAudioStartResult _result(
    CallAudioStartStatus status,
    CallAudioFailure failure,
  ) {
    _updateState(_state.withFailure(failure));
    return CallAudioStartResult(status: status, state: _state);
  }

  CallAudioStartResult _closedResult([MicPermissionStatus? permissionStatus]) {
    _updateState(_state.inactive(nextFailure: CallAudioFailure.closed));
    return CallAudioStartResult(
      status: CallAudioStartStatus.closed,
      state: _state,
      permissionStatus: permissionStatus,
    );
  }

  static bool _isAudioOnlyCapture(CallConnectionConfiguration configuration) =>
      configuration.receiveAudio &&
      configuration.captureAudio &&
      !configuration.receiveVideo &&
      !configuration.captureVideo;

  static List<CallAudioOutputRoute> _deduplicate(
    List<CallAudioOutputRoute> routes,
  ) => List<CallAudioOutputRoute>.unmodifiable(<CallAudioOutputRoute>{
    ...routes,
  });

  void _updateState(CallAudioControlState next) {
    _state = next;
    if (!_stateChanges.isClosed) _stateChanges.add(next);
  }
}
