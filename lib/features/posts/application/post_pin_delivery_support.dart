import 'dart:collection';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_job.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const Duration interactivePostPinBudget = Duration(seconds: 4);
// Pins use a higher fanout cap than the prior serialized path so updates and
// removals do not stack behind one slow recipient.
const int defaultPostPinDeliveryConcurrency = 25;
const String postPinUpdateFollowOnEventType = 'post_pin_update';
const String postPinRemoveFollowOnEventType = 'post_pin_remove';

Future<List<String>> loadPostPinRecipients({
  required PostRepository postRepo,
  required String postId,
}) async {
  final deliveries = await postRepo.getRecipientDeliveries(postId);
  final recipients = <String>{
    for (final delivery in deliveries)
      if (delivery.recipientPeerId.isNotEmpty) delivery.recipientPeerId,
  };
  return recipients.toList(growable: false);
}

Future<List<PostMediaAttachmentModel>> loadRenderablePostPinMedia({
  required PostRepository postRepo,
  required PostModel post,
}) async {
  final media = post.media.isNotEmpty
      ? post.media
      : await postRepo.loadPostMediaAttachments(post.id);
  if (media.isEmpty) {
    return const <PostMediaAttachmentModel>[];
  }
  return media
      .map((attachment) => attachment.copyWith(postId: post.id))
      .toList(growable: false);
}

Future<PostFollowOnDeliveryResult> sendPostPinEnvelope({
  required P2PService p2pService,
  required List<String> recipientPeerIds,
  required String envelope,
  int maxConcurrentRecipients = defaultPostPinDeliveryConcurrency,
}) async {
  return fanoutPostFollowOnEnvelope(
    p2pService: p2pService,
    recipientPeerIds: recipientPeerIds,
    envelope: envelope,
    maxConcurrentRecipients: maxConcurrentRecipients,
    interactiveBudget: interactivePostPinBudget,
  );
}

bool isPostPinFollowOnEventType(String eventType) {
  return eventType == postPinUpdateFollowOnEventType ||
      eventType == postPinRemoveFollowOnEventType;
}

Future<PostFollowOnDeliveryResult> queueAndSendPostPinFollowOn({
  required PostRepository postRepo,
  required P2PService p2pService,
  required String eventId,
  required String eventType,
  required String postId,
  required String senderPeerId,
  required String envelope,
  required String createdAt,
  required List<String> recipientPeerIds,
  int maxConcurrentRecipients = defaultPostPinDeliveryConcurrency,
}) async {
  final recipients = LinkedHashSet<String>.from(
    recipientPeerIds.where((recipientPeerId) => recipientPeerId.isNotEmpty),
  ).toList(growable: false);

  await postRepo.saveFollowOnOutboxEvent(
    PostFollowOnOutboxEvent(
      eventId: eventId,
      eventType: eventType,
      postId: postId,
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

  return _deliverPostPinFollowOnRecipients(
    postRepo: postRepo,
    p2pService: p2pService,
    eventId: eventId,
    envelope: envelope,
    deliveries: queuedDeliveries,
    maxConcurrentRecipients: maxConcurrentRecipients,
  );
}

Future<PostFollowOnDeliveryResult> retryPostPinFollowOnJob({
  required PostRepository postRepo,
  required P2PService p2pService,
  required PostFollowOnOutboxJob job,
  int maxConcurrentRecipients = defaultPostPinDeliveryConcurrency,
}) async {
  return _deliverPostPinFollowOnRecipients(
    postRepo: postRepo,
    p2pService: p2pService,
    eventId: job.event.eventId,
    envelope: job.event.rawEnvelope,
    deliveries: job.recipientDeliveries,
    maxConcurrentRecipients: maxConcurrentRecipients,
  );
}

Future<PostFollowOnDeliveryResult> _deliverPostPinFollowOnRecipients({
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
    return _loadPersistedPostPinFollowOnResult(postRepo, eventId);
  }

  try {
    final result = await fanoutPostFollowOnEnvelope(
      p2pService: p2pService,
      recipientPeerIds: unresolvedDeliveries.map(
        (delivery) => delivery.recipientPeerId,
      ),
      envelope: envelope,
      maxConcurrentRecipients: maxConcurrentRecipients,
      interactiveBudget: interactivePostPinBudget,
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

  return _loadPersistedPostPinFollowOnResult(postRepo, eventId);
}

Future<PostFollowOnDeliveryResult> _loadPersistedPostPinFollowOnResult(
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
    settlement: _aggregatePostPinFollowOnSettlement(deliveries),
  );
}

PostFollowOnSettlement _aggregatePostPinFollowOnSettlement(
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
