import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/delete_message_tombstone_visibility.dart';
import 'package:flutter_app/features/conversation/application/outbound_envelope_policy.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

enum _RetryFailedMessageSkipReason { none, localFileMissing, uploadCancelled }

/// 116 EF-1 (row-derived action): the semantic action of a retried row comes
/// from the DB row, never from caller defaults — an `editedAt`-bearing row
/// goes back out as an EDIT with its original metadata. Shared by the
/// full-send fallback below, the tombstone route (116 P3), and the 115
/// custody sweep.
String deriveRetryAction(ConversationMessage msg) {
  if (msg.editedAt != null && !msg.isDeleted) {
    return MessagePayload.actionEdit;
  }
  return MessagePayload.actionSend;
}

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

/// 116 EF-3 single-flight: at most one in-flight retry per message id across
/// all four triggers (PendingMessageRetrier periodic, reconnect debounce,
/// app-resume 8c, UI retry button). File-private top-level set — every
/// trigger funnels through [_retryFailedMessageCandidate] in the same
/// isolate. If retries ever move to a background isolate, this guard must
/// move with them.
final Set<String> _retryInFlightMessageIds = {};

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
  if (!_retryInFlightMessageIds.add(msg.id)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGE_SKIPPED_IN_FLIGHT',
      details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
    );
    return false;
  }
  try {
    // 116 EF-3 settled-recheck: the loaded list may hold a stale snapshot of
    // a row that settled between load and execution — re-fetch and use the
    // FRESH row for all subsequent derivation.
    final fresh = await messageRepo.getMessage(msg.id);
    if (fresh == null || fresh.isIncoming || fresh.status != 'failed') {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_MESSAGE_SKIPPED_SETTLED',
        details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
      );
      return false;
    }
    msg = fresh;

    if (msg.isDeleted) {
      return _retryFailedDeletedTombstone(
        msg: msg,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );
    }

    // Prefer wire_envelope -> inbox-only (preserves media, no re-encrypt)
    if (msg.wireEnvelope != null && msg.wireEnvelope!.isNotEmpty) {
      if (msg.transport == 'inbox') {
        // Already in the relay inbox — that is custody, not receiver delivery
        // (F6). Keep it 'inboxed' (envelope retained) so the custody sweep +
        // DeliveryReceiptListener flip it to 'delivered' only on the receiver's
        // confirmation; a false terminal 'delivered' here is uncorrectable.
        await messageRepo.saveMessage(
          normalizeOutgoingDeleteTombstoneVisibility(
            msg.copyWith(status: 'inboxed'),
          ),
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_MESSAGE_ALREADY_INBOX',
          details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
        );
        return true;
      }

      final unsafeLegacyEnvelope = isUnsafeLegacyOutboundEnvelope(
        msg.wireEnvelope!,
      );
      if (!unsafeLegacyEnvelope) {
        try {
          final stored = await p2pService.storeInInbox(
            msg.contactPeerId,
            msg.wireEnvelope!,
          );
          if (stored) {
            // Relay STORE success alone is custody, not receiver delivery (F6):
            // no peer ack, no delivery receipt. Persist 'inboxed' and RETAIN the
            // wire envelope so the custody sweep + receipt repair can advance it
            // to 'delivered' on the receiver's confirmation.
            await messageRepo.saveMessage(
              normalizeOutgoingDeleteTombstoneVisibility(
                msg.copyWith(
                  status: 'inboxed',
                  transport: 'inbox',
                ),
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
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_MESSAGE_SKIP_LEGACY_WIRE_ENVELOPE',
          details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
        );
      }
    }

    // Look up contact for ML-KEM public key
    final contact = await contactRepo.getContact(msg.contactPeerId);
    final mlKemPk = contact?.mlKemPublicKey;

    // Three-branch attachment dispatch (Part F)
    final (:attachments, :skipReason) = await _resolveAttachmentsForRetry(
      messageId: msg.id,
      mediaAttachmentRepo: mediaAttachmentRepo,
      bridge: bridge,
      targetPeerId: msg.contactPeerId,
      uploadFn: uploadFn,
    );

    if (skipReason != _RetryFailedMessageSkipReason.none) {
      final details = {
        'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
      };
      switch (skipReason) {
        case _RetryFailedMessageSkipReason.localFileMissing:
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_MEDIA_LOCAL_FILE_MISSING',
            details: details,
          );
          break;
        case _RetryFailedMessageSkipReason.uploadCancelled:
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_MEDIA_UPLOAD_CANCELLED',
            details: details,
          );
          break;
        case _RetryFailedMessageSkipReason.none:
          break;
      }
      return false;
    }

    // 116 EF-1: the fallback derives action/editedAt/createdAt from the ROW
    // so a failed edit goes back out as an EDIT (the row's ORIGINAL editedAt
    // preserves the receiver staleness-gate ordering), and plain rows keep
    // their original createdAt instead of re-minting it.
    final retryAction = deriveRetryAction(msg);
    final (result, _) = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: msg.contactPeerId,
      text: msg.text,
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      action: retryAction,
      editedAt: msg.editedAt,
      messageId: msg.id,
      timestamp: msg.timestamp,
      createdAt: msg.createdAt,
      bridge: bridge,
      recipientMlKemPublicKey: mlKemPk,
      quotedMessageId: msg.quotedMessageId,
      mediaAttachments: attachments,
      mediaAttachmentRepo: mediaAttachmentRepo,
      emitTimingEvent: false,
    );

    if (result == SendChatMessageResult.success) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_MESSAGE_SUCCESS',
        details: {
          'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
          'action': retryAction,
        },
      );
      return true;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGE_STILL_FAILED',
      details: {
        'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
        'reason': result.name,
        'action': retryAction,
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
  } finally {
    _retryInFlightMessageIds.remove(msg.id);
  }
}

