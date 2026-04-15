import 'dart:async';
import 'dart:collection';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:flutter_app/features/posts/application/post_repost_engagement_support.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const Duration _interactivePostBudget = Duration(seconds: 4);
// Keep interactive post fanout bounded while shortening long recipient tails.
const int defaultPostDeliveryConcurrency = 25;

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

  List<String> get recipientPeerIds => allRecipientPeerIds.isNotEmpty
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
    this.maxConcurrentRecipients = defaultPostDeliveryConcurrency,
  }) {
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
    final deliveryStopwatch = Stopwatch()..start();

    try {
      progress = _PostDeliveryProgress(
        latestPost: created.post,
        deliveriesByRecipient: await _loadExistingDeliveries(
          created.post.id,
          postRepo,
        ),
      );
      final recipientPeerIds = created.recipientPeerIds;
      await _runRecipientFanout(
        p2pService: p2pService,
        maxConcurrentRecipients: maxConcurrentRecipients,
        resolvedRecipients: created.resolvedRecipients,
        buildWireEnvelope: (recipient) {
          return _buildWireEnvelope(
            post: created.post,
            bridge: bridge,
            recipient: recipient.contact,
            recipientPeerIds: recipientPeerIds,
            nearbyDistanceM: recipient.nearbyDistanceM,
          );
        },
        persistRecipientCompletion: (recipient, attemptedAt, delivery) {
          return progress!.applyRecipientCompletion(
            postRepo: postRepo,
            recipientPeerId: recipient.contact.peerId,
            attemptedAt: attemptedAt,
            delivery: delivery,
          );
        },
      );
    } catch (error) {
      deliveryStopwatch.stop();
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_SEND_DELIVERY_TIMING',
        details: {
          'elapsedMs': deliveryStopwatch.elapsedMilliseconds,
          'outcome': 'error',
          'recipientCount': created.resolvedRecipients.length,
        },
      );
      return _persistTerminalFailure(
        created.post.id,
        progress?.latestPost ?? created.post,
        error,
        postRepo,
      );
    }

    deliveryStopwatch.stop();
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_SEND_DELIVERY_TIMING',
      details: {
        'elapsedMs': deliveryStopwatch.elapsedMilliseconds,
        'outcome': _resultForAggregate(progress.aggregate).name,
        'recipientCount': created.resolvedRecipients.length,
        'deliveryStatus': progress.aggregate.deliveryStatus,
      },
    );

    return (_resultForAggregate(progress.aggregate), progress.latestPost);
  }

  Future<(SendPostResult, PostPassModel)> executePostPass({
    required PostPassModel pass,
    required PostModel snapshotPost,
    required List<CreatedLocalPostRecipient> resolvedRecipients,
    List<String> allRecipientPeerIds = const <String>[],
  }) async {
    final progress = _PostPassDeliveryProgress(
      latestPass: pass,
      deliveriesByRecipient: await _loadExistingPostPassDeliveries(
        pass.passId,
        postRepo,
      ),
    );
    var innerPayloadJson = pass.innerPayloadJson;
    PostPassEnvelope? innerEnvelope;
    if (innerPayloadJson == null || innerPayloadJson.isEmpty) {
      final participantBasePeerIds =
          await loadPersistedRepostParticipantPeerIds(
            postRepo: postRepo,
            postId: snapshotPost.id,
            authorPeerId: snapshotPost.authorPeerId,
            passerPeerId: pass.passerPeerId,
          );
      final activeHeartPeerIds = await loadProjectedActiveHeartPeerIds(
        postRepo: postRepo,
        postId: snapshotPost.id,
      );
      final repostTotalBaseline = await loadProjectedRepostShareCount(
        postRepo: postRepo,
        postId: snapshotPost.id,
      );
      final participantPeerIds = _mergeSortedParticipantPeerIds(
        participantBasePeerIds,
        allRecipientPeerIds,
      );
      innerEnvelope = PostPassEnvelope.fromPass(
        pass: pass,
        post: snapshotPost,
        participantPeerIds: participantPeerIds,
        participantBasePeerIds: participantBasePeerIds,
        activeHeartPeerIds: activeHeartPeerIds,
        repostTotalBaseline: repostTotalBaseline > 0
            ? repostTotalBaseline - 1
            : 0,
      );
      innerPayloadJson = innerEnvelope.toInnerJson();
      progress.latestPass = pass.copyWith(innerPayloadJson: innerPayloadJson);
      await postRepo.savePostPass(progress.latestPass);
    } else {
      innerEnvelope = PostPassEnvelope.fromInnerJson(
        innerJson: innerPayloadJson,
        eventId: pass.eventId,
        createdAt: pass.createdAt,
        senderPeerId: pass.senderPeerId,
      );
    }

    try {
      await _runRecipientFanout(
        p2pService: p2pService,
        maxConcurrentRecipients: maxConcurrentRecipients,
        resolvedRecipients: resolvedRecipients,
        buildWireEnvelope: (recipient) {
          final scopedInnerPayloadJson = _buildRecipientScopedPostPassInnerJson(
            pass: progress.latestPass,
            innerPayloadJson: innerPayloadJson!,
            innerEnvelope: innerEnvelope,
            recipientPeerId: recipient.contact.peerId,
            allRecipientPeerIds: allRecipientPeerIds,
          );
          return _buildPostPassWireEnvelope(
            pass: progress.latestPass,
            innerPayloadJson: scopedInnerPayloadJson,
            bridge: bridge,
            recipient: recipient.contact,
          );
        },
        persistRecipientCompletion: (recipient, attemptedAt, delivery) {
          return progress.applyRecipientCompletion(
            postRepo: postRepo,
            postId: snapshotPost.id,
            recipientPeerId: recipient.contact.peerId,
            attemptedAt: attemptedAt,
            delivery: delivery,
          );
        },
      );
    } catch (error) {
      await progress.markUnsettledAsFailed(
        postRepo: postRepo,
        postId: snapshotPost.id,
        error: error,
      );
    }

    return (_resultForAggregate(progress.aggregate), progress.latestPass);
  }
}

