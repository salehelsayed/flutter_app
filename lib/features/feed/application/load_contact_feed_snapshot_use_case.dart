import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/group_messages_into_threads.dart';

class ContactFeedSnapshot {
  final ConnectionFeedItem? connectionItem;
  final ThreadFeedItem? threadItem;

  const ContactFeedSnapshot({this.connectionItem, this.threadItem});
}

Future<ContactFeedSnapshot> loadContactFeedSnapshot({
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  required String contactPeerId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  final contact = await contactRepo.getContact(contactPeerId);
  if (contact == null || contact.isArchived) {
    return const ContactFeedSnapshot();
  }

  final messages = await loadConversation(
    messageRepo: messageRepo,
    contactPeerId: contactPeerId,
    mediaAttachmentRepo: mediaAttachmentRepo,
    mediaFileManager: mediaFileManager,
  );

  final threadItem = groupMessagesIntoThreads(
    allMessages: messages,
    contactUsernames: {contact.peerId: contact.username},
    contactBlocked: {contact.peerId: contact.isBlocked},
  ).firstOrNull;

  return ContactFeedSnapshot(
    connectionItem: ConnectionFeedItem.fromContact(contact),
    threadItem: threadItem,
  );
}
