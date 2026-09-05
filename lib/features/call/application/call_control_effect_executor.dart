import 'dart:collection';

import '../../../core/utils/flow_event_emitter.dart';
import '../domain/call_end_reason.dart';
import '../domain/call_event.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_signal.dart';
import '../domain/call_state.dart';
import 'call_coordinator.dart';
import 'call_signaling_context_store.dart';

export 'composite_call_effect_executor.dart';

enum CallControlSignalingPortErrorCode {
  preparationUnavailable,
  endpointMismatch,
  transportUnavailable,
}

/// A fixed-shape call-control adapter failure. It cannot carry raw signaling,
/// call handles, endpoint authority, or identity values.
final class CallControlSignalingPortException implements Exception {
  const CallControlSignalingPortException(this.code);

  final CallControlSignalingPortErrorCode code;

  @override
  String toString() => 'CallControlSignalingPortException(${code.name})';
}

/// The bounded result of the dedicated direct/mailbox call-signaling race.
final class CallControlSendResult {
  const CallControlSendResult({
    required this.directAccepted,
    required this.mailboxStored,
    required this.mailboxStoreSettled,
    this.directRoute,
    this.wakeDispatched = false,
  });

  final bool directAccepted;
  final bool mailboxStored;

  /// The relay alerted the callee's device for this signal; the caller may
  /// treat the far end as ringing.
  final bool wakeDispatched;
  final CallRouteClass? directRoute;
  final Future<void> mailboxStoreSettled;

  bool get delivered => directAccepted || mailboxStored;

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'directAccepted': directAccepted,
    'mailboxStored': mailboxStored,
    'wakeDispatched': wakeDispatched,
    'directRoute': directRoute?.name,
  };

  @override
  String toString() => 'CallControlSendResult(${toDiagnosticMap()})';
}

/// Public, non-secret preparation data returned before an outgoing invite.
/// Endpoint keys and transport authority remain encapsulated by the port.
final class OutgoingCallSignalingPreparation {
  const OutgoingCallSignalingPreparation({
    required this.callHandle,
    required this.remoteAccountPeerId,
    required this.remoteDevicePeerId,
    this.nextSenderSequence = 1,
    this.iceGeneration = 0,
    this.invitePayload = const <String, Object?>{},
  });

  final String callHandle;
  final String remoteAccountPeerId;
  final String remoteDevicePeerId;
  final int nextSenderSequence;
  final int iceGeneration;
  final Map<String, Object?> invitePayload;

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'nextSenderSequence': nextSenderSequence,
    'iceGeneration': iceGeneration,
    'invitePayloadFieldCount': invitePayload.length,
  };

  @override
  String toString() =>
      'OutgoingCallSignalingPreparation('
      '${toDiagnosticMap()})';
}

/// The only application port used for call-control signaling. Implementations
/// may adapt the dedicated call direct/mailbox transport, but never chat,
/// durable message outbox, or the generic message retrier.
abstract interface class CallControlSignalingPort {
  Future<OutgoingCallSignalingPreparation> prepareOutgoingInvite(
    CallSessionSnapshot snapshot,
  );

  Future<CallControlSendResult> send({
    required CallSignal signal,
    required String callHandle,
  });
}

typedef OutgoingPreInviteRegistrar = Future<bool> Function(CallId callId);

typedef OutgoingMailboxInviteCanceller =
    Future<bool> Function({
      required String recipientDevicePeerId,
      required String callHandle,
    });

/// Executes reducer-approved call-control effects without owning transitions.
final class CallControlEffectExecutor implements CallEffectExecutor {
  /// Default sender lifetime, reserving cross-device clock headroom below the
  /// protocol's hard preconnect acceptance ceiling.
  static const Duration defaultSignalLifetime = Duration(seconds: 40);

  static const Duration defaultSignalExpiryHeadroom = Duration(seconds: 5);

