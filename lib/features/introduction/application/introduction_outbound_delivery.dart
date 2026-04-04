import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_outbox_delivery.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

Future<void> deliverIntroductionPayloadReliably({
  required IntroductionRepository introRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required String senderPeerId,
  required String targetPeerId,
  required String? targetMlKemPublicKey,
  required IntroductionPayload payload,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  final rawEnvelope = await _buildRawEnvelope(
    bridge: bridge,
    senderPeerId: senderPeerId,
    targetMlKemPublicKey: targetMlKemPublicKey,
    payload: payload,
  );
  final normalizedEnvelope = IntroductionPayload.ensureEnvelopeMessageId(
    rawEnvelope,
    payload.introductionId,
  );

  final deliveryId = _uuid.v4();
  final staged = IntroductionOutboxDelivery(
    deliveryId: deliveryId,
    introductionId: payload.introductionId,
    action: payload.action,
    targetPeerId: targetPeerId,
    senderPeerId: senderPeerId,
    rawEnvelope: normalizedEnvelope,
    deliveryStatus: IntroductionOutboxDeliveryStatus.sending,
    deliveryPath: IntroductionOutboxDeliveryPath.pending,
    createdAt: now,
    updatedAt: now,
  );
  await introRepo.saveOutboxDelivery(staged);

  final result = await _deliverEnvelope(
    p2pService: p2pService,
    senderPeerId: senderPeerId,
    targetPeerId: targetPeerId,
    rawEnvelope: normalizedEnvelope,
  );

  final updatedAt = DateTime.now().toUtc().toIso8601String();
  switch (result.state) {
    case _IntroductionDeliveryState.delivered:
      final deliveredRow = staged.copyWith(
        deliveryStatus: IntroductionOutboxDeliveryStatus.delivered,
        deliveryPath: result.via,
        lastError: null,
        updatedAt: updatedAt,
      );
      await introRepo.saveOutboxDelivery(deliveredRow);
      await introRepo.deleteOutboxDelivery(deliveryId);
      return;
    case _IntroductionDeliveryState.sent:
      await introRepo.saveOutboxDelivery(
        staged.copyWith(
          deliveryStatus: IntroductionOutboxDeliveryStatus.sent,
          deliveryPath: result.via,
          lastError: null,
          updatedAt: updatedAt,
        ),
      );
      return;
    case _IntroductionDeliveryState.failed:
      await introRepo.saveOutboxDelivery(
        staged.copyWith(
          deliveryStatus: IntroductionOutboxDeliveryStatus.failed,
          deliveryPath: result.via ?? IntroductionOutboxDeliveryPath.pending,
          lastError: result.reason ?? 'send_failed',
          updatedAt: updatedAt,
        ),
      );
      return;
  }
}

Future<int> retryPendingIntroductionDeliveries({
  required IntroductionRepository introRepo,
  required P2PService p2pService,
}) async {
  final deliveries = await introRepo.loadRetryableOutboxDeliveries();
  if (deliveries.isEmpty) {
    return 0;
  }

  var deliveredCount = 0;
  for (final delivery in deliveries) {
    final normalizedEnvelope = IntroductionPayload.ensureEnvelopeMessageId(
      delivery.rawEnvelope,
      delivery.introductionId,
    );
    if (delivery.deliveryStatus == IntroductionOutboxDeliveryStatus.delivered &&
        delivery.deliveryPath == IntroductionOutboxDeliveryPath.inbox) {
      await introRepo.deleteOutboxDelivery(delivery.deliveryId);
      deliveredCount++;
      continue;
    }

    try {
      final stored = await p2pService.storeInInbox(
        delivery.targetPeerId,
        normalizedEnvelope,
      );
      if (stored) {
        await introRepo.saveOutboxDelivery(
          delivery.copyWith(
            rawEnvelope: normalizedEnvelope,
            deliveryStatus: IntroductionOutboxDeliveryStatus.delivered,
            deliveryPath: IntroductionOutboxDeliveryPath.inbox,
            lastError: null,
            updatedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        await introRepo.deleteOutboxDelivery(delivery.deliveryId);
        deliveredCount++;
        continue;
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'INTRO_OUTBOX_RETRY_ERROR',
        details: {
          'deliveryId': delivery.deliveryId,
          'targetPeerId': delivery.targetPeerId,
          'error': e.toString(),
        },
      );
    }

    await introRepo.saveOutboxDelivery(
      delivery.copyWith(
        rawEnvelope: normalizedEnvelope,
        deliveryStatus: IntroductionOutboxDeliveryStatus.failed,
        deliveryPath: delivery.deliveryPath,
        lastError: 'inbox_retry_failed',
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  return deliveredCount;
}

Future<String> _buildRawEnvelope({
  required Bridge bridge,
  required String senderPeerId,
  required String? targetMlKemPublicKey,
  required IntroductionPayload payload,
}) async {
  if (targetMlKemPublicKey != null) {
    try {
      final encrypted = await callEncryptMessage(
        bridge: bridge,
        recipientMlKemPublicKey: targetMlKemPublicKey,
        plaintext: payload.toInnerJson(),
      );
      if (encrypted['ok'] == true) {
        return IntroductionPayload.buildEncryptedEnvelope(
          introductionId: payload.introductionId,
          senderPeerId: senderPeerId,
          kem: encrypted['kem'] as String,
          ciphertext: encrypted['ciphertext'] as String,
          nonce: encrypted['nonce'] as String,
        );
      }
    } catch (_) {}
  }

  return payload.toJson();
}

Future<_DeliveryAttemptResult> _deliverEnvelope({
  required P2PService p2pService,
  required String senderPeerId,
  required String targetPeerId,
  required String rawEnvelope,
}) async {
  final alreadyConnected =
      p2pService.isConnectedToPeer(targetPeerId) ||
      p2pService.currentState.connections.any((c) => c.peerId == targetPeerId);

  if (alreadyConnected) {
    try {
      final sendResult = await p2pService.sendMessageWithReply(
        targetPeerId,
        rawEnvelope,
        timeoutMs: interactiveDirectBudget.inMilliseconds,
      );
      if (sendResult.sent) {
        return _DeliveryAttemptResult(
          state: sendResult.acknowledged
              ? _IntroductionDeliveryState.delivered
              : _IntroductionDeliveryState.sent,
          via: _resolveGoSendTransport(
            p2pService,
            targetPeerId,
            sendResult,
            preserveLocalPeerLabel: true,
          ),
        );
      }
    } catch (_) {}
  }

  final raceResult = await _runInteractiveRace(
    p2pService: p2pService,
    senderPeerId: senderPeerId,
    targetPeerId: targetPeerId,
    rawEnvelope: rawEnvelope,
  );
  if (raceResult.success) {
    return _DeliveryAttemptResult(
      state: raceResult.acknowledged
          ? _IntroductionDeliveryState.delivered
          : _IntroductionDeliveryState.sent,
      via: raceResult.via,
    );
  }

  var failureReason = raceResult.reason ?? 'send_failed';
  if (raceResult.relayProbeEligible) {
    final relayProbeResult = await _tryRelayProbeSend(
      p2pService,
      targetPeerId,
      rawEnvelope,
      failureReason: failureReason,
    );
    if (relayProbeResult.success) {
      return _DeliveryAttemptResult(
        state: relayProbeResult.acknowledged
            ? _IntroductionDeliveryState.delivered
            : _IntroductionDeliveryState.sent,
        via: relayProbeResult.via,
      );
    }
    failureReason = relayProbeResult.reason ?? failureReason;
  }

  try {
    final stored = await p2pService.storeInInbox(targetPeerId, rawEnvelope);
    if (stored) {
      return const _DeliveryAttemptResult(
        state: _IntroductionDeliveryState.delivered,
        via: IntroductionOutboxDeliveryPath.inbox,
      );
    }
  } catch (_) {}

  return _DeliveryAttemptResult(
    state: _IntroductionDeliveryState.failed,
    via: IntroductionOutboxDeliveryPath.pending,
    reason: failureReason,
  );
}

Future<_RaceResult> _runInteractiveRace({
  required P2PService p2pService,
  required String senderPeerId,
  required String targetPeerId,
  required String rawEnvelope,
}) async {
  final raceFutures = <Future<_RaceResult>>[];
  if (p2pService.isLocalPeer(targetPeerId)) {
    raceFutures.add(
      _tryLocalSend(
        p2pService,
        targetPeerId,
        rawEnvelope,
        senderPeerId,
        timeoutMs: interactiveLocalBudget.inMilliseconds,
      ),
    );
  }
  raceFutures.add(
    _tryDirectSend(p2pService, targetPeerId, rawEnvelope).timeout(
      interactiveDirectBudget,
      onTimeout: () => _RaceResult.failed('direct_timeout'),
    ),
  );

  final completer = Completer<_RaceResult>();
  var pendingCount = raceFutures.length;
  final failures = <_RaceResult>[];

  for (final future in raceFutures) {
    future
        .then((result) {
          if (result.success && !completer.isCompleted) {
            completer.complete(result);
          } else {
            failures.add(result);
            pendingCount--;
            if (pendingCount <= 0 && !completer.isCompleted) {
              completer.complete(_mergeFailures(failures));
            }
          }
        })
        .catchError((Object error) {
          failures.add(_RaceResult.failed(error.toString()));
          pendingCount--;
          if (pendingCount <= 0 && !completer.isCompleted) {
            completer.complete(_mergeFailures(failures));
          }
        });
  }

  return completer.future;
}

_RaceResult _mergeFailures(List<_RaceResult> failures) {
  var failureReason = failures.isNotEmpty
      ? failures.first.reason ?? 'unknown'
      : 'unknown';
  var relayProbeEligible = false;
  for (final failure in failures) {
    if (failure.relayProbeEligible) {
      failureReason = failure.reason ?? failureReason;
      relayProbeEligible = true;
      break;
    }
  }
  return _RaceResult.failed(
    failureReason,
    relayProbeEligible: relayProbeEligible,
  );
}

String _resolveGoSendTransport(
  P2PService p2pService,
  String peerId,
  SendMessageResult sendResult, {
  bool preserveLocalPeerLabel = false,
}) {
  if (preserveLocalPeerLabel && p2pService.isLocalPeer(peerId)) {
    return IntroductionOutboxDeliveryPath.local;
  }

  final actualTransport = sendResult.transport;
  if (actualTransport != null && actualTransport.isNotEmpty) {
    return actualTransport;
  }

  return _inferTransportForConnectedPeer(p2pService, peerId);
}

String _inferTransportForConnectedPeer(P2PService p2pService, String peerId) {
  if (p2pService.isLocalPeer(peerId)) {
    return IntroductionOutboxDeliveryPath.local;
  }
  final hasRelayConnection = p2pService.currentState.connections.any(
    (connection) =>
        connection.peerId == peerId &&
        connection.multiaddrs.any(
          (multiaddr) => multiaddr.contains('/p2p-circuit'),
        ),
  );
  return hasRelayConnection
      ? IntroductionOutboxDeliveryPath.relay
      : IntroductionOutboxDeliveryPath.direct;
}

Future<_RaceResult> _tryLocalSend(
  P2PService p2pService,
  String targetPeerId,
  String rawEnvelope,
  String senderPeerId, {
  required int timeoutMs,
}) async {
  final sent = await p2pService.sendLocalMessage(
    targetPeerId,
    rawEnvelope,
    senderPeerId,
    timeoutMs: timeoutMs,
  );
  if (sent) {
    return const _RaceResult.succeeded(
      via: IntroductionOutboxDeliveryPath.local,
      acknowledged: true,
    );
  }
  return const _RaceResult.failed('local_send_failed');
}

Future<_RaceResult> _tryDirectSend(
  P2PService p2pService,
  String targetPeerId,
  String rawEnvelope,
) async {
  final peer = await p2pService.discoverPeer(
    targetPeerId,
    timeoutMs: interactiveDirectBudget.inMilliseconds,
  );
  if (peer == null) {
    return const _RaceResult.failed('peer_not_found', relayProbeEligible: true);
  }

  final dialed = await p2pService.dialPeer(
    targetPeerId,
    addresses: peer.addresses,
    timeoutMs: interactiveDirectBudget.inMilliseconds,
  );
  if (!dialed) {
    return const _RaceResult.failed('dial_failed', relayProbeEligible: true);
  }

  final sendResult = await p2pService.sendMessageWithReply(
    targetPeerId,
    rawEnvelope,
    timeoutMs: interactiveDirectBudget.inMilliseconds,
  );
  if (!sendResult.sent) {
    return const _RaceResult.failed('send_failed');
  }

  return _RaceResult.succeeded(
    via: _resolveGoSendTransport(p2pService, targetPeerId, sendResult),
    acknowledged: sendResult.acknowledged,
  );
}

Future<_RaceResult> _tryRelayProbeSend(
  P2PService p2pService,
  String targetPeerId,
  String rawEnvelope, {
  required String failureReason,
}) async {
  RelayProbeResult probeResult;
  try {
    probeResult = await p2pService.probeRelay(targetPeerId);
  } catch (_) {
    return _RaceResult.failed(failureReason);
  }

  switch (probeResult) {
    case RelayProbeResult.connected:
      try {
        await p2pService.dialPeer(
          targetPeerId,
          timeoutMs: interactiveDirectBudget.inMilliseconds,
        );
      } catch (_) {}
      for (var attempt = 1; attempt <= relayProbeSendAttempts; attempt++) {
        try {
          final sendResult = await p2pService.sendMessageWithReply(
            targetPeerId,
            rawEnvelope,
            timeoutMs: interactiveDirectBudget.inMilliseconds,
          );
          if (sendResult.sent) {
            return _RaceResult.succeeded(
              via: _resolveGoSendTransport(
                p2pService,
                targetPeerId,
                sendResult,
              ),
              acknowledged: sendResult.acknowledged,
            );
          }
        } catch (_) {}
        if (attempt < relayProbeSendAttempts) {
          await Future<void>.delayed(relayProbeRetryBackoff);
        }
      }
      return const _RaceResult.failed('send_failed');
    case RelayProbeResult.noReservation:
      return const _RaceResult.failed('peer_not_found');
    case RelayProbeResult.error:
      return _RaceResult.failed(failureReason);
  }
}

enum _IntroductionDeliveryState { delivered, sent, failed }

class _DeliveryAttemptResult {
  final _IntroductionDeliveryState state;
  final String? via;
  final String? reason;

  const _DeliveryAttemptResult({required this.state, this.via, this.reason});
}

class _RaceResult {
  final bool success;
  final bool acknowledged;
  final String? via;
  final String? reason;
  final bool relayProbeEligible;

  const _RaceResult._({
    required this.success,
    this.acknowledged = false,
    this.via,
    this.reason,
    this.relayProbeEligible = false,
  });

  const _RaceResult.succeeded({required String via, bool acknowledged = false})
    : this._(success: true, acknowledged: acknowledged, via: via);

  const _RaceResult.failed(String reason, {bool relayProbeEligible = false})
    : this._(
        success: false,
        reason: reason,
        relayProbeEligible: relayProbeEligible,
      );
}
