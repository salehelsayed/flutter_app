import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/nearby_eligibility_service.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_upload_recovery_item.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';

export 'package:flutter_app/features/posts/application/post_delivery_runner.dart'
    show CreatedLocalPost, CreatedLocalPostRecipient, SendPostResult;

const _uuid = Uuid();
const Duration _postExpiry = Duration(days: 3);

Future<(SendPostResult, PostModel?)> sendPost({
  required P2PService p2pService,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required String senderPeerId,
  required String senderUsername,
  required String text,
  required PostAudience audience,
  List<PostMediaDraft> mediaDrafts = const <PostMediaDraft>[],
  SecureKeyStore? secureKeyStore,
  ImageProcessor? imageProcessor,
  MediaFileManager? mediaFileManager,
  UploadPostMediaFn? uploadPostMediaFn,
  Bridge? bridge,
  ContactPresenceSnapshotRepository? contactPresenceSnapshotRepository,
  PostsPrivacySettingsRepository? postsPrivacySettingsRepository,
}) async {
  final normalizedText = _normalizePostText(text);

  emitFlowEvent(
    layer: 'FL',
    event: 'POST_SEND_START',
    details: {'audienceKind': audience.kind.toWireValue()},
  );

  if (_isInvalidPostPayload(text: normalizedText, mediaDrafts: mediaDrafts)) {
    return (SendPostResult.invalidPost, null);
  }

  if (!p2pService.currentState.isStarted) {
    return (SendPostResult.nodeNotRunning, null);
  }

  final (createResult, created) = await createLocalPost(
    postRepo: postRepo,
    contactRepo: contactRepo,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    text: normalizedText,
    audience: audience,
    mediaDrafts: mediaDrafts,
    secureKeyStore: secureKeyStore,
    imageProcessor: imageProcessor,
    mediaFileManager: mediaFileManager,
    uploadPostMediaFn: uploadPostMediaFn,
    bridge: bridge,
    contactPresenceSnapshotRepository: contactPresenceSnapshotRepository,
    postsPrivacySettingsRepository: postsPrivacySettingsRepository,
  );
  if (createResult != SendPostResult.success || created == null) {
    return (createResult, created?.post);
  }

  final (mediaResult, prepared) = await prepareCreatedLocalPostMedia(
    created: created,
    postRepo: postRepo,
    secureKeyStore: secureKeyStore,
    imageProcessor: imageProcessor,
    mediaFileManager: mediaFileManager,
    uploadPostMediaFn: uploadPostMediaFn,
    bridge: bridge,
  );
  if (mediaResult != SendPostResult.success || prepared == null) {
    return (mediaResult, prepared?.post);
  }

  return PostDeliveryRunner(
    p2pService: p2pService,
    postRepo: postRepo,
    bridge: bridge,
  ).execute(prepared);
}

bool _isInvalidPostPayload({
  required String text,
  required List<PostMediaDraft> mediaDrafts,
}) => text.trim().isEmpty && mediaDrafts.isEmpty;

String _normalizePostText(String text) {
  return sanitizeMessageText(text);
}

String _deriveDraftMediaKind(List<PostMediaDraft> mediaDrafts) {
  if (mediaDrafts.isEmpty) {
    return 'none';
  }
  final firstKind = mediaDrafts.first.kind;
  if (firstKind == 'image' && mediaDrafts.length > 1) {
    return 'image_carousel';
  }
  return firstKind;
}

