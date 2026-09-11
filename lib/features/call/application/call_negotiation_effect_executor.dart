import 'dart:async';
import 'dart:collection';

import '../domain/call_engine.dart';
import '../domain/call_end_reason.dart';
import '../domain/call_event.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';
import 'call_coordinator.dart';
import 'call_negotiation_material_store.dart';

/// Expected failures reported by app-owned media and signaling adapters.
enum CallNegotiationPortErrorCode {
  permissionDenied,
  mediaUnavailable,
  signalingUnavailable,
  iceServersUnavailable,
}

/// A fixed-shape adapter failure. Raw media and signaling data are excluded.
final class CallNegotiationPortException implements Exception {
  const CallNegotiationPortException(this.code);

  final CallNegotiationPortErrorCode code;

  @override
  String toString() => 'CallNegotiationPortException(${code.name})';
}

/// Prepares microphone permission, audio ownership, and the engine connection.
///
/// The executor invokes this port only after the reducer has committed local
/// acceptance. Implementations may adapt the app's audio controller without
/// exposing that controller's API to the negotiation seam.
abstract interface class CallNegotiationMediaPreparer {
  Future<void> prepareLocallyAcceptedMedia({
    required CallSessionSnapshot snapshot,
    required CallConnectionConfiguration configuration,
  });
}

/// Sends authenticated descriptions and engine-approved local candidates.
abstract interface class CallNegotiationSignalingPort {
  Future<void> sendIceRestart({
    required CallId callId,
    required int iceGeneration,
  });

  Future<void> sendDescription({
    required CallId callId,
    required CallSessionDescription description,
    required int iceGeneration,
  });

  Future<void> sendCandidates({
    required CallId callId,
    required List<CallIceCandidate> candidates,
  });
}

typedef CallNegotiationEventDispatcher = Future<void> Function(CallEvent event);
typedef CallNegotiationSnapshotReader = CallSessionSnapshot? Function();
typedef CallStagedIceServerReader =
    Future<List<CallIceServer>> Function(CallId callId);

/// Executes only reducer-approved media effects and bridges engine state back
/// through the one process-owned call coordinator.
final class CallNegotiationEffectExecutor implements CallEffectExecutor {
  CallNegotiationEffectExecutor({
    required this.engine,
    required this.materialStore,
    required this.mediaPreparer,
    required this.signaling,
    required this.configuration,
    required this.dispatchEvent,
    required this.readActiveSnapshot,
    required this.readStagedIceServers,
    required this.clock,
    this.maxPendingLocalCandidates = 64,
    this.maxPendingRemoteCandidates = 64,
    this.maxLocalCandidateBatchSize = 8,
    CallTimerScheduler? mediaReadinessTimerScheduler,
    this.mediaReadinessPollInterval = const Duration(milliseconds: 100),
    this.maxMediaReadinessSamples,
  }) : _mediaReadinessTimerScheduler =
           mediaReadinessTimerScheduler ?? const DartCallTimerScheduler() {
    if (maxPendingLocalCandidates <= 0 ||
        maxPendingRemoteCandidates <= 0 ||
        maxLocalCandidateBatchSize <= 0 ||
        maxLocalCandidateBatchSize > maxPendingLocalCandidates) {
      throw ArgumentError(
        'candidate egress bounds must be positive and nested',
      );
    }
    if (mediaReadinessPollInterval <= Duration.zero ||
        (maxMediaReadinessSamples != null && maxMediaReadinessSamples! <= 0)) {
      throw ArgumentError('media readiness sampling bounds must be positive');
    }
    _engineEventSubscription = engine.events.listen(
      _onEngineEvent,
      onError: _onEngineStreamError,
      onDone: _onEngineStreamDone,
    );
    _candidateSubscription = engine.localCandidates.listen(
      _onLocalCandidate,
      onError: _onCandidateStreamError,
    );
  }

  final CallEngine engine;
  final CallNegotiationMaterialStore materialStore;
  final CallNegotiationMediaPreparer mediaPreparer;
  final CallNegotiationSignalingPort signaling;
  final CallConnectionConfiguration configuration;
  final CallNegotiationEventDispatcher dispatchEvent;
  final CallNegotiationSnapshotReader readActiveSnapshot;
  final CallStagedIceServerReader readStagedIceServers;
  final DateTime Function() clock;
  final int maxPendingLocalCandidates;
  final int maxPendingRemoteCandidates;
  final int maxLocalCandidateBatchSize;
  final Duration mediaReadinessPollInterval;

