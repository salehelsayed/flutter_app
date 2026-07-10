import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

import 'share_target_selection.dart';

const _shareBatchUuid = Uuid();

enum ShareBatchTargetStatus { sent, queued, failed }

enum ShareBatchDeliveryPhase { uploading, sending }

class ShareBatchDeliveryProgress {
  final int sentBytes;
  final int totalBytes;
  final ShareBatchDeliveryPhase phase;

  const ShareBatchDeliveryProgress({
    required this.sentBytes,
    required this.totalBytes,
    required this.phase,
  });
}

typedef ShareBatchDeliveryProgressCallback =
    void Function(ShareBatchDeliveryProgress progress);

class ShareBatchUploadHooks {
  final void Function({required String blobId, required int budgetBytes})
  _onStarted;
  final void Function({required bool succeeded}) _onSettled;
  final void Function() _onSending;

  const ShareBatchUploadHooks({
    required void Function({required String blobId, required int budgetBytes})
    onStarted,
    required void Function({required bool succeeded}) onSettled,
    required void Function() onSending,
  }) : _onStarted = onStarted,
       _onSettled = onSettled,
       _onSending = onSending;

  static final none = ShareBatchUploadHooks(
    onStarted: ({required blobId, required budgetBytes}) {},
    onSettled: ({required succeeded}) {},
    onSending: () {},
  );

  void started({required String blobId, required int budgetBytes}) =>
      _onStarted(blobId: blobId, budgetBytes: budgetBytes);

  void settled({required bool succeeded}) => _onSettled(succeeded: succeeded);

  void sending() => _onSending();
}

class ShareBatchTargetResult {
  final ShareTargetSelection target;
  final ShareBatchTargetStatus status;
  final String detail;

  const ShareBatchTargetResult({
    required this.target,
    required this.status,
    required this.detail,
  });
}

class ShareBatchDeliveryResult {
  final List<ShareBatchTargetResult> results;
  final int skippedOversizedGifCount;
  final String? skippedOversizedGifReason;

  const ShareBatchDeliveryResult({
    required this.results,
    this.skippedOversizedGifCount = 0,
    this.skippedOversizedGifReason,
  });

  int get sentCount => results
      .where((result) => result.status == ShareBatchTargetStatus.sent)
      .length;

  int get queuedCount => results
      .where((result) => result.status == ShareBatchTargetStatus.queued)
      .length;

  int get failureCount => results
      .where((result) => result.status == ShareBatchTargetStatus.failed)
      .length;

  bool get hasFailures => failureCount > 0;

  bool get hasCompletions => sentCount + queuedCount > 0;

  bool get hasSkippedOversizedGifs => skippedOversizedGifCount > 0;

  Set<String> get failedTargetKeys => results
      .where((result) => result.status == ShareBatchTargetStatus.failed)
      .map((result) => result.target.key)
      .toSet();
}

abstract class ShareBatchDeliveryCoordinator {
  Future<ShareBatchDeliveryResult> deliver({
    required ShareIntent shareIntent,
    required List<ShareTargetSelection> targets,
    ShareBatchDeliveryProgressCallback? onProgress,
  });

  /// 236: one explicit accepted group-media Forward. Unlike [deliver], the
  /// source is a stable `(groupId, messageId, attachmentId)` identity that is
  /// reloaded and hash-verified at dispatch time, and every destination is
  /// reloaded from its repository immediately before its upload — a missing
  /// or ineligible target is a failed result, never a stale-picker fallback.
  Future<ShareBatchDeliveryResult> deliverGroupMediaForward({
    required GroupMediaForwardRequest request,
    String? caption,
    required List<ShareTargetSelection> targets,
  });
}

typedef ProcessSharedMediaFn =
    Future<ProcessedShareMediaBatch> Function(ShareIntent shareIntent);

class ProcessedShareMediaBatch {
  final List<PendingComposerMedia> processedMedia;
  final int skippedOversizedGifCount;
  final String? skippedOversizedGifReason;

