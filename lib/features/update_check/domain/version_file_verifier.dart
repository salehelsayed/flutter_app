/// Verification of the signed SE-41 version file.
///
/// Shared by the app and by `tool/sign_version_file.dart`, so the CLI checks a
/// file with exactly the code the app runs. Plain Dart only: no Flutter.
///
/// Envelope (the downloaded bytes):
/// `{"v":1,"keyId":"k1","payload":"<base64 raw payload>","sig":"<base64 Ed25519>"}`
///
/// Order (any failure = ignore the file, never block):
/// 1 size <= 16 KB, 2 envelope shape, 3 built-in keyId, 4 key rank >= stored
/// highest accepted rank, 5 Ed25519 over the decoded payload bytes, 6 payload
/// shape. Step 7 (sequence) is [decideVersionFileRatchet].
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart' as nacl;

import 'update_check_models.dart';

/// Hard cap on the envelope size, also enforced on the network.
const int maxVersionFileBytes = 16 * 1024;

const int _envelopeVersion = 1;
const int _payloadSchemaVersion = 1;

/// A built-in public key and its rank. A higher rank replaces lower ranks
/// forever (one-way ratchet).
class TrustedVersionKey {
  TrustedVersionKey({
    required this.keyId,
    required this.rank,
    required List<int> publicKey,
  }) : publicKey = Uint8List.fromList(publicKey) {
    if (rank < 1) {
      throw ArgumentError.value(rank, 'rank', 'must be >= 1');
    }
    if (this.publicKey.length != nacl.VerifyKey.keyLength) {
      throw ArgumentError.value(
        this.publicKey.length,
        'publicKey',
        'must be ${nacl.VerifyKey.keyLength} bytes',
      );
    }
  }

  factory TrustedVersionKey.fromBase64({
    required String keyId,
    required int rank,
    required String publicKeyBase64,
  }) => TrustedVersionKey(
    keyId: keyId,
    rank: rank,
    publicKey: base64.decode(publicKeyBase64),
  );

  final String keyId;
  final int rank;
  final Uint8List publicKey;
}

/// Why a file was ignored. Used by tests and logs; never shown to users.
enum VersionFileRejection {
  tooLarge,
  malformedEnvelope,
  unknownKey,
  rankBelowStored,
  badSignature,
  malformedPayload,
  unsupportedSchema,
  missingPlatform,
  minAboveLatest,
}

/// A file whose signature and payload both passed.
class VerifiedVersionFile {
  const VerifiedVersionFile({
    required this.envelopeBytes,
    required this.keyId,
    required this.rank,
    required this.payloadBytes,
    required this.payload,
  });

  final Uint8List envelopeBytes;
  final String keyId;
  final int rank;
  final Uint8List payloadBytes;
  final VersionPayload payload;
}

/// Result of [VersionFileVerifier.verify]: exactly one of the two is set.
class VersionFileCheck {
  const VersionFileCheck.accepted(VerifiedVersionFile this.file)
    : rejection = null;

  const VersionFileCheck.rejected(VersionFileRejection this.rejection)
    : file = null;

  final VerifiedVersionFile? file;
  final VersionFileRejection? rejection;

  bool get isAccepted => file != null;
}

class VersionFileVerifier {
  VersionFileVerifier(Iterable<TrustedVersionKey> keys)
    : _keys = {for (final key in keys) key.keyId: key};

  final Map<String, TrustedVersionKey> _keys;

  /// Rank of a built-in key, or null when the key is not built in.
  int? rankOf(String keyId) => _keys[keyId]?.rank;

