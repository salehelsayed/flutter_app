import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../domain/call_event.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_signal.dart';
import '../infrastructure/call_mailbox_client.dart';
import '../infrastructure/p2p_call_transport.dart';
import '../infrastructure/secure_call_envelope_codec.dart';
import 'call_coordinator.dart';
import 'call_endpoint_resolver.dart';
import 'call_network_gate.dart';

enum CallSignalingErrorCode {
  migrationPaused,
  endpointMismatch,
  transportUnavailable,
}

final class CallSignalingException implements Exception {
  const CallSignalingException(this.code);

  final CallSignalingErrorCode code;

  @override
  String toString() => 'Call signaling failed: ${code.name}';
}

final class CallSignalTransportResult {
  const CallSignalTransportResult({
    required this.directAccepted,
    required this.mailboxStored,
    required this.directRoute,
    this.wakeDispatched = false,
  }) : _directSettled = true,
       _mailboxStoreSettled = null;

  const CallSignalTransportResult._race({
    required this.directAccepted,
    required this.mailboxStored,
    required this.directRoute,
    required bool directSettled,
    required Future<void> mailboxStoreSettled,
    this.wakeDispatched = false,
  }) : _directSettled = directSettled,
       _mailboxStoreSettled = mailboxStoreSettled;

  final bool directAccepted;
  final bool mailboxStored;

  /// The relay alerted the callee's device for this signal (its store
  /// receipt said `wake: dispatched`). The caller may ring back on it.
  final bool wakeDispatched;
  final CallDirectRoute directRoute;
  final bool _directSettled;
  final Future<void>? _mailboxStoreSettled;

  bool get delivered => directAccepted || mailboxStored;

  /// Completes without error after this exact mailbox write either settles in
  /// custody or definitively fails. A retirement path can await this handoff
  /// before issuing mailbox cancellation without delaying direct delivery.
  Future<void> get mailboxStoreSettled =>
      _mailboxStoreSettled ?? Future<void>.value();

  @override
  String toString() =>
      'CallSignalTransportResult(directAccepted: $directAccepted, '
      'mailboxStored: $mailboxStored, route: ${directRoute.name})';
}

enum _CallSignalingLeg {
  directSend('direct_send'),
  mailboxStore('mailbox_store');

  const _CallSignalingLeg(this.operation);

  final String operation;
}

/// Encodes one canonical signal exactly once, then races the dedicated direct
/// stream and ephemeral call mailbox. Neither leg uses chat serialization,
/// durable chat outbox, or the generic retrier.
final class CallSignalingService {
  const CallSignalingService({
    required SecureCallEnvelopeCodec codec,
    required CallDirectTransport directTransport,
    required CallMailboxClient mailboxClient,
    // Transport-only runtimes (the headless decline reply) pass no
    // coordinator: [transmit] works, [send] fails closed.
    CallCoordinator? coordinator,
    required CallNetworkEffectsAllowed networkEffectsAllowed,
  }) : _codec = codec,
       _directTransport = directTransport,
       _mailboxClient = mailboxClient,
       _coordinator = coordinator,
       _networkEffectsAllowed = networkEffectsAllowed;

  final SecureCallEnvelopeCodec _codec;
  final CallDirectTransport _directTransport;
  final CallMailboxClient _mailboxClient;
  final CallCoordinator? _coordinator;
  final CallNetworkEffectsAllowed _networkEffectsAllowed;
  static final RegExp _wakeHandleGrammar = RegExp(r'^[0-9a-f]{32}$');

  Future<CallSignalTransportResult> send({
    required CallSignal signal,
    required String callHandle,
    required ResolvedCallEndpoint endpoint,
    required String senderSigningPrivateKey,
  }) async {
    final result = await transmit(
      signal: signal,
      callHandle: callHandle,
      endpoint: endpoint,
      senderSigningPrivateKey: senderSigningPrivateKey,
    );

    await _dispatchReceipts(signal: signal, result: result);
    return result;
  }

