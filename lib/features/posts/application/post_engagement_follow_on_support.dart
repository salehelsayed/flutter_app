import 'dart:collection';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_job.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const String postReactionFollowOnEventType = 'post_reaction';
const String postCommentFollowOnEventType = 'post_comment';
const String postCommentReactionFollowOnEventType = 'post_comment_reaction';
const int defaultPostCommentDeliveryConcurrency = 25;

bool isPostEngagementFollowOnEventType(String eventType) {
  return eventType == postReactionFollowOnEventType ||
      eventType == postCommentFollowOnEventType ||
      eventType == postCommentReactionFollowOnEventType;
}

int postEngagementDeliveryConcurrencyForEventType(String eventType) {
  return switch (eventType) {
    postCommentFollowOnEventType => defaultPostCommentDeliveryConcurrency,
    _ => defaultPostFollowOnDeliveryConcurrency,
  };
}

Future<PostFollowOnDeliveryResult> queueAndSendPostEngagementFollowOn({
  required PostRepository postRepo,
  required P2PService p2pService,
  required String eventId,
  required String eventType,
  required String postId,
  required String? commentId,
  required String senderPeerId,
  required String envelope,
  required String createdAt,
  required Iterable<String> recipientPeerIds,
  int maxConcurrentRecipients = defaultPostFollowOnDeliveryConcurrency,
}) async {
  await queuePostEngagementFollowOn(
    postRepo: postRepo,
    eventId: eventId,
    eventType: eventType,
    postId: postId,
    commentId: commentId,
    senderPeerId: senderPeerId,
    envelope: envelope,
    createdAt: createdAt,
    recipientPeerIds: recipientPeerIds,
  );

  return deliverQueuedPostEngagementFollowOn(
    postRepo: postRepo,
    p2pService: p2pService,
    eventId: eventId,
    envelope: envelope,
    maxConcurrentRecipients: maxConcurrentRecipients,
  );
}

Future<void> queuePostEngagementFollowOn({
  required PostRepository postRepo,
  required String eventId,
  required String eventType,
  required String postId,
  required String? commentId,
  required String senderPeerId,
  required String envelope,
  required String createdAt,
  required Iterable<String> recipientPeerIds,
}) async {
  final recipients = LinkedHashSet<String>.from(
    recipientPeerIds.where((recipientPeerId) => recipientPeerId.isNotEmpty),
  ).toList(growable: false);

  await postRepo.saveFollowOnOutboxEvent(
    PostFollowOnOutboxEvent(
      eventId: eventId,
      eventType: eventType,
      postId: postId,
      commentId: commentId,
      senderPeerId: senderPeerId,
      rawEnvelope: envelope,
      createdAt: createdAt,
    ),
  );

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
  for (final delivery in queuedDeliveries) {
    await postRepo.saveFollowOnOutboxRecipientDelivery(delivery);
  }
}

Future<PostFollowOnDeliveryResult> deliverQueuedPostEngagementFollowOn({
  required PostRepository postRepo,
  required P2PService p2pService,
  required String eventId,
  required String envelope,
  required int maxConcurrentRecipients,
}) async {
  final deliveries = await postRepo.loadFollowOnOutboxRecipientDeliveries(
    eventId,
  );
  return _deliverPostEngagementFollowOnRecipients(
    postRepo: postRepo,
    p2pService: p2pService,
    eventId: eventId,
    envelope: envelope,
    deliveries: deliveries,
    maxConcurrentRecipients: maxConcurrentRecipients,
  );
}

Future<PostFollowOnDeliveryResult> retryPostEngagementFollowOnJob({
  required PostRepository postRepo,
  required P2PService p2pService,
  required PostFollowOnOutboxJob job,
  int? maxConcurrentRecipients,
}) async {
  final resolvedMaxConcurrentRecipients =
      maxConcurrentRecipients ??
      postEngagementDeliveryConcurrencyForEventType(job.event.eventType);
  return _deliverPostEngagementFollowOnRecipients(
    postRepo: postRepo,
    p2pService: p2pService,
    eventId: job.event.eventId,
    envelope: job.event.rawEnvelope,
    deliveries: job.recipientDeliveries,
    maxConcurrentRecipients: resolvedMaxConcurrentRecipients,
  );
}

Future<PostFollowOnDeliveryResult> _deliverPostEngagementFollowOnRecipients({
  required PostRepository postRepo,
  required P2PService p2pService,
  required String eventId,
  required String envelope,
  required List<PostFollowOnOutboxRecipientDelivery> deliveries,
  required int maxConcurrentRecipients,
}) async {
  final unresolvedDeliveries = deliveries
      .where((delivery) => !delivery.isSettled)
      .toList(growable: false);
  if (unresolvedDeliveries.isEmpty) {
    return _loadPersistedPostEngagementFollowOnResult(postRepo, eventId);
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
        PostFollowOnOutboxRecipientDelivery(
          eventId: delivery.eventId,
          recipientPeerId: delivery.recipientPeerId,
          deliveryStatus: outcome.deliveryStatus,
          deliveryPath: outcome.deliveryPath,
          lastError: outcome.lastError,
          lastAttemptAt: outcome.attemptedAt,
          createdAt: delivery.createdAt,
          updatedAt: outcome.attemptedAt,
        ),
      );
    }
  } catch (error) {
    final attemptedAt = DateTime.now().toUtc().toIso8601String();
    for (final delivery in unresolvedDeliveries) {
      await postRepo.saveFollowOnOutboxRecipientDelivery(
        PostFollowOnOutboxRecipientDelivery(
          eventId: delivery.eventId,
          recipientPeerId: delivery.recipientPeerId,
          deliveryStatus: 'failed',
          deliveryPath: 'failed',
          lastError: error.toString(),
          lastAttemptAt: attemptedAt,
          createdAt: delivery.createdAt,
          updatedAt: attemptedAt,
        ),
      );
    }
  }

  return _loadPersistedPostEngagementFollowOnResult(postRepo, eventId);
}

Future<PostFollowOnDeliveryResult> _loadPersistedPostEngagementFollowOnResult(
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
  return PostFollowOnDeliveryResult(
    recipientResults: recipientResults,
    settlement: _aggregatePostEngagementFollowOnSettlement(deliveries),
  );
}

PostFollowOnSettlement _aggregatePostEngagementFollowOnSettlement(
  List<PostFollowOnOutboxRecipientDelivery> deliveries,
) {
  if (deliveries.isEmpty) {
    return PostFollowOnSettlement.notSettled;
  }
  final settledCount = deliveries
      .where((delivery) => delivery.isSettled)
      .length;
  if (settledCount == 0) {
    return PostFollowOnSettlement.notSettled;
  }
  if (settledCount == deliveries.length) {
    return PostFollowOnSettlement.fullySettled;
  }
  return PostFollowOnSettlement.partiallySettled;
}
