import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

/// Types of feed items.
enum FeedItemType { connection, message, thread, groupThread }

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
  final String? connectedVia;
  final String? introducedBy;
  final String? introducedByPeerId;

  /// True when this contact already has conversation history
  /// (`summary.messageCount > 0`), even if no [ThreadFeedItem] was materialized
  /// for them on this mount (160 A1 pending-filter loads ZERO messages for
  /// all-read contacts). The pending projection suppresses the "new connection"
  /// letter for any contact with history, so an all-read contact does not
  /// resurface as a brand-new connection (160 A5 / TC-160-21). Defaults to
  /// false so a genuinely-new contact (no history) still shows its letter.
  final bool hasConversationHistory;

  const ConnectionFeedItem({
    required super.id,
    required super.timestamp,
    required this.contactPeerId,
    required this.contactUsername,
    this.contactAvatarPath,
    this.isBlocked = false,
    this.connectedVia,
    this.introducedBy,
    this.introducedByPeerId,
    this.hasConversationHistory = false,
  }) : super(type: FeedItemType.connection);

  /// Creates a ConnectionFeedItem from a ContactModel.
  factory ConnectionFeedItem.fromContact(
    ContactModel contact, {
    bool hasConversationHistory = false,
  }) {
    return ConnectionFeedItem(
      id: 'connection_${contact.peerId}',
      timestamp: DateTime.tryParse(contact.scannedAt) ?? DateTime.now(),
      contactPeerId: contact.peerId,
      contactUsername: contact.username,
      contactAvatarPath: contact.avatarPath,
      isBlocked: contact.isBlocked,
      introducedBy: contact.introducedBy,
      introducedByPeerId: contact.introducedByPeerId,
      hasConversationHistory: hasConversationHistory,
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
  final bool isDeleted;
  final String? status;
  final String? editedAt;
  final String? quotedMessageId;
  final List<MediaAttachment> media;
  final String? senderUsername;
  final String? senderPeerId;

  const ThreadMessage({
    required this.id,
    required this.text,
    required this.time,
    required this.timestamp,
    this.isUnread = false,
    this.isIncoming = true,
    this.isDeleted = false,
    this.status,
    this.editedAt,
    this.quotedMessageId,
    this.media = const [],
    this.senderUsername,
    this.senderPeerId,
  });

  bool get isEdited => editedAt != null;
}

/// Abstract base for thread-based feed items rendered as feed cards.
///
/// Both [ThreadFeedItem] (1:1) and [GroupThreadFeedItem] (group) extend this,
/// allowing [FeedCard], [OpenModeCardBody], and [CollapsedModeCardBody] to
/// accept either type.
abstract class CardThreadFeedItem extends FeedItem {
  const CardThreadFeedItem({
    required super.id,
    required super.timestamp,
    required super.type,
  });

  /// Maximum number of unread messages visible in open-mode preview.
  static const int maxPreview = 3;

  List<ThreadMessage> get messages;
  int get unreadCount;
  ConversationState get conversationState;

  /// Total non-deleted message count for the whole thread, independent of how
  /// many messages are loaded into [messages]. For a windowed preview this is
  /// sourced from `summary.messageCount` (160 A3); when no window is in play it
  /// equals `messages.length`. "View earlier" / `additionalCount` derive from
  /// this so a capped preview never loses the older-history affordance.
  int get totalMessageCount;

  // Display
  String get displayName;
  String get displayId;
  bool get isGroup;

  // 1:1-specific (safe defaults for groups)
  bool get isBlocked;
  DateTime? get lastRepliedAt;
  bool get isUnreadCard;

  // Computed getters (shared logic)
  bool get isMultiMessage => messages.length > 1;
  ThreadMessage get latestMessage => messages.last;

  /// Count of messages beyond the latest, sourced from [totalMessageCount] so a
  /// windowed preview reports the true "+N earlier" rather than the loaded
  /// slice size (160 A3/A7). Equals `messages.length - 1` when no window is in
  /// play (`totalMessageCount` defaults to `messages.length`).
  int get additionalCount => totalMessageCount - 1;

  /// Last 2 messages for exchange preview in collapsed card.
  List<ThreadMessage> get exchangePreview {
    if (messages.length <= 2) return messages;
    return messages.sublist(messages.length - 2);
  }

  /// Whether the thread contains any sent (outgoing) message. Honors
  /// [lastRepliedAt] (sourced from `summary.lastOutgoingAt`, 160 A4) so a window
  /// that excludes the answering outgoing does not false-negative `hasReply`.
  bool get hasReply =>
      lastRepliedAt != null ||
      messages.any((m) => !m.isIncoming && !m.isDeleted);

  /// All unread incoming messages in chronological order.
  List<ThreadMessage> get unreadMessages => messages
      .where((m) => m.isUnread && m.isIncoming && !m.isDeleted)
      .toList();

  /// First [maxPreview] unread messages for open-mode card.
  List<ThreadMessage> get previewMessages {
    final unread = unreadMessages;
    if (unread.length <= maxPreview) return unread;
    return unread.sublist(0, maxPreview);
  }

  /// True when read messages exist before the first unread. Derives from
  /// [totalMessageCount] first (160 A7) so a windowed preview that dropped the
  /// older history still surfaces the "View earlier" affordance.
  bool get hasEarlierHistory {
    if (totalMessageCount > messages.length) return true;
    final unread = unreadMessages;
    if (unread.isEmpty) return messages.isNotEmpty;
    final firstUnreadIndex = messages.indexOf(unread.first);
    return firstUnreadIndex > 0;
  }

  /// Most recent outgoing message, or null if none.
  ThreadMessage? get lastSentMessage {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (!messages[i].isIncoming && !messages[i].isDeleted) return messages[i];
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
    final firstUnreadIndex = messages.indexWhere(
      (m) => m.isUnread && m.isIncoming,
    );
    if (firstUnreadIndex >= 0) return messages.sublist(firstUnreadIndex);
    // No unread — show tail context
    if (messages.length <= maxPreview) return messages;
    return messages.sublist(messages.length - maxPreview);
  }

  /// Whether messages exist before the interaction window shown in expanded
  /// collapsed card (used to decide "View earlier messages" link).
  bool get hasEarlierInteractionHistory {
    if (messages.isEmpty) return false;
    // A windowed preview that dropped older history always has earlier
    // interaction (160 A7).
    if (totalMessageCount > messages.length) return true;
    final firstUnreadIndex = messages.indexWhere(
      (m) => m.isUnread && m.isIncoming,
    );
    if (firstUnreadIndex > 0) return true;
    if (firstUnreadIndex == 0) return false;
    return messages.length > maxPreview;
  }

  /// Single message to show in collapsed card: always the latest message.
  ThreadMessage get collapsedPreviewMessage => latestMessage;
}

/// A feed item representing a thread of messages from a contact.
///
/// Groups multiple messages (sent and received) from the same contact,
/// split by 24-hour time gaps. Derives conversation state from message
/// read status and direction.
class ThreadFeedItem extends CardThreadFeedItem {
  final String contactPeerId;
  final String contactUsername;
  @override
  final List<ThreadMessage> messages;
  @override
  final int unreadCount;
  @override
  final bool isUnreadCard;
  @override
  final ConversationState conversationState;
  @override
  final DateTime? lastRepliedAt;
  @override
  final bool isBlocked;

  /// Explicit total (from `summary.messageCount`) when the [messages] list is a
  /// windowed preview; null means "no window" → falls back to `messages.length`.
  final int? _totalMessageCount;

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
    int? totalMessageCount,
  }) : _totalMessageCount = totalMessageCount,
       super(type: FeedItemType.thread);

  @override
  int get totalMessageCount => _totalMessageCount ?? messages.length;

  @override
  String get displayName => contactUsername;
  @override
  String get displayId => contactPeerId;
  @override
  bool get isGroup => false;
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

