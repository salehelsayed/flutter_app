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
    // B4: optional per-device fingerprints to fold into the number. EMPTY (the
    // default, every existing caller) yields the byte-identical `v1` account-level
    // number — non-breaking. When non-empty, a sorted device block is folded in
    // and the version bumps to `v2`, so adding/swapping a device changes the
    // displayed number (a deliberate security-string change).
    List<String> deviceFingerprints = const [],
    // 360: EXPLICIT roster initialization, independent of whether any device
    // fingerprint survives.
    //
    // Deriving "has a roster" from `deviceFingerprints.isNotEmpty` is wrong at
    // exactly the moment it matters: a contact whose only linked device was
    // revoked, or whose legacy target was revoked, has made a real security
    // decision — and silently falling back to the `v1` account-level number
    // would show the SAME digits as before that decision. Once initialized the
    // number stays `v2`, so revoking a device visibly changes the string the
    // two people compare.
    bool rosterInitialized = false,
  }) {
    final normalizedPeerId = peerId.trim();
    final normalizedPublicKey = publicKey?.trim();
    if (normalizedPeerId.isEmpty ||
        normalizedPublicKey == null ||
        normalizedPublicKey.isEmpty) {
      return null;
    }

    final normalizedMlKemPublicKey = mlKemPublicKey?.trim() ?? '';
    final normalizedDevices =
        deviceFingerprints
            .map((fingerprint) => fingerprint.trim())
            .where((fingerprint) => fingerprint.isNotEmpty)
            .toList()
          ..sort();
    final String material;
    if (normalizedDevices.isEmpty && !rosterInitialized) {
      material =
          'mknoon-safety-v1\n'
          'peer:$normalizedPeerId\n'
          'ed25519:$normalizedPublicKey\n'
          'mlkem:$normalizedMlKemPublicKey';
    } else {
      material =
          'mknoon-safety-v2\n'
          'peer:$normalizedPeerId\n'
          'ed25519:$normalizedPublicKey\n'
          'mlkem:$normalizedMlKemPublicKey\n'
          'devices:${normalizedDevices.join(",")}';
    }
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