  /// Performs only the dedicated call-network writes and returns their
  /// receipts. Effect executors use this entrypoint because they already run
  /// inside the coordinator's serialized dispatch lane; receipt events are
  /// returned to that lane instead of recursively dispatching here.
  Future<CallSignalTransportResult> transmit({
    required CallSignal signal,
    required String callHandle,
    required ResolvedCallEndpoint endpoint,
    required String senderSigningPrivateKey,
  }) async {
    var networkEffectsAllowed = false;
    try {
      networkEffectsAllowed = await callNetworkEffectsAreAllowed(
        _networkEffectsAllowed,
      );
    } catch (_) {
      networkEffectsAllowed = false;
    }
    if (!networkEffectsAllowed) {
      throw const CallSignalingException(
        CallSignalingErrorCode.migrationPaused,
      );
    }
    if (signal.recipientAccountPeerId != endpoint.accountPeerId ||
        signal.recipientDevicePeerId != endpoint.devicePeerId ||
        endpoint.expiresAtMs <= signal.createdAtMs ||
        endpoint.routingHandle.trim().isEmpty ||
        !_wakeHandleGrammar.hasMatch(endpoint.wakeHandle)) {
      throw const CallSignalingException(
        CallSignalingErrorCode.endpointMismatch,
      );
    }

    final envelope = await _codec.encode(
      signal: signal,
      callHandle: callHandle,
      recipientMlKemPublicKey: endpoint.mlKemPublicKey,
      senderSigningPrivateKey: senderSigningPrivateKey,
    );

    // Invoke both before awaiting either so a slow/unreachable direct path can
    // never delay custody at the call mailbox.
    final directFuture = _sendDirect(
      recipientDevicePeerId: endpoint.devicePeerId,
      envelopeJson: envelope,
    );
    final mailboxFuture = _storeMailbox(
      signal: signal,
      callHandle: callHandle,
      endpoint: endpoint,
      envelope: envelope,
    );
    return _firstSufficientResult(
      directFuture: directFuture,
      mailboxFuture: mailboxFuture,
    );
  }

  Future<CallSignalTransportResult> _firstSufficientResult({
    required Future<CallDirectSendResult> directFuture,
    required Future<_MailboxLegResult> mailboxFuture,
  }) {
    final result = Completer<CallSignalTransportResult>();
    final mailboxStoreSettled = mailboxFuture.then<void>((_) {});
    CallDirectSendResult? direct;
    bool? mailboxStored;
    var wakeDispatched = false;
    var resolutionQueued = false;

    void resolve() {
      resolutionQueued = false;
      if (result.isCompleted) return;

      final currentDirect = direct;
      final currentMailboxStored = mailboxStored;
      if ((currentDirect?.accepted ?? false) || currentMailboxStored == true) {
        result.complete(
          CallSignalTransportResult._race(
            directAccepted: currentDirect?.accepted ?? false,
            mailboxStored: currentMailboxStored ?? false,
            directRoute: currentDirect?.route ?? CallDirectRoute.unknown,
            directSettled: currentDirect != null,
            mailboxStoreSettled: mailboxStoreSettled,
            wakeDispatched: wakeDispatched,
          ),
        );
        return;
      }
      if (currentDirect != null && currentMailboxStored != null) {
        result.completeError(
          const CallSignalingException(
            CallSignalingErrorCode.transportUnavailable,
          ),
        );
      }
    }

    void queueResolution() {
      if (result.isCompleted || resolutionQueued) return;
      resolutionQueued = true;
      // Preserve receipts from legs that settle in the same event-loop turn
      // without waiting for a genuinely slow or hung sibling transport.
      scheduleMicrotask(resolve);
    }

    unawaited(
      directFuture.then<void>((value) {
        direct = value;
        queueResolution();
      }),
    );
    unawaited(
      mailboxFuture.then<void>((value) {
        mailboxStored = value.stored;
        wakeDispatched = value.wakeDispatched;
        queueResolution();
      }),
    );
    return result.future;
  }

