import 'dart:async';

import '../../core/permissions/mic_permission_gateway.dart';
import '../../core/utils/flow_event_emitter.dart';
import '../../features/call/diagnostics/call_diagnostics.dart';
import '../../features/call/application/foreground_call_capability.dart';
import '../../features/call/application/ringing_call_mailbox_poller.dart';
import '../../features/call/application/handle_incoming_call_signal.dart';
import '../../features/call/infrastructure/call_authority_client.dart';
import '../../features/call/application/outgoing_call_capability.dart';
import '../../features/call/domain/call_wake_handle_grant.dart';
import '../../features/call/domain/call_id.dart';
import '../../features/call/domain/call_session_snapshot.dart';
import '../../features/call/domain/call_state.dart';

typedef AwaitCallSignalingReadiness = Future<void> Function();
typedef RequestOutgoingMicrophonePermission =
    Future<MicPermissionStatus> Function();
typedef EnsureOutgoingCallWakeAuthority =
    Future<bool> Function(String contactAccountPeerId);
typedef BuildCallSignalingGraph =
    Future<CallSignalingGraphLifecycle> Function();

enum _CallSignalingStartStage {
  foregroundPresentationReadiness('foregroundPresentationReadiness'),
  signalingReadiness('signalingReadiness'),
  graphConstruction('graphConstruction'),
  foregroundBinding('foregroundBinding'),
  listenerInstallation('listenerInstallation'),
  capabilityAdvertisement('capabilityAdvertisement'),
  complete('complete');

  const _CallSignalingStartStage(this.diagnosticValue);

  final String diagnosticValue;
}

/// The narrow process-owned lifecycle exposed by the production call graph.
/// Implementations own no shared chat/router/bridge/P2P resources.
abstract interface class CallSignalingGraphLifecycle {
  /// Returns true only when the dedicated call listener is installed.
  Future<bool> start();

  Future<void> onResume();

  Future<bool> advertiseCapability();

  Future<bool> isOutgoingCallAvailableFor(String contactAccountPeerId);

  Future<OutgoingCallStartResult> startOutgoingCall(
    String contactAccountPeerId,
  );

  Future<void> shutdown();
}

/// Foreground-only call graphs implement this narrow lifecycle hook so an
/// active VC2-03 call is terminalized without tearing down the dedicated
/// signaling listener needed on the next foreground resume.
abstract interface class ForegroundCallBackgroundLifecycle {
  Future<void> onBackgrounded();
}

/// Optional graph signal used when external callability authority is withdrawn
/// after startup. The composition owns graph withdrawal so outgoing UI state
/// changes atomically with teardown.
abstract interface class CallSignalingCallabilityInvalidations {
  Stream<void> get callabilityInvalidations;
}

/// Diagnostic metadata follows invalidation without becoming authority.
abstract interface class CallSignalingDiagnosticInvalidations {
  String get invalidationDiagnosticReason;
  String? get invalidationDiagnosticOperationId;
}

/// Optional graph signal: a capability advertisement that was deferred
/// because a call was live can be retried now (the call reached a terminal
/// snapshot). The composition owns the retry so it stays serialized with
/// contact reconciliation and withdraws the graph only when the retry fails
/// while idle.
abstract interface class CallSignalingDeferredAdvertisementRetries {
  Stream<void> get deferredAdvertisementRetries;
}

/// Optional graph hook: drains the ephemeral call mailbox right now because a
/// native call wake (PushKit) or a relay recovery reported that a signal may be
/// waiting there for this device. Foreground state is not touched.
abstract interface class CallSignalingWakeDrain {
  Future<void> drainCallMailbox();
}

/// Optional graph boundary used by encrypted contact-request distribution.
/// The stable composition prevents retained UI owners from holding a graph-
/// lifetime coordinator after callability has been withdrawn.
abstract interface class CallWakeHandleDistributionLifecycle {
  /// Returns true only after the current durable grant set was fully scanned
  /// and every eligible grant was made distribution-pending.
  Future<bool> rearmCallWakeHandleDistribution();

  Future<CallWakeHandleGrant?> resolveCallWakeHandle(
    String contactAccountPeerId,
  );

  Future<bool> markCallWakeHandleDistributed(
    String contactAccountPeerId,
    CallWakeHandleGrant grant,
  );
}

