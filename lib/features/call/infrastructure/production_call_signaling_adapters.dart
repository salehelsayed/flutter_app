import 'package:uuid/uuid.dart';

import '../../../core/utils/flow_event_emitter.dart';
import '../application/call_control_effect_executor.dart';
import '../application/call_endpoint_resolver.dart';
import '../application/call_negotiation_effect_executor.dart';
import '../application/call_signaling_context_store.dart';
import '../application/call_signaling_service.dart';
import 'call_authority_client.dart';
import '../domain/call_engine.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_signal.dart';
import '../domain/call_state.dart';
import 'p2p_call_transport.dart';
import 'secure_call_envelope_codec.dart';

typedef ResolveCurrentCallEndpoint =
    Future<ResolvedCallEndpoint> Function(String remoteAccountPeerId);
typedef LoadCallSenderSigningPrivateKey = Future<String> Function();

/// Adapts reducer-approved control signals to the dedicated call transport.
///
/// Endpoint authority is resolved again for every network write. The adapter
/// deliberately calls [CallSignalingService.transmit], so it never recursively
/// dispatches receipt events while an effect executor is already in the
/// coordinator lane.
final class ProductionCallControlSignalingAdapter
    implements CallControlSignalingPort {
  ProductionCallControlSignalingAdapter({
    required CallSignalingService signalingService,
    required CallSignalingContextStore contextStore,
    required ResolveCurrentCallEndpoint resolveCurrentEndpoint,
    required LoadCallSenderSigningPrivateKey loadSenderSigningPrivateKey,
    CallId Function()? callHandleSource,
    DateTime Function()? clock,
  }) : _signalingService = signalingService,
       _contextStore = contextStore,
       _resolveCurrentEndpoint = resolveCurrentEndpoint,
       _loadSenderSigningPrivateKey = loadSenderSigningPrivateKey,
       _callHandleSource = callHandleSource ?? _newOpaqueId,
       _clock = clock ?? DateTime.now;

  static const Map<String, Object?> _audioOnlyInvitePayload = <String, Object?>{
    'capabilities': <Object?>['audio'],
    'metadata': <String, Object?>{'media': 'audio', 'video': false},
  };

  final CallSignalingService _signalingService;
  final CallSignalingContextStore _contextStore;
  final ResolveCurrentCallEndpoint _resolveCurrentEndpoint;
  final LoadCallSenderSigningPrivateKey _loadSenderSigningPrivateKey;
  final CallId Function() _callHandleSource;
  final DateTime Function() _clock;

  int _preparationCount = 0;
  int _sendCount = 0;
  int _failureCount = 0;

  @override
  Future<OutgoingCallSignalingPreparation> prepareOutgoingInvite(
    CallSessionSnapshot snapshot,
  ) async {
    try {
      final callId = snapshot.callId;
      final contactPeerId = snapshot.contactPeerId;
      if (callId == null ||
          contactPeerId == null ||
          snapshot.direction != CallDirection.outgoing ||
          snapshot.state != CallState.preparing ||
          !_validIdentity(contactPeerId) ||
          !_validIdentity(snapshot.callerAccountPeerId) ||
          !_validIdentity(snapshot.callerDeviceId)) {
        throw const CallControlSignalingPortException(
          CallControlSignalingPortErrorCode.preparationUnavailable,
        );
      }

      late final ResolvedCallEndpoint endpoint;
      try {
        endpoint = await _resolveCurrentEndpoint(contactPeerId);
      } catch (_) {
        throw const CallControlSignalingPortException(
          CallControlSignalingPortErrorCode.preparationUnavailable,
        );
      }
      if (endpoint.accountPeerId != contactPeerId ||
          !_validIdentity(endpoint.devicePeerId)) {
        throw const CallControlSignalingPortException(
          CallControlSignalingPortErrorCode.endpointMismatch,
        );
      }

      final callHandle = _callHandleSource().value;
      if (CallId.tryParse(callHandle) == null || callHandle == callId.value) {
        throw const CallControlSignalingPortException(
          CallControlSignalingPortErrorCode.preparationUnavailable,
        );
      }
      _preparationCount++;
      return OutgoingCallSignalingPreparation(
        callHandle: callHandle,
        remoteAccountPeerId: endpoint.accountPeerId,
        remoteDevicePeerId: endpoint.devicePeerId,
        nextSenderSequence: 1,
        iceGeneration: 0,
        invitePayload: _audioOnlyInvitePayload,
      );
    } on CallControlSignalingPortException {
      _failureCount++;
      rethrow;
    } catch (_) {
      _failureCount++;
      throw const CallControlSignalingPortException(
        CallControlSignalingPortErrorCode.preparationUnavailable,
      );
    }
  }

  @override
  Future<CallControlSendResult> send({
    required CallSignal signal,
    required String callHandle,
  }) async {
    try {
      if (CallId.tryParse(callHandle) == null) {
        throw const CallControlSignalingPortException(
          CallControlSignalingPortErrorCode.transportUnavailable,
        );
      }
      final endpoint = await _resolveExactEndpoint(
        callId: signal.callId,
        event: signal.event,
        accountPeerId: signal.recipientAccountPeerId,
        devicePeerId: signal.recipientDevicePeerId,
      );
      final signingPrivateKey = await _loadSigningKey();
      late final CallSignalTransportResult transport;
      try {
        transport = await _signalingService.transmit(
          signal: signal,
          callHandle: callHandle,
          endpoint: endpoint,
          senderSigningPrivateKey: signingPrivateKey,
          authorizeTerminalRetry: _terminalRetryAuthorizer(endpoint),
        );
      } on CallSignalingException catch (error) {
        throw CallControlSignalingPortException(
          error.code == CallSignalingErrorCode.endpointMismatch
              ? CallControlSignalingPortErrorCode.endpointMismatch
              : CallControlSignalingPortErrorCode.transportUnavailable,
        );
      } catch (_) {
        throw const CallControlSignalingPortException(
          CallControlSignalingPortErrorCode.transportUnavailable,
        );
      }
      _sendCount++;
      return CallControlSendResult(
        directAccepted: transport.directAccepted,
        mailboxStored: transport.mailboxStored,
        wakeDispatched: transport.wakeDispatched,
        directRoute: _routeClass(transport.directRoute),
        mailboxStoreSettled: transport.mailboxStoreSettled,
      );
    } on CallControlSignalingPortException {
      _failureCount++;
      rethrow;
    } catch (_) {
      _failureCount++;
      throw const CallControlSignalingPortException(
        CallControlSignalingPortErrorCode.transportUnavailable,
      );
    }
  }

  Future<bool> Function() _terminalRetryAuthorizer(
    ResolvedCallEndpoint endpoint,
  ) =>
      () => _authorizeTerminalRetry(endpoint);

  Future<bool> _authorizeTerminalRetry(ResolvedCallEndpoint original) async {
    // Resolve without re-pinning: terminal cleanup already purged the call's
    // context, and this delivery must not recreate it or bind a successor.
    final current = await _resolveRetryEndpoint(
      _resolveCurrentEndpoint,
      original,
    );
    if (!_sameEndpointAuthority(original, current) ||
        current.expiresAtMs <= _clock().toUtc().millisecondsSinceEpoch) {
      return false;
    }
    // The production loader verifies the graph's current account authority.
    // Read it last, after endpoint awaits, and never retain it for retry.
    await _loadSigningKey();
    return current.expiresAtMs > _clock().toUtc().millisecondsSinceEpoch;
  }

  /// Re-resolves the exact accepted endpoint for every control write and
  /// pins it per call. A signal other than `invite` may fall back to that
  /// pin only when the directory record is transiently gone
  /// (`unavailable`) or the bridge failed; every other refusal fails closed.
  Future<ResolvedCallEndpoint> _resolveExactEndpoint({
    required CallId callId,
    required CallSignalType event,
    required String accountPeerId,
    required String devicePeerId,
  }) async {
    late final ResolvedCallEndpoint endpoint;
    try {
      endpoint = await _resolveCurrentEndpoint(accountPeerId);
    } on CallEndpointResolutionException catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_ENDPOINT_RESOLUTION_FAILED',
        details: <String, Object?>{'code': error.code.name},
      );
      final pinned = _pinnedEndpointFallback(
        pinned: _contextStore.pinnedEndpoint(callId),
        event: event,
        accountPeerId: accountPeerId,
        devicePeerId: devicePeerId,
        reason: error.code == CallEndpointResolutionCode.unavailable
            ? _PinnedFallbackReason.unavailable
            : null,
        nowMs: _clock().toUtc().millisecondsSinceEpoch,
        adapter: 'control',
      );
      if (pinned != null) return pinned;
      throw const CallControlSignalingPortException(
        CallControlSignalingPortErrorCode.endpointMismatch,
      );
    } on CallAuthorityException catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_ENDPOINT_RESOLUTION_FAILED',
        details: const <String, Object?>{'code': 'unexpected'},
      );
      final pinned = _pinnedEndpointFallback(
        pinned: _contextStore.pinnedEndpoint(callId),
        event: event,
        accountPeerId: accountPeerId,
        devicePeerId: devicePeerId,
        reason: error.code == CallAuthorityErrorCode.bridgeFailure
            ? _PinnedFallbackReason.bridgeFailure
            : null,
        nowMs: _clock().toUtc().millisecondsSinceEpoch,
        adapter: 'control',
      );
      if (pinned != null) return pinned;
      throw const CallControlSignalingPortException(
        CallControlSignalingPortErrorCode.endpointMismatch,
      );
    } catch (_) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_ENDPOINT_RESOLUTION_FAILED',
        details: const <String, Object?>{'code': 'unexpected'},
      );
      throw const CallControlSignalingPortException(
        CallControlSignalingPortErrorCode.endpointMismatch,
      );
    }
    if (endpoint.accountPeerId != accountPeerId ||
        endpoint.devicePeerId != devicePeerId) {
      throw const CallControlSignalingPortException(
        CallControlSignalingPortErrorCode.endpointMismatch,
      );
    }
    _contextStore.pinEndpoint(callId, endpoint);
    return endpoint;
  }

  Future<String> _loadSigningKey() async {
    try {
      final key = await _loadSenderSigningPrivateKey();
      if (key.trim().isEmpty) {
        throw const CallControlSignalingPortException(
          CallControlSignalingPortErrorCode.transportUnavailable,
        );
      }
      return key;
    } on CallControlSignalingPortException {
      rethrow;
    } catch (_) {
      throw const CallControlSignalingPortException(
        CallControlSignalingPortErrorCode.transportUnavailable,
      );
    }
  }

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'preparationCount': _preparationCount,
    'sendCount': _sendCount,
    'failureCount': _failureCount,
  };

  @override
  String toString() =>
      'ProductionCallControlSignalingAdapter(${toDiagnosticMap()})';
}

