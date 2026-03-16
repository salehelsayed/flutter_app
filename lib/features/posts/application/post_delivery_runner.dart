import 'dart:async';
import 'dart:collection';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const Duration _interactivePostBudget = Duration(seconds: 4);
const int defaultPostDeliveryConcurrency = 4;

enum SendPostResult {
  success,
  partialSuccess,
  nodeNotRunning,
  invalidPost,
  noEligibleRecipients,
  sendFailed,
}

class CreatedLocalPost {
  final PostModel post;
  final List<CreatedLocalPostRecipient> resolvedRecipients;
  final List<PostMediaDraft> mediaDrafts;
  final List<String> allRecipientPeerIds;

  const CreatedLocalPost({
    required this.post,
    required this.resolvedRecipients,
    this.mediaDrafts = const <PostMediaDraft>[],
    this.allRecipientPeerIds = const <String>[],
  });

  List<String> get recipientPeerIds =>
      allRecipientPeerIds.isNotEmpty
      ? allRecipientPeerIds
      : resolvedRecipients
            .map((recipient) => recipient.contact.peerId)
            .toList(growable: false);

  bool get hasPendingMediaUpload => mediaDrafts.isNotEmpty;

  CreatedLocalPost copyWith({
    PostModel? post,
    List<CreatedLocalPostRecipient>? resolvedRecipients,
    List<PostMediaDraft>? mediaDrafts,
    List<String>? allRecipientPeerIds,
  }) {
    return CreatedLocalPost(
      post: post ?? this.post,
      resolvedRecipients: resolvedRecipients ?? this.resolvedRecipients,
      mediaDrafts: mediaDrafts ?? this.mediaDrafts,
      allRecipientPeerIds: allRecipientPeerIds ?? this.allRecipientPeerIds,
    );
  }
}

class CreatedLocalPostRecipient {
  final ContactModel contact;
  final int? nearbyDistanceM;

  const CreatedLocalPostRecipient({
    required this.contact,
    this.nearbyDistanceM,
  });
}

class PostDeliveryRunner {
  final P2PService p2pService;
  final PostRepository postRepo;
  final Bridge? bridge;
  final int maxConcurrentRecipients;

  PostDeliveryRunner({
    required this.p2pService,
    required this.postRepo,
    this.bridge,
    int maxConcurrentRecipients = defaultPostDeliveryConcurrency,
  }) : maxConcurrentRecipients = maxConcurrentRecipients {
    if (maxConcurrentRecipients < 1) {
      throw ArgumentError.value(
        maxConcurrentRecipients,
        'maxConcurrentRecipients',
        'Must be at least 1.',
      );
    }
  }

  Future<(SendPostResult, PostModel)> execute(CreatedLocalPost created) async {
    _PostDeliveryProgress? progress;

    try {
      progress = _PostDeliveryProgress(
        latestPost: created.post,
        deliveriesByRecipient: await _loadExistingDeliveries(
          created.post.id,
          postRepo,
        ),
      );
      final recipientPeerIds = created.recipientPeerIds;
      final pendingRecipients = Queue<CreatedLocalPostRecipient>.of(
        created.resolvedRecipients,
      );
      final inFlight = <Future<void>>[];
      AsyncError? fatalError;
      final completionQueue = _SerializedPostCompletionQueue(
        onError: (error, stackTrace) {
          fatalError ??= AsyncError(error, stackTrace);
        },
      );

      Future<void> runRecipient(CreatedLocalPostRecipient recipient) async {
        try {
          final attemptedAt = DateTime.now().toUtc().toIso8601String();
          final wireEnvelope = await _buildWireEnvelope(
            post: created.post,
            bridge: bridge,
            recipient: recipient.contact,
            recipientPeerIds: recipientPeerIds,
            nearbyDistanceM: recipient.nearbyDistanceM,
          );
          final delivery = await _deliverToRecipient(
            p2pService: p2pService,
            recipientPeerId: recipient.contact.peerId,
            wireEnvelope: wireEnvelope,
          );

          if (fatalError != null) {
            return;
          }

          completionQueue.enqueue(() {
            if (fatalError != null) {
              return Future<void>.value();
            }
            return progress!.applyRecipientCompletion(
              postRepo: postRepo,
              recipientPeerId: recipient.contact.peerId,
              attemptedAt: attemptedAt,
              delivery: delivery,
            );
          });
        } catch (error, stackTrace) {
          fatalError ??= AsyncError(error, stackTrace);
        }
      }

      while (pendingRecipients.isNotEmpty || inFlight.isNotEmpty) {
        while (fatalError == null &&
            pendingRecipients.isNotEmpty &&
            inFlight.length < maxConcurrentRecipients) {
          final recipient = pendingRecipients.removeFirst();
          late final Future<void> task;
          task = runRecipient(recipient).whenComplete(() {
            inFlight.remove(task);
          });
          inFlight.add(task);
        }

        if (inFlight.isEmpty) {
          break;
        }

        await Future.any(inFlight);
      }

      await completionQueue.flush();
      final uncaughtError = fatalError;
      if (uncaughtError != null) {
        Error.throwWithStackTrace(
          uncaughtError.error,
          uncaughtError.stackTrace,
        );
      }
    } catch (error) {
      return _persistTerminalFailure(
        created.post.id,
        progress?.latestPost ?? created.post,
        error,
        postRepo,
      );
    }

    return (_resultForAggregate(progress.aggregate), progress.latestPost);
  }
}

