import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/android_production_audio_call_e2e.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/domain/issued_call_wake_handle_store.dart';

typedef ReadProductionAudioCallSession = CallSessionSnapshot? Function();
typedef ReadProductionAudioCallForeground =
    ForegroundCallProjection? Function();
typedef ReadProductionAudioCallConnection =
    Future<CallConnectionSnapshot?> Function();
typedef ReadOutgoingCallWakeAuthorityReady =
    Future<bool> Function(String contactAccountPeerId);

/// Fail-closed predicate for the issuer-side proof required by outgoing calls.
///
/// It accepts no signaling or persistence authority and returns only a
/// boolean. In particular, pending, revoked, legacy-receipt, future-dated, and
/// expired grants never become ready.
bool hasExactCurrentProductionCallWakeAuthority({
  required CallIssuedWakeHandleRecord? record,
  required String contactAccountPeerId,
  required String expectedRecipientDevicePeerId,
  required int expectedDeviceKeyEpoch,
  required int nowMs,
}) =>
    record != null &&
    record.contactAccountPeerId == contactAccountPeerId &&
    !record.revokePending &&
    !record.distributionPending &&
    record.hasCurrentDistributionReceipt &&
    record.grant.recipientDevicePeerId == expectedRecipientDevicePeerId &&
    record.grant.deviceKeyEpoch == expectedDeviceKeyEpoch &&
    record.grant.isValidAt(nowMs);

/// Read-only views over canonical production state.
///
/// Deliberately absent are place/answer/reject/end, mute, and route callbacks.
/// UI and native controls remain the only authority exercised by the host.
final class AndroidProductionAudioCallObservationSource {
  const AndroidProductionAudioCallObservationSource({
    required this.readCurrentSession,
    required this.sessionChanges,
    required this.readCurrentForeground,
    required this.foregroundChanges,
    required this.readActiveConnectionSnapshot,
    required this.readOutgoingCallWakeAuthorityReady,
  });

  final ReadProductionAudioCallSession readCurrentSession;
  final Stream<CallSessionSnapshot> sessionChanges;
  final ReadProductionAudioCallForeground readCurrentForeground;
  final Stream<ForegroundCallProjection?> foregroundChanges;
  final ReadProductionAudioCallConnection readActiveConnectionSnapshot;
  final ReadOutgoingCallWakeAuthorityReady readOutgoingCallWakeAuthorityReady;
}

/// Profile-gated observer for the installed production-app call journey.
///
/// It can only read readiness or arm, sample, and stop subscriptions. All
/// retained values are fixed-shape booleans, coarse enums, or one-way
/// bindings.
final class AndroidProductionAudioCallE2EObserver {
  AndroidProductionAudioCallE2EObserver._();

  static AndroidProductionAudioCallE2EObserver? tryCreate({
    required bool enabled,
    required bool isAndroid,
    required String installedProfileId,
  }) {
    if (!enabled ||
        !isAndroid ||
        installedProfileId != androidProductionAudioCallE2EBuildProfile) {
      return null;
    }
    return AndroidProductionAudioCallE2EObserver._();
  }

  AndroidProductionAudioCallObservationSource? _source;
  _ObservationRun? _active;
  StreamSubscription<CallSessionSnapshot>? _sessionSubscription;
  StreamSubscription<ForegroundCallProjection?>? _foregroundSubscription;
  Future<void> _sampleTail = Future<void>.value();
  Future<void>? _disposeFuture;
  int _generation = 0;
  bool _disposed = false;

