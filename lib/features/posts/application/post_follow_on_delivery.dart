import 'dart:collection';

import 'package:flutter_app/core/services/p2p_service.dart';

const Duration interactivePostFollowOnBudget = Duration(seconds: 4);
const int defaultPostFollowOnDeliveryConcurrency = 4;

enum PostFollowOnSettlement {
  fullySettled,
  partiallySettled,
  notSettled,
}

class PostFollowOnRecipientResult {
  final String recipientPeerId;
  final String deliveryStatus;
  final String deliveryPath;
  final String? lastError;
  final String attemptedAt;

  const PostFollowOnRecipientResult({
    required this.recipientPeerId,
    required this.deliveryStatus,
    required this.deliveryPath,
    required this.attemptedAt,
    this.lastError,
  });

  bool get isSettled =>
      deliveryStatus == 'delivered' || deliveryStatus == 'inbox';
}

class PostFollowOnDeliveryResult {
  final List<PostFollowOnRecipientResult> recipientResults;
  final PostFollowOnSettlement settlement;

  const PostFollowOnDeliveryResult({
    required this.recipientResults,
    required this.settlement,
  });

  bool get didDeliverAny => settlement != PostFollowOnSettlement.notSettled;
}

Future<PostFollowOnDeliveryResult> fanoutPostFollowOnEnvelope({
  required P2PService p2pService,
  required Iterable<String> recipientPeerIds,
  required String envelope,
  int maxConcurrentRecipients = defaultPostFollowOnDeliveryConcurrency,
  Duration interactiveBudget = interactivePostFollowOnBudget,
  bool fallbackToInboxOnDirectSendError = false,
}) async {
  if (maxConcurrentRecipients < 1) {
    throw ArgumentError.value(
      maxConcurrentRecipients,
      'maxConcurrentRecipients',
      'Must be at least 1.',
    );
  }

  final recipients = recipientPeerIds
      .where((recipientPeerId) => recipientPeerId.isNotEmpty)
      .toList(growable: false);
  final pendingRecipients = Queue<String>.of(recipients);
  final outcomesByRecipient =
      <String, PostFollowOnRecipientResult>{};
  final inFlight = <Future<void>>[];

  while (pendingRecipients.isNotEmpty || inFlight.isNotEmpty) {
    while (pendingRecipients.isNotEmpty &&
        inFlight.length < maxConcurrentRecipients) {
      final recipientPeerId = pendingRecipients.removeFirst();
      late final Future<void> task;
      task =
          _deliverPostFollowOnEnvelope(
            p2pService: p2pService,
            recipientPeerId: recipientPeerId,
            envelope: envelope,
            interactiveBudget: interactiveBudget,
            fallbackToInboxOnDirectSendError: fallbackToInboxOnDirectSendError,
          ).then((outcome) {
            outcomesByRecipient[recipientPeerId] = outcome;
          }).whenComplete(() {
            inFlight.remove(task);
          });
      inFlight.add(task);
    }

      if (inFlight.isEmpty) {
        break;
      }

    await Future.any(inFlight);
  }

  final orderedOutcomes = recipients
      .map((recipientPeerId) => outcomesByRecipient[recipientPeerId])
      .whereType<PostFollowOnRecipientResult>()
      .toList(growable: false);
  return PostFollowOnDeliveryResult(
    recipientResults: orderedOutcomes,
    settlement: _aggregatePostFollowOnResult(orderedOutcomes),
  );
}

Future<PostFollowOnRecipientResult> _deliverPostFollowOnEnvelope({
  required P2PService p2pService,
  required String recipientPeerId,
  required String envelope,
  required Duration interactiveBudget,
  required bool fallbackToInboxOnDirectSendError,
}) async {
  final attemptedAt = DateTime.now().toUtc().toIso8601String();
  try {
    final sendResult = await p2pService.sendMessageWithReply(
      recipientPeerId,
      envelope,
      timeoutMs: interactiveBudget.inMilliseconds,
    );
    if (sendResult.sent) {
      return PostFollowOnRecipientResult(
        recipientPeerId: recipientPeerId,
        deliveryStatus: 'delivered',
        deliveryPath: 'direct',
        attemptedAt: attemptedAt,
      );
    }
  } catch (error) {
    if (!fallbackToInboxOnDirectSendError) {
      rethrow;
    }
    final stored = await p2pService.storeInInbox(recipientPeerId, envelope);
    return PostFollowOnRecipientResult(
      recipientPeerId: recipientPeerId,
      deliveryStatus: stored ? 'inbox' : 'failed',
      deliveryPath: 'inbox',
      attemptedAt: attemptedAt,
      lastError: stored ? null : error.toString(),
    );
  }

  final stored = await p2pService.storeInInbox(recipientPeerId, envelope);
  return PostFollowOnRecipientResult(
    recipientPeerId: recipientPeerId,
    deliveryStatus: stored ? 'inbox' : 'failed',
    deliveryPath: 'inbox',
    attemptedAt: attemptedAt,
    lastError: stored ? null : 'inbox_store_failed',
  );
}

PostFollowOnSettlement _aggregatePostFollowOnResult(
  List<PostFollowOnRecipientResult> outcomes,
) {
  if (outcomes.isEmpty) {
    return PostFollowOnSettlement.notSettled;
  }
  final settledCount = outcomes.where((outcome) => outcome.isSettled).length;
  if (settledCount == 0) {
    return PostFollowOnSettlement.notSettled;
  }
  if (settledCount == outcomes.length) {
    return PostFollowOnSettlement.fullySettled;
  }
  return PostFollowOnSettlement.partiallySettled;
}
