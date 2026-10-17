import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/received_call_wake_handle_store.dart';

/// Shared deterministic crypto boundary for two-user contact-request tests.
///
/// The production send/receive code still assembles, canonicalizes, encrypts,
/// decrypts, reconstructs, and verifies every payload. This fake only supplies
/// deterministic native bridge results and rejects signatures whose verified
/// data differs from the exact data originally signed.
final class ContactRequestCryptoBus {
  final Map<String, String> privateKeyByPublicKey = <String, String>{};
  final Map<String, String> plaintextByCiphertext = <String, String>{};
  var _nextCiphertext = 0;

  String signatureFor(String privateKey, String data) =>
      base64UrlEncode(utf8.encode('$privateKey\u0000$data'));

  String encrypt(String plaintext) {
    final ciphertext = 'ciphertext-${++_nextCiphertext}';
    plaintextByCiphertext[ciphertext] = plaintext;
    return ciphertext;
  }
}

/// One user's bridge over a shared [ContactRequestCryptoBus].
final class DeterministicContactRequestBridge extends Bridge {
  DeterministicContactRequestBridge(this.bus);

  final ContactRequestCryptoBus bus;
  final List<Map<String, dynamic>> encryptedPlaintexts =
      <Map<String, dynamic>>[];
  var verifiedPayloadCount = 0;

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
    final payload =
        request['payload'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    switch (request['cmd']) {
      case 'payload.sign':
        final data = payload['data'] as String;
        final privateKey = payload['privateKey'] as String;
        return jsonEncode(<String, Object>{
          'ok': true,
          'signature': bus.signatureFor(privateKey, data),
        });
      case 'payload.verify':
        final publicKey = payload['publicKey'] as String;
        final data = payload['data'] as String;
        final signature = payload['signature'] as String;
        final privateKey = bus.privateKeyByPublicKey[publicKey];
        final valid =
            privateKey != null &&
            signature == bus.signatureFor(privateKey, data);
        if (valid) verifiedPayloadCount += 1;
        return jsonEncode(<String, Object>{'ok': true, 'valid': valid});
      case 'contactrequest.encrypt':
        final plaintext = payload['plaintext'] as String;
        encryptedPlaintexts.add(jsonDecode(plaintext) as Map<String, dynamic>);
        final ciphertext = bus.encrypt(plaintext);
        return jsonEncode(<String, Object>{
          'ok': true,
          'ephemeralPublicKey': 'ephemeral-$ciphertext',
          'ciphertext': ciphertext,
          'nonce': 'nonce-$ciphertext',
        });
      case 'contactrequest.decrypt':
        final ciphertext = payload['ciphertext'] as String;
        final plaintext = bus.plaintextByCiphertext[ciphertext];
        return jsonEncode(<String, Object?>{
          'ok': plaintext != null,
          'plaintext': ?plaintext,
        });
      default:
        return jsonEncode(<String, Object>{'ok': true});
    }
  }
}

/// In-memory [ReceivedCallWakeHandleStore] with the production
/// strictly-newer acceptance rule.
final class InMemoryReceivedCallWakeHandleStore
    implements ReceivedCallWakeHandleStore {
  final Map<String, CallWakeHandleGrant> _grants =
      <String, CallWakeHandleGrant>{};

  @override
  Future<CallWakeHandleGrant?> readForIssuer(
    String issuerAccountPeerId,
  ) async => _grants[issuerAccountPeerId];

  @override
  Future<bool> storeIfStrictlyNewer({
    required String issuerAccountPeerId,
    required CallWakeHandleGrant grant,
    required int nowMs,
  }) async {
    if (!grant.isValidAt(nowMs)) return false;
    final prior = _grants[issuerAccountPeerId];
    if (prior != null && !grant.isStrictlyNewerThan(prior)) return false;
    _grants[issuerAccountPeerId] = grant;
    return true;
  }

  @override
  Future<void> removeForIssuer(String issuerAccountPeerId) async {
    _grants.remove(issuerAccountPeerId);
  }

  @override
  Future<void> clear() async => _grants.clear();
}