  Future<void> _dispatchReceipts({
    required CallSignal signal,
    required CallSignalTransportResult result,
  }) async {
    final coordinator = _coordinator;
    if (coordinator == null) {
      throw StateError('receipt dispatch requires a coordinator');
    }
    // Mailbox custody can win while direct is still unresolved. Do not turn
    // that provisional false value into a synthetic direct-failure event.
    if (result._directSettled) {
      await coordinator.dispatch(
        CallEvent(
          type: result.directAccepted
              ? CallEventType.directAccepted
              : CallEventType.directFailed,
          eventId:
              '${signal.messageId}:${result.directAccepted ? 'direct-ok' : 'direct-failed'}',
          occurredAt: DateTime.fromMillisecondsSinceEpoch(
            signal.createdAtMs,
            isUtc: true,
          ),
          callId: signal.callId,
          contactPeerId: signal.recipientAccountPeerId,
          localAccountPeerId: signal.senderAccountPeerId,
          localDeviceId: signal.senderDevicePeerId,
          remoteAccountPeerId: signal.recipientAccountPeerId,
          remoteDeviceId: signal.recipientDevicePeerId,
          transportRoute: _routeClass(result.directRoute),
        ),
      );
    }
    if (result.mailboxStored) {
      await coordinator.dispatch(
        CallEvent(
          type: CallEventType.mailboxStored,
          eventId: '${signal.messageId}:mailbox-stored',
          occurredAt: DateTime.fromMillisecondsSinceEpoch(
            signal.createdAtMs,
            isUtc: true,
          ),
          callId: signal.callId,
          contactPeerId: signal.recipientAccountPeerId,
          localAccountPeerId: signal.senderAccountPeerId,
          localDeviceId: signal.senderDevicePeerId,
          remoteAccountPeerId: signal.recipientAccountPeerId,
          remoteDeviceId: signal.recipientDevicePeerId,
          transportRoute: CallRouteClass.ephemeralMailbox,
        ),
      );
    }
    if (result.wakeDispatched) {
      // The relay alerted the callee's device. A headless callee rings
      // without signalling anything until it is answered, so this receipt is
      // the caller's only sign that the far end is being alerted.
      await coordinator.dispatch(
        CallEvent(
          type: CallEventType.wakeRequested,
          eventId: '${signal.messageId}:wake-dispatched',
          occurredAt: DateTime.fromMillisecondsSinceEpoch(
            signal.createdAtMs,
            isUtc: true,
          ),
          callId: signal.callId,
          contactPeerId: signal.recipientAccountPeerId,
          localAccountPeerId: signal.senderAccountPeerId,
          localDeviceId: signal.senderDevicePeerId,
          remoteAccountPeerId: signal.recipientAccountPeerId,
          remoteDeviceId: signal.recipientDevicePeerId,
          transportRoute: CallRouteClass.ephemeralMailbox,
        ),
      );
    }
  }

  Future<CallDirectSendResult> _sendDirect({
    required String recipientDevicePeerId,
    required String envelopeJson,
  }) async {
    try {
      final result = await _directTransport.send(
        recipientDevicePeerId: recipientDevicePeerId,
        envelopeJson: envelopeJson,
      );
      _emitLegResult(_CallSignalingLeg.directSend, result.accepted);
      return result;
    } catch (_) {
      _emitLegResult(_CallSignalingLeg.directSend, false);
      // A failed direct leg cannot erase committed mailbox custody.
      return const CallDirectSendResult(
        outcome: CallDirectTransportOutcome.failed,
        transportAcknowledged: false,
        route: CallDirectRoute.unknown,
      );
    }
  }

  Future<_MailboxLegResult> _storeMailbox({
    required CallSignal signal,
    required String callHandle,
    required ResolvedCallEndpoint endpoint,
    required String envelope,
  }) async {
    try {
      final result = await _mailboxClient.store(
        CallMailboxStoreRequest(
          recipientDevicePeerId: endpoint.devicePeerId,
          callHandle: callHandle,
          messageId: signal.messageId,
          envelopeJson: envelope,
          expiresAtMs: signal.expiresAtMs,
          wakeHandle: endpoint.wakeHandle,
        ),
      );
      final stored =
          result.expiresAtMs > signal.createdAtMs &&
          result.expiresAtMs <= signal.expiresAtMs;
      _emitLegResult(
        _CallSignalingLeg.mailboxStore,
        stored,
        wake: result.wake.name,
      );
      return (
        stored: stored,
        wakeDispatched:
            stored && result.wake == CallMailboxWakeStatus.dispatched,
      );
    } catch (_) {
      _emitLegResult(_CallSignalingLeg.mailboxStore, false);
      return (stored: false, wakeDispatched: false);
    }
  }

  static void _emitLegResult(
    _CallSignalingLeg leg,
    bool result, {
    String? wake,
  }) {
    try {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_SIGNALING_LEG_RESULT',
        details: <String, Object?>{
          'operation': leg.operation,
          'result': result,
          'wake': ?wake,
        },
      );
    } catch (_) {
      // Identifier-free diagnostics cannot change signaling behavior.
    }
  }

  static CallRouteClass? _routeClass(CallDirectRoute route) => switch (route) {
    CallDirectRoute.direct => CallRouteClass.direct,
    CallDirectRoute.circuitRelay => CallRouteClass.circuitRelay,
    CallDirectRoute.unknown => null,
  };
}

typedef _MailboxLegResult = ({bool stored, bool wakeDispatched});
