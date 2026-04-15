import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../core/bridge/fake_bridge.dart';
import 'benchmark_harness.dart';

/// A bridge that never completes send() — used to test timeout behavior.
class _HangingBridge extends FakeBridge {
  @override
  Future<String> send(String message) {
    // Parse to track calls, but never complete
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    lastCommand = cmd;
    if (cmd != null) commandLog.add(cmd);
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);

    // Return a future that never completes
    return Completer<String>().future;
  }
}

void main() {
  late BenchmarkHarness harness;

  setUp(() {
    harness = BenchmarkHarness();
  });

  tearDown(() {
    harness.dispose();
  });

  group('Benchmark: Timeout Accuracy (Dart-side)', () {
    test('H-Dart-1: Bridge call timeout fires within budget', () async {
      final bridge = _HangingBridge();
      const timeout = Duration(milliseconds: 500); // Short for test speed

      final sw = Stopwatch()..start();
      try {
        await bridge
            .send(jsonEncode({'cmd': 'node:status'}))
            .timeout(timeout);
        fail('Should have thrown TimeoutException');
      } on TimeoutException {
        sw.stop();
        expect(
          sw.elapsedMilliseconds,
          greaterThanOrEqualTo(450), // ± 10%
        );
        expect(
          sw.elapsedMilliseconds,
          lessThanOrEqualTo(750), // generous margin
        );
      }
    });

    test('H-Dart-2: Multiple timeouts fire independently', () async {
      final bridge = _HangingBridge();
      const timeout = Duration(milliseconds: 300);

      final timings = <int>[];

      for (var i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        try {
          await bridge
              .send(jsonEncode({'cmd': 'peer:dial', 'idx': i}))
              .timeout(timeout);
        } on TimeoutException {
          sw.stop();
          timings.add(sw.elapsedMilliseconds);
        }
      }

      expect(timings, hasLength(3));
      for (final t in timings) {
        expect(t, greaterThanOrEqualTo(250)); // ± 16%
        expect(t, lessThanOrEqualTo(500));
      }
    });

    test('H-Dart-3: Non-hanging bridge completes before timeout', () async {
      final bridge = FakeBridge();
      const timeout = Duration(seconds: 5);

      final sw = Stopwatch()..start();
      final response = await bridge
          .send(jsonEncode({'cmd': 'node:status'}))
          .timeout(timeout);
      sw.stop();

      expect(jsonDecode(response)['ok'], isTrue);
      expect(
        sw.elapsedMilliseconds,
        lessThan(100),
        reason: 'Non-hanging bridge should return immediately',
      );
    });
  });
}
