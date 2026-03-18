import 'dart:collection';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';

const Duration interactivePostFollowOnBudget = Duration(seconds: 4);
const int defaultPostFollowOnDeliveryConcurrency = 4;

enum PostFollowOnSettlement { fullySettled, partiallySettled, notSettled }

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
  final outcomesByRecipient = <String, PostFollowOnRecipientResult>{};
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
                fallbackToInboxOnDirectSendError:
                    fallbackToInboxOnDirectSendError,
              )
              .then((outcome) {
                outcomesByRecipient[recipientPeerId] = outcome;
              })
              .whenComplete(() {
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
  var directFailureReason = 'direct_send_failed';
  try {
    final directReady = await ensurePostRecipientDirectConnection(
      p2pService: p2pService,
      recipientPeerId: recipientPeerId,
      interactiveBudget: interactiveBudget,
    );
    if (directReady) {
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
      directFailureReason = 'direct_send_returned_not_sent';
    } else {
      directFailureReason = 'direct_connect_unavailable';
    }
  } catch (error) {
    if (!fallbackToInboxOnDirectSendError) {
      rethrow;
    }
    directFailureReason = error.toString();
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_DIRECT_SEND_FALLBACK_TO_INBOX',
      details: {
        'recipientPeerId': recipientPeerId,
        'reason': directFailureReason,
      },
    );
    final stored = await p2pService.storeInInbox(recipientPeerId, envelope);
    return PostFollowOnRecipientResult(
      recipientPeerId: recipientPeerId,
      deliveryStatus: stored ? 'inbox' : 'failed',
      deliveryPath: 'inbox',
      attemptedAt: attemptedAt,
      lastError: stored ? null : error.toString(),
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'POST_DIRECT_SEND_FALLBACK_TO_INBOX',
    details: {
      'recipientPeerId': recipientPeerId,
      'reason': directFailureReason,
    },
  );
  final stored = await p2pService.storeInInbox(recipientPeerId, envelope);
  return PostFollowOnRecipientResult(
    recipientPeerId: recipientPeerId,
    deliveryStatus: stored ? 'inbox' : 'failed',
    deliveryPath: 'inbox',
    attemptedAt: attemptedAt,
    lastError: stored ? null : directFailureReason,
  );
}

Future<bool> ensurePostRecipientDirectConnection({
  required P2PService p2pService,
  required String recipientPeerId,
  required Duration interactiveBudget,
}) async {
  final timeoutMs = interactiveBudget.inMilliseconds;
  if (p2pService.isConnectedToPeer(recipientPeerId)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_DIRECT_CONNECT_SKIP_CONNECTED',
      details: {'recipientPeerId': recipientPeerId},
    );
    return true;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'POST_DIRECT_CONNECT_BEGIN',
    details: {'recipientPeerId': recipientPeerId, 'timeoutMs': timeoutMs},
  );

  try {
    final discoveredPeer = await p2pService.discoverPeer(
      recipientPeerId,
      timeoutMs: timeoutMs,
    );
    if (discoveredPeer == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_DIRECT_CONNECT_DISCOVER_NOT_FOUND',
        details: {'recipientPeerId': recipientPeerId},
      );
      return false;
    }
    return _dialDiscoveredPostRecipient(
      p2pService: p2pService,
      recipientPeerId: recipientPeerId,
      discoveredPeer: discoveredPeer,
      timeoutMs: timeoutMs,
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_DIRECT_CONNECT_EXCEPTION',
      details: {'recipientPeerId': recipientPeerId, 'error': error.toString()},
    );
    return false;
  }
}

Future<bool> _dialDiscoveredPostRecipient({
  required P2PService p2pService,
  required String recipientPeerId,
  required DiscoveredPeer discoveredPeer,
  required int timeoutMs,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_DIRECT_CONNECT_DISCOVER_SUCCESS',
    details: {
      'recipientPeerId': recipientPeerId,
      'addressCount': discoveredPeer.addresses.length,
    },
  );
  final dialed = await p2pService.dialPeer(
    recipientPeerId,
    addresses: discoveredPeer.addresses,
    timeoutMs: timeoutMs,
  );
  emitFlowEvent(
    layer: 'FL',
    event: dialed
        ? 'POST_DIRECT_CONNECT_DIAL_SUCCESS'
        : 'POST_DIRECT_CONNECT_DIAL_FAILED',
    details: {
      'recipientPeerId': recipientPeerId,
      'addressCount': discoveredPeer.addresses.length,
      'timeoutMs': timeoutMs,
    },
  );
  return dialed;
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
