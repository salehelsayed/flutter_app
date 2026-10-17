import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/key_conversion.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:pinenacl/ed25519.dart' as nacl;

/// A TEST-ONLY account identity with a real Ed25519 key pair. The seed is a
/// public fixture. [peerId] is derived from the public key with the
/// production libp2p derivation, so the pair is a genuine binding.
final class TestEd25519Identity {
  TestEd25519Identity.fromSeedByte(int seedByte)
    : signingKey = nacl.SigningKey.fromSeed(
        Uint8List.fromList(List<int>.filled(32, seedByte)),
      ),
      privateKey = 'test-only-ed25519-seed-$seedByte';

  final nacl.SigningKey signingKey;

  /// Opaque private-key handle, as the bridge sees it.
  final String privateKey;

  String get publicKey => base64Encode(signingKey.verifyKey.asTypedList);

  String get peerId => ed25519PublicKeyToPeerId(publicKey);

  /// Real Ed25519 signature over the UTF-8 bytes of [data], base64-encoded.
  String signBase64(String data) => base64Encode(
    signingKey
        .sign(Uint8List.fromList(utf8.encode(data)))
        .signature
        .asTypedList,
  );
}

/// Shared crypto authority for several [Ed25519ContactRequestBridge]s.
///
/// Signatures are real Ed25519. Encryption is a lookup table, but it is bound
/// to the recipient public key and to the outer msgId/ts associated data, so a
/// payload encrypted to the wrong key or re-labelled under another message ID
/// cannot be decrypted.
final class Ed25519ContactRequestCryptoBus {
  final Map<String, TestEd25519Identity> _byPrivateKey =
      <String, TestEd25519Identity>{};
  final Map<String, _SealedPlaintext> _sealed = <String, _SealedPlaintext>{};
  var _next = 0;

  void register(TestEd25519Identity identity) {
    _byPrivateKey[identity.privateKey] = identity;
  }

  TestEd25519Identity? identityFor(String privateKey) =>
      _byPrivateKey[privateKey];
}

final class _SealedPlaintext {
  const _SealedPlaintext(this.recipientPublicKey, this.plaintext, this.aad);

  final String recipientPublicKey;
  final String plaintext;
  final String aad;
}

/// One encrypt call as observed at the bridge boundary.
final class ObservedContactRequestEncrypt {
  const ObservedContactRequestEncrypt({
    required this.recipientPublicKey,
    required this.msgId,
    required this.payload,
  });

  final String recipientPublicKey;
  final String msgId;
  final Map<String, dynamic> payload;
}

final class Ed25519ContactRequestBridge extends Bridge {
  Ed25519ContactRequestBridge(this.bus);

  final Ed25519ContactRequestCryptoBus bus;
  final List<ObservedContactRequestEncrypt> encrypts =
      <ObservedContactRequestEncrypt>[];
  final List<String> verifiedData = <String>[];
  var verifyCalls = 0;

  /// Every command, in order, before it is answered.
  final List<Map<String, dynamic>> commands = <Map<String, dynamic>>[];
  void Function(Map<String, dynamic> request)? onCommand;

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    commands.add(request);
    onCommand?.call(request);
    final payload =
        request['payload'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    switch (request['cmd']) {
      case 'payload.sign':
        final identity = bus.identityFor(payload['privateKey'] as String);
        if (identity == null) {
          return jsonEncode(<String, Object>{'ok': false});
        }
        return jsonEncode(<String, Object>{
          'ok': true,
          'signature': identity.signBase64(payload['data'] as String),
        });
      case 'payload.verify':
        verifyCalls += 1;
        final valid = _verify(
          payload['publicKey'] as String,
          payload['data'] as String,
          payload['signature'] as String,
        );
        if (valid) verifiedData.add(payload['data'] as String);
        return jsonEncode(<String, Object>{'ok': true, 'valid': valid});
      case 'contactrequest.encrypt':
        final recipient = payload['recipientPublicKey'] as String;
        final plaintext = payload['plaintext'] as String;
        final msgId = payload['msgId'] as String;
        encrypts.add(
          ObservedContactRequestEncrypt(
            recipientPublicKey: recipient,
            msgId: msgId,
            payload: jsonDecode(plaintext) as Map<String, dynamic>,
          ),
        );
        final ciphertext = 'sealed-${++bus._next}';
        bus._sealed[ciphertext] = _SealedPlaintext(
          recipient,
          plaintext,
          '$msgId|${payload['ts']}',
        );
        return jsonEncode(<String, Object>{
          'ok': true,
          'ephemeralPublicKey': 'ephemeral-$ciphertext',
          'ciphertext': ciphertext,
          'nonce': 'nonce-$ciphertext',
        });
      case 'contactrequest.decrypt':
        final sealed = bus._sealed[payload['ciphertext'] as String];
        final owner = bus.identityFor(payload['privateKey'] as String);
        final opens =
            sealed != null &&
            owner != null &&
            owner.publicKey == sealed.recipientPublicKey &&
            sealed.aad == '${payload['msgId']}|${payload['ts']}';
        return jsonEncode(<String, Object?>{
          'ok': opens,
          if (opens) 'plaintext': sealed.plaintext,
        });
      default:
        return jsonEncode(<String, Object>{'ok': true});
    }
  }

  static bool _verify(String publicKey, String data, String signature) {
    try {
      final key = base64Decode(publicKey);
      final sig = base64Decode(signature);
      if (key.length != nacl.VerifyKey.keyLength ||
          sig.length != nacl.Signature.signatureLength) {
        return false;
      }
      return nacl.VerifyKey(Uint8List.fromList(key)).verify(
        signature: nacl.Signature(Uint8List.fromList(sig)),
        message: Uint8List.fromList(utf8.encode(data)),
      );
    } catch (_) {
      return false;
    }
  }
}

/// The account [IdentityModel] for a test identity.
IdentityModel testIdentityModel(
  TestEd25519Identity identity, {
  required String username,
  String? mlKemPublicKey,
}) => IdentityModel(
  peerId: identity.peerId,
  publicKey: identity.publicKey,
  privateKey: identity.privateKey,
  mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
  mlKemPublicKey: mlKemPublicKey,
  mlKemSecretKey: mlKemPublicKey == null ? null : 'secret-$mlKemPublicKey',
  username: username,
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
);
