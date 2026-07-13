import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/push/application/push_relay_registration_proof.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('proof command is exact, hash-bound, size-bounded, and fresh', () {
    final now = DateTime.utc(2026, 7, 13, 3);
    final bytes = _commandBytes(now: now);
    final proof = parsePushRelayRegistrationProofCommand(bytes, now: now);

    expect(proof.commandId, 'tc256-relay-registration-1783911600000000-17');
    expect(proof.commandSha256, sha256.convert(bytes).toString());
    expect(proof.matchesToken('new-fcm-token'), isTrue);
    expect(proof.matchesToken('wrong-fcm-token'), isFalse);
    expect(
      () => parsePushRelayRegistrationProofCommand(
        bytes,
        now: now.add(const Duration(minutes: 6)),
      ),
      throwsFormatException,
    );
    expect(
      () => parsePushRelayRegistrationProofCommand(<int>[], now: now),
      throwsFormatException,
    );
    expect(
      () => parsePushRelayRegistrationProofCommand(
        List<int>.filled(pushRelayRegistrationProofMaxCommandBytes + 1, 1),
        now: now,
      ),
      throwsFormatException,
    );
    final extra = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>
      ..['extra'] = true;
    expect(
      () => parsePushRelayRegistrationProofCommand(
        utf8.encode(jsonEncode(extra)),
        now: now,
      ),
      throwsFormatException,
    );
  });

  test(
    'v2 current-token command binds authorization and fresh generation',
    () async {
      final now = DateTime.utc(2026, 7, 13, 4);
      final bytes = _currentTokenCommandBytes(now: now);
      Map<String, Object?>? receipt;
      final proof = parsePushRelayRegistrationProofCommand(
        bytes,
        now: now,
        clock: () => now,
        completeCommand: (value) async => receipt = value,
      );

      expect(proof.proofSchema, pushRelayRegistrationProofCommandSchemaV2);
      expect(proof.matchesToken('new-fcm-token'), isTrue);
      expect(proof.safeDetails(platform: 'android'), <String, Object?>{
        'proofSchema': pushRelayRegistrationProofCommandSchemaV2,
        'commandId': 'tc256-relay-registration-1783915200000000-18',
        'tokenSha256': _tokenHash,
        'authorizationKind':
            pushRelayRegistrationProofCurrentTokenAuthorizationKind,
        'authorizationArtifactSha256': 'b' * 64,
        'gateACommandGenerationId': 'tc256-gate-a-command-1783915200000000-19',
        'commandSha256': sha256.convert(bytes).toString(),
        'platform': 'android',
      });
      expect(proof.bindAccountIdentity('account-peer'), isTrue);
      expect(proof.bindTransportIdentity('transport-peer'), isTrue);
      expect(proof.claimRelayAttempt(), isTrue);
      await proof.complete(platform: 'android');
      expect(receipt?['schema'], pushRelayRegistrationProofReceiptSchemaV2);
      expect(receipt?['authorizationArtifactSha256'], 'b' * 64);
      expect(
        receipt?['gateACommandGenerationId'],
        'tc256-gate-a-command-1783915200000000-19',
      );
      expect(receipt?['tokenSha256'], _tokenHash);

      for (final mutate in <void Function(Map<String, dynamic>)>[
        (value) => value['authorizationKind'] = 'forced_reregistration',
        (value) => value['authorizationArtifactSha256'] = 'not-a-hash',
        (value) => value['gateACommandGenerationId'] =
            'tc256-token-refresh-1783915200000000-19',
        (value) => value['refreshArtifactSha256'] = 'c' * 64,
      ]) {
        final changed = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        mutate(changed);
        expect(
          () => parsePushRelayRegistrationProofCommand(
            utf8.encode(jsonEncode(changed)),
            now: now,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('claim expires between parse and relay without claiming', () {
    var now = DateTime.utc(2026, 7, 13, 3);
    final proof = parsePushRelayRegistrationProofCommand(
      _commandBytes(now: now, maxAgeSeconds: 30),
      now: now,
      clock: () => now,
    );
    expect(proof.bindAccountIdentity('account-peer'), isTrue);
    expect(proof.bindTransportIdentity('transport-peer'), isTrue);
    now = now.add(const Duration(seconds: 31));
    expect(proof.claimRelayAttempt(), isFalse);
  });

  test('completion is one-shot, fresh, atomic-receipt input', () async {
    var now = DateTime.utc(2026, 7, 13, 3);
    Map<String, Object?>? receipt;
    final proof = parsePushRelayRegistrationProofCommand(
      _commandBytes(now: now),
      now: now,
      clock: () => now,
      completeCommand: (value) async => receipt = value,
    );
    expect(proof.bindAccountIdentity('account-peer'), isTrue);
    expect(proof.bindTransportIdentity('transport-peer'), isTrue);
    expect(proof.claimRelayAttempt(), isTrue);
    await proof.complete(platform: 'android');
    expect(receipt, isNotNull);
    expect(receipt!['relayFrameAccepted'], isTrue);
    expect(receipt!['tokenPersisted'], isTrue);
    expect(receipt!['commandDeleted'], isTrue);
    expect(receipt!['containsSecrets'], isFalse);
    expect(receipt!['tokenSha256'], _tokenHash);
    await expectLater(proof.complete(platform: 'android'), throwsStateError);
  });

  test('completion expires after claim and does not publish receipt', () async {
    var now = DateTime.utc(2026, 7, 13, 3);
    var receiptCalls = 0;
    final proof = parsePushRelayRegistrationProofCommand(
      _commandBytes(now: now, maxAgeSeconds: 30),
      now: now,
      clock: () => now,
      completeCommand: (_) async => receiptCalls++,
    );
    expect(proof.bindAccountIdentity('account-peer'), isTrue);
    expect(proof.bindTransportIdentity('transport-peer'), isTrue);
    expect(proof.claimRelayAttempt(), isTrue);
    now = now.add(const Duration(seconds: 31));
    await expectLater(proof.complete(platform: 'android'), throwsStateError);
    expect(receiptCalls, 0);
  });

  test('default compilation keeps proof mode dormant', () {
    expect(pushRelayRegistrationProofMode, isFalse);
  });
}

final String _tokenHash = sha256
    .convert(utf8.encode('new-fcm-token'))
    .toString();

List<int> _commandBytes({required DateTime now, int maxAgeSeconds = 300}) =>
    utf8.encode(
      jsonEncode(<String, Object?>{
        'schema': pushRelayRegistrationProofCommandSchema,
        'commandId': 'tc256-relay-registration-1783911600000000-17',
        'issuedAt': now.toIso8601String(),
        'maxAgeSeconds': maxAgeSeconds,
        'tokenSha256': _tokenHash,
        'tokenGenerationId': 'tc256-token-refresh-1783910955896883-866020056',
        'refreshArtifactSha256': 'a' * 64,
      }),
    );

List<int> _currentTokenCommandBytes({required DateTime now}) => utf8.encode(
  jsonEncode(<String, Object?>{
    'schema': pushRelayRegistrationProofCommandSchemaV2,
    'commandId': 'tc256-relay-registration-1783915200000000-18',
    'issuedAt': now.toIso8601String(),
    'maxAgeSeconds': 300,
    'tokenSha256': _tokenHash,
    'authorizationKind':
        pushRelayRegistrationProofCurrentTokenAuthorizationKind,
    'authorizationArtifactSha256': 'b' * 64,
    'gateACommandGenerationId': 'tc256-gate-a-command-1783915200000000-19',
  }),
);
