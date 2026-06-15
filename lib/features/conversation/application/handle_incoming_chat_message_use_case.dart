import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/app_owned_media_delete_telemetry.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/core/utils/chat_console_logger.dart';
import 'package:flutter_app/features/conversation/application/send_delivery_receipt_use_case.dart'
    show shouldMintDeliveryReceipt;
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Result of handling an incoming chat message.
enum HandleChatMessageResult {
  /// Valid chat message received and stored.
  chatMessage,

  /// Not a chat_message type — ignore.
  notChatMessage,

  /// V2 chat message could not be decrypted because required local key
  /// material is not currently available.
  missingMlKemSecret,

  /// V2 chat message decryption failed cryptographically (Go-returned
  /// failure). Terminal for this attempt; the staged entry must be kept.
  decryptionFailed,

  /// V2 chat message decryption hit a transient infrastructure failure
  /// (bridge timeout or thrown bridge exception). Safe to retry later;
  /// the message content was never evaluated.
  decryptionDeferred,

  /// Sender is not a known contact.
  unknownSender,

  /// Duplicate message ID already stored.
  duplicate,

  /// Edit references an original message that is not stored locally.
  editMissingOriginal,

  /// Sender identifiers do not agree or the edit does not belong to the
  /// original author.
  unauthorized,

  /// Edit was ignored because it is stale, duplicate, or targets a deleted row.
  ignoredEdit,
}

