import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/reaction_notification_proof_support.dart';

void main() {
  final capturedAt = DateTime.utc(2026, 7, 13, 3, 33, 30);

  (List<int>, String) encode(Map<String, Object?> artifact) {
    final bytes = utf8.encode(jsonEncode(artifact));
    return (bytes, sha256.convert(bytes).toString());
  }

  Map<String, Object?> clone(Map<String, Object?> source) =>
      (jsonDecode(jsonEncode(source)) as Map).cast<String, Object?>();

  test('accepts exact fresh Gate A PASS and extracts only safe bindings', () {
    final artifact = _validGateAArtifact(capturedAt);
    final (bytes, hash) = encode(artifact);
    final authorization = parseDirectTextGateAAuthorization(
      bytes,
      now: capturedAt.add(const Duration(minutes: 10)),
      expectedArtifactSha256: hash,
    );

    expect(authorization['gateAArtifactSha256'], hash);
    expect(authorization['tokenSha256'], _tokenHash);
    expect(authorization['originalRefreshArtifactSha256'], _refreshHash);
    expect(authorization['accountIdentitySha256'], _identityHash);
    expect(authorization['transportIdentitySha256'], _identityHash);
    expect(authorization['downstreamDeliveryStillRequired'], isTrue);
    expect(jsonEncode(authorization), isNot(contains('emulator-5554')));
  });

  test('rejects stale and externally mutated Gate A bytes', () {
    final artifact = _validGateAArtifact(capturedAt);
    final (bytes, hash) = encode(artifact);
    expect(
      () => parseDirectTextGateAAuthorization(
        bytes,
        now: capturedAt.add(const Duration(hours: 1, seconds: 1)),
        expectedArtifactSha256: hash,
      ),
      throwsFormatException,
    );

    final mutated = clone(artifact)..['status'] = 'failed';
    final (mutatedBytes, _) = encode(mutated);
    expect(
      () => parseDirectTextGateAAuthorization(
        mutatedBytes,
        now: capturedAt,
        expectedArtifactSha256: hash,
      ),
      throwsFormatException,
    );

    final staleWrapper = clone(artifact);
    final refresh = (staleWrapper['refreshAuthorization']! as Map)
        .cast<String, Object?>();
    refresh['capturedAt'] = capturedAt
        .subtract(const Duration(hours: 1, seconds: 1))
        .toIso8601String();
    final (staleWrapperBytes, staleWrapperHash) = encode(staleWrapper);
    expect(
      () => parseDirectTextGateAAuthorization(
        staleWrapperBytes,
        now: capturedAt,
        expectedArtifactSha256: staleWrapperHash,
      ),
      throwsFormatException,
    );
  });

  test(
    'revalidation rejects consistently mutated token and refresh bindings',
    () {
      final artifact = _validGateAArtifact(capturedAt);
      final (bytes, hash) = encode(artifact);
      final authorization = parseDirectTextGateAAuthorization(
        bytes,
        now: capturedAt,
        expectedArtifactSha256: hash,
      );

      for (final mutation in <String>['token', 'refresh']) {
        final changed = clone(artifact);
        final refresh = (changed['refreshAuthorization']! as Map)
            .cast<String, Object?>();
        final flow = (changed['flowEvidence']! as Map).cast<String, Object?>();
        final receipt = (changed['receipt']! as Map).cast<String, Object?>();
        if (mutation == 'token') {
          refresh['tokenSha256'] = '9' * 64;
          flow['tokenSha256'] = '9' * 64;
          receipt['tokenSha256'] = '9' * 64;
        } else {
          refresh['refreshArtifactSha256'] = '8' * 64;
          flow['refreshArtifactSha256'] = '8' * 64;
          receipt['refreshArtifactSha256'] = '8' * 64;
        }
        final (changedBytes, changedHash) = encode(changed);
        expect(
          () => revalidateDirectTextGateAAuthorization(
            changedBytes,
            now: capturedAt,
            expectedArtifactSha256: changedHash,
            expectedAuthorization: authorization,
          ),
          throwsFormatException,
          reason: 'consistently changed $mutation binding survived',
        );
      }
    },
  );

  test('rejects account drift and downstream-complete claims', () {
    final artifact = _validGateAArtifact(capturedAt);
    final changedIdentity = clone(artifact);
    final flow = (changedIdentity['flowEvidence']! as Map)
        .cast<String, Object?>();
    final receipt = (changedIdentity['receipt']! as Map)
        .cast<String, Object?>();
    flow['accountIdentitySha256'] = '7' * 64;
    receipt['accountIdentitySha256'] = '7' * 64;
    final (identityBytes, identityHash) = encode(changedIdentity);
    final original = encode(artifact);
    final originalAuthorization = parseDirectTextGateAAuthorization(
      original.$1,
      now: capturedAt,
      expectedArtifactSha256: original.$2,
    );
    expect(
      () => revalidateDirectTextGateAAuthorization(
        identityBytes,
        now: capturedAt,
        expectedArtifactSha256: identityHash,
        expectedAuthorization: originalAuthorization,
      ),
      throwsFormatException,
    );

    final downstreamDone = clone(artifact)
      ..['downstreamDeliveryStillRequired'] = false;
    final (downstreamBytes, downstreamHash) = encode(downstreamDone);
    expect(
      () => parseDirectTextGateAAuthorization(
        downstreamBytes,
        now: capturedAt,
        expectedArtifactSha256: downstreamHash,
      ),
      throwsFormatException,
    );
  });

  test('accepts exact Gate A v2 current-token production binding', () {
    final artifact = _validGateAArtifactV2(capturedAt);
    final (bytes, hash) = encode(artifact);
    final authorization = parseDirectTextGateAAuthorization(
      bytes,
      now: capturedAt.add(const Duration(minutes: 10)),
      expectedArtifactSha256: hash,
    );

    expect(authorization['gateAArtifactSha256'], hash);
    expect(
      authorization['authorizationKind'],
      backgroundCryptoCurrentTokenAuthorizationKind,
    );
    expect(authorization['authorizationArtifactSha256'], _authorizationHash);
    expect(authorization['tokenSha256'], _tokenHash);
    expect(
      authorization['gateACommandGenerationId'],
      _gateACommandGenerationId,
    );
    expect(authorization['accountIdentitySha256'], _identityHash);
    expect(authorization['transportIdentitySha256'], _identityHash);
    expect(authorization, isNot(contains('originalRefreshArtifactSha256')));
  });

  test('Gate A v2 rejects stale source and all binding drift', () {
    final original = _validGateAArtifactV2(capturedAt);
    final mutations = <void Function(Map<String, Object?>)>[
      (value) =>
          (value['currentTokenAuthorization']!
                  as Map)['authorizationArtifactSha256'] =
              '9' * 64,
      (value) => (value['currentTokenAuthorization']! as Map)['tokenSha256'] =
          '9' * 64,
      (value) => (value['command']! as Map)['gateACommandGenerationId'] =
          'tc256-token-refresh-1783910955896883-866020056',
      (value) =>
          (value['flowEvidence']! as Map)['accountIdentitySha256'] = '9' * 64,
      (value) => (value['receipt']! as Map)['tokenPersisted'] = false,
      (value) => value['extra'] = true,
    ];
    for (final mutate in mutations) {
      final changed = clone(original);
      mutate(changed);
      final (bytes, hash) = encode(changed);
      expect(
        () => parseDirectTextGateAAuthorization(
          bytes,
          now: capturedAt,
          expectedArtifactSha256: hash,
        ),
        throwsFormatException,
      );
    }

    final staleSource = clone(original);
    (staleSource['currentTokenAuthorization']!
        as Map)['capturedAt'] = capturedAt
        .subtract(const Duration(minutes: 30, microseconds: 1))
        .toIso8601String();
    final (staleBytes, staleHash) = encode(staleSource);
    expect(
      () => parseDirectTextGateAAuthorization(
        staleBytes,
        now: capturedAt,
        expectedArtifactSha256: staleHash,
      ),
      throwsFormatException,
    );

    // The nested authorization must be fresh at the current acceptance
    // boundary, not merely close to the older Gate A capture timestamp.
    final oldAuthorization = _validGateAArtifactV2(capturedAt);
    final (oldAuthorizationBytes, oldAuthorizationHash) = encode(
      oldAuthorization,
    );
    expect(
      () => parseDirectTextGateAAuthorization(
        oldAuthorizationBytes,
        now: capturedAt.add(const Duration(minutes: 59)),
        expectedArtifactSha256: oldAuthorizationHash,
      ),
      throwsFormatException,
    );

    // A bounded future Gate A artifact cannot make a future nested
    // authorization valid at the current boundary.
    final futureArtifact = _validGateAArtifactV2(
      capturedAt.add(const Duration(seconds: 5)),
    );
    (futureArtifact['currentTokenAuthorization']! as Map)['capturedAt'] =
        capturedAt.add(const Duration(seconds: 1)).toIso8601String();
    final (futureBytes, futureHash) = encode(futureArtifact);
    expect(
      () => parseDirectTextGateAAuthorization(
        futureBytes,
        now: capturedAt,
        expectedArtifactSha256: futureHash,
      ),
      throwsFormatException,
    );
  });
}

