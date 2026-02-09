import 'dart:convert';

import 'conversation_message.dart';

/// Wire-format model for chat messages sent over P2P.
///
/// Follows the same envelope pattern as `contact_request`:
/// ```json
/// {
///   "type": "chat_message",
///   "version": "1",
///   "payload": { "id", "text", "senderPeerId", "senderUsername", "timestamp" }
/// }
/// ```
class MessagePayload {
  final String id;
  final String text;
  final String senderPeerId;
  final String senderUsername;
  final String timestamp;

  const MessagePayload({
    required this.id,
    required this.text,
    required this.senderPeerId,
    required this.senderUsername,
    required this.timestamp,
  });

  /// Parses a JSON string into a MessagePayload, or returns null if invalid.
  ///
  /// Expects the full envelope: `{ "type": "chat_message", "version": "1", "payload": {...} }`.
  static MessagePayload? fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      if (json['type'] != 'chat_message') return null;

      final payload = json['payload'] as Map<String, dynamic>?;
      if (payload == null) return null;

      final id = payload['id'] as String?;
      final text = payload['text'] as String?;
      final senderPeerId = payload['senderPeerId'] as String?;
      final senderUsername = payload['senderUsername'] as String?;
      final timestamp = payload['timestamp'] as String?;

      if (id == null ||
          text == null ||
          senderPeerId == null ||
          senderUsername == null ||
          timestamp == null) {
        return null;
      }

      return MessagePayload(
        id: id,
        text: text,
        senderPeerId: senderPeerId,
        senderUsername: senderUsername,
        timestamp: timestamp,
      );
    } catch (_) {
      return null;
    }
  }

  /// Serializes to the full JSON envelope string.
  String toJson() {
    final envelope = {
      'type': 'chat_message',
      'version': '1',
      'payload': {
        'id': id,
        'text': text,
        'senderPeerId': senderPeerId,
        'senderUsername': senderUsername,
        'timestamp': timestamp,
      },
    };
    return jsonEncode(envelope);
  }

  /// Converts this wire-format payload to a local ConversationMessage.
  ///
  /// [contactPeerId] is the peer ID of the contact the conversation is with.
  /// [isIncoming] indicates whether the message was received or sent.
  ConversationMessage toConversationMessage({
    required String contactPeerId,
    required bool isIncoming,
    String status = 'sent',
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: contactPeerId,
      senderPeerId: senderPeerId,
      text: text,
      timestamp: timestamp,
      status: status,
      isIncoming: isIncoming,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }
}
