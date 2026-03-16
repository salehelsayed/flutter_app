class PostFollowOnOutboxRecipientDelivery {
  final String eventId;
  final String recipientPeerId;
  final String deliveryStatus;
  final String deliveryPath;
  final String? lastError;
  final String? lastAttemptAt;
  final String createdAt;
  final String updatedAt;

  const PostFollowOnOutboxRecipientDelivery({
    required this.eventId,
    required this.recipientPeerId,
    required this.deliveryStatus,
    required this.deliveryPath,
    this.lastError,
    this.lastAttemptAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isSettled =>
      deliveryStatus == 'delivered' || deliveryStatus == 'inbox';

  factory PostFollowOnOutboxRecipientDelivery.fromMap(
    Map<String, Object?> map,
  ) {
    return PostFollowOnOutboxRecipientDelivery(
      eventId: map['event_id'] as String,
      recipientPeerId: map['recipient_peer_id'] as String,
      deliveryStatus: map['delivery_status'] as String? ?? 'pending',
      deliveryPath: map['delivery_path'] as String? ?? 'unknown',
      lastError: map['last_error'] as String?,
      lastAttemptAt: map['last_attempt_at'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'event_id': eventId,
      'recipient_peer_id': recipientPeerId,
      'delivery_status': deliveryStatus,
      'delivery_path': deliveryPath,
      'last_error': lastError,
      'last_attempt_at': lastAttemptAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  PostFollowOnOutboxRecipientDelivery copyWith({
    String? deliveryStatus,
    String? deliveryPath,
    String? lastError,
    String? lastAttemptAt,
    String? updatedAt,
  }) {
    return PostFollowOnOutboxRecipientDelivery(
      eventId: eventId,
      recipientPeerId: recipientPeerId,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      deliveryPath: deliveryPath ?? this.deliveryPath,
      lastError: lastError ?? this.lastError,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