/// Parses an incoming P2P ChatMessage for chat_message type,
/// validates the sender, checks for duplicates, and persists.
///
/// Returns (result, ConversationMessage?, ContactModel?) —
/// message is non-null on chatMessage, updatedContact is non-null when
/// the sender's username changed since last stored.
Future<(HandleChatMessageResult, ConversationMessage?, ContactModel?)>
handleIncomingChatMessage({
  required ChatMessage message,
  required MessageRepository messageRepo,
  required ContactRepository contactRepo,
  Bridge? bridge,
  String? ownMlKemSecretKey,
  // Prior ML-KEM secrets (newest first) tried in order when the primary
  // secret fails CRYPTOGRAPHICALLY — same-device recovery of traffic
  // encrypted to a pre-restore key (P0-B). Never consulted on transient
  // failures.
  List<String>? fallbackMlKemSecretKeys,
  MediaAttachmentRepository? mediaAttachmentRepo,
  // Used by the duplicate-replay media repair to invalidate staged
  // artifacts left behind by a previous key/nonce (112 Phase 1).
  MediaFileManager? mediaFileManager,
  String? transport,
  // 115 P2: delivery-receipt hook + arrival-origin marker. The hook fires
  // AFTER a durable persist (and on duplicate receives, closing the
  // lost-receipt repair loop) — but ONLY for relay-inbox arrivals per the
  // shared origin contract (shouldMintDeliveryReceipt): 'direct:'/'lan:'
  // staged replays are confirmed by their own acks.
  Future<void> Function(String messageId)? sendDeliveryReceipt,
  String? stagedEntryId,
}) async {
  Future<void> maybeSendDeliveryReceipt(String messageId) async {
    if (sendDeliveryReceipt == null) return;
    if (!shouldMintDeliveryReceipt(
      stagedEntryId: stagedEntryId,
      transport: transport,
    )) {
      return;
    }
    try {
      await sendDeliveryReceipt(messageId);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_HOOK_ERROR',
        details: {
          'id': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
          'error': e.toString(),
        },
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_RECEIVE_START',
    details: {
      'from': message.from.length > 10
          ? message.from.substring(0, 10)
          : message.from,
    },
  );

  // Log raw wire envelope
  logChatWireEnvelope(
    direction: 'IN',
    messageId: '',
    wireJson: message.content,
  );

  // 1. Try v2 encrypted envelope first, then fall back to v1 plaintext
  MessagePayload? payload;

  final v2Envelope = MessagePayload.parseEncryptedEnvelope(message.content);
  final envelopeSenderPeerId = v2Envelope?['senderPeerId'] as String?;
  if (v2Envelope != null) {
    // v2 encrypted message
    if (bridge == null || ownMlKemSecretKey == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_V2_NO_KEY',
        details: {},
      );
      return (HandleChatMessageResult.missingMlKemSecret, null, null);
    }

    final encrypted = v2Envelope['encrypted'] as Map<String, dynamic>;
    try {
      var decryptResult = await callDecryptMessage(
        bridge: bridge,
        ownMlKemSecretKey: ownMlKemSecretKey,
        kem: encrypted['kem'] as String,
        ciphertext: encrypted['ciphertext'] as String,
        nonce: encrypted['nonce'] as String,
      );

      if (decryptResult['ok'] != true) {
        // BRIDGE_TIMEOUT is synthesized on the Dart side (bridge.dart) when
        // the native call never answered — the ciphertext was never
        // evaluated, so the failure is transient, not cryptographic.
        if (decryptResult['errorCode'] == 'BRIDGE_TIMEOUT') {
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_RECEIVE_DECRYPT_DEFERRED',
            details: {'errorCode': decryptResult['errorCode']},
          );
          return (HandleChatMessageResult.decryptionDeferred, null, null);
        }

        // Cryptographic failure with the primary secret: the sender may
        // have encrypted to a pre-restore key — try the ring.
        for (final fallbackSecret in fallbackMlKemSecretKeys ?? const []) {
          final fallbackResult = await callDecryptMessage(
            bridge: bridge,
            ownMlKemSecretKey: fallbackSecret,
            kem: encrypted['kem'] as String,
            ciphertext: encrypted['ciphertext'] as String,
            nonce: encrypted['nonce'] as String,
          );
          if (fallbackResult['ok'] == true) {
            emitFlowEvent(
              layer: 'FL',
              event: 'MLKEM_RING_FALLBACK_USED',
              details: {},
            );
            decryptResult = fallbackResult;
            break;
          }
          if (fallbackResult['errorCode'] == 'BRIDGE_TIMEOUT') {
            emitFlowEvent(
              layer: 'FL',
              event: 'CHAT_MSG_RECEIVE_DECRYPT_DEFERRED',
              details: {'errorCode': fallbackResult['errorCode']},
            );
            return (HandleChatMessageResult.decryptionDeferred, null, null);
          }
        }

        if (decryptResult['ok'] != true) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_RECEIVE_DECRYPT_FAILED',
            details: {'errorCode': decryptResult['errorCode']},
          );
          return (HandleChatMessageResult.decryptionFailed, null, null);
        }
      }

      payload = MessagePayload.fromDecryptedJson(
        decryptResult['plaintext'] as String,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_DECRYPT_ERROR',
        details: {'error': e.toString()},
      );
      return (HandleChatMessageResult.decryptionDeferred, null, null);
    }
  } else {
    // v1 plaintext envelope
    payload = MessagePayload.fromJson(message.content);
  }

  if (payload == null) {
    emitFlowEvent(layer: 'FL', event: 'CHAT_MSG_RECEIVE_NOT_CHAT', details: {});
    return (HandleChatMessageResult.notChatMessage, null, null);
  }

  // Sanitize incoming text and username to strip bidi control characters
  payload = MessagePayload(
    id: payload.id,
    text: sanitizeMessageText(payload.text),
    senderPeerId: payload.senderPeerId,
    senderUsername: sanitizeUsername(payload.senderUsername),
    timestamp: payload.timestamp,
    action: payload.action,
    editedAt: payload.editedAt,
    quotedMessageId: payload.quotedMessageId,
    media: payload.media,
  );

  final textPreview = buildTextPreview(payload.text);

  // 2a. Require the stream sender and decrypted payload sender to agree.
  final senderMismatch =
      message.from != payload.senderPeerId ||
      (v2Envelope != null && envelopeSenderPeerId != payload.senderPeerId);
  if (senderMismatch) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_SENDER_MISMATCH',
      details: {
        'streamFrom': message.from.length > 10
            ? message.from.substring(0, 10)
            : message.from,
        'envelopeFrom': envelopeSenderPeerId == null
            ? '<missing>'
            : (envelopeSenderPeerId.length > 10
                  ? envelopeSenderPeerId.substring(0, 10)
                  : envelopeSenderPeerId),
        'payloadFrom': payload.senderPeerId.length > 10
            ? payload.senderPeerId.substring(0, 10)
            : payload.senderPeerId,
      },
    );
    return (HandleChatMessageResult.unauthorized, null, null);
  }

  // 2. Check sender is a known contact
  final contact = await contactRepo.getContact(payload.senderPeerId);
  if (contact == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_UNKNOWN_SENDER',
      details: {
        'senderPeerId': payload.senderPeerId.length > 10
            ? payload.senderPeerId.substring(0, 10)
            : payload.senderPeerId,
      },
    );
    return (HandleChatMessageResult.unknownSender, null, null);
  }

  // 3. Check for duplicate / same-ID edit update
  final existingMessage = await messageRepo.getMessage(payload.id);
  final shouldMaterializeDeferredEdit =
      existingMessage != null &&
      !payload.isEdit &&
      _isHiddenIncomingEditPlaceholder(existingMessage);
  final shouldPreserveDeletedPlaceholder =
      existingMessage != null &&
      !payload.isEdit &&
      _isIncomingDeletedPlaceholder(existingMessage);
  if (existingMessage != null &&
      !payload.isEdit &&
      !shouldMaterializeDeferredEdit &&
      !shouldPreserveDeletedPlaceholder) {
    if (payload.text != existingMessage.text) {
      final idPrefix = payload.id.length > 8
          ? payload.id.substring(0, 8)
          : payload.id;
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH',
        details: {
          'id': idPrefix,
          'incomingTextLength': payload.text.length,
          'existingTextLength': existingMessage.text.length,
          'existingHasEditedAt': existingMessage.editedAt != null,
        },
      );
    }
    await _repairDuplicateReplayMedia(
      payload: payload,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_DUPLICATE',
      details: {'id': payload.id.substring(0, 8)},
    );
    // Duplicate receive of an already-durable message: re-mint the receipt
    // (the sender may have missed the first one — D-5 repair loop).
    await maybeSendDeliveryReceipt(payload.id);
    return (HandleChatMessageResult.duplicate, null, null);
  }
  if (existingMessage == null && payload.isEdit) {
    final stagedEdit = _buildHiddenIncomingEditPlaceholder(
      payload: payload,
      transport: transport,
    );
    await messageRepo.saveMessage(stagedEdit);
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_EDIT_MISSING_ORIGINAL',
      details: {'id': payload.id.substring(0, 8)},
    );
    return (HandleChatMessageResult.editMissingOriginal, null, null);
  }

  if (payload.isEdit && existingMessage != null) {
    if (existingMessage.senderPeerId != payload.senderPeerId) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_EDIT_UNAUTHORIZED',
        details: {'id': payload.id.substring(0, 8)},
      );
      return (HandleChatMessageResult.unauthorized, null, null);
    }
    if (existingMessage.isDeleted) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_EDIT_IGNORED_DELETED',
        details: {'id': payload.id.substring(0, 8)},
      );
      return (HandleChatMessageResult.ignoredEdit, null, null);
    }
    final incomingEditedAt = payload.editedAt ?? payload.timestamp;
    final currentEditedAt = existingMessage.editedAt;
    if (currentEditedAt != null &&
        !_isIncomingEditNewer(
          incomingEditedAt: incomingEditedAt,
          currentEditedAt: currentEditedAt,
        )) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_EDIT_IGNORED_STALE',
        details: {'id': payload.id.substring(0, 8)},
      );
      return (HandleChatMessageResult.ignoredEdit, null, null);
    }
  }

  // 4. Detect + persist contact name change
  ContactModel? updatedContact;
  if (contact.username != payload.senderUsername) {
    updatedContact = contact.copyWith(username: payload.senderUsername);
    await contactRepo.addContact(updatedContact);
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_CONTACT_NAME_UPDATED',
      details: {
        'peerId': contact.peerId.length > 10
            ? contact.peerId.substring(0, 10)
            : contact.peerId,
        'oldName': contact.username,
        'newName': payload.senderUsername,
      },
    );
  }

  // 5. Persist message
  final resultAfterSave = shouldPreserveDeletedPlaceholder
      ? HandleChatMessageResult.duplicate
      : HandleChatMessageResult.chatMessage;
  final conversationMessage = shouldMaterializeDeferredEdit
      ? _materializeIncomingOriginalFromHiddenEdit(
          hiddenEditMessage: existingMessage!,
          payload: payload,
          transport: transport,
        )
      : shouldPreserveDeletedPlaceholder
      ? _mergeIncomingOriginalIntoDeletedPlaceholder(
          deletedMessage: existingMessage!,
          payload: payload,
          transport: transport,
        )
      : payload.isEdit && existingMessage != null
      ? existingMessage.copyWith(
          senderPeerId: payload.senderPeerId,
          text: payload.text,
          status: 'delivered',
          editedAt:
              payload.editedAt ?? DateTime.now().toUtc().toIso8601String(),
          quotedMessageId:
              payload.quotedMessageId ?? existingMessage.quotedMessageId,
          transport: transport ?? existingMessage.transport,
        )
      : payload.toConversationMessage(
          contactPeerId: payload.senderPeerId,
          isIncoming: true,
          status: 'delivered',
          editedAt: payload.editedAt,
          transport: transport,
        );
  await messageRepo.saveMessage(conversationMessage);
  // 115 P2: the message is durably persisted — confirm custody to the
  // sender (relay-drain arrivals only, per the origin contract).
  await maybeSendDeliveryReceipt(payload.id);
  if (shouldMaterializeDeferredEdit) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_EDIT_MATERIALIZED',
      details: {'id': payload.id.substring(0, 8)},
    );
  }
  if (shouldPreserveDeletedPlaceholder) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_ORIGINAL_IGNORED_AFTER_DELETE',
      details: {'id': payload.id.substring(0, 8)},
    );
  }

  // 6. Persist media attachment metadata and collect parsed attachments
  final parsedAttachments = <MediaAttachment>[];
  if (!shouldPreserveDeletedPlaceholder &&
      mediaAttachmentRepo != null &&
      payload.media != null) {
    for (final mediaJson in payload.media!) {
      final attachment = MediaAttachment.fromJson(
        mediaJson,
      ).copyWith(messageId: payload.id);
      await mediaAttachmentRepo.saveAttachment(attachment);
      parsedAttachments.add(attachment);
    }
  }

  // 7. Hydrate media on the returned message so downstream consumers
  // (notably ChatMessageListener.maybeShowNotification) can derive the
  // notification body from media metadata without a separate DB query.
  // This mirrors the send-path pattern at send_chat_message_use_case.dart:695.
  final hydratedMessage = parsedAttachments.isNotEmpty
      ? conversationMessage.copyWith(media: parsedAttachments)
      : conversationMessage;

  final storedTextPreview = buildTextPreview(conversationMessage.text);

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_RECEIVE_STORED',
    details: {
      'id': payload.id.substring(0, 8),
      'from': payload.senderPeerId.length > 10
          ? payload.senderPeerId.substring(0, 10)
          : payload.senderPeerId,
      'textPreview': storedTextPreview,
    },
  );
  logChatIncoming(
    messageId: payload.id,
    fromPeerId: payload.senderPeerId,
    status: 'delivered',
    text: conversationMessage.text,
  );
  if (resultAfterSave != HandleChatMessageResult.chatMessage) {
    return (resultAfterSave, null, updatedContact);
  }
  return (HandleChatMessageResult.chatMessage, hydratedMessage, updatedContact);
}

