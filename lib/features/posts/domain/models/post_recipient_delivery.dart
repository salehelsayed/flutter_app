const String postRecipientDeliveryOwnerKindPost = 'post';
const String postRecipientDeliveryOwnerKindPass = 'post_pass';

class PostRecipientDelivery {
  final String postId;
  final String recipientPeerId;
  final String deliveryStatus;
  final String lastAttemptAt;
  final String deliveryPath;
  final String? lastError;
  final int? nearbyDistanceM;
  final String createdAt;
  final String updatedAt;
  final String deliveryOwnerKind;
  final String deliveryOwnerId;

  const PostRecipientDelivery({
    required this.postId,
    required this.recipientPeerId,
    required this.deliveryStatus,
    required this.lastAttemptAt,
    required this.deliveryPath,
    this.lastError,
    this.nearbyDistanceM,
    required this.createdAt,
    required this.updatedAt,
    this.deliveryOwnerKind = postRecipientDeliveryOwnerKindPost,
    String? deliveryOwnerId,
  }) : deliveryOwnerId = deliveryOwnerId ?? postId;

  factory PostRecipientDelivery.fromMap(Map<String, Object?> map) {
    final postId = map['post_id'] as String;
    return PostRecipientDelivery(
      postId: postId,
      recipientPeerId: map['recipient_peer_id'] as String,
      deliveryStatus: map['delivery_status'] as String? ?? 'pending',
      lastAttemptAt: map['last_attempt_at'] as String,
      deliveryPath: map['delivery_path'] as String? ?? 'unknown',
      lastError: map['last_error'] as String?,
      nearbyDistanceM: (map['nearby_distance_m'] as num?)?.toInt(),
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
      deliveryOwnerKind:
          map['delivery_owner_kind'] as String? ??
          postRecipientDeliveryOwnerKindPost,
      deliveryOwnerId: map['delivery_owner_id'] as String? ?? postId,
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
      'nearby_distance_m': nearbyDistanceM,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'delivery_owner_kind': deliveryOwnerKind,
      'delivery_owner_id': deliveryOwnerId,
    };
  }

  PostRecipientDelivery copyWith({
    String? deliveryStatus,
    String? lastAttemptAt,
    String? deliveryPath,
    String? lastError,
    int? nearbyDistanceM,
    String? updatedAt,
    String? deliveryOwnerKind,
    String? deliveryOwnerId,
  }) {
    return PostRecipientDelivery(
      postId: postId,
      recipientPeerId: recipientPeerId,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      deliveryPath: deliveryPath ?? this.deliveryPath,
      lastError: lastError ?? this.lastError,
      nearbyDistanceM: nearbyDistanceM ?? this.nearbyDistanceM,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deliveryOwnerKind: deliveryOwnerKind ?? this.deliveryOwnerKind,
      deliveryOwnerId: deliveryOwnerId ?? this.deliveryOwnerId,
    );
  }
}