/// Adapts authenticated SDP, ICE, and restart material to call-only transport.
/// Raw negotiation material and authenticated bindings never enter diagnostics.
final class ProductionCallNegotiationSignalingAdapter
    implements
        CallNegotiationSignalingPort,
        CallNegotiationFencedSignalingPort {
  ProductionCallNegotiationSignalingAdapter({
    required CallSignalingService signalingService,
    required CallSignalingContextStore contextStore,
    required ResolveCurrentCallEndpoint resolveCurrentEndpoint,
    required LoadCallSenderSigningPrivateKey loadSenderSigningPrivateKey,
    DateTime Function()? clock,
    CallId Function()? messageIdSource,
    this.signalLifetime = CallControlEffectExecutor.defaultSignalLifetime,
  }) : _signalingService = signalingService,
       _contextStore = contextStore,
       _resolveCurrentEndpoint = resolveCurrentEndpoint,
       _loadSenderSigningPrivateKey = loadSenderSigningPrivateKey,
       _clock = clock ?? DateTime.now,
       _messageIdSource = messageIdSource ?? _newOpaqueId {
    if (signalLifetime <= Duration.zero ||
        signalLifetime > SecureCallEnvelopeCodec.maximumPostconnectLifetime) {
      throw ArgumentError.value(
        signalLifetime,
        'signalLifetime',
        'must be within the secure call envelope lifetime',
      );
    }
  }

  final CallSignalingService _signalingService;
  final CallSignalingContextStore _contextStore;
  final ResolveCurrentCallEndpoint _resolveCurrentEndpoint;
  final LoadCallSenderSigningPrivateKey _loadSenderSigningPrivateKey;
  final DateTime Function() _clock;
  final CallId Function() _messageIdSource;
  final Duration signalLifetime;

  int _descriptionSendCount = 0;
  int _candidateSendCount = 0;
  int _restartSendCount = 0;
  int _failureCount = 0;

  @override
  Future<void> sendDescription({
    required CallId callId,
    required CallSessionDescription description,
    required int iceGeneration,
    bool Function()? canApply,
  }) => _guarded(() async {
    final fingerprint = description.fingerprint;
    if (description.value.isEmpty ||
        fingerprint == null ||
        fingerprint.isEmpty ||
        iceGeneration < 0) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }
    final event = switch (description.type) {
      CallSessionDescriptionType.offer => CallSignalType.offer,
      CallSessionDescriptionType.answer => CallSignalType.answer,
    };
    await _transmit(
      callId: callId,
      event: event,
      iceGeneration: iceGeneration,
      payload: <String, Object?>{
        'description': description.value,
        'fingerprint': fingerprint,
      },
      onDelivered: _descriptionDelivered,
      canApply: canApply,
    );
  });

  @override
  Future<void> sendCandidates({
    required CallId callId,
    required List<CallIceCandidate> candidates,
  }) => _guarded(() async {
    final batch = List<CallIceCandidate>.unmodifiable(candidates);
    for (final candidate in batch) {
      if (candidate.value.isEmpty || candidate.iceGeneration < 0) {
        throw const CallNegotiationPortException(
          CallNegotiationPortErrorCode.signalingUnavailable,
        );
      }
    }
    await _sendCandidateTail(callId, batch, 0);
  });

  Future<void> _sendCandidateTail(
    CallId callId,
    List<CallIceCandidate> batch,
    int start, {
    bool Function()? canApply,
  }) async {
    for (var index = start; index < batch.length; index++) {
      final candidate = batch[index];
      try {
        await _transmit(
          callId: callId,
          event: CallSignalType.ice,
          iceGeneration: candidate.iceGeneration,
          payload: <String, Object?>{
            'candidate': candidate.value,
            'media_id': candidate.mediaId,
            'media_line_index': candidate.mediaLineIndex,
          },
          canApply: canApply,
          onDelivered: _candidateDelivered,
        );
      } on CallNegotiationPortException catch (error) {
        final retry = error.retry;
        if (error.code != CallNegotiationPortErrorCode.transportUnavailable ||
            retry == null) {
          rethrow;
        }
        throw CallNegotiationPortException(
          error.code,
          retry: _candidateTailRetry(retry, callId, batch, index + 1),
        );
      }
    }
  }

  CallNegotiationSignalRetry _candidateTailRetry(
    CallNegotiationSignalRetry first,
    CallId callId,
    List<CallIceCandidate> batch,
    int next,
  ) => _CandidateBatchRetry(
    first,
    (canApply) => _sendCandidateTail(callId, batch, next, canApply: canApply),
  );

  /// Sends the authenticated generation boundary before a fresh restart offer.
  /// The executor owns the order and creates the fresh offer after this returns.
  @override
  Future<void> sendIceRestart({
    required CallId callId,
    required int iceGeneration,
  }) => _guarded(() async {
    if (iceGeneration < 0) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }
    await _transmit(
      callId: callId,
      event: CallSignalType.iceRestart,
      iceGeneration: iceGeneration,
      payload: const <String, Object?>{},
      onDelivered: _restartDelivered,
    );
  });

  Future<void> _transmit({
    required CallId callId,
    required CallSignalType event,
    required int iceGeneration,
    required Map<String, Object?> payload,
    required void Function() onDelivered,
    bool Function()? canApply,
  }) async {
    final initial = _contextStore.read(callId);
    if (initial == null || canApply?.call() == false) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }

    final endpoint = await _resolveExactEndpoint(
      initial,
      event: event,
      canApply: canApply,
    );
    final signingPrivateKey = await _loadSigningKey();
    final current = _contextStore.read(callId);
    if (current == null ||
        !_sameBinding(initial, current) ||
        canApply?.call() == false) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }
    final metadata = _contextStore.reserveNextMetadata(
      callId,
      iceGeneration: iceGeneration,
    );
    final now = _clock().toUtc();
    final signal = CallSignal.create(
      callId: callId,
      messageId: _messageIdSource().value,
      event: event,
      senderAccountPeerId: current.localAccountPeerId,
      senderDevicePeerId: current.localDevicePeerId,
      recipientAccountPeerId: current.remoteAccountPeerId,
      recipientDevicePeerId: current.remoteDevicePeerId,
      senderSequence: metadata.senderSequence,
      iceGeneration: metadata.iceGeneration,
      createdAtMs: now.millisecondsSinceEpoch,
      expiresAtMs: now.add(signalLifetime).millisecondsSinceEpoch,
      payload: payload,
    );
    try {
      await _signalingService.transmit(
        signal: signal,
        callHandle: current.callHandle,
        endpoint: endpoint,
        senderSigningPrivateKey: signingPrivateKey,
        retainForRetry: true,
        canApply: canApply,
      );
      onDelivered();
    } on CallSignalingException catch (error) {
      final retry = error.retry;
      if (error.code == CallSignalingErrorCode.transportUnavailable) {
        throw CallNegotiationPortException(
          CallNegotiationPortErrorCode.transportUnavailable,
          retry: retry == null
              ? null
              : _negotiationRetry(
                  retry,
                  current,
                  endpoint,
                  signal.iceGeneration,
                  onDelivered,
                ),
        );
      }
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }
  }

  void _descriptionDelivered() => _descriptionSendCount++;
  void _candidateDelivered() => _candidateSendCount++;
  void _restartDelivered() => _restartSendCount++;

  CallNegotiationSignalRetry _negotiationRetry(
    CallSignalTransmissionRetry retry,
    CallSignalingContext context,
    ResolvedCallEndpoint endpoint,
    int iceGeneration,
    void Function() onDelivered,
  ) => _ProductionNegotiationSignalRetry(
    retry,
    () => _authorizeNegotiationRetry(context, endpoint, iceGeneration),
    onDelivered,
  );

  Future<bool> _authorizeNegotiationRetry(
    CallSignalingContext initial,
    ResolvedCallEndpoint original,
    int iceGeneration,
  ) async {
    bool currentBinding() {
      final current = _contextStore.read(initial.callId);
      return current != null &&
          _sameBinding(initial, current) &&
          current.iceGeneration == iceGeneration;
    }

    if (!currentBinding()) return false;
    final endpoint = await _resolveRetryEndpoint(
      _resolveCurrentEndpoint,
      original,
    );
    if (!_sameEndpointAuthority(original, endpoint) ||
        endpoint.expiresAtMs <= _clock().toUtc().millisecondsSinceEpoch) {
      return false;
    }
    await _loadSigningKey();
    return currentBinding() &&
        endpoint.expiresAtMs > _clock().toUtc().millisecondsSinceEpoch;
  }

  /// Re-resolves the exact accepted endpoint for every negotiation write and
  /// pins it per call; offer/answer/ICE/restart may fall back to the pin only
  /// when the directory record is transiently gone or the bridge failed.
  Future<ResolvedCallEndpoint> _resolveExactEndpoint(
    CallSignalingContext context, {
    required CallSignalType event,
    bool Function()? canApply,
  }) async {
    late final ResolvedCallEndpoint endpoint;
    try {
      endpoint = await _resolveCurrentEndpoint(context.remoteAccountPeerId);
    } on CallEndpointResolutionException catch (error) {
      final pinned = _pinnedEndpointFallback(
        pinned: _contextStore.pinnedEndpoint(context.callId),
        event: event,
        accountPeerId: context.remoteAccountPeerId,
        devicePeerId: context.remoteDevicePeerId,
        reason: error.code == CallEndpointResolutionCode.unavailable
            ? _PinnedFallbackReason.unavailable
            : null,
        nowMs: _clock().toUtc().millisecondsSinceEpoch,
        adapter: 'negotiation',
      );
      if (pinned != null) return pinned;
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    } on CallAuthorityException catch (error) {
      final pinned = _pinnedEndpointFallback(
        pinned: _contextStore.pinnedEndpoint(context.callId),
        event: event,
        accountPeerId: context.remoteAccountPeerId,
        devicePeerId: context.remoteDevicePeerId,
        reason: error.code == CallAuthorityErrorCode.bridgeFailure
            ? _PinnedFallbackReason.bridgeFailure
            : null,
        nowMs: _clock().toUtc().millisecondsSinceEpoch,
        adapter: 'negotiation',
      );
      if (pinned != null) return pinned;
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }
    if (endpoint.accountPeerId != context.remoteAccountPeerId ||
        endpoint.devicePeerId != context.remoteDevicePeerId) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }
    final current = _contextStore.read(context.callId);
    if (current == null ||
        !_sameBinding(context, current) ||
        canApply?.call() == false) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }
    _contextStore.pinEndpoint(context.callId, endpoint);
    return endpoint;
  }

  Future<String> _loadSigningKey() async {
    final key = await _loadSenderSigningPrivateKey();
    if (key.trim().isEmpty) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }
    return key;
  }

  Future<void> _guarded(Future<void> Function() operation) async {
    try {
      await operation();
    } on CallNegotiationPortException {
      _failureCount++;
      rethrow;
    } catch (_) {
      _failureCount++;
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }
  }

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'descriptionSendCount': _descriptionSendCount,
    'candidateSendCount': _candidateSendCount,
    'restartSendCount': _restartSendCount,
    'failureCount': _failureCount,
    'signalLifetimeMs': signalLifetime.inMilliseconds,
  };

  @override
  String toString() =>
      'ProductionCallNegotiationSignalingAdapter(${toDiagnosticMap()})';
}

