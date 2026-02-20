import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Loads all messages for a conversation with a contact.
///
/// Returns messages ordered by timestamp ASC.
Future<List<ConversationMessage>> loadConversation({
  required MessageRepository messageRepo,
  required String contactPeerId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
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

  return _attachMedia(messages, mediaAttachmentRepo, mediaFileManager);
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
  MediaFileManager? mediaFileManager,
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

  return _attachMedia(messages, mediaAttachmentRepo, mediaFileManager);
}

/// Batch-loads media attachments and attaches them to messages.
///
/// When [mediaFileManager] is provided, relative paths stored in the DB
/// are resolved to absolute paths for display.
Future<List<ConversationMessage>> _attachMedia(
  List<ConversationMessage> messages,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
) async {
  if (mediaAttachmentRepo == null || messages.isEmpty) return messages;

  final ids = messages.map((m) => m.id).toList();
  final mediaMap = await mediaAttachmentRepo.getAttachmentsForMessages(ids);
  if (mediaMap.isEmpty) return messages;

  // Resolve relative paths to absolute for display
  final resolvedMap = <String, List<MediaAttachment>>{};
  for (final entry in mediaMap.entries) {
    final resolved = <MediaAttachment>[];
    for (final attachment in entry.value) {
      if (attachment.localPath != null && mediaFileManager != null) {
        final absolutePath =
            await mediaFileManager.resolveStoredPath(attachment.localPath!);
        resolved.add(attachment.copyWith(localPath: absolutePath));
      } else {
        resolved.add(attachment);
      }
    }
    resolvedMap[entry.key] = resolved;
  }

  return messages
      .map((m) => m.copyWith(media: resolvedMap[m.id] ?? const []))
      .toList();
}
