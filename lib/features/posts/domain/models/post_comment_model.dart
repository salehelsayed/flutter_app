class PostCommentModel {
  final String id;
  final String eventId;
  final String postId;
  final String senderPeerId;
  final String authorUsername;
  final String body;
  final String commentedAt;
  final int heartCount;
  final bool viewerHasHearted;
  final bool isIncoming;

  const PostCommentModel({
    required this.id,
    required this.eventId,
    required this.postId,
    required this.senderPeerId,
    this.authorUsername = '',
    required this.body,
    required this.commentedAt,
    this.heartCount = 0,
    this.viewerHasHearted = false,
    this.isIncoming = true,
  });

  factory PostCommentModel.fromMap(Map<String, Object?> map) {
    return PostCommentModel(
      id: map['comment_id'] as String,
      eventId: map['event_id'] as String,
      postId: map['post_id'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      authorUsername: map['author_username'] as String? ?? '',
      body: map['body'] as String? ?? '',
      commentedAt:
          map['commented_at'] as String? ?? map['created_at'] as String? ?? '',
      heartCount: map['heart_count'] as int? ?? 0,
      viewerHasHearted: (map['viewer_has_hearted'] as int? ?? 0) == 1,
      isIncoming: (map['is_incoming'] as int? ?? 1) == 1,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'comment_id': id,
      'event_id': eventId,
      'post_id': postId,
      'sender_peer_id': senderPeerId,
      'author_username': authorUsername,
      'body': body,
      'commented_at': commentedAt,
      'created_at': commentedAt,
      'is_incoming': isIncoming ? 1 : 0,
    };
  }

  PostCommentModel copyWith({
    String? authorUsername,
    String? body,
    int? heartCount,
    bool? viewerHasHearted,
    bool? isIncoming,
  }) {
    return PostCommentModel(
      id: id,
      eventId: eventId,
      postId: postId,
      senderPeerId: senderPeerId,
      authorUsername: authorUsername ?? this.authorUsername,
      body: body ?? this.body,
      commentedAt: commentedAt,
      heartCount: heartCount ?? this.heartCount,
      viewerHasHearted: viewerHasHearted ?? this.viewerHasHearted,
      isIncoming: isIncoming ?? this.isIncoming,
    );
  }
}