  void bind(AndroidProductionAudioCallObservationSource source) {
    if (_disposed) return;
    if (identical(_source, source)) return;

    final run = _active;
    if (run == null) {
      _source = source;
      return;
    }

    // A production graph may be withdrawn and rebuilt while an observation is
    // armed. Prepare both replacement listeners before invalidating the old
    // generation, so graph construction never depends on debug observation.
    final nextGeneration = _generation + 1;
    StreamSubscription<CallSessionSnapshot>? nextSession;
    StreamSubscription<ForegroundCallProjection?>? nextForeground;
    try {
      nextSession = _listenToSessions(source, run, nextGeneration);
      nextForeground = _listenToForeground(source, run, nextGeneration);
    } catch (_) {
      unawaited(_cancelSubscriptionPair(nextSession, nextForeground));
      return;
    }

    final previousSession = _sessionSubscription;
    final previousForeground = _foregroundSubscription;
    _source = source;
    _generation = nextGeneration;
    _sessionSubscription = nextSession;
    _foregroundSubscription = nextForeground;
    unawaited(_cancelSubscriptionPair(previousSession, previousForeground));
    unawaited(
      _sampleCurrent(source, run, nextGeneration).catchError((Object _) {}),
    );
  }

  Future<Map<String, Object?>> run(Map<String, dynamic> config) async {
    if (_disposed) throw StateError('production-call observer is disposed');
    final request = AndroidProductionAudioCallE2ERequest.fromConfig(config);
    return switch (request.operation) {
      androidProductionAudioCallArmOperation => _arm(request),
      androidProductionAudioCallSampleOperation => _sample(request),
      androidProductionAudioCallStopOperation => _stop(request),
      androidProductionAudioCallReadinessOperation => _readiness(request),
      _ => throw StateError('unreachable production-call operation'),
    };
  }

  Future<Map<String, Object?>> _readiness(
    AndroidProductionAudioCallE2ERequest request,
  ) async {
    final source = _source;
    if (source == null) {
      throw StateError('production-call observation source is not bound');
    }
    final ready = await source.readOutgoingCallWakeAuthorityReady(
      request.contactAccountPeerId!,
    );
    final run = _ObservationRun(request)..wakeAuthorityReady = ready;
    return _receipt(run, request, status: ready ? 'ready' : 'not_ready');
  }

  Future<Map<String, Object?>> _arm(
    AndroidProductionAudioCallE2ERequest request,
  ) async {
    final source = _source;
    if (source == null) {
      throw StateError('production-call observation source is not bound');
    }
    if (_active != null) {
      throw StateError('production-call observation is already armed');
    }
    final generation = ++_generation;
    final run = _ObservationRun(request);
    _active = run;
    StreamSubscription<CallSessionSnapshot>? sessionSubscription;
    StreamSubscription<ForegroundCallProjection?>? foregroundSubscription;
    try {
      sessionSubscription = _listenToSessions(source, run, generation);
      foregroundSubscription = _listenToForeground(source, run, generation);
    } catch (_) {
      await _cancelSubscriptionPair(
        sessionSubscription,
        foregroundSubscription,
      );
      if (_generation == generation && identical(_active, run)) {
        _active = null;
        _generation++;
      }
      rethrow;
    }
    _sessionSubscription = sessionSubscription;
    _foregroundSubscription = foregroundSubscription;
    await _sampleCurrent(source, run, generation);
    return _receipt(run, request, status: 'armed');
  }

  StreamSubscription<CallSessionSnapshot> _listenToSessions(
    AndroidProductionAudioCallObservationSource source,
    _ObservationRun run,
    int generation,
  ) => source.sessionChanges.listen((session) {
    if (_generation != generation || !identical(_active, run)) return;
    _recordSession(run, session);
    _queueConnectionSample(source, run, generation);
  }, onError: (Object _, StackTrace _) {});

  StreamSubscription<ForegroundCallProjection?> _listenToForeground(
    AndroidProductionAudioCallObservationSource source,
    _ObservationRun run,
    int generation,
  ) => source.foregroundChanges.listen((projection) {
    if (_generation != generation || !identical(_active, run)) return;
    _recordForeground(run, projection);
    _queueConnectionSample(source, run, generation);
  }, onError: (Object _, StackTrace _) {});

  Future<Map<String, Object?>> _sample(
    AndroidProductionAudioCallE2ERequest request,
  ) async {
    final (source, run) = _requireActive(request);
    await _sampleCurrent(source, run, _generation);
    return _receipt(run, request, status: 'observing');
  }