  /// Runs steps 1-6 on raw envelope bytes.
  ///
  /// [highestAcceptedRank] is the stored ratchet (0 when nothing is stored).
  /// [requiredPlatforms] must all be present in the payload: the app passes
  /// its own platform, the signing CLI passes both.
  VersionFileCheck verify(
    List<int> envelopeBytes, {
    required int highestAcceptedRank,
    required Set<UpdatePlatform> requiredPlatforms,
  }) {
    // 1 size.
    if (envelopeBytes.length > maxVersionFileBytes) {
      return const VersionFileCheck.rejected(VersionFileRejection.tooLarge);
    }
    // 2 envelope.
    final envelope = _parseEnvelope(envelopeBytes);
    if (envelope == null) {
      return const VersionFileCheck.rejected(
        VersionFileRejection.malformedEnvelope,
      );
    }
    // 3 built-in key.
    final key = _keys[envelope.keyId];
    if (key == null) {
      return const VersionFileCheck.rejected(VersionFileRejection.unknownKey);
    }
    // 4 rank ratchet.
    if (key.rank < highestAcceptedRank) {
      return const VersionFileCheck.rejected(
        VersionFileRejection.rankBelowStored,
      );
    }
    // 5 signature over the decoded payload bytes, exactly as received.
    if (!verifyEd25519(
      publicKey: key.publicKey,
      message: envelope.payload,
      signature: envelope.signature,
    )) {
      return const VersionFileCheck.rejected(VersionFileRejection.badSignature);
    }
    // 6 payload.
    final parsed = parseVersionPayload(
      envelope.payload,
      requiredPlatforms: requiredPlatforms,
    );
    if (parsed.payload == null) {
      return VersionFileCheck.rejected(parsed.rejection!);
    }
    return VersionFileCheck.accepted(
      VerifiedVersionFile(
        envelopeBytes: Uint8List.fromList(envelopeBytes),
        keyId: envelope.keyId,
        rank: key.rank,
        payloadBytes: envelope.payload,
        payload: parsed.payload!,
      ),
    );
  }
}

/// Ed25519 verification (pinenacl). Returns false instead of throwing.
bool verifyEd25519({
  required List<int> publicKey,
  required List<int> message,
  required List<int> signature,
}) {
  if (publicKey.length != nacl.VerifyKey.keyLength ||
      signature.length != nacl.Signature.signatureLength) {
    return false;
  }
  try {
    return nacl.VerifyKey(Uint8List.fromList(publicKey)).verify(
      signature: nacl.Signature(Uint8List.fromList(signature)),
      message: Uint8List.fromList(message),
    );
  } catch (_) {
    // pinenacl throws on a forged or malformed signature.
    return false;
  }
}

/// Result of [parseVersionPayload]: exactly one of the two is set.
class VersionPayloadParse {
  const VersionPayloadParse._(this.payload, this.rejection);

  final VersionPayload? payload;
  final VersionFileRejection? rejection;
}

/// Step 6. Also used by the CLI before it signs (with both platforms
/// required). Every platform section that is present must be valid.
VersionPayloadParse parseVersionPayload(
  List<int> payloadBytes, {
  required Set<UpdatePlatform> requiredPlatforms,
}) {
  VersionPayloadParse reject(VersionFileRejection reason) =>
      VersionPayloadParse._(null, reason);

  final Object? decoded = _decodeJson(payloadBytes);
  if (decoded is! Map<String, Object?>) {
    return reject(VersionFileRejection.malformedPayload);
  }
  final schemaVersion = decoded['schemaVersion'];
  if (schemaVersion is! int || schemaVersion != _payloadSchemaVersion) {
    return reject(VersionFileRejection.unsupportedSchema);
  }
  final sequence = decoded['sequence'];
  final issuedAt = decoded['issuedAt'];
  if (!_isNonNegativeInt(sequence) || !_isNonNegativeInt(issuedAt)) {
    return reject(VersionFileRejection.malformedPayload);
  }
  final platforms = <UpdatePlatform, UpdatePlatformPolicy>{};
  for (final platform in UpdatePlatform.values) {
    if (!decoded.containsKey(platform.wireName)) continue;
    final section = decoded[platform.wireName];
    if (section is! Map<String, Object?>) {
      return reject(VersionFileRejection.malformedPayload);
    }
    final latestBuild = section['latestBuild'];
    final minBuild = section['minBuild'];
    if (!_isNonNegativeInt(latestBuild) || !_isNonNegativeInt(minBuild)) {
      return reject(VersionFileRejection.malformedPayload);
    }
    if ((minBuild as int) > (latestBuild as int)) {
      return reject(VersionFileRejection.minAboveLatest);
    }
    platforms[platform] = UpdatePlatformPolicy(
      latestBuild: latestBuild,
      minBuild: minBuild,
      reasonCode: UpdateReasonCode.parse(section['reasonCode']),
    );
  }
  if (!requiredPlatforms.every(platforms.containsKey)) {
    return reject(VersionFileRejection.missingPlatform);
  }
  return VersionPayloadParse._(
    VersionPayload(
      sequence: sequence as int,
      issuedAt: issuedAt as int,
      platforms: Map.unmodifiable(platforms),
    ),
    null,
  );
}

