class PostPassModel {
  final String passId;
  final String eventId;
  final String postId;
  final String senderPeerId;
  final String passerPeerId;
  final String passerUsername;
  final String passedAt;
  final String createdAt;
  final bool isIncoming;
  final String deliveryStatus;

  const PostPassModel({
    required this.passId,
    required this.eventId,
    required this.postId,
    required this.senderPeerId,
    required this.passerPeerId,
    required this.passerUsername,
    required this.passedAt,
    required this.createdAt,
    this.isIncoming = true,
    String? deliveryStatus,
  }) : deliveryStatus =
           deliveryStatus ?? (isIncoming ? 'available' : 'sending');

  factory PostPassModel.fromMap(Map<String, Object?> map) {
    final isIncoming = (map['is_incoming'] as int? ?? 1) == 1;
    return PostPassModel(
      passId: map['pass_id'] as String,
      eventId: map['event_id'] as String,
      postId: map['post_id'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      passerPeerId: map['passer_peer_id'] as String,
      passerUsername: map['passer_username'] as String,
      passedAt: map['passed_at'] as String,
      createdAt: map['created_at'] as String,
      isIncoming: isIncoming,
      deliveryStatus:
          map['delivery_status'] as String? ??
          (isIncoming ? 'available' : 'sending'),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'pass_id': passId,
      'event_id': eventId,
      'post_id': postId,
      'sender_peer_id': senderPeerId,
      'passer_peer_id': passerPeerId,
      'passer_username': passerUsername,
      'passed_at': passedAt,
      'created_at': createdAt,
      'is_incoming': isIncoming ? 1 : 0,
      'delivery_status': deliveryStatus,
    };
  }

  PostPassModel copyWith({
    String? senderPeerId,
    String? passerPeerId,
    String? passerUsername,
    String? passedAt,
    String? createdAt,
    bool? isIncoming,
    String? deliveryStatus,
  }) {
    final resolvedIncoming = isIncoming ?? this.isIncoming;
    return PostPassModel(
      passId: passId,
      eventId: eventId,
      postId: postId,
      senderPeerId: senderPeerId ?? this.senderPeerId,
      passerPeerId: passerPeerId ?? this.passerPeerId,
      passerUsername: passerUsername ?? this.passerUsername,
      passedAt: passedAt ?? this.passedAt,
      createdAt: createdAt ?? this.createdAt,
      isIncoming: resolvedIncoming,
      deliveryStatus:
          deliveryStatus ??
          (resolvedIncoming ? 'available' : this.deliveryStatus),
    );
  }
}
