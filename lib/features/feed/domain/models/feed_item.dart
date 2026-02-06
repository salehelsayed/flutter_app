import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';

/// Types of feed items.
enum FeedItemType {
  connection,
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

  const ConnectionFeedItem({
    required super.id,
    required super.timestamp,
    required this.contactPeerId,
    required this.contactUsername,
    this.contactAvatarPath,
  }) : super(type: FeedItemType.connection);

  /// Creates a ConnectionFeedItem from a ContactModel.
  factory ConnectionFeedItem.fromContact(ContactModel contact) {
    return ConnectionFeedItem(
      id: 'connection_${contact.peerId}',
      timestamp: DateTime.now(),
      contactPeerId: contact.peerId,
      contactUsername: contact.username,
      contactAvatarPath: contact.avatarPath,
    );
  }
}
