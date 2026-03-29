import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
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

/// Retries all failed outgoing messages.
///
/// Loads identity, queries failed messages, then re-sends each via
/// [sendChatMessage] with the original messageId + timestamp so the
/// DB row is updated in-place (INSERT OR REPLACE).
///
/// When [mediaAttachmentRepo] is provided, loads persisted attachment rows
/// to determine whether a CDN re-upload is needed before re-sending.
///
/// When [uploadMediaFn] is provided, uses that function for media uploads
/// instead of the production [uploadMedia] symbol (for testability).
///
/// Returns the count of successfully retried messages.
/// Non-fatal: catches errors per-message and continues with the next.
Future<int> retryFailedMessages({
  required MessageRepository messageRepo,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  MediaAttachmentRepository? mediaAttachmentRepo,
  UploadMediaFn? uploadMediaFn,
}) {
  return _retryFailedMessagesInternal(
    messageRepo: messageRepo,
    identityRepo: identityRepo,
    contactRepo: contactRepo,
    p2pService: p2pService,
    bridge: bridge,
    mediaAttachmentRepo: mediaAttachmentRepo,
    uploadMediaFn: uploadMediaFn,
    loadFailedMessages: messageRepo.getFailedOutgoingMessages,
  );
}

/// Retries one failed outgoing message in place.
Future<int> retryFailedMessage({
  required String messageId,
  required MessageRepository messageRepo,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  MediaAttachmentRepository? mediaAttachmentRepo,
  UploadMediaFn? uploadMediaFn,
}) {
  return _retryFailedMessagesInternal(
    messageRepo: messageRepo,
    identityRepo: identityRepo,
    contactRepo: contactRepo,
    p2pService: p2pService,
    bridge: bridge,
    mediaAttachmentRepo: mediaAttachmentRepo,
    uploadMediaFn: uploadMediaFn,
    loadFailedMessages: () async {
      final message = await messageRepo.getMessage(messageId);
      if (message == null || message.isIncoming || message.status != 'failed') {
        return const <ConversationMessage>[];
      }
      return <ConversationMessage>[message];
    },
  );
}

Future<int> _retryFailedMessagesInternal({
  required MessageRepository messageRepo,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required Future<List<ConversationMessage>> Function() loadFailedMessages,
  MediaAttachmentRepository? mediaAttachmentRepo,
  UploadMediaFn? uploadMediaFn,
}) async {
  final retryStopwatch = Stopwatch()..start();
  final effectiveUploadFn = uploadMediaFn ?? uploadMedia;
  void emitRetryTiming({
    required String outcome,
    required int total,
    required int succeeded,
    Map<String, dynamic> details = const {},
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGES_TIMING',
      details: {
        'elapsedMs': retryStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'total': total,
        'succeeded': succeeded,
        ...details,
      },
    );
  }

  emitFlowEvent(layer: 'FL', event: 'RETRY_FAILED_MESSAGES_START', details: {});

  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGES_NO_IDENTITY',
      details: {},
    );
    emitRetryTiming(outcome: 'no_identity', total: 0, succeeded: 0);
    return 0;
  }

  final failedMessages = await loadFailedMessages();
  if (failedMessages.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGES_NONE',
      details: {},
    );
    emitRetryTiming(outcome: 'none', total: 0, succeeded: 0);
    return 0;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_MESSAGES_FOUND',
    details: {'count': failedMessages.length},
  );

  var successCount = 0;

  for (final msg in failedMessages) {
    final retried = await _retryFailedMessageCandidate(
      msg: msg,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      identity: identity,
      mediaAttachmentRepo: mediaAttachmentRepo,
      uploadFn: effectiveUploadFn,
    );
    if (retried) {
      successCount++;
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_MESSAGES_COMPLETE',
    details: {'total': failedMessages.length, 'succeeded': successCount},
  );
  emitRetryTiming(
    outcome: 'complete',
    total: failedMessages.length,
    succeeded: successCount,
  );

  return successCount;
}

