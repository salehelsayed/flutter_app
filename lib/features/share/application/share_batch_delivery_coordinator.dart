import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
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
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

import 'share_target_selection.dart';

const _shareBatchUuid = Uuid();

enum ShareBatchTargetStatus { sent, queued, failed }

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

  const ShareBatchDeliveryResult({required this.results});

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

  Set<String> get failedTargetKeys => results
      .where((result) => result.status == ShareBatchTargetStatus.failed)
      .map((result) => result.target.key)
      .toSet();
}

abstract class ShareBatchDeliveryCoordinator {
  Future<ShareBatchDeliveryResult> deliver({
    required ShareIntent shareIntent,
    required List<ShareTargetSelection> targets,
  });
}

typedef ProcessSharedMediaFn =
    Future<List<PendingComposerMedia>> Function(ShareIntent shareIntent);

typedef SendToContactFn =
    Future<ShareBatchTargetResult> Function({
      required IdentityModel identity,
      required ShareIntent shareIntent,
      required ContactModel contact,
      required List<PendingComposerMedia> processedMedia,
    });

typedef SendToGroupFn =
    Future<ShareBatchTargetResult> Function({
      required IdentityModel identity,
      required ShareIntent shareIntent,
      required GroupModel group,
      required List<PendingComposerMedia> processedMedia,
    });

class DefaultShareBatchDeliveryCoordinator
    implements ShareBatchDeliveryCoordinator {
  final IdentityRepository identityRepository;
  final ContactRepository contactRepository;
  final MessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final GroupRepository? groupRepository;
  final GroupMessageRepository? groupMessageRepository;
  final Bridge bridge;
  final P2PService p2pService;
  final MediaFileManager mediaFileManager;
  final ImageProcessor imageProcessor;
  final ImageQualityPreference qualityPreference;
  final ImageQualityPreference videoQualityPreference;
  final ProcessSharedMediaFn? processSharedMediaFn;
  final SendToContactFn? sendToContactFn;
  final SendToGroupFn? sendToGroupFn;

  const DefaultShareBatchDeliveryCoordinator({
    required this.identityRepository,
    required this.contactRepository,
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.groupRepository,
    required this.groupMessageRepository,
    required this.bridge,
    required this.p2pService,
    required this.mediaFileManager,
    required this.imageProcessor,
    this.qualityPreference = ImageQualityPreference.compressed,
    this.videoQualityPreference = ImageQualityPreference.compressed,
    this.processSharedMediaFn,
    this.sendToContactFn,
    this.sendToGroupFn,
  });

  @override
  Future<ShareBatchDeliveryResult> deliver({
    required ShareIntent shareIntent,
    required List<ShareTargetSelection> targets,
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

    final processedMedia = await (processSharedMediaFn ?? _processSharedMedia)(
      shareIntent,
    );
    final results = <ShareBatchTargetResult>[];

    for (final target in targets) {
      final result = switch (target.kind) {
        ShareTargetSelectionKind.contact =>
          await (sendToContactFn ?? _sendToContact)(
            identity: identity,
            shareIntent: shareIntent,
            contact: target.requireContact,
            processedMedia: processedMedia,
          ),
        ShareTargetSelectionKind.group => await (sendToGroupFn ?? _sendToGroup)(
          identity: identity,
          shareIntent: shareIntent,
          group: target.requireGroup,
          processedMedia: processedMedia,
        ),
      };
      results.add(result);
    }

    return ShareBatchDeliveryResult(results: results);
  }

  Future<List<PendingComposerMedia>> _processSharedMedia(
    ShareIntent shareIntent,
  ) async {
    if (!shareIntent.hasFiles) {
      return const [];
    }

    final processed = <PendingComposerMedia>[];
    for (final path in shareIntent.filePaths) {
      try {
        final file = File(path);
        if (!file.existsSync()) {
          continue;
        }
        processed.add(
          await preparePendingComposerMedia(
            inputPath: path,
            imageProcessor: imageProcessor,
            imageQualityPreference: qualityPreference,
            videoQualityPreference: videoQualityPreference,
          ),
        );
      } catch (_) {
        final file = File(path);
        if (!file.existsSync()) {
          continue;
        }
        processed.add(
          PendingComposerMedia(file: file, budgetBytes: file.lengthSync()),
        );
      }
    }

    return processed;
  }

  Future<ShareBatchTargetResult> _sendToContact({
    required IdentityModel identity,
    required ShareIntent shareIntent,
    required ContactModel contact,
    required List<PendingComposerMedia> processedMedia,
  }) async {
    final resolvedContact =
        await contactRepository.getContact(contact.peerId) ?? contact;
    final attachments = <MediaAttachment>[];

    for (final media in processedMedia) {
      final mime = _mimeFromPath(media.file.path);
      final attachmentId = _shareBatchUuid.v4();
      final fileSize = File(media.file.path).lengthSync();
      final isLocalSuccess =
          p2pService.isLocalPeer(resolvedContact.peerId) &&
          await p2pService.sendLocalMedia(
            peerId: resolvedContact.peerId,
            filePath: media.file.path,
            mime: mime,
            mediaId: attachmentId,
            fromPeerId: identity.peerId,
            durationMs: media.durationMs,
          );

      if (isLocalSuccess) {
        attachments.add(
          MediaAttachment(
            id: attachmentId,
            messageId: '',
            mime: mime,
            size: fileSize,
            mediaType: MediaAttachment.mediaTypeFromMime(mime),
            width: media.width,
            height: media.height,
            durationMs: media.durationMs,
            localPath: media.file.path,
            downloadStatus: 'done',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        continue;
      }

      final uploaded = await uploadMedia(
        bridge: bridge,
        localFilePath: media.file.path,
        mime: mime,
        recipientPeerId: resolvedContact.peerId,
        mediaFileManager: mediaFileManager,
        width: media.width,
        height: media.height,
        durationMs: media.durationMs,
        blobId: attachmentId,
      );
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

    final resolvedGroup = await groupRepo.getGroup(group.id) ?? group;
    final allowedPeers = (await groupRepo.getMembers(
      resolvedGroup.id,
    )).map((member) => member.peerId).toList(growable: false);
    final attachments = <MediaAttachment>[];

    for (final media in processedMedia) {
      final mime = _mimeFromPath(media.file.path);
      final attachmentId = _shareBatchUuid.v4();
      final uploaded = await uploadMedia(
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
      mediaAttachments: attachments.isEmpty ? null : attachments,
      mediaAttachmentRepo: mediaAttachmentRepository,
    );

    return ShareBatchTargetResult(
      target: ShareTargetSelection.group(resolvedGroup),
      status: switch (result) {
        SendGroupMessageResult.success => ShareBatchTargetStatus.sent,
        SendGroupMessageResult.successNoPeers => ShareBatchTargetStatus.queued,
        _ when message != null => ShareBatchTargetStatus.queued,
        _ => ShareBatchTargetStatus.failed,
      },
      detail: switch (result) {
        SendGroupMessageResult.success => 'Sent.',
        SendGroupMessageResult.successNoPeers =>
          'Stored for offline group delivery.',
        SendGroupMessageResult.groupNotFound => 'Group was not found.',
        SendGroupMessageResult.unauthorized =>
          'You no longer have permission to post there.',
        SendGroupMessageResult.error when message != null => 'Saved for retry.',
        _ => 'Share failed.',
      },
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
