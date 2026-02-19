import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';

/// A P2P chat message — the canonical model used across all layers.
///
/// Incoming messages arrive from either the Go libp2p node (via push events)
/// or the local WiFi WebSocket server. Outgoing messages are created when
/// the user sends a message.
class ChatMessage {
  final String from;
  final String to;
  final String content;
  final DateTime timestamp;
  final bool isIncoming;

  const ChatMessage({
    required this.from,
    required this.to,
    required this.content,
    required this.timestamp,
    required this.isIncoming,
  });

  /// Create from a Go bridge event data map.
  factory ChatMessage.fromEventData(Map<String, dynamic> data) {
    return ChatMessage(
      from: data['from'] as String,
      to: data['to'] as String,
      content: data['content'] as String,
      timestamp: DateTime.parse(data['timestamp'] as String),
      isIncoming: data['isIncoming'] as bool? ?? true,
    );
  }

  /// Create from a [LocalChatMessage] (local WiFi delivery).
  factory ChatMessage.fromLocal(LocalChatMessage localMsg) {
    return ChatMessage(
      from: localMsg.from,
      to: localMsg.to,
      content: localMsg.content,
      timestamp: localMsg.timestamp,
      isIncoming: localMsg.isIncoming,
    );
  }

  @override
  String toString() =>
      'ChatMessage(from: $from, to: $to, isIncoming: $isIncoming)';
}
