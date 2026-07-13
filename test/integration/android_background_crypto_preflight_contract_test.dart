import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';

import '../../integration_test/scripts/reaction_notification_proof_support.dart';

void main() {
  test('ordinary preflight matrix is the exact 3 x 4 contract', () {
    expect(backgroundCryptoPreflightOrdinaryRows, hasLength(12));
    expect(backgroundCryptoPreflightOrdinaryRows.map((row) => row.id), <String>[
      'direct-text',
      'direct-image',
      'direct-video',
      'direct-voice',
      'group-text',
      'group-image',
      'group-video',
      'group-voice',
      'announcement-text',
      'announcement-image',
      'announcement-video',
      'announcement-voice',
    ]);
    expect(
      backgroundCryptoPreflightOrdinaryRows
          .where((row) => row.context == 'direct')
          .every(
            (row) =>
                row.providerKind == 'chat' && row.remoteType == 'new_message',
          ),
      isTrue,
    );
    expect(
      backgroundCryptoPreflightOrdinaryRows
          .where((row) => row.context != 'direct')
          .every((row) => row.remoteType == 'group_message'),
      isTrue,
    );
  });

  test('authorization rejection matrix is exact and bounded', () {
    expect(backgroundCryptoPreflightNegativeRows, hasLength(3));
    expect(backgroundCryptoPreflightNegativeRows.map((row) => row.id), <String>[
      'group-missing-transport',
      'group-unknown-transport',
      'announcement-non-admin',
    ]);
  });

  test('controller and fixture share the exact cleanup command modes', () {
    expect(backgroundCryptoCleanupCommandModes, <String>{
      'cleanup-only',
      'setup-only',
      'recovery',
      'post-proof',
    });
    final app = File(
      'integration_test/android_background_crypto_preflight_app.dart',
    ).readAsStringSync();
    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    expect(app, contains('backgroundCryptoCleanupCommandModes.contains(mode)'));
    expect(
      controller,
      contains('backgroundCryptoCleanupCommandModes.contains(mode)'),
    );
    expect(controller, contains("_runCleanupCommand(mode: 'setup-only')"));
  });

  test('validated cleanup command wins simultaneous clear marker startup', () {
    expect(
      backgroundCryptoFixtureStartupIntent(
        hasValidatedCleanupCommand: true,
        hasClearNotificationsMarker: true,
      ),
      BackgroundCryptoFixtureStartupIntent.cleanupCommand,
    );
    expect(
      backgroundCryptoFixtureStartupIntent(
        hasValidatedCleanupCommand: false,
        hasClearNotificationsMarker: true,
      ),
      BackgroundCryptoFixtureStartupIntent.clearNotifications,
    );
    expect(
      backgroundCryptoFixtureStartupIntent(
        hasValidatedCleanupCommand: false,
        hasClearNotificationsMarker: false,
      ),
      BackgroundCryptoFixtureStartupIntent.setup,
    );

    final app = File(
      'integration_test/android_background_crypto_preflight_app.dart',
    ).readAsStringSync();
    final commandRead = app.indexOf(
      'final cleanupCommand = await _readCleanupCommand(support)',
    );
    final startupSelection = app.indexOf(
      'backgroundCryptoFixtureStartupIntent(',
      commandRead,
    );
    final clearBranch = app.indexOf(
      'BackgroundCryptoFixtureStartupIntent.clearNotifications',
      startupSelection,
    );
    expect(commandRead, greaterThan(0));
    expect(startupSelection, greaterThan(commandRead));
    expect(clearBranch, greaterThan(startupSelection));
    expect(app, contains("'clearNotificationsMarkerDeleted': true"));
  });

  test('private bundle validator accepts the complete encrypted matrix', () {
    expect(validateBackgroundCryptoPreflightBundle(_validBundle()), isEmpty);
  });

  test(
    'fresh FCM token race accepts only a different token and invalidates once',
    () async {
      final refreshes = StreamController<String>();
      var invalidations = 0;
      final staleSubjectHash = sha256
          .convert(utf8.encode('stale-token'))
          .toString();
      final observation = await acquireBackgroundCryptoFreshFcmToken(
        previousToken: 'stale-token',
        expectedSubjectTokenSha256: staleSubjectHash,
        tokenRefreshes: refreshes.stream,
        invalidateToken: () async {
          invalidations++;
          refreshes
            ..add('stale-token')
            ..add('fresh-stream-token');
        },
        pollToken: () async => 'stale-token',
        now: () => DateTime.utc(2026, 7, 13, 12),
        timeout: const Duration(seconds: 1),
        pollInterval: Duration.zero,
      );
      await refreshes.close();
      expect(invalidations, 1);
      expect(observation.token, 'fresh-stream-token');
      expect(observation.source, 'on_token_refresh');
      expect(observation.tokenSha256, isNot(observation.priorTokenSha256));
    },
  );

  test(
    'fresh FCM token race falls back to bounded polling and times out safely',
    () async {
      final refreshes = StreamController<String>();
      var invalidations = 0;
      var polls = 0;
      final staleSubjectHash = sha256
          .convert(utf8.encode('stale-token'))
          .toString();
      final observation = await acquireBackgroundCryptoFreshFcmToken(
        previousToken: 'stale-token',
        expectedSubjectTokenSha256: staleSubjectHash,
        tokenRefreshes: refreshes.stream,
        invalidateToken: () async => invalidations++,
        pollToken: () async {
          polls++;
          if (polls == 1) return 'stale-token';
          if (polls == 2) throw StateError('transient poll failure');
          return 'fresh-polled-token';
        },
        now: () => DateTime.utc(2026, 7, 13, 12),
        timeout: const Duration(seconds: 1),
        pollInterval: Duration.zero,
      );
      expect(observation.source, 'poll');
      expect(invalidations, 1);
      expect(polls, 3);

      final timeoutRefreshes = StreamController<String>();
      await expectLater(
        acquireBackgroundCryptoFreshFcmToken(
          previousToken: 'stale-token',
          expectedSubjectTokenSha256: staleSubjectHash,
          tokenRefreshes: timeoutRefreshes.stream,
          invalidateToken: () async => invalidations++,
          pollToken: () async => 'stale-token',
          now: () => DateTime.utc(2026, 7, 13, 12),
          timeout: const Duration(milliseconds: 10),
          pollInterval: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await refreshes.close();
      await timeoutRefreshes.close();
      expect(invalidations, 2);

      var mismatchInvalidations = 0;
      await expectLater(
        acquireBackgroundCryptoFreshFcmToken(
          previousToken: 'different-device-token',
          expectedSubjectTokenSha256: staleSubjectHash,
          tokenRefreshes: const Stream<String>.empty(),
          invalidateToken: () async => mismatchInvalidations++,
          pollToken: () async => 'must-not-poll',
          now: () => DateTime.utc(2026, 7, 13, 12),
        ),
        throwsArgumentError,
      );
      expect(mismatchInvalidations, 0);
    },
  );

  test(
    'refresh command and redacted token observation are generation-bound',
    () {
      final now = DateTime.utc(2026, 7, 13, 12);
      const generation = 'tc256-token-refresh-1783944000000000-17';
      final subjectHash = sha256
          .convert(utf8.encode('stale-private-token'))
          .toString();
      final commandBytes = utf8.encode(
        jsonEncode(<String, Object?>{
          'schema': backgroundCryptoFcmRefreshCommandSchema,
          'commandId': generation,
          'issuedAt': now
              .subtract(const Duration(seconds: 5))
              .toIso8601String(),
          'maxAgeSeconds': 120,
          'subjectTokenSha256': subjectHash,
        }),
      );
      final command = parseBackgroundCryptoFcmRefreshCommand(
        commandBytes,
        now: now,
      );
      expect(command.commandId, generation);
      expect(command.subjectTokenSha256, subjectHash);
      expect(command.rawSha256, sha256.convert(commandBytes).toString());
      expect(
        () => parseBackgroundCryptoFcmRefreshCommand(
          commandBytes,
          now: now.add(const Duration(minutes: 3)),
        ),
        throwsFormatException,
      );

      final bundle = _validBundle();
      const token = 'fresh-private-token';
      final priorHash = sha256
          .convert(utf8.encode('stale-private-token'))
          .toString();
      bundle
        ..['token'] = token
        ..['tokenMetadata'] = <String, Object?>{
          'schema': backgroundCryptoFcmTokenObservationSchema,
          'source': 'forced_reregistration',
          'observedAt': now.toIso8601String(),
          'generationId': generation,
          'tokenSha256': sha256.convert(utf8.encode(token)).toString(),
          'priorTokenSha256': priorHash,
          'refreshSignal': 'poll',
        };
      final observation = parseBackgroundCryptoFcmTokenObservation(
        bundle,
        expectedGenerationId: generation,
        expectedPriorTokenSha256: subjectHash,
        requireForcedRefresh: true,
        now: now,
      );
      expect(observation['tokenSha256'], isNot(priorHash));
      expect(
        backgroundCryptoFcmRefreshSubjectMatches(
          currentToken: 'stale-private-token',
          subjectTokenSha256: subjectHash,
        ),
        isTrue,
      );
      expect(
        backgroundCryptoFcmRefreshSubjectMatches(
          currentToken: token,
          subjectTokenSha256: subjectHash,
        ),
        isFalse,
        reason: 'the rotated token makes the same command non-replayable',
      );

      (bundle['tokenMetadata']! as Map<String, Object?>)['generationId'] =
          '${generation}9';
      expect(
        () => parseBackgroundCryptoFcmTokenObservation(
          bundle,
          expectedGenerationId: generation,
          expectedPriorTokenSha256: subjectHash,
          requireForcedRefresh: true,
          now: now,
        ),
        throwsFormatException,
      );
      (bundle['tokenMetadata']! as Map<String, Object?>)
        ..['generationId'] = generation
        ..['priorTokenSha256'] = sha256
            .convert(utf8.encode('tampered-prior-token'))
            .toString();
      expect(
        () => parseBackgroundCryptoFcmTokenObservation(
          bundle,
          expectedGenerationId: generation,
          expectedPriorTokenSha256: subjectHash,
          requireForcedRefresh: true,
          now: now,
        ),
        throwsFormatException,
      );
    },
  );

  test('only exact sanitized UNREGISTERED artifact authorizes refresh', () {
    final artifact = _validUnregisteredProviderArtifact();
    expect(
      parseBackgroundCryptoUnregisteredDiagnosticAuthorization(
        artifact,
        now: DateTime.utc(2026, 7, 13, 12, 5),
      ),
      containsPair('reason', 'UNREGISTERED'),
    );
    expect(
      () => parseBackgroundCryptoUnregisteredDiagnosticAuthorization(
        artifact,
        now: DateTime.utc(2026, 7, 13, 12, 31),
      ),
      throwsFormatException,
    );
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (value) => value['deliveryAttempted'] = true,
      (value) => value['schema'] = 'mknoon.android-provider-diagnostic.v1',
      (value) => value['providerValidationAttempts'] = 2,
      (value) => value['subjectTokenSha256'] = 'wrong-device-token',
      (value) => (value['providerDiagnostic'] as Map)['httpStatus'] = 400,
      (value) => (value['providerDiagnostic'] as Map)['reason'] = 'UNKNOWN',
      (value) => (value['cleanup'] as Map)['fixtureDbRowsRemaining'] = 1,
      (value) => value['unexpected'] = true,
    ]) {
      final changed = jsonDecode(jsonEncode(artifact)) as Map<String, dynamic>;
      mutation(changed);
      expect(
        () => parseBackgroundCryptoUnregisteredDiagnosticAuthorization(
          changed,
          now: DateTime.utc(2026, 7, 13, 12, 5),
        ),
        throwsFormatException,
      );
    }
  });

  test('fallback cleanup detects refresh residue and becomes idempotent', () {
    final verifiedAbsence = <String, int>{
      for (final path in backgroundCryptoRecoveryPrivateArtifactPaths) path: 0,
    };
    expect(
      backgroundCryptoRecoveryFallbackIsVerified(
        removalExitCode: 0,
        absenceProbeExitCodes: verifiedAbsence,
      ),
      isTrue,
    );
    expect(
      backgroundCryptoRecoveryFallbackIsVerified(
        removalExitCode: 23,
        absenceProbeExitCodes: verifiedAbsence,
      ),
      isFalse,
      reason: 'a failed rm transport cannot be treated as cleanup',
    );
    expect(
      backgroundCryptoRecoveryFallbackIsVerified(
        removalExitCode: 0,
        absenceProbeExitCodes: <String, int>{
          ...verifiedAbsence,
          backgroundCryptoAppPrivateFcmRefreshCommandPath: 1,
        },
      ),
      isFalse,
      reason: 'a surviving command or probe error blocks restoration closure',
    );
    expect(
      () => backgroundCryptoRecoveryFallbackIsVerified(
        removalExitCode: 0,
        absenceProbeExitCodes: <String, int>{},
      ),
      throwsArgumentError,
    );
  });

  test(
    'ordinary-only bundle validation never requires or parses reaction data',
    () {
      final missing = _copy(_validBundle())..remove('reaction');
      expect(
        validateBackgroundCryptoPreflightBundle(
          missing,
          requireReaction: false,
        ),
        isEmpty,
      );
      expect(
        validateBackgroundCryptoPreflightBundle(missing),
        contains(contains('bundle.reaction.data must be an object')),
      );
      expect(
        validateBackgroundCryptoPreflightBundle(missing, requireReaction: null),
        isEmpty,
      );

      for (final reaction in <Object?>[
        null,
        'private-malformed-reaction',
        <String, Object?>{
          'data': <String, Object?>{
            'type': <String, String>{'secret': 'must-not-be-parsed'},
          },
        },
      ]) {
        final bundle = _copy(_validBundle())..['reaction'] = reaction;
        expect(
          validateBackgroundCryptoPreflightBundle(
            bundle,
            requireReaction: false,
          ),
          isEmpty,
        );
        expect(
          validateBackgroundCryptoPreflightBundle(
            bundle,
            requireReaction: null,
          ),
          isNotEmpty,
        );
      }
    },
  );

  test('private bundle validator rejects actor and parity drift', () {
    final unreservedReaction = _copy(_validBundle());
    final unreservedReactionData =
        (unreservedReaction['reaction']! as Map<String, dynamic>)['data']!
            as Map<String, dynamic>;
    unreservedReactionData['event_id'] = 'real-reaction';
    expect(
      validateBackgroundCryptoPreflightBundle(unreservedReaction),
      contains(contains('reserved reaction prefix')),
    );

    final unreservedMessage = _copy(_validBundle());
    final unreservedDirect = (unreservedMessage['ordinaryCases']! as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((row) => row['context'] == 'direct');
    unreservedDirect['messageId'] = 'real-message';
    (unreservedDirect['data']! as Map<String, dynamic>)['message_id'] =
        'real-message';
    expect(
      validateBackgroundCryptoPreflightBundle(unreservedMessage),
      contains(contains('messageId must use tc256-direct-')),
    );

    final groupSender = _copy(_validBundle());
    final groupCase = (groupSender['ordinaryCases']! as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((row) => row['context'] == 'group');
    (groupCase['data']! as Map<String, dynamic>)['sender_id'] = 'untrusted';
    expect(
      validateBackgroundCryptoPreflightBundle(groupSender),
      contains(contains('sender_id must be omitted')),
    );

    final directWithoutSender = _copy(_validBundle());
    final directCase = (directWithoutSender['ordinaryCases']! as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((row) => row['context'] == 'direct');
    (directCase['data']! as Map<String, dynamic>).remove('sender_id');
    expect(
      validateBackgroundCryptoPreflightBundle(directWithoutSender),
      contains(contains('sender_id is required')),
    );

    final groupWithoutTransport = _copy(_validBundle());
    final transportCase = (groupWithoutTransport['ordinaryCases']! as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((row) => row['context'] == 'group');
    (transportCase['data']! as Map<String, dynamic>).remove(
      'sender_transport_peer_id',
    );
    expect(
      validateBackgroundCryptoPreflightBundle(groupWithoutTransport),
      contains(contains('sender_transport_peer_id must equal')),
    );

    final accountTransportAlias = _copy(_validBundle());
    final aliasedCase = (accountTransportAlias['ordinaryCases']! as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((row) => row['context'] == 'announcement');
    (aliasedCase['data']! as Map<String, dynamic>)['sender_transport_peer_id'] =
        backgroundCryptoPreflightActorPeerId;
    expect(
      validateBackgroundCryptoPreflightBundle(accountTransportAlias),
      contains(contains('reserved active device transport')),
    );

    final wrongMessage = _copy(_validBundle());
    final firstCase = (wrongMessage['ordinaryCases']! as List).first as Map;
    (firstCase['data']! as Map)['message_id'] = 'different-message';
    expect(
      validateBackgroundCryptoPreflightBundle(wrongMessage),
      contains(contains('data.message_id must equal')),
    );

    final selfFulfilledRoute = _copy(_validBundle());
    final routedGroup = (selfFulfilledRoute['ordinaryCases']! as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((row) => row['context'] == 'announcement');
    routedGroup['expectedPayload'] = 'group:attacker|message:attacker';
    expect(
      validateBackgroundCryptoPreflightBundle(selfFulfilledRoute),
      contains(
        contains(
          'expectedPayload must equal '
          'group:tc256-preflight-announcement',
        ),
      ),
    );

    final missingCrypto = _copy(_validBundle());
    final encryptedDirect = (missingCrypto['ordinaryCases']! as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((row) => row['context'] == 'direct');
    (encryptedDirect['data']! as Map<String, dynamic>).remove('nonce');
    expect(
      validateBackgroundCryptoPreflightBundle(missingCrypto),
      contains(contains('data.nonce must be non-empty')),
    );

    final duplicateMessage = _copy(_validBundle());
    final cases = (duplicateMessage['ordinaryCases']! as List)
        .cast<Map<String, dynamic>>();
    final duplicateId = cases.first['messageId']! as String;
    cases[1]['messageId'] = duplicateId;
    (cases[1]['data']! as Map<String, dynamic>)['message_id'] = duplicateId;
    expect(
      validateBackgroundCryptoPreflightBundle(duplicateMessage),
      contains(contains('duplicate ordinary messageId')),
    );
  });

  test('private bundle validator rejects malformed reaction crypto', () {
    final bundle = _copy(_validBundle());
    final reaction = bundle['reaction']! as Map<String, dynamic>;
    final data = reaction['data']! as Map<String, dynamic>;
    data
      ..['type'] = 'new_message'
      ..remove('kem');
    final errors = validateBackgroundCryptoPreflightBundle(bundle);
    expect(errors, contains(contains('type must equal message_reaction')));
    expect(errors, contains(contains('data.kem must be non-empty')));
  });

  test('private bundle validator locks the three authorization rejections', () {
    final missingWithTransport = _copy(_validBundle());
    final missingCase = (missingWithTransport['negativeCases']! as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((row) => row['rejectionReason'] == 'missing_transport');
    (missingCase['data']! as Map<String, dynamic>)['sender_transport_peer_id'] =
        backgroundCryptoPreflightActorTransportPeerId;
    expect(
      validateBackgroundCryptoPreflightBundle(missingWithTransport),
      contains(contains('must omit sender_transport_peer_id')),
    );

    final writerUsingAdminTransport = _copy(_validBundle());
    final writerCase = (writerUsingAdminTransport['negativeCases']! as List)
        .cast<Map<String, dynamic>>()
        .firstWhere(
          (row) => row['rejectionReason'] == 'non_admin_announcement',
        );
    (writerCase['data']! as Map<String, dynamic>)['sender_transport_peer_id'] =
        backgroundCryptoPreflightActorTransportPeerId;
    expect(
      validateBackgroundCryptoPreflightBundle(writerUsingAdminTransport),
      contains(contains('reserved non-admin transport')),
    );

    final missingRow = _copy(_validBundle());
    (missingRow['negativeCases']! as List).removeLast();
    expect(
      validateBackgroundCryptoPreflightBundle(missingRow),
      contains(contains('must contain exactly 3 rows')),
    );
  });

  test('Pixel notification parser retains ID and Android msg category', () {
    const dump = '''
NotificationRecord(0x123: pkg=com.mknoon.app user=UserHandle{0} id=42 tag=null category=msg)
  android.title=String (TC256 Trusted Group)
  android.text=String (Photo)
Ranking Config:
''';
    final cards = extractActiveNotificationCards(
      dump,
      packageName: 'com.mknoon.app',
    );
    expect(cards, hasLength(1));
    expect(cards.single.id, 42);
    expect(cards.single.category, 'msg');
    expect(cards.single.title, 'TC256 Trusted Group');
    expect(cards.single.body, 'Photo');
  });

  test('reset baselines unrelated cards but rejects every fixture signal', () {
    const unrelated = ActiveNotificationCard(
      id: 7,
      title: 'Ordinary app notice',
      body: 'Unrelated body',
      category: 'status',
    );
    const reservedTitle = ActiveNotificationCard(
      id: 8,
      title: backgroundCryptoPreflightDirectTrustedTitle,
      body: 'Photo',
    );
    const reservedBody = ActiveNotificationCard(
      id: 9,
      title: 'Other',
      body: 'TC256 encrypted direct text',
    );
    const reservedRoute = ActiveNotificationCard(
      id: 10,
      title: 'Other',
      body: 'Other',
      routePayload: backgroundCryptoPreflightActorPeerId,
    );
    const knownId = ActiveNotificationCard(
      id: 11,
      title: 'Other',
      body: 'Other',
    );
    final reset = classifyBackgroundCryptoNotificationReset(
      const <ActiveNotificationCard>[
        unrelated,
        reservedTitle,
        reservedBody,
        reservedRoute,
        knownId,
      ],
      knownFixtureIds: const <int>{11},
    );
    expect(reset.fixtureCards, <ActiveNotificationCard>[
      reservedTitle,
      reservedBody,
      reservedRoute,
      knownId,
    ]);
    expect(reset.baselineIds, <int>{7});
    expect(reset.baselineHash, sha256.convert(utf8.encode('7')).toString());

    const newFixture = ActiveNotificationCard(
      id: 12,
      title: backgroundCryptoPreflightGroupTrustedTitle,
      body: 'TC256 Alice: Photo',
      category: 'msg',
    );
    expect(
      backgroundCryptoCardsOutsideBaseline(const <ActiveNotificationCard>[
        unrelated,
        newFixture,
      ], baselineIds: reset.baselineIds),
      <ActiveNotificationCard>[newFixture],
    );
    expect(
      backgroundCryptoFixtureNotificationOwnership(reservedTitle).reasons,
      <BackgroundCryptoFixtureNotificationOwnershipReason>{
        BackgroundCryptoFixtureNotificationOwnershipReason.copy,
      },
    );
    expect(
      backgroundCryptoFixtureNotificationOwnership(reservedRoute).reasons,
      <BackgroundCryptoFixtureNotificationOwnershipReason>{
        BackgroundCryptoFixtureNotificationOwnershipReason.route,
      },
    );
    expect(
      backgroundCryptoFixtureNotificationOwnership(
        knownId,
        knownFixtureIds: const <int>{11},
      ).reasons,
      <BackgroundCryptoFixtureNotificationOwnershipReason>{
        BackgroundCryptoFixtureNotificationOwnershipReason.knownId,
      },
    );
  });

  test('host and device ownership is strict and collision-safe', () {
    const payloadNullFixture = ActiveNotificationCard(
      id: 51,
      title: backgroundCryptoPreflightDirectTrustedTitle,
      body: 'Photo',
    );
    const unrelatedSamePackage = ActiveNotificationCard(
      id: 52,
      title: 'TC256 Weather',
      body: 'Photo',
      routePayload: 'group:tc256-preflight-group-not-fixture',
    );
    const idCollision = ActiveNotificationCard(
      id: 53,
      title: 'Normal app notice',
      body: 'Unrelated body',
    );
    expect(
      backgroundCryptoFixtureNotificationOwnership(payloadNullFixture).isOwned,
      isTrue,
    );
    expect(
      backgroundCryptoFixtureNotificationOwnership(
        unrelatedSamePackage,
      ).isOwned,
      isFalse,
    );
    expect(
      backgroundCryptoFixtureNotificationOwnership(idCollision).isOwned,
      isFalse,
    );
    expect(
      backgroundCryptoFixtureNotificationOwnership(
        idCollision,
        knownFixtureIds: const <int>{53},
      ).reasons,
      <BackgroundCryptoFixtureNotificationOwnershipReason>{
        BackgroundCryptoFixtureNotificationOwnershipReason.knownId,
      },
    );
    final snapshot = classifyBackgroundCryptoNotificationReset(
      const <ActiveNotificationCard>[
        payloadNullFixture,
        unrelatedSamePackage,
        idCollision,
      ],
    );
    expect(snapshot.fixtureCards, <ActiveNotificationCard>[payloadNullFixture]);
    expect(snapshot.baselineIds, <int>{52, 53});

    final app = File(
      'integration_test/android_background_crypto_preflight_app.dart',
    ).readAsStringSync();
    final support = File(
      'integration_test/scripts/reaction_notification_proof_support.dart',
    ).readAsStringSync();
    final clear = app.indexOf(
      'Future<Map<String, int>> _clearSyntheticNotifications(',
    );
    final count = app.indexOf(
      'Future<Map<String, int>> _countSyntheticNotifications(',
      clear,
    );
    final sharedOwnership = app.indexOf(
      'backgroundCryptoFixtureNotificationOwnership(',
      clear,
    );
    final indexValidation = app.indexOf(
      'validateBackgroundCryptoCleanupIndex(',
      count,
    );
    final ownerBinding = app.indexOf(
      '_syntheticConversationOwnerHashes()',
      indexValidation,
    );
    expect(clear, greaterThan(0));
    expect(count, greaterThan(clear));
    expect(sharedOwnership, greaterThan(clear));
    expect(sharedOwnership, lessThan(count));
    expect(indexValidation, greaterThan(count));
    expect(ownerBinding, greaterThan(indexValidation));
    expect(
      support,
      allOf(
        contains('fixtureNotificationRouteOwnedCardsRemaining'),
        contains('fixtureNotificationCopyOwnedCardsRemaining'),
        contains('fixtureNotificationKnownIdOwnedCardsRemaining'),
      ),
    );
  });

  test('notification reset convergence handles injected snapshot sequences', () {
    const fixture = ActiveNotificationCard(
      id: 21,
      title: backgroundCryptoPreflightDirectTrustedTitle,
      body: 'Photo',
    );
    const unrelatedA = ActiveNotificationCard(
      id: 31,
      title: 'Unrelated A',
      body: 'Background sync',
    );
    const unrelatedB = ActiveNotificationCard(
      id: 32,
      title: 'Unrelated B',
      body: 'Background sync',
    );

    final fixtureThenGone = convergedBackgroundCryptoNotificationReset(
      const <List<ActiveNotificationCard>>[
        <ActiveNotificationCard>[fixture],
        <ActiveNotificationCard>[unrelatedA],
        <ActiveNotificationCard>[unrelatedA],
      ],
    );
    expect(fixtureThenGone, isNotNull);
    expect(fixtureThenGone!.baselineIds, <int>{31});

    expect(
      convergedBackgroundCryptoNotificationReset(
        const <List<ActiveNotificationCard>>[
          <ActiveNotificationCard>[fixture],
          <ActiveNotificationCard>[fixture],
          <ActiveNotificationCard>[fixture],
        ],
      ),
      isNull,
    );
    expect(
      convergedBackgroundCryptoNotificationReset(
        const <List<ActiveNotificationCard>>[
          <ActiveNotificationCard>[unrelatedA],
          <ActiveNotificationCard>[unrelatedB],
          <ActiveNotificationCard>[unrelatedA],
        ],
      ),
      isNull,
    );
    final stableUnrelated = convergedBackgroundCryptoNotificationReset(
      const <List<ActiveNotificationCard>>[
        <ActiveNotificationCard>[unrelatedA, unrelatedB],
        <ActiveNotificationCard>[unrelatedB, unrelatedA],
      ],
    );
    expect(stableUnrelated, isNotNull);
    expect(stableUnrelated!.baselineIds, <int>{31, 32});

    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    final convergence = controller.indexOf(
      '_waitForNotificationResetConvergence() async',
    );
    final convergenceCall = controller.indexOf(
      'final reset = await _waitForNotificationResetConvergence()',
    );
    final deadline = controller.indexOf(
      'const Duration(seconds: 5)',
      convergence,
    );
    final poll = controller.indexOf(
      'const Duration(milliseconds: 200)',
      deadline,
    );
    final commit = controller.indexOf(
      '_baselineNotificationIds = reset.baselineIds',
    );
    expect(convergence, greaterThan(0));
    expect(convergenceCall, greaterThan(0));
    expect(commit, greaterThan(convergenceCall));
    expect(deadline, greaterThan(convergence));
    expect(poll, greaterThan(deadline));
    expect(commit, lessThan(convergence));
  });

  test(
    'notification reset rejects late match and never-returning poll',
    () async {
      const unrelated = ActiveNotificationCard(
        id: 41,
        title: 'Unrelated',
        body: 'Background sync',
      );
      final startedAt = DateTime.utc(2026, 7, 13);
      var clock = startedAt;
      var polls = 0;
      final lateMatch =
          await waitForBackgroundCryptoNotificationResetConvergence(
            poll: () async {
              polls++;
              clock = startedAt.add(
                Duration(milliseconds: polls == 1 ? 4700 : 5100),
              );
              return const <ActiveNotificationCard>[unrelated];
            },
            timeout: const Duration(seconds: 5),
            interval: const Duration(milliseconds: 200),
            now: () => clock,
            delay: (duration) async {
              clock = clock.add(duration);
            },
            withinBudget: (operation, remaining) => operation,
          );
      expect(polls, 2);
      expect(lateMatch, isNull);

      final never = Completer<List<ActiveNotificationCard>>();
      Duration? observedBudget;
      final timedOut =
          await waitForBackgroundCryptoNotificationResetConvergence(
            poll: () => never.future,
            timeout: const Duration(seconds: 5),
            interval: const Duration(milliseconds: 200),
            now: () => startedAt,
            delay: (_) async {},
            withinBudget: (operation, remaining) {
              observedBudget = remaining;
              return Future<List<ActiveNotificationCard>>.error(
                TimeoutException('injected bounded poll'),
              );
            },
          );
      expect(observedBudget, const Duration(seconds: 5));
      expect(timedOut, isNull);
    },
  );

  test('shown-flow parser returns the latest anchored route payload', () {
    const log = '''
I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN","details":{"payload":"peer-old"}}
I/flutter: [FLOW] {"event":"OTHER","details":{}}
I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN","details":{"payload":"group:trusted|message:m-2"}}
''';
    expect(
      extractBackgroundNotificationShownPayload(log),
      'group:trusted|message:m-2',
    );
  });

  test(
    'authorization rejection proof rejects every downstream marker family',
    () {
      const reason = 'group_message_local_state_ineligible';
      const terminalSuppression =
          '''
PUSH_BACKGROUND_MESSAGE_RECEIVED
PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED reason=$reason
''';
      expect(
        backgroundCryptoExpectedAuthorizationSuppressionObserved(
          terminalSuppression,
          reason: reason,
        ),
        isTrue,
      );
      expect(
        backgroundCryptoForbiddenAuthorizationStageFamilies(
          terminalSuppression,
        ),
        isEmpty,
      );

      const counterexamples = <String, String>{
        'PUSH_BACKGROUND_ENVELOPE_STAGE_ERROR': 'envelope_staging',
        'PUSH_BACKGROUND_MESSAGE_CLAIM_STORAGE_UNAVAILABLE': 'claim_or_tone',
        'PUSH_BACKGROUND_MESSAGE_CLAIM_ATTEMPTED': 'claim_or_tone',
        'PUSH_BACKGROUND_MESSAGE_CLAIM_COMMIT_FAILED': 'claim_or_tone',
        'PUSH_BACKGROUND_MESSAGE_CLAIM_RELEASE_FAILED': 'claim_or_tone',
        'PUSH_BACKGROUND_MESSAGE_TONE_STORAGE_UNAVAILABLE': 'claim_or_tone',
        'PUSH_BACKGROUND_MESSAGE_TONE_ATTEMPTED': 'claim_or_tone',
        'PUSH_BACKGROUND_MESSAGE_TONE_COMMIT_FAILED': 'claim_or_tone',
        'PUSH_BACKGROUND_MESSAGE_TONE_RELEASE_FAILED': 'claim_or_tone',
        'PUSH_BACKGROUND_MESSAGE_CRYPTO_PLUGIN_OK': 'crypto_or_decrypt',
        'PUSH_BACKGROUND_MESSAGE_CRYPTO_PLUGIN_REJECTED': 'crypto_or_decrypt',
        'PUSH_ANDROID_DATA_DECRYPT_OK': 'crypto_or_decrypt',
        'PUSH_ANDROID_DATA_DECRYPT_FAIL': 'crypto_or_decrypt',
        'PUSH_BACKGROUND_NOTIFICATION_ID_ALLOCATION_UNAVAILABLE':
            'notification_id_allocation',
        'PUSH_BACKGROUND_NOTIFICATION_ID_ALLOCATION_ATTEMPTED':
            'notification_id_allocation',
        'PUSH_BACKGROUND_NOTIFICATION_SHOWN':
            'os_show_or_notification_pipeline',
        'PUSH_BACKGROUND_NOTIFICATION_ERROR':
            'os_show_or_notification_pipeline',
      };
      for (final entry in counterexamples.entries) {
        expect(
          backgroundCryptoForbiddenAuthorizationStageFamilies(
            '$terminalSuppression\n${entry.key}',
          ),
          contains(entry.value),
          reason: entry.key,
        );
      }
      expect(
        backgroundCryptoExpectedAuthorizationSuppressionObserved(
          'PUSH_BACKGROUND_MESSAGE_RECEIVED\n'
          'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED reason=other\n'
          'OTHER reason=$reason',
          reason: reason,
        ),
        isFalse,
      );
    },
  );

  test('both dedupe gates round-trip byte-for-byte including absence', () {
    const background = 'mknoon_recent_background_notifications.json';
    const remote = 'mknoon_recent_remote_notifications.json';
    final encoded = encodeBackgroundCryptoFileBaselines(<String, List<int>?>{
      background: <int>[0, 1, 127, 128, 255],
      remote: null,
    });
    final decoded = decodeBackgroundCryptoFileBaselines(
      jsonDecode(jsonEncode(encoded)),
      expectedFileNames: const <String>{background, remote},
    );
    expect(decoded[background], <int>[0, 1, 127, 128, 255]);
    expect(decoded[remote], isNull);

    final malformed = jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
    (malformed['files']! as Map).remove(remote);
    expect(
      () => decodeBackgroundCryptoFileBaselines(
        malformed,
        expectedFileNames: const <String>{background, remote},
      ),
      throwsFormatException,
    );
  });

  test('Activity parser rejects attached paused and resumed Activities', () {
    const detached = '''
* Hist #0: ActivityRecord{abc u0 com.mknoon.app/.MainActivity t42}
  app=null
''';
    const attachedPaused = '''
* Hist #0: ActivityRecord{abc u0 com.mknoon.app/.MainActivity t42}
  state=PAUSED
  app=ProcessRecord{def 1234:com.mknoon.app/u0a123}
''';
    const resumed = '''
mResumedActivity: ActivityRecord{abc u0 com.mknoon.app/.MainActivity t42}
''';
    const detachedThenAttached = '''
* Hist #1: ActivityRecord{abc u0 com.mknoon.app/.MainActivity t41}
  app=null
* Hist #0: ActivityRecord{def u0 com.mknoon.app/.MainActivity t42}
  state=STOPPED
  app=ProcessRecord{ghi 1234:com.mknoon.app/u0a123}
''';
    expect(
      androidActivityIsAttached(detached, packageName: 'com.mknoon.app'),
      isFalse,
    );
    expect(
      androidActivityIsAttached(attachedPaused, packageName: 'com.mknoon.app'),
      isTrue,
    );
    expect(
      androidActivityIsAttached(resumed, packageName: 'com.mknoon.app'),
      isTrue,
    );
    expect(
      androidActivityIsAttached(
        detachedThenAttached,
        packageName: 'com.mknoon.app',
      ),
      isTrue,
    );
  });

  test(
    'package stopped-state parser rejects stopped or ambiguous delivery',
    () {
      const eligible = '''
Packages:
  Package [com.mknoon.app] (abc123):
    userId=10123
    User 0: ceDataInode=42 installed=true hidden=false stopped=false enabled=0
''';
      const stopped = '''
Packages:
  Package [com.mknoon.app] (abc123):
    userId=10123
    User 0: ceDataInode=42 installed=true hidden=false stopped=true enabled=0
''';
      expect(
        androidPackageStoppedForUser(
          eligible,
          packageName: 'com.mknoon.app',
          userId: 0,
        ),
        isFalse,
      );
      expect(
        androidPackageStoppedForUser(
          stopped,
          packageName: 'com.mknoon.app',
          userId: 0,
        ),
        isTrue,
      );
      expect(
        () => androidPackageStoppedForUser(
          eligible,
          packageName: 'com.other.app',
          userId: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => androidPackageStoppedForUser(
          eligible,
          packageName: 'com.mknoon.app',
          userId: 10,
        ),
        throwsFormatException,
      );
      expect(
        () => androidPackageStoppedForUser(
          eligible.replaceFirst('stopped=false', 'enabled=0'),
          packageName: 'com.mknoon.app',
          userId: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => androidPackageStoppedForUser(
          '$eligible\n    User 0: installed=true stopped=false enabled=0',
          packageName: 'com.mknoon.app',
          userId: 0,
        ),
        throwsFormatException,
      );
    },
  );

  test('process/task quiescence rejects PID and task bring-forward races', () {
    const attachedTask = '''
* Hist #0: ActivityRecord{abc u0 com.mknoon.app/.MainActivity t42}
  state=STOPPED
  app=ProcessRecord{def 1234:com.mknoon.app/u0a123}
''';
    const detachedHistory = '''
* Hist #0: ActivityRecord{abc u0 com.mknoon.app/.MainActivity t42}
  app=null
''';
    expect(
      androidProcessAndTaskAreAbsent(
        pidExitCode: 1,
        pidOutput: '',
        pidStderr: '',
        activityDump: attachedTask,
        packageName: 'com.mknoon.app',
      ),
      isFalse,
    );
    expect(
      androidProcessAndTaskAreAbsent(
        pidExitCode: 0,
        pidOutput: '1234',
        pidStderr: '',
        activityDump: detachedHistory,
        packageName: 'com.mknoon.app',
      ),
      isFalse,
    );
    expect(
      androidProcessAndTaskAreAbsent(
        pidExitCode: 1,
        pidOutput: '',
        pidStderr: '',
        activityDump: detachedHistory,
        packageName: 'com.mknoon.app',
      ),
      isTrue,
    );
    expect(
      androidProcessAndTaskAreAbsent(
        pidExitCode: 127,
        pidOutput: '',
        pidStderr: 'pidof: not found',
        activityDump: detachedHistory,
        packageName: 'com.mknoon.app',
      ),
      isFalse,
    );
    expect(
      androidProcessAndTaskAreAbsent(
        pidExitCode: 0,
        pidOutput: '',
        pidStderr: '',
        activityDump: detachedHistory,
        packageName: 'com.mknoon.app',
      ),
      isFalse,
    );
  });

  test(
    'cleanup command transport preserves bytes and exact adb boundaries',
    () async {
      final commandBytes = utf8.encode(
        jsonEncode(<String, Object?>{
          'schema': 'mknoon.tc256-cleanup-command.v1',
          'commandId': r'''id with spaces & | > < $() ; ' " \n snowman ☃''',
          'mode': 'cleanup-only',
        }),
      );
      final expectedHash = sha256.convert(commandBytes).toString();
      final invocations = <BackgroundCryptoTransportInvocation>[];
      List<int>? pushedBytes;
      String? hostStageFile;
      String? deviceStage;

      Future<BackgroundCryptoTransportResult> run(
        BackgroundCryptoTransportInvocation invocation,
      ) async {
        invocations.add(invocation);
        if (invocation.channel == BackgroundCryptoTransportChannel.adb &&
            invocation.arguments.first == 'push') {
          hostStageFile = invocation.arguments[1];
          deviceStage = invocation.arguments[2];
          pushedBytes = await File(invocation.arguments[1]).readAsBytes();
        }
        if (invocation.arguments.first == 'sha256sum') {
          return BackgroundCryptoTransportResult(
            exitCode: 0,
            stdout: '$expectedHash  ${invocation.arguments.last}\n',
          );
        }
        return const BackgroundCryptoTransportResult(exitCode: 0);
      }

      final receipt = await copyBackgroundCryptoCommandBytesToAppPrivateFile(
        bytes: commandBytes,
        run: run,
      );

      expect(pushedBytes, commandBytes);
      expect(receipt.byteLength, commandBytes.length);
      expect(receipt.sha256, expectedHash);
      expect(hostStageFile, isNotNull);
      expect(deviceStage, isNotNull);
      expect(hostStageFile, contains('mknoon tc256 command owned-'));
      expect(isBackgroundCryptoOwnedDeviceStagePath(deviceStage!), isTrue);
      expect(
        await File(hostStageFile!).parent.exists(),
        isFalse,
        reason: 'the internally owned host directory must be deleted',
      );
      final expectedInvocations =
          <(BackgroundCryptoTransportChannel, List<String>)>[
            (
              BackgroundCryptoTransportChannel.adb,
              <String>['push', hostStageFile!, deviceStage!],
            ),
            (
              BackgroundCryptoTransportChannel.shell,
              <String>['chmod', '0644', deviceStage!],
            ),
            (
              BackgroundCryptoTransportChannel.shell,
              <String>['sha256sum', deviceStage!],
            ),
            (
              BackgroundCryptoTransportChannel.runAs,
              <String>['mkdir', '-p', 'files'],
            ),
            (
              BackgroundCryptoTransportChannel.runAs,
              <String>[
                'cp',
                deviceStage!,
                backgroundCryptoAppPrivateCommandPath,
              ],
            ),
            (
              BackgroundCryptoTransportChannel.runAs,
              <String>['sha256sum', backgroundCryptoAppPrivateCommandPath],
            ),
            (
              BackgroundCryptoTransportChannel.shell,
              <String>['rm', '-f', deviceStage!],
            ),
          ];
      expect(invocations, hasLength(expectedInvocations.length));
      for (var index = 0; index < expectedInvocations.length; index++) {
        expect(invocations[index].channel, expectedInvocations[index].$1);
        expect(invocations[index].arguments, expectedInvocations[index].$2);
      }
      final allArguments = invocations.expand(
        (invocation) => invocation.arguments,
      );
      expect(allArguments, isNot(contains('sh')));
      expect(allArguments, isNot(contains('-c')));
      expect(allArguments.any((argument) => argument.contains('|')), isFalse);
      expect(allArguments.any((argument) => argument.contains('>')), isFalse);
      expect(
        allArguments.any((argument) => argument.contains('commandId')),
        isFalse,
      );
    },
  );

  test(
    'cleanup command transport deletes staging after every failed leg',
    () async {
      final commandBytes = utf8.encode('{"special":"spaces | > ☃"}');
      final expectedHash = sha256.convert(commandBytes).toString();
      const stages = <String>[
        'device_stage_push',
        'device_stage_chmod',
        'device_stage_hash',
        'app_private_mkdir',
        'app_private_copy',
        'app_private_hash',
      ];

      for (var failedLeg = 0; failedLeg < stages.length; failedLeg++) {
        final invocations = <BackgroundCryptoTransportInvocation>[];
        var mainLeg = 0;
        String? hostStageFile;
        String? deviceStage;

        Future<BackgroundCryptoTransportResult> run(
          BackgroundCryptoTransportInvocation invocation,
        ) async {
          invocations.add(invocation);
          if (invocation.arguments.first == 'push') {
            hostStageFile = invocation.arguments[1];
            deviceStage = invocation.arguments[2];
          }
          if (invocation.arguments.first == 'rm') {
            return const BackgroundCryptoTransportResult(exitCode: 0);
          }
          final shouldFail = mainLeg++ == failedLeg;
          if (shouldFail) {
            return const BackgroundCryptoTransportResult(exitCode: 19);
          }
          if (invocation.arguments.first == 'sha256sum') {
            return BackgroundCryptoTransportResult(
              exitCode: 0,
              stdout: '$expectedHash  ${invocation.arguments.last}\n',
            );
          }
          return const BackgroundCryptoTransportResult(exitCode: 0);
        }

        await expectLater(
          copyBackgroundCryptoCommandBytesToAppPrivateFile(
            bytes: commandBytes,
            run: run,
          ),
          throwsA(
            isA<BackgroundCryptoStagedFileFailure>().having(
              (failure) => failure.primaryStage,
              'primaryStage',
              stages[failedLeg],
            ),
          ),
        );
        expect(invocations.last.arguments, <String>['rm', '-f', deviceStage!]);
        expect(await File(hostStageFile!).parent.exists(), isFalse);
      }
    },
  );

  test(
    'device staging cleanup failure still deletes the host staging file',
    () async {
      final commandBytes = utf8.encode('{"mode":"cleanup-only"}');
      final expectedHash = sha256.convert(commandBytes).toString();
      String? hostStageFile;

      Future<BackgroundCryptoTransportResult> run(
        BackgroundCryptoTransportInvocation invocation,
      ) async {
        if (invocation.arguments.first == 'push') {
          hostStageFile = invocation.arguments[1];
        }
        if (invocation.arguments.first == 'rm') {
          return const BackgroundCryptoTransportResult(exitCode: 20);
        }
        if (invocation.arguments.first == 'sha256sum') {
          return BackgroundCryptoTransportResult(
            exitCode: 0,
            stdout: '$expectedHash  ${invocation.arguments.last}\n',
          );
        }
        return const BackgroundCryptoTransportResult(exitCode: 0);
      }

      await expectLater(
        copyBackgroundCryptoCommandBytesToAppPrivateFile(
          bytes: commandBytes,
          run: run,
        ),
        throwsA(
          isA<BackgroundCryptoStagedFileFailure>()
              .having((failure) => failure.primaryStage, 'primaryStage', isNull)
              .having(
                (failure) => failure.cleanupStages,
                'cleanupStages',
                <String>['device_stage_delete'],
              ),
        ),
      );
      expect(await File(hostStageFile!).parent.exists(), isFalse);
    },
  );

  test('cleanup command transport exposes only fixed owned path forms', () {
    expect(
      isBackgroundCryptoOwnedDeviceStagePath(
        '/data/local/tmp/mknoon-tc256-command-'
        '0123456789abcdef0123456789abcdef.bin',
      ),
      isTrue,
    );
    for (final path in <String>[
      '/data/local/tmp/..',
      '/data/local/tmp/-command.bin',
      '/data/local/tmp/mknoon-tc256-command-../command.bin',
      '/data/local/tmp/mknoon-tc256-command-'
          '0123.bin',
      '/data/local/tmp/mknoon-tc256-command-'
          '0123456789abcdef0123456789abcdef.bin\n',
      '/sdcard/mknoon-tc256-command-'
          '0123456789abcdef0123456789abcdef.bin',
    ]) {
      expect(isBackgroundCryptoOwnedDeviceStagePath(path), isFalse);
    }
    expect(
      isBackgroundCryptoOwnedAppPrivateCommandPath(
        backgroundCryptoAppPrivateCommandPath,
      ),
      isTrue,
    );
    expect(
      isBackgroundCryptoOwnedAppPrivateCommandPath(
        backgroundCryptoAppPrivateFcmRefreshCommandPath,
      ),
      isTrue,
    );
    for (final path in <String>[
      '.',
      '..',
      '-tc256_post_foreground',
      '/data/user/0/com.mknoon.app/files/tc256_post_foreground',
      'files/../tc256_post_foreground',
      'files/tc256_post_foreground/extra',
      'files/tc256_fcm_refresh_command.json/extra',
    ]) {
      expect(isBackgroundCryptoOwnedAppPrivateCommandPath(path), isFalse);
    }
  });

  test(
    'transport runner throws and hash tampering remain causal failures',
    () async {
      final bytes = utf8.encode('{"mode":"cleanup-only"}');
      final expectedHash = sha256.convert(bytes).toString();

      for (final hashFailure in <String>[
        'device_stage_hash',
        'app_private_hash',
      ]) {
        String? hostStageFile;
        var hashIndex = 0;
        await expectLater(
          copyBackgroundCryptoCommandBytesToAppPrivateFile(
            bytes: bytes,
            run: (invocation) async {
              if (invocation.arguments.first == 'push') {
                hostStageFile = invocation.arguments[1];
              }
              if (invocation.arguments.first == 'sha256sum') {
                final currentStage = hashIndex++ == 0
                    ? 'device_stage_hash'
                    : 'app_private_hash';
                return BackgroundCryptoTransportResult(
                  exitCode: 0,
                  stdout:
                      '${currentStage == hashFailure ? '0' * 64 : expectedHash}  '
                      '${invocation.arguments.last}\n',
                );
              }
              return const BackgroundCryptoTransportResult(exitCode: 0);
            },
          ),
          throwsA(
            isA<BackgroundCryptoStagedFileFailure>().having(
              (failure) => failure.primaryStage,
              'primaryStage',
              hashFailure,
            ),
          ),
        );
        expect(await File(hostStageFile!).parent.exists(), isFalse);
      }

      String? thrownHostStageFile;
      await expectLater(
        copyBackgroundCryptoCommandBytesToAppPrivateFile(
          bytes: bytes,
          run: (invocation) async {
            if (invocation.arguments.first == 'push') {
              thrownHostStageFile = invocation.arguments[1];
            }
            if (invocation.arguments.first == 'chmod') {
              throw StateError('synthetic runner failure');
            }
            return const BackgroundCryptoTransportResult(exitCode: 0);
          },
        ),
        throwsA(
          isA<BackgroundCryptoStagedFileFailure>()
              .having(
                (failure) => failure.primaryStage,
                'primaryStage',
                'device_stage_chmod',
              )
              .having(
                (failure) => failure.primaryType,
                'primaryType',
                'StateError',
              ),
        ),
      );
      expect(await File(thrownHostStageFile!).parent.exists(), isFalse);
    },
  );

  test('host staging write failure cleans only the owned directory', () async {
    Set<String> ownedStagePaths() => Directory.systemTemp
        .listSync()
        .whereType<Directory>()
        .map((directory) => directory.path)
        .where((path) => path.contains('mknoon tc256 command owned-'))
        .toSet();

    final before = ownedStagePaths();
    final invocations = <BackgroundCryptoTransportInvocation>[];
    await expectLater(
      copyBackgroundCryptoCommandBytesToAppPrivateFile(
        bytes: _FailOnSecondTraversalBytes(<int>[1, 2, 3, 4]),
        run: (invocation) async {
          invocations.add(invocation);
          return const BackgroundCryptoTransportResult(exitCode: 0);
        },
      ),
      throwsA(
        isA<BackgroundCryptoStagedFileFailure>().having(
          (failure) => failure.primaryStage,
          'primaryStage',
          'host_stage_write',
        ),
      ),
    );
    expect(ownedStagePaths(), before);
    expect(invocations, hasLength(1));
    expect(invocations.single.channel, BackgroundCryptoTransportChannel.shell);
    expect(invocations.single.arguments.take(2), <String>['rm', '-f']);
    expect(
      isBackgroundCryptoOwnedDeviceStagePath(invocations.single.arguments.last),
      isTrue,
    );
  });

  test('host staging owner tamper fails closed without deleting it', () async {
    final bytes = utf8.encode('{"mode":"cleanup-only"}');
    final expectedHash = sha256.convert(bytes).toString();
    Directory? ownedDirectory;

    addTearDown(() async {
      final directory = ownedDirectory;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    await expectLater(
      copyBackgroundCryptoCommandBytesToAppPrivateFile(
        bytes: bytes,
        run: (invocation) async {
          if (invocation.arguments.first == 'push') {
            ownedDirectory = File(invocation.arguments[1]).parent;
            final ownerMarker = ownedDirectory!
                .listSync()
                .whereType<File>()
                .singleWhere((file) => !file.path.endsWith('command.bin'));
            await ownerMarker.writeAsString('tampered-owner', flush: true);
          }
          if (invocation.arguments.first == 'sha256sum') {
            return BackgroundCryptoTransportResult(
              exitCode: 0,
              stdout: '$expectedHash  ${invocation.arguments.last}\n',
            );
          }
          return const BackgroundCryptoTransportResult(exitCode: 0);
        },
      ),
      throwsA(
        isA<BackgroundCryptoStagedFileFailure>()
            .having((failure) => failure.primaryStage, 'primaryStage', isNull)
            .having(
              (failure) => failure.cleanupStages,
              'cleanupStages',
              <String>['host_stage_owned_delete'],
            ),
      ),
    );
    expect(await ownedDirectory!.exists(), isTrue);
  });

  test('cleanup receipts bind both events to exact command bytes', () {
    const commandId = 'tc256-command-123456';
    final expectedHash = sha256
        .convert(utf8.encode('exact raw command'))
        .toString();
    final alteredHash = sha256
        .convert(utf8.encode('altered command'))
        .toString();
    String marker(String event, String hash) =>
        'I/flutter: MKNOON_256_CRYPTO_PREFLIGHT '
        '${jsonEncode(<String, Object?>{'event': event, 'commandId': commandId, 'commandSha256': hash})}';

    final exact = <String>[
      marker('cleanup_started', expectedHash),
      marker('cleanup_complete', expectedHash),
    ].join('\n');
    expect(
      backgroundCryptoCleanupReceiptsMatch(
        exact,
        commandId: commandId,
        commandSha256: expectedHash,
      ),
      isTrue,
    );
    for (final tampered in <String>[
      marker('cleanup_started', expectedHash),
      <String>[
        marker('cleanup_started', expectedHash),
        marker('cleanup_complete', alteredHash),
      ].join('\n'),
      <String>[
        marker('cleanup_started', alteredHash),
        marker('cleanup_started', expectedHash),
        marker('cleanup_complete', expectedHash),
      ].join('\n'),
    ]) {
      expect(
        backgroundCryptoCleanupReceiptsMatch(
          tampered,
          commandId: commandId,
          commandSha256: expectedHash,
        ),
        isFalse,
      );
    }
  });

  test('cleanup evidence requires exact receipts and every zero counter', () {
    const commandId = 'tc256-command-123456';
    final commandBytes = utf8.encode(
      '{"schema":"mknoon.tc256-cleanup-command.v1"}',
    );
    final commandHash = sha256.convert(commandBytes).toString();
    String marker(String event, Map<String, Object?> fields) =>
        'I/flutter: MKNOON_256_CRYPTO_PREFLIGHT '
        '${jsonEncode(<String, Object?>{'event': event, ...fields})}';
    final shared = <String, Object?>{
      'commandId': commandId,
      'commandSha256': commandHash,
      'mode': 'recovery',
      'mainReexecuted': true,
    };
    final complete = <String, Object?>{
      ...shared,
      'reservedOnly': true,
      'privateBundleDeleted': true,
      'cleanupIndexDeleted': true,
      'fcmRefreshCommandDeleted': true,
      'clearNotificationsMarkerDeleted': true,
      'boundedReactionClaimsVerified': true,
      'dedupeGatesRestored': 2,
      'dedupeGatesScrubbed': 2,
      for (final field in backgroundCryptoCleanupZeroCountFields) field: 0,
    };
    final log = <String>[
      marker('cleanup_started', shared),
      marker('cleanup_complete', complete),
    ].join('\n');
    expect(
      backgroundCryptoCleanupEvidenceFromLog(
        log,
        commandId: commandId,
        commandSha256: commandHash,
        commandByteLength: commandBytes.length,
        mode: 'recovery',
      ),
      <String, Object?>{
        'mode': 'recovery',
        'commandId': commandId,
        'commandSha256': commandHash,
        'commandByteLength': commandBytes.length,
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
    );
    for (final invalid in <String>[
      log.replaceFirst(
        '"fixtureClaimsRemaining":0',
        '"fixtureClaimsRemaining":1',
      ),
      log.replaceFirst(
        '"fixtureClaimsRemaining":0',
        '"fixtureClaimsRemaining":0.0',
      ),
      log.replaceFirst('"dedupeGatesRestored":2', '"dedupeGatesRestored":1'),
      log.replaceFirst(
        '"clearNotificationsMarkerDeleted":true',
        '"clearNotificationsMarkerDeleted":false',
      ),
      log.replaceFirst(commandHash, List<String>.filled(64, '0').join()),
      '$log\n${marker('cleanup_complete', complete)}',
    ]) {
      expect(
        () => backgroundCryptoCleanupEvidenceFromLog(
          invalid,
          commandId: commandId,
          commandSha256: commandHash,
          commandByteLength: commandBytes.length,
          mode: 'recovery',
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'primary cleanup and restoration failures remain independently visible',
    () {
      const primary = BackgroundCryptoFailureRecord(
        stage: 'setup',
        type: 'FormatException',
        environmentBlocked: true,
      );
      const cleanup = BackgroundCryptoFailureRecord(
        stage: 'cleanup_synthetic_state',
        type: 'TimeoutException',
      );
      const restoration = BackgroundCryptoFailureRecord(
        stage: 'restore_installed_app',
        type: 'FileSystemException',
      );
      final artifact = buildBackgroundCryptoCompositeFailureArtifact(
        capturedAt: DateTime.utc(2026, 7, 12),
        primary: primary,
        cleanup: cleanup,
        restoration: restoration,
      );
      expect(artifact['verdict'], 'primary_and_cleanup_and_restoration_failed');
      expect(artifact['exitCode'], 1);
      expect(artifact['primaryFailure'], <String, Object?>{
        'stage': 'setup',
        'type': '_CampaignFailure',
        'environmentBlocked': true,
        'setupPhase': 'app_init',
        'setupReason': 'operation_failed',
      });
      expect(artifact['cleanupFailure'], <String, Object?>{
        'stage': 'cleanup_synthetic_state',
        'type': 'TimeoutException',
        'environmentBlocked': false,
      });
      expect(artifact['restorationFailure'], <String, Object?>{
        'stage': 'restore_installed_app',
        'type': 'FileSystemException',
        'environmentBlocked': false,
      });
    },
  );

  test(
    'setup reasons are allowlisted and exception text is never persisted',
    () {
      expect(
        BackgroundCryptoSetupReason.values.map((reason) => reason.wireName),
        <String>[
          'operation_failed',
          'schema_guard',
          'missing_identity',
          'missing_mlkem_public',
          'missing_mlkem_secret',
          'missing_fcm_token',
          'fixture_seed',
          'app_launch',
          'quiescence_failed',
          'unknown',
        ],
      );
      for (final reason in BackgroundCryptoSetupReason.values) {
        expect(backgroundCryptoSetupReasonFromWire(reason.wireName), reason);
        if (reason == BackgroundCryptoSetupReason.unknown) continue;
        final record = BackgroundCryptoFailureRecord(
          stage: 'setup',
          type: 'SELECT private_key FROM identity -- token=/secret/path',
          setupReason: reason,
          setupPhase: BackgroundCryptoSetupPhase.appInit,
        ).toJson();
        expect(record['setupReason'], reason.wireName);
        expect(record['type'], '_CampaignFailure');
        final encoded = jsonEncode(record);
        expect(encoded, isNot(contains('private_key')));
        expect(encoded, isNot(contains('/secret/path')));
      }
      expect(
        backgroundCryptoSetupReasonFromWire(
          'StateError: SQL failed token=secret /private/path',
        ),
        BackgroundCryptoSetupReason.unknown,
      );
      expect(
        () => const BackgroundCryptoFailureRecord(
          stage: 'setup',
          type: 'StateError',
          setupReason: BackgroundCryptoSetupReason.unknown,
          setupPhase: BackgroundCryptoSetupPhase.firebaseInit,
        ).toJson(),
        throwsStateError,
        reason: 'a known setup operation must never persist unknown',
      );
    },
  );

  test('cleanup phases and reasons are finite and redact private details', () {
    expect(
      BackgroundCryptoCleanupPhase.values.map((phase) => phase.wireName),
      <String>[
        'command_staging',
        'app_quiescence',
        'log_reset',
        'app_launch',
        'acknowledgement',
        'private_residue_verification',
      ],
    );
    expect(
      BackgroundCryptoCleanupReason.values.map((reason) => reason.wireName),
      <String>[
        'operation_failed',
        'command_staging_failed',
        'quiescence_failed',
        'log_reset_failed',
        'app_launch_failed',
        'acknowledgement_failed',
        'private_residue_verification_failed',
      ],
    );
    expect(
      const BackgroundCryptoFailureRecord(
        stage: 'setup_only_cleanup',
        type: 'token=secret /private/path',
        cleanupReason: BackgroundCryptoCleanupReason.acknowledgementFailed,
        cleanupPhase: BackgroundCryptoCleanupPhase.acknowledgement,
      ).toJson(),
      <String, Object?>{
        'stage': 'setup_only_cleanup',
        'type': '_CampaignFailure',
        'environmentBlocked': false,
        'cleanupPhase': 'acknowledgement',
        'cleanupReason': 'acknowledgement_failed',
      },
    );
    expect(
      () => const BackgroundCryptoFailureRecord(
        stage: 'setup_only_cleanup',
        type: 'StateError',
        cleanupPhase: BackgroundCryptoCleanupPhase.acknowledgement,
      ).toJson(),
      throwsStateError,
    );
  });

  test(
    'campaign phases and reasons are finite and provider text is redacted',
    () {
      expect(
        BackgroundCryptoCampaignPhase.values.map((phase) => phase.wireName),
        <String>[
          'headless_quiescence',
          'request_prepare',
          'delivery_eligibility',
          'oauth',
          'provider_send',
          'receive_wait',
          'crypto_wait',
          'eligibility',
          'card_verify',
          'route_verify',
        ],
      );
      expect(
        BackgroundCryptoCampaignReason.values.map((reason) => reason.wireName),
        <String>[
          'operation_failed',
          'headless_quiescence_failed',
          'request_prepare_failed',
          'delivery_eligibility_failed',
          'oauth_failed',
          'provider_send_failed',
          'receive_timeout',
          'crypto_timeout',
          'eligibility_failed',
          'card_verification_failed',
          'route_verification_failed',
        ],
      );
      const causal =
          <BackgroundCryptoCampaignPhase, BackgroundCryptoCampaignReason>{
            BackgroundCryptoCampaignPhase.headlessQuiescence:
                BackgroundCryptoCampaignReason.headlessQuiescenceFailed,
            BackgroundCryptoCampaignPhase.requestPrepare:
                BackgroundCryptoCampaignReason.requestPrepareFailed,
            BackgroundCryptoCampaignPhase.deliveryEligibility:
                BackgroundCryptoCampaignReason.deliveryEligibilityFailed,
            BackgroundCryptoCampaignPhase.oauth:
                BackgroundCryptoCampaignReason.oauthFailed,
            BackgroundCryptoCampaignPhase.providerSend:
                BackgroundCryptoCampaignReason.providerSendFailed,
            BackgroundCryptoCampaignPhase.receiveWait:
                BackgroundCryptoCampaignReason.receiveTimeout,
            BackgroundCryptoCampaignPhase.cryptoWait:
                BackgroundCryptoCampaignReason.cryptoTimeout,
            BackgroundCryptoCampaignPhase.eligibility:
                BackgroundCryptoCampaignReason.eligibilityFailed,
            BackgroundCryptoCampaignPhase.cardVerify:
                BackgroundCryptoCampaignReason.cardVerificationFailed,
            BackgroundCryptoCampaignPhase.routeVerify:
                BackgroundCryptoCampaignReason.routeVerificationFailed,
          };
      for (final entry in causal.entries) {
        final record = BackgroundCryptoFailureRecord(
          stage: 'ordinary_direct-text',
          type: 'HTTP 401 token=secret provider private response',
          campaignPhase: entry.key,
          campaignReason: entry.value,
          syntheticCaseId: 'direct-text',
        ).toJson();
        expect(record['campaignPhase'], entry.key.wireName);
        expect(record['campaignReason'], entry.value.wireName);
        expect(record['syntheticCaseId'], 'direct-text');
        expect(record['type'], '_CampaignFailure');
        final encoded = jsonEncode(record);
        expect(encoded, isNot(contains('HTTP 401')));
        expect(encoded, isNot(contains('provider private response')));
        expect(encoded, isNot(contains('token=secret')));
      }
      expect(
        () => const BackgroundCryptoFailureRecord(
          stage: 'ordinary_direct-text',
          type: 'StateError',
          campaignPhase: BackgroundCryptoCampaignPhase.providerSend,
          syntheticCaseId: 'direct-text',
        ).toJson(),
        throwsStateError,
      );
      expect(
        () => const BackgroundCryptoFailureRecord(
          stage: 'ordinary_direct-text',
          type: 'StateError',
          campaignPhase: BackgroundCryptoCampaignPhase.providerSend,
          campaignReason: BackgroundCryptoCampaignReason.providerSendFailed,
        ).toJson(),
        throwsStateError,
      );
      expect(
        () => const BackgroundCryptoFailureRecord(
          stage: 'ordinary_direct-text',
          type: 'StateError',
          campaignPhase: BackgroundCryptoCampaignPhase.providerSend,
          campaignReason: BackgroundCryptoCampaignReason.providerSendFailed,
          syntheticCaseId: '',
        ).toJson(),
        throwsStateError,
      );
      expect(
        () => const BackgroundCryptoFailureRecord(
          stage: 'ordinary_real-user-id',
          type: 'StateError',
          campaignPhase: BackgroundCryptoCampaignPhase.providerSend,
          campaignReason: BackgroundCryptoCampaignReason.providerSendFailed,
          syntheticCaseId: 'real-user-id',
        ).toJson(),
        throwsStateError,
      );
    },
  );

  test(
    'notification clear phases and reasons are finite and survive recovery',
    () {
      expect(
        BackgroundCryptoNotificationClearPhase.values.map(
          (phase) => phase.wireName,
        ),
        <String>[
          'known_id_load',
          'active_query',
          'classify',
          'cancel',
          'tone_cleanup',
          'marker_write',
        ],
      );
      expect(
        BackgroundCryptoNotificationClearReason.values.map(
          (reason) => reason.wireName,
        ),
        <String>[
          'operation_failed',
          'known_id_load_failed',
          'active_query_failed',
          'classify_failed',
          'cancel_failed',
          'tone_cleanup_failed',
          'marker_write_failed',
          'missing_marker',
          'rejected_schema',
        ],
      );
      expect(
        BackgroundCryptoNotificationClearBoundary.values.map(
          (boundary) => boundary.wireName,
        ),
        <String>[
          'command_delivery',
          'command_ack',
          'app_launch',
          'app_phase',
          'completion_schema',
        ],
      );
      expect(
        BackgroundCryptoNotificationClearObservation.values.map(
          (observation) => observation.wireName,
        ),
        <String>['observed', 'not_observed'],
      );
      for (final phase in BackgroundCryptoNotificationClearPhase.values) {
        final reason = backgroundCryptoNotificationClearReasonForPhase(phase);
        final record = BackgroundCryptoFailureRecord(
          stage: 'clear_direct_cards',
          type: 'private card title and device detail',
          campaignPhase: BackgroundCryptoCampaignPhase.cardVerify,
          campaignReason: BackgroundCryptoCampaignReason.cardVerificationFailed,
          syntheticCaseId: 'direct-text',
          notificationClearPhase: phase,
          notificationClearReason: reason,
          notificationClearBoundary:
              BackgroundCryptoNotificationClearBoundary.appPhase,
          notificationClearObservation:
              BackgroundCryptoNotificationClearObservation.observed,
        ).toJson();
        expect(record['notificationClearPhase'], phase.wireName);
        expect(record['notificationClearReason'], reason.wireName);
        expect(record['type'], '_CampaignFailure');
        expect(jsonEncode(record), isNot(contains('private card title')));
      }
      expect(
        () => const BackgroundCryptoFailureRecord(
          stage: 'clear_direct_cards',
          type: 'StateError',
          notificationClearPhase:
              BackgroundCryptoNotificationClearPhase.activeQuery,
        ).toJson(),
        throwsStateError,
      );
      expect(
        () => const BackgroundCryptoFailureRecord(
          stage: 'clear_direct_cards',
          type: 'StateError',
          notificationClearReason:
              BackgroundCryptoNotificationClearReason.missingMarker,
        ).toJson(),
        throwsStateError,
      );

      final noPhase = const BackgroundCryptoFailureRecord(
        stage: 'clear_direct_cards',
        type: 'private command detail',
        campaignPhase: BackgroundCryptoCampaignPhase.cardVerify,
        campaignReason: BackgroundCryptoCampaignReason.cardVerificationFailed,
        syntheticCaseId: 'direct-text',
        notificationClearReason:
            BackgroundCryptoNotificationClearReason.missingMarker,
        notificationClearBoundary:
            BackgroundCryptoNotificationClearBoundary.commandAck,
        notificationClearObservation:
            BackgroundCryptoNotificationClearObservation.notObserved,
      ).toJson();
      expect(noPhase, isNot(contains('notificationClearPhase')));
      expect(noPhase['notificationClearReason'], 'missing_marker');
      expect(noPhase['notificationClearBoundary'], 'command_ack');
      expect(noPhase['notificationClearObservation'], 'not_observed');
      expect(noPhase['type'], '_CampaignFailure');
      expect(jsonEncode(noPhase), isNot(contains('private command detail')));

      final app = File(
        'integration_test/android_background_crypto_preflight_app.dart',
      ).readAsStringSync();
      final controller = File(
        'integration_test/scripts/capture_android_background_crypto_preflight.dart',
      ).readAsStringSync();
      expect(app, contains("_marker('notification_clear_phase'"));
      expect(app, contains("_marker('notification_clear_error'"));
      for (final phase in BackgroundCryptoNotificationClearPhase.values) {
        expect(
          app,
          contains('BackgroundCryptoNotificationClearPhase.${phase.name}'),
        );
      }
      expect(
        controller,
        contains('BackgroundCryptoNotificationClearReason.missingMarker'),
      );
      expect(
        controller,
        contains('BackgroundCryptoNotificationClearReason.rejectedSchema'),
      );
      expect(controller, contains("event: 'notification_clear_error'"));
    },
  );

  test('notification clear completion is one atomic typed marker', () {
    String marker(Map<String, Object?> fields) =>
        'I/flutter: MKNOON_256_CRYPTO_PREFLIGHT ${jsonEncode(fields)}';
    final phaseVisibleCompletionAbsent = marker(<String, Object?>{
      'event': 'notification_clear_phase',
      'phase': 'marker_write',
    });
    expect(backgroundCryptoNotificationClearCommandAckFromLog(''), isFalse);
    expect(backgroundCryptoNotificationClearCompletionFromLog(''), isNull);
    expect(
      () => backgroundCryptoNotificationClearCompletionFromLog(
        phaseVisibleCompletionAbsent,
      ),
      throwsFormatException,
    );

    final commandAck = marker(<String, Object?>{
      'event': 'notification_clear_command_ack',
      'schema': 'mknoon.tc256-notification-clear.v1',
    });
    expect(
      backgroundCryptoNotificationClearCommandAckFromLog(commandAck),
      isTrue,
    );
    expect(
      backgroundCryptoNotificationClearCompletionFromLog(commandAck),
      isNull,
    );

    final atomic = marker(<String, Object?>{
      'event': 'notification_clear_phase',
      'phase': 'marker_write',
      'completed': true,
      for (final field in backgroundCryptoNotificationClearCountFields)
        field: 0,
    });
    final parsed = backgroundCryptoNotificationClearCompletionFromLog(
      '$commandAck\n$atomic',
    );
    expect(parsed, isNotNull);
    expect(parsed!['completed'], isTrue);
    for (final field in backgroundCryptoNotificationClearCountFields) {
      expect(parsed[field], 0);
    }

    final app = File(
      'integration_test/android_background_crypto_preflight_app.dart',
    ).readAsStringSync();
    expect(app, isNot(contains("_marker('notifications_cleared'")));
    expect(
      app,
      allOf(
        contains("_marker('notification_clear_command_ack'"),
        contains("_marker('notification_clear_phase'"),
        contains("'completed': true"),
        contains('...cleared'),
      ),
    );
  });

  test('notification clear command is delivered through a typed cold launch', () {
    final app = File(
      'integration_test/android_background_crypto_preflight_app.dart',
    ).readAsStringSync();
    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();

    final clearCall = controller.indexOf(
      'await _prepareNotificationClearColdLaunch()',
    );
    final waitForCompletion = controller.indexOf(
      "description: 'synthetic-notification cleanup acknowledgement'",
      clearCall,
    );
    final helper = controller.indexOf(
      'Future<void> _prepareNotificationClearColdLaunch()',
      waitForCompletion,
    );
    final helperEnd = controller.indexOf(
      'Future<BackgroundCryptoNotificationResetSnapshot>',
      helper,
    );
    final helperSource = controller.substring(helper, helperEnd);
    final touch = helperSource.indexOf(
      "await _runAs(['touch', _clearNotificationsMarker])",
    );
    final forceStop = helperSource.indexOf(
      "['am', 'force-stop', appPackage]",
      touch,
    );
    final absent = helperSource.indexOf(
      'await _waitForProcessAndTaskAbsent()',
      forceStop,
    );
    final logReset = helperSource.indexOf(
      "await _adb(['logcat', '-c'])",
      absent,
    );
    final explicitLaunch = helperSource.indexOf(
      'await _launchExplicitActivityClearingStoppedState()',
      logReset,
    );
    expect(clearCall, greaterThan(0));
    expect(waitForCompletion, greaterThan(clearCall));
    expect(helper, greaterThan(waitForCompletion));
    expect(touch, greaterThan(0));
    expect(forceStop, greaterThan(touch));
    expect(absent, greaterThan(forceStop));
    expect(logReset, greaterThan(absent));
    expect(explicitLaunch, greaterThan(logReset));
    expect(helperSource, isNot(contains('await _launch();')));
    expect(
      controller,
      isNot(
        contains(
          '_lastNotificationClearPhase ?? '
          'BackgroundCryptoNotificationClearPhase.markerWrite',
        ),
      ),
    );

    final clearBranch = app.indexOf(
      'BackgroundCryptoFixtureStartupIntent.clearNotifications',
    );
    final commandAck = app.indexOf(
      "_marker('notification_clear_command_ack'",
      clearBranch,
    );
    final markerDelete = app.indexOf(
      'await clearNotifications.delete()',
      commandAck,
    );
    final firstPhase = app.indexOf(
      'clearCheckpoint(BackgroundCryptoNotificationClearPhase.knownIdLoad)',
      markerDelete,
    );
    expect(clearBranch, greaterThan(0));
    expect(commandAck, greaterThan(clearBranch));
    expect(markerDelete, greaterThan(commandAck));
    expect(firstPhase, greaterThan(markerDelete));
  });

  test(
    'post-clear quiescence preserves push eligibility and localizes failure',
    () {
      expect(
        BackgroundCryptoPostClearBoundary.values.map(
          (boundary) => boundary.wireName,
        ),
        <String>[
          'delivery_quiescence',
          'process_absence',
          'baseline_polling',
          'convergence',
        ],
      );
      expect(
        BackgroundCryptoPostClearReason.values.map((reason) => reason.wireName),
        <String>[
          'delivery_quiescence_failed',
          'process_absence_failed',
          'process_absence_timeout',
          'baseline_poll_failed',
          'convergence_timeout',
        ],
      );
      expect(
        BackgroundCryptoPostClearObservation.values.map(
          (observation) => observation.wireName,
        ),
        <String>['observed', 'not_observed'],
      );

      final absenceTimeout = const BackgroundCryptoFailureRecord(
        stage: 'reset_only',
        type: 'private process detail',
        campaignPhase: BackgroundCryptoCampaignPhase.cardVerify,
        campaignReason: BackgroundCryptoCampaignReason.cardVerificationFailed,
        syntheticCaseId: 'direct-text',
        postClearReason: BackgroundCryptoPostClearReason.processAbsenceTimeout,
        postClearBoundary: BackgroundCryptoPostClearBoundary.processAbsence,
        postClearObservation: BackgroundCryptoPostClearObservation.notObserved,
      ).toJson();
      expect(absenceTimeout['postClearReason'], 'process_absence_timeout');
      expect(absenceTimeout['postClearBoundary'], 'process_absence');
      expect(absenceTimeout, isNot(contains('postClearPollCount')));
      expect(
        jsonEncode(absenceTimeout),
        isNot(contains('private process detail')),
      );

      final emptyBaselineHash = sha256.convert(utf8.encode('')).toString();
      final convergenceTimeout = BackgroundCryptoFailureRecord(
        stage: 'reset_only',
        type: 'private notification detail',
        campaignPhase: BackgroundCryptoCampaignPhase.cardVerify,
        campaignReason: BackgroundCryptoCampaignReason.cardVerificationFailed,
        syntheticCaseId: 'direct-text',
        postClearReason: BackgroundCryptoPostClearReason.convergenceTimeout,
        postClearBoundary: BackgroundCryptoPostClearBoundary.convergence,
        postClearObservation: BackgroundCryptoPostClearObservation.notObserved,
        postClearPollCount: 3,
        postClearBaselineCount: 0,
        postClearBaselineHash: emptyBaselineHash,
      ).toJson();
      expect(convergenceTimeout['postClearReason'], 'convergence_timeout');
      expect(convergenceTimeout['postClearBoundary'], 'convergence');
      expect(convergenceTimeout['postClearPollCount'], 3);
      expect(convergenceTimeout['postClearBaselineCount'], 0);
      expect(convergenceTimeout['postClearBaselineHash'], emptyBaselineHash);
      expect(
        jsonEncode(convergenceTimeout),
        isNot(contains('private notification detail')),
      );
      expect(
        () => const BackgroundCryptoFailureRecord(
          stage: 'reset_only',
          type: 'StateError',
          postClearReason: BackgroundCryptoPostClearReason.convergenceTimeout,
          postClearBoundary: BackgroundCryptoPostClearBoundary.convergence,
          postClearObservation:
              BackgroundCryptoPostClearObservation.notObserved,
        ).toJson(),
        throwsStateError,
      );

      final controller = File(
        'integration_test/scripts/capture_android_background_crypto_preflight.dart',
      ).readAsStringSync();
      final clearStart = controller.indexOf(
        'Future<void> _clearSyntheticCards()',
      );
      final clearEnd = controller.indexOf(
        'Future<void> _prepareNotificationClearColdLaunch()',
        clearStart,
      );
      final clear = controller.substring(clearStart, clearEnd);
      final acceptedCompletion = clear.indexOf(
        '_notificationClearOwnershipEvidence.add',
      );
      final deliveryQuiescence = clear.indexOf(
        'await _quiescePackageForPushDelivery()',
        acceptedCompletion,
      );
      final convergence = clear.indexOf(
        'await _waitForNotificationResetConvergence()',
        deliveryQuiescence,
      );
      final baselineCommit = clear.indexOf(
        '_resetBaselineEvidence.add',
        convergence,
      );
      expect(clearStart, greaterThan(0));
      expect(clearEnd, greaterThan(clearStart));
      expect(acceptedCompletion, greaterThan(0));
      expect(deliveryQuiescence, greaterThan(acceptedCompletion));
      expect(convergence, greaterThan(deliveryQuiescence));
      expect(baselineCommit, greaterThan(convergence));
      expect(clear, isNot(contains("['am', 'force-stop', appPackage]")));
      expect(
        clear.substring(acceptedCompletion),
        isNot(contains('_launchExplicitActivityClearingStoppedState')),
      );
      expect(
        controller,
        allOf(
          contains('BackgroundCryptoPostClearReason.processAbsenceTimeout'),
          contains('BackgroundCryptoPostClearReason.convergenceTimeout'),
          contains('on _ProcessAndTaskAbsenceTimeout'),
          contains('throw const _ProcessAndTaskAbsenceTimeout()'),
          contains("'postClearPollCount': ?primaryRecord?.postClearPollCount"),
          contains(
            "'postClearBaselineHash': ?primaryRecord?.postClearBaselineHash",
          ),
        ),
      );
    },
  );

  test(
    'delivery quiescence never force-stops and stopped state gates every send',
    () {
      final controller = File(
        'integration_test/scripts/capture_android_background_crypto_preflight.dart',
      ).readAsStringSync();

      final quiesceStart = controller.indexOf(
        'Future<void> _quiescePackageForPushDelivery()',
      );
      final quiesceEnd = controller.indexOf(
        'Future<void> _requirePackageEligibleForDataOnlyFcm(',
        quiesceStart,
      );
      expect(quiesceStart, greaterThan(0));
      expect(quiesceEnd, greaterThan(quiesceStart));
      final quiesce = controller.substring(quiesceStart, quiesceEnd);
      final home = quiesce.indexOf('KEYCODE_HOME');
      final settle = quiesce.indexOf('Duration(seconds: 1)', home);
      final kill = quiesce.indexOf("['am', 'kill', appPackage]", settle);
      final boundedCombined = quiesce.indexOf(
        '_processAndTaskAbsentWithin(const Duration(seconds: 5))',
        kill,
      );
      final stopApp = quiesce.indexOf(
        "['cmd', 'activity', 'stop-app', appPackage]",
        boundedCombined,
      );
      final finalCombined = quiesce.indexOf(
        'await _waitForProcessAndTaskAbsent()',
        stopApp,
      );
      expect(home, greaterThan(0));
      expect(settle, greaterThan(home));
      expect(kill, greaterThan(settle));
      expect(boundedCombined, greaterThan(kill));
      expect(stopApp, greaterThan(boundedCombined));
      expect(finalCombined, greaterThan(stopApp));
      expect(quiesce, isNot(contains("['am', 'force-stop', appPackage]")));

      final combinedStart = controller.indexOf(
        'Future<bool> _processAndTaskAbsentWithin(',
      );
      final combinedEnd = controller.indexOf(
        'Future<void> _waitForProcessAndTaskAbsent()',
        combinedStart,
      );
      final combined = controller.substring(combinedStart, combinedEnd);
      expect(combined, contains("['pidof', appPackage]"));
      expect(combined, contains("'activity',\n        'activities'"));
      expect(combined, contains('androidProcessAndTaskAreAbsent('));
      expect(combined, contains('return false'));

      final eligibility = controller.substring(
        quiesceEnd,
        controller.indexOf(
          'Future<void> _prepareFixtureColdLaunch()',
          quiesceEnd,
        ),
      );
      expect(eligibility, contains("'get-current-user'"));
      expect(eligibility, contains("'dumpsys'"));
      expect(eligibility, contains("'package'"));
      expect(eligibility, contains('androidPackageStoppedForUser('));
      expect(
        eligibility,
        contains('BackgroundCryptoCampaignReason.deliveryEligibilityFailed'),
      );
      expect(eligibility, contains("'stopped': false"));

      final sendStart = controller.indexOf(
        'Future<void> _sendPrivateProviderRequest(',
      );
      final sendEnd = controller.indexOf(
        'Future<void> _exerciseOrdinaryCase(',
        sendStart,
      );
      final send = controller.substring(sendStart, sendEnd);
      final requestWrite = send.indexOf('await requestFile.writeAsString(');
      final deliveryPhase = send.indexOf(
        'BackgroundCryptoCampaignPhase.deliveryEligibility',
        requestWrite,
      );
      final stoppedGuard = send.indexOf(
        'await _requirePackageEligibleForDataOnlyFcm(id)',
        deliveryPhase,
      );
      final attempts = send.indexOf(
        '_providerRequestsAttempted++',
        stoppedGuard,
      );
      final provider = send.indexOf(
        "final provider = await _run('node'",
        attempts,
      );
      expect(requestWrite, greaterThan(0));
      expect(deliveryPhase, greaterThan(requestWrite));
      expect(stoppedGuard, greaterThan(deliveryPhase));
      expect(attempts, greaterThan(stoppedGuard));
      expect(provider, greaterThan(attempts));
      expect(
        send.substring(stoppedGuard, provider),
        isNot(contains("_adbShell(['am', 'force-stop'")),
      );
    },
  );

  test('every pre-provider setup phase is finite and checkpointed', () {
    expect(
      BackgroundCryptoSetupPhase.values.map((phase) => phase.wireName),
      <String>[
        'app_init',
        'app_quiescence',
        'firebase_init',
        'secure_storage',
        'db_key',
        'db_open',
        'db_schema',
        'identity_load',
        'mlkem_public',
        'mlkem_secret',
        'fixture_seed',
        'fcm_token',
        'bundle_validation',
      ],
    );
    final app = File(
      'integration_test/android_background_crypto_preflight_app.dart',
    ).readAsStringSync();
    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    for (final phase in BackgroundCryptoSetupPhase.values) {
      expect(backgroundCryptoSetupPhaseFromWire(phase.wireName), phase);
      expect(
        phase == BackgroundCryptoSetupPhase.appQuiescence ? controller : app,
        phase == BackgroundCryptoSetupPhase.appQuiescence
            ? contains(
                '_lastSetupPhase = BackgroundCryptoSetupPhase.appQuiescence',
              )
            : contains('checkpoint(BackgroundCryptoSetupPhase.${phase.name})'),
        reason: phase.wireName,
      );
      final artifact = buildBackgroundCryptoCompositeFailureArtifact(
        capturedAt: DateTime.utc(2026, 7, 13),
        primary: BackgroundCryptoFailureRecord(
          stage: 'setup',
          type: 'discarded private failure text',
          setupReason: BackgroundCryptoSetupReason.operationFailed,
          setupPhase: phase,
        ),
        cleanup: const BackgroundCryptoFailureRecord(
          stage: 'cleanup_synthetic_state',
          type: 'TimeoutException',
        ),
        restoration: const BackgroundCryptoFailureRecord(
          stage: 'restore_installed_app',
          type: 'FileSystemException',
        ),
      );
      final primary = artifact['primaryFailure']! as Map<String, Object?>;
      expect(primary['setupPhase'], phase.wireName);
      expect(primary['setupReason'], 'operation_failed');
      expect(jsonEncode(artifact), isNot(contains('private failure text')));
    }
    expect(backgroundCryptoSetupPhaseFromWire('secret/path'), isNull);
  });

  test('post-ready host failures retain bundle validation phase', () {
    final cases = <String, BackgroundCryptoSetupReason?>{
      'cat_failure': null,
      'malformed_json': null,
      'cast_failure': null,
      'generic_catch': null,
      'validator_failure': BackgroundCryptoSetupReason.schemaGuard,
    };
    for (final entry in cases.entries) {
      final diagnostic = backgroundCryptoHostSetupFailure(
        lastObservedPhase: BackgroundCryptoSetupPhase.bundleValidation,
        reason: entry.value,
      );
      expect(
        diagnostic.phase,
        BackgroundCryptoSetupPhase.bundleValidation,
        reason: entry.key,
      );
      expect(
        diagnostic.reason,
        entry.value ?? BackgroundCryptoSetupReason.operationFailed,
        reason: entry.key,
      );
    }
    final invalidMarker = backgroundCryptoHostSetupFailure(
      lastObservedPhase: BackgroundCryptoSetupPhase.bundleValidation,
      reason: BackgroundCryptoSetupReason.unknown,
    );
    expect(invalidMarker.reason, BackgroundCryptoSetupReason.operationFailed);
    final beforeAnyAppPhase = backgroundCryptoHostSetupFailure();
    expect(beforeAnyAppPhase.phase, BackgroundCryptoSetupPhase.appInit);
    expect(beforeAnyAppPhase.reason, BackgroundCryptoSetupReason.appLaunch);

    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    final retainedPhase = controller.indexOf(
      '_lastSetupPhase = BackgroundCryptoSetupPhase.bundleValidation',
    );
    final bundleCat = controller.indexOf(
      "final requestRaw = await _runAs([",
      retainedPhase,
    );
    final bundleDecode = controller.indexOf(
      'final decodedRequest = jsonDecode(requestRaw.stdout)',
      bundleCat,
    );
    final bundleCast = controller.indexOf(
      'final request = decodedRequest.cast<String, dynamic>()',
      bundleDecode,
    );
    final bundleValidate = controller.indexOf(
      'final bundleErrors = validateBackgroundCryptoPreflightBundle(',
      bundleCast,
    );
    expect(retainedPhase, greaterThan(0));
    expect(bundleCat, greaterThan(retainedPhase));
    expect(bundleDecode, greaterThan(bundleCat));
    expect(bundleCast, greaterThan(bundleDecode));
    expect(bundleValidate, greaterThan(bundleCast));
    expect(controller, contains('backgroundCryptoSetupPhaseFromWire('));
    expect(controller, contains('_lastSetupPhase'));
  });

  test('fixture force-stop is confined to typed cold-launch quiescence', () {
    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    final fixtureCall = controller.indexOf('await _prepareFixtureColdLaunch()');
    final helper = controller.indexOf(
      'Future<void> _prepareFixtureColdLaunch()',
    );
    final phase = controller.indexOf(
      '_lastSetupPhase = BackgroundCryptoSetupPhase.appQuiescence',
      helper,
    );
    final forceStop = controller.indexOf(
      "['am', 'force-stop', appPackage]",
      phase,
    );
    final absent = controller.indexOf(
      'await _waitForProcessAndTaskAbsent()',
      forceStop,
    );
    final clearStopped = controller.indexOf(
      'await _launchExplicitActivityClearingStoppedState()',
      absent,
    );
    expect(fixtureCall, greaterThan(0));
    expect(helper, greaterThan(fixtureCall));
    expect(phase, greaterThan(helper));
    expect(forceStop, greaterThan(phase));
    expect(absent, greaterThan(forceStop));
    expect(clearStopped, greaterThan(absent));
    expect(controller, contains('isValidAndroidAppPackage(appPackage)'));
    expect(
      controller,
      contains('BackgroundCryptoSetupReason.quiescenceFailed'),
    );
    expect(
      const BackgroundCryptoFailureRecord(
        stage: 'setup',
        type: 'private detail',
        setupReason: BackgroundCryptoSetupReason.quiescenceFailed,
        setupPhase: BackgroundCryptoSetupPhase.appQuiescence,
      ).toJson(),
      <String, Object?>{
        'stage': 'setup',
        'type': '_CampaignFailure',
        'environmentBlocked': false,
        'setupPhase': 'app_quiescence',
        'setupReason': 'quiescence_failed',
      },
    );

    final headlessStart = controller.indexOf(
      'Future<void> _prepareHeadlessCase(',
    );
    final headlessEnd = controller.indexOf(
      'Future<DateTime> _exerciseLegacyReaction(',
      headlessStart,
    );
    final headless = controller.substring(headlessStart, headlessEnd);
    expect(headless, contains('await _quiescePackageForPushDelivery()'));
    expect(headless, isNot(contains('force-stop')));
  });

  test('cleanup command is staged before cleanup-scoped cold quiescence', () {
    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    final support = File(
      'integration_test/scripts/reaction_notification_proof_support.dart',
    ).readAsStringSync();
    final runCleanup = controller.indexOf('Future<String> _runCleanupCommand(');
    final commandBytes = controller.indexOf(
      'final commandBytes = utf8.encode(command)',
      runCleanup,
    );
    final privateCopy = controller.indexOf(
      'copyBackgroundCryptoCommandBytesToAppPrivateFile(',
      commandBytes,
    );
    final cleanupColdLaunch = controller.indexOf(
      'await _prepareCleanupCommandColdLaunch()',
      privateCopy,
    );
    final cleanupHelper = controller.indexOf(
      'Future<void> _prepareCleanupCommandColdLaunch()',
      cleanupColdLaunch,
    );
    final packageValidation = controller.indexOf(
      'isValidAndroidAppPackage(appPackage)',
      cleanupHelper,
    );
    final forceStop = controller.indexOf(
      "['am', 'force-stop', appPackage]",
      packageValidation,
    );
    final exactAbsence = controller.indexOf(
      'await _waitForProcessAndTaskAbsent()',
      forceStop,
    );
    final logReset = controller.indexOf(
      "await _adb(['logcat', '-c'])",
      exactAbsence,
    );
    final explicitStart = controller.indexOf(
      'await _launchExplicitActivityClearingStoppedState()',
      logReset,
    );
    expect(runCleanup, greaterThan(0));
    expect(commandBytes, greaterThan(runCleanup));
    expect(privateCopy, greaterThan(commandBytes));
    expect(cleanupColdLaunch, greaterThan(privateCopy));
    expect(cleanupHelper, greaterThan(cleanupColdLaunch));
    expect(packageValidation, greaterThan(cleanupHelper));
    expect(forceStop, greaterThan(packageValidation));
    expect(exactAbsence, greaterThan(forceStop));
    expect(logReset, greaterThan(exactAbsence));
    expect(explicitStart, greaterThan(logReset));
    expect(
      support.indexOf("'app_private_hash'", support.indexOf('sha256sum')),
      greaterThan(0),
    );

    final cleanupSlice = controller.substring(runCleanup, cleanupHelper);
    expect(cleanupSlice, isNot(contains("['am', 'kill', appPackage]")));
    expect(cleanupSlice, isNot(contains('KEYCODE_HOME')));

    final headlessStart = controller.indexOf(
      'Future<void> _prepareHeadlessCase(',
    );
    final headlessEnd = controller.indexOf(
      'Future<DateTime> _exerciseLegacyReaction(',
      headlessStart,
    );
    final headless = controller.substring(headlessStart, headlessEnd);
    expect(headless, contains('await _quiescePackageForPushDelivery()'));
    expect(headless, isNot(contains('force-stop')));
  });

  test('setup-ready and successful recovery evidence survive final failure', () {
    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    final validation = controller.indexOf(
      'final bundleErrors = validateBackgroundCryptoPreflightBundle(',
    );
    final setupReady = controller.indexOf('_setupReady = true', validation);
    final checkpoint = controller.indexOf(
      '_persistSetupReadyCheckpoint()',
      setupReady,
    );
    final setupCleanup = controller.indexOf(
      "_runCleanupCommand(mode: 'setup-only')",
      checkpoint,
    );
    expect(validation, greaterThan(0));
    expect(setupReady, greaterThan(validation));
    expect(checkpoint, greaterThan(setupReady));
    expect(setupCleanup, greaterThan(checkpoint));

    final checkpointWriter = controller.indexOf(
      'void _persistSetupReadyCheckpoint()',
    );
    final failureWriter = controller.indexOf(
      'void writeFailure(_CampaignCompositeFailure failure)',
    );
    expect(checkpointWriter, greaterThan(0));
    expect(
      controller.substring(checkpointWriter, failureWriter),
      allOf(
        contains("'setupReady': true"),
        contains("'setupStatus': 'ready'"),
        contains("'providerCodePathEntered': false"),
      ),
    );
    final cleanupRunner = controller.indexOf(
      'Future<String> _runCleanupCommand(',
      failureWriter,
    );
    final failureSlice = controller.substring(failureWriter, cleanupRunner);
    expect(
      failureSlice,
      allOf(
        contains("..['setupReady'] = _setupReady"),
        contains("'cleanupPhase': phase.wireName"),
        contains("'cleanupReason': reason.wireName"),
        contains("'successfulCleanupEvidence'"),
        contains("'successfulRestorationEvidence'"),
        contains("..['providerRequestsSent'] = 0"),
      ),
    );
    expect(
      controller,
      allOf(
        contains('_successfulCleanupEvidence.add('),
        contains("await _runCleanupCommand(mode: 'recovery')"),
        contains('_successfulRestorationEvidence = <String, Object?>{'),
      ),
    );
  });

  test('ordinary-only branch never enters the legacy reaction row', () {
    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    final reactionGuard = controller.indexOf('if (!ordinaryOnly) {');
    final reactionRead = controller.indexOf(
      "final reaction = request['reaction']",
      reactionGuard,
    );
    final ordinaryCases = controller.indexOf(
      "final ordinaryCases = (request['ordinaryCases']! as List)",
    );
    final legacyCall = controller.indexOf(
      'reactionSentAt = await _exerciseLegacyReaction(',
      reactionRead,
    );
    final ordinaryElse = controller.indexOf('} else {', legacyCall);
    final ordinaryFirst = controller.indexOf(
      'await _runOrdinaryMatrix(token: token, ordinaryCases: ordinaryCases)',
      ordinaryElse,
    );
    final negativeAfter = controller.indexOf(
      'await _runNegativeAuthorizationMatrix(',
      ordinaryFirst,
    );
    expect(ordinaryCases, greaterThan(0));
    expect(reactionGuard, greaterThan(ordinaryCases));
    expect(reactionRead, greaterThan(reactionGuard));
    expect(legacyCall, greaterThan(reactionRead));
    expect(ordinaryElse, greaterThan(legacyCall));
    expect(ordinaryFirst, greaterThan(ordinaryElse));
    expect(negativeAfter, greaterThan(ordinaryFirst));
    expect(
      controller.substring(ordinaryElse, negativeAfter),
      isNot(contains('_exerciseLegacyReaction(')),
    );
    expect(controller, contains("ordinaryCases.first['id'] != 'direct-text'"));
  });

  test('ordinary-only mode omits reaction construction and bundle parsing', () {
    final app = File(
      'integration_test/android_background_crypto_preflight_app.dart',
    ).readAsStringSync();
    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    final support = File(
      'integration_test/scripts/reaction_notification_proof_support.dart',
    ).readAsStringSync();

    expect(
      app,
      contains(
        "const _ordinaryOnly = bool.fromEnvironment('MKNOON_TC256_ORDINARY_ONLY')",
      ),
    );
    expect(
      controller,
      contains("'--dart-define=MKNOON_TC256_ORDINARY_ONLY=true'"),
    );

    final encryptionDeclaration = app.indexOf(
      'Map<String, dynamic>? reactionEncrypted;',
    );
    final encryptionGuard = app.indexOf(
      'if (!_ordinaryOnly) {',
      encryptionDeclaration,
    );
    final reactionEncrypt = app.indexOf(
      'reactionEncrypted = await callEncryptMessage(',
      encryptionGuard,
    );
    final requestWrite = app.indexOf('await request.writeAsString(');
    final conditionalReaction = app.indexOf(
      'if (!_ordinaryOnly)',
      requestWrite,
    );
    final reactionBundleKey = app.indexOf(
      "'reaction': <String, Object?>{",
      conditionalReaction,
    );
    expect(encryptionDeclaration, greaterThan(0));
    expect(encryptionGuard, greaterThan(encryptionDeclaration));
    expect(reactionEncrypt, greaterThan(encryptionGuard));
    expect(conditionalReaction, greaterThan(requestWrite));
    expect(reactionBundleKey, greaterThan(conditionalReaction));

    expect(
      RegExp(
        r"if \(!_ordinaryOnly\) \{\s+final reaction = bundle\?\['reaction'\];",
      ).allMatches(app),
      hasLength(2),
    );
    expect(
      controller,
      contains(
        'requireReaction: '
        '!(ordinaryOnly || resetOnly || providerDiagnosticOnly)',
      ),
    );
    expect(
      RegExp(
        r"if \(!ordinaryOnly\) \{\s+final reaction = request\['reaction'\];",
      ).allMatches(controller),
      hasLength(1),
    );
    expect(support, contains('if (requireReaction == true ||'));
    final validatorGuard = support.indexOf('if (requireReaction == true ||');
    final validatorReactionRead = support.indexOf(
      "final reaction = bundle['reaction'];",
      validatorGuard,
    );
    expect(validatorReactionRead, greaterThan(validatorGuard));
  });

  test('campaign case IDs are the exact reserved allowlist', () {
    final allowed = <String>{
      'reaction',
      ...backgroundCryptoPreflightOrdinaryRows.map((row) => row.id),
      ...backgroundCryptoPreflightNegativeRows.map((row) => row.id),
    };
    for (final id in allowed) {
      expect(isBackgroundCryptoSyntheticCaseId(id), isTrue, reason: id);
    }
    for (final id in <String>['', ' ', 'real-user-id', 'direct-text-extra']) {
      expect(isBackgroundCryptoSyntheticCaseId(id), isFalse, reason: id);
    }
    expect(
      backgroundCryptoCampaignCaseOrder(ordinaryOnly: true),
      isNot(contains('reaction')),
    );
  });

  test('campaign failure checkpoint retains causal counts through recovery', () {
    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    final provider = File(
      'scripts/send_fcm_provider_probe.js',
    ).readAsStringSync();
    final primaryGuard = controller.indexOf('if (primaryFailure != null) {');
    final checkpoint = controller.indexOf(
      'writeFailure(_CampaignCompositeFailure(primary: primaryFailure))',
      primaryGuard,
    );
    final cleanup = controller.indexOf(
      'var cleanupFailure = await _attemptPreRestorationCleanup()',
      checkpoint,
    );
    final restoration = controller.indexOf(
      'final restorationFailure = await _attemptOutermostRestoration()',
      cleanup,
    );
    expect(primaryGuard, greaterThan(0));
    expect(checkpoint, greaterThan(primaryGuard));
    expect(cleanup, greaterThan(checkpoint));
    expect(restoration, greaterThan(cleanup));

    final failureWriter = controller.indexOf(
      'void writeFailure(_CampaignCompositeFailure failure)',
    );
    final cleanupRunner = controller.indexOf(
      'Future<String> _runCleanupCommand(',
      failureWriter,
    );
    final failureSlice = controller.substring(failureWriter, cleanupRunner);
    for (final field in <String>[
      "'campaignPhase': phase.wireName",
      "'campaignReason': reason.wireName",
      "'currentSyntheticCaseId'",
      "['providerRequestsAttempted']",
      "['providerRequestsSucceeded']",
      "['caseExecutionOrder']",
      "['reactionRowsExecuted']",
      "['ordinaryCasesExecuted']",
      "['negativeCasesExecuted']",
      "'successfulCleanupEvidence'",
      "'successfulRestorationEvidence'",
    ]) {
      expect(failureSlice, contains(field), reason: field);
    }

    final requestWrite = controller.indexOf('await requestFile.writeAsString(');
    final attempted = controller.indexOf(
      '_providerRequestsAttempted++',
      requestWrite,
    );
    final providerRun = controller.indexOf(
      "final provider = await _run('node'",
      attempted,
    );
    final succeeded = controller.indexOf(
      '_providerRequestsSucceeded++',
      providerRun,
    );
    expect(requestWrite, greaterThan(0));
    expect(attempted, greaterThan(requestWrite));
    expect(providerRun, greaterThan(attempted));
    expect(succeeded, greaterThan(providerRun));
    expect(controller, contains('provider.exitCode == 70'));
    expect(controller, contains('provider.exitCode == 71'));
    expect(provider, contains('const EXIT_OAUTH = 70'));
    expect(provider, contains('const EXIT_PROVIDER_SEND = 71'));
    expect(provider, contains("throw new ProviderPhaseFailure('oauth'"));
    expect(provider, contains("throw new ProviderPhaseFailure('fcm'"));
    expect(provider, isNot(contains('console.error(error.message)')));

    for (final causal in <String>[
      'BackgroundCryptoCampaignReason.headlessQuiescenceFailed',
      'BackgroundCryptoCampaignReason.requestPrepareFailed',
      'BackgroundCryptoCampaignReason.oauthFailed',
      'BackgroundCryptoCampaignReason.providerSendFailed',
      'BackgroundCryptoCampaignReason.receiveTimeout',
      'BackgroundCryptoCampaignReason.cryptoTimeout',
      'BackgroundCryptoCampaignReason.eligibilityFailed',
      'BackgroundCryptoCampaignReason.cardVerificationFailed',
      'BackgroundCryptoCampaignReason.routeVerificationFailed',
    ]) {
      expect(controller, contains(causal), reason: causal);
    }
  });

  test('provider result parser is finite, exit-bound, and secret-free', () {
    Map<String, Object?> receipt({
      required bool ok,
      required String stage,
      required bool validateOnly,
      int? status,
      String? rpcStatus,
      String? reason,
      String? requestIdHash,
    }) => <String, Object?>{
      'schema': backgroundCryptoProviderResultSchema,
      'ok': ok,
      'stage': stage,
      'operation': validateOnly ? 'validate_only' : 'deliver',
      'validateOnly': validateOnly,
      'validationResult': validateOnly
          ? (ok ? 'accepted' : 'rejected')
          : 'not_run',
      'httpClass': status == null ? 'network' : '${status ~/ 100}xx',
      'httpStatus': status,
      'rpcStatus': rpcStatus,
      'reason': reason,
      'requestIdSha256': requestIdHash,
    };

    final accepted = receipt(
      ok: true,
      stage: 'fcm',
      validateOnly: true,
      status: 200,
      rpcStatus: 'OK',
      requestIdHash: sha256.convert(utf8.encode('request-id')).toString(),
    );
    expect(
      parseBackgroundCryptoProviderResult(
        jsonEncode(accepted),
        exitCode: 0,
        expectValidateOnly: true,
      ),
      accepted,
    );
    final unregistered = receipt(
      ok: false,
      stage: 'fcm',
      validateOnly: true,
      status: 404,
      rpcStatus: 'NOT_FOUND',
      reason: 'UNREGISTERED',
    );
    expect(
      parseBackgroundCryptoProviderResult(
        jsonEncode(unregistered),
        exitCode: 71,
        expectValidateOnly: true,
      )['reason'],
      'UNREGISTERED',
    );
    final oauth = receipt(
      ok: false,
      stage: 'oauth',
      validateOnly: true,
      status: 400,
      reason: 'INVALID_GRANT',
    );
    expect(
      parseBackgroundCryptoProviderResult(
        jsonEncode(oauth),
        exitCode: 70,
        expectValidateOnly: true,
      )['stage'],
      'oauth',
    );

    for (final invalid in <Map<String, Object?>>[
      <String, Object?>{...accepted, 'rawMessage': 'PRIVATE_MESSAGE'},
      <String, Object?>{...accepted, 'operation': 'deliver'},
      <String, Object?>{...accepted, 'httpClass': '4xx'},
      <String, Object?>{...accepted, 'rpcStatus': 'PRIVATE_RPC'},
      <String, Object?>{...accepted, 'requestIdSha256': 'raw-request-id'},
      <String, Object?>{...accepted, 'reason': 'PRIVATE_REASON'},
    ]) {
      expect(
        () => parseBackgroundCryptoProviderResult(
          jsonEncode(invalid),
          exitCode: 0,
          expectValidateOnly: true,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => parseBackgroundCryptoProviderResult(
        jsonEncode(accepted),
        exitCode: 71,
        expectValidateOnly: true,
      ),
      throwsFormatException,
    );
  });

  test(
    'provider probe injected response matrix passes without network',
    () async {
      final result = await Process.run('node', <String>[
        '--test',
        'scripts/test/send_fcm_provider_probe_contract_test.js',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout.toString(), contains('# pass 5'));
    },
  );

  test('setup reason survives composite cleanup and restoration failures', () {
    const primary = BackgroundCryptoFailureRecord(
      stage: 'setup',
      type: 'StateError: secret detail',
      setupReason: BackgroundCryptoSetupReason.fixtureSeed,
      setupPhase: BackgroundCryptoSetupPhase.fixtureSeed,
    );
    const cleanup = BackgroundCryptoFailureRecord(
      stage: 'cleanup_synthetic_state',
      type: 'TimeoutException',
    );
    const restoration = BackgroundCryptoFailureRecord(
      stage: 'restore_installed_app',
      type: 'FileSystemException',
    );
    final artifact = buildBackgroundCryptoCompositeFailureArtifact(
      capturedAt: DateTime.utc(2026, 7, 13),
      primary: primary,
      cleanup: cleanup,
      restoration: restoration,
    );
    final primaryJson = artifact['primaryFailure']! as Map<String, Object?>;
    expect(primaryJson['setupReason'], 'fixture_seed');
    expect(primaryJson['setupPhase'], 'fixture_seed');
    expect(primaryJson['type'], '_CampaignFailure');
    expect(jsonEncode(artifact), isNot(contains('secret detail')));
  });

  test('reserved-only gate cleanup preserves every unrelated entry', () {
    final unrelatedValue = <String, Object?>{'nested': true};
    final source = <String, Object?>{
      'payload=peer-real|id=message-real': 101,
      'message:group:real|message:message-real': 102,
      'payload=group:tc256-preflight-group-not-fixture|id=message-real': 103,
      'payload=peer-real|id=tc256-unrelated': 104,
      'payload:peer-real': 105,
      'opaque': unrelatedValue,
      'payload=$backgroundCryptoPreflightActorPeerId|id=tc256-direct-text-1':
          201,
      'message:group:$backgroundCryptoPreflightGroupId|message:tc256-group-text-1':
          202,
      'message:group:$backgroundCryptoPreflightAnnouncementId|message:tc256-announcement-text-1':
          203,
      'payload:$backgroundCryptoPreflightActorPeerId': 204,
      'message:$backgroundCryptoPreflightActorPeerId|tc256-direct-text-2': 205,
    };
    final cleaned = removeBackgroundCryptoFixtureGateEntries(source);
    expect(cleaned.keys, <String>{
      'payload=peer-real|id=message-real',
      'message:group:real|message:message-real',
      'payload=group:tc256-preflight-group-not-fixture|id=message-real',
      'payload=peer-real|id=tc256-unrelated',
      'payload:peer-real',
      'opaque',
    });
    expect(cleaned['payload=peer-real|id=message-real'], 101);
    expect(cleaned['message:group:real|message:message-real'], 102);
    expect(
      cleaned['payload=group:tc256-preflight-group-not-fixture|id=message-real'],
      103,
    );
    expect(cleaned['payload=peer-real|id=tc256-unrelated'], 104);
    expect(cleaned['payload:peer-real'], 105);
    expect(cleaned['opaque'], same(unrelatedValue));
    expect(
      isBackgroundCryptoFixtureRoutePayload(
        'group:tc256-preflight-group-not-fixture|message:real',
      ),
      isFalse,
    );
    expect(
      isBackgroundCryptoFixtureClaimFileName(
        'new_message-tc256-direct-image-123',
      ),
      isTrue,
    );
    expect(
      isBackgroundCryptoFixtureClaimFileName('new_message-real-message'),
      isFalse,
    );
    expect(
      isBackgroundCryptoFixtureClaimFileName('new_message-tc256-unrelated'),
      isFalse,
    );
    final boundedReactionClaim =
        DurableNotificationToneLease.messageEventClaimFileName(
          type: 'message_reaction',
          eventIdentity: boundedReactionEventIdentity('tc256-reaction-123'),
        );
    expect(
      isBackgroundCryptoFixtureClaimFileName(boundedReactionClaim),
      isFalse,
      reason: 'bounded reaction claims require exact recovered event IDs',
    );
    expect(
      isBackgroundCryptoFixtureEnvelope(
        senderPeerId: 'real-peer',
        messageId: 'tc256-direct-voice-123',
      ),
      isTrue,
    );
    expect(
      isBackgroundCryptoFixtureEnvelope(
        senderPeerId: 'real-peer',
        messageId: 'real-message',
      ),
      isFalse,
    );
  });

  test('cleanup index rejects stale, corrupt, and unrelated claim targets', () {
    final valid = <String, dynamic>{
      'schema': 'mknoon.tc256-cleanup-index.v2',
      'reactionEventIds': <String>['tc256-reaction-123'],
      'reactionTargetMessageIds': <String>['tc256-target-123'],
      'boundedReactionClaimNames': <String>[
        _boundedClaimName('tc256-reaction-123'),
      ],
      'ordinaryMessageIds': <String>[
        for (final row in backgroundCryptoPreflightOrdinaryRows)
          _messageId(row),
      ],
      'negativeMessageIds': <String>[
        for (final row in backgroundCryptoPreflightNegativeRows)
          _negativeMessageId(row),
      ],
    };
    expect(
      validateBackgroundCryptoCleanupIndex(
        valid,
        boundedClaimName: _boundedClaimName,
      ).isValid,
      isTrue,
    );

    final ordinaryOnly = _copy(valid)
      ..['reactionEventIds'] = <String>[]
      ..['reactionTargetMessageIds'] = <String>[]
      ..['boundedReactionClaimNames'] = <String>[];
    expect(
      validateBackgroundCryptoCleanupIndex(
        ordinaryOnly,
        boundedClaimName: _boundedClaimName,
        requireReaction: false,
      ).isValid,
      isTrue,
    );
    expect(
      validateBackgroundCryptoCleanupIndex(
        ordinaryOnly,
        boundedClaimName: _boundedClaimName,
      ).errors,
      contains(contains('reaction/target cardinality is invalid')),
    );
    for (final recoveryIndex in <Map<String, dynamic>>[valid, ordinaryOnly]) {
      expect(
        validateBackgroundCryptoCleanupIndex(
          recoveryIndex,
          boundedClaimName: _boundedClaimName,
          requireReaction: null,
        ).isValid,
        isTrue,
      );
    }

    final staleClaim = _copy(valid);
    staleClaim['boundedReactionClaimNames'] = <String>[
      _boundedClaimName('real-reaction-999'),
    ];
    expect(
      validateBackgroundCryptoCleanupIndex(
        staleClaim,
        boundedClaimName: _boundedClaimName,
      ).errors,
      contains(contains('do not match reaction IDs')),
    );

    final mismatchedTarget = _copy(valid);
    mismatchedTarget['reactionTargetMessageIds'] = <String>['tc256-target-456'];
    expect(
      validateBackgroundCryptoCleanupIndex(
        mismatchedTarget,
        boundedClaimName: _boundedClaimName,
      ).errors,
      contains(contains('parity')),
    );

    final nonString = _copy(valid);
    nonString['reactionEventIds'] = <Object?>[7];
    expect(
      validateBackgroundCryptoCleanupIndex(
        nonString,
        boundedClaimName: _boundedClaimName,
      ).errors,
      contains(contains('must all be strings')),
    );

    final unrelatedOrdinary = _copy(valid);
    final unrelatedOrdinaryIds =
        (unrelatedOrdinary['ordinaryMessageIds']! as List).cast<String>();
    unrelatedOrdinaryIds[0] = 'real-message';
    expect(
      validateBackgroundCryptoCleanupIndex(
        unrelatedOrdinary,
        boundedClaimName: _boundedClaimName,
      ).errors,
      contains(contains('ordinary matrix must contain one')),
    );

    final unrelatedNegative = _copy(valid);
    final unrelatedNegativeIds =
        (unrelatedNegative['negativeMessageIds']! as List).cast<String>();
    unrelatedNegativeIds[0] = 'real-negative-message';
    expect(
      validateBackgroundCryptoCleanupIndex(
        unrelatedNegative,
        boundedClaimName: _boundedClaimName,
      ).errors,
      contains(contains('negative matrix must contain one')),
    );
  });

  test(
    'controller dry-run is a secret-free 12-case no-side-effect plan',
    () async {
      final result = await Process.run('dart', <String>[
        'run',
        'integration_test/scripts/capture_android_background_crypto_preflight.dart',
        '--dry-run',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final raw = result.stdout.toString();
      final jsonStart = raw.indexOf('{');
      expect(jsonStart, greaterThanOrEqualTo(0), reason: raw);
      final manifest =
          jsonDecode(raw.substring(jsonStart)) as Map<String, dynamic>;
      expect(manifest['schema'], backgroundCryptoPreflightBundleSchema);
      expect(manifest['ordinaryCaseCount'], 12);
      expect(manifest['negativeCaseCount'], 3);
      expect(manifest['reactionRows'], 1);
      expect(manifest['providerRowsPlanned'], 16);
      expect(manifest['performsBuild'], isFalse);
      expect(manifest['usesDevice'], isFalse);
      expect(manifest['contactsProvider'], isFalse);
      expect(manifest['containsSecrets'], isFalse);
      expect(manifest['cases'], hasLength(12));
      expect(manifest['negativeCases'], hasLength(3));
      expect(
        manifest['groupTransportContract'],
        'authenticated-active-device-roster',
      );
      for (final forbidden in <String>[
        'fcmToken',
        'ciphertext',
        'secretKey',
        'service-account',
      ]) {
        expect(raw, isNot(contains(forbidden)));
      }
    },
  );

  test(
    'cleanup-only dry-run cannot contact provider or execute proof rows',
    () async {
      final result = await Process.run('dart', <String>[
        'run',
        'integration_test/scripts/capture_android_background_crypto_preflight.dart',
        '--cleanup-only',
        '--dry-run',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final raw = result.stdout.toString();
      final manifest =
          jsonDecode(raw.substring(raw.indexOf('{'))) as Map<String, dynamic>;
      expect(manifest['schema'], backgroundCryptoCleanupArtifactSchema);
      expect(manifest['mode'], 'cleanup-only-dry-run');
      expect(manifest['cleanupOnly'], isTrue);
      expect(manifest['ordinaryCaseCount'], 0);
      expect(manifest['negativeCaseCount'], 0);
      expect(manifest['cases'], isEmpty);
      expect(manifest['negativeCases'], isEmpty);
      expect(manifest['contactsProvider'], isFalse);
      expect(manifest['performsOrdinaryProof'], isFalse);
      expect(raw, isNot(contains('service-account')));
    },
  );

  test('setup-only dry-run has no provider, secret, or proof-row path', () async {
    final result = await Process.run('dart', <String>[
      'run',
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
      '--setup-only',
      '--dry-run',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final raw = result.stdout.toString();
    final manifest =
        jsonDecode(raw.substring(raw.indexOf('{'))) as Map<String, dynamic>;
    expect(manifest['schema'], backgroundCryptoSetupArtifactSchema);
    expect(manifest['mode'], 'setup-only-dry-run');
    expect(manifest['setupOnly'], isTrue);
    expect(manifest['cleanupOnly'], isFalse);
    expect(manifest['ordinaryCaseCount'], 0);
    expect(manifest['negativeCaseCount'], 0);
    expect(manifest['cases'], isEmpty);
    expect(manifest['negativeCases'], isEmpty);
    expect(manifest['contactsProvider'], isFalse);
    expect(manifest['performsOrdinaryProof'], isFalse);
    expect(manifest['containsSecrets'], isFalse);
    for (final forbidden in <String>[
      'fcmToken',
      'ciphertext',
      'secretKey',
      'service-account',
    ]) {
      expect(raw, isNot(contains(forbidden)));
    }
  });

  test(
    'ordinary-only dry-run is reaction-free and retains exact 12 plus 3',
    () async {
      final result = await Process.run('dart', <String>[
        'run',
        'integration_test/scripts/capture_android_background_crypto_preflight.dart',
        '--ordinary-only',
        '--dry-run',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final raw = result.stdout.toString();
      final manifest =
          jsonDecode(raw.substring(raw.indexOf('{'))) as Map<String, dynamic>;
      expect(manifest['mode'], 'ordinary-only-dry-run');
      expect(manifest['ordinaryOnly'], isTrue);
      expect(manifest['cleanupOnly'], isFalse);
      expect(manifest['setupOnly'], isFalse);
      expect(manifest['reactionRows'], 0);
      expect(manifest['ordinaryCaseCount'], 12);
      expect(manifest['negativeCaseCount'], 3);
      expect(manifest['providerRowsPlanned'], 15);
      expect(manifest['firstOrdinaryCaseId'], 'direct-text');
      expect(manifest['cases'], hasLength(12));
      expect(manifest['negativeCases'], hasLength(3));
      final order = (manifest['caseExecutionOrder']! as List).cast<String>();
      expect(order, hasLength(15));
      expect(order.first, 'direct-text');
      expect(order, isNot(contains('reaction')));
      expect(manifest['contactsProvider'], isFalse);
      expect(manifest['usesDevice'], isFalse);
      expect(manifest['containsSecrets'], isFalse);
    },
  );

  test('reset-only is provider-free and mutually exclusive', () async {
    final result = await Process.run('dart', <String>[
      'run',
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
      '--reset-only',
      '--dry-run',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final raw = result.stdout.toString();
    final manifest =
        jsonDecode(raw.substring(raw.indexOf('{'))) as Map<String, dynamic>;
    expect(manifest['schema'], backgroundCryptoResetArtifactSchema);
    expect(manifest['mode'], 'reset-only-dry-run');
    expect(manifest['resetOnly'], isTrue);
    expect(manifest['providerRowsPlanned'], 0);
    expect(manifest['reactionRows'], 0);
    expect(manifest['ordinaryCaseCount'], 0);
    expect(manifest['negativeCaseCount'], 0);
    expect(manifest['caseExecutionOrder'], isEmpty);
    expect(manifest['contactsProvider'], isFalse);
    expect(manifest['performsBuild'], isFalse);
    expect(manifest['usesDevice'], isFalse);

    final conflict = await Process.run('dart', <String>[
      'run',
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
      '--reset-only',
      '--ordinary-only',
      '--dry-run',
    ]);
    expect(conflict.exitCode, 64);

    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    final resetBranch = controller.indexOf('if (resetOnly) {');
    final clear = controller.indexOf(
      'await _clearSyntheticCards()',
      resetBranch,
    );
    final cleanup = controller.indexOf(
      "_runCleanupCommand(mode: 'recovery')",
      clear,
    );
    final resetReturn = controller.indexOf('return;', cleanup);
    final tokenRead = controller.indexOf(
      "final token = request['token']! as String",
    );
    final providerPreflight = controller.indexOf(
      "stage = 'provider_preflight'",
    );
    expect(resetBranch, greaterThan(0));
    expect(clear, greaterThan(resetBranch));
    expect(cleanup, greaterThan(clear));
    expect(resetReturn, greaterThan(cleanup));
    expect(tokenRead, greaterThan(resetReturn));
    expect(providerPreflight, greaterThan(tokenRead));
    final resetSlice = controller.substring(resetBranch, resetReturn);
    expect(resetSlice, isNot(contains('_sendPrivateProviderRequest(')));
    expect(resetSlice, isNot(contains("'mknoon-tc256-fcm-'")));
    expect(
      controller,
      contains('if (ordinaryOnly || resetOnly || providerDiagnosticOnly)'),
    );
    expect(controller, contains('!resetOnly &&'));
  });

  test(
    'provider diagnostic dry-run is one validate-only row and zero delivery',
    () async {
      final result = await Process.run('dart', <String>[
        'run',
        'integration_test/scripts/capture_android_background_crypto_preflight.dart',
        '--provider-diagnostic-only',
        '--dry-run',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final raw = result.stdout.toString();
      final manifest =
          jsonDecode(raw.substring(raw.indexOf('{'))) as Map<String, dynamic>;
      expect(
        manifest['schema'],
        backgroundCryptoProviderDiagnosticArtifactSchema,
      );
      expect(manifest['mode'], 'provider-diagnostic-only-dry-run');
      expect(manifest['providerDiagnosticOnly'], isTrue);
      expect(manifest['providerValidationRowsPlanned'], 1);
      expect(manifest['deliveryRowsPlanned'], 0);
      expect(manifest['diagnosticFixtureCaseId'], 'direct-text');
      expect(manifest['providerRowsPlanned'], 0);
      expect(manifest['reactionRows'], 0);
      expect(manifest['ordinaryCaseCount'], 0);
      expect(manifest['negativeCaseCount'], 0);
      expect(manifest['caseExecutionOrder'], isEmpty);
      expect(manifest['cases'], isEmpty);
      expect(manifest['negativeCases'], isEmpty);
      expect(manifest['contactsProvider'], isFalse);
      expect(manifest['usesDevice'], isFalse);
      expect(manifest['containsSecrets'], isFalse);
      for (final forbidden in <String>[
        'fcmToken',
        'ciphertext',
        'secretKey',
        'service-account',
      ]) {
        expect(raw, isNot(contains(forbidden)));
      }

      final conflict = await Process.run('dart', <String>[
        'run',
        'integration_test/scripts/capture_android_background_crypto_preflight.dart',
        '--provider-diagnostic-only',
        '--ordinary-only',
        '--dry-run',
      ]);
      expect(conflict.exitCode, 64);

      final refreshDryRun = await Process.run('dart', <String>[
        'run',
        'integration_test/scripts/capture_android_background_crypto_preflight.dart',
        '--provider-diagnostic-only',
        '--refresh-unregistered-token',
        '--prior-provider-diagnostic',
        '/path/is/not/read/by/dry-run.json',
        '--dry-run',
      ]);
      expect(
        refreshDryRun.exitCode,
        0,
        reason: refreshDryRun.stderr.toString(),
      );
      final refreshRaw = refreshDryRun.stdout.toString();
      final refreshManifest =
          jsonDecode(refreshRaw.substring(refreshRaw.indexOf('{')))
              as Map<String, dynamic>;
      expect(refreshManifest['refreshUnregisteredToken'], isTrue);
      expect(refreshManifest['performsRegistrationRefresh'], isFalse);
      expect(refreshManifest['contactsProvider'], isFalse);

      final unboundRefresh = await Process.run('dart', <String>[
        'run',
        'integration_test/scripts/capture_android_background_crypto_preflight.dart',
        '--refresh-unregistered-token',
        '--prior-provider-diagnostic',
        '/not-used.json',
        '--dry-run',
      ]);
      expect(unboundRefresh.exitCode, 64);

      final controller = File(
        'integration_test/scripts/capture_android_background_crypto_preflight.dart',
      ).readAsStringSync();
      final provider = File(
        'scripts/send_fcm_provider_probe.js',
      ).readAsStringSync();
      final app = File(
        'integration_test/android_background_crypto_preflight_app.dart',
      ).readAsStringSync();
      final diagnosticStart = controller.indexOf(
        'Future<void> _runProviderDiagnosticOnly(',
      );
      final validateStart = controller.indexOf(
        'Future<Map<String, Object?>> _validateProviderOnly(',
        diagnosticStart,
      );
      final diagnostic = controller.substring(diagnosticStart, validateStart);
      final validateEnd = controller.indexOf(
        'Future<void> _requireDevice()',
        validateStart,
      );
      final validate = controller.substring(validateStart, validateEnd);
      expect(diagnostic, contains("['am', 'force-stop', appPackage]"));
      expect(diagnostic, contains('await _waitForProcessAndTaskAbsent()'));
      expect(
        diagnostic,
        contains("await _runCleanupCommand(mode: 'recovery')"),
      );
      expect(diagnostic, contains('_writeProviderDiagnosticArtifact('));
      expect(diagnostic, isNot(contains('_sendPrivateProviderRequest(')));
      expect(diagnostic, isNot(contains('_launchExplicitActivity')));
      expect(validate, contains("'--validate-only'"));
      expect(validate, contains('_providerValidationAttempts++'));
      expect(validate, contains('_providerValidationSucceeded++'));
      expect(validate, contains('parseBackgroundCryptoProviderResult('));
      expect(validate, isNot(contains('_providerRequestsAttempted++')));
      expect(controller, contains('credentialMode != 0x180'));
      expect(controller, contains("'deliveryAttempted': false"));
      expect(
        controller.indexOf(
          'parseBackgroundCryptoUnregisteredDiagnosticAuthorization(',
        ),
        lessThan(controller.indexOf('await campaign.run()')),
      );
      expect(
        RegExp(r'invalidateToken: messaging\.deleteToken').allMatches(app),
        hasLength(1),
      );
      expect(app, contains('tokenRefreshes: messaging.onTokenRefresh'));
      expect(
        app.indexOf('backgroundCryptoFcmRefreshSubjectMatches('),
        lessThan(app.indexOf('invalidateToken: messaging.deleteToken')),
      );
      expect(app, contains('commandAge > refresh.maxAge'));
      expect(app, contains("'fcmRefreshCommandDeleted': true"));
      expect(controller, contains('commandAgeAtObservationMs'));
      expect(controller, contains('_fcmRefreshCommand'));
      expect(provider, contains('{message, validate_only: validateOnly}'));
      expect(provider, contains('validateServiceAccountMode'));
      expect(provider, contains('MAX_RESPONSE_BYTES = 64 * 1024'));
      expect(provider, isNot(contains('raw: text')));
    },
  );

  test(
    'source contract uses production crypto, killed process, and exact cleanup',
    () {
      final app = File(
        'integration_test/android_background_crypto_preflight_app.dart',
      ).readAsStringSync();
      final controller = File(
        'integration_test/scripts/capture_android_background_crypto_preflight.dart',
      ).readAsStringSync();
      final provider = File(
        'scripts/send_fcm_provider_probe.js',
      ).readAsStringSync();

      expect(app, contains('callEncryptMessage('));
      expect(app, contains('callGroupEncrypt('));
      expect(app, contains('secureStoreReferenceForKey('));
      expect(app, contains('Intentionally no sender_id'));
      expect(
        app,
        contains("'sender_transport_peer_id': _actorTransportPeerId"),
      );
      expect(app, contains('GroupMemberDeviceIdentity.listToJsonString'));
      expect(app, contains("_marker('setup_error'"));
      expect(app, contains("'phase': setupPhase.wireName"));
      expect(app, contains('backgroundCryptoTerminalSetupReason('));
      final setupCatch = app.indexOf('} catch (error) {');
      final setupFailureClass = app.indexOf('class _SetupFailure', setupCatch);
      expect(setupCatch, greaterThan(0));
      expect(setupFailureClass, greaterThan(setupCatch));
      expect(
        app.substring(setupCatch, setupFailureClass),
        isNot(contains('error.runtimeType')),
      );
      expect(
        app.substring(setupCatch, setupFailureClass),
        isNot(contains('error.toString')),
      );
      expect(app, contains('_maliciousDecryptedName'));
      expect(app, contains('_deleteSyntheticNotificationClaims'));
      expect(app, contains('boundedReactionEventIdentity(eventId)'));
      expect(app, contains("'tc256-reaction-\${targetId.substring"));
      expect(app, contains('envelope.eventId?.trim()'));
      expect(app, contains('tc256_cleanup_index.json'));
      expect(app, contains('_deleteSyntheticStagedEnvelopes'));
      expect(app, contains('_restoreRecentGateBaseline'));
      expect(app, contains('mknoon_recent_background_notifications.json'));
      expect(app, contains('mknoon_recent_remote_notifications.json'));
      expect(app, contains("'dedupeGatesRestored': 2"));
      expect(app, contains("'privateBundleDeleted': true"));
      expect(app, contains('final rawBytes = await command.readAsBytes()'));
      expect(app, contains('sha256.convert(rawBytes).toString()'));
      expect(app, contains("'commandSha256': cleanupCommand.rawSha256"));
      expect(app, contains("'commandSha256': command.rawSha256"));
      expect(app, isNot(contains('openEncryptedDatabase(')));
      expect(app, contains("rawQuery('PRAGMA user_version')"));
      expect(app, contains("rawQuery('PRAGMA busy_timeout = 5000')"));
      expect(app, isNot(contains("execute('PRAGMA busy_timeout = 5000')")));
      expect(app, contains('version != currentIdentityDatabaseVersion'));
      expect(app, contains("'group_message_local_deletions'"));

      expect(controller, contains("['am', 'kill', appPackage]"));
      expect(controller, contains('_waitForProcessAndTaskAbsent()'));
      expect(controller, contains('backgroundCryptoCleanupEvidenceFromLog('));
      expect(controller, contains('commandId: commandId'));
      expect(controller, contains('commandSha256: commandReceipt.sha256'));
      expect(controller, contains("'ro.product.cpu.abi'"));
      expect(controller, contains("'x86_64' => 'android-x64'"));
      expect(
        controller,
        contains('extractBackgroundNotificationShownPayload('),
      );
      expect(controller, contains('card.category != expectedCategory'));
      expect(controller, contains('_conversationNotificationIds'));
      expect(controller, contains('forbiddenDisplayValues.any'));
      expect(controller, contains('_exerciseNegativeAuthorizationCase'));
      expect(controller, contains('NotificationServiceDedupe'));
      expect(controller, contains('NotificationToneLeases'));
      expect(controller, contains("'cleanup_private_bundle'"));
      expect(controller, contains('_restoreNotificationPermission()'));
      expect(
        controller,
        contains('copyBackgroundCryptoCommandBytesToAppPrivateFile('),
      );
      expect(controller, contains('backgroundCryptoCleanupEvidenceFromLog('));
      expect(controller, isNot(contains("'sh', '-c'")));
      expect(controller, isNot(contains('| base64')));
      expect(controller, isNot(contains(r'> $_postForegroundMarker')));

      final cleanupOnlyBranch = controller.indexOf('if (cleanupOnly) {');
      final cleanupOnlyReturn = controller.indexOf(
        'return;',
        cleanupOnlyBranch,
      );
      final providerTemp = controller.indexOf(
        "'mknoon-tc256-fcm-'",
        cleanupOnlyReturn,
      );
      expect(cleanupOnlyBranch, greaterThan(0));
      expect(cleanupOnlyReturn, greaterThan(cleanupOnlyBranch));
      expect(providerTemp, greaterThan(cleanupOnlyReturn));

      final setupOnlyBranch = controller.indexOf('if (setupOnly) {');
      final setupOnlyCleanup = controller.indexOf(
        "_runCleanupCommand(mode: 'setup-only')",
        setupOnlyBranch,
      );
      final setupOnlyReturn = controller.indexOf('return;', setupOnlyCleanup);
      final providerPreflight = controller.indexOf(
        "stage = 'provider_preflight'",
        setupOnlyReturn,
      );
      final providerSend = controller.indexOf(
        '_sendPrivateProviderRequest(',
        providerPreflight,
      );
      expect(setupOnlyBranch, greaterThan(0));
      expect(setupOnlyCleanup, greaterThan(setupOnlyBranch));
      expect(setupOnlyReturn, greaterThan(setupOnlyCleanup));
      expect(providerPreflight, greaterThan(setupOnlyReturn));
      expect(providerTemp, greaterThan(setupOnlyReturn));
      expect(providerSend, greaterThan(providerPreflight));
      expect(controller, contains('!resetOnly &&'));

      final setupCheckpoint = controller.indexOf(
        'if (primaryFailure != null) {',
      );
      final checkpointWrite = controller.indexOf(
        'writeFailure(_CampaignCompositeFailure(primary: primaryFailure))',
        setupCheckpoint,
      );
      final recovery = controller.indexOf(
        '_attemptPreRestorationCleanup()',
        checkpointWrite,
      );
      expect(setupCheckpoint, greaterThan(0));
      expect(checkpointWrite, greaterThan(setupCheckpoint));
      expect(recovery, greaterThan(checkpointWrite));

      expect(provider, contains("kind === 'chat'"));
      expect(provider, contains("? 'new_message'"));
      expect(provider, contains(": 'group_message'"));
      expect(provider, contains("'announcement'"));
      expect(provider, contains("privateRequest && mode !== 'data-only'"));
      expect(provider, contains('validatePrivateTransportContract'));
      expect(provider, contains("'sender_transport_peer_id'"));
    },
  );

  test(
    'cleanup-only opener mirrors production query-safe DB configuration',
    () {
      final app = File(
        'integration_test/android_background_crypto_preflight_app.dart',
      ).readAsStringSync();
      final production = File(
        'lib/core/database/encrypted_db_opener.dart',
      ).readAsStringSync();
      final localDeletionMigration = File(
        'lib/core/database/migrations/069_group_message_local_deletions.dart',
      ).readAsStringSync();

      expect(production, contains("rawQuery('PRAGMA busy_timeout = 5000')"));
      expect(
        production,
        isNot(contains("execute('PRAGMA busy_timeout = 5000')")),
      );
      final open = app.indexOf('final candidate = await openDatabase(');
      final configure = app.indexOf(
        "rawQuery('PRAGMA busy_timeout = 5000')",
        open,
      );
      final keyValidation = app.indexOf(
        "rawQuery('SELECT count(*) FROM sqlite_master')",
        configure,
      );
      final versionGuard = app.indexOf(
        "rawQuery('PRAGMA user_version')",
        keyValidation,
      );
      expect(open, greaterThan(0));
      expect(configure, greaterThan(open));
      expect(keyValidation, greaterThan(configure));
      expect(versionGuard, greaterThan(keyValidation));
      expect(app, isNot(contains("execute('PRAGMA busy_timeout = 5000')")));

      expect(
        localDeletionMigration,
        contains('CREATE TABLE IF NOT EXISTS group_message_local_deletions'),
      );
      expect(localDeletionMigration, contains('group_id TEXT NOT NULL'));
      final deleteMessages = app.indexOf('dbDeleteGroupMessagesForGroup(');
      final deleteTombstones = app.indexOf(
        "'group_message_local_deletions'",
        deleteMessages,
      );
      final deleteKeys = app.indexOf('dbDeleteAllGroupKeys(', deleteTombstones);
      expect(deleteTombstones, greaterThan(deleteMessages));
      expect(deleteKeys, greaterThan(deleteTombstones));
      expect(
        app.substring(deleteTombstones, deleteKeys),
        contains("where: 'group_id = ?'"),
      );
      expect(
        app.substring(app.indexOf('Future<int> _countReservedDatabaseRows')),
        contains("'group_message_local_deletions'"),
      );
    },
  );

  test('cleanup failures cannot bypass APK and local artifact restoration', () {
    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    final tempDelete = controller.indexOf('await temp.delete(recursive: true)');
    final broadCleanupCatch = controller.indexOf("'cleanup_before_restore'");
    final restoreInstalled = controller.indexOf(
      "stage = 'restore_installed_app'",
      broadCleanupCatch,
    );
    final restoreLocal = controller.indexOf(
      'await _restoreLocalBuildArtifact()',
      restoreInstalled,
    );
    expect(tempDelete, greaterThan(0));
    expect(broadCleanupCatch, greaterThan(tempDelete));
    expect(restoreInstalled, greaterThan(broadCleanupCatch));
    expect(restoreLocal, greaterThan(restoreInstalled));
    expect(
      controller.substring(tempDelete, restoreInstalled),
      contains('cleanupFailure ??='),
    );
  });

  test('restoration baselines and cleanup classification fail closed', () {
    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    final app = File(
      'integration_test/android_background_crypto_preflight_app.dart',
    ).readAsStringSync();

    final captureStart = controller.indexOf(
      'Future<void> _captureNotificationPermission()',
    );
    final permissionRead = controller.indexOf(
      'final granted = await _isNotificationPermissionGranted()',
      captureStart,
    );
    final captureCommit = controller.indexOf(
      '_notificationPermissionCaptured = true',
      permissionRead,
    );
    expect(permissionRead, greaterThan(captureStart));
    expect(captureCommit, greaterThan(permissionRead));

    final installAttempt = controller.indexOf('_replacementAttempted = true');
    final install = controller.indexOf(
      "await _adb(['install', '-r', '-t', '-d'",
      installAttempt,
    );
    final installed = controller.indexOf('_preflightInstalled = true', install);
    expect(installAttempt, greaterThan(0));
    expect(install, greaterThan(installAttempt));
    expect(installed, greaterThan(install));
    expect(
      controller,
      contains('if (!_replacementAttempted || _installedAppApks.isEmpty)'),
    );

    expect(
      app,
      allOf(
        contains('validateBackgroundCryptoPreflightBundle('),
        contains('requireReaction: _ordinaryOnly ? false : null'),
      ),
    );
    expect(app, contains('cannot classify staged envelope:'));
    expect(app, contains('cannot classify notification ID owner:'));
    expect(app, contains('exactClaimNames: boundedReactionClaimNames'));
    expect(app, contains('boundedReactionClaimNames'));
  });

  test('private bundle deletion is acknowledged and verified before pass', () {
    final app = File(
      'integration_test/android_background_crypto_preflight_app.dart',
    ).readAsStringSync();
    final controller = File(
      'integration_test/scripts/capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    final support = File(
      'integration_test/scripts/reaction_notification_proof_support.dart',
    ).readAsStringSync();
    final cleanupCall = app.indexOf(
      'final cleanup = await _performReservedCleanup',
    );
    final marker = app.indexOf("_marker('cleanup_complete'", cleanupCall);
    final cleanupImplementation = app.indexOf(
      'Future<Map<String, Object?>> _performReservedCleanup',
    );
    final delete = app.indexOf(
      'await privateBundle.delete()',
      cleanupImplementation,
    );
    final verification = app.indexOf(
      'final verification = await _verifyReservedCleanup',
      delete,
    );
    expect(cleanupCall, greaterThan(0));
    expect(marker, greaterThan(cleanupCall));
    expect(cleanupImplementation, greaterThan(marker));
    expect(delete, greaterThan(0));
    expect(verification, greaterThan(delete));
    expect(app.substring(delete, verification), contains('commandFile.delete'));

    final acknowledged = support.indexOf(
      "complete['privateBundleDeleted'] != true",
    );
    final postForeground = controller.indexOf(
      "stage = 'post_foreground_callback'",
    );
    final cleanupRun = controller.indexOf(
      '_runCleanupCommand(',
      postForeground,
    );
    final probe = controller.indexOf(
      'await _verifyPrivateBundleAbsent()',
      cleanupRun,
    );
    final confirmed = controller.indexOf(
      '_syntheticCleanupConfirmed = true',
      probe,
    );
    expect(acknowledged, greaterThan(0));
    expect(postForeground, greaterThan(0));
    expect(cleanupRun, greaterThan(postForeground));
    expect(probe, greaterThan(cleanupRun));
    expect(confirmed, greaterThan(probe));
  });
}

Map<String, dynamic> _validBundle() {
  return <String, dynamic>{
    'schema': backgroundCryptoPreflightBundleSchema,
    'token': 'private-token',
    'reaction': <String, dynamic>{
      'data': <String, dynamic>{
        'type': 'message_reaction',
        'sender_id': backgroundCryptoPreflightActorPeerId,
        'event_id': 'tc256-reaction-1',
        'target_message_id': 'tc256-target-1',
        'action': 'add',
        'kem': 'kem',
        'ciphertext': 'ciphertext',
        'nonce': 'nonce',
      },
    },
    'ordinaryCases': <Map<String, dynamic>>[
      for (final row in backgroundCryptoPreflightOrdinaryRows)
        <String, dynamic>{
          ...row.toJson(),
          'conversationKey': _conversationKey(row),
          'messageId': _messageId(row),
          'expectedTitle': switch (row.context) {
            'direct' => backgroundCryptoPreflightDirectTrustedTitle,
            'group' => backgroundCryptoPreflightGroupTrustedTitle,
            _ => backgroundCryptoPreflightAnnouncementTrustedTitle,
          },
          'expectedBody': row.modality == 'text'
              ? row.context == 'direct'
                    ? 'TC256 encrypted direct text'
                    : '$backgroundCryptoPreflightDirectTrustedTitle: '
                          'TC256 encrypted ${row.context} text'
              : row.context == 'direct'
              ? 'localized-${row.modality}'
              : '$backgroundCryptoPreflightDirectTrustedTitle: '
                    'localized-${row.modality}',
          'expectedPayload': row.context == 'direct'
              ? backgroundCryptoPreflightActorPeerId
              : '${_conversationKey(row)}|message:${_messageId(row)}',
          'expectedCategory': 'msg',
          if (row.context != 'direct')
            'trustedActorAccountPeerId': backgroundCryptoPreflightActorPeerId,
          if (row.context != 'direct')
            'trustedActorTransportPeerId':
                backgroundCryptoPreflightActorTransportPeerId,
          if (row.context != 'direct')
            'trustedActorRole': row.context == 'announcement'
                ? 'admin'
                : 'writer',
          if (row.context != 'direct')
            'trustedActorName': backgroundCryptoPreflightDirectTrustedTitle,
          'forbiddenDisplayValues': const <String>[
            backgroundCryptoPreflightMaliciousOuterName,
            backgroundCryptoPreflightMaliciousDecryptedName,
            backgroundCryptoPreflightMaliciousDecryptedGroupName,
          ],
          'data': <String, dynamic>{
            'type': row.remoteType,
            if (row.context == 'direct')
              'sender_id': backgroundCryptoPreflightActorPeerId,
            if (row.context != 'direct')
              'groupId': _groupIdForContext(row.context),
            if (row.context != 'direct')
              'sender_transport_peer_id':
                  backgroundCryptoPreflightActorTransportPeerId,
            'message_id': _messageId(row),
            if (row.context == 'direct') 'kem': 'kem-${row.id}',
            if (row.context != 'direct') 'keyEpoch': '7',
            'ciphertext': 'ciphertext-${row.id}',
            'nonce': 'nonce-${row.id}',
          },
        },
    ],
    'negativeCases': <Map<String, dynamic>>[
      for (final row in backgroundCryptoPreflightNegativeRows)
        <String, dynamic>{
          ...row.toJson(),
          'remoteType': 'group_message',
          'conversationKey': 'group:${_groupIdForContext(row.context)}',
          'messageId': _negativeMessageId(row),
          'expectedSuppressionReason': 'group_message_local_state_ineligible',
          'data': <String, dynamic>{
            'type': 'group_message',
            'groupId': _groupIdForContext(row.context),
            'message_id': _negativeMessageId(row),
            if (row.rejectionReason == 'unknown_transport')
              'sender_transport_peer_id':
                  backgroundCryptoPreflightUnknownTransportPeerId,
            if (row.rejectionReason == 'non_admin_announcement')
              'sender_transport_peer_id':
                  backgroundCryptoPreflightNonAdminTransportPeerId,
            'keyEpoch': '7',
            'ciphertext': 'negative-ciphertext-${row.id}',
            'nonce': 'negative-nonce-${row.id}',
          },
        },
    ],
  };
}

Map<String, dynamic> _validUnregisteredProviderArtifact() => <String, dynamic>{
  'testCase': 'TC-07-provider-diagnostic',
  'scenario': 'android_provider_validate_only',
  'schema': backgroundCryptoProviderDiagnosticArtifactSchema,
  'status': 'completed',
  'capturedAt': '2026-07-13T12:00:00.000Z',
  'mode': 'provider-diagnostic-only',
  'setupReady': true,
  'fixtureCaseId': 'direct-text',
  'providerValidationAttempts': 1,
  'providerValidationSucceeded': 0,
  'subjectTokenSha256': sha256
      .convert(utf8.encode('stale-private-token'))
      .toString(),
  'providerDiagnostic': <String, Object?>{
    'schema': backgroundCryptoProviderResultSchema,
    'ok': false,
    'stage': 'fcm',
    'operation': 'validate_only',
    'validateOnly': true,
    'validationResult': 'rejected',
    'httpClass': '4xx',
    'httpStatus': 404,
    'rpcStatus': 'NOT_FOUND',
    'reason': 'UNREGISTERED',
    'requestIdSha256': null,
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
    'clearNotificationsMarkerDeleted': true,
    'privateProviderTempDeleted': true,
    'installedCandidateRestored': true,
    'localBuildArtifactRestoredToPriorState': true,
    'notificationPermissionRestored': true,
  },
  'redaction': <String, Object?>{},
  'containsSecrets': false,
  'privateProviderTempDeleted': true,
  'successfulRestorationEvidence': <String, Object?>{},
};

Map<String, dynamic> _copy(Map<String, dynamic> source) =>
    jsonDecode(jsonEncode(source)) as Map<String, dynamic>;

String _groupIdForContext(String context) => context == 'group'
    ? backgroundCryptoPreflightGroupId
    : backgroundCryptoPreflightAnnouncementId;

String _conversationKey(BackgroundCryptoPreflightRow row) =>
    row.context == 'direct'
    ? backgroundCryptoPreflightActorPeerId
    : 'group:${_groupIdForContext(row.context)}';

String _messageId(BackgroundCryptoPreflightRow row) =>
    'tc256-${row.context}-${row.modality}-message';

String _negativeMessageId(BackgroundCryptoPreflightNegativeRow row) =>
    'tc256-${row.context}-negative-${row.rejectionReason}-message';

String _boundedClaimName(String eventId) =>
    DurableNotificationToneLease.messageEventClaimFileName(
      type: 'message_reaction',
      eventIdentity: boundedReactionEventIdentity(eventId),
    );

class _FailOnSecondTraversalBytes extends ListBase<int> {
  _FailOnSecondTraversalBytes(this._values);

  final List<int> _values;
  var _reads = 0;

  @override
  int get length => _values.length;

  @override
  set length(int value) => throw UnsupportedError('fixed test bytes');

  @override
  int operator [](int index) {
    if (_reads++ >= _values.length) {
      throw const FileSystemException('synthetic host write failure');
    }
    return _values[index];
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('fixed test bytes');
}
