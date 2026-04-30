import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Builds a short, deterministic safety number for comparing contact keys.
class ContactSafetyNumber {
  ContactSafetyNumber._();

  static final BigInt _oneTrillion = BigInt.from(1000000000000);

  static String? build({
    required String peerId,
    required String? publicKey,
    String? mlKemPublicKey,
  }) {
    final normalizedPeerId = peerId.trim();
    final normalizedPublicKey = publicKey?.trim();
    if (normalizedPeerId.isEmpty ||
        normalizedPublicKey == null ||
        normalizedPublicKey.isEmpty) {
      return null;
    }

    final normalizedMlKemPublicKey = mlKemPublicKey?.trim() ?? '';
    final material =
        'mknoon-safety-v1\n'
        'peer:$normalizedPeerId\n'
        'ed25519:$normalizedPublicKey\n'
        'mlkem:$normalizedMlKemPublicKey';
    final digest = sha256.convert(utf8.encode(material)).bytes;
    var value = BigInt.zero;
    for (final byte in digest.take(8)) {
      value = (value << 8) | BigInt.from(byte);
    }

    final digits = (value % _oneTrillion).toString().padLeft(12, '0');
    return '${digits.substring(0, 4)} '
        '${digits.substring(4, 8)} '
        '${digits.substring(8, 12)}';
  }
}