const _tokenHash =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _priorTokenHash =
    '2222222222222222222222222222222222222222222222222222222222222222';
const _refreshHash =
    '3333333333333333333333333333333333333333333333333333333333333333';
const _commandHash =
    '4444444444444444444444444444444444444444444444444444444444444444';
const _identityHash =
    '5555555555555555555555555555555555555555555555555555555555555555';
const _apkHash =
    '6666666666666666666666666666666666666666666666666666666666666666';
const _notificationHash =
    '7777777777777777777777777777777777777777777777777777777777777777';
const _commandId = 'tc256-relay-registration-1783913597122203-857967423';
const _generationId = 'tc256-token-refresh-1783910955896883-866020056';
const _authorizationHash =
    '8888888888888888888888888888888888888888888888888888888888888888';
const _gateACommandGenerationId =
    'tc256-gate-a-command-1783913597122203-857967424';

Map<String, Object?> _validGateAArtifact(DateTime capturedAt) =>
    <String, Object?>{
      'schema': backgroundCryptoPushRelayRegistrationArtifactSchema,
      'status': 'passed',
      'capturedAt': capturedAt.toIso8601String(),
      'mode': 'instrumented-production-main',
      'recipient': <String, Object?>{
        'deviceId': 'emulator-5554',
        'platform': 'android',
        'targetPlatform': 'android-arm64',
      },
      'refreshAuthorization': <String, Object?>{
        'refreshArtifactSha256': _refreshHash,
        'capturedAt': capturedAt
            .subtract(const Duration(minutes: 44))
            .toIso8601String(),
        'tokenSha256': _tokenHash,
        'priorTokenSha256': _priorTokenHash,
        'tokenGenerationId': _generationId,
        'refreshSignal': 'poll',
      },
      'command': <String, Object?>{
        'commandId': _commandId,
        'commandSha256': _commandHash,
        'mode': '0600',
        'deleted': true,
      },
      'flowEvidence': <String, Object?>{
        'proofSchema': backgroundCryptoPushRelayRegistrationCommandSchema,
        'commandId': _commandId,
        'tokenSha256': _tokenHash,
        'tokenGenerationId': _generationId,
        'refreshArtifactSha256': _refreshHash,
        'commandSha256': _commandHash,
        'platform': 'android',
        'accountIdentitySha256': _identityHash,
        'transportIdentitySha256': _identityHash,
        'relayFrameAccepted': true,
        'tokenPersisted': true,
        'commandDeleted': true,
        'coordinatorSuccess': true,
        'orderedEventCount': 13,
      },
      'receipt': <String, Object?>{
        'schema': backgroundCryptoPushRelayRegistrationReceiptSchema,
        'status': 'completed',
        'completedAt': capturedAt
            .subtract(const Duration(seconds: 8))
            .toIso8601String(),
        'proofSchema': backgroundCryptoPushRelayRegistrationCommandSchema,
        'commandId': _commandId,
        'tokenSha256': _tokenHash,
        'tokenGenerationId': _generationId,
        'refreshArtifactSha256': _refreshHash,
        'commandSha256': _commandHash,
        'platform': 'android',
        'accountIdentitySha256': _identityHash,
        'transportIdentitySha256': _identityHash,
        'relayFrameAccepted': true,
        'tokenPersisted': true,
        'commandDeleted': true,
        'containsSecrets': false,
      },
      'relayClaim': 'relay_frame_status_ok',
      'relayPersistenceProvenByThisGate': false,
      'downstreamDeliveryStillRequired': true,
      'productionPath': <String, Object?>{
        'entrypoint': 'lib/main.dart',
        'kE2ETestMode': false,
        'compileGate': 'MKNOON_PUSH_RELAY_REGISTRATION_PROOF',
        'byteIdenticalToRestoredCandidate': false,
      },
      'notificationState': <String, Object?>{
        'baselineSha256': _notificationHash,
        'finalSha256': _notificationHash,
        'unchanged': true,
      },
      'cleanup': <String, Object?>{
        'appIdle': true,
        'commandDeleted': true,
        'receiptDeleted': true,
        'receiptTempDeleted': true,
        'notificationStateUnchanged': true,
        'installedCandidateRestored': true,
        'installedCandidateBytesVerified': true,
        'installedCandidateApkSha256': <String>[_apkHash],
        'localBuildArtifactRestoredToPriorState': true,
        'localBuildArtifactBytesVerified': true,
        'notificationPermissionRestored': true,
        'notificationPermissionInitiallyGranted': true,
        'backupDirectoryDeleted': true,
      },
      'intentionalPersistentEffects': const <String>[
        'relay_registration_frame_accepted',
        'push_token_store_updated',
      ],
      'redaction': const <String, Object?>{
        'rawTokenPersisted': false,
        'peerIdPersisted': false,
        'commandPayloadPersisted': false,
        'rawLogPersisted': false,
      },
      'containsSecrets': false,
    };

