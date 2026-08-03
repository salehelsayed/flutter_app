/// Model representing an emoji reaction on a message.
///
/// Maps to the `message_reactions` database table. Each reaction links a
/// single emoji to a message, keyed by sender — one reaction per user per
/// message (UNIQUE on message_id + sender_peer_id).
class MessageReaction {
  /// Unique reaction ID (UUID v4).
  final String id;

  /// The message this reaction is on (FK to messages.id).
  final String messageId;

  /// The emoji codepoint(s), e.g. "👍" or "👨‍👩‍👧‍👦".
  final String emoji;

  /// Peer ID of the user who reacted.
  final String senderPeerId;

  /// ISO-8601 timestamp when the reaction was created by the sender.
  final String timestamp;

  /// ISO-8601 timestamp when the row was created locally.
  final String createdAt;

  /// ISO-8601 sender-authored timestamp of the remove that tombstoned this
  /// reaction, or null when the reaction is active. A tombstoned reaction is
  /// hidden from all UI loaders but retained as a last-writer-wins comparand so
  /// an older (stale) re-add can be recognised and dropped (INV-T1/INV-T2).
  final String? removedAt;

  /// Local-only conversation-read boundary for notification projection.
  /// Never serialized onto the wire or written by ordinary reaction payloads.
  final String? notificationAcknowledgedAt;

  const MessageReaction({
    required this.id,
    required this.messageId,
    required this.emoji,
    required this.senderPeerId,
    required this.timestamp,
    required this.createdAt,
    this.removedAt,
    this.notificationAcknowledgedAt,
  });

  /// Whether this reaction has been tombstoned by a remove.
  bool get isRemoved => removedAt != null;

  /// Creates a MessageReaction from a database row map (snake_case keys).
  factory MessageReaction.fromMap(Map<String, dynamic> map) {
    return MessageReaction(
      id: map['id'] as String,
      messageId: map['message_id'] as String,
      emoji: map['emoji'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      timestamp: map['timestamp'] as String,
      createdAt: map['created_at'] as String,
      removedAt: map['removed_at'] as String?,
      notificationAcknowledgedAt:
          map['notification_acknowledged_at'] as String?,
    );
  }

  /// Converts the model to a database row map (snake_case keys). Always writes
  /// `removed_at` (null for an active reaction) so a `ConflictAlgorithm.replace`
  /// insert overwrites — and thereby clears — any prior tombstone (INV-T3).
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'message_id': messageId,
      'emoji': emoji,
      'sender_peer_id': senderPeerId,
      'timestamp': timestamp,
      'created_at': createdAt,
      'removed_at': removedAt,
    };
  }

  /// Creates a MessageReaction from a wire-format JSON map (camelCase keys).
  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      id: json['id'] as String,
      messageId: json['messageId'] as String,
      emoji: json['emoji'] as String,
      senderPeerId: json['senderPeerId'] as String,
      timestamp: json['timestamp'] as String,
      createdAt: json['createdAt'] as String,
    );
  }

  /// Converts the model to a wire-format JSON map (camelCase keys).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'messageId': messageId,
      'emoji': emoji,
      'senderPeerId': senderPeerId,
      'timestamp': timestamp,
      'createdAt': createdAt,
    };
  }

  /// Creates a copy with updated fields. Pass `clearRemovedAt: true` to
  /// resurrect a tombstoned reaction (the `removedAt`/`clearRemovedAt` combo
  /// distinguishes "leave unchanged" from "set to null").
  MessageReaction copyWith({
    String? id,
    String? messageId,
    String? emoji,
    String? senderPeerId,
    String? timestamp,
    String? createdAt,
    String? removedAt,
    bool clearRemovedAt = false,
    String? notificationAcknowledgedAt,
    bool clearNotificationAcknowledgedAt = false,
  }) {
    return MessageReaction(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      emoji: emoji ?? this.emoji,
      senderPeerId: senderPeerId ?? this.senderPeerId,
      timestamp: timestamp ?? this.timestamp,
      createdAt: createdAt ?? this.createdAt,
      removedAt: clearRemovedAt ? null : (removedAt ?? this.removedAt),
      notificationAcknowledgedAt: clearNotificationAcknowledgedAt
          ? null
          : (notificationAcknowledgedAt ?? this.notificationAcknowledgedAt),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MessageReaction && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'MessageReaction(id: $id, messageId: ${messageId.length > 10 ? messageId.substring(0, 10) : messageId}..., emoji: $emoji)';
  }
}
