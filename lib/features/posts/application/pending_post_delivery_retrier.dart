import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class PendingPostDeliveryRetrier {
  final P2PService p2pService;
  final PostRepository postRepo;
  final ContactRepository contactRepo;
  final Bridge? bridge;
  final Future<int> Function()? beforeRetry;
  final Duration retryDebounce;
  final Duration periodicRetryInterval;

  StreamSubscription? _stateSubscription;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  bool _wasOnline = false;
  bool _isRetrying = false;

  PendingPostDeliveryRetrier({
    required this.p2pService,
    required this.postRepo,
    required this.contactRepo,
    this.bridge,
    this.beforeRetry,
    this.retryDebounce = const Duration(seconds: 5),
    this.periodicRetryInterval = const Duration(minutes: 5),
  });

  void start() {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_POST_RETRIER_START',
      details: {},
    );

    _wasOnline = _isOnline(p2pService.currentState);
    if (_wasOnline) {
      _scheduleRetry();
      _periodicTimer?.cancel();
      _periodicTimer = Timer.periodic(
        periodicRetryInterval,
        (_) => unawaited(retryNow()),
      );
    }
    _stateSubscription = p2pService.stateStream.listen((state) {
      final nowOnline = _isOnline(state);

      if (nowOnline && !_wasOnline) {
        _scheduleRetry();
        _periodicTimer?.cancel();
        _periodicTimer = Timer.periodic(
          periodicRetryInterval,
          (_) => unawaited(retryNow()),
        );
      } else if (!nowOnline && _wasOnline) {
        _periodicTimer?.cancel();
        _periodicTimer = null;
      }

      _wasOnline = nowOnline;
    });
  }

  bool _isOnline(dynamic state) {
    return state.isStarted && (state.circuitAddresses as List).isNotEmpty;
  }

  void _scheduleRetry() {
    _debounceTimer?.cancel();
    if (retryDebounce == Duration.zero) {
      unawaited(retryNow());
    } else {
      _debounceTimer = Timer(retryDebounce, () {
        unawaited(retryNow());
      });
    }
  }

  Future<int> retryNow() async {
    if (!_isOnline(p2pService.currentState) || _isRetrying) {
      return 0;
    }
    _isRetrying = true;

    try {
      final runBeforeRetry = beforeRetry;
      if (runBeforeRetry != null) {
        await runBeforeRetry();
      }
      final retried = await retryPendingPostDeliveries(
        postRepo: postRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );
      if (retried > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_POST_RETRIER_RETRIED',
          details: {'count': retried},
        );
      }
      return retried;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_POST_RETRIER_ERROR',
        details: {'error': e.toString()},
      );
      return 0;
    } finally {
      _isRetrying = false;
    }
  }

  void dispose() {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_POST_RETRIER_DISPOSE',
      details: {},
    );
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _stateSubscription?.cancel();
    _stateSubscription = null;
  }
}

