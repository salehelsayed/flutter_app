import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/direct_private_media_device_local_journey_criteria.dart';

void main() {
  group('direct private-media device-local journey criteria', () {
    test(
      'locks the causal sender pending-open proof to artifact version 3',
      () {
        expect(directPrivateMediaDeviceLocalJourneyVersion, 3);
      },
    );

    test('accepts one complete automated physical/emulator artifact', () {
      final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
        _validArtifact(),
      );

      expect(result.ok, isTrue, reason: result.detail);
      expect(result.failures, isEmpty);
      expect(result.detail, 'accepted');
    });

    test('requires the exact sender pending-open causal evidence keys', () {
      for (final key in const <String>[
        'pendingOpenTapCount',
        'pendingOpenSqlStateSequence',
        'pendingOpenProofSequence',
      ]) {
        final artifact = _validArtifact();
        _senderObservations(artifact).remove(key);

        final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
          artifact,
        );

        expect(result.ok, isFalse, reason: '$key removal was accepted');
        expect(
          result.failures,
          contains(
            r'$.sender.observations missing fields: '
            '$key',
          ),
          reason: result.detail,
        );
      }
    });

    test('requires exactly one scoped sender Open tap', () {
      for (final invalidCount in const <Object?>[0, 2, true]) {
        final artifact = _validArtifact();
        _senderObservations(artifact)['pendingOpenTapCount'] = invalidCount;

        final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
          artifact,
        );

        expect(result.ok, isFalse, reason: '$invalidCount was accepted');
        expect(
          result.failures,
          contains(
            r'$.sender.observations.pendingOpenTapCount must equal integer 1',
          ),
          reason: result.detail,
        );
      }
    });

    test('requires SQL-derived available-opening-viewing-consumed order', () {
      final mutations = <Object?>[
        const <String>['available', 'viewing', 'opening', 'consumed'],
        const <String>['available', 'opening', 'viewing'],
        true,
      ];
      for (final mutation in mutations) {
        final artifact = _validArtifact();
        _senderObservations(artifact)['pendingOpenSqlStateSequence'] = mutation;

        final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
          artifact,
        );

        expect(result.ok, isFalse, reason: '$mutation was accepted');
        expect(
          result.failures,
          contains(
            r'$.sender.observations.pendingOpenSqlStateSequence must equal '
            'the derived available -> opening -> viewing -> consumed sequence',
          ),
          reason: result.detail,
        );
      }
    });

    test('requires causal first-frame, Back, route, and cleanup evidence', () {
      final mutations = <Object?>[
        <String>[..._pendingOpenProofSequence]..remove('viewer_first_frame'),
        const <String>[
          'pending_sql_authority_verified',
          'repository_mirror_seeded',
          'open_tapped',
          'opening_sql_observed',
          'viewing_sql_observed',
          'viewer_first_frame',
          'viewer_back_tapped',
          'conversation_route_resumed',
          'consumed_sql_observed',
          'attachment_cleanup_observed',
          'pending_source_cleanup_observed',
        ],
        true,
      ];
      for (final mutation in mutations) {
        final artifact = _validArtifact();
        _senderObservations(artifact)['pendingOpenProofSequence'] = mutation;

        final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
          artifact,
        );

        expect(result.ok, isFalse, reason: '$mutation was accepted');
        expect(
          result.failures,
          contains(
            r'$.sender.observations.pendingOpenProofSequence must equal the '
            'exact causal sender pending-open proof sequence',
          ),
          reason: result.detail,
        );
      }
    });

    test('rejects p262 evidence under the recipient role', () {
      final artifact = _validArtifact();
      _recipientObservations(artifact)['pendingOpenTapCount'] = 1;

      final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
        artifact,
      );

      expect(result.ok, isFalse);
      expect(
        result.failures.any(
          (failure) => failure.contains('unexpected fields at indexes:'),
        ),
        isTrue,
        reason: result.detail,
      );
    });

    test('rejects boolean-only p262 success evidence', () {
      final artifact = _validArtifact();
      final observations = _senderObservations(artifact)
        ..remove('pendingOpenTapCount')
        ..remove('pendingOpenSqlStateSequence')
        ..remove('pendingOpenProofSequence')
        ..['pendingOpenSucceeded'] = true;

      final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
        artifact,
      );

      expect(result.ok, isFalse);
      expect(
        result.failures.any(
          (failure) =>
              failure.contains('missing fields:') &&
              failure.contains('pendingOpenSqlStateSequence'),
        ),
        isTrue,
        reason: result.detail,
      );
      expect(
        result.failures.any(
          (failure) => failure.contains('unexpected fields at indexes:'),
        ),
        isTrue,
        reason: result.detail,
      );
      expect(observations['pendingOpenSucceeded'], isTrue);
    });

    test('rejects non-object and non-string-keyed artifacts', () {
      expect(
        validateDirectPrivateMediaDeviceLocalJourneyArtifact(null).ok,
        isFalse,
      );
      expect(
        validateDirectPrivateMediaDeviceLocalJourneyArtifact(<Object?, Object?>{
          1: 'not a JSON object',
        }).ok,
        isFalse,
      );
    });

    test('rejects a boolean-only artifact', () {
      final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(true);

      expect(result.ok, isFalse);
      expect(result.failures, contains(r'$ must be a JSON object'));
    });

    for (final missingRole in const <String>['sender', 'recipient']) {
      test('rejects a missing $missingRole child', () {
        final artifact = _validArtifact()..remove(missingRole);

        final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
          artifact,
        );

        expect(result.ok, isFalse);
        expect(
          result.failures.any(
            (failure) =>
                failure.contains('missing fields:') &&
                failure.contains(missingRole),
          ),
          isTrue,
          reason: result.detail,
        );
      });
    }

    test('rejects a missing sender fixture digest', () {
      final artifact = _validArtifact();
      _senderObservations(artifact).remove('fixtureDigest');

      final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
        artifact,
      );

      expect(result.ok, isFalse);
      expect(
        result.failures,
        contains(r'$.sender.observations missing fields: fixtureDigest'),
        reason: result.detail,
      );
    });

    test('rejects a missing recipient fixture digest', () {
      final artifact = _validArtifact();
      _recipientObservations(artifact).remove('fixtureDigest');

      final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
        artifact,
      );

      expect(result.ok, isFalse);
      expect(
        result.failures,
        contains(r'$.recipient.observations missing fields: fixtureDigest'),
        reason: result.detail,
      );
    });

    test('rejects mismatched sender and recipient fixture digests', () {
      final artifact = _validArtifact();
      _recipientObservations(artifact)['fixtureDigest'] =
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

      final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
        artifact,
      );

      expect(result.ok, isFalse);
      expect(
        result.failures,
        contains(
          r'$.recipient.observations.fixtureDigest must match '
          r'$.sender.observations.fixtureDigest',
        ),
        reason: result.detail,
      );
    });

    test(
      'requires production private-card render evidence from both roles',
      () {
        final accepted = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
          _validArtifact(),
        );
        expect(accepted.ok, isTrue, reason: accepted.detail);

        for (final role in const <String>['sender', 'recipient']) {
          final artifact = _validArtifact();
          final observations =
              (artifact[role] as Map<String, dynamic>)['observations']
                  as Map<String, dynamic>;
          observations['productionConversationMounted'] = false;

          final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
            artifact,
          );

          expect(result.ok, isFalse, reason: '$role mutation was accepted');
          expect(
            result.failures,
            contains(
              r'$.'
              '$role'
              r'.observations.productionConversationMounted must equal true',
            ),
            reason: result.detail,
          );
        }
      },
    );

    test('rejects vacuous or pixel-bearing production card measurements', () {
      final mutations = <String, Object?>{
        'productionLetterCardCount': 2,
        'privateSlotCount': 2,
        'slotsInsideDecoratedBodies': 2,
        'nonZeroPrivateSlotCount': 2,
        'slotImageWidgetCount': 1,
        'slotDecorationImageCount': 1,
        'outgoingActionVisible': false,
        'incomingActionVisible': false,
        'terminalActionVisibleAfterRepump': false,
      };
      for (final entry in mutations.entries) {
        final artifact = _validArtifact();
        _recipientObservations(artifact)[entry.key] = entry.value;

        final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
          artifact,
        );

        expect(
          result.ok,
          isFalse,
          reason: '${entry.key} mutation was accepted',
        );
      }
    });

    test(
      'rejects a fixture digest that is not exactly 64 hexadecimal digits',
      () {
        final artifact = _validArtifact();
        _senderObservations(artifact)['fixtureDigest'] = 'abc123';

        final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
          artifact,
        );

        expect(result.ok, isFalse);
        expect(
          result.failures,
          contains(
            r'$.sender.observations.fixtureDigest must be exactly 64 '
            'hexadecimal digits',
          ),
          reason: result.detail,
        );
      },
    );

    test('rejects swapped emulator sender and physical recipient roles', () {
      final artifact = _validArtifact();
      final topology = _topology(artifact);
      topology['senderDeviceId'] = 'emulator-5554';
      topology['senderDeviceKind'] = 'emulator';
      topology['recipientDeviceId'] = '21071FDF600CSC';
      topology['recipientDeviceKind'] = 'physical';
      _sender(artifact)['deviceId'] = 'emulator-5554';
      _recipient(artifact)['deviceId'] = '21071FDF600CSC';

      final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
        artifact,
      );

      expect(result.ok, isFalse);
      expect(
        result.failures,
        contains(
          r'$.topology sender must be physical and recipient must be emulator',
        ),
        reason: result.detail,
      );
    });

    test('rejects a forbidden secret embedded in an allowed string value', () {
      final artifact = _validArtifact();
      _topology(artifact)['senderDeviceId'] = 'device-secret-material';
      _sender(artifact)['deviceId'] = 'device-secret-material';

      final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
        artifact,
      );

      expect(result.ok, isFalse);
      expect(
        result.failures,
        contains(
          r'$.topology.senderDeviceId contains forbidden sensitive string '
          'value',
        ),
        reason: result.detail,
      );
    });

    test('rejects the implicit Flutter all-device selector', () {
      final artifact = _validArtifact();
      _topology(artifact)['senderDeviceId'] = 'all';
      _sender(artifact)['deviceId'] = 'all';

      final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
        artifact,
      );

      expect(result.ok, isFalse);
      expect(
        result.failures,
        contains(
          r'$.topology.senderDeviceId must be an explicit safe Android '
          'device ID',
        ),
        reason: result.detail,
      );
    });

    for (final forbiddenValue in const <String>[
      'opaque-kem',
      'opaque-ciphertext',
      'private-blob.bin',
      'MIME',
      'kind',
      'bytes',
      'size',
      'dimensions',
      'duration',
      'policy',
      'lifecycle',
    ]) {
      test('rejects forbidden $forbiddenValue value smuggling', () {
        final artifact = _validArtifact();
        final smuggledValue = 'device-$forbiddenValue';
        _topology(artifact)['senderDeviceId'] = smuggledValue;
        _sender(artifact)['deviceId'] = smuggledValue;

        final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
          artifact,
        );

        expect(result.ok, isFalse);
        expect(
          result.failures,
          contains(
            r'$.topology.senderDeviceId contains forbidden sensitive string '
            'value',
          ),
          reason: result.detail,
        );
        expect(result.detail, isNot(contains(smuggledValue)));
      });
    }

    for (final denialField in const <String>[
      'privateEgressDenied',
      'legacyOrdinaryViewerEntryDenied',
      'typedPictureInPictureDenied',
    ]) {
      test('rejects false $denialField evidence', () {
        final artifact = _validArtifact();
        _recipientObservations(artifact)[denialField] = false;

        final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
          artifact,
        );

        expect(result.ok, isFalse);
        expect(
          result.failures,
          contains(
            r'$.recipient.observations.'
            '$denialField must equal true',
          ),
          reason: result.detail,
        );
      });
    }

    test('redacts an attacker-controlled unknown field label', () {
      const attackerField = 'operatorApprovedOpaqueMaterial';
      final artifact = _validArtifact();
      _recipientObservations(artifact)[attackerField] = true;

      final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
        artifact,
      );

      expect(result.ok, isFalse);
      expect(
        result.failures.any(
          (failure) => failure.contains('unexpected fields at indexes:'),
        ),
        isTrue,
        reason: result.detail,
      );
      expect(result.detail, isNot(contains(attackerField)));
    });

    final mutations = <String, void Function(Map<String, dynamic>)>{
      'missing required root field': (artifact) => artifact.remove('schema'),
      'unexpected root field': (artifact) => artifact['verdict'] = 'passed',
      'wrong schema': (artifact) => artifact['schema'] = 'plan234.demo',
      'non-integer version': (artifact) => artifact['version'] = 1.0,
      'legacy v1 version': (artifact) => artifact['version'] = 1,
      'legacy v2 version': (artifact) => artifact['version'] = 2,
      'future v4 version': (artifact) => artifact['version'] = 4,
      'manual generator': (artifact) => artifact['generatedBy'] = 'operator',
      'non-Android platform': (artifact) =>
          _topology(artifact)['platform'] = 'ios',
      'manual automation': (artifact) =>
          _topology(artifact)['automation'] = 'manual',
      'relay transport claim': (artifact) =>
          _topology(artifact)['transportScope'] = 'relay_authoritative',
      'same sender and recipient': (artifact) =>
          _topology(artifact)['recipientDeviceId'] = '21071FDF600CSC',
      'two physical devices': (artifact) =>
          _topology(artifact)['recipientDeviceKind'] = 'physical',
      'invalid emulator id': (artifact) =>
          _topology(artifact)['recipientDeviceId'] = 'android-emulator',
      'unsafe physical id': (artifact) =>
          _topology(artifact)['senderDeviceId'] = '/tmp/device-secret',
      'generic physical id': (artifact) =>
          _topology(artifact)['senderDeviceId'] = 'default',
      'wrong sender role': (artifact) =>
          _sender(artifact)['role'] = 'recipient',
      'sender id does not match topology': (artifact) =>
          _sender(artifact)['deviceId'] = 'DIFFERENT123',
      'untrusted sender observation': (artifact) =>
          _sender(artifact)['observationSource'] = 'operator_statement',
      'wrong recipient role': (artifact) =>
          _recipient(artifact)['role'] = 'sender',
      'recipient id does not match topology': (artifact) =>
          _recipient(artifact)['deviceId'] = 'emulator-5556',
      'untrusted recipient observation': (artifact) =>
          _recipient(artifact)['observationSource'] = 'screenshot',
      'non-v2 encrypted envelope': (artifact) =>
          _senderObservations(artifact)['encryptedEnvelopeCodec'] =
              'encrypted-v1',
      'private metadata on outer envelope': (artifact) =>
          _senderObservations(artifact)['outerPrivateMediaPresent'] = true,
      'missing private metadata inside encryption': (artifact) =>
          _senderObservations(artifact)['innerPrivateMediaPresent'] = false,
      'ordinary sender regression': (artifact) =>
          _senderObservations(artifact)['ordinarySendPreserved'] = false,
      'private payload not persisted': (artifact) =>
          _recipientObservations(artifact)['privatePayloadPersisted'] = false,
      'private policy not applied': (artifact) =>
          _recipientObservations(artifact)['privatePolicyApplied'] = false,
      'persistence after policy': (artifact) =>
          _recipientObservations(artifact)['persistedSequence'] = 20,
      'preview before policy': (artifact) =>
          _recipientObservations(artifact)['previewSequence'] = 15,
      'download before policy': (artifact) =>
          _recipientObservations(artifact)['downloadSequence'] = 15,
      'fractional event sequence': (artifact) =>
          _recipientObservations(artifact)['policySequence'] = 20.0,
      'non-generic notification copy': (artifact) =>
          _recipientObservations(artifact)['notificationCopy'] = 'Photo',
      'caption leaked through quote copy': (artifact) =>
          _recipientObservations(artifact)['quoteCopy'] = 'secret caption',
      'automatic private download': (artifact) =>
          _recipientObservations(artifact)['autoDownloadCount'] = 1,
      'missing manual download': (artifact) =>
          _recipientObservations(artifact)['manualDownloadCount'] = 0,
      'non-canonical manual result': (artifact) =>
          _recipientObservations(artifact)['manualDownloadResult'] =
              'temporary_file',
      'second view-once reveal': (artifact) =>
          _recipientObservations(artifact)['viewOnceRevealCount'] = 2,
      'view-once cleanup absent': (artifact) =>
          _recipientObservations(artifact)['viewOnceCleanupCompleted'] = false,
      'view-once bytes survive cleanup': (artifact) => _recipientObservations(
        artifact,
      )['viewOnceAttachmentPresentAfterCleanup'] = true,
      'view-once resurrects after reopen': (artifact) =>
          _recipientObservations(artifact)['viewOnceAvailableAfterReopen'] =
              true,
      'disappearing media did not expire': (artifact) =>
          _recipientObservations(artifact)['disappearingExpiryCompleted'] =
              false,
      'disappearing media remains available': (artifact) =>
          _recipientObservations(artifact)['disappearingAvailableAfterExpiry'] =
              true,
      'protected first open decision fails': (artifact) =>
          _recipientObservations(
            artifact,
          )['protectedFirstOpenDecisionAllowed'] = false,
      'protected repeat open decision fails': (artifact) =>
          _recipientObservations(
            artifact,
          )['protectedRepeatOpenDecisionAllowed'] = false,
      'protected media consumed by repeat': (artifact) =>
          _recipientObservations(artifact)['protectedAvailableAfterRepeat'] =
              false,
      'ordinary preview regresses': (artifact) =>
          _recipientObservations(artifact)['ordinaryPreviewSucceeded'] = false,
      'ordinary download regresses': (artifact) =>
          _recipientObservations(artifact)['ordinaryManualDownloadSucceeded'] =
              false,
      'consume receipt emitted': (artifact) =>
          _recipientObservations(artifact)['consumeReceiptCount'] = 1,
      'consume-receipt claim': (artifact) =>
          _claims(artifact)['consumeReceipt'] = true,
      'account-wide claim': (artifact) =>
          _claims(artifact)['accountWideConsumption'] = true,
      'relay revocation claim': (artifact) =>
          _claims(artifact)['relayAuthoritativeRevocation'] = true,
      'missing nested observation': (artifact) =>
          _recipientObservations(artifact).remove('autoDownloadCount'),
      'extra nested theatrical assertion': (artifact) =>
          _recipientObservations(artifact)['operatorApproved'] = true,
    };

    for (final mutation in mutations.entries) {
      test('rejects ${mutation.key}', () {
        final artifact = _validArtifact();
        mutation.value(artifact);

        final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
          artifact,
        );

        expect(result.ok, isFalse, reason: mutation.key);
        expect(result.failures, isNotEmpty, reason: mutation.key);
      });
    }

    for (final sensitiveField in const <String>[
      'secret',
      'filePath',
      'encryptionKey',
      'nonce',
      'caption',
    ]) {
      test(
        'rejects leaked $sensitiveField fields anywhere in the artifact',
        () {
          final artifact = _validArtifact();
          _recipientObservations(artifact)[sensitiveField] = 'leaked-material';

          final result = validateDirectPrivateMediaDeviceLocalJourneyArtifact(
            artifact,
          );

          expect(result.ok, isFalse);
          expect(
            result.failures.any(
              (failure) => failure.contains('sensitive field'),
            ),
            isTrue,
            reason: result.detail,
          );
          expect(result.detail, isNot(contains(sensitiveField)));
        },
      );
    }
  });
}

