import 'dart:convert';

class PostReactionEnvelope {
  static const Duration _maxFutureClockSkew = Duration(minutes: 5);

  final String type;
  final String eventId;
  final String createdAt;
  final String senderPeerId;
  final String reactionId;
  final String postId;
  final String? commentId;
  final bool isActive;
  final String reactedAt;

  const PostReactionEnvelope({
    required this.type,
    required this.eventId,
    required this.createdAt,
    required this.senderPeerId,
    required this.reactionId,
    required this.postId,
    this.commentId,
    required this.isActive,
    required this.reactedAt,
  });

  bool get isCommentReaction => type == 'post_comment_reaction';

  static PostReactionEnvelope? fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type != 'post_reaction' && type != 'post_comment_reaction') {
        return null;
      }
      if (json['version'] == '2') {
        return null;
      }
      final eventId = json['event_id'] as String?;
      final createdAt = json['created_at'] as String?;
      final senderPeerId = json['sender_peer_id'] as String?;
      final payload = json['payload'] as Map<String, dynamic>?;
      final reactionId = payload?['reaction_id'] as String?;
      final postId = payload?['post_id'] as String?;
      final kind = payload?['kind'] as String?;
      final isActive = payload?['is_active'] as bool?;
      final reactedAt = payload?['reacted_at'] as String?;
      final commentId = payload?['comment_id'] as String?;
      if (eventId == null ||
          createdAt == null ||
          senderPeerId == null ||
          reactionId == null ||
          postId == null ||
          kind != 'heart' ||
          isActive == null ||
          reactedAt == null) {
        return null;
      }
      if (type == 'post_comment_reaction' && commentId == null) {
        return null;
      }
      if (!_isValidCreatedAt(createdAt)) {
        return null;
      }
      final expectedReactionId = type == 'post_reaction'
          ? 'post_heart:$postId:$senderPeerId'
          : 'comment_heart:$commentId:$senderPeerId';
      if (reactionId != expectedReactionId) {
        return null;
      }
      return PostReactionEnvelope(
        type: type!,
        eventId: eventId,
        createdAt: createdAt,
        senderPeerId: senderPeerId,
        reactionId: reactionId,
        postId: postId,
        commentId: commentId,
        isActive: isActive,
        reactedAt: reactedAt,
      );
    } catch (_) {
      return null;
    }
  }

  static String buildPostReactionJson({
    required String eventId,
    required String createdAt,
    required String senderPeerId,
    required String postId,
    required bool isActive,
  }) {
    return jsonEncode({
      'type': 'post_reaction',
      'version': '1',
      'event_id': eventId,
      'created_at': createdAt,
      'sender_peer_id': senderPeerId,
      'payload': <String, Object?>{
        'reaction_id': 'post_heart:$postId:$senderPeerId',
        'post_id': postId,
        'kind': 'heart',
        'is_active': isActive,
        'reacted_at': createdAt,
      },
    });
  }

  static String buildCommentReactionJson({
    required String eventId,
    required String createdAt,
    required String senderPeerId,
    required String postId,
    required String commentId,
    required bool isActive,
  }) {
    return jsonEncode({
      'type': 'post_comment_reaction',
      'version': '1',
      'event_id': eventId,
      'created_at': createdAt,
      'sender_peer_id': senderPeerId,
      'payload': <String, Object?>{
        'reaction_id': 'comment_heart:$commentId:$senderPeerId',
        'post_id': postId,
        'comment_id': commentId,
        'kind': 'heart',
        'is_active': isActive,
        'reacted_at': createdAt,
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
