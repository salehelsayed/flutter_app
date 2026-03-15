class PostCommentReactionModel {
  final String reactionId;
  final String eventId;
  final String postId;
  final String commentId;
  final String senderPeerId;
  final bool isActive;
  final String reactedAt;

  const PostCommentReactionModel({
    required this.reactionId,
    required this.eventId,
    required this.postId,
    required this.commentId,
    required this.senderPeerId,
    required this.isActive,
    required this.reactedAt,
  });

  factory PostCommentReactionModel.fromMap(Map<String, Object?> map) {
    return PostCommentReactionModel(
      reactionId: map['reaction_id'] as String,
      eventId: map['event_id'] as String,
      postId: map['post_id'] as String,
      commentId: map['comment_id'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      isActive: (map['is_active'] as int? ?? 0) == 1,
      reactedAt: map['reacted_at'] as String,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'reaction_id': reactionId,
      'event_id': eventId,
      'post_id': postId,
      'comment_id': commentId,
      'sender_peer_id': senderPeerId,
      'kind': 'heart',
      'is_active': isActive ? 1 : 0,
      'reacted_at': reactedAt,
      'created_at': reactedAt,
    };
  }
}