Map<String, dynamic> _validArtifact() {
  return jsonDecode(jsonEncode(_validArtifactFixture)) as Map<String, dynamic>;
}

Map<String, dynamic> _topology(Map<String, dynamic> artifact) {
  return artifact['topology'] as Map<String, dynamic>;
}

Map<String, dynamic> _claims(Map<String, dynamic> artifact) {
  return artifact['claims'] as Map<String, dynamic>;
}

Map<String, dynamic> _sender(Map<String, dynamic> artifact) {
  return artifact['sender'] as Map<String, dynamic>;
}

Map<String, dynamic> _senderObservations(Map<String, dynamic> artifact) {
  return _sender(artifact)['observations'] as Map<String, dynamic>;
}

Map<String, dynamic> _recipient(Map<String, dynamic> artifact) {
  return artifact['recipient'] as Map<String, dynamic>;
}

Map<String, dynamic> _recipientObservations(Map<String, dynamic> artifact) {
  return _recipient(artifact)['observations'] as Map<String, dynamic>;
}

const Map<String, Object?> _validArtifactFixture = <String, Object?>{
  'schema': directPrivateMediaDeviceLocalJourneySchema,
  'version': 3,
  'generatedBy': 'automated_instrumented_harness',
  'topology': <String, Object?>{
    'platform': 'android',
    'automation': 'fully_automated',
    'transportScope': 'device_local_app_layer',
    'senderDeviceId': '21071FDF600CSC',
    'senderDeviceKind': 'physical',
    'recipientDeviceId': 'emulator-5554',
    'recipientDeviceKind': 'emulator',
  },
  'claims': <String, Object?>{
    'consumeReceipt': false,
    'accountWideConsumption': false,
    'relayAuthoritativeRevocation': false,
  },
  'sender': <String, Object?>{
    'role': 'sender',
    'deviceId': '21071FDF600CSC',
    'observationSource': 'instrumented_app',
    'observations': <String, Object?>{
      'fixtureDigest': _fixtureDigest,
      'encryptedEnvelopeCodec': 'encrypted-v2',
      'outerPrivateMediaPresent': false,
      'innerPrivateMediaPresent': true,
      'ordinarySendPreserved': true,
      'pendingOpenTapCount': 1,
      'pendingOpenSqlStateSequence': <String>[
        'available',
        'opening',
        'viewing',
        'consumed',
      ],
      'pendingOpenProofSequence': _pendingOpenProofSequence,
      'productionConversationMounted': true,
      'productionLetterCardCount': 3,
      'privateSlotCount': 3,
      'slotsInsideDecoratedBodies': 3,
      'nonZeroPrivateSlotCount': 3,
      'slotImageWidgetCount': 0,
      'slotDecorationImageCount': 0,
      'outgoingActionVisible': true,
      'incomingActionVisible': true,
      'terminalActionVisibleAfterRepump': true,
    },
  },
  'recipient': <String, Object?>{
    'role': 'recipient',
    'deviceId': 'emulator-5554',
    'observationSource': 'instrumented_app',
    'observations': <String, Object?>{
      'fixtureDigest': _fixtureDigest,
      'privatePayloadPersisted': true,
      'privatePolicyApplied': true,
      'privateEgressDenied': true,
      'legacyOrdinaryViewerEntryDenied': true,
      'typedPictureInPictureDenied': true,
      'persistedSequence': 10,
      'policySequence': 20,
      'previewSequence': 30,
      'downloadSequence': 40,
      'notificationCopy': 'Private media',
      'quoteCopy': 'Private media',
      'autoDownloadCount': 0,
      'manualDownloadCount': 1,
      'manualDownloadResult': 'canonical_durable_storage',
      'viewOnceRevealCount': 1,
      'viewOnceCleanupCompleted': true,
      'viewOnceAttachmentPresentAfterCleanup': false,
      'viewOnceAvailableAfterReopen': false,
      'disappearingExpiryCompleted': true,
      'disappearingAvailableAfterExpiry': false,
      'protectedFirstOpenDecisionAllowed': true,
      'protectedRepeatOpenDecisionAllowed': true,
      'protectedAvailableAfterRepeat': true,
      'ordinaryPreviewSucceeded': true,
      'ordinaryManualDownloadSucceeded': true,
      'consumeReceiptCount': 0,
      'productionConversationMounted': true,
      'productionLetterCardCount': 3,
      'privateSlotCount': 3,
      'slotsInsideDecoratedBodies': 3,
      'nonZeroPrivateSlotCount': 3,
      'slotImageWidgetCount': 0,
      'slotDecorationImageCount': 0,
      'outgoingActionVisible': true,
      'incomingActionVisible': true,
      'terminalActionVisibleAfterRepump': true,
    },
  },
};

const String _fixtureDigest =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const List<String> _pendingOpenProofSequence = <String>[
  'pending_sql_authority_verified',
  'repository_mirror_seeded',
  'open_tapped',
  'opening_sql_observed',
  'viewer_first_frame',
  'viewing_sql_observed',
  'viewer_back_tapped',
  'conversation_route_resumed',
  'consumed_sql_observed',
  'attachment_cleanup_observed',
  'pending_source_cleanup_observed',
];