  CallControlEffectExecutor({
    required this.contextStore,
    required this.signalingPort,
    required this.clock,
    required this.idSource,
    OutgoingPreInviteRegistrar? registerOutgoingBeforeInvite,
    OutgoingMailboxInviteCanceller? cancelOutgoingMailboxInvite,
    this.signalLifetime = defaultSignalLifetime,
    this.maxAttemptedEffects = 64,
  }) : _registerOutgoingBeforeInvite =
           registerOutgoingBeforeInvite ?? _allowOutgoingWithoutNativeOwner,
       _cancelOutgoingMailboxInvite =
           cancelOutgoingMailboxInvite ??
           _allowMailboxRetirementWithoutTransport {
    if (signalLifetime <= Duration.zero ||
        signalLifetime.inMilliseconds >
            CallSignal.maximumPreconnectLifetimeMs) {
      throw ArgumentError.value(
        signalLifetime,
        'signalLifetime',
        'must be within the call preconnect lifetime',
      );
    }
    if (maxAttemptedEffects <= 0) {
      throw ArgumentError.value(
        maxAttemptedEffects,
        'maxAttemptedEffects',
        'must be positive',
      );
    }
  }

  final CallSignalingContextStore contextStore;
  final CallControlSignalingPort signalingPort;
  final DateTime Function() clock;
  final CallId Function() idSource;
  final OutgoingPreInviteRegistrar _registerOutgoingBeforeInvite;
  final OutgoingMailboxInviteCanceller _cancelOutgoingMailboxInvite;
  final Duration signalLifetime;
  final int maxAttemptedEffects;

  final Set<String> _attempted = <String>{};
  final ListQueue<String> _attemptOrder = ListQueue<String>();
  final Set<CallId> _mailboxRetirementRequired = <CallId>{};
  final Map<CallId, Future<CallEvent?>> _inFlightInviteSends =
      <CallId, Future<CallEvent?>>{};
  final Map<CallId, Future<void>> _mailboxStoreSettlements =
      <CallId, Future<void>>{};
  final Map<CallId, Future<void>> _inFlightMailboxRetirements =
      <CallId, Future<void>>{};
  final Set<CallId> _retiredMailboxInvites = <CallId>{};
  final Set<CallId> _mailboxStoredInvites = <CallId>{};
  final Map<CallId, Future<CallEvent?>> _inFlightPreconnectTerminals =
      <CallId, Future<CallEvent?>>{};
  final ListQueue<CallId> _retiredMailboxInviteOrder = ListQueue<CallId>();
  int _nextEventSequence = 0;
  int _failureCount = 0;

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    final callId = snapshot.callId;
    if (callId == null) return null;

