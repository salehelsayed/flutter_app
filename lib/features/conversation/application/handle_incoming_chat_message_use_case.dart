import 'package:flutter_app/core/bridge/js_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/chat_console_logger.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Result of handling an incoming chat message.
enum HandleChatMessageResult {
  /// Valid chat message received and stored.
  chatMessage,

  /// Not a chat_message type — ignore.
  notChatMessage,

  /// Sender is not a known contact.
  unknownSender,

  /// Duplicate message ID already stored.
  duplicate,
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
  JsBridge? bridge,
  String? ownMlKemSecretKey,
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
  if (v2Envelope != null) {
    // v2 encrypted message
    if (bridge == null || ownMlKemSecretKey == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_V2_NO_KEY',
        details: {},
      );
      return (HandleChatMessageResult.notChatMessage, null, null);
    }

    final encrypted = v2Envelope['encrypted'] as Map<String, dynamic>;
    try {
      final decryptResult = await callJsDecryptMessage(
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
          details: {
            'errorCode': decryptResult['errorCode'],
          },
        );
        return (HandleChatMessageResult.notChatMessage, null, null);
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
      return (HandleChatMessageResult.notChatMessage, null, null);
    }
  } else {
    // v1 plaintext envelope
    payload = MessagePayload.fromJson(message.content);
  }

  if (payload == null) {
    emitFlowEvent(layer: 'FL', event: 'CHAT_MSG_RECEIVE_NOT_CHAT', details: {});
    return (HandleChatMessageResult.notChatMessage, null, null);
  }
  final textPreview = buildTextPreview(payload.text);

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

  // 3. Check for duplicate
  final exists = await messageRepo.messageExists(payload.id);
  if (exists) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_DUPLICATE',
      details: {'id': payload.id.substring(0, 8)},
    );
    return (HandleChatMessageResult.duplicate, null, null);
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
  final conversationMessage = payload.toConversationMessage(
    contactPeerId: payload.senderPeerId,
    isIncoming: true,
    status: 'delivered',
  );
  await messageRepo.saveMessage(conversationMessage);

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_RECEIVE_STORED',
    details: {
      'id': payload.id.substring(0, 8),
      'from': payload.senderPeerId.length > 10
          ? payload.senderPeerId.substring(0, 10)
          : payload.senderPeerId,
      'textPreview': textPreview,
    },
  );
  logChatIncoming(
    messageId: payload.id,
    fromPeerId: payload.senderPeerId,
    status: 'delivered',
    text: payload.text,
  );
  return (
    HandleChatMessageResult.chatMessage,
    conversationMessage,
    updatedContact,
  );
}
