import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

class _PreparedGroupRetryUpload {
  final MediaAttachment pendingAttachment;
  final String absolutePath;

  const _PreparedGroupRetryUpload({
    required this.pendingAttachment,
    required this.absolutePath,
  });
}

/// Re-uploads any group attachment rows with downloadStatus='upload_pending',
/// grouped by messageId, then re-sends the full message once per group message.
///
/// This mirrors the durable retry contract used by the group composer:
/// - only group-owned rows are processed
/// - done attachments are preserved
/// - only upload_pending rows are re-uploaded
/// - the original messageId/timestamp are reused on send
/// - durable pending_uploads copies are used when available
Future<int> retryIncompleteGroupUploads({
  required GroupRepository groupRepo,
  required GroupMessageRepository groupMsgRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepo,
  UploadMediaFn uploadMediaFn = uploadMedia,
  MediaFileManager? mediaFileManager,
}) async {
  final retryStopwatch = Stopwatch()..start();
  void emitRetryTiming({
    required String outcome,
    required int attachmentCount,
    required int messageCount,
    required int succeeded,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_TIMING',
      details: {
        'elapsedMs': retryStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'attachmentCount': attachmentCount,
        'messageCount': messageCount,
        'succeeded': succeeded,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_START',
    details: {},
  );

  final pendingAttachments = await mediaAttachmentRepo
      .getUploadPendingAttachments();
  if (pendingAttachments.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_NONE',
      details: {},
    );
    emitRetryTiming(
      outcome: 'none',
      attachmentCount: 0,
      messageCount: 0,
      succeeded: 0,
    );
    return 0;
  }

  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_NO_IDENTITY',
      details: {},
    );
    emitRetryTiming(
      outcome: 'no_identity',
      attachmentCount: pendingAttachments.length,
      messageCount: 0,
      succeeded: 0,
    );
    return 0;
  }

  final byMessageId = <String, List<MediaAttachment>>{};
  for (final attachment in pendingAttachments) {
    byMessageId.putIfAbsent(attachment.messageId, () => []).add(attachment);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_FOUND',
    details: {
      'attachmentCount': pendingAttachments.length,
      'messageCount': byMessageId.length,
    },
  );

  var successCount = 0;

  for (final entry in byMessageId.entries) {
    final messageId = entry.key;
    final pendingAttachmentsForMessage = entry.value;

    try {
      final parentMessage = await groupMsgRepo.getMessage(messageId);
      if (parentMessage == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_NO_MSG',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
          },
        );
        continue;
      }

      if (parentMessage.isIncoming) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_INCOMING',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
          },
        );
        continue;
      }

      final allAttachments = await mediaAttachmentRepo.getAttachmentsForMessage(
        messageId,
      );

      final group = await groupRepo.getGroup(parentMessage.groupId);
      if (group == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_NO_GROUP',
          details: {
            'groupId': parentMessage.groupId.length > 8
                ? parentMessage.groupId.substring(0, 8)
                : parentMessage.groupId,
          },
        );
        continue;
      }

      final members = await groupRepo.getMembers(parentMessage.groupId);
      final allowedPeers = members
          .map((member) => member.peerId)
          .where((peerId) => peerId.isNotEmpty && peerId != identity.peerId)
          .toSet()
          .toList();

      final preparedUploads = <_PreparedGroupRetryUpload>[];
      final resolvedPendingAttachments = <String, MediaAttachment>{};
      var allUploadsSucceeded = true;
      var hasTerminalInvalidMedia = false;

      for (final attachment in pendingAttachmentsForMessage) {
        final validation = GroupMediaMimePolicy.validateDescriptor(
          mime: attachment.mime,
          mediaType: attachment.mediaType,
        );
        if (!validation.isValid) {
          await mediaAttachmentRepo.saveAttachment(
            attachment.copyWith(downloadStatus: 'upload_failed'),
          );
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_INVALID_MIME',
            details: {
              'attachmentId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
              'mime': attachment.mime,
              'mediaType': attachment.mediaType,
              'reason': validation.reason,
            },
          );
          allUploadsSucceeded = false;
          hasTerminalInvalidMedia = true;
          break;
        }

        var localPath = attachment.localPath;
        if (localPath == null || localPath.isEmpty) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_NO_PATH',
            details: {
              'attachmentId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
            },
          );
          allUploadsSucceeded = false;
          break;
        }

        if (mediaFileManager != null) {
          localPath = await mediaFileManager.resolveStoredPath(localPath);
        }

        final resolvedSize = await _resolveRetryAttachmentSize(
          attachment: attachment,
          absolutePath: localPath,
        );
        if (resolvedSize == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_NO_SIZE',
            details: {
              'attachmentId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
            },
          );
          allUploadsSucceeded = false;
          break;
        }

        final sizeValidation = GroupMediaSizePolicy.validateSize(
          sizeBytes: resolvedSize,
          mime: attachment.mime,
        );
        if (!sizeValidation.isValid) {
          final failed = attachment.copyWith(
            size: resolvedSize,
            downloadStatus: 'upload_failed',
          );
          await mediaAttachmentRepo.saveAttachment(failed);
          resolvedPendingAttachments[attachment.id] = failed;
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_INVALID_SIZE',
            details: {
              'attachmentId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
              'reason': sizeValidation.reason,
            },
          );
          allUploadsSucceeded = false;
          hasTerminalInvalidMedia = true;
          break;
        }

        final resolvedAttachment = attachment.copyWith(size: resolvedSize);
        resolvedPendingAttachments[attachment.id] = resolvedAttachment;
        preparedUploads.add(
          _PreparedGroupRetryUpload(
            pendingAttachment: resolvedAttachment,
            absolutePath: localPath,
          ),
        );
      }

      if (!allUploadsSucceeded) {
        if (hasTerminalInvalidMedia) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_MSG_DEFERRED',
            details: {
              'messageId': messageId.length > 8
                  ? messageId.substring(0, 8)
                  : messageId,
              'reason': 'invalid_group_media',
              'totalAttachments': pendingAttachmentsForMessage.length,
            },
          );
          continue;
        }

        final failedCount = <String, int>{};
        for (final attachment in pendingAttachmentsForMessage) {
          failedCount[attachment.id] = (attachment.uploadRetryCount ?? 0) + 1;
          final retryCount = failedCount[attachment.id]!;
          await mediaAttachmentRepo.saveAttachment(
            attachment.copyWith(
              downloadStatus: retryCount >= kMaxUploadRetries
                  ? 'upload_failed'
                  : 'upload_pending',
              uploadRetryCount: retryCount,
            ),
          );
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_MSG_DEFERRED',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
            'reason': 'invalid_pending_path',
            'totalAttachments': pendingAttachmentsForMessage.length,
          },
        );
        continue;
      }

      final preUploadAttachments = allAttachments
          .map(
            (attachment) =>
                resolvedPendingAttachments[attachment.id] ?? attachment,
          )
          .toList(growable: false);
      final preUploadSizeValidation = GroupMediaSizePolicy.validateAttachments(
        preUploadAttachments,
      );
      if (!preUploadSizeValidation.isValid) {
        for (final attachment in pendingAttachmentsForMessage) {
          await mediaAttachmentRepo.saveAttachment(
            (resolvedPendingAttachments[attachment.id] ?? attachment).copyWith(
              downloadStatus: 'upload_failed',
            ),
          );
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_MSG_DEFERRED',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
            'reason': preUploadSizeValidation.reason,
            'totalAttachments': preUploadAttachments.length,
          },
        );
        continue;
      }

      final uploadResults = await Future.wait(
        preparedUploads.map((plan) async {
          try {
            final mime = plan.pendingAttachment.mime;
            return await uploadMediaFn(
              bridge: bridge,
              localFilePath: plan.absolutePath,
              mime: mime,
              recipientPeerId: parentMessage.groupId,
              mediaFileManager: mediaFileManager,
              width: plan.pendingAttachment.width,
              height: plan.pendingAttachment.height,
              durationMs: plan.pendingAttachment.durationMs,
              waveform: plan.pendingAttachment.waveform,
              allowedPeers: allowedPeers,
              blobId: plan.pendingAttachment.id,
            );
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_ERROR',
              details: {'error': e.toString()},
            );
            return null;
          }
        }),
      );

      final failedPlans = <_PreparedGroupRetryUpload>[];
      for (var i = 0; i < uploadResults.length; i++) {
        final plan = preparedUploads[i];
        final uploaded = uploadResults[i];
        if (uploaded == null) {
          failedPlans.add(plan);
          continue;
        }

        final contentHash =
            uploaded.contentHash ??
            await GroupMediaIntegrityPolicy.computeFileSha256Hex(
              plan.absolutePath,
            );
        final completed = uploaded.copyWith(
          messageId: parentMessage.id,
          downloadStatus: 'done',
          uploadRetryCount: plan.pendingAttachment.uploadRetryCount,
          contentHash: contentHash,
        );
        await mediaAttachmentRepo.saveAttachment(completed);
      }

      if (failedPlans.isNotEmpty) {
        for (final plan in failedPlans) {
          final nextRetryCount =
              (plan.pendingAttachment.uploadRetryCount ?? 0) + 1;
          await mediaAttachmentRepo.saveAttachment(
            plan.pendingAttachment.copyWith(
              downloadStatus: nextRetryCount >= kMaxUploadRetries
                  ? 'upload_failed'
                  : 'upload_pending',
              uploadRetryCount: nextRetryCount,
            ),
          );
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_MSG_DEFERRED',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
            'reason': 'transient_failure',
            'totalAttachments': pendingAttachmentsForMessage.length,
          },
        );
        continue;
      }

      final refreshedMessage = await groupMsgRepo.getMessage(messageId);
      final refreshedAttachments = await mediaAttachmentRepo
          .getAttachmentsForMessage(messageId);
      final abortReason = _lateGroupSendAbortReason(
        message: refreshedMessage,
        attachments: refreshedAttachments,
        expectedAttachmentCount: allAttachments.length,
      );
      if (abortReason != null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_ABORT_FINAL_SEND',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
            'reason': abortReason,
          },
        );
        continue;
      }

      final fullAttachmentList = refreshedAttachments
          .where((attachment) => attachment.downloadStatus == 'done')
          .toList(growable: false);

      final senderDeviceId = p2pService.currentState.peerId?.trim();
      final currentSenderDeviceId =
          senderDeviceId == null || senderDeviceId.isEmpty
          ? null
          : senderDeviceId;
      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
        groupId: refreshedMessage!.groupId,
        text: refreshedMessage.text,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        messageId: refreshedMessage.id,
        timestamp: refreshedMessage.timestamp,
        quotedMessageId: refreshedMessage.quotedMessageId,
        senderDeviceId: currentSenderDeviceId,
        senderTransportPeerId: currentSenderDeviceId,
        mediaAttachments: fullAttachmentList,
        mediaAttachmentRepo: mediaAttachmentRepo,
        emitTimingEvent: false,
      );

      if (result == SendGroupMessageResult.success ||
          result == SendGroupMessageResult.successNoPeers) {
        successCount++;
        if (mediaFileManager != null) {
          try {
            await mediaFileManager.deletePendingUploadDir(messageId);
          } catch (_) {}
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SUCCESS',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
            'attachmentCount': fullAttachmentList.length,
            if (result == SendGroupMessageResult.successNoPeers)
              'topicPeers': 0,
          },
        );
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SEND_FAILED',
          details: {'result': result.name},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_COMPLETE',
    details: {
      'totalAttachments': pendingAttachments.length,
      'totalMessages': byMessageId.length,
      'succeeded': successCount,
    },
  );
  emitRetryTiming(
    outcome: 'complete',
    attachmentCount: pendingAttachments.length,
    messageCount: byMessageId.length,
    succeeded: successCount,
  );

  return successCount;
}