  /// Optional fail-safe for isolated owners without a canonical setup timer.
  ///
  /// Production leaves this unset so the coordinator's negotiation deadline is
  /// the single authority that bounds readiness observation.
  final int? maxMediaReadinessSamples;
  final CallTimerScheduler _mediaReadinessTimerScheduler;

  late final StreamSubscription<CallEngineEvent> _engineEventSubscription;
  late final StreamSubscription<CallIceCandidate> _candidateSubscription;
  final Set<CallId> _trackedCallIds = <CallId>{};
  final Set<CallId> _mediaPreparationAttempted = <CallId>{};
  final Set<CallId> _mediaPrepared = <CallId>{};
  final Set<CallId> _offerAttempted = <CallId>{};
  final ListQueue<_PendingLocalCandidate> _pendingLocalCandidates =
      ListQueue<_PendingLocalCandidate>();
  final ListQueue<CallIceCandidate> _pendingRemoteCandidates =
      ListQueue<CallIceCandidate>();
  final Set<int> _announcedLocalDescriptionGenerations = <int>{};
  int? _remoteDescriptionGeneration;

  Future<void>? _candidateDrainFuture;
  Future<void>? _engineEventDrainFuture;
  Future<void>? _closeFuture;
  CallEngineEvent? _pendingEngineEvent;
  CallTimerHandle? _mediaReadinessTimer;
  CallId? _mediaReadinessCallId;
  CallEventType? _mediaReadinessEventType;
  final Set<(CallId, CallEventType)> _closedMediaReadinessPhases =
      <(CallId, CallEventType)>{};
  int _candidateInFlightCount = 0;
  int _nextEventSequence = 0;
  int _dispatchFailureCount = 0;
  int _mediaReadinessEpoch = 0;
  int _mediaReadinessSampleCount = 0;
  bool _restartAttempted = false;
  bool _candidateEgressFailed = false;
  bool _candidateFailureDispatched = false;
  bool _closed = false;
  bool _engineEventSubscriptionClosed = false;
  bool _candidateSubscriptionClosed = false;
  bool _engineClosed = false;

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    if (_closed) return null;
    final callId = snapshot.callId;
    if (callId == null) return null;
    _trackedCallIds.add(callId);

