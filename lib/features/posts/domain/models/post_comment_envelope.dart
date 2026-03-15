import 'dart:convert';

class PostCommentEnvelope {
  static const Duration _maxFutureClockSkew = Duration(minutes: 5);

  final String eventId;
  final String createdAt;
  final String senderPeerId;
  final String commentId;
  final String postId;
  final String body;
  final String commentedAt;

  const PostCommentEnvelope({
    required this.eventId,
    required this.createdAt,
    required this.senderPeerId,
    required this.commentId,
    required this.postId,
    required this.body,
    required this.commentedAt,
  });

  static PostCommentEnvelope? fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'post_comment' || json['version'] == '2') {
        return null;
      }
      final eventId = json['event_id'] as String?;
      final createdAt = json['created_at'] as String?;
      final senderPeerId = json['sender_peer_id'] as String?;
      final payload = json['payload'] as Map<String, dynamic>?;
      final commentId = payload?['comment_id'] as String?;
      final postId = payload?['post_id'] as String?;
      final body = payload?['body'] as String?;
      final commentedAt = payload?['commented_at'] as String?;
      if (eventId == null ||
          createdAt == null ||
          senderPeerId == null ||
          commentId == null ||
          postId == null ||
          body == null ||
          commentedAt == null) {
        return null;
      }
      final trimmedBody = body.trim();
      if (trimmedBody.isEmpty || !_isValidCreatedAt(createdAt)) {
        return null;
      }
      return PostCommentEnvelope(
        eventId: eventId,
        createdAt: createdAt,
        senderPeerId: senderPeerId,
        commentId: commentId,
        postId: postId,
        body: trimmedBody,
        commentedAt: commentedAt,
      );
    } catch (_) {
      return null;
    }
  }

  String toJson() {
    return jsonEncode({
      'type': 'post_comment',
      'version': '1',
      'event_id': eventId,
      'created_at': createdAt,
      'sender_peer_id': senderPeerId,
      'payload': <String, Object?>{
        'comment_id': commentId,
        'post_id': postId,
        'body': body,
        'commented_at': commentedAt,
      },
    });
  }

  static bool _isValidCreatedAt(String createdAt) {
    final timestamp = DateTime.tryParse(createdAt)?.toUtc();
    if (timestamp == null) {
      return false;
    }
    final latestAllowed = DateTime.now().toUtc().add(_maxFutureClockSkew);
    return !timestamp.isAfter(latestAllowed);
  }
}
