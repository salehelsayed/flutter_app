import 'dart:convert';

import 'package:flutter_app/core/services/p2p_service.dart';

enum CallDirectTransportOutcome { acceptedBytes, failed, rejectedOversized }

enum CallDirectRoute { direct, circuitRelay, unknown }

final class CallDirectSendResult {
  const CallDirectSendResult({
    required this.outcome,
    required this.transportAcknowledged,
    required this.route,
  });

  final CallDirectTransportOutcome outcome;

  /// This is only byte acceptance by the authenticated stream. It is never an
  /// application `ringing` transition.
  final bool transportAcknowledged;
  final CallDirectRoute route;

  bool get accepted => outcome == CallDirectTransportOutcome.acceptedBytes;
}

abstract interface class CallDirectTransport {
  /// Attempts one bounded direct/Circuit Relay write.
  ///
  /// Implementations must convert transport exceptions and timeouts to a
  /// non-accepted result. Call orchestration can therefore race this attempt
  /// with durable mailbox custody without an exceptional direct leg skipping
  /// the mailbox outcome.
  Future<CallDirectSendResult> send({
    required String recipientDevicePeerId,
    required String envelopeJson,
  });
}

final class P2PCallTransport implements CallDirectTransport {
  const P2PCallTransport({
    required P2PService p2pService,
    this.timeoutMs = 5000,
  }) : _p2pService = p2pService;

  static const int maxSignalBytes = 96 * 1024;

  final P2PService _p2pService;
  final int timeoutMs;

  @override
  Future<CallDirectSendResult> send({
    required String recipientDevicePeerId,
    required String envelopeJson,
  }) async {
    if (recipientDevicePeerId.trim().isEmpty || timeoutMs <= 0) {
      return const CallDirectSendResult(
        outcome: CallDirectTransportOutcome.failed,
        transportAcknowledged: false,
        route: CallDirectRoute.unknown,
      );
    }
    if (utf8.encode(envelopeJson).length > maxSignalBytes) {
      return const CallDirectSendResult(
        outcome: CallDirectTransportOutcome.rejectedOversized,
        transportAcknowledged: false,
        route: CallDirectRoute.unknown,
      );
    }
    try {
      final result = await _p2pService
          .sendMessageWithReply(
            recipientDevicePeerId,
            envelopeJson,
            timeoutMs: timeoutMs,
          )
          .timeout(Duration(milliseconds: timeoutMs));
      final acknowledged = result.sent && result.acked == true;
      return CallDirectSendResult(
        outcome: acknowledged
            ? CallDirectTransportOutcome.acceptedBytes
            : CallDirectTransportOutcome.failed,
        transportAcknowledged: acknowledged,
        route: _route(result.transport),
      );
    } catch (_) {
      return const CallDirectSendResult(
        outcome: CallDirectTransportOutcome.failed,
        transportAcknowledged: false,
        route: CallDirectRoute.unknown,
      );
    }
  }

  static CallDirectRoute _route(String? transport) {
    final normalized = transport?.toLowerCase() ?? '';
    if (normalized.contains('relay') || normalized.contains('circuit')) {
      return CallDirectRoute.circuitRelay;
    }
    if (normalized.contains('direct')) return CallDirectRoute.direct;
    return CallDirectRoute.unknown;
  }
}