  const ProcessedShareMediaBatch({
    required this.processedMedia,
    this.skippedOversizedGifCount = 0,
    this.skippedOversizedGifReason,
  });
}

typedef SendToContactFn =
    Future<ShareBatchTargetResult> Function({
      required IdentityModel identity,
      required ShareIntent shareIntent,
      required ContactModel contact,
      required List<PendingComposerMedia> processedMedia,
      required ShareBatchUploadHooks uploadHooks,
    });

typedef SendToGroupFn =
    Future<ShareBatchTargetResult> Function({
      required IdentityModel identity,
      required ShareIntent shareIntent,
      required GroupModel group,
      required List<PendingComposerMedia> processedMedia,
      required ShareBatchUploadHooks uploadHooks,
    });

class DefaultShareBatchDeliveryCoordinator
    implements ShareBatchDeliveryCoordinator {
  final IdentityRepository identityRepository;
  final ContactRepository contactRepository;
  final MessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final GroupRepository? groupRepository;
  final GroupMessageRepository? groupMessageRepository;
  final GroupInviteDeliveryAttemptRepository?
  groupInviteDeliveryAttemptRepository;
  final Bridge bridge;
  final P2PService p2pService;
  final MediaFileManager mediaFileManager;
  final ImageProcessor imageProcessor;
  final ImageQualityPreference qualityPreference;
  final ImageQualityPreference videoQualityPreference;
  final ProcessSharedMediaFn? processSharedMediaFn;
  final SendToContactFn? sendToContactFn;
  final SendToGroupFn? sendToGroupFn;
  final Stream<Map<String, dynamic>>? mediaUploadProgressEvents;

  /// 236 test seam: overrides the dispatch-time forward source gate. The
  /// production default is built from this coordinator's own repositories.
  final GroupMediaForwardSourceGate? groupMediaForwardSourceGate;

  const DefaultShareBatchDeliveryCoordinator({
    required this.identityRepository,
    required this.contactRepository,
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.groupRepository,
    required this.groupMessageRepository,
    this.groupInviteDeliveryAttemptRepository,
    required this.bridge,
    required this.p2pService,
    required this.mediaFileManager,
    required this.imageProcessor,
    this.qualityPreference = ImageQualityPreference.compressed,
    this.videoQualityPreference = ImageQualityPreference.compressed,
    this.processSharedMediaFn,
    this.sendToContactFn,
    this.sendToGroupFn,
    this.mediaUploadProgressEvents,
    this.groupMediaForwardSourceGate,
  });

  String? get _currentSenderDeviceId {
    final peerId = p2pService.currentState.peerId?.trim();
    return peerId == null || peerId.isEmpty ? null : peerId;
  }

  @override
  Future<ShareBatchDeliveryResult> deliver({
    required ShareIntent shareIntent,
    required List<ShareTargetSelection> targets,
    ShareBatchDeliveryProgressCallback? onProgress,
  }) async {
    if (targets.isEmpty) {
      return const ShareBatchDeliveryResult(results: []);
    }

    final identity = await identityRepository.loadIdentity();
    if (identity == null) {
      return ShareBatchDeliveryResult(
        results: targets
            .map(
              (target) => ShareBatchTargetResult(
                target: target,
                status: ShareBatchTargetStatus.failed,
                detail: 'Identity unavailable.',
              ),
            )
            .toList(growable: false),
      );
    }

    final processedBatch = await (processSharedMediaFn ?? _processSharedMedia)(
      shareIntent,
    );
    final processedMedia = processedBatch.processedMedia;
    final results = <ShareBatchTargetResult>[];

    var bytesPerTarget = 0;
    for (final media in processedMedia) {
      bytesPerTarget += media.budgetBytes;
    }
    final totalBytes = bytesPerTarget * targets.length;
    final progressTracker = onProgress == null || totalBytes <= 0
        ? null
        : _ShareBatchProgressTracker(
            totalBytes: totalBytes,
            onProgress: onProgress,
          );
    final uploadHooks = progressTracker?.hooks ?? ShareBatchUploadHooks.none;
    final progressSubscription = progressTracker == null
        ? null
        : (mediaUploadProgressEvents ?? mediaUploadProgressStream).listen(
            progressTracker.onUploadEvent,
          );

    try {
      for (final target in targets) {
        // 236 TC-236-03E: each target is its own exception boundary — one
        // thrown target becomes one typed failed result and can never abort
        // the targets after it.
        ShareBatchTargetResult result;
        try {
          result = switch (target.kind) {
            ShareTargetSelectionKind.contact =>
              await (sendToContactFn ?? _sendToContact)(
                identity: identity,
                shareIntent: shareIntent,
                contact: target.requireContact,
                processedMedia: processedMedia,
                uploadHooks: uploadHooks,
              ),
            ShareTargetSelectionKind.group =>
              await (sendToGroupFn ?? _sendToGroup)(
                identity: identity,
                shareIntent: shareIntent,
                group: target.requireGroup,
                processedMedia: processedMedia,
                uploadHooks: uploadHooks,
              ),
          };
        } catch (_) {
          uploadHooks.settled(succeeded: false);
          result = ShareBatchTargetResult(
            target: target,
            status: ShareBatchTargetStatus.failed,
            detail: 'Share failed.',
          );
        }
        results.add(result);
      }
    } finally {
      await progressSubscription?.cancel();
    }

    return ShareBatchDeliveryResult(
      results: results,
      skippedOversizedGifCount: processedBatch.skippedOversizedGifCount,
      skippedOversizedGifReason: processedBatch.skippedOversizedGifReason,
    );
  }

  @override
  Future<ShareBatchDeliveryResult> deliverGroupMediaForward({
    required GroupMediaForwardRequest request,
    String? caption,
    required List<ShareTargetSelection> targets,
  }) async {
    if (targets.isEmpty) {
      return const ShareBatchDeliveryResult(results: []);
    }

    ShareBatchDeliveryResult failAll(String detail) {
      return ShareBatchDeliveryResult(
        results: targets
            .map(
              (target) => ShareBatchTargetResult(
                target: target,
                status: ShareBatchTargetStatus.failed,
                detail: detail,
              ),
            )
            .toList(growable: false),
      );
    }

    final identity = await identityRepository.loadIdentity();
    if (identity == null) {
      return failAll('Identity unavailable.');
    }
    final groupRepo = groupRepository;
    final groupMsgRepo = groupMessageRepository;
    if (groupRepo == null || groupMsgRepo == null) {
      return failAll('Group forwarding is unavailable.');
    }

    // Dispatch-time source verification: reload the exact parent and
    // group-owned row and hash the CURRENT file before any target lookup,
    // source read, or upload.
    final gate =
        groupMediaForwardSourceGate ??
        GroupMediaForwardSourceGate(
          groupRepository: groupRepo,
          messageRepository: groupMsgRepo,
          mediaAttachmentRepository: mediaAttachmentRepository,
          mediaFileManager: mediaFileManager,
        );
    final sourceResult = await gate.verify(request);
    final source = sourceResult.source;
    if (source == null) {
      return failAll('This media can no longer be forwarded.');
    }

    final trimmedCaption = caption?.trim() ?? '';
    final shareIntent = ShareIntent(
      type: trimmedCaption.isEmpty
          ? ShareIntentType.files
          : ShareIntentType.mixed,
      text: trimmedCaption.isEmpty ? null : trimmedCaption,
      filePaths: [source.resolvedPath],
      forwardProvenance: request.provenance,
    );

    // Read/process the verified source bytes once; every destination below
    // still gets its own fresh attachment id, encryption, and upload.
    final processedBatch = await (processSharedMediaFn ?? _processSharedMedia)(
      shareIntent,
    );
    final processedMedia = processedBatch.processedMedia;
    final results = <ShareBatchTargetResult>[];
    for (final target in targets) {
      results.add(
        await _deliverForwardTarget(
          identity: identity,
          shareIntent: shareIntent,
          target: target,
          processedMedia: processedMedia,
        ),
      );
    }

    return ShareBatchDeliveryResult(
      results: results,
      skippedOversizedGifCount: processedBatch.skippedOversizedGifCount,
      skippedOversizedGifReason: processedBatch.skippedOversizedGifReason,
    );
  }

  /// One forward destination: reload the CURRENT target from its repository
  /// (a missing target is failure, never stale-picker fallback), require its
  /// current authority, and isolate any thrown error to this target alone.
  Future<ShareBatchTargetResult> _deliverForwardTarget({
    required IdentityModel identity,
    required ShareIntent shareIntent,
    required ShareTargetSelection target,
    required List<PendingComposerMedia> processedMedia,
  }) async {
    ShareBatchTargetResult failed(String detail) {
      return ShareBatchTargetResult(
        target: target,
        status: ShareBatchTargetStatus.failed,
        detail: detail,
      );
    }

    try {
      switch (target.kind) {
        case ShareTargetSelectionKind.contact:
          final current = await contactRepository.getContact(
            target.requireContact.peerId,
          );
          if (current == null) {
            return failed('Contact is no longer available.');
          }
          final mlKemKey = current.mlKemPublicKey?.trim();
          if (mlKemKey == null || mlKemKey.isEmpty) {
            return failed('Contact is missing required encryption support.');
          }
          return await (sendToContactFn ?? _sendToContact)(
            identity: identity,
            shareIntent: shareIntent,
            contact: current,
            processedMedia: processedMedia,
            uploadHooks: ShareBatchUploadHooks.none,
          );
        case ShareTargetSelectionKind.group:
          final groupRepo = groupRepository!;
          final current = await groupRepo.getGroup(target.requireGroup.id);
          if (current == null) {
            return failed('Group was not found.');
          }
          // Destination-lane filter: internal group-media forwarding posts
          // only to discussion groups; announcement/QA authoring stays with
          // its dedicated plans even for admins.
          if (current.type != GroupType.chat) {
            return failed('You can only forward to discussion groups.');
          }
          if (current.isArchived || current.isDissolved) {
            return failed('You no longer have permission to post there.');
          }
          final latestKey = await groupRepo.getLatestKey(current.id);
          if (latestKey == null) {
            return failed('You no longer have permission to post there.');
          }
          final members = await groupRepo.getMembers(current.id);
          final isMember = members.any(
            (member) => member.peerId == identity.peerId,
          );
          if (!isMember) {
            return failed('You no longer have permission to post there.');
          }
          return await (sendToGroupFn ?? _sendToGroup)(
            identity: identity,
            shareIntent: shareIntent,
            group: current,
            processedMedia: processedMedia,
            uploadHooks: ShareBatchUploadHooks.none,
          );
      }
    } catch (_) {
      return failed('Share failed.');
    }
  }

  Future<ProcessedShareMediaBatch> _processSharedMedia(
    ShareIntent shareIntent,
  ) async {
    if (!shareIntent.hasFiles) {
      return const ProcessedShareMediaBatch(processedMedia: []);
    }

    final processed = <PendingComposerMedia>[];
    var skippedOversizedGifCount = 0;
    for (final path in shareIntent.filePaths) {
      PendingComposerMedia prepared;
      try {
        final file = File(path);
        if (!file.existsSync()) {
          continue;
        }
        prepared = await preparePendingComposerMedia(
          inputPath: path,
          imageProcessor: imageProcessor,
          imageQualityPreference: qualityPreference,
          videoQualityPreference: videoQualityPreference,
        );
      } catch (_) {
        final file = File(path);
        if (!file.existsSync()) {
          continue;
        }
        prepared = PendingComposerMedia(
          file: file,
          budgetBytes: file.lengthSync(),
        );
      }
      // Per-type SEND size gate on FINAL (post-processing) budget bytes (OQ-2 —
      // the per-type cap table now applies to share-batch too). Replaces the old
      // raw pre-compression GIF-only lengthSync check (INV-SZ-2). Oversized media
      // is skipped per-file and surfaced via the batch summary; since images and
      // video are compressed before this point, GIF is the dominant survivor of
      // an oversize, so the summary copy stays GIF-worded.
      final sizeValidation = GroupMediaSizePolicy.validateSize(
        sizeBytes: prepared.budgetBytes,
        mime: _mimeFromPath(prepared.file.path),
      );
      if (!sizeValidation.isValid) {
        skippedOversizedGifCount++;
        continue;
      }
      processed.add(prepared);
    }

    return ProcessedShareMediaBatch(
      processedMedia: processed,
      skippedOversizedGifCount: skippedOversizedGifCount,
      // Media-agnostic: the per-type gate skips ANY oversized type (image,
      // video, audio, file, gif), so the summary must not claim "GIF".
      skippedOversizedGifReason: skippedOversizedGifCount > 0
          ? 'Some attachments were too large and were skipped.'
          : null,
    );
  }

  Future<ShareBatchTargetResult> _sendToContact({
    required IdentityModel identity,
    required ShareIntent shareIntent,
    required ContactModel contact,
    required List<PendingComposerMedia> processedMedia,
    required ShareBatchUploadHooks uploadHooks,
  }) async {
    final resolvedContact =
        await contactRepository.getContact(contact.peerId) ?? contact;
    final attachments = <MediaAttachment>[];

    for (final media in processedMedia) {
      final mime = _mimeFromPath(media.file.path);
      final attachmentId = _shareBatchUuid.v4();
      // LAN best-effort first, but the relay upload below ALWAYS runs
      // (composer semantics): it is the durable recovery copy AND the
      // source of the attachment's encryption metadata. The old
      // LAN-success `continue` skipped uploadMedia entirely, building a
      // metadata-free attachment the G5 send gate now rejects (112 Phase
      // 2.4). Phase 4: encrypt once — the LAN leg streams the SAME
      // ciphertext artifact the relay upload consumes, never the raw
      // shared file.
      EncryptedMediaArtifact? preparedArtifact;
      if (p2pService.isLocalPeer(resolvedContact.peerId)) {
        try {
          preparedArtifact = await prepareEncryptedMediaArtifact(
            bridge: bridge,
            localFilePath: media.file.path,
          );
          await p2pService.sendLocalMedia(
            peerId: resolvedContact.peerId,
            filePath: preparedArtifact.encryptedPath,
            mime: kOpaqueMediaTransportMime,
            mediaId: attachmentId,
            fromPeerId: identity.peerId,
            durationMs: media.durationMs,
            enc: true,
            encScheme: preparedArtifact.scheme,
          );
        } catch (_) {
          // Fail closed on the LAN leg — never stream the raw shared file.
          preparedArtifact = null;
        }
      }

      uploadHooks.started(blobId: attachmentId, budgetBytes: media.budgetBytes);
      MediaAttachment? uploaded;
      try {
        uploaded = await uploadMedia(
          bridge: bridge,
          localFilePath: media.file.path,
          mime: mime,
          recipientPeerId: resolvedContact.peerId,
          mediaFileManager: mediaFileManager,
          width: media.width,
          height: media.height,
          durationMs: media.durationMs,
          blobId: attachmentId,
          preparedArtifact: preparedArtifact,
        );
      } finally {
        uploadHooks.settled(succeeded: uploaded != null);
      }
      if (uploaded == null) {
        return ShareBatchTargetResult(
          target: ShareTargetSelection.contact(resolvedContact),
          status: ShareBatchTargetStatus.failed,
          detail: 'Media upload failed.',
        );
      }
      attachments.add(uploaded);
    }

    final text = shareIntent.text ?? '';
    uploadHooks.sending();
    final (result, message) = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepository,
      targetPeerId: resolvedContact.peerId,
      text: text,
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      bridge: bridge,
      recipientMlKemPublicKey: resolvedContact.mlKemPublicKey,
      mediaAttachments: attachments.isEmpty ? null : attachments,
      mediaAttachmentRepo: mediaAttachmentRepository,
      dedupKey: shareIntent.forwardProvenance?.operationDedupKey,
      isForwarded: shareIntent.forwardProvenance != null,
    );

    return ShareBatchTargetResult(
      target: ShareTargetSelection.contact(resolvedContact),
      status: switch (result) {
        SendChatMessageResult.success => ShareBatchTargetStatus.sent,
        _ when message != null => ShareBatchTargetStatus.queued,
        _ => ShareBatchTargetStatus.failed,
      },
      detail: switch (result) {
        SendChatMessageResult.success => 'Sent.',
        SendChatMessageResult.nodeNotRunning =>
          'Saved locally for later retry.',
        SendChatMessageResult.peerNotFound => 'Saved locally for later retry.',
        SendChatMessageResult.dialFailed => 'Saved locally for later retry.',
        SendChatMessageResult.sendFailed when message != null =>
          'Saved locally for later retry.',
        SendChatMessageResult.invalidMessage => 'Nothing valid to share.',
        SendChatMessageResult.encryptionRequired =>
          'Contact is missing required encryption support.',
        _ => 'Share failed.',
      },
    );
  }

  Future<ShareBatchTargetResult> _sendToGroup({
    required IdentityModel identity,
    required ShareIntent shareIntent,
    required GroupModel group,
    required List<PendingComposerMedia> processedMedia,
    required ShareBatchUploadHooks uploadHooks,
  }) async {
    final groupRepo = groupRepository;
    final msgRepo = groupMessageRepository;
    if (groupRepo == null || msgRepo == null) {
      return ShareBatchTargetResult(
        target: ShareTargetSelection.group(group),
        status: ShareBatchTargetStatus.failed,
        detail: 'Group sharing is unavailable.',
      );
    }

    String? bgTaskId;
    try {
      bgTaskId = await callBgBegin(bridge);
      final resolvedGroup = await groupRepo.getGroup(group.id) ?? group;
      final allowedPeers = (await groupRepo.getMembers(
        resolvedGroup.id,
      )).map((member) => member.peerId).toList(growable: false);
      final attachments = <MediaAttachment>[];

      for (final media in processedMedia) {
        final mime = _mimeFromPath(media.file.path);
        final attachmentId = _shareBatchUuid.v4();
        uploadHooks.started(
          blobId: attachmentId,
          budgetBytes: media.budgetBytes,
        );
        MediaAttachment? uploaded;
        try {
          uploaded = await uploadMedia(
            bridge: bridge,
            localFilePath: media.file.path,
            mime: mime,
            recipientPeerId: resolvedGroup.id,
            mediaFileManager: mediaFileManager,
            width: media.width,
            height: media.height,
            durationMs: media.durationMs,
            allowedPeers: allowedPeers,
            blobId: attachmentId,
          );
        } finally {
          uploadHooks.settled(succeeded: uploaded != null);
        }
        if (uploaded == null) {
          return ShareBatchTargetResult(
            target: ShareTargetSelection.group(resolvedGroup),
            status: ShareBatchTargetStatus.failed,
            detail: 'Media upload failed.',
          );
        }
        attachments.add(
          uploaded.copyWith(id: attachmentId, downloadStatus: 'done'),
        );
      }

      final senderDeviceId = _currentSenderDeviceId;
      uploadHooks.sending();
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: resolvedGroup.id,
        text: shareIntent.text ?? '',
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        senderDeviceId: senderDeviceId,
        senderTransportPeerId: senderDeviceId,
        mediaAttachments: attachments.isEmpty ? null : attachments,
        mediaAttachmentRepo: mediaAttachmentRepository,
        inviteDeliveryAttemptRepo: groupInviteDeliveryAttemptRepository,
        // Only an explicit internal Forward carries provenance; OS shares
        // and ordinary sends stay unmarked (TC-236-13).
        isForwarded: shareIntent.forwardProvenance != null,
      );
      final pendingCompletion =
          result == SendGroupMessageResult.success &&
          message?.status == 'pending';

      return ShareBatchTargetResult(
        target: ShareTargetSelection.group(resolvedGroup),
        status: switch (result) {
          SendGroupMessageResult.success when pendingCompletion =>
            ShareBatchTargetStatus.queued,
          SendGroupMessageResult.success => ShareBatchTargetStatus.sent,
          SendGroupMessageResult.successNoPeers =>
            ShareBatchTargetStatus.queued,
          // 210b: durably queued while the sender is offline (self-healing).
          SendGroupMessageResult.queuedOffline => ShareBatchTargetStatus.queued,
          _ when message != null => ShareBatchTargetStatus.queued,
          _ => ShareBatchTargetStatus.failed,
        },
        detail: switch (result) {
          SendGroupMessageResult.success when pendingCompletion =>
            'Stored while group delivery finishes.',
          SendGroupMessageResult.success => 'Sent.',
          SendGroupMessageResult.successNoPeers =>
            'Stored for offline group delivery.',
          SendGroupMessageResult.queuedOffline =>
            "Stored — will send when you're back online.",
          SendGroupMessageResult.groupNotFound => 'Group was not found.',
          SendGroupMessageResult.unauthorized =>
            'You no longer have permission to post there.',
          SendGroupMessageResult.error when message != null =>
            'Saved for retry.',
          _ => 'Share failed.',
        },
      );
    } finally {
      await callBgEnd(bridge, bgTaskId);
    }
  }
}