    try {
      switch (effect.type) {
        case CallEffectType.prepareAcceptedMedia:
          await _prepareMedia(snapshot);
          return null;
        case CallEffectType.startNegotiation:
          return await _startNegotiation(snapshot);
        case CallEffectType.deliverOffer:
          return await _deliverOffer(snapshot);
        case CallEffectType.deliverAnswer:
          return await _deliverAnswer(snapshot);
        case CallEffectType.queueIceCandidate:
          return await _queueIceCandidate(snapshot);
        case CallEffectType.restartIce:
          return await _restartIce(snapshot);
        case CallEffectType.requestIceRestart:
          return await _requestIceRestart(snapshot);
        default:
          return null;
      }
    } on CallNegotiationPortException catch (error) {
      return _followUp(
        CallEventType.negotiationFailed,
        snapshot,
        endReason: error.code == CallNegotiationPortErrorCode.permissionDenied
            ? CallEndReason.permissionDenied
            : null,
      );
    } on CallEngineException {
      return _followUp(CallEventType.negotiationFailed, snapshot);
    }
  }

  Future<CallEvent?> _startNegotiation(CallSessionSnapshot snapshot) async {
    if (!_canStartNegotiation(snapshot.state)) return null;
    final callId = snapshot.callId!;
    if (!_offerAttempted.add(callId)) return null;

    await _prepareMedia(snapshot);
    final offer = await engine.createOffer();
    if (_closed) return null;
    if (!_isAuthenticatedDescription(offer, CallSessionDescriptionType.offer)) {
      return _followUp(CallEventType.negotiationFailed, snapshot);
    }
    await engine.setLocalDescription(offer);
    if (_closed) return null;
    await signaling.sendDescription(
      callId: callId,
      description: offer,
      iceGeneration: engine.iceGeneration,
    );
    _announceLocalDescription(engine.iceGeneration);
    return _followUp(CallEventType.negotiationReady, snapshot);
  }

  Future<CallEvent?> _deliverOffer(CallSessionSnapshot snapshot) async {
    if (snapshot.state != CallState.negotiating &&
        snapshot.state != CallState.reconnecting) {
      return null;
    }
    final material = _takeRecentMaterial(snapshot);
    if (material == null) return null;
    if (material.type != CallNegotiationMaterialType.offer) {
      return _followUp(CallEventType.negotiationFailed, snapshot);
    }
    if (material.iceGeneration != engine.iceGeneration) {
      // The caller's restart announcement can be lost while its offer still
      // arrives; the callee mirrors the announced generation from the offer.
      if (snapshot.direction != CallDirection.incoming ||
          snapshot.state != CallState.reconnecting ||
          material.iceGeneration != engine.iceGeneration + 1) {
        return _followUp(CallEventType.negotiationFailed, snapshot);
      }
      final mirrored = await _mirrorAnnouncedRestart(
        snapshot,
        material.iceGeneration,
      );
      if (mirrored != null) return mirrored;
      if (_closed) return null;
    }
    final offer = _descriptionFromMaterial(
      material,
      CallSessionDescriptionType.offer,
    );
    if (offer == null) {
      return _followUp(CallEventType.negotiationFailed, snapshot);
    }

    await _prepareMedia(snapshot);
    if (!_isCurrentRemoteWork(snapshot, material.iceGeneration)) return null;
    await engine.setRemoteDescription(offer);
    if (!await _acceptRemoteDescription(snapshot, material.iceGeneration)) {
      return null;
    }
    final answer = await engine.createAnswer();
    if (_closed) return null;
    if (!_isAuthenticatedDescription(
      answer,
      CallSessionDescriptionType.answer,
    )) {
      return _followUp(CallEventType.negotiationFailed, snapshot);
    }
    await engine.setLocalDescription(answer);
    if (_closed) return null;
    await signaling.sendDescription(
      callId: snapshot.callId!,
      description: answer,
      iceGeneration: engine.iceGeneration,
    );
    _announceLocalDescription(engine.iceGeneration);
    return null;
  }

  Future<CallEvent?> _deliverAnswer(CallSessionSnapshot snapshot) async {
    if (snapshot.state != CallState.negotiating &&
        snapshot.state != CallState.reconnecting) {
      return null;
    }
    final material = _takeRecentMaterial(snapshot);
    if (material == null) return null;
    if (material.type != CallNegotiationMaterialType.answer) {
      return _followUp(CallEventType.negotiationFailed, snapshot);
    }
    if (material.iceGeneration != engine.iceGeneration) {
      return _followUp(CallEventType.negotiationFailed, snapshot);
    }
    final answer = _descriptionFromMaterial(
      material,
      CallSessionDescriptionType.answer,
    );
    if (answer == null) {
      return _followUp(CallEventType.negotiationFailed, snapshot);
    }
    await engine.setRemoteDescription(answer);
    await _acceptRemoteDescription(snapshot, material.iceGeneration);
    return null;
  }

  Future<CallEvent?> _queueIceCandidate(CallSessionSnapshot snapshot) async {
    if (!_canApplyCandidate(snapshot.state)) return null;
    final material = _takeRecentMaterial(snapshot);
    if (material == null) return null;
    if (material.type != CallNegotiationMaterialType.ice) {
      return _followUp(CallEventType.negotiationFailed, snapshot);
    }
    final candidate = _candidateFromMaterial(material);
    if (candidate == null) {
      return _followUp(CallEventType.negotiationFailed, snapshot);
    }
    final remoteGeneration = _remoteDescriptionGeneration;
    if (remoteGeneration == null ||
        candidate.iceGeneration > remoteGeneration) {
      if (_pendingRemoteCandidates.length >= maxPendingRemoteCandidates) {
        return _followUp(CallEventType.negotiationFailed, snapshot);
      }
      _pendingRemoteCandidates.addLast(candidate);
      return _candidateHandled(snapshot);
    }
    if (candidate.iceGeneration == remoteGeneration) {
      await engine.addIceCandidates(<CallIceCandidate>[candidate]);
    }
    return _candidateHandled(snapshot);
  }

  CallEvent? _candidateHandled(CallSessionSnapshot snapshot) {
    if (snapshot.pendingCandidateIds.isEmpty) return null;
    // This effect's immutable snapshot ends with the candidate it admitted.
    // The executor now owns it in its bounded pre-SDP queue, has delivered it,
    // or has discarded an obsolete generation. None remains reducer-pending.
    return _followUp(
      CallEventType.iceCandidateHandled,
      snapshot,
      candidateId: snapshot.pendingCandidateIds.last,
    );
  }

  Future<CallEvent?> _restartIce(CallSessionSnapshot snapshot) async {
    if (snapshot.state != CallState.negotiating &&
        snapshot.state != CallState.reconnecting) {
      return null;
    }
    final callId = snapshot.callId!;
    // A new reconnect episode may watch media readiness again.
    _closedMediaReadinessPhases.remove((callId, CallEventType.mediaRecovered));

    final material = _takeRecentMaterial(snapshot);
    if (material != null &&
        material.type != CallNegotiationMaterialType.iceRestart) {
      return _followUp(CallEventType.negotiationFailed, snapshot);
    }
    if (snapshot.direction == CallDirection.incoming) {
      // The caller owns ICE restarts. The callee only mirrors an announced
      // generation so the caller's new offer applies; a repeated or stale
      // announcement is a no-op.
      if (material == null || material.iceGeneration <= engine.iceGeneration) {
        // An offer can complete recovery before its delayed announcement.
        // The reducer has entered reconnecting for that announcement; restore
        // connected only if the existing media actually proves readiness.
        if (material != null &&
            snapshot.state == CallState.reconnecting &&
            (await engine.snapshot()).isMediaReady) {
          return _followUp(CallEventType.mediaRecovered, snapshot);
        }
        return null;
      }
      return _mirrorAnnouncedRestart(snapshot, material.iceGeneration);
    }
    // Caller: a local media loss or the callee's request starts exactly one
    // new generation per reconnect episode.
    if (_restartAttempted) return null;
    _restartAttempted = true;
    final generation = await engine.restartIce(
      iceServers: await _unexpiredStagedIceServers(callId),
    );
    await signaling.sendIceRestart(callId: callId, iceGeneration: generation);
    final offer = await engine.createOffer();
    if (!_isAuthenticatedDescription(offer, CallSessionDescriptionType.offer)) {
      return _followUp(CallEventType.negotiationFailed, snapshot);
    }
    await engine.setLocalDescription(offer);
    await signaling.sendDescription(
      callId: callId,
      description: offer,
      iceGeneration: generation,
    );
    _announceLocalDescription(generation);
    return null;
  }

  Future<CallEvent?> _mirrorAnnouncedRestart(
    CallSessionSnapshot snapshot,
    int announcedGeneration,
  ) async {
    _closedMediaReadinessPhases.remove((
      snapshot.callId!,
      CallEventType.mediaRecovered,
    ));
    final generation = await engine.restartIce(
      iceServers: await _unexpiredStagedIceServers(snapshot.callId!),
    );
    if (generation != announcedGeneration) {
      return _followUp(CallEventType.negotiationFailed, snapshot);
    }
    return null;
  }

  /// Callee-side media loss: ask the caller to restart ICE. The current
  /// generation marks the signal as a request; the caller answers with an
  /// announcement of the next generation and a fresh offer.
  Future<CallEvent?> _requestIceRestart(CallSessionSnapshot snapshot) async {
    if (snapshot.state != CallState.reconnecting) return null;
    final callId = snapshot.callId!;
    _closedMediaReadinessPhases.remove((callId, CallEventType.mediaRecovered));
    await signaling.sendIceRestart(
      callId: callId,
      iceGeneration: engine.iceGeneration,
    );
    return null;
  }

  Future<List<CallIceServer>> _unexpiredStagedIceServers(CallId callId) async {
    final now = clock().toUtc();
    final staged = await readStagedIceServers(callId);
    return List<CallIceServer>.unmodifiable(
      staged.where((server) => server.expiresAt.isAfter(now)),
    );
  }

  void _announceLocalDescription(int generation) {
    _announcedLocalDescriptionGenerations.add(generation);
    _ensureCandidateDrain();
  }

  bool _isCurrentRemoteWork(CallSessionSnapshot snapshot, int generation) {
    final active = _readSnapshotSafely();
    return !_closed &&
        !engine.isClosed &&
        engine.iceGeneration == generation &&
        active != null &&
        active.callId == snapshot.callId &&
        _canApplyCandidate(active.state);
  }

  Future<bool> _acceptRemoteDescription(
    CallSessionSnapshot snapshot,
    int generation,
  ) async {
    if (!_isCurrentRemoteWork(snapshot, generation)) return false;
    _remoteDescriptionGeneration = generation;
    final ready = <CallIceCandidate>[];
    final future = ListQueue<CallIceCandidate>();
    while (_pendingRemoteCandidates.isNotEmpty) {
      final candidate = _pendingRemoteCandidates.removeFirst();
      if (candidate.iceGeneration == generation) {
        ready.add(candidate);
      } else if (candidate.iceGeneration > generation) {
        future.addLast(candidate);
      }
    }
    _pendingRemoteCandidates.addAll(future);
    // Take ownership before awaiting: a partially applied batch must never be
    // replayed. Failures propagate to the coordinator's terminal cleanup.
    final capacity = engine.candidateBatchCapacity;
    for (var offset = 0; offset < ready.length; offset += capacity) {
      if (!_isCurrentRemoteWork(snapshot, generation) ||
          _remoteDescriptionGeneration != generation) {
        return false;
      }
      final end = offset + capacity;
      await engine.addIceCandidates(
        ready.sublist(offset, end < ready.length ? end : ready.length),
      );
    }
    return _isCurrentRemoteWork(snapshot, generation) &&
        _remoteDescriptionGeneration == generation;
  }

  Future<void> _prepareMedia(CallSessionSnapshot snapshot) async {
    final callId = snapshot.callId!;
    if (_mediaPrepared.contains(callId)) return;
    if (!_mediaPreparationAttempted.add(callId)) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.mediaUnavailable,
      );
    }
    await mediaPreparer.prepareLocallyAcceptedMedia(
      snapshot: snapshot,
      configuration: configuration,
    );
    if (_closed) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.mediaUnavailable,
      );
    }
    _mediaPrepared.add(callId);
  }

  CallNegotiationMaterial? _takeRecentMaterial(CallSessionSnapshot snapshot) {
    if (snapshot.recentEventIds.isEmpty) return null;
    return materialStore.take(snapshot.callId!, snapshot.recentEventIds.last);
  }

  static CallSessionDescription? _descriptionFromMaterial(
    CallNegotiationMaterial material,
    CallSessionDescriptionType type,
  ) {
    final description = material.payload['description'];
    final fingerprint = material.payload['fingerprint'];
    if (description is! String ||
        description.isEmpty ||
        fingerprint is! String ||
        fingerprint.isEmpty) {
      return null;
    }
    return CallSessionDescription(
      type: type,
      value: description,
      fingerprint: fingerprint,
    );
  }

  static CallIceCandidate? _candidateFromMaterial(
    CallNegotiationMaterial material,
  ) {
    final value = material.payload['candidate'];
    final mediaId = material.payload['media_id'];
    final mediaLineIndex = material.payload['media_line_index'];
    if (value is! String ||
        value.isEmpty ||
        (mediaId != null && mediaId is! String) ||
        (mediaLineIndex != null && mediaLineIndex is! int)) {
      return null;
    }
    return CallIceCandidate(
      value: value,
      mediaId: mediaId as String?,
      mediaLineIndex: mediaLineIndex as int?,
      iceGeneration: material.iceGeneration,
    );
  }

  static bool _isAuthenticatedDescription(
    CallSessionDescription description,
    CallSessionDescriptionType expectedType,
  ) =>
      description.type == expectedType &&
      description.value.isNotEmpty &&
      (description.fingerprint?.isNotEmpty ?? false);

  void _onLocalCandidate(CallIceCandidate candidate) {
    if (_closed || _candidateEgressFailed) return;
    final snapshot = _readSnapshotSafely();
    if (snapshot == null || !_canApplyCandidate(snapshot.state)) return;
    final callId = snapshot.callId;
    if (callId == null) return;
    _trackedCallIds.add(callId);
    if (candidate.iceGeneration != engine.iceGeneration) {
      _failCandidateEgress(snapshot);
      return;
    }

    final pendingCount =
        _pendingLocalCandidates.length + _candidateInFlightCount;
    if (pendingCount >= maxPendingLocalCandidates) {
      _failCandidateEgress(snapshot);
      return;
    }
    _pendingLocalCandidates.addLast(
      _PendingLocalCandidate(callId: callId, candidate: candidate),
    );
    _ensureCandidateDrain();
  }

  void _ensureCandidateDrain() {
    if (_closed ||
        _candidateEgressFailed ||
        _pendingLocalCandidates.isEmpty ||
        _candidateDrainFuture != null) {
      return;
    }
    if (!_announcedLocalDescriptionGenerations.contains(
      _pendingLocalCandidates.first.candidate.iceGeneration,
    )) {
      return;
    }
    final drain = _drainLocalCandidates();
    _candidateDrainFuture = drain;
    unawaited(drain);
  }

  Future<void> _drainLocalCandidates() async {
    try {
      while (!_closed &&
          !_candidateEgressFailed &&
          _pendingLocalCandidates.isNotEmpty) {
        final first = _pendingLocalCandidates.first;
        if (!_announcedLocalDescriptionGenerations.contains(
          first.candidate.iceGeneration,
        )) {
          return;
        }
        _pendingLocalCandidates.removeFirst();
        final batch = <CallIceCandidate>[first.candidate];
        while (batch.length < maxLocalCandidateBatchSize &&
            _pendingLocalCandidates.isNotEmpty &&
            _pendingLocalCandidates.first.callId == first.callId) {
          batch.add(_pendingLocalCandidates.removeFirst().candidate);
        }
        final current = _readSnapshotSafely();
        if (current?.callId != first.callId ||
            !_canApplyCandidate(current!.state)) {
          continue;
        }

        _candidateInFlightCount = batch.length;
        try {
          await signaling.sendCandidates(
            callId: first.callId,
            candidates: List<CallIceCandidate>.unmodifiable(batch),
          );
        } catch (_) {
          _failCandidateEgress(current);
          return;
        } finally {
          _candidateInFlightCount = 0;
        }
      }
    } finally {
      _candidateDrainFuture = null;
      if (!_closed &&
          !_candidateEgressFailed &&
          _pendingLocalCandidates.isNotEmpty) {
        scheduleMicrotask(_ensureCandidateDrain);
      }
    }
  }

  void _failCandidateEgress(CallSessionSnapshot snapshot) {
    if (_candidateEgressFailed) return;
    _candidateEgressFailed = true;
    _pendingLocalCandidates.clear();
    if (_candidateFailureDispatched || _closed) return;
    _candidateFailureDispatched = true;
    unawaited(
      _dispatchCanonical(_followUp(CallEventType.negotiationFailed, snapshot)),
    );
  }

  void _onCandidateStreamError(Object _, StackTrace _) {
    final snapshot = _readSnapshotSafely();
    if (snapshot != null) _failCandidateEgress(snapshot);
  }

  void _onEngineEvent(CallEngineEvent event) {
    if (_closed) return;
    if (_isFailureEngineEvent(event)) {
      _cancelMediaReadinessWatch(closeActivePhase: true);
    } else if (event.connectionState != CallConnectionState.connected) {
      _cancelMediaReadinessWatch();
    }
    final pending = _pendingEngineEvent;
    final pendingIsFailure = pending != null && _isFailureEngineEvent(pending);
    // Latest wins unless a failure is already pending: a `connected` that
    // follows a coalesced `checking` or `disconnected` must not be dropped,
    // or the readiness watch never runs and the reconnect timer fires.
    if (pending == null || _isFailureEngineEvent(event) || !pendingIsFailure) {
      _pendingEngineEvent = event;
    }
    _ensureEngineEventDrain();
  }

  void _ensureEngineEventDrain() {
    if (_closed ||
        _pendingEngineEvent == null ||
        _engineEventDrainFuture != null) {
      return;
    }
    final drain = _drainEngineEvents();
    _engineEventDrainFuture = drain;
    unawaited(drain);
  }

  Future<void> _drainEngineEvents() async {
    try {
      while (!_closed && _pendingEngineEvent != null) {
        final event = _pendingEngineEvent!;
        _pendingEngineEvent = null;
        await _bridgeEngineEvent(event);
      }
    } finally {
      _engineEventDrainFuture = null;
      if (!_closed && _pendingEngineEvent != null) {
        scheduleMicrotask(_ensureEngineEventDrain);
      }
    }
  }

  Future<void> _bridgeEngineEvent(CallEngineEvent event) async {
    final session = _readSnapshotSafely();
    if (session == null || session.callId == null || session.isTerminal) {
      _cancelMediaReadinessWatch();
      return;
    }
    _trackedCallIds.add(session.callId!);

    if (_isFailureEngineEvent(event)) {
      _closeMediaReadinessPhase(session);
      await _dispatchCanonical(
        _followUp(CallEventType.negotiationFailed, session),
      );
      return;
    }
    if (event.connectionState == CallConnectionState.disconnected) {
      if (session.state == CallState.connected) {
        // A new reconnect episode: allow one restart and one recovery watch.
        _restartAttempted = false;
        _closedMediaReadinessPhases.remove((
          session.callId!,
          CallEventType.mediaRecovered,
        ));
        await _dispatchCanonical(_followUp(CallEventType.mediaLost, session));
      }
      return;
    }
    if (event.connectionState != CallConnectionState.connected) return;

    final type = _mediaReadinessTypeFor(session.state);
    if (type == null) {
      _cancelMediaReadinessWatch();
      return;
    }
    await _startMediaReadinessWatch(session, type);
  }

  void _onEngineStreamError(Object _, StackTrace _) {
    _cancelMediaReadinessWatch(closeActivePhase: true);
    unawaited(_dispatchFailureForCurrentSnapshot());
  }

  void _onEngineStreamDone() {
    if (_closed) return;
    _cancelMediaReadinessWatch(closeActivePhase: true);
    unawaited(_dispatchFailureForCurrentSnapshot());
  }

  Future<void> _dispatchFailureForCurrentSnapshot() async {
    final snapshot = _readSnapshotSafely();
    if (snapshot == null || snapshot.callId == null || snapshot.isTerminal) {
      return;
    }
    _closeMediaReadinessPhase(snapshot);
    await _dispatchCanonical(
      _followUp(CallEventType.negotiationFailed, snapshot),
    );
  }

  Future<void> _startMediaReadinessWatch(
    CallSessionSnapshot session,
    CallEventType type,
  ) async {
    final callId = session.callId!;
    final phase = (callId, type);
    if (_closedMediaReadinessPhases.contains(phase)) return;
    if (_mediaReadinessCallId == callId && _mediaReadinessEventType == type) {
      return;
    }

    _cancelMediaReadinessWatch();
    _closedMediaReadinessPhases.removeWhere(
      (candidate) => candidate.$1 != callId,
    );
    _mediaReadinessCallId = callId;
    _mediaReadinessEventType = type;
    _mediaReadinessSampleCount = 0;
    final epoch = ++_mediaReadinessEpoch;
    await _sampleMediaReadiness(epoch);
  }

  Future<void> _sampleMediaReadiness(int epoch) async {
    var session = _currentMediaReadinessSession(epoch);
    if (session == null) return;
    _mediaReadinessSampleCount++;

    CallConnectionSnapshot media;
    try {
      media = await engine.snapshot();
    } on CallEngineException {
      session = _currentMediaReadinessSession(epoch);
      if (session == null) return;
      _closeMediaReadinessPhase(session, expectedEpoch: epoch);
      await _dispatchCanonical(
        _followUp(CallEventType.negotiationFailed, session),
      );
      return;
    }

    session = _currentMediaReadinessSession(epoch);
    if (session == null) return;
    if (media.isMediaReady) {
      final type = _mediaReadinessEventType!;
      _closedMediaReadinessPhases.add((session.callId!, type));
      _cancelMediaReadinessWatch(expectedEpoch: epoch);
      if (type == CallEventType.mediaRecovered) _restartAttempted = false;
      await _dispatchCanonical(_followUp(type, session));
      return;
    }
    final sampleLimit = maxMediaReadinessSamples;
    if (sampleLimit != null && _mediaReadinessSampleCount >= sampleLimit) {
      _closedMediaReadinessPhases.add((
        session.callId!,
        _mediaReadinessEventType!,
      ));
      _cancelMediaReadinessWatch(expectedEpoch: epoch);
      return;
    }

    _mediaReadinessTimer = _mediaReadinessTimerScheduler.schedule(
      mediaReadinessPollInterval,
      () async {
        if (_closed || epoch != _mediaReadinessEpoch) return;
        await _sampleMediaReadiness(epoch);
      },
    );
  }

  CallSessionSnapshot? _currentMediaReadinessSession(int epoch) {
    if (_closed || epoch != _mediaReadinessEpoch) return null;
    final callId = _mediaReadinessCallId;
    final type = _mediaReadinessEventType;
    if (callId == null || type == null) return null;
    final session = _readSnapshotSafely();
    if (session == null ||
        session.callId != callId ||
        session.isTerminal ||
        _mediaReadinessTypeFor(session.state) != type) {
      _cancelMediaReadinessWatch(expectedEpoch: epoch);
      return null;
    }
    return session;
  }

  void _closeMediaReadinessPhase(
    CallSessionSnapshot session, {
    int? expectedEpoch,
  }) {
    final callId = session.callId;
    final type = _mediaReadinessTypeFor(session.state);
    if (callId != null && type != null) {
      _closedMediaReadinessPhases.add((callId, type));
    }
    _cancelMediaReadinessWatch(
      expectedEpoch: expectedEpoch,
      closeActivePhase: true,
    );
  }

  void _cancelMediaReadinessWatch({
    int? expectedEpoch,
    bool closeActivePhase = false,
  }) {
    if (expectedEpoch != null && expectedEpoch != _mediaReadinessEpoch) return;
    final callId = _mediaReadinessCallId;
    final type = _mediaReadinessEventType;
    if (closeActivePhase && callId != null && type != null) {
      _closedMediaReadinessPhases.add((callId, type));
    }
    _mediaReadinessEpoch++;
    _mediaReadinessTimer?.cancel();
    _mediaReadinessTimer = null;
    _mediaReadinessCallId = null;
    _mediaReadinessEventType = null;
    _mediaReadinessSampleCount = 0;
  }

  Future<void> _dispatchCanonical(CallEvent event) async {
    if (_closed) return;
    try {
      await dispatchEvent(event);
    } catch (_) {
      _dispatchFailureCount++;
    }
  }

  CallSessionSnapshot? _readSnapshotSafely() {
    try {
      return readActiveSnapshot();
    } catch (_) {
      return null;
    }
  }

  CallEvent _followUp(
    CallEventType type,
    CallSessionSnapshot snapshot, {
    CallEndReason? endReason,
    String? candidateId,
  }) => CallEvent(
    type: type,
    eventId: 'call-negotiation-${type.name}-${_nextEventSequence++}',
    occurredAt: clock(),
    callId: snapshot.callId,
    endReason: endReason,
    candidateId: candidateId,
  );

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    if (!_closed) {
      final activeCallId = _readSnapshotSafely()?.callId;
      if (activeCallId != null) _trackedCallIds.add(activeCallId);
      _closed = true;
      _cancelMediaReadinessWatch();
      _pendingEngineEvent = null;
      _pendingLocalCandidates.clear();
      _pendingRemoteCandidates.clear();
    }
    final close = _runCloseAttempt();
    _closeFuture = close;
    return close;
  }

  Future<void> _runCloseAttempt() async {
    try {
      await _closeOnce();
    } catch (_) {
      _closeFuture = null;
      rethrow;
    }
  }

  Future<void> _closeOnce() async {
    Object? firstError;
    StackTrace? firstStack;

    Future<void> attempt(
      bool completed,
      Future<void> Function() action,
      void Function() markCompleted,
    ) async {
      if (completed) return;
      try {
        await action();
        markCompleted();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }

    await attempt(
      _engineEventSubscriptionClosed,
      _engineEventSubscription.cancel,
      () => _engineEventSubscriptionClosed = true,
    );
    await attempt(
      _candidateSubscriptionClosed,
      _candidateSubscription.cancel,
      () => _candidateSubscriptionClosed = true,
    );
    await attempt(_engineClosed, engine.close, () => _engineClosed = true);
    for (final callId in List<CallId>.of(_trackedCallIds)) {
      await attempt(false, () async {
        materialStore.purgeCall(callId);
      }, () => _trackedCallIds.remove(callId));
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
  }

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'closed': _closed,
    'trackedCallCount': _trackedCallIds.length,
    'offerAttempted': _offerAttempted.isNotEmpty,
    'restartAttempted': _restartAttempted,
    'candidateEgressFailed': _candidateEgressFailed,
    'mediaReadinessSampling': _mediaReadinessCallId != null,
    'pendingLocalCandidateCount':
        _pendingLocalCandidates.length + _candidateInFlightCount,
    'pendingRemoteCandidateCount': _pendingRemoteCandidates.length,
    'dispatchFailureCount': _dispatchFailureCount,
  };

  @override
  String toString() => 'CallNegotiationEffectExecutor(${toDiagnosticMap()})';

  static bool _canStartNegotiation(CallState state) =>
      state == CallState.accepted || state == CallState.negotiating;

  static bool _canApplyCandidate(CallState state) => switch (state) {
    CallState.accepted ||
    CallState.negotiating ||
    CallState.connected ||
    CallState.reconnecting => true,
    _ => false,
  };

  static bool _isFailureEngineEvent(CallEngineEvent event) =>
      event.type == CallEngineEventType.overflow ||
      event.type == CallEngineEventType.closed ||
      event.connectionState == CallConnectionState.failed ||
      event.connectionState == CallConnectionState.closed ||
      event.failureReason != CallFailureReason.none;

  static CallEventType? _mediaReadinessTypeFor(CallState state) =>
      switch (state) {
        CallState.negotiating => CallEventType.mediaConnected,
        CallState.reconnecting => CallEventType.mediaRecovered,
        _ => null,
      };
}

final class _PendingLocalCandidate {
  const _PendingLocalCandidate({required this.callId, required this.candidate});

  final CallId callId;
  final CallIceCandidate candidate;
}
