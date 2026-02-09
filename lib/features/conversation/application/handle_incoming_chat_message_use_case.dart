import 'package:flutter_app/core/utils/flow_event_emitter.dart';
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
/// Returns (result, ConversationMessage?) — message is non-null on chatMessage.
Future<(HandleChatMessageResult, ConversationMessage?)>
    handleIncomingChatMessage({
  required ChatMessage message,
  required MessageRepository messageRepo,
  required ContactRepository contactRepo,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_RECEIVE_START',
    details: {'from': message.from.length > 10 ? message.from.substring(0, 10) : message.from},
  );

  // 1. Parse as MessagePayload
  final payload = MessagePayload.fromJson(message.content);
  if (payload == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_NOT_CHAT',
      details: {},
    );
    return (HandleChatMessageResult.notChatMessage, null);
  }

  // 2. Check sender is a known contact
  final isContact = await contactRepo.contactExists(payload.senderPeerId);
  if (!isContact) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_UNKNOWN_SENDER',
      details: {
        'senderPeerId': payload.senderPeerId.length > 10
            ? payload.senderPeerId.substring(0, 10)
            : payload.senderPeerId,
      },
    );
    return (HandleChatMessageResult.unknownSender, null);
  }

  // 3. Check for duplicate
  final exists = await messageRepo.messageExists(payload.id);
  if (exists) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_DUPLICATE',
      details: {'id': payload.id.substring(0, 8)},
    );
    return (HandleChatMessageResult.duplicate, null);
  }

  // 4. Persist
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
    },
  );
  return (HandleChatMessageResult.chatMessage, conversationMessage);
}
