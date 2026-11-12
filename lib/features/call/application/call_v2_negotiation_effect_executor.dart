import 'dart:async';
import 'dart:collection';
import 'dart:math';

import '../domain/call_engine.dart';
import '../domain/call_event.dart';
import '../domain/call_id.dart';
import '../domain/call_media.dart';
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

/// One call's initial v2 SDP/ICE owner. The legacy executor retains microphone,
/// engine-event and v1 ownership; its single candidate listener routes here.
///
/// Native jobs share one queue, but canonical dispatch never waits inside that
/// queue: the coordinator may execute another job before dispatch completes.
/// Two description slots are reserved separately from the bounded ICE queue,
/// so ICE arriving before SDP cannot prevent the offer that drains it.
final class CallV2NegotiationEffectExecutor implements CallEffectExecutor {
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

  CallMediaSwitchEffectExecutor? get mediaSwitch => null;

  CallVideoSession? get videoSession => _session;
  CallVideoNegotiation? get negotiation => _token;

  /// Completes after currently adopted jobs and canonical dispatch settle.
  /// ICE awaiting a future description remains bounded without blocking this.
  Future<void> get workSettled async {
    while (true) {
      final tail = _tail;
      await tail;
      await Future.wait<void>(_background.toList(growable: false));
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
        // Later switch/recovery work must use this same owner. Until its unit
        // supplies that behavior, v2 never falls through to v1 signaling.
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
        signal.expiresAtMs <= _nowMs ||
        signal.iceGeneration != legacy.engine.iceGeneration ||
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
    if (_seenIncoming.length >= 128) return IncomingCallSignalOutcome.deferred;
    final work = _V2MediaWork(signal, callHandle, canApply);
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
        final expectedId = _token?.negotiationId ?? _incomingNegotiationId;
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
        !_ready ||
        token == null ||
        snapshot.callId != callId ||
        candidate.iceGeneration != legacy.engine.iceGeneration ||
        (!_initialCommitted && !_budgetOpen)) {
      return true;
    }
    if (_localCandidates.length + _localInFlight >= maxPendingMedia) {
      final failure = _failure(snapshot);
      if (failure != null) _track(_dispatchSafely(failure));
      return true;
    }
    // Capture the token at arrival. A later negotiation cannot retag this ICE.
    _localCandidates.addLast(_V2LocalCandidate(token, candidate));
    _scheduleLocalDrain();
    return true;
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
          _nowMs < expires &&
          (_initialCommitted || _budgetOpen) &&
          (work == null || _workCurrent(work)),
    );
    _check(work);
    if (!sent) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.transportUnavailable,
      );
    }
  }

  void _scheduleLocalDrain() {
    if (!_ready ||
        !_localAnnounced ||
        _localDrainScheduled ||
        _localCandidates.isEmpty) {
      return;
    }
    final snapshot = _snapshot;
    if (snapshot == null) return;
    _localDrainScheduled = true;
    _queueBackground(snapshot, () async {
      try {
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
    if (!_ready ||
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
    if (!_remoteApplied) return;
    while (_remoteCandidates.isNotEmpty) {
      _check();
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
    type: work.signal.event == CallSignalV2Type.offer
        ? CallEventType.remoteOffer
        : CallEventType.remoteAnswer,
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
