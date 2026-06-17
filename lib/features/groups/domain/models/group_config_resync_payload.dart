import 'dart:convert';

/// Wire types for the on-join authoritative-metadata resync pull (finding D).
///
/// Both ride the same v2-style encrypted envelope as group-invite revocations:
/// the inner plaintext is encrypted to the recipient's ML-KEM key, then wrapped
/// in `{type, version, id, senderPeerId, encrypted{kem,ciphertext,nonce}}`.
///
/// - `config:request` inner plaintext = `{groupId, requesterPeerId}`.
/// - `config:response` inner plaintext = the admin-signed `__sys`
///   `group_metadata_updated` system payload (verified by
///   `extractGroupMetadataActorEventVerificationData` + `callVerifyPayload`).
const groupConfigRequestType = 'group_config_request';
const groupConfigResponseType = 'group_config_response';
const groupConfigResyncEnvelopeVersion = '1';

class GroupConfigResyncEnvelope {
  static String build({
    required String type,
    required String senderPeerId,
    required String groupId,
    required String kem,
    required String ciphertext,
    required String nonce,
  }) {
    return jsonEncode({
      'type': type,
      'version': groupConfigResyncEnvelopeVersion,
      'id': groupId,
      'senderPeerId': senderPeerId,
      'encrypted': {'kem': kem, 'ciphertext': ciphertext, 'nonce': nonce},
    });
  }

  /// Parses an envelope of [expectedType], returning the decoded map (with the
  /// `encrypted` sub-map) or null when malformed / wrong type.
  static Map<String, dynamic>? parse(String jsonString, String expectedType) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != expectedType) return null;
      if (json['version'] != groupConfigResyncEnvelopeVersion) return null;
      final encrypted = json['encrypted'] as Map<String, dynamic>?;
      if (encrypted == null) return null;
      if (_isBlank(json['id'] as String?) ||
          _isBlank(json['senderPeerId'] as String?) ||
          _isBlank(encrypted['kem'] as String?) ||
          _isBlank(encrypted['ciphertext'] as String?) ||
          _isBlank(encrypted['nonce'] as String?)) {
        return null;
      }
      return json;
    } catch (_) {
      return null;
    }
  }

  static bool isRequest(String jsonString) =>
      parse(jsonString, groupConfigRequestType) != null;

  static bool isResponse(String jsonString) =>
      parse(jsonString, groupConfigResponseType) != null;

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;
}

/// Inner plaintext of a `config:request`.
class GroupConfigRequestBody {
  final String groupId;
  final String requesterPeerId;

  const GroupConfigRequestBody({
    required this.groupId,
    required this.requesterPeerId,
  });

  String toInnerJson() =>
      jsonEncode({'groupId': groupId, 'requesterPeerId': requesterPeerId});

  static GroupConfigRequestBody? fromInnerJson(String innerJson) {
    try {
      final map = jsonDecode(innerJson) as Map<String, dynamic>;
      final groupId = map['groupId'] as String?;
      final requesterPeerId = map['requesterPeerId'] as String?;
      if (GroupConfigResyncEnvelope._isBlank(groupId) ||
          GroupConfigResyncEnvelope._isBlank(requesterPeerId)) {
        return null;
      }
      return GroupConfigRequestBody(
        groupId: groupId!,
        requesterPeerId: requesterPeerId!,
      );
    } catch (_) {
      return null;
    }
  }
}
