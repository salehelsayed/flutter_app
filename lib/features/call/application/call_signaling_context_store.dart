import 'dart:collection';

import '../diagnostics/call_diagnostics.dart';

import '../domain/call_id.dart';
import '../domain/call_media.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_signal.dart';
import '../domain/call_signal_v2.dart';
import '../domain/call_wire_signal.dart';
import 'call_endpoint_resolver.dart';

enum CallSignalingContextErrorCode {
  capacityExceeded,
  contextUnavailable,
  invalidContext,
  bindingConflict,
  nonMonotonicMetadata,
}

/// Fixed-shape failure for the in-memory, call-only signaling context store.
///
/// Handles and peer authority are intentionally absent from the exception.
final class CallSignalingContextException implements Exception {
  const CallSignalingContextException(this.code);

  final CallSignalingContextErrorCode code;

  @override
  String toString() => 'CallSignalingContextException(${code.name})';
}

/// Receives a context only after a secure incoming envelope was authenticated.
abstract interface class AuthenticatedCallSignalingContextObserver {
  void captureAuthenticated({
    required CallSignal signal,
    required String callHandle,
    CallAdmissionAuthorityWitness? admissionAuthority,
  });

  void purge(CallId callId);
}

/// Optional typed v2 context capture. Legacy observers retain their v1 API.
abstract interface class AuthenticatedCallSignalingContextObserverV2
    implements AuthenticatedCallSignalingContextObserver {
  void captureAuthenticatedV2({
    required CallSignalV2 signal,
    required String callHandle,
    CallAdmissionAuthorityWitness? admissionAuthority,
  });
}

/// One reserved local sender sequence and its non-regressing ICE generation.
final class CallSignalingMetadata {
  const CallSignalingMetadata({
    required this.senderSequence,
    required this.iceGeneration,
  });

  final int senderSequence;
  final int iceGeneration;

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'senderSequence': senderSequence,
    'iceGeneration': iceGeneration,
  };

  @override
  String toString() => 'CallSignalingMetadata(${toDiagnosticMap()})';
}

/// Immutable, redacted view of one call's signaling bindings and counters.
final class CallSignalingContext {
  CallSignalingContext._({
    required this.callId,
    required this.direction,
    required this.callHandle,
    required this.localAccountPeerId,
    required this.localDevicePeerId,
    required this.remoteAccountPeerId,
    required this.remoteDevicePeerId,
    required this.admissionAuthority,
    required this.nextSenderSequence,
    required this.remoteSenderSequence,
    required this.iceGeneration,
    required Map<String, Object?> invitePayload,
    required this.wireVersion,
    required this.requestedMedia,
    required this.initialAcceptedMedia,
    required this.initialOfferReceived,
  }) : invitePayload = Map<String, Object?>.unmodifiable(invitePayload);

  final CallId callId;
  final CallDirection direction;
  final String callHandle;
  final String localAccountPeerId;
  final String localDevicePeerId;
  final String remoteAccountPeerId;
  final String remoteDevicePeerId;
  final CallAdmissionAuthorityWitness? admissionAuthority;
  final int nextSenderSequence;
  final int remoteSenderSequence;
  final int iceGeneration;
  final Map<String, Object?> invitePayload;

  /// Exact outgoing v2 invite, retained only for this bounded context lifetime.
  CallSignalV2? get preparedOutgoingV2Invite => null;

  final CallWireVersion wireVersion;
  final CallMediaKind requestedMedia;

  /// Immutable revision-zero choice, not the later switch machine's agreement.
  final CallMediaKind? initialAcceptedMedia;
  final bool initialOfferReceived;

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'direction': direction.name,
    'nextSenderSequence': nextSenderSequence,
    'remoteSenderSequence': remoteSenderSequence,
    'iceGeneration': iceGeneration,
    'invitePayloadFieldCount': invitePayload.length,
  };

  @override
  String toString() => 'CallSignalingContext(${toDiagnosticMap()})';
}

