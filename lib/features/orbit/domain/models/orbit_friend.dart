import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';

/// Composite model combining a contact with conversation activity data.
///
/// Used by the Orbit screen to determine ring placement (sorted by messageCount)
/// and display activity info in the friends list.
class OrbitFriend {
  final ContactModel contact;
  final int messageCount;

  /// The latest message's caption/text, or null. Empty-but-present text on a
  /// media-only message is NOT a caption — the row falls back to [latestMedia].
  final String? lastActivity;
  final String? lastMessageTimestamp;
  final int unreadCount;

  /// Key-free media summary of the latest message, when it carries attachments
  /// (and is not soft-deleted). Drives the "Photo"/"Voice message" preview
  /// label when [lastActivity] is empty. Null for text-only or empty threads.
  final MediaPreviewDescriptor? latestMedia;

  /// True when the latest message is soft-deleted; the row then shows the
  /// localized "message deleted" placeholder instead of any media label.
  final bool isLatestDeleted;

  /// 409: the newest terminal call, set ONLY when it is newer than the latest
  /// message. Null therefore means "a message is the most recent thing here",
  /// which keeps the row's preview rule a single null check.
  final ConversationCallTimelineEntry? latestCall;

  const OrbitFriend({
    required this.contact,
    required this.messageCount,
    this.lastActivity,
    this.lastMessageTimestamp,
    this.unreadCount = 0,
    this.latestMedia,
    this.isLatestDeleted = false,
    this.latestCall,
  });

  String get peerId => contact.peerId;
  String get username => contact.username;
  String get scannedAt => contact.scannedAt;
  String? get avatarPath => contact.avatarPath;
  bool get isArchived => contact.isArchived;
  bool get isBlocked => contact.isBlocked;

  /// 409: the newest thing that happened in this conversation — a message or
  /// a terminal call. Orbit orders rows and renders relative time by this, so
  /// a call cannot leave a contact stranded at the bottom of the ring.
  ///
  /// A call contributes its END: that is when the conversation last had
  /// activity. The chat timeline orders by start instead, because there a call
  /// must sit where it began relative to the messages around it.
  String? get lastActivityAt {
    final call = latestCall;
    if (call == null) return lastMessageTimestamp;
    return call.endedAt.toIso8601String();
  }
}
