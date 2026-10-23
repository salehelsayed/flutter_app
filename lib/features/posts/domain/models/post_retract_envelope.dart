import 'dart:convert';

/// Tells a friend to delete their copy of a thought.
///
/// The envelope names no sender: receivers trust only the transport's
/// authenticated sender, which must be the stored thought's author.
class PostRetractEnvelope {
  static const type = 'post_retract';

  const PostRetractEnvelope({
    required this.eventId,
    required this.createdAt,
    required this.postId,
    required this.postCreatedAt,
  });

  final String eventId;
  final DateTime createdAt;
  final String postId;

  /// When the thought was written. Retries stop once it would have expired.
  final DateTime postCreatedAt;

  static PostRetractEnvelope? fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != type) return null;
      final eventId = json['event_id'] as String?;
      final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
      final payload = json['payload'] as Map<String, dynamic>?;
      final postId = payload?['post_id'] as String?;
      final postCreatedAt = DateTime.tryParse(
        payload?['post_created_at'] as String? ?? '',
      );
      if (eventId == null ||
          createdAt == null ||
          postId == null ||
          postId.isEmpty ||
          postCreatedAt == null) {
        return null;
      }
      return PostRetractEnvelope(
        eventId: eventId,
        createdAt: createdAt,
        postId: postId,
        postCreatedAt: postCreatedAt,
      );
    } catch (_) {
      return null;
    }
  }

  String toJson() {
    return jsonEncode(<String, Object?>{
      'type': type,
      'version': '1',
      'event_id': eventId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'payload': <String, Object?>{
        'post_id': postId,
        'post_created_at': postCreatedAt.toUtc().toIso8601String(),
      },
    });
  }
}
