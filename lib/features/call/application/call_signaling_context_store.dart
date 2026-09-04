import 'dart:collection';

import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_signal.dart';

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
  });

  void purge(CallId callId);
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
    required this.nextSenderSequence,
    required this.remoteSenderSequence,
    required this.iceGeneration,
    required Map<String, Object?> invitePayload,
  }) : invitePayload = Map<String, Object?>.unmodifiable(invitePayload);

  final CallId callId;
  final CallDirection direction;
  final String callHandle;
  final String localAccountPeerId;
  final String localDevicePeerId;
  final String remoteAccountPeerId;
  final String remoteDevicePeerId;
  final int nextSenderSequence;
  final int remoteSenderSequence;
  final int iceGeneration;
  final Map<String, Object?> invitePayload;

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
    implements AuthenticatedCallSignalingContextObserver {
  CallSignalingContextStore({this.maxContexts = 4}) {
    if (maxContexts <= 0) {
      throw ArgumentError.value(maxContexts, 'maxContexts', 'must be positive');
    }
  }

  final int maxContexts;
  final LinkedHashMap<CallId, _StoredCallSignalingContext> _contexts =
      LinkedHashMap<CallId, _StoredCallSignalingContext>();
  final ListQueue<CallId> _pendingIncomingInviteIds = ListQueue<CallId>();

  int get length => _contexts.length;

  void storeOutgoing({
    required CallId callId,
    required String callHandle,
    required String localAccountPeerId,
    required String localDevicePeerId,
    required String remoteAccountPeerId,
    required String remoteDevicePeerId,
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
      callHandle: callHandle,
      localAccountPeerId: localAccountPeerId,
      localDevicePeerId: localDevicePeerId,
      remoteAccountPeerId: remoteAccountPeerId,
      remoteDevicePeerId: remoteDevicePeerId,
      nextSenderSequence: nextSenderSequence,
      remoteSenderSequence: 0,
      remoteHighWaterEvent: null,
      iceGeneration: iceGeneration,
      invitePayload: _copyPayload(invitePayload),
    );
  }

  @override
  void captureAuthenticated({
    required CallSignal signal,
    required String callHandle,
  }) {
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
      final senderSequenceRegressed =
          signal.senderSequence < existing.remoteSenderSequence;
      final reorderDistance =
          existing.remoteSenderSequence - signal.senderSequence;
      final reorderableNegotiationSignal =
          senderSequenceRegressed &&
          reorderDistance <= CallSignal.maximumNegotiationReorderingDistance &&
          signal.iceGeneration == existing.iceGeneration &&
          _isNegotiationSignal(signal.event) &&
          existing.remoteHighWaterEvent != null &&
          _isNegotiationSignal(existing.remoteHighWaterEvent!);
      final generationRegressed = signal.iceGeneration < existing.iceGeneration;
      final generationAdvancedWithoutNewerSequence =
          signal.iceGeneration > existing.iceGeneration &&
          signal.senderSequence <= existing.remoteSenderSequence;
      if ((senderSequenceRegressed && !reorderableNegotiationSignal) ||
          generationRegressed ||
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
        existing.remoteHighWaterEvent = signal.event;
      }
      if (signal.iceGeneration > existing.iceGeneration) {
        existing.iceGeneration = signal.iceGeneration;
      }
      return;
    }

    _ensureCapacity();
    _contexts[signal.callId] = _StoredCallSignalingContext(
      callId: signal.callId,
      direction: CallDirection.incoming,
      callHandle: callHandle,
      localAccountPeerId: signal.recipientAccountPeerId,
      localDevicePeerId: signal.recipientDevicePeerId,
      remoteAccountPeerId: signal.senderAccountPeerId,
      remoteDevicePeerId: signal.senderDevicePeerId,
      nextSenderSequence: 1,
      remoteSenderSequence: signal.senderSequence,
      remoteHighWaterEvent: signal.event,
      iceGeneration: signal.iceGeneration,
      invitePayload: const <String, Object?>{},
    );
    if (signal.event == CallSignalType.invite) {
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
    _pendingIncomingInviteIds.removeWhere((candidate) => candidate == callId);
  }

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'contextCount': _contexts.length,
    'pendingIncomingInviteCount': _pendingIncomingInviteIds.length,
    'maxContexts': maxContexts,
  };

  @override
  String toString() => 'CallSignalingContextStore(${toDiagnosticMap()})';

  static bool _isNegotiationSignal(CallSignalType event) => switch (event) {
    CallSignalType.offer || CallSignalType.answer || CallSignalType.ice => true,
    _ => false,
  };

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
    required this.callHandle,
    required this.localAccountPeerId,
    required this.localDevicePeerId,
    required this.remoteAccountPeerId,
    required this.remoteDevicePeerId,
    required this.nextSenderSequence,
    required this.remoteSenderSequence,
    required this.remoteHighWaterEvent,
    required this.iceGeneration,
    required this.invitePayload,
  });

  final CallId callId;
  final CallDirection direction;
  final String callHandle;
  final String localAccountPeerId;
  final String localDevicePeerId;
  final String remoteAccountPeerId;
  final String remoteDevicePeerId;
  int nextSenderSequence;
  int remoteSenderSequence;
  CallSignalType? remoteHighWaterEvent;
  int iceGeneration;
  final Map<String, Object?> invitePayload;

  CallSignalingContext snapshot() => CallSignalingContext._(
    callId: callId,
    direction: direction,
    callHandle: callHandle,
    localAccountPeerId: localAccountPeerId,
    localDevicePeerId: localDevicePeerId,
    remoteAccountPeerId: remoteAccountPeerId,
    remoteDevicePeerId: remoteDevicePeerId,
    nextSenderSequence: nextSenderSequence,
    remoteSenderSequence: remoteSenderSequence,
    iceGeneration: iceGeneration,
    invitePayload: invitePayload,
  );
}
