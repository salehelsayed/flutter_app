import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/reaction_notification_proof_support.dart';

void main() {
  group('direct-text relay token receipt', () {
    final now = DateTime.utc(2026, 7, 13, 3, 30);
    const commandId = 'direct-text-relay-1783913400000000-12345';
    const commandSha256 =
        '1111111111111111111111111111111111111111111111111111111111111111';
    const tokenSha256 =
        '2222222222222222222222222222222222222222222222222222222222222222';
    const tokenGenerationId = 'tc256-token-refresh-1783913400000000-67890';
    const refreshArtifactSha256 =
        '3333333333333333333333333333333333333333333333333333333333333333';
    const gateAArtifactSha256 =
        '4444444444444444444444444444444444444444444444444444444444444444';
    const accountIdentitySha256 =
        '5555555555555555555555555555555555555555555555555555555555555555';
    const transportIdentitySha256 = accountIdentitySha256;

    Map<String, Object?> validReceipt() => <String, Object?>{
      'schema': directTextRelayTokenProofReceiptSchema,
      'status': 'completed',
      'completedAt': now.toIso8601String(),
      'commandId': commandId,
      'commandSha256': commandSha256,
      'tokenSha256': tokenSha256,
      'tokenGenerationId': tokenGenerationId,
      'refreshArtifactSha256': refreshArtifactSha256,
      'gateAArtifactSha256': gateAArtifactSha256,
      'accountIdentitySha256': accountIdentitySha256,
      'transportIdentitySha256': transportIdentitySha256,
      'tokenSha256Matched': true,
      'commandDeleted': true,
      'containsSecrets': false,
    };

    Map<String, Object?> parse(Map<String, Object?> receipt) =>
        parseDirectTextRelayTokenProofReceipt(
          utf8.encode(jsonEncode(receipt)),
          now: now,
          commandId: commandId,
          commandSha256: commandSha256,
          tokenSha256: tokenSha256,
          tokenGenerationId: tokenGenerationId,
          refreshArtifactSha256: refreshArtifactSha256,
          gateAArtifactSha256: gateAArtifactSha256,
          accountIdentitySha256: accountIdentitySha256,
          transportIdentitySha256: transportIdentitySha256,
        );

    test('accepts only the exact fresh hash-bound receipt', () {
      final receipt = parse(validReceipt());
      expect(receipt['tokenSha256Matched'], isTrue);
      expect(receipt['containsSecrets'], isFalse);
    });

    test('rejects extra, stale, and mismatched receipts', () {
      expect(
        () => parse(validReceipt()..['rawToken'] = 'secret'),
        throwsFormatException,
      );
      expect(
        () => parse(
          validReceipt()
            ..['completedAt'] = now
                .subtract(const Duration(minutes: 6))
                .toIso8601String(),
        ),
        throwsFormatException,
      );
      expect(
        () => parse(validReceipt()..['tokenSha256'] = '4' * 64),
        throwsFormatException,
      );
    });

    test('allows only bounded device-to-host future clock skew', () {
      final future = validReceipt()
        ..['completedAt'] = now
            .add(const Duration(seconds: 2))
            .toIso8601String();
      expect(parse(future), containsPair('status', 'completed'));

      future['completedAt'] = now
          .add(const Duration(seconds: 6))
          .toIso8601String();
      expect(() => parse(future), throwsFormatException);
    });
  });

  group('direct-text relay token receipt v2', () {
    final now = DateTime.utc(2026, 7, 13, 6, 30);
    const commandId = 'direct-text-relay-1783924200000000-12345';
    const commandSha256 =
        '1111111111111111111111111111111111111111111111111111111111111111';
    const tokenSha256 =
        '2222222222222222222222222222222222222222222222222222222222222222';
    const authorizationArtifactSha256 =
        '3333333333333333333333333333333333333333333333333333333333333333';
    const generationId = 'tc256-gate-a-command-1783924200000000-67890';
    const gateAArtifactSha256 =
        '4444444444444444444444444444444444444444444444444444444444444444';
    const accountIdentitySha256 =
        '5555555555555555555555555555555555555555555555555555555555555555';
    const transportIdentitySha256 = accountIdentitySha256;

    Map<String, Object?> validReceipt() => <String, Object?>{
      'schema': directTextRelayTokenProofReceiptSchemaV2,
      'status': 'completed',
      'completedAt': now.toIso8601String(),
      'commandId': commandId,
      'commandSha256': commandSha256,
      'tokenSha256': tokenSha256,
      'authorizationKind': backgroundCryptoCurrentTokenAuthorizationKind,
      'authorizationArtifactSha256': authorizationArtifactSha256,
      'gateACommandGenerationId': generationId,
      'gateAArtifactSha256': gateAArtifactSha256,
      'accountIdentitySha256': accountIdentitySha256,
      'transportIdentitySha256': transportIdentitySha256,
      'tokenSha256Matched': true,
      'commandDeleted': true,
      'containsSecrets': false,
    };

    Map<String, Object?> parse(Map<String, Object?> receipt) =>
        parseDirectTextRelayTokenProofReceiptV2(
          utf8.encode(jsonEncode(receipt)),
          now: now,
          commandId: commandId,
          commandSha256: commandSha256,
          tokenSha256: tokenSha256,
          authorizationKind: backgroundCryptoCurrentTokenAuthorizationKind,
          authorizationArtifactSha256: authorizationArtifactSha256,
          gateACommandGenerationId: generationId,
          gateAArtifactSha256: gateAArtifactSha256,
          accountIdentitySha256: accountIdentitySha256,
          transportIdentitySha256: transportIdentitySha256,
        );

    test('accepts exact current-token authorization receipt', () {
      final receipt = parse(validReceipt());
      expect(receipt['tokenSha256Matched'], isTrue);
      expect(receipt, isNot(contains('refreshArtifactSha256')));
      expect(receipt, isNot(contains('tokenGenerationId')));
    });

    test('rejects stale, legacy, mismatched, and forged receipts', () {
      for (final mutation in <void Function(Map<String, Object?>)>[
        (value) => value['completedAt'] = now
            .subtract(const Duration(minutes: 6))
            .toIso8601String(),
        (value) => value['schema'] = directTextRelayTokenProofReceiptSchema,
        (value) => value['authorizationKind'] = 'forced_reregistration',
        (value) => value['authorizationArtifactSha256'] = '6' * 64,
        (value) => value['gateACommandGenerationId'] =
            'tc256-token-refresh-1783924200000000-67890',
        (value) => value['gateAArtifactSha256'] = '7' * 64,
        (value) => value['accountIdentitySha256'] = '8' * 64,
        (value) => value['transportIdentitySha256'] = '9' * 64,
        (value) => value['rawToken'] = 'secret',
      ]) {
        final receipt = validReceipt();
        mutation(receipt);
        expect(() => parse(receipt), throwsFormatException);
      }
    });
  });

  group('Android cold local notification-open evidence', () {
    const expectedPeerId = '12D3KooWExpectedPeer';
    final expectedPeerBytes = utf8.encode(expectedPeerId);
    final expectedPeerSha256 = sha256.convert(expectedPeerBytes).toString();

    String flow(String event, Map<String, Object?> details) =>
        'I/flutter (123): [FLOW] ${jsonEncode(<String, Object?>{'layer': 'FL', 'event': event, 'details': details})}';

    Map<String, Object?> validParsedRouteDetails() => <String, Object?>{
      'payloadSha256': expectedPeerSha256,
      'payloadUtf8Length': expectedPeerBytes.length,
      'routeKind': 'conversation',
      'peerSha256': expectedPeerSha256,
      'canonicalPayloadMatched': true,
    };

    List<String> validLines() => <String>[
      flow(
        androidColdLocalNotificationParsedRouteEvent,
        validParsedRouteDetails(),
      ),
      flow('CHAT_MSG_LOAD_PAGE_START', <String, Object?>{
        'contactPeerId': expectedPeerId.substring(0, 10),
        'pageSize': 50,
        'hasCursor': false,
      }),
      flow('NOTIFICATION_TAP_TO_MESSAGE_TIMING', <String, Object?>{
        'elapsedMs': 412,
        'routeKind': 'conversation',
        'milestone': 'stale_render',
        'messageId': '',
      }),
      flow('CONV_FL_NOTIF_DRAIN_REFETCH', <String, Object?>{
        'trigger': 'notif_tap',
        'before': 1,
        'after': 2,
        'drainMs': 37,
      }),
    ];

    test(
      'accepts exact consumed payload while dumpsys payload is unavailable',
      () {
        final evidence = parseAndroidColdLocalNotificationOpenEvidence(
          <String>['noise', ...validLines(), 'trailing noise'].join('\n'),
          expectedPeerId: expectedPeerId,
          tappedRoutePayload: null,
        );

        expect(evidence.isComplete, isTrue);
        expect(evidence.hasTerminalFailure, isFalse);
        expect(evidence.exactRoutePayloadMatched, isTrue);
        expect(evidence.parsedRouteMarkerCount, 1);
        expect(evidence.routePayloadSha256, expectedPeerSha256);
        expect(evidence.routePayloadUtf8Length, expectedPeerBytes.length);
        expect(evidence.parsedRouteKind, 'conversation');
        expect(evidence.parsedPeerSha256, expectedPeerSha256);
        expect(evidence.canonicalPayloadMatched, isTrue);
        expect(evidence.cardRoutePayloadAvailable, isFalse);
        expect(evidence.timingElapsedMs, 412);
        expect(evidence.drainReloadMs, 37);
        expect(evidence.toJson(), containsPair('passed', true));
        expect(
          evidence.toJson(),
          containsPair('source', 'production_main_local_notification'),
        );
        final encoded = jsonEncode(evidence.toJson());
        expect(encoded, isNot(contains(expectedPeerId)));
        expect(encoded, isNot(contains(expectedPeerId.substring(0, 10))));
      },
    );

    test('dumpsys payload is optional diagnostics and never decides route', () {
      for (final cardPayload in <String?>[
        null,
        '',
        expectedPeerId,
        'unrelated-dumpsys-value',
      ]) {
        final evidence = parseAndroidColdLocalNotificationOpenEvidence(
          validLines().join('\n'),
          expectedPeerId: expectedPeerId,
          tappedRoutePayload: cardPayload,
        );

        expect(
          evidence.isComplete,
          isTrue,
          reason: 'card payload must be non-authoritative: $cardPayload',
        );
        expect(
          evidence.cardRoutePayloadAvailable,
          cardPayload?.trim().isNotEmpty == true,
        );
        expect(
          evidence.cardRoutePayloadSha256,
          cardPayload?.trim().isNotEmpty == true
              ? sha256.convert(utf8.encode(cardPayload!.trim())).toString()
              : isNull,
        );
      }
    });

    test('retained tap-flow evidence is privacy-total across event families', () {
      final peerPrefix = expectedPeerId.substring(0, 10);
      final shortPeerPrefix = expectedPeerId.substring(0, 8);
      final sanitized = sanitizeAndroidColdLocalNotificationRouteEvidence(
        <String>[
          ...validLines(),
          flow(androidColdLocalNotificationParsedRouteEvent, <String, Object?>{
            ...validParsedRouteDetails(),
            'payload': expectedPeerId,
            'peerId': peerPrefix,
          }),
          'I/flutter: [FLOW] {"layer":"FL","event":"CHAT_MSG_LOAD_PAGE_START","details":{"contactPeerId":"$peerPrefix"',
          flow('NOTIFICATION_TAPPED', <String, Object?>{
            'payload': expectedPeerId,
          }),
          flow('NOTIFICATION_SHOWN', <String, Object?>{
            'contactPeerId': peerPrefix,
            'sender': expectedPeerId,
            'payload': expectedPeerId,
          }),
          flow(
            'CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE',
            <String, Object?>{'peerId': shortPeerPrefix},
          ),
          flow('REMOTE_NOTIFICATION_ROUTE_ERROR', <String, Object?>{
            'payload': expectedPeerId,
          }),
          flow('NOTIFICATION_TAP_NAV_ERROR', <String, Object?>{
            'error': expectedPeerId,
          }),
          flow('CONV_FL_LOAD_ERROR', <String, Object?>{'error': peerPrefix}),
          flow('NOTIFICATION_TAP_TO_MESSAGE_TIMING', <String, Object?>{
            'elapsedMs': 12,
            'routeKind': 'conversation',
            'milestone': 'stale_render',
            'messageId': expectedPeerId,
          }),
          flow('CONV_FL_NOTIF_DRAIN_REFETCH', <String, Object?>{
            'trigger': 'notif_tap',
            'before': expectedPeerId,
            'after': peerPrefix,
            'drainMs': 7,
          }),
          'raw NOTIFICATION_SHOWN $expectedPeerId',
          'unrelated $expectedPeerId',
        ].join('\n'),
      );

      expect(sanitized, contains(androidColdLocalNotificationParsedRouteEvent));
      expect(sanitized, contains('CHAT_MSG_LOAD_PAGE_START'));
      expect(sanitized, contains('CHAT_MSG_LOAD_PAGE_REDACTED'));
      expect(sanitized, contains('"pageSize":50'));
      expect(sanitized, contains('"hasCursor":false'));
      expect(sanitized, contains('NOTIFICATION_TAP_TO_MESSAGE_TIMING'));
      expect(sanitized, contains('CONV_FL_NOTIF_DRAIN_REFETCH'));
      expect(sanitized, contains('NOTIFICATION_TAPPED'));
      expect(sanitized, contains('NOTIFICATION_SHOWN'));
      expect(
        sanitized,
        contains('CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE'),
      );
      expect(sanitized, contains('NOTIFICATION_ROUTE_EVIDENCE_REDACTED'));
      expect(sanitized, isNot(contains('contactPeerId')));
      expect(sanitized, isNot(contains('"payload":')));
      expect(sanitized, isNot(contains('"peerId":')));
      expect(sanitized, isNot(contains('"sender":')));
      expect(sanitized, isNot(contains('"messageId":')));
      expect(sanitized, isNot(contains('"before":')));
      expect(sanitized, isNot(contains('"after":')));
      expect(sanitized, isNot(contains('"error":')));
      expect(sanitized, isNot(contains(shortPeerPrefix)));
      expect(sanitized, isNot(contains(peerPrefix)));
      expect(sanitized, isNot(contains(expectedPeerId)));
    });

    test('each causal positive is independently required', () {
      final lines = validLines();
      for (var omitted = 0; omitted < lines.length; omitted++) {
        final evidence = parseAndroidColdLocalNotificationOpenEvidence(
          <String>[
            for (var index = 0; index < lines.length; index++)
              if (index != omitted) lines[index],
          ].join('\n'),
          expectedPeerId: expectedPeerId,
          tappedRoutePayload: null,
        );
        expect(
          evidence.isComplete,
          isFalse,
          reason: 'omitted causal line $omitted must prevent PASS',
        );
      }
    });

    test('every parsed-route field and exact key set is fail-closed', () {
      final mutations = <void Function(Map<String, Object?>)>[
        (details) => details['payloadSha256'] = '0' * 64,
        (details) => details['payloadSha256'] = 'not-a-hash',
        (details) =>
            details['payloadUtf8Length'] = expectedPeerBytes.length + 1,
        (details) =>
            details['payloadUtf8Length'] = '${expectedPeerBytes.length}',
        (details) => details['routeKind'] = 'group',
        (details) => details['routeKind'] = expectedPeerId,
        (details) => details['peerSha256'] = '1' * 64,
        (details) => details['peerSha256'] = null,
        (details) => details['canonicalPayloadMatched'] = false,
        (details) => details['canonicalPayloadMatched'] = 'true',
        (details) => details.remove('payloadSha256'),
        (details) => details['peerId'] = expectedPeerId,
      ];

      for (final mutate in mutations) {
        final details = validParsedRouteDetails();
        mutate(details);
        final evidence = parseAndroidColdLocalNotificationOpenEvidence(
          <String>[
            flow(androidColdLocalNotificationParsedRouteEvent, details),
            ...validLines().skip(1),
          ].join('\n'),
          expectedPeerId: expectedPeerId,
          tappedRoutePayload: null,
        );

        expect(evidence.exactRoutePayloadMatched, isFalse);
        expect(evidence.routeTargetMismatch, isTrue);
        expect(evidence.hasTerminalFailure, isTrue);
        expect(evidence.isComplete, isFalse);
      }
    });

    test('missing, duplicate, conflicting, and malformed markers cannot pass', () {
      final missing = parseAndroidColdLocalNotificationOpenEvidence(
        '',
        expectedPeerId: expectedPeerId,
        tappedRoutePayload: null,
      );
      expect(missing.parsedRouteMarkerCount, 0);
      expect(missing.isComplete, isFalse);
      expect(missing.hasTerminalFailure, isFalse);

      final conflictingDetails = validParsedRouteDetails()
        ..['payloadSha256'] = '2' * 64;
      for (final lines in <List<String>>[
        <String>[
          validLines().first,
          validLines().first,
          ...validLines().skip(1),
        ],
        <String>[
          validLines().first,
          flow(
            androidColdLocalNotificationParsedRouteEvent,
            conflictingDetails,
          ),
          ...validLines().skip(1),
        ],
        <String>[
          'I/flutter: [FLOW] {"layer":"FL","event":"$androidColdLocalNotificationParsedRouteEvent","details":',
          ...validLines().skip(1),
        ],
        <String>[
          validLines().first,
          'I/flutter: [FLOW] {"event":"$androidColdLocalNotificationParsedRouteEvent',
          ...validLines().skip(1),
        ],
      ]) {
        final evidence = parseAndroidColdLocalNotificationOpenEvidence(
          lines.join('\n'),
          expectedPeerId: expectedPeerId,
          tappedRoutePayload: null,
        );
        expect(evidence.hasTerminalFailure, isTrue);
        expect(evidence.isComplete, isFalse);
      }
    });

    test('wrong loaded peer and any route/load/drain error veto proof', () {
      final wrongLoad = <String>[
        validLines().first,
        flow('CHAT_MSG_LOAD_PAGE_START', <String, Object?>{
          'contactPeerId': '12D3KooWWr',
          'pageSize': 50,
          'hasCursor': false,
        }),
        ...validLines().skip(2),
      ];
      final wrongPeer = parseAndroidColdLocalNotificationOpenEvidence(
        wrongLoad.join('\n'),
        expectedPeerId: expectedPeerId,
        tappedRoutePayload: null,
      );
      expect(wrongPeer.exactRoutePayloadMatched, isTrue);
      expect(wrongPeer.routeTargetMismatch, isTrue);
      expect(wrongPeer.hasTerminalFailure, isTrue);
      expect(wrongPeer.isComplete, isFalse);

      for (final errorEvent in androidColdLocalNotificationOpenErrorEvents) {
        final errored = parseAndroidColdLocalNotificationOpenEvidence(
          <String>[
            ...validLines(),
            // Raw substring detection is intentionally fail-closed even when
            // Android truncates the JSON tail of an error log line.
            'I/flutter: [FLOW] {"event":"$errorEvent"',
          ].join('\n'),
          expectedPeerId: expectedPeerId,
          tappedRoutePayload: null,
        );
        expect(errored.routeErrorEvents, contains(errorEvent));
        expect(errored.hasTerminalFailure, isTrue);
        expect(errored.isComplete, isFalse);
      }
    });

    test(
      'malformed timing and non-notification drain cannot satisfy proof',
      () {
        final evidence = parseAndroidColdLocalNotificationOpenEvidence(
          <String>[
            validLines().first,
            validLines()[1],
            flow('NOTIFICATION_TAP_TO_MESSAGE_TIMING', <String, Object?>{
              'elapsedMs': '412',
              'routeKind': 'conversation',
              'milestone': 'stale_render',
            }),
            flow('CONV_FL_NOTIF_DRAIN_REFETCH', <String, Object?>{
              'trigger': 'resume',
              'drainMs': -1,
            }),
          ].join('\n'),
          expectedPeerId: expectedPeerId,
          tappedRoutePayload: null,
        );

        expect(evidence.exactPeerRouteMatched, isTrue);
        expect(evidence.timingMatched, isFalse);
        expect(evidence.drainReloadMatched, isFalse);
        expect(evidence.isComplete, isFalse);
        expect(
          () => parseAndroidColdLocalNotificationOpenEvidence(
            '',
            expectedPeerId: ' ',
            tappedRoutePayload: null,
          ),
          throwsFormatException,
        );
      },
    );

    test('requires parsed marker before route load, timing, and drain', () {
      final lines = validLines();
      for (final reordered in <List<String>>[
        <String>[lines[1], lines[0], lines[2], lines[3]],
        <String>[lines[2], lines[0], lines[1], lines[3]],
        <String>[lines[0], lines[2], lines[1], lines[3]],
        <String>[lines[3], lines[0], lines[1], lines[2]],
      ]) {
        final evidence = parseAndroidColdLocalNotificationOpenEvidence(
          reordered.join('\n'),
          expectedPeerId: expectedPeerId,
          tappedRoutePayload: null,
        );

        expect(evidence.routeTargetMismatch, isTrue);
        expect(evidence.hasTerminalFailure, isTrue);
        expect(evidence.isComplete, isFalse);
      }
    });
  });

  test('TC-07 waits for cleanup acknowledgement before APK restoration', () {
    final source = File(
      'integration_test/scripts/'
      'capture_android_background_crypto_preflight.dart',
    ).readAsStringSync();
    final wait = source.indexOf(
      "description: 'acknowledged synthetic-state cleanup marker'",
    );
    final restore = source.indexOf("stage = 'restore_installed_app'");

    expect(wait, greaterThan(0));
    expect(restore, greaterThan(wait));
    expect(
      source.substring(wait, restore),
      isNot(contains('Duration(seconds: 2)')),
    );
  });

  test('Plan 256 live smoke validates typed copy before notification tap', () {
    final source = File(
      'integration_test/scripts/'
      'capture_1to1_reaction_head_provenance.dart',
    ).readAsStringSync();
    final mode = source.indexOf("args.contains('--live-typed-smoke')");
    final workingTreeBuild = source.indexOf('_buildWorkingTreeApks()');
    final typedValidation = source.indexOf(
      'validateDirectReactionNotificationCard(',
    );
    final tap = source.indexOf('_tapAndClassifyRoute(cards.single)');
    final unreadLifecycle = source.indexOf('_captureUnreadLifecycle()');

    expect(mode, greaterThan(0));
    expect(workingTreeBuild, greaterThan(mode));
    expect(typedValidation, greaterThan(workingTreeBuild));
    expect(tap, greaterThan(typedValidation));
    expect(unreadLifecycle, greaterThan(tap));
  });

  test('Plan 256 notification tap scrolls to the validated card body', () {
    final source = File(
      'integration_test/scripts/'
      'capture_1to1_reaction_head_provenance.dart',
    ).readAsStringSync();
    final methodStart = source.indexOf(
      'Future<(int, int)> _waitForNotificationCardInShade(',
    );
    final methodEnd = source.indexOf('File _writeRelayEvidence', methodStart);

    expect(methodStart, greaterThan(0));
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);
    expect(method, contains('findSemanticNodeCenter(xml, card.title)'));
    expect(method, contains('findSemanticNodeCenter(xml, card.body)'));
    expect(method, contains("'swipe'"));
    expect(method, contains("'1900'"));
    expect(method, contains("'700'"));
  });

  test('Plan 257 notification tap reaches a card below the visible shade', () {
    final source = File(
      'integration_test/scripts/'
      'capture_group_reaction_notification_device.dart',
    ).readAsStringSync();
    final methodStart = source.indexOf(
      'Future<void> _dismissNotificationCard()',
    );
    final methodEnd = source.indexOf(
      'Future<void> _terminateAndroidRecipient()',
      methodStart,
    );

    expect(methodStart, greaterThan(0));
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);
    expect(
      method,
      contains('Future<(int, int)> _waitForNotificationCardInShade()'),
    );
    expect(method, contains('findSemanticNodeCenter(xml, _groupName)'));
    expect(method, contains("'swipe'"));
    expect(method, contains("'1900'"));
    expect(method, contains("'700'"));
    expect(method, contains('await _waitForNotificationCardInShade()'));
  });

  test('Plan 257 group sends require a committed FLOW outcome', () {
    final source = File(
      'integration_test/scripts/'
      'capture_group_reaction_notification_device.dart',
    ).readAsStringSync();
    final methodStart = source.indexOf('Future<void> _sendGroupText(');
    final methodEnd = source.indexOf(
      'Future<void> _waitForGroupUnread',
      methodStart,
    );

    expect(methodStart, greaterThan(0));
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);
    expect(method, contains('enterGroupComposeMarkerOnce('));
    expect(
      method,
      contains('markerEntry != GroupComposeMarkerEntryOutcome.accepted'),
    );
    expect(method, contains('maximumFocusPolls: 80'));
    expect(method, contains('maximumAcceptancePolls: 80'));
    expect(method, contains('group compose marker accepted on'));
    expect(method, isNot(contains('group compose draft restored on')));
    expect(method, contains('findEnabledFocusableGroupComposeEditorBounds('));
    expect(method, contains('requireFocused: true'));
    expect(method, contains('exactText: marker'));
    expect(method, contains('baselineOutcomeCount'));
    expect(method, contains('extractGroupSendTimingObservations('));
    expect(method, contains('outcome.isRecoveryPending'));
    expect(method, contains('outcome.hasRequiredInboxCustody('));
    expect(method, contains('findNodeBoundsByClassContainingText('));
    expect(method, isNot(contains('_waitForUiText(deviceId, marker')));
  });

  test(
    'Plan 257 SQLCipher probes cannot downgrade and erase candidate data',
    () {
      final source = File(
        'integration_test/scripts/'
        'capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf(
        'Future<_AndroidBuilds> _buildAndroidCandidate()',
      );
      final methodEnd = source.indexOf(
        'Future<String> _candidateProvenance()',
        methodStart,
      );

      expect(methodStart, greaterThan(0));
      expect(methodEnd, greaterThan(methodStart));
      final method = source.substring(methodStart, methodEnd);
      expect(method, isNot(contains("'--split-per-abi'")));
      expect(method, contains("'build/app/outputs/flutter-apk/app-debug.apk'"));
    },
  );

  test('Plan 257 process death falls back without force-stopping push', () {
    final source = File(
      'integration_test/scripts/'
      'capture_group_reaction_notification_device.dart',
    ).readAsStringSync();
    final methodStart = source.indexOf(
      'Future<void> _terminateAndroidRecipient()',
    );
    final methodEnd = source.indexOf(
      'Future<void> _waitForRelayTokenRegistration',
      methodStart,
    );

    expect(methodStart, greaterThan(0));
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);
    final kill = method.indexOf("'kill'");
    final stopApp = method.indexOf("'stop-app'");
    expect(kill, greaterThan(0));
    expect(stopApp, greaterThan(kill));
    expect(method, contains('_recipientProcessAbsentWithin'));
    expect(method, isNot(contains("'force-stop'")));
  });

  test('Plan 257 duplicate probe proves the stored envelope decrypts', () {
    final capture = File(
      'integration_test/scripts/'
      'capture_group_reaction_notification_device.dart',
    ).readAsStringSync();
    final probe = File(
      'integration_test/group_reaction_notification_sqlcipher_probe_test.dart',
    ).readAsStringSync();
    final appProbe = File(
      'lib/core/debug/group_reaction_e2e_probe.dart',
    ).readAsStringSync();

    expect(capture, contains("observation['storedEnvelopeDecryptOk'] != true"));
    expect(probe, contains('prepareExactGroupReactionAddRedrive('));
    expect(appProbe, contains('crypto.decryptGroup('));
    expect(appProbe, contains("'storedEnvelopeDecryptOk'"));
    expect(appProbe, contains('runGroupReactionE2EProbeAction('));

    final methodStart = capture.indexOf('Future<void> _redriveExactStoredAdd(');
    final methodEnd = capture.indexOf(
      'Future<void> _collectBoundedLogs()',
      methodStart,
    );
    expect(methodStart, greaterThan(0));
    expect(methodEnd, greaterThan(methodStart));
    final method = capture.substring(methodStart, methodEnd);
    expect(method, contains("'drive'"));
    expect(method, contains("'--keep-app-running'"));
    expect(method, contains("'test_driver/integration_test.dart'"));
    expect(method, contains('_runInstalledGroupReactionProbe('));
    expect(method, contains('if (noChildBuilds)'));
    expect(method, isNot(contains("'test',\n")));
  });

  test('Plan 257 installed-app probe is wired before generic E2E actions', () {
    final runner = File(
      'lib/core/debug/intro_e2e_runner.dart',
    ).readAsStringSync();
    final productionSource = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    final compositionSource = File(
      'lib/debug/debug_e2e_composition_root.dart',
    ).readAsStringSync();
    final probeBranch = runner.indexOf('isGroupReactionE2EProbeAction(');
    final genericActions = runner.indexOf(
      'await runIntroE2EActions(',
      probeBranch,
    );

    expect(probeBranch, greaterThan(0));
    expect(genericActions, greaterThan(probeBranch));
    expect(runner, contains('runGroupReactionE2EProbeAction('));
    expect(runner, contains('groupReactionProbeDatabase'));
    expect(runner, contains('groupReactionProbeSecureKeyStore'));
    expect(
      productionSource,
      contains('if (debugE2EComposition?.startsIntroPoller ?? false) {'),
    );
    expect(
      productionSource,
      contains('debugE2EComposition!.startIntroPollerAfterColdRecovery('),
    );
    expect(
      compositionSource,
      contains('groupReactionProbeDatabase: dependencies.database'),
    );
    expect(
      compositionSource,
      contains('groupReactionProbeSecureKeyStore: dependencies.secureKeyStore'),
    );
  });

  test(
    'Plan 257 artifact capture uses the production group crypto markers',
    () {
      final capture = File(
        'integration_test/scripts/'
        'capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final criteria = File(
        'integration_test/scripts/'
        'group_reaction_notification_device_criteria.dart',
      ).readAsStringSync();

      for (final source in <String>[capture, criteria]) {
        expect(source, contains('PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK'));
        expect(source, contains('PUSH_ANDROID_DATA_DECRYPT_OK'));
        expect(
          source,
          isNot(contains('PUSH_BACKGROUND_GROUP_REACTION_CRYPTO_PLUGIN_OK')),
        );
        expect(
          source,
          isNot(contains('PUSH_ANDROID_GROUP_REACTION_DECRYPT_OK')),
        );
      }
    },
  );

  test('Plan 256 unread proof reopens Orbit without force-stop', () {
    final source = File(
      'integration_test/scripts/'
      'capture_1to1_reaction_head_provenance.dart',
    ).readAsStringSync();
    final methodStart = source.indexOf(
      'Future<void> _reopenRecipientAtOrbit()',
    );
    final methodEnd = source.indexOf(
      'Future<void> _sendUiMessageFromSender',
      methodStart,
    );

    expect(methodStart, greaterThan(0));
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);
    expect(method, contains('android.intent.action.MAIN'));
    expect(method, contains('android.intent.category.LAUNCHER'));
    expect(method, contains('0x10008000'));
    expect(method, isNot(contains('force-stop')));
    expect(method, isNot(contains('_launch(')));
  });

  test(
    'Plan 257 group invite acceptance preserves the live invite handler',
    () {
      final source = File(
        'integration_test/scripts/'
        'capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf('Future<void> _createAndAcceptGroup(');
      final methodEnd = source.indexOf(
        'Future<void> _runAndroidUnreadLifecycle()',
        methodStart,
      );

      expect(methodStart, greaterThan(0));
      expect(methodEnd, greaterThan(methodStart));
      final method = source.substring(methodStart, methodEnd);
      expect(method, contains('await _startAndroid(invitee.deviceId)'));
      expect(method, isNot(contains('_launchAndroid(invitee.deviceId)')));
      expect(method, isNot(contains('force-stop')));
    },
  );

  test('Plan 256 cached candidates require revision and hash provenance', () {
    final source = File(
      'integration_test/scripts/'
      'capture_1to1_reaction_head_provenance.dart',
    ).readAsStringSync();
    final methodStart = source.indexOf(
      'Future<_BuildArtifacts> _reuseWorkingTreeApks()',
    );
    final methodEnd = source.indexOf(
      'Future<void> _prepareE2EParty',
      methodStart,
    );

    expect(methodStart, greaterThan(0));
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);
    expect(method, contains("metadata['buildProfile']"));
    expect(method, contains("metadata['revision']"));
    expect(method, contains('revision != head'));
    expect(method, contains('final actualE2E = await _sha256(e2eApk)'));
    expect(method, contains('final actualNormal = await _sha256(normalApk)'));
    expect(method, contains('actualE2E != expectedE2E'));
    expect(method, contains('actualNormal != expectedNormal'));
  });

  test('Plan 256 live smoke exchanges recipient-issued wake authorization', () {
    final source = File(
      'integration_test/scripts/'
      'capture_1to1_reaction_head_provenance.dart',
    ).readAsStringSync();
    final contactsCall = source.indexOf('await _prepopulateContacts();');
    final seedCall = source.indexOf('_seedIncomingMessage(messageMarker)');
    final contactsMethod = source.indexOf(
      'Future<void> _prepopulateContacts()',
    );
    final seedMethod = source.indexOf(
      'Future<String> _seedIncomingMessage',
      contactsMethod,
    );
    final contactSetup = source.substring(contactsMethod, seedMethod);
    final senderExchange = contactSetup.indexOf(
      'await _exchangeWakeToken(sender, recipient);',
    );
    final recipientExchange = contactSetup.indexOf(
      'await _exchangeWakeToken(recipient, sender);',
    );

    expect(contactsCall, greaterThan(0));
    expect(seedCall, greaterThan(contactsCall));
    expect(contactsMethod, greaterThan(seedCall));
    expect(senderExchange, greaterThan(0));
    expect(recipientExchange, greaterThan(senderExchange));
    expect(
      source,
      contains("'send_contact_requests_for_added_contacts': true"),
    );
  });

  test(
    'intro E2E contact exchange uses the production wake-token resolver',
    () {
      final runner = File(
        'lib/core/debug/intro_e2e_runner.dart',
      ).readAsStringSync();
      final productionSource = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final compositionSource = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();

      expect(
        runner,
        contains('ResolveWakeTokenForIntroE2EFn? resolveWakeToken'),
      );
      expect(runner, contains('resolveWakeToken: resolveWakeToken,'));
      expect(
        productionSource,
        contains('if (debugE2EComposition?.startsIntroPoller ?? false) {'),
      );
      expect(
        productionSource,
        contains('debugE2EComposition!.startIntroPollerAfterColdRecovery('),
      );
      expect(
        compositionSource,
        contains('resolveWakeToken: dependencies.wakeTokenResolver,'),
      );
    },
  );

  group('Plan 256 closure artifact contract', () {
    for (final scenario in const <String>[
      'android_physical_recipient',
      'ios_physical_recipient',
      'android_message_unread_lifecycle',
    ]) {
      test('accepts a complete $scenario artifact', () {
        final artifact = _validClosureArtifact(scenario);
        final result = validatePlan256ArtifactContract(
          scenario: scenario,
          artifact: artifact,
          rawJson: '{}',
        );

        expect(result.errors, isEmpty, reason: result.errors.join('\n'));
      });
    }

    test('rejects force-stop and a reaction-created unread row', () {
      final artifact = _validClosureArtifact('android_physical_recipient');
      (artifact['capture'] as Map<String, dynamic>)
        ..['forceStopUsed'] = true
        ..['recipientTerminationCommand'] = 'am force-stop com.mknoon.app';
      (artifact['state'] as Map<String, dynamic>)['unreadAfterDelivery'] = 1;

      final result = validatePlan256ArtifactContract(
        scenario: 'android_physical_recipient',
        artifact: artifact,
      );

      expect(result.errors.join('\n'), contains('forceStopUsed'));
      expect(result.errors.join('\n'), contains('unreadAfterDelivery'));
    });

    test('rejects two iOS audible alerts and a generic timeout fallback', () {
      final artifact = _validClosureArtifact('ios_physical_recipient');
      final orders = artifact['arrivalOrders'] as Map<String, dynamic>;
      (orders['remoteFirst'] as Map<String, dynamic>)['audibleAlerts'] = 2;
      (artifact['provider'] as Map<String, dynamic>)['fallbackTitle'] =
          'New Message';

      final result = validatePlan256ArtifactContract(
        scenario: 'ios_physical_recipient',
        artifact: artifact,
      );

      expect(result.errors.join('\n'), contains('audibleAlerts'));
      expect(result.errors.join('\n'), contains('fallbackTitle'));
    });

    test('rejects early unread clear and hidden-widget-only Orbit proof', () {
      final artifact = _validClosureArtifact(
        'android_message_unread_lifecycle',
      );
      (artifact['timeline'] as Map<String, dynamic>)['unreadCounts'] = <int>[
        0,
        1,
        0,
        2,
        0,
      ];
      (artifact['tap'] as Map<String, dynamic>)['hiddenWidgetOnly'] = true;

      final result = validatePlan256ArtifactContract(
        scenario: 'android_message_unread_lifecycle',
        artifact: artifact,
      );

      expect(result.errors.join('\n'), contains('unreadCounts'));
      expect(result.errors.join('\n'), contains('hiddenWidgetOnly'));
    });

    test('rejects raw provider tokens even when booleans claim redaction', () {
      final artifact = _validClosureArtifact('android_physical_recipient');
      final result = validatePlan256ArtifactContract(
        scenario: 'android_physical_recipient',
        artifact: artifact,
        rawJson: '{"fcmToken":"must-not-persist"}',
      );

      expect(result.errors.join('\n'), contains('"fcmToken":'));
    });
  });

  group('classifyRelayCapture', () {
    test('matches the bounded store and proves no provider send', () {
      const log = '''
Jul 12 01:20:01 relay [INBOX] Stored message for recipient-prefix-123 from sender-prefix-456
Jul 12 01:20:01 relay [INBOX] stream handled in 12ms
''';

      final result = classifyRelayCapture(
        log: log,
        senderPrefix: 'sender-prefix-456',
        recipientPrefix: 'recipient-prefix-123',
      );

      expect(result.relayMatchedEvent, isTrue);
      expect(result.providerMatchedEvent, isFalse);
      expect(result.providerConfirmedNoSend, isTrue);
    });

    test('does not attribute another recipient store to this reaction', () {
      const log = '''
Jul 12 01:20:01 relay [INBOX] Stored message for other-recipient from sender-prefix-456
''';

      final result = classifyRelayCapture(
        log: log,
        senderPrefix: 'sender-prefix-456',
        recipientPrefix: 'recipient-prefix-123',
      );

      expect(result.relayMatchedEvent, isFalse);
      expect(result.providerConfirmedNoSend, isFalse);
    });

    test('attributes a provider send only for the bounded recipient', () {
      const log = '''
Jul 12 01:20:01 relay [INBOX] Stored message for recipient-prefix-123 from sender-prefix-456
Jul 12 01:20:02 relay [PUSH] Notification sent to recipient-prefix-123 (attempt 1/3)
''';

      final result = classifyRelayCapture(
        log: log,
        senderPrefix: 'sender-prefix-456',
        recipientPrefix: 'recipient-prefix-123',
      );

      expect(result.relayMatchedEvent, isTrue);
      expect(result.providerMatchedEvent, isTrue);
      expect(result.providerConfirmedNoSend, isFalse);
    });

    test('rejects every bounded provider refusal, fallback, and retry error', () {
      const prefix = 'recipient-prefix-123';
      for (final failureLine in <String>[
        '[PUSH] Failed to send push to $prefix after 3 attempt(s): error',
        '[PUSH] Removed invalid token for $prefix after chat push error: bad',
        '[PUSH] Skip chat push to $prefix: no registered token',
        '[PUSH] Refusing chat push to $prefix: required routing cannot fit provider budget',
        '[PUSH] Refusing oversized chat push to $prefix: no smaller valid routing payload',
        '[PUSH] Strict routing fallback to $prefix failed after provider rejected chat payload size: bad',
        '[PUSH] Strict routing fallback sent to $prefix after provider rejected chat payload size',
        '[PUSH] Aborting chat push retry to $prefix: context canceled',
        '[PUSH] Push to $prefix failed on attempt 1/3: error; retrying in 1s',
      ]) {
        final result = classifyRelayCapture(
          log:
              '[INBOX] Stored message for $prefix from sender-prefix-456\n'
              '[PUSH] Notification sent to $prefix (attempt 2/3)\n'
              '$failureLine',
          senderPrefix: 'sender-prefix-456',
          recipientPrefix: prefix,
        );
        expect(result.providerFailureMatched, isTrue, reason: failureLine);
      }
    });
  });

  group('hasAttachedAndroidActivity', () {
    test('detects an active task/activity for the package', () {
      const dump = '''
* Task{abc #12}
  * Hist #0: ActivityRecord{def u0 com.mknoon.app/.MainActivity t12}
mRemoteInsetsControlTarget=target
''';
      expect(hasAttachedAndroidActivity(dump, 'com.mknoon.app'), isTrue);
    });

    test(
      'ignores historical rotation diagnostics after the active section',
      () {
        const dump = '''
topResumedActivity=ActivityRecord{abc u0 com.android.launcher/.Launcher t5}
mRemoteInsetsControlTarget=target
source=ActivityRecord{old u0 com.mknoon.app/.MainActivity t406}
''';
        expect(hasAttachedAndroidActivity(dump, 'com.mknoon.app'), isFalse);
      },
    );

    test('PID gone but active task remains is not process/activity absent', () {
      const dump = '''
* Task{abc #12}
  * Hist #0: ActivityRecord{def u0 com.mknoon.app/.MainActivity t12}
mRemoteInsetsControlTarget=target
''';
      expect(
        isAndroidAppProcessAndActivityAbsent(
          pidOutput: '',
          dumpsysActivities: dump,
          packageName: 'com.mknoon.app',
        ),
        isFalse,
      );
    });
  });

  group('extractReactionSuccessId', () {
    test('returns the emitted reaction id prefix from a FLOW record', () {
      const log = '''
I/flutter: [FLOW] {"event":"REACTION_SEND_START","details":{"emoji":"👍"}}
I/flutter: [FLOW] {"event":"REACTION_SEND_SUCCESS","details":{"id":"a1b2c3d4","emoji":"👍"}}
''';

      expect(extractReactionSuccessId(log), 'a1b2c3d4');
    });

    test('extracts a UI-seeded chat message id from its FLOW record', () {
      const log = '''
I/flutter: [FLOW] {"event":"CHAT_MSG_SEND_START","details":{}}
I/flutter: [FLOW] {"event":"CHAT_MSG_SEND_SUCCESS","details":{"id":"feedbeef","status":"inboxed"}}
''';

      expect(extractChatSendSuccessId(log), 'feedbeef');
    });

    test('ignores malformed and unrelated records', () {
      const log = '''
I/flutter: [FLOW] not-json
I/flutter: [FLOW] {"event":"CHAT_SEND_SUCCESS","details":{"id":"wrong"}}
''';

      expect(extractReactionSuccessId(log), isNull);
    });
  });

  group('extractGroupSendTimingObservations', () {
    test('preserves terminal ordering across recovery and committed retry', () {
      const log = '''
I/flutter: [FLOW] {"event":"GROUP_SEND_MSG_TIMING","details":{"outcome":"success","expectedRecipientCount":1,"inboxStored":true,"inboxPending":false}}
I/flutter: [FLOW] not-json
I/flutter: [FLOW] {"event":"GROUP_SEND_MSG_USE_CASE_RECOVERY_PENDING","details":{}}
I/flutter: [FLOW] {"event":"GROUP_SEND_MSG_TIMING","details":{"outcome":"group_recovery_pending"}}
I/flutter: [FLOW] {"event":"GROUP_SEND_MSG_TIMING","details":{"outcome":"success_no_peers","expectedRecipientCount":1,"inboxStored":true,"inboxPending":false}}
''';

      final observations = extractGroupSendTimingObservations(log);

      expect(observations, hasLength(3));
      expect(observations[0].isCommitted, isTrue);
      expect(observations[1].isRecoveryPending, isTrue);
      expect(observations[2].outcome, 'success_no_peers');
      expect(
        observations[2].hasRequiredInboxCustody(recipientCount: 1),
        isTrue,
      );
    });

    test('does not accept incomplete or mismatched custody as a commit', () {
      const log = '''
I/flutter: [FLOW] {"event":"GROUP_SEND_MSG_TIMING","details":{"outcome":"success","expectedRecipientCount":2,"inboxStored":true,"inboxPending":false}}
I/flutter: [FLOW] {"event":"GROUP_SEND_MSG_TIMING","details":{"outcome":"success","expectedRecipientCount":1,"inboxStored":true,"inboxPending":true}}
I/flutter: [FLOW] {"event":"GROUP_SEND_MSG_TIMING","details":{"outcome":"success_no_peers","expectedRecipientCount":1,"inboxStored":false,"inboxPending":false}}
''';

      final observations = extractGroupSendTimingObservations(log);

      expect(observations, hasLength(3));
      for (final observation in observations) {
        expect(observation.hasRequiredInboxCustody(recipientCount: 1), isFalse);
      }
    });
  });

  group('extractActiveNotificationCards', () {
    test('normalizes managed payload envelopes to the navigation route', () {
      final payload = encodeConversationNotificationPayload(
        routePayload: 'group:proof-group|message:proof-message',
        conversationKey: 'group:proof-group',
        metadata: const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'proof-message',
          generation: 'proof-generation',
        ),
      );
      final dump =
          '''
Active Notifications:
  NotificationRecord(0x2: pkg=com.mknoon.app user=UserHandle{0} id=2 tag=null importance=3)
    android.title=New Message
    android.text=You have a new message
    payload=String ($payload)
Ranking Config:
''';

      final card = extractActiveNotificationCards(
        dump,
        packageName: 'com.mknoon.app',
      ).single;

      expect(card.routePayload, 'group:proof-group|message:proof-message');
    });

    test('returns only active records for the requested package', () {
      const dump = '''
Active Notifications:
  NotificationRecord(0x1: pkg=com.other.app user=UserHandle{0} id=1 tag=null importance=3)
    android.title=Other
    android.text=Ignore me
  NotificationRecord(0x2: pkg=com.mknoon.app user=UserHandle{0} id=2 tag=null importance=3)
    android.title=New Message
    android.text=You have a new message
Ranking Config:
  PackagePreferences: com.mknoon.app
''';

      final cards = extractActiveNotificationCards(
        dump,
        packageName: 'com.mknoon.app',
      );

      expect(cards, hasLength(1));
      expect(cards.single.title, 'New Message');
      expect(cards.single.body, 'You have a new message');
      expect(cards.single.id, 2);
    });

    test('does not mistake package preferences for an active card', () {
      const dump = '''
Active Notifications:
Ranking Config:
  PackagePreferences: com.mknoon.app
''';

      expect(
        extractActiveNotificationCards(dump, packageName: 'com.mknoon.app'),
        isEmpty,
      );
    });

    test(
      'marks Android auto-group summaries separately from content cards',
      () {
        const dump = '''
Active Notifications:
  NotificationRecord(0x1: pkg=com.mknoon.app user=UserHandle{0} id=0 tag=0|com.mknoon.app|g:Aggregate_AlertingSection importance=4)
    flags=AUTO_CANCEL|LOCAL_ONLY|GROUP_SUMMARY|AUTOGROUP_SUMMARY
    android.title=null
    android.text=null
  NotificationRecord(0x2: pkg=com.mknoon.app user=UserHandle{0} id=11 tag=null importance=4)
    flags=AUTO_CANCEL
    android.title=Plan330A
    android.text=Alice: message A
  NotificationRecord(0x3: pkg=com.mknoon.app user=UserHandle{0} id=12 tag=null importance=4)
    flags=AUTO_CANCEL
    android.title=Plan330B
    android.text=Alice: message B
Ranking Config:
''';

        final cards = extractActiveNotificationCards(
          dump,
          packageName: 'com.mknoon.app',
        );

        expect(cards, hasLength(3));
        expect(cards.where((card) => card.isGroupSummary), hasLength(1));
        expect(
          cards.where((card) => !card.isGroupSummary).map((card) => card.title),
          orderedEquals(const <String>['Plan330A', 'Plan330B']),
        );

        final contentCards = extractActiveContentNotificationCards(
          dump,
          packageName: 'com.mknoon.app',
        );
        expect(contentCards, hasLength(2));
        expect(
          contentCards.map((card) => card.title),
          orderedEquals(const <String>['Plan330A', 'Plan330B']),
        );
      },
    );

    test('keeps an app-owned group summary in fail-closed content', () {
      const dump = '''
Active Notifications:
  NotificationRecord(0x1: pkg=com.mknoon.app user=UserHandle{0} id=42 tag=null importance=4)
    flags=AUTO_CANCEL|GROUP_SUMMARY
    android.title=Unexpected app summary
    android.text=Must remain observable
Ranking Config:
''';

      final cards = extractActiveContentNotificationCards(
        dump,
        packageName: 'com.mknoon.app',
      );

      expect(cards, hasLength(1));
      expect(cards.single.id, 42);
      expect(cards.single.isGroupSummary, isFalse);
    });
  });

  group('extractOrbitUnreadCount', () {
    test('reads zero, singular, and plural contact semantics', () {
      const zero = '''
<node content-desc="Open chat with TC256-A" bounds="[0,0][20,20]" />
''';
      const one = '''
<node content-desc="Open chat with TC256-A, 1 unread message" bounds="[0,0][20,20]" />
''';
      const two = '''
<node content-desc="Open chat with TC256-A, 2 unread messages" bounds="[0,0][20,20]" />
''';

      expect(extractOrbitUnreadCount(zero, 'TC256-A'), 0);
      expect(extractOrbitUnreadCount(one, 'TC256-A'), 1);
      expect(extractOrbitUnreadCount(two, 'TC256-A'), 2);
    });

    test('returns null when the contact node is absent', () {
      expect(
        extractOrbitUnreadCount(
          '<node content-desc="Open chat with Someone Else" />',
          'TC256-A',
        ),
        isNull,
      );
    });
  });

  group('validateDirectReactionNotificationCard', () {
    test('accepts exact trusted reactor title and semantic emoji body', () {
      final errors = validateDirectReactionNotificationCard(
        const ActiveNotificationCard(
          title: 'TC256-A',
          body: 'Reacted 👍 to your message',
        ),
        expectedTitle: 'TC256-A',
        emoji: '👍',
      );

      expect(errors, isEmpty);
    });

    test('rejects the generic message fallback and mismatched actor', () {
      final errors = validateDirectReactionNotificationCard(
        const ActiveNotificationCard(
          title: 'New Message',
          body: 'You have a new message',
        ),
        expectedTitle: 'TC256-A',
        emoji: '👍',
      );

      expect(errors.join('\n'), contains('trusted reactor title'));
      expect(errors.join('\n'), contains('Reacted 👍 to your message'));
      expect(errors.join('\n'), contains('New Message'));
    });
  });

  group('validateOrdinaryMessageNotificationCard', () {
    test('accepts exact sender and message body', () {
      expect(
        validateOrdinaryMessageNotificationCard(
          const ActiveNotificationCard(
            title: 'TC256-A',
            body: 'TC256-unread-1',
          ),
          expectedTitle: 'TC256-A',
          expectedBody: 'TC256-unread-1',
        ),
        isEmpty,
      );
    });

    test('rejects a generic New Message card', () {
      final errors = validateOrdinaryMessageNotificationCard(
        const ActiveNotificationCard(
          title: 'New Message',
          body: 'You have a new message',
        ),
        expectedTitle: 'TC256-A',
        expectedBody: 'TC256-unread-1',
      );

      expect(errors.join('\n'), contains('New Message'));
      expect(errors.join('\n'), contains('TC256-A'));
      expect(errors.join('\n'), contains('TC256-unread-1'));
    });
  });

  group('findSemanticNodeCenter', () {
    test('finds a message body inside Flutter combined semantics', () {
      const dump = '''
<hierarchy>
  <node text="" content-desc="TC256-B&#10;TC256-unique-marker&#10;1:54 AM&#10;Received via cellular relay" bounds="[42,1912][797,2035]" />
</hierarchy>
''';

      expect(findSemanticNodeCenter(dump, 'TC256-unique-marker'), (419, 1973));
    });

    test('prefers an exact semantic node over an earlier containing node', () {
      const dump = '''
<hierarchy>
  <node text="" content-desc="Reaction: &#128077;" bounds="[0,0][20,20]" />
  <node text="" content-desc="&#128077;" bounds="[100,200][140,260]" />
</hierarchy>
''';

      expect(findSemanticNodeCenter(dump, '👍'), (120, 230));
    });

    test('does not return an unrelated semantic node', () {
      const dump = '''
<hierarchy>
  <node text="" content-desc="another message" bounds="[0,0][20,20]" />
</hierarchy>
''';

      expect(findSemanticNodeCenter(dump, 'TC256-unique-marker'), isNull);
    });
  });

  group('isAcceptedGroupSurface', () {
    test('rejects the pending invite card while Accept is still present', () {
      const dump = '''
<hierarchy>
  <node content-desc="TC257Group123" bounds="[42,600][1038,800]" />
  <node content-desc="Accept" bounds="[700,820][1000,930]" />
</hierarchy>
''';

      expect(isAcceptedGroupSurface(dump, 'TC257Group123'), isFalse);
    });

    test(
      'accepts the direct group-conversation destination after approval',
      () {
        const dump = '''
<hierarchy>
  <node content-desc="TC257Group123" bounds="[284,182][767,242]" />
  <node content-desc="Discussion" bounds="[796,195][920,229]" />
  <node class="android.widget.EditText" hint="Write something..." bounds="[192,2177][888,2303]" />
</hierarchy>
''';

        expect(isAcceptedGroupSurface(dump, 'TC257Group123'), isTrue);
      },
    );

    test('rejects an invite card whose Accept action became a spinner', () {
      const dump = '''
<hierarchy>
  <node content-desc="TC257Group123" bounds="[42,600][1038,800]" />
  <node class="android.widget.ProgressBar" bounds="[820,820][900,900]" />
</hierarchy>
''';

      expect(isAcceptedGroupSurface(dump, 'TC257Group123'), isFalse);
    });
  });

  group('isGroupConversationSurface', () {
    test('recognizes an announcement conversation without a compose field', () {
      const dump = '''
<hierarchy>
  <node content-desc="TC257Ann123" bounds="[284,182][767,242]" />
  <node content-desc="Announcement" bounds="[796,195][920,229]" />
</hierarchy>
''';

      expect(isGroupConversationSurface(dump, 'TC257Ann123'), isTrue);
    });

    test('recognizes the announcement admin surface labelled Announce', () {
      const dump = '''
<hierarchy>
  <node content-desc="TC257Ann123" bounds="[284,182][767,242]" />
  <node content-desc="Announce" bounds="[796,195][920,229]" />
</hierarchy>
''';

      expect(isGroupConversationSurface(dump, 'TC257Ann123'), isTrue);
    });

    test('does not mistake the Orbit group card for an open conversation', () {
      const dump = '''
<hierarchy>
  <node content-desc="Open group TC257Ann123" bounds="[42,500][1038,700]" />
</hierarchy>
''';

      expect(isGroupConversationSurface(dump, 'TC257Ann123'), isFalse);
    });
  });

  group('findNodeBoundsByClass', () {
    test('returns the compose edit bounds from the UIAutomator tree', () {
      const dump = '''
<hierarchy>
  <node class="android.view.View" bounds="[0,0][1080,2400]" />
  <node class="android.widget.EditText" bounds="[192,1328][888,1454]" />
</hierarchy>
''';

      expect(findNodeBoundsByClass(dump, 'android.widget.EditText'), (
        192,
        1328,
        888,
        1454,
      ));
    });

    test('returns null when the requested class is absent', () {
      const dump = '''
<hierarchy>
  <node class="android.view.View" bounds="[0,0][1080,2400]" />
</hierarchy>
''';

      expect(findNodeBoundsByClass(dump, 'android.widget.EditText'), isNull);
    });

    test('class-scoped text distinguishes a restored draft from a bubble', () {
      const withDraft = '''
<hierarchy>
  <node class="android.view.View" content-desc="TC257First123" bounds="[42,900][1038,1040]" />
  <node class="android.widget.EditText" text="TC257First123" bounds="[192,1328][888,1454]" />
</hierarchy>
''';
      const bubbleOnly = '''
<hierarchy>
  <node class="android.view.View" content-desc="TC257First123" bounds="[42,900][1038,1040]" />
  <node class="android.widget.EditText" text="" bounds="[192,1328][888,1454]" />
</hierarchy>
''';

      expect(
        findNodeBoundsByClassContainingText(
          withDraft,
          'android.widget.EditText',
          'TC257First123',
        ),
        (192, 1328, 888, 1454),
      );
      expect(
        findNodeBoundsByClassContainingText(
          bubbleOnly,
          'android.widget.EditText',
          'TC257First123',
        ),
        isNull,
      );
    });
  });

  group('enterGroupComposeMarkerOnce', () {
    const marker = 'Plan330TextA123';
    const unfocusedEditor = '''
<hierarchy>
  <node class="android.widget.EditText" enabled="true" focusable="true" focused="false" text="" bounds="[192,1328][888,1454]" />
</hierarchy>
''';
    const focusedEditor = '''
<hierarchy>
  <node class="android.widget.EditText" enabled="true" focusable="true" focused="true" text="" bounds="[192,1328][888,1454]" />
</hierarchy>
''';
    const acceptedMarker =
        '''
<hierarchy>
  <node class="android.widget.EditText" enabled="true" focusable="true" focused="true" text="$marker" bounds="[192,1328][888,1454]" />
</hierarchy>
''';

    test(
      'waits for exact editor focus before injecting exactly once',
      () async {
        final dumps = <String>[
          unfocusedEditor,
          unfocusedEditor,
          focusedEditor,
          acceptedMarker,
        ];
        final events = <String>[];

        final outcome = await enterGroupComposeMarkerOnce(
          marker: marker,
          readUiDump: () async {
            events.add('read');
            return dumps.removeAt(0);
          },
          tapEditor: (center) async =>
              events.add('tap:${center.$1},${center.$2}'),
          injectMarker: (value) async => events.add('inject:$value'),
          maximumFocusPolls: 2,
          maximumAcceptancePolls: 1,
          pollInterval: Duration.zero,
        );

        expect(outcome, GroupComposeMarkerEntryOutcome.accepted);
        expect(events, <String>[
          'read',
          'tap:540,1391',
          'read',
          'read',
          'inject:$marker',
          'read',
        ]);
        expect(
          events.where((event) => event.startsWith('inject:')),
          hasLength(1),
        );
      },
    );

    test('does not inject before the exact editor acquires focus', () async {
      var injections = 0;

      final outcome = await enterGroupComposeMarkerOnce(
        marker: marker,
        readUiDump: () async => unfocusedEditor,
        tapEditor: (_) async {},
        injectMarker: (_) async => injections += 1,
        maximumFocusPolls: 2,
        maximumAcceptancePolls: 1,
        pollInterval: Duration.zero,
      );

      expect(outcome, GroupComposeMarkerEntryOutcome.focusNotAcquired);
      expect(injections, 0);
    });

    test('fails closed on partial content without reinjection', () async {
      final dumps = <String>[
        unfocusedEditor,
        focusedEditor,
        '''
<hierarchy>
  <node class="android.widget.EditText" enabled="true" focusable="true" focused="true" text="Plan330TextA" bounds="[192,1328][888,1454]" />
</hierarchy>
''',
        acceptedMarker,
      ];
      var injections = 0;

      final outcome = await enterGroupComposeMarkerOnce(
        marker: marker,
        readUiDump: () async => dumps.removeAt(0),
        tapEditor: (_) async {},
        injectMarker: (_) async => injections += 1,
        maximumFocusPolls: 1,
        maximumAcceptancePolls: 2,
        pollInterval: Duration.zero,
      );

      expect(outcome, GroupComposeMarkerEntryOutcome.markerMismatch);
      expect(injections, 1);
      expect(dumps, hasLength(1), reason: 'must stop at the partial value');
    });

    test(
      'fails closed on different pre-existing content without injection',
      () async {
        const focusedDifferent = '''
<hierarchy>
  <node class="android.widget.EditText" enabled="true" focusable="true" focused="true" text="another draft" bounds="[192,1328][888,1454]" />
</hierarchy>
''';
        final dumps = <String>[unfocusedEditor, focusedDifferent];
        var injections = 0;

        final outcome = await enterGroupComposeMarkerOnce(
          marker: marker,
          readUiDump: () async => dumps.removeAt(0),
          tapEditor: (_) async {},
          injectMarker: (_) async => injections += 1,
          maximumFocusPolls: 1,
          maximumAcceptancePolls: 1,
          pollInterval: Duration.zero,
        );

        expect(outcome, GroupComposeMarkerEntryOutcome.composeNotEmpty);
        expect(injections, 0);
      },
    );

    test(
      'does not accept a marker that exists only in a message bubble',
      () async {
        const bubbleOnly =
            '''
<hierarchy>
  <node class="android.view.View" content-desc="$marker" bounds="[42,900][1038,1040]" />
  <node class="android.widget.EditText" enabled="true" focusable="true" focused="true" text="" bounds="[192,1328][888,1454]" />
</hierarchy>
''';
        final dumps = <String>[
          unfocusedEditor,
          focusedEditor,
          bubbleOnly,
          bubbleOnly,
        ];
        var injections = 0;

        final outcome = await enterGroupComposeMarkerOnce(
          marker: marker,
          readUiDump: () async => dumps.removeAt(0),
          tapEditor: (_) async {},
          injectMarker: (_) async => injections += 1,
          maximumFocusPolls: 1,
          maximumAcceptancePolls: 2,
          pollInterval: Duration.zero,
        );

        expect(outcome, GroupComposeMarkerEntryOutcome.markerNotObserved);
        expect(injections, 1);
      },
    );

    test('selector requires enabled, focusable, and focused EditText', () {
      const dump =
          '''
<hierarchy>
  <node class="android.widget.EditText" enabled="false" focusable="true" focused="true" text="$marker" bounds="[0,0][20,20]" />
  <node class="android.widget.EditText" enabled="true" focusable="false" focused="true" text="$marker" bounds="[20,0][40,20]" />
  <node class="android.widget.EditText" enabled="true" focusable="true" focused="false" text="$marker" bounds="[40,0][60,20]" />
  <node class="android.widget.EditText" enabled="true" focusable="true" focused="true" text="$marker" bounds="[100,200][140,260]" />
</hierarchy>
''';

      expect(
        findEnabledFocusableGroupComposeEditorBounds(
          dump,
          requireFocused: true,
          exactText: marker,
        ),
        (100, 200, 140, 260),
      );
    });
  });

  group('findBottommostNodeCenterByClass', () {
    test('selects the unlabeled group-name field below the contact search', () {
      const dump = '''
<hierarchy>
  <node class="android.widget.FrameLayout" bounds="[0,0][1080,2400]" />
  <node class="android.widget.EditText" bounds="[42,317][1038,443]" />
  <node class="android.widget.EditText" bounds="[42,2009][1038,2135]" />
</hierarchy>
''';

      expect(findBottommostNodeCenterByClass(dump, 'android.widget.EditText'), (
        540,
        2072,
      ));
    });

    test('returns null when the requested class is absent', () {
      expect(
        findBottommostNodeCenterByClass(
          '<hierarchy><node class="android.view.View" /></hierarchy>',
          'android.widget.EditText',
        ),
        isNull,
      );
    });
  });

  group('findTopRightClickableNodeCenter', () {
    test(
      'finds the unlabeled Orbit create FAB from real Android semantics',
      () {
        const dump = '''
<hierarchy>
  <node class="android.widget.FrameLayout" clickable="false" bounds="[0,0][1080,2400]" />
  <node class="android.view.View" clickable="true" bounds="[0,128][1080,2337]" />
  <node class="android.widget.Button" clickable="true" content-desc="Open chat with Bob" bounds="[477,1007][603,1133]" />
  <node class="android.view.View" clickable="true" bounds="[933,149][1038,254]" />
  <node class="android.widget.Button" clickable="true" content-desc="Find someone in your circle" bounds="[901,2214][1038,2350]" />
</hierarchy>
''';

        expect(findTopRightClickableNodeCenter(dump), (985, 201));
      },
    );

    test('does not mistake a full-screen scrim for the top-right action', () {
      const dump = '''
<hierarchy>
  <node class="android.widget.FrameLayout" clickable="false" bounds="[0,0][1080,2400]" />
  <node class="android.view.View" clickable="true" bounds="[0,128][1080,2337]" />
</hierarchy>
''';

      expect(findTopRightClickableNodeCenter(dump), isNull);
    });
  });
}

