class PostRecipientDelivery {
  final String postId;
  final String recipientPeerId;
  final String deliveryStatus;
  final String lastAttemptAt;
  final String deliveryPath;
  final String? lastError;
  final String createdAt;
  final String updatedAt;

  const PostRecipientDelivery({
    required this.postId,
    required this.recipientPeerId,
    required this.deliveryStatus,
    required this.lastAttemptAt,
    required this.deliveryPath,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PostRecipientDelivery.fromMap(Map<String, Object?> map) {
    return PostRecipientDelivery(
      postId: map['post_id'] as String,
      recipientPeerId: map['recipient_peer_id'] as String,
      deliveryStatus: map['delivery_status'] as String? ?? 'pending',
      lastAttemptAt: map['last_attempt_at'] as String,
      deliveryPath: map['delivery_path'] as String? ?? 'unknown',
      lastError: map['last_error'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'post_id': postId,
      'recipient_peer_id': recipientPeerId,
      'delivery_status': deliveryStatus,
      'last_attempt_at': lastAttemptAt,
      'delivery_path': deliveryPath,
      'last_error': lastError,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  PostRecipientDelivery copyWith({
    String? deliveryStatus,
    String? lastAttemptAt,
    String? deliveryPath,
    String? lastError,
    String? updatedAt,
  }) {
    return PostRecipientDelivery(
      postId: postId,
      recipientPeerId: recipientPeerId,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      deliveryPath: deliveryPath ?? this.deliveryPath,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