/// Bounded call-owned memory for opaque handles, authenticated peer bindings,
/// and the monotonic metadata shared by control and negotiation signaling.
///
/// This is not a call state machine. Admission and terminal ownership remain
/// exclusively in [CallCoordinator]/[CallReducer]; this store only supplies
/// bytes that reducer-approved effects need in order to send one signal.
final class CallSignalingContextStore
    implements AuthenticatedCallSignalingContextObserverV2 {
  CallSignalingContextStore({this.maxContexts = 4, this.videoEnabled = false}) {
    if (maxContexts <= 0) {
      throw ArgumentError.value(maxContexts, 'maxContexts', 'must be positive');
    }
  }

  final int maxContexts;
  final bool videoEnabled;
  final LinkedHashMap<CallId, _StoredCallSignalingContext> _contexts =
      LinkedHashMap<CallId, _StoredCallSignalingContext>();
  final ListQueue<CallId> _pendingIncomingInviteIds = ListQueue<CallId>();
  final LinkedHashMap<CallId, ResolvedCallEndpoint> _pinnedEndpoints =
      LinkedHashMap<CallId, ResolvedCallEndpoint>();

  int get length => _contexts.length;

  /// Remembers the most recent exactly-resolved endpoint of one call so a
  /// later signal can still reach the accepted device when the directory
  /// record is transiently gone. Bounded like contexts; [purge] clears it.
  void pinEndpoint(CallId callId, ResolvedCallEndpoint endpoint) {
    _pinnedEndpoints.remove(callId);
    while (_pinnedEndpoints.length >= maxContexts) {
      _pinnedEndpoints.remove(_pinnedEndpoints.keys.first);
    }
    _pinnedEndpoints[callId] = endpoint;
  }

  ResolvedCallEndpoint? pinnedEndpoint(CallId callId) =>
      _pinnedEndpoints[callId];

  /// The immutable prepared invite already owns its first sender sequence.
  /// Fresh capability/permission admission remains the caller's responsibility.
  void storeOutgoingV2({
    required CallSignalV2 invite,
    required String callHandle,
    CallAdmissionAuthorityWitness? admissionAuthority,
  }) {
    if (!videoEnabled || invite.event != CallSignalV2Type.invite) {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.invalidContext,
      );
    }
    _storeOutgoing(
      callId: invite.callId,
      callHandle: callHandle,
      localAccountPeerId: invite.senderAccountPeerId,
      localDevicePeerId: invite.senderDevicePeerId,
      remoteAccountPeerId: invite.recipientAccountPeerId,
      remoteDevicePeerId: invite.recipientDevicePeerId,
      admissionAuthority: admissionAuthority,
      nextSenderSequence: invite.senderSequence + 1,
      iceGeneration: invite.iceGeneration,
      invitePayload: invite.payload,
      wireVersion: CallWireVersion.v2,
      requestedMedia: _media(invite.payload['media']),
    );
  }

  @override
  void captureAuthenticatedV2({
    required CallSignalV2 signal,
    required String callHandle,
    CallAdmissionAuthorityWitness? admissionAuthority,
  }) {
    if (!videoEnabled) {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.invalidContext,
      );
    }
    _captureAuthenticated(
      signal: signal,
      callHandle: callHandle,
      admissionAuthority: admissionAuthority,
    );
  }

  /// Records an already-authorized local answer; it never opens capture.
  void recordLocalAcceptance(CallId callId, {required CallMediaKind media}) {
    final context = _contexts[callId];
    if (context == null) {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.contextUnavailable,
      );
    }
    if (context.wireVersion != CallWireVersion.v2 ||
        context.direction != CallDirection.incoming) {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.bindingConflict,
      );
    }
    _validateInitialChoice(context, media);
    context.initialAcceptedMedia = media;
  }

  void storeOutgoing({
    required CallId callId,
    required String callHandle,
    required String localAccountPeerId,
    required String localDevicePeerId,
    required String remoteAccountPeerId,
    required String remoteDevicePeerId,
    CallAdmissionAuthorityWitness? admissionAuthority,
    int nextSenderSequence = 1,
    int iceGeneration = 0,
    Map<String, Object?> invitePayload = const <String, Object?>{},
  }) => _storeOutgoing(
    callId: callId,
    callHandle: callHandle,
    localAccountPeerId: localAccountPeerId,
    localDevicePeerId: localDevicePeerId,
    remoteAccountPeerId: remoteAccountPeerId,
    remoteDevicePeerId: remoteDevicePeerId,
    admissionAuthority: admissionAuthority,
    nextSenderSequence: nextSenderSequence,
    iceGeneration: iceGeneration,
    invitePayload: invitePayload,
    wireVersion: CallWireVersion.v1,
    requestedMedia: CallMediaKind.audio,
  );

  void _storeOutgoing({
    required CallWireVersion wireVersion,
    required CallMediaKind requestedMedia,
    required CallId callId,
    required String callHandle,
    required String localAccountPeerId,
    required String localDevicePeerId,
    required String remoteAccountPeerId,
    required String remoteDevicePeerId,
    CallAdmissionAuthorityWitness? admissionAuthority,
    int nextSenderSequence = 1,
    int iceGeneration = 0,
    Map<String, Object?> invitePayload = const <String, Object?>{},
  }) {
    _validateBindings(
      callHandle: callHandle,
      localAccountPeerId: localAccountPeerId,
      localDevicePeerId: localDevicePeerId,
      remoteAccountPeerId: remoteAccountPeerId,
      remoteDevicePeerId: remoteDevicePeerId,
    );
    if (nextSenderSequence < 1 || iceGeneration < 0) {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.invalidContext,
      );
    }
    final existing = _contexts[callId];
    if (existing != null) {
      if (existing.direction == CallDirection.outgoing &&
          existing.wireVersion == wireVersion &&
          existing.requestedMedia == requestedMedia &&
          (wireVersion == CallWireVersion.v1 ||
              existing.invitePayload['camera'] == invitePayload['camera']) &&
          existing.callHandle == callHandle &&
          existing.localAccountPeerId == localAccountPeerId &&
          existing.localDevicePeerId == localDevicePeerId &&
          existing.remoteAccountPeerId == remoteAccountPeerId &&
          existing.remoteDevicePeerId == remoteDevicePeerId) {
        return;
      }
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.bindingConflict,
      );
    }
    _ensureCapacity();
    _contexts[callId] = _StoredCallSignalingContext(
      callId: callId,
      direction: CallDirection.outgoing,
      wireVersion: wireVersion,
      requestedMedia: requestedMedia,
      callHandle: callHandle,
      localAccountPeerId: localAccountPeerId,
      localDevicePeerId: localDevicePeerId,
      remoteAccountPeerId: remoteAccountPeerId,
      remoteDevicePeerId: remoteDevicePeerId,
      admissionAuthority: admissionAuthority,
      nextSenderSequence: nextSenderSequence,
      remoteSenderSequence: 0,
      remoteHighWaterEvent: null,
      iceGeneration: iceGeneration,
      invitePayload: _copyPayload(invitePayload),
    );
    final diagnostics = CallDiagnostics.instance;
    final traceId =
        diagnostics.traceForCall(callId: callId.value) ??
        diagnostics.currentTraceId;
    if (traceId != null) {
      diagnostics.bindCall(
        callId: callId.value,
        callHandle: callHandle,
        traceId: traceId,
      );
    }
  }

  @override
  void captureAuthenticated({
    required CallSignal signal,
    required String callHandle,
    CallAdmissionAuthorityWitness? admissionAuthority,
  }) => _captureAuthenticated(
    signal: signal,
    callHandle: callHandle,
    admissionAuthority: admissionAuthority,
  );

  void _captureAuthenticated({
    required CallWireSignal signal,
    required String callHandle,
    CallAdmissionAuthorityWitness? admissionAuthority,
  }) {
    final version = signal is CallSignalV2
        ? CallWireVersion.v2
        : CallWireVersion.v1;
    final event = signal.eventWireName;
    _validateBindings(
      callHandle: callHandle,
      localAccountPeerId: signal.recipientAccountPeerId,
      localDevicePeerId: signal.recipientDevicePeerId,
      remoteAccountPeerId: signal.senderAccountPeerId,
      remoteDevicePeerId: signal.senderDevicePeerId,
    );
    final existing = _contexts[signal.callId];
    if (existing != null) {
      if (existing.callHandle != callHandle ||
          existing.localAccountPeerId != signal.recipientAccountPeerId ||
          existing.localDevicePeerId != signal.recipientDevicePeerId ||
          existing.remoteAccountPeerId != signal.senderAccountPeerId ||
          existing.remoteDevicePeerId != signal.senderDevicePeerId) {
        throw const CallSignalingContextException(
          CallSignalingContextErrorCode.bindingConflict,
        );
      }
      // Validate before mutating any counters or initial media facts.
      final acceptedMedia = _validateVersionAndMedia(existing, signal, version);
      final senderSequenceRegressed =
          signal.senderSequence < existing.remoteSenderSequence;
      final reorderDistance =
          existing.remoteSenderSequence - signal.senderSequence;
      final reorderableNegotiationSignal =
          senderSequenceRegressed &&
          reorderDistance <= CallSignal.maximumNegotiationReorderingDistance &&
          signal.iceGeneration == existing.iceGeneration &&
          _isNegotiationSignal(event, version) &&
          existing.remoteHighWaterEvent != null &&
          _isNegotiationSignal(
            existing.remoteHighWaterEvent!,
            existing.wireVersion,
          );
      final generationRegressed = signal.iceGeneration < existing.iceGeneration;
      // A peer can hang up before receiving our latest ICE restart. Terminal
      // authority belongs to the bound call, not one negotiation generation;
      // binding and sender ordering checks still apply below.
      final terminalSignal = event == 'reject' || event == 'terminate';
      final generationAdvancedWithoutNewerSequence =
          signal.iceGeneration > existing.iceGeneration &&
          signal.senderSequence <= existing.remoteSenderSequence;
      if ((senderSequenceRegressed && !reorderableNegotiationSignal) ||
          (generationRegressed && !terminalSignal) ||
          generationAdvancedWithoutNewerSequence) {
        throw const CallSignalingContextException(
          CallSignalingContextErrorCode.nonMonotonicMetadata,
        );
      }
      // Authenticated frames can arrive out of sender order because each uses
      // an independent transport stream. Preserve the high-water metadata
      // while allowing an unseen frame from the current ICE generation to be
      // dispatched; replay/sequence reuse was rejected by the secure codec.
      if (signal.senderSequence > existing.remoteSenderSequence) {
        existing.remoteSenderSequence = signal.senderSequence;
        existing.remoteHighWaterEvent = event;
      }
      if (signal.iceGeneration > existing.iceGeneration) {
        existing.iceGeneration = signal.iceGeneration;
      }
      if (acceptedMedia != null) existing.initialAcceptedMedia = acceptedMedia;
      if (version == CallWireVersion.v2 &&
          event == 'offer' &&
          signal.payload['purpose'] == 'initial') {
        existing.initialOfferReceived = true;
      }
      return;
    }

    if (version == CallWireVersion.v2 &&
        event != 'invite' &&
        event != 'reject' &&
        event != 'terminate') {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.contextUnavailable,
      );
    }
    _ensureCapacity();
    _contexts[signal.callId] = _StoredCallSignalingContext(
      callId: signal.callId,
      direction: CallDirection.incoming,
      wireVersion: version,
      requestedMedia: version == CallWireVersion.v2 && event == 'invite'
          ? _media(signal.payload['media'])
          : CallMediaKind.audio,
      callHandle: callHandle,
      localAccountPeerId: signal.recipientAccountPeerId,
      localDevicePeerId: signal.recipientDevicePeerId,
      remoteAccountPeerId: signal.senderAccountPeerId,
      remoteDevicePeerId: signal.senderDevicePeerId,
      admissionAuthority: admissionAuthority,
      nextSenderSequence: 1,
      remoteSenderSequence: signal.senderSequence,
      remoteHighWaterEvent: event,
      iceGeneration: signal.iceGeneration,
      invitePayload: event == 'invite'
          ? _copyPayload(signal.payload)
          : const <String, Object?>{},
    );
    if (event == 'invite') {
      _pendingIncomingInviteIds.addLast(signal.callId);
    }
  }

  CallSignalingContext? read(CallId callId) => _contexts[callId]?.snapshot();

  CallSignalingMetadata reserveNextMetadata(
    CallId callId, {
    required int iceGeneration,
  }) {
    final context = _contexts[callId];
    if (context == null) {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.contextUnavailable,
      );
    }
    if (iceGeneration < context.iceGeneration ||
        context.nextSenderSequence < 1 ||
        context.nextSenderSequence >= 0x7fffffff) {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.nonMonotonicMetadata,
      );
    }
    context.iceGeneration = iceGeneration;
    final metadata = CallSignalingMetadata(
      senderSequence: context.nextSenderSequence,
      iceGeneration: context.iceGeneration,
    );
    context.nextSenderSequence++;
    return metadata;
  }

  void advanceIceGeneration(CallId callId, int iceGeneration) {
    final context = _contexts[callId];
    if (context == null) {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.contextUnavailable,
      );
    }
    if (iceGeneration < context.iceGeneration) {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.nonMonotonicMetadata,
      );
    }
    context.iceGeneration = iceGeneration;
  }

  /// Removes an admitted invite from the bounded busy-candidate queue.
  void markAdmitted(CallId callId) {
    _pendingIncomingInviteIds.removeWhere((candidate) => candidate == callId);
  }

  /// Claims one authenticated invite that the coordinator rejected as busy.
  /// The context remains addressable until the executor completes and purges
  /// it, while the queue claim prevents a duplicate send.
  CallSignalingContext? takePendingIncomingInvite({CallId? excluding}) {
    final candidates = _pendingIncomingInviteIds.length;
    for (var index = 0; index < candidates; index++) {
      final callId = _pendingIncomingInviteIds.removeFirst();
      if (callId == excluding) {
        _pendingIncomingInviteIds.addLast(callId);
        continue;
      }
      final context = _contexts[callId];
      if (context != null) return context.snapshot();
    }
    return null;
  }

  @override
  void purge(CallId callId) {
    _contexts.remove(callId);
    _pinnedEndpoints.remove(callId);
    _pendingIncomingInviteIds.removeWhere((candidate) => candidate == callId);
  }

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'contextCount': _contexts.length,
    'pinnedEndpointCount': _pinnedEndpoints.length,
    'pendingIncomingInviteCount': _pendingIncomingInviteIds.length,
    'maxContexts': maxContexts,
  };

  @override
  String toString() => 'CallSignalingContextStore(${toDiagnosticMap()})';

  static bool _isNegotiationSignal(String event, CallWireVersion version) {
    if (const {'offer', 'answer', 'ice'}.contains(event)) return true;
    // Keep the v1 context policy unchanged; v2 optional transactions use the
    // same bounded same-generation admission as their secure envelope path.
    return version == CallWireVersion.v2 &&
        const {
          'ice_restart',
          'media_request',
          'media_response',
          'media_commit',
          'media_commit_ack',
          'media_abort',
          'camera_state',
        }.contains(event);
  }

  static CallMediaKind _media(Object? value) => switch (value) {
    'audio' => CallMediaKind.audio,
    'video' => CallMediaKind.video,
    _ => throw const CallSignalingContextException(
      CallSignalingContextErrorCode.invalidContext,
    ),
  };

  static void _validateInitialChoice(
    _StoredCallSignalingContext context,
    CallMediaKind media,
  ) {
    if ((context.requestedMedia == CallMediaKind.audio &&
            media != CallMediaKind.audio) ||
        (context.initialAcceptedMedia != null &&
            context.initialAcceptedMedia != media)) {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.bindingConflict,
      );
    }
  }

  static CallMediaKind? _validateVersionAndMedia(
    _StoredCallSignalingContext context,
    CallWireSignal signal,
    CallWireVersion version,
  ) {
    if (context.wireVersion != version) {
      // Caller cancellation can outrun a lost v2 accept. The callee has no
      // proof the caller received its answer until the initial offer arrives.
      // Actual terminal reduction/tombstones remain owned by the coordinator.
      final compatibleCleanup =
          context.wireVersion == CallWireVersion.v2 &&
          version == CallWireVersion.v1 &&
          context.direction == CallDirection.incoming &&
          !context.initialOfferReceived &&
          signal.eventWireName == 'terminate' &&
          signal.payload['reason'] == 'unsupported';
      if (compatibleCleanup) return null;
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.bindingConflict,
      );
    }
    if (version == CallWireVersion.v1) return null;
    final event = signal.eventWireName;
    if (event == 'invite') {
      if (_media(signal.payload['media']) != context.requestedMedia ||
          signal.payload['camera'] != context.invitePayload['camera']) {
        throw const CallSignalingContextException(
          CallSignalingContextErrorCode.bindingConflict,
        );
      }
    }
    if (event == 'accept') {
      final accepted = _media(signal.payload['media']);
      if (context.direction != CallDirection.outgoing) {
        throw const CallSignalingContextException(
          CallSignalingContextErrorCode.bindingConflict,
        );
      }
      _validateInitialChoice(context, accepted);
      return accepted;
    }
    if (event == 'offer' || event == 'answer') {
      if (context.initialAcceptedMedia == null ||
          (event == 'offer' && context.direction != CallDirection.incoming) ||
          (event == 'answer' && context.direction != CallDirection.outgoing) ||
          (signal.payload['purpose'] == 'initial' &&
              _media(signal.payload['media']) !=
                  context.initialAcceptedMedia)) {
        throw const CallSignalingContextException(
          CallSignalingContextErrorCode.bindingConflict,
        );
      }
    }
    return null;
  }

  void _ensureCapacity() {
    if (_contexts.length >= maxContexts) {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.capacityExceeded,
      );
    }
  }

  static void _validateBindings({
    required String callHandle,
    required String localAccountPeerId,
    required String localDevicePeerId,
    required String remoteAccountPeerId,
    required String remoteDevicePeerId,
  }) {
    if (CallId.tryParse(callHandle) == null ||
        !_validIdentity(localAccountPeerId) ||
        !_validIdentity(localDevicePeerId) ||
        !_validIdentity(remoteAccountPeerId) ||
        !_validIdentity(remoteDevicePeerId)) {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.invalidContext,
      );
    }
  }

  static bool _validIdentity(String value) =>
      value.trim() == value && value.isNotEmpty && value.length <= 512;

  static Map<String, Object?> _copyPayload(Map<String, Object?> payload) =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in payload.entries)
          entry.key: _freezeJson(entry.value),
      });

  static Object? _freezeJson(Object? value) {
    if (value is Map) {
      final copy = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const CallSignalingContextException(
            CallSignalingContextErrorCode.invalidContext,
          );
        }
        copy[entry.key! as String] = _freezeJson(entry.value);
      }
      return Map<String, Object?>.unmodifiable(copy);
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map<Object?>(_freezeJson));
    }
    return value;
  }
}

