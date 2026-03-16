import 'dart:async';

import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../../../../shared/fakes/fake_p2p_network.dart';
import '../../../../shared/fakes/fake_p2p_service_integration.dart';

Future<void> drainPostPinDeliveryMicrotasks([int turns = 3]) async {
  for (var index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class ControlledPostPinDeliveryP2PService extends FakeP2PService {
  final Map<String, PostPinDeliveryPeerPolicy> policies;
  final List<String> sendStartOrder = <String>[];
  final List<String> inboxAttempts = <String>[];

  int _inFlightSends = 0;
  int maxInFlightSends = 0;

  ControlledPostPinDeliveryP2PService({
    required super.peerId,
    required super.network,
    this.policies = const <String, PostPinDeliveryPeerPolicy>{},
  });

  Future<void> waitForSendCount(
    int count, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (sendStartOrder.length < count) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'Timed out waiting for $count sends; observed ${sendStartOrder.length}.',
        );
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    final policy = policies[targetPeerId] ?? const PostPinDeliveryPeerPolicy();
    sendStartOrder.add(targetPeerId);
    _inFlightSends++;
    if (_inFlightSends > maxInFlightSends) {
      maxInFlightSends = _inFlightSends;
    }

    try {
      await policy.onSendStart?.call(targetPeerId);
      final gate = policy.sendGate;
      if (gate != null) {
        await gate.future;
      }
      return SendMessageResult(
        sent: policy.sendResult ?? true,
        reply: (policy.sendResult ?? true) ? 'received' : null,
      );
    } finally {
      _inFlightSends--;
    }
  }

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async {
    inboxAttempts.add(toPeerId);
    return (policies[toPeerId] ?? const PostPinDeliveryPeerPolicy())
            .storeInInboxResult ??
        true;
  }
}

class PostPinDeliveryPeerPolicy {
  final Completer<void>? sendGate;
  final bool? sendResult;
  final bool? storeInInboxResult;
  final FutureOr<void> Function(String targetPeerId)? onSendStart;

  const PostPinDeliveryPeerPolicy({
    this.sendGate,
    this.sendResult,
    this.storeInInboxResult,
    this.onSendStart,
  });
}
