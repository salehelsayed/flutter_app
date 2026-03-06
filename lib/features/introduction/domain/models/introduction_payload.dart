import 'dart:convert';

/// Wire-format model for introduction messages sent over P2P.
///
/// Follows the same envelope pattern as `GroupInvitePayload`:
/// ```json
/// {
///   "type": "introduction",
///   "version": "1",
///   "payload": { "action", "introductionId", ... }
/// }
/// ```
///
/// Three actions:
/// - `send`: introducer → both parties (includes introduced party's keys)
/// - `accept`: responder → introducer + other party
/// - `pass`: responder → introducer + other party
class IntroductionPayload {
  final String action; // 'send', 'accept', 'pass'
  final String introductionId;
  final String? introducerId;
  final String? introducerUsername;
  final String? recipientId;
  final String? recipientUsername;
  final String? introducedId;
  final String? introducedUsername;
  final String? introducedPublicKey;
  final String? introducedMlKemPublicKey;
  final String? recipientPublicKey;
  final String? recipientMlKemPublicKey;
  final String? responderId;
  final String? responderUsername;
  final String timestamp;

  const IntroductionPayload({
    required this.action,
    required this.introductionId,
    this.introducerId,
    this.introducerUsername,
    this.recipientId,
    this.recipientUsername,
    this.introducedId,
    this.introducedUsername,
    this.introducedPublicKey,
    this.introducedMlKemPublicKey,
    this.recipientPublicKey,
    this.recipientMlKemPublicKey,
    this.responderId,
    this.responderUsername,
    required this.timestamp,
  });

  /// Serializes only the inner payload fields (without envelope wrapper).
  ///
  /// Used as plaintext input for encryption in v2 flow.
  String toInnerJson() {
    final map = <String, dynamic>{
      'action': action,
      'introductionId': introductionId,
      'timestamp': timestamp,
    };

    if (introducerId != null) map['introducerId'] = introducerId;
    if (introducerUsername != null) {
      map['introducerUsername'] = introducerUsername;
    }
    if (recipientId != null) map['recipientId'] = recipientId;
    if (recipientUsername != null) map['recipientUsername'] = recipientUsername;
    if (introducedId != null) map['introducedId'] = introducedId;
    if (introducedUsername != null) {
      map['introducedUsername'] = introducedUsername;
    }
    if (introducedPublicKey != null) {
      map['introducedPublicKey'] = introducedPublicKey;
    }
    if (introducedMlKemPublicKey != null) {
      map['introducedMlKemPublicKey'] = introducedMlKemPublicKey;
    }
    if (recipientPublicKey != null) {
      map['recipientPublicKey'] = recipientPublicKey;
    }
    if (recipientMlKemPublicKey != null) {
      map['recipientMlKemPublicKey'] = recipientMlKemPublicKey;
    }
    if (responderId != null) map['responderId'] = responderId;
    if (responderUsername != null) {
      map['responderUsername'] = responderUsername;
    }

    return jsonEncode(map);
  }

  /// Creates an IntroductionPayload from inner JSON string (decrypted payload).
  ///
  /// Returns null if JSON is invalid or missing required fields.
  static IntroductionPayload? fromInnerJson(String innerJson) {
    try {
      final payload = jsonDecode(innerJson) as Map<String, dynamic>;

      final action = payload['action'] as String?;
      final introductionId = payload['introductionId'] as String?;
      final timestamp = payload['timestamp'] as String?;

      if (action == null || introductionId == null || timestamp == null) {
        return null;
      }

      return IntroductionPayload(
        action: action,
        introductionId: introductionId,
        introducerId: payload['introducerId'] as String?,
        introducerUsername: payload['introducerUsername'] as String?,
        recipientId: payload['recipientId'] as String?,
        recipientUsername: payload['recipientUsername'] as String?,
        introducedId: payload['introducedId'] as String?,
        introducedUsername: payload['introducedUsername'] as String?,
        introducedPublicKey: payload['introducedPublicKey'] as String?,
        introducedMlKemPublicKey: payload['introducedMlKemPublicKey'] as String?,
        recipientPublicKey: payload['recipientPublicKey'] as String?,
        recipientMlKemPublicKey: payload['recipientMlKemPublicKey'] as String?,
        responderId: payload['responderId'] as String?,
        responderUsername: payload['responderUsername'] as String?,
        timestamp: timestamp,
      );
    } catch (_) {
      return null;
    }
  }

  /// Serializes to the full v1 JSON envelope string.
  String toJson() {
    final innerMap = jsonDecode(toInnerJson()) as Map<String, dynamic>;
    final envelope = {
      'type': 'introduction',
      'version': '1',
      'payload': innerMap,
    };
    return jsonEncode(envelope);
  }

  /// Parses a JSON string into an IntroductionPayload, or returns null if invalid.
  ///
  /// Expects the full v1 envelope: `{ "type": "introduction", "version": "1", "payload": {...} }`.
  static IntroductionPayload? fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      if (json['type'] != 'introduction') return null;

      final payload = json['payload'] as Map<String, dynamic>?;
      if (payload == null) return null;

      final action = payload['action'] as String?;
      final introductionId = payload['introductionId'] as String?;
      final timestamp = payload['timestamp'] as String?;

      if (action == null || introductionId == null || timestamp == null) {
        return null;
      }

      return IntroductionPayload(
        action: action,
        introductionId: introductionId,
        introducerId: payload['introducerId'] as String?,
        introducerUsername: payload['introducerUsername'] as String?,
        recipientId: payload['recipientId'] as String?,
        recipientUsername: payload['recipientUsername'] as String?,
        introducedId: payload['introducedId'] as String?,
        introducedUsername: payload['introducedUsername'] as String?,
        introducedPublicKey: payload['introducedPublicKey'] as String?,
        introducedMlKemPublicKey: payload['introducedMlKemPublicKey'] as String?,
        recipientPublicKey: payload['recipientPublicKey'] as String?,
        recipientMlKemPublicKey: payload['recipientMlKemPublicKey'] as String?,
        responderId: payload['responderId'] as String?,
        responderUsername: payload['responderUsername'] as String?,
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
  }) {
    final envelope = {
      'type': 'introduction',
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
  /// Returns the parsed envelope map if it's a v2 introduction with
  /// encrypted block, or null otherwise.
  static Map<String, dynamic>? parseEncryptedEnvelope(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'introduction') return null;
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
