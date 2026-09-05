import 'dart:convert';

import '../../../core/bridge/bridge.dart';
import '../../../core/bridge/p2p_bridge_client.dart';
import 'p2p_call_transport.dart';

/// Direct leg for runtimes without a P2PService (the headless call runs):
/// one bounded `message:send` through the Go bridge, mapped exactly like
/// [P2PCallTransport]. A non-accepted result never throws, so the mailbox
/// leg keeps racing it.
final class BridgeCallDirectTransport implements CallDirectTransport {
  const BridgeCallDirectTransport({
    required Bridge bridge,
    this.timeoutMs = 5000,
  }) : _bridge = bridge;

  final Bridge _bridge;
  final int timeoutMs;

  @override
  Future<CallDirectSendResult> send({
    required String recipientDevicePeerId,
    required String envelopeJson,
  }) async {
    if (recipientDevicePeerId.trim().isEmpty || timeoutMs <= 0) {
      return _failed;
    }
    if (utf8.encode(envelopeJson).length > P2PCallTransport.maxSignalBytes) {
      return const CallDirectSendResult(
        outcome: CallDirectTransportOutcome.rejectedOversized,
        transportAcknowledged: false,
        route: CallDirectRoute.unknown,
      );
    }
    try {
      final response = await callP2PMessageSend(
        _bridge,
        peerId: recipientDevicePeerId,
        message: envelopeJson,
        timeoutMs: timeoutMs,
      );
      final acknowledged =
          response['ok'] == true &&
          response['sent'] != false &&
          response['acked'] == true;
      if (!acknowledged) return _failed;
      return CallDirectSendResult(
        outcome: CallDirectTransportOutcome.acceptedBytes,
        transportAcknowledged: true,
        route: _route(response['transport']?.toString()),
      );
    } catch (_) {
      return _failed;
    }
  }

  static const CallDirectSendResult _failed = CallDirectSendResult(
    outcome: CallDirectTransportOutcome.failed,
    transportAcknowledged: false,
    route: CallDirectRoute.unknown,
  );

  static CallDirectRoute _route(String? transport) {
    final normalized = transport?.toLowerCase() ?? '';
    if (normalized.contains('relay') || normalized.contains('circuit')) {
      return CallDirectRoute.circuitRelay;
    }
    if (normalized.contains('direct')) return CallDirectRoute.direct;
    return CallDirectRoute.unknown;
  }
}