Future<void> _repairDuplicateReplayMedia({
  required MessagePayload payload,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  final incomingMedia = payload.media;
  if (mediaAttachmentRepo == null ||
      incomingMedia == null ||
      incomingMedia.isEmpty) {
    return;
  }

  final existingAttachments = await mediaAttachmentRepo
      .getAttachmentsForMessage(payload.id);
  final existingById = {
    for (final attachment in existingAttachments) attachment.id: attachment,
  };
  var repairedCount = 0;
  for (final mediaJson in incomingMedia) {
    final incoming = MediaAttachment.fromJson(
      mediaJson,
    ).copyWith(messageId: payload.id);
    final existing = existingById[incoming.id];
    if (existing != null && _isCompleteLocalMedia(existing)) {
      continue;
    }
    if (existing == null || _isRecoverableIncomingMediaStatus(existing)) {
      // A replay that carries DIFFERENT key/nonce supersedes whatever was
      // staged under the old metadata — the new key must never be asked to
      // decrypt old bytes (112 KC-2 receive side). Drop stale staged
      // artifacts before resetting the row.
      if (existing != null &&
          mediaFileManager != null &&
          (existing.encryptionKeyBase64 != incoming.encryptionKeyBase64 ||
              existing.encryptionNonce != incoming.encryptionNonce)) {
        await _invalidateStaleStagedArtifacts(
          mediaFileManager: mediaFileManager,
          contactPeerId: payload.senderPeerId,
          existing: existing,
        );
      }
      await mediaAttachmentRepo.saveAttachment(incoming);
      repairedCount++;
    }
  }

  if (repairedCount > 0) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_DUPLICATE_MEDIA_REPAIR',
      details: {'id': payload.id.substring(0, 8), 'count': repairedCount},
    );
  }
}

