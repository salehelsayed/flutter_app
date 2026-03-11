import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

/// Model representing a single message in a group conversation.
///
/// Maps to the `group_messages` database table.
class GroupMessage {
  /// Unique message ID (UUID v4).
  final String id;

  /// The group this message belongs to.
  final String groupId;

  /// The peer ID of the message sender.
  final String senderPeerId;

  /// The display name of the sender at the time of sending.
  final String? senderUsername;

  /// The message text content.
  final String text;

  /// When the message was sent/received.
  final DateTime timestamp;

  /// The message ID this message is quoting, if any.
  final String? quotedMessageId;

  /// The key generation used to encrypt this message.
  final int keyGeneration;

  /// Delivery status: 'sending', 'sent', 'delivered', 'failed'.
  final String status;

  /// Whether this message was received from another group member.
  final bool isIncoming;

  /// When the message was read. NULL means unread.
  final DateTime? readAt;

  /// When the row was created locally.
  final DateTime createdAt;

  /// Media attachments (loaded from media_attachments table, not from this row).
  final List<MediaAttachment> media;

  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderPeerId,
    this.senderUsername,
    required this.text,
    required this.timestamp,
    this.quotedMessageId,
    this.keyGeneration = 0,
    this.status = 'sent',
    this.isIncoming = true,
    this.readAt,
    required this.createdAt,
    this.media = const [],
  });

  /// Creates a GroupMessage from a database row map.
  factory GroupMessage.fromMap(Map<String, dynamic> map) {
    return GroupMessage(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      senderUsername: map['sender_username'] as String?,
      text: map['text'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      quotedMessageId: map['quoted_message_id'] as String?,
      keyGeneration: map['key_generation'] as int? ?? 0,
      status: map['status'] as String? ?? 'sent',
      isIncoming: (map['is_incoming'] as int? ?? 1) == 1,
      readAt: map['read_at'] != null
          ? DateTime.parse(map['read_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Converts the model to a database row map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'group_id': groupId,
      'sender_peer_id': senderPeerId,
      'sender_username': senderUsername,
      'text': text,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'quoted_message_id': quotedMessageId,
      'key_generation': keyGeneration,
      'status': status,
      'is_incoming': isIncoming ? 1 : 0,
      'read_at': readAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  /// Creates a copy with updated fields.
  GroupMessage copyWith({
    String? id,
    String? groupId,
    String? senderPeerId,
    String? senderUsername,
    String? text,
    DateTime? timestamp,
    Object? quotedMessageId = _sentinel,
    int? keyGeneration,
    String? status,
    bool? isIncoming,
    Object? readAt = _sentinel,
    DateTime? createdAt,
    List<MediaAttachment>? media,
  }) {
    return GroupMessage(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      senderPeerId: senderPeerId ?? this.senderPeerId,
      senderUsername: senderUsername ?? this.senderUsername,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      quotedMessageId: quotedMessageId == _sentinel
          ? this.quotedMessageId
          : quotedMessageId as String?,
      keyGeneration: keyGeneration ?? this.keyGeneration,
      status: status ?? this.status,
      isIncoming: isIncoming ?? this.isIncoming,
      readAt: readAt == _sentinel ? this.readAt : readAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      media: media ?? this.media,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroupMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'GroupMessage(id: $id, groupId: $groupId, isIncoming: $isIncoming)';
  }
}

const _sentinel = Object();
