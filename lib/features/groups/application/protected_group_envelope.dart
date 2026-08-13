import 'dart:convert';

const linkedGroupBootstrapEnvelopeType = 'linked_group_bootstrap_v1';
const protectedGroupAuthorityEnvelopeType = 'group_authority_v1';
const protectedGroupEnvelopeVersion = '1';
const protectedGroupLogicalIdMaxLength = 512;

const _outerKeys = <String>{
  'type',
  'version',
  'id',
  'senderPeerId',
  'recipientPeerId',
  'encrypted',
};
const _encryptedKeys = <String>{'kem', 'ciphertext', 'nonce'};

class ProtectedGroupEnvelope {
  const ProtectedGroupEnvelope({
    required this.type,
    required this.id,
    required this.senderPeerId,
    required this.recipientPeerId,
    required this.kem,
    required this.ciphertext,
    required this.nonce,
  });

  final String type;
  final String id;
  final String senderPeerId;
  final String recipientPeerId;
  final String kem;
  final String ciphertext;
  final String nonce;

  String toJson() => jsonEncode(<String, Object?>{
    'type': type,
    'version': protectedGroupEnvelopeVersion,
    'id': id,
    'senderPeerId': senderPeerId,
    'recipientPeerId': recipientPeerId,
    'encrypted': <String, Object?>{
      'kem': kem,
      'ciphertext': ciphertext,
      'nonce': nonce,
    },
  });

  static ProtectedGroupEnvelope? tryParse(String raw, {String? expectedType}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          !_hasExactKeys(decoded, _outerKeys)) {
        return null;
      }
      final type = _exactString(decoded['type']);
      final id = _exactString(decoded['id']);
      final senderPeerId = _exactString(decoded['senderPeerId']);
      final recipientPeerId = _exactString(decoded['recipientPeerId']);
      if ((type != linkedGroupBootstrapEnvelopeType &&
              type != protectedGroupAuthorityEnvelopeType) ||
          (expectedType != null && type != expectedType) ||
          decoded['version'] != protectedGroupEnvelopeVersion ||
          !_validLogicalId(id) ||
          senderPeerId == null ||
          recipientPeerId == null ||
          senderPeerId == recipientPeerId) {
        return null;
      }
      final encrypted = decoded['encrypted'];
      if (encrypted is! Map<String, dynamic> ||
          !_hasExactKeys(encrypted, _encryptedKeys)) {
        return null;
      }
      final kem = _exactString(encrypted['kem']);
      final ciphertext = _exactString(encrypted['ciphertext']);
      final nonce = _exactString(encrypted['nonce']);
      if (kem == null || ciphertext == null || nonce == null) return null;
      return ProtectedGroupEnvelope(
        type: type!,
        id: id!,
        senderPeerId: senderPeerId,
        recipientPeerId: recipientPeerId,
        kem: kem,
        ciphertext: ciphertext,
        nonce: nonce,
      );
    } catch (_) {
      return null;
    }
  }
}

bool _hasExactKeys(Map<String, dynamic> value, Set<String> keys) =>
    value.length == keys.length && value.keys.toSet().containsAll(keys);

String? _exactString(Object? value) {
  if (value is! String || value.isEmpty || value.trim() != value) return null;
  return value;
}

bool _validLogicalId(String? value) {
  if (value == null || value.length > protectedGroupLogicalIdMaxLength) {
    return false;
  }
  return RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);
}
