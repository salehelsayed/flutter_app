import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/reaction_notification_proof_support.dart';

void main() {
  // Replaces the relay-journal token-registration wait, which greps a line
  // relay v1.8.0 no longer emits. The relay's [PUSH] vocabulary is now
  // deliberately content-free, so registration is attributed at the RECIPIENT
  // boundary instead — the device's own log is unambiguously that device's.
  group('android relay push registration acceptance', () {
    String flow(String event, Map<String, Object?> details) =>
        'I/flutter: [FLOW] '
        '${jsonEncode(<String, Object?>{
          'ts': '2026-08-17T20:00:00.000Z',
          'milestone': 'M1_IDENTITY_INIT',
          'layer': 'FL',
          'event': event,
          'details': details,
        })}';

    test('accepts the unconditional PUSH_DIAG success line', () {
      expect(
        androidRelayPushRegistrationAccepted(
          'I/flutter: [PUSH_DIAG] relay_push_registration_success '
          'platform=android',
        ),
        isTrue,
      );
    });

    test('accepts the gated FLOW success event', () {
      expect(
        androidRelayPushRegistrationAccepted(
          flow('PUSH_REGISTER_TOKEN_SUCCESS', <String, Object?>{
            'platform': 'android',
          }),
        ),
        isTrue,
      );
    });

    test('rejects intent without acceptance', () {
      // PUSH_REGISTER_TOKEN_SENDING is emitted BEFORE the frame leaves the
      // device. Accepting it would make the gate pass while the relay is down.
      expect(
        androidRelayPushRegistrationAccepted(
          flow('PUSH_REGISTER_TOKEN_SENDING', <String, Object?>{
            'platform': 'android',
            'tokenLength': 163,
          }),
        ),
        isFalse,
      );
    });

    test('rejects a failed registration on either channel', () {
      expect(
        androidRelayPushRegistrationAccepted(
          flow('PUSH_REGISTER_TOKEN_FAILED', <String, Object?>{
            'platform': 'android',
          }),
        ),
        isFalse,
      );
      expect(
        androidRelayPushRegistrationAccepted(
          'I/flutter: [PUSH_DIAG] relay_push_registration_failed '
          'platform=android',
        ),
        isFalse,
      );
    });

    test('rejects a non-android platform', () {
      expect(
        androidRelayPushRegistrationAccepted(
          '${flow('PUSH_REGISTER_TOKEN_SUCCESS', <String, Object?>{'platform': 'ios'})}\n'
          'I/flutter: [PUSH_DIAG] relay_push_registration_success '
          'platform=ios',
        ),
        isFalse,
      );
    });

    test('rejects unrelated, empty, and malformed logs', () {
      expect(androidRelayPushRegistrationAccepted(''), isFalse);
      expect(
        androidRelayPushRegistrationAccepted('I/flutter: [FLOW] {not json'),
        isFalse,
      );
      expect(
        androidRelayPushRegistrationAccepted(
          'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_REGISTER_TOKEN_BEGIN",'
          '"details":{}}',
        ),
        isFalse,
      );
    });

    test('finds the success line among surrounding noise', () {
      final log = <String>[
        'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_REGISTER_TOKEN_BEGIN","details":{}}',
        flow('PUSH_REGISTER_TOKEN_SENDING', <String, Object?>{
          'platform': 'android',
          'tokenLength': 163,
        }),
        'D/AudioSystem: unrelated device chatter',
        flow('P2P_INBOX_REGISTER_TOKEN_RESPONSE', <String, Object?>{
          'ok': true,
        }),
        flow('PUSH_REGISTER_TOKEN_SUCCESS', <String, Object?>{
          'platform': 'android',
        }),
      ].join('\n');

      expect(androidRelayPushRegistrationAccepted(log), isTrue);
    });
  });

  group('flow event occurrence counting', () {
    String flow(String event, Map<String, Object?> details) =>
        'I/flutter: [FLOW] '
        '${jsonEncode(<String, Object?>{
          'layer': 'DB',
          'event': event,
          'details': details,
        })}';

    test('counts only exact event matches', () {
      final log = <String>[
        flow('GROUP_MESSAGES_DB_INSERT_SUCCESS', <String, Object?>{'id': 'aaaa1111'}),
        flow('GROUP_MESSAGES_DB_INSERT_START', <String, Object?>{'id': 'bbbb2222'}),
        flow('GROUP_MESSAGES_DB_INSERT_SUCCESS', <String, Object?>{'id': 'cccc3333'}),
        'D/unrelated: GROUP_MESSAGES_DB_INSERT_SUCCESS in prose',
      ].join('\n');

      expect(
        countFlowEventOccurrences(log, 'GROUP_MESSAGES_DB_INSERT_SUCCESS'),
        2,
      );
      expect(countFlowEventOccurrences('', 'ANYTHING'), 0);
    });

    test('an id-bound arrival survives a rotated logcat ring; a count '
        'delta does not', () {
      // Device evidence, run 11 (2026-08-18): `adb logcat -d` returns only
      // what is still in the ring buffer, so a later dump can hold FEWER
      // occurrences than the baseline even though the row under test was
      // written. `count > baseline` is therefore unsound as an arrival
      // predicate and must not be reintroduced.
      final baseline = <String>[
        flow('GROUP_MESSAGES_DB_INSERT_SUCCESS', <String, Object?>{
          'id': 'aaaa1111',
        }),
        flow('GROUP_MESSAGES_DB_INSERT_SUCCESS', <String, Object?>{
          'id': 'bbbb2222',
        }),
      ].join('\n');
      // The ring rotated both baseline lines away and kept only the new row.
      final rotated = flow('GROUP_MESSAGES_DB_INSERT_SUCCESS',
          <String, Object?>{'id': 'dddd4444'});

      expect(
        countFlowEventOccurrences(
              rotated,
              'GROUP_MESSAGES_DB_INSERT_SUCCESS',
            ) >
            countFlowEventOccurrences(
              baseline,
              'GROUP_MESSAGES_DB_INSERT_SUCCESS',
            ),
        isFalse,
        reason: 'the unsound delta predicate misses the arrival',
      );
      expect(groupMessageStoredWithId(rotated, 'dddd4444'), isTrue);
      expect(groupMessageStoredWithId(baseline, 'dddd4444'), isFalse);
    });

    test('an insert for a different id is not the message under test', () {
      final log = flow('GROUP_MESSAGES_DB_INSERT_SUCCESS', <String, Object?>{
        'id': 'aaaa1111',
      });

      expect(groupMessageStoredWithId(log, 'dddd4444'), isFalse);
      expect(groupMessageStoredWithId(log, ''), isFalse);
      expect(
        groupMessageStoredWithId(
          'D/unrelated: GROUP_MESSAGES_DB_INSERT_SUCCESS id aaaa1111',
          'aaaa1111',
        ),
        isFalse,
        reason: 'prose mentioning the event is not a structured insert',
      );
    });

    test('a replayed duplicate with an existing row also proves arrival', () {
      // Device evidence, run 11: the live-fanout insert happened at 11:10:52Z
      // and had rotated out of the ring by the time the dump was pulled, but
      // every later inbox replay still reported the row as already stored.
      final duplicate = 'I/flutter: [FLOW] '
          '${jsonEncode(<String, Object?>{
            'layer': 'FL',
            'event': 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
            'details': <String, Object?>{
              'incoming': true,
              'messageId': '6e4e1d63-bb8f-43fd-90a8-116ea10f34a9',
              'existingLocalRowId': '6e4e1d63-bb8f-43fd-90a8-116ea10f34a9',
            },
          })}';

      expect(groupMessageStoredWithId(duplicate, '6e4e1d63'), isTrue);
      expect(groupMessageStoredWithId(duplicate, 'dddd4444'), isFalse);
    });

    test('the sender publish id is the last successful group send', () {
      final log = <String>[
        'I/flutter: [FLOW] '
            '${jsonEncode(<String, Object?>{
              'layer': 'FL',
              'event': 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
              'details': <String, Object?>{'messageId': 'aaaa1111'},
            })}',
        'I/flutter: [FLOW] '
            '${jsonEncode(<String, Object?>{
              'layer': 'FL',
              'event': 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
              'details': <String, Object?>{'messageId': 'dddd4444'},
            })}',
      ].join('\n');

      expect(latestGroupSendMessageId(log), 'dddd4444');
      expect(latestGroupSendMessageId(''), isNull);
    });

    // Census guard. The relay outage this lane hit — and one bug in this very
    // harness — both came from grepping a literal that no longer existed.
    // Anything the capture waits on must be pinned to its real emission site.
    test('the awaited literals still exist in production source', () {
      expect(
        File(
          'lib/core/database/helpers/group_messages_db_helpers.dart',
        ).readAsStringSync(),
        contains("event: 'GROUP_MESSAGES_DB_INSERT_SUCCESS'"),
      );
      expect(
        File(
          'lib/core/database/helpers/group_messages_db_helpers.dart',
        ).readAsStringSync(),
        contains("event: 'GROUP_MESSAGES_DB_LOAD_ALL_SUCCESS'"),
      );
      final registration = File(
        'lib/features/push/application/register_push_token_use_case.dart',
      ).readAsStringSync();
      expect(registration, contains("'relay_push_registration_success'"));
      expect(registration, contains("'PUSH_REGISTER_TOKEN_SUCCESS'"));
      expect(
        File(
          'lib/features/groups/application/send_group_message_use_case.dart',
        ).readAsStringSync(),
        contains("'GROUP_SEND_MSG_USE_CASE_SUCCESS'"),
      );
    });
  });

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

  test('the 1to1 reaction runner reaches the typed smoke scenario', () {
    // Plan 391 TC-391-01. Reaching the card-asserting variant needs THREE
    // links, not one: the catalog row --scenario resolves, the switch case
    // that names its capture driver, and the flag the variant is gated on.
    // A catalog-only edit still exits 78 ENVIRONMENT BLOCKED at run time.
    final source = _collapsedSource(
      'integration_test/scripts/run_1to1_reaction_notification_device.dart',
    );

    final catalogStart = source.indexOf('const List<_Scenario> _scenarios');
    final catalogEnd = source.indexOf('Future<void> main(', catalogStart);
    expect(catalogStart, greaterThan(0));
    expect(catalogEnd, greaterThan(catalogStart));
    final catalog = source.substring(catalogStart, catalogEnd);
    final entryStart = catalog.indexOf("id: 'android_typed_reaction_smoke'");
    expect(
      entryStart,
      greaterThan(0),
      reason: 'the typed smoke scenario must be selectable by --scenario',
    );
    final nextEntry = catalog.indexOf('_Scenario(', entryStart);
    final entry = nextEntry < 0
        ? catalog.substring(entryStart)
        : catalog.substring(entryStart, nextEntry);
    expect(entry, contains("testCase: 'TC-13-core-smoke'"));
    expect(
      entry,
      contains('requiresSender: true'),
      reason: 'a second device drives the reaction by UI automation',
    );

    expect(
      source,
      contains(
        "'android_typed_reaction_smoke' => _headProvenanceCaptureDriver",
      ),
      reason:
          'without the switch case the runner exits 78 ENVIRONMENT BLOCKED '
          'instead of capturing',
    );

    final argsStart = source.indexOf('final captureArgs = <String>[');
    final argsEnd = source.indexOf(
      'final capture = await Process.start(',
      argsStart,
    );
    expect(argsStart, greaterThan(0));
    expect(argsEnd, greaterThan(argsStart));
    expect(
      source.substring(argsStart, argsEnd),
      contains(
        "if (scenario.id == 'android_typed_reaction_smoke') "
        "'--live-typed-smoke'",
      ),
      reason:
          'only the typed smoke variant hard-asserts one card, and only it '
          'may receive the flag',
    );
  });

  test('each capture branch stem matches its scenario id', () {
    // Plan 391 TC-391-02. The runner resolves <artifact-dir>/<scenario>.json;
    // the driver writes <artifact-dir>/<stem>.json flat. A stem that is not
    // the id makes _validateArtifacts exit 66 "Missing artifact:" AFTER a
    // fully successful device capture.
    final source = _collapsedSource(
      'integration_test/scripts/capture_1to1_reaction_head_provenance.dart',
    );
    final stemStart = source.indexOf('String get _artifactStem');
    final scenarioStart = source.indexOf('String get _scenario', stemStart);
    final testCaseStart = source.indexOf('String get _testCase', scenarioStart);
    expect(stemStart, greaterThan(0));
    expect(scenarioStart, greaterThan(stemStart));
    expect(testCaseStart, greaterThan(scenarioStart));

    List<String> literals(String slice) => RegExp(
      r"'([A-Za-z0-9_]+)'",
    ).allMatches(slice).map((match) => match.group(1)!).toList(growable: false);

    final stems = literals(source.substring(stemStart, scenarioStart));
    final scenarios = literals(source.substring(scenarioStart, testCaseStart));
    expect(stems, hasLength(4));
    expect(scenarios, hasLength(4));
    expect(
      stems,
      scenarios,
      reason: 'every capture branch must write <scenario id>.json',
    );
  });

  test('typed smoke measures recipient absence immediately before the reaction '
      'drive', () {
    // Plan 391 TC-391-03. The window is load-bearing: absence at KILL time
    // is already established by _terminateRecipient, so only a measurement
    // taken inside the reaction_capture stage, before the reaction is
    // driven, proves the recipient was dead when the push was sent.
    final source = _collapsedSource(
      'integration_test/scripts/capture_1to1_reaction_head_provenance.dart',
    );
    final windowStart = source.indexOf("_stage = 'reaction_capture'");
    final windowEnd = source.indexOf('_longPressText(', windowStart);
    expect(windowStart, greaterThan(0));
    expect(windowEnd, greaterThan(windowStart));

    final measurement = RegExp(
      r'final (\w+) = await _recipientProcessAndActivityAbsentWithin\(',
    ).firstMatch(source.substring(windowStart, windowEnd));
    expect(
      measurement,
      isNotNull,
      reason:
          'the recipient absence bool must be measured in the '
          'reaction_capture stage, before the reaction is driven',
    );
    final identifier = measurement!.group(1)!;

    final callStart = source.indexOf('_writePassedArtifact(', windowEnd);
    expect(callStart, greaterThan(windowEnd));
    expect(
      source.substring(callStart, source.indexOf(');', callStart)),
      contains('recipientAbsentBeforeReaction: $identifier'),
      reason: 'the measured value must reach the artifact writer',
    );

    final observationStart = source.indexOf("'observation': {");
    final observationEnd = source.indexOf(
      "'sourceAttribution': {",
      observationStart,
    );
    expect(observationStart, greaterThan(0));
    expect(observationEnd, greaterThan(observationStart));
    expect(
      source.substring(observationStart, observationEnd),
      contains("'recipientProcessAbsentBeforeReaction': $identifier,"),
      reason:
          'the artifact must record the measured value, never a literal '
          'the capture never observed',
    );
  });

  test(
    'the 1to1 android capture attributes push registration to the recipient '
    'device',
    () {
      // Plan 391 TC-391-11, found by executing the lane. The android arm
      // waited on the relay-journal line `[PUSH] Token registered for
      // <peerPrefix> (android)`, which relay v1.8.0 (8d86501e4) deleted with
      // the rest of the identifying [PUSH] vocabulary — a removal Plan 368
      // pins. Measured 2026-08-20: the recipient logged
      // relay_push_registration_success at 07:49:06Z and the capture still
      // failed at 07:51:12Z with "Timed out waiting for recipient FCM token
      // registration". capture_group_reaction_notification_device.dart already
      // moved this wait to the device boundary; this pins the same move here.
      final source = _collapsedSource(
        'integration_test/scripts/capture_1to1_reaction_head_provenance.dart',
      );
      final stageStart = source.indexOf(
        "_stage = 'recipient_push_registration'",
      );
      final stageEnd = source.indexOf(
        'await _requireCleanNotificationSlate();',
        stageStart,
      );
      expect(stageStart, greaterThan(0));
      expect(stageEnd, greaterThan(stageStart));
      expect(
        source.substring(stageStart, stageEnd),
        contains('await _waitForRecipientPushRegistrationAccepted();'),
        reason:
            'the android capture must attribute registration to the '
            'recipient device, not to a relay line the relay no longer emits',
      );

      final methodStart = source.indexOf(
        'Future<void> _waitForRecipientPushRegistrationAccepted()',
      );
      expect(methodStart, greaterThan(0));
      final method = source.substring(
        methodStart,
        source.indexOf('Future<', methodStart + 1),
      );
      expect(method, contains('androidRelayPushRegistrationAccepted('));
      expect(
        method,
        contains("_adb(recipientId, ['logcat'"),
        reason: 'the evidence must come from the recipient device own log',
      );
    },
  );

  group('android direct-reaction background push observation', () {
    // Plan 391 TC-391-12. The relay's peer-attributed push line is gone
    // (`[PUSH] Notification sent to <peerPrefix>`, deleted by 8d86501e4), and
    // the surviving [PUSH] vocabulary is `outcome=…` with no peer at all. The
    // provider send is therefore attributed on the RECIPIENT device, where the
    // evidence is unambiguously that device's: the direct-reaction decrypt
    // marker fires only after the background isolate decrypted a reaction
    // addressed to this recipient with this recipient's own secret key.
    String flow(String event, Map<String, Object?> details) =>
        'I/flutter: [FLOW] '
        '${jsonEncode(<String, Object?>{'ts': '2026-08-20T07:49:06.000Z', 'milestone': 'M1_IDENTITY_INIT', 'layer': 'FL', 'event': event, 'details': details})}';

    test('accepts the direct reaction crypto-plugin marker', () {
      expect(
        androidDirectReactionBackgroundPushObserved(
          flow('PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK', <String, Object?>{
            'kind': 'reaction',
          }),
        ),
        isTrue,
      );
    });

    test('rejects the group reaction marker', () {
      // The same event fires for group reactions. A 1:1 proof must not be
      // satisfiable by the arm it is not testing.
      expect(
        androidDirectReactionBackgroundPushObserved(
          flow('PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK', <String, Object?>{
            'kind': 'group_reaction',
          }),
        ),
        isFalse,
      );
    });

    test('rejects a bare background message receipt', () {
      // A push that arrived but never reached the direct-reaction decrypt path
      // cannot have produced a typed reaction card.
      expect(
        androidDirectReactionBackgroundPushObserved(
          flow('PUSH_BACKGROUND_MESSAGE_RECEIVED', <String, Object?>{
            'messageId': '0:1787212139',
            'dataKeys': <String>['type', 'sender_id', 'kem', 'ciphertext'],
          }),
        ),
        isFalse,
      );
    });

    test('rejects an unrelated or empty log', () {
      expect(androidDirectReactionBackgroundPushObserved(''), isFalse);
      expect(
        androidDirectReactionBackgroundPushObserved(
          'I/flutter: [PUSH_DIAG] registration_success trigger=startup',
        ),
        isFalse,
      );
    });
  });

  test('the 1to1 provider send is attributed on the recipient device', () {
    // Plan 391 TC-391-13. Every card-attribution decision must read the
    // effective signal, not `relayCapture.providerMatchedEvent`, which the
    // current relay can never set. Otherwise the typed smoke throws whether or
    // not the card was posted, and TC-00 writes a false providerConfirmedNoSend.
    final source = _collapsedSource(
      'integration_test/scripts/capture_1to1_reaction_head_provenance.dart',
    );
    final stageStart = source.indexOf("_stage = 'reaction_capture'");
    final stageEnd = source.indexOf("_stage = 'artifact'", stageStart);
    expect(stageStart, greaterThan(0));
    expect(stageEnd, greaterThan(stageStart));
    final stage = source.substring(stageStart, stageEnd);

    expect(
      stage,
      contains("_adb(recipientId, ['logcat', '-c'])"),
      reason: 'the recipient observation window must be bounded too',
    );
    expect(stage, contains('_recipientDirectReactionPushWithin('));
    for (final guard in const <String>[
      'if (providerSendObserved && cards.length != 1)',
      'if (!providerSendObserved && cards.isNotEmpty)',
      // Widened from `liveTypedSmoke` when the alive-connected durable leg
      // joined it: both card-asserting variants require an observed provider
      // send. The claim this row makes is unchanged — the guard reads the
      // EFFECTIVE signal, never relayCapture.providerMatchedEvent.
      'if (_typedCopyRequired && !providerSendObserved)',
    ]) {
      expect(
        stage,
        contains(guard),
        reason: 'a card-attribution guard still reads the dead relay signal',
      );
    }

    final attributionStart = source.indexOf("'sourceAttribution': {");
    final attributionEnd = source.indexOf(
      "'unreadLifecycle':",
      attributionStart,
    );
    expect(attributionStart, greaterThan(0));
    expect(attributionEnd, greaterThan(attributionStart));
    final attribution = source.substring(attributionStart, attributionEnd);
    expect(attribution, contains("'recipientBackgroundPushObserved':"));
    expect(
      attribution,
      contains("'providerEvidenceSource':"),
      reason: 'the artifact must name where its provider evidence came from',
    );
    expect(attribution, contains("'providerEvidencePath':"));
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

  // -------------------------------------------------------------------------
  // Plan 386 W2 (G20) — graded selection is identity-bound and the device flow
  // log is accumulated monotonically.
  // -------------------------------------------------------------------------

  group('Plan 386 graded send selection', () {
    String breadcrumb(String marker) =>
        '08-19 10:00:00.000  1000  1000 I $groupSendMarkerBreadcrumbTag: '
        '$groupSendMarkerBreadcrumbPrefix$marker';

    String timing(String outcome, {int recipients = 1, bool stored = true}) =>
        '08-19 10:00:01.000  2000  2000 I flutter : [FLOW] '
        '${jsonEncode(<String, Object?>{
          'event': 'GROUP_SEND_MSG_TIMING',
          'details': <String, Object?>{
            'outcome': outcome,
            'expectedRecipientCount': recipients,
            'inboxStored': stored,
            'inboxPending': false,
          },
        })}';

    test(
      'the graded send outcome is selected by its own marker, never by position',
      () {
        // A ROTATED window: the first two sends' outcomes aged out of the
        // source, so only the third send's breadcrumb and outcome survive.
        // Today's positional rule computed `baselineOutcomeCount` from a read
        // that still held those two, then indexed `observations[2]` — which in
        // this window does not exist, and in a partially rotated window points
        // at the WRONG send.
        final rotated = <String>[
          timing('group_recovery_pending'),
          breadcrumb('plan386-graded'),
          timing('success'),
        ].join('\n');

        final selected = selectGroupSendObservationForMarker(
          rotated,
          'plan386-graded',
        );

        expect(selected, isNotNull);
        expect(selected!.outcome, 'success');
        expect(selected.isCommitted, isTrue);
        expect(
          selected.hasRequiredInboxCustody(recipientCount: 1),
          isTrue,
        );

        // The positional rule on the same window: two observations exist and
        // the pre-tap baseline was 2, so `observations[2]` is out of range and
        // an index of 1 would return the WRONG send's outcome.
        final positional = extractGroupSendTimingObservations(rotated);
        expect(positional.length, 2);
        expect(positional[0].outcome, 'group_recovery_pending');
      },
    );

    test('the marker selector fails closed on a foreign or absent breadcrumb', () {
      final window = <String>[
        breadcrumb('plan386-other'),
        timing('success'),
      ].join('\n');

      expect(
        selectGroupSendObservationForMarker(window, 'plan386-graded'),
        isNull,
        reason: 'a different send must never grade this one',
      );
      expect(selectGroupSendObservationForMarker(window, ''), isNull);
      expect(
        selectGroupSendObservationForMarker(breadcrumb('plan386-graded'), 'plan386-graded'),
        isNull,
        reason: 'a breadcrumb with no outcome after it is not a result',
      );
    });

    test('the last breadcrumb for a marker wins', () {
      // `_sendGroupText` re-taps after a group-recovery-pending outcome and
      // mints a fresh breadcrumb each attempt; only the final attempt is the
      // send under test.
      final window = <String>[
        breadcrumb('plan386-graded'),
        timing('group_recovery_pending'),
        breadcrumb('plan386-graded'),
        timing('success'),
      ].join('\n');

      expect(
        selectGroupSendObservationForMarker(window, 'plan386-graded')!.outcome,
        'success',
      );
    });

    test('the capture file contains no positional or count-delta selector', () {
      // The fixture rows above cannot see the capture file, so a repair that
      // fixed the helper and left the old rule in place would pass them all.
      final capture = File(
        'integration_test/scripts/'
        'capture_group_reaction_notification_device.dart',
      ).readAsStringSync();

      expect(capture, isNot(contains('baselineOutcomeCount')));
      expect(capture, isNot(contains('observations.length >')));
      expect(capture, contains('selectGroupSendObservationForMarker('));
      expect(capture, contains('_mintGroupSendBreadcrumb('));
    });
  });

  group('Plan 386 device flow accumulator', () {
    test('the accumulator keeps id-distinct events that render identically', () {
      final accumulator = DeviceFlowAccumulator();
      const line = '08-19 10:00:00.000 I flutter : [FLOW] '
          '{"event":"GROUP_REACTION_SEND_QUEUED"}';

      // Two genuinely distinct sends whose raw lines render identically. The
      // previous `Set<String>` fold collapsed them to one, which silently
      // deflated every count taken over the accumulator — including the
      // `GROUP_REACTION_SEND_QUEUED == 2` transition assertion this lane makes.
      accumulator.absorb('$line\n$line\n');
      expect(accumulator.length, 2);

      // Re-absorbing an overlapping window is still idempotent.
      accumulator.absorb('$line\n$line\n');
      expect(accumulator.length, 2);

      // A third genuine occurrence still contributes.
      accumulator.absorb('$line\n$line\n$line\n');
      expect(accumulator.length, 3);
    });

    test('the accumulator is monotonic across a rotated window', () {
      final accumulator = DeviceFlowAccumulator();
      accumulator.absorb('first\nsecond\n');
      // The next read no longer contains the earlier lines at all — exactly
      // what a rotated ring returns, and what made `count > baseline` waits
      // hang forever.
      accumulator.absorb('third\n');

      expect(accumulator.text, 'first\nsecond\nthird\n');
      accumulator.reset();
      expect(accumulator.text, '');
    });

    test('the sender path and the bounded collector both fold through it', () {
      final capture = File(
        'integration_test/scripts/'
        'capture_group_reaction_notification_device.dart',
      ).readAsStringSync();

      final waitStart = capture.indexOf(
        'Future<void> _waitForSenderEventCount(',
      );
      final waitEnd = capture.indexOf(
        'Future<double?> _relayWakeAttemptsSince(',
        waitStart,
      );
      expect(waitStart, greaterThan(0));
      expect(waitEnd, greaterThan(waitStart));
      final wait = capture.substring(waitStart, waitEnd);
      expect(wait, contains('_accumulatedSenderFlowLines()'));
      expect(wait, isNot(contains("'logcat'")));

      final collectStart = capture.indexOf('Future<void> _collectBoundedLogs()');
      final collectEnd = capture.indexOf(
        'Future<void> _tapOrbitCreateFab(',
        collectStart,
      );
      expect(collectStart, greaterThan(0));
      expect(collectEnd, greaterThan(collectStart));
      final collect = capture.substring(collectStart, collectEnd);
      expect(collect, contains('_accumulatedSenderFlowLines()'));
      expect(collect, contains('_accumulatedRecipientFlowLines()'));
      expect(collect, isNot(contains('_readAndroidLogcat(')));
    });
  });

  group('Plan 386 relay counter evidence', () {
    test('a scrape pair parses into per-series deltas', () {
      final window = parseRelayMetricsWindow(
        '$relayMetricsPhaseMarker$relayMetricsBaselinePhase\n'
        '# HELP relay_group_reaction_wake_total ignored\n'
        '# TYPE relay_group_reaction_wake_total counter\n'
        'relay_group_reaction_wake_total{outcome="attempted"} 40\n'
        'relay_push_sent_total{result="success"} 900\n'
        '$relayMetricsPhaseMarker$relayMetricsFinalPhase\n'
        // Labels deliberately reordered and re-spaced: a canonical key must
        // still subtract correctly.
        'relay_group_reaction_wake_total{outcome="attempted"}  42\n'
        'relay_push_sent_total{result="success"} 903\n',
      );

      expect(window, isNotNull);
      expect(
        window!.delta(
          relayCounterSeries(
            relayGroupReactionWakeCounter,
            const <String, String>{'outcome': 'attempted'},
          ),
        ),
        2,
      );
      // A series absent from the baseline has never been incremented on this
      // process, which Prometheus does not export — treating it as 0 is right.
      expect(
        window.delta(
          relayCounterSeries(
            relayGroupReactionWakeCounter,
            const <String, String>{'outcome': 'route_error'},
          ),
        ),
        0,
      );
      expect(relayCounterFamilyDelta(window, relayPushSentCounter), 3);
    });

    test('a truncated or restarted window is null, never zero', () {
      expect(
        parseRelayMetricsWindow(
          '$relayMetricsPhaseMarker$relayMetricsBaselinePhase\n'
          'relay_push_sent_total{result="success"} 900\n',
        ),
        isNull,
        reason: 'a missing final phase must not read as "no growth"',
      );
      expect(
        parseRelayMetricsWindow(
          '$relayMetricsPhaseMarker$relayMetricsFinalPhase\n'
          'relay_push_sent_total{result="success"} 900\n'
          '$relayMetricsPhaseMarker$relayMetricsBaselinePhase\n'
          'relay_push_sent_total{result="success"} 800\n',
        ),
        isNull,
        reason: 'phases out of order are not a window',
      );

      final restarted = parseRelayMetricsWindow(
        '$relayMetricsPhaseMarker$relayMetricsBaselinePhase\n'
        'relay_push_sent_total{result="success"} 900\n'
        '$relayMetricsPhaseMarker$relayMetricsFinalPhase\n'
        'relay_push_sent_total{result="success"} 4\n',
      );
      expect(restarted, isNotNull);
      expect(
        relayCounterFamilyDelta(restarted!, relayPushSentCounter),
        isNull,
        reason: 'a counter that went backwards means the relay restarted',
      );
    });
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
    // Plan 386 TC-386-06 re-pin. This slice used to require
    // `baselineOutcomeCount` and `extractGroupSendTimingObservations(` — the
    // positional selector and its raw extractor. Selection is now bound to a
    // send-scoped identity the harness mints, so the pinned literals move with
    // it rather than being deleted.
    expect(method, contains('_mintGroupSendBreadcrumb(deviceId, marker)'));
    expect(method, contains('selectGroupSendObservationForMarker('));
    expect(method, isNot(contains('baselineOutcomeCount')));
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
    // Plan 391, device-measured 2026-08-20. This pin used to require
    // 0x10008000 — NEW_TASK|CLEAR_TASK. CLEAR_TASK destroys the activity while
    // the process lives, so a SECOND Flutter engine starts in a process whose
    // first engine still owns the canonical Go runtime and the SQLCipher
    // handle: GO_BRIDGE_PLATFORM_ERROR 'This Flutter engine does not own the
    // active Go runtime', DatabaseException(database_closed), and a BLACK
    // screen with no Orbit nodes at all. The task must be RESUMED, and the
    // walk back to Orbit must be observed rather than assumed.
    expect(method, contains('0x10000000'));
    expect(method, isNot(contains('0x10008000')));
    expect(method, contains('KEYCODE_BACK'));
    expect(method, contains('extractOrbitUnreadCount('));
    expect(method, isNot(contains('force-stop')));
    expect(method, isNot(contains('_launch(')));

    // The artifact must not describe a navigation the driver stopped using.
    expect(
      source,
      contains(
        "'orbitObservationNavigation': "
        "'launcher_resume_walk_back_no_force_stop'",
      ),
    );
    expect(source, isNot(contains('launcher_reopen_clear_task')));
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

  // The DURABLE direct-reaction arm, and the alive-connected leg that is the
  // only place it can execute.
  //
  // Measured over the whole device-log corpus 2026-08-20: all 14 `durable:
  // true` sightings came from processes running the full foreground app
  // runtime; none came from a cold wake. That is not a coincidence of sampling
  // — `background_message_handler.dart:1080-1087` says so in a comment, and the
  // writer census backs it: only the foreground runtime stages the exact
  // `direct_notification_display_outbox` row the arm resolves.
  group('durable direct-reaction arm', () {
    String flow(String event, Map<String, Object?> details) =>
        'I/flutter: [FLOW] '
        '${jsonEncode(<String, Object?>{
          'ts': '2026-08-20T09:00:00.000Z',
          'milestone': 'M1_IDENTITY_INIT',
          'layer': 'FL',
          'event': event,
          'details': details,
        })}';

    test('reports the durable arm executed for an osPosted direct reaction', () {
      final observed = androidDurableDirectReactionShow(
        [
          flow('PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK', <String, Object?>{
            'kind': 'reaction',
          }),
          flow('PUSH_BACKGROUND_NOTIFICATION_SHOWN', <String, Object?>{
            'durable': true,
            'producer': 'direct_reaction',
            'disposition': 'osPosted',
            'silent': false,
          }),
        ].join('\n'),
      );

      expect(observed.durableArmExecuted, isTrue);
      expect(observed.durableShown, isTrue);
      expect(observed.disposition, 'osPosted');
      expect(observed.silent, isFalse);
      expect(observed.deferralReasons, isEmpty);
    });

    test('rejects the non-durable fallback and names the deferral reason', () {
      // This is exactly what Plan 391's killed-path leg observed, twice. The
      // card IS posted, so a card-only assertion goes green while the arm
      // under test never ran.
      final observed = androidDurableDirectReactionShow(
        [
          flow('PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED', <String, Object?>{
            'reason': 'exact_sql_authority_unavailable',
            'presentation': 'nondurable_fallback',
          }),
          flow('PUSH_BACKGROUND_NOTIFICATION_SHOWN', <String, Object?>{
            'messageId': '0:1787100673237835%1d5344bef9fd7ecd',
            'payload': '[redacted:peerid]',
            'silent': false,
          }),
        ].join('\n'),
      );

      expect(observed.durableArmExecuted, isFalse);
      expect(observed.durableShown, isFalse);
      expect(observed.fallbackShown, isTrue);
      expect(observed.deferralReasons, ['exact_sql_authority_unavailable']);
    });

    test('does not accept another producer as the direct-reaction arm', () {
      for (final producer in const ['direct_message', 'group_reaction']) {
        final observed = androidDurableDirectReactionShow(
          flow('PUSH_BACKGROUND_NOTIFICATION_SHOWN', <String, Object?>{
            'durable': true,
            'producer': producer,
            'disposition': 'osPosted',
          }),
        );
        expect(
          observed.durableArmExecuted,
          isFalse,
          reason: '$producer is a different arm of the same resolver',
        );
      }
    });

    test('accumulates across polls so a rotated ring cannot erase evidence', () {
      // The alive recipient's log rotates fast. Each poll re-reads the whole
      // remaining buffer, and rotation only drops from the FRONT, so the fold
      // must keep the per-reason maximum rather than the last snapshot.
      final early = androidDurableDirectReactionShow(
        [
          flow('PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED', <String, Object?>{
            'reason': 'exact_sql_authority_unavailable',
          }),
          flow('PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED', <String, Object?>{
            'reason': 'exact_sql_authority_unavailable',
          }),
        ].join('\n'),
      );
      // A later read whose front has rotated away: one deferral is gone, and
      // the durable show has since landed.
      final late = androidDurableDirectReactionShow(
        [
          flow('PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED', <String, Object?>{
            'reason': 'exact_sql_authority_unavailable',
          }),
          flow('PUSH_BACKGROUND_NOTIFICATION_SHOWN', <String, Object?>{
            'durable': true,
            'producer': 'direct_reaction',
            'disposition': 'osPosted',
            'silent': false,
          }),
        ].join('\n'),
      );

      expect(early.durableArmExecuted, isFalse);
      expect(late.deferralReasons, hasLength(1));

      final folded = early.mergedWith(late);
      expect(folded.durableArmExecuted, isTrue);
      expect(
        folded.deferralReasons,
        hasLength(2),
        reason: 'the deferral the ring dropped must survive the fold',
      );
      expect(
        AndroidDurableDirectReactionShow.nothingObserved
            .mergedWith(early)
            .mergedWith(late)
            .deferralReasons,
        hasLength(2),
        reason: 'folding from the empty seed is the capture loop\'s own path',
      );
    });

    test('does not accept a durable show the OS did not post', () {
      final observed = androidDurableDirectReactionShow(
        flow('PUSH_BACKGROUND_NOTIFICATION_SHOWN', <String, Object?>{
          'durable': true,
          'producer': 'direct_reaction',
          'disposition': 'suppressedPolicy',
        }),
      );

      expect(observed.durableShown, isTrue);
      expect(observed.durableArmExecuted, isFalse);
      expect(observed.disposition, 'suppressedPolicy');
    });
  });

  group('alive-but-backgrounded recipient', () {
    const package = 'com.mknoon.app';
    const backgrounded = '''
  Task{111 #42 type=standard A=$package U=0 visible=false}
    ActivityRecord{aaa u0 $package/.MainActivity t42}
  mResumedActivity: ActivityRecord{bbb u0 com.android.launcher/.Launcher t1}
  mFocusedApp=ActivityRecord{bbb u0 com.android.launcher/.Launcher t1}
''';
    const foreground = '''
  Task{111 #42 type=standard A=$package U=0 visible=true}
    ActivityRecord{aaa u0 $package/.MainActivity t42}
  mResumedActivity: ActivityRecord{aaa u0 $package/.MainActivity t42}
  mFocusedApp=ActivityRecord{aaa u0 $package/.MainActivity t42}
''';

    test('a backgrounded app still has an attached activity record', () {
      // The distinction the leg depends on. KEYCODE_HOME leaves the
      // ActivityRecord in the task stack, so the absence predicate the killed
      // path uses cannot express "alive but backgrounded".
      expect(hasAttachedAndroidActivity(backgrounded, package), isTrue);
      expect(hasResumedAndroidActivity(backgrounded, package), isFalse);
      expect(hasResumedAndroidActivity(foreground, package), isTrue);
    });

    test('alive-and-backgrounded requires a live pid and no resumed activity', () {
      expect(
        isAndroidAppProcessAliveAndBackgrounded(
          pidOutput: '6130',
          dumpsysActivities: backgrounded,
          packageName: package,
        ),
        isTrue,
      );
      expect(
        isAndroidAppProcessAliveAndBackgrounded(
          pidOutput: '',
          dumpsysActivities: backgrounded,
          packageName: package,
        ),
        isFalse,
        reason: 'a killed recipient is the other leg, and cannot go durable',
      );
      expect(
        isAndroidAppProcessAliveAndBackgrounded(
          pidOutput: '6130',
          dumpsysActivities: foreground,
          packageName: package,
        ),
        isFalse,
        reason:
            'a foreground app takes the in-app lane, not the background '
            'isolate the durable arm runs in',
      );
    });
  });

  group('the alive-connected durable leg is reachable and honest', () {
    test('the 1to1 reaction runner reaches the durable scenario', () {
      // Same three links Plan 391's TC-391-01 pins for the typed smoke: the
      // catalog row --scenario resolves, the switch case naming the capture
      // driver, and the flag the variant is gated on. A catalog-only edit
      // still exits 78 ENVIRONMENT BLOCKED at run time.
      final source = _collapsedSource(
        'integration_test/scripts/run_1to1_reaction_notification_device.dart',
      );

      final catalogStart = source.indexOf('const List<_Scenario> _scenarios');
      final catalogEnd = source.indexOf('Future<void> main(', catalogStart);
      expect(catalogStart, greaterThan(0));
      expect(catalogEnd, greaterThan(catalogStart));
      final catalog = source.substring(catalogStart, catalogEnd);
      final entryStart = catalog.indexOf(
        "id: 'android_durable_reaction_background_connected'",
      );
      expect(
        entryStart,
        greaterThan(0),
        reason: 'the durable leg must be selectable by --scenario',
      );
      final nextEntry = catalog.indexOf('_Scenario(', entryStart);
      final entry = nextEntry < 0
          ? catalog.substring(entryStart)
          : catalog.substring(entryStart, nextEntry);
      expect(entry, contains("testCase: 'TC-DURABLE-DIRECT-REACTION'"));
      expect(
        entry,
        contains('requiresSender: true'),
        reason: 'a second device drives the reaction by UI automation',
      );

      expect(
        source,
        contains(
          "'android_durable_reaction_background_connected' => "
          '_headProvenanceCaptureDriver',
        ),
        reason:
            'without the switch case the runner exits 78 ENVIRONMENT BLOCKED '
            'instead of capturing',
      );

      final argsStart = source.indexOf('final captureArgs = <String>[');
      final argsEnd = source.indexOf(
        'final capture = await Process.start(',
        argsStart,
      );
      expect(argsStart, greaterThan(0));
      expect(argsEnd, greaterThan(argsStart));
      expect(
        source.substring(argsStart, argsEnd),
        contains(
          "if (scenario.id == 'android_durable_reaction_background_connected') "
          "'--durable-background-connected'",
        ),
        reason:
            'the capture driver derives its variant from flags, never from '
            '--scenario',
      );
    });

    test('the durable variant backgrounds the recipient instead of killing it', () {
      // The load-bearing difference between this leg and the killed-path leg.
      // _terminateRecipient sat on the COMMON path; if the durable variant
      // still took it, the app would be dead, no display-outbox row would
      // exist, and the arm under test could not run at all.
      final source = _collapsedSource(
        'integration_test/scripts/capture_1to1_reaction_head_provenance.dart',
      );

      expect(
        source,
        contains(
          'if (durableBackgroundConnected) { await _backgroundRecipient(); } '
          'else { await _terminateRecipient(); }',
        ),
        reason:
            'the durable variant must background the recipient, and every '
            'other variant must still kill it',
      );
      expect(
        source,
        contains(
          'Future<void> _backgroundRecipient() async { await '
          "_adbShell(recipientId, ['input', 'keyevent', 'KEYCODE_HOME']);",
        ),
        reason: 'HOME backgrounds; am kill would not',
      );
      expect(
        source.substring(source.indexOf('Future<void> _backgroundRecipient()')),
        contains('_recipientProcessAliveAndBackgroundedWithin('),
        reason:
            'a recipient that died during HOME must fail the leg, not be '
            'graded as if it were alive',
      );
    });

    test('the durable verdict is measured, never assumed', () {
      // The artifact must carry what the recipient device actually logged. A
      // literal here would let the leg claim the durable arm ran on a run
      // where it deferred — which is the precise failure this whole leg
      // exists to make impossible.
      final source = _collapsedSource(
        'integration_test/scripts/capture_1to1_reaction_head_provenance.dart',
      );

      final windowStart = source.indexOf("_stage = 'reaction_capture'");
      final windowEnd = source.indexOf('_writePassedArtifact(', windowStart);
      expect(windowStart, greaterThan(0));
      expect(windowEnd, greaterThan(windowStart));
      final window = source.substring(windowStart, windowEnd);

      final measurement = RegExp(
        r'final (\w+) = durableBackgroundConnected \? await '
        r'_recipientDurableDirectReactionShowWithin\(',
      ).firstMatch(window);
      expect(
        measurement,
        isNotNull,
        reason:
            'the durable verdict must be read from the recipient log inside '
            'the reaction window',
      );
      final identifier = measurement!.group(1)!;

      expect(
        window,
        contains('!$identifier.durableArmExecuted'),
        reason: 'a deferred run must fail the capture, not write a passed '
            'artifact',
      );

      final observationStart = source.indexOf("'observation': {");
      final observationEnd = source.indexOf(
        "'sourceAttribution': {",
        observationStart,
      );
      expect(observationStart, greaterThan(0));
      expect(observationEnd, greaterThan(observationStart));
      final observation = source.substring(observationStart, observationEnd);
      expect(
        observation,
        contains("'durableEffectObserved': durableShow?.durableShown ?? false"),
      );
      expect(
        observation,
        contains(
          "'durableEffectDisposition': durableShow?.disposition ?? "
          "'not_observed'",
        ),
      );
      expect(
        observation,
        contains(
          "'durableEffectDeferralReasons': durableShow?.deferralReasons ?? "
          'const <String>[]',
        ),
        reason:
            'the deferral reasons are the diagnosis when the arm does not '
            'run, and must survive into the artifact',
      );
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

/// Reads a harness source file with every run of whitespace collapsed to one
/// space, so source-slice pins survive `dart format` line wrapping.
String _collapsedSource(String path) =>
    File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