/// Deletes staged download artifacts (`.enc`/`.part`) that were produced
/// under a superseded key/nonce. Paths derive from the EXISTING row's mime —
/// that is the metadata the artifact was staged under.
Future<void> _invalidateStaleStagedArtifacts({
  required MediaFileManager mediaFileManager,
  required String contactPeerId,
  required MediaAttachment existing,
}) async {
  late final String absolutePath;
  try {
    absolutePath = await mediaFileManager.localPathForAttachment(
      contactPeerId: contactPeerId,
      blobId: existing.id,
      mime: existing.mime,
    );
  } catch (_) {
    return;
  }
  for (final suffix in const ['.enc', '.part']) {
    await deleteAppOwnedMediaFileIfExists(
      file: File('$absolutePath$suffix'),
      caller: 'handleIncomingChatMessage.invalidateStaleStagedArtifacts',
      reason: 'duplicate_replay_key_rotation',
      details: {
        'attachmentId': existing.id,
        'messageId': existing.messageId,
        'mime': existing.mime,
        'downloadStatus': existing.downloadStatus,
      },
      swallowErrors: true,
    );
  }
}

bool _isCompleteLocalMedia(MediaAttachment attachment) {
  return attachment.downloadStatus == 'done' &&
      attachment.localPath != null &&
      attachment.localPath!.isNotEmpty;
}