Future<int> retryPendingPostDeliveries({
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  Bridge? bridge,
}) async {
  final retryablePosts = await postRepo.loadRetryableOutgoingPosts();
  var retriedCount = 0;

  for (final post in retryablePosts) {
    if (post.isIncoming) {
      continue;
    }

    final deliveries = await postRepo.getRecipientDeliveries(post.id);
    if (deliveries.isEmpty) {
      continue;
    }

    final aggregate = aggregatePostDeliveryStatusFromDeliveries(deliveries);
    final unresolvedDeliveries = deliveries
        .where(
          (delivery) =>
              !isSuccessfulRecipientDeliveryStatus(delivery.deliveryStatus),
        )
        .toList(growable: false);

    if (unresolvedDeliveries.isEmpty) {
      if (aggregate.deliveryStatus != post.deliveryStatus) {
        await postRepo.savePost(
          post.copyWith(deliveryStatus: aggregate.deliveryStatus),
        );
      }
      continue;
    }

    final attachments = await postRepo.loadPostMediaAttachments(post.id);
    final hydratedPost = post.copyWith(
      mediaKind: post.mediaKind == 'none' && attachments.isNotEmpty
          ? PostMediaAttachmentModel.deriveMediaKind(attachments)
          : post.mediaKind,
      media: attachments,
    );

    // Media upload recovery now runs in its own retrier. Delivery retry still
    // skips posts whose upload stage has not produced attachments yet.
    if (hydratedPost.mediaKind != 'none' && hydratedPost.media.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_POST_RETRIER_SKIPPED_PENDING_MEDIA',
        details: {'postId': hydratedPost.id},
      );
      continue;
    }

    final retryRecipients = <CreatedLocalPostRecipient>[];
    for (final delivery in unresolvedDeliveries) {
      final contact = await contactRepo.getContact(delivery.recipientPeerId);
      if (contact == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_POST_RETRIER_MISSING_CONTACT',
          details: {
            'postId': hydratedPost.id,
            'recipientPeerId': delivery.recipientPeerId,
          },
        );
        continue;
      }
      retryRecipients.add(
        CreatedLocalPostRecipient(
          contact: contact,
          nearbyDistanceM: delivery.nearbyDistanceM,
        ),
      );
    }

    if (retryRecipients.isEmpty) {
      continue;
    }

    retriedCount++;
    await PostDeliveryRunner(
      p2pService: p2pService,
      postRepo: postRepo,
      bridge: bridge,
    ).execute(
      CreatedLocalPost(
        post: hydratedPost,
        resolvedRecipients: retryRecipients,
        allRecipientPeerIds: deliveries
            .map((delivery) => delivery.recipientPeerId)
            .toList(growable: false),
      ),
    );
  }

  final retryablePasses = await postRepo.loadRetryableOutgoingPostPasses();
  for (final pass in retryablePasses) {
    if (pass.isIncoming) {
      continue;
    }

    final deliveries = await postRepo.getPostPassRecipientDeliveries(
      pass.passId,
    );
    if (deliveries.isEmpty) {
      continue;
    }

    final aggregate = aggregatePostDeliveryStatusFromDeliveries(deliveries);
    final unresolvedDeliveries = deliveries
        .where(
          (delivery) =>
              !isSuccessfulRecipientDeliveryStatus(delivery.deliveryStatus),
        )
        .toList(growable: false);
    if (unresolvedDeliveries.isEmpty) {
      if (aggregate.deliveryStatus != pass.deliveryStatus) {
        await postRepo.savePostPass(
          pass.copyWith(deliveryStatus: aggregate.deliveryStatus),
        );
      }
      continue;
    }

    final sourcePost = await postRepo.getPost(pass.postId);
    if (sourcePost == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_POST_RETRIER_MISSING_PASS_SOURCE_POST',
        details: {'passId': pass.passId, 'postId': pass.postId},
      );
      continue;
    }

    final attachments = await postRepo.loadPostMediaAttachments(sourcePost.id);
    final hydratedPost = sourcePost.copyWith(
      mediaKind: sourcePost.mediaKind == 'none' && attachments.isNotEmpty
          ? PostMediaAttachmentModel.deriveMediaKind(attachments)
          : sourcePost.mediaKind,
      media: attachments,
    );
    if (hydratedPost.mediaKind != 'none' && hydratedPost.media.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_POST_RETRIER_SKIPPED_PENDING_PASS_MEDIA',
        details: {'passId': pass.passId, 'postId': hydratedPost.id},
      );
      continue;
    }

    final retryRecipients = <CreatedLocalPostRecipient>[];
    for (final delivery in unresolvedDeliveries) {
      final contact = await contactRepo.getContact(delivery.recipientPeerId);
      if (contact == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_POST_RETRIER_MISSING_PASS_CONTACT',
          details: {
            'passId': pass.passId,
            'recipientPeerId': delivery.recipientPeerId,
          },
        );
        continue;
      }
      retryRecipients.add(
        CreatedLocalPostRecipient(
          contact: contact,
          nearbyDistanceM: delivery.nearbyDistanceM,
        ),
      );
    }

    if (retryRecipients.isEmpty) {
      continue;
    }

    retriedCount++;
    await PostDeliveryRunner(
      p2pService: p2pService,
      postRepo: postRepo,
      bridge: bridge,
      maxConcurrentRecipients: defaultPostDeliveryConcurrency,
    ).executePostPass(
      pass: pass,
      snapshotPost: hydratedPost,
      resolvedRecipients: retryRecipients,
      allRecipientPeerIds: deliveries
          .map((delivery) => delivery.recipientPeerId)
          .toList(growable: false),
    );
  }

  return retriedCount;
}
