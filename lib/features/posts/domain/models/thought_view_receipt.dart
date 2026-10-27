class ThoughtViewReceipt {
  const ThoughtViewReceipt({
    required this.postId,
    required this.viewerPeerId,
    required this.viewedAt,
  });

  final String postId;
  final String viewerPeerId;
  final String viewedAt;

  factory ThoughtViewReceipt.fromMap(Map<String, Object?> row) =>
      ThoughtViewReceipt(
        postId: row['post_id'] as String,
        viewerPeerId: row['viewer_peer_id'] as String,
        viewedAt: row['viewed_at'] as String,
      );

  Map<String, Object?> toMap() => {
    'post_id': postId,
    'viewer_peer_id': viewerPeerId,
    'viewed_at': viewedAt,
  };
}