Future<bool> _retryFailedMessageCandidate({
  required ConversationMessage msg,
  required MessageRepository messageRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required dynamic identity,
  required UploadMediaFn uploadFn,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  try {
    // Prefer wire_envelope -> inbox-only (preserves media, no re-encrypt)
    if (msg.wireEnvelope != null && msg.wireEnvelope!.isNotEmpty) {
      if (msg.transport == 'inbox') {
        await messageRepo.saveMessage(
          msg.copyWith(status: 'delivered', wireEnvelope: null),
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_MESSAGE_ALREADY_INBOX',
          details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
        );
        return true;
      }
      try {
        final stored = await p2pService.storeInInbox(
          msg.contactPeerId,
          msg.wireEnvelope!,
        );
        if (stored) {
          await messageRepo.saveMessage(
            msg.copyWith(
              status: 'delivered',
              transport: 'inbox',
              wireEnvelope: null,
            ),
          );
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_MESSAGE_SUCCESS',
            details: {
              'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
              'via': 'wire_envelope',
            },
          );
          return true;
        }
      } catch (_) {
        // Wire envelope inbox failed -- fall through to full send
      }
    }

    // Look up contact for ML-KEM public key
    final contact = await contactRepo.getContact(msg.contactPeerId);
    final mlKemPk = contact?.mlKemPublicKey;

    // Three-branch attachment dispatch (Part F)
    final (:attachments, :skipMessage) = await _resolveAttachmentsForRetry(
      messageId: msg.id,
      mediaAttachmentRepo: mediaAttachmentRepo,
      bridge: bridge,
      targetPeerId: msg.contactPeerId,
      uploadFn: uploadFn,
    );

    if (skipMessage) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_MEDIA_LOCAL_FILE_MISSING',
        details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
      );
      return false;
    }

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
      recipientMlKemPublicKey: mlKemPk,
      mediaAttachments: attachments,
      mediaAttachmentRepo: mediaAttachmentRepo,
      emitTimingEvent: false,
    );

    if (result == SendChatMessageResult.success) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_MESSAGE_SUCCESS',
        details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
      );
      return true;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGE_STILL_FAILED',
      details: {
        'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
        'reason': result.name,
      },
    );
    return false;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGE_ERROR',
      details: {
        'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
        'error': e.toString(),
      },
    );
    return false;
  }
}

/// Resolves which attachments (if any) should be passed to [sendChatMessage]
/// for a retry.
///
/// Returns [attachments] = null for text-only messages, or the list of
/// [MediaAttachment] objects (either reused from Part C or re-uploaded).
/// Returns [skipMessage] = true when the message cannot be recovered
/// (e.g. local file missing).
Future<({List<MediaAttachment>? attachments, bool skipMessage})>
_resolveAttachmentsForRetry({
  required String messageId,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required Bridge bridge,
  required String targetPeerId,
  required UploadMediaFn uploadFn,
}) async {
  // Load any persisted attachments for this message
  final persistedAttachments =
      await mediaAttachmentRepo?.getAttachmentsForMessage(messageId) ??
      const <MediaAttachment>[];

  // Use `every` not `any` -- if a message has 2 attachments, one 'done'
  // and one 'upload_pending', `any` would return true and the Part C path
  // would silently drop the incomplete attachment.
  final allUploaded =
      persistedAttachments.isNotEmpty &&
      persistedAttachments.every((a) => a.downloadStatus == 'done');

  if (allUploaded) {
    // CDN blobs already exist for ALL attachments -- reuse them (Part C path).
    return (attachments: persistedAttachments, skipMessage: false);
  } else if (persistedAttachments.isNotEmpty) {
    // Attachment rows exist but upload never completed -> re-upload required.
    final reuploadedAttachments = await _reuploadAttachments(
      attachments: persistedAttachments,
      bridge: bridge,
      targetPeerId: targetPeerId,
      uploadFn: uploadFn,
    );
    if (reuploadedAttachments == null) {
      return (attachments: null, skipMessage: true);
    }
    return (attachments: reuploadedAttachments, skipMessage: false);
  } else {
    // Text-only message with no attachment rows.
    return (attachments: null, skipMessage: false);
  }
}

/// Re-uploads each attachment whose local file still exists on disk.
///
/// Returns the re-uploaded [MediaAttachment] list on full success, or null
/// if any local file is missing or any CDN upload returns null. In the null
/// case the caller skips the message and leaves it as 'failed'.
///
/// NOTE: Re-upload produces a new blob ID (UUID v4 inside uploadMedia)
/// unless the Stable-ID contract is used (blobId: attachment.id).
/// The old blob ID in media_attachments is orphaned on the relay;
/// relay blobs expire after 7 days so orphaned blobs are self-cleaning.
Future<List<MediaAttachment>?> _reuploadAttachments({
  required List<MediaAttachment> attachments,
  required Bridge bridge,
  required String targetPeerId,
  required UploadMediaFn uploadFn,
}) async {
  // Defensive ceiling: skip messages with too many attachments
  if (attachments.length > kReuploadMaxAttachmentsPerMessage) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_REUPLOAD_TOO_MANY_ATTACHMENTS',
      details: {'count': attachments.length},
    );
    return null;
  }

  final result = <MediaAttachment>[];

  for (final attachment in attachments) {
    final localPath = attachment.localPath;
    if (localPath == null || localPath.isEmpty) {
      return null; // No path recorded -- cannot re-upload
    }

    if (!File(localPath).existsSync()) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_REUPLOAD_FILE_NOT_FOUND',
        details: {'localPath': localPath},
      );
      return null;
    }

    final uploaded = await uploadFn(
      bridge: bridge,
      localFilePath: localPath,
      mime: attachment.mime,
      recipientPeerId: targetPeerId,
      durationMs: attachment.durationMs,
      waveform: attachment.waveform,
      width: attachment.width,
      height: attachment.height,
      blobId: attachment.id, // Stable-ID contract (F.7.1)
    );

    if (uploaded == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_REUPLOAD_FAILED',
        details: {'localPath': localPath},
      );
      return null;
    }

    result.add(uploaded);
  }

  return result;
}