Future<bool> _retryFailedDeletedTombstone({
  required ConversationMessage msg,
  required MessageRepository messageRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
}) async {
  if (!p2pService.currentState.isStarted) {
    _emitDeleteTombstoneStillFailed(msg, reason: 'node_not_running');
    return false;
  }

  final existingEnvelope = msg.wireEnvelope?.trim();
  if (existingEnvelope != null &&
      existingEnvelope.isNotEmpty &&
      _isV2DeletionWireEnvelope(existingEnvelope)) {
    return _storeOrReplayDeleteEnvelope(
      msg: msg,
      messageRepo: messageRepo,
      p2pService: p2pService,
      wireEnvelope: existingEnvelope,
      rebuilt: false,
    );
  }

  final contact = await contactRepo.getContact(msg.contactPeerId);
  final recipientKey = contact?.mlKemPublicKey?.trim();
  if (recipientKey == null || recipientKey.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE',
      details: {
        'id': _messageIdPreview(msg.id),
        'reason': 'missing_recipient_key',
      },
    );
    return false;
  }

  String rebuiltEnvelope;
  try {
    rebuiltEnvelope = await buildDeletionWireEnvelope(
      bridge: bridge,
      originalMessage: msg,
      deletedAt: msg.deletedAt ?? msg.timestamp,
      recipientMlKemPublicKey: recipientKey,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE',
      details: {
        'id': _messageIdPreview(msg.id),
        'reason': 'encrypt_failed',
        'error': e.toString(),
      },
    );
    return false;
  }

  return _storeOrReplayDeleteEnvelope(
    msg: msg,
    messageRepo: messageRepo,
    p2pService: p2pService,
    wireEnvelope: rebuiltEnvelope,
    rebuilt: true,
  );
}

Future<bool> _storeOrReplayDeleteEnvelope({
  required ConversationMessage msg,
  required MessageRepository messageRepo,
  required P2PService p2pService,
  required String wireEnvelope,
  required bool rebuilt,
}) async {
  if (msg.transport == 'inbox') {
    await messageRepo.saveMessage(
      normalizeOutgoingDeleteTombstoneVisibility(
        msg.copyWith(
          status: 'inboxed',
          transport: 'inbox',
          wireEnvelope: wireEnvelope,
        ),
      ),
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGE_ALREADY_INBOX',
      details: {'id': _messageIdPreview(msg.id), 'type': 'message_deletion'},
    );
    return true;
  }

  try {
    final stored = await p2pService.storeInInbox(
      msg.contactPeerId,
      wireEnvelope,
    );
    if (stored) {
      await messageRepo.saveMessage(
        normalizeOutgoingDeleteTombstoneVisibility(
          msg.copyWith(
            status: 'inboxed',
            transport: 'inbox',
            wireEnvelope: wireEnvelope,
          ),
        ),
      );
      _emitDeleteTombstoneSuccess(
        msg,
        via: 'inbox',
        status: 'inboxed',
        rebuilt: rebuilt,
      );
      return true;
    }
  } catch (_) {
    // Inbox custody failed; fall through to direct deletion-envelope replay.
  }

  SendMessageResult sendResult;
  try {
    sendResult = await p2pService.sendMessageWithReply(
      msg.contactPeerId,
      wireEnvelope,
      timeoutMs: interactiveDirectBudget.inMilliseconds,
    );
  } catch (e) {
    _emitDeleteTombstoneStillFailed(msg, reason: 'send_error', error: e);
    return false;
  }

  if (!sendResult.sent) {
    _emitDeleteTombstoneStillFailed(msg, reason: 'send_failed');
    return false;
  }

  final via = _resolveRetryDeleteTransport(
    p2pService,
    msg.contactPeerId,
    sendResult,
  );
  final status = sendResult.acknowledged ? 'delivered' : 'sent';
  await messageRepo.saveMessage(
    normalizeOutgoingDeleteTombstoneVisibility(
      msg.copyWith(
        status: status,
        transport: via,
        wireEnvelope: sendResult.acknowledged ? null : wireEnvelope,
      ),
    ),
  );
  _emitDeleteTombstoneSuccess(msg, via: via, status: status, rebuilt: rebuilt);
  return true;
}