  Future<Map<String, Object?>> _stop(
    AndroidProductionAudioCallE2ERequest request,
  ) async {
    final (source, run) = _requireActive(request);
    final generation = _generation;
    await _sampleCurrent(source, run, generation);
    await _cancelSubscriptions();
    if (_generation == generation && identical(_active, run)) {
      _active = null;
      _generation++;
    }
    return _receipt(run, request, status: 'complete');
  }

  (AndroidProductionAudioCallObservationSource, _ObservationRun) _requireActive(
    AndroidProductionAudioCallE2ERequest request,
  ) {
    final source = _source;
    final run = _active;
    if (source == null || run == null || !run.request.isSameRun(request)) {
      throw StateError('production-call observation binding mismatch');
    }
    return (source, run);
  }

  Future<void> _sampleCurrent(
    AndroidProductionAudioCallObservationSource source,
    _ObservationRun run,
    int generation,
  ) {
    final next = _sampleTail.then((_) async {
      if (_generation != generation || !identical(_active, run)) return;
      final session = source.readCurrentSession();
      if (session != null) _recordSession(run, session);
      _recordForeground(run, source.readCurrentForeground());
      await _recordConnection(source, run, generation);
    });
    _sampleTail = next.catchError((Object _) {});
    return next;
  }

  void _queueConnectionSample(
    AndroidProductionAudioCallObservationSource source,
    _ObservationRun run,
    int generation,
  ) {
    final next = _sampleTail.then(
      (_) => _recordConnection(source, run, generation),
    );
    _sampleTail = next.catchError((Object _) {});
  }

  void _recordSession(_ObservationRun run, CallSessionSnapshot session) {
    final callId = session.callId;
    if (callId == null) return;
    if (!_bindCall(run, callId)) return;
    final state = _coarseState(session);
    if (state != null && !run.stateSequence.contains(state)) {
      run.stateSequence.add(state);
    }
    switch (state) {
      case 'outgoing':
        run.outgoingObserved = true;
      case 'ringing':
        run.ringingObserved = true;
      case 'accepted':
        run.acceptedObserved = true;
      case 'connected':
        run.connectedObserved = true;
      case 'terminal':
        run.terminalObserved = true;
      case null:
        break;
    }
  }

  void _recordForeground(
    _ObservationRun run,
    ForegroundCallProjection? projection,
  ) {
    if (projection == null || projection.session.callId == null) return;
    if (!_bindCall(run, projection.session.callId!)) return;
    _recordSession(run, projection.session);
    final state = projection.session.state;
    if (state == CallState.accepted ||
        state == CallState.negotiating ||
        state == CallState.connected ||
        state == CallState.reconnecting) {
      run.activeCallSurfaceObserved = true;
    }
  }

  Future<void> _recordConnection(
    AndroidProductionAudioCallObservationSource source,
    _ObservationRun run,
    int generation,
  ) async {
    if (_generation != generation ||
        !identical(_active, run) ||
        run.callId == null ||
        run.terminalObserved) {
      return;
    }
    CallConnectionSnapshot? snapshot;
    try {
      snapshot = await source.readActiveConnectionSnapshot();
    } catch (_) {
      return;
    }
    if (_generation != generation ||
        !identical(_active, run) ||
        snapshot == null) {
      return;
    }
    run.structuralMediaReadyObserved |= snapshot.isMediaReady;
    run.relayOnlyObserved |=
        snapshot.transportPolicy == CallTransportPolicy.relayOnly;
    run.localAudioEnabledObserved |= snapshot.localAudioEnabled;
    run.inboundAudioRtpObserved |= snapshot.inboundAudioRtpObserved;
    run.outboundAudioRtpObserved |= snapshot.outboundAudioRtpObserved;
    final transport = switch (snapshot.transport) {
      CallTransportClass.turnUdp => 'turn_udp',
      CallTransportClass.turnTcpTls => 'turn_tcp_tls',
      CallTransportClass.relay => 'relay',
      CallTransportClass.unknown || CallTransportClass.direct => 'unknown',
    };
    if (transport != 'unknown') run.selectedRelayTransport = transport;
  }

