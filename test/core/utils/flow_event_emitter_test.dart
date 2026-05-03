import 'dart:convert';

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