CallId _newOpaqueId() => CallId.parse(const Uuid().v4());

enum _PinnedFallbackReason { unavailable, bridgeFailure }

/// Returns the call's pinned accepted endpoint when a resolution failure is
/// eligible for the fallback: never for `invite` (a fresh directory record is
/// the callee's consent to be woken), only for a transiently absent record or
/// a bridge failure, only for the exact expected device, and only while the
/// pinned record is unexpired. Emits one identifier-free diagnostic per use.
ResolvedCallEndpoint? _pinnedEndpointFallback({
  required ResolvedCallEndpoint? pinned,
  required CallSignalType event,
  required String accountPeerId,
  required String devicePeerId,
  required _PinnedFallbackReason? reason,
  required int nowMs,
  required String adapter,
}) {
  if (reason == null || event == CallSignalType.invite) return null;
  if (pinned == null ||
      pinned.accountPeerId != accountPeerId ||
      pinned.devicePeerId != devicePeerId ||
      pinned.expiresAtMs <= nowMs) {
    return null;
  }
  try {
    emitFlowEvent(
      layer: 'FL',
      event: 'CALL_ENDPOINT_PINNED_FALLBACK',
      details: <String, Object?>{'reason': reason.name, 'adapter': adapter},
    );
  } catch (_) {
    // Diagnostics never change signaling authority.
  }
  return pinned;
}