String _buildRecipientScopedPostPassInnerJson({
  required PostPassModel pass,
  required String innerPayloadJson,
  required String recipientPeerId,
  required List<String> allRecipientPeerIds,
  PostPassEnvelope? innerEnvelope,
}) {
  final envelope =
      innerEnvelope ??
      PostPassEnvelope.fromInnerJson(
        innerJson: innerPayloadJson,
        eventId: pass.eventId,
        createdAt: pass.createdAt,
        senderPeerId: pass.senderPeerId,
      );
  if (envelope == null) {
    return innerPayloadJson;
  }

  final participantBasePeerIds = envelope.participantBasePeerIds.isNotEmpty
      ? envelope.participantBasePeerIds
      : envelope.participantPeerIds;
  final scopedParticipantPeerIds =
      recipientPeerId == envelope.originalSnapshot.authorPeerId
      ? _mergeSortedParticipantPeerIds(
          participantBasePeerIds,
          allRecipientPeerIds,
        )
      : _mergeSortedParticipantPeerIds(participantBasePeerIds, <String>[
          recipientPeerId,
        ]);

  return PostPassEnvelope(
    eventId: pass.eventId,
    createdAt: pass.createdAt,
    senderPeerId: pass.senderPeerId,
    passId: envelope.passId,
    postId: envelope.postId,
    passedAt: envelope.passedAt,
    passerPeerId: envelope.passerPeerId,
    passerUsername: envelope.passerUsername,
    originalSnapshot: envelope.originalSnapshot,
    participantPeerIds: scopedParticipantPeerIds,
    participantBasePeerIds: participantBasePeerIds,
    activeHeartPeerIds: envelope.activeHeartPeerIds,
    repostTotalBaseline: envelope.repostTotalBaseline,
    sharedToCountBaseline: envelope.sharedToCountBaseline,
    recipientCount: envelope.recipientCount,
    mediaKeys: envelope.mediaKeys,
  ).toInnerJson();
}