Future<(SendPostResult, PostModel)> _persistTerminalFailure(
  String postId,
  PostModel post,
  Object error,
  PostRepository postRepo,
) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_DELIVERY_RUNNER_ERROR',
    details: {'postId': postId, 'error': error.toString()},
  );

  final failedPost = post.copyWith(deliveryStatus: 'failed');
  try {
    await postRepo.savePost(failedPost);
  } catch (persistError) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_DELIVERY_RUNNER_PERSIST_FAILURE_ERROR',
      details: {'postId': postId, 'error': persistError.toString()},
    );
  }
  return (SendPostResult.sendFailed, failedPost);
}

Future<Map<String, PostRecipientDelivery>> _loadExistingDeliveries(
  String postId,
  PostRepository postRepo,
) async {
  final deliveries = await postRepo.getRecipientDeliveries(postId);
  return <String, PostRecipientDelivery>{
    for (final delivery in deliveries) delivery.recipientPeerId: delivery,
  };
}

PostDeliveryAggregate aggregatePostDeliveryStatusFromDeliveries(
  Iterable<PostRecipientDelivery> deliveries,
) {
  var successCount = 0;
  var failureCount = 0;
  var pendingCount = 0;

  for (final delivery in deliveries) {
    if (isSuccessfulRecipientDeliveryStatus(delivery.deliveryStatus)) {
      successCount++;
      continue;
    }
    if (delivery.deliveryStatus == 'failed') {
      failureCount++;
      continue;
    }
    pendingCount++;
  }

  if (successCount == 0 && failureCount == 0) {
    return const PostDeliveryAggregate(deliveryStatus: 'sending');
  }
  if (pendingCount > 0) {
    return const PostDeliveryAggregate(deliveryStatus: 'sending');
  }

  return switch ((successCount, failureCount)) {
    (> 0, 0) => const PostDeliveryAggregate(deliveryStatus: 'sent'),
    (> 0, > 0) => const PostDeliveryAggregate(deliveryStatus: 'partial'),
    _ => const PostDeliveryAggregate(deliveryStatus: 'failed'),
  };
}

bool isSuccessfulRecipientDeliveryStatus(String deliveryStatus) {
  return deliveryStatus == 'delivered' || deliveryStatus == 'inbox';
}

SendPostResult _resultForAggregate(PostDeliveryAggregate aggregate) {
  return switch (aggregate.deliveryStatus) {
    'sent' => SendPostResult.success,
    'partial' => SendPostResult.partialSuccess,
    _ => SendPostResult.sendFailed,
  };
}

