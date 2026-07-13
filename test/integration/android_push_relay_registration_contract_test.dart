import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/push/application/push_relay_registration_proof.dart'
    as production;
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/reaction_notification_proof_support.dart';

void main() {
  test(
    'current-token diagnostic authorization is exact, 30m, and byte-bound',
    () {
      final capturedAt = DateTime.utc(2026, 7, 13, 3);
      final artifact = _validCurrentTokenDiagnostic(capturedAt);
      final bytes = utf8.encode(jsonEncode(artifact));
      final immutableBytes = List<int>.unmodifiable(bytes);
      final artifactSha256 = sha256.convert(immutableBytes).toString();
      final authorization =
          parseBackgroundCryptoCurrentTokenDiagnosticAuthorization(
            immutableBytes,
            now: capturedAt.add(const Duration(minutes: 30)),
          );

      expect(authorization, <String, Object?>{
        'authorizationKind': backgroundCryptoCurrentTokenAuthorizationKind,
        'authorizationArtifactSha256': artifactSha256,
        'capturedAt': capturedAt.toIso8601String(),
        'tokenSha256': _tokenHash,
        'providerOperation': 'validate_only',
        'providerValidationResult': 'accepted',
        'providerHttpStatus': 200,
        'providerRpcStatus': 'OK',
        'deliveryAttempted': false,
      });
      expect(
        revalidateBackgroundCryptoCurrentTokenDiagnosticAuthorization(
          immutableBytes,
          now: capturedAt.add(const Duration(minutes: 29)),
          expectedArtifactSha256: artifactSha256,
          expectedAuthorization: authorization,
        ),
        authorization,
      );
      expect(
        () => parseBackgroundCryptoCurrentTokenDiagnosticAuthorization(
          immutableBytes,
          now: capturedAt.add(const Duration(minutes: 30, microseconds: 1)),
        ),
        throwsFormatException,
      );
      expect(
        () => parseBackgroundCryptoCurrentTokenDiagnosticAuthorization(
          immutableBytes,
          now: capturedAt.subtract(const Duration(microseconds: 1)),
        ),
        throwsFormatException,
      );
      final mutatedBytes = List<int>.from(immutableBytes)
        ..[immutableBytes.length - 2] ^= 1;
      expect(
        () => revalidateBackgroundCryptoCurrentTokenDiagnosticAuthorization(
          mutatedBytes,
          now: capturedAt,
          expectedArtifactSha256: artifactSha256,
          expectedAuthorization: authorization,
        ),
        throwsFormatException,
      );
    },
  );

  test('current-token diagnostic rejects drift, residue, and delivery', () {
    final capturedAt = DateTime.utc(2026, 7, 13, 3);
    final artifact = _validCurrentTokenDiagnostic(capturedAt);
    final mutations = <void Function(Map<String, dynamic>)>[
      (value) => value['extra'] = true,
      (value) => value['subjectTokenSha256'] = 'not-a-sha256',
      (value) => value['providerValidationSucceeded'] = 0,
      (value) => value['deliveryAttempted'] = true,
      (value) => value['providerRequestsAttempted'] = 1,
      (value) => value['callbacksObserved'] = 1,
      (value) => (value['providerDiagnostic'] as Map)['operation'] = 'deliver',
      (value) => (value['providerDiagnostic'] as Map)['httpStatus'] = 201,
      (value) =>
          (value['providerDiagnostic'] as Map)['requestIdSha256'] = 'a' * 64,
      (value) => (value['cleanup'] as Map)['fixtureDbRowsRemaining'] = 1,
      (value) =>
          (value['cleanup'] as Map)['privateProviderTempDeleted'] = false,
      (value) => (value['cleanup'] as Map)['extra'] = true,
      (value) => (value['redaction'] as Map)['fcmTokenPersisted'] = true,
      (value) => (value['redaction'] as Map)['extra'] = false,
      (value) => (value['successfulCleanupEvidence'] as List).clear(),
      (value) =>
          ((value['successfulCleanupEvidence'] as List).single
                  as Map)['dedupeGatesScrubbed'] =
              1,
      (value) =>
          (value['successfulRestorationEvidence']
                  as Map)['installedCandidateBytesVerified'] =
              false,
      (value) =>
          (value['successfulRestorationEvidence']
              as Map)['installedCandidateApkSha256'] = <String>[
            'b' * 64,
          ],
    ];
    for (final mutate in mutations) {
      final changed = jsonDecode(jsonEncode(artifact)) as Map<String, dynamic>;
      mutate(changed);
      expect(
        () => parseBackgroundCryptoCurrentTokenDiagnosticAuthorization(
          utf8.encode(jsonEncode(changed)),
          now: capturedAt.add(const Duration(minutes: 1)),
        ),
        throwsFormatException,
      );
    }
  });

  test('accepted refresh artifact is exact, fresh, and hash-bound', () {
    final now = DateTime.utc(2026, 7, 13, 3);
    final artifact = _validRefreshArtifact(now);
    final bytes = utf8.encode(jsonEncode(artifact));
    final authorization = parseBackgroundCryptoRelayRegistrationAuthorization(
      bytes,
      now: now.add(const Duration(minutes: 1)),
    );
    expect(authorization['tokenSha256'], _tokenHash);
    expect(authorization['tokenGenerationId'], _generationId);
    expect(
      authorization['refreshArtifactSha256'],
      sha256.convert(bytes).toString(),
    );

    for (final mutation in <void Function(Map<String, dynamic>)>[
      (value) => value['deliveryAttempted'] = true,
      (value) => value['providerValidationSucceeded'] = 0,
      (value) => value['subjectTokenSha256'] = 'f' * 64,
      (value) => (value['providerDiagnostic'] as Map)['httpStatus'] = 404,
      (value) => (value['tokenRegistration'] as Map)['source'] = 'sdk_current',
      (value) => (value['tokenRegistration'] as Map)['tokenSha256'] = 'e' * 64,
      (value) => (value['cleanup'] as Map)['fixtureDbRowsRemaining'] = 1,
      (value) => value['extra'] = true,
    ]) {
      final changed = jsonDecode(jsonEncode(artifact)) as Map<String, dynamic>;
      mutation(changed);
      expect(
        () => parseBackgroundCryptoRelayRegistrationAuthorization(
          utf8.encode(jsonEncode(changed)),
          now: now.add(const Duration(minutes: 1)),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => parseBackgroundCryptoRelayRegistrationAuthorization(
        bytes,
        now: now.add(const Duration(hours: 2)),
      ),
      throwsFormatException,
    );
  });

  test('near-expiry authorization cannot survive a long build delay', () {
    final capturedAt = DateTime.utc(2026, 7, 13, 3);
    final bytes = utf8.encode(jsonEncode(_validRefreshArtifact(capturedAt)));
    final immutableBytes = List<int>.unmodifiable(bytes);
    final initial = parseBackgroundCryptoRelayRegistrationAuthorization(
      immutableBytes,
      now: capturedAt.add(const Duration(minutes: 59, seconds: 58)),
    );
    final artifactSha256 = sha256.convert(immutableBytes).toString();

    expect(
      () => revalidateBackgroundCryptoRelayRegistrationAuthorization(
        immutableBytes,
        now: capturedAt.add(const Duration(hours: 1, seconds: 3)),
        expectedArtifactSha256: artifactSha256,
        expectedAuthorization: initial,
      ),
      throwsFormatException,
    );
  });

  test('command staging requires fresh unchanged immutable authorization', () {
    final capturedAt = DateTime.utc(2026, 7, 13, 3);
    final sourceBytes = utf8.encode(
      jsonEncode(_validRefreshArtifact(capturedAt)),
    );
    final immutableBytes = List<int>.unmodifiable(sourceBytes);
    final initial = parseBackgroundCryptoRelayRegistrationAuthorization(
      immutableBytes,
      now: capturedAt.add(const Duration(minutes: 59)),
    );
    final artifactSha256 = sha256.convert(immutableBytes).toString();
    sourceBytes[0] ^= 1;

    expect(
      revalidateBackgroundCryptoRelayRegistrationAuthorization(
        immutableBytes,
        now: capturedAt.add(const Duration(minutes: 59, seconds: 30)),
        expectedArtifactSha256: artifactSha256,
        expectedAuthorization: initial,
      ),
      initial,
    );
    expect(
      () => revalidateBackgroundCryptoRelayRegistrationAuthorization(
        sourceBytes,
        now: capturedAt.add(const Duration(minutes: 59, seconds: 30)),
        expectedArtifactSha256: artifactSha256,
        expectedAuthorization: initial,
      ),
      throwsFormatException,
    );
    expect(
      () => revalidateBackgroundCryptoRelayRegistrationAuthorization(
        immutableBytes,
        now: capturedAt.add(const Duration(hours: 1, milliseconds: 1)),
        expectedArtifactSha256: artifactSha256,
        expectedAuthorization: initial,
      ),
      throwsFormatException,
    );
  });

  test('receipt acceptance rejects expired or mutated authorization', () {
    final capturedAt = DateTime.utc(2026, 7, 13, 3);
    final bytes = utf8.encode(jsonEncode(_validRefreshArtifact(capturedAt)));
    final initial = parseBackgroundCryptoRelayRegistrationAuthorization(
      bytes,
      now: capturedAt.add(const Duration(minutes: 59)),
    );
    final artifactSha256 = sha256.convert(bytes).toString();
    final mutated = List<int>.from(bytes)..[bytes.length - 2] ^= 1;

    expect(
      () => revalidateBackgroundCryptoRelayRegistrationAuthorization(
        bytes,
        now: capturedAt.add(const Duration(hours: 1, seconds: 1)),
        expectedArtifactSha256: artifactSha256,
        expectedAuthorization: initial,
      ),
      throwsFormatException,
    );
    expect(
      () => revalidateBackgroundCryptoRelayRegistrationAuthorization(
        mutated,
        now: capturedAt.add(const Duration(minutes: 59, seconds: 30)),
        expectedArtifactSha256: artifactSha256,
        expectedAuthorization: initial,
      ),
      throwsFormatException,
    );
  });

  test('private receipt is exact and bound to command and identities', () {
    final now = DateTime.utc(2026, 7, 13, 3);
    final receipt = _validReceipt(now);
    final parsed = parseBackgroundCryptoPushRelayRegistrationReceipt(
      utf8.encode(jsonEncode(receipt)),
      now: now.add(const Duration(seconds: 1)),
      commandId: _commandId,
      commandSha256: _commandHash,
      tokenSha256: _tokenHash,
      tokenGenerationId: _generationId,
      refreshArtifactSha256: _refreshArtifactHash,
    );
    expect(parsed['relayFrameAccepted'], isTrue);
    expect(parsed['tokenPersisted'], isTrue);
    expect(parsed['commandDeleted'], isTrue);

    final mutations = <String, Object?>{
      'schema': 'wrong-schema',
      'status': 'failed',
      'completedAt': now
          .subtract(const Duration(minutes: 10))
          .toIso8601String(),
      'proofSchema': 'wrong-proof-schema',
      'commandId': 'wrong-command',
      'tokenSha256': '0' * 64,
      'tokenGenerationId': 'wrong-generation',
      'refreshArtifactSha256': '0' * 64,
      'commandSha256': '0' * 64,
      'platform': 'ios',
      'accountIdentitySha256': 'B' * 64,
      'transportIdentitySha256': 'C' * 64,
      'relayFrameAccepted': false,
      'tokenPersisted': false,
      'commandDeleted': false,
      'containsSecrets': true,
    };
    for (final mutation in mutations.entries) {
      final changed = Map<String, dynamic>.from(receipt)
        ..[mutation.key] = mutation.value;
      expect(
        () => parseBackgroundCryptoPushRelayRegistrationReceipt(
          utf8.encode(jsonEncode(changed)),
          now: now,
          commandId: _commandId,
          commandSha256: _commandHash,
          tokenSha256: _tokenHash,
          tokenGenerationId: _generationId,
          refreshArtifactSha256: _refreshArtifactHash,
        ),
        throwsFormatException,
        reason: 'one-field mutation survived: ${mutation.key}',
      );
    }
    final extra = Map<String, dynamic>.from(receipt)..['extra'] = true;
    final missing = Map<String, dynamic>.from(receipt)
      ..remove('commandDeleted');
    for (final changed in <Map<String, dynamic>>[extra, missing]) {
      expect(
        () => parseBackgroundCryptoPushRelayRegistrationReceipt(
          utf8.encode(jsonEncode(changed)),
          now: now,
          commandId: _commandId,
          commandSha256: _commandHash,
          tokenSha256: _tokenHash,
          tokenGenerationId: _generationId,
          refreshArtifactSha256: _refreshArtifactHash,
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'production receipt producer round-trips through exact host parser',
    () async {
      final completedAt = DateTime.utc(2026, 7, 13, 3);
      late Map<String, Object?> produced;
      final proof = production.PushRelayRegistrationProof(
        commandId: _commandId,
        issuedAt: completedAt.subtract(const Duration(seconds: 1)),
        maxAge: const Duration(minutes: 5),
        tokenSha256: _tokenHash,
        tokenGenerationId: _generationId,
        refreshArtifactSha256: _refreshArtifactHash,
        commandSha256: _commandHash,
        completeCommand: (receipt) async => produced = receipt,
        now: () => completedAt,
      );
      expect(proof.bindAccountIdentity('account-peer'), isTrue);
      expect(proof.bindTransportIdentity('transport-peer'), isTrue);
      expect(proof.claimRelayAttempt(), isTrue);
      await proof.complete(platform: 'android');

      final parsed = parseBackgroundCryptoPushRelayRegistrationReceipt(
        utf8.encode(jsonEncode(produced)),
        now: completedAt,
        commandId: _commandId,
        commandSha256: _commandHash,
        tokenSha256: _tokenHash,
        tokenGenerationId: _generationId,
        refreshArtifactSha256: _refreshArtifactHash,
      );
      expect(parsed, produced);
    },
  );

  test(
    'v2 production receipt and ordered flow bind current token proof',
    () async {
      final now = DateTime.utc(2026, 7, 13, 4);
      final commandBytes = utf8.encode(
        jsonEncode(<String, Object?>{
          'schema': production.pushRelayRegistrationProofCommandSchemaV2,
          'commandId': _commandId,
          'issuedAt': now
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
          'maxAgeSeconds': 300,
          'tokenSha256': _tokenHash,
          'authorizationKind': production
              .pushRelayRegistrationProofCurrentTokenAuthorizationKind,
          'authorizationArtifactSha256': _currentAuthorizationArtifactHash,
          'gateACommandGenerationId': _gateACommandGenerationId,
        }),
      );
      late Map<String, Object?> produced;
      final proof = production.parsePushRelayRegistrationProofCommand(
        commandBytes,
        now: now,
        clock: () => now,
        completeCommand: (receipt) async => produced = receipt,
      );
      expect(proof.matchesToken('wrong-token'), isFalse);
      expect(proof.bindAccountIdentity('account-peer'), isTrue);
      expect(proof.bindTransportIdentity('transport-peer'), isTrue);
      expect(proof.claimRelayAttempt(), isTrue);
      await proof.complete(platform: 'android');

      expect(
        parseBackgroundCryptoPushRelayRegistrationReceiptV2(
          utf8.encode(jsonEncode(produced)),
          now: now,
          commandId: _commandId,
          commandSha256: sha256.convert(commandBytes).toString(),
          tokenSha256: _tokenHash,
          authorizationArtifactSha256: _currentAuthorizationArtifactHash,
          gateACommandGenerationId: _gateACommandGenerationId,
        ),
        produced,
      );
      final flow = backgroundCryptoPushRelayProofEvidenceFromLogV2(
        _validFlowLogV2(commandSha256: _commandHash),
        commandId: _commandId,
        commandSha256: _commandHash,
        tokenSha256: _tokenHash,
        authorizationArtifactSha256: _currentAuthorizationArtifactHash,
        gateACommandGenerationId: _gateACommandGenerationId,
      );
      expect(flow['accountIdentitySha256'], _accountHash);
      expect(flow['transportIdentitySha256'], _transportHash);
      expect(flow['relayFrameAccepted'], isTrue);
      expect(flow['tokenPersisted'], isTrue);

      expect(
        () => backgroundCryptoPushRelayProofEvidenceFromLogV2(
          _validFlowLogV2(
            commandSha256: _commandHash,
          ).replaceAll(_currentAuthorizationArtifactHash, 'f' * 64),
          commandId: _commandId,
          commandSha256: _commandHash,
          tokenSha256: _tokenHash,
          authorizationArtifactSha256: _currentAuthorizationArtifactHash,
          gateACommandGenerationId: _gateACommandGenerationId,
        ),
        throwsFormatException,
      );
      expect(
        () => backgroundCryptoPushRelayProofEvidenceFromLogV2(
          _validFlowLogV2(
            commandSha256: _commandHash,
          ).replaceFirst(_accountHash, 'f' * 64),
          commandId: _commandId,
          commandSha256: _commandHash,
          tokenSha256: _tokenHash,
          authorizationArtifactSha256: _currentAuthorizationArtifactHash,
          gateACommandGenerationId: _gateACommandGenerationId,
        ),
        throwsFormatException,
      );
    },
  );

  test('private receipt tolerates bounded device-to-host clock skew', () {
    final completedAt = DateTime.utc(2026, 7, 13, 3);
    final receipt = _validReceipt(completedAt);

    expect(
      parseBackgroundCryptoPushRelayRegistrationReceipt(
        utf8.encode(jsonEncode(receipt)),
        now: completedAt.subtract(const Duration(seconds: 2)),
        commandId: _commandId,
        commandSha256: _commandHash,
        tokenSha256: _tokenHash,
        tokenGenerationId: _generationId,
        refreshArtifactSha256: _refreshArtifactHash,
      ),
      containsPair('status', 'completed'),
    );
    expect(
      () => parseBackgroundCryptoPushRelayRegistrationReceipt(
        utf8.encode(jsonEncode(receipt)),
        now: completedAt.subtract(const Duration(seconds: 6)),
        commandId: _commandId,
        commandSha256: _commandHash,
        tokenSha256: _tokenHash,
        tokenGenerationId: _generationId,
        refreshArtifactSha256: _refreshArtifactHash,
      ),
      throwsFormatException,
    );
  });

  test('flow proof requires one exact ordered bound success sequence', () {
    final log = _validFlowLog();
    final evidence = backgroundCryptoPushRelayProofEvidenceFromLog(
      log,
      commandId: _commandId,
      commandSha256: _commandHash,
      tokenSha256: _tokenHash,
      tokenGenerationId: _generationId,
      refreshArtifactSha256: _refreshArtifactHash,
    );
    expect(evidence['relayFrameAccepted'], isTrue);
    expect(evidence['coordinatorSuccess'], isTrue);
    expect(evidence['orderedEventCount'], 13);

    final earlierAutomaticAttempt = <String>[
      _flowLine('P2P_SERVICE_REGISTER_PUSH_TOKEN_BEGIN', <String, Object?>{
        'platform': 'android',
      }),
      _flowLine('P2P_INBOX_REGISTER_TOKEN_REQUEST', <String, Object?>{
        'platform': 'android',
      }),
      _flowLine('P2P_INBOX_REGISTER_TOKEN_RESPONSE', const <String, Object?>{
        'ok': true,
      }),
      _flowLine('P2P_SERVICE_REGISTER_PUSH_TOKEN_SUCCESS', <String, Object?>{
        'platform': 'android',
      }),
      log,
    ].join('\n');
    final evidenceWithEarlierAttempt =
        backgroundCryptoPushRelayProofEvidenceFromLog(
          earlierAutomaticAttempt,
          commandId: _commandId,
          commandSha256: _commandHash,
          tokenSha256: _tokenHash,
          tokenGenerationId: _generationId,
          refreshArtifactSha256: _refreshArtifactHash,
        );
    expect(evidenceWithEarlierAttempt['relayFrameAccepted'], isTrue);

    final duplicate =
        '$log\n${_flowLine('PUSH_REGISTER_RELAY_PROOF_COMPLETE', _boundDetails(<String, Object?>{'relayFrameAccepted': true, 'tokenPersisted': true, 'commandDeleted': true}))}';
    expect(
      () => backgroundCryptoPushRelayProofEvidenceFromLog(
        duplicate,
        commandId: _commandId,
        commandSha256: _commandHash,
        tokenSha256: _tokenHash,
        tokenGenerationId: _generationId,
        refreshArtifactSha256: _refreshArtifactHash,
      ),
      throwsFormatException,
    );
    final reordered = log.replaceFirst(
      'PUSH_REGISTER_TOKEN_PERSISTED',
      'PUSH_REGISTER_COORDINATOR_SUCCESS',
    );
    expect(
      () => backgroundCryptoPushRelayProofEvidenceFromLog(
        reordered,
        commandId: _commandId,
        commandSha256: _commandHash,
        tokenSha256: _tokenHash,
        tokenGenerationId: _generationId,
        refreshArtifactSha256: _refreshArtifactHash,
      ),
      throwsFormatException,
    );
  });

  test('harness dry-run is provider, relay, device, and secret free', () async {
    final result = await Process.run('dart', <String>[
      'run',
      'integration_test/scripts/capture_android_push_relay_registration.dart',
      '--dry-run',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final raw = result.stdout.toString();
    final manifest =
        jsonDecode(raw.substring(raw.indexOf('{'))) as Map<String, dynamic>;
    expect(
      manifest['schema'],
      backgroundCryptoPushRelayRegistrationArtifactSchema,
    );
    expect(manifest['productionMain'], isTrue);
    expect(manifest['e2eTestMode'], isFalse);
    expect(manifest['contactsDevice'], isFalse);
    expect(manifest['contactsRelay'], isFalse);
    expect(manifest['containsSecrets'], isFalse);
  });

  test('source pins dormant production path and checked restoration', () {
    final harness = File(
      'integration_test/scripts/capture_android_push_relay_registration.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final proof = File(
      'lib/features/push/application/push_relay_registration_proof.dart',
    ).readAsStringSync();
    final register = File(
      'lib/features/push/application/register_push_token_use_case.dart',
    ).readAsStringSync();
    final diagnostics = File(
      'lib/core/utils/push_diagnostics_logger.dart',
    ).readAsStringSync();

    expect(
      harness.indexOf('parseBackgroundCryptoRelayRegistrationAuthorization('),
      lessThan(harness.indexOf('await campaign.run()')),
    );
    final build = harness.indexOf("stage = 'build';");
    final beforeCommand = harness.indexOf(
      "_revalidateAuthorization('authorization_before_command_staging')",
    );
    final stageCommand = harness.indexOf('await _stageProofCommand()');
    final receiptRead = harness.indexOf('final receipt = await _runAs');
    final beforeReceipt = harness.indexOf(
      "_revalidateAuthorization('authorization_before_receipt')",
    );
    final receiptParse = harness.indexOf(
      'parseBackgroundCryptoPushRelayRegistrationReceipt(',
    );
    final beforePass = harness.indexOf(
      "_revalidateAuthorization('authorization_before_pass')",
    );
    final restoreCall = harness.indexOf(
      'await _restoreExactHostAndCandidateState();',
    );
    final writePass = harness.indexOf('await _writePassArtifact()');
    expect(build, greaterThan(0));
    expect(beforeCommand, greaterThan(build));
    expect(stageCommand, greaterThan(beforeCommand));
    expect(receiptRead, greaterThan(stageCommand));
    expect(beforeReceipt, greaterThan(receiptRead));
    expect(receiptParse, greaterThan(beforeReceipt));
    expect(beforePass, greaterThan(restoreCall));
    expect(writePass, greaterThan(beforePass));
    expect(harness, contains('List<int>.unmodifiable('));
    expect(
      harness,
      isNot(contains('stage = checkStage;')),
      reason:
          'authorization revalidation must not relabel later receipt failures',
    );
    for (final reason in const <String>[
      'receipt_size_rejected',
      'receipt_json_rejected',
      'receipt_root_rejected',
      'receipt_contract_rejected',
      'receipt_time_rejected',
      'receipt_format_rejected',
    ]) {
      expect(harness, contains(reason));
    }
    expect(harness, contains("'proofMilestones': <String, Object?>{"));
    expect(harness, contains("'privateReceiptSha256': _privateReceiptSha256"));
    expect(harness, contains("'--target',\n      'lib/main.dart'"));
    expect(
      harness,
      contains("'--dart-define=MKNOON_PUSH_RELAY_REGISTRATION_PROOF=true'"),
    );
    expect(harness, isNot(contains('MKNOON_E2E_TEST')));
    expect(harness, contains("'chmod',\n      '0600'"));
    expect(harness, contains("['test', '!', '-e', path]"));
    expect(harness, contains('_restoreExactHostAndCandidateState()'));
    expect(harness, contains('_forceStopAndRequireAbsent()'));
    expect(main, contains('await loadPushRelayRegistrationProof()'));
    expect(
      main,
      contains('relayRegistrationProof: pushRelayRegistrationProof'),
    );
    expect(proof, contains('pushRelayRegistrationProofMode'));
    expect(proof, contains('pushRelayRegistrationProofMaxCommandBytes'));
    expect(proof, contains('claimRelayAttempt()'));
    expect(
      harness,
      contains('parseBackgroundCryptoCurrentTokenDiagnosticAuthorization('),
    );
    expect(
      harness,
      contains("'tc256-gate-a-command-${r'${now.microsecondsSinceEpoch}'}-'"),
    );
    expect(
      harness,
      contains('backgroundCryptoPushRelayProofEvidenceFromLogV2('),
    );
    expect(
      harness,
      contains('parseBackgroundCryptoPushRelayRegistrationReceiptV2('),
    );
    expect(register, contains('PUSH_REGISTER_RELAY_PROOF_TOKEN_MISMATCH'));
    expect(
      register,
      contains('PUSH_REGISTER_RELAY_PROOF_RELAY_FRAME_ACCEPTED'),
    );
    final match = register.indexOf(
      'relayRegistrationProof.matchesToken(token)',
    );
    final relay = register.indexOf('p2pService.registerPushToken(');
    expect(match, greaterThan(0));
    expect(relay, greaterThan(match));
    expect(diagnostics, contains('sha256.convert(utf8.encode(token))'));
    expect(diagnostics, isNot(contains('token.substring')));
  });

  test('proof command is the only additional stageable private path', () {
    expect(
      isBackgroundCryptoOwnedAppPrivateCommandPath(
        backgroundCryptoAppPrivatePushRelayCommandPath,
      ),
      isTrue,
    );
    expect(
      isBackgroundCryptoOwnedAppPrivateCommandPath(
        backgroundCryptoAppPrivatePushRelayReceiptPath,
      ),
      isFalse,
    );
    expect(
      isBackgroundCryptoOwnedAppPrivateCommandPath(
        '$backgroundCryptoAppPrivatePushRelayCommandPath/extra',
      ),
      isFalse,
    );
  });
}

const String _commandId = 'tc256-relay-registration-1783911600000000-17';
const String _generationId = 'tc256-token-refresh-1783910955896883-866020056';
const String _tokenHash =
    'be1b968991eedb01d02612fbdd68ccc4d88e1f5ee1df3758545d68dbd9804774';
const String _priorTokenHash =
    'b3863f9250040c453e8047f293af4fd6d446f9a56acb7b58f5a5fb59a4c9f2fe';
const String _refreshArtifactHash =
    '5cded66afd1a3aeaad900895ebf494a54d0d3ab39ef5a0074e9e1a2ffba19570';
const String _currentAuthorizationArtifactHash =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
const String _gateACommandGenerationId =
    'tc256-gate-a-command-1783915200000000-19';
const String _commandHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _accountHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _transportHash =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

Map<String, dynamic> _validCurrentTokenDiagnostic(DateTime capturedAt) {
  final installedHashes = <String>['9' * 64];
  return <String, dynamic>{
    'testCase': 'TC-07-provider-diagnostic',
    'scenario': 'android_provider_validate_only',
    'schema': backgroundCryptoProviderDiagnosticArtifactSchema,
    'status': 'completed',
    'capturedAt': capturedAt.toIso8601String(),
    'mode': 'provider-diagnostic-only',
    'setupReady': true,
    'fixtureCaseId': 'direct-text',
    'providerValidationAttempts': 1,
    'providerValidationSucceeded': 1,
    'providerDiagnostic': <String, Object?>{
      'schema': backgroundCryptoProviderResultSchema,
      'ok': true,
      'stage': 'fcm',
      'operation': 'validate_only',
      'validateOnly': true,
      'validationResult': 'accepted',
      'httpClass': '2xx',
      'httpStatus': 200,
      'rpcStatus': 'OK',
      'reason': null,
      'requestIdSha256': null,
    },
    'subjectTokenSha256': _tokenHash,
    'deliveryAttempted': false,
    'providerRequestsAttempted': 0,
    'providerRequestsSucceeded': 0,
    'reactionCasesExecuted': 0,
    'ordinaryCasesExecuted': 0,
    'negativeCasesExecuted': 0,
    'callbacksObserved': 0,
    'notificationCardsObserved': 0,
    'successfulCleanupEvidence': <Object?>[
      <String, Object?>{
        'mode': 'recovery',
        'commandId': 'tc256-1783911600000000-17',
        'commandSha256': '8' * 64,
        'commandByteLength': 110,
        'receiptsMatched': true,
        'mainReexecuted': true,
        'reservedOnly': true,
        'privateProviderBundleDeleted': true,
        'cleanupIndexDeleted': true,
        'fcmRefreshCommandDeleted': true,
        'clearNotificationsMarkerDeleted': true,
        'boundedReactionClaimsVerified': true,
        'dedupeGatesRestored': 2,
        'dedupeGatesScrubbed': 2,
        for (final field in backgroundCryptoCleanupZeroCountFields) field: 0,
      },
    ],
    'cleanup': <String, Object?>{
      for (final field in backgroundCryptoCleanupZeroCountFields) field: 0,
      'privateProviderBundleDeleted': true,
      'cleanupIndexDeleted': true,
      'fcmRefreshCommandDeleted': true,
      'clearNotificationsMarkerDeleted': true,
      'privateProviderTempDeleted': true,
      'boundedReactionClaimsVerified': true,
      'bothRecentGatesScrubbed': true,
      'notificationPermissionRestored': true,
      'installedCandidateRestored': true,
      'installedCandidateBytesVerified': true,
      'installedCandidateApkSha256': installedHashes,
      'localBuildArtifactRestoredToPriorState': true,
      'localBuildArtifactBytesVerified': true,
      'notificationPermissionInitiallyGranted': true,
    },
    'redaction': <String, Object?>{
      'providerMessagePersisted': false,
      'fcmTokenPersisted': false,
      'credentialPersisted': false,
      'jwtPersisted': false,
      'providerUrlPersisted': false,
      'payloadPersisted': false,
      'rawHeaderPersisted': false,
    },
    'containsSecrets': false,
    'privateProviderTempDeleted': true,
    'successfulRestorationEvidence': <String, Object?>{
      'installedCandidateRestored': true,
      'installedCandidateBytesVerified': true,
      'installedCandidateApkSha256': installedHashes,
      'localBuildArtifactRestoredToPriorState': true,
      'localBuildArtifactBytesVerified': true,
      'notificationPermissionRestored': true,
      'notificationPermissionInitiallyGranted': true,
    },
  };
}

Map<String, dynamic> _validRefreshArtifact(DateTime now) => <String, dynamic>{
  'testCase': 'TC-07-provider-diagnostic',
  'scenario': 'android_provider_validate_only',
  'schema': backgroundCryptoProviderDiagnosticArtifactSchema,
  'status': 'completed',
  'capturedAt': now.toIso8601String(),
  'mode': 'provider-diagnostic-only',
  'setupReady': true,
  'fixtureCaseId': 'direct-text',
  'providerValidationAttempts': 1,
  'providerValidationSucceeded': 1,
  'providerDiagnostic': <String, Object?>{
    'schema': backgroundCryptoProviderResultSchema,
    'ok': true,
    'stage': 'fcm',
    'operation': 'validate_only',
    'validateOnly': true,
    'validationResult': 'accepted',
    'httpClass': '2xx',
    'httpStatus': 200,
    'rpcStatus': 'OK',
    'reason': null,
    'requestIdSha256': null,
  },
  'subjectTokenSha256': _tokenHash,
  'tokenRegistration': <String, Object?>{
    'schema': backgroundCryptoFcmTokenObservationSchema,
    'source': 'forced_reregistration',
    'observedAt': now.toIso8601String(),
    'generationId': _generationId,
    'tokenSha256': _tokenHash,
    'priorTokenSha256': _priorTokenHash,
    'refreshSignal': 'poll',
    'commandIssuedAt': now
        .subtract(const Duration(milliseconds: 5279))
        .toIso8601String(),
    'commandAgeAtObservationMs': 5279,
    'priorDiagnosticSha256': 'd' * 64,
  },
  'deliveryAttempted': false,
  'providerRequestsAttempted': 0,
  'providerRequestsSucceeded': 0,
  'reactionCasesExecuted': 0,
  'ordinaryCasesExecuted': 0,
  'negativeCasesExecuted': 0,
  'callbacksObserved': 0,
  'notificationCardsObserved': 0,
  'successfulCleanupEvidence': <Object?>[],
  'cleanup': <String, Object?>{
    for (final field in backgroundCryptoCleanupZeroCountFields) field: 0,
    'privateProviderBundleDeleted': true,
    'cleanupIndexDeleted': true,
    'fcmRefreshCommandDeleted': true,
    'clearNotificationsMarkerDeleted': true,
    'privateProviderTempDeleted': true,
    'boundedReactionClaimsVerified': true,
    'bothRecentGatesScrubbed': true,
    'notificationPermissionRestored': true,
    'installedCandidateRestored': true,
    'installedCandidateBytesVerified': true,
    'localBuildArtifactRestoredToPriorState': true,
    'localBuildArtifactBytesVerified': true,
  },
  'redaction': <String, Object?>{
    'providerMessagePersisted': false,
    'fcmTokenPersisted': false,
    'credentialPersisted': false,
    'jwtPersisted': false,
    'providerUrlPersisted': false,
    'payloadPersisted': false,
    'rawHeaderPersisted': false,
  },
  'containsSecrets': false,
  'privateProviderTempDeleted': true,
  'successfulRestorationEvidence': <String, Object?>{},
};

Map<String, dynamic> _validReceipt(DateTime now) => <String, dynamic>{
  'schema': backgroundCryptoPushRelayRegistrationReceiptSchema,
  'status': 'completed',
  'completedAt': now.toIso8601String(),
  'proofSchema': backgroundCryptoPushRelayRegistrationCommandSchema,
  'commandId': _commandId,
  'tokenSha256': _tokenHash,
  'tokenGenerationId': _generationId,
  'refreshArtifactSha256': _refreshArtifactHash,
  'commandSha256': _commandHash,
  'platform': 'android',
  'accountIdentitySha256': _accountHash,
  'transportIdentitySha256': _transportHash,
  'relayFrameAccepted': true,
  'tokenPersisted': true,
  'commandDeleted': true,
  'containsSecrets': false,
};

Map<String, Object?> _baseProofDetails() => <String, Object?>{
  'proofSchema': backgroundCryptoPushRelayRegistrationCommandSchema,
  'commandId': _commandId,
  'tokenSha256': _tokenHash,
  'tokenGenerationId': _generationId,
  'refreshArtifactSha256': _refreshArtifactHash,
  'commandSha256': _commandHash,
  'platform': 'android',
};

Map<String, Object?> _boundDetails([Map<String, Object?> extra = const {}]) =>
    <String, Object?>{
      ..._baseProofDetails(),
      'accountIdentitySha256': _accountHash,
      'transportIdentitySha256': _transportHash,
      ...extra,
    };

String _flowLine(String event, Map<String, Object?> details) =>
    '[FLOW] ${jsonEncode(<String, Object?>{'ts': '2026-07-13T03:00:00.000Z', 'milestone': 'M1_IDENTITY_INIT', 'layer': 'FL', 'event': event, 'details': details})}';

String _validFlowLog() => <String>[
  _flowLine('PUSH_REGISTER_RELAY_PROOF_ARMED', _baseProofDetails()),
  _flowLine('PUSH_REGISTER_COORDINATOR_ATTEMPT', <String, Object?>{
    'trigger': 'startup',
  }),
  _flowLine('PUSH_REGISTER_TOKEN_BEGIN', const <String, Object?>{}),
  _flowLine('PUSH_REGISTER_RELAY_PROOF_TOKEN_MATCHED', _boundDetails()),
  _flowLine('P2P_SERVICE_REGISTER_PUSH_TOKEN_BEGIN', <String, Object?>{
    'platform': 'android',
  }),
  _flowLine('P2P_INBOX_REGISTER_TOKEN_REQUEST', <String, Object?>{
    'platform': 'android',
  }),
  _flowLine('P2P_INBOX_REGISTER_TOKEN_RESPONSE', const <String, Object?>{
    'ok': true,
  }),
  _flowLine('P2P_SERVICE_REGISTER_PUSH_TOKEN_SUCCESS', <String, Object?>{
    'platform': 'android',
  }),
  _flowLine('PUSH_REGISTER_TOKEN_SUCCESS', <String, Object?>{
    'platform': 'android',
  }),
  _flowLine(
    'PUSH_REGISTER_RELAY_PROOF_RELAY_FRAME_ACCEPTED',
    _boundDetails(<String, Object?>{'relayFrameAccepted': true}),
  ),
  _flowLine('PUSH_REGISTER_TOKEN_PERSISTED', <String, Object?>{
    'platform': 'android',
  }),
  _flowLine(
    'PUSH_REGISTER_RELAY_PROOF_COMPLETE',
    _boundDetails(<String, Object?>{
      'relayFrameAccepted': true,
      'tokenPersisted': true,
      'commandDeleted': true,
    }),
  ),
  _flowLine('PUSH_REGISTER_COORDINATOR_SUCCESS', <String, Object?>{
    'trigger': 'startup',
    ..._boundDetails(),
  }),
].join('\n');

Map<String, Object?> _baseProofDetailsV2({required String commandSha256}) =>
    <String, Object?>{
      'proofSchema': backgroundCryptoPushRelayRegistrationCommandSchemaV2,
      'commandId': _commandId,
      'tokenSha256': _tokenHash,
      'authorizationKind': backgroundCryptoCurrentTokenAuthorizationKind,
      'authorizationArtifactSha256': _currentAuthorizationArtifactHash,
      'gateACommandGenerationId': _gateACommandGenerationId,
      'commandSha256': commandSha256,
      'platform': 'android',
    };

Map<String, Object?> _boundDetailsV2({
  required String commandSha256,
  Map<String, Object?> extra = const <String, Object?>{},
}) => <String, Object?>{
  ..._baseProofDetailsV2(commandSha256: commandSha256),
  'accountIdentitySha256': _accountHash,
  'transportIdentitySha256': _transportHash,
  ...extra,
};

String _validFlowLogV2({required String commandSha256}) => <String>[
  _flowLine(
    'PUSH_REGISTER_RELAY_PROOF_ARMED',
    _baseProofDetailsV2(commandSha256: commandSha256),
  ),
  _flowLine('PUSH_REGISTER_COORDINATOR_ATTEMPT', <String, Object?>{
    'trigger': 'startup',
  }),
  _flowLine('PUSH_REGISTER_TOKEN_BEGIN', const <String, Object?>{}),
  _flowLine(
    'PUSH_REGISTER_RELAY_PROOF_TOKEN_MATCHED',
    _boundDetailsV2(commandSha256: commandSha256),
  ),
  _flowLine('P2P_SERVICE_REGISTER_PUSH_TOKEN_BEGIN', <String, Object?>{
    'platform': 'android',
  }),
  _flowLine('P2P_INBOX_REGISTER_TOKEN_REQUEST', <String, Object?>{
    'platform': 'android',
  }),
  _flowLine('P2P_INBOX_REGISTER_TOKEN_RESPONSE', const <String, Object?>{
    'ok': true,
  }),
  _flowLine('P2P_SERVICE_REGISTER_PUSH_TOKEN_SUCCESS', <String, Object?>{
    'platform': 'android',
  }),
  _flowLine('PUSH_REGISTER_TOKEN_SUCCESS', <String, Object?>{
    'platform': 'android',
  }),
  _flowLine(
    'PUSH_REGISTER_RELAY_PROOF_RELAY_FRAME_ACCEPTED',
    _boundDetailsV2(
      commandSha256: commandSha256,
      extra: const <String, Object?>{'relayFrameAccepted': true},
    ),
  ),
  _flowLine('PUSH_REGISTER_TOKEN_PERSISTED', <String, Object?>{
    'platform': 'android',
  }),
  _flowLine(
    'PUSH_REGISTER_RELAY_PROOF_COMPLETE',
    _boundDetailsV2(
      commandSha256: commandSha256,
      extra: const <String, Object?>{
        'relayFrameAccepted': true,
        'tokenPersisted': true,
        'commandDeleted': true,
      },
    ),
  ),
  _flowLine('PUSH_REGISTER_COORDINATOR_SUCCESS', <String, Object?>{
    'trigger': 'startup',
    ..._boundDetailsV2(commandSha256: commandSha256),
  }),
].join('\n');