  bool _bindCall(_ObservationRun run, CallId callId) {
    final existing = run.callId;
    if (existing != null) return existing == callId;
    run.callId = callId;
    run.callBindingSha256 = sha256
        .convert(
          utf8.encode(
            '${run.request.runId}\u0000${run.request.nonce}\u0000${callId.value}',
          ),
        )
        .toString();
    return true;
  }

  Future<void> _cancelSubscriptions() async {
    final session = _sessionSubscription;
    final foreground = _foregroundSubscription;
    _sessionSubscription = null;
    _foregroundSubscription = null;
    await _cancelSubscriptionPair(session, foreground);
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _generation++;
    _active = null;
    _source = null;
    await _cancelSubscriptions();
  }
}

Future<void> _cancelSubscriptionPair(
  StreamSubscription<CallSessionSnapshot>? session,
  StreamSubscription<ForegroundCallProjection?>? foreground,
) async {
  Future<void> cancel(StreamSubscription<Object?>? subscription) async {
    try {
      await subscription?.cancel();
    } catch (_) {}
  }

  await Future.wait<void>([cancel(session), cancel(foreground)]);
}

String? _coarseState(CallSessionSnapshot session) => switch (session.state) {
  CallState.preparing || CallState.inviting
      when session.direction == CallDirection.outgoing =>
    'outgoing',
  CallState.ringing => 'ringing',
  CallState.accepted || CallState.negotiating => 'accepted',
  CallState.connected || CallState.reconnecting => 'connected',
  CallState.ending || CallState.ended => 'terminal',
  _ => null,
};

Map<String, Object?> _receipt(
  _ObservationRun run,
  AndroidProductionAudioCallE2ERequest request, {
  required String status,
}) => <String, Object?>{
  'schema': androidProductionAudioCallE2EResultSchema,
  'scenario': androidProductionAudioCallE2EScenario,
  'buildProfile': androidProductionAudioCallE2EBuildProfile,
  'role': request.role,
  'operation': request.operation,
  'stepId': request.stepId,
  'runId': request.runId,
  'nonce': request.nonce,
  'profileSha256': request.profileSha256,
  'apkSha256': request.apkSha256,
  'callBindingSha256': run.callBindingSha256,
  'status': status,
  'success': true,
  'stateSequence': List<String>.unmodifiable(run.stateSequence),
  'outgoingObserved': run.outgoingObserved,
  'ringingObserved': run.ringingObserved,
  'acceptedObserved': run.acceptedObserved,
  'connectedObserved': run.connectedObserved,
  'terminalObserved': run.terminalObserved,
  'activeCallSurfaceObserved': run.activeCallSurfaceObserved,
  'structuralMediaReadyObserved': run.structuralMediaReadyObserved,
  'relayOnlyObserved': run.relayOnlyObserved,
  'selectedRelayTransport': run.selectedRelayTransport,
  'localAudioEnabledObserved': run.localAudioEnabledObserved,
  'inboundAudioRtpObserved': run.inboundAudioRtpObserved,
  'outboundAudioRtpObserved': run.outboundAudioRtpObserved,
  'wakeAuthorityReady': run.wakeAuthorityReady,
  'containsPrivateMaterial': false,
};

final class _ObservationRun {
  _ObservationRun(this.request);

  final AndroidProductionAudioCallE2ERequest request;
  final List<String> stateSequence = <String>[];
  CallId? callId;
  String? callBindingSha256;
  bool outgoingObserved = false;
  bool ringingObserved = false;
  bool acceptedObserved = false;
  bool connectedObserved = false;
  bool terminalObserved = false;
  bool activeCallSurfaceObserved = false;
  bool structuralMediaReadyObserved = false;
  bool relayOnlyObserved = false;
  String selectedRelayTransport = 'unknown';
  bool localAudioEnabledObserved = false;
  bool inboundAudioRtpObserved = false;
  bool outboundAudioRtpObserved = false;
  bool wakeAuthorityReady = false;
}
