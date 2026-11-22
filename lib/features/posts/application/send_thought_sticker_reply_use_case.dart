import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/config/direct_linked_media_fanout_flag.dart';
import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/core/media/app_owned_media_delete_telemetry.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/direct_upload_retry_signal.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_mime.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/conversation/application/direct_media_fanout_admission.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:uuid/uuid.dart';

final _safeMessageId = RegExp(r'^[a-zA-Z0-9_-]+$');

/// Authors one ordinary direct sticker with a Thought quote. The caller keeps
/// the message ID for retries. A fresh attempt adopts [preparedMedia] only
/// after the app has made and recorded its own durable copy.
Future<ThoughtReplyStatus> sendThoughtStickerReply({
  required String messageId,
  required String postId,
  required String authorPeerId,
  required String expectedSenderPeerId,
  required String stickerId,
  PendingComposerMedia? preparedMedia,
  void Function()? onMediaAdopted,
  required PostRepository postRepo,
  required MessageRepository messageRepo,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaFileManager mediaFileManager,
  ({ActiveIdentityReporter? reporter, ActiveIdentityReporterCapture? capture})?
  capturedActivity,
  DirectEventFanoutAuthoring? directEventFanout,
  DateTime Function()? nowProvider,
  UploadMediaFn uploadMediaFn = uploadMedia,
  PrepareEncryptedMediaArtifactFn prepareEncryptedMediaArtifactFn =
      prepareEncryptedMediaArtifact,
  PreparedDirectMediaBlobCustodyCoordinator? directMediaBlobCustodyCoordinator,
  bool directMediaBlobCustodyClientEnabled =
      kDirectMediaBlobCustodyClientEnabled,
  bool directLinkedEventFanoutEnabled = kDirectLinkedEventFanoutEnabled,
  DirectLinkedMediaFanoutSelector directLinkedMediaFanoutSelector =
      const DirectLinkedMediaFanoutSelector(),
}) async {
  if (!_safeMessageId.hasMatch(messageId) ||
      postId.isEmpty ||
      authorPeerId.isEmpty ||
      expectedSenderPeerId.isEmpty ||
      stickerId.isEmpty ||
      stickerId.trim() != stickerId) {
    return ThoughtReplyStatus.failed;
  }
  final quoteId = thoughtQuoteId(postId);
  final blobId = const Uuid().v5(
    Namespace.url.value,
    'mknoon:thought-sticker:$messageId',
  );
  final intentId = computeDirectMediaCustodyIntentId(
    messageId: messageId,
    attachmentIds: [blobId],
  );
  final now = nowProvider ?? DateTime.now;
  final activity = capturedActivity ?? (reporter: null, capture: null);
  final blobRepository = switch (mediaAttachmentRepo) {
    DirectMediaBlobCustodyRepository repository
        when repository.supportsDirectMediaBlobCustody =>
      repository,
    _ => null,
  };
  final strict = directMediaBlobCustodyClientEnabled && blobRepository != null;
  final coordinator =
      directMediaBlobCustodyCoordinator ??
      (blobRepository == null
          ? null
          : PreparedDirectMediaBlobCustodyCoordinator(
              repository: blobRepository,
              artifactStore: DirectMediaBlobArtifactStore(),
              prepareArtifact: prepareEncryptedMediaArtifactFn,
            ));

  bool ownsReply(ConversationMessage parent) =>
      parent.id == messageId &&
      parent.senderPeerId == expectedSenderPeerId &&
      parent.contactPeerId == authorPeerId &&
      parent.quotedMessageId == quoteId &&
      parent.text.isEmpty &&
      !parent.isIncoming &&
      !parent.isDeleted &&
      !parent.isHidden &&
      !parent.isForwarded &&
      parent.editedAt == null &&
      parent.privateMediaPolicy == const PrivateMediaPolicy.ordinary();

  bool ownsSticker(MediaAttachment attachment) =>
      attachment.id == blobId &&
      attachment.messageId == messageId &&
      attachment.ownerLane == MediaOwnerLane.direct &&
      attachment.stickerId == stickerId &&
      attachment.mediaType == 'image';

  Future<List<MediaAttachment>> loadAttachments() => mediaAttachmentRepo
      .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.direct);

  Future<ContactModel?> eligibleContact() async {
    final contact = await contactRepo.getContact(authorPeerId);
    final post = await postRepo.getPost(postId);
    final identity = await identityRepo.loadIdentity();
    final expiry = DateTime.tryParse(post?.expiresAt ?? '');
    if (contact == null ||
        contact.peerId != authorPeerId ||
        contact.isBlocked ||
        contact.isArchived ||
        post == null ||
        !post.isIncoming ||
        post.authorPeerId != authorPeerId ||
        expiry == null ||
        !expiry.isAfter(now()) ||
        identity?.peerId != expectedSenderPeerId) {
      return null;
    }
    return contact;
  }

  Future<ThoughtReplyStatus> currentStatus() async {
    final current = await messageRepo.getMessage(messageId);
    if (current == null || !ownsReply(current)) {
      return ThoughtReplyStatus.failed;
    }
    return ThoughtReplyStatus.fromMessage(current);
  }

  MediaUploadLease? lease;
  String? copiedPath;
  String? backgroundTask;
  var requestRetry = false;
  try {
    if (await eligibleContact() == null) return ThoughtReplyStatus.failed;
    final existing = await messageRepo.getMessage(messageId);
    MediaAttachment? rearmStrict;
    if (existing != null) {
      if (!ownsReply(existing)) return ThoughtReplyStatus.failed;
      final stored = await loadAttachments();
      if (stored.isEmpty) {
        // A partial local preparation can only be repaired from picker media
        // under the same parent and attachment identity.
        if (existing.directMediaCustodyIntentId != intentId ||
            existing.wireEnvelope != null ||
            existing.transport != null ||
            !const {'sending', 'failed'}.contains(existing.status)) {
          return ThoughtReplyStatus.failed;
        }
      } else {
        if (stored.length != 1 || !ownsSticker(stored.single)) {
          return ThoughtReplyStatus.failed;
        }
        if (existing.status != 'failed') {
          return ThoughtReplyStatus.fromMessage(existing);
        }
        final attachment = stored.single;
        final strictAuthorityMissing =
            strict &&
            existing.wireEnvelope == null &&
            existing.directMediaCustodyIntentId == intentId &&
            attachment.downloadStatus == 'upload_failed' &&
            (await blobRepository.loadDirectMediaBlobCustodyForMessage(
              messageId,
            )).isEmpty;
        if (strictAuthorityMissing) {
          rearmStrict = attachment;
        } else {
          if (await eligibleContact() == null) return ThoughtReplyStatus.failed;
          await retryFailedMessage(
            messageId: messageId,
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: bridge,
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            directMediaBlobCustodyCoordinator: coordinator,
            uploadMediaFn: uploadMediaFn,
            tryClaimUploadLease: (ids) => mediaUploadInFlightTracker
                .tryClaimAll(ids, source: MediaUploadTriggerSource.manual),
            releaseUploadLease: mediaUploadInFlightTracker.release,
          );
          return await currentStatus();
        }
      }
    }

    final media = preparedMedia;
    final mime =
        rearmStrict?.mime ??
        (media == null ? '' : mimeFromPath(media.file.path));
    if (MediaAttachment.mediaTypeFromMime(mime) != 'image' ||
        (rearmStrict == null &&
            (media == null ||
                media.budgetBytes <= 0 ||
                await media.file.length() != media.budgetBytes))) {
      return ThoughtReplyStatus.failed;
    }

    final canServeFanout =
        strict &&
        directLinkedEventFanoutEnabled &&
        directLinkedMediaFanoutSelector
            .allowsDirectLinkedMediaFanoutAuthoring &&
        mediaAttachmentRepo is OutgoingDirectLinkedMediaBlobFanoutRepository &&
        (mediaAttachmentRepo as OutgoingDirectLinkedMediaBlobFanoutRepository)
            .supportsDirectLinkedMediaBlobFanout;
    final admission = await resolveDirectMediaFanoutAdmission(
      mediaAttachmentRepository: mediaAttachmentRepo,
      contactAccountPeerId: authorPeerId,
      canServeLinkedFanout: canServeFanout,
    );
    if (admission.refuses) return ThoughtReplyStatus.failed;

    lease = mediaUploadInFlightTracker.tryClaimAll(
      [blobId],
      source: rearmStrict == null
          ? MediaUploadTriggerSource.foreground
          : MediaUploadTriggerSource.manual,
    );
    if (lease == null) return await currentStatus();

    final current = await messageRepo.getMessage(messageId);
    if (!mapEquals(current?.toMap(), existing?.toMap())) {
      return await currentStatus();
    }
    final timestamp = now().toUtc().toIso8601String();
    final authoredParent =
        existing ??
        ConversationMessage(
          id: messageId,
          contactPeerId: authorPeerId,
          senderPeerId: expectedSenderPeerId,
          text: '',
          timestamp: timestamp,
          status: 'sending',
          isIncoming: false,
          createdAt: timestamp,
          quotedMessageId: quoteId,
          directMediaCustodyIntentId: intentId,
        );
    late final MediaAttachment authoredAttachment;
    late final String absolutePath;
    if (rearmStrict case final failed?) {
      final path = failed.localPath;
      if (path == null ||
          path !=
              MediaFilePathConvention.relativePathForPendingUpload(
                messageId: messageId,
                attachmentId: blobId,
                mime: mime,
              ) ||
          messageRepo is! DirectManualUploadRetryRearmRepository) {
        return ThoughtReplyStatus.failed;
      }
      absolutePath = await mediaFileManager.resolveStoredPath(path);
      if (await eligibleContact() == null ||
          !(await (messageRepo as DirectManualUploadRetryRearmRepository)
              .rearmUploadRetryForManualRetry(
                messageId: messageId,
                attachments: [
                  ManualUploadRetryAttachmentExpectation(
                    attachmentId: blobId,
                    storedLocalPath: path,
                    downloadStatus: failed.downloadStatus,
                    uploadRetryCount: failed.uploadRetryCount ?? 0,
                  ),
                ],
              ))) {
        return ThoughtReplyStatus.failed;
      }
      authoredAttachment = failed.copyWith(
        downloadStatus: 'upload_pending',
        uploadRetryCount: 0,
      );
    } else {
      if ((await loadAttachments()).isNotEmpty) return await currentStatus();
      final path = MediaFilePathConvention.relativePathForPendingUpload(
        messageId: messageId,
        attachmentId: blobId,
        mime: mime,
      );
      copiedPath = path;
      final storedPath = await mediaFileManager.copyToDurableStorage(
        sourceFilePath: media!.file.path,
        messageId: messageId,
        attachmentId: blobId,
        mime: mime,
      );
      if (storedPath != path) {
        throw StateError('Unexpected pending sticker path');
      }
      absolutePath = await mediaFileManager.resolveStoredPath(path);
      final contact = await eligibleContact();
      if (contact == null ||
          (admission.allowsIncumbentSingleTarget &&
              (contact.mlKemPublicKey?.isEmpty ?? true))) {
        return ThoughtReplyStatus.failed;
      }
      authoredAttachment = MediaAttachment(
        id: blobId,
        messageId: messageId,
        mime: mime,
        size: media.budgetBytes,
        mediaType: 'image',
        width: media.width,
        height: media.height,
        durationMs: media.durationMs,
        createdAt: authoredParent.createdAt,
        localPath: path,
        downloadStatus: 'upload_pending',
        ownerLane: MediaOwnerLane.direct,
        stickerId: stickerId,
      );
      if (existing == null) await messageRepo.saveMessage(authoredParent);
      await mediaAttachmentRepo.saveAttachment(
        authoredAttachment,
        owner: MediaOwnerLane.direct,
      );
    }

    final parent = await messageRepo.getMessage(messageId);
    final attachments = await loadAttachments();
    if (parent == null ||
        !mapEquals(
          authoredParent.copyWith(status: parent.status).toMap(),
          parent.toMap(),
        ) ||
        attachments.length != 1 ||
        !_samePendingSticker(authoredAttachment, attachments.single) ||
        !isExactDirectMediaCustodyRetryProjection(
          message: parent,
          expectedSenderPeerId: expectedSenderPeerId,
          attachments: attachments,
        )) {
      throw StateError('Pending sticker ownership changed');
    }
    final attachment = attachments.single;
    if (copiedPath != null) {
      copiedPath = null;
      onMediaAdopted?.call();
      if (media!.file.path != absolutePath) {
        await deleteAppOwnedMediaFileIfExists(
          file: media.file,
          caller: 'sendThoughtStickerReply',
          reason: 'durable_sticker_source_adopted',
          swallowErrors: true,
        );
      }
    }

    final identity = await identityRepo.loadIdentity();
    if (identity?.peerId != expectedSenderPeerId) {
      return ThoughtReplyStatus.queued;
    }
    backgroundTask = await callBgBegin(bridge);

    Future<ThoughtReplyStatus> projectFailure(UploadMediaFailed failure) async {
      final authority = mediaAttachmentRepo;
      if (authority is OutgoingDirectMediaCustodyFailureRepository &&
          (authority as OutgoingDirectMediaCustodyFailureRepository)
              .supportsDirectMediaCustodyFailureProjection) {
        final result =
            await (authority as OutgoingDirectMediaCustodyFailureRepository)
                .projectDirectMediaCustodyUploadFailure(
                  expectedParent: parent,
                  expectedAttachments: attachments,
                  failedAttachmentId: blobId,
                  failure: failure,
                );
        if (result.applied) {
          requestRetry = !result.isTerminal;
          if (requestRetry &&
              failure.stage != UploadMediaStage.consumerBoundary &&
              existing == null) {
            final capture = activity.capture;
            if (capture != null) {
              try {
                activity.reporter?.markCaptured(capture);
              } catch (_) {}
            }
          }
          return result.isTerminal
              ? ThoughtReplyStatus.failed
              : ThoughtReplyStatus.queued;
        }
      }
      return await currentStatus();
    }

    final freshActivity = existing == null
        ? activity
        : (reporter: activity.reporter, capture: null);
    late final List<MediaAttachment> completed;
    if (strict) {
      final sources = [
        PreparedDirectMediaBlobSource(
          attachment: attachment,
          plaintextPath: absolutePath,
        ),
      ];
      final snapshot = admission.snapshot;
      bool hasDurableAuthority;
      if (snapshot != null) {
        final result = await coordinator!.prepareAndUploadFreshFanout(
          bridge: bridge,
          identityPeerId: expectedSenderPeerId,
          contactAccountPeerId: authorPeerId,
          snapshot: snapshot,
          expectedParent: parent,
          sources: sources,
          capturedActivity: freshActivity,
        );
        hasDurableAuthority = result.hasDurableAuthority;
        completed = result.attachments;
      } else {
        final result = await coordinator!.prepareAndUploadFresh(
          bridge: bridge,
          identityPeerId: expectedSenderPeerId,
          recipientPeerId: authorPeerId,
          expectedParent: parent,
          sources: sources,
          capturedActivity: freshActivity,
          onGenerationReady: p2pService.isLocalPeer(authorPeerId)
              ? (artifacts) async {
                  final artifact = artifacts.single;
                  await p2pService.sendLocalMedia(
                    peerId: authorPeerId,
                    filePath: artifact.absoluteCiphertextPath,
                    mime: kOpaqueMediaTransportMime,
                    mediaId: blobId,
                    fromPeerId: expectedSenderPeerId,
                    durationMs: attachment.durationMs,
                    enc: true,
                    encScheme: artifact.attachment.encryptionScheme,
                  );
                }
              : null,
        );
        hasDurableAuthority = result.hasDurableAuthority;
        completed = result.attachments;
      }
      if (completed.isEmpty) {
        if (hasDurableAuthority ||
            (await blobRepository.loadDirectMediaBlobCustodyForMessage(
              messageId,
            )).isNotEmpty) {
          requestRetry = true;
          return ThoughtReplyStatus.queued;
        }
        // Keep strict pre-publication refusals out of the generic legacy
        // automatic retry lane. A manual attempt can rearm this exact source.
        return await projectFailure(
          const UploadMediaFailed(
            stage: UploadMediaStage.consumerBoundary,
            disposition: UploadMediaDisposition.terminal,
            errorCode: 'THOUGHT_STICKER_PREPARATION_REFUSED',
          ),
        );
      }
    } else {
      EncryptedMediaArtifact? artifact;
      if (p2pService.isLocalPeer(authorPeerId)) {
        try {
          artifact = await prepareEncryptedMediaArtifactFn(
            bridge: bridge,
            localFilePath: absolutePath,
          );
          await p2pService.sendLocalMedia(
            peerId: authorPeerId,
            filePath: artifact.encryptedPath,
            mime: kOpaqueMediaTransportMime,
            mediaId: blobId,
            fromPeerId: expectedSenderPeerId,
            durationMs: attachment.durationMs,
            enc: true,
            encScheme: artifact.scheme,
          );
        } catch (_) {}
      }
      final outcome = await runUploadMedia(
        uploadMediaFn: uploadMediaFn,
        bridge: bridge,
        localFilePath: absolutePath,
        mime: mime,
        recipientPeerId: authorPeerId,
        mediaFileManager: mediaFileManager,
        blobId: blobId,
        width: attachment.width,
        height: attachment.height,
        durationMs: attachment.durationMs,
        preparedArtifact: artifact,
      );
      if (outcome is UploadMediaFailed) return await projectFailure(outcome);
      final uploaded = completeDirectMediaCustodyRetryAttachment(
        prepared: attachment,
        uploaded: outcome.attachmentOrNull!,
      );
      if (uploaded == null ||
          uploaded.localPath !=
              mediaFileManager.relativePathForAttachment(
                contactPeerId: authorPeerId,
                blobId: blobId,
                mime: mime,
              )) {
        return await projectFailure(
          const UploadMediaFailed(
            stage: UploadMediaStage.consumerBoundary,
            disposition: UploadMediaDisposition.terminal,
            errorCode: 'THOUGHT_STICKER_COMPLETION_MISMATCH',
          ),
        );
      }
      completed = [uploaded];
    }

    final recipient = await contactRepo.getContact(authorPeerId);
    final liveIdentity = await identityRepo.loadIdentity();
    if (liveIdentity?.peerId != expectedSenderPeerId ||
        recipient == null ||
        recipient.isBlocked ||
        recipient.isArchived) {
      return ThoughtReplyStatus.queued;
    }
    final (result, message) = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: authorPeerId,
      text: parent.text,
      senderPeerId: expectedSenderPeerId,
      senderUsername: liveIdentity!.username,
      messageId: messageId,
      timestamp: parent.timestamp,
      quotedMessageId: quoteId,
      dedupKey: parent.dedupKey,
      bridge: bridge,
      recipientMlKemPublicKey: recipient.mlKemPublicKey,
      mediaAttachments: completed,
      mediaAttachmentRepo: mediaAttachmentRepo,
      directEventFanout: directEventFanout,
      capturedActivity: strict
          ? (reporter: activity.reporter, capture: null)
          : freshActivity,
    );
    if (!strict &&
        (await messageRepo.getMessage(messageId))?.directMediaCustodyIntentId ==
            null) {
      try {
        await mediaFileManager.deletePendingUploadDir(messageId);
      } catch (_) {}
    }
    if (result != SendChatMessageResult.success) {
      final envelope = message?.wireEnvelope;
      if (envelope != null &&
          envelope.isNotEmpty &&
          (result == SendChatMessageResult.peerNotFound ||
              result == SendChatMessageResult.dialFailed ||
              result == SendChatMessageResult.sendFailed) &&
          messageRepo is OutgoingTransportMutationRepository) {
        await (messageRepo as OutgoingTransportMutationRepository)
            .settleOutgoingOrdinaryTransport(
              messageId: messageId,
              expectedContactPeerId: authorPeerId,
              expectedEnvelope: envelope,
              status: 'sent',
              transport: message?.transport,
              relayExpiresAt: null,
              mode: OutgoingOrdinarySettlementMode.live,
            );
      } else if (strict &&
          (await blobRepository.loadDirectMediaBlobCustodyForMessage(
            messageId,
          )).isNotEmpty) {
        requestRetry = true;
      } else {
        await messageRepo.conditionalTransitionStatus(
          messageId,
          fromStatus: 'sending',
          toStatus: 'failed',
        );
      }
    }
    return await currentStatus();
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'THOUGHT_STICKER_REPLY_FAILED',
      details: {'errorType': error.runtimeType.toString()},
    );
    try {
      final status = await currentStatus();
      if (status != ThoughtReplyStatus.queued) return status;
      final rows = await loadAttachments();
      if (rows.length == 1 && ownsSticker(rows.single)) {
        requestRetry =
            rows.single.downloadStatus == 'upload_pending' &&
            (!strict ||
                (await blobRepository.loadDirectMediaBlobCustodyForMessage(
                  messageId,
                )).isNotEmpty);
        return status;
      }
      if (rows.isEmpty && lease != null) {
        await messageRepo.conditionalTransitionStatus(
          messageId,
          fromStatus: 'sending',
          toStatus: 'failed',
        );
      }
    } catch (_) {}
    return ThoughtReplyStatus.failed;
  } finally {
    if (backgroundTask != null) await callBgEnd(bridge, backgroundTask);
    final path = copiedPath;
    if (path != null) {
      try {
        if (!(await loadAttachments()).any(
          (attachment) => attachment.localPath == path,
        )) {
          await mediaFileManager.deleteOwnedPendingUploadFilesForMessage(
            messageId: messageId,
            storedPaths: [path],
          );
        }
      } catch (_) {}
    }
    if (lease != null) mediaUploadInFlightTracker.release(lease);
    if (requestRetry) requestDirectUploadRetry();
  }
}

bool _samePendingSticker(MediaAttachment expected, MediaAttachment actual) =>
    mapEquals(
      expected.copyWith(uploadRetryCount: 0, downloadRetryCount: 0).toMap(),
      actual
          .copyWith(
            uploadRetryCount: actual.uploadRetryCount ?? 0,
            downloadRetryCount: actual.downloadRetryCount ?? 0,
          )
          .toMap(),
    );
