/// Wire format model for group messages (v3 envelope).
///
/// Used for serializing/deserializing group messages to/from JSON
/// for transport over the network.
class GroupMessagePayload {
  /// The message text content.
  final String text;

  /// ISO-8601 timestamp when the message was sent.
  final String timestamp;

  /// The sender's display name at the time of sending.
  final String? username;

  /// The message ID being quoted, if any.
  final String? quotedMessageId;

  /// Optional extra metadata.
  final Map<String, dynamic>? extra;

  const GroupMessagePayload({
    required this.text,
    required this.timestamp,
    this.username,
    this.quotedMessageId,
    this.extra,
  });

  /// Creates a GroupMessagePayload from a JSON map (wire format).
  factory GroupMessagePayload.fromJson(Map<String, dynamic> json) {
    return GroupMessagePayload(
      text: json['text'] as String,
      timestamp: json['timestamp'] as String,
      username: json['username'] as String?,
      quotedMessageId: json['quotedMessageId'] as String?,
      extra: json['extra'] != null
          ? Map<String, dynamic>.from(json['extra'] as Map)
          : null,
    );
  }

  /// Converts the payload to a JSON map (wire format).
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'timestamp': timestamp,
      if (username != null) 'username': username,
      if (quotedMessageId != null) 'quotedMessageId': quotedMessageId,
      if (extra != null) 'extra': extra,
    };
  }

  @override
  String toString() {
    return 'GroupMessagePayload(text: ${text.length > 20 ? '${text.substring(0, 20)}...' : text}, timestamp: $timestamp)';
  }
}