class _ShareBatchProgressTracker {
  final int totalBytes;
  final ShareBatchDeliveryProgressCallback onProgress;

  String? _activeBlobId;
  int _activeBudgetBytes = 0;
  int _currentBytes = 0;
  int _completedBytes = 0;

  _ShareBatchProgressTracker({
    required this.totalBytes,
    required this.onProgress,
  });

  late final ShareBatchUploadHooks hooks = ShareBatchUploadHooks(
    onStarted: _onUploadStarted,
    onSettled: _onUploadSettled,
    onSending: _onSending,
  );

  void onUploadEvent(Map<String, dynamic> event) {
    final activeBlobId = _activeBlobId;
    if (activeBlobId == null || event['id'] != activeBlobId) {
      return;
    }
    final rawSentBytes = event['sentBytes'];
    if (rawSentBytes is! num) {
      return;
    }
    final clamped = rawSentBytes.toInt().clamp(0, _activeBudgetBytes).toInt();
    if (clamped <= _currentBytes) {
      return;
    }
    _currentBytes = clamped;
    _emit(ShareBatchDeliveryPhase.uploading);
  }

  void _onUploadStarted({required String blobId, required int budgetBytes}) {
    if (_activeBlobId != null) {
      _onUploadSettled(succeeded: false);
    }
    _activeBlobId = blobId;
    _activeBudgetBytes = budgetBytes < 0 ? 0 : budgetBytes;
    _currentBytes = 0;
    _emit(ShareBatchDeliveryPhase.uploading);
  }