Future<String> _buildWireEnvelope({
  required PostModel post,
  required ContactModel recipient,
  required List<String> recipientPeerIds,
  Bridge? bridge,
  int? nearbyDistanceM,
}) async {
  final envelope = PostCreateEnvelope.fromPost(post);
  if (bridge == null || recipient.mlKemPublicKey == null) {
    return envelope.toJson(
      selectedPeerIds: post.audience.selectedPeerIds,
      recipientPeerIds: recipientPeerIds,
      nearbyDistanceM: nearbyDistanceM,
    );
  }

  final encryptResult = await callEncryptMessage(
    bridge: bridge,
    recipientMlKemPublicKey: recipient.mlKemPublicKey!,
    plaintext: envelope.toInnerJson(
      selectedPeerIds: post.audience.selectedPeerIds,
      recipientPeerIds: recipientPeerIds,
      nearbyDistanceM: nearbyDistanceM,
    ),
  );

  if (encryptResult['ok'] != true) {
    return envelope.toJson(
      selectedPeerIds: post.audience.selectedPeerIds,
      recipientPeerIds: recipientPeerIds,
      nearbyDistanceM: nearbyDistanceM,
    );
  }

  return PostCreateEnvelope.buildEncryptedEnvelope(
    eventId: post.eventId,
    createdAt: post.createdAt,
    senderPeerId: post.senderPeerId,
    kem: encryptResult['kem'] as String,
    ciphertext: encryptResult['ciphertext'] as String,
    nonce: encryptResult['nonce'] as String,
  );
}

Future<_DeliveryAttempt> _deliverToRecipient({
  required P2PService p2pService,
  required String recipientPeerId,
  required String wireEnvelope,
}) async {
  try {
    final sendResult = await p2pService.sendMessageWithReply(
      recipientPeerId,
      wireEnvelope,
      timeoutMs: _interactivePostBudget.inMilliseconds,
    );
    if (sendResult.sent) {
      return const _DeliveryAttempt(
        deliveryStatus: 'delivered',
        deliveryPath: 'direct',
      );
    }
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_SEND_DIRECT_ERROR',
      details: {'recipientPeerId': recipientPeerId, 'error': error.toString()},
    );
  }

  final stored = await p2pService.storeInInbox(recipientPeerId, wireEnvelope);
  if (stored) {
    return const _DeliveryAttempt(
      deliveryStatus: 'inbox',
      deliveryPath: 'inbox',
    );
  }
  return const _DeliveryAttempt(
    deliveryStatus: 'failed',
    deliveryPath: 'failed',
    lastError: 'direct_and_inbox_failed',
  );
}

class _DeliveryAttempt {
  final String deliveryStatus;
  final String deliveryPath;
  final String? lastError;

  const _DeliveryAttempt({
    required this.deliveryStatus,
    required this.deliveryPath,
    this.lastError,
  });
}

class _PostDeliveryProgress {
  PostModel latestPost;
  final Map<String, PostRecipientDelivery> deliveriesByRecipient;
  PostDeliveryAggregate aggregate;

  _PostDeliveryProgress({
    required this.latestPost,
    required this.deliveriesByRecipient,
  }) : aggregate = aggregatePostDeliveryStatusFromDeliveries(
         deliveriesByRecipient.values,
       );

  Future<void> applyRecipientCompletion({
    required PostRepository postRepo,
    required String recipientPeerId,
    required String attemptedAt,
    required _DeliveryAttempt delivery,
  }) async {
    final existingDelivery = deliveriesByRecipient[recipientPeerId];
    final updatedDelivery = PostRecipientDelivery(
      postId: latestPost.id,
      recipientPeerId: recipientPeerId,
      deliveryStatus: delivery.deliveryStatus,
      lastAttemptAt: attemptedAt,
      deliveryPath: delivery.deliveryPath,
      lastError: delivery.lastError,
      nearbyDistanceM: existingDelivery?.nearbyDistanceM,
      createdAt: existingDelivery?.createdAt ?? attemptedAt,
      updatedAt: attemptedAt,
    );
    deliveriesByRecipient[recipientPeerId] = updatedDelivery;
    await postRepo.saveRecipientDelivery(updatedDelivery);

    aggregate = aggregatePostDeliveryStatusFromDeliveries(
      deliveriesByRecipient.values,
    );
    latestPost = latestPost.copyWith(deliveryStatus: aggregate.deliveryStatus);
    await postRepo.savePost(latestPost);
  }
}

class _SerializedPostCompletionQueue {
  final void Function(Object error, StackTrace stackTrace) onError;
  Future<void> _tail = Future<void>.value();

  _SerializedPostCompletionQueue({required this.onError});

  void enqueue(Future<void> Function() operation) {
    _tail = _tail.then((_) => operation()).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      onError(error, stackTrace);
    });
  }

  Future<void> flush() => _tail;
}

class PostDeliveryAggregate {
  final String deliveryStatus;

  const PostDeliveryAggregate({required this.deliveryStatus});
}
