import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Loads all messages for a conversation with a contact.
///
/// Returns messages ordered by timestamp ASC.
Future<List<ConversationMessage>> loadConversation({
  required MessageRepository messageRepo,
  required String contactPeerId,
  MediaAttachmentRepository? mediaAttachmentRepo,
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

  return _attachMedia(messages, mediaAttachmentRepo);
}

/// Loads a single page of messages for a conversation.
///
/// Returns at most [pageSize] messages in chronological order.
/// When [beforeTimestamp] is null, returns the most recent page.
/// When provided, returns messages older than that cursor.
Future<List<ConversationMessage>> loadConversationPage({
  required MessageRepository messageRepo,
  required String contactPeerId,
  int pageSize = 50,
  String? beforeTimestamp,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_LOAD_PAGE_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
      'pageSize': pageSize,
      'hasCursor': beforeTimestamp != null,
    },
  );

  final messages = await messageRepo.getMessagesPage(
    contactPeerId,
    limit: pageSize,
    beforeTimestamp: beforeTimestamp,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_LOAD_PAGE_SUCCESS',
    details: {'count': messages.length},
  );

  return _attachMedia(messages, mediaAttachmentRepo);
}

/// Batch-loads media attachments and attaches them to messages.
Future<List<ConversationMessage>> _attachMedia(
  List<ConversationMessage> messages,
  MediaAttachmentRepository? mediaAttachmentRepo,
) async {
  if (mediaAttachmentRepo == null || messages.isEmpty) return messages;

  final ids = messages.map((m) => m.id).toList();
  final mediaMap = await mediaAttachmentRepo.getAttachmentsForMessages(ids);
  if (mediaMap.isEmpty) return messages;

  return messages
      .map((m) => m.copyWith(media: mediaMap[m.id] ?? const []))
      .toList();
}