  void _onUploadSettled({required bool succeeded}) {
    if (_activeBlobId == null) {
      return;
    }
    final settledBytes = succeeded ? _activeBudgetBytes : _currentBytes;

    // Clear the active id before folding completion so a late synchronous
    // final event cannot be adopted or counted twice.
    _activeBlobId = null;
    _activeBudgetBytes = 0;
    _currentBytes = 0;
    _completedBytes = (_completedBytes + settledBytes)
        .clamp(0, totalBytes)
        .toInt();
    _emit(ShareBatchDeliveryPhase.uploading);
  }

  void _onSending() {
    _emit(ShareBatchDeliveryPhase.sending);
  }

  void _emit(ShareBatchDeliveryPhase phase) {
    final sentBytes = (_completedBytes + _currentBytes)
        .clamp(0, totalBytes)
        .toInt();
    onProgress(
      ShareBatchDeliveryProgress(
        sentBytes: sentBytes,
        totalBytes: totalBytes,
        phase: phase,
      ),
    );
  }
}

String _mimeFromPath(String path) {
  final ext = path.split('.').last.toLowerCase();
  const map = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'avi': 'video/x-msvideo',
    'mkv': 'video/x-matroska',
    'm4v': 'video/x-m4v',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
  };
  return map[ext] ?? 'application/octet-stream';
}
