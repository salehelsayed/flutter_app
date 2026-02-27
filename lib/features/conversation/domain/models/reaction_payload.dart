import 'dart:convert';

import 'message_reaction.dart';

/// Wire-format model for emoji reactions sent over P2P.
///
/// Follows the same envelope pattern as `MessagePayload`:
/// - v1: `{ "type": "message_reaction", "version": "1", "payload": {...} }`
/// - v2: `{ "type": "message_reaction", "version": "2", "senderPeerId": "...", "encrypted": { "kem", "ciphertext", "nonce" } }`
///
/// Inner payload: `{ "id", "messageId", "emoji", "action", "senderPeerId", "timestamp" }`
/// Action is either `"add"` or `"remove"`.
class ReactionPayload {
  final String id;
  final String messageId;
  final String emoji;
  final String action; // 'add' | 'remove'
  final String senderPeerId;
  final String timestamp;

  const ReactionPayload({
    required this.id,
    required this.messageId,
    required this.emoji,
    required this.action,
    required this.senderPeerId,
    required this.timestamp,
  });

  /// Parses a JSON string into a ReactionPayload (v1 envelope), or null.
  static ReactionPayload? fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      if (json['type'] != 'message_reaction') return null;

      final payload = json['payload'] as Map<String, dynamic>?;
      if (payload == null) return null;

      final id = payload['id'] as String?;
      final messageId = payload['messageId'] as String?;
      final emoji = payload['emoji'] as String?;
      final action = payload['action'] as String?;
      final senderPeerId = payload['senderPeerId'] as String?;
      final timestamp = payload['timestamp'] as String?;

      if (id == null ||
          messageId == null ||
          emoji == null ||
          action == null ||
          senderPeerId == null ||
          timestamp == null) {
        return null;
      }

      return ReactionPayload(
        id: id,
        messageId: messageId,
        emoji: emoji,
        action: action,
        senderPeerId: senderPeerId,
        timestamp: timestamp,
      );
    } catch (_) {
      return null;
    }
  }

  /// Serializes to the full v1 JSON envelope string.
  String toJson() {
    final payload = {
      'id': id,
      'messageId': messageId,
      'emoji': emoji,
      'action': action,
      'senderPeerId': senderPeerId,
      'timestamp': timestamp,
    };
    final envelope = {
      'type': 'message_reaction',
      'version': '1',
      'payload': payload,
    };
    return jsonEncode(envelope);
  }

  /// Builds a v2 encrypted envelope JSON string.
  static String buildEncryptedEnvelope({
    required String senderPeerId,
    required String kem,
    required String ciphertext,
    required String nonce,
  }) {
    final envelope = {
      'type': 'message_reaction',
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
  /// Returns the parsed envelope map if it's a v2 message_reaction with
  /// encrypted block, or null otherwise.
  static Map<String, dynamic>? parseEncryptedEnvelope(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'message_reaction') return null;
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

  /// Creates a ReactionPayload from decrypted inner JSON string.
  static ReactionPayload? fromDecryptedJson(String innerJson) {
    try {
      final payload = jsonDecode(innerJson) as Map<String, dynamic>;
      final id = payload['id'] as String?;
      final messageId = payload['messageId'] as String?;
      final emoji = payload['emoji'] as String?;
      final action = payload['action'] as String?;
      final senderPeerId = payload['senderPeerId'] as String?;
      final timestamp = payload['timestamp'] as String?;

      if (id == null ||
          messageId == null ||
          emoji == null ||
          action == null ||
          senderPeerId == null ||
          timestamp == null) {
        return null;
      }

      return ReactionPayload(
        id: id,
        messageId: messageId,
        emoji: emoji,
        action: action,
        senderPeerId: senderPeerId,
        timestamp: timestamp,
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
      'messageId': messageId,
      'emoji': emoji,
      'action': action,
      'senderPeerId': senderPeerId,
      'timestamp': timestamp,
    });
  }

  /// Converts this wire-format payload to a local MessageReaction.
  MessageReaction toMessageReaction() {
    return MessageReaction(
      id: id,
      messageId: messageId,
      emoji: emoji,
      senderPeerId: senderPeerId,
      timestamp: timestamp,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }
}