Map<String, Object?> _validGateAArtifactV2(DateTime capturedAt) {
  final artifact = _validGateAArtifact(capturedAt);
  artifact['schema'] = backgroundCryptoPushRelayRegistrationArtifactSchemaV2;
  artifact.remove('refreshAuthorization');
  artifact['currentTokenAuthorization'] = <String, Object?>{
    'authorizationKind': backgroundCryptoCurrentTokenAuthorizationKind,
    'authorizationArtifactSha256': _authorizationHash,
    'capturedAt': capturedAt
        .subtract(const Duration(minutes: 20))
        .toIso8601String(),
    'tokenSha256': _tokenHash,
    'providerOperation': 'validate_only',
    'providerValidationResult': 'accepted',
    'providerHttpStatus': 200,
    'providerRpcStatus': 'OK',
    'deliveryAttempted': false,
  };
  final command = (artifact['command']! as Map).cast<String, Object?>();
  command['gateACommandGenerationId'] = _gateACommandGenerationId;
  final flow = (artifact['flowEvidence']! as Map).cast<String, Object?>();
  flow
    ..['proofSchema'] = backgroundCryptoPushRelayRegistrationCommandSchemaV2
    ..remove('tokenGenerationId')
    ..remove('refreshArtifactSha256')
    ..['authorizationKind'] = backgroundCryptoCurrentTokenAuthorizationKind
    ..['authorizationArtifactSha256'] = _authorizationHash
    ..['gateACommandGenerationId'] = _gateACommandGenerationId;
  final receipt = (artifact['receipt']! as Map).cast<String, Object?>();
  receipt
    ..['schema'] = backgroundCryptoPushRelayRegistrationReceiptSchemaV2
    ..['proofSchema'] = backgroundCryptoPushRelayRegistrationCommandSchemaV2
    ..remove('tokenGenerationId')
    ..remove('refreshArtifactSha256')
    ..['authorizationKind'] = backgroundCryptoCurrentTokenAuthorizationKind
    ..['authorizationArtifactSha256'] = _authorizationHash
    ..['gateACommandGenerationId'] = _gateACommandGenerationId;
  return artifact;
}