Map<String, dynamic> _validClosureArtifact(String scenario) {
  const digestA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const digestB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const digestC =
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
  final ios = scenario == 'ios_physical_recipient';
  final reaction = scenario != 'android_message_unread_lifecycle';
  final evidenceKinds = ios
      ? const <String>[
          'relay_provider',
          'apns_delivery',
          'nse_log',
          'xcuitest',
          'local_state',
        ]
      : const <String>[
          'relay_provider',
          'android_logcat',
          'notification_records',
          'ui_automation',
          'sqlcipher_state',
        ];
  final artifact = <String, dynamic>{
    'schema': plan256ArtifactSchema,
    'testCase': switch (scenario) {
      'android_physical_recipient' => 'TC-13',
      'ios_physical_recipient' => 'TC-14',
      _ => 'TC-16',
    },
    'scenario': scenario,
    'status': 'passed',
    'capturedAt': '2026-07-12T10:00:00.000Z',
    'environment': <String, dynamic>{
      'name': 'staging',
      'candidateAppRevision': 'app-revision',
      'candidateRelayRevision': 'relay-revision',
      'candidateRelaySha256': digestA,
      'provider': ios ? 'apns' : 'fcm',
      'providerConfigured': true,
      'candidateBuildInstalled': true,
      'typedReactionEnabled': reaction,
    },
    'topology': <String, dynamic>{
      'sender': <String, dynamic>{
        'deviceId': 'sender-device',
        'platform': 'android',
        'liveDiscovered': true,
        'explicitId': true,
      },
      'recipient': <String, dynamic>{
        'deviceId': 'recipient-device',
        'platform': ios ? 'ios' : 'android',
        'physical': true,
        'liveDiscovered': true,
        'explicitId': true,
      },
    },
    'capture': <String, dynamic>{
      'automationOnly': true,
      'manualTaps': 0,
      'forceStopUsed': false,
      'productionDeploymentPerformed': false,
      if (scenario == 'android_physical_recipient') ...<String, dynamic>{
        'recipientTerminationCommand': 'am kill com.mknoon.app',
        'pidAbsentBeforeDelivery': true,
      },
    },
    'evidence': <Map<String, dynamic>>[
      for (final kind in evidenceKinds)
        <String, dynamic>{
          'kind': kind,
          'path': '$kind.log',
          'sha256': digestA,
          'bytes': 1,
        },
    ],
    'redaction': <String, dynamic>{
      'peerIdsPersisted': false,
      'pushTokensPersisted': false,
      'secretKeysPersisted': false,
      'ciphertextPersisted': false,
      'plaintextPayloadPersisted': false,
    },
  };

  switch (scenario) {
    case 'android_physical_recipient':
      artifact.addAll(<String, dynamic>{
        'events': <String, dynamic>{
          'first': <String, dynamic>{
            'eventIdSha256': digestA,
            'targetIdSha256': digestC,
            'remoteType': 'message_reaction',
            'action': 'add',
            'stored': true,
            'providerMatched': true,
          },
          'replacement': <String, dynamic>{
            'eventIdSha256': digestB,
            'targetIdSha256': digestC,
            'remoteType': 'message_reaction',
            'action': 'add',
            'stored': true,
            'providerMatched': true,
          },
          'ownTargetNegative': <String, dynamic>{
            'eventIdSha256': digestC,
            'storedOnRecipient': true,
            'targetAuthoredByReactor': true,
            'providerMatched': false,
            'activeCardDelta': 0,
          },
        },
        'notification': <String, dynamic>{
          'trustedActorTitle': 'Alice',
          'emoji': '👍',
          'firstCard': <String, dynamic>{
            'activeMatchingCards': 1,
            'title': 'Alice',
            'body': 'Reacted 👍 to your message',
            'category': 'message',
            'decryptSucceeded': true,
            'notificationId': 123,
          },
          'replacementCard': <String, dynamic>{
            'activeMatchingCards': 1,
            'title': 'Alice',
            'body': 'Reacted 👍 to your message',
            'category': 'message',
            'decryptSucceeded': true,
            'notificationId': 123,
          },
          'replacementObserved': true,
          'containsNewMessageCopy': false,
        },
        'tap': <String, dynamic>{
          'automated': true,
          'route': 'conversation',
          'realConversationRendered': true,
          'routeErrors': 0,
        },
        'state': <String, dynamic>{
          'targetReactionRows': 1,
          'negativeReactionRows': 1,
          'reactionCreatedMessageRows': 0,
          'unreadBefore': 0,
          'unreadAfterDelivery': 0,
          'unreadAfterTap': 0,
          'orbitIndicatorsAfterReturn': 0,
          'sqlCipherRead': true,
        },
      });
    case 'ios_physical_recipient':
      artifact.addAll(<String, dynamic>{
        'reaction': <String, dynamic>{
          'remoteType': 'message_reaction',
          'action': 'add',
          'eventIdSha256': digestA,
          'targetIdSha256': digestB,
          'stored': true,
        },
        'provider': <String, dynamic>{
          'matchedEvent': true,
          'mutableContent': true,
          'fallbackSilent': true,
          'fallbackTitle': 'New reaction',
          'fallbackSaysNewMessage': false,
          'canonicalTapPayload': true,
          'collapseIdUtf8Bytes': 32,
        },
        'nse': <String, dynamic>{
          'executed': true,
          'projectionMatched': true,
          'decryptSucceeded': true,
          'validatedBeforeClaim': true,
          'matchingClaims': 1,
        },
        'notification': <String, dynamic>{
          'trustedActorTitle': 'Alice',
          'emoji': '👍',
          'title': 'Alice',
          'body': 'Reacted 👍 to your message',
          'peerThreadMatched': true,
          'containsNewMessageCopy': false,
        },
        'arrivalOrders': <String, dynamic>{
          for (final name in const <String>['liveFirst', 'remoteFirst'])
            name: <String, dynamic>{
              'audibleAlerts': 1,
              'samePeerThread': true,
              'duplicatePassiveOrAbsent': true,
              'retainedItems': 1,
            },
        },
        'tap': <String, dynamic>{
          'automated': true,
          'xcodeSelector':
              'RunnerUITests/NotificationTapUITests/testReactionNotificationTap',
          'route': 'conversation',
          'coldLaunch': true,
          'realConversationRendered': true,
          'routeErrors': 0,
        },
        'state': <String, dynamic>{
          'reactionRows': 1,
          'reactionCreatedMessageRows': 0,
          'unreadBefore': 0,
          'unreadAfterDelivery': 0,
          'unreadAfterTap': 0,
          'localProjectionRead': true,
        },
      });
    case 'android_message_unread_lifecycle':
      artifact.addAll(<String, dynamic>{
        'messages': <String, dynamic>{
          'first': <String, dynamic>{
            'messageIdSha256': digestA,
            'body': 'first ordinary message',
            'persistedIncoming': true,
          },
          'second': <String, dynamic>{
            'messageIdSha256': digestB,
            'body': 'second ordinary message',
            'persistedIncoming': true,
          },
        },
        'timeline': <String, dynamic>{
          'unreadCounts': <int>[0, 1, 1, 2, 0],
          'orbitSatelliteCounts': <int>[0, 1, 1, 2, 0],
          'dismissedCardUnreadCount': 1,
          'readCommitBeforeTap': false,
          'readCommitAfterConversationRender': true,
          'sqlCipherReadAtEveryStep': true,
        },
        'notification': <String, dynamic>{
          'firstCardCount': 1,
          'firstCardDismissedByAutomation': true,
          'secondCardCount': 1,
          'replacementObserved': true,
          'category': 'message',
          'ordinaryCopyMatched': true,
          'firstNotificationId': 123,
          'secondNotificationId': 123,
        },
        'tap': <String, dynamic>{
          'automated': true,
          'route': 'conversation',
          'realConversationWired': true,
          'bothMessagesVisible': true,
          'repositoryReadEventObserved': true,
          'returnedToOrbit': true,
          'orbitIndicatorsAfterReturn': 0,
          'hiddenWidgetOnly': false,
          'routeErrors': 0,
        },
      });
  }
  return artifact;
}