Future<(SendPostResult, CreatedLocalPost?)> createLocalPost({
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required String senderPeerId,
  required String senderUsername,
  required String text,
  required PostAudience audience,
  List<PostMediaDraft> mediaDrafts = const <PostMediaDraft>[],
  SecureKeyStore? secureKeyStore,
  ImageProcessor? imageProcessor,
  MediaFileManager? mediaFileManager,
  UploadPostMediaFn? uploadPostMediaFn,
  Bridge? bridge,
  ContactPresenceSnapshotRepository? contactPresenceSnapshotRepository,
  PostsPrivacySettingsRepository? postsPrivacySettingsRepository,
}) async {
  final normalizedText = _normalizePostText(text);
  final normalizedSenderUsername = sanitizeUsername(senderUsername);
  final hasMedia = mediaDrafts.isNotEmpty;
  final createStopwatch = Stopwatch()..start();
  void emitPostTiming({
    required String outcome,
    Map<String, dynamic> details = const {},
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_CREATE_LOCAL_TIMING',
      details: {
        'elapsedMs': createStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'hasMedia': hasMedia,
        ...details,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'POST_CREATE_LOCAL_START',
    details: {
      'audienceKind': audience.kind.toWireValue(),
      'hasMedia': hasMedia,
    },
  );
  if (_isInvalidPostPayload(text: normalizedText, mediaDrafts: mediaDrafts)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_CREATE_LOCAL_ABORT',
      details: {
        'audienceKind': audience.kind.toWireValue(),
        'hasMedia': hasMedia,
        'reason': SendPostResult.invalidPost.name,
        'elapsedMs': createStopwatch.elapsedMilliseconds,
      },
    );
    emitPostTiming(outcome: 'invalid_post');
    return (SendPostResult.invalidPost, null);
  }

  final nearbySettings =
      audience.kind == PostAudienceKind.peopleNearby &&
          postsPrivacySettingsRepository != null
      ? await postsPrivacySettingsRepository.load()
      : null;
  final resolvedRecipients = await _resolveEligibleRecipients(
    contactRepo: contactRepo,
    audience: audience,
    contactPresenceSnapshotRepository: contactPresenceSnapshotRepository,
    postsPrivacySettingsRepository: postsPrivacySettingsRepository,
    nearbySettings: nearbySettings,
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_CREATE_LOCAL_RECIPIENTS_READY',
    details: {
      'audienceKind': audience.kind.toWireValue(),
      'recipientCount': resolvedRecipients.length,
      'elapsedMs': createStopwatch.elapsedMilliseconds,
    },
  );
  if (resolvedRecipients.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_CREATE_LOCAL_ABORT',
      details: {
        'audienceKind': audience.kind.toWireValue(),
        'hasMedia': hasMedia,
        'reason': SendPostResult.noEligibleRecipients.name,
        'elapsedMs': createStopwatch.elapsedMilliseconds,
      },
    );
    emitPostTiming(outcome: 'no_eligible_recipients');
    return (SendPostResult.noEligibleRecipients, null);
  }

  final now = DateTime.now().toUtc();
  final createdAt = now.toIso8601String();
  var post = PostModel(
    id: 'post_${_uuid.v4()}',
    eventId: 'evt_${_uuid.v4()}',
    senderPeerId: senderPeerId,
    authorPeerId: senderPeerId,
    authorUsername: normalizedSenderUsername,
    text: normalizedText,
    audience: audience,
    createdAt: createdAt,
    visibleAt: createdAt,
    expiresAt: now.add(_postExpiry).toIso8601String(),
    keepAvailable: false,
    mediaKind: _deriveDraftMediaKind(mediaDrafts),
    nearbySenderLatE3: nearbySettings?.lastLocalLatE3,
    nearbySenderLngE3: nearbySettings?.lastLocalLngE3,
    nearbySenderCapturedAt: nearbySettings?.lastLocalCapturedAt,
    nearbySenderAccuracyM: nearbySettings?.lastLocalAccuracyM,
    isIncoming: false,
    deliveryStatus: 'sending',
  );
  if (hasMedia) {
    await postRepo.replacePostMediaUploadRecoveryItems(
      post.id,
      mediaDrafts
          .asMap()
          .entries
          .map((entry) {
            final draft = entry.value;
            return PostMediaUploadRecoveryItem(
              postId: post.id,
              position: entry.key,
              localFilePath: draft.localFilePath,
              mime: draft.mime,
              kind: draft.kind,
              width: draft.width,
              height: draft.height,
              durationMs: draft.durationMs,
              waveform: draft.waveform,
              createdAt: createdAt,
            );
          })
          .toList(growable: false),
    );
  }
  var postSaved = false;
  try {
    await postRepo.savePost(post);
    postSaved = true;
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_CREATE_LOCAL_POST_SAVED',
      details: {
        'postId': post.id,
        'elapsedMs': createStopwatch.elapsedMilliseconds,
      },
    );
  } catch (_) {
    if (hasMedia && !postSaved) {
      try {
        await postRepo.replacePostMediaUploadRecoveryItems(
          post.id,
          const <PostMediaUploadRecoveryItem>[],
        );
      } catch (_) {}
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_CREATE_LOCAL_ABORT',
      details: {
        'audienceKind': audience.kind.toWireValue(),
        'hasMedia': hasMedia,
        'reason': 'save_post_failed',
        'elapsedMs': createStopwatch.elapsedMilliseconds,
      },
    );
    emitPostTiming(outcome: 'save_failed');
    rethrow;
  }
  await _savePendingRecipientDeliveries(
    postRepo: postRepo,
    postId: post.id,
    recipients: resolvedRecipients,
    createdAt: createdAt,
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_CREATE_LOCAL_DELIVERIES_SAVED',
    details: {
      'postId': post.id,
      'recipientCount': resolvedRecipients.length,
      'elapsedMs': createStopwatch.elapsedMilliseconds,
    },
  );

  if (!hasMedia) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_CREATE_LOCAL_SUCCESS',
      details: {
        'postId': post.id,
        'recipientCount': resolvedRecipients.length,
        'hasMedia': false,
        'elapsedMs': createStopwatch.elapsedMilliseconds,
      },
    );
    emitPostTiming(
      outcome: 'success',
      details: {'recipientCount': resolvedRecipients.length},
    );
    return (
      SendPostResult.success,
      CreatedLocalPost(post: post, resolvedRecipients: resolvedRecipients),
    );
  }
  emitFlowEvent(
    layer: 'FL',
    event: 'POST_CREATE_LOCAL_SUCCESS',
    details: {
      'postId': post.id,
      'recipientCount': resolvedRecipients.length,
      'hasMedia': true,
      'elapsedMs': createStopwatch.elapsedMilliseconds,
    },
  );
  emitPostTiming(
    outcome: 'success',
    details: {'recipientCount': resolvedRecipients.length},
  );
  return (
    SendPostResult.success,
    CreatedLocalPost(
      post: post,
      resolvedRecipients: resolvedRecipients,
      mediaDrafts: mediaDrafts,
    ),
  );
}

