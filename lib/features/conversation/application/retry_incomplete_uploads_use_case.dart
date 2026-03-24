import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Re-uploads any attachment rows with downloadStatus='upload_pending',
/// grouped by messageId, then calls [sendChatMessage] ONCE per message
/// with the full attachment list to complete the original send.
///
/// This mirrors the real send path in `conversation_wired.dart`, which
/// uploads all attachments for a message and then calls `sendChatMessage`
/// once with the complete list. Processing per-attachment would fragment
/// multi-attachment messages into separate single-attachment sends.
///
/// Ordering in [handleAppResumed]:
///   recoverStuckSendingMessages -> retryIncompleteUploads -> retryFailedMessages
///
/// Returns the number of messages successfully sent after re-upload.
/// Non-fatal per-message: errors are caught, logged, and iteration continues
/// to the next message.
Future<int> retryIncompleteUploads({
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MessageRepository messageRepo,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  UploadMediaFn uploadMediaFn = uploadMedia,
  MediaFileManager? mediaFileManager,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_UPLOADS_START',
    details: {},
  );

  final pendingAttachments =
      await mediaAttachmentRepo.getUploadPendingAttachments();
  if (pendingAttachments.isEmpty) {
    emitFlowEvent(
        layer: 'FL', event: 'RETRY_INCOMPLETE_UPLOADS_NONE', details: {});
    return 0;
  }

  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_INCOMPLETE_UPLOADS_NO_IDENTITY',
        details: {});
    return 0;
  }

  // Group attachments by messageId so we process all attachments for a
  // single message together and issue ONE sendChatMessage call per message.
  final byMessageId = <String, List<MediaAttachment>>{};
  for (final att in pendingAttachments) {
    byMessageId.putIfAbsent(att.messageId, () => []).add(att);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_UPLOADS_FOUND',
    details: {
      'attachmentCount': pendingAttachments.length,
      'messageCount': byMessageId.length,
    },
  );

  var successCount = 0;

  for (final entry in byMessageId.entries) {
    final messageId = entry.key;
    final pendingAttsForMessage = entry.value;

    try {
      // 1. Load and validate the parent message.
      final msg = await messageRepo.getMessage(messageId);
      if (msg == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_NO_MSG',
          details: {
            'messageId':
                messageId.length > 8 ? messageId.substring(0, 8) : messageId,
          },
        );
        continue;
      }

      if (msg.status != 'sending' && msg.status != 'failed') {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_STATUS',
          details: {'status': msg.status},
        );
        continue;
      }

      // Load ALL attachments for this message (including already-done ones)
      // so we can combine them with newly-uploaded ones for the send call.
      final allAttachments =
          await mediaAttachmentRepo.getAttachmentsForMessage(messageId);
      final doneAttachments = allAttachments
          .where((a) => a.downloadStatus == 'done')
          .toList();

      // 2. Re-upload ALL pending attachments for this message.
      //    If any single upload fails, the message is skipped and
      //    sendChatMessage is NOT called (no partial sends).
      final uploadedAttachments = <MediaAttachment>[];
      var allUploadsSucceeded = true;
      var isNonRetryable = false;

      for (final attachment in pendingAttsForMessage) {
        var localPath = attachment.localPath;
        if (localPath == null || localPath.isEmpty) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_NO_PATH',
            details: {
              'attachmentId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
            },
          );
          allUploadsSucceeded = false;
          isNonRetryable = true;
          break;
        }

        // Resolve relative/legacy paths to absolute filesystem paths
        if (mediaFileManager != null) {
          localPath = await mediaFileManager.resolveStoredPath(localPath);
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_START',
          details: {'mime': attachment.mime},
        );

        final uploaded = await uploadMediaFn(
          bridge: bridge,
          localFilePath: localPath,
          mime: attachment.mime,
          recipientPeerId: msg.contactPeerId,
          durationMs: attachment.durationMs,
          waveform: attachment.waveform,
          width: attachment.width,
          height: attachment.height,
          blobId: attachment.id, // Stable-ID contract (F.7.1)
        );

        if (uploaded == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_UPLOAD_REUPLOAD_FAILED',
            details: {
              'attachmentId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
            },
          );
          allUploadsSucceeded = false;
          break;
        }

        final completedAttachment = uploaded.copyWith(
          messageId: msg.id,
          downloadStatus: 'done',
        );
        await mediaAttachmentRepo.saveAttachment(completedAttachment);
        uploadedAttachments.add(completedAttachment);
      }

      // Canonical failure handling (G.8.2): transient vs non-retryable
      if (!allUploadsSucceeded) {
        for (final att in pendingAttsForMessage) {
          final newRetryCount = (att.uploadRetryCount ?? 0) + 1;

          if (isNonRetryable || newRetryCount >= kMaxUploadRetries) {
            // Terminal: mark as permanently failed
            await mediaAttachmentRepo.saveAttachment(
              att.copyWith(
                downloadStatus: 'upload_failed',
                uploadRetryCount: newRetryCount,
              ),
            );
          } else {
            // Transient: keep as upload_pending for next retry cycle
            await mediaAttachmentRepo.saveAttachment(
              att.copyWith(
                downloadStatus: 'upload_pending', // Still retryable
                uploadRetryCount: newRetryCount,
              ),
            );
          }
        }
        emitFlowEvent(
          layer: 'FL',
          event: isNonRetryable
              ? 'RETRY_INCOMPLETE_UPLOAD_MSG_SKIPPED'
              : 'RETRY_INCOMPLETE_UPLOAD_MSG_DEFERRED',
          details: {
            'messageId':
                messageId.length > 8 ? messageId.substring(0, 8) : messageId,
            'reason':
                isNonRetryable ? 'non_retryable_failure' : 'transient_failure',
            'totalAttachments': pendingAttsForMessage.length,
          },
        );
        continue;
      }

      // 3. All uploads succeeded — send the message ONCE with the full list.
      // Combine previously-done attachments with newly-uploaded ones.
      final fullAttachmentList = [
        ...doneAttachments,
        ...uploadedAttachments,
      ];

      final contact = await contactRepo.getContact(msg.contactPeerId);
      final (result, _) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: msg.contactPeerId,
        text: msg.text,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        messageId: msg.id,
        timestamp: msg.timestamp,
        bridge: bridge,
        recipientMlKemPublicKey: contact?.mlKemPublicKey,
        quotedMessageId: msg.quotedMessageId,
        mediaAttachments: fullAttachmentList,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      if (result == SendChatMessageResult.success) {
        successCount++;
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SUCCESS',
          details: {
            'messageId':
                messageId.length > 8 ? messageId.substring(0, 8) : messageId,
            'attachmentCount': fullAttachmentList.length,
          },
        );

        // Cleanup durable storage after successful send
        if (mediaFileManager != null) {
          try {
            await mediaFileManager.deletePendingUploadDir(messageId);
          } catch (_) {}
        }
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SEND_FAILED',
          details: {'result': result.name},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_INCOMPLETE_UPLOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_UPLOADS_COMPLETE',
    details: {
      'totalAttachments': pendingAttachments.length,
      'totalMessages': byMessageId.length,
      'succeeded': successCount,
    },
  );

  return successCount;
}
