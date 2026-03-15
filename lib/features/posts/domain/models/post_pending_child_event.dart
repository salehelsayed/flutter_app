class PostPendingChildEvent {
  final String postId;
  final String eventId;
  final String eventType;
  final String senderPeerId;
  final String createdAt;
  final String rawEnvelope;

  const PostPendingChildEvent({
    required this.postId,
    required this.eventId,
    required this.eventType,
    required this.senderPeerId,
    required this.createdAt,
    required this.rawEnvelope,
  });

  factory PostPendingChildEvent.fromMap(Map<String, Object?> map) {
    return PostPendingChildEvent(
      postId: map['post_id'] as String,
      eventId: map['event_id'] as String,
      eventType: map['event_type'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      createdAt: map['created_at'] as String,
      rawEnvelope: map['raw_envelope'] as String,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'post_id': postId,
      'event_id': eventId,
      'event_type': eventType,
      'sender_peer_id': senderPeerId,
      'created_at': createdAt,
      'raw_envelope': rawEnvelope,
    };
  }
}