bool _validIdentity(String? value) =>
    value != null &&
    value.trim() == value &&
    value.isNotEmpty &&
    value.length <= 512;

bool _sameBinding(CallSignalingContext first, CallSignalingContext second) =>
    first.callId == second.callId &&
    first.direction == second.direction &&
    first.callHandle == second.callHandle &&
    first.localAccountPeerId == second.localAccountPeerId &&
    first.localDevicePeerId == second.localDevicePeerId &&
    first.remoteAccountPeerId == second.remoteAccountPeerId &&
    first.remoteDevicePeerId == second.remoteDevicePeerId;

CallRouteClass? _routeClass(CallDirectRoute route) => switch (route) {
  CallDirectRoute.direct => CallRouteClass.direct,
  CallDirectRoute.circuitRelay => CallRouteClass.circuitRelay,
  CallDirectRoute.unknown => null,
};

Future<ResolvedCallEndpoint> _resolveRetryEndpoint(
  ResolveCurrentCallEndpoint resolve,
  ResolvedCallEndpoint original,
) async {
  try {
    return await resolve(original.accountPeerId);
  } on CallEndpointResolutionException catch (error) {
    if (error.code == CallEndpointResolutionCode.unavailable) {
      throw const CallSignalingException(
        CallSignalingErrorCode.transportUnavailable,
      );
    }
    rethrow;
  } on CallAuthorityException catch (error) {
    if (error.code == CallAuthorityErrorCode.bridgeFailure &&
        (error.relayErrorCode == null ||
            error.relayErrorCode == 'CALL_CONTROL_UNAVAILABLE')) {
      // The production Go bridge uses this explicit code when the relay
      // transport is unavailable. Other relay refusals remain fail-closed.
      throw const CallSignalingException(
        CallSignalingErrorCode.transportUnavailable,
      );
    }
    rethrow;
  }
}

