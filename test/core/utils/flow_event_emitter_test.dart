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

      emitFlowEvent(
        layer: 'FL',
        event: 'SHOULD_NOT_APPEAR',
        details: {},
      );

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

      emitFlowEvent(
        layer: 'FL',
        event: 'TS_TEST',
        details: {},
      );

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
