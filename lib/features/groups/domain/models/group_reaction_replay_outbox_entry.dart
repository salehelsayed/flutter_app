class GroupReactionReplayOutboxStatus {
  static const String pending = 'pending';
  static const String failed = 'failed';
  static const String stored = 'stored';
}

class GroupReactionReplayOutboxEntry {
  final String reactionId;
  final String groupId;
  final String messageId;
  final String senderPeerId;
  final String emoji;
  final String action;
  final String inboxRetryPayload;
  final String deliveryStatus;
  final String? lastError;
  final String createdAt;
  final String updatedAt;

  const GroupReactionReplayOutboxEntry({
    required this.reactionId,
    required this.groupId,
    required this.messageId,
    required this.senderPeerId,
    required this.emoji,
    required this.action,
    required this.inboxRetryPayload,
    required this.deliveryStatus,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GroupReactionReplayOutboxEntry.fromMap(Map<String, Object?> map) {
    return GroupReactionReplayOutboxEntry(
      reactionId: map['reaction_id'] as String,
      groupId: map['group_id'] as String,
      messageId: map['message_id'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      emoji: map['emoji'] as String,
      action: map['action'] as String,
      inboxRetryPayload: map['inbox_retry_payload'] as String,
      deliveryStatus: map['delivery_status'] as String,
      lastError: map['last_error'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'reaction_id': reactionId,
      'group_id': groupId,
      'message_id': messageId,
      'sender_peer_id': senderPeerId,
      'emoji': emoji,
      'action': action,
      'inbox_retry_payload': inboxRetryPayload,
      'delivery_status': deliveryStatus,
      'last_error': lastError,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  GroupReactionReplayOutboxEntry copyWith({
    String? reactionId,
    String? groupId,
    String? messageId,
    String? senderPeerId,
    String? emoji,
    String? action,
    String? inboxRetryPayload,
    String? deliveryStatus,
    Object? lastError = _sentinel,
    String? createdAt,
    String? updatedAt,
  }) {
    return GroupReactionReplayOutboxEntry(
      reactionId: reactionId ?? this.reactionId,
      groupId: groupId ?? this.groupId,
      messageId: messageId ?? this.messageId,
      senderPeerId: senderPeerId ?? this.senderPeerId,
      emoji: emoji ?? this.emoji,
      action: action ?? this.action,
      inboxRetryPayload: inboxRetryPayload ?? this.inboxRetryPayload,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const Object _sentinel = Object();