String? _lateGroupSendAbortReason({
  required GroupMessage? message,
  required List<MediaAttachment> attachments,
  required int expectedAttachmentCount,
}) {
  if (message == null) {
    return 'message_missing';
  }
  if (message.isIncoming) {
    return 'message_incoming';
  }
  if (message.status != 'sending' && message.status != 'failed') {
    return 'message_status_${message.status}';
  }

  if (attachments.any(
    (attachment) => attachment.downloadStatus == 'upload_failed',
  )) {
    return 'attachments_terminalized';
  }
  final doneCount = attachments
      .where((attachment) => attachment.downloadStatus == 'done')
      .length;
  if (doneCount < expectedAttachmentCount) {
    return 'attachments_not_done';
  }
  final sizeValidation = GroupMediaSizePolicy.validateAttachments(attachments);
  if (!sizeValidation.isValid) {
    return sizeValidation.reason ?? 'invalid_group_media_size';
  }
  return null;
}

Future<int?> _resolveRetryAttachmentSize({
  required MediaAttachment attachment,
  required String absolutePath,
}) async {
  if (attachment.size > 0) {
    return attachment.size;
  }

  try {
    final file = File(absolutePath);
    if (!await file.exists()) return null;
    final size = await file.length();
    return size > 0 ? size : null;
  } catch (_) {
    return null;
  }
}