Future<void> _savePendingRecipientDeliveries({
  required PostRepository postRepo,
  required String postId,
  required List<CreatedLocalPostRecipient> recipients,
  required String createdAt,
}) async {
  for (final recipient in recipients) {
    await postRepo.saveRecipientDelivery(
      PostRecipientDelivery(
        postId: postId,
        recipientPeerId: recipient.contact.peerId,
        deliveryStatus: 'pending',
        lastAttemptAt: createdAt,
        deliveryPath: 'pending',
        nearbyDistanceM: recipient.nearbyDistanceM,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
  }
}

Future<List<CreatedLocalPostRecipient>> _resolveEligibleRecipients({
  required ContactRepository contactRepo,
  required PostAudience audience,
  ContactPresenceSnapshotRepository? contactPresenceSnapshotRepository,
  PostsPrivacySettingsRepository? postsPrivacySettingsRepository,
  PostsPrivacySettings? nearbySettings,
}) async {
  final recipients = <CreatedLocalPostRecipient>[];
  switch (audience.kind) {
    case PostAudienceKind.allFriends:
      final contacts = await contactRepo.getActiveContacts();
      recipients.addAll(
        contacts
            .where((contact) => !contact.isBlocked)
            .map((contact) => CreatedLocalPostRecipient(contact: contact)),
      );
    case PostAudienceKind.peopleNearby:
      final snapshotRepo = contactPresenceSnapshotRepository;
      final privacyRepo = postsPrivacySettingsRepository;
      final radiusM = audience.radiusM;
      if (snapshotRepo == null || privacyRepo == null || radiusM == null) {
        return const <CreatedLocalPostRecipient>[];
      }
      final nearbyRecipients = await resolveNearbyEligibleRecipients(
        contactRepo: contactRepo,
        snapshotRepo: snapshotRepo,
        privacySettingsRepo: privacyRepo,
        radiusM: radiusM,
        localSettings: nearbySettings,
      );
      recipients.addAll(
        nearbyRecipients.map(
          (entry) => CreatedLocalPostRecipient(
            contact: entry.contact,
            nearbyDistanceM: entry.distanceM,
          ),
        ),
      );
    case PostAudienceKind.pickPeople:
      for (final peerId in audience.selectedPeerIds) {
        final contact = await contactRepo.getContact(peerId);
        if (contact == null || contact.isArchived || contact.isBlocked) {
          continue;
        }
        recipients.add(CreatedLocalPostRecipient(contact: contact));
      }
  }

  final deduped = <String, CreatedLocalPostRecipient>{};
  for (final recipient in recipients) {
    deduped[recipient.contact.peerId] = recipient;
  }
  return deduped.values.toList(growable: false);
}