/// Default-off composition latch for exactly one call graph per process.
///
/// Readiness always precedes graph construction. The graph (and therefore its
/// coordinator) is constructed before either its dedicated subscription or
/// capability advertisement is allowed to start.
final class CallSignalingComposition
    implements
        OutgoingCallCapability,
        OutgoingCallReadinessRecovery,
        ForegroundCallCapability,
        IncomingCallPresenter {
  CallSignalingComposition({
    required Map<String, bool> featureFlags,
    required CallEndpointPlatform? platform,
    required AwaitCallSignalingReadiness awaitReadiness,
    required BuildCallSignalingGraph buildGraph,
    RequestOutgoingMicrophonePermission? requestOutgoingMicrophonePermission,
    EnsureOutgoingCallWakeAuthority? ensureOutgoingCallWakeAuthority,
    AwaitCallSignalingReadiness? awaitForegroundPresentationReadiness,
    bool Function()? isForeground,
    DateTime Function()? clock,
  }) : _featureFlags = Map<String, bool>.unmodifiable(featureFlags),
       _platform = platform,
       _awaitReadiness = awaitReadiness,
       _awaitForegroundPresentationReadiness =
           awaitForegroundPresentationReadiness ?? _readyImmediately,
       _requestOutgoingMicrophonePermission =
           requestOutgoingMicrophonePermission ??
           _denyOutgoingMicrophonePermission,
       _ensureOutgoingCallWakeAuthority =
           ensureOutgoingCallWakeAuthority ?? _allowOutgoingCallWakeAuthority,
       _buildGraph = buildGraph,
       _isForeground = isForeground ?? _defaultForegroundState,
       _clock = clock ?? DateTime.now;

  final Map<String, bool> _featureFlags;
  final CallEndpointPlatform? _platform;
  final AwaitCallSignalingReadiness _awaitReadiness;
  final AwaitCallSignalingReadiness _awaitForegroundPresentationReadiness;
  final RequestOutgoingMicrophonePermission
  _requestOutgoingMicrophonePermission;
  final EnsureOutgoingCallWakeAuthority _ensureOutgoingCallWakeAuthority;
  final BuildCallSignalingGraph _buildGraph;
  final bool Function() _isForeground;
  final DateTime Function() _clock;

  CallSignalingGraphLifecycle? _graph;
  CallSignalingGraphLifecycle? _boundGraph;
  ForegroundCallCapability? _foregroundGraph;
  StreamSubscription<ForegroundCallProjection?>? _foregroundSubscription;
  StreamSubscription<void>? _callabilityInvalidationSubscription;
  StreamSubscription<void>? _deferredAdvertisementRetrySubscription;
  final StreamController<ForegroundCallProjection?> _foregroundChanges =
      StreamController<ForegroundCallProjection?>.broadcast(sync: true);
  final StreamController<bool> _outgoingCallAvailabilityChanges =
      StreamController<bool>.broadcast(sync: true);
  final Completer<void> _terminalSignal = Completer<void>();
  ForegroundCallProjection? _foregroundCurrent;

  /// Native calls keep receiving mailbox control even with no visible overlay.
  late final RingingCallMailboxPoller _ringingPoller = RingingCallMailboxPoller(
    drain: _drainCallMailboxForLiveCall,
  );
  CallId? _presentedIncomingCallId;
  int _foregroundGeneration = 0;
  Future<void>? _startInFlight;
  Future<bool>? _outgoingReadinessRecoveryInFlight;
  int _outgoingReadinessLifecycleGeneration = 0;
  Future<bool>? _callWakeDistributionRearmInFlight;
  Future<void>? _shutdownInFlight;
  Future<void> _contactReconciliationTail = Future<void>.value();
  bool _started = false;
  bool _terminal = false;
  bool _foregroundAllowed = true;
  bool _callWakeDistributionRearmed = false;

  bool get _hasForegroundCapability =>
      _platform != null &&
      _featureFlags['voice_call_capability_v1'] == true &&
      _featureFlags['voice_call_turn_enabled'] == true;

  bool get isEnabled {
    if (!_hasForegroundCapability) return false;
    // The endpoint capability is not direction-specific: advertising it also
    // claims inbound callability. Until that contract can distinguish
    // directions, an outgoing-only configuration must not build the graph.
    final directionEnabled =
        _featureFlags['voice_call_incoming_enabled'] == true;
    // Foreground VC2-03 uses the Dart presentation path. Android Telecom and
    // iOS CallKit remain independent later-wave gates and stay default-off.
    return directionEnabled;
  }

  bool get isStarted => _started && !_terminal;

  bool get _hasLiveForegroundCall {
    final session = _foregroundGraph?.current?.session;
    return session != null && session.callId != null && !session.isTerminal;
  }

  bool get isShutdown => _terminal;

  @override
  ForegroundCallProjection? get current => _foregroundCurrent;

  @override
  Stream<ForegroundCallProjection?> get changes => _foregroundChanges.stream;

  @override
  Stream<bool> get outgoingCallAvailabilityChanges =>
      _outgoingCallAvailabilityChanges.stream;

  @override
  bool get isOutgoingCallAvailable =>
      _hasForegroundCapability &&
      _featureFlags['voice_call_outgoing_enabled'] == true &&
      isStarted &&
      _graph != null;

  /// An explicit tap may retry an idle graph withdrawn by a transient startup
  /// or advertisement failure. Passive probes keep observing current state.
  @override
  Future<bool> recoverOutgoingCallReadiness() {
    if (!isEnabled ||
        _featureFlags['voice_call_outgoing_enabled'] != true ||
        _terminal ||
        !_foregroundAllowed ||
        !_isForeground() ||
        _hasLiveForegroundCall) {
      return Future<bool>.value(false);
    }
    if (isOutgoingCallAvailable) return Future<bool>.value(true);
    final inFlight = _outgoingReadinessRecoveryInFlight;
    if (inFlight != null) return inFlight;
    final generation = _outgoingReadinessLifecycleGeneration;
    late final Future<bool> attempt;
    attempt = _recoverOutgoingCallReadiness(generation).whenComplete(() {
      if (identical(_outgoingReadinessRecoveryInFlight, attempt)) {
        _outgoingReadinessRecoveryInFlight = null;
      }
    });
    _outgoingReadinessRecoveryInFlight = attempt;
    return attempt;
  }

  Future<bool> _recoverOutgoingCallReadiness(int generation) async {
    try {
      await Future.any(<Future<void>>[
        start(),
        _terminalSignal.future,
      ]).timeout(const Duration(seconds: 10));
    } catch (_) {
      return false;
    }
    return generation == _outgoingReadinessLifecycleGeneration &&
        _foregroundAllowed &&
        _isForeground() &&
        !_hasLiveForegroundCall &&
        isOutgoingCallAvailable;
  }

  @override
  Future<bool> isOutgoingCallAvailableFor(String contactAccountPeerId) async {
    final graph = _graph;
    if (!isOutgoingCallAvailable || graph == null) return false;
    try {
      final available = await graph.isOutgoingCallAvailableFor(
        contactAccountPeerId,
      );
      return available && identical(_graph, graph) && isOutgoingCallAvailable;
    } catch (_) {
      return false;
    }
  }

  /// Resolves the graph at invocation time. The composition is safe to retain
  /// in route authority; it never hands presentation a graph that was later
  /// withdrawn or replaced.
  @override
  Future<OutgoingCallStartResult> startOutgoingCall(
    String contactAccountPeerId,
  ) {
    final diagnostics = CallDiagnostics.instance;
    final traceId = diagnostics.currentTraceId ?? diagnostics.beginAttempt();
    return diagnostics.runWithTrace(
      traceId,
      () => _startOutgoingCallWithDiagnostics(contactAccountPeerId, traceId),
    );
  }

  Future<OutgoingCallStartResult> _startOutgoingCallWithDiagnostics(
    String contactAccountPeerId,
    String? traceId,
  ) async {
    final diagnostics = CallDiagnostics.instance;
    OutgoingCallStartResult reject(String reason, {bool failed = false}) {
      diagnostics.record(
        stage: 'preflight',
        action: 'check',
        outcome: 'rejected',
        reason: reason,
        traceId: traceId,
      );
      diagnostics.finishAttempt(
        traceId: traceId,
        outcome: 'preflight_failed',
        reason: reason,
      );
      return failed
          ? OutgoingCallStartResult.failed
          : OutgoingCallStartResult.unavailable;
    }

    final graph = _graph;
    if (!isOutgoingCallAvailable || graph == null) {
      return reject(_terminal ? 'graph_shutdown' : 'graph_unavailable');
    }
    final graphGeneration = _foregroundGeneration;
    var failureReason = 'microphone_denied';
    try {
      final permissionStatus = await _requestOutgoingMicrophonePermission();
      diagnostics.record(
        stage: 'preflight',
        action: 'check',
        outcome: permissionStatus == MicPermissionStatus.granted
            ? 'ok'
            : 'rejected',
        reason: permissionStatus == MicPermissionStatus.granted
            ? 'none'
            : 'microphone_denied',
        traceId: traceId,
        values: <String, Object?>{
          'microphoneAllowed': permissionStatus == MicPermissionStatus.granted,
        },
      );
      if (permissionStatus != MicPermissionStatus.granted) {
        return reject('microphone_denied', failed: true);
      }
      if (!isOutgoingCallAvailable ||
          !identical(_graph, graph) ||
          _foregroundGeneration != graphGeneration) {
        return reject('graph_replaced');
      }
      failureReason = 'capability_publish_failed';
      late final bool callerAuthorityReady;
      try {
        callerAuthorityReady = await graph.advertiseCapability();
      } catch (_) {
        if (identical(_graph, graph) &&
            _foregroundGeneration == graphGeneration) {
          await _withdrawGraph(graph);
        }
        return reject('capability_publish_failed', failed: true);
      }
      if (!callerAuthorityReady) {
        if (identical(_graph, graph) &&
            _foregroundGeneration == graphGeneration) {
          await _withdrawGraph(graph);
        }
        return reject('capability_unavailable');
      }
      if (!isOutgoingCallAvailable ||
          !identical(_graph, graph) ||
          _foregroundGeneration != graphGeneration) {
        return reject('graph_replaced');
      }
      failureReason = 'wake_authority_missing';
      late final bool callerWakeAuthorityReady;
      try {
        callerWakeAuthorityReady = await _ensureOutgoingCallWakeAuthority(
          contactAccountPeerId,
        );
      } catch (_) {
        return reject('wake_authority_missing', failed: true);
      }
      if (!callerWakeAuthorityReady) return reject('wake_authority_missing');
      if (!isOutgoingCallAvailable ||
          !identical(_graph, graph) ||
          _foregroundGeneration != graphGeneration) {
        return reject('graph_replaced');
      }
      failureReason = 'authority_unreachable';
      final result = await graph.startOutgoingCall(contactAccountPeerId);
      if (result != OutgoingCallStartResult.started) {
        return reject(
          'unavailable',
          failed: result == OutgoingCallStartResult.failed,
        );
      }
      diagnostics.record(
        stage: 'preflight',
        action: 'finish',
        outcome: 'ok',
        traceId: traceId,
      );
      return result;
    } catch (_) {
      return reject(failureReason, failed: true);
    }
  }

  Future<CallWakeHandleGrant?> resolveCallWakeHandle(
    String contactAccountPeerId,
  ) async {
    final graph = _graph;
    final distribution = graph is CallWakeHandleDistributionLifecycle
        ? graph as CallWakeHandleDistributionLifecycle
        : null;
    if (!isStarted || graph == null || distribution == null) {
      return null;
    }
    try {
      final grant = await distribution.resolveCallWakeHandle(
        contactAccountPeerId,
      );
      return isStarted && identical(_graph, graph) ? grant : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> onCallWakeHandleDistributed(
    String contactAccountPeerId,
    CallWakeHandleGrant grant,
  ) async {
    final graph = _graph;
    final distribution = graph is CallWakeHandleDistributionLifecycle
        ? graph as CallWakeHandleDistributionLifecycle
        : null;
    if (!isStarted || graph == null || distribution == null) {
      return;
    }
    try {
      await distribution.markCallWakeHandleDistributed(
        contactAccountPeerId,
        grant,
      );
    } catch (_) {
      // The durable issuer record remains distribution-pending for resume.
    }
  }

  /// Re-publishes the current process-level outgoing-call readiness without
  /// touching graph lifecycle or authority. Mounted conversations use this
  /// pulse to rerun their own exact per-contact endpoint resolution after a
  /// newly received call wake handle becomes durable.
  Future<void> refreshOutgoingCallAvailability() async {
    _publishOutgoingCallAvailability();
  }

  /// Serializes contact/block/device-authority changes through the same
  /// fail-closed advertisement boundary used on startup and resume.
  Future<void> onContactEligibilityChanged() {
    final prior = _contactReconciliationTail;
    final next = () async {
      try {
        await prior;
      } catch (_) {
        // Every operation below is total, but keep the lane recoverable.
      }
      await _reconcileContactEligibility();
    }();
    _contactReconciliationTail = next;
    return next;
  }

  Future<void> _reconcileContactEligibility() async {
    final graph = _graph;
    if (!isEnabled || _terminal || !_started || graph == null) return;
    var outcome = 'failed';
    try {
      if (!await graph.advertiseCapability()) {
        if (_hasLiveForegroundCall) {
          // Never tear down a live call over a failed advertisement; the
          // graph retries it at the terminal snapshot (or the next resume).
          _publishOutgoingCallAvailability();
          outcome = 'advertisement_deferred';
          return;
        }
        await _withdrawGraph(graph);
        outcome = 'advertisement_unavailable';
        return;
      }
      if (!_terminal && identical(_graph, graph)) {
        _publishOutgoingCallAvailability();
        outcome = 'ready';
        return;
      }
      outcome = _terminal ? 'terminal' : 'graph_replaced';
    } catch (_) {
      if (_hasLiveForegroundCall) {
        outcome = 'reconcile_failed_live_call_retained';
        return;
      }
      await _withdrawGraph(graph);
    } finally {
      _emitLifecycleResult(
        event: 'CALL_SIGNALING_RECONCILE_RESULT',
        outcome: outcome,
      );
    }
  }

  Future<void> start() {
    if (!isEnabled || _terminal || _started) return Future<void>.value();
    final inFlight = _startInFlight;
    if (inFlight != null) return inFlight;
    late final Future<void> attempt;
    attempt = _startInternal().whenComplete(() {
      if (identical(_startInFlight, attempt)) _startInFlight = null;
    });
    _startInFlight = attempt;
    return attempt;
  }

  Future<void> _startInternal() async {
    CallSignalingGraphLifecycle? graph;
    var outcome = 'failed';
    var stage = _CallSignalingStartStage.foregroundPresentationReadiness;
    try {
      await Future.any(<Future<void>>[
        _awaitForegroundPresentationReadiness(),
        _terminalSignal.future,
      ]);
      if (_terminal) {
        outcome = 'terminal';
        return;
      }
      stage = _CallSignalingStartStage.signalingReadiness;
      await _awaitReadiness();
      if (_terminal) {
        outcome = 'terminal';
        return;
      }
      stage = _CallSignalingStartStage.graphConstruction;
      graph = await _buildGraph();
      if (_terminal) {
        await graph.shutdown();
        outcome = 'terminal';
        return;
      }
      _graph = graph;
      stage = _CallSignalingStartStage.foregroundBinding;
      await _bindForegroundGraph(graph);
      stage = _CallSignalingStartStage.listenerInstallation;
      if (!await graph.start()) {
        await _withdrawGraph(graph);
        outcome = 'listener_unavailable';
        return;
      }
      if (_terminal) {
        outcome = 'terminal';
        return;
      }
      stage = _CallSignalingStartStage.capabilityAdvertisement;
      if (!await graph.advertiseCapability()) {
        await _withdrawGraph(graph);
        outcome = 'advertisement_unavailable';
        return;
      }
      _started = true;
      outcome = 'ready';
      _publishOutgoingCallAvailability();
      _acceptForegroundProjection(
        graph,
        _foregroundGraph?.current,
        _foregroundGeneration,
      );
      stage = _CallSignalingStartStage.complete;
    } catch (_) {
      if (graph != null) await _withdrawGraph(graph);
    } finally {
      _emitLifecycleResult(
        event: 'CALL_SIGNALING_START_RESULT',
        outcome: outcome,
        startStage: stage,
      );
    }
  }

  /// A native call wake (a PushKit VoIP push presented a call while the app
  /// was backgrounded) or a relay recovery: the call mailbox may hold the
  /// invite that the live transport could not deliver. Starts the graph if
  /// needed and drains that mailbox without changing foreground state, so the
  /// call exists on the Dart side before the user answers from the lock screen.
  Future<void> onCallWake() async {
    var outcome = 'failed';
    try {
      if (!isEnabled) {
        outcome = 'disabled';
        return;
      }
      if (_terminal) {
        outcome = 'terminal';
        return;
      }
      await start();
      final graph = _graph;
      if (!_started || graph == null || _terminal) {
        outcome = _terminal ? 'terminal' : 'start_unavailable';
        return;
      }
      final drain = graph is CallSignalingWakeDrain
          ? graph as CallSignalingWakeDrain
          : null;
      if (drain == null) {
        outcome = 'unsupported';
        return;
      }
      await drain.drainCallMailbox();
      outcome = identical(_graph, graph) ? 'drained' : 'graph_replaced';
    } catch (_) {
      // Best effort: the next resume or relay recovery drains again.
    } finally {
      _emitLifecycleResult(
        event: 'CALL_SIGNALING_WAKE_RESULT',
        outcome: outcome,
      );
    }
  }

  /// Drains only the ephemeral call mailbox. It is intentionally independent
  /// of chat inbox/outbox/retrier resume work.
  Future<void> onResume() async {
    var outcome = 'failed';
    try {
      if (!isEnabled) {
        outcome = 'disabled';
        return;
      }
      if (_terminal) {
        outcome = 'terminal';
        return;
      }
      _foregroundAllowed = true;
      await start();
      final graph = _graph;
      if (!_started || graph == null || _terminal) {
        outcome = _terminal ? 'terminal' : 'start_unavailable';
        return;
      }
      try {
        await graph.onResume();
        if (_terminal || !identical(_graph, graph)) {
          outcome = _terminal ? 'terminal' : 'graph_replaced';
          return;
        }
        // Restore a live call surface before any relay round trip.
        _acceptForegroundProjection(
          graph,
          _foregroundGraph?.current,
          _foregroundGeneration,
        );
        if (!await graph.advertiseCapability()) {
          if (_hasLiveForegroundCall) {
            // Never tear down a live call over a failed advertisement; the
            // next resume retries it.
            _publishOutgoingCallAvailability();
            outcome = 'advertisement_deferred';
            return;
          }
          await _withdrawGraph(graph);
          outcome = 'advertisement_unavailable';
          return;
        }
        final distribution = graph is CallWakeHandleDistributionLifecycle
            ? graph as CallWakeHandleDistributionLifecycle
            : null;
        if (!_callWakeDistributionRearmed && distribution != null) {
          await _rearmCallWakeDistributionOnce(graph, distribution);
          if (_terminal || !identical(_graph, graph)) {
            outcome = _terminal ? 'terminal' : 'graph_replaced';
            return;
          }
        }
        if (!_terminal && identical(_graph, graph)) {
          _acceptForegroundProjection(
            graph,
            _foregroundGraph?.current,
            _foregroundGeneration,
          );
          _publishOutgoingCallAvailability();
          outcome = 'ready';
          return;
        }
        outcome = _terminal ? 'terminal' : 'graph_replaced';
      } catch (_) {
        if (_hasLiveForegroundCall) {
          outcome = 'resume_failed_live_call_retained';
          return;
        }
        await _withdrawGraph(graph);
        outcome = 'failed';
      }
    } finally {
      _emitLifecycleResult(
        event: 'CALL_SIGNALING_RESUME_RESULT',
        outcome: outcome,
      );
    }
  }

  Future<bool> _rearmCallWakeDistributionOnce(
    CallSignalingGraphLifecycle graph,
    CallWakeHandleDistributionLifecycle distribution,
  ) {
    if (_callWakeDistributionRearmed) return Future<bool>.value(true);
    final inFlight = _callWakeDistributionRearmInFlight;
    if (inFlight != null) return inFlight;

    late final Future<bool> attempt;
    attempt =
        () async {
          try {
            final completed = await distribution
                .rearmCallWakeHandleDistribution();
            if (!completed || _terminal || !identical(_graph, graph)) {
              return false;
            }
            _callWakeDistributionRearmed = true;
            return true;
          } catch (_) {
            return false;
          }
        }().whenComplete(() {
          if (identical(_callWakeDistributionRearmInFlight, attempt)) {
            _callWakeDistributionRearmInFlight = null;
          }
        });
    _callWakeDistributionRearmInFlight = attempt;
    return attempt;
  }

  void _emitLifecycleResult({
    required String event,
    required String outcome,
    _CallSignalingStartStage? startStage,
  }) {
    try {
      emitFlowEvent(
        layer: 'CALL_SIGNALING_COMPOSITION',
        event: event,
        details: <String, dynamic>{
          'outcome': outcome,
          'enabled': isEnabled,
          'started': isStarted,
          'graphPresent': _graph != null,
          'outgoingAvailable': isOutgoingCallAvailable,
          if (startStage != null) 'stage': startStage.diagnosticValue,
        },
      );
    } catch (_) {
      // Diagnostics must never affect the fail-closed lifecycle.
    }
  }

  /// Withdraws foreground presentation synchronously, then asks the active
  /// production graph to end only its current call through the canonical
  /// reducer. The graph itself remains started for the next resume.
  Future<void> onBackgrounded() async {
    _outgoingReadinessLifecycleGeneration++;
    _foregroundAllowed = false;
    _presentedIncomingCallId = null;
    _publishForeground(null);
    final graph = _graph;
    if (!isEnabled || _terminal || !_started || graph == null) return;
    final backgroundLifecycle = graph is ForegroundCallBackgroundLifecycle
        ? graph as ForegroundCallBackgroundLifecycle
        : null;
    if (backgroundLifecycle == null) return;
    try {
      await backgroundLifecycle.onBackgrounded();
    } catch (_) {
      // Presentation stays withdrawn if terminalization fails unexpectedly.
    }
  }

  Future<void> _withdrawGraph(CallSignalingGraphLifecycle graph) async {
    if (identical(_graph, graph)) {
      _graph = null;
      // A superseded graph may finish a failed advertisement after its
      // replacement has started. Cleanup must preserve the new readiness.
      _started = false;
      _publishOutgoingCallAvailability();
    }
    await _unbindForegroundGraph(graph);
    try {
      await graph.shutdown();
    } catch (_) {
      // Authority failure stays fail-closed and detail-free.
    }
  }

  Future<void> shutdown() {
    if (!isEnabled) return Future<void>.value();
    final inFlight = _shutdownInFlight;
    if (inFlight != null) return inFlight;
    if (_terminal) return Future<void>.value();
    _terminal = true;
    // Stop polling before anything it reads can be torn down.
    _ringingPoller.dispose();
    _publishOutgoingCallAvailability();
    if (!_terminalSignal.isCompleted) _terminalSignal.complete();
    late final Future<void> attempt;
    attempt = _shutdownInternal().whenComplete(() {
      if (identical(_shutdownInFlight, attempt)) _shutdownInFlight = null;
    });
    _shutdownInFlight = attempt;
    return attempt;
  }

  Future<void> _shutdownInternal() async {
    await _startInFlight;
    await _contactReconciliationTail;
    final graph = _graph;
    _graph = null;
    _started = false;
    if (graph != null) await _unbindForegroundGraph(graph);
    if (graph == null) return;
    try {
      await graph.shutdown();
    } catch (_) {
      // Shutdown remains terminal even if best-effort authority revoke fails.
    }
  }

  Future<void> _bindForegroundGraph(CallSignalingGraphLifecycle graph) async {
    _ringingPoller.onSession(null);
    await _foregroundSubscription?.cancel();
    await _callabilityInvalidationSubscription?.cancel();
    await _deferredAdvertisementRetrySubscription?.cancel();
    _foregroundSubscription = null;
    _callabilityInvalidationSubscription = null;
    _deferredAdvertisementRetrySubscription = null;
    _boundGraph = graph;
    _foregroundGeneration++;
    final generation = _foregroundGeneration;
    final ForegroundCallCapability? foreground =
        graph is ForegroundCallCapability
        ? graph as ForegroundCallCapability
        : null;
    _foregroundGraph = foreground;
    _presentedIncomingCallId = null;
    _publishForeground(null);
    final callability = graph is CallSignalingCallabilityInvalidations
        ? graph as CallSignalingCallabilityInvalidations
        : null;
    _callabilityInvalidationSubscription = callability?.callabilityInvalidations
        .listen((_) {
          if (identical(_graph, graph)) {
            final metadata = graph is CallSignalingDiagnosticInvalidations
                ? graph as CallSignalingDiagnosticInvalidations
                : null;
            final diagnostics = CallDiagnostics.instance;
            final operationId =
                metadata?.invalidationDiagnosticOperationId ??
                diagnostics.beginOperation(
                  reason: metadata?.invalidationDiagnosticReason ?? 'unknown',
                );
            unawaited(
              diagnostics.runWithOperation(
                operationId,
                () => _withdrawGraph(graph),
              ),
            );
          }
        });
    final deferredRetries = graph is CallSignalingDeferredAdvertisementRetries
        ? graph as CallSignalingDeferredAdvertisementRetries
        : null;
    _deferredAdvertisementRetrySubscription = deferredRetries
        ?.deferredAdvertisementRetries
        .listen((_) {
          if (identical(_graph, graph)) {
            unawaited(onContactEligibilityChanged());
          }
        });
    if (foreground == null) return;
    _foregroundSubscription = foreground.changes.listen(
      (projection) =>
          _acceptForegroundProjection(graph, projection, generation),
      onError: (_) {
        if (identical(_graph, graph) && generation == _foregroundGeneration) {
          _ringingPoller.onSession(null);
          _publishForeground(null);
        }
      },
    );
  }

  Future<void> _unbindForegroundGraph(CallSignalingGraphLifecycle graph) async {
    if (_boundGraph != null && !identical(_boundGraph, graph)) {
      return;
    }
    _ringingPoller.onSession(null);
    _boundGraph = null;
    _foregroundGeneration++;
    _foregroundGraph = null;
    _presentedIncomingCallId = null;
    final subscription = _foregroundSubscription;
    _foregroundSubscription = null;
    final callabilitySubscription = _callabilityInvalidationSubscription;
    _callabilityInvalidationSubscription = null;
    final retrySubscription = _deferredAdvertisementRetrySubscription;
    _deferredAdvertisementRetrySubscription = null;
    _publishForeground(null);
    await Future.wait<void>(<Future<void>>[
      if (subscription != null) subscription.cancel(),
      if (callabilitySubscription != null) callabilitySubscription.cancel(),
      if (retrySubscription != null) retrySubscription.cancel(),
    ]);
  }

  void _acceptForegroundProjection(
    CallSignalingGraphLifecycle graph,
    ForegroundCallProjection? projection,
    int generation,
  ) {
    if (!identical(_graph, graph) || generation != _foregroundGeneration) {
      return;
    }
    final session = projection?.session;
    final callId = session?.callId;
    // The graph carries canonical state even when native presentation or
    // backgrounding hides it from Flutter. Visibility must not stop delivery.
    _ringingPoller.onSession(_started && !_terminal ? session : null);
    if (!_started ||
        !_foregroundAllowed ||
        projection == null ||
        callId == null ||
        session!.state == CallState.idle ||
        session.isTerminal) {
      final shownCallId = _foregroundCurrent?.session.callId;
      if (callId != null && _presentedIncomingCallId == callId) {
        _presentedIncomingCallId = null;
      }
      if (projection != null &&
          callId != null &&
          session!.isTerminal &&
          _started &&
          _foregroundAllowed &&
          shownCallId == callId) {
        // The call this surface was showing ended: pass its terminal
        // snapshot through once for the end notice, then hold null.
        _foregroundCurrent = null;
        if (!_foregroundChanges.isClosed) _foregroundChanges.add(projection);
        return;
      }
      _publishForeground(null);
      return;
    }
    if (session.direction == CallDirection.incoming &&
        (!session.incomingValidated ||
            (session.acceptedAt == null &&
                _presentedIncomingCallId != callId &&
                // Native presenter success commits canonical ringing without
                // calling present() here. Foreground controls may then show,
                // including after a notification tap resumes the app.
                (session.state != CallState.ringing || !_isForeground())))) {
      _publishForeground(null);
      return;
    }
    _publishForeground(projection);
  }

  void _publishForeground(ForegroundCallProjection? projection) {
    _foregroundCurrent = projection;
    if (!_foregroundChanges.isClosed) _foregroundChanges.add(projection);
  }

  /// Unlike [onCallWake], polling never starts a graph or changes visibility.
  Future<void> _drainCallMailboxForLiveCall() async {
    if (!isEnabled || _terminal || !_started) return;
    final graph = _graph;
    if (graph is! CallSignalingWakeDrain) return;
    await (graph as CallSignalingWakeDrain).drainCallMailbox();
  }

  void _publishOutgoingCallAvailability() {
    if (!_outgoingCallAvailabilityChanges.isClosed) {
      _outgoingCallAvailabilityChanges.add(isOutgoingCallAvailable);
    }
  }

  @override
  Future<bool> present(IncomingCallPresentation presentation) async {
    final graph = _graph;
    final foreground = _foregroundGraph;
    // Presentation is allowed while start() is still running: the runtime
    // drains the call mailbox during start, and an invite retained across a
    // process death must ring rather than be rejected and acknowledged.
    if (graph == null ||
        foreground == null ||
        _terminal ||
        !_foregroundAllowed ||
        _featureFlags['voice_call_incoming_enabled'] != true ||
        !_isForeground() ||
        !_foregroundChanges.hasListener ||
        !presentation.expiresAt.isAfter(_clock().toUtc())) {
      return false;
    }
    final projection = foreground.current;
    final session = projection?.session;
    if (projection == null ||
        session == null ||
        session.callId != presentation.callId ||
        session.contactPeerId != presentation.callerAccountPeerId ||
        session.direction != CallDirection.incoming ||
        session.state != CallState.incomingValidating ||
        !session.incomingValidated) {
      return false;
    }
    _presentedIncomingCallId = presentation.callId;
    _acceptForegroundProjection(graph, projection, _foregroundGeneration);
    return identical(_graph, graph) &&
        _presentedIncomingCallId == presentation.callId;
  }

  @override
  Future<void> dismiss(IncomingCallPresentation presentation) async {
    if (_presentedIncomingCallId != presentation.callId) return;
    _presentedIncomingCallId = null;
    if (_foregroundCurrent?.session.callId == presentation.callId) {
      _publishForeground(null);
    }
  }

  @override
  Future<ForegroundCallActionResult> answer(CallId callId) =>
      _runForegroundAction(callId, (graph) => graph.answer(callId));

  @override
  Future<ForegroundCallActionResult> decline(CallId callId) =>
      _runForegroundAction(callId, (graph) => graph.decline(callId));

  @override
  Future<ForegroundCallActionResult> cancel(CallId callId) =>
      _runForegroundAction(callId, (graph) => graph.cancel(callId));

  @override
  Future<ForegroundCallActionResult> end(CallId callId) =>
      _runForegroundAction(callId, (graph) => graph.end(callId));

  @override
  Future<ForegroundCallActionResult> setMuted(CallId callId, bool muted) =>
      _runForegroundAction(callId, (graph) => graph.setMuted(callId, muted));

  @override
  Future<ForegroundCallActionResult> setSpeakerEnabled(
    CallId callId,
    bool enabled,
  ) => _runForegroundAction(
    callId,
    (graph) => graph.setSpeakerEnabled(callId, enabled),
  );

  Future<ForegroundCallActionResult> _runForegroundAction(
    CallId callId,
    Future<ForegroundCallActionResult> Function(ForegroundCallCapability graph)
    action,
  ) async {
    final graph = _foregroundGraph;
    if (!isStarted ||
        graph == null ||
        _foregroundCurrent?.session.callId != callId) {
      return ForegroundCallActionResult.unavailable;
    }
    try {
      final result = await action(graph);
      return identical(_foregroundGraph, graph) && isStarted
          ? result
          : ForegroundCallActionResult.unavailable;
    } catch (_) {
      return ForegroundCallActionResult.failed;
    }
  }

  static bool _defaultForegroundState() => false;

  static Future<void> _readyImmediately() => Future<void>.value();

  static Future<MicPermissionStatus> _denyOutgoingMicrophonePermission() =>
      Future<MicPermissionStatus>.value(MicPermissionStatus.permanentlyDenied);

  static Future<bool> _allowOutgoingCallWakeAuthority(
    String contactAccountPeerId,
  ) => Future<bool>.value(true);
}

/// Keeps shared router/P2P/bridge owners alive until call-specific shutdown has
/// canceled subscriptions, terminalized the active session, and completed any
/// bounded endpoint revocation.
Future<void> shutdownCallSignalingBeforeSharedOwners({
  required Future<void> Function()? shutdownCallSignaling,
  required void Function() disposeMessageRouter,
  required void Function() disposeP2PService,
  required void Function() disposeBridge,
}) async {
  try {
    if (shutdownCallSignaling != null) {
      await shutdownCallSignaling();
    }
  } finally {
    disposeMessageRouter();
    disposeP2PService();
    disposeBridge();
  }
}
