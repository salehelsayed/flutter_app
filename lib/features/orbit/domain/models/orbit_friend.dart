import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';

/// Composite model combining a contact with conversation activity data.
///
/// Used by the Orbit screen to determine ring placement (sorted by messageCount)
/// and display activity info in the friends list.
class OrbitFriend {
  final ContactModel contact;
  final int messageCount;
  final String? lastActivity;
  final String? lastMessageTimestamp;
  final int unreadCount;

  const OrbitFriend({
    required this.contact,
    required this.messageCount,
    this.lastActivity,
    this.lastMessageTimestamp,
    this.unreadCount = 0,
  });

  String get peerId => contact.peerId;
  String get username => contact.username;
  String get scannedAt => contact.scannedAt;
  String? get avatarPath => contact.avatarPath;
  bool get isArchived => contact.isArchived;
  bool get isBlocked => contact.isBlocked;
}
