import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
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
///
/// [isUploadInFlight] guards against the 127-Bug-B double-encrypt race: while a
/// foreground send is actively uploading a blob (its row sits `upload_pending`
/// for the whole upload+envelope window), this retrier must NOT re-encrypt and
/// re-upload the SAME blob — a fresh AES-GCM nonce would mint divergent
/// ciphertext that no longer matches the `contentHash` the foreground already
/// advertised in the message envelope, so the recipient's pre-decrypt
/// content-hash gate rejects it (`integrity_failed` / "Couldn't verify this
/// media"). A blob reported in-flight defers the WHOLE message (rows left
/// `upload_pending`, no terminalization) — the foreground send owns it.
Future<int> retryIncompleteUploads({
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MessageRepository messageRepo,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  UploadMediaFn uploadMediaFn = uploadMedia,
  MediaFileManager? mediaFileManager,
  bool Function(String blobId) isUploadInFlight = _uploadNeverInFlight,
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
      event: 'RETRY_INCOMPLETE_UPLOADS_TIMING',
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
    event: 'RETRY_INCOMPLETE_UPLOADS_START',
    details: {},
  );

  final pendingAttachments = await mediaAttachmentRepo
      .getUploadPendingAttachments();
  if (pendingAttachments.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_UPLOADS_NONE',
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
      event: 'RETRY_INCOMPLETE_UPLOADS_NO_IDENTITY',
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

    // 127-Bug-B: never race a foreground send. If ANY pending blob for this
    // message is currently being uploaded by the live send path, defer the
    // whole message untouched — re-encrypting here would diverge the relay
    // bytes from the already-advertised contentHash.
    String? inFlightBlob;
    for (final att in pendingAttsForMessage) {
      if (isUploadInFlight(att.id)) {
        inFlightBlob = att.id;
        break;
      }
    }
    if (inFlightBlob != null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_IN_FLIGHT',
        details: {
          'messageId':
              messageId.length > 8 ? messageId.substring(0, 8) : messageId,
          'attachmentId':
              inFlightBlob.length > 8 ? inFlightBlob.substring(0, 8) : inFlightBlob,
        },
      );
      continue;
    }

    try {
      // 1. Load and validate the parent message.
      final msg = await messageRepo.getMessage(messageId);
      if (msg == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_NO_MSG',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
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
      final allAttachments = await mediaAttachmentRepo.getAttachmentsForMessage(
        messageId,
      );

      // 2. Re-upload ALL pending attachments for this message.
      //    If any single upload fails, the message is skipped and
      //    sendChatMessage is NOT called (no partial sends).
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

        final latestBeforeSave = await _latestAttachmentForMessage(
          mediaAttachmentRepo: mediaAttachmentRepo,
          messageId: messageId,
          attachmentId: attachment.id,
        );
        if (latestBeforeSave != null &&
            latestBeforeSave.downloadStatus != 'upload_pending') {
          if (latestBeforeSave.downloadStatus == 'done') {
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_ALREADY_DONE',
              details: {
                'attachmentId': attachment.id.length > 8
                    ? attachment.id.substring(0, 8)
                    : attachment.id,
              },
            );
            continue;
          }
          allUploadsSucceeded = false;
          isNonRetryable = true;
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_UPLOAD_ABORT_STALE_ATTACHMENT',
            details: {
              'attachmentId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
              'status': latestBeforeSave.downloadStatus,
            },
          );
          break;
        }

        final completedAttachment = uploaded.copyWith(
          messageId: msg.id,
          downloadStatus: 'done',
        );
        await mediaAttachmentRepo.saveAttachment(completedAttachment);

        // KC-2 (112 Phase 3): the re-upload minted a fresh key/nonce, so a
        // persisted wire envelope (the Section-4 crash-replay contract,
        // replayed verbatim without re-encrypting) would reference the DEAD
        // key — receivers could download the new blob but never decrypt it.
        // Invalidate it; the send below (or any later retry path) rebuilds
        // the envelope from the current attachment rows. KC-1 holds because
        // this runs BEFORE the sendChatMessage call below.
        final keyChanged =
            uploaded.encryptionKeyBase64 != attachment.encryptionKeyBase64 ||
            uploaded.encryptionNonce != attachment.encryptionNonce;
        if (keyChanged) {
          final staleMsg = await messageRepo.getMessage(messageId);
          if (staleMsg != null && staleMsg.wireEnvelope != null) {
            await messageRepo.saveMessage(staleMsg.copyWith(wireEnvelope: null));
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_INCOMPLETE_UPLOAD_WIRE_ENVELOPE_INVALIDATED',
              details: {
                'messageId': messageId.length > 8
                    ? messageId.substring(0, 8)
                    : messageId,
                'attachmentId': attachment.id.length > 8
                    ? attachment.id.substring(0, 8)
                    : attachment.id,
              },
            );
          }
        }
      }

      // Canonical failure handling (G.8.2): transient vs non-retryable
      if (!allUploadsSucceeded) {
        for (final att in pendingAttsForMessage) {
          final latest = await _latestAttachmentForMessage(
            mediaAttachmentRepo: mediaAttachmentRepo,
            messageId: messageId,
            attachmentId: att.id,
          );
          final current = latest ?? att;
          if (current.downloadStatus != 'upload_pending') {
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_STALE_FAILURE_UPDATE',
              details: {
                'attachmentId': att.id.length > 8
                    ? att.id.substring(0, 8)
                    : att.id,
                'status': current.downloadStatus,
              },
            );
            continue;
          }

          final newRetryCount = (current.uploadRetryCount ?? 0) + 1;

          if (isNonRetryable || newRetryCount >= kMaxUploadRetries) {
            // Terminal: mark as permanently failed
            await mediaAttachmentRepo.saveAttachment(
              current.copyWith(
                downloadStatus: 'upload_failed',
                uploadRetryCount: newRetryCount,
              ),
            );
          } else {
            // Transient: keep as upload_pending for next retry cycle
            await mediaAttachmentRepo.saveAttachment(
              current.copyWith(
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
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
            'reason': isNonRetryable
                ? 'non_retryable_failure'
                : 'transient_failure',
            'totalAttachments': pendingAttsForMessage.length,
          },
        );
        continue;
      }

      final refreshedMsg = await messageRepo.getMessage(messageId);
      final refreshedAttachments = await mediaAttachmentRepo
          .getAttachmentsForMessage(messageId);
      final abortReason = _lateSendAbortReason(
        message: refreshedMsg,
        attachments: refreshedAttachments,
        expectedAttachmentCount: allAttachments.length,
      );
      if (abortReason != null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_ABORT_FINAL_SEND',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
            'reason': abortReason,
          },
        );
        continue;
      }

      // 3. All uploads still belong to a live retryable row — send ONCE with
      // the current completed attachment set.
      final fullAttachmentList = refreshedAttachments
          .where((attachment) => attachment.downloadStatus == 'done')
          .toList(growable: false);

      final contact = await contactRepo.getContact(refreshedMsg!.contactPeerId);
      final (result, _) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: refreshedMsg.contactPeerId,
        text: refreshedMsg.text,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        messageId: refreshedMsg.id,
        timestamp: refreshedMsg.timestamp,
        bridge: bridge,
        recipientMlKemPublicKey: contact?.mlKemPublicKey,
        quotedMessageId: refreshedMsg.quotedMessageId,
        mediaAttachments: fullAttachmentList,
        mediaAttachmentRepo: mediaAttachmentRepo,
        emitTimingEvent: false,
      );

      if (result == SendChatMessageResult.success) {
        successCount++;
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SUCCESS',
          details: {
            'messageId': messageId.length > 8
                ? messageId.substring(0, 8)
                : messageId,
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
  emitRetryTiming(
    outcome: 'complete',
    attachmentCount: pendingAttachments.length,
    messageCount: byMessageId.length,
    succeeded: successCount,
  );

  return successCount;
}

/// Default [retryIncompleteUploads] in-flight predicate: nothing is in-flight
/// (used in tests and any caller without a foreground upload tracker).
bool _uploadNeverInFlight(String _) => false;

Future<MediaAttachment?> _latestAttachmentForMessage({
  required MediaAttachmentRepository mediaAttachmentRepo,
  required String messageId,
  required String attachmentId,
}) async {
  final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
    messageId,
  );
  for (final attachment in attachments) {
    if (attachment.id == attachmentId) {
      return attachment;
    }
  }
  return null;
}

String? _lateSendAbortReason({
  required ConversationMessage? message,
  required List<MediaAttachment> attachments,
  required int expectedAttachmentCount,
}) {
  if (message == null) {
    return 'message_missing';
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
  return null;
}