    switch (effect.type) {
      case CallEffectType.prepareOutgoingInvite:
        if (snapshot.direction != CallDirection.outgoing ||
            snapshot.state != CallState.preparing ||
            !_markAttempted(callId, effect.type)) {
          return null;
        }
        return _prepareOutgoing(snapshot);
      case CallEffectType.validateIncomingInvite:
      case CallEffectType.presentIncomingCall:
        if (snapshot.direction == CallDirection.incoming &&
            snapshot.state == CallState.incomingValidating) {
          contextStore.markAdmitted(callId);
        }
        return null;
      case CallEffectType.sendBusy:
        return _sendBusy(snapshot);
      case CallEffectType.sendInvite:
      case CallEffectType.sendRinging:
      case CallEffectType.sendAccept:
      case CallEffectType.sendReject:
      case CallEffectType.sendTerminate:
        if (!_effectAllowed(effect.type, snapshot) ||
            !_markAttempted(callId, effect.type)) {
          return null;
        }
        if (effect.type == CallEffectType.sendInvite) {
          _mailboxRetirementRequired.add(callId);
          return _trackInviteSend(snapshot);
        }
        if ((effect.type == CallEffectType.sendTerminate ||
                effect.type == CallEffectType.sendReject) &&
            snapshot.direction == CallDirection.outgoing &&
            snapshot.connectedAt == null &&
            _mailboxRetirementRequired.contains(callId)) {
          return _trackPreconnectTerminal(effect.type, snapshot);
        }
        return _sendForSnapshot(effect.type, snapshot);
      default:
        return null;
    }
  }

  /// Retires the caller's pre-connect mailbox invitation before its signaling
  /// context is purged. The invite send is allowed to settle first so a late
  /// store cannot recreate custody after cancellation. Concurrent terminal
  /// delivery and cleanup callers share one cancellation attempt.
  Future<void> retireOutgoingPreconnectInvite(CallSessionSnapshot snapshot) {
    final callId = snapshot.callId;
    if (callId == null ||
        snapshot.direction != CallDirection.outgoing ||
        !snapshot.isTerminal) {
      return Future<void>.value();
    }
    if (snapshot.connectedAt != null || snapshot.ringingAt != null) {
      // The callee already holds the invite (it rang). Cancelling the
      // mailbox now would also delete the terminate stored a moment ago,
      // which is the only copy a backgrounded callee can still receive.
      _mailboxRetirementRequired.remove(callId);
      _mailboxStoreSettlements.remove(callId);
      _mailboxStoredInvites.remove(callId);
      return Future<void>.value();
    }
    if (_mailboxStoredInvites.remove(callId)) {
      // The relay took the invite into the callee's mailbox and woke the
      // callee natively for it, even though no ringing signal reached this
      // side yet. The terminate stored behind that invite is the callee's
      // only cancel; retiring the mailbox would delete both and leave a
      // natively presented call with nothing to end it.
      _mailboxRetirementRequired.remove(callId);
      _mailboxStoreSettlements.remove(callId);
      return _awaitPreconnectTerminal(callId);
    }
    if (!_mailboxRetirementRequired.contains(callId)) {
      return Future<void>.value();
    }
    if (_retiredMailboxInvites.contains(callId)) {
      return Future<void>.value();
    }
    final inFlight = _inFlightMailboxRetirements[callId];
    if (inFlight != null) return inFlight;

    late final Future<void> retirement;
    retirement = _retireOutgoingPreconnectInvite(callId).whenComplete(() {
      if (identical(_inFlightMailboxRetirements[callId], retirement)) {
        _inFlightMailboxRetirements.remove(callId);
      }
    });
    _inFlightMailboxRetirements[callId] = retirement;
    return retirement;
  }

  /// A pre-connect terminate waits for the invite's mailbox custody, so the
  /// signaling-context cleanup must not purge the context underneath it.
  /// The context is purged right after retirement; let the terminate that
  /// is still ordering itself behind the invite finish first.
  Future<void> _awaitPreconnectTerminal(CallId callId) async {
    final send = _inFlightPreconnectTerminals[callId];
    if (send == null) return;
    try {
      await send;
    } catch (_) {
      // The send reports its own failure; retirement is unaffected.
    }
  }

  Future<CallEvent?> _trackPreconnectTerminal(
    CallEffectType effectType,
    CallSessionSnapshot snapshot,
  ) async {
    final callId = snapshot.callId!;
    final send = _sendForSnapshot(effectType, snapshot);
    _inFlightPreconnectTerminals[callId] = send;
    try {
      return await send;
    } finally {
      if (identical(_inFlightPreconnectTerminals[callId], send)) {
        _inFlightPreconnectTerminals.remove(callId);
      }
    }
  }

  Future<CallEvent?> _trackInviteSend(CallSessionSnapshot snapshot) async {
    final callId = snapshot.callId!;
    final send = _sendForSnapshot(CallEffectType.sendInvite, snapshot);
    _inFlightInviteSends[callId] = send;
    try {
      return await send;
    } finally {
      if (identical(_inFlightInviteSends[callId], send)) {
        _inFlightInviteSends.remove(callId);
      }
    }
  }

  Future<void> _retireOutgoingPreconnectInvite(CallId callId) async {
    final context = contextStore.read(callId);
    if (context == null) {
      throw const CallSignalingContextException(
        CallSignalingContextErrorCode.contextUnavailable,
      );
    }
    final inviteSend = _inFlightInviteSends[callId];
    if (inviteSend != null) await inviteSend;
    final mailboxStoreSettlement = _mailboxStoreSettlements[callId];
    if (mailboxStoreSettlement != null) await mailboxStoreSettlement;
    final cancelled = await _cancelOutgoingMailboxInvite(
      recipientDevicePeerId: context.remoteDevicePeerId,
      callHandle: context.callHandle,
    );
    if (!cancelled) {
      throw const CallControlSignalingPortException(
        CallControlSignalingPortErrorCode.transportUnavailable,
      );
    }
    _mailboxRetirementRequired.remove(callId);
    _mailboxStoreSettlements.remove(callId);
    if (_retiredMailboxInvites.add(callId)) {
      _retiredMailboxInviteOrder.addLast(callId);
      while (_retiredMailboxInviteOrder.length > maxAttemptedEffects) {
        _retiredMailboxInvites.remove(_retiredMailboxInviteOrder.removeFirst());
      }
    }
  }

  Future<CallEvent?> _prepareOutgoing(CallSessionSnapshot snapshot) async {
    final callId = snapshot.callId!;
    try {
      final prepared = await signalingPort.prepareOutgoingInvite(snapshot);
      if (prepared.remoteAccountPeerId != snapshot.contactPeerId) {
        throw const CallControlSignalingPortException(
          CallControlSignalingPortErrorCode.endpointMismatch,
        );
      }
      contextStore.storeOutgoing(
        callId: callId,
        callHandle: prepared.callHandle,
        localAccountPeerId: snapshot.callerAccountPeerId!,
        localDevicePeerId: snapshot.callerDeviceId!,
        remoteAccountPeerId: prepared.remoteAccountPeerId,
        remoteDevicePeerId: prepared.remoteDevicePeerId,
        nextSenderSequence: prepared.nextSenderSequence,
        iceGeneration: prepared.iceGeneration,
        invitePayload: prepared.invitePayload,
      );
      final registered = await _registerOutgoingBeforeInvite(callId);
      if (!registered) {
        throw const CallControlSignalingPortException(
          CallControlSignalingPortErrorCode.preparationUnavailable,
        );
      }
      return _followUp(
        type: CallEventType.outgoingInviteReady,
        snapshot: snapshot,
      );
    } catch (_) {
      _failureCount++;
      contextStore.purge(callId);
      return _signalingFailure(snapshot);
    }
  }

  Future<CallEvent?> _sendForSnapshot(
    CallEffectType effectType,
    CallSessionSnapshot snapshot,
  ) async {
    final callId = snapshot.callId!;
    final terminal =
        effectType == CallEffectType.sendReject ||
        effectType == CallEffectType.sendTerminate;
    final preserveForMailboxRetirement =
        snapshot.direction == CallDirection.outgoing &&
        snapshot.connectedAt == null &&
        _mailboxRetirementRequired.contains(callId);
    try {
      final context = contextStore.read(callId);
      if (context == null) {
        throw const CallSignalingContextException(
          CallSignalingContextErrorCode.contextUnavailable,
        );
      }
      if (terminal && preserveForMailboxRetirement) {
        // A pre-connect terminate must land behind the invite's mailbox
        // custody, never before it: a callee draining a late invite after
        // the terminate would ring for a call that is already over.
        final inviteCustody = _mailboxStoreSettlements[callId];
        if (inviteCustody != null) {
          try {
            await inviteCustody;
          } catch (_) {
            // A failed invite store leaves nothing to order behind.
          }
        }
      }
      final result = await _send(
        effectType: effectType,
        context: context,
        endReason: snapshot.endReason,
      );
      if (effectType != CallEffectType.sendInvite) return null;
      _mailboxStoreSettlements[callId] = result.mailboxStoreSettled;
      if (result.mailboxStored) {
        _mailboxStoredInvites.add(callId);
        // A dispatched wake confirms custody and alerts the far end at once:
        // a headless callee rings without signalling until it is answered.
        return _followUp(
          type: result.wakeDispatched
              ? CallEventType.wakeRequested
              : CallEventType.mailboxStored,
          snapshot: snapshot,
          transportRoute: CallRouteClass.ephemeralMailbox,
        );
      }
      return _followUp(
        type: CallEventType.directAccepted,
        snapshot: snapshot,
        transportRoute: result.directRoute,
      );
    } catch (_) {
      _failureCount++;
      if (effectType != CallEffectType.sendInvite &&
          !preserveForMailboxRetirement) {
        contextStore.purge(callId);
      }
      return _signalingFailure(snapshot);
    } finally {
      if (terminal && !preserveForMailboxRetirement) {
        _mailboxStoredInvites.remove(callId);
        contextStore.purge(callId);
      }
    }
  }

  Future<CallEvent?> _sendBusy(CallSessionSnapshot activeSnapshot) async {
    final pending = contextStore.takePendingIncomingInvite(
      excluding: activeSnapshot.callId,
    );
    if (pending == null ||
        !_markAttempted(pending.callId, CallEffectType.sendBusy)) {
      return null;
    }
    try {
      await _send(
        effectType: CallEffectType.sendBusy,
        context: pending,
        endReason: CallEndReason.busy,
      );
    } catch (_) {
      // Busy belongs to the rejected incoming call. Its transport failure must
      // never recursively fail or terminate the unrelated active snapshot.
      _failureCount++;
    } finally {
      contextStore.purge(pending.callId);
    }
    return null;
  }

  Future<CallControlSendResult> _send({
    required CallEffectType effectType,
    required CallSignalingContext context,
    required CallEndReason? endReason,
  }) async {
    final metadata = contextStore.reserveNextMetadata(
      context.callId,
      iceGeneration: context.iceGeneration,
    );
    final now = clock().toUtc();
    final signal = CallSignal.create(
      callId: context.callId,
      messageId: idSource().value,
      event: _signalType(effectType),
      senderAccountPeerId: context.localAccountPeerId,
      senderDevicePeerId: context.localDevicePeerId,
      recipientAccountPeerId: context.remoteAccountPeerId,
      recipientDevicePeerId: context.remoteDevicePeerId,
      senderSequence: metadata.senderSequence,
      iceGeneration: metadata.iceGeneration,
      createdAtMs: now.millisecondsSinceEpoch,
      expiresAtMs: now.add(signalLifetime).millisecondsSinceEpoch,
      payload: _payload(effectType, context.invitePayload, endReason),
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'CALL_CONTROL_SIGNAL_SEND_ATTEMPT',
      details: <String, Object?>{'type': signal.event.wireName},
    );
    late final CallControlSendResult result;
    try {
      result = await signalingPort.send(
        signal: signal,
        callHandle: context.callHandle,
      );
    } on CallControlSignalingPortException catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_CONTROL_SIGNAL_SEND_FAILED',
        details: <String, Object?>{
          'type': signal.event.wireName,
          'code': error.code.name,
        },
      );
      rethrow;
    } catch (_) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_CONTROL_SIGNAL_SEND_FAILED',
        details: <String, Object?>{
          'type': signal.event.wireName,
          'code': 'unexpected',
        },
      );
      rethrow;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CALL_CONTROL_SIGNAL_SEND_RESULT',
      details: <String, Object?>{
        'type': signal.event.wireName,
        'delivered': result.delivered,
        'directAccepted': result.directAccepted,
        'mailboxStored': result.mailboxStored,
      },
    );
    if (!result.delivered) {
      throw const CallControlSignalingPortException(
        CallControlSignalingPortErrorCode.transportUnavailable,
      );
    }
    return result;
  }

  CallEvent _signalingFailure(CallSessionSnapshot snapshot) => _followUp(
    type: CallEventType.negotiationFailed,
    snapshot: snapshot,
    endReason: CallEndReason.signalingFailed,
  );

  static Future<bool> _allowOutgoingWithoutNativeOwner(CallId _) async => true;

  static Future<bool> _allowMailboxRetirementWithoutTransport({
    required String recipientDevicePeerId,
    required String callHandle,
  }) async => true;

  CallEvent _followUp({
    required CallEventType type,
    required CallSessionSnapshot snapshot,
    CallRouteClass? transportRoute,
    CallEndReason? endReason,
  }) => CallEvent(
    type: type,
    eventId: 'call-control-${type.name}-${_nextEventSequence++}',
    occurredAt: clock(),
    callId: snapshot.callId,
    contactPeerId: snapshot.contactPeerId,
    localAccountPeerId: snapshot.direction == CallDirection.outgoing
        ? snapshot.callerAccountPeerId
        : null,
    localDeviceId: snapshot.direction == CallDirection.outgoing
        ? snapshot.callerDeviceId
        : null,
    remoteAccountPeerId: snapshot.direction == CallDirection.incoming
        ? snapshot.callerAccountPeerId
        : snapshot.contactPeerId,
    remoteDeviceId: snapshot.direction == CallDirection.incoming
        ? snapshot.callerDeviceId
        : null,
    transportRoute: transportRoute,
    endReason: endReason,
  );

  bool _markAttempted(CallId callId, CallEffectType type) {
    final key = '${callId.value}\u0000${type.name}';
    if (_attempted.contains(key)) return false;
    if (_attempted.length >= maxAttemptedEffects) {
      _attempted.remove(_attemptOrder.removeFirst());
    }
    _attempted.add(key);
    _attemptOrder.addLast(key);
    return true;
  }

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'attemptedEffectCount': _attempted.length,
    'failureCount': _failureCount,
    'storedContextCount': contextStore.length,
    'pendingMailboxRetirementCount': _mailboxRetirementRequired.length,
    'retiredMailboxInviteCount': _retiredMailboxInvites.length,
    'maxAttemptedEffects': maxAttemptedEffects,
  };

  @override
  String toString() => 'CallControlEffectExecutor(${toDiagnosticMap()})';

  static bool _effectAllowed(
    CallEffectType effectType,
    CallSessionSnapshot snapshot,
  ) => switch (effectType) {
    CallEffectType.sendInvite =>
      snapshot.direction == CallDirection.outgoing &&
          snapshot.state == CallState.inviting,
    CallEffectType.sendRinging =>
      snapshot.direction == CallDirection.incoming &&
          snapshot.state == CallState.ringing,
    CallEffectType.sendAccept =>
      snapshot.direction == CallDirection.incoming &&
          snapshot.state == CallState.accepted,
    CallEffectType.sendReject =>
      snapshot.direction == CallDirection.incoming &&
          snapshot.state == CallState.ended,
    CallEffectType.sendTerminate => snapshot.state == CallState.ended,
    _ => false,
  };

  static CallSignalType _signalType(CallEffectType effectType) =>
      switch (effectType) {
        CallEffectType.sendInvite => CallSignalType.invite,
        CallEffectType.sendRinging => CallSignalType.ringing,
        CallEffectType.sendAccept => CallSignalType.accept,
        CallEffectType.sendReject ||
        CallEffectType.sendBusy => CallSignalType.reject,
        CallEffectType.sendTerminate => CallSignalType.terminate,
        _ => throw const CallControlSignalingPortException(
          CallControlSignalingPortErrorCode.preparationUnavailable,
        ),
      };

  static Map<String, Object?> _payload(
    CallEffectType effectType,
    Map<String, Object?> invitePayload,
    CallEndReason? endReason,
  ) => switch (effectType) {
    CallEffectType.sendInvite => invitePayload,
    CallEffectType.sendReject => <String, Object?>{
      'reason': (endReason ?? CallEndReason.declined).wireName,
    },
    CallEffectType.sendBusy => <String, Object?>{
      'reason': CallEndReason.busy.wireName,
    },
    CallEffectType.sendTerminate => <String, Object?>{
      'reason': (endReason ?? CallEndReason.localHangup).wireName,
    },
    _ => const <String, Object?>{},
  };
}
