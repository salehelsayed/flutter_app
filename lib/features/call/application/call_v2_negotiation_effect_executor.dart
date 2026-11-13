import 'dart:async';
import 'dart:collection';
import 'dart:math';

import '../domain/call_engine.dart';
import '../domain/call_event.dart';
import '../domain/call_id.dart';
import '../domain/call_media.dart';
import '../domain/call_media_switch.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_signal_v2.dart';
import '../domain/call_state.dart';
import 'call_coordinator.dart';
import 'call_media_switch_effect_executor.dart';
import 'call_endpoint_resolver.dart';
import 'call_negotiation_effect_executor.dart';
import 'call_signaling_context_store.dart';
import 'handle_incoming_call_signal.dart';

/// The production binding uses ProductionCallV2SignalingAdapter.prepare and
/// the resulting immutable transmission. True means direct or mailbox custody;
/// a wake request alone is not delivery. No camera consent crosses this seam.
typedef SendCallV2MediaSignal =
    Future<bool> Function({
      required CallSignalV2 signal,
      required String callHandle,
      required ResolvedCallEndpoint admittedEndpoint,
      required bool Function() canApply,
    });

/// One call's v2 SDP/ICE owner. The legacy executor retains microphone,
/// engine-event and v1 ownership; its single candidate listener routes here.
///
/// Native jobs share one queue, but canonical dispatch never waits inside that
/// queue: the coordinator may execute another job before dispatch completes.
/// Two description slots are reserved separately from the bounded ICE queue,
/// so ICE arriving before SDP cannot prevent the offer that drains it.
final class CallV2NegotiationEffectExecutor
    implements CallEffectExecutor, CallMediaSwitchHost {
  CallV2NegotiationEffectExecutor({
    required this.callId,
    required this.legacy,
    required this.videoEngine,
    required this.contexts,
    required this.resolveEndpoint,
    required this.sendSignal,
    required this.canApply,
    required this.idSource,
    this.videoEnabled = false,
    this.maxPendingMedia = 64,
    this.monotonicNowMs,
    this.onMediaChanged,
    this.timerScheduler = const DartCallTimerScheduler(),
  }) {
    if (maxPendingMedia <= 0 || maxPendingMedia > 128) {
      throw ArgumentError.value(maxPendingMedia, 'maxPendingMedia');
    }
  }

  final CallId callId;
  final CallNegotiationEffectExecutor legacy;
  final CallVideoEngine videoEngine;
  final CallSignalingContextStore contexts;
  final Future<ResolvedCallEndpoint> Function(String) resolveEndpoint;
  final SendCallV2MediaSignal sendSignal;
  final bool Function() canApply;
  final String Function() idSource;
  final bool videoEnabled;
  final int maxPendingMedia;
  final int Function()? monotonicNowMs;
  final void Function()? onMediaChanged;
  final CallTimerScheduler timerScheduler;

  final Stopwatch _elapsed = Stopwatch()..start();
  final Map<String, _V2MediaWork> _descriptions = {};
  final LinkedHashSet<String> _seenIncoming = LinkedHashSet<String>();
  final ListQueue<_V2MediaWork> _remoteCandidates = ListQueue<_V2MediaWork>();
  final ListQueue<_V2LocalCandidate> _localCandidates =
      ListQueue<_V2LocalCandidate>();
  final Set<Future<void>> _background = {};
  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;
  CallSignalingContext? _context;
  ResolvedCallEndpoint? _originalEndpoint;
  CallVideoSession? _session;
  CallVideoNegotiation? _token;
  CallTimerHandle? _initialTimer;
  int? _initialExpiryMs;
  int? _elapsedDeadlineMs;
  int? _negotiationIceGeneration;
  String? _incomingNegotiationId;
  bool _offerStarted = false;
  bool _answerAdmitted = false;
  bool _remoteApplied = false;
  bool _localAnnounced = false;
  bool _initialCommitted = false;
  bool _localDrainScheduled = false;
  bool _remoteDrainScheduled = false;
  int _localInFlight = 0;
  int _remoteInFlight = 0;
  int _epoch = 0;
  bool _closed = false;
  bool _failed = false;

  CallMediaSwitchEffectExecutor? _switch;
  final Map<String, _CachedSwitchSignal> _switchSignals = {};
  final Map<String, _IncomingSwitchRequest> _switchRequests = {};
  bool _awaitingOptionalOffer = false;
  bool _mediaRetired = false;
  bool Function()? _optionalTokenCurrent;
  int _optionalJobs = 0;
  int _optionalSends = 0;
  int _optionalAuthority = 0;
  bool _optionalCommitPending = false;
  bool _pendingTakeoverBlocked = false;
  _V2Recovery? _recovery;
  final Map<CallSignalV2Type, _V2MediaWork> _recoveryIngress = {};
  int? _recoveryIngressEpisode;
  int? _observedReconnectGeneration;
  int? _observedReconnectDeadlineMs;
  CallVideoNegotiation? _remoteCameraToken;
  CallCameraState _remoteCamera = CallCameraState.off;
  int _remoteCameraSequence = -1;

  /// Receives the original canonical timer observation before recovery effects.
  void observeReconnectTimer(
    CallSessionSnapshot snapshot,
    Duration effectiveDelay,
  ) {
    if (!_initialCommitted ||
        !_ready ||
        snapshot.callId != callId ||
        snapshot.state != CallState.reconnecting ||
        snapshot.reconnectGeneration != _snapshot?.reconnectGeneration ||
        (_observedReconnectGeneration != null &&
            snapshot.reconnectGeneration <= _observedReconnectGeneration!)) {
      return;
    }
    _observedReconnectGeneration = snapshot.reconnectGeneration;
    _observedReconnectDeadlineMs =
        _monotonicMs + max(0, effectiveDelay.inMilliseconds);
    // Audio-focus loss can open the canonical episode before any ICE effect.
    // Retire consent now; a later transport upgrade keeps this same budget.
    _adoptRecovery(snapshot);
  }

  CallMediaSwitchEffectExecutor? get mediaSwitch {
    if (!current) return null;
    return _switch ??= CallMediaSwitchEffectExecutor(
      host: this,
      localIsCaller: _context!.direction == CallDirection.outgoing,
      initialMedia: _token!.media,
      settledRevision: _token!.mediaRevision,
      nowMs: () => _monotonicMs,
      idSource: idSource,
      videoEnabled: videoEnabled,
      timerScheduler: timerScheduler,
      onChanged: _switchChanged,
    );
  }

  bool get _switchRecoveryCurrent {
    final recovery = _recovery;
    return recovery != null && recovery.takeover && _recoveryCurrent(recovery);
  }

  bool get _repairRecoveryCurrent =>
      _switchRecoveryCurrent &&
      !_recovery!.prepared &&
      legacy.engine.iceGeneration == _recovery!.oldGeneration;

  void _switchChanged() {
    final recovery = _recovery;
    if (recovery != null && recovery.takeover) {
      _scheduleRecovery(recovery);
    }
    try {
      onMediaChanged?.call();
    } catch (_) {
      // A presentation observer cannot stop owned recovery progress.
    }
  }

  @override
  bool get current =>
      _ready &&
      _initialCommitted &&
      !_pendingTakeoverBlocked &&
      _snapshot?.state == CallState.connected;

  @override
  CallVideoSession get session => _session!;

  /// The same tail used by initial SDP and the single ICE listener.
  @override
  Future<void> serialize(Future<void> Function() job) {
    _optionalJobs++;
    final result = _tail.then<void>((_) async {
      final completingCommit =
          _optionalCommitPending &&
          _switch?.machine.phase == MediaSwitchPhase.committed;
      var completed = false;
      try {
        if (current || _repairRecoveryCurrent) {
          await job();
          completed = true;
        }
      } finally {
        _optionalJobs--;
        if (completed && completingCommit && current) {
          _optionalCommitPending = false;
        }
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<bool> freshUpgradeAuthority() async {
    if (!current) return false;
    _optionalAuthority++;
    try {
      await _freshAuthority();
      return current;
    } catch (_) {
      return false;
    } finally {
      _optionalAuthority--;
    }
  }

  @override
  CallVideoNegotiation beginNegotiation({
    required String negotiationId,
    required int revision,
    required CallMediaKind media,
    required bool Function() canApply,
  }) {
    final recovery = !current && _repairRecoveryCurrent ? _recovery : null;
    if ((!current && recovery == null) ||
        !_allowed(canApply) ||
        (recovery != null &&
            (media != CallMediaKind.audio ||
                revision != _switch?.machine.settledRevision))) {
      throw const _V2WorkRetired();
    }
    final preserveRemote = _awaitingOptionalOffer;
    _awaitingOptionalOffer = false;
    _mediaRetired = false;
    _localAnnounced = false;
    _remoteApplied = false;
    _localCandidates.clear();
    if (preserveRemote) {
      _remoteCandidates.removeWhere(
        (work) => work.signal.payload['negotiation_id'] != negotiationId,
      );
    } else {
      _remoteCandidates.clear();
    }
    final epoch = ++_epoch;
    if (recovery != null) recovery.epoch = epoch;
    _optionalTokenCurrent = canApply;
    _token = _session!.beginNegotiation(
      negotiationId: negotiationId,
      mediaRevision: revision,
      media: media,
      canApply: () =>
          (current || _repairRecoveryCurrent) &&
          _epoch == epoch &&
          !_mediaRetired &&
          _allowed(canApply),
    );
    if (recovery != null) {
      recovery.oldToken = _token!;
      recovery.media = media;
      recovery.revision = revision;
    }
    return _token!;
  }

  @override
  void expectRemoteOffer() {
    if (_awaitingOptionalOffer) return;
    _awaitingOptionalOffer = true;
    _mediaRetired = true;
    _localAnnounced = false;
    _remoteApplied = false;
    _localCandidates.clear();
    _remoteCandidates.clear();
  }

  @override
  Future<void> remoteDescriptionApplied(CallVideoNegotiation token) async {
    if (!identical(token, _token) || !_candidateReady) {
      throw const _V2WorkRetired();
    }
    _remoteApplied = true;
    await _flushRemoteCandidates();
    if (!identical(token, _token) || !_candidateReady) {
      throw const _V2WorkRetired();
    }
  }

  @override
  void localDescriptionAnnounced(CallVideoNegotiation token) {
    if (!identical(token, _token) || !_candidateReady) return;
    _localAnnounced = true;
    _scheduleLocalDrain();
  }

  @override
  Future<bool> closeVideo() {
    _mediaRetired = true;
    _awaitingOptionalOffer = false;
    _localAnnounced = false;
    _remoteApplied = false;
    _localCandidates.clear();
    _remoteCandidates.clear();
    return _session?.retireVideo() ?? Future.value(true);
  }

  @override
  Future<bool> sendControl(
    MediaSwitchEffect effect, {
    required bool Function() canApply,
  }) {
    final kind = effect.replayOf ?? effect.kind;
    if (effect.kind == MediaSwitchEffectKind.sendAck) {
      _optionalCommitPending = true;
    }
    final (event, payload) = switch (kind) {
      MediaSwitchEffectKind.sendRequest => (
        CallSignalV2Type.mediaRequest,
        <String, Object?>{
          'switch_id': effect.switchId,
          'base_revision': effect.baseRevision,
          'target_media': effect.media.name,
          'camera': effect.camera.name,
        },
      ),
      MediaSwitchEffectKind.sendResponse => (
        CallSignalV2Type.mediaResponse,
        <String, Object?>{
          'switch_id': effect.switchId,
          'base_revision': effect.baseRevision,
          'decision': effect.response!.name,
          'camera': effect.camera.name,
        },
      ),
      MediaSwitchEffectKind.sendCommit || MediaSwitchEffectKind.sendAck => (
        kind == MediaSwitchEffectKind.sendCommit
            ? CallSignalV2Type.mediaCommit
            : CallSignalV2Type.mediaCommitAck,
        <String, Object?>{
          'switch_id': effect.switchId,
          'media_revision': effect.revision,
          'media': effect.media.name,
        },
      ),
      MediaSwitchEffectKind.sendAbort => (
        CallSignalV2Type.mediaAbort,
        <String, Object?>{
          'switch_id': effect.switchId,
          'base_revision': effect.baseRevision,
          'media_revision': effect.revision,
          'media': 'audio',
          'reason': effect.abortReason!.name,
        },
      ),
      _ => throw const _V2WorkRetired(),
    };
    final key =
        '${effect.switchId}:${kind.name}:${effect.response?.name}:${effect.deadlineMs}';
    return _sendOptional(
      key: key,
      event: event,
      payload: payload,
      deadlineMs: effect.deadlineMs,
      canApply: canApply,
      reservedAbort: kind == MediaSwitchEffectKind.sendAbort,
    );
  }

  @override
  Future<bool> sendDescription({
    required String switchId,
    required CallVideoNegotiation token,
    required CallSessionDescription description,
    required bool repair,
    required int deadlineMs,
    required bool Function() canApply,
  }) => _sendOptional(
    key: '${token.negotiationId}:${description.type.name}',
    event: description.type == CallSessionDescriptionType.offer
        ? CallSignalV2Type.offer
        : CallSignalV2Type.answer,
    payload: {
      'negotiation_id': token.negotiationId,
      'purpose': repair ? 'media_repair' : 'media_switch',
      'switch_id': switchId,
      'media_revision': token.mediaRevision,
      'media': token.media.name,
      'description': description.value,
      'fingerprint': description.fingerprint,
    },
    deadlineMs: deadlineMs,
    canApply: () => identical(token, _token) && _allowed(canApply),
  );

  Future<bool> _sendOptional({
    required String key,
    required CallSignalV2Type event,
    required Map<String, Object?> payload,
    required int deadlineMs,
    required bool Function() canApply,
    bool reservedAbort = false,
  }) async {
    bool authority() {
      if (current) return true;
      if (!_switchRecoveryCurrent ||
          payload['switch_id'] != _switch?.machine.selectedSwitchId) {
        return false;
      }
      return const {
            CallSignalV2Type.mediaAbort,
            CallSignalV2Type.mediaCommit,
            CallSignalV2Type.mediaCommitAck,
          }.contains(event) ||
          (_repairRecoveryCurrent &&
              (event == CallSignalV2Type.offer ||
                  event == CallSignalV2Type.answer) &&
              payload['purpose'] == 'media_repair' &&
              payload['media'] == 'audio');
    }

    if (!authority() || !_allowed(canApply) || _monotonicMs >= deadlineMs) {
      return false;
    }
    final generation = legacy.engine.iceGeneration;
    final generationKey = '$generation:$key';
    var cached = _switchSignals[generationKey];
    if (cached == null) {
      if (_switchSignals.length >= (reservedAbort ? 64 : 60)) return false;
      final now = _nowMs;
      final expires = min(
        _originalEndpoint!.expiresAtMs,
        now + min(30000, deadlineMs - _monotonicMs),
      );
      if (expires <= now) return false;
      final metadata = contexts.reserveNextMetadata(
        callId,
        iceGeneration: legacy.engine.iceGeneration,
      );
      final context = _context!;
      final signal = CallSignalV2.fromMap({
        'schema': CallSignalV2.schema,
        'call_id': callId.value,
        'message_id': idSource(),
        'event': event.wireName,
        'sender_account_peer_id': context.localAccountPeerId,
        'sender_device_peer_id': context.localDevicePeerId,
        'recipient_account_peer_id': context.remoteAccountPeerId,
        'recipient_device_peer_id': context.remoteDevicePeerId,
        'sender_sequence': metadata.senderSequence,
        'ice_generation': metadata.iceGeneration,
        'created_at_ms': now,
        'expires_at_ms': expires,
        'payload': payload,
      }, videoEnabled: videoEnabled);
      cached = _CachedSwitchSignal(signal, deadlineMs, canApply);
      // Reserving before the first await retains exact IDs through retries.
      // The shared production adapter reserves the immutable sealed bytes.
      _switchSignals[generationKey] = cached;
    } else if (cached.signal.event != event ||
        cached.deadlineMs != deadlineMs ||
        cached.signal.payload.length != payload.length ||
        !payload.keys.every(
          (key) => cached!.signal.payload[key] == payload[key],
        )) {
      return false;
    }
    final captured = cached;
    bool valid() =>
        authority() &&
        captured.signal.iceGeneration == legacy.engine.iceGeneration &&
        _monotonicMs < captured.deadlineMs &&
        _nowMs < captured.signal.expiresAtMs &&
        _allowed(captured.canApply) &&
        _allowed(canApply);
    if (!valid()) return false;
    _optionalSends++;
    try {
      final delivered = await sendSignal(
        signal: captured.signal,
        callHandle: _context!.callHandle,
        admittedEndpoint: _originalEndpoint!,
        canApply: valid,
      );
      return delivered && valid();
    } finally {
      _optionalSends--;
    }
  }

  IncomingCallSignalOutcome _handleSwitch(_V2MediaWork work) {
    final owner = current
        ? mediaSwitch
        : (_switchRecoveryCurrent ? _switch : null);
    if (owner == null) return IncomingCallSignalOutcome.rejected;
    final signal = work.signal;
    final p = signal.payload;
    if (!current &&
        (p['switch_id'] != owner.machine.selectedSwitchId ||
            (!const {
                  CallSignalV2Type.mediaAbort,
                  CallSignalV2Type.mediaCommit,
                  CallSignalV2Type.mediaCommitAck,
                }.contains(signal.event) &&
                !(_repairRecoveryCurrent &&
                    (signal.event == CallSignalV2Type.offer ||
                        signal.event == CallSignalV2Type.answer) &&
                    p['purpose'] == 'media_repair' &&
                    p['media'] == 'audio')))) {
      return IncomingCallSignalOutcome.rejected;
    }
    final remoteIsCaller = _context!.direction == CallDirection.incoming;
    bool accepted;
    switch (signal.event) {
      case CallSignalV2Type.mediaRequest:
        final id = p['switch_id']! as String;
        var known = _switchRequests[id];
        if (known == null) {
          if (_switchRequests.length >= owner.maximumTransactions) {
            return IncomingCallSignalOutcome.deferred;
          }
          final age = max(0, _nowMs - signal.createdAtMs);
          final request = MediaSwitchRequest(
            id: id,
            baseRevision: p['base_revision']! as int,
            target: CallMediaKind.values.byName(p['target_media']! as String),
            requesterIsCaller: remoteIsCaller,
            createdAtMs: _monotonicMs - age,
            deadlineMs:
                _monotonicMs + min(signal.expiresAtMs - _nowMs, 30000 - age),
            camera: CallCameraState.values.byName(p['camera']! as String),
          );
          known = _IncomingSwitchRequest(
            request,
            signal.createdAtMs,
            signal.expiresAtMs,
          );
          _switchRequests[id] = known;
        } else if (known.createdAtMs != signal.createdAtMs ||
            known.expiresAtMs != signal.expiresAtMs ||
            known.request.baseRevision != p['base_revision'] ||
            known.request.target.name != p['target_media'] ||
            known.request.camera.name != p['camera']) {
          return IncomingCallSignalOutcome.rejected;
        }
        accepted = owner.request(
          known.request,
          canApply: () => _workCurrent(work),
        );
      case CallSignalV2Type.mediaResponse:
        accepted = owner.respond(
          id: p['switch_id']! as String,
          baseRevision: p['base_revision']! as int,
          fromCaller: remoteIsCaller,
          response: MediaSwitchResponse.values.byName(p['decision']! as String),
          camera: CallCameraState.values.byName(p['camera']! as String),
          canApply: () => _workCurrent(work),
        );
      case CallSignalV2Type.offer:
      case CallSignalV2Type.answer:
        if (p['purpose'] != 'media_switch' && p['purpose'] != 'media_repair') {
          return IncomingCallSignalOutcome.rejected;
        }
        accepted = owner.receiveDescription(
          id: p['switch_id']! as String,
          negotiationId: p['negotiation_id']! as String,
          revision: p['media_revision']! as int,
          media: CallMediaKind.values.byName(p['media']! as String),
          description: _description(signal),
          repair: p['purpose'] == 'media_repair',
          canApply: () => _workCurrent(work),
        );
      case CallSignalV2Type.mediaCommit:
        accepted = owner.receiveCommit(
          id: p['switch_id']! as String,
          revision: p['media_revision']! as int,
          media: CallMediaKind.values.byName(p['media']! as String),
        );
      case CallSignalV2Type.mediaCommitAck:
        final alreadyCommitted =
            owner.machine.phase == MediaSwitchPhase.committed;
        accepted = owner.receiveAck(
          id: p['switch_id']! as String,
          revision: p['media_revision']! as int,
          media: CallMediaKind.values.byName(p['media']! as String),
        );
        if (accepted && !alreadyCommitted) _optionalCommitPending = true;
      case CallSignalV2Type.mediaAbort:
        accepted = owner.abort(
          id: p['switch_id']! as String,
          baseRevision: p['base_revision']! as int,
          revision: p['media_revision']! as int,
          remote: true,
          reason: MediaSwitchAbortReason.values.byName(p['reason']! as String),
        );
      default:
        return IncomingCallSignalOutcome.rejected;
    }
    if (accepted && _seenIncoming.length < 128) {
      _seenIncoming.add(signal.messageId);
    }
    return accepted
        ? IncomingCallSignalOutcome.accepted
        : IncomingCallSignalOutcome.rejected;
  }

  bool _reservedSwitchControl(CallSignalV2 signal) {
    final owner = _switch;
    if (!_initialCommitted || owner == null) return false;
    final id = signal.payload['switch_id'];
    return switch (signal.event) {
      CallSignalV2Type.mediaResponse => id == owner.machine.currentSwitchId,
      CallSignalV2Type.offer || CallSignalV2Type.answer =>
        id == owner.machine.selectedSwitchId &&
            (signal.payload['purpose'] == 'media_switch' ||
                signal.payload['purpose'] == 'media_repair'),
      CallSignalV2Type.mediaAbort ||
      CallSignalV2Type.mediaCommit ||
      CallSignalV2Type.mediaCommitAck => id == owner.machine.selectedSwitchId,
      _ => false,
    };
  }

  bool get _candidateReady =>
      _ready &&
      !_mediaRetired &&
      !_awaitingOptionalOffer &&
      (_optionalTokenCurrent == null || _allowed(_optionalTokenCurrent!));

  CallVideoSession? get videoSession => _session;
  CallVideoNegotiation? get negotiation => _token;

  /// Authenticated presentation hint for the current committed video token.
  /// It never authorizes local capture and disappears with that token's gates.
  CallCameraState get remoteCamera {
    final token = _currentCameraToken;
    return token != null && identical(token, _remoteCameraToken)
        ? _remoteCamera
        : CallCameraState.off;
  }

  CallVideoNegotiation? get _currentCameraToken {
    final token = _token;
    if (!current ||
        !_candidateReady ||
        token == null ||
        token.media != CallMediaKind.video ||
        (_switch?.machine.settledMedia ?? token.media) != CallMediaKind.video ||
        (_switch?.machine.settledRevision ?? token.mediaRevision) !=
            token.mediaRevision) {
      return null;
    }
    return token;
  }

  /// Publishes an already-owned camera state through the existing bounded
  /// signaling custody. The foreground owner retains permission/lease checks;
  /// this operation does not start capture or change the media agreement.
  Future<bool> publishLocalCameraState(
    CallCameraState state, {
    required bool Function() canApply,
  }) async {
    final token = _currentCameraToken;
    if (token == null || !_allowed(canApply)) return false;
    try {
      return await _sendOptional(
        key: 'camera:${idSource()}',
        event: CallSignalV2Type.cameraState,
        payload: {'media_revision': token.mediaRevision, 'state': state.name},
        deadlineMs: _monotonicMs + 30000,
        canApply: () =>
            identical(token, _currentCameraToken) && _allowed(canApply),
      );
    } catch (_) {
      // A presentation hint failure cannot end the live audio call.
      return false;
    }
  }

  IncomingCallSignalOutcome _handleCameraState(CallSignalV2 signal) {
    final token = _currentCameraToken;
    if (token == null ||
        signal.payload['media_revision'] != token.mediaRevision ||
        (identical(token, _remoteCameraToken) &&
            signal.senderSequence <= _remoteCameraSequence)) {
      return IncomingCallSignalOutcome.rejected;
    }
    _remoteCameraToken = token;
    _remoteCameraSequence = signal.senderSequence;
    _remoteCamera = CallCameraState.values.byName(
      signal.payload['state']! as String,
    );
    _seenIncoming.add(signal.messageId);
    try {
      onMediaChanged?.call();
    } catch (_) {
      // Presentation observers cannot change authenticated message custody.
    }
    return IncomingCallSignalOutcome.accepted;
  }

  /// Completes after currently adopted jobs and canonical dispatch settle.
  /// ICE awaiting a future description remains bounded without blocking this.
  Future<void> get workSettled async {
    while (true) {
      final tail = _tail;
      await tail;
      await Future.wait<void>(_background.toList(growable: false));
      await _switch?.workSettled;
      if (identical(tail, _tail) && _background.isEmpty) return;
    }
  }

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    if (_closed || snapshot.callId != callId) return null;
    final context = contexts.read(callId);
    if (context?.wireVersion == CallWireVersion.v1) {
      return await legacy.execute(effect, snapshot);
    }
    if (!videoEnabled || !_callCurrent() || _failed) return null;
    if (_initialCommitted && snapshot.state == CallState.reconnecting) {
      _executeRecovery(effect, snapshot);
      return null;
    }
    if (context?.initialAcceptedMedia == null ||
        !_initialPhase(snapshot.state)) {
      return null;
    }
    if (!_bindContext(context!) || !_ensureInitialBudget()) {
      return _failure(snapshot);
    }
    switch (effect.type) {
      case CallEffectType.prepareAcceptedMedia:
        return await _queue(snapshot, () async {
          _check();
          final failure = await legacy.execute(effect, snapshot);
          _check();
          return failure;
        });
      case CallEffectType.startNegotiation:
        if (context.direction != CallDirection.outgoing || _offerStarted) {
          return null;
        }
        _offerStarted = true;
        return await _queue(snapshot, () => _startInitial(snapshot));
      case CallEffectType.deliverOffer:
      case CallEffectType.deliverAnswer:
        if (snapshot.recentEventIds.isEmpty) return null;
        final work = _descriptions.remove(snapshot.recentEventIds.last);
        if (work == null) return null;
        return await _queue(snapshot, () async {
          if (effect.type == CallEffectType.deliverOffer &&
              work.signal.event == CallSignalV2Type.offer) {
            return await _applyOffer(snapshot, work);
          }
          if (effect.type == CallEffectType.deliverAnswer &&
              work.signal.event == CallSignalV2Type.answer) {
            return await _applyAnswer(work);
          }
          return null;
        });
      default:
        // V2 effects never fall through to v1 signaling.
        return null;
    }
  }

  IncomingCallSignalOutcome handleAuthenticated({
    required CallSignalV2 signal,
    required String callHandle,
    required bool Function() canApply,
  }) {
    final context = contexts.read(callId);
    if (!videoEnabled ||
        _closed ||
        _failed ||
        !_callCurrent() ||
        context == null ||
        context.wireVersion != CallWireVersion.v2 ||
        context.initialAcceptedMedia == null ||
        !_bindContext(context) ||
        !_sameSignalBinding(signal, callHandle) ||
        !_allowed(canApply) ||
        signal.expiresAtMs <= _nowMs) {
      return IncomingCallSignalOutcome.rejected;
    }
    if (_initialCommitted &&
        (signal.event == CallSignalV2Type.iceRestart ||
            ((signal.event == CallSignalV2Type.offer ||
                    signal.event == CallSignalV2Type.answer) &&
                signal.payload['purpose'] == 'ice_restart'))) {
      return _handleRecovery(_V2MediaWork(signal, callHandle, canApply));
    }
    if (_initialCommitted &&
        signal.event == CallSignalV2Type.ice &&
        context.direction == CallDirection.incoming &&
        signal.iceGeneration == legacy.engine.iceGeneration + 1 &&
        _recoveryIngress.values.any(
          (work) =>
              work.signal.iceGeneration == signal.iceGeneration &&
              work.signal.payload['negotiation_id'] ==
                  signal.payload['negotiation_id'],
        )) {
      return IncomingCallSignalOutcome.deferred;
    }
    if (signal.iceGeneration != legacy.engine.iceGeneration ||
        (_negotiationIceGeneration != null &&
            signal.iceGeneration != _negotiationIceGeneration)) {
      return IncomingCallSignalOutcome.rejected;
    }
    final snapshot = _snapshot;
    if (snapshot == null ||
        (!_initialCommitted && !_initialPhase(snapshot.state)) ||
        !_ensureInitialBudget()) {
      return IncomingCallSignalOutcome.rejected;
    }
    if (_seenIncoming.contains(signal.messageId)) {
      return IncomingCallSignalOutcome.duplicate;
    }
    if (_seenIncoming.length >= 128 && !_reservedSwitchControl(signal)) {
      return IncomingCallSignalOutcome.deferred;
    }
    final work = _V2MediaWork(signal, callHandle, canApply);
    if (_initialCommitted && signal.event == CallSignalV2Type.cameraState) {
      return _handleCameraState(signal);
    }
    if (_initialCommitted && signal.event != CallSignalV2Type.ice) {
      return _handleSwitch(work);
    }
    switch (signal.event) {
      case CallSignalV2Type.offer:
      case CallSignalV2Type.answer:
        if (_initialCommitted ||
            signal.payload['purpose'] != 'initial' ||
            signal.payload['media_revision'] != 0 ||
            signal.payload['media'] != context.initialAcceptedMedia!.name) {
          return IncomingCallSignalOutcome.rejected;
        }
        final negotiationId = signal.payload['negotiation_id']! as String;
        if (signal.event == CallSignalV2Type.offer) {
          if (context.direction != CallDirection.incoming ||
              _incomingNegotiationId != null ||
              _token != null) {
            return IncomingCallSignalOutcome.rejected;
          }
        } else if (context.direction != CallDirection.outgoing ||
            _token?.negotiationId != negotiationId ||
            _answerAdmitted) {
          return IncomingCallSignalOutcome.rejected;
        }
        if (_descriptions.length >= 2) {
          return IncomingCallSignalOutcome.deferred;
        }
        if (signal.event == CallSignalV2Type.offer) {
          _incomingNegotiationId = negotiationId;
        } else {
          _answerAdmitted = true;
        }
        _seenIncoming.add(signal.messageId);
        _descriptions[signal.messageId] = work;
        _track(
          Future<void>.microtask(() async {
                if (!_workCurrent(work)) return;
                await legacy.dispatchEvent(_remoteEvent(work));
              })
              .catchError((Object _) async {
                final failure = _failure(snapshot);
                if (failure != null) await _dispatchSafely(failure);
              })
              .whenComplete(() {
                _descriptions.remove(signal.messageId);
              }),
        );
        return IncomingCallSignalOutcome.accepted;
      case CallSignalV2Type.ice:
        if (_initialCommitted && _mediaRetired && !_awaitingOptionalOffer) {
          return IncomingCallSignalOutcome.rejected;
        }
        final expectedId = _awaitingOptionalOffer
            ? null
            : (_token?.negotiationId ?? _incomingNegotiationId);
        if (expectedId != null &&
            signal.payload['negotiation_id'] != expectedId) {
          return IncomingCallSignalOutcome.rejected;
        }
        if (_remoteCandidates.length + _remoteInFlight >= maxPendingMedia) {
          return IncomingCallSignalOutcome.deferred;
        }
        _seenIncoming.add(signal.messageId);
        _remoteCandidates.addLast(work);
        _scheduleRemoteDrain();
        return IncomingCallSignalOutcome.accepted;
      default:
        return IncomingCallSignalOutcome.rejected;
    }
  }

  /// True takes custody (including a deliberate stale discard), preventing a
  /// v2 candidate from reaching the legacy sender.
  bool consumeLocalCandidate(
    CallSessionSnapshot snapshot,
    CallIceCandidate candidate,
  ) {
    if (_context?.wireVersion != CallWireVersion.v2 &&
        contexts.read(callId)?.wireVersion != CallWireVersion.v2) {
      return false;
    }
    final token = _token;
    if (!videoEnabled ||
        !_candidateReady ||
        token == null ||
        snapshot.callId != callId ||
        candidate.iceGeneration != legacy.engine.iceGeneration ||
        (!_initialCommitted && !_budgetOpen)) {
      return true;
    }
    if (_localCandidates.length + _localInFlight >= maxPendingMedia) {
      if (_initialCommitted && _switch != null) {
        _switch!.failOptionalMedia();
        return true;
      }
      final failure = _failure(snapshot);
      if (failure != null) _track(_dispatchSafely(failure));
      return true;
    }
    // Capture the token at arrival. A later negotiation cannot retag this ICE.
    _localCandidates.addLast(_V2LocalCandidate(token, candidate));
    _scheduleLocalDrain();
    return true;
  }

  IncomingCallSignalOutcome _handleRecovery(_V2MediaWork work) {
    final snapshot = _snapshot;
    final signal = work.signal;
    final payload = signal.payload;
    if (snapshot == null ||
        (snapshot.state != CallState.connected &&
            snapshot.state != CallState.reconnecting) ||
        _token == null) {
      return IncomingCallSignalOutcome.rejected;
    }
    final retained = _recovery;
    final recovery =
        retained?.snapshot.reconnectGeneration == snapshot.reconnectGeneration
        ? retained
        : null;
    if (recovery != null &&
        recovery.takeover &&
        !recovery.prepared &&
        _switch?.recoveryReady == false) {
      // A peer's advanced ICE tuple cannot replace unresolved same-generation
      // audio repair or its terminal custody.
      return IncomingCallSignalOutcome.rejected;
    }
    final caller = _context!.direction == CallDirection.outgoing;
    final revision = _switch?.machine.settledRevision ?? _token!.mediaRevision;
    final media = _switch?.machine.settledMedia ?? _token!.media;
    if (payload['media_revision'] != revision ||
        (signal.event != CallSignalV2Type.iceRestart &&
            payload['media'] != media.name)) {
      return IncomingCallSignalOutcome.rejected;
    }
    final negotiation = payload['negotiation_id'];
    final generation = legacy.engine.iceGeneration;
    if (signal.event == CallSignalV2Type.answer) {
      if (!caller ||
          recovery == null ||
          recovery.negotiationId != negotiation ||
          signal.iceGeneration != recovery.oldGeneration + 1 ||
          recovery.localDescription == null) {
        return IncomingCallSignalOutcome.rejected;
      }
      if (recovery.completed && snapshot.state == CallState.connected) {
        return IncomingCallSignalOutcome.duplicate;
      }
    } else if (caller) {
      if (signal.event != CallSignalV2Type.iceRestart ||
          signal.iceGeneration != generation ||
          negotiation != _token!.negotiationId) {
        return IncomingCallSignalOutcome.rejected;
      }
    } else {
      final matching =
          recovery != null &&
          recovery.negotiationId == negotiation &&
          signal.iceGeneration == recovery.oldGeneration + 1;
      if (matching &&
          recovery.completed &&
          snapshot.state == CallState.connected) {
        return IncomingCallSignalOutcome.duplicate;
      }
      if (!matching && signal.iceGeneration != generation + 1) {
        return IncomingCallSignalOutcome.rejected;
      }
      if (recovery != null &&
          snapshot.state == CallState.reconnecting &&
          recovery.negotiationId != null &&
          !matching) {
        return IncomingCallSignalOutcome.rejected;
      }
    }
    final episode =
        snapshot.reconnectGeneration +
        (snapshot.state == CallState.connected ? 1 : 0);
    if (_recoveryIngressEpisode != episode) {
      _recoveryIngress.clear();
      _recoveryIngressEpisode = episode;
    }
    final existing = _recoveryIngress[signal.event];
    if (existing != null) {
      final previous = existing.signal;
      return previous.iceGeneration == signal.iceGeneration &&
              previous.payload.length == payload.length &&
              payload.keys.every((key) => previous.payload[key] == payload[key])
          ? IncomingCallSignalOutcome.duplicate
          : IncomingCallSignalOutcome.rejected;
    }
    if (!caller &&
        _recoveryIngress.values.any(
          (other) =>
              other.signal.payload['negotiation_id'] != negotiation ||
              other.signal.iceGeneration != signal.iceGeneration,
        )) {
      return IncomingCallSignalOutcome.rejected;
    }
    _recoveryIngress[signal.event] = work;
    if (_seenIncoming.length < 128) _seenIncoming.add(signal.messageId);
    _track(
      Future<void>.microtask(() async {
        final current = _snapshot;
        if (!_callCurrent() ||
            !_allowed(work.canApply) ||
            signal.expiresAtMs <= _nowMs ||
            current == null ||
            !((current.state == CallState.connected &&
                    current.reconnectGeneration + 1 == episode) ||
                (current.state == CallState.reconnecting &&
                    current.reconnectGeneration == episode))) {
          return;
        }
        await legacy.dispatchEvent(_remoteEvent(work));
      }).catchError((Object _) async {
        final current = _snapshot;
        if (current == null ||
            !((current.state == CallState.connected &&
                    current.reconnectGeneration + 1 == episode) ||
                (current.state == CallState.reconnecting &&
                    current.reconnectGeneration == episode))) {
          return;
        }
        final failure = _failure(snapshot);
        if (failure != null) await _dispatchSafely(failure);
      }),
    );
    return IncomingCallSignalOutcome.accepted;
  }

  _V2Recovery? _adoptRecovery(CallSessionSnapshot snapshot) {
    if (!_ready || _session == null || _token == null) return null;
    final existing = _recovery;
    if (existing?.snapshot.reconnectGeneration ==
        snapshot.reconnectGeneration) {
      return existing;
    }
    final machine = _switch?.machine;
    final settled =
        machine == null ||
        const {
          null,
          MediaSwitchPhase.committed,
          MediaSwitchPhase.declined,
          MediaSwitchPhase.superseded,
        }.contains(machine.phase);
    final pending =
        !settled ||
        machine?.requiresReconciliation == true ||
        _optionalJobs != 0 ||
        _optionalSends != 0 ||
        _optionalAuthority != 0 ||
        _optionalCommitPending;
    final observed =
        _observedReconnectGeneration == snapshot.reconnectGeneration;
    final takeover = observed && !_pendingTakeoverBlocked;
    _pendingTakeoverBlocked = _pendingTakeoverBlocked || (pending && !takeover);
    existing?.timer?.cancel();
    final old = _token!;
    final recovery = _V2Recovery(
      snapshot: snapshot,
      oldToken: old,
      epoch: ++_epoch,
      oldGeneration: legacy.engine.iceGeneration,
      media: machine?.settledMedia ?? old.media,
      revision: machine?.settledRevision ?? old.mediaRevision,
      deadlineMs: min(
        _monotonicMs + 15000,
        observed ? _observedReconnectDeadlineMs! : _monotonicMs + 15000,
      ),
      blocked: _pendingTakeoverBlocked,
      takeover: takeover,
      transportRequested: !observed,
    );
    _recovery = recovery;
    _mediaRetired = true;
    _awaitingOptionalOffer = false;
    _optionalTokenCurrent = null;
    _localAnnounced = false;
    _remoteApplied = false;
    _localCandidates.clear();
    _remoteCandidates.clear();
    legacy.rearmMediaRecoveryObservation(snapshot);
    recovery.retirement = _session!.retireVideo().then(
      (closed) => closed,
      onError: (Object _, StackTrace _) => false,
    );
    _track(recovery.retirement!.then<void>((_) {}));
    final switches = _switch;
    if (takeover && switches != null) {
      _optionalCommitPending = false;
      switches.beginRecovery(
        reconnectGeneration: snapshot.reconnectGeneration,
        deadlineMs: recovery.deadlineMs,
        canApply: () => _recoveryCurrent(recovery),
      );
      recovery.media = switches.machine.settledMedia;
      recovery.revision = switches.machine.settledRevision;
    }
    return recovery;
  }

  void _executeRecovery(CallEffect effect, CallSessionSnapshot snapshot) {
    if (!const {
      CallEffectType.restartIce,
      CallEffectType.requestIceRestart,
      CallEffectType.resumeRecoverySignals,
      CallEffectType.deliverOffer,
      CallEffectType.deliverAnswer,
    }.contains(effect.type)) {
      return;
    }
    final recovery = _adoptRecovery(snapshot);
    if (recovery == null || recovery.blocked) return;
    final id = snapshot.recentEventIds.isEmpty
        ? null
        : snapshot.recentEventIds.last;
    final incoming = _recoveryIngress.values.where(
      (work) => work.signal.messageId == id,
    );
    final work = incoming.isEmpty ? null : incoming.first;
    if (effect.type != CallEffectType.resumeRecoverySignals || work != null) {
      recovery.transportRequested = true;
    }
    if (effect.type == CallEffectType.resumeRecoverySignals &&
        recovery.takeover &&
        !recovery.prepared &&
        _optionalSends == 0 &&
        _switch?.machine.requiresReconciliation == true) {
      _switch!.reconnect();
    }
    recovery.authorityWork ??= work;
    if (_context!.direction == CallDirection.incoming && work != null) {
      recovery.negotiationId ??=
          work.signal.payload['negotiation_id']! as String;
    }
    if (work?.signal.event == CallSignalV2Type.offer ||
        work?.signal.event == CallSignalV2Type.answer) {
      recovery.remoteWork ??= work;
    }
    _scheduleRecovery(recovery);
  }

  bool _recoveryCurrent(_V2Recovery recovery) {
    final snapshot = _snapshot;
    final authority = recovery.authorityWork;
    return identical(recovery, _recovery) &&
        !_closed &&
        !_failed &&
        !recovery.blocked &&
        !_pendingTakeoverBlocked &&
        _epoch == recovery.epoch &&
        _callCurrent() &&
        !legacy.engine.isClosed &&
        (authority == null ||
            (_allowed(authority.canApply) &&
                authority.signal.expiresAtMs > _nowMs &&
                _sameSignalBinding(authority.signal, authority.callHandle))) &&
        _validEndpoint(_originalEndpoint!) &&
        snapshot?.state == CallState.reconnecting &&
        snapshot?.reconnectGeneration ==
            recovery.snapshot.reconnectGeneration &&
        _monotonicMs < recovery.deadlineMs;
  }

  bool _recoveryTokenCurrent(_V2Recovery recovery) =>
      _epoch == recovery.epoch &&
      legacy.engine.iceGeneration == recovery.oldGeneration + 1 &&
      (_recoveryCurrent(recovery) ||
          (recovery.completed &&
              _ready &&
              !_pendingTakeoverBlocked &&
              _snapshot?.state == CallState.connected &&
              _snapshot?.reconnectGeneration ==
                  recovery.snapshot.reconnectGeneration));

  void _checkRecovery(_V2Recovery recovery, [_V2MediaWork? work]) {
    if (!_recoveryCurrent(recovery) ||
        (work != null &&
            (!_allowed(work.canApply) ||
                work.signal.expiresAtMs <= _nowMs ||
                !_sameSignalBinding(work.signal, work.callHandle) ||
                work.signal.iceGeneration != recovery.oldGeneration + 1 ||
                work.signal.payload['negotiation_id'] !=
                    recovery.negotiationId))) {
      throw const _V2WorkRetired();
    }
  }

  void _scheduleRecovery(_V2Recovery recovery) {
    if (!_recoveryCurrent(recovery)) return;
    recovery.needsDrive = true;
    if (recovery.scheduled) return;
    recovery.scheduled = true;
    final result = _tail.then<CallEvent?>((_) async {
      try {
        while (_recoveryCurrent(recovery) && recovery.needsDrive) {
          recovery.needsDrive = false;
          await _driveRecovery(recovery);
        }
      } on _V2WorkRetired {
        // Canonical End, timeout or successor episode owns retirement.
      } catch (_) {
        if (_recoveryCurrent(recovery)) return _failure(recovery.snapshot);
      } finally {
        recovery.scheduled = false;
      }
      return null;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _track(
      result.then<void>((failure) async {
        if (failure != null) await _dispatchSafely(failure);
      }),
    );
  }

  Future<void> _prepareRecovery(_V2Recovery recovery) async {
    if (recovery.prepared) return;
    _checkRecovery(recovery);
    if (!await recovery.retirement!) {
      recovery.blocked = true;
      return;
    }
    _checkRecovery(recovery);
    final session = _session!;
    if (session is! CallVideoSdpReconciler) {
      recovery.blocked = true;
      return;
    }
    final proof = await (session as CallVideoSdpReconciler).reconcilePending(
      recovery.oldToken,
      canApply: () => _recoveryCurrent(recovery),
    );
    _checkRecovery(recovery);
    if (proof == CallVideoSdpReconciliationOutcome.unreconciled) {
      recovery.blocked = true;
      return;
    }
    await _freshAuthority();
    _checkRecovery(recovery);
    final staged = await legacy.readStagedIceServers(callId);
    _checkRecovery(recovery);
    final now = legacy.clock().toUtc();
    final servers = [
      ...legacy.configuration.iceServers,
      ...staged,
    ].where((server) => server.expiresAt.isAfter(now)).toList(growable: false);
    if (legacy.configuration.transportPolicy == CallTransportPolicy.relayOnly &&
        !servers.any((server) => server.containsTurnUrl)) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.iceServersUnavailable,
      );
    }
    final generation = await legacy.engine.restartIce(iceServers: servers);
    _checkRecovery(recovery);
    if (generation != recovery.oldGeneration + 1) throw const _V2WorkRetired();
    _negotiationIceGeneration = generation;
    // Prior-generation media messages are rejected before custody. Retire their
    // bounded identity ledger so later recovery episodes can admit fresh ICE.
    _seenIncoming.clear();
    recovery.negotiationId ??= idSource();
    _token = session.beginNegotiation(
      negotiationId: recovery.negotiationId!,
      mediaRevision: recovery.revision,
      media: recovery.media,
      canApply: () => _recoveryTokenCurrent(recovery),
    );
    _optionalTokenCurrent = () => _recoveryTokenCurrent(recovery);
    _mediaRetired = false;
    recovery.prepared = true;
    if (recovery.takeover) {
      // Preserve the semantic outcome while using new-generation transport
      // custody. The machine bars a fresh switch base until delivery settles.
      _switch?.reconnect();
    }
  }

  Future<void> _driveRecovery(_V2Recovery recovery) async {
    _checkRecovery(recovery);
    if (recovery.takeover && !recovery.prepared) {
      final switches = _switch;
      if (switches != null && !switches.recoveryReady) {
        if (switches.machine.requiresReconciliation && _optionalSends == 0) {
          _armRecoveryRetry(recovery, reconcileSwitch: true);
        }
        return;
      }
      recovery.timer?.cancel();
      recovery.timer = null;
    }
    if (!recovery.transportRequested) return;
    final candidate = recovery.candidateSignal;
    if (candidate != null && await _deliverRecovery(recovery, candidate)) {
      recovery.candidateSignal = null;
      _scheduleLocalDrain();
    }
    if (recovery.completed) return;
    final caller = _context!.direction == CallDirection.outgoing;
    if (!caller && recovery.negotiationId == null) {
      recovery.requestSignal ??=
          _recoverySignal(recovery, CallSignalV2Type.iceRestart, {
            'negotiation_id': recovery.oldToken.negotiationId,
            'media_revision': recovery.revision,
          }, generation: recovery.oldGeneration);
      if (!recovery.requestDelivered) {
        recovery.requestDelivered = await _deliverRecovery(
          recovery,
          recovery.requestSignal!,
        );
      }
      return;
    }
    await _prepareRecovery(recovery);
    if (recovery.blocked) return;
    _checkRecovery(recovery);
    final token = _token!;
    if (caller) {
      recovery.announcement ??=
          _recoverySignal(recovery, CallSignalV2Type.iceRestart, {
            'negotiation_id': token.negotiationId,
            'media_revision': token.mediaRevision,
          });
      if (!recovery.announcementDelivered) {
        if (!await _deliverRecovery(recovery, recovery.announcement!)) return;
        recovery.announcementDelivered = true;
      }
      if (recovery.localDescription == null) {
        final offer = await _session!.createOffer(token);
        _checkRecovery(recovery);
        _validateDescription(offer, CallSessionDescriptionType.offer);
        await _session!.applyLocal(token, offer);
        _checkRecovery(recovery);
        recovery.localDescription = offer;
      }
      if (!await _publishRecoveryDescription(recovery)) return;
      final work = recovery.remoteWork;
      if (work == null) return;
      if (!recovery.remoteApplied) {
        _checkRecovery(recovery, work);
        await _session!.applyRemote(token, _description(work.signal));
        _checkRecovery(recovery, work);
        recovery.remoteApplied = true;
        _remoteApplied = true;
        await _flushRemoteCandidates();
        _checkRecovery(recovery, work);
      }
    } else {
      final work = recovery.remoteWork;
      if (work == null) return;
      _checkRecovery(recovery, work);
      if (!recovery.remoteApplied) {
        await _session!.applyRemote(token, _description(work.signal));
        _checkRecovery(recovery, work);
        recovery.remoteApplied = true;
        _remoteApplied = true;
        await _flushRemoteCandidates();
        _checkRecovery(recovery, work);
      }
      if (recovery.localDescription == null) {
        final answer = await _session!.createAnswer(token);
        _checkRecovery(recovery, work);
        _validateDescription(answer, CallSessionDescriptionType.answer);
        await _session!.applyLocal(token, answer);
        _checkRecovery(recovery, work);
        recovery.localDescription = answer;
      }
      if (!await _publishRecoveryDescription(recovery)) return;
    }
    await _session!.commit(token);
    _checkRecovery(recovery, recovery.remoteWork);
    recovery.completed = true;
    if (recovery.candidateSignal == null) {
      recovery.timer?.cancel();
      recovery.timer = null;
    }
    legacy.deferMediaRecoveryObservation(
      recovery.snapshot,
      legacy.engine.iceGeneration,
    );
  }

  Future<bool> _publishRecoveryDescription(_V2Recovery recovery) async {
    if (recovery.localDelivered) return true;
    final description = recovery.localDescription!;
    recovery.descriptionSignal ??= _recoverySignal(
      recovery,
      description.type == CallSessionDescriptionType.offer
          ? CallSignalV2Type.offer
          : CallSignalV2Type.answer,
      {
        'negotiation_id': recovery.negotiationId!,
        'purpose': 'ice_restart',
        'switch_id': null,
        'media_revision': recovery.revision,
        'media': recovery.media.name,
        'description': description.value,
        'fingerprint': description.fingerprint,
      },
    );
    if (!await _deliverRecovery(recovery, recovery.descriptionSignal!)) {
      return false;
    }
    recovery.localDelivered = true;
    _localAnnounced = true;
    _scheduleLocalDrain();
    return true;
  }

  CallSignalV2 _recoverySignal(
    _V2Recovery recovery,
    CallSignalV2Type event,
    Map<String, Object?> payload, {
    int? generation,
  }) {
    _checkRecovery(recovery);
    final now = _nowMs;
    final expires = min(
      _originalEndpoint!.expiresAtMs,
      now + recovery.deadlineMs - _monotonicMs,
    );
    if (expires <= now) throw const _V2WorkRetired();
    final metadata = contexts.reserveNextMetadata(
      callId,
      iceGeneration: generation ?? legacy.engine.iceGeneration,
    );
    final context = _context!;
    return CallSignalV2.fromMap({
      'schema': CallSignalV2.schema,
      'call_id': callId.value,
      'message_id': idSource(),
      'event': event.wireName,
      'sender_account_peer_id': context.localAccountPeerId,
      'sender_device_peer_id': context.localDevicePeerId,
      'recipient_account_peer_id': context.remoteAccountPeerId,
      'recipient_device_peer_id': context.remoteDevicePeerId,
      'sender_sequence': metadata.senderSequence,
      'ice_generation': metadata.iceGeneration,
      'created_at_ms': now,
      'expires_at_ms': expires,
      'payload': payload,
    }, videoEnabled: videoEnabled);
  }

  Future<bool> _deliverRecovery(
    _V2Recovery recovery,
    CallSignalV2 signal,
  ) async {
    _checkRecovery(recovery);
    bool valid() =>
        _recoveryCurrent(recovery) &&
        signal.expiresAtMs > _nowMs &&
        signal.iceGeneration == legacy.engine.iceGeneration;
    var delivered = false;
    try {
      delivered = await sendSignal(
        signal: signal,
        callHandle: _context!.callHandle,
        admittedEndpoint: _originalEndpoint!,
        canApply: valid,
      );
    } on CallNegotiationPortException catch (error) {
      if (error.code != CallNegotiationPortErrorCode.transportUnavailable) {
        rethrow;
      }
    }
    _checkRecovery(recovery);
    if (delivered && valid()) return true;
    _armRecoveryRetry(recovery);
    return false;
  }

  void _armRecoveryRetry(_V2Recovery recovery, {bool reconcileSwitch = false}) {
    if (!_recoveryCurrent(recovery) || recovery.timer?.isActive == true) return;
    final remaining = recovery.deadlineMs - _monotonicMs;
    if (remaining <= 0) return;
    recovery.timer = timerScheduler.schedule(
      Duration(milliseconds: min(remaining, 500)),
      () async {
        recovery.timer = null;
        if (reconcileSwitch &&
            _recoveryCurrent(recovery) &&
            !recovery.prepared &&
            _optionalSends == 0 &&
            _switch?.machine.requiresReconciliation == true) {
          _switch!.reconnect();
        }
        _scheduleRecovery(recovery);
      },
    );
  }

  Future<CallEvent?> _startInitial(CallSessionSnapshot snapshot) async {
    final failure = await _prepareAndBind(snapshot, idSource());
    if (failure != null) return failure;
    final token = _token!;
    final offer = await _session!.createOffer(token);
    _check();
    _validateDescription(offer, CallSessionDescriptionType.offer);
    await _session!.applyLocal(token, offer);
    _check();
    await _sendDescription(offer);
    _check();
    _localAnnounced = true;
    _scheduleLocalDrain();
    return _event(CallEventType.negotiationReady, snapshot);
  }

  Future<CallEvent?> _applyOffer(
    CallSessionSnapshot snapshot,
    _V2MediaWork work,
  ) async {
    _check(work);
    if (_token != null || _context!.direction != CallDirection.incoming) {
      return null;
    }
    final failure = await _prepareAndBind(
      snapshot,
      work.signal.payload['negotiation_id']! as String,
      work,
    );
    if (failure != null) return failure;
    final token = _token!;
    await _session!.applyRemote(token, _description(work.signal));
    _check(work);
    _remoteApplied = true;
    await _flushRemoteCandidates();
    _check(work);
    final answer = await _session!.createAnswer(token);
    _check(work);
    _validateDescription(answer, CallSessionDescriptionType.answer);
    await _session!.applyLocal(token, answer);
    _check(work);
    await _sendDescription(answer, work);
    _check(work);
    _localAnnounced = true;
    await _session!.commit(token);
    _check(work);
    _completeInitial();
    _scheduleLocalDrain();
    return null;
  }

  Future<CallEvent?> _applyAnswer(_V2MediaWork work) async {
    _check(work);
    final token = _token;
    if (token == null ||
        _context!.direction != CallDirection.outgoing ||
        token.negotiationId != work.signal.payload['negotiation_id']) {
      return null;
    }
    await _freshAuthority(work);
    await _session!.applyRemote(token, _description(work.signal));
    _check(work);
    _remoteApplied = true;
    await _flushRemoteCandidates();
    _check(work);
    await _session!.commit(token);
    _check(work);
    _completeInitial();
    return null;
  }

  Future<CallEvent?> _prepareAndBind(
    CallSessionSnapshot snapshot,
    String negotiationId, [
    _V2MediaWork? work,
  ]) async {
    await _freshAuthority(work);
    final failure = await legacy.execute(
      const CallEffect(CallEffectType.prepareAcceptedMedia),
      snapshot,
    );
    _check(work);
    if (failure != null) return failure;
    final epoch = ++_epoch;
    _negotiationIceGeneration = legacy.engine.iceGeneration;
    _session ??= videoEngine.bindV2Video(
      callId: callId,
      localIsCaller: _context!.direction == CallDirection.outgoing,
      wireVersion: CallWireVersion.v2,
      canApply: () => _ready,
      videoEnabled: videoEnabled,
    );
    _token = _session!.beginNegotiation(
      negotiationId: negotiationId,
      mediaRevision: 0,
      media: _context!.initialAcceptedMedia!,
      // A committed call outlives the initial envelope, but never its owner.
      canApply: () =>
          _ready &&
          _epoch == epoch &&
          (_initialCommitted ||
              (_budgetOpen && (work == null || _workCurrent(work)))),
    );
    _check(work);
    return null;
  }

  Future<void> _freshAuthority([_V2MediaWork? work]) async {
    _check(work);
    final fresh = ResolvedCallEndpoint.frozen(
      await resolveEndpoint(_context!.remoteAccountPeerId),
    );
    _check(work);
    final original = _originalEndpoint!;
    if (!_validEndpoint(fresh) ||
        original.accountPeerId != fresh.accountPeerId ||
        original.devicePeerId != fresh.devicePeerId ||
        original.signingPublicKey != fresh.signingPublicKey ||
        original.mlKemPublicKey != fresh.mlKemPublicKey ||
        original.deviceKeyEpoch != fresh.deviceKeyEpoch ||
        original.preferenceEpoch != fresh.preferenceEpoch ||
        original.admissionAuthority != fresh.admissionAuthority ||
        original.platform != fresh.platform ||
        original.routingHandle != fresh.routingHandle ||
        original.wakeHandle != fresh.wakeHandle) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }
  }

  Future<void> _sendDescription(
    CallSessionDescription description, [
    _V2MediaWork? work,
  ]) => _send(
    description.type == CallSessionDescriptionType.offer
        ? CallSignalV2Type.offer
        : CallSignalV2Type.answer,
    {
      'negotiation_id': _token!.negotiationId,
      'purpose': 'initial',
      'switch_id': null,
      'media_revision': 0,
      'media': _token!.media.name,
      'description': description.value,
      'fingerprint': description.fingerprint,
    },
    work,
  );

  Future<void> _send(
    CallSignalV2Type type,
    Map<String, Object?> payload, [
    _V2MediaWork? work,
  ]) async {
    _check(work);
    final candidateToken = type == CallSignalV2Type.ice ? _token : null;
    if (candidateToken != null && !_candidateReady) {
      throw const _V2WorkRetired();
    }
    final recovery = _recovery;
    if (type == CallSignalV2Type.ice &&
        recovery != null &&
        recovery.prepared &&
        _recoveryCurrent(recovery)) {
      recovery.candidateSignal ??= _recoverySignal(recovery, type, payload);
      if (await _deliverRecovery(recovery, recovery.candidateSignal!)) {
        recovery.candidateSignal = null;
      }
      return;
    }
    final now = _nowMs;
    final expires = min(
      now + 30000,
      _initialCommitted ? _originalEndpoint!.expiresAtMs : _initialExpiryMs!,
    );
    if (expires <= now) throw const _V2WorkRetired();
    final context = _context!;
    final metadata = contexts.reserveNextMetadata(
      callId,
      iceGeneration: legacy.engine.iceGeneration,
    );
    final signal = CallSignalV2.fromMap({
      'schema': CallSignalV2.schema,
      'call_id': callId.value,
      'message_id': idSource(),
      'event': type.wireName,
      'sender_account_peer_id': context.localAccountPeerId,
      'sender_device_peer_id': context.localDevicePeerId,
      'recipient_account_peer_id': context.remoteAccountPeerId,
      'recipient_device_peer_id': context.remoteDevicePeerId,
      'sender_sequence': metadata.senderSequence,
      'ice_generation': metadata.iceGeneration,
      'created_at_ms': now,
      'expires_at_ms': expires,
      'payload': payload,
    }, videoEnabled: videoEnabled);
    final sent = await sendSignal(
      signal: signal,
      callHandle: context.callHandle,
      admittedEndpoint: _originalEndpoint!,
      canApply: () =>
          _ready &&
          (candidateToken == null ||
              (_candidateReady && identical(candidateToken, _token))) &&
          _nowMs < expires &&
          (_initialCommitted || _budgetOpen) &&
          (work == null || _workCurrent(work)),
    );
    _check(work);
    if (candidateToken != null &&
        (!_candidateReady || !identical(candidateToken, _token))) {
      throw const _V2WorkRetired();
    }
    if (!sent) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.transportUnavailable,
      );
    }
  }

  void _scheduleLocalDrain() {
    if (!_candidateReady ||
        !_localAnnounced ||
        _localDrainScheduled ||
        (_recovery?.candidateSignal != null &&
            _snapshot?.state == CallState.reconnecting) ||
        _localCandidates.isEmpty) {
      return;
    }
    final snapshot = _snapshot;
    if (snapshot == null) return;
    _localDrainScheduled = true;
    _queueBackground(snapshot, () async {
      try {
        if (!_candidateReady || !_localAnnounced || _localCandidates.isEmpty) {
          return null;
        }
        final pending = _localCandidates.removeFirst();
        _localInFlight = 1;
        if (!identical(pending.token, _token) ||
            pending.candidate.iceGeneration != legacy.engine.iceGeneration) {
          return null;
        }
        final candidate = pending.candidate;
        await _send(CallSignalV2Type.ice, {
          'negotiation_id': pending.token.negotiationId,
          'candidate': candidate.value,
          'media_id': candidate.mediaId,
          'media_line_index': candidate.mediaLineIndex,
        });
        return null;
      } finally {
        _localInFlight = 0;
        _localDrainScheduled = false;
        _scheduleLocalDrain();
      }
    });
  }

  void _scheduleRemoteDrain() {
    if (!_candidateReady ||
        !_remoteApplied ||
        _remoteDrainScheduled ||
        _remoteCandidates.isEmpty) {
      return;
    }
    final snapshot = _snapshot;
    if (snapshot == null) return;
    _remoteDrainScheduled = true;
    _queueBackground(snapshot, () async {
      try {
        await _flushRemoteCandidates();
        return null;
      } finally {
        _remoteDrainScheduled = false;
        _scheduleRemoteDrain();
      }
    });
  }

  Future<void> _flushRemoteCandidates() async {
    if (!_remoteApplied || !_candidateReady) return;
    final token = _token;
    while (_remoteCandidates.isNotEmpty) {
      _check();
      if (!_candidateReady || !identical(token, _token)) {
        throw const _V2WorkRetired();
      }
      final batch = <CallIceCandidate>[];
      final works = <_V2MediaWork>[];
      while (_remoteCandidates.isNotEmpty &&
          batch.length < legacy.engine.candidateBatchCapacity) {
        final work = _remoteCandidates.removeFirst();
        if (!_workCurrent(work) ||
            work.signal.payload['negotiation_id'] != _token?.negotiationId) {
          continue;
        }
        works.add(work);
        batch.add(
          CallIceCandidate(
            value: work.signal.payload['candidate']! as String,
            mediaId: work.signal.payload['media_id'] as String?,
            mediaLineIndex: work.signal.payload['media_line_index'] as int?,
            iceGeneration: work.signal.iceGeneration,
          ),
        );
      }
      if (batch.isEmpty) continue;
      _remoteInFlight = batch.length;
      try {
        _check();
        if (!works.every(_workCurrent)) continue;
        await legacy.engine.addIceCandidates(batch);
        _check();
        if (!_candidateReady || !identical(token, _token)) {
          throw const _V2WorkRetired();
        }
      } finally {
        _remoteInFlight = 0;
      }
    }
  }

  Future<CallEvent?> _queue(
    CallSessionSnapshot snapshot,
    Future<CallEvent?> Function() job,
  ) {
    final result = _tail.then<CallEvent?>((_) async {
      if (!_ready) return null;
      try {
        return await job();
      } on _V2WorkRetired {
        return null;
      } catch (_) {
        if (_initialCommitted && _switch != null) {
          _switch!.failOptionalMedia();
          return null;
        }
        return _failure(snapshot);
      }
    });
    _tail = result.then<void>((_) {});
    return result;
  }

  void _queueBackground(
    CallSessionSnapshot snapshot,
    Future<CallEvent?> Function() job,
  ) {
    _track(
      _queue(snapshot, job).then<void>((failure) async {
        if (failure != null) await _dispatchSafely(failure);
      }),
    );
  }

  void _track(Future<void> future) {
    late final Future<void> tracked;
    tracked = future.whenComplete(() => _background.remove(tracked));
    _background.add(tracked);
  }

  Future<void> _dispatchSafely(CallEvent event) async {
    if (!_callCurrent() || _closed) return;
    try {
      await legacy.dispatchEvent(event);
    } catch (_) {
      // Keep the local owner retired. The canonical setup/cleanup deadline
      // remains authoritative if the coordinator can no longer admit work.
    }
  }

  bool _bindContext(CallSignalingContext context) {
    final original = contexts.admittedV2Endpoint(callId);
    if (original == null || context.wireVersion != CallWireVersion.v2) {
      return false;
    }
    if (_context == null) {
      _context = context;
      _originalEndpoint = original;
    }
    return _sameContext(context) &&
        identical(original, _originalEndpoint) &&
        _validEndpoint(original);
  }

  bool _ensureInitialBudget() {
    if (_initialCommitted) return true;
    final expires = contexts.originalV2InviteExpiresAtMs(callId);
    if (expires == null) return false;
    if (_elapsedDeadlineMs == null) {
      final remaining = min(expires - _nowMs, 45000);
      if (remaining <= 0) return false;
      _initialExpiryMs = expires;
      _elapsedDeadlineMs = _monotonicMs + remaining;
      _initialTimer = timerScheduler.schedule(
        Duration(milliseconds: remaining),
        () async {
          if (_closed || _initialCommitted) return;
          final snapshot = _snapshot;
          if (snapshot == null) return;
          final failure = _failure(snapshot);
          if (failure != null) await _dispatchSafely(failure);
        },
      );
    }
    return expires == _initialExpiryMs && _budgetOpen;
  }

  bool get _budgetOpen =>
      _initialExpiryMs != null &&
      _elapsedDeadlineMs != null &&
      _nowMs < _initialExpiryMs! &&
      _monotonicMs < _elapsedDeadlineMs!;

  void _completeInitial() {
    _initialCommitted = true;
    _initialTimer?.cancel();
    _initialTimer = null;
  }

  bool get _ready =>
      videoEnabled &&
      !_closed &&
      !_failed &&
      _context != null &&
      _originalEndpoint != null &&
      _callCurrent() &&
      (_negotiationIceGeneration == null ||
          _negotiationIceGeneration == legacy.engine.iceGeneration) &&
      _validEndpoint(_originalEndpoint!);

  bool _callCurrent() {
    if (!_allowed(canApply)) return false;
    final snapshot = _snapshot;
    final context = contexts.read(callId);
    return snapshot?.callId == callId &&
        snapshot?.isTerminal == false &&
        snapshot?.state != CallState.ending &&
        context != null &&
        (_context == null ||
            (_sameContext(context) &&
                identical(
                  contexts.admittedV2Endpoint(callId),
                  _originalEndpoint,
                )));
  }

  bool _sameContext(CallSignalingContext context) {
    final original = _context!;
    return context.callId == original.callId &&
        context.wireVersion == original.wireVersion &&
        context.direction == original.direction &&
        context.callHandle == original.callHandle &&
        context.localAccountPeerId == original.localAccountPeerId &&
        context.localDevicePeerId == original.localDevicePeerId &&
        context.remoteAccountPeerId == original.remoteAccountPeerId &&
        context.remoteDevicePeerId == original.remoteDevicePeerId &&
        context.admissionAuthority == original.admissionAuthority &&
        context.initialAcceptedMedia == original.initialAcceptedMedia;
  }

  bool _validEndpoint(ResolvedCallEndpoint endpoint) =>
      endpoint.accountPeerId == _context!.remoteAccountPeerId &&
      endpoint.devicePeerId == _context!.remoteDevicePeerId &&
      endpoint.admissionAuthority == _context!.admissionAuthority &&
      endpoint.expiresAtMs > _nowMs &&
      endpoint.capabilities.contains(CallEndpointResolver.voiceCapability) &&
      endpoint.capabilities.contains('video_call_v2');

  bool _sameSignalBinding(CallSignalV2 signal, String handle) =>
      signal.callId == callId &&
      handle == _context!.callHandle &&
      signal.senderAccountPeerId == _context!.remoteAccountPeerId &&
      signal.senderDevicePeerId == _context!.remoteDevicePeerId &&
      signal.recipientAccountPeerId == _context!.localAccountPeerId &&
      signal.recipientDevicePeerId == _context!.localDevicePeerId;

  bool _workCurrent(_V2MediaWork work) =>
      _ready &&
      _allowed(work.canApply) &&
      work.signal.expiresAtMs > _nowMs &&
      _sameSignalBinding(work.signal, work.callHandle) &&
      work.signal.iceGeneration == legacy.engine.iceGeneration &&
      (_initialCommitted || _budgetOpen);

  void _check([_V2MediaWork? work]) {
    if (!_ready ||
        (!_initialCommitted && !_budgetOpen) ||
        (work != null && !_workCurrent(work))) {
      throw const _V2WorkRetired();
    }
  }

  CallSessionSnapshot? get _snapshot {
    try {
      return legacy.readActiveSnapshot();
    } catch (_) {
      return null;
    }
  }

  int get _nowMs => legacy.clock().millisecondsSinceEpoch;
  int get _monotonicMs =>
      monotonicNowMs?.call() ?? _elapsed.elapsedMilliseconds;

  static bool _initialPhase(CallState state) =>
      state == CallState.accepted || state == CallState.negotiating;

  CallEvent? _failure(CallSessionSnapshot snapshot) {
    if (_closed || _failed || !_callCurrent()) return null;
    _failed = true;
    _epoch++;
    _initialTimer?.cancel();
    _remoteCandidates.clear();
    _localCandidates.clear();
    _descriptions.clear();
    return _event(CallEventType.negotiationFailed, snapshot);
  }

  CallEvent _event(CallEventType type, CallSessionSnapshot snapshot) =>
      CallEvent(
        type: type,
        eventId: idSource(),
        occurredAt: legacy.clock(),
        callId: callId,
        contactPeerId: snapshot.contactPeerId,
        reconnectGeneration: snapshot.reconnectGeneration,
      );

  CallEvent _remoteEvent(_V2MediaWork work) => CallEvent(
    type: switch (work.signal.event) {
      CallSignalV2Type.iceRestart => CallEventType.remoteIceRestart,
      CallSignalV2Type.offer => CallEventType.remoteOffer,
      _ => CallEventType.remoteAnswer,
    },
    eventId: work.signal.messageId,
    occurredAt: DateTime.fromMillisecondsSinceEpoch(
      work.signal.createdAtMs,
      isUtc: true,
    ),
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      work.signal.expiresAtMs,
      isUtc: true,
    ),
    callId: callId,
    contactPeerId: _context!.remoteAccountPeerId,
    localAccountPeerId: work.signal.recipientAccountPeerId,
    localDeviceId: work.signal.recipientDevicePeerId,
    remoteAccountPeerId: work.signal.senderAccountPeerId,
    remoteDeviceId: work.signal.senderDevicePeerId,
  );

  static CallSessionDescription _description(CallSignalV2 signal) =>
      CallSessionDescription(
        type: signal.event == CallSignalV2Type.offer
            ? CallSessionDescriptionType.offer
            : CallSessionDescriptionType.answer,
        value: signal.payload['description']! as String,
        fingerprint: signal.payload['fingerprint']! as String,
      );

  static void _validateDescription(
    CallSessionDescription description,
    CallSessionDescriptionType expected,
  ) {
    if (description.type != expected ||
        description.value.isEmpty ||
        (description.fingerprint?.isEmpty ?? true)) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.mediaUnavailable,
      );
    }
  }

  Future<void> close() {
    final pending = _closeFuture;
    if (pending != null) return pending;
    final result = _close();
    _closeFuture = result;
    unawaited(
      result.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          _closeFuture = null;
        },
      ),
    );
    return result;
  }

  Future<void> _close() async {
    _closed = true;
    _recovery?.timer?.cancel();
    _recoveryIngress.clear();
    _switch?.terminate();
    _epoch++;
    _initialTimer?.cancel();
    _remoteCandidates.clear();
    _localCandidates.clear();
    _descriptions.clear();
    try {
      final session = _session;
      if (session != null && !await session.close()) {
        throw const CallEngineException(CallEngineErrorCode.other);
      }
    } finally {
      // Optional video cleanup can never skip microphone/peer cleanup.
      await legacy.close();
    }
  }

  @override
  String toString() => 'CallV2NegotiationEffectExecutor';
}

