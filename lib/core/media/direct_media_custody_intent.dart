import 'dart:convert';

import 'package:crypto/crypto.dart';

const _directMediaCustodyDomain = 'direct_media_custody_v1';

/// Computes the deterministic local custody authority for one authored media
/// manifest.
///
/// Attachment identity is set-valued: duplicates are removed and the
/// remaining IDs are sorted before the domain-separated JSON array is hashed.
/// The first 16 SHA-256 bytes are returned as exactly 32 lowercase hex digits.
String computeDirectMediaCustodyIntentId({
  required String messageId,
  required Iterable<String> attachmentIds,
}) {
  final canonicalAttachmentIds = attachmentIds.toSet().toList()..sort();
  final encodedManifest = jsonEncode(<String>[
    _directMediaCustodyDomain,
    messageId,
    ...canonicalAttachmentIds,
  ]);
  final digest = sha256.convert(utf8.encode(encodedManifest)).bytes;
  return digest
      .take(16)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}
