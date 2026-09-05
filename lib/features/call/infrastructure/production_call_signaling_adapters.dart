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
    implements CallNegotiationSignalingPort {
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
    );
    _descriptionSendCount++;
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
    for (final candidate in batch) {
      await _transmit(
        callId: callId,
        event: CallSignalType.ice,
        iceGeneration: candidate.iceGeneration,
        payload: <String, Object?>{
          'candidate': candidate.value,
          'media_id': candidate.mediaId,
          'media_line_index': candidate.mediaLineIndex,
        },
      );
      _candidateSendCount++;
    }
  });

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
    );
    _restartSendCount++;
  });

  Future<void> _transmit({
    required CallId callId,
    required CallSignalType event,
    required int iceGeneration,
    required Map<String, Object?> payload,
  }) async {
    final initial = _contextStore.read(callId);
    if (initial == null) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.signalingUnavailable,
      );
    }

    final endpoint = await _resolveExactEndpoint(initial, event: event);
    final signingPrivateKey = await _loadSigningKey();
    final current = _contextStore.read(callId);
    if (current == null || !_sameBinding(initial, current)) {
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
    await _signalingService.transmit(
      signal: signal,
      callHandle: current.callHandle,
      endpoint: endpoint,
      senderSigningPrivateKey: signingPrivateKey,
    );
  }

  /// Re-resolves the exact accepted endpoint for every negotiation write and
  /// pins it per call; offer/answer/ICE/restart may fall back to the pin only
  /// when the directory record is transiently gone or the bridge failed.
  Future<ResolvedCallEndpoint> _resolveExactEndpoint(
    CallSignalingContext context, {
    required CallSignalType event,
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
