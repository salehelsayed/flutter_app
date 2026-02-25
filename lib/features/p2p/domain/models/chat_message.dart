/// Chat message model for P2P messaging.
class ChatMessage {
  final String from;
  final String to;
  final String content;
  final String timestamp;
  final bool isIncoming;
  final String? transport;

  const ChatMessage({
    required this.from,
    required this.to,
    required this.content,
    required this.timestamp,
    required this.isIncoming,
    this.transport,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // Handle timestamp that may come as int (Unix ms) or String (ISO8601)
    String timestamp;
    final ts = json['timestamp'];
    if (ts is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(ts).toUtc().toIso8601String();
    } else if (ts is String) {
      timestamp = ts;
    } else {
      timestamp = DateTime.now().toUtc().toIso8601String();
    }

    return ChatMessage(
      from: json['from'] as String,
      to: json['to']?.toString() ?? '',
      content: json['content'] as String,
      timestamp: timestamp,
      isIncoming: json['isIncoming'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'to': to,
      'content': content,
      'timestamp': timestamp,
      'isIncoming': isIncoming,
    };
  }

  ChatMessage copyWith({
    String? from,
    String? to,
    String? content,
    String? timestamp,
    bool? isIncoming,
    String? transport,
  }) {
    return ChatMessage(
      from: from ?? this.from,
      to: to ?? this.to,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isIncoming: isIncoming ?? this.isIncoming,
      transport: transport ?? this.transport,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatMessage &&
        other.from == from &&
        other.to == to &&
        other.content == content &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(from, to, content, timestamp);

  @override
  String toString() {
    return 'ChatMessage(from: $from, to: $to, isIncoming: $isIncoming)';
  }
}
