import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Loads all messages for a conversation with a contact.
///
/// Returns messages ordered by timestamp ASC.
Future<List<ConversationMessage>> loadConversation({
  required MessageRepository messageRepo,
  required String contactPeerId,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_LOAD_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
    },
  );

  final messages = await messageRepo.getMessagesForContact(contactPeerId);

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_LOAD_SUCCESS',
    details: {'count': messages.length},
  );

  return messages;
}