final class _StoredCallSignalingContext {
  _StoredCallSignalingContext({
    required this.callId,
    required this.direction,
    required this.wireVersion,
    required this.requestedMedia,
    required this.callHandle,
    required this.localAccountPeerId,
    required this.localDevicePeerId,
    required this.remoteAccountPeerId,
    required this.remoteDevicePeerId,
    required this.admissionAuthority,
    required this.nextSenderSequence,
    required this.remoteSenderSequence,
    required this.remoteHighWaterEvent,
    required this.iceGeneration,
    required this.invitePayload,
  });

  final CallId callId;
  final CallDirection direction;
  final CallWireVersion wireVersion;
  final CallMediaKind requestedMedia;
  CallMediaKind? initialAcceptedMedia;
  bool initialOfferReceived = false;
  final String callHandle;
  final String localAccountPeerId;
  final String localDevicePeerId;
  final String remoteAccountPeerId;
  final String remoteDevicePeerId;
  final CallAdmissionAuthorityWitness? admissionAuthority;
  int nextSenderSequence;
  int remoteSenderSequence;
  String? remoteHighWaterEvent;
  int iceGeneration;
  final Map<String, Object?> invitePayload;

  CallSignalingContext snapshot() => CallSignalingContext._(
    callId: callId,
    direction: direction,
    wireVersion: wireVersion,
    requestedMedia: requestedMedia,
    initialAcceptedMedia: initialAcceptedMedia,
    initialOfferReceived: initialOfferReceived,
    callHandle: callHandle,
    localAccountPeerId: localAccountPeerId,
    localDevicePeerId: localDevicePeerId,
    remoteAccountPeerId: remoteAccountPeerId,
    remoteDevicePeerId: remoteDevicePeerId,
    admissionAuthority: admissionAuthority,
    nextSenderSequence: nextSenderSequence,
    remoteSenderSequence: remoteSenderSequence,
    iceGeneration: iceGeneration,
    invitePayload: invitePayload,
  );
}
