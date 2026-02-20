import 'media_attachment.dart';

/// Model representing a single message in a conversation.
///
/// Maps to the `messages` database table. Each message belongs to a
/// conversation identified by `contactPeerId`.
class ConversationMessage {
  /// Unique message ID (UUID v4).
  final String id;

  /// The peer ID of the contact this conversation belongs to.
  final String contactPeerId;

  /// The peer ID of the message sender.
  final String senderPeerId;

  /// The message text content.
  final String text;

  /// ISO-8601 timestamp when the message was created.
  final String timestamp;

  /// Delivery status: 'sending', 'sent', 'delivered', 'failed'.
  final String status;

  /// Whether this message was received from the contact.
  final bool isIncoming;

  /// ISO-8601 timestamp when the row was created locally.
  final String createdAt;

  /// ISO-8601 timestamp when the message was read. NULL means unread.
  final String? readAt;

  /// The ID of the message being quoted (quote-reply). NULL means no quote.
  final String? quotedMessageId;

  /// Transient media attachments — populated via copyWith() after batch-loading
  /// from media_attachments table. NOT serialized to DB.
  final List<MediaAttachment> media;

  const ConversationMessage({
    required this.id,
    required this.contactPeerId,
    required this.senderPeerId,
    required this.text,
    required this.timestamp,
    required this.status,
    required this.isIncoming,
    required this.createdAt,
    this.readAt,
    this.quotedMessageId,
    this.media = const [],
  });

  /// Creates a ConversationMessage from a database row map.
  factory ConversationMessage.fromMap(Map<String, dynamic> map) {
    return ConversationMessage(
      id: map['id'] as String,
      contactPeerId: map['contact_peer_id'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      text: map['text'] as String,
      timestamp: map['timestamp'] as String,
      status: map['status'] as String? ?? 'sent',
      isIncoming: (map['is_incoming'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as String,
      readAt: map['read_at'] as String?,
      quotedMessageId: map['quoted_message_id'] as String?,
    );
  }

  /// Converts the model to a database row map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contact_peer_id': contactPeerId,
      'sender_peer_id': senderPeerId,
      'text': text,
      'timestamp': timestamp,
      'status': status,
      'is_incoming': isIncoming ? 1 : 0,
      'created_at': createdAt,
      'read_at': readAt,
      'quoted_message_id': quotedMessageId,
    };
  }

  /// Creates a copy with updated fields.
  ConversationMessage copyWith({
    String? id,
    String? contactPeerId,
    String? senderPeerId,
    String? text,
    String? timestamp,
    String? status,
    bool? isIncoming,
    String? createdAt,
    String? readAt,
    String? quotedMessageId,
    List<MediaAttachment>? media,
  }) {
    return ConversationMessage(
      id: id ?? this.id,
      contactPeerId: contactPeerId ?? this.contactPeerId,
      senderPeerId: senderPeerId ?? this.senderPeerId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      isIncoming: isIncoming ?? this.isIncoming,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
      quotedMessageId: quotedMessageId ?? this.quotedMessageId,
      media: media ?? this.media,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConversationMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ConversationMessage(id: $id, contactPeerId: ${contactPeerId.length > 10 ? contactPeerId.substring(0, 10) : contactPeerId}..., isIncoming: $isIncoming)';
  }
}
