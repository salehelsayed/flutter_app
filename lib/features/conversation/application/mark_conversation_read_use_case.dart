import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Marks all unread incoming messages for a conversation as read.
///
/// Returns the number of messages that were marked as read.
Future<int> markConversationRead({
  required MessageRepository messageRepo,
  required String contactPeerId,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'MARK_CONVERSATION_READ_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
    },
  );

  final count = await messageRepo.markConversationAsRead(contactPeerId);

  emitFlowEvent(
    layer: 'UC',
    event: 'MARK_CONVERSATION_READ_SUCCESS',
    details: {'markedCount': count},
  );

  return count;
}
