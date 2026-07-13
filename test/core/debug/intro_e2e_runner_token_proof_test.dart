import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/intro_e2e_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 13, 3, 30);
  const token = 'safe-test-firebase-token';
  final tokenSha256 = sha256.convert(utf8.encode(token)).toString();

  List<int> commandBytes({
    DateTime? issuedAt,
    Map<String, Object?> extras = const <String, Object?>{},
  }) => utf8.encode(
    jsonEncode(<String, Object?>{
      'schema': directTextRelayTokenProofCommandSchema,
      'commandId': 'direct-text-relay-1783913400000000-12345',
      'issuedAt': (issuedAt ?? now).toIso8601String(),
      'maxAgeSeconds': 300,
      'tokenSha256': tokenSha256,
      'tokenGenerationId': 'tc256-token-refresh-1783913400000000-67890',
      'refreshArtifactSha256': 'a' * 64,
      'gateAArtifactSha256': 'b' * 64,
      'accountIdentitySha256': 'c' * 64,
      'transportIdentitySha256': 'c' * 64,
      ...extras,
    }),
  );

  List<int> commandBytesV2({
    DateTime? issuedAt,
    Map<String, Object?> extras = const <String, Object?>{},
  }) => utf8.encode(
    jsonEncode(<String, Object?>{
      'schema': directTextRelayTokenProofCommandSchemaV2,
      'commandId': 'direct-text-relay-1783913400000000-54321',
      'issuedAt': (issuedAt ?? now).toIso8601String(),
      'maxAgeSeconds': 300,
      'tokenSha256': tokenSha256,
      'authorizationKind':
          directTextRelayTokenProofCurrentTokenAuthorizationKind,
      'authorizationArtifactSha256': 'd' * 64,
      'gateACommandGenerationId': 'tc256-gate-a-command-1783913400000000-98765',
      'gateAArtifactSha256': 'e' * 64,
      'accountIdentitySha256': 'f' * 64,
      'transportIdentitySha256': 'f' * 64,
      ...extras,
    }),
  );

  test('direct-text token command is exact, fresh, and byte-bound', () {
    final bytes = commandBytes();
    final command = parseDirectTextRelayTokenProofCommand(bytes, now: now);

    expect(command.tokenSha256, tokenSha256);
    expect(command.commandSha256, sha256.convert(bytes).toString());
    expect(command.maxAge, const Duration(minutes: 5));
  });

  test('direct-text token command rejects extras, staleness, and oversize', () {
    expect(
      () => parseDirectTextRelayTokenProofCommand(
        commandBytes(extras: const <String, Object?>{'rawToken': 'secret'}),
        now: now,
      ),
      throwsFormatException,
    );
    expect(
      () => parseDirectTextRelayTokenProofCommand(
        commandBytes(issuedAt: now.subtract(const Duration(minutes: 6))),
        now: now,
      ),
      throwsFormatException,
    );
    expect(
      () => parseDirectTextRelayTokenProofCommand(
        List<int>.filled(directTextRelayTokenProofMaxCommandBytes + 1, 0x20),
        now: now,
      ),
      throwsFormatException,
    );
  });

  test(
    'v2 current-token command and receipt bind authorization and generation',
    () async {
      final bytes = commandBytesV2();
      final command = parseDirectTextRelayTokenProofCommand(bytes, now: now);
      expect(command.proofSchema, directTextRelayTokenProofCommandSchemaV2);
      expect(
        command.authorizationKind,
        directTextRelayTokenProofCurrentTokenAuthorizationKind,
      );
      expect(
        command.authorizationGenerationId,
        'tc256-gate-a-command-1783913400000000-98765',
      );
      expect(command.authorizationArtifactSha256, 'd' * 64);

      final receipt = await evaluateDirectTextRelayTokenProof(
        command: command,
        getToken: () async => token,
        now: now,
      );
      expect(
        receipt,
        containsPair('schema', directTextRelayTokenProofReceiptSchemaV2),
      );
      expect(
        receipt,
        containsPair(
          'authorizationKind',
          directTextRelayTokenProofCurrentTokenAuthorizationKind,
        ),
      );
      expect(receipt, containsPair('authorizationArtifactSha256', 'd' * 64));
      expect(
        receipt,
        containsPair(
          'gateACommandGenerationId',
          'tc256-gate-a-command-1783913400000000-98765',
        ),
      );
      expect(receipt, isNot(contains('refreshArtifactSha256')));
      expect(receipt, isNot(contains('tokenGenerationId')));

      for (final mutation in <Map<String, Object?>>[
        const <String, Object?>{'authorizationKind': 'forced_reregistration'},
        <String, Object?>{'authorizationArtifactSha256': 'not-a-hash'},
        const <String, Object?>{
          'gateACommandGenerationId':
              'tc256-token-refresh-1783913400000000-98765',
        },
        <String, Object?>{'refreshArtifactSha256': 'a' * 64},
      ]) {
        expect(
          () => parseDirectTextRelayTokenProofCommand(
            commandBytesV2(extras: mutation),
            now: now,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('current Firebase token evaluator emits hashes only', () async {
    final command = parseDirectTextRelayTokenProofCommand(
      commandBytes(),
      now: now,
    );
    final receipt = await evaluateDirectTextRelayTokenProof(
      command: command,
      getToken: () async => token,
      now: now,
    );

    expect(receipt['status'], 'completed');
    expect(receipt['tokenSha256'], tokenSha256);
    expect(receipt['containsSecrets'], isFalse);
    expect(jsonEncode(receipt), isNot(contains(token)));
    await expectLater(
      evaluateDirectTextRelayTokenProof(
        command: command,
        getToken: () async => 'different-token',
        now: now,
      ),
      throwsStateError,
    );
  });

  test('private command is deleted before atomic completed receipt', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mknoon-direct-token-proof-test-',
    );
    addTearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });
    final command = File('${directory.path}/intro_e2e_config.json')
      ..writeAsBytesSync(commandBytes());

    final handled = await runDirectTextRelayTokenProofIfPresent(
      getToken: () async => token,
      now: () => now,
      getDocumentsDirectory: () async => directory,
      proofModeOverride: true,
    );

    expect(handled, isTrue);
    expect(command.existsSync(), isFalse);
    expect(
      File('${directory.path}/intro_e2e_result.json.tmp').existsSync(),
      isFalse,
    );
    final receipt =
        jsonDecode(
              File(
                '${directory.path}/intro_e2e_result.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(receipt['status'], 'completed');
    expect(receipt['commandDeleted'], isTrue);
    expect(receipt['containsSecrets'], isFalse);
    expect(jsonEncode(receipt), isNot(contains(token)));
  });

  test('private v2 command emits only the exact v2 receipt fields', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mknoon-direct-token-proof-v2-test-',
    );
    addTearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });
    File(
      '${directory.path}/intro_e2e_config.json',
    ).writeAsBytesSync(commandBytesV2());

    expect(
      await runDirectTextRelayTokenProofIfPresent(
        getToken: () async => token,
        now: () => now,
        getDocumentsDirectory: () async => directory,
        proofModeOverride: true,
      ),
      isTrue,
    );

    final receipt =
        jsonDecode(
              File(
                '${directory.path}/intro_e2e_result.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(receipt['schema'], directTextRelayTokenProofReceiptSchemaV2);
    expect(
      receipt['authorizationKind'],
      directTextRelayTokenProofCurrentTokenAuthorizationKind,
    );
    expect(receipt, isNot(contains('refreshArtifactSha256')));
    expect(receipt, isNot(contains('tokenGenerationId')));
    expect(receipt['commandDeleted'], isTrue);
  });

  test(
    'token mismatch deletes command and leaves finite failed receipt',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mknoon-direct-token-proof-mismatch-',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      final command = File('${directory.path}/intro_e2e_config.json')
        ..writeAsBytesSync(commandBytes());

      expect(
        await runDirectTextRelayTokenProofIfPresent(
          getToken: () async => 'wrong-token',
          now: () => now,
          getDocumentsDirectory: () async => directory,
          proofModeOverride: true,
        ),
        isTrue,
      );

      expect(command.existsSync(), isFalse);
      final raw = File(
        '${directory.path}/intro_e2e_result.json',
      ).readAsStringSync();
      final receipt = jsonDecode(raw) as Map<String, dynamic>;
      expect(receipt['status'], 'failed');
      expect(receipt['reason'], 'token_hash_mismatch_or_unavailable');
      expect(receipt['containsSecrets'], isFalse);
      expect(raw, isNot(contains('wrong-token')));
    },
  );
}
