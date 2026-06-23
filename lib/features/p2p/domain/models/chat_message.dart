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

  /// 147: transient, in-memory-only plaintext attached by the inbox-drain
  /// decrypt-prefetch pass (p2p_service_impl `_predecryptInboxChatEntries`).
  /// When the bounded fan-out has already decrypted this message's v2 envelope
  /// ahead of the serial commit loop, the resulting inner JSON rides here so the
  /// handler (handleIncomingChatMessage, via ChatMessageListener) can skip its
  /// own bridge decrypt. Like [transport] this is a transport-layer annotation:
  /// it is NOT part of the wire/DB contract (excluded from ==, hashCode, toJson,
  /// fromJson) and is null on every live path (decrypt-in-handler default).
  final String? predecryptedText;

  const ChatMessage({
    required this.from,
    required this.to,
    required this.content,
    required this.timestamp,
    required this.isIncoming,
    this.transport,
    this.confirmNonce,
    this.predecryptedText,
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
    String? predecryptedText,
  }) {
    return ChatMessage(
      from: from ?? this.from,
      to: to ?? this.to,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isIncoming: isIncoming ?? this.isIncoming,
      transport: transport ?? this.transport,
      confirmNonce: confirmNonce ?? this.confirmNonce,
      predecryptedText: predecryptedText ?? this.predecryptedText,
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