/// Builds envelope bytes. Used by the CLI after signing and by tests.
Uint8List encodeVersionEnvelope({
  required String keyId,
  required List<int> payloadBytes,
  required List<int> signature,
}) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'v': _envelopeVersion,
      'keyId': keyId,
      'payload': base64.encode(payloadBytes),
      'sig': base64.encode(signature),
    }),
  ),
);

/// What step 7 does with a verified file.
enum VersionFileRatchet {
  /// Store it: new highest rank, a higher sequence in the same rank, or the
  /// same rank and sequence when no envelope is stored.
  accept,

  /// Same rank, same sequence, byte-identical payload: only lastCheckAt moves.
  refresh,

  /// Replay or conflicting file: ignore it.
  ignore,
}

/// Step 7. [storedPayloadBytes] is the payload of the stored, re-verified
/// envelope (null when nothing is stored).
VersionFileRatchet decideVersionFileRatchet({
  required VerifiedVersionFile candidate,
  required int highestAcceptedRank,
  required int? storedSequence,
  required List<int>? storedPayloadBytes,
}) {
  if (candidate.rank < highestAcceptedRank) return VersionFileRatchet.ignore;
  // A higher rank starts its sequence fresh.
  if (candidate.rank > highestAcceptedRank || storedSequence == null) {
    return VersionFileRatchet.accept;
  }
  final sequence = candidate.payload.sequence;
  if (sequence > storedSequence) return VersionFileRatchet.accept;
  // The stored envelope was dropped (a retired key, corrupt bytes) but its rank
  // and sequence stay. The same rank and sequence is no rollback: take it.
  if (sequence == storedSequence && storedPayloadBytes == null) {
    return VersionFileRatchet.accept;
  }
  if (sequence == storedSequence &&
      storedPayloadBytes != null &&
      _bytesEqual(candidate.payloadBytes, storedPayloadBytes)) {
    return VersionFileRatchet.refresh;
  }
  return VersionFileRatchet.ignore;
}

class _Envelope {
  const _Envelope(this.keyId, this.payload, this.signature);

  final String keyId;
  final Uint8List payload;
  final Uint8List signature;
}

_Envelope? _parseEnvelope(List<int> bytes) {
  final Object? decoded = _decodeJson(bytes);
  if (decoded is! Map<String, Object?>) return null;
  final version = decoded['v'];
  if (version is! int || version != _envelopeVersion) return null;
  final keyId = decoded['keyId'];
  final payload = decoded['payload'];
  final sig = decoded['sig'];
  if (keyId is! String || payload is! String || sig is! String) return null;
  final payloadBytes = _strictBase64(payload);
  final sigBytes = _strictBase64(sig);
  if (payloadBytes == null || sigBytes == null) return null;
  return _Envelope(keyId, payloadBytes, sigBytes);
}

Object? _decodeJson(List<int> bytes) {
  try {
    return jsonDecode(utf8.decode(bytes));
  } on FormatException {
    return null;
  }
}

/// Standard padded base64 only: the input must re-encode to itself.
Uint8List? _strictBase64(String text) {
  try {
    final bytes = base64.decode(text);
    return base64.encode(bytes) == text ? bytes : null;
  } on FormatException {
    return null;
  }
}

bool _isNonNegativeInt(Object? value) => value is int && value >= 0;

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