bool _sameEndpointAuthority(
  ResolvedCallEndpoint first,
  ResolvedCallEndpoint next,
) =>
    first.accountPeerId == next.accountPeerId &&
    first.devicePeerId == next.devicePeerId &&
    first.signingPublicKey == next.signingPublicKey &&
    first.mlKemPublicKey == next.mlKemPublicKey &&
    first.deviceKeyEpoch == next.deviceKeyEpoch &&
    first.preferenceEpoch == next.preferenceEpoch &&
    first.platform == next.platform &&
    first.routingHandle == next.routingHandle &&
    first.wakeHandle == next.wakeHandle;

final class _ProductionNegotiationSignalRetry
    implements CallNegotiationSignalRetry {
  _ProductionNegotiationSignalRetry(
    this._transmission,
    this._authorize,
    this._onDelivered,
  );
  CallSignalTransmissionRetry? _transmission;
  Future<bool> Function()? _authorize;
  void Function()? _onDelivered;

  @override
  Future<void> retry({required bool Function() canApply}) async {
    final transmission = _transmission;
    final authorize = _authorize;
    if (transmission == null || authorize == null || !canApply()) {
      close();
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }
    try {
      await transmission.retry(authorize: authorize, canApply: canApply);
      if (!canApply()) {
        throw const CallNegotiationPortException(
          CallNegotiationPortErrorCode.signalingUnavailable,
        );
      }
      _onDelivered?.call();
      close();
    } on CallSignalingException catch (error) {
      if (error.code == CallSignalingErrorCode.transportUnavailable) {
        final available = transmission.isAvailable;
        if (!available) close();
        throw CallNegotiationPortException(
          CallNegotiationPortErrorCode.transportUnavailable,
          retry: available ? this : null,
        );
      }
      close();
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    } catch (_) {
      close();
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }
  }

  @override
  void close() {
    _transmission?.close();
    _transmission = null;
    _authorize = null;
    _onDelivered = null;
  }
}

final class _CandidateBatchRetry implements CallNegotiationSignalRetry {
  _CandidateBatchRetry(this._first, this._tail);
  CallNegotiationSignalRetry? _first;
  Future<void> Function(bool Function())? _tail;

  @override
  Future<void> retry({required bool Function() canApply}) async {
    final first = _first;
    final tail = _tail;
    if (first == null || tail == null || !canApply()) {
      close();
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }
    try {
      await first.retry(canApply: canApply);
    } on CallNegotiationPortException catch (error) {
      if (error.code == CallNegotiationPortErrorCode.transportUnavailable &&
          error.retry != null) {
        if (!identical(_first, error.retry)) {
          _first?.close();
          _first = error.retry;
        }
        throw CallNegotiationPortException(error.code, retry: this);
      }
      close();
      rethrow;
    }
    _first = null;
    first.close();
    try {
      await tail(canApply);
    } finally {
      close();
    }
  }

  @override
  void close() {
    _first?.close();
    _first = null;
    _tail = null;
  }
}