bool _isRecoverableIncomingMediaStatus(MediaAttachment attachment) {
  return attachment.downloadStatus == 'pending' ||
      attachment.downloadStatus == 'downloading' ||
      attachment.downloadStatus == 'failed' ||
      attachment.downloadStatus == 'integrity_failed';
}

bool _isHiddenIncomingEditPlaceholder(ConversationMessage message) {
  return message.isIncoming &&
      message.isHidden &&
      !message.isDeleted &&
      message.editedAt != null;
}

bool _isIncomingDeletedPlaceholder(ConversationMessage message) {
  return message.isIncoming && message.isDeleted;
}

ConversationMessage _buildHiddenIncomingEditPlaceholder({
  required MessagePayload payload,
  String? transport,
}) {
  final editedAt = payload.editedAt ?? payload.timestamp;
  return payload
      .toConversationMessage(
        contactPeerId: payload.senderPeerId,
        isIncoming: true,
        status: 'delivered',
        editedAt: editedAt,
        transport: transport,
      )
      .copyWith(hiddenAt: editedAt);
}

ConversationMessage _materializeIncomingOriginalFromHiddenEdit({
  required ConversationMessage hiddenEditMessage,
  required MessagePayload payload,
  String? transport,
}) {
  final original = payload.toConversationMessage(
    contactPeerId: payload.senderPeerId,
    isIncoming: true,
    status: 'delivered',
    transport: transport,
  );
  return original.copyWith(
    text: hiddenEditMessage.text,
    createdAt: hiddenEditMessage.createdAt,
    editedAt: hiddenEditMessage.editedAt,
    quotedMessageId:
        hiddenEditMessage.quotedMessageId ?? original.quotedMessageId,
    transport: transport ?? hiddenEditMessage.transport ?? original.transport,
    hiddenAt: null,
  );
}

ConversationMessage _mergeIncomingOriginalIntoDeletedPlaceholder({
  required ConversationMessage deletedMessage,
  required MessagePayload payload,
  String? transport,
}) {
  final original = payload.toConversationMessage(
    contactPeerId: payload.senderPeerId,
    isIncoming: true,
    status: deletedMessage.status,
    transport: transport,
  );
  return original.copyWith(
    text: '',
    createdAt: deletedMessage.createdAt,
    editedAt: deletedMessage.editedAt,
    quotedMessageId: deletedMessage.quotedMessageId ?? original.quotedMessageId,
    deletedAt: deletedMessage.deletedAt,
    deletedByPeerId: deletedMessage.deletedByPeerId,
    hiddenAt: deletedMessage.hiddenAt,
    transport: transport ?? deletedMessage.transport ?? original.transport,
    media: const [],
  );
}

bool _isIncomingEditNewer({
  required String incomingEditedAt,
  required String currentEditedAt,
}) {
  final incoming = DateTime.tryParse(incomingEditedAt);
  final current = DateTime.tryParse(currentEditedAt);
  if (incoming != null && current != null) {
    return incoming.isAfter(current);
  }
  return incomingEditedAt.compareTo(currentEditedAt) > 0;
}
