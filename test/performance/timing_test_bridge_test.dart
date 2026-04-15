import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'timing_test_bridge.dart';

void main() {
  group('TimingTestBridge', () {
    test('default behavior matches FakeBridge (no delays)', () async {
      final bridge = TimingTestBridge();
      final sw = Stopwatch()..start();
      final response = await bridge.send(jsonEncode({'cmd': 'node:status'}));
      sw.stop();

      expect(jsonDecode(response)['ok'], isTrue);
      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('per-command delay is applied', () async {
      final bridge = TimingTestBridge(
        commandDelays: {'peer:dial': const Duration(milliseconds: 200)},
      );
      final sw = Stopwatch()..start();
      await bridge.send(
        jsonEncode({'cmd': 'peer:dial', 'payload': {}}),
      );
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(200));
    });

    test('delay only applies to matching command', () async {
      final bridge = TimingTestBridge(
        commandDelays: {'peer:dial': const Duration(milliseconds: 200)},
      );
      final sw = Stopwatch()..start();
      await bridge.send(jsonEncode({'cmd': 'node:status'}));
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('Go-side timing fields injected into response', () async {
      final bridge = TimingTestBridge(
        responseTimingFields: {
          'message:send': {
            'streamOpenMs': 15,
            'writeMs': 8,
            'ackWaitMs': 12,
          },
        },
      );

      final response = await bridge.send(
        jsonEncode({'cmd': 'message:send', 'payload': {}}),
      );
      final parsed = jsonDecode(response) as Map<String, dynamic>;

      expect(parsed['streamOpenMs'], 15);
      expect(parsed['writeMs'], 8);
      expect(parsed['ackWaitMs'], 12);
      expect(parsed['ok'], isTrue); // base response preserved
    });

    test('timing fields not injected for non-matching command', () async {
      final bridge = TimingTestBridge(
        responseTimingFields: {
          'message:send': {'streamOpenMs': 15},
        },
      );

      final response = await bridge.send(
        jsonEncode({'cmd': 'node:status'}),
      );
      final parsed = jsonDecode(response) as Map<String, dynamic>;

      expect(parsed.containsKey('streamOpenMs'), isFalse);
    });
  });
}
