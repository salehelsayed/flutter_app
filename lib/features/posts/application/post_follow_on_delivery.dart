import 'dart:collection';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_retract_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_view_envelope.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const Duration interactivePostFollowOnBudget = Duration(seconds: 4);
const int defaultPostFollowOnDeliveryConcurrency = 4;

/// Queued follow-ons fan out wider so one slow recipient does not hold the rest.
const int queuedPostFollowOnConcurrency = 25;

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
      if (sendResult.acknowledged) {
        return PostFollowOnRecipientResult(
          recipientPeerId: recipientPeerId,
          deliveryStatus: 'delivered',
          deliveryPath: 'direct',
          attemptedAt: attemptedAt,
        );
      }
      directFailureReason = sendResult.sent
          ? 'direct_send_unacknowledged'
          : 'direct_send_returned_not_sent';
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
    return await _dialDiscoveredPostRecipient(
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

/// Records one outbox event with a pending delivery per recipient, then makes
/// the first delivery attempt. Unsettled recipients stay queued for the
/// follow-on retrier.
Future<PostFollowOnDeliveryResult> queueAndSendPostFollowOn({
  required PostRepository postRepo,
  required P2PService p2pService,
  required String eventId,
  required String eventType,
  required String postId,
  required String senderPeerId,
  required String envelope,
  required String createdAt,
  required List<String> recipientPeerIds,
  int maxConcurrentRecipients = queuedPostFollowOnConcurrency,
}) async {
  final queuedDeliveries = await queuePostFollowOn(
    postRepo: postRepo,
    eventId: eventId,
    eventType: eventType,
    postId: postId,
    senderPeerId: senderPeerId,
    envelope: envelope,
    createdAt: createdAt,
    recipientPeerIds: recipientPeerIds,
  );
  return deliverQueuedPostFollowOn(
    postRepo: postRepo,
    p2pService: p2pService,
    eventId: eventId,
    envelope: envelope,
    deliveries: queuedDeliveries,
    maxConcurrentRecipients: maxConcurrentRecipients,
  );
}

Future<List<PostFollowOnOutboxRecipientDelivery>> queuePostFollowOn({
  required PostRepository postRepo,
  required String eventId,
  required String eventType,
  required String postId,
  required String senderPeerId,
  required String envelope,
  required String createdAt,
  required List<String> recipientPeerIds,
}) async {
  final recipients = LinkedHashSet<String>.from(
    recipientPeerIds.where((recipientPeerId) => recipientPeerId.isNotEmpty),
  ).toList(growable: false);

  final queuedDeliveries = recipients
      .map(
        (recipientPeerId) => PostFollowOnOutboxRecipientDelivery(
          eventId: eventId,
          recipientPeerId: recipientPeerId,
          deliveryStatus: 'pending',
          deliveryPath: 'queued',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      )
      .toList(growable: false);
  await postRepo.saveFollowOnOutboxEventWithRecipients(
    PostFollowOnOutboxEvent(
      eventId: eventId,
      eventType: eventType,
      postId: postId,
      senderPeerId: senderPeerId,
      rawEnvelope: envelope,
      createdAt: createdAt,
    ),
    queuedDeliveries,
  );
  return queuedDeliveries;
}

/// Attempts the unsettled recipients of a queued follow-on and records each
/// outcome, then reports the settlement of every recipient the event has.
Future<PostFollowOnDeliveryResult> deliverQueuedPostFollowOn({
  required PostRepository postRepo,
  required P2PService p2pService,
  required String eventId,
  required String envelope,
  required List<PostFollowOnOutboxRecipientDelivery> deliveries,
  int maxConcurrentRecipients = queuedPostFollowOnConcurrency,
}) async {
  final unresolvedDeliveries = deliveries
      .where((delivery) => !delivery.isSettled)
      .toList(growable: false);
  if (unresolvedDeliveries.isEmpty) {
    return _loadPersistedPostFollowOnResult(postRepo, eventId);
  }

  try {
    final result = await fanoutPostFollowOnEnvelope(
      p2pService: p2pService,
      recipientPeerIds: unresolvedDeliveries.map(
        (delivery) => delivery.recipientPeerId,
      ),
      envelope: envelope,
      maxConcurrentRecipients: maxConcurrentRecipients,
      fallbackToInboxOnDirectSendError: true,
    );
    final outcomesByRecipient = <String, PostFollowOnRecipientResult>{
      for (final outcome in result.recipientResults)
        outcome.recipientPeerId: outcome,
    };
    for (final delivery in unresolvedDeliveries) {
      final outcome = outcomesByRecipient[delivery.recipientPeerId];
      if (outcome == null) {
        continue;
      }
      await postRepo.saveFollowOnOutboxRecipientDelivery(
        delivery.copyWith(
          deliveryStatus: outcome.deliveryStatus,
          deliveryPath: outcome.deliveryPath,
          lastError: outcome.lastError,
          lastAttemptAt: outcome.attemptedAt,
          updatedAt: outcome.attemptedAt,
        ),
      );
    }
  } catch (error) {
    final attemptedAt = DateTime.now().toUtc().toIso8601String();
    for (final delivery in unresolvedDeliveries) {
      await postRepo.saveFollowOnOutboxRecipientDelivery(
        delivery.copyWith(
          deliveryStatus: 'failed',
          deliveryPath: 'failed',
          lastError: error.toString(),
          lastAttemptAt: attemptedAt,
          updatedAt: attemptedAt,
        ),
      );
    }
  }

  return _loadPersistedPostFollowOnResult(postRepo, eventId);
}

Future<PostFollowOnDeliveryResult> _loadPersistedPostFollowOnResult(
  PostRepository postRepo,
  String eventId,
) async {
  final deliveries = await postRepo.loadFollowOnOutboxRecipientDeliveries(
    eventId,
  );
  final recipientResults = deliveries
      .map(
        (delivery) => PostFollowOnRecipientResult(
          recipientPeerId: delivery.recipientPeerId,
          deliveryStatus: delivery.deliveryStatus,
          deliveryPath: delivery.deliveryPath,
          attemptedAt: delivery.lastAttemptAt ?? delivery.updatedAt,
          lastError: delivery.lastError,
        ),
      )
      .toList(growable: false);
  final result = PostFollowOnDeliveryResult(
    recipientResults: recipientResults,
    settlement: _aggregatePostFollowOnResult(recipientResults),
  );
  if (result.settlement == PostFollowOnSettlement.fullySettled) {
    final event = await postRepo.getFollowOnOutboxEvent(eventId);
    if (event?.eventType == PostRetractEnvelope.type ||
        event?.eventType == PostViewEnvelope.type) {
      await postRepo.deleteFollowOnOutboxEvent(eventId);
    }
  }
  return result;
}
