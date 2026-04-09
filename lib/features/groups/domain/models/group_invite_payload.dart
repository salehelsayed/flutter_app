import 'dart:convert';

/// Wire-format model for group invite messages sent over P2P.
///
/// Follows the same envelope pattern as `MessagePayload`:
/// ```json
/// {
///   "type": "group_invite",
///   "version": "1",
///   "payload": { "id", "groupId", "groupKey", "keyEpoch", "groupConfig", ... }
/// }
/// ```
class GroupInvitePayload {
  final String id;
  final String groupId;
  final String groupKey;
  final int keyEpoch;
  final Map<String, dynamic> groupConfig;
  final String senderPeerId;
  final String senderUsername;
  final String timestamp;

  const GroupInvitePayload({
    required this.id,
    required this.groupId,
    required this.groupKey,
    required this.keyEpoch,
    required this.groupConfig,
    required this.senderPeerId,
    required this.senderUsername,
    required this.timestamp,
  });

  /// Serializes only the inner payload fields (without envelope wrapper).
  ///
  /// Used as plaintext input for encryption in v2 flow.
  String toInnerJson() {
    return jsonEncode({
      'id': id,
      'groupId': groupId,
      'groupKey': groupKey,
      'keyEpoch': keyEpoch,
      'groupConfig': groupConfig,
      'senderPeerId': senderPeerId,
      'senderUsername': senderUsername,
      'timestamp': timestamp,
    });
  }

  /// Creates a GroupInvitePayload from inner JSON string (decrypted payload).
  ///
  /// Returns null if JSON is invalid or missing required fields.
  static GroupInvitePayload? fromInnerJson(String innerJson) {
    try {
      final payload = jsonDecode(innerJson) as Map<String, dynamic>;

      final id = payload['id'] as String?;
      final groupId = payload['groupId'] as String?;
      final groupKey = payload['groupKey'] as String?;
      final keyEpoch = payload['keyEpoch'] as int?;
      final groupConfig = payload['groupConfig'] as Map<String, dynamic>?;
      final senderPeerId = payload['senderPeerId'] as String?;
      final senderUsername = payload['senderUsername'] as String?;
      final timestamp = payload['timestamp'] as String?;

      if (id == null ||
          groupId == null ||
          groupKey == null ||
          keyEpoch == null ||
          groupConfig == null ||
          senderPeerId == null ||
          senderUsername == null ||
          timestamp == null) {
        return null;
      }

      return GroupInvitePayload(
        id: id,
        groupId: groupId,
        groupKey: groupKey,
        keyEpoch: keyEpoch,
        groupConfig: groupConfig,
        senderPeerId: senderPeerId,
        senderUsername: senderUsername,
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
      'groupId': groupId,
      'groupKey': groupKey,
      'keyEpoch': keyEpoch,
      'groupConfig': groupConfig,
      'senderPeerId': senderPeerId,
      'senderUsername': senderUsername,
      'timestamp': timestamp,
    };
    final envelope = {
      'type': 'group_invite',
      'version': '1',
      'payload': payload,
    };
    return jsonEncode(envelope);
  }

  /// Parses a JSON string into a GroupInvitePayload, or returns null if invalid.
  ///
  /// Expects the full v1 envelope: `{ "type": "group_invite", "version": "1", "payload": {...} }`.
  static GroupInvitePayload? fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      if (json['type'] != 'group_invite') return null;

      final payload = json['payload'] as Map<String, dynamic>?;
      if (payload == null) return null;

      final id = payload['id'] as String?;
      final groupId = payload['groupId'] as String?;
      final groupKey = payload['groupKey'] as String?;
      final keyEpoch = payload['keyEpoch'] as int?;
      final groupConfig = payload['groupConfig'] as Map<String, dynamic>?;
      final senderPeerId = payload['senderPeerId'] as String?;
      final senderUsername = payload['senderUsername'] as String?;
      final timestamp = payload['timestamp'] as String?;

      if (id == null ||
          groupId == null ||
          groupKey == null ||
          keyEpoch == null ||
          groupConfig == null ||
          senderPeerId == null ||
          senderUsername == null ||
          timestamp == null) {
        return null;
      }

      return GroupInvitePayload(
        id: id,
        groupId: groupId,
        groupKey: groupKey,
        keyEpoch: keyEpoch,
        groupConfig: groupConfig,
        senderPeerId: senderPeerId,
        senderUsername: senderUsername,
        timestamp: timestamp,
      );
    } catch (_) {
      return null;
    }
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
    String? inviteId,
    String? groupId,
    String? senderUsername,
    String? groupName,
  }) {
    final envelope = {
      'type': 'group_invite',
      'version': '2',
      if (inviteId != null && inviteId.isNotEmpty) 'id': inviteId,
      'senderPeerId': senderPeerId,
      if (senderUsername != null && senderUsername.isNotEmpty)
        'senderUsername': senderUsername,
      if (groupId != null && groupId.isNotEmpty) 'groupId': groupId,
      if (groupName != null && groupName.isNotEmpty) 'groupName': groupName,
      'encrypted': {'kem': kem, 'ciphertext': ciphertext, 'nonce': nonce},
    };
    return jsonEncode(envelope);
  }

  /// Attempts to parse a JSON string as a v2 encrypted envelope.
  ///
  /// Returns the parsed envelope map if it's a v2 group_invite with
  /// encrypted block, or null otherwise.
  static Map<String, dynamic>? parseEncryptedEnvelope(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'group_invite') return null;
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
}
