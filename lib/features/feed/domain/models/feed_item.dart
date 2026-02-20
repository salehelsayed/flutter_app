import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

/// Types of feed items.
enum FeedItemType {
  connection,
  message,
  thread,
}

/// Conversation state for a thread card.
enum ConversationState {
  /// Has unread incoming messages, no sent messages in thread.
  unread,

  /// Has unread incoming AND sent messages in thread.
  active,

  /// All incoming read, has sent messages in thread.
  replied,

  /// All incoming read, no sent messages in thread.
  read,
}

/// Base class for all feed items.
abstract class FeedItem {
  final String id;
  final DateTime timestamp;
  final FeedItemType type;

  const FeedItem({
    required this.id,
    required this.timestamp,
    required this.type,
  });
}

/// A feed item representing a new connection with a contact.
class ConnectionFeedItem extends FeedItem {
  final String contactPeerId;
  final String contactUsername;
  final String? contactAvatarPath;
  final bool isBlocked;

  const ConnectionFeedItem({
    required super.id,
    required super.timestamp,
    required this.contactPeerId,
    required this.contactUsername,
    this.contactAvatarPath,
    this.isBlocked = false,
  }) : super(type: FeedItemType.connection);

  /// Creates a ConnectionFeedItem from a ContactModel.
  factory ConnectionFeedItem.fromContact(ContactModel contact) {
    return ConnectionFeedItem(
      id: 'connection_${contact.peerId}',
      timestamp: DateTime.tryParse(contact.scannedAt) ?? DateTime.now(),
      contactPeerId: contact.peerId,
      contactUsername: contact.username,
      contactAvatarPath: contact.avatarPath,
      isBlocked: contact.isBlocked,
    );
  }
}

/// A single message within a thread group.
class ThreadMessage {
  final String id;
  final String text;
  final String time;
  final DateTime timestamp;
  final bool isUnread;
  final bool isIncoming;
  final String? status;
  final String? quotedMessageId;
  final List<MediaAttachment> media;

  const ThreadMessage({
    required this.id,
    required this.text,
    required this.time,
    required this.timestamp,
    this.isUnread = false,
    this.isIncoming = true,
    this.status,
    this.quotedMessageId,
    this.media = const [],
  });
}

/// A feed item representing a thread of messages from a contact.
///
/// Groups multiple messages (sent and received) from the same contact,
/// split by 24-hour time gaps. Derives conversation state from message
/// read status and direction.
class ThreadFeedItem extends FeedItem {
  final String contactPeerId;
  final String contactUsername;
  final List<ThreadMessage> messages;
  final int unreadCount;
  final bool isUnreadCard;
  final ConversationState conversationState;
  final DateTime? lastRepliedAt;
  final bool isBlocked;

  const ThreadFeedItem({
    required super.id,
    required super.timestamp,
    required this.contactPeerId,
    required this.contactUsername,
    required this.messages,
    this.unreadCount = 0,
    this.isUnreadCard = false,
    this.conversationState = ConversationState.read,
    this.lastRepliedAt,
    this.isBlocked = false,
  }) : super(type: FeedItemType.thread);

  bool get isMultiMessage => messages.length > 1;
  ThreadMessage get latestMessage => messages.last;
  int get additionalCount => messages.length - 1;

  /// Last 2 messages for exchange preview in collapsed card.
  List<ThreadMessage> get exchangePreview {
    if (messages.length <= 2) return messages;
    return messages.sublist(messages.length - 2);
  }

  /// Whether the thread contains any sent (outgoing) message.
  bool get hasReply => messages.any((m) => !m.isIncoming);
}

/// A feed item representing an incoming message from a contact.
class MessageFeedItem extends FeedItem {
  final String contactPeerId;
  final String contactUsername;
  final String messageId;
  final String messageText;
  final String messageTime;
  final int unreadCount;

  const MessageFeedItem({
    required super.id,
    required super.timestamp,
    required this.contactPeerId,
    required this.contactUsername,
    required this.messageId,
    required this.messageText,
    required this.messageTime,
    this.unreadCount = 0,
  }) : super(type: FeedItemType.message);
}
