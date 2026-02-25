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

  /// Maximum number of unread messages visible in open-mode preview.
  static const int maxPreview = 3;

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

  /// All unread incoming messages in chronological order.
  List<ThreadMessage> get unreadMessages =>
      messages.where((m) => m.isUnread && m.isIncoming).toList();

  /// First [maxPreview] unread messages for open-mode card.
  List<ThreadMessage> get previewMessages {
    final unread = unreadMessages;
    if (unread.length <= maxPreview) return unread;
    return unread.sublist(0, maxPreview);
  }

  /// True when read messages exist before the first unread.
  bool get hasEarlierHistory {
    final unread = unreadMessages;
    if (unread.isEmpty) return messages.isNotEmpty;
    final firstUnreadIndex = messages.indexOf(unread.first);
    return firstUnreadIndex > 0;
  }

  /// Most recent outgoing message, or null if none.
  ThreadMessage? get lastSentMessage {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (!messages[i].isIncoming) return messages[i];
    }
    return null;
  }

  /// True for unread/active states (open-mode card), false for read/replied.
  bool get isOpenMode =>
      conversationState == ConversationState.unread ||
      conversationState == ConversationState.active;

  /// Messages to show in expanded collapsed card: from first unread onward,
  /// or tail context (last [maxPreview]) when all are read.
  List<ThreadMessage> get recentInteractionMessages {
    if (messages.isEmpty) return const [];
    final firstUnreadIndex =
        messages.indexWhere((m) => m.isUnread && m.isIncoming);
    if (firstUnreadIndex >= 0) return messages.sublist(firstUnreadIndex);
    // No unread — show tail context
    if (messages.length <= maxPreview) return messages;
    return messages.sublist(messages.length - maxPreview);
  }

  /// Whether messages exist before the interaction window shown in expanded
  /// collapsed card (used to decide "View earlier messages" link).
  bool get hasEarlierInteractionHistory {
    if (messages.isEmpty) return false;
    final firstUnreadIndex =
        messages.indexWhere((m) => m.isUnread && m.isIncoming);
    if (firstUnreadIndex > 0) return true;
    if (firstUnreadIndex == 0) return false;
    return messages.length > maxPreview;
  }

  /// Single message to show in collapsed card: always the latest message.
  ThreadMessage get collapsedPreviewMessage => latestMessage;
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
