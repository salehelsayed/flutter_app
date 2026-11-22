import 'package:flutter_app/features/posts/domain/models/post_model.dart';

/// One text composition that began while its incoming Thought was live.
/// This proof stays with the open composer and is never persisted.
class ThoughtReplyDraft {
  ThoughtReplyDraft._(this._post, this.expiresAt);

  static const grace = Duration(seconds: 60);

  static ThoughtReplyDraft? start(PostModel post, DateTime now) {
    final expiry = DateTime.tryParse(post.expiresAt);
    if (!post.isIncoming || expiry == null || !expiry.isAfter(now)) {
      return null;
    }
    return ThoughtReplyDraft._(post, expiry);
  }

  final PostModel _post;
  final DateTime expiresAt;

  String get postId => _post.id;
  String get authorPeerId => _post.authorPeerId;
  DateTime get deadline => expiresAt.add(grace);

  bool isInGraceAt(DateTime now) =>
      !now.isBefore(expiresAt) && now.isBefore(deadline);

  bool matches(PostModel post) =>
      post.isIncoming &&
      post.id == postId &&
      post.authorPeerId == authorPeerId &&
      post.eventId == _post.eventId &&
      post.createdAt == _post.createdAt &&
      DateTime.tryParse(post.expiresAt)?.isAtSameMomentAs(expiresAt) == true;

  bool isSupersededBy(PostModel post) {
    if (!post.isIncoming || post.authorPeerId != authorPeerId) return false;
    final original = DateTime.tryParse(_post.createdAt);
    final candidate = DateTime.tryParse(post.createdAt);
    if (original == null || candidate == null) return false;
    return candidate.isAfter(original) ||
        (candidate.isAtSameMomentAs(original) && post.id.compareTo(postId) < 0);
  }

  int secondsRemaining(DateTime now) =>
      (deadline.difference(now).inMilliseconds / 1000)
          .ceil()
          .clamp(0, 60)
          .toInt();
}
