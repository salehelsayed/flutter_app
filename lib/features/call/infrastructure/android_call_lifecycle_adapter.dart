import 'dart:async';

import '../application/call_audio_controller.dart';
import '../application/call_coordinator.dart';
import '../application/handle_incoming_call_signal.dart';
import '../domain/call_engine.dart';
import '../domain/call_end_reason.dart';
import '../domain/call_event.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';
import 'call_audio_route_adapter.dart';

typedef NativeCallLifecycleMethodInvoker =
    Future<Object?> Function(String method, Map<String, Object?> arguments);
typedef AndroidCallMethodInvoker = NativeCallLifecycleMethodInvoker;
typedef AuthenticatedCallHandleResolver = String? Function(CallId callId);
typedef NativeCallMuteApplier =
    Future<bool> Function(CallId callId, bool muted);
typedef NativeCallStateProjector =
    String Function(CallSessionSnapshot snapshot);
typedef AndroidNativeMuteApplier = NativeCallMuteApplier;
typedef NativeOutgoingRegistrationResultObserver =
    void Function(
      NativeOutgoingRegistrationStage stage,
      NativeOutgoingRegistrationStatus status,
      NativeOutgoingRegistrationReason reason,
    );

/// Coarse, identifier-free boundaries for one outgoing native registration.
enum NativeOutgoingRegistrationStage {
  preflight,
  handleResolution,
  descriptorValidation,
  binding,
  terminalReplay,
  adoption,
  nativeRegistration,
  adoptionCompletion,
}

enum NativeOutgoingRegistrationStatus { success, rejected, error }

/// Fixed vocabulary only: no call, peer, handle, endpoint or native payload
/// can cross the diagnostic observer boundary.
enum NativeOutgoingRegistrationReason {
  none,
  closed,
  invalidLatched,
  expired,
  sessionMismatch,
  invalidHandle,
  handleResolutionFailed,
  descriptorConflict,
  bindingConflict,
  terminalPending,
  terminalCleanupPending,
  terminalDispatchRejected,
  terminalDispatchFailed,
  adoptionRejected,
  adoptionInvocationFailed,
  adoptionAcknowledgementRejected,
  adoptionReconciliationFailed,
  nativeRejected,
  nativeInvocationFailed,
  adoptionIncomplete,
}

/// The platform-neutral surface consumed by the single production call graph.
///
/// Android Telecom and iOS CallKit share the same strict v1 journal protocol;
/// platform wrappers retain their own channel names, rollout gates and public
/// error types while this interface prevents either platform from owning a
/// second coordinator or media runtime.
abstract interface class NativeCallLifecycleAdapter
    implements
        IncomingCallPresenter,
        CallForegroundAudioSession,
        CallAudioRoutePort {
  Future<void> start();

  /// Finishes an exact retained terminal before a new coordinator placement
  /// begins. Callers must invoke this outside the coordinator effect tail.
  Future<bool> reconcileBeforeOutgoing();

  Future<bool> registerOutgoing(CallId callId, {required DateTime expiresAt});

  bool isBoundTo(CallId callId);

  void bindNativeMuteApplier(NativeCallMuteApplier applier);

  void notifyNativeMuteTargetReady(CallId callId);

  Future<void> close();
}

/// The persisted native capability is authorized only when the same complete
/// gate set can construct the canonical Dart call graph.
bool isAndroidNativeCallCapabilityAuthorized(Map<String, bool> featureFlags) =>
    featureFlags['voice_call_capability_v1'] == true &&
    featureFlags['voice_call_incoming_enabled'] == true &&
    featureFlags['voice_call_turn_enabled'] == true &&
    featureFlags['voice_call_android_native_enabled'] == true;

/// Clears a previously persisted native capability when the current rollout
/// does not authorize Android system calling. Enabling remains owned by the
/// fully constructed adapter after authenticated graph readiness.
Future<void> enforceAndroidCallCapabilityRollback({
  required bool isAndroid,
  required bool capabilityEnabled,
  required AndroidCallMethodInvoker invokeMethod,
}) async {
  if (!isAndroid || capabilityEnabled) return;
  try {
    final disabled = await invokeMethod(
      'setCapabilityEnabled',
      const <String, Object?>{
        'version': AndroidCallLifecycleAdapter.protocolVersion,
        'enabled': false,
      },
    );
    if (disabled == true) return;
  } catch (_) {
    // The fixed-shape failure below does not expose platform details.
  }
  throw const AndroidCallLifecycleException(
    AndroidCallLifecycleErrorCode.nativeFailure,
  );
}

enum AndroidCallLifecycleErrorCode {
  closed,
  unavailable,
  malformedResponse,
  nativeFailure,
}

/// A fixed-shape error which never includes native values or call authority.
final class AndroidCallLifecycleException implements Exception {
  const AndroidCallLifecycleException(this.code);

  final AndroidCallLifecycleErrorCode code;

  @override
  String toString() => 'AndroidCallLifecycleException(${code.name})';
}

final class AndroidCallAudioState {
  AndroidCallAudioState({
    required this.active,
    required this.muted,
    required this.route,
    required List<CallAudioOutputRoute> availableRoutes,
  }) : availableRoutes = List<CallAudioOutputRoute>.unmodifiable(
         availableRoutes,
       );

  final bool active;
  final bool muted;
  final CallAudioOutputRoute route;
  final List<CallAudioOutputRoute> availableRoutes;
}

/// Reconciles one bounded Android pre-start record into the process-owned
/// coordinator. Native owns presentation and Telecom audio mechanics only;
/// this adapter never owns product call state.
/// Optional signal that a native lifecycle adapter failed closed. The graph
/// forwards it as a callability invalidation so the composition withdraws
/// and rebuilds a fresh adapter on the next resume.
abstract interface class NativeCallLifecycleInvalidations {
  Stream<void> get invalidations;
}