final class _V2Recovery {
  _V2Recovery({
    required this.snapshot,
    required this.oldToken,
    required this.epoch,
    required this.oldGeneration,
    required this.media,
    required this.revision,
    required this.deadlineMs,
    required this.blocked,
    required this.takeover,
    required this.transportRequested,
  });
  final CallSessionSnapshot snapshot;
  CallVideoNegotiation oldToken;
  int epoch;
  final int oldGeneration;
  CallMediaKind media;
  int revision;
  final int deadlineMs;
  final bool takeover;
  bool transportRequested;
  bool blocked;
  bool scheduled = false;
  bool needsDrive = false;
  bool prepared = false;
  bool requestDelivered = false;
  bool announcementDelivered = false;
  bool remoteApplied = false;
  bool localDelivered = false;
  bool completed = false;
  String? negotiationId;
  Future<bool>? retirement;
  _V2MediaWork? remoteWork;
  _V2MediaWork? authorityWork;
  CallSessionDescription? localDescription;
  CallSignalV2? requestSignal;
  CallSignalV2? announcement;
  CallSignalV2? descriptionSignal;
  CallSignalV2? candidateSignal;
  CallTimerHandle? timer;
}

final class _V2MediaWork {
  const _V2MediaWork(this.signal, this.callHandle, this.canApply);
  final CallSignalV2 signal;
  final String callHandle;
  final bool Function() canApply;
}

final class _V2LocalCandidate {
  const _V2LocalCandidate(this.token, this.candidate);
  final CallVideoNegotiation token;
  final CallIceCandidate candidate;
}

final class _V2WorkRetired implements Exception {
  const _V2WorkRetired();
}

bool _allowed(bool Function() predicate) {
  try {
    return predicate();
  } catch (_) {
    return false;
  }
}

final class _CachedSwitchSignal {
  const _CachedSwitchSignal(this.signal, this.deadlineMs, this.canApply);
  final CallSignalV2 signal;
  final int deadlineMs;
  final bool Function() canApply;
}

final class _IncomingSwitchRequest {
  const _IncomingSwitchRequest(
    this.request,
    this.createdAtMs,
    this.expiresAtMs,
  );
  final MediaSwitchRequest request;
  final int createdAtMs;
  final int expiresAtMs;
}
