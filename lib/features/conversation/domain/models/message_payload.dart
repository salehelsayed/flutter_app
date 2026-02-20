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
  final String? quotedMessageId;
  final List<Map<String, dynamic>>? media;

  const MessagePayload({
    required this.id,
    required this.text,
    required this.senderPeerId,
    required this.senderUsername,
    required this.timestamp,
    this.quotedMessageId,
    this.media,
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

      final quotedMessageId = payload['quotedMessageId'] as String?;

      final rawMedia = payload['media'] as List<dynamic>?;
      final media = rawMedia
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      return MessagePayload(
        id: id,
        text: text,
        senderPeerId: senderPeerId,
        senderUsername: senderUsername,
        timestamp: timestamp,
        quotedMessageId: quotedMessageId,
        media: media,
      );
    } catch (_) {
      return null;
    }
  }

  /// Serializes to the full JSON envelope string.
  String toJson() {
    final payload = {
      'id': id,
      'text': text,
      'senderPeerId': senderPeerId,
      'senderUsername': senderUsername,
      'timestamp': timestamp,
      if (quotedMessageId != null) 'quotedMessageId': quotedMessageId,
      if (media != null && media!.isNotEmpty) 'media': media,
    };
    final envelope = {
      'type': 'chat_message',
      'version': '1',
      'payload': payload,
    };
    return jsonEncode(envelope);
  }

  /// Builds a v2 encrypted envelope JSON string.
  ///
  /// The envelope contains the KEM ciphertext, AES ciphertext, and nonce
  /// alongside the sender's peer ID (cleartext for routing).
  static String buildEncryptedEnvelope({
    required String senderPeerId,
    required String kem,
    required String ciphertext,
    required String nonce,
  }) {
    final envelope = {
      'type': 'chat_message',
      'version': '2',
      'senderPeerId': senderPeerId,
      'encrypted': {
        'kem': kem,
        'ciphertext': ciphertext,
        'nonce': nonce,
      },
    };
    return jsonEncode(envelope);
  }

  /// Attempts to parse a JSON string as a v2 encrypted envelope.
  ///
  /// Returns the parsed envelope map if it's a v2 chat_message with
  /// encrypted block, or null otherwise.
  static Map<String, dynamic>? parseEncryptedEnvelope(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'chat_message') return null;
      if (json['version'] != '2') return null;
      final encrypted = json['encrypted'] as Map<String, dynamic>?;
      if (encrypted == null) return null;
      if (encrypted['kem'] == null ||
          encrypted['ciphertext'] == null ||
          encrypted['nonce'] == null) {
        return null;
      }
      return json;
    } catch (_) {
      return null;
    }
  }

  /// Creates a MessagePayload from decrypted inner JSON string.
  ///
  /// The inner JSON contains: id, text, senderPeerId, senderUsername, timestamp.
  static MessagePayload? fromDecryptedJson(String innerJson) {
    try {
      final payload = jsonDecode(innerJson) as Map<String, dynamic>;
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

      final quotedMessageId = payload['quotedMessageId'] as String?;

      final rawMedia = payload['media'] as List<dynamic>?;
      final media = rawMedia
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      return MessagePayload(
        id: id,
        text: text,
        senderPeerId: senderPeerId,
        senderUsername: senderUsername,
        timestamp: timestamp,
        quotedMessageId: quotedMessageId,
        media: media,
      );
    } catch (_) {
      return null;
    }
  }

  /// Serializes only the inner payload fields (without envelope wrapper).
  ///
  /// Used as plaintext input for encryption in v2 flow.
  String toInnerJson() {
    return jsonEncode({
      'id': id,
      'text': text,
      'senderPeerId': senderPeerId,
      'senderUsername': senderUsername,
      'timestamp': timestamp,
      if (quotedMessageId != null) 'quotedMessageId': quotedMessageId,
      if (media != null && media!.isNotEmpty) 'media': media,
    });
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
      quotedMessageId: quotedMessageId,
    );
  }
}
