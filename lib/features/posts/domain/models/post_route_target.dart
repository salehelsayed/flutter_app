class PostRouteTarget {
  final String postId;
  final String? commentId;

  const PostRouteTarget({required this.postId, this.commentId});

  bool get opensComments => commentId != null;
}