final class AndroidCallLifecycleAdapter
    implements
        NativeCallLifecycleInvalidations,
        NativeCallLifecycleAdapter,
        IncomingCallPresenter,
        CallForegroundAudioSession,
        CallAudioRoutePort {
  AndroidCallLifecycleAdapter({
    required AndroidCallMethodInvoker invokeMethod,
    required Stream<Object?> nativeEvents,
    required CallCoordinator coordinator,
    required AuthenticatedCallHandleResolver resolveAuthenticatedHandle,
    DateTime Function()? clock,
    this.maxEventsPerBatch = 32,
    NativeCallStateProjector? projectState,
    this.projectTerminalBeforeEnd = false,
    this.requireAdoptionForAudio = false,
    this.failStartOnAttachError = false,
    NativeOutgoingRegistrationResultObserver? onOutgoingRegistrationResult,
  }) : _invokeMethod = invokeMethod,
       _nativeEvents = nativeEvents,
       _coordinator = coordinator,
       _resolveAuthenticatedHandle = resolveAuthenticatedHandle,
       _clock = clock ?? _systemClock,
       _projectState = projectState ?? _defaultProjectedState,
       _onOutgoingRegistrationResult = onOutgoingRegistrationResult {
    if (maxEventsPerBatch <= 0 || maxEventsPerBatch > 256) {
      throw ArgumentError.value(
        maxEventsPerBatch,
        'maxEventsPerBatch',
        'must be 1..256',
      );
    }
  }

  static const int protocolVersion = 1;
  static const String methodChannelName = 'mknoon/android_call_lifecycle';
  static const String eventChannelName = 'mknoon/android_call_lifecycle/events';
  static const int maxRetiredCallFences = 16;
  static const Duration outgoingRegistrationTtl = Duration(seconds: 45);
  static const Duration _failClosedTimeout = Duration(seconds: 2);
  static const String _failClosedEventId =
      '00000000-0000-4000-8000-000000000001';

  final AndroidCallMethodInvoker _invokeMethod;
  final Stream<Object?> _nativeEvents;
  final CallCoordinator _coordinator;
  final AuthenticatedCallHandleResolver _resolveAuthenticatedHandle;
  final DateTime Function() _clock;
  final int maxEventsPerBatch;
  final NativeCallStateProjector _projectState;
  final bool projectTerminalBeforeEnd;
  final bool requireAdoptionForAudio;
  final bool failStartOnAttachError;
  final NativeOutgoingRegistrationResultObserver? _onOutgoingRegistrationResult;

  final StreamController<CallAudioSessionInterruption> _interruptions =
      StreamController<CallAudioSessionInterruption>.broadcast(sync: true);
  final StreamController<void> _invalidations = StreamController<void>.broadcast(
    sync: true,
  );
  final StreamController<bool> _muteChanges = StreamController<bool>.broadcast(
    sync: true,
  );
  final Map<int, _NativeEvent> _events = <int, _NativeEvent>{};
  final Map<int, _NativeEvent> _observedEvents = <int, _NativeEvent>{};
  final Map<String, int> _eventIds = <String, int>{};
  final Set<String> _endedHandles = <String>{};
  final Map<String, int> _retiredHighWatermarks = <String, int>{};

  StreamSubscription<Object?>? _nativeSubscription;
  StreamSubscription<CallSessionSnapshot>? _snapshotSubscription;
  Future<void> _tail = Future<void>.value();
  Future<void> _audioCommandTail = Future<void>.value();
  Future<void>? _startFuture;
  Future<void>? _closeFuture;
  Future<void>? _invalidationFuture;
  _NativeDescriptor? _descriptor;
  CallId? _boundCallId;
  String? _boundHandle;
  int _bindingGeneration = 0;
  int _highestObservedSequence = 0;
  int _acknowledgedSequence = 0;
  bool _invalid = false;
  bool _adoptionAcknowledgementPending = false;
  bool _ownsSession = false;
  bool _closed = false;
  CallAudioOutputRoute _selectedRoute = CallAudioOutputRoute.systemDefault;
  List<CallAudioOutputRoute> _availableRoutes = const <CallAudioOutputRoute>[];
  bool? _lastPublishedMuted;
  AndroidNativeMuteApplier? _nativeMuteApplier;
  int? _failedMuteSequence;

  @override
  Stream<CallAudioSessionInterruption> get interruptions =>
      _interruptions.stream;

  /// Emits only authoritative, coarse native mute changes. Native event
  /// payloads and call authority never cross this boundary.
  Stream<bool> get muteChanges => _muteChanges.stream;

  /// Installs the one application-owned bridge from authoritative Telecom
  /// mute state to the existing call-scoped audio controller. A `false`
  /// result means that the media bundle is not ready yet; throwing means that
  /// applying the requested privacy state failed and the call must end.
  @override
  void bindNativeMuteApplier(AndroidNativeMuteApplier applier) {
    if (_startFuture != null || _nativeMuteApplier != null) {
      throw StateError('native mute applier already bound');
    }
    _nativeMuteApplier = applier;
  }

  /// Retries an ordered native event after the exact call's media bundle
  /// becomes available. This does not create media or mutate call state.
  @override
  void notifyNativeMuteTargetReady(CallId callId) {
    if (_closed || _invalid || callId != _boundCallId) return;
    unawaited(
      _schedule<void>(() async {
        if (_closed || _invalid || callId != _boundCallId) return;
        await _reconcileBoundEvents();
      }),
    );
  }

  @override
  bool get ownsSession => _ownsSession;

  @override
  CallAudioOutputRoute get selectedRoute => _selectedRoute;

  /// True only while this adapter owns the exact native lifecycle used by the
  /// coordinator call. Call state remains coordinator-owned.
  @override
  bool isBoundTo(CallId callId) =>
      !_closed && !_invalid && _boundCallId == callId && _boundHandle != null;

  @override
  Future<void> start() => _startFuture ??= _startOnce();

  Future<void> _startOnce() async {
    if (_closed) {
      throw const AndroidCallLifecycleException(
        AndroidCallLifecycleErrorCode.closed,
      );
    }
    // Listen first so an event emitted while attach is executing cannot be
    // lost between native replay and Dart registration.
    _nativeSubscription = _nativeEvents.listen(
      _onNativeValue,
      onError: (Object _) => _queueInvalidation(),
    );
    _snapshotSubscription = _coordinator.snapshots.listen(
      _onSnapshot,
      onError: (Object _) => _queueInvalidation(),
    );
    final capabilityEnabled = await _invokeBoolean(
      'setCapabilityEnabled',
      const <String, Object?>{'version': protocolVersion, 'enabled': true},
    );
    if (_closed) return;
    if (!capabilityEnabled) {
      await _schedule<void>(() async => _invalidate());
      throw const AndroidCallLifecycleException(
        AndroidCallLifecycleErrorCode.nativeFailure,
      );
    }
    try {
      final attached = await _invokeMethod('attach', _versionArguments());
      await _schedule<void>(() async {
        if (_closed || _invalid) return;
        _ingest(attached);
      });
    } catch (error) {
      await _schedule<void>(() async => _invalidate());
      if (failStartOnAttachError) {
        throw AndroidCallLifecycleException(
          error is FormatException
              ? AndroidCallLifecycleErrorCode.malformedResponse
              : AndroidCallLifecycleErrorCode.nativeFailure,
        );
      }
    }
  }

  @override
  Future<bool> present(IncomingCallPresentation presentation) async {
    await start();
    return _schedule<bool>(() => _presentNow(presentation));
  }

  /// Retries only the prior bound call's canonical cleanup, then gives its
  /// retained native terminal one literal ACK opportunity. Production invokes
  /// this before [CallCoordinator.placeCall], where awaiting the coordinator
  /// tail is safe. Refused cleanup or native ACK retains the complete binding
  /// and journal for a later bounded attempt.
  @override
  Future<bool> reconcileBeforeOutgoing() async {
    await start();
    return _schedule<bool>(_reconcileBeforeOutgoingNow);
  }

  Future<bool> _reconcileBeforeOutgoingNow() async {
    if (_closed) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.preflight,
        NativeOutgoingRegistrationReason.closed,
      );
    }
    if (_invalid) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.preflight,
        NativeOutgoingRegistrationReason.invalidLatched,
      );
    }
    final terminal = _pendingTerminal;
    if (terminal == null) return true;
    final priorCallId = _boundCallId;
    if (priorCallId == null) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.terminalReplay,
        NativeOutgoingRegistrationReason.terminalCleanupPending,
      );
    }

    var cleanupReady = _coordinator.terminalCleanupAckReady(priorCallId);
    if (!cleanupReady) {
      try {
        cleanupReady = await _coordinator.retryTerminalCleanup(priorCallId);
      } catch (_) {
        cleanupReady = false;
      }
    }
    if (!cleanupReady) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.terminalReplay,
        NativeOutgoingRegistrationReason.terminalCleanupPending,
      );
    }
    if (_boundCallId != priorCallId || !identical(_pendingTerminal, terminal)) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.terminalReplay,
        NativeOutgoingRegistrationReason.terminalPending,
      );
    }
    if (!await _acknowledge(
      _highestObservedSequence,
      _AcknowledgementDisposition.terminal,
    )) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.terminalReplay,
        NativeOutgoingRegistrationReason.terminalPending,
      );
    }
    _emitOutgoingRegistrationResult(
      NativeOutgoingRegistrationStage.terminalReplay,
      NativeOutgoingRegistrationStatus.success,
      NativeOutgoingRegistrationReason.none,
    );
    return true;
  }

  /// Registers one authenticated outgoing call with Telecom before the
  /// existing VC2-03 media path is allowed to activate audio.
  @override
  Future<bool> registerOutgoing(
    CallId callId, {
    required DateTime expiresAt,
  }) async {
    await start();
    final registered = await _schedule<bool>(
      () => _registerOutgoingNow(callId, expiresAt.toUtc()),
    );
    if (!registered) return false;

    // Native emits the durable presented replay while the registration method
    // is still executing. That event is serialized behind the current tail,
    // so waiting for adoption from inside [_registerOutgoingNow] would
    // deadlock. Enqueuing this barrier only after registration lets that replay
    // ingest and ACK first, while preventing signaling from observing success
    // until the exact outgoing descriptor is durably adopted.
    return _schedule<bool>(() => _completeOutgoingRegistration(callId));
  }

  Future<bool> _completeOutgoingRegistration(CallId callId) async {
    if (_closed) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.adoptionCompletion,
        NativeOutgoingRegistrationReason.closed,
      );
    }
    if (_invalid) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.adoptionCompletion,
        NativeOutgoingRegistrationReason.invalidLatched,
      );
    }
    if (!_outgoingAdoptionComplete(callId)) {
      try {
        final replay = await _invokeMethod(
          'attach',
          _versionArguments(),
        ).timeout(_failClosedTimeout);
        if (!_closed && !_invalid && _boundCallId == callId) {
          _ingest(replay);
          await _reconcileBoundEvents();
        }
      } catch (_) {
        _emitOutgoingRegistrationResult(
          NativeOutgoingRegistrationStage.adoptionCompletion,
          NativeOutgoingRegistrationStatus.error,
          NativeOutgoingRegistrationReason.adoptionReconciliationFailed,
        );
        await _invalidate();
        return false;
      }
    }
    if (_closed) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.adoptionCompletion,
        NativeOutgoingRegistrationReason.closed,
      );
    }
    if (_invalid) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.adoptionCompletion,
        NativeOutgoingRegistrationReason.invalidLatched,
      );
    }
    if (!_outgoingAdoptionComplete(callId)) {
      _emitOutgoingRegistrationResult(
        NativeOutgoingRegistrationStage.adoptionCompletion,
        NativeOutgoingRegistrationStatus.rejected,
        NativeOutgoingRegistrationReason.adoptionIncomplete,
      );
      await _invalidate();
      return false;
    }
    _emitOutgoingRegistrationResult(
      NativeOutgoingRegistrationStage.adoptionCompletion,
      NativeOutgoingRegistrationStatus.success,
      NativeOutgoingRegistrationReason.none,
    );
    return true;
  }

  bool _outgoingAdoptionComplete(CallId callId) {
    final descriptor = _descriptor;
    return _boundCallId == callId &&
        _validHandle(_boundHandle) &&
        descriptor != null &&
        descriptor.callHandle == _boundHandle &&
        descriptor.direction == _NativeCallDirection.outgoing &&
        descriptor.presented &&
        descriptor.phase == _NativeDescriptorPhase.journal &&
        !_adoptionAcknowledgementPending;
  }

  Future<bool> _registerOutgoingNow(CallId callId, DateTime expiresAt) async {
    final active = _coordinator.activeSession;
    if (_closed) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.preflight,
        NativeOutgoingRegistrationReason.closed,
      );
    }
    if (_invalid) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.preflight,
        NativeOutgoingRegistrationReason.invalidLatched,
      );
    }
    if (!_clock().isBefore(expiresAt)) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.preflight,
        NativeOutgoingRegistrationReason.expired,
      );
    }
    if (active?.callId != callId ||
        active?.direction != CallDirection.outgoing ||
        active?.isTerminal != false) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.preflight,
        NativeOutgoingRegistrationReason.sessionMismatch,
      );
    }
    if (_pendingTerminal != null) {
      if (!await _retryRetainedTerminalBeforeOutgoing()) return false;
      final resumed = _coordinator.activeSession;
      if (resumed?.callId != callId ||
          resumed?.direction != CallDirection.outgoing ||
          resumed?.isTerminal != false) {
        return _outgoingRegistrationRejected(
          NativeOutgoingRegistrationStage.preflight,
          NativeOutgoingRegistrationReason.sessionMismatch,
        );
      }
    }
    String? handle;
    try {
      handle = _resolveAuthenticatedHandle(callId);
    } catch (_) {
      _emitOutgoingRegistrationResult(
        NativeOutgoingRegistrationStage.handleResolution,
        NativeOutgoingRegistrationStatus.error,
        NativeOutgoingRegistrationReason.handleResolutionFailed,
      );
      rethrow;
    }
    if (!_validHandle(handle)) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.handleResolution,
        NativeOutgoingRegistrationReason.invalidHandle,
      );
    }
    final descriptor = _descriptor;
    if (descriptor != null) {
      if (descriptor.callHandle != handle ||
          descriptor.direction != _NativeCallDirection.outgoing ||
          (descriptor.phase == _NativeDescriptorPhase.preStart &&
              !_clock().isBefore(descriptor.expiresAt))) {
        return _outgoingRegistrationRejected(
          NativeOutgoingRegistrationStage.descriptorValidation,
          NativeOutgoingRegistrationReason.descriptorConflict,
        );
      }
      if (!_bind(callId, handle!)) {
        _emitOutgoingRegistrationResult(
          NativeOutgoingRegistrationStage.binding,
          NativeOutgoingRegistrationStatus.rejected,
          NativeOutgoingRegistrationReason.bindingConflict,
        );
        await _invalidate();
        return false;
      }
      final terminal = _pendingTerminal;
      if (terminal != null) {
        late final bool dispatched;
        try {
          dispatched = await _dispatch(terminal);
        } catch (_) {
          _emitOutgoingRegistrationResult(
            NativeOutgoingRegistrationStage.terminalReplay,
            NativeOutgoingRegistrationStatus.error,
            NativeOutgoingRegistrationReason.terminalDispatchFailed,
          );
          rethrow;
        }
        if (!dispatched) {
          return _outgoingRegistrationRejected(
            NativeOutgoingRegistrationStage.terminalReplay,
            NativeOutgoingRegistrationReason.terminalDispatchRejected,
          );
        }
        await _acknowledge(
          _highestObservedSequence,
          _AcknowledgementDisposition.terminal,
        );
        return _outgoingRegistrationRejected(
          NativeOutgoingRegistrationStage.terminalReplay,
          NativeOutgoingRegistrationReason.terminalPending,
        );
      }
      if (descriptor.presented) {
        Object? adopted;
        try {
          adopted = await _invokeMethod('adopt', _handleArguments(handle));
        } catch (_) {
          _emitOutgoingRegistrationResult(
            NativeOutgoingRegistrationStage.adoption,
            NativeOutgoingRegistrationStatus.error,
            NativeOutgoingRegistrationReason.adoptionInvocationFailed,
          );
          await _invalidate();
          return false;
        }
        if (adopted != true) {
          _emitOutgoingRegistrationResult(
            NativeOutgoingRegistrationStage.adoption,
            NativeOutgoingRegistrationStatus.rejected,
            NativeOutgoingRegistrationReason.adoptionRejected,
          );
          await _invalidate();
          return false;
        }
        _adoptionAcknowledgementPending = true;
        if (!await _ackPresentedPrefix(_AcknowledgementDisposition.adopted)) {
          _emitOutgoingRegistrationResult(
            NativeOutgoingRegistrationStage.adoption,
            NativeOutgoingRegistrationStatus.rejected,
            NativeOutgoingRegistrationReason.adoptionAcknowledgementRejected,
          );
          await _invalidate();
          return false;
        }
        _adoptionAcknowledgementPending = false;
        try {
          await _reconcileBoundEvents();
        } catch (_) {
          _emitOutgoingRegistrationResult(
            NativeOutgoingRegistrationStage.adoption,
            NativeOutgoingRegistrationStatus.error,
            NativeOutgoingRegistrationReason.adoptionReconciliationFailed,
          );
          rethrow;
        }
        return true;
      }
    }
    if (!_bind(callId, handle!)) {
      _emitOutgoingRegistrationResult(
        NativeOutgoingRegistrationStage.binding,
        NativeOutgoingRegistrationStatus.rejected,
        NativeOutgoingRegistrationReason.bindingConflict,
      );
      await _invalidate();
      return false;
    }
    _adoptionAcknowledgementPending = true;
    Object? registered;
    try {
      registered = await _invokeMethod(
        'registerOutgoingAuthenticated',
        <String, Object?>{
          ..._handleArguments(handle),
          'expiresAtMs': expiresAt.millisecondsSinceEpoch,
        },
      );
    } catch (_) {
      _adoptionAcknowledgementPending = false;
      _clearProvisionalOutgoingBinding();
      _emitOutgoingRegistrationResult(
        NativeOutgoingRegistrationStage.nativeRegistration,
        NativeOutgoingRegistrationStatus.error,
        NativeOutgoingRegistrationReason.nativeInvocationFailed,
      );
      return false;
    }
    if (registered == true) return true;
    _adoptionAcknowledgementPending = false;
    _clearProvisionalOutgoingBinding();
    return _outgoingRegistrationRejected(
      NativeOutgoingRegistrationStage.nativeRegistration,
      NativeOutgoingRegistrationReason.nativeRejected,
    );
  }

  /// Gives one already-ingested terminal from the prior call a single exact
  /// ACK opportunity before validating a distinct outgoing descriptor. This
  /// method can run inside the coordinator's effect tail, so it must never
  /// enqueue and await a nested coordinator dispatch. Only an exact prior call
  /// whose critical cleanup is already ACK-ready may reach native ACK. A live
  /// nonterminal descriptor remains a hard conflict, while pending cleanup or
  /// a refused ACK retains the complete terminal replay for a later attempt.
  Future<bool> _retryRetainedTerminalBeforeOutgoing() async {
    final terminal = _pendingTerminal;
    if (terminal == null) return true;
    final priorCallId = _boundCallId;
    if (priorCallId == null ||
        !_coordinator.terminalCleanupAckReady(priorCallId)) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.terminalReplay,
        NativeOutgoingRegistrationReason.terminalCleanupPending,
      );
    }
    if (!await _acknowledge(
      _highestObservedSequence,
      _AcknowledgementDisposition.terminal,
    )) {
      return _outgoingRegistrationRejected(
        NativeOutgoingRegistrationStage.terminalReplay,
        NativeOutgoingRegistrationReason.terminalPending,
      );
    }
    return true;
  }

  /// Releases a distinct prior call only after its critical cleanup is
  /// already safe to acknowledge. A refused ACK keeps the complete terminal
  /// binding intact so the new incoming descriptor cannot overwrite it.
  Future<bool> _ackCleanupReadyRetainedTerminal() async {
    final terminal = _pendingTerminal;
    if (terminal == null) return true;
    final priorCallId = _boundCallId;
    if (priorCallId == null ||
        !_coordinator.terminalCleanupAckReady(priorCallId)) {
      return false;
    }
    if (_boundCallId != priorCallId || !identical(_pendingTerminal, terminal)) {
      return false;
    }
    return _acknowledge(
      _highestObservedSequence,
      _AcknowledgementDisposition.terminal,
    );
  }

  void _clearProvisionalOutgoingBinding() {
    if (_descriptor == null && _events.isEmpty) {
      _boundCallId = null;
      _boundHandle = null;
    }
  }

  bool _outgoingRegistrationRejected(
    NativeOutgoingRegistrationStage stage,
    NativeOutgoingRegistrationReason reason,
  ) {
    _emitOutgoingRegistrationResult(
      stage,
      NativeOutgoingRegistrationStatus.rejected,
      reason,
    );
    return false;
  }

  void _emitOutgoingRegistrationResult(
    NativeOutgoingRegistrationStage stage,
    NativeOutgoingRegistrationStatus status,
    NativeOutgoingRegistrationReason reason,
  ) {
    try {
      _onOutgoingRegistrationResult?.call(stage, status, reason);
    } catch (_) {
      // Identifier-free diagnostics cannot change native call authority.
    }
  }

  Future<bool> _presentNow(IncomingCallPresentation presentation) async {
    if (_closed || _invalid || !_clock().isBefore(presentation.expiresAt)) {
      return false;
    }
    final handle = _resolveAuthenticatedHandle(presentation.callId);
    if (!_validHandle(handle)) return false;

    var descriptor = _descriptor;
    if (descriptor != null &&
        descriptor.callHandle != handle &&
        _pendingTerminal != null) {
      if (!await _ackCleanupReadyRetainedTerminal()) return false;
      descriptor = _descriptor;
    }
    if (descriptor != null) {
      if (descriptor.callHandle != handle ||
          descriptor.direction != _NativeCallDirection.incoming ||
          (descriptor.phase == _NativeDescriptorPhase.preStart &&
              !_clock().isBefore(descriptor.expiresAt))) {
        return false;
      }
      if (!_bind(presentation.callId, handle!)) {
        await _invalidate();
        return false;
      }
      final terminal = _pendingTerminal;
      if (terminal != null) {
        final dispatched = await _dispatch(terminal);
        if (!dispatched) return false;
        await _acknowledge(
          _highestObservedSequence,
          _AcknowledgementDisposition.terminal,
        );
        return false;
      }

      if (descriptor.presented) {
        final adopted = await _invokeBoolean('adopt', _handleArguments(handle));
        if (!adopted) return false;
        _adoptionAcknowledgementPending = true;
        if (await _ackPresentedPrefix(_AcknowledgementDisposition.adopted)) {
          _adoptionAcknowledgementPending = false;
          await _reconcileBoundEvents();
        }
        return true;
      }
    }

    if (!_bind(presentation.callId, handle!)) {
      await _invalidate();
      return false;
    }
    _adoptionAcknowledgementPending = true;
    final presented =
        await _invokeBoolean('presentAuthenticated', <String, Object?>{
          ..._handleArguments(handle),
          'expiresAtMs': presentation.expiresAt.millisecondsSinceEpoch,
        });
    if (!presented) _adoptionAcknowledgementPending = false;
    return presented;
  }

  @override
  Future<void> dismiss(IncomingCallPresentation presentation) async {
    await start();
    await _schedule<void>(() async {
      if (_closed) return;
      final handle = _handleFor(presentation.callId);
      if (!_validHandle(handle)) return;
      await _endNativeHandle(handle!, retainFailureFence: false);
    });
  }

  Future<AndroidCallAudioState> readAudioState() async {
    await start();
    final handle = _requireBoundHandle();
    return _scheduleExactHandleAudioStateRead(
      handle: handle,
      bindingGeneration: _bindingGeneration,
    );
  }

  Future<void> requestRoute(CallAudioOutputRoute route) async {
    await start();
    if (_releaseRetainedTerminalAudio(route: route)) return;
    await _schedule<void>(() async {
      if (_releaseRetainedTerminalAudio(route: route)) return;
      final handle = _requireBoundHandle();
      if (!_availableRoutes.contains(route)) {
        await _readAudioStateNow(handle);
      }
      if (!_availableRoutes.contains(route)) {
        throw const CallAudioRouteException(
          CallAudioRouteErrorCode.unsupported,
        );
      }
      try {
        final selected = await _invokeMethod('requestRoute', <String, Object?>{
          ..._handleArguments(handle),
          'route': _routeWireName(route),
        });
        if (selected != true) {
          throw const CallAudioRouteException(
            CallAudioRouteErrorCode.selectionFailed,
          );
        }
      } on CallAudioRouteException {
        rethrow;
      } catch (_) {
        throw const CallAudioRouteException(
          CallAudioRouteErrorCode.selectionFailed,
        );
      }
      _selectedRoute = route;
    });
  }

  /// iOS in-app Answer: CallKit must perform the answer so its audio session
  /// activates; the native `answerRequested` event then drives the accept.
  /// Returns false when this call is not the bound native call, so the
  /// caller can fall back to a direct Dart answer.
  Future<bool> answerNatively(CallId callId) async {
    await start();
    final handle = _boundHandle;
    if (handle == null || _invalid || callId != _boundCallId) return false;
    try {
      return await _invokeMethod('answer', _handleArguments(handle)) == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> activateAudio() async {
    await start();
    final handle = _requireBoundHandle();
    await _scheduleExactHandleAudioCommand(
      method: 'activateAudio',
      handle: handle,
      bindingGeneration: _bindingGeneration,
      ownsSessionAfterSuccess: true,
    );
  }

  Future<void> deactivateAudio() async {
    await start();
    if (_releaseRetainedTerminalAudio()) return;
    final handle = _boundHandle;
    if (handle == null) return;
    await _scheduleExactHandleAudioCommand(
      method: 'deactivateAudio',
      handle: handle,
      bindingGeneration: _bindingGeneration,
      ownsSessionAfterSuccess: false,
    );
  }

  /// Native termination already releases platform audio and restores its
  /// default route. Media cleanup can be invoked while the exact terminal is
  /// being reconciled on [_tail], so queueing these idempotent release commands
  /// back onto that lane would self-wait until cleanup times out. No live call
  /// or non-default route is accepted by this terminal-only seam.
  bool _releaseRetainedTerminalAudio({CallAudioOutputRoute? route}) {
    if (_closed ||
        _invalid ||
        _boundCallId == null ||
        _boundHandle == null ||
        _pendingTerminal == null ||
        (route != null && route != CallAudioOutputRoute.systemDefault)) {
      return false;
    }
    _ownsSession = false;
    _selectedRoute = CallAudioOutputRoute.systemDefault;
    return true;
  }

  /// Runs CallKit/Telecom audio operations outside the ordered journal lane.
  ///
  /// A native answer is reconciled inside [_tail]. Its coordinator effect can
  /// synchronously create media, whose audio controller calls [activateAudio]
  /// and reads supported routes. Enqueuing either operation back onto [_tail]
  /// would make answer wait for media while media waits for answer. This
  /// exact-handle lane preserves operation ordering without allowing a later
  /// call binding to satisfy an earlier operation.
  Future<AndroidCallAudioState> _scheduleExactHandleAudioStateRead({
    required String handle,
    required int bindingGeneration,
  }) {
    final completer = Completer<AndroidCallAudioState>();
    _audioCommandTail = _audioCommandTail.then<void>((_) async {
      try {
        _throwIfAudioCommandFenced(
          handle: handle,
          bindingGeneration: bindingGeneration,
        );
        final state = await _fetchAudioStateNow(handle);
        _throwIfAudioCommandFenced(
          handle: handle,
          bindingGeneration: bindingGeneration,
        );
        _acceptAudioState(state);
        completer.complete(state);
      } on AndroidCallLifecycleException catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } catch (_, stackTrace) {
        completer.completeError(
          const AndroidCallLifecycleException(
            AndroidCallLifecycleErrorCode.nativeFailure,
          ),
          stackTrace,
        );
      }
    });
    return completer.future;
  }

  void _throwIfAudioCommandFenced({
    required String handle,
    required int bindingGeneration,
  }) {
    if (_closed) {
      throw const AndroidCallLifecycleException(
        AndroidCallLifecycleErrorCode.closed,
      );
    }
    if (_invalid ||
        _boundHandle != handle ||
        _bindingGeneration != bindingGeneration ||
        (requireAdoptionForAudio && _adoptionAcknowledgementPending)) {
      throw const AndroidCallLifecycleException(
        AndroidCallLifecycleErrorCode.unavailable,
      );
    }
  }

  Future<void> _scheduleExactHandleAudioCommand({
    required String method,
    required String handle,
    required int bindingGeneration,
    required bool ownsSessionAfterSuccess,
  }) {
    final completer = Completer<void>();
    _audioCommandTail = _audioCommandTail.then<void>((_) async {
      try {
        _throwIfAudioCommandFenced(
          handle: handle,
          bindingGeneration: bindingGeneration,
        );
        final result = await _invokeMethod(method, _handleArguments(handle));
        if (result != true) {
          throw const AndroidCallLifecycleException(
            AndroidCallLifecycleErrorCode.nativeFailure,
          );
        }
        try {
          _throwIfAudioCommandFenced(
            handle: handle,
            bindingGeneration: bindingGeneration,
          );
        } on AndroidCallLifecycleException {
          if (method == 'activateAudio' &&
              (_closed || _invalid || _boundHandle != handle)) {
            try {
              await _invokeMethod('deactivateAudio', _handleArguments(handle));
            } catch (_) {
              // The stale command is already fenced locally.
            }
          }
          rethrow;
        }
        _ownsSession = ownsSessionAfterSuccess;
        completer.complete();
      } on AndroidCallLifecycleException catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } catch (_, stackTrace) {
        completer.completeError(
          const AndroidCallLifecycleException(
            AndroidCallLifecycleErrorCode.nativeFailure,
          ),
          stackTrace,
        );
      }
    });
    return completer.future;
  }

  @override
  Future<void> activate() => activateAudio();

  @override
  Future<void> deactivate() => deactivateAudio();

  @override
  Future<List<CallAudioOutputRoute>> supportedOutputRoutes() async =>
      (await readAudioState()).availableRoutes;

  @override
  Future<void> selectOutputRoute(CallAudioOutputRoute route) =>
      requestRoute(route);

  void _onNativeValue(Object? value) {
    if (_closed) return;
    unawaited(
      _schedule<void>(() async {
        if (_closed || _invalid) return;
        try {
          _ingest(value);
          await _reconcileBoundEvents();
        } catch (_) {
          await _invalidate();
        }
      }),
    );
  }

  void _onSnapshot(CallSessionSnapshot snapshot) {
    if (_closed) return;
    unawaited(
      _schedule<void>(() async {
        final callId = snapshot.callId;
        if (_closed || _invalid || callId == null || callId != _boundCallId) {
          return;
        }
        if (snapshot.isTerminal) {
          var nativeTerminalCommitted =
              projectTerminalBeforeEnd && await _project(snapshot);
          if (!nativeTerminalCommitted) {
            nativeTerminalCommitted = await _endCanonicalTerminal();
          }
          if (nativeTerminalCommitted && _pendingTerminal == null) {
            await _replayCommittedNativeTerminal(callId);
          }
        } else {
          await _project(snapshot);
        }
        await _reconcileBoundEvents();
      }),
    );
  }

  /// A native terminal method commits its journal entry before returning, but
  /// the EventChannel delivery can be queued behind this snapshot task. Read
  /// the non-consuming native replay now so the exact terminal sequence is
  /// dispatched and ACKed before a later call can observe the old binding.
  Future<void> _replayCommittedNativeTerminal(CallId callId) async {
    if (_closed || _invalid || _boundCallId != callId) return;
    Object? replay;
    try {
      replay = await _invokeMethod('attach', _versionArguments());
      _ingest(replay);
    } catch (_) {
      await _invalidate();
      return;
    }
  }

  Future<bool> _endCanonicalTerminal() async {
    final handle = _boundHandle;
    if (handle == null) return false;
    final ended = await _endNativeHandle(handle, retainFailureFence: true);
    if (!ended) await _invalidate();
    return ended;
  }

  Future<bool> _endNativeHandle(
    String handle, {
    required bool retainFailureFence,
  }) async {
    if (!_endedHandles.add(handle)) return true;
    try {
      final ended =
          await _invokeMethod('end', _handleArguments(handle)) == true;
      if (!ended && !retainFailureFence) _endedHandles.remove(handle);
      return ended;
    } catch (_) {
      if (!retainFailureFence) _endedHandles.remove(handle);
      return false;
    }
  }

  Future<bool> _project(CallSessionSnapshot snapshot) async {
    final handle = _boundHandle;
    if (handle == null) return false;
    try {
      final state = _projectState(snapshot);
      return await _invokeMethod('project', <String, Object?>{
            ..._handleArguments(handle),
            'state': state,
          }) ==
          true;
    } catch (_) {
      // Projection cannot mutate or fail the coordinator-owned state.
      return false;
    }
  }

  Future<void> _reconcileBoundEvents() async {
    if (_boundCallId == null) return;
    final terminal = _pendingTerminal;
    if (terminal != null) {
      if (await _dispatch(terminal)) {
        await _acknowledge(
          _highestObservedSequence,
          _AcknowledgementDisposition.terminal,
        );
      }
      return;
    }
    await _drainConsumableEvents(
      ringing: _coordinator.activeSession?.state == CallState.ringing,
    );
  }

  Future<void> _drainConsumableEvents({required bool ringing}) async {
    while (true) {
      final event = _events[_acknowledgedSequence + 1];
      if (event == null) return;
      switch (event.type) {
        case _NativeEventType.presented:
          final disposition = _adoptionAcknowledgementPending
              ? _AcknowledgementDisposition.adopted
              : _AcknowledgementDisposition.none;
          if (!await _acknowledge(event.sequence, disposition)) return;
          _adoptionAcknowledgementPending = false;
        case _NativeEventType.answer:
          if (!ringing) return;
          if (!await _dispatch(event)) return;
          await _acknowledge(event.sequence, _AcknowledgementDisposition.none);
          return;
        case _NativeEventType.decline:
        case _NativeEventType.end:
        case _NativeEventType.remoteCancelled:
        case _NativeEventType.expired:
        case _NativeEventType.providerRemoved:
        case _NativeEventType.nativeFailure:
          if (!await _dispatch(event)) return;
          await _acknowledge(
            _highestObservedSequence,
            _AcknowledgementDisposition.terminal,
          );
          return;
        case _NativeEventType.muteChanged:
          try {
            final state = await _readAudioStateNow(_requireBoundHandle());
            final applier = _nativeMuteApplier;
            final callId = _boundCallId;
            if (applier == null || callId == null) return;
            final applied = await applier(callId, state.muted);
            if (!applied) return;
            _publishNativeMute(state.muted);
          } catch (_) {
            await _failClosedNativeMute(event);
            return;
          }
          if (!await _acknowledge(
            event.sequence,
            _AcknowledgementDisposition.none,
          )) {
            return;
          }
        case _NativeEventType.routeChanged:
          try {
            await _readAudioStateNow(_requireBoundHandle());
          } catch (_) {
            return;
          }
          if (!await _acknowledge(
            event.sequence,
            _AcknowledgementDisposition.none,
          )) {
            return;
          }
        case _NativeEventType.audioActivated:
        case _NativeEventType.audioDeactivated:
          try {
            await _readAudioStateNow(
              _requireBoundHandle(),
              publishNativeActiveChange: true,
            );
          } catch (_) {
            return;
          }
          if (!await _acknowledge(
            event.sequence,
            _AcknowledgementDisposition.none,
          )) {
            return;
          }
      }
    }
  }

  Future<void> _failClosedNativeMute(_NativeEvent event) async {
    if (_failedMuteSequence == event.sequence) return;
    _failedMuteSequence = event.sequence;
    final handle = _boundHandle;
    if (handle == null) return;
    final nativeEnd = _endNativeHandle(handle, retainFailureFence: true);
    await _dispatch(event, actionOverride: CallNativeAction.end);
    await nativeEnd;
  }

  Future<bool> _dispatch(
    _NativeEvent event, {
    CallNativeAction? actionOverride,
  }) async {
    final callId = _boundCallId;
    if (callId == null) return false;
    final activeSnapshot = _coordinator.activeSession;
    final action =
        actionOverride ??
        switch (event.type) {
          _NativeEventType.answer => CallNativeAction.answer,
          _NativeEventType.decline => CallNativeAction.decline,
          _NativeEventType.end => CallNativeAction.end,
          _NativeEventType.remoteCancelled ||
          _NativeEventType.expired ||
          _NativeEventType.providerRemoved ||
          _NativeEventType.nativeFailure => CallNativeAction.end,
          _NativeEventType.presented ||
          _NativeEventType.muteChanged ||
          _NativeEventType.routeChanged ||
          _NativeEventType.audioActivated ||
          _NativeEventType.audioDeactivated => null,
        };
    if (action == null) return true;
    final endReason = actionOverride != null
        ? null
        : switch (event.type) {
            _NativeEventType.remoteCancelled =>
              activeSnapshot?.connectedAt == null
                  ? CallEndReason.callerCancelled
                  : CallEndReason.remoteHangup,
            _NativeEventType.expired => CallEndReason.expired,
            _NativeEventType.providerRemoved ||
            _NativeEventType.nativeFailure => CallEndReason.mediaFailed,
            _ => null,
          };
    try {
      final reduction = await _coordinator.dispatch(
        CallEvent(
          type: CallEventType.nativeAction,
          eventId: event.eventId,
          occurredAt: event.occurredAt,
          callId: callId,
          contactPeerId: activeSnapshot?.contactPeerId,
          nativeAction: action,
          endReason: endReason,
        ),
      );
      final accepted =
          reduction.decision == CallEventDecision.applied ||
          (reduction.decision == CallEventDecision.ignored &&
              (reduction.reason == CallReductionReason.duplicateEvent ||
                  reduction.reason == CallReductionReason.terminalDominates));
      if (!accepted || !event.type.isTerminal) return accepted;
      if (_coordinator.terminalCleanupAckReady(callId)) return true;
      if (reduction.decision == CallEventDecision.ignored) {
        return _coordinator.retryTerminalCleanup(callId);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ackPresentedPrefix(
    _AcknowledgementDisposition disposition,
  ) async {
    var through = _acknowledgedSequence;
    while (_events[through + 1]?.type == _NativeEventType.presented) {
      through++;
    }
    if (through > _acknowledgedSequence) {
      return _acknowledge(through, disposition);
    }
    return true;
  }

  Future<bool> _acknowledge(
    int through,
    _AcknowledgementDisposition disposition,
  ) async {
    if (through <= _acknowledgedSequence) return true;
    final handle = _boundHandle;
    if (handle == null) return false;
    try {
      final acknowledged = await _invokeMethod('acknowledge', <String, Object?>{
        ..._handleArguments(handle),
        'throughSequence': through,
        'disposition': disposition.wireName,
      });
      if (acknowledged != true) return false;
    } catch (_) {
      return false;
    }
    if (disposition == _AcknowledgementDisposition.adopted) {
      final descriptor = _descriptor;
      if (descriptor == null) return false;
      _descriptor = _NativeDescriptor(
        callHandle: descriptor.callHandle,
        expiresAt: descriptor.expiresAt,
        presented: descriptor.presented,
        phase: _NativeDescriptorPhase.journal,
        direction: descriptor.direction,
      );
    }
    _acknowledgedSequence = through;
    _events.removeWhere((sequence, _) => sequence <= through);
    final firstRetainedSequence = through - maxEventsPerBatch + 1;
    final discardedSequences = _observedEvents.keys
        .where((sequence) => sequence < firstRetainedSequence)
        .toList(growable: false);
    for (final sequence in discardedSequences) {
      final discarded = _observedEvents.remove(sequence);
      if (discarded != null && _eventIds[discarded.eventId] == sequence) {
        _eventIds.remove(discarded.eventId);
      }
    }
    if (disposition == _AcknowledgementDisposition.terminal) {
      final retiredHandle = _boundHandle ?? _descriptor?.callHandle;
      if (retiredHandle != null) {
        _retiredHighWatermarks.remove(retiredHandle);
        _retiredHighWatermarks[retiredHandle] = through;
        while (_retiredHighWatermarks.length > maxRetiredCallFences) {
          _retiredHighWatermarks.remove(_retiredHighWatermarks.keys.first);
        }
      }
      _resetPerCallState();
    }
    return true;
  }

  void _resetPerCallState() {
    _bindingGeneration++;
    _descriptor = null;
    _boundCallId = null;
    _boundHandle = null;
    _events.clear();
    _observedEvents.clear();
    _eventIds.clear();
    _endedHandles.clear();
    _highestObservedSequence = 0;
    _acknowledgedSequence = 0;
    _adoptionAcknowledgementPending = false;
    _ownsSession = false;
    _selectedRoute = CallAudioOutputRoute.systemDefault;
    _availableRoutes = const <CallAudioOutputRoute>[];
    _lastPublishedMuted = null;
    _failedMuteSequence = null;
  }

  void _ingest(Object? value) {
    final batch = _NativeBatch.parse(value, maxEvents: maxEventsPerBatch);
    final nativeCallId = batch.nativeCallId;
    final retiredThrough = nativeCallId == null
        ? null
        : _retiredHighWatermarks[nativeCallId];
    if (retiredThrough != null) {
      if (batch.highestSequence <= retiredThrough) return;
      throw const FormatException('event follows terminal acknowledgement');
    }
    final descriptor = batch.descriptor;
    var delayedOutgoingAdoptionReplay = false;
    if (descriptor == null &&
        batch.events.isEmpty &&
        batch.nativeCallId == null &&
        batch.highestSequence == 0 &&
        _descriptor != null) {
      // The event channel is subscribed before attach. A newer event envelope
      // may win this queue ahead of an empty attach snapshot captured just
      // before the event was persisted.
      return;
    }
    if (descriptor != null) {
      if (descriptor.phase == _NativeDescriptorPhase.preStart &&
          !_clock().isBefore(descriptor.expiresAt)) {
        throw const FormatException('expired native descriptor');
      }
      final current = _descriptor;
      // Native constructs an EventChannel envelope before posting it to the
      // main thread. A synchronous attach can therefore adopt the same record
      // first. Permit only that exact, already-acknowledged presented event;
      // every handle, expiry, direction, payload, and sequence mutation keeps
      // the existing fail-closed descriptor fence.
      delayedOutgoingAdoptionReplay =
          current != null &&
          current.callHandle == descriptor.callHandle &&
          current.expiresAt == descriptor.expiresAt &&
          current.presented &&
          descriptor.presented &&
          current.direction == _NativeCallDirection.outgoing &&
          descriptor.direction == _NativeCallDirection.outgoing &&
          current.phase == _NativeDescriptorPhase.journal &&
          descriptor.phase == _NativeDescriptorPhase.preStart &&
          batch.events.length == 1 &&
          batch.events.single.type == _NativeEventType.presented &&
          batch.events.single.sequence <= _acknowledgedSequence &&
          _observedEvents[batch.events.single.sequence] == batch.events.single;
      if (current != null &&
          current != descriptor &&
          !delayedOutgoingAdoptionReplay) {
        throw const FormatException('native descriptor changed');
      }
      final bound = _coordinator.activeSession;
      if (_boundCallId != null &&
          bound?.callId == _boundCallId &&
          ((bound?.direction == CallDirection.incoming) !=
              (descriptor.direction == _NativeCallDirection.incoming))) {
        throw const FormatException('native descriptor direction mismatch');
      }
      if (!delayedOutgoingAdoptionReplay) _descriptor = descriptor;
    }
    if (batch.events.isNotEmpty && descriptor == null && _descriptor == null) {
      throw const FormatException('event batch has no descriptor');
    }
    final expectedHandle = descriptor?.callHandle ?? _descriptor?.callHandle;
    if (batch.nativeCallId != null && batch.nativeCallId != expectedHandle) {
      throw const FormatException('native call id mismatch');
    }
    if (_highestObservedSequence == 0 && _observedEvents.isEmpty) {
      final baseline = batch.events.isEmpty
          ? batch.highestSequence
          : batch.events.first.sequence - 1;
      _acknowledgedSequence = baseline;
      _highestObservedSequence = baseline;
    }
    for (final event in batch.events) {
      if (event.callHandle != expectedHandle) {
        throw const FormatException('event handle mismatch');
      }
      final existing = _observedEvents[event.sequence];
      if (existing != null) {
        if (existing != event) {
          throw const FormatException('event sequence conflict');
        }
        continue;
      }
      if (event.sequence != _highestObservedSequence + 1) {
        throw const FormatException('non-contiguous event sequence');
      }
      final existingSequence = _eventIds[event.eventId];
      if (existingSequence != null && existingSequence != event.sequence) {
        throw const FormatException('event id conflict');
      }
      _highestObservedSequence = event.sequence;
      _observedEvents[event.sequence] = event;
      _eventIds[event.eventId] = event.sequence;
      _events[event.sequence] = event;
    }
    if (batch.highestSequence != _highestObservedSequence &&
        !delayedOutgoingAdoptionReplay) {
      throw const FormatException('native high sequence mismatch');
    }
    final terminalSequences = _events.values
        .where((event) => event.type.isTerminal)
        .map((event) => event.sequence)
        .toList(growable: false);
    if (terminalSequences.length > 1 ||
        (terminalSequences.isNotEmpty &&
            terminalSequences.single != _highestObservedSequence)) {
      throw const FormatException('terminal event must dominate batch tail');
    }
  }

  _NativeEvent? get _pendingTerminal {
    for (final event in _events.values) {
      if (event.type.isTerminal) return event;
    }
    return null;
  }

  bool _bind(CallId callId, String handle) {
    if ((_boundCallId != null && _boundCallId != callId) ||
        (_boundHandle != null && _boundHandle != handle)) {
      return false;
    }
    if (_boundCallId != callId || _boundHandle != handle) {
      _bindingGeneration++;
      _boundCallId = callId;
      _boundHandle = handle;
    }
    return true;
  }

  String? _handleFor(CallId callId) {
    if (_boundCallId == callId) return _boundHandle;
    return _resolveAuthenticatedHandle(callId);
  }

  String _requireBoundHandle() {
    if (_closed) {
      throw const AndroidCallLifecycleException(
        AndroidCallLifecycleErrorCode.closed,
      );
    }
    final handle = _boundHandle;
    if (!_validHandle(handle)) {
      throw const AndroidCallLifecycleException(
        AndroidCallLifecycleErrorCode.unavailable,
      );
    }
    return handle!;
  }

  Future<bool> _invokeBoolean(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      return await _invokeMethod(method, arguments) == true;
    } catch (_) {
      return false;
    }
  }

  Future<AndroidCallAudioState> _readAudioStateNow(
    String handle, {
    bool publishNativeActiveChange = false,
  }) async {
    final state = await _fetchAudioStateNow(handle);
    _acceptAudioState(
      state,
      publishNativeActiveChange: publishNativeActiveChange,
    );
    return state;
  }

  Future<AndroidCallAudioState> _fetchAudioStateNow(String handle) async {
    Object? value;
    try {
      value = await _invokeMethod('readAudioState', _handleArguments(handle));
    } catch (_) {
      throw const AndroidCallLifecycleException(
        AndroidCallLifecycleErrorCode.nativeFailure,
      );
    }
    return _parseAudioState(value);
  }

  void _acceptAudioState(
    AndroidCallAudioState state, {
    bool publishNativeActiveChange = false,
  }) {
    final wasActive = _ownsSession;
    _selectedRoute = state.route;
    _availableRoutes = state.availableRoutes;
    _ownsSession = state.active;
    if (publishNativeActiveChange) {
      if (wasActive != state.active && !_interruptions.isClosed) {
        _interruptions.add(
          state.active
              ? const CallAudioSessionInterruption.end()
              : const CallAudioSessionInterruption.begin(),
        );
      }
    }
  }

  void _publishNativeMute(bool muted) {
    if (_lastPublishedMuted == muted || _muteChanges.isClosed) return;
    _lastPublishedMuted = muted;
    _muteChanges.add(muted);
  }

  AndroidCallAudioState _parseAudioState(Object? value) {
    final map = _exactMap(value, const <String>{
      'version',
      'active',
      'muted',
      'route',
      'availableRoutes',
    });
    if (map['version'] != protocolVersion ||
        map['active'] is! bool ||
        map['muted'] is! bool ||
        map['route'] is! String ||
        map['availableRoutes'] is! List<Object?>) {
      throw const AndroidCallLifecycleException(
        AndroidCallLifecycleErrorCode.malformedResponse,
      );
    }
    try {
      final rawRoutes = map['availableRoutes']! as List<Object?>;
      if (rawRoutes.length > 6 || rawRoutes.any((route) => route is! String)) {
        throw const FormatException('invalid route inventory');
      }
      final availableRoutes = rawRoutes
          .cast<String>()
          .map(_parseRoute)
          .toList(growable: false);
      if (availableRoutes.toSet().length != availableRoutes.length) {
        throw const FormatException('duplicate route inventory');
      }
      return AndroidCallAudioState(
        active: map['active']! as bool,
        muted: map['muted']! as bool,
        route: _parseRoute(map['route']! as String),
        availableRoutes: availableRoutes,
      );
    } catch (_) {
      throw const AndroidCallLifecycleException(
        AndroidCallLifecycleErrorCode.malformedResponse,
      );
    }
  }

  void _queueInvalidation() {
    if (_closed) return;
    unawaited(_schedule<void>(_invalidate));
  }

  @override
  Stream<void> get invalidations => _invalidations.stream;

  Future<void> _invalidate() {
    final existing = _invalidationFuture;
    if (existing != null) return existing;
    _invalid = true;
    _bindingGeneration++;
    if (!_invalidations.isClosed) _invalidations.add(null);
    return _invalidationFuture = _invalidateOnce();
  }

  Future<void> _invalidateOnce() async {
    final callId = _boundCallId;
    final handle = _boundHandle;
    if (callId != null && handle != null) {
      final active = _coordinator.activeSession;
      if (active?.callId == callId && active?.isTerminal == false) {
        await _dispatch(
          _NativeEvent(
            callHandle: handle,
            sequence: _highestObservedSequence + 1,
            eventId: _failClosedEventId,
            type: _NativeEventType.nativeFailure,
            occurredAt: _clock(),
          ),
        );
      } else if (!_coordinator.terminalCleanupAckReady(callId)) {
        await _coordinator.retryTerminalCleanup(callId);
      }
    }
    try {
      await _invokeMethod(
        'failClosed',
        _versionArguments(),
      ).timeout(_failClosedTimeout);
    } catch (_) {
      // Local invalidation remains terminal even when native cannot confirm.
    }
    _descriptor = null;
    _events.clear();
    _observedEvents.clear();
    _eventIds.clear();
    _ownsSession = false;
  }

  Future<T> _schedule<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then<void>((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<void> close() => _closeFuture ??= _closeOnce();

  Future<void> _closeOnce() async {
    if (_closed) return;
    _closed = true;
    _bindingGeneration++;
    _ownsSession = false;
    if (!_invalidations.isClosed) unawaited(_invalidations.close());
    final subscriptions = <Future<void>>[];
    final nativeSubscription = _nativeSubscription;
    _nativeSubscription = null;
    if (nativeSubscription != null) {
      subscriptions.add(nativeSubscription.cancel());
    }
    final snapshotSubscription = _snapshotSubscription;
    _snapshotSubscription = null;
    if (snapshotSubscription != null) {
      subscriptions.add(snapshotSubscription.cancel());
    }
    await Future.wait(subscriptions);
    await Future.wait<void>(<Future<void>>[_tail, _audioCommandTail]);
    // Literal true is the only successful detach acknowledgement, but close
    // remains best-effort and terminal on the Dart side either way.
    await _invokeBoolean('detach', _versionArguments());
    if (!_interruptions.isClosed) await _interruptions.close();
    if (!_muteChanges.isClosed) await _muteChanges.close();
  }

  static Map<String, Object?> _versionArguments() => const <String, Object?>{
    'version': protocolVersion,
  };

  static Map<String, Object?> _handleArguments(String handle) =>
      <String, Object?>{'version': protocolVersion, 'callHandle': handle};

  static bool _validHandle(String? value) =>
      value != null && _uuid.hasMatch(value);

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  static String _routeWireName(CallAudioOutputRoute route) => switch (route) {
    CallAudioOutputRoute.systemDefault => 'system_default',
    CallAudioOutputRoute.earpiece => 'earpiece',
    CallAudioOutputRoute.speaker => 'speaker',
    CallAudioOutputRoute.wiredHeadset => 'wired_headset',
    CallAudioOutputRoute.bluetooth => 'bluetooth',
  };

  static CallAudioOutputRoute _parseRoute(String value) => switch (value) {
    'system_default' => CallAudioOutputRoute.systemDefault,
    'earpiece' => CallAudioOutputRoute.earpiece,
    'speaker' => CallAudioOutputRoute.speaker,
    'wired_headset' => CallAudioOutputRoute.wiredHeadset,
    'bluetooth' => CallAudioOutputRoute.bluetooth,
    _ => throw const FormatException('unsupported audio route'),
  };

  static DateTime _systemClock() => DateTime.now().toUtc();

  /// Native accepts `ringing` (incoming card with Answer/Decline) and
  /// `accepted` (ongoing card). An outgoing call that reaches `ringing`
  /// must not be projected as an incoming call on the caller's phone, and
  /// every post-accept state keeps the ongoing card.
  static String _defaultProjectedState(CallSessionSnapshot snapshot) =>
      switch (snapshot.state) {
        CallState.ringing =>
          snapshot.direction == CallDirection.incoming
              ? 'ringing'
              : 'outgoing_ringing',
        CallState.accepted ||
        CallState.negotiating ||
        CallState.connected ||
        CallState.reconnecting => 'accepted',
        _ => snapshot.state.name,
      };
}

enum _AcknowledgementDisposition {
  none('NONE'),
  adopted('ADOPTED'),
  terminal('TERMINAL');

  const _AcknowledgementDisposition(this.wireName);

  final String wireName;
}

enum _NativeEventType {
  presented,
  answer,
  decline,
  end,
  remoteCancelled,
  expired,
  providerRemoved,
  nativeFailure,
  muteChanged,
  routeChanged,
  audioActivated,
  audioDeactivated;

  bool get isTerminal => switch (this) {
    _NativeEventType.decline ||
    _NativeEventType.end ||
    _NativeEventType.remoteCancelled ||
    _NativeEventType.expired ||
    _NativeEventType.providerRemoved ||
    _NativeEventType.nativeFailure => true,
    _ => false,
  };

  static _NativeEventType parse(String value) => switch (value) {
    'presented' => _NativeEventType.presented,
    'answer' => _NativeEventType.answer,
    'decline' => _NativeEventType.decline,
    'end' => _NativeEventType.end,
    'remoteCancelled' => _NativeEventType.remoteCancelled,
    'expired' => _NativeEventType.expired,
    'providerRemoved' => _NativeEventType.providerRemoved,
    'nativeFailure' => _NativeEventType.nativeFailure,
    'muteChanged' => _NativeEventType.muteChanged,
    'routeChanged' => _NativeEventType.routeChanged,
    'audioActivated' => _NativeEventType.audioActivated,
    'audioDeactivated' => _NativeEventType.audioDeactivated,
    _ => throw const FormatException('unsupported native event'),
  };
}

final class _NativeDescriptor {
  const _NativeDescriptor({
    required this.callHandle,
    required this.expiresAt,
    required this.presented,
    required this.phase,
    required this.direction,
  });

  final String callHandle;
  final DateTime expiresAt;
  final bool presented;
  final _NativeDescriptorPhase phase;
  final _NativeCallDirection direction;

  static _NativeDescriptor parse(Object? value) {
    final map = _exactMap(value, const <String>{
      'callHandle',
      'expiresAtMs',
      'presented',
      'phase',
      'direction',
    });
    final callHandle = map['callHandle'];
    final expiresAtMs = map['expiresAtMs'];
    final presented = map['presented'];
    final phase = map['phase'];
    final direction = map['direction'];
    if (callHandle is! String ||
        !AndroidCallLifecycleAdapter._validHandle(callHandle) ||
        expiresAtMs is! int ||
        expiresAtMs <= 0 ||
        presented is! bool ||
        phase is! String ||
        direction is! String) {
      throw const FormatException('malformed native descriptor');
    }
    return _NativeDescriptor(
      callHandle: callHandle,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs, isUtc: true),
      presented: presented,
      phase: _NativeDescriptorPhase.parse(phase),
      direction: _NativeCallDirection.parse(direction),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _NativeDescriptor &&
      callHandle == other.callHandle &&
      expiresAt == other.expiresAt &&
      presented == other.presented &&
      phase == other.phase &&
      direction == other.direction;

  @override
  int get hashCode =>
      Object.hash(callHandle, expiresAt, presented, phase, direction);
}

enum _NativeCallDirection {
  incoming,
  outgoing;

  static _NativeCallDirection parse(String value) => switch (value) {
    'incoming' => _NativeCallDirection.incoming,
    'outgoing' => _NativeCallDirection.outgoing,
    _ => throw const FormatException('unsupported native call direction'),
  };
}

enum _NativeDescriptorPhase {
  preStart,
  journal;

  static _NativeDescriptorPhase parse(String value) => switch (value) {
    'preStart' => _NativeDescriptorPhase.preStart,
    'journal' => _NativeDescriptorPhase.journal,
    _ => throw const FormatException('unsupported native descriptor phase'),
  };
}

final class _NativeEvent {
  const _NativeEvent({
    required this.callHandle,
    required this.sequence,
    required this.eventId,
    required this.type,
    required this.occurredAt,
  });

  final String callHandle;
  final int sequence;
  final String eventId;
  final _NativeEventType type;
  final DateTime occurredAt;

  static _NativeEvent parse(Object? value) {
    final map = _exactMap(value, const <String>{
      'callHandle',
      'sequence',
      'eventId',
      'type',
      'occurredAtMs',
    });
    final callHandle = map['callHandle'];
    final sequence = map['sequence'];
    final eventId = map['eventId'];
    final type = map['type'];
    final occurredAtMs = map['occurredAtMs'];
    if (callHandle is! String ||
        !AndroidCallLifecycleAdapter._validHandle(callHandle) ||
        sequence is! int ||
        sequence <= 0 ||
        sequence >= 0x7fffffff ||
        eventId is! String ||
        !AndroidCallLifecycleAdapter._uuid.hasMatch(eventId) ||
        type is! String ||
        occurredAtMs is! int ||
        occurredAtMs < 0) {
      throw const FormatException('malformed native event');
    }
    return _NativeEvent(
      callHandle: callHandle,
      sequence: sequence,
      eventId: eventId,
      type: _NativeEventType.parse(type),
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        occurredAtMs,
        isUtc: true,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _NativeEvent &&
      callHandle == other.callHandle &&
      sequence == other.sequence &&
      eventId == other.eventId &&
      type == other.type &&
      occurredAt == other.occurredAt;

  @override
  int get hashCode =>
      Object.hash(callHandle, sequence, eventId, type, occurredAt);
}

final class _NativeBatch {
  const _NativeBatch({
    required this.descriptor,
    required this.events,
    required this.nativeCallId,
    required this.highestSequence,
  });

  final _NativeDescriptor? descriptor;
  final List<_NativeEvent> events;
  final String? nativeCallId;
  final int highestSequence;

  static _NativeBatch parse(Object? value, {required int maxEvents}) {
    final map = _boundedMap(
      value,
      requiredKeys: const <String>{
        'version',
        'descriptor',
        'events',
        'nativeCallId',
        'highestSequence',
      },
      allowedKeys: const <String>{
        'version',
        'descriptor',
        'events',
        'nativeCallId',
        'highestSequence',
      },
    );
    final rawEvents = map['events'];
    if (map['version'] != AndroidCallLifecycleAdapter.protocolVersion ||
        rawEvents is! List<Object?> ||
        rawEvents.length > maxEvents) {
      throw const FormatException('malformed native batch');
    }
    final events = rawEvents.map(_NativeEvent.parse).toList(growable: false);
    for (var index = 1; index < events.length; index++) {
      if (events[index].sequence != events[index - 1].sequence + 1) {
        throw const FormatException('unordered native batch');
      }
    }
    final descriptor = map['descriptor'] == null
        ? null
        : _NativeDescriptor.parse(map['descriptor']);
    final nativeCallId = map['nativeCallId'];
    if (nativeCallId != null &&
        (nativeCallId is! String ||
            !AndroidCallLifecycleAdapter._validHandle(nativeCallId))) {
      throw const FormatException('invalid native call id');
    }
    final highestSequence = map['highestSequence'];
    if (highestSequence is! int ||
        highestSequence < 0 ||
        highestSequence >= 0x7fffffff ||
        (events.isNotEmpty && highestSequence != events.last.sequence)) {
      throw const FormatException('invalid native high sequence');
    }
    return _NativeBatch(
      descriptor: descriptor,
      events: events,
      nativeCallId: nativeCallId as String?,
      highestSequence: highestSequence,
    );
  }
}

Map<String, Object?> _exactMap(Object? value, Set<String> exactKeys) {
  return _boundedMap(value, requiredKeys: exactKeys, allowedKeys: exactKeys);
}

Map<String, Object?> _boundedMap(
  Object? value, {
  required Set<String> requiredKeys,
  required Set<String> allowedKeys,
}) {
  if (value is! Map) throw const FormatException('expected map');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String || !allowedKeys.contains(key)) {
      throw const FormatException('unexpected field');
    }
    result[key] = entry.value;
  }
  if (!requiredKeys.every(result.containsKey)) {
    throw const FormatException('missing field');
  }
  return result;
}
