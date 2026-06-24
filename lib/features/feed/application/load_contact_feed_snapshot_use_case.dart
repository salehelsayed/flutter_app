import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_thread_summary.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_thread_summary_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/group_messages_into_threads.dart';

class ContactFeedSnapshot {
  final ConnectionFeedItem? connectionItem;
  final ThreadFeedItem? threadItem;

  const ContactFeedSnapshot({this.connectionItem, this.threadItem});
}

/// Rebuilds a single contact's feed snapshot (used by every per-event refresh:
/// send / delete / hide / nav-return).
///
/// When [pageSize] is provided (160 db-persistence-3), the thread is loaded
/// through a bounded, NEWEST-first, media-resolved page ([loadConversationPage])
/// instead of the unbounded [loadConversation], and its counts/state come from
/// the batched [ConversationThreadSummary] so a deep thread is not undercounted
/// by the page bound and a just-drained newest message stays visible as the
/// latest. [pageSize] null keeps the legacy unbounded behaviour (parity callers).
Future<ContactFeedSnapshot> loadContactFeedSnapshot({
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  required String contactPeerId,
  int? pageSize,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  final contact = await contactRepo.getContact(contactPeerId);
  if (contact == null || contact.isArchived) {
    return const ContactFeedSnapshot();
  }

  final List<ConversationMessage> messages;
  ConversationThreadSummary? summary;
  if (pageSize != null) {
    messages = await loadConversationPage(
      messageRepo: messageRepo,
      contactPeerId: contactPeerId,
      pageSize: pageSize,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
    );
    if (messageRepo is ConversationThreadSummaryRepository) {
      summary = await (messageRepo as ConversationThreadSummaryRepository)
          .getConversationThreadSummary(contactPeerId);
    }
  } else {
    messages = await loadConversation(
      messageRepo: messageRepo,
      contactPeerId: contactPeerId,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
    );
  }

  final threadItem = groupMessagesIntoThreads(
    allMessages: messages,
    contactUsernames: {contact.peerId: contact.username},
    contactBlocked: {contact.peerId: contact.isBlocked},
    totalMessageCounts: summary == null
        ? const {}
        : {contact.peerId: summary.messageCount},
    unreadCounts: summary == null
        ? const {}
        : {contact.peerId: summary.unreadCount},
    lastOutgoingAtByContact: summary == null
        ? const {}
        : {contact.peerId: summary.lastOutgoingAt},
  ).firstOrNull;

  return ContactFeedSnapshot(
    connectionItem: ConnectionFeedItem.fromContact(
      contact,
      hasConversationHistory: (summary?.messageCount ?? messages.length) > 0,
    ),
    threadItem: threadItem,
  );
}
