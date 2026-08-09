import 'dart:convert';

/// Wire-format model for delete-for-everyone message events.
///
/// - v1: `{ "type": "message_deletion", "version": "1", "payload": {...} }`
/// - v2: `{ "type": "message_deletion", "version": "2", "senderPeerId": "...", "encrypted": { ... } }`
///
/// Inner payload: `{ "messageId", "senderPeerId", "timestamp" }`
class MessageDeletionPayload {
  final String messageId;
  final String senderPeerId;
  final String timestamp;
  final String? eventId;

  const MessageDeletionPayload({
    required this.messageId,
    required this.senderPeerId,
    required this.timestamp,
    this.eventId,
  });

  static MessageDeletionPayload? fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'message_deletion') return null;

      final payload = json['payload'] as Map<String, dynamic>?;
      if (payload == null) return null;

      final messageId = payload['messageId'] as String?;
      final senderPeerId = payload['senderPeerId'] as String?;
      final timestamp = payload['timestamp'] as String?;
      if (messageId == null || senderPeerId == null || timestamp == null) {
        return null;
      }

      return MessageDeletionPayload(
        messageId: messageId,
        senderPeerId: senderPeerId,
        timestamp: timestamp,
        eventId: payload['eventId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  String toJson() {
    return jsonEncode({
      'type': 'message_deletion',
      'version': '1',
      'payload': {
        'messageId': messageId,
        'senderPeerId': senderPeerId,
        'timestamp': timestamp,
        if (eventId != null) 'eventId': eventId,
      },
    });
  }

  static String buildEncryptedEnvelope({
    required String senderPeerId,
    required String kem,
    required String ciphertext,
    required String nonce,
    String? eventId,
  }) {
    return jsonEncode({
      'type': 'message_deletion',
      'version': '2',
      'senderPeerId': senderPeerId,
      'eventId': ?eventId,
      'encrypted': {'kem': kem, 'ciphertext': ciphertext, 'nonce': nonce},
    });
  }

  static Map<String, dynamic>? parseEncryptedEnvelope(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'message_deletion') return null;
      if (json['version'] != '2') return null;
      if (json.containsKey('eventId') && json['eventId'] is! String) {
        return null;
      }
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

  static MessageDeletionPayload? fromDecryptedJson(String innerJson) {
    try {
      final payload = jsonDecode(innerJson) as Map<String, dynamic>;
      final messageId = payload['messageId'] as String?;
      final senderPeerId = payload['senderPeerId'] as String?;
      final timestamp = payload['timestamp'] as String?;
      if (payload.containsKey('eventId') && payload['eventId'] is! String) {
        return null;
      }
      if (messageId == null || senderPeerId == null || timestamp == null) {
        return null;
      }
      return MessageDeletionPayload(
        messageId: messageId,
        senderPeerId: senderPeerId,
        timestamp: timestamp,
        eventId: payload['eventId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  String toInnerJson() {
    return jsonEncode({
      'messageId': messageId,
      'senderPeerId': senderPeerId,
      'timestamp': timestamp,
      if (eventId != null) 'eventId': eventId,
    });
  }
}