List<String> _mergeSortedParticipantPeerIds(
  Iterable<String> seedPeerIds,
  Iterable<String> extraPeerIds,
) {
  final peerIds = <String>{...seedPeerIds, ...extraPeerIds}
    ..removeWhere((peerId) => peerId.isEmpty);
  final sortedPeerIds = peerIds.toList(growable: false)..sort();
  return sortedPeerIds;
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

Future<Map<String, PostRecipientDelivery>> _loadExistingPostPassDeliveries(
  String passId,
  PostRepository postRepo,
) async {
  final deliveries = await postRepo.getPostPassRecipientDeliveries(passId);
  return <String, PostRecipientDelivery>{
    for (final delivery in deliveries) delivery.recipientPeerId: delivery,
  };
}

Future<void> _runRecipientFanout({
  required P2PService p2pService,
  required int maxConcurrentRecipients,
  required List<CreatedLocalPostRecipient> resolvedRecipients,
  required Future<String> Function(CreatedLocalPostRecipient recipient)
  buildWireEnvelope,
  required Future<void> Function(
    CreatedLocalPostRecipient recipient,
    String attemptedAt,
    _DeliveryAttempt delivery,
  )
  persistRecipientCompletion,
}) async {
  final pendingRecipients = Queue<CreatedLocalPostRecipient>.of(
    resolvedRecipients,
  );
  final inFlight = <Future<void>>[];
  AsyncError? fatalError;
  final completionQueue = _SerializedPostCompletionQueue(
    onError: (error, stackTrace) {
      fatalError ??= AsyncError(error, stackTrace);
    },
  );

  Future<void> runRecipient(CreatedLocalPostRecipient recipient) async {
    final attemptedAt = DateTime.now().toUtc().toIso8601String();
    try {
      final wireEnvelope = await buildWireEnvelope(recipient);
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
        return persistRecipientCompletion(recipient, attemptedAt, delivery);
      });
    } on _RecipientDeliveryBuildException catch (error) {
      completionQueue.enqueue(() {
        if (fatalError != null) {
          return Future<void>.value();
        }
        return persistRecipientCompletion(
          recipient,
          attemptedAt,
          _DeliveryAttempt(
            deliveryStatus: 'failed',
            deliveryPath: 'failed',
            lastError: error.message,
          ),
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
    Error.throwWithStackTrace(uncaughtError.error, uncaughtError.stackTrace);
  }
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

Future<String> _buildPostPassWireEnvelope({
  required PostPassModel pass,
  required String innerPayloadJson,
  required ContactModel recipient,
  Bridge? bridge,
}) async {
  if (bridge == null) {
    throw const _RecipientDeliveryBuildException(
      'repost_encryption_unavailable',
    );
  }
  final recipientMlKemPublicKey = recipient.mlKemPublicKey;
  if (recipientMlKemPublicKey == null || recipientMlKemPublicKey.isEmpty) {
    throw const _RecipientDeliveryBuildException(
      'repost_recipient_missing_mlkem_key',
    );
  }

  final encryptResult = await callEncryptMessage(
    bridge: bridge,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    plaintext: innerPayloadJson,
  );
  if (encryptResult['ok'] != true) {
    final errorCode = encryptResult['errorCode']?.toString();
    throw _RecipientDeliveryBuildException(
      errorCode == null || errorCode.isEmpty
          ? 'repost_encrypt_failed'
          : 'repost_encrypt_failed:$errorCode',
    );
  }

  return PostPassEnvelope.buildEncryptedEnvelope(
    eventId: pass.eventId,
    createdAt: pass.createdAt,
    senderPeerId: pass.senderPeerId,
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
  var directFailureReason = 'direct_send_failed';
  try {
    final directReady = await ensurePostRecipientDirectConnection(
      p2pService: p2pService,
      recipientPeerId: recipientPeerId,
      interactiveBudget: _interactivePostBudget,
    );
    if (directReady) {
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
      directFailureReason = 'direct_send_returned_not_sent';
    } else {
      directFailureReason = 'direct_connect_unavailable';
    }
  } catch (error) {
    directFailureReason = error.toString();
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_SEND_DIRECT_ERROR',
      details: {'recipientPeerId': recipientPeerId, 'error': error.toString()},
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
  final stored = await p2pService.storeInInbox(recipientPeerId, wireEnvelope);
  if (stored) {
    return const _DeliveryAttempt(
      deliveryStatus: 'inbox',
      deliveryPath: 'inbox',
    );
  }
  return _DeliveryAttempt(
    deliveryStatus: 'failed',
    deliveryPath: 'failed',
    lastError: '$directFailureReason:inbox_store_failed',
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

class _RecipientDeliveryBuildException implements Exception {
  final String message;

  const _RecipientDeliveryBuildException(this.message);
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
      deliveryOwnerKind:
          existingDelivery?.deliveryOwnerKind ??
          postRecipientDeliveryOwnerKindPost,
      deliveryOwnerId: existingDelivery?.deliveryOwnerId ?? latestPost.id,
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

class _PostPassDeliveryProgress {
  PostPassModel latestPass;
  final Map<String, PostRecipientDelivery> deliveriesByRecipient;
  PostDeliveryAggregate aggregate;

  _PostPassDeliveryProgress({
    required this.latestPass,
    required this.deliveriesByRecipient,
  }) : aggregate = aggregatePostDeliveryStatusFromDeliveries(
         deliveriesByRecipient.values,
       );

  Future<void> applyRecipientCompletion({
    required PostRepository postRepo,
    required String postId,
    required String recipientPeerId,
    required String attemptedAt,
    required _DeliveryAttempt delivery,
  }) async {
    final existingDelivery = deliveriesByRecipient[recipientPeerId];
    final updatedDelivery = PostRecipientDelivery(
      postId: postId,
      recipientPeerId: recipientPeerId,
      deliveryStatus: delivery.deliveryStatus,
      lastAttemptAt: attemptedAt,
      deliveryPath: delivery.deliveryPath,
      lastError: delivery.lastError,
      nearbyDistanceM: existingDelivery?.nearbyDistanceM,
      createdAt: existingDelivery?.createdAt ?? attemptedAt,
      updatedAt: attemptedAt,
      deliveryOwnerKind: postRecipientDeliveryOwnerKindPass,
      deliveryOwnerId: latestPass.passId,
    );
    deliveriesByRecipient[recipientPeerId] = updatedDelivery;
    await postRepo.saveRecipientDelivery(updatedDelivery);

    aggregate = aggregatePostDeliveryStatusFromDeliveries(
      deliveriesByRecipient.values,
    );
    latestPass = latestPass.copyWith(deliveryStatus: aggregate.deliveryStatus);
    await postRepo.savePostPass(latestPass);
  }

  Future<void> markUnsettledAsFailed({
    required PostRepository postRepo,
    required String postId,
    required Object error,
  }) async {
    final attemptedAt = DateTime.now().toUtc().toIso8601String();
    final unsettledDeliveries = deliveriesByRecipient.values
        .where(
          (delivery) =>
              !isSuccessfulRecipientDeliveryStatus(delivery.deliveryStatus),
        )
        .toList(growable: false);
    for (final delivery in unsettledDeliveries) {
      final failedDelivery = delivery.copyWith(
        deliveryStatus: 'failed',
        deliveryPath: 'failed',
        lastError: error.toString(),
        lastAttemptAt: attemptedAt,
        updatedAt: attemptedAt,
        deliveryOwnerKind: postRecipientDeliveryOwnerKindPass,
        deliveryOwnerId: latestPass.passId,
      );
      deliveriesByRecipient[delivery.recipientPeerId] = failedDelivery;
      await postRepo.saveRecipientDelivery(failedDelivery);
    }

    aggregate = aggregatePostDeliveryStatusFromDeliveries(
      deliveriesByRecipient.values,
    );
    latestPass = latestPass.copyWith(deliveryStatus: aggregate.deliveryStatus);
    await postRepo.savePostPass(latestPass);
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
