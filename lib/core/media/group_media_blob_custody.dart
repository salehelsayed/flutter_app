import 'dart:convert';

import 'package:crypto/crypto.dart';

const String kGroupMediaBlobCustodyKind = 'group_media_blob_v1';
const String kGroupMediaBlobCustodyFingerprintDomain =
    'mknoon.group-media-blob-custody-fingerprint.v1';

final RegExp _lowerSha256 = RegExp(r'^[0-9a-f]{64}$');

/// Stable pre-upload lineage for one attachment and its frozen physical ACL.
///
/// Relay expiries are deliberately absent: a pre-content-arm proof refresh may
/// replace them without changing ciphertext, blob ID or target authority. The
/// same digest is computable by a receiver from the signed manifest, including
/// recipients that are not represented in its device-local incoming DB row.
String computeGroupMediaBlobCustodyFingerprint({
  required String groupId,
  required String messageId,
  required String attachmentId,
  required String custodyBlobId,
  required String contentHash,
  required int ciphertextSize,
  required Iterable<String> recipientPeerIds,
}) {
  for (final value in <String>[
    groupId,
    messageId,
    attachmentId,
    custodyBlobId,
  ]) {
    if (value.trim().isEmpty || value != value.trim()) {
      throw const FormatException('invalid group-media fingerprint identity');
    }
  }
  if (!_lowerSha256.hasMatch(contentHash) || ciphertextSize <= 0) {
    throw const FormatException('invalid group-media fingerprint proof');
  }
  final recipients = recipientPeerIds.toSet().toList(growable: false)..sort();
  if (recipients.any(
    (recipient) => recipient.trim().isEmpty || recipient != recipient.trim(),
  )) {
    throw const FormatException('invalid group-media fingerprint recipient');
  }
  return sha256
      .convert(
        utf8.encode(
          jsonEncode(<Object>[
            kGroupMediaBlobCustodyFingerprintDomain,
            groupId,
            messageId,
            attachmentId,
            custodyBlobId,
            contentHash,
            ciphertextSize,
            recipients,
          ]),
        ),
      )
      .toString();
}
