/// Chat message model for P2P messaging.
class ChatMessage {
  final String from;
  final String to;
  final String content;
  final String timestamp;
  final bool isIncoming;
  final String? transport;

  /// WIRE CONTRACT (Go->Dart, doc 118 / plan 120 G5): set by Go on an incoming
  /// direct `message:received` event (go-mknoon/node/node.go, attach site) when
  /// `EnableDeferredDirectAck` is true (default). Drives the deferred-ack->notify
  /// path; if Go renames/drops the key or flips the default this goes null and
  /// live-direct notifications silently break. Go producer side is guarded by
  /// transport_label_test.go TestHandleIncomingMessage_DirectAckContract_AttachesConfirmNonce.
  final String? confirmNonce;

  const ChatMessage({
    required this.from,
    required this.to,
    required this.content,
    required this.timestamp,
    required this.isIncoming,
    this.transport,
    this.confirmNonce,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // Handle timestamp that may come as int (Unix ms) or String (ISO8601)
    String timestamp;
    final ts = json['timestamp'];
    if (ts is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(
        ts,
      ).toUtc().toIso8601String();
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
      transport: json['transport']?.toString(),
      // Reads the shared `confirmNonce` wire key produced by Go (see the field
      // doc above + go-mknoon/node/node.go). Must stay byte-identical to Go's
      // msgData["confirmNonce"]; the existing parser pin is in chat_message_test.dart.
      confirmNonce: json['confirmNonce']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'to': to,
      'content': content,
      'timestamp': timestamp,
      'isIncoming': isIncoming,
      if (confirmNonce != null) 'confirmNonce': confirmNonce,
    };
  }

  ChatMessage copyWith({
    String? from,
    String? to,
    String? content,
    String? timestamp,
    bool? isIncoming,
    String? transport,
    String? confirmNonce,
  }) {
    return ChatMessage(
      from: from ?? this.from,
      to: to ?? this.to,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isIncoming: isIncoming ?? this.isIncoming,
      transport: transport ?? this.transport,
      confirmNonce: confirmNonce ?? this.confirmNonce,
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
