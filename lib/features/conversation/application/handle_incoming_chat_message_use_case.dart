import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/core/utils/chat_console_logger.dart';
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

  /// V2 chat message decryption failed.
  decryptionFailed,

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
  MediaAttachmentRepository? mediaAttachmentRepo,
  String? transport,
}) async {
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
      final decryptResult = await callDecryptMessage(
        bridge: bridge,
        ownMlKemSecretKey: ownMlKemSecretKey,
        kem: encrypted['kem'] as String,
        ciphertext: encrypted['ciphertext'] as String,
        nonce: encrypted['nonce'] as String,
      );

      if (decryptResult['ok'] != true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_RECEIVE_DECRYPT_FAILED',
          details: {'errorCode': decryptResult['errorCode']},
        );
        return (HandleChatMessageResult.decryptionFailed, null, null);
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
      return (HandleChatMessageResult.decryptionFailed, null, null);
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
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_DUPLICATE',
      details: {'id': payload.id.substring(0, 8)},
    );
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
