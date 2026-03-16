import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_upload_recovery_item.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class PendingPostMediaUploadRetrier {
  final P2PService p2pService;
  final PostRepository postRepo;
  final ContactRepository contactRepo;
  final SecureKeyStore secureKeyStore;
  final ImageProcessor imageProcessor;
  final MediaFileManager? mediaFileManager;
  final UploadPostMediaFn? uploadPostMediaFn;
  final Bridge? bridge;
  final Duration retryDebounce;
  final Duration periodicRetryInterval;

  StreamSubscription? _stateSubscription;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  bool _wasOnline = false;
  bool _isRetrying = false;

  PendingPostMediaUploadRetrier({
    required this.p2pService,
    required this.postRepo,
    required this.contactRepo,
    required this.secureKeyStore,
    required this.imageProcessor,
    this.mediaFileManager,
    this.uploadPostMediaFn,
    this.bridge,
    this.retryDebounce = const Duration(seconds: 5),
    this.periodicRetryInterval = const Duration(minutes: 5),
  });

  void start() {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_POST_MEDIA_UPLOAD_RETRIER_START',
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

  Future<int> retryNow() async {
    if (!_isOnline(p2pService.currentState) || _isRetrying) {
      return 0;
    }
    _isRetrying = true;

    try {
      final retried = await retryPendingPostMediaUploads(
        postRepo: postRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        mediaFileManager: mediaFileManager,
        uploadPostMediaFn: uploadPostMediaFn,
        bridge: bridge,
      );
      if (retried > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_POST_MEDIA_UPLOAD_RETRIER_RETRIED',
          details: {'count': retried},
        );
      }
      return retried;
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_POST_MEDIA_UPLOAD_RETRIER_ERROR',
        details: {'error': error.toString()},
      );
      return 0;
    } finally {
      _isRetrying = false;
    }
  }

  void dispose() {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_POST_MEDIA_UPLOAD_RETRIER_DISPOSE',
      details: {},
    );
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _stateSubscription?.cancel();
    _stateSubscription = null;
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
}

Future<int> retryPendingPostMediaUploads({
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required SecureKeyStore secureKeyStore,
  required ImageProcessor imageProcessor,
  MediaFileManager? mediaFileManager,
  UploadPostMediaFn? uploadPostMediaFn,
  Bridge? bridge,
}) async {
  final pendingPosts = await postRepo.loadPendingMediaUploadPosts();
  var retriedCount = 0;

  for (final post in pendingPosts) {
    final recoveryItems = await postRepo.loadPostMediaUploadRecoveryItems(
      post.id,
    );
    if (recoveryItems.isEmpty) {
      continue;
    }

    final missingItem = await _firstMissingLocalFile(recoveryItems);
    if (missingItem != null) {
      retriedCount++;
      await _persistMissingLocalFileFailure(
        postRepo: postRepo,
        post: post,
        missingItem: missingItem,
      );
      continue;
    }

    final deliveries = await postRepo.getRecipientDeliveries(post.id);
    if (deliveries.isEmpty) {
      continue;
    }

    retriedCount++;
    final retryRecipients = await _loadRetryRecipients(
      contactRepo: contactRepo,
      post: post,
      deliveries: deliveries,
    );
    final (prepareResult, prepared) = await prepareCreatedLocalPostMedia(
      created: CreatedLocalPost(
        post: post,
        resolvedRecipients: retryRecipients,
        allRecipientPeerIds: deliveries
            .map((delivery) => delivery.recipientPeerId)
            .toList(growable: false),
      ),
      postRepo: postRepo,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      mediaFileManager: mediaFileManager,
      uploadPostMediaFn: uploadPostMediaFn,
      bridge: bridge,
    );
    if (prepareResult != SendPostResult.success || prepared == null) {
      continue;
    }

    if (retryRecipients.isEmpty) {
      final aggregate = aggregatePostDeliveryStatusFromDeliveries(deliveries);
      if (aggregate.deliveryStatus != prepared.post.deliveryStatus) {
        await postRepo.savePost(
          prepared.post.copyWith(deliveryStatus: aggregate.deliveryStatus),
        );
      }
      continue;
    }

    await PostDeliveryRunner(
      p2pService: p2pService,
      postRepo: postRepo,
      bridge: bridge,
    ).execute(prepared);
  }

  return retriedCount;
}

Future<List<CreatedLocalPostRecipient>> _loadRetryRecipients({
  required ContactRepository contactRepo,
  required PostModel post,
  required List<PostRecipientDelivery> deliveries,
}) async {
  final retryRecipients = <CreatedLocalPostRecipient>[];
  final unresolvedDeliveries = deliveries
      .where(
        (delivery) =>
            !isSuccessfulRecipientDeliveryStatus(delivery.deliveryStatus),
      )
      .toList(growable: false);

  for (final delivery in unresolvedDeliveries) {
    final contact = await contactRepo.getContact(delivery.recipientPeerId);
    if (contact == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_POST_MEDIA_UPLOAD_RETRIER_MISSING_CONTACT',
        details: {
          'postId': post.id,
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

  return retryRecipients;
}

Future<PostMediaUploadRecoveryItem?> _firstMissingLocalFile(
  List<PostMediaUploadRecoveryItem> items,
) async {
  for (final item in items) {
    if (!await File(item.localFilePath).exists()) {
      return item;
    }
  }
  return null;
}

Future<void> _persistMissingLocalFileFailure({
  required PostRepository postRepo,
  required PostModel post,
  required PostMediaUploadRecoveryItem missingItem,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'PENDING_POST_MEDIA_UPLOAD_RETRIER_MISSING_LOCAL_FILE',
    details: {'postId': post.id, 'localFilePath': missingItem.localFilePath},
  );
  await postRepo.replacePostMediaUploadRecoveryItems(post.id, const []);
  await postRepo.replacePostMediaAttachments(
    post.id,
    const <PostMediaAttachmentModel>[],
  );
  await postRepo.savePost(
    post.copyWith(deliveryStatus: 'failed', media: const []),
  );
}
