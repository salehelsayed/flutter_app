import 'dart:convert';

/// Exact frozen copy of the pre-Plan-256 v2 reaction-envelope reader.
///
/// Keep this independent from production `ReactionPayload`. Historical
/// binaries required only the type/version, an encrypted map, and non-null
/// crypto entries. They did not validate additive metadata or sender fields.
Map<String, dynamic>? parseFrozenPre256ReactionV2Envelope(String source) {
  try {
    final json = jsonDecode(source) as Map<String, dynamic>;
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