bool _isV2DeletionWireEnvelope(String wireEnvelope) {
  try {
    final decoded = jsonDecode(wireEnvelope);
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    return decoded['type'] == 'message_deletion' &&
        decoded['version'].toString() == '2';
  } catch (_) {
    return false;
  }
}

String _resolveRetryDeleteTransport(
  P2PService p2pService,
  String peerId,
  SendMessageResult sendResult,
) {
  final actualTransport = sendResult.transport;
  if (actualTransport != null && actualTransport.isNotEmpty) {
    return actualTransport;
  }

  final hasRelayConnection = p2pService.currentState.connections.any(
    (connection) =>
        connection.peerId == peerId &&
        connection.multiaddrs.any(
          (multiaddr) => multiaddr.contains('/p2p-circuit'),
        ),
  );
  return hasRelayConnection ? 'relay' : 'direct';
}

void _emitDeleteTombstoneSuccess(
  ConversationMessage msg, {
  required String via,
  required String status,
  required bool rebuilt,
}) {
  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_DELETE_TOMBSTONE_SUCCESS',
    details: {
      'id': _messageIdPreview(msg.id),
      'via': via,
      'status': status,
      'rebuilt': rebuilt,
    },
  );
}

void _emitDeleteTombstoneStillFailed(
  ConversationMessage msg, {
  required String reason,
  Object? error,
}) {
  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_MESSAGE_STILL_FAILED',
    details: {
      'id': _messageIdPreview(msg.id),
      'reason': reason,
      'type': 'message_deletion',
      if (error != null) 'error': error.toString(),
    },
  );
}

/// Resolves which attachments (if any) should be passed to [sendChatMessage]
/// for a retry.
///
/// Returns [attachments] = null for text-only messages, or the list of
/// [MediaAttachment] objects (either reused from Part C or re-uploaded).
/// Returns [skipReason] when the message cannot be recovered or should remain
/// terminal (e.g. local file missing or user-cancelled upload).
Future<
  ({
    List<MediaAttachment>? attachments,
    _RetryFailedMessageSkipReason skipReason,
  })
>
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

  if (persistedAttachments.any(
    (attachment) => attachment.downloadStatus == 'upload_cancelled',
  )) {
    return (
      attachments: null,
      skipReason: _RetryFailedMessageSkipReason.uploadCancelled,
    );
  }

  // Use `every` not `any` -- if a message has 2 attachments, one 'done'
  // and one 'upload_pending', `any` would return true and the Part C path
  // would silently drop the incomplete attachment.
  final allUploaded =
      persistedAttachments.isNotEmpty &&
      persistedAttachments.every((a) => a.downloadStatus == 'done');

  if (allUploaded) {
    // CDN blobs already exist for ALL attachments -- reuse them (Part C path).
    return (
      attachments: persistedAttachments,
      skipReason: _RetryFailedMessageSkipReason.none,
    );
  } else if (persistedAttachments.isNotEmpty) {
    // Attachment rows exist but upload never completed -> re-upload required.
    final reuploadedAttachments = await _reuploadAttachments(
      attachments: persistedAttachments,
      bridge: bridge,
      targetPeerId: targetPeerId,
      uploadFn: uploadFn,
    );
    if (reuploadedAttachments == null) {
      return (
        attachments: null,
        skipReason: _RetryFailedMessageSkipReason.localFileMissing,
      );
    }
    return (
      attachments: reuploadedAttachments,
      skipReason: _RetryFailedMessageSkipReason.none,
    );
  } else {
    // Text-only message with no attachment rows.
    return (attachments: null, skipReason: _RetryFailedMessageSkipReason.none);
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

String _messageIdPreview(String id) => id.length > 8 ? id.substring(0, 8) : id;