/// A feed item representing a thread of messages in a group.
///
/// Groups multiple messages from the same group conversation.
/// Derives conversation state from message read status and direction.
class GroupThreadFeedItem extends CardThreadFeedItem {
  final String groupId;
  final String groupName;
  final GroupType groupType;
  final GroupRole myRole;
  final bool isDissolved;
  final String? avatarPath;
  final String? avatarCacheBustKey;
  @override
  final List<ThreadMessage> messages;
  @override
  final int unreadCount;
  @override
  final ConversationState conversationState;

  /// Explicit total (from `summary.messageCount`, 161 G3) when [messages] is a
  /// windowed preview; null means "no window" → falls back to `messages.length`.
  final int? _totalMessageCount;

  /// Timestamp of the newest outgoing message anywhere in the group (from
  /// `summary.lastOutgoingAt`, 161 G4), so `hasReply` / `hasSentMessage` /
  /// `conversationState` stay correct when an old reply sits OFF the loaded
  /// window. Null when no window is in play (legacy full-list builder) → the
  /// list scan answers `hasSentMessage`. Unlike 1:1, group sort/divider key on
  /// the latest-message timestamp, not this, so it is purely a state signal.
  final DateTime? _lastRepliedAt;

  const GroupThreadFeedItem({
    required super.id,
    required super.timestamp,
    required this.groupId,
    required this.groupName,
    required this.groupType,
    this.myRole = GroupRole.member,
    this.isDissolved = false,
    this.avatarPath,
    this.avatarCacheBustKey,
    required this.messages,
    this.unreadCount = 0,
    this.conversationState = ConversationState.read,
    int? totalMessageCount,
    DateTime? lastRepliedAt,
  }) : _totalMessageCount = totalMessageCount,
       _lastRepliedAt = lastRepliedAt,
       super(type: FeedItemType.groupThread);

  @override
  int get totalMessageCount => _totalMessageCount ?? messages.length;

  @override
  String get displayName => groupName;
  @override
  String get displayId => groupId;
  @override
  bool get isGroup => true;
  @override
  bool get isBlocked => false;
  @override
  DateTime? get lastRepliedAt => _lastRepliedAt;
  @override
  bool get isUnreadCard => false;

  bool get canWrite =>
      !isDissolved &&
      (groupType != GroupType.announcement || myRole == GroupRole.admin);

  bool get canReact => !isDissolved;

  String get readOnlyBannerText => isDissolved
      ? 'This group has been dissolved. History stays available, but new messages are disabled.'
      : 'Only admins can send messages in this group';

  /// Whether the thread contains any sent (outgoing) message. Honors
  /// [lastRepliedAt] (from `summary.lastOutgoingAt`, 161 G4) so a window that
  /// excludes the answering outgoing does not false-negative `hasSentMessage`.
  bool get hasSentMessage =>
      lastRepliedAt != null || messages.any((m) => !m.isIncoming);
}
