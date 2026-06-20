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

  const OrbitFriend({
    required this.contact,
    required this.messageCount,
    this.lastActivity,
    this.lastMessageTimestamp,
    this.unreadCount = 0,
    this.latestMedia,
    this.isLatestDeleted = false,
  });

  String get peerId => contact.peerId;
  String get username => contact.username;
  String get scannedAt => contact.scannedAt;
  String? get avatarPath => contact.avatarPath;
  bool get isArchived => contact.isArchived;
  bool get isBlocked => contact.isBlocked;
}
