class PostPinStateModel {
  final String postId;
  final String eventId;
  final String pinEventId;
  final String senderPeerId;
  final String state;
  final String effectiveAt;
  final String? pinnedAt;
  final String? removedAt;
  final String? reason;
  final String createdAt;

  const PostPinStateModel({
    required this.postId,
    required this.eventId,
    required this.pinEventId,
    required this.senderPeerId,
    required this.state,
    required this.effectiveAt,
    this.pinnedAt,
    this.removedAt,
    this.reason,
    required this.createdAt,
  });

  bool get isActive => state == 'active';

  factory PostPinStateModel.fromMap(Map<String, Object?> map) {
    return PostPinStateModel(
      postId: map['post_id'] as String,
      eventId: map['event_id'] as String,
      pinEventId: map['pin_event_id'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      state: map['state'] as String,
      effectiveAt: map['effective_at'] as String,
      pinnedAt: map['pinned_at'] as String?,
      removedAt: map['removed_at'] as String?,
      reason: map['reason'] as String?,
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'post_id': postId,
      'event_id': eventId,
      'pin_event_id': pinEventId,
      'sender_peer_id': senderPeerId,
      'state': state,
      'effective_at': effectiveAt,
      'pinned_at': pinnedAt,
      'removed_at': removedAt,
      'reason': reason,
      'created_at': createdAt,
    };
  }
}
