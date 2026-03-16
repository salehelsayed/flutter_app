class PostFollowOnOutboxEvent {
  final String eventId;
  final String eventType;
  final String postId;
  final String? commentId;
  final String senderPeerId;
  final String rawEnvelope;
  final String createdAt;

  const PostFollowOnOutboxEvent({
    required this.eventId,
    required this.eventType,
    required this.postId,
    this.commentId,
    required this.senderPeerId,
    required this.rawEnvelope,
    required this.createdAt,
  });

  factory PostFollowOnOutboxEvent.fromMap(Map<String, Object?> map) {
    return PostFollowOnOutboxEvent(
      eventId: map['event_id'] as String,
      eventType: map['event_type'] as String,
      postId: map['post_id'] as String,
      commentId: map['comment_id'] as String?,
      senderPeerId: map['sender_peer_id'] as String,
      rawEnvelope: map['raw_envelope'] as String,
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'event_id': eventId,
      'event_type': eventType,
      'post_id': postId,
      'comment_id': commentId,
      'sender_peer_id': senderPeerId,
      'raw_envelope': rawEnvelope,
      'created_at': createdAt,
    };
  }
}
