import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
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
    return 0;
  }

  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_NO_IDENTITY',
      details: {},
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
      final doneAttachments = allAttachments
          .where((attachment) => attachment.downloadStatus == 'done')
          .toList();

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
      final allowedPeers = members.map((member) => member.peerId).toList();

      final preparedUploads = <_PreparedGroupRetryUpload>[];
      final uploadedAttachments = <MediaAttachment>[];
      var allUploadsSucceeded = true;

      for (final attachment in pendingAttachmentsForMessage) {
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

        preparedUploads.add(
          _PreparedGroupRetryUpload(
            pendingAttachment: attachment,
            absolutePath: localPath,
          ),
        );
      }

      if (!allUploadsSucceeded) {
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

        final completed = uploaded.copyWith(
          messageId: parentMessage.id,
          downloadStatus: 'done',
          uploadRetryCount: plan.pendingAttachment.uploadRetryCount,
        );
        await mediaAttachmentRepo.saveAttachment(completed);
        uploadedAttachments.add(completed);
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

      final completedById = <String, MediaAttachment>{
        for (final attachment in doneAttachments) attachment.id: attachment,
        for (final attachment in uploadedAttachments) attachment.id: attachment,
      };
      final fullAttachmentList = allAttachments
          .map((attachment) => completedById[attachment.id] ?? attachment)
          .toList(growable: false);

      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
        groupId: parentMessage.groupId,
        text: parentMessage.text,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        messageId: parentMessage.id,
        timestamp: parentMessage.timestamp,
        quotedMessageId: parentMessage.quotedMessageId,
        mediaAttachments: fullAttachmentList,
        mediaAttachmentRepo: mediaAttachmentRepo,
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

  return successCount;
}
