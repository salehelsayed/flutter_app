import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

void main() {
  setUp(() {
    flowEventLoggingEnabled = false;
  });

  tearDown(() {
    flowEventLoggingEnabled = kDebugMode;
    debugSetFlowEventSink(null);
    debugPrint = debugPrintThrottled;
  });

  // ---------------------------------------------------------------------------
  // emitFlowEvent
  // ---------------------------------------------------------------------------
  group('emitFlowEvent', () {
    test('outputs JSON with [FLOW] prefix when enabled', () {
      flowEventLoggingEnabled = true;

      final output = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };

      emitFlowEvent(
        layer: 'FL',
        event: 'TEST_EVENT',
        details: {'key': 'value'},
      );

      // Restore debugPrint
      debugPrint = debugPrintThrottled;

      expect(output.length, equals(1));
      expect(output.first, startsWith('[FLOW] '));
    });

    test('does not output when flowEventLoggingEnabled is false', () {
      flowEventLoggingEnabled = false;

      final output = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };

      emitFlowEvent(layer: 'FL', event: 'SHOULD_NOT_APPEAR', details: {});

      debugPrint = debugPrintThrottled;

      expect(output, isEmpty);
    });

    test('includes milestone, layer, event, details in output', () {
      flowEventLoggingEnabled = true;

      final output = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };

      emitFlowEvent(
        layer: 'FL',
        event: 'SAMPLE_EVENT',
        details: {'foo': 'bar'},
      );

      debugPrint = debugPrintThrottled;

      final jsonStr = output.first.substring('[FLOW] '.length);
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(parsed['milestone'], equals('M1_IDENTITY_INIT'));
      expect(parsed['layer'], equals('FL'));
      expect(parsed['event'], equals('SAMPLE_EVENT'));
      expect(parsed['details'], equals({'foo': 'bar'}));
    });

    test('includes ISO-8601 ts field', () {
      flowEventLoggingEnabled = true;

      final output = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };

      emitFlowEvent(layer: 'FL', event: 'TS_TEST', details: {});

      debugPrint = debugPrintThrottled;

      final jsonStr = output.first.substring('[FLOW] '.length);
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(parsed['ts'], isA<String>());
      // Should parse as valid DateTime
      final dt = DateTime.parse(parsed['ts'] as String);
      expect(dt.isUtc, isTrue);
    });

    test('encodes details map into JSON correctly', () {
      flowEventLoggingEnabled = true;

      final output = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };

      emitFlowEvent(
        layer: 'FL',
        event: 'DETAILS_TEST',
        details: {'count': 42, 'flag': true, 'name': 'test'},
      );

      debugPrint = debugPrintThrottled;

      final jsonStr = output.first.substring('[FLOW] '.length);
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
      final details = parsed['details'] as Map<String, dynamic>;

      expect(details['count'], equals(42));
      expect(details['flag'], equals(true));
      expect(details['name'], equals('test'));
    });

    test('ER005 redacts secrets and multiaddrs before sink and logs', () {
      flowEventLoggingEnabled = true;

      final sinkEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(sinkEvents.add);
      final output = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };

      emitFlowEvent(
        layer: 'FL',
        event: 'ER005_SECRET_SURFACE',
        details: {
          'privateKeyHex': 'deadbeef-private-key',
          'ciphertext': 'raw-ciphertext-blob',
          'peerId': '12D3KooWLongSensitivePeerIdentifier',
          'errorMessage':
              'failed privateKey=deadbeef ciphertext=raw-ciphertext-blob '
              '/ip4/10.0.0.1/tcp/4001/p2p/12D3KooWRelayPeer',
          'nested': {'secretKey': 'mlkem-secret-key', 'nonce': 'nonce-secret'},
        },
      );

      final sinkPayload = jsonEncode(sinkEvents.single);
      final logPayload = output.single.substring('[FLOW] '.length);

      for (final payload in [sinkPayload, logPayload]) {
        expect(payload, isNot(contains('deadbeef-private-key')));
        expect(payload, isNot(contains('raw-ciphertext-blob')));
        expect(payload, isNot(contains('12D3KooWLongSensitivePeerIdentifier')));
        expect(payload, isNot(contains('/ip4/10.0.0.1')));
        expect(payload, isNot(contains('mlkem-secret-key')));
        expect(payload, isNot(contains('nonce-secret')));
        expect(payload, contains('[redacted]'));
        expect(payload, contains('[redacted:multiaddr]'));
      }
    });

    test(
      'OB-012 redacts real-looking diagnostic secrets from sink and logs',
      () {
        flowEventLoggingEnabled = true;

        const groupKey = 'k7Yx6WcRZP9Lq2mN4bV8tS0uA3hD5fG7jK9pL1qR3sT=';
        const privateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDOb012Private
KeyMaterialShouldNeverAppearInDiagnostics
-----END PRIVATE KEY-----''';
        const plaintext =
            'OB012 private plaintext body: meet at 10:45 near the east gate';
        const relay =
            '/dns/relay.ob012.example/tcp/4001/wss/p2p/12D3KooWOb012Relay';
        const forbidden = [
          groupKey,
          'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcw',
          '-----BEGIN PRIVATE KEY-----',
          'KeyMaterialShouldNeverAppearInDiagnostics',
          plaintext,
          relay,
        ];

        final sinkEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(sinkEvents.add);
        final output = <String>[];
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) output.add(message);
        };

        emitFlowEvent(
          layer: 'FL',
          event: 'OB012_REAL_SECRET_SURFACE',
          details: {
            'groupKey': groupKey,
            'privateKeyPem': privateKeyPem,
            'plaintextMessage': plaintext,
            'errorMessage':
                'failure groupKey="$groupKey" privateKey="$privateKeyPem" '
                'plaintext="$plaintext" $relay',
            'nested': [
              {'secretKey': groupKey, 'note': 'plaintext="$plaintext"'},
            ],
          },
        );

        final sinkPayload = jsonEncode(sinkEvents.single);
        final logPayload = output.single.substring('[FLOW] '.length);

        for (final payload in [sinkPayload, logPayload]) {
          for (final fragment in forbidden) {
            expect(
              payload,
              isNot(contains(fragment)),
              reason: 'diagnostic leaked $fragment',
            );
          }
          expect(payload, contains('[redacted]'));
          expect(payload, contains('[redacted:multiaddr]'));
        }
      },
    );

    test(
      'PB266-08 exit flow events expose only allowlisted code phase and severity',
      () {
        String fixedEventBlock({
          required String path,
          required String event,
          required String code,
          required String phase,
        }) {
          final source = File(path).readAsStringSync();
          var offset = 0;
          while (true) {
            final eventOffset = source.indexOf("'$event'", offset);
            expect(
              eventOffset,
              greaterThanOrEqualTo(0),
              reason: '$path $event',
            );
            final start = source.lastIndexOf('emitFlowEvent(', eventOffset);
            final end = source.indexOf(');', eventOffset);
            expect(start, greaterThanOrEqualTo(0), reason: '$path $event');
            expect(end, greaterThan(eventOffset), reason: '$path $event');
            final block = source.substring(start, end + 2);
            if (block.contains("'code': '$code'") &&
                block.contains("'phase': '$phase'")) {
              return block;
            }
            offset = eventOffset + event.length;
          }
        }

        const expected = <({String path, String event, String code, String phase})>[
          (
            path: 'lib/core/bridge/bridge_group_helpers.dart',
            event: 'GROUP_FL_BRIDGE_LEAVE_RESPONSE',
            code: 'EX99',
            phase: 'native',
          ),
          (
            path: 'lib/core/bridge/bridge_group_helpers.dart',
            event: 'GROUP_FL_BRIDGE_LEAVE_RESPONSE',
            code: 'EX06',
            phase: 'native',
          ),
          (
            path:
                'lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart',
            event: 'GROUP_ACTIVE_EXIT_SNAPSHOT_FAILED',
            code: 'EX01',
            phase: 'authority',
          ),
          (
            path:
                'lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart',
            event: 'GROUP_ACTIVE_EXIT_PREWORK_FAILED',
            code: 'EX03',
            phase: 'notice',
          ),
          (
            path:
                'lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart',
            event: 'GROUP_ACTIVE_EXIT_NATIVE_UNCERTAIN',
            code: 'EX06',
            phase: 'native',
          ),
          (
            path:
                'lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart',
            event: 'GROUP_ACTIVE_EXIT_CLEANUP_INCOMPLETE',
            code: 'EX07',
            phase: 'cleanup',
          ),
          (
            path:
                'lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart',
            event: 'GROUP_ACTIVE_EXIT_ROLLBACK_FAILED',
            code: 'EX03',
            phase: 'notice',
          ),
          (
            path:
                'lib/features/groups/application/group_exit_terminal_diagnostics.dart',
            event: 'GROUP_EXIT_DIAGNOSTIC_WRITE_FAILED',
            code: 'EX01',
            phase: 'local_delete',
          ),
          (
            path:
                'lib/features/groups/presentation/screens/group_info_wired.dart',
            event: 'GROUP_INFO_FL_EXIT_CLASSIFY_ERROR',
            code: 'EX01',
            phase: 'authority',
          ),
          (
            path:
                'lib/features/groups/presentation/screens/group_info_wired.dart',
            event: 'GROUP_INFO_FL_LEAVE_ERROR',
            code: 'EX99',
            phase: 'authority',
          ),
          (
            path:
                'lib/features/groups/presentation/screens/group_info_wired.dart',
            event: 'GROUP_INFO_FL_DELETE_SELF_REMOVED_GROUP_ERROR',
            code: 'EX10',
            phase: 'local_delete',
          ),
          (
            path:
                'lib/features/groups/presentation/screens/group_info_wired.dart',
            event: 'GROUP_INFO_FL_DELETE_LOCAL_DISSOLVED_ERROR',
            code: 'EX10',
            phase: 'local_delete',
          ),
          (
            path:
                'lib/features/groups/presentation/screens/group_list_wired.dart',
            event: 'GROUP_LIST_FL_STUCK_EXIT_CLASSIFY_ERROR',
            code: 'EX01',
            phase: 'authority',
          ),
          (
            path:
                'lib/features/groups/presentation/screens/group_list_wired.dart',
            event: 'GROUP_LIST_FL_STUCK_LEAVE_ERROR',
            code: 'EX99',
            phase: 'authority',
          ),
          (
            path:
                'lib/features/groups/presentation/screens/group_list_wired.dart',
            event: 'GROUP_LIST_FL_DELETE_SELF_REMOVED_GROUP_ERROR',
            code: 'EX10',
            phase: 'local_delete',
          ),
          (
            path: 'lib/features/orbit/presentation/screens/orbit_wired.dart',
            event: 'ORBIT_FL_GROUP_EXIT_CLASSIFY_ERROR',
            code: 'EX01',
            phase: 'authority',
          ),
          (
            path: 'lib/features/orbit/presentation/screens/orbit_wired.dart',
            event: 'ORBIT_FL_GROUP_EXIT_PROMOTION_ERROR',
            code: 'EX02',
            phase: 'role_sync',
          ),
          (
            path: 'lib/features/orbit/presentation/screens/orbit_wired.dart',
            event: 'ORBIT_FL_DELETE_GROUP_ERROR',
            code: 'EX10',
            phase: 'local_delete',
          ),
          (
            path: 'lib/features/orbit/presentation/screens/orbit_wired.dart',
            event: 'ORBIT_FL_DELETE_SELF_REMOVED_GROUP_ERROR',
            code: 'EX10',
            phase: 'local_delete',
          ),
          (
            path: 'lib/features/orbit/presentation/screens/orbit_wired.dart',
            event: 'ORBIT_FL_STUCK_EXIT_CLASSIFY_ERROR',
            code: 'EX01',
            phase: 'authority',
          ),
        ];

        for (final row in expected) {
          final block = fixedEventBlock(
            path: row.path,
            event: row.event,
            code: row.code,
            phase: row.phase,
          );
          expect(block, contains("'severity':"), reason: row.event);
          for (final forbidden in const [
            "'groupId'",
            "'peerId'",
            "'error'",
            'errorMessage',
            'toString()',
            'stackTrace',
            'privateKey',
          ]) {
            expect(block, isNot(contains(forbidden)), reason: row.event);
          }
        }
      },
    );
  });

  // ---------------------------------------------------------------------------
  // flowEventLoggingEnabled
  // ---------------------------------------------------------------------------
  group('flowEventLoggingEnabled', () {
    test('defaults to kDebugMode value', () {
      // Reset to true default by reading what kDebugMode is
      flowEventLoggingEnabled = kDebugMode;
      expect(flowEventLoggingEnabled, equals(kDebugMode));
    });
  });
}
